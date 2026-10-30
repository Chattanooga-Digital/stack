#!/usr/bin/env bash
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

must_reject 'SMTP_HOST=smtp.invalid'
must_reject 'SMTP_USER=unused'
must_reject 'MAIL_FROM=noreply@smtp.invalid'
must_reject 'DB_PASSWORD=changeme'
must_reject 'DOMAIN=<your-domain>'
must_reject 'API=https://api.example.com/v1'
must_reject 'HOST=foo.test'
must_reject 'MAIL=admin@example.org'
must_reject 'TPL={{ domain }}'


must_accept 'SMTP_HOST=smtp.resend.com'
must_accept 'DOMAIN=keycloak.staging.chattanooga.digital'
must_accept 'MAIL_FROM=no-reply@get.chattanooga.digital'
must_accept 'DB_PASSWORD=correct-horse-battery-staple'
must_accept 'SMTP_USER=resend'
must_accept 'DB_NAME=authentik'
# Empty is left to compose's ${VAR:?}.
must_accept 'SMTP_PASSWORD='

if [ "$fail" = 0 ]; then
  echo "ok   placeholder detection (canaries rejected, real values accepted)"
fi
exit "$fail"
