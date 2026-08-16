#!/bin/sh
# Nextcloud outbound mail (Resend) — Chattanooga.Digital member services
#
# Idempotent + gated, mirroring scripts/nextcloud/harden.sh. Safe to re-run.
#
# WHY THIS EXISTS: Nextcloud shipped with NO mail configuration at all, so share
# invitations, activity notifications and password resets have been failing silently.
# Greg moved transactional email to Resend on 2026-07-29 (sending subdomain
# get.chattanooga.digital) after Stalwart was shut down on 07-28.
#
# WHERE IT RUNS: inside a Nextcloud container where `occ` is available, as the web user,
# from the Nextcloud webroot — i.e. the live AIO app (`nextcloud-aio-nextcloud`, invoked
# via the Portainer exec API), the fallback plain-compose `app` service, or a future
# declarative stack's init step. Designed to be exec'd (`sh mail.sh`).
#
# REQUIRED (falls back to /run/secrets/* first, like harden.sh):
#   NC_SMTP_PASSWORD   the Resend API key (starts `re_`). This IS the SMTP password.
#
# OPTIONAL (defaults are the CD production values):
#   NC_SMTP_HOST=smtp.resend.com   NC_SMTP_PORT=587
#   NC_SMTP_USER=resend            <- literal string for every Resend account, NOT an address
#   NC_MAIL_FROM=no-reply          <- LOCAL PART ONLY (see the footgun below)
#   NC_MAIL_DOMAIN=get.chattanooga.digital
#
# ⚠️ THE FOOTGUN: Nextcloud composes the visible sender as `mail_from_address@mail_domain`.
# `mail_from_address` is the LOCAL PART ONLY. Putting a full address there yields
# `no-reply@get.chattanooga.digital@get.chattanooga.digital` and every send fails. This is a
# DIFFERENT shape from the hub, where SMTP_FROM is one complete address.
#
# ⚠️ THE DOMAIN IS `get.`, NOT `go.`. Greg's 2026-07-29 email said go.chattanooga.digital;
# the Resend account is configured for get.chattanooga.digital. `go.` does not exist.
#
# Domain state, verified 2026-07-31 via the Resend API: get.chattanooga.digital is
# status=verified with DKIM/SPF/MX live (confirmed against a public resolver, not just the
# dashboard), and a real send from no-reply@get.chattanooga.digital succeeded. So DNS is NOT
# a blocker here.
#
# ⚠️ What CAN still block: a Resend API key may be scoped to a single domain. A key scoped
# elsewhere returns 403 "not authorized to send emails from ..." — which looks exactly like a
# config error. This script will happily write a correct config that cannot deliver; the
# config is never the proof. See cd-hubzilla/docs/SOP-TRANSACTIONAL-EMAIL.md.

set +e

log()  { printf '[nc-mail] %s\n' "$*"; }
warn() { printf '[nc-mail] WARN: %s\n' "$*"; }

cd "${NEXTCLOUD_WEBROOT:-/var/www/html}" 2>/dev/null || true
occ() { php occ "$@"; }

# --- secret: /run/secrets first, then env (harden.sh:31-32 pattern) ---
[ -f /run/secrets/nc_smtp_password ] && NC_SMTP_PASSWORD="$(cat /run/secrets/nc_smtp_password)"

NC_SMTP_HOST="${NC_SMTP_HOST:-smtp.resend.com}"
NC_SMTP_PORT="${NC_SMTP_PORT:-587}"
NC_SMTP_USER="${NC_SMTP_USER:-resend}"
NC_MAIL_FROM="${NC_MAIL_FROM:-no-reply}"
NC_MAIL_DOMAIN="${NC_MAIL_DOMAIN:-get.chattanooga.digital}"

if [ -z "${NC_SMTP_PASSWORD:-}" ]; then
  warn "NC_SMTP_PASSWORD (the Resend API key) is required — aborting without touching config"
  exit 1
fi

# Guard the footgun rather than trusting the caller: a full address in the local-part slot
# is silently broken mail, which is exactly the class of bug that cost us #5 on the hub.
case "$NC_MAIL_FROM" in
  *@*)
    warn "NC_MAIL_FROM must be the LOCAL PART only (e.g. 'no-reply'), not '$NC_MAIL_FROM'."
    warn "Nextcloud builds the sender as mail_from_address@mail_domain — aborting."
    exit 1
    ;;
esac

log "configuring outbound mail: $NC_SMTP_USER@$NC_SMTP_HOST:$NC_SMTP_PORT, from ${NC_MAIL_FROM}@${NC_MAIL_DOMAIN}"

occ config:system:set mail_smtpmode    --value="smtp"             >/dev/null 2>&1 || warn "mail_smtpmode failed"
occ config:system:set mail_smtphost    --value="$NC_SMTP_HOST"    >/dev/null 2>&1 || warn "mail_smtphost failed"
occ config:system:set mail_smtpport    --value="$NC_SMTP_PORT" --type=integer >/dev/null 2>&1 || warn "mail_smtpport failed"
occ config:system:set mail_smtpsecure  --value="tls"              >/dev/null 2>&1 || warn "mail_smtpsecure failed"
occ config:system:set mail_smtpauth    --value=true --type=boolean >/dev/null 2>&1 || warn "mail_smtpauth failed"
occ config:system:set mail_smtpname    --value="$NC_SMTP_USER"    >/dev/null 2>&1 || warn "mail_smtpname failed"
occ config:system:set mail_smtppassword --value="$NC_SMTP_PASSWORD" >/dev/null 2>&1 || warn "mail_smtppassword failed"
occ config:system:set mail_from_address --value="$NC_MAIL_FROM"   >/dev/null 2>&1 || warn "mail_from_address failed"
occ config:system:set mail_domain      --value="$NC_MAIL_DOMAIN"  >/dev/null 2>&1 || warn "mail_domain failed"

# --- read back what actually landed (never trust the writes) ---
log "verifying:"
for k in mail_smtpmode mail_smtphost mail_smtpport mail_smtpsecure mail_smtpauth \
         mail_smtpname mail_from_address mail_domain; do
  v="$(occ config:system:get "$k" 2>/dev/null)"
  log "  $k = ${v:-<unset>}"
done
# Deliberately NOT echoed: mail_smtppassword. Confirm only that it is non-empty.
if [ -n "$(occ config:system:get mail_smtppassword 2>/dev/null)" ]; then
  log "  mail_smtppassword = <set>"
else
  warn "  mail_smtppassword is EMPTY — auth will fail"
fi

log "config written. THIS IS NOT PROOF OF DELIVERY."
log "Verify for real: Settings > Administration > Basic settings > 'Send email' test,"
log "or trigger a password reset and confirm the message actually arrives."
log "If it doesn't, check that get.chattanooga.digital is verified in the Resend dashboard."
