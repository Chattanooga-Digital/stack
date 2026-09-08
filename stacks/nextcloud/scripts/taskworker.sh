#!/bin/sh
# Runs Nextcloud's synchronous TaskProcessing worker, which is what actually
# executes transcription. Without it, audio2text tasks sit at "scheduled"
# forever: nothing else consumes them.
#
# Swarm ignores depends_on ordering, so this waits for the install rather than
# racing it.
#
# --timeout IS NOT OPTIONAL, AND ITS DEFAULT OF 0 IS A TRAP. The worker is a
# long-lived PHP process and IAppConfig is cached for the life of that process.
# A worker started before a config change goes on using the values it booted
# with, forever, while `occ config:app:get` in any other container reports the
# new ones -- so the config reads as applied and is not. Upstream says so in the
# command's own help text: "You should regularly (e.g. every 5 minutes) restart
# this worker by using this option to make sure it picks up configuration
# changes."
#
# Measured on production 2026-09-08: the worker had been up 6 days, so it still
# held the app default of 240s while the database had said 14400 for a day. The
# ops meeting transcribed for exactly 241s and died.
#
# restart_policy is `condition: any` with a 10s delay, so Swarm respawns this
# after each exit. A task already running finishes before the timeout is
# honoured, so recycling never truncates a transcription.
set -eu

until php /var/www/html/occ status 2>/dev/null | grep -q 'installed: true'; do
  echo '[taskworker] waiting for install'
  sleep 10
done

echo "[taskworker] starting, recycling every ${TASKWORKER_TIMEOUT:-300}s"
exec php /var/www/html/occ taskprocessing:worker --timeout="${TASKWORKER_TIMEOUT:-300}"
