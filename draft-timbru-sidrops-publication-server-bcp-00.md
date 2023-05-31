%%%
Title = "RPKI Publication Server Best Current Practices"
abbrev = "RPKI Publication Server Operations"
ipr = "trust200902"
obsoletes = [ 8416 ]

[seriesInfo]
status = "bcp"
name = "Internet-Draft"
value = "draft-timbru-sidrops-publication-server-bcp-00"

[[author]]
initials="T."
surname="Bruijnzeels"
fullname="Tim Bruijnzeels"
organization = "NLnet Labs"
  [author.address]
  email = "tim@nlnetlabs.nl"
  uri = "https://www.nlnetlabs.nl/"

[[author]]
initials="T."
surname="de Kock"
fullname="Ties de Kock"
organization = "RIPE NCC"
  [author.address]
  email = "tdekock@ripe.net"

[pi]
 toc = "yes"
 compact = "yes"
 symrefs = "yes"
 sortrefs = "yes"

%%%

.# Abstract

This document describes best current practices for operating an RFC 8181
RPKI Publication Server and its rsync and RRDP (RFC 8182) public
repositories.

{mainmatter}

# Requirements notation

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD",
"SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in
this document are to be interpreted as described in BCP 14 [@!RFC2119]
[@!RFC8174] when, and only when, they appear in all capitals, as shown here.

# Introduction

[@!RFC8181] describes the RPKI Publication Protocol used between
RPKI Certificate Authorities (CAs) and their Publication Repository server.
The server is responsible for handling publication requests sent by the
CAs, called Publishers in this context, and ensuring that their data is
made available to RPKI Relying Parties (RPs) in (public) rsync and RRDP
[@!RFC8182] publication points.

In this document, we will describe best current practices based on the
operational experience of several implementers and operators.

# Glossary

Term               | Description
-------------------|----------------------------------------------------
Publication Server | [@!RFC8181] Publication Repository server
Publishers         | [@!RFC8181] Publishers (Certificate Authorities)
RRDP Repository    | Public facing [@!RFC8182] RRDP repository
Rsync Repository   | Public facing rsync server

# Publication Server

The Publication Server handles the server side of the [@!RFC8181] Publication
Protocol. The Publication Server generates the content for the public-facing
RRDP and Rsync Repositories. It is strongly RECOMMENDED that these functions
are separated from serving the repository content.

## Availability

The Publication Server and repository content have different demands on their
availability and reachability. While the repository content MUST be highly
available to any RP worldwide, only publishers need to access the Publication
Server. Dependent on the specific setup, this may allow for additional access
restrictions in this context. For example, the Publication Server can limit
access to known source IP addresses or apply rate limits.

If the Publication Server is unavailable for some reason, this will prevent
Publishers from publishing any updated RPKI objects. The most immediate impact
of this is that the publisher cannot update their ROAs, ASPAs or BGPSec Router
Certificates during this outage. Thus, it cannot authorise changes in its
routing operations. If the outage persists for a more extended period, then the
RPKI manifests and CRLs published will expire, resulting in the RPs rejecting
CA publication points.

For this reason, the Publication Server MUST be operated in a highly available
fashion. Maintenance windows SHOULD be planned and communicated to publishers,
so they can avoid - if possible - that changes in published RPKI objects are
needed during these windows.

# RRDP Repository

In this section, we will elaborate on the following recommendations:

  - Use a separate hostname: do not share fate with rsync or the Publication Server.
  - Use a CDN if possible
  - Use randomized filenames for Snapshot and Delta Files
  - Limit the size of the Notification File
  - Combine deltas to limit the size of the Notification File
  - Timing of publication of Notification File

## Unique Hostname

It is RECOMMENDED that the public RRDP Repository URIs use a hostname different
from both the [@!RFC8181] service_uri used by publishers, and the hostname used
in rsync URIs (`sia_base`).

Using a unique hostname will allow the operator to use dedicated infrastructure
and/or a Content Delivery Network for its RRDP content without interfering with
the other functions.

## Content Delivery Network

If possible, it is strongly RECOMMENDED that a Content Delivery Network is used
to serve the RRDP content. Care MUST BE taken to ensure that the Notification
File is not cached for longer than 1 minute unless the back-end RRDP Repository
is unavailable, in which case it is RECOMMENDED that stale files are served.

When using a CDN, it will likely cache 404s for files not found on the back-end
server. Because of this, the Publication Server SHOULD use randomized,
unpredictable paths for Snapshot and Delta Files to avoid the CDN caching such
404s for future updates.

