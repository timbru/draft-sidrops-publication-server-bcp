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
RPKI Publication Server and its rsync (RFC 5781) and RRDP (RFC 8182) public
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

## Limit Notification File Size

The size of the RRDP Notification File can significantly impact RRDP
operations. If this file becomes too large, then it can easily result in
significant traffic if the RRDP Repository does not use any CDN or in high
costs if it does.

[@!RFC8182] stipulated that any deltas that, combined with all more recent
delta, will result in the total size of deltas exceeding the snapshot size MUST
be excluded to avoid Relying Parties downloading more data than necessary.

In addition to the restriction described above, we RECOMMEND that the
Notification File size is reduced by removing delta files that have been
available for more than 75 minutes. As RP typically refresh their caches every
10 minutes, this will ensure that deltas are available for the vast majority of
RPs, while limiting the size of the Notification File.

Furthermore, we RECOMMEND that Publication Servers with many, e.g. 1000s of,
Publishers ensure they do not produce Delta Files more frequently than once per
minute. A possible approach for this is that the Publication Server SHOULD
publish changes at a regular (one-minute) interval. The Publication Server then
publishes the updates received from all Publishers in this interval in a single
RRDP Delta File.

## Consistent load-balancing and Notification File Timing

Notification Files MUST NOT be available to RPs before the referenced snapshot
and delta files are available.

As a result, when using a load-balancing setup, care SHOULD be taken to ensure
that RPs that make multiple subsequent requests receive content from the same
node. This way, clients view the timeline on one node where the referenced
snapshot and delta files are available. Alternatively, publication
infrastructure SHOULD ensure a particular ordering of the visibility of the
snapshot plus delta and notification file. All nodes should receive the new
snapshot and delta files before any node receives the new notification file.

# Rsync Repository

In this section, we will elaborate on the following recommendations:

  - Use symlinks to provide consistent content
  - Use deterministic timestamps for files
  - Load balancing and testing

## Consistent Content

A naive implementation of the Rsync Repository might change the repository
content while RPs transfer files. Even when the repository is consistent from
the repository server's point of view, clients may read an inconsistent set of
files. Clients may get a combination of newer and older files. This "phantom
read" can lead to unpredictable and unreliable results. While modern RPs will
treat such inconsistencies as a "Failed Fetch" ([@!RFC9286]), it is best to
avoid this situation since a failed fetch for one repository can cause the
rejection of the publication point for a sub-CA when resources change.

One way to ensure that rsyncd serves connected clients (RPs) with a consistent
view of the repository is by configuring the rsyncd 'module' path to a path
that contains a symlink that the repository-writing process updates for every
repository publication.

Following this process, when an update is published:

  1. write the complete updated repository into a new directory
  2. fix the timestamps of files (see next section)
  3. change the symlink to point to the new directory

Multiple implementations implement this behavior (krill, krill-sync, rpki-core,
rsyncit, a supporting shellscript [@rsync-move]).

Because rsyncd resolves this symlink when it `chdir`s into the module directory
when a client connects, any connected RPs can read a consistent state. To limit
the amount of disk space a repository uses, a Rsync Repository must clean up
copies of the repository; this is a trade-off between providing service to slow
clients and disk space.

A repository can safely remove old directories when no RP fetching at a
reasonable rate is reading that data. Since the last moment an RP can start
reading from a copy is when it last "current", the time a client has to read a
copy begins when it was last current (c.f. since written).

Empirical data suggests that Rsync Repositories MAY assume it is safe to do so
after one hour. We recommend monitoring for "file has vanished" lines in the
rsync log file to detect how many clients are affected by this cleanup process.

## Deterministic Timestamps

By default, rsync uses the modification time and file size to determine if it
should transfer a file. Therefore, throughout a file's lifetime, the
modification time SHOULD NOT change unless the file's content changes.

We RECOMMEND the following deterministic heuristics for objects' timestamps
when written to disk. These heuristics assume that a CA is compliant with
[@!RFC9286] and uses "one-time-use" EE certificates:

  - For CRLs, use the value of thisUpdate.
  - For RPKI Signed Objects, use the CMS signing-time (see
    ([@!I-D.spaghetti-sidrops-cms-signing-time]))
  - For CA and BGPSec Router Certificates, use the value of notBefore
  - For directories, use any constant value.

## Load Balancing and Testing

It is RECOMMENDED that the Rsync Repository is load tested to ensure that it
can handle the requests by all RPs in case they need to fall back from using
RRDP (as is currently preferred).

Because Rsync exchanges rely on sessions over TCP, there is no need for
consistent load-balancing between multiple rsyncd servers as long as they (1)
each provide a consistent view and (2) are updated more frequently than the
typical refresh rate for rsync repositories used by RPs.

We RECOMMEND serving rsync repositories from local storage so the host
operating system can optimally use its I/O cache. Using network storage is NOT
RECOMMENDED because it may not benefit from this cache. For example, when using
NFS, the operating system cannot cache the directory listing(s) of the repository.

We RECOMMENDED setting the "max connections" to a value that a single node can
handle with (1) the available memory and (2) the IO performance available to
be able to serve this number of connections in the time RPs allow for rsync to
fetch data. Load-testing results show that machine memory is likely the limiting
factor for large repositories that are not IO limited.

The number of rsyncd servers needed depends on the number of RPs, their refresh
rate, and the "max connections" used. These values are subject to change over
time, so we cannot give clear recommendations here except to restate that we
RECOMMEND load-testing rsync and re-evaluating these parameters over time.

# Acknowledgments

This document is the result of many informal discussions between implementers.

The authors would like to thank Job Snijders for their helpful review of this document.

{backmatter}

<reference anchor='rsync-move' target='http://sobornost.net/~job/rpki-rsync-move.sh.txt'>
    <front>
        <title>rpki-rsync-move.sh.txt</title>
        <author initials='J.' surname='Snijders' fullname='Job Snijders'>
            <organization>Fastly</organization>
            <address>
                <email>job@fastly.com</email>
            </address>
        </author>
        <date year='2023'/>
    </front>
</reference>
