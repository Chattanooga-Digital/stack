# Nextcloud

[Nextcloud](https://github.com/nextcloud/server) with Talk and Office, running
`go.eduity.net`. Six services: `nextcloud` (Apache), `cron`, `talk`,
`collabora`, plus its own `db` and `redis`.

Three hostnames, three Traefik routers, three DNS records: `DOMAIN` for files,
`TURN_DOMAIN` for Talk, `OFFICE_DOMAIN` for Collabora.

Primary storage is S3, not the `nc_html` volume. That volume holds the
installation and config only.

## NEXTCLOUD_VERSION is load-bearing

Nextcloud refuses a database written by a newer version and will not skip a
major. A floating tag like `nextcloud:apache` is therefore a broken instance
waiting to happen, not an upgrade, which is why the variable is required with no
default. Pin it to a real tag and step one major at a time.

Read the version the live instance is on with:

```
docker exec $(docker ps -qf name=nextcloud) php occ status
```

## Talk networking

`talk` publishes 3478 with `mode: host` so TURN sees real client addresses
rather than the ingress mesh's SNAT. It still joins `traefik_net`, because the
`${INSTANCE_NAME}-talk` router fronts its signaling on 8081 over the overlay.

`RELAY_IP` is the public load balancer address. If it is wrong, calls connect
and then carry no media.

## Office runs as its own container

`collabora` replaces the built-in CODE server (the `richdocumentscode` app),
which ran Collabora as PHP inside the Nextcloud container. As `www-data` it
could not create per-document jails, fell back to copying the LibreOffice tree
per child process instead of bind-mounting it, and had no listener, so every
byte was tunnelled through `proxy.php`.

Fixing that in place would mean giving `SYS_ADMIN` to the container that holds
the data, the database credentials, and the config. The capability belongs on
the renderer instead, so `cap_add: [MKNOD, SYS_ADMIN]` is on `collabora` alone.
Do not move it to `nextcloud`.

Collabora reaches Nextcloud over the public `DOMAIN`, so the host must be able
to resolve and route to its own public name. If hairpin NAT blocks that, add an
`extra_hosts` entry pointing `DOMAIN` at the internal address.

### Wiring it up

Not declarative: this repo has no init script, so run these once against the
running instance.

```
occ app:disable richdocumentscode
occ config:app:set richdocuments wopi_url --value https://OFFICE_DOMAIN
occ richdocuments:activate-config
```

Leave `richdocuments` itself enabled. Confirm under **Administration settings →
Office**, which should report the connection as OK.

## Notes

- Whiteboard is not in this stack.
- Only `db` and `redis` have healthchecks. The Nextcloud, Talk, and Collabora
  images have not been checked for `curl` or `wget`, and a healthcheck whose
  binary is missing marks the service unhealthy and restart-loops it. Collabora
  answers `GET /hosting/discovery` on 9980 once one is confirmed present.
- Traefik upgrades WebSockets and sets `X-Forwarded-Proto` without configuration,
  so `collabora` needs no header labels. Response timeouts for long-lived
  connections are entrypoint-level Traefik config, outside this repo.
- Every service updates stop-first. `nextcloud` and `cron` share `nc_html`, so
  two versions must never run against it at once.
- First-run admin variables are deliberately absent. This stack is attached to
  an installed instance; `NEXTCLOUD_ADMIN_USER` and `NEXTCLOUD_ADMIN_PASSWORD`
  would be ignored anyway once the database exists.
