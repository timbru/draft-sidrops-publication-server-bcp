%%%
Title = "RPKI Publication Server Best Current Practices"
abbrev = "RPKI Publication Server Operations"
ipr = "trust200902"

[seriesInfo]
status = "bcp"
name = "Internet-Draft"
value = "draft-ietf-sidrops-publication-server-bcp-01"

[[author]]
initials="T."
surname="Bruijnzeels"
fullname="Tim Bruijnzeels"
organization = "RIPE NCC"
  [author.address]
  email = "tim@ripe.net"

[[author]]
initials="T."
surname="de Kock"
fullname="Ties de Kock"
organization = "RIPE NCC"
  [author.address]
  email = "tdekock@ripe.net"

[[author]]
initials="F."
surname="Hill"
fullname="Frank Hill"
organization = "ARIN"
  [author.address]
  email = "frank@arin.net"

[[author]]
initials="T."
surname="Harrison"
fullname="Tom Harrison"
organization = "APNIC"
  [author.address]
  email = "tomh@apnic.net"


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
RPKI Certification Authorities (CAs) and their Publication Repository server.
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
Publishers         | [@!RFC8181] Publishers (Certification Authorities)
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

For this reason, the Publication Server MUST have a high availability.
Measuring the availability of the Publication Server in a round-trip fashion is
recommended by monitoring the publication of objects. Maintenance windows
SHOULD be planned and communicated to publishers. This makes publishers aware
of the root cause for disruption in the Publication Server that effectively is
part of their infrastructure, and helps publishers avoid - if possible -
changes in published RPKI objects that are needed during these windows.

# RRDP Repository

## Distinct Hostnames

It is RECOMMENDED that the public RRDP Repository URI uses a different
hostname from both the [@!RFC8181] service_uri used by publishers and the
hostname used in rsync URIs (`sia_base`).

Using a unique hostname will allow the operator to use dedicated infrastructure
and/or a Content Delivery Network for its RRDP content without interfering with
the other functions.

## Bandwidth and Data Usage

The bandwidth needed for RRDP evolves and depends on many parameters. These
consist of three main groups:

   1. RRDP-specific repository properties, such as the size of notification-,
      delta-, and snapshot files.
   2. Properties of the CAs publishing in a repository, such as the number of
      updates, number of objects, and size of objects.
   3. Relying party behaviour, e.g. using HTTP compression or not, timeouts or
      minimum transfer speed for downloads, using conditional HTTP requests for
      `notification.xml`.
      
When an RRDP repository server is overloaded, for example, if the bandwidth
demands exceed capacity, this causes a negative feedback loop (i.e. the
aggregate load increases), and the efficiency of RRDP degrades. For example,
when an RP attempts to download one or more delta files, and one fails, it
causes them to try to download the snapshot (larger than the sum of the size of
the deltas). If this also fails, the RP falls back to rsync. Furthermore, when
the RP tries to use RRDP again on the next run, it typically starts by
downloading the snapshot.

A Publication Server SHOULD attempt to prevent these issues by closely
monitoring performance (e.g. bandwidth, performance on an RP outside their
network, unexpected fallback to snapshot). Besides increasing the capacity, we
will discuss several other measures to reduce bandwidth demands. Which measures
are most effective is situational.

Publication Servers SHOULD support compression using deflate or gzip content
encoding as described in sections 8.4.1.2 and 8.4.1.3 of [@!RFC9110], as in most
cases this reduces transferred data by about 50%.

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

Nowadays, most RPs use conditional requests for notification files, which
reduces the traffic for repositories that do not often update relative to the
update frequency of RPs. On the other hand, for repositories that update
frequently, the content uses the most traffic. For example, for a large
repository in January 2024, with a notification file with 144 deltas covering 14
hours, the requests for the notification file used 251GB out of 55.5TB/less than
0.5% of total traffic during a period.

