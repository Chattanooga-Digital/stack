#!/bin/sh
# Nextcloud admin hardening — Chattanooga.Digital member services
#
# Idempotent + gated. Mirrors the house pattern of scripts/fix-settings/login-hardening.sh
# and the self-enroll (never-forced) TFA posture of scripts/setup-tfa.php.
#
# WHERE IT RUNS: inside a Nextcloud container where `occ` is available, as the web user,
# from the Nextcloud webroot — i.e. the live AIO app (`nextcloud-aio-nextcloud`, invoked
# once post-wizard via the Portainer exec API), the fallback plain-compose `app` service,
# or a future declarative stack's init step. Designed to be exec'd (`sh harden.sh`).
#
# REQUIRED ENV (falls back to /run/secrets/* first, like backup-offsite.sh):
#   NC_ADMIN_USER      non-default admin username (e.g. cdadmin) — NEVER "admin"
#   NC_ADMIN_PASSWORD  strong password for that admin (used only on first create)
#
# WHAT IT DOES (all gated, safe to re-run):
#   1. create NC_ADMIN_USER in the admin group if it doesn't already exist
#   2. enable TOTP 2FA apps for SELF-ENROLL — never sets twofactor_enforced (no lockout)
#   3. disable the built-in `admin` account, but ONLY after NC_ADMIN_USER is confirmed
# It never deletes `admin` (reversible: `occ user:enable admin`) and never enforces 2FA.

set +e

log()  { printf '[nc-harden] %s\n' "$*"; }
warn() { printf '[nc-harden] WARN: %s\n' "$*"; }

cd "${NEXTCLOUD_WEBROOT:-/var/www/html}" 2>/dev/null || true
occ() { php occ "$@"; }

# --- secrets: /run/secrets first, then env (scripts/backup-offsite.sh:24-25 pattern) ---
[ -f /run/secrets/nc_admin_user ]     && NC_ADMIN_USER="$(cat /run/secrets/nc_admin_user)"
[ -f /run/secrets/nc_admin_password ] && NC_ADMIN_PASSWORD="$(cat /run/secrets/nc_admin_password)"

if [ -z "${NC_ADMIN_USER:-}" ]; then
  warn "NC_ADMIN_USER is required — aborting"
  exit 1
fi
if [ "$NC_ADMIN_USER" = "admin" ]; then
  warn "NC_ADMIN_USER must not be the default 'admin' — that's the whole point; aborting"
  exit 1
fi

users_json="$(occ user:list --output=json 2>/dev/null)"

# 1. create the non-default admin if missing (gated like module-enables.sh:59-62)
if printf '%s' "$users_json" | grep -q "\"$NC_ADMIN_USER\""; then
  log "admin user '$NC_ADMIN_USER' already exists — skipping create"
else
  if [ -z "${NC_ADMIN_PASSWORD:-}" ]; then
    warn "'$NC_ADMIN_USER' missing and NC_ADMIN_PASSWORD not set — cannot create; aborting"
    exit 1
  fi
  OC_PASS="$NC_ADMIN_PASSWORD" occ user:add --password-from-env --group=admin \
    --display-name="CD Admin" "$NC_ADMIN_USER" \
    && log "created admin '$NC_ADMIN_USER' (admin group)" \
    || { warn "failed to create '$NC_ADMIN_USER' — aborting before touching 'admin'"; exit 1; }
fi

# 1b. named admin accounts, so a rebuild does not come back with only one login.
#
# Before this existed, cdadmin was the only account a rebuild produced, and the real
# people were added by hand afterwards — so tearing an instance down silently deleted
# them. NC_ADMIN_ACCOUNTS makes them part of the recipe:
#
#   NC_ADMIN_ACCOUNTS="greg:Greg Laudeman:greg@eduity.net,jon:TurtleWolfe:jon@example.net"
#
# No password is set here and none is stored. Each account is created with a throwaway
# random secret and immediately sent Nextcloud's own set-your-own-password link, which
# is the flow already used for the staging accounts. Unset the variable and this is a
# no-op, so instances that do not want named admins are unaffected.
if [ -n "${NC_ADMIN_ACCOUNTS:-}" ]; then
  echo "$NC_ADMIN_ACCOUNTS" | tr ',' '\n' | while IFS=':' read -r uid name email; do
    [ -n "$uid" ] || continue
    if printf '%s' "$users_json" | grep -q "\"$uid\""; then
      log "account '$uid' already exists — skipping"
      continue
    fi
    # 32 chars of base62. Not `tr </dev/urandom | head`: head closes the pipe, tr takes
    # SIGPIPE, and under pipefail that exits the script silently.
    pw="$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | cut -c1-32)"
    if OC_PASS="$pw" occ user:add --password-from-env --group=admin \
         --display-name="$name" "$uid" >/dev/null 2>&1; then
      [ -n "$email" ] && occ user:setting "$uid" settings email "$email" >/dev/null 2>&1
      # user:welcome --reset-password, NOT user:resetpassword --send-email: the latter
      # flag does not exist on 33 and fails silently into the fallback branch.
      occ user:welcome --reset-password "$uid" >/dev/null 2>&1 \
        && log "created '$uid' (admin) and sent a set-password link to $email" \
        || log "created '$uid' (admin); welcome mail did not send, reset the password by hand"
    else
      warn "failed to create '$uid'"
    fi
    unset pw
  done
fi

# 2. TOTP 2FA — enable apps for SELF-ENROLL only (occ app:enable is idempotent).
#    NEVER set twofactor_enforced: enforcing before a device is enrolled locks the operator
#    out (same reasoning as setup-tfa.php's required_roles=[] self-enroll posture).
occ app:enable twofactor_totp twofactor_backupcodes >/dev/null 2>&1 \
  && log "2FA available (twofactor_totp + backup codes) — self-enroll at /settings/user/security" \
  || warn "could not enable 2FA apps (may already be enabled)"

# 3. disable the built-in 'admin' — ONLY once our named admin is confirmed present
#    (never orphan the last working admin). Disable is reversible; we never delete.
users_json="$(occ user:list --output=json 2>/dev/null)"
if printf '%s' "$users_json" | grep -q "\"$NC_ADMIN_USER\"" \
   && printf '%s' "$users_json" | grep -q '"admin"'; then
  if occ user:info admin --output=json 2>/dev/null | grep -qE '"enabled" *: *false'; then
    log "'admin' already disabled"
  else
    occ user:disable admin >/dev/null 2>&1 \
      && log "disabled built-in 'admin' (reversible: occ user:enable admin)" \
      || warn "could not disable 'admin'"
  fi
else
  log "'admin' or '$NC_ADMIN_USER' not both present — leaving 'admin' untouched"
fi

log "hardening complete"
