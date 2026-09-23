#!/bin/sh
# Everything the OpenDJ user store needs BEFORE the OpenAM configurator will run.
#
# Both of these are documented in ../README.md as Trap 1 and Trap 2, and both
# were done by hand on 2026-09-18, which is why a rebuild would not have
# reproduced the instance Rob and William evaluated.
#
# Trap 1: this OpenDJ image advertises the suffix as a naming context but never
#         creates the base entry. The configurator calls that "Invalid Suffix".
# Trap 2: an external user store needs OpenAM's own schema loaded into it, or the
#         configurator runs to its LAST step and fails with a bare "error code :500";
#         the real message is an unknown objectclass, in a debug log nobody reads.
#
# The LDIF files live in the OpenAM image (inside its WAR), the LDAP tools live in
# this one. They are vendored in ../schema/ and mounted here as Swarm configs.
set -u
: "${DIRECTORY_PASSWORD:?DIRECTORY_PASSWORD not set}"
: "${BASE_DN:=dc=openam,dc=example,dc=org}"
DC=$(echo "$BASE_DN" | sed 's/^dc=//; s/,.*//')
PW=$(mktemp); printf '%s' "$DIRECTORY_PASSWORD" > "$PW"; chmod 0400 "$PW"
trap 'rm -f "$PW" /tmp/step.out' EXIT

fail=0
step() {
  label="$1"; shift
  if "$@" >/tmp/step.out 2>&1; then echo "ok: $label"
  else echo "FAILED (exit $?): $label"; sed 's/^/    /' /tmp/step.out | tail -12; fail=1; fi
}

echo "waiting for OpenDJ ..."
i=0
while [ "$i" -lt 60 ]; do
  /opt/opendj/bin/ldapsearch -h opendj -p 1389 -D "cn=Directory Manager" -j "$PW" \
    -b "" -s base "(objectClass=*)" 1.1 >/dev/null 2>&1 && break
  i=$((i+1)); sleep 5
done
[ "$i" -ge 60 ] && { echo "FAILED: OpenDJ never answered"; exit 1; }
echo "ok: OpenDJ is answering"

# ---- Trap 1: the base entry
if /opt/opendj/bin/ldapsearch -h opendj -p 1389 -D "cn=Directory Manager" -j "$PW" \
     -b "$BASE_DN" -s base "(objectClass=*)" dn >/dev/null 2>&1; then
  echo "skip: base entry exists"
else
  printf 'dn: %s\nobjectClass: top\nobjectClass: domain\ndc: %s\n' "$BASE_DN" "$DC" > /tmp/base.ldif
  step "create the base entry" /opt/opendj/bin/ldapmodify -a -h opendj -p 1389 \
    -D "cn=Directory Manager" -j "$PW" -f /tmp/base.ldif
fi

# The schema is vendored per OpenAM version and arrives as Swarm configs under
# /schema. Loading one version's schema under another's OpenAM is the drift this
# stops: fail loudly, with the fix, rather than half-work.
: "${OPENAM_VERSION:?OPENAM_VERSION not set}"
have=$(tr -d '[:space:]' < /schema/VERSION 2>/dev/null)
if [ "$have" != "$OPENAM_VERSION" ]; then
  echo "FAILED: vendored schema is for OpenAM '${have:-missing}', OPENAM_VERSION is '$OPENAM_VERSION'."
  echo "        Re-extract stacks/openam/schema/ from the new image -- see ../README.md."
  exit 1
fi
echo "ok: vendored schema matches OPENAM_VERSION ($have)"

# ---- Trap 2: OpenAM's user schema
# Applied every run: ldapmodify on an already-present schema element is a no-op
# that reports attributeType/objectClass already exists, which is not a failure
# worth stopping for -- so these are reported individually rather than gated.
for f in opendj_user_schema.ldif opendj_dashboard.ldif opendj_deviceprint.ldif \
         opendj_kba.ldif opendj_oathdevices.ldif opendj_pushdevices.ldif; do
  if [ ! -f "/schema/$f" ]; then echo "MISSING: /schema/$f (config not mounted?)"; fail=1; continue; fi
  if /opt/opendj/bin/ldapmodify -h opendj -p 1389 -D "cn=Directory Manager" -j "$PW" \
       -f "/schema/$f" >/tmp/step.out 2>&1; then
    echo "ok: schema $f"
  elif grep -qi 'already exists\|attribute type with name' /tmp/step.out; then
    echo "ok: schema $f (already present)"
  else
    echo "FAILED: schema $f"; sed 's/^/    /' /tmp/step.out | tail -8; fail=1
  fi
done

# ---- force a change on a password WE set
# Also causes OpenAM to demand a SECOND change after a self-service reset, because
# OpenAM sets that password by binding as the administrator and the directory
# cannot tell that apart from a real admin reset. Keycloak and Zitadel can. That
# is a finding about OpenAM, not a misconfiguration; see ../README.md.
step "force-change-on-reset" /opt/opendj/bin/dsconfig set-password-policy-prop \
  --hostname opendj --port 4444 --bindDN "cn=Directory Manager" --bindPasswordFile "$PW" \
  --trustAll --no-prompt --policy-name "Default Password Policy" --set force-change-on-reset:true

echo
if [ "$fail" -eq 0 ]; then
  touch /ldif/.prep-done       # post-install waits on this; only written on success
  echo "opendj prep complete."
else
  echo "opendj prep FINISHED WITH FAILURES -- post-install will not start."
fi
exit "$fail"
