#!/bin/sh
# Nextcloud member-facing apps — Chattanooga.Digital
#
# Installs and wires the apps that AIO used to bundle for us. The declarative stack
# runs the Collabora and Whiteboard backends, but the official `nextcloud` image
# ships with none of the matching apps installed. Talk is optional because its
# production network path is tracked separately.
#
# Mirrors the house pattern of harden.sh / mail.sh: idempotent, gated, safe to re-run,
# exec'd into the running app container as the web user from the webroot.
#
# REQUIRED ENV (falls back to /run/secrets/* first, like harden.sh):
#   NC_DOMAIN           the public hostname, e.g. nextcloud.staging.chattanooga.digital
#   NC_JWT_SECRET       must MATCH the whiteboard container's JWT_SECRET_KEY
#
# TALK ENV, required only when NC_TALK_ENABLED=true (the default for staging):
#   NC_TURN_RELAY        the SHARED STUN/TURN relay, as host:port. This value is
#                        IDENTICAL in every environment, and that identity is the whole
#                        point: it is what makes staging a faithful test of the media
#                        path production uses. Defaults to turn.chattanooga.digital:3478.
#
#                        The port here is the one CLIENTS reach the relay on. It is NOT
#                        the stack's TALK_PUBLISHED_PORT, which is what the talk
#                        container binds internally and is 5349 on production. Feeding
#                        one into the other advertises a relay on a port nothing listens
#                        on: the config looks right, the deploy succeeds, and every call
#                        fails to get media. Verify with a real STUN binding request
#                        before believing any value here.
#   NC_TURN_RELAY_SECRET must MATCH the SHARED relay's TURN secret. This is NOT
#                        NC_TURN_SECRET, and they are not interchangeable. Ours is the
#                        secret our own talk container was handed; the relay answering on
#                        3478 belongs to the neighbouring Eduity service and signs
#                        allocations with its own. Use the wrong one and STUN still
#                        succeeds, every TURN allocation 401s, and nothing logs it.
#   NC_TURN_DOMAIN       this instance's OWN signaling hostname, per environment, e.g.
#                        turn.staging.chattanooga.digital. Signaling cannot be shared the
#                        way the relay is, because the signaling server binds to a single
#                        Nextcloud backend.
#   NC_SIGNALING_SECRET  must MATCH this instance's talk container SIGNALING_SECRET

set +e

log()  { printf '[nc-apps] %s\n' "$*"; }
warn() { printf '[nc-apps] WARN: %s\n' "$*"; }

cd "${NEXTCLOUD_WEBROOT:-/var/www/html}" 2>/dev/null || true
occ() { php occ "$@"; }

[ -f /run/secrets/nc_jwt_secret ]       && NC_JWT_SECRET="$(cat /run/secrets/nc_jwt_secret)"

NC_TALK_ENABLED=${NC_TALK_ENABLED:-true}

# The relay is the same host in every environment, so it carries a default. Only its
# secret and the per-environment signaling host have to be supplied.
#
# turn.chattanooga.digital and turn.eduity.net are two A records for one machine, and
# either name reaches it. We name ours because the eduity record is William's to
# repoint or retire; if he ever does, our media path breaks and nothing in this repo
# would explain why.
NC_TURN_RELAY=${NC_TURN_RELAY:-turn.chattanooga.digital:3478}

