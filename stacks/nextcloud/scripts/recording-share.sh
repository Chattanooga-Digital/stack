#!/bin/sh
# Publishes Talk recordings and their transcripts into the conversation they
# were recorded in, because Talk leaves them private to whoever pressed record.
#
# Set RECORDING_AUTOSHARE=0 to stop it without redeploying the stack; the guard
# lives in share-recordings.php so this loop stays dumb.
#
# Swarm ignores depends_on ordering, so this waits for the install rather than
# racing it.
set -eu

until php /var/www/html/occ status 2>/dev/null | grep -q 'installed: true'; do
  echo '[recording-share] waiting for install'
  sleep 10
done

INTERVAL="${RECORDING_SHARE_INTERVAL:-120}"
echo "[recording-share] watching, interval ${INTERVAL}s"

while true; do
  php /config/share-recordings.php --apply || echo '[recording-share] run failed'
  sleep "$INTERVAL"
done
