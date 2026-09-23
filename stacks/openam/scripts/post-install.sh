#!/bin/sh
# OpenAM post-install: everything a fresh deploy does NOT get.
#
# WHY THIS EXISTS
# Until 2026-09-23 this stack had no post-install step at all. The realm auth
# chain, the self-service settings, the mail settings and the evaluator accounts
# existed only inside the running OpenDJ config store, put there by hand on
# 2026-09-18. That had two consequences, both of which bit:
#
#   1. amadmin's password was typed once and written down nowhere, so nobody --
#      including us -- could administer the instance.
#   2. A rebuild would have silently produced a DIFFERENT system from the one
#      Rob Aitchison and William Roush evaluated, invalidating their findings.
#
# The measured state this reproduces is recorded in ../README.md under
# "The live instance's actual configuration". Change one, change the other.
#
# IDEMPOTENT: every phase checks before it acts, so a redeploy is safe.
set -u

# ---------------------------------------------------------------- reporting
# NOT `cmd | tail -n && echo ok || echo failed`. That reports tail's exit status,
# which is always 0, so failures print the success message. This repo has lost
# weeks to that shape; see the deploy-exit-status note in the platform docs.
fail=0
step() {
  label="$1"; shift
  if "$@" >/tmp/step.out 2>&1; then
    echo "ok: $label"
  else
    rc=$?
    echo "FAILED (exit $rc): $label"
    sed 's/^/    /' /tmp/step.out | tail -15
    fail=1
  fi
}

: "${OPENAM_URL:?OPENAM_URL not set}"
: "${OPENAM_ADMIN_PASSWORD:?OPENAM_ADMIN_PASSWORD not set}"
: "${OPENAM_AMLDAPUSER_PASSWORD:?OPENAM_AMLDAPUSER_PASSWORD not set}"
: "${DIRECTORY_PASSWORD:?DIRECTORY_PASSWORD not set}"
: "${BASE_DN:=dc=openam,dc=example,dc=org}"
: "${DIRECTORY_SERVER:=opendj}"
: "${DIRECTORY_PORT:=1389}"
: "${SMTP_HOST:=smtp.resend.com}"
: "${SMTP_PORT:=465}"
: "${SMTP_USER:=resend}"
: "${SMTP_FROM:=no-reply@get.chattanooga.digital}"

CFG=/usr/openam/ssoconfiguratortools
ADM=/usr/openam/ssoadmintools

# 🔴 THE ADMIN TOOLS ARE NOT IN THE IMAGE. Measured 2026-09-23: the OpenAM image
# ships the WAR and nothing else; ssoconfiguratortools/ and ssoadmintools/ on the
# live instance were downloaded and unpacked by hand on 2026-09-18. Upstream
# publishes them as SSOConfiguratorTools-<ver>.zip (4 MB) and
# SSOAdminTools-<ver>.zip (155 MB) on the GitHub release. The stack conventions
# forbid fetching code at deploy time, a Swarm config caps at 500 KB, and 155 MB
# does not belong in git -- so until that is decided (derived image, or REST in
# place of ssoadm), a fresh volume CANNOT get past this point. Say so, first.
missing=""
ls "$CFG"/openam-configurator-tool-*.jar >/dev/null 2>&1 || missing="$missing $CFG/openam-configurator-tool-<ver>.jar"
[ -f "$ADM/setup" ] || missing="$missing $ADM/setup"
if [ -n "$missing" ]; then
  echo "FAILED: the OpenAM admin tools are not present on this volume:$missing"
  echo "        See the note above this check, and ../README.md."
  exit 1
fi

# ssoadm refuses a password file that is not readable by owner ONLY. mktemp
# gives 0600, and `chmod +x` on it yields 0700 -- both wrong here. 0400.
PWFILE=$(mktemp); printf '%s' "$OPENAM_ADMIN_PASSWORD" > "$PWFILE"; chmod 0400 "$PWFILE"
DJPW=$(mktemp);  printf '%s' "$DIRECTORY_PASSWORD"   > "$DJPW";   chmod 0400 "$DJPW"
trap 'rm -f "$PWFILE" "$DJPW" /tmp/step.out' EXIT

# ------------------------------------------------- 0. wait for the directory prep
# Swarm starts every service at once and depends_on means nothing here. An
# UNCONFIGURED OpenAM still answers isAlive.jsp, so waiting on that alone would
# run the configurator against a directory with no base entry -- "Invalid
# Suffix". dj-prep writes this marker only when it finished without failures.
echo "waiting for dj-prep ..."
i=0
while [ ! -f /ldif/.prep-done ] && [ "$i" -lt 120 ]; do i=$((i+1)); sleep 5; done
[ -f /ldif/.prep-done ] || { echo "FAILED: dj-prep never finished (no /ldif/.prep-done)"; exit 1; }
echo "ok: directory is prepared"

# ------------------------------------------------------------- 1. wait for it
echo "waiting for OpenAM at $OPENAM_URL ..."
i=0
while [ "$i" -lt 120 ]; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$OPENAM_URL/isAlive.jsp" 2>/dev/null || echo 000)
  [ "$code" = "200" ] && break
  i=$((i+1)); sleep 5
done
[ "$i" -ge 120 ] && { echo "FAILED: OpenAM never came up"; exit 1; }
echo "ok: OpenAM is responding"

# ------------------------------------------------------- 2. configure if needed
# A configured instance answers isAlive.jsp AND has a bootstrap file.
if [ -f /usr/openam/config/boot.json ]; then
  echo "skip: already configured (boot.json present)"
