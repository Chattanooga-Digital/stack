#!/bin/sh
# Provisioning for a Nextcloud stack deploy. Runs as www-data so nothing it
# writes is unreadable by the server that has to serve it.
set -eu

log() { printf '[init] %s\n' "$*"; }
die() { printf '[init] %s\n' "$*" >&2; exit 1; }

cd /var/www/html
occ() { php occ "$@"; }

# `--lazy` prompts for confirmation and --no-interaction answers NO, so the
# confirmation is fed in explicitly; then verified, because a mismatched lazy flag
# fails by looking applied. README: "The --lazy flag is load-bearing".
occ_set_lazy() { # app key value
  printf 'yes\n' | occ config:app:set "$1" "$2" --value="$3" --lazy >/dev/null 2>&1 || true
  # Assert the FLAG, not the presence of the key. `config:app:get` succeeds just
  # as happily on the non-lazy row this function exists to prevent, so checking
  # that the key exists would pass in exactly the broken case. --details is the
  # only output that carries the flag. Its JSON also carries the value, so it is
  # matched against, never printed.
  occ config:app:get "$1" "$2" --details --output=json 2>/dev/null \
    | grep -q '"lazy":true' \
    || die "$1/$2 is still stored non-lazy; the app reads it lazily and will ignore it"
}

# Seed a POLICY value once and never again. The distinction this whole file turns
# on: WIRING (where a container lives, which secret it uses) must be re-asserted
# every deploy, because the containers move. POLICY (whether to record, whether to
# transcribe, whether consent is required) belongs to the admin panel, and a deploy
# that overwrites it takes the decision away from the person whose decision it is.
# Setting policy unconditionally is what makes an admin's UI change revert on the
# next deploy, which is unexpected behaviour and was raised in review.
occ_seed() {  # app key value
  if occ config:app:get "$1" "$2" >/dev/null 2>&1; then
    log "$1 $2 already set, leaving it alone"
  else
    occ config:app:set "$1" "$2" --value "$3" >/dev/null && log "seeded $1 $2=$3"
  fi
}

# Every optional guard and secret gets its default HERE, not at the point of use:
# `set -u` means an unexported "$RECORDING_SECRET" kills the script, so turning
# recording OFF used to break provisioning entirely.
TALK_ENABLED="${TALK_ENABLED:-true}"
RECORDING_ENABLED="${RECORDING_ENABLED:-true}"
RECORDING_CONSENT="${RECORDING_CONSENT:-2}"
LOCALAI_ENABLED="${LOCALAI_ENABLED:-true}"
RECORDING_SECRET="${RECORDING_SECRET:-}"
SMTP_HOST="${SMTP_HOST:-smtp.resend.com}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_USER="${SMTP_USER:-resend}"
MAIL_FROM="${MAIL_FROM:-no-reply}"
TURN_PORT="${TURN_PORT:-3478}"
ADMIN_EMAIL="${ADMIN_EMAIL:-}"
ADMIN_ACCOUNTS="${ADMIN_ACCOUNTS:-}"
MEMBER_ACCOUNTS="${MEMBER_ACCOUNTS:-}"
EXTRA_APPS="${EXTRA_APPS:-}"
check_bool() { # name value
  case "$2" in true|false) ;; *) die "$1 must be true or false, got '$2'" ;; esac
}
check_bool TALK_ENABLED "$TALK_ENABLED"
check_bool RECORDING_ENABLED "$RECORDING_ENABLED"
check_bool LOCALAI_ENABLED "$LOCALAI_ENABLED"

# Commas silently disable proxy trust, so refuse the string outright. Checks the
# RAW VARIABLE, never the resolved config -- that resolves per container and
# reading it here crash-looped staging. README: TRUSTED_PROXIES.
case "${TRUSTED_PROXIES:-}" in
  *,*) die "TRUSTED_PROXIES is comma-separated; the image splits on SPACES, so this silently disables proxy trust. Use: TRUSTED_PROXIES='10.0.0.0/8 172.16.0.0/12'" ;;
esac

# Nextcloud builds the sender as <from>@<domain>, so a full address here yields
# no-reply@x@x and every message is silently dropped.
case "$MAIL_FROM" in *@*) die "MAIL_FROM is the local part only, got '$MAIL_FROM'" ;; esac

[ "$ADMIN_USER" != admin ] || die "ADMIN_USER must not be the built-in 'admin'"

