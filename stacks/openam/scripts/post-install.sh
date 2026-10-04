#!/bin/sh
# Configures a fresh OpenAM and reproduces what a deploy does not get: the realm auth
# chain, self-service, mail, accounts and the admin group.
# Every phase checks before it acts, so a redeploy is safe.
set -u

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
# OpenAM's own config dir (the image's OPENAM_DATA_DIR), which CATALINA_OPTS points the
# server at. Not /usr/openam.
AMCONFIG=/usr/openam/config
_host=${OPENAM_URL#https://}; _host=${_host#http://}; _host=${_host%%/*}
SERVER_URL="https://$_host"                       # origin only; DEPLOYMENT_URI adds /openam
COOKIE_DOMAIN="${OPENAM_COOKIE_DOMAIN:-.${_host#*.}}"

# The tools come from the image through the openam-home volume. An empty volume is
# filled from the image on first mount, and a reused one keeps the tools of whatever
# image created it. Check the version, not presence.
jar=''
for f in "$CFG"/openam-configurator-tool-*.jar; do [ -f "$f" ] && { jar=$f; break; }; done
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

# ssoadm requires the password file to be read-only for its owner (0400). mktemp's
# 0600 is refused.
PWFILE=$(mktemp); printf '%s' "$OPENAM_ADMIN_PASSWORD" > "$PWFILE"; chmod 0400 "$PWFILE"
DJPW=$(mktemp);  printf '%s' "$DIRECTORY_PASSWORD"   > "$DJPW";   chmod 0400 "$DJPW"
trap 'rm -f "$PWFILE" "$DJPW" /tmp/step.out ${SS:+"$SS"} ${MS:+"$MS"}' EXIT

# Swarm ignores depends_on. dj-prep writes this marker only on success, and the
# configurator fails with "Invalid Suffix" until the base entry exists.
echo "waiting for dj-prep ..."
i=0
while [ ! -f /ldif/.prep-done ] && [ "$i" -lt 120 ]; do i=$((i+1)); sleep 5; done
[ -f /ldif/.prep-done ] || { echo "FAILED: dj-prep never finished (no /ldif/.prep-done)"; exit 1; }
echo "ok: directory is prepared"

# Up means Tomcat is serving the webapp: isAlive.jsp answers 200 when configured, or
# 302 to config/options.htm when not. Anything else (000, 404, or 502 from Traefik
# while Tomcat starts) is not up yet.
echo "waiting for OpenAM at $OPENAM_URL ..."
i=0; state=''
while [ "$i" -lt 120 ]; do
  out=$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "$OPENAM_URL/isAlive.jsp" 2>/dev/null || echo 000)
  case "$out" in
    200\ *)                         state=configured; break ;;
    302\ */openam/config/options.htm) state=unconfigured; break ;;
  esac
  i=$((i+1)); sleep 5
done
[ -n "$state" ] || { echo "FAILED: OpenAM never came up (last answer: ${out:-none})"; exit 1; }
echo "ok: OpenAM is responding ($state)"

if [ -f "$AMCONFIG/boot.json" ]; then
  echo "skip: already configured (boot.json present)"
else
  # mktemp gives 0600. Do not chmod 0400 before the write below: this image runs as a
  # non-root user, so the write would be refused and the configurator would read an
  # empty file ("Property 'SERVER_URL' was not set").
  PROPS=$(mktemp)
  # The licence key is ACCEPT_LICENSES; acceptLicense is ignored without an error.
  # AM_ENC_KEY stays empty, the tool generates one. AMLDAPUSERPASSWD has no _CONFIRM twin.
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
  step "configurator" java -jar "$jar" --file "$PROPS"
  rm -f "$PROPS"
  # Nothing below works without a configured server.
  if [ "$fail" -ne 0 ] || [ ! -f "$AMCONFIG/boot.json" ]; then
    echo "STOPPING: OpenAM is not configured (no $AMCONFIG/boot.json); nothing below can work."
    exit 1
  fi
fi

if [ -x "$ADM/openam/bin/ssoadm" ]; then
  echo "skip: ssoadm already set up"
else
  # --path is the server's config dir. The tools then install under
  # $ADM/<deployment-uri>/, hence $ADM/openam/bin/ssoadm.
  step "ssoadm setup" sh -c "cd $ADM && ./setup --acceptLicense --path $AMCONFIG --debug /usr/openam/ssoadm-debug --log /usr/openam/ssoadm-log"
fi
SSOADM="$ADM/openam/bin/ssoadm"
[ -x "$SSOADM" ] || { echo "FAILED: ssoadm missing after setup"; exit 1; }
adm() { _sub=$1; shift; "$SSOADM" "$_sub" -u amadmin -f "$PWFILE" "$@"; }

# A fresh instance has only the stock ldapService chain. Its DataStore module ignores
# the directory's password-policy response controls, so a forced password change never
# happens. userLdapService uses the LDAP module, which honours them. amadmin cannot
# bind through LDAP (it lives in the config store, not under the user search base), so
# the admin chain stays on ldapService.
if adm list-auth-cfgs -e / 2>/dev/null | grep -q userLdapService; then
  echo "skip: userLdapService chain exists"
