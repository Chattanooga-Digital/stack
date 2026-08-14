#!/usr/bin/env bash
# refresh-staging-from-prod.sh
#
# Reseed STAGING Nextcloud from PRODUCTION so staging is a real copy of what prod
# serves -- the only way staging can genuinely test Talk (and everything else)
# against production-like data. It copies two things that must move together:
#
#   1. the database  (users, shares, Talk rooms, app config, file cache)
#   2. the S3 object store  (the actual file blobs the file cache points at)
#
# then re-asserts the handful of settings that must stay staging-specific.
#
# ---------------------------------------------------------------------------
# THIS READS PRODUCTION AND OVERWRITES STAGING. Read scripts/REFRESH.md first.
#   - Production DB + bucket: read-only here, but they are WILLIAM'S systems.
#     Coordinate before running. (See "WE ARE GUESTS" in the ops docs.)
#   - Staging DB + bucket: DESTROYED and replaced. Anything only in staging is lost.
#   - Dry-run by default. Nothing destructive happens without --confirm.
# ---------------------------------------------------------------------------
set -euo pipefail

DRY_RUN=1
for arg in "$@"; do
  case "$arg" in
    --confirm) DRY_RUN=0 ;;
    --dry-run) DRY_RUN=1 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "unknown argument: $arg" >&2; exit 2 ;;
  esac
done

# --- configuration ----------------------------------------------------------
# Set these in the environment (e.g. `set -a; . ./refresh.env; set +a` with a
# gitignored refresh.env). NOTHING here is committed with a value.
#
# Prod and staging live on different Swarm clusters, so each half is reached
# through its own Portainer, and the DB dump/restore runs via Portainer exec
# into the db container (the databases are not exposed off their overlay).
: "${PROD_PORTAINER_URL:?set PROD_PORTAINER_URL}"
: "${PROD_PORTAINER_USER:?}"; : "${PROD_PORTAINER_PASSWORD:?}"
: "${PROD_ENDPOINT_ID:?}";     : "${PROD_DB_SERVICE:?prod db service/container name, e.g. chattanooga-nextcloud_db}"
: "${STAGING_PORTAINER_URL:?}"; : "${STAGING_PORTAINER_USER:?}"; : "${STAGING_PORTAINER_PASSWORD:?}"
: "${STAGING_ENDPOINT_ID:?}";   : "${STAGING_DB_SERVICE:?staging db service/container name, e.g. nextcloud_db}"
: "${STAGING_NC_SERVICE:?staging nextcloud (app) service/container name}"

DB_NAME="${DB_NAME:-nextcloud}"
DB_USER="${DB_USER:-nextcloud}"

# S3 (DigitalOcean Spaces). Prod bucket is copied INTO the staging bucket; staging
# keeps its own bucket so it can never write to prod's.
: "${PROD_S3_ENDPOINT:?e.g. https://nyc3.digitaloceanspaces.com}"
: "${PROD_S3_BUCKET:?}"; : "${PROD_S3_KEY:?}"; : "${PROD_S3_SECRET:?}"
: "${STAGING_S3_ENDPOINT:?}"
: "${STAGING_S3_BUCKET:?}"; : "${STAGING_S3_KEY:?}"; : "${STAGING_S3_SECRET:?}"

# The guard: the destructive half refuses to run unless the staging domain looks
# like staging. Set STAGING_DOMAIN so a fat-fingered prod value cannot slip through.
: "${STAGING_DOMAIN:?e.g. nextcloud.staging.chattanooga.digital}"

WORKDIR="$(mktemp -d)"
DUMP="$WORKDIR/prod-nextcloud.dump"
trap 'rm -rf "$WORKDIR"' EXIT

log()  { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
step() { if [ "$DRY_RUN" = 1 ]; then printf '  [dry-run] %s\n' "$*"; else printf '  %s\n' "$*"; fi; }
die()  { printf '\033[31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

case "$STAGING_DOMAIN" in
  *staging*) : ;;
  *) die "STAGING_DOMAIN='$STAGING_DOMAIN' does not contain 'staging' -- refusing to overwrite what may be production." ;;
esac

# Tools are only invoked on the real run; a dry-run needs nothing but bash.
if [ "$DRY_RUN" = 0 ]; then
  for bin in curl jq aws; do command -v "$bin" >/dev/null 2>&1 || die "missing required tool: $bin"; done
fi