if [ "$TALK_ENABLED" = true ]; then
  printf '%s' "$TURN_HOST" | grep -Eq '^[A-Za-z0-9.-]+$' || die "TURN_HOST must be a hostname, got '$TURN_HOST'"
  printf '%s' "$TURN_SECRET" | grep -Eq '^[A-Za-z0-9]+$' || die "TURN_SECRET must be alphanumeric"
fi

# Object storage is optional; a partial set is not. Nextcloud reads
# OBJECTSTORE_S3_* only at first install, so whatever it picks is permanent for
# the instance and an incomplete set installs to a local volume without error.
S3_BUCKET="${S3_BUCKET:-}"
if [ -n "$S3_BUCKET" ]; then
  [ -n "${S3_HOST:-}" ]   || die "S3_BUCKET is set but S3_HOST is not"
  [ -n "${S3_KEY:-}" ]    || die "S3_BUCKET is set but S3_KEY is not"
  [ -n "${S3_SECRET:-}" ] || die "S3_BUCKET is set but S3_SECRET is not"
fi

# Swarm ignores depends_on, so the app container may still be installing.
log "waiting for Nextcloud to finish installing"
i=0
until occ status 2>/dev/null | grep -q "installed: true"; do
  i=$((i + 1))
  [ "$i" -le 90 ] || die "Nextcloud never reported installed after 15 minutes"
  sleep 10
done

# Report what the install actually chose, not what was asked for. Passing the
# variables is not proof they took, and this is the last moment the difference is
# cheap to fix.
if occ config:system:get objectstore >/dev/null 2>&1; then
  if [ -z "$S3_BUCKET" ]; then
    die "instance installed on object storage but S3_BUCKET is unset; the environment does not match the instance"
  fi
  # Which bucket, not just whether there is one. This cluster hosts both
  # `nextcloud` and `nextcloud-cd`; a presence check calls the wrong one healthy.
  got="$(occ config:system:get objectstore arguments bucket 2>/dev/null || true)"
  [ "$got" = "$S3_BUCKET" ] || die "S3_BUCKET=$S3_BUCKET was requested but the instance installed against bucket '${got:-unknown}'"
  log "primary storage: object store, bucket $S3_BUCKET"
elif [ -n "$S3_BUCKET" ]; then
  die "S3_BUCKET=$S3_BUCKET was requested but the instance installed on a local volume; rebuild from empty volumes"
else
  log "primary storage: local volume. Set S3_BUCKET/S3_HOST/S3_KEY/S3_SECRET to use object storage; honoured at first install only, so changing it later is a data migration."
fi

# The discovery prime below goes through the public hostname, so this waits on
# Traefik, DNS and the certificate as much as on Collabora.
log "waiting for Collabora discovery via https://$DOMAIN"
i=0
until [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "https://$DOMAIN/hosting/discovery")" = 200 ]; do
  i=$((i + 1))
  [ "$i" -le 60 ] || die "/hosting/discovery never answered; Office would 500 on every document open"
  sleep 10
done

log "configuring mail: $SMTP_USER@$SMTP_HOST:$SMTP_PORT, from $MAIL_FROM@$MAIL_DOMAIN"
occ config:system:set mail_smtpmode --value=smtp >/dev/null
occ config:system:set mail_smtphost --value="$SMTP_HOST" >/dev/null
occ config:system:set mail_smtpport --value="$SMTP_PORT" --type=integer >/dev/null
occ config:system:set mail_smtpsecure --value=tls >/dev/null
occ config:system:set mail_smtpauth --value=true --type=boolean >/dev/null
occ config:system:set mail_smtpname --value="$SMTP_USER" >/dev/null
occ config:system:set mail_smtppassword --value="$SMTP_PASSWORD" >/dev/null
occ config:system:set mail_from_address --value="$MAIL_FROM" >/dev/null
occ config:system:set mail_domain --value="$MAIL_DOMAIN" >/dev/null

# Enabling admin_audit is NOT enough: it logs at INFO, the instance floors at WARN,
# and the file stays zero bytes while reading as coverage. log.condition.matches
# lowers the threshold for this app alone. README: "Audit logging that records".
occ config:system:set log_type_audit --value=file >/dev/null
occ config:system:set logfile_audit --value=/var/www/html/data/audit.log >/dev/null
occ config:system:set log.condition matches 0 apps 0 --value=admin_audit >/dev/null
occ config:system:set log.condition matches 0 loglevel --value=1 --type=integer >/dev/null

