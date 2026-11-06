#!/bin/sh
# Without /config.json gancio serves a first-run setup wizard instead of the site,
# so the file is rendered here from the environment.
# Paths are absolute so uploads stay on the volume.
set -eu

DATA=/data
mkdir -p "$DATA/uploads" "$DATA/logs" "$DATA/user_locale"

: "${GANCIO_BASEURL:?GANCIO_BASEURL not set}"
: "${DB_PASSWORD:?DB_PASSWORD not set}"

# Values land inside a JSON document; a quote or backslash would surface as a
# parse error against an unreadable file.
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

# Postgres accepts TCP before it accepts queries, so probe with a query.
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