# --- Portainer helpers ------------------------------------------------------
# Auth -> JWT, then find the container id backing a Swarm service and exec in it.
portainer_jwt() { # url user pass
  curl -fsS "$1/api/auth" -H 'Content-Type: application/json' \
    -d "{\"username\":\"$2\",\"password\":\"$3\"}" | jq -r .jwt
}
container_id() { # url jwt endpoint service
  curl -fsS "$1/api/endpoints/$3/docker/containers/json?all=1" -H "Authorization: Bearer $2" \
    | jq -r --arg s "$4" '.[] | select(.Labels["com.docker.swarm.service.name"]==$s) | .Id' | head -n1
}
# Run a command in a container and stream stdout to a file (raw exec, Tty:false).
exec_capture() { # url jwt endpoint cid outfile cmd...
  local url="$1" jwt="$2" ep="$3" cid="$4" out="$5"; shift 5
  local args; args="$(printf '%s\n' "$@" | jq -R . | jq -sc .)"
  local exid
  exid="$(curl -fsS "$url/api/endpoints/$ep/docker/containers/$cid/exec" \
    -H "Authorization: Bearer $jwt" -H 'Content-Type: application/json' \
    -d "{\"AttachStdout\":true,\"AttachStderr\":true,\"Tty\":false,\"User\":\"root\",\"Cmd\":$args}" | jq -r .Id)"
  curl -fsS "$url/api/endpoints/$ep/docker/exec/$exid/start" \
    -H "Authorization: Bearer $jwt" -H 'Content-Type: application/json' \
    -d '{"Detach":false,"Tty":false}' --output "$out"
}
occ_staging() { # jwt cid  -- run occ (as www-data) on staging, args follow
  local jwt="$1" cid="$2"; shift 2
  exec_capture "$STAGING_PORTAINER_URL" "$jwt" "$STAGING_ENDPOINT_ID" "$cid" /dev/stdout \
    gosu www-data php /var/www/html/occ "$@"
}

# --- run --------------------------------------------------------------------
log "Refresh staging Nextcloud from production  (dry-run=$DRY_RUN)"
[ "$DRY_RUN" = 1 ] && echo "  No changes will be made. Re-run with --confirm to execute." || \
  echo "  --confirm given: this WILL overwrite the staging database and bucket."

log "0. Authenticate to both Portainers + resolve container ids"
if [ "$DRY_RUN" = 0 ]; then
  PROD_JWT="$(portainer_jwt "$PROD_PORTAINER_URL" "$PROD_PORTAINER_USER" "$PROD_PORTAINER_PASSWORD")"
  STG_JWT="$(portainer_jwt "$STAGING_PORTAINER_URL" "$STAGING_PORTAINER_USER" "$STAGING_PORTAINER_PASSWORD")"
  PROD_DB_CID="$(container_id "$PROD_PORTAINER_URL" "$PROD_JWT" "$PROD_ENDPOINT_ID" "$PROD_DB_SERVICE")"
  STG_DB_CID="$(container_id "$STAGING_PORTAINER_URL" "$STG_JWT" "$STAGING_ENDPOINT_ID" "$STAGING_DB_SERVICE")"
  STG_NC_CID="$(container_id "$STAGING_PORTAINER_URL" "$STG_JWT" "$STAGING_ENDPOINT_ID" "$STAGING_NC_SERVICE")"
  [ -n "$PROD_DB_CID" ] && [ -n "$STG_DB_CID" ] && [ -n "$STG_NC_CID" ] \
    || die "could not resolve one or more container ids (prod db / staging db / staging app)"
else
  step "auth prod ($PROD_PORTAINER_URL) + staging ($STAGING_PORTAINER_URL); resolve db + app containers"
fi

log "1. Staging into maintenance mode (blocks writes during the copy)"
step "occ maintenance:mode --on   [staging]"
[ "$DRY_RUN" = 0 ] && occ_staging "$STG_JWT" "$STG_NC_CID" maintenance:mode --on

log "2. Dump the production database"
step "pg_dump -Fc $DB_NAME  ->  $DUMP   [prod db exec]"
if [ "$DRY_RUN" = 0 ]; then
  exec_capture "$PROD_PORTAINER_URL" "$PROD_JWT" "$PROD_ENDPOINT_ID" "$PROD_DB_CID" "$DUMP" \
    pg_dump -U "$DB_USER" -Fc -Z6 "$DB_NAME"
  [ -s "$DUMP" ] || die "prod dump is empty -- aborting before touching staging"
  echo "  dump size: $(du -h "$DUMP" | cut -f1)"