case "$NC_TALK_ENABLED" in
  true)
    [ -f /run/secrets/nc_turn_relay_secret ] && NC_TURN_RELAY_SECRET="$(cat /run/secrets/nc_turn_relay_secret)"
    [ -f /run/secrets/nc_signaling_secret ]  && NC_SIGNALING_SECRET="$(cat /run/secrets/nc_signaling_secret)"

    # Retired variables. Warn rather than silently substituting: NC_TURN_SECRET is our
    # own talk container's secret, NC_TURN_RELAY_SECRET is the shared relay's, and
    # falling back from one to the other would write a TURN entry signed with the wrong
    # key. That fails silently, which is the exact class of bug this block exists to
    # stop. NC_TURN_SECRET itself is still live — the stack hands it to the talk
    # container — it just no longer has anything to do with the relay.
    if [ -n "$NC_TURN_SECRET" ] && [ -z "$NC_TURN_RELAY_SECRET" ]; then
      warn "NC_TURN_SECRET is no longer read here. It is NOT the same value as"
      warn "NC_TURN_RELAY_SECRET, which must be the SHARED relay's secret."
    fi
    [ -n "$NC_TALK_PORT" ] && \
      warn "NC_TALK_PORT is ignored; the port now lives inside NC_TURN_RELAY"

    # config:app:set stores whatever it is handed, so a malformed relay or a secret
    # carrying a quote or a backslash would produce syntactically broken JSON that
    # Nextcloud accepts and no call can use. talk:turn:add used to validate this for us.
    if ! printf '%s' "$NC_TURN_RELAY" | grep -Eq '^[A-Za-z0-9.-]+:[0-9]+$'; then
      warn "NC_TURN_RELAY must be host:port, got '$NC_TURN_RELAY' — aborting"
      exit 1
    fi
    if [ -n "$NC_TURN_RELAY_SECRET" ] && \
       ! printf '%s' "$NC_TURN_RELAY_SECRET" | grep -Eq '^[A-Za-z0-9]+$'; then
      warn "NC_TURN_RELAY_SECRET must be alphanumeric — aborting"
      exit 1
    fi

    required="NC_DOMAIN NC_JWT_SECRET NC_TURN_DOMAIN NC_TURN_RELAY_SECRET NC_SIGNALING_SECRET"
    ;;
  false)
    required="NC_DOMAIN NC_JWT_SECRET"
    ;;
  *)
    warn "NC_TALK_ENABLED must be true or false"
    exit 1
    ;;
esac

for v in $required; do
  eval "val=\$$v"
  if [ -z "$val" ]; then
    warn "$v is required — aborting without touching config"
    exit 1
  fi
done

# --- 1. install the apps (app:install is NOT idempotent — it errors if present) ----
#
# `deck` added 2026-08-04 for the issue-tracking question (Chattanooga-Digital#295).
# Greg asked twice for "an issue tracking system… I think we can use Nextcloud in the
# short-term". He said NEXTCLOUD, not Deck — Deck is our inference, so this is here to
# be DEMONSTRATED and decided on, not because the choice has been made. Staging only
# so far; production Nextcloud does not exist yet.
#
# Note his stated motive is chargeback ("so we can eventually charge it back to
# members"), and a kanban board does not record billable work. Do not present this as
# the answer to that.
# Greg's requested set, 2026-08-14 ("Standard C.D Nextcloud Docker image"): the Hub
# Bundle (Office with CODE, calendar, contacts, mail, Talk) plus security apps —
# auditing, brute-force, deleted files, password policy, quota warning, suspicious
# login, and 2FA. bruteforcesettings, files_trashbin, password_policy and the
# twofactor_* apps are on by default and need no line here.
#
# admin_audit and suspicious_login SHIP with Nextcloud but are disabled; the loop
# below skips the install and enables them.
#
# admincockpit is the last item on Greg's list. It was held out of this array as
# "third-party and unverified" (#13) while it was already installed and running on
# staging — the check that was supposedly pending had in fact been passed and nobody
# looked. Verified 2026-08-16 against the live instances: store id `admincockpit`,
# 1.3.4, declares min-version 31 / max-version 34 so it covers the 33 both environments
# run, and its Application class loads clean as www-data on staging. Upstream still
# calls it "a preliminary version that is not intended for productive use" — that is a
# maturity caveat to pass to Greg, not a reason to keep telling him it is unchecked.
#
# firstrunwizard is enabled by default on a fresh Nextcloud, so listing it changes
# nothing today. It is here because Greg asked for it BY NAME and intends to customise
# it, and an app nobody declares is an app a future base-image change can drop silently.
#
# whiteboard stays until Greg answers, having said he is "probably going to remove it".
apps="richdocuments whiteboard deck calendar contacts mail quota_warning admin_audit suspicious_login admincockpit firstrunwizard"
[ "$NC_TALK_ENABLED" = true ] && apps="spreed $apps"