else
  step "create userLdapService chain" adm create-auth-cfg -e / -m userLdapService
  step "add LDAP REQUIRED to the chain" adm add-auth-cfg-entr -e / -m userLdapService \
      -o LDAP -c REQUIRED -p 0
fi
step "point the realm at it" adm set-svc-attrs -e / -s iPlanetAMAuthService \
  -a iplanet-am-auth-org-config=userLdapService \
     iplanet-am-auth-admin-auth-module=ldapService \
     iplanet-am-auth-alias-attr-name=uid

# Each goes in two places: the service's global defaults (set-attr-defs), which the
# self-service handler reads, and the root realm as an assigned service (add-svc-realm,
# then set-realm-svc-attrs). Whether the realm copy is required is untested.
# Values go in owner-only datafiles (ssoadm -D), so the SMTP password is never in argv.

# realm_svc <service> <datafile>: assign to the root realm, or update if assigned.
realm_svc() {
  _svcs=$(adm show-realm-svcs -e / 2>&1) || {
    echo "FAILED: realm $1 -- could not list the realm's services"; fail=1; return 0; }
  if printf '%s\n' "$_svcs" | grep -qx "$1"; then
    step "realm $1 (update)" adm set-realm-svc-attrs -e / -s "$1" -D "$2"
  else
    step "realm $1 (assign)" adm add-svc-realm -e / -s "$1" -D "$2"
  fi
}

SS=$(mktemp)
cat > "$SS" <<'EOF'
selfServiceForgottenPasswordEnabled=true
selfServiceForgottenPasswordEmailVerificationEnabled=true
selfServiceForgottenPasswordKbaEnabled=false
selfServiceForgottenPasswordCaptchaEnabled=false
selfServiceForgottenPasswordTokenTTL=86400
selfServiceEncryptionKeyPairAlias=selfserviceenctest
selfServiceSigningSecretKeyAlias=selfservicesigntest
EOF
step "self-service password reset (defaults)" adm set-attr-defs -s selfService -t organization -D "$SS"
realm_svc selfService "$SS"
rm -f "$SS"

# OpenAM's mail service has no STARTTLS (sslState is SSL or Non SSL), so use an SSL
# port: 465, not 587.
if [ -z "${SMTP_PASSWORD:-}" ]; then
  echo "SKIPPED: mail server -- SMTP_PASSWORD is empty, so self-service reset cannot send mail."
  echo "         Set it in the stack environment and redeploy; the phase is idempotent."
else
  MS=$(mktemp)
  printf '%s\n' \
    "forgerockEmailServiceSMTPHostName=$SMTP_HOST" \
    "forgerockEmailServiceSMTPHostPort=$SMTP_PORT" \
    "forgerockEmailServiceSMTPUserName=$SMTP_USER" \
    "forgerockEmailServiceSMTPUserPassword=$SMTP_PASSWORD" \
    "forgerockEmailServiceSMTPSSLEnabled=SSL" \
    "forgerockEmailServiceSMTPFromAddress=$SMTP_FROM" \
    "forgerockEmailServiceSMTPSubject=Set your password" \
    "forgerockEmailServiceSMTPMessage=Use the link below to choose a password for your account." \
    > "$MS"
  step "mail server (defaults)" adm set-attr-defs -s MailServer -t organization -D "$MS"
  realm_svc MailServer "$MS"
  rm -f "$MS"
fi

# exists | absent | error for one identity. A failed check must never read as "absent".
# ssoadm show-identity does not exist (rc 12), and get-identity returns rc 127 for "not
# found" and for every other failure. list-identities returns rc 0 either way and the
# output says which:
#   present -> "<uid> (id=<uid>,ou=user,<basedn>)"      absent -> "There were no entries."
identity_state() {          # $1 name, $2 type (default User)
  _out=$(adm list-identities -e / -x "$1" -t "${2:-User}" 2>&1) || { echo error; return 0; }
  if printf '%s\n' "$_out" | grep -q "^$1 (id=$1,"; then echo exists
  elif printf '%s\n' "$_out" | grep -q 'There were no entries'; then echo absent
  else echo error; fi
}

