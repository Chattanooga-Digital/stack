# Nextcloud

[Nextcloud](https://github.com/nextcloud/server) with Talk, running
`go.eduity.net`. Five services: `nextcloud` (Apache), `cron`, `talk`, plus its
own `db` and `redis`.

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

## Notes

- Office is not in this stack. Collabora and Whiteboard are unbuilt.
- Only `db` and `redis` have healthchecks. The Nextcloud and Talk images have
  not been checked for `curl` or `wget`, and a healthcheck whose binary is
  missing marks the service unhealthy and restart-loops it.
- Every service updates stop-first. `nextcloud` and `cron` share `nc_html`, so
  two versions must never run against it at once.
- First-run admin variables are deliberately absent. This stack is attached to
  an installed instance; `NEXTCLOUD_ADMIN_USER` and `NEXTCLOUD_ADMIN_PASSWORD`
  would be ignored anyway once the database exists.