# Start hour is UTC and Nextcloud works forward four hours. 8 UTC = 4am Eastern,
# deliberately AFTER the 07:00 UTC off-site backup, not on top of it: both are
# I/O-heavy and prod is one node sharing a volume between object store and DB.
occ config:system:set maintenance_window_start --value="${MAINTENANCE_WINDOW_START:-8}" --type=integer >/dev/null

# Indices ship with app updates but are never added automatically, because on a
# large table the ALTER can take minutes. Ours are small and this is idempotent:
# it adds only what is missing and is a no-op once they exist. Running it here,
# during a deploy, is the whole point -- it happens in the window we already
# accept downtime in rather than being a surprise later.
occ db:add-missing-indices >/dev/null

# NO CHECK HERE ON PURPOSE: the effective value is per-container and this one does
# not declare the variable, so asserting it here reads a staler value than the web
# server uses. The check belongs in the app container. README: TRUSTED_PROXIES.

# The stock sample contact is a plausible-looking fake PERSON, which in a member's
# address book reads like someone they should know. Sample stays ON, card is ours.
# README: "The default contact card".
occ config:app:set dav createExampleContact --value=yes >/dev/null

# The sample EVENT stays off: there is no replacement designed for it, and the stock one has
# the same fake-data problem with nothing better to put in its place.
occ config:app:set dav createExampleEvent --value=no >/dev/null

# --lazy must MATCH how the app reads the key, or the value is silently invisible.
# Check before adding one:
#   grep -r "APP_ID, 'the_key'" custom_apps/<app>/lib/ | grep 'lazy: true'
# README: "The --lazy flag is load-bearing" has the production evidence.
#
# 4h: whisper-base on CPU took 7 min for a 1-hour recording; 2h is the ceiling.
occ_set_lazy integration_openai stt_request_timeout "${STT_REQUEST_TIMEOUT:-14400}"
occ_set_lazy integration_openai request_timeout "${STT_REQUEST_TIMEOUT:-14400}"

# The card survives redeploys in appdata and is NOT re-applied here (it needs an
# authenticated HTTPS PUT, which a cold rebuild may not have a certificate for yet).
# files/defaultContact.vcf is its content, applied by hand.
# README: "The default contact card" has the command and how to verify it.

apps="richdocuments whiteboard deck calendar contacts mail quota_warning admin_audit suspicious_login admincockpit firstrunwizard twofactor_totp twofactor_backupcodes $EXTRA_APPS"
if [ "$TALK_ENABLED" = true ]; then apps="spreed $apps"; fi
for app in $apps; do
  occ app:install "$app" >/dev/null 2>&1 || true
  occ app:enable "$app" >/dev/null || die "could not enable $app"
done
log "enabled: $apps"

# Preliminary upstream, so admins only.
occ app:enable admincockpit --groups admin >/dev/null

# Runs Collabora as PHP inside this container, which the collabora service
# replaces. Leaving both enabled costs memory and serves nothing.
occ app:disable richdocumentscode >/dev/null 2>&1 || true

occ config:app:set richdocuments wopi_url --value="https://$DOMAIN" >/dev/null
occ config:app:set richdocuments public_wopi_url --value="https://$DOMAIN" >/dev/null
occ config:app:set richdocuments disable_certificate_verification --value="" >/dev/null

# Without this the cache is only filled by a background job and every document
# open returns 500 until it runs.
php -r '
require_once "/var/www/html/lib/base.php";
OC_App::loadApp("richdocuments");
$s = OC::$server->get(OCA\Richdocuments\Service\DiscoveryService::class);
$s->resetCache();
$r = $s->fetch();
if (!simplexml_load_string($r)) { fwrite(STDERR, "discovery did not parse\n"); exit(1); }
fwrite(STDERR, sprintf("[init] discovery primed, %d bytes\n", strlen($r)));
'

occ config:app:set whiteboard collabBackendUrl --value="https://$DOMAIN/whiteboard" >/dev/null
occ config:app:set whiteboard jwt_secret_key --value="$JWT_SECRET" >/dev/null

