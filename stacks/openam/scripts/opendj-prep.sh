#!/bin/sh
# Prepares the OpenDJ user store before the OpenAM configurator runs.
#
# Base entry: this image advertises the suffix without creating it, and the
# configurator reports "Invalid Suffix".
# Schema: an external user store needs OpenAM's schema, or the configurator fails on
# its last step with a bare "error code :500" (unknown objectclass, in debug/IdRepo).
#
# The LDIF files are in the OpenAM image's WAR and the LDAP tools in this one, so the
# files are vendored in ../schema/ and mounted as Swarm configs.
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

if /opt/opendj/bin/ldapsearch -h opendj -p 1389 -D "cn=Directory Manager" -j "$PW" \
     -b "$BASE_DN" -s base "(objectClass=*)" dn >/dev/null 2>&1; then
  echo "skip: base entry exists"
else
  printf 'dn: %s\nobjectClass: top\nobjectClass: domain\ndc: %s\n' "$BASE_DN" "$DC" > /tmp/base.ldif
  step "create the base entry" /opt/opendj/bin/ldapmodify -a -h opendj -p 1389 \
    -D "cn=Directory Manager" -j "$PW" -f /tmp/base.ldif
fi

# A line starting with one space continues the previous one (RFC 2849).
unfold() { awk '/^ / && NR > 1 { buf = buf substr($0, 2); next }
                NR > 1 { print buf }
                { buf = $0 }
                END { if (NR) print buf }'; }

# The configurator writes its demo user into ou=people and never creates it, then
# fails with a bare "error code :500". OpenAM's opendj_userinit.ldif creates
# ou=people and ou=groups plus an ACI that denies users write access to their own
# status attributes; hand-written OUs would drop the ACI.
# -c carries on past "already exists", so the end state is checked, not the exit status.
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

# The schema is vendored per OpenAM version and mounted under /schema. Fail rather
# than load one version's schema under another's OpenAM.
: "${OPENAM_VERSION:?OPENAM_VERSION not set}"
have=$(tr -d '[:space:]' < /schema/VERSION 2>/dev/null)
if [ "$have" != "$OPENAM_VERSION" ]; then
  echo "FAILED: vendored schema is for OpenAM '${have:-missing}', OPENAM_VERSION is '$OPENAM_VERSION'."
  echo "        Re-extract stacks/openam/schema/ from the new image -- see ../README.md."
  exit 1
fi
echo "ok: vendored schema matches OPENAM_VERSION ($have)"

# Each file is one modify on cn=schema, applied atomically: if any value already
# exists the whole modify fails with "20 (Attribute or Value Exists)". A file cannot
# be re-sent, and a release that adds one definition to an existing file would be
# blocked. Compare definitions to the live schema by OID, send only the missing ones,
# then read back and require every OID. A definition changed under an existing OID is
# not reconciled.
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

# Forces a change on every password an administrator sets. OpenAM then demands a
# second change after a self-service reset: it sets that password by binding as the
# administrator, and the directory cannot tell that from an admin reset.
#
# ldapmodify on cn=config instead of dsconfig, which checks the version of a local
# installation (config/buildinfo) that this container does not have.
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
