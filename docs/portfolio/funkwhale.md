# Funkwhale

[Portfolio index](../PORTFOLIO.md)

| | |
|---|---|
| State | Proposed |
| Repo | **Ready** [stacks/funkwhale](../../stacks/funkwhale) |
| Verdict | EVAL |

A federated music server, for local Chattanooga artists to host and stream their
own work rather than rent the privilege from a platform.

## Why it is on this list at all

It is the option Greg named first in his own essay,
[Streaming Platforms as Software Infrastructure](https://www.chattanooga.digital/blog/2025-09/streaming-platforms-as-software-infrastructure)
— *"a federated, ActivityPub-based platform focused on sharing and listening to
music within a decentralized community"* — and the piece opens on *"the creators
don't get squat."* The co-op's service catalogue already lists music
sharing/streaming. The essay also names the barrier honestly: *"You have to be
pretty geeky to deploy and self-host these servers,"* which is the argument for
the co-op doing it once rather than each artist doing it alone.

## Why EVAL and not Go

Nothing here is a technical doubt — the stack validates and the client that reads
it is written and tested. Three things are undecided, and none of them are code:

- **Nobody has asked the artists.** Hosting someone's music needs their
  permission and a licence choice per track. This gates the library, not the
  build.
- **It is a new Swarm stack, a new subdomain and a new MinIO bucket.** William
  donates the hardware and asked on 2026-07-25 to be consulted on changes to it.
- **Mastodon next door has 14 accounts and 121 statuses.** A second federated
  service is worth having only if the first one's quiet is a content problem
  rather than an appetite problem.

## What already exists on the other side

`Chattanooga-Digital-Expo` ships a Funkwhale client — artist and track listing, a
player, and licence display per row — verified against the Funkwhale 2.0 API. Its
`pnpm test:live` fails today with `ENOTFOUND music.chattanooga.digital`, which is
exactly what it should say until this is deployed.

## Notes

- Collections moved to `/api/v2/` in 2.0 while nodeinfo stayed on `/api/v1/`.
  `/api/v1/tracks/` is a 404.
- The whole mobile client depends on `anonymousCanListen` staying true. Flipping
  it empties the app with no other symptom.
- `/api/v2/listen/<uuid>/` redirects to a presigned URL that expires in an hour.
  The client re-resolves; raising the expiry is not the fix.