else
  PROPS=$(mktemp); chmod 0400 "$PROPS"
  cat > "$PROPS" <<EOF
SERVER_URL=$OPENAM_URL
DEPLOYMENT_URI=/openam
BASE_DIR=/usr/openam
locale=en_US
PLATFORM_LOCALE=en_US
AM_ENC_KEY=
ADMIN_PWD=$OPENAM_ADMIN_PASSWORD
AMLDAPUSERPASSWD=$OPENAM_AMLDAPUSER_PASSWORD
ACCEPT_LICENSES=true
DATA_STORE=dirServer
DIRECTORY_SSL=SIMPLE
DIRECTORY_SERVER=$DIRECTORY_SERVER
DIRECTORY_PORT=$DIRECTORY_PORT
ROOT_SUFFIX=$BASE_DN
DS_DIRMGRDN=cn=Directory Manager
DS_DIRMGRPASSWD=$DIRECTORY_PASSWORD
EOF
  step "configurator" java -jar "$CFG"/openam-configurator-tool-*.jar --file "$PROPS"
  rm -f "$PROPS"
fi

# ------------------------------------------------------------ 3. ssoadm setup
if [ -x "$ADM/openam/bin/ssoadm" ]; then
  echo "skip: ssoadm already set up"
else
  step "ssoadm setup" sh -c "cd $ADM && ./setup --acceptLicense --path $ADM/openam --debug $ADM/debug --log $ADM/log"
fi
SSOADM="$ADM/openam/bin/ssoadm"
[ -x "$SSOADM" ] || { echo "FAILED: ssoadm missing after setup"; exit 1; }
ADMOPTS="-u amadmin -f $PWFILE"

# --------------------------------------------- 4. the realm authentication chain
# A fresh instance has ONLY the stock `ldapService` chain, whose single DataStore
# module ignores the directory's password-policy response controls -- so a forced
# password change never happens. `userLdapService` uses the LDAP module, which
# honours them. amadmin CANNOT bind through LDAP (it lives in the config store,
# not under the user search base), so the admin chain stays on ldapService.
if $SSOADM list-auth-cfgs -e / $ADMOPTS 2>/dev/null | grep -q userLdapService; then
  echo "skip: userLdapService chain exists"
else
  step "create userLdapService chain" $SSOADM create-auth-cfg -e / -m userLdapService $ADMOPTS
  step "add LDAP REQUIRED to the chain" $SSOADM add-auth-cfg-entr -e / -m userLdapService \
      -o LDAP -c REQUIRED -p 0 $ADMOPTS
fi
step "point the realm at it" $SSOADM set-svc-attrs -e / -s iPlanetAMAuthService $ADMOPTS \
  -a iplanet-am-auth-org-config=userLdapService \
     iplanet-am-auth-admin-auth-module=ldapService \
     iplanet-am-auth-alias-attr-name=uid

# ------------------------------------------- 5. self-service and the mail server
# The REST config endpoint writes realm-level values while the self-service
# handler reads GLOBAL defaults, so a successful-looking REST write changes
# nothing. set-attr-defs is what actually lands.
step "self-service password reset" $SSOADM set-attr-defs -s selfService -t organization $ADMOPTS \
  -a selfServiceForgottenPasswordEnabled=true \
     selfServiceForgottenPasswordEmailVerificationEnabled=true \
     selfServiceForgottenPasswordKbaEnabled=false \
     selfServiceForgottenPasswordCaptchaEnabled=false \
     selfServiceForgottenPasswordTokenTTL=86400 \
     selfServiceEncryptionKeyPairAlias=selfserviceenctest \
     selfServiceSigningSecretKeyAlias=selfservicesigntest

# OpenAM's mail service has no STARTTLS -- sslState is SSL or Non SSL only -- so
# this is Resend on 465, not 587.
if [ -z "${SMTP_PASSWORD:-}" ]; then
  echo "SKIPPED: mail server -- SMTP_PASSWORD is empty, so self-service reset cannot send mail."
  echo "         Set it in the stack environment and redeploy; the phase is idempotent."
else
step "mail server" $SSOADM set-attr-defs -s MailServer -t organization $ADMOPTS \
  -a forgerockEmailServiceSMTPHostName="$SMTP_HOST" \
     forgerockEmailServiceSMTPHostPort="$SMTP_PORT" \
     forgerockEmailServiceSMTPUserName="$SMTP_USER" \
     forgerockEmailServiceSMTPUserPassword="${SMTP_PASSWORD:-}" \
     forgerockEmailServiceSMTPSSLEnabled=SSL \
     forgerockEmailServiceSMTPFromAddress="$SMTP_FROM" \
     forgerockEmailServiceSMTPSubject="Set your password"
fi

# ------------------------------------------------------------- 6. the accounts
# Created without a password on purpose: people set their own from the mail the
# system sends. We never learn it, so there is nothing to store or leak.
for u in ${OPENAM_USERS:-}; do
  if $SSOADM show-identity -e / -i "$u" -t User $ADMOPTS >/dev/null 2>&1; then
    echo "skip: $u exists"
  else
    step "create $u" $SSOADM create-identity -e / -i "$u" -t User $ADMOPTS \
      -a inetuserstatus=Active
  fi
done

# Note: force-change-on-reset lives in opendj-prep.sh, because dsconfig ships in
# the OpenDJ image and not this one.

echo
if [ "$fail" -eq 0 ]; then
  echo "post-install complete."
else
  echo "post-install FINISHED WITH FAILURES -- read the lines above."
fi
exit "$fail"
