#!/usr/bin/env bash
# Checks the environment of DEPLOYED stacks for placeholder values.
#
# validate.sh can only see what the repo ships. The failure this exists to catch
# happened at deploy time: four stacks were given SMTP_HOST=smtp.invalid in the
# Portainer UI, which satisfies ${SMTP_HOST:?} and guarantees silence. Nothing in
# the repo could see it, and nothing errored -- the stacks reported healthy while
# every account-handover email went nowhere.
#
# Needs PORTAINER_URL, PORTAINER_USER, PORTAINER_PASSWORD. Takes stack names as
# arguments, or checks all of them.
#
# Values are only ever echoed for variables that are not credential-shaped; the
# rest report the reason alone.
set -uo pipefail

cd "$(dirname "$0")/.."

: "${PORTAINER_URL:?PORTAINER_URL not set}"
: "${PORTAINER_USER:?PORTAINER_USER not set}"
: "${PORTAINER_PASSWORD:?PORTAINER_PASSWORD not set}"

jwt=$(PU="$PORTAINER_USER" PP="$PORTAINER_PASSWORD" python3 -c '
import json, os, urllib.request
body = json.dumps({"username": os.environ["PU"], "password": os.environ["PP"]}).encode()
req = urllib.request.Request(os.environ["PORTAINER_URL"] + "/api/auth", data=body,
                             headers={"Content-Type": "application/json"})
print(json.load(urllib.request.urlopen(req, timeout=30)).get("jwt", ""))')

if [ -z "$jwt" ]; then
  echo "FAIL: could not authenticate to Portainer"
  exit 1
fi

stacks_json=$(mktemp)
trap 'rm -f "$stacks_json"' EXIT
curl -sS -H "Authorization: Bearer $jwt" "$PORTAINER_URL/api/stacks" --max-time 60 > "$stacks_json"

status=0
wanted="$*"

while IFS= read -r stack; do
  [ -z "$stack" ] && continue
  env_lines=$(STACK="$stack" python3 -c '
import json, os, sys
for s in json.load(open(sys.argv[1])):
    if s.get("Name") == os.environ["STACK"]:
        for e in s.get("Env") or []:
            print("%s=%s" % (e["name"], e["value"]))
        break' "$stacks_json")

  bad=$(printf '%s\n' "$env_lines" | python3 scripts/placeholders.py)
  if [ -n "$bad" ]; then
    echo "FAIL $stack: deployed environment contains placeholder values:"
    echo "$bad" | sed 's/^/       /'
    status=1
  else
    echo "ok   $stack"
  fi
done < <(WANTED="$wanted" python3 -c '
import json, os, sys
want = os.environ["WANTED"].split()
for s in json.load(open(sys.argv[1])):
    n = s.get("Name")
    if not want or n in want:
        print(n)' "$stacks_json")

exit "$status"
