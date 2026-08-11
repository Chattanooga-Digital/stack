# Nextcloud

Files, Office, and Whiteboard. Declarative — not
[All-in-One](https://github.com/nextcloud/all-in-one). AIO's mastercontainer mounts
the Docker socket, which on a shared host means anyone who can admin AIO can reach
every other tenant's containers.

Installs unattended from `NC_ADMIN_USER` / `NC_ADMIN_PASSWORD`; there is no web
wizard step.

## Routing

Three routers per instance share `NC_DOMAIN` and are separated by priority,
because the app's rule matches the whole host:

| Router | Rule | Priority | Port |
|---|---|---|---|
| `${INSTANCE_NAME}-office` | `Host(NC_DOMAIN) && PathPrefix(/browser,/hosting,/cool)` | 100 | 9980 |
| `${INSTANCE_NAME}-board` | `Host(NC_DOMAIN) && PathPrefix(/whiteboard)` | 100 | 3002 |
| `${INSTANCE_NAME}-app` | `Host(NC_DOMAIN)` | 10 | 80 |

Office and Whiteboard are path-routed on the main hostname rather than given their
own subdomains, so neither needs a DNS record.

Set `NC_TRUSTED_PROXIES` to the actual Traefik overlay subnet. The Nextcloud image
expects a space-separated value. Don't trust every private address range on a shared
host: any trusted peer can supply forwarded client-IP headers.

## Talk

Talk isn't part of this stack. Port 3478 is already reserved cluster-wide by another
tenant, and the separate-listener, relay, and Traefik design isn't settled. Keep it
out until [cd-nextcloud#8](https://github.com/TortoiseWolfe/cd-nextcloud/issues/8)
passes its external-network acceptance test.

## Secrets that are shared state

This value must match something outside the compose file. A mismatch doesn't fail the
deploy; Whiteboard silently never connects:

| Variable | Must equal |
|---|---|
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
- Apps and post-install configuration (Office WOPI, whiteboard JWT, mail, hardening)
  are applied by `occ` scripts that live outside this repo, in
  [cd-nextcloud](https://github.com/TortoiseWolfe/cd-nextcloud). A stack deploy does not
  run them.