if [ "$TALK_ENABLED" = true ]; then
  occ config:app:set spreed stun_servers --value "[\"$TURN_HOST:$TURN_PORT\"]" >/dev/null
  occ config:app:set spreed turn_servers --value \
    "[{\"schemes\":\"turn\",\"server\":\"$TURN_HOST:$TURN_PORT\",\"secret\":\"$TURN_SECRET\",\"protocols\":\"udp,tcp\"}]" >/dev/null
  occ config:app:set spreed signaling_servers --value \
    "{\"servers\":[{\"server\":\"https://$TALK_HOST\",\"verify\":true}],\"secret\":\"$SIGNALING_SECRET\"}" >/dev/null
  log "talk: relay $TURN_HOST:$TURN_PORT, signaling https://$TALK_HOST"

  # Talk transcribes a finished recording BY ITSELF once any provider is
  # registered, so there is no transcription logic here: make the backends
  # reachable, register the provider, set the flag.
  if [ "$RECORDING_ENABLED" = true ] && [ -n "$RECORDING_SECRET" ]; then
    # WIRING -- re-asserted every deploy, because the container it points at moves.
    occ config:app:set spreed recording_servers --value \
      "{\"servers\":[{\"server\":\"${RECORDING_URL:-http://talk-recording:1234}\",\"verify\":false}],\"secret\":\"$RECORDING_SECRET\"}" >/dev/null

    # POLICY -- seeded once, then the admin panel owns it.
    occ_seed spreed call_recording yes
    occ_seed spreed call_recording_transcription yes

    # CONSENT. Talk ships the whole feature and we were leaving it at its default
    # of 0, which is not the neutral choice it looks like: at 0 Talk HIDES the
    # per-conversation control from moderators, so "we'll let the co-op decide"
    # actually removed their ability to decide. 2 = CONSENT_REQUIRED_OPTIONAL,
    # which is what puts the per-call switch in a moderator's hands.
    # (custom_apps/spreed/lib/Service/RecordingService.php: NO=0, YES=1, OPTIONAL=2)
    #
    # NOT occ_set_lazy. Config::getRecordingConsentConfig() reads this through the
    # non-lazy IConfig::getAppValue (lib/Config.php:231), so a lazy row would be
    # written, shown by occ, and never seen by Talk.
    occ_seed spreed recording_consent "$RECORDING_CONSENT"
    log "talk: recording ${RECORDING_URL:-http://talk-recording:1234}"

    # A docker-install daemon hands a container the Docker socket on a host that
    # is not ours, and AppAPI's own help calls it deprecated. One was registered
    # by hand on production pointing at a container that never existed and logged
    # an error on every admin visit to /settings/apps, so remove any that appear.
    for d in $(occ app_api:daemon:list 2>/dev/null | awk -F'|' '$5 ~ /docker-install/ {gsub(/ /,"",$3); print $3}'); do
      occ app_api:daemon:unregister "$d" >/dev/null 2>&1 \
        && log "removed stale docker-install daemon '$d'" || true
    done

    # LocalAI (whisper.cpp) via integration_openai -- the only transcription
    # provider now. README: "Why LocalAI, and why stt_whisper2 was removed".
    if [ "$LOCALAI_ENABLED" = true ]; then
      # `|| true` is load-bearing under `set -eu`: app:install is NOT idempotent
      # and errors when the app is already present, which aborted the whole
      # script on production 2026-08-30 -- silently, because the failure was
      # redirected to /dev/null. Same guard the app loop above uses.
      occ app:install integration_openai >/dev/null 2>&1 || true
      occ app:enable integration_openai >/dev/null 2>&1 || true
      occ config:app:set integration_openai url --value="${LOCALAI_URL:-http://localai:8080/v1}" >/dev/null
      # Point STT at the prompt-injecting proxy, not LocalAI directly. Without
      # the prompt, base-en garbled the co-op's own name on three runs of four.
      occ_set_lazy integration_openai stt_url "${LOCALAI_STT_URL:-http://stt-proxy:9040/v1}"
      occ_set_lazy integration_openai default_stt_model_id "${LOCALAI_STT_MODEL:-whisper-base-en-q5_1}"
      occ config:app:set integration_openai stt_provider_enabled --value=1 >/dev/null
      occ_set_lazy integration_openai service_name "LocalAI (self-hosted)"
      log "transcription provider: LocalAI ${LOCALAI_STT_MODEL:-whisper-base-en-q5_1} at ${LOCALAI_URL:-http://localai:8080/v1}"

      # Pin it even though LocalAI is currently the ONLY provider: without an
      # explicit preference Nextcloud picks whichever registered first, and any
      # future provider would silently take over transcription. That is how the
      # slowest possible pairing got chosen once before.
      occ_seed core ai.taskprocessing_provider_preferences \
        '{"core:audio2text":"integration_openai-audio2text"}'

      # Install the model INTO LocalAI. Without this Nextcloud is pointed at a
      # model that does not exist, which looks configured and fails on first
      # use. Idempotent: LocalAI no-ops if it is already present.
      _lm=${LOCALAI_STT_MODEL:-whisper-base-en-q5_1}
      _lb=$(printf '%s' "${LOCALAI_URL:-http://localai:8080/v1}" | sed 's#/v1$##')
      if curl -sf -m 20 "$_lb/v1/models" 2>/dev/null | grep -q "$_lm"; then
        log "LocalAI model $_lm already installed"
      elif curl -sf -m 30 -X POST "$_lb/models/apply" \
             -H 'Content-Type: application/json' -d "{\"id\":\"$_lm\"}" >/dev/null 2>&1; then
        log "LocalAI model $_lm install requested (downloads in the background)"
      else
        log "WARN could not reach LocalAI at $_lb to install $_lm"
      fi
    fi
  elif [ "$RECORDING_ENABLED" = true ]; then
    # NOT fatal -- booting clean without the secrets is deliberate. But it must
    # SAY SO: silently skipping is indistinguishable from running and doing
    # nothing, which is the failure mode this file exists to remove.
    log "WARN recording enabled but RECORDING_SECRET is empty -- recording, transcription and the STT provider are all UNCONFIGURED"
  fi

  # recording_consent is deliberately NOT set. Whether members are asked before
  # being recorded is the co-op's decision, not a default to pick for them.
