#!/bin/sh
# Provisioning for a Nextcloud stack deploy. Runs as www-data so nothing it
# writes is unreadable by the server that has to serve it.
set -eu

log() { printf '[init] %s\n' "$*"; }
die() { printf '[init] %s\n' "$*" >&2; exit 1; }

cd /var/www/html
occ() { php occ "$@"; }

TALK_ENABLED="${TALK_ENABLED:-true}"
SMTP_HOST="${SMTP_HOST:-smtp.resend.com}"
SMTP_PORT="${SMTP_PORT:-587}"
SMTP_USER="${SMTP_USER:-resend}"
MAIL_FROM="${MAIL_FROM:-no-reply}"
TURN_PORT="${TURN_PORT:-3478}"
ADMIN_ACCOUNTS="${ADMIN_ACCOUNTS:-}"
EXTRA_APPS="${EXTRA_APPS:-}"
THEME_NAME="${THEME_NAME:-}"
THEME_URL="${THEME_URL:-}"
THEME_SLOGAN="${THEME_SLOGAN:-}"
THEME_COLOR="${THEME_COLOR:-}"
THEME_BACKGROUND="${THEME_BACKGROUND:-}"
THEME_LOGO_B64="${THEME_LOGO_B64:-}"
THEME_LOGOHEADER_B64="${THEME_LOGOHEADER_B64:-}"
THEME_FAVICON_B64="${THEME_FAVICON_B64:-}"

case "$TALK_ENABLED" in true|false) ;; *) die "TALK_ENABLED must be true or false" ;; esac

# Nextcloud builds the sender as <from>@<domain>, so a full address here yields
# no-reply@x@x and every message is silently dropped.
case "$MAIL_FROM" in *@*) die "MAIL_FROM is the local part only, got '$MAIL_FROM'" ;; esac

required="DOMAIN JWT_SECRET SMTP_PASSWORD MAIL_DOMAIN ADMIN_USER ADMIN_PASSWORD"
if [ "$TALK_ENABLED" = true ]; then
  required="$required TALK_HOST TURN_HOST TURN_SECRET SIGNALING_SECRET"
fi
for v in $required; do
  eval "val=\${$v:-}"
  [ -n "$val" ] || die "$v is required"
done

[ "$ADMIN_USER" != admin ] || die "ADMIN_USER must not be the built-in 'admin'"

if [ "$TALK_ENABLED" = true ]; then
  printf '%s' "$TURN_HOST" | grep -Eq '^[A-Za-z0-9.-]+$' || die "TURN_HOST must be a hostname, got '$TURN_HOST'"
  printf '%s' "$TURN_SECRET" | grep -Eq '^[A-Za-z0-9]+$' || die "TURN_SECRET must be alphanumeric"
fi

# Swarm ignores depends_on, so the app container may still be installing.
log "waiting for Nextcloud to finish installing"
i=0
until occ status 2>/dev/null | grep -q "installed: true"; do
  i=$((i + 1))
  [ "$i" -le 90 ] || die "Nextcloud never reported installed after 15 minutes"
  sleep 10
done

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
fi

users="$(occ user:list --output=json)"
if printf '%s' "$users" | grep -q "\"$ADMIN_USER\""; then
  log "admin '$ADMIN_USER' exists"
else
  OC_PASS="$ADMIN_PASSWORD" occ user:add --password-from-env --group=admin \
    --display-name="Service Admin" "$ADMIN_USER" >/dev/null
  log "created admin '$ADMIN_USER'"
fi

# uid:Display Name:email, comma separated. Empty means a rebuild comes back with
# the service account alone and every real person has to be recreated by hand.
if [ -n "$ADMIN_ACCOUNTS" ]; then
  printf '%s\n' "$ADMIN_ACCOUNTS" | tr ',' '\n' | while IFS=: read -r uid name email; do
    [ -n "$uid" ] || continue
    if printf '%s' "$users" | grep -q "\"$uid\""; then
      log "account '$uid' exists"
      continue
    fi
    pw="$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-32)"
    OC_PASS="$pw" occ user:add --password-from-env --group=admin --display-name="$name" "$uid" >/dev/null
    if [ -n "${email:-}" ]; then occ user:setting "$uid" settings email "$email" >/dev/null; fi
    # Sends a set-password link, so it must not run for an account that exists.
    occ user:welcome --reset-password "$uid" >/dev/null || log "'$uid' created; welcome mail did not send"
    log "created '$uid'"
  done
fi

# NEXTCLOUD_ADMIN_USER installs as the named account, so on a fresh instance there
# is no built-in admin to disable and the command would abort the run.
if occ user:info admin >/dev/null 2>&1; then
  if printf '%s' "$(occ user:list --output=json)" | grep -q "\"$ADMIN_USER\""; then
    occ user:disable admin >/dev/null
    log "built-in 'admin' disabled"
  fi
fi

# Branding is instance state, so a rebuild from empty volumes loses it unless it
# is restored here. theming:config has no key for the images; the app reads them
# from appdata and trusts the matching *Mime entry, so that is what this writes.
if [ -n "$THEME_NAME$THEME_COLOR$THEME_LOGO_B64$THEME_FAVICON_B64" ]; then
  for pair in "name=$THEME_NAME" "url=$THEME_URL" "slogan=$THEME_SLOGAN" \
              "primary_color=$THEME_COLOR" "background_color=$THEME_BACKGROUND"; do
    key=${pair%%=*}; val=${pair#*=}
    if [ -n "$val" ]; then occ theming:config "$key" "$val" >/dev/null; fi
  done

  imgdir="$(occ config:system:get datadirectory)/appdata_$(occ config:system:get instanceid)/theming/global/images"
  mkdir -p "$imgdir"
  for img in logo logoheader favicon; do
    eval "b64=\${THEME_$(printf '%s' "$img" | tr '[:lower:]' '[:upper:]')_B64:-}"
    if [ -n "$b64" ]; then
      printf '%s' "$b64" | base64 -d > "$imgdir/$img"
      occ config:app:set theming "${img}Mime" --value=image/png >/dev/null
      log "branding: restored $img ($(wc -c < "$imgdir/$img") bytes)"
    fi
  done

  # Clients cache the old images against the old number.
  cb="$(occ config:app:get theming cachebuster 2>/dev/null || true)"
  occ config:app:set theming cachebuster --value="$(( ${cb:-0} + 1 ))" >/dev/null
fi

log "provisioning complete"