for app in $apps; do
  if occ app:list 2>/dev/null | grep -q "  - $app:"; then
    log "$app already installed — skipping"
  else
    occ app:install "$app" >/dev/null 2>&1 \
      && log "installed $app" \
      || warn "could not install $app (check network / app store reachability)"
  fi
  occ app:enable "$app" >/dev/null 2>&1
done

# Admin Cockpit is an operator tool, so scope it to the admin group rather than leaving
# it enabled for everyone. This matches how it already sits on staging (`enabled` reads
# ["admin"] there, not "yes"). app:enable --groups is idempotent and re-narrows an app
# the generic loop above has just enabled site-wide, so the order here matters.
occ app:enable admincockpit --groups admin >/dev/null 2>&1 \
  && log "admincockpit scoped to the admin group" \
  || warn "could not scope admincockpit to the admin group"

# --- 2. Collabora / Office ---------------------------------------------------------
# Collabora is routed by PATH on the main hostname (/browser, /hosting, /cool), so the
# WOPI URL is the site itself rather than a separate office.* host. That is why this
# needs no extra DNS record.
#
# Deliberately NOT pointing this at the internal http://collabora:9980. That works, but
# only if you also set allow_local_remote_servers=true, which disables Nextcloud's SSRF
# protection site-wide. The public URL fetches the discovery document perfectly well.
occ config:app:set richdocuments wopi_url --value="https://${NC_DOMAIN}" >/dev/null 2>&1 \
  && log "richdocuments wopi_url -> https://${NC_DOMAIN}" \
  || warn "failed to set wopi_url"
# Let Collabora reach us back for the WOPI callback.
occ config:app:set richdocuments public_wopi_url --value="https://${NC_DOMAIN}" >/dev/null 2>&1
occ config:app:set richdocuments disable_certificate_verification --value="" >/dev/null 2>&1

# --- 2b. PRIME THE DISCOVERY CACHE — do not skip this ------------------------------
# Without this, Office is silently broken: opening any document returns HTTP 500 from
# /apps/richdocuments/token with "Call to a member function xpath() on false".
#
# Why: DiscoveryService::get() NEVER fetches. Read CachedRequestService::get() — it
# checks the distributed cache, then the appdata folder, and returns null otherwise.
# Only fetch() performs the request, and fetch() is called from the ObtainCapabilities
# BACKGROUND JOB. So a freshly installed richdocuments has an empty discovery until
# cron happens to run that job — and if the job errored even once (a stale PHP opcache
# in a container that started before the app was installed is enough), you are left
# with a permanently empty cache and a 500 that names neither cron nor discovery.
php -r '
require_once "/var/www/html/lib/base.php";
OC_App::loadApp("richdocuments");
$s = OC::$server->get(OCA\Richdocuments\Service\DiscoveryService::class);
$s->resetCache();
$r = $s->fetch();
fwrite(STDERR, sprintf("[nc-apps] discovery primed: %d bytes, parses %s\n",
    strlen($r), simplexml_load_string($r) ? "OK" : "FALSE"));
' 2>&1 || warn "could not prime the WOPI discovery cache — Office will 500 on open"

# If this ever reports 0 bytes with a "Could not create path .../richdocuments" error,
# the appdata folder was deleted from disk without telling Nextcloud, leaving stale
# oc_filecache rows. `occ files:scan-app-data` resyncs it.