fi

# user:list --output=json is a uid to display-name map, so grepping it matches
# display names too. user:info keys on the uid alone.
if occ user:info "$ADMIN_USER" >/dev/null 2>&1; then
  log "admin '$ADMIN_USER' exists"
else
  OC_PASS="$ADMIN_PASSWORD" occ user:add --password-from-env --group=admin \
    --display-name="Service Admin" "$ADMIN_USER" >/dev/null
  log "created admin '$ADMIN_USER'"
fi

# OUTSIDE the create branch on purpose: the account already exists everywhere, so
# setting the address only at creation would never reach it. Without an address
# this admin cannot be password-reset and gets no admin alerts. Idempotent.
if [ -n "$ADMIN_EMAIL" ]; then
  occ user:setting "$ADMIN_USER" settings email "$ADMIN_EMAIL" >/dev/null
  log "admin '$ADMIN_USER' email set"
else
  log "WARN ADMIN_EMAIL is empty -- '$ADMIN_USER' has no address, so it cannot be password-reset and will receive no admin alerts"
fi

# uid:Display Name:email, comma separated. Empty means a rebuild comes back with
# the service account alone and every real person has to be recreated by hand.
# $1 = uid:name:email,... list   $2 = group to put them in
provision_accounts() {
  _list="$1"; _group="$2"
  [ -n "$_list" ] || return 0
  # Trailing newline matters: `read` drops a final entry with no line ending, which
  # silently skipped the last account in the list.
  printf '%s\n' "$_list" | tr ',' '\n' | while IFS=: read -r uid name email; do
    [ -n "$uid" ] || continue
    if occ user:info "$uid" >/dev/null 2>&1; then
      # Existing accounts are left alone. Re-sending the welcome mail on every
      # start mailed dormant accounts repeatedly; password reset is the recovery path.
      log "account '$uid' exists"
      continue
    fi
    pw="$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-32)"
    OC_PASS="$pw" occ user:add --password-from-env --group="$_group" --display-name="$name" "$uid" >/dev/null
    if [ -n "${email:-}" ]; then occ user:setting "$uid" settings email "$email" >/dev/null; fi
    occ user:welcome --reset-password "$uid" >/dev/null
    log "created '$uid' in group '$_group'"
  done
}

# Members are ordinary users, NOT admins. Until now the only provisioning path put
# every account in the admin group, so adding a pilot member meant making them an
# administrator of the whole instance. That is the wrong shape for someone who is
# there to use the thing.
occ group:add members >/dev/null 2>&1 || true

provision_accounts "$ADMIN_ACCOUNTS" admin
provision_accounts "$MEMBER_ACCOUNTS" members

# NEXTCLOUD_ADMIN_USER installs as the named account, so on a fresh instance there
# is no built-in admin to disable and the command would abort the run.
if occ user:info admin >/dev/null 2>&1; then
  if occ user:info "$ADMIN_USER" >/dev/null 2>&1; then
    occ user:disable admin >/dev/null
    log "built-in 'admin' disabled"
  fi
fi

log "provisioning complete"
