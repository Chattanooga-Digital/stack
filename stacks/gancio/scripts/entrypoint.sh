#!/bin/sh
# Gancio is configured by a JSON file, not by environment variables.
#
# server/config.js reads `-c/--config` (default /config.json) and, when the file
# is absent, sets status=SETUP and serves a first-run web wizard instead of the
# site. A stack that mounted no config would therefore come up "healthy" showing
# a setup screen to the public, so the file is rendered here from the stack
# environment and the compose file stays instance-agnostic per CONVENTIONS.md.
#
# Paths in config.example.json are relative to the process working directory.
# They are absolute here so a working-directory change upstream cannot silently
# relocate uploads onto the container filesystem, where a redeploy loses them.
set -eu

DATA=/data
mkdir -p "$DATA/uploads" "$DATA/logs" "$DATA/user_locale"

: "${GANCIO_BASEURL:?GANCIO_BASEURL not set}"
: "${DB_PASSWORD:?DB_PASSWORD not set}"

# Gancio has no SMTP environment variables. server/api/controller/settings.js
# seeds its live settings from this file -- `admin_email: config.admin_email ||
# ''` and `smtp: config.smtp || {}` -- and thereafter reads the `settings` table,
# so a value saved in the admin panel wins over this one. That layering is
# deliberate: this is the reproducible default a rebuild restores, not a lock on
# what the site owner may change.
#
# Emitted only when SMTP_HOST is set, because a half-filled block is worse than
# none. mail.js builds its nodemailer transport from `settings.smtp || {}`, and
# the guard that warns about unconfigured mail is `!settings.smtp` -- which an
# empty object passes. A blank host would therefore boot clean and fail at send.
MAIL_JSON=""
if [ -n "${SMTP_HOST:-}" ]; then
  : "${ADMIN_EMAIL:?ADMIN_EMAIL not set (gancio sends as this address)}"
  SMTP_PORT="${SMTP_PORT:-587}"

  # 465 is implicit TLS, 587 is STARTTLS. Defaulted off the port so the two
  # common cases need no second variable, still overridable for the third.
  if [ "$SMTP_PORT" = "465" ]; then
    SMTP_SECURE="${SMTP_SECURE:-true}"
  else
    SMTP_SECURE="${SMTP_SECURE:-false}"
  fi

  # A quote or backslash in a value would produce invalid JSON, and gancio
  # reports that as a parse error against a file nobody can see. Fail here with
  # the reason instead.
  case "${SMTP_PASSWORD:-}${SMTP_USER:-}${ADMIN_EMAIL}" in
    *'"'*|*\\*)
      echo "FATAL: SMTP_USER/SMTP_PASSWORD/ADMIN_EMAIL cannot contain a quote or backslash" >&2
      exit 1 ;;
  esac

  MAIL_JSON=$(cat <<MAILJSON
  "admin_email": "${ADMIN_EMAIL}",
  "smtp": {
    "host": "${SMTP_HOST}",
    "port": ${SMTP_PORT},
    "secure": ${SMTP_SECURE},
    "auth": { "user": "${SMTP_USER:-}", "pass": "${SMTP_PASSWORD:-}" }
  },
MAILJSON
)
fi

HOSTNAME_ONLY=$(printf '%s' "$GANCIO_BASEURL" | sed -e 's|^https\{0,1\}://||' -e 's|/.*$||')

cat > /config.json <<JSON
{
  "baseurl": "${GANCIO_BASEURL}",
  "hostname": "${HOSTNAME_ONLY}",
  "server": { "host": "0.0.0.0", "port": 13120 },
  "log_level": "${GANCIO_LOG_LEVEL:-info}",
  "log_path": "${DATA}/logs",
  "db": {
    "dialect": "postgres",
    "host": "${DB_HOST:-db}",
    "port": ${DB_PORT:-5432},
    "database": "${DB_NAME:-gancio}",
    "username": "${DB_USER:-gancio}",
    "password": "${DB_PASSWORD}",
    "logging": false
  },
${MAIL_JSON}
  "user_locale": "${DATA}/user_locale",
  "upload_path": "${DATA}/uploads"
}
JSON

# Postgres accepts TCP before it accepts queries, so a plain port check races the
# first migration. Ask the database a question instead.
i=0
until node -e '
const{Client}=require("/home/node/node_modules/pg");
const c=JSON.parse(require("fs").readFileSync("/config.json")).db;
const cl=new Client({host:c.host,port:c.port,database:c.database,user:c.username,password:c.password});
cl.connect().then(()=>cl.query("select 1")).then(()=>process.exit(0)).catch(()=>process.exit(1));
' 2>/dev/null; do
  i=$((i + 1))
  if [ "$i" -ge 60 ]; then
    echo "FATAL: database did not accept a query after 60 attempts" >&2
    exit 1
  fi
  echo "  waiting for the database ($i)…"
  sleep 2
done

echo "> running migrations"
/home/node/server/cli.js migrate -c /config.json

echo "> starting gancio"
exec /home/node/server/cli.js start -c /config.json
