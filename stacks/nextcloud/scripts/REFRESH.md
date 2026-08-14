# Refresh staging Nextcloud from production

`refresh-staging-from-prod.sh` makes staging a real copy of what production
serves, so Talk and everything else can be tested against production-like data
instead of an empty shell. Config parity is handled separately by the stack
(`talk-config.sh`, cd-nextcloud#10); this is **data** parity.

## What it copies, and why both halves move together

Nextcloud splits its state in two:

- **Database** — users, shares, Talk rooms, app config, and the *file cache*
  (a row per file pointing at an object key like `urn:oid:1234`).
- **S3 object store** — the actual file blobs those keys resolve to.

They must be copied as a pair. A database restored without the matching objects
lists files that 404; objects without the matching database are invisible. The
script copies both from the same point in time, with staging in maintenance mode
so nothing changes underneath it.

Staging keeps its **own** bucket and database — production's data is copied *into*
them. Staging never writes to a production bucket.

## Before you run it — this touches William's infrastructure

Production is William's. The script only **reads** prod (a `pg_dump` and an S3
read), but reading it, and running dumps against his db container, is a change of
load on his systems. **Coordinate with William first.** Staging is ours to
overwrite; production is not ours to touch unannounced.

The script is **dry-run by default** and prints each step it would take. Nothing
destructive happens without `--confirm`. It also refuses to run unless
`STAGING_DOMAIN` contains `staging`, so a mistyped production value cannot slip
into the destructive half.

## Prerequisites

- `curl`, `jq`, and `aws` (the CLI, used only for `s3 sync`) on the machine you
  run this from.
- Portainer logins for **both** clusters (prod + staging) and the db/app service
  names on each.
- S3 (DigitalOcean Spaces) keys for **both** buckets.

## How to run

1. Copy the connection details into a gitignored env file (never commit it):

   ```sh
   # refresh.env  (gitignored)
   PROD_PORTAINER_URL=https://portainer.chattanooga.digital
   PROD_PORTAINER_USER=...        PROD_PORTAINER_PASSWORD=...
   PROD_ENDPOINT_ID=1             PROD_DB_SERVICE=chattanooga-nextcloud_db
   STAGING_PORTAINER_URL=https://portainer.staging.chattanooga.digital
   STAGING_PORTAINER_USER=...     STAGING_PORTAINER_PASSWORD=...
   STAGING_ENDPOINT_ID=1          STAGING_DB_SERVICE=nextcloud_db
   STAGING_NC_SERVICE=nextcloud_app
   STAGING_DOMAIN=nextcloud.staging.chattanooga.digital
   PROD_S3_ENDPOINT=https://nyc3.digitaloceanspaces.com
   PROD_S3_BUCKET=...    PROD_S3_KEY=...    PROD_S3_SECRET=...
   STAGING_S3_ENDPOINT=https://nyc3.digitaloceanspaces.com
   STAGING_S3_BUCKET=... STAGING_S3_KEY=... STAGING_S3_SECRET=...
   DB_NAME=nextcloud     DB_USER=nextcloud
   ```

2. Dry-run first and read every line it prints:

   ```sh
   set -a; . ./refresh.env; set +a
   ./refresh-staging-from-prod.sh            # dry-run, no changes
   ```

3. When it looks right and William is expecting it:

   ```sh
   ./refresh-staging-from-prod.sh --confirm
   ```

4. After it finishes, **redeploy the staging `nextcloud` service** in Portainer.
   That re-runs the `before-starting` hook (`talk-config.sh`), which re-applies
   staging's own Talk config over the production values the restore brought in.
   Then open staging and place a test call between two participants.

## Consistency and rollback

- **Point in time.** Staging is in maintenance mode for the dump + sync, so the
  database and objects are consistent with each other. Production is not paused;
  it is read live, which is fine for a staging copy.
- **`--delete` on the object sync** makes staging an exact mirror, so objects from
  a previous refresh do not linger.
- **Rollback.** There is no automatic staging backup here. If you want a safety
  net, snapshot the staging bucket + `pg_dump` staging before `--confirm`. Losing
  staging is cheap by design; production is never written.

## What this does not do

- It does not copy `config.php` (the `nc_html` volume). That is intentional — S3
  credentials, trusted domains, and the overwrite host must stay staging's, and
  they come from the stack's environment, not from production.
- It does not migrate encryption keys or per-user external storage mounts, if any
  are ever added. Revisit this doc if the instances gain either.