# --- 3. Talk: STUN, TURN and the High-Performance Backend --------------------------
if [ "$NC_TALK_ENABLED" = true ]; then
  # STUN and TURN point at the SHARED relay, identical in every environment, so staging
  # exercises the same media path production does (#10). Before this they pointed at
  # each instance's own host, and on staging that host's UDP port is closed, so a STUN
  # binding timed out and calls between remote participants failed. Staging therefore
  # could not test Talk, which is the only reason staging exists.
  #
  # Each list is written WHOLE with config:app:set rather than built up with talk:*:add.
  # The add verbs are additive and their matching delete verbs only match an EXACT
  # server:port, so deleting the entry you are about to add clears nothing once the
  # value has changed: the old one survives and the instance advertises a dead relay
  # beside the live one. That is what happened on the 2026-08-15 rebuild, where a 5349
  # entry lingered next to 3478. Writing the whole list makes that unrepresentable
  # rather than merely guarded against, and it closes the same hole for
  # signaling_servers, which the delete-then-add form never covered at all.
  occ config:app:set spreed stun_servers --value \
    "[\"${NC_TURN_RELAY}\"]" >/dev/null 2>&1 \
    && log "talk STUN  -> ${NC_TURN_RELAY} (shared)" || warn "stun_servers set failed"

  occ config:app:set spreed turn_servers --value \
    "[{\"schemes\":\"turn\",\"server\":\"${NC_TURN_RELAY}\",\"secret\":\"${NC_TURN_RELAY_SECRET}\",\"protocols\":\"udp,tcp\"}]" >/dev/null 2>&1 \
    && log "talk TURN  -> ${NC_TURN_RELAY} (shared, udp,tcp)" || warn "turn_servers set failed"

  # Signaling stays per-environment: this instance's own talk container.
  occ config:app:set spreed signaling_servers --value \
    "{\"servers\":[{\"server\":\"https://${NC_TURN_DOMAIN}\",\"verify\":true}],\"secret\":\"${NC_SIGNALING_SECRET}\"}" >/dev/null 2>&1 \
    && log "talk HPB   -> https://${NC_TURN_DOMAIN} (per-env)" || warn "signaling_servers set failed"
else
  log "Talk skipped; cd-nextcloud#8 owns its production network path"
fi

# --- 3b. Whiteboard ---------------------------------------------------------------
# Greg asked for this by name for the co-op's webinars. Routed by path on the main
# hostname like Collabora, so collabBackendUrl is the site itself plus /whiteboard.
#
# jwt_secret_key MUST equal the whiteboard container's JWT_SECRET_KEY. If they drift
# the board never connects and the UI says nothing useful.
occ config:app:set whiteboard collabBackendUrl --value="https://${NC_DOMAIN}/whiteboard" >/dev/null 2>&1 \
  && log "whiteboard collabBackendUrl -> https://${NC_DOMAIN}/whiteboard" \
  || warn "failed to set whiteboard collabBackendUrl"
occ config:app:set whiteboard jwt_secret_key --value="${NC_JWT_SECRET}" >/dev/null 2>&1 \
  || warn "failed to set whiteboard jwt_secret_key"

# --- 4. read it back --------------------------------------------------------------
log "verifying:"
log "  wopi_url  = $(occ config:app:get richdocuments wopi_url 2>/dev/null)"
if [ "$NC_TALK_ENABLED" = true ]; then
  log "  stun      = $(occ config:app:get spreed stun_servers 2>/dev/null)"
  log "  turn      = $(occ config:app:get spreed turn_servers 2>/dev/null | sed 's/"secret":"[^"]*"/"secret":"<set>"/g')"
  log "  signaling = $(occ config:app:get spreed signaling_servers 2>/dev/null | sed 's/"secret":"[^"]*"/"secret":"<set>"/g')"
fi
log "  whiteboard= $(occ config:app:get whiteboard collabBackendUrl 2>/dev/null) (jwt $([ -n "$(occ config:app:get whiteboard jwt_secret_key 2>/dev/null)" ] && echo set || echo MISSING))"

log "config written. THIS IS NOT PROOF."
if [ "$NC_TALK_ENABLED" = true ]; then
  log "Verify for real: open a document, a .whiteboard file, and start a call."
else
  log "Verify for real: open a document and a .whiteboard file."
fi
