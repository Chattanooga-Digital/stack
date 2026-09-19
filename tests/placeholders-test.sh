#!/usr/bin/env bash
# Guards the guard. A detector that silently stops detecting reads exactly like
# a clean repo, so the canaries below MUST be rejected or this test fails. That
# is the whole point: the bug this tooling exists to catch was a check that
# accepted a placeholder and reported success.
set -uo pipefail
cd "$(dirname "$0")/.."

fail=0

must_reject() {
  if printf '%s\n' "$1" | python3 scripts/placeholders.py >/dev/null; then
    echo "FAIL: should have been rejected -> $1"
    fail=1
  fi
}

must_accept() {
  local out
  out=$(printf '%s\n' "$1" | python3 scripts/placeholders.py)
  if [ -n "$out" ]; then
    echo "FAIL: should have been accepted -> $1 ($out)"
    fail=1
  fi
}

# --- the values that actually shipped and cost a day
must_reject 'SMTP_HOST=smtp.invalid'
must_reject 'SMTP_USER=unused'
must_reject 'MAIL_FROM=noreply@smtp.invalid'
# --- other shapes of the same mistake
must_reject 'DB_PASSWORD=changeme'
must_reject 'DOMAIN=<your-domain>'
must_reject 'API=https://api.example.com/v1'
must_reject 'HOST=foo.test'
must_reject 'MAIL=admin@example.org'
must_reject 'TPL={{ domain }}'

# --- real settings that must NOT be flagged, or the check gets switched off
must_accept 'SMTP_HOST=smtp.resend.com'
must_accept 'DOMAIN=keycloak.staging.chattanooga.digital'
must_accept 'MAIL_FROM=no-reply@get.chattanooga.digital'
must_accept 'DB_PASSWORD=LfAKMo0pUS.Tz-gk5vgR'
must_accept 'SMTP_USER=resend'
must_accept 'DB_NAME=authentik'
# empty is already caught by compose's ${VAR:?}; flagging it here would be noise
must_accept 'SMTP_PASSWORD='

if [ "$fail" = 0 ]; then
  echo "ok   placeholder detection (canaries rejected, real values accepted)"
fi
exit "$fail"
