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

# MAIL IS NOT SEEDED FROM HERE. It is set in Administration > Settings, which is
# gancio's supported place for it, and this file deliberately does not pre-empt
# that. An earlier version wrote `admin_email` and `smtp` into the config so a
# rebuild from empty volumes came back with mail on; that is the cost of the
# rule, and the cost is accepted rather than worked around.
#
# The consequence to know: a fresh volume comes up with mail off, so password
# resets and confirmations silently do nothing until someone fills the panel in.

# Everything interpolated below lands inside a JSON document. A quote or a
# backslash in any of it produces a file gancio can only report as a parse error,
# against a path nobody can read. Fail here, with the reason, instead.
#
# This check used to cover only the SMTP values and went away with them. The
# password is the one that actually matters -- it is arbitrary, it is the value
# most likely to contain punctuation, and Portainer is documented as mangling
# `%`, `*` and `$` in env values already.
case "${DB_PASSWORD}${GANCIO_BASEURL}${DB_USER:-}${DB_NAME:-}" in
  *'"'*|*\\*)
    echo "FATAL: DB_PASSWORD/GANCIO_BASEURL/DB_USER/DB_NAME cannot contain a quote or backslash" >&2
    exit 1 ;;
esac

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
