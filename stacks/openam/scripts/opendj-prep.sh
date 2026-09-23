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
trap 'rm -f "$PW" /tmp/step.out /tmp/policy.ldif /tmp/base.ldif /tmp/userinit.ldif' EXIT

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

# LDIF folds long lines: a line starting with ONE space continues the previous one
# (RFC 2849), joined with no separator.
unfold() { awk '/^ / && NR > 1 { buf = buf substr($0, 2); next }
                NR > 1 { print buf }
                { buf = $0 }
                END { if (NR) print buf }'; }
# ---- Trap 1b: ou=people, ou=groups, and the self-modification deny ACI
# The configurator writes its demo user into ou=people and never creates it: without
# it, it runs to "Creating demo user" and fails with a bare "error code :500" (only
# debug/IdRepo says the parent entry does not exist). OpenAM ships the fix as
# opendj_userinit.ldif -- both containers PLUS an ACI on the suffix denying users
# write access to their own inetuserstatus, ds-pwp-account-disabled, memberof and
# the rest. The 09-18 directory has all three. 803a7b1 hand-wrote the two OUs
# instead and so dropped the ACI, which ../README.md (Trap 2) had warned against.
# Now: the vendor's file, token substituted, and the END STATE checked -- -c lets a
# re-run carry on past "already exists", so the exit status cannot be the test.
UI=/schema/opendj_userinit.ldif
if [ ! -f "$UI" ]; then
  echo "MISSING: $UI (config not mounted?)"; fail=1
else
  sed "s/@userStoreRootSuffix@/$BASE_DN/g" "$UI" > /tmp/userinit.ldif
  /opt/opendj/bin/ldapmodify -a -c -h opendj -p 1389 -D "cn=Directory Manager" -j "$PW" \
    -f /tmp/userinit.ldif >/tmp/step.out 2>&1 || true
  for ou in people groups; do
    if /opt/opendj/bin/ldapsearch -h opendj -p 1389 -D "cn=Directory Manager" -j "$PW" \
         -b "ou=$ou,$BASE_DN" -s base "(objectClass=*)" dn >/dev/null 2>&1; then
      echo "ok: ou=$ou present"
    else
      echo "FAILED: ou=$ou absent after applying opendj_userinit.ldif"
      sed 's/^/    /' /tmp/step.out | tail -8; fail=1
    fi
  done
  if /opt/opendj/bin/ldapsearch -h opendj -p 1389 -D "cn=Directory Manager" -j "$PW" \
       -b "$BASE_DN" -s base "(objectClass=*)" aci 2>/dev/null | unfold \
       | grep -q 'OpenAM User self modification denied for these attributes'; then
    echo "ok: self-modification deny ACI present on $BASE_DN"
  else
    echo "FAILED: self-modification deny ACI missing on $BASE_DN"
    sed 's/^/    /' /tmp/step.out | tail -8; fail=1
  fi
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

# ---- Trap 2: OpenAM's user schema, RECONCILED per definition
# Each file is ONE modify on cn=schema adding many definitions, and the server
# applies it atomically: if any single value already exists the whole modify is
# refused with "20 (Attribute or Value Exists)". So re-sending a file can never
# work on a directory that has it -- which is every deploy after the first -- and
# it would also block a later OpenAM version that adds ONE new definition to a
# file whose others are present. (Until 2026-09-23 this matched "already exists",
# a message OpenDJ never prints; the second rebuild failed every file on it.)
#
# So: unfold the LDIF, compare each definition to the live schema BY OID, send only
# the missing ones, then read back and require every OID present. A definition
# CHANGED under an existing OID is not reconciled -- that needs the exact old value
# deleted -- and is not something any OpenAM release so far has done.
#
# "at:<oid>" / "oc:<oid>" for every definition line on stdin (already unfolded).
oids() { awk '{ k = tolower(substr($0, 1, index($0, ":") - 1))
                if (k == "attributetypes") t = "at"; else if (k == "objectclasses") t = "oc"; else next
                v = substr($0, index($0, ":") + 1); sub(/^[ ]*\([ ]*/, "", v); split(v, a, " ")
                print t ":" tolower(a[1]) }' | sort -u; }
live_oids() {
  /opt/opendj/bin/ldapsearch -h opendj -p 1389 -D "cn=Directory Manager" -j "$PW" \
    -b cn=schema -s base "(objectClass=*)" attributeTypes objectClasses 2>/dev/null | unfold | oids
}
# Writes to stdout an LDIF adding only the definitions of file $1 whose OID is not
# listed in file $2; nothing at all if none are missing.
missing_ldif() {
  unfold < "$1" | awk -v have="$2" '
    BEGIN { while ((getline l < have) > 0) present[l] = 1 }
    { k = tolower(substr($0, 1, index($0, ":") - 1))
      if (k == "attributetypes") t = "at"; else if (k == "objectclasses") t = "oc"; else next
      v = substr($0, index($0, ":") + 1); sub(/^[ ]*\([ ]*/, "", v); split(v, a, " ")
      if ((t ":" tolower(a[1])) in present) next
      val = substr($0, index($0, ":") + 1); sub(/^[ ]*/, "", val)
      if (t == "at") at = at "attributeTypes: " val "\n"; else oc = oc "objectClasses: " val "\n" }
    END { if (at == "" && oc == "") exit
          printf "dn: cn=schema\nchangetype: modify\n"
          if (at != "") printf "add: attributeTypes\n%s-\n", at   # types first: classes use them
          if (oc != "") printf "add: objectClasses\n%s-\n", oc }'
}

HAVE=$(mktemp); WANT=$(mktemp); ADD=$(mktemp)
for f in opendj_user_schema.ldif opendj_dashboard.ldif opendj_deviceprint.ldif \
         opendj_kba.ldif opendj_oathdevices.ldif opendj_pushdevices.ldif; do
  if [ ! -f "/schema/$f" ]; then echo "MISSING: /schema/$f (config not mounted?)"; fail=1; continue; fi
  unfold < "/schema/$f" | oids > "$WANT"
  total=$(wc -l < "$WANT")
  if ! live_oids > "$HAVE" || [ ! -s "$HAVE" ]; then
    echo "FAILED: schema $f -- could not read the live schema, so cannot tell what is missing"
    fail=1; continue
  fi
  missing_ldif "/schema/$f" "$HAVE" > "$ADD"
  if [ ! -s "$ADD" ]; then
    echo "ok: schema $f (all $total definitions present)"; continue
  fi
  need=$(comm -23 "$WANT" "$HAVE" | wc -l)
  if ! /opt/opendj/bin/ldapmodify -h opendj -p 1389 -D "cn=Directory Manager" -j "$PW" \
         -f "$ADD" >/tmp/step.out 2>&1; then
    echo "FAILED: schema $f (adding $need of $total)"; sed 's/^/    /' /tmp/step.out | tail -8; fail=1; continue
  fi
  live_oids > "$HAVE"
  still=$(comm -23 "$WANT" "$HAVE" | wc -l)
  if [ "$still" -eq 0 ]; then echo "ok: schema $f (added $need of $total, all now present)"
  else echo "FAILED: schema $f -- $still of $total definitions still absent after the add"; fail=1; fi
done
rm -f "$HAVE" "$WANT" "$ADD"

# ---- force a change on a password WE set
# Also causes OpenAM to demand a SECOND change after a self-service reset, because
# OpenAM sets that password by binding as the administrator and the directory
# cannot tell that apart from a real admin reset. Keycloak and Zitadel can. That
# is a finding about OpenAM, not a misconfiguration; see ../README.md.
#
# ldapmodify on cn=config, NOT dsconfig. dsconfig is only an LDAP client that sends
# this same modify to cn=config, and the server validates it the same way -- but it
# first checks the version of a LOCAL installation, and this container has none:
# run.sh never ran here, so there is no instance.loc and no config/buildinfo.
# Measured on the first fresh 16.1.3 rebuild: "The version of the installed OpenDJ
# could not be determined because the version file '/opt/opendj/config/buildinfo'
# could not be found". It had never run on a fresh stack before; 09-18 did it by hand.
POLICY="cn=Default Password Policy,cn=Password Policies,cn=config"
printf 'dn: %s\nchangetype: modify\nreplace: ds-cfg-force-change-on-reset\nds-cfg-force-change-on-reset: true\n' \
  "$POLICY" > /tmp/policy.ldif
step "force-change-on-reset" /opt/opendj/bin/ldapmodify -h opendj -p 1389 \
  -D "cn=Directory Manager" -j "$PW" -f /tmp/policy.ldif
# Read it back: a modify that "succeeds" against the wrong entry changes nothing.
got=$(/opt/opendj/bin/ldapsearch -h opendj -p 1389 -D "cn=Directory Manager" -j "$PW" \
        -b "$POLICY" -s base "(objectClass=*)" ds-cfg-force-change-on-reset 2>/dev/null \
      | sed -n 's/^ds-cfg-force-change-on-reset: //p')
if [ "$got" = "true" ]; then echo "ok: force-change-on-reset reads back true"
else echo "FAILED: force-change-on-reset reads back '${got:-nothing}'"; fail=1; fi

echo
if [ "$fail" -eq 0 ]; then
  touch /ldif/.prep-done       # post-install waits on this; only written on success
  echo "opendj prep complete."
else
  echo "opendj prep FINISHED WITH FAILURES -- post-install will not start."
fi
exit "$fail"
