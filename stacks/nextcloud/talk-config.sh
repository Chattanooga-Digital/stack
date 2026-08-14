#!/bin/sh
# Apply Nextcloud Talk (spreed) relay + signaling config from the environment, so
# staging and production converge on every deploy instead of drifting from a value
# that was set once by hand in the database.
#
# Injected as a Swarm config into the official image's
# /docker-entrypoint-hooks.d/before-starting/, so it re-runs on every container
# start and is idempotent. occ must run as www-data; gosu handles the root case.
set -eu

if [ -z "${NC_TURN_SERVER:-}" ] || [ -z "${NC_TURN_SECRET:-}" ] \
   || [ -z "${TURN_DOMAIN:-}" ] || [ -z "${SIGNALING_SECRET:-}" ]; then
  echo "talk-config: required env not set, skipping"
  exit 0
fi

occ() {
  if [ "$(id -u)" = "0" ]; then
    gosu www-data php /var/www/html/occ "$@"
  else
    php /var/www/html/occ "$@"
  fi
}

# First boot runs this hook before the install finishes; do nothing until then.
if ! occ status --output=json 2>/dev/null | grep -q '"installed":true'; then
  echo "talk-config: Nextcloud not installed yet, skipping"
  exit 0
fi

occ app:enable spreed >/dev/null 2>&1 || true

# STUN + TURN point at the SHARED relay. NC_TURN_SERVER / NC_TURN_SECRET are
# identical in every environment -- that identity is what makes staging a
# faithful test of production's media path.
occ config:app:set spreed stun_servers --value "[\"${NC_TURN_SERVER}\"]"
occ config:app:set spreed turn_servers --value \
  "[{\"schemes\":\"turn\",\"server\":\"${NC_TURN_SERVER}\",\"secret\":\"${NC_TURN_SECRET}\",\"protocols\":\"udp,tcp\"}]"

# Signaling points at THIS instance's own talk container (per-environment host),
# with the same SIGNALING_SECRET the talk service is deployed with.
occ config:app:set spreed signaling_servers --value \
  "{\"servers\":[{\"server\":\"https://${TURN_DOMAIN}\",\"verify\":true}],\"secret\":\"${SIGNALING_SECRET}\"}"

echo "talk-config: applied (turn=${NC_TURN_SERVER}, signaling=https://${TURN_DOMAIN})"
