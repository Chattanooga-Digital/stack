# Funkwhale

[Funkwhale](https://dev.funkwhale.audio/funkwhale/funkwhale), a federated music
server, intended for `music.chattanooga.digital`.

Four services: `api` (the Django app and the only thing Traefik routes), a Celery
`worker` and `beat` for imports and federation, plus a dedicated `redis`.

## Why this and not a private music silo

It is the option Greg wrote up himself, in
[Streaming Platforms as Software Infrastructure](https://www.chattanooga.digital/blog/2025-09/streaming-platforms-as-software-infrastructure):
Funkwhale is named first, the argument is cooperative hosting, and the piece
opens on *"the creators don't get squat."* The co-op's own service catalogue
already lists music sharing and streaming. Federation is the part that makes it
infrastructure rather than a folder with a web page — it speaks ActivityPub like
the Mastodon on the same Swarm.

## Needs a PostgreSQL it does not own

Beyond the [platform baseline](../../docs/CONVENTIONS.md#platform-baseline), this
stack needs a reachable `postgres_db` on `internal_network` with a database and
role matching `DB_NAME` and `DB_USER`. That database lives in another stack.
Nothing here creates or backs it up.

## Two settings the mobile app depends on

`Chattanooga-Digital-Expo`'s Music tab is **read-only and carries no token**. It
lists artists and plays tracks with no account at all, which works only while
both of these hold:

    FUNKWHALE_API_AUTHENTICATION_REQUIRED=false
    FUNKWHALE_ANONYMOUS_CAN_LISTEN=true

Flip either and the Music tab goes empty with no other symptom — the server looks
healthy, the app looks broken. `nodeinfo` is where the truth is, and it is
unauthenticated:

```bash
curl -s "https://music.chattanooga.digital/api/v1/instance/nodeinfo/2.0/" \
  | grep -o '"anonymousCanListen":[a-z]*'          # must be true
```

The app's own `pnpm test:live` asserts exactly that and is the fastest check.

## Playback that stops partway is not an expiry-length problem

`GET /api/v2/listen/<uuid>/` answers **302** to a presigned object URL carrying
`X-Amz-Expires=3600`. A client that stores the resolved URL and replays it will
work for an hour and then fail, and the listener hears a track simply stop.

This exact bug — signed CDN URL fetched once, never refreshed, against a library
holding tracks over fifty minutes long — was the loudest user complaint on
another audio app built in this workspace. **The fix is in the client**, which
re-derives the listen URL per play and re-resolves once on a mid-track failure
(`src/audio/usePlayer.ts` in `Chattanooga-Digital-Expo`).

Raising `S3_URL_EXPIRY` makes the failure rarer and harder to reproduce. It does
not fix it. Leave it at an hour so the recovery path stays exercised.

## API versions moved and nodeinfo did not

On Funkwhale 2.0 the collections are on **v2** and nodeinfo is still on **v1**:

| Call | |
|---|---|
| `GET /api/v2/tracks/?page_size=N` | `{count, next, previous, results}` |
| `GET /api/v2/artists/` | `{next, previous, results}` — cursor, no count |
| `GET /api/v2/listen/<uuid>/` | 302 to a presigned URL |
| `GET /api/v1/instance/nodeinfo/2.0/` | v1, deliberately |

`/api/v1/tracks/` is a **404**. Anonymous reads are rate-limited under the scope
`anonymous-retrieve`, 10,000 a day.

## Before anyone uploads anything

**Artist permission is not a technical step and it gates the whole library.**
Hosting a local artist's work needs their agreement and a licence choice per
track; `license` and `copyright` are first-class fields on a Funkwhale track and
the mobile app displays the licence on every row, because on a platform whose
argument is that creators should get paid, the licence is the feature rather than
metadata.

## Notes

- Changing `FUNKWHALE_DOMAIN` on a live instance breaks federation.
- `redis`, `worker` and `beat` update stop-first and drop briefly on every
  deploy. `api` updates start-first.
- Registration defaults to `disabled`: this is a co-op library, not a public
  host. Members are made by an admin, and uploads are gated behind that.
- Traefik buffers uploads to 1 GB by default. Whole albums arrive in one request.
