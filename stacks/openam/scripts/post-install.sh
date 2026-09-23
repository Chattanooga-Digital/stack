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
: "${OPENAM_VERSION:?OPENAM_VERSION not set}"
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
# OpenAM's own config dir -- the image's OPENAM_DATA_DIR, and what CATALINA_OPTS
# points the server at. NOT /usr/openam. Every value below was checked against the
# configurator's own record of the 2026-09-18 run (config/install.log in the backup).
AMCONFIG=/usr/openam/config
_host=${OPENAM_URL#https://}; _host=${_host#http://}; _host=${_host%%/*}
SERVER_URL="https://$_host"                       # origin only; DEPLOYMENT_URI adds /openam
COOKIE_DOMAIN="${OPENAM_COOKIE_DOMAIN:-.${_host#*.}}"   # 09-18: .staging.chattanooga.digital

# THE TOOLS COME FROM THE IMAGE, THROUGH THE VOLUME. Upstream's Dockerfile bakes
# SSOConfiguratorTools and SSOAdminTools into /usr/openam; openam-home mounts over
# it, and Docker fills an EMPTY named volume from the image on first mount. So a
# fresh volume has this image's tools -- and a REUSED one keeps the tools of
# whatever image created it. Upgrading while keeping openam-home would run this
# version's WAR against an older configurator. Check the version, not presence.
# (Until 2026-09-23 this said the tools were not in the image at all. Wrong: the
# search behind it excluded /usr/openam, the one path the volume masks.)
jar=$(ls "$CFG"/openam-configurator-tool-*.jar 2>/dev/null | head -1)
if [ -z "$jar" ] || [ ! -f "$ADM/setup" ]; then
  echo "FAILED: no admin tools under /usr/openam. openam-home should have been filled"
  echo "        from the image on first mount; was it created some other way?"
  exit 1
fi
have=$(basename "$jar" .jar | sed 's/^openam-configurator-tool-//')
if [ "$have" != "$OPENAM_VERSION" ]; then
  echo "FAILED: openam-home carries configurator $have, but OPENAM_VERSION is $OPENAM_VERSION."
  echo "        The volume was created by an older image and is masking this one's tools."
  echo "        Rebuild with a fresh openam-home -- see ../README.md."
  exit 1
fi
echo "ok: admin tools on the volume match OPENAM_VERSION ($have)"

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
if [ -f "$AMCONFIG/boot.json" ]; then
  echo "skip: already configured (boot.json present)"
else
  PROPS=$(mktemp); chmod 0400 "$PROPS"
  cat > "$PROPS" <<EOF
SERVER_URL=$SERVER_URL
DEPLOYMENT_URI=/openam
BASE_DIR=$AMCONFIG
COOKIE_DOMAIN=$COOKIE_DOMAIN
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
DIRECTORY_ADMIN_PORT=4444
DIRECTORY_JMX_PORT=1689
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
  # --path is path.AMConfig: the SERVER's config dir, read out of setup itself. The
  # tools then install under $ADM/<deployment-uri>/, hence $ADM/openam/bin/ssoadm.
  step "ssoadm setup" sh -c "cd $ADM && ./setup --acceptLicense --path $AMCONFIG --debug /usr/openam/ssoadm-debug --log /usr/openam/ssoadm-log"
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