However, for some servers, this ratio may be different. [@!RFC8182] stipulated
that the sum of the size of deltas MUST not exceed the snapshot size to avoid
Relying Parties downloading more data than necessary. However, this does not
account for the size of the notification file all RPs download. Keeping many
deltas present may allow RPs to recover more efficiently if they are
significantly out of sync. Still, including _all_ such deltas can also increase
the total data transfer because it increases the size of the notification file. 

The Notification File size SHOULD be reduced by removing delta files that have
been available for a long time to prevent this situation. Because some RPs will
only update every 1-2 hours (in 2024), the Publication Server SHOULD include
deltas for at least 4 hours.

Furthermore, we RECOMMEND that Publication Servers do not produce Delta Files
more frequently than once per minute. A possible approach for this is that the
Publication Server SHOULD publish changes at a regular (one-minute) interval.
The Publication Server then publishes the updates received from all Publishers
in this interval in a single RRDP Delta File.

While, the latter may not reduce the amount of data due to changed objects,
this will result in shorter notification files, and will reduce the number of
delta files that RPs need to fetch and process.

## Manifest and CRL Update Times

The manifest and CRL nextUpdate time and expiry are determined by the issuing
CA rather than the Publication Server.

From the CA's point of view a longer period used between scheduled Manifest and
CRL re-issuance ensures that they will have more time to resolve unforeseen
operational issues. Their current RPKI objects would still remain valid. On
the other hand, CAs may wish to avoid using excessive periods because it would
make them vulnerable to RPKI data replay attacks.

From the Publication Server's point of view shorter update times result in
more data churn due to manifest and CRL refreshes only. As said, the choice
is made by the CAs, but in certain setups - particularly hosted RPKI services -
it may be possible to tweak the manifest and CRL re-signing timing. One large
repository has found that increasing the re-signing cycle from once every 24
hours, to once every 48 hours (still deemed acceptable) reduced the data
usage with approximately 50% as most changes in the system are due to re-signing
rather than e.g. ROA changes.

## Consistent load-balancing

### Notification File Timing

Notification Files MUST NOT be available to RPs before the referenced snapshot
and delta files are available.

As a result, when using a load-balancing setup, care SHOULD be taken to ensure
that RPs that make multiple subsequent requests receive content from the same
node (e.g. consistent hashing). This way, clients view the timeline on one node
where the referenced snapshot and delta files are available. Alternatively,
publication infrastructure SHOULD ensure a particular ordering of the
visibility of the snapshot plus delta and notification file. All nodes should
receive the new snapshot and delta files before any node receives the new
notification file.

When using a load-balancing setup with multiple backends, each backend MUST
provide a consistent view and MUST update more frequently than the typical
refresh rate for rsync repositories used by RPs. When these conditions hold,
RPs observe the same RRDP session with the serial monotonically increasing.
Unfortunately, [@!RFC8182] does not specify RP behavior if the serial regresses.
As a result, some RPs download the snapshot to re-sync if they observe a serial
regression.

### L4 load-balancing

If an RRDP repository uses L4 load-balancing, some load-balancer
implementations will keep connections to a node in the pool that is no longer
active (e.g. disabled because of maintenance). Due to HTTP keepalive, requests
from an RP (or CDN) may continue to use the disabled node for an extended
period. This issue is especially prominent with CDNs that use HTTP proxies
internally when connecting to the origin while also load-balancing over
multiple proxies. As a result, some requests may use a connection to the
disabled server and retrieve stale content, while other connections load data
from another server. Depending on the exact configuration – for example, nodes
behind the LB may have different RRDP sessions – this can lead to an
inconsistent RRDP repository.

Because of this issue, we RECOMMEND to (1) limit HTTP keepalive to a short
period on the webservers in the pool and (2) limit the number of HTTP requests
per connection. When applying these recommendations, this issue is limited (and
effectively less impactful when using a CDN due to caching) to a fail-over
between RRDP sessions, where clients also risk reading a notification file for
which some of the content is unavailable.

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

