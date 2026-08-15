# Nextcloud

Files, Office, Whiteboard and Talk. Declarative, not
[All-in-One](https://github.com/nextcloud/all-in-one). AIO's mastercontainer mounts the
Docker socket, so on a shared host anyone who can admin AIO can reach every other
tenant's containers.

Installs unattended from `NC_ADMIN_USER` / `NC_ADMIN_PASSWORD`; there is no web wizard
step.

## Routing

Three routers per instance share `NC_DOMAIN` and are separated by priority, because the
app's rule matches the whole host:

| Router | Rule | Priority | Port |
|---|---|---|---|
| `${INSTANCE_NAME}-office` | `Host(NC_DOMAIN) && PathPrefix(/browser,/hosting,/cool)` | 100 | 9980 |
| `${INSTANCE_NAME}-board` | `Host(NC_DOMAIN) && PathPrefix(/whiteboard)` | 100 | 3002 |
| `${INSTANCE_NAME}-app` | `Host(NC_DOMAIN)` | 10 | 80 |

Office and Whiteboard are path-routed on the main hostname rather than given their own
subdomains, so neither needs a DNS record.

Set `NC_TRUSTED_PROXIES` to the actual Traefik overlay subnet. The image expects a
space-separated value. Do not trust a whole private range on a shared host: any trusted
peer can supply forwarded client-IP headers.

## Talk

One image bundling signaling, janus, nats and eturnal. This stack runs the signaling
half only, routed on `TALK_HOST`, and publishes no port.

The STUN/TURN relay is shared and already listens on 3478. Do not add a `ports:` block:
an ingress publish reserves that port across every node and stack, so a second relay
cannot bind it. Signaling cannot be shared the same way, because the server binds to one
Nextcloud backend via `NC_DOMAIN`.

The relay sees the overlay address rather than the client's, so every call is relayed
rather than peer to peer, and only `turn` on 3478 is offered, not `turns` on 5349.

## Secrets that are shared state

These must match a value outside the compose file. A mismatch does not fail the deploy;
the feature silently never connects:

| Variable | Must equal |
|---|---|
| `NC_JWT_SECRET` | the whiteboard app's `jwt_secret_key` |
| `TALK_SIGNALING_SECRET` | the `secret` Talk stores for this signaling server |
| `TALK_TURN_SECRET` | the shared secret the relay on 3478 enforces |

## Notes

- **Primary storage is the local `nextcloud_html` volume.** `OBJECTSTORE_S3_*` is
  honoured at first install only, so adopting object storage after a rebuild is a data
  migration rather than a config change. Decide before an instance's first deploy.
- `postgres:18` takes its volume at `/var/lib/postgresql`, one level up from 17 and
  earlier. Mounting the old `/data` path against 18 fails the container at startup with
  a wall of `pg_upgrade` advice and no obvious error line
  ([docker-library/postgres#37](https://github.com/docker-library/postgres/issues/37)).
  A PostgreSQL 18 dump cannot be restored into 16, so this is not a free downgrade.
- Do **not** set `STORAGE_STRATEGY=redis` on the whiteboard image. The `release` build
  exits immediately with `TypeError: RedisStrategy.createRedisClient is not a function`.
  Redis storage only matters for sharing board state across replicas, and this runs one.
- `cron` shares `app`'s image and webroot volume. Without it no background job runs and
  the admin overview shows a permanent cron warning.
- Apps and post-install configuration (Office WOPI, whiteboard JWT, mail, hardening) are
  applied by `occ` scripts kept outside this repo. A stack deploy does not run them.