# OpenAM will not create a user with no password ("Minimum password length is 8."), so
# each account gets 32 random characters that nobody is told. They go in an owner-only
# file for ssoadm -D, never in argv, and the file is deleted at once. The directory's
# force-change-on-reset makes an administrator-set password must-change anyway.
#
# One record per person, ';' between records, ',' between fields: uid,mail,Given,Surname
# Self-service reset sends to the account's mail attribute, so an account without one
# could never receive its link. A record missing any field is refused, not half-created.
#
# Create-only: an existing account is left alone, so a changed address is not reverted.
set -f                     # the records are data; never let the shell glob them
_ifs=$IFS; IFS=';'; n=0
for rec in ${OPENAM_USERS:-}; do
  IFS=$_ifs
  n=$((n+1))
  rec=$(printf '%s' "$rec" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
  [ -n "$rec" ] || continue
  IFS=, read -r u mail given sn extra <<EOF
$rec
EOF
  IFS=$_ifs
  case "$u" in ''|*[!a-z0-9._-]*) u='' ;; esac
  case "$mail" in *@*.*) ;; *) mail='' ;; esac
  if [ -z "$u" ] || [ -z "$mail" ] || [ -z "$given" ] || [ -z "$sn" ] || [ -n "$extra" ]; then
    echo "FAILED: OPENAM_USERS record $n is not uid,mail,Given,Surname -- not created"
    fail=1; continue
  fi
  st=$(identity_state "$u")
  if [ "$st" = exists ]; then
    echo "skip: $u exists"
  elif [ "$st" != absent ]; then
    echo "FAILED: $u -- could not tell whether it exists, so not creating it"; fail=1
  else
    DATA=$(mktemp)      # 0600 already; written before anything restricts it
    rnd=$(head -c 48 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32)
    if [ "${#rnd}" -lt 32 ]; then
      echo "FAILED: create $u -- could not generate a random password"; fail=1; rm -f "$DATA"; continue
    fi
    printf 'inetuserstatus=Active\nmail=%s\ngivenName=%s\nsn=%s\ncn=%s %s\nuserpassword=%s\n' \
      "$mail" "$given" "$sn" "$given" "$sn" "$rnd" > "$DATA"
    rnd=''
    step "create $u" adm create-identity -e / -i "$u" -t User -D "$DATA"
    rm -f "$DATA"
    [ "$(identity_state "$u")" = exists ] || { echo "FAILED: $u does not read back after create"; fail=1; }
  fi
done
IFS=$_ifs; set +f

# The configurator creates uid=demo with OpenAM's documented password "changeit",
# which signs in from the public URL. Delete it.
case "$(identity_state demo)" in
  absent) echo "skip: no demo account" ;;
  exists)
    step "delete the configurator's demo account" adm delete-identities -e / -i demo -t User
    [ "$(identity_state demo)" = absent ] || { echo "FAILED: demo still present after delete"; fail=1; } ;;
  *) echo "FAILED: could not tell whether the demo account exists"; fail=1 ;;
esac

# OpenAM delegates administration through privileges granted to a group: one group in
# the top realm, the accounts as members, RealmAdmin on the group. Every step checks
# first and reads back after. A check that cannot tell fails the phase.
ADMIN_GROUP="${OPENAM_ADMIN_GROUP:-co-op-admins}"
# Members: OPENAM_ADMINS if set (space separated), else every uid in OPENAM_USERS.
admins="${OPENAM_ADMINS:-$(printf '%s' "${OPENAM_USERS:-}" | tr ';' '\n' \
  | sed 's/^[[:space:]]*//' | cut -d, -f1 | grep -E '^[a-z0-9._-]+$' | tr '\n' ' ')}"

case "$(identity_state "$ADMIN_GROUP" Group)" in
  exists) echo "skip: group $ADMIN_GROUP exists" ;;
  absent)
    step "create group $ADMIN_GROUP" adm create-identity -e / -i "$ADMIN_GROUP" -t Group
    [ "$(identity_state "$ADMIN_GROUP" Group)" = exists ] \
      || { echo "FAILED: group $ADMIN_GROUP does not read back after create"; fail=1; } ;;
  *) echo "FAILED: could not tell whether group $ADMIN_GROUP exists"; fail=1 ;;
esac

if [ "$(identity_state "$ADMIN_GROUP" Group)" = exists ]; then
  for u in $admins; do
    [ "$(identity_state "$u")" = exists ] || { echo "FAILED: admin $u is not an account here -- not added"; fail=1; continue; }
    if adm show-members -e / -i "$ADMIN_GROUP" -t Group -m User 2>&1 | grep -q "^$u (id=$u,"; then
      echo "skip: $u already in $ADMIN_GROUP"
    else
      step "add $u to $ADMIN_GROUP" adm add-member -e / -i "$ADMIN_GROUP" -t Group -m "$u" -y User
      adm show-members -e / -i "$ADMIN_GROUP" -t Group -m User 2>&1 | grep -q "^$u (id=$u," \
        || { echo "FAILED: $u is not a member of $ADMIN_GROUP after adding"; fail=1; }
    fi
  done
  if adm show-privileges -e / -i "$ADMIN_GROUP" -t Group 2>&1 | grep -qw RealmAdmin; then
    echo "skip: $ADMIN_GROUP already holds RealmAdmin"
  else
    step "grant RealmAdmin to $ADMIN_GROUP" adm add-privileges -e / -i "$ADMIN_GROUP" -t Group -g RealmAdmin
    adm show-privileges -e / -i "$ADMIN_GROUP" -t Group 2>&1 | grep -qw RealmAdmin \
      || { echo "FAILED: $ADMIN_GROUP does not show RealmAdmin after granting"; fail=1; }
  fi
fi

# force-change-on-reset is set in opendj-prep.sh; the LDAP tools are only in the OpenDJ image.

echo
if [ "$fail" -eq 0 ]; then
  echo "post-install complete."
else
  echo "post-install FINISHED WITH FAILURES -- read the lines above."
fi
exit "$fail"
