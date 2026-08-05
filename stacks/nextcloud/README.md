# Nextcloud

Files, Talk, Office, and Whiteboard. Declarative — not
[All-in-One](https://github.com/nextcloud/all-in-one). AIO's mastercontainer mounts
the Docker socket, which on a shared host means anyone who can admin AIO can reach
every other tenant's containers.

Installs unattended from `NC_ADMIN_USER` / `NC_ADMIN_PASSWORD`; there is no web
wizard step.

## Routing

Four routers per instance. Three share `NC_DOMAIN` and are separated by priority,
because the app's rule matches the whole host:

| Router | Rule | Priority | Port |
|---|---|---|---|
| `${INSTANCE_NAME}-office` | `Host(NC_DOMAIN) && PathPrefix(/browser,/hosting,/cool)` | 100 | 9980 |
| `${INSTANCE_NAME}-board` | `Host(NC_DOMAIN) && PathPrefix(/whiteboard)` | 100 | 3002 |
| `${INSTANCE_NAME}-app` | `Host(NC_DOMAIN)` | 10 | 80 |
| `${INSTANCE_NAME}-talk` | `Host(NC_TURN_DOMAIN)` | — | 8081 |

Office and Whiteboard are path-routed on the main hostname rather than given their
own subdomains, so neither needs a DNS record. Only Talk does.

## Talk

Two prerequisites beyond the platform baseline: **3478 TCP and UDP** reachable, and
a DNS record for `NC_TURN_DOMAIN`.

`NC_RELAY_IP` is the address eturnal advertises to clients as the TURN relay. It has
to be the environment's public address — on an overlay network the container's own
IP is a private `10.x`, and a private relay address fails ICE for every remote
participant.

`TALK_IMAGE` selects which backend runs, and the two are not interchangeable:

- `strangewill/aio-talk-standalone` (default) adds `RELAY_IP_V4`, which overrides the
  relay address. Because that override displaces the container's own address from
  eturnal's `whitelist_peers`, it also needs `EXTRA_WHITELIST_PEER` to put the subnet
  back — eturnal's `blacklist_peers: recommended` blocks `10.0.0.0/8`.
- `ghcr.io/nextcloud-releases/aio-talk` is upstream and has neither variable. It takes
  the relay address from `hostname -i`, so it is only correct where that returns a
  routable address — i.e. host networking. On an overlay it advertises the private IP.

Switching to upstream therefore means moving Talk to host networking, which a service
cannot combine with `traefik_net`, so the signaling route needs rearranging at the
same time. Untested here.

Separately: TURN relay allocates on **UDP 49152–65535** (eturnal's default range,
which the AIO images do not narrow). Only 3478 is published, so relay may be
unreachable regardless of image.

## Secrets that are shared state

Three values must match something outside the compose file, and none of them fail the
deploy when wrong — the feature just silently never connects:

| Variable | Must equal |
|---|---|
| `NC_TURN_SECRET` | Talk's TURN secret, set via `occ talk:turn:add --secret` |
| `NC_SIGNALING_SECRET` | Talk's signaling secret, set via `occ talk:signaling:add` |
| `NC_JWT_SECRET` | the whiteboard app's `jwt_secret_key` |

## Notes

- **Primary storage is the local `nextcloud_html` volume.** `OBJECTSTORE_S3_*` is
  honoured at first install only, so adopting object storage after a rebuild is a data
  migration rather than a config change. Decide before the first deploy of an instance.
- `postgres:18` takes its volume at `/var/lib/postgresql`, one level up from 17 and
  earlier. Mounting the old `/data` path against 18 fails the container at startup with
  a wall of `pg_upgrade` advice and no obvious error line
  ([docker-library/postgres#37](https://github.com/docker-library/postgres/issues/37)).
  A PostgreSQL 18 dump also cannot be restored into 16, so this is not a free downgrade.
- Do **not** set `STORAGE_STRATEGY=redis` on the whiteboard image. The `release` build
  exits immediately with `TypeError: RedisStrategy.createRedisClient is not a function`.
  Redis storage only matters for sharing board state across replicas, and this runs one.
- `cron` shares `app`'s image and webroot volume. Without it no background job runs at
  all and the admin overview shows a permanent cron warning.
- Apps and post-install configuration (Office WOPI, Talk STUN/TURN/signaling, whiteboard
  JWT, mail, hardening) are applied by `occ` scripts that live outside this repo, in
  [cd-nextcloud](https://github.com/TortoiseWolfe/cd-nextcloud). A stack deploy does not
  run them.