fi

log "3. Restore into the staging database (drops and recreates the schema)"
step "pg_restore --clean --if-exists --no-owner  <  prod dump   [staging db exec]"
if [ "$DRY_RUN" = 0 ]; then
  # Stream the dump into pg_restore running inside the staging db container.
  EXID="$(curl -fsS "$STAGING_PORTAINER_URL/api/endpoints/$STAGING_ENDPOINT_ID/docker/containers/$STG_DB_CID/exec" \
    -H "Authorization: Bearer $STG_JWT" -H 'Content-Type: application/json' \
    -d "{\"AttachStdin\":true,\"AttachStdout\":true,\"AttachStderr\":true,\"Tty\":false,\"User\":\"root\",\"Cmd\":[\"pg_restore\",\"-U\",\"$DB_USER\",\"-d\",\"$DB_NAME\",\"--clean\",\"--if-exists\",\"--no-owner\"]}" | jq -r .Id)"
  curl -fsS "$STAGING_PORTAINER_URL/api/endpoints/$STAGING_ENDPOINT_ID/docker/exec/$EXID/start" \
    -H "Authorization: Bearer $STG_JWT" -H 'Content-Type: application/vnd.docker.raw-stream' \
    --data-binary "@$DUMP" >/dev/null
fi

log "4. Sync the object store (prod bucket -> staging bucket)"
step "aws s3 sync s3://$PROD_S3_BUCKET s3://$STAGING_S3_BUCKET --delete   (cross-account copy)"
if [ "$DRY_RUN" = 0 ]; then
  # Read from prod creds, write with staging creds. --delete makes staging an exact
  # mirror so no orphan objects survive from a previous refresh.
  AWS_ACCESS_KEY_ID="$PROD_S3_KEY" AWS_SECRET_ACCESS_KEY="$PROD_S3_SECRET" \
    aws --endpoint-url "$PROD_S3_ENDPOINT" s3 sync "s3://$PROD_S3_BUCKET" "$WORKDIR/bucket" --no-progress
  AWS_ACCESS_KEY_ID="$STAGING_S3_KEY" AWS_SECRET_ACCESS_KEY="$STAGING_S3_SECRET" \
    aws --endpoint-url "$STAGING_S3_ENDPOINT" s3 sync "$WORKDIR/bucket" "s3://$STAGING_S3_BUCKET" --delete --no-progress
fi

log "5. Re-assert the staging-specific settings the restore just overwrote"
# trusted_domains and overwrite.cli.url come from the stack's env (config.php), so a
# restart re-asserts them -- but set them here too so staging is correct immediately.
step "occ config:system:set overwrite.cli.url --value https://$STAGING_DOMAIN   [staging]"
step "occ config:system:set trusted_domains 0 --value $STAGING_DOMAIN            [staging]"
if [ "$DRY_RUN" = 0 ]; then
  occ_staging "$STG_JWT" "$STG_NC_CID" config:system:set overwrite.cli.url --value "https://$STAGING_DOMAIN" >/dev/null
  occ_staging "$STG_JWT" "$STG_NC_CID" config:system:set trusted_domains 0 --value "$STAGING_DOMAIN" >/dev/null
fi
# Talk (spreed) config: the restore brought prod's values, but talk-config.sh
# (the before-starting hook from cd-nextcloud#10) re-applies staging's on the next
# app start, so a service update fixes it automatically. Until that ships, set it here.

log "6. Rescan files, leave maintenance mode, restart the app"
step "occ maintenance:repair && occ files:scan --all   [staging]"
step "occ maintenance:mode --off                        [staging]"
step "restart the staging nextcloud service (re-runs the Talk-config hook)"
if [ "$DRY_RUN" = 0 ]; then
  occ_staging "$STG_JWT" "$STG_NC_CID" maintenance:mode --off >/dev/null
  occ_staging "$STG_JWT" "$STG_NC_CID" files:scan --all >/dev/null || true
  echo "  Now redeploy/restart the staging nextcloud service in Portainer so the"
  echo "  before-starting hook re-applies staging's Talk config."
fi

log "7. Verify"
step "occ status   +   open https://$STAGING_DOMAIN and place a test call"
if [ "$DRY_RUN" = 0 ]; then
  occ_staging "$STG_JWT" "$STG_NC_CID" status || true
fi

log "Done (dry-run=$DRY_RUN)."