Alternatively, the Publication Server can delay writing the notification file
for this duration or clear the CDN cache for any new files it publishes.

## Limit Size Notification File

The size of the RRDP Notification File can have a big impact on RRDP
operations. If this file becomes too large, then it can easily result in
network congestion if the RRDP Repository does not use any CDN, or in
high costs if it does.

[@!RFC8182] stipulated that any deltas that, when combined with all more
recent delta, will result in the total size of deltas exceeding the size
of the snapshot MUST be excluded to avoid that Relying Parties download
more data than necessary.

In addition to the restriction described above we RECOMMEND that the
Notification File size is limited by removing access delta files that
have been available for more than 30 minutes. As RP typically refresh
their caches every 10 minutes, this will ensure that deltas are available
for vast majority of RPs, while limiting the size of the Notification
File.

Furthermore, we RECOMMEND that Publication Servers with many, e.g. 1000s
of, Publishers ensure that they do not produce Delta Files more frequently
than once per minute. A possible approach for this is that any publication
request sent by a Publisher to the Server SHOULD be published immediately
if the last delta was produced more than one minute ago. Otherwise the
request can be handled by server immediately, but the content change is
staged for up to 1 minute and combined with changes from other Publishers
in a single RRDP Delta File.

## Sticky Balancing and Notification File Timing

Notification Files SHOULD NOT be available to RPs before the referenced
snapshot and delta files are available.

This means that in case a load balancing setup is used, then care SHOULD
be taken to either ensure that RPs that fetch a Notification File from
one node, will also be served from the same node where the referenced
snapshot and delta files are available. Alternatively, snapshot and delta
files can be pushed out to all nodes first, and notification files are
pushed out second.

# Rsync Repository

In this section we will elaborate on the following recommendations:

- Use symlinks to provide consistent content
- Use deterministic timestamps for files
- Load balancing and testing

## Consistent Content

A naive implementation of the Rsync Repository could lead to the contents
of the repository being changed while RPs are transferring files. This
can lead to unpredictable, and inconsistent results. While modern RPs will
treat such inconsistencies as a "Failed Fetch" ([@!RFC9286]), this
situation is best avoided.

One way to ensure that rsyncd serves connected clients (RPs) a consistent
view of the repository, is by configuring the rsyncd 'module' path to map
a symlink that has the current state of the repository.

Whenever there is an update:

- write the complete updated repository into a new directory
- fix the timestamps of files (see next section)
- change the symlink to point to the new directory

This way rsyncd does not need to be restarted, and since symlinks are
resolved when clients connect, any connected RPs will get the content
from the old directory containing the consistent, but previous, state.

The old directories can then be removed when no more RP are fetching that
data. Because it's hard to determine this in practice, Rsync Repositories
MAY assume that it is safe to do so after 1 HOUR.

## Deterministic Timestamps

Timestamps can be used in recursive rsync fetches to determine which
files have changed. Therefore, it's important that timestamps do not
change for files that did not change in content.

We therefore RECOMMEND that the following deterministic heuristics are
used to set the timestamps of objects in case they are re-written to
disk:

- For CRLs use the value of "this update".
- For manifests use the value of "this update".
- For other RPKI Signed Objects use "not before" from the embedded EE
  Certificate. Note that "signing time" could in theory be a more
  accurate value for this, but since this is optional it cannot be
  assumed to be present. And a preference for "signing time" with a
  fallback to "not before" would result in inconsistencies between
  objects that could be surprising.
- For CA and BGPSec Router Certificates use "not before"

## Load Balancing and Testing

It is RECOMMENDED that the Rsync Repository is load tested to ensure that
it can handle the requests by all RPs in case they need to fall back from
using RRDP (as is currently preferred).

Because Rsync exchanges rely on sessions over TCP there is no need for
'sticky' load balancing in case multiple rsyncd servers are used. As long
as they each provide a consistent view, and are updated more frequently
than the typical refresh rate for rsync repositories used by RPs.

It is RECOMMENDED to set the "max connections" to a value that a single
node can handle, and that this value is re-evaluated as the repository
changes in size over time.

The number of rsyncd servers needed is a function of the number of RPs,
their refresh rate, and the "max connections" used. All of these values
are subject to change over time so we cannot give clear recommendations
here, except to restate the we RECOMMEND the load testing is done and
these values are re-evaluated over time.

# Acknowledgements

This document is the result of many informal discussions between
implementers. Proper acknowledgements will follow.


{backmatter}
