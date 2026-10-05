#!/usr/bin/env python3
"""Check the environment of deployed stacks for placeholder values, which
validate.sh cannot see.

Needs PORTAINER_URL, PORTAINER_USER, PORTAINER_PASSWORD. Takes stack names as
arguments, or checks all of them. Credential-shaped values are never echoed.
"""
import json
import os
import sys
import urllib.error
import urllib.request

sys.dont_write_bytecode = True
from placeholders import describe


def api(url, token=None, body=None):
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = "Bearer " + token
    data = None if body is None else json.dumps(body).encode()
    req = urllib.request.Request(url, data=data, headers=headers)
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.load(resp)


def main():
    missing = [v for v in ("PORTAINER_URL", "PORTAINER_USER", "PORTAINER_PASSWORD")
               if not os.environ.get(v)]
    if missing:
        sys.exit("%s not set" % ", ".join(missing))
    base = os.environ["PORTAINER_URL"].rstrip("/")

    try:
        token = api(base + "/api/auth", body={"username": os.environ["PORTAINER_USER"],
                                              "password": os.environ["PORTAINER_PASSWORD"]}).get("jwt")
    except urllib.error.HTTPError:
        token = None
    if not token:
        sys.exit("FAIL: could not authenticate to Portainer")

    wanted = set(sys.argv[1:])
    status = 0
    for stack in api(base + "/api/stacks", token):
        name = stack.get("Name")
        if wanted and name not in wanted:
            continue
        bad = [r for r in (describe(e["name"], e["value"]) for e in stack.get("Env") or []) if r]
        if bad:
            print("FAIL %s: deployed environment contains placeholder values:" % name)
            for r in bad:
                print("       " + r)
            status = 1
        else:
            print("ok   %s" % name)
    sys.exit(status)


if __name__ == "__main__":
    main()