Multiple implementations implement this behavior ([@krill-sync], [@rpki-core],
[@rsyncit], the rpki.apnic.net repositories, a supporting shellscript
[@rsync-move]).

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

To increase availability, during both regular maintenance and exceptional
situations, a rsync repository that strives for high availability should be
deployed on multiple nodes load-balanced by an L4 load-balancer.  Because Rsync
sessions use a single TCP connection per session, there is no need for
consistent load-balancing between multiple rsyncd servers as long as they each
provide a consistent view. While it is RECOMMENDED that repositories are
updated more frequently than the typical refresh rate for rsync repositories
used by RPs to ensure that the repository continuously moves forward from a
client's point of view, breaking not holding this constraint does not cause
degraded behavior.

It is RECOMMENDED that the Rsync Repository is load tested to ensure that it
can handle the requests by all RPs in case they need to fall back from using
RRDP (as is currently preferred).

We RECOMMEND serving rsync repositories from local storage so the host
operating system can optimally use its I/O cache. Using network storage is NOT
RECOMMENDED because it may not benefit from this cache. For example, when using
NFS, the operating system cannot cache the directory listing(s) of the
repository.

We RECOMMENDED setting the "max connections" to a value that a single node can
handle with (1) the available memory and (2) the IO performance available to
be able to serve this number of connections in the time RPs allow for rsync to
fetch data. Load-testing results show that machine memory is likely the limiting
factor for large repositories that are not IO limited.

The number of rsyncd servers needed depends on the number of RPs, their refresh
rate, and the "max connections" used. These values are subject to change over
time, so we cannot give clear recommendations here except to restate that we
RECOMMEND load-testing rsync and re-evaluating these parameters over time.

# Single CA Repositories

Some delegated CAs in the RPKI use their own dedicated Repository.

Operating a small repository is much easier than operating a large one.
There may not be a need to use a CDN for RRDP because the notification,
snapshot and delta are relatively small. Also, the performance issues of
rscynd for recursive fetches are far less of a problem for small and flat
repositories.

Because RPs will use cached data, short outages don't need to cause
immediate issues if CAs fix their Repository before objects expire and
ensure that their Publication Server ([@!RFC8181]) is available when there
is a need to update RPKI objects such as ROAs.

However, availability issues with such repositories are frequent, which
can negatively impact Relying Party software. Therefore, it is strongly
RECOMMENDED that CAs use a publication service provided by their RIR,
NIR or other parent as much as possible. And it is RECOMMENDED that CAs
that act as a parent make a Publication Service available to their
children.


# Acknowledgments

This document is the result of many informal discussions between implementers.

The authors would like to thank Job Snijders for their helpful review of this
document.

{backmatter}

<reference anchor='rsync-move' target='http://sobornost.net/~job/rpki-rsync-move.sh.txt'>
    <front>
        <title>rpki-rsync-move.sh.txt</title>
        <author initials='J.' surname='Snijders' fullname='Job Snijders'>
            <organization>Fastly</organization>
        </author>
        <date year='2023'/>
    </front>
</reference>

<reference anchor='krill-sync' target='https://github.com/NLnetLabs/krill-sync'>
    <front>
        <title>krill-sync</title>
        <author initials='T.' surname='Bruijnzeels' fullname='Tim Bruijnzeels'>
            <organization>NLnet Labs</organization>
        </author>
        <date year='2023'/>
    </front>
</reference>

<reference anchor='rpki-core' target='https://github.com/RIPE-NCC/rpki-core'>
    <front>
        <title>rpki-core</title>
        <author fullname='RPKI Team'>
            <organization>RIPE NCC</organization>
        </author>
        <date year='2023'/>
    </front>
</reference>

<reference anchor='rsyncit' target='https://github.com/RIPE-NCC/rsyncit'>
    <front>
        <title>rpki-core</title>
        <author fullname='RPKI Team'>
            <organization>RIPE NCC</organization>
        </author>
        <date year='2023'/>
    </front>
</reference>
