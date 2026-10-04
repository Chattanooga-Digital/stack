#!/usr/bin/env python3
"""Decide whether a configuration value is a placeholder rather than a setting.

`${VAR:?}` only rejects an unset or empty variable, so smtp.invalid passes it.

Used by validate.sh against .env.example and by check-deployed.sh against a live
stack environment.
"""
import re
import sys

# Reserved by RFC 2606 and RFC 6761, so they never resolve.
RESERVED_SUFFIX = re.compile(
    r"(^|[@.])(?:invalid|example|test|localdomain)$"
    r"|(^|[@.])example\.(?:com|net|org)$"
    r"|(^|[@.])localhost$",
    re.I,
)

# Whole-value only, so a password containing "none" is not rejected.
PLACEHOLDER_WORDS = {
    "changeme", "change-me", "change_me", "placeholder", "unused", "unset",
    "todo", "tbd", "xxx", "xxxx", "dummy", "fixme", "notset", "none", "null",
    "your-value", "yourdomain", "yourdomain.com", "replaceme", "secret",
    "password", "admin123", "test", "foo", "bar",
}

TEMPLATE = re.compile(r"<[^>]+>|\{\{[^}]+\}\}")


def reason(value):
    """Return why this value is a placeholder, or None if it looks real."""
    if value is None:
        return None
    v = value.strip()
    if not v:
        return None                      # compose's :? already rejects empty
    if TEMPLATE.search(v):
        return "unfilled template"
    if v.lower() in PLACEHOLDER_WORDS:
        return "placeholder word"
    candidates = [v]
    m = re.match(r"^[a-z][a-z0-9+.-]*://([^/?#]+)", v, re.I)
    if m:
        candidates.append(m.group(1))
    candidates += [p for p in v.split("@") if p]
    for c in candidates:
        host = c.split(":")[0].strip().rstrip(".")
        if RESERVED_SUFFIX.search(host):
            return "reserved/non-resolvable domain"
    return None


if __name__ == "__main__":
    bad = 0
    for line in sys.stdin:
        line = line.rstrip("\n")
        if not line or line.lstrip().startswith("#") or "=" not in line:
            continue
        name, _, value = line.partition("=")
        name = name.strip().lstrip("#").strip()
        why = reason(value)
        if why:
            secretish = any(t in name.upper() for t in
                            ("PASSWORD", "SECRET", "KEY", "TOKEN", "CREDENTIAL"))
            shown = "<withheld>" if secretish else value.strip()
            print("%s=%s (%s)" % (name, shown, why))
            bad += 1
    sys.exit(1 if bad else 0)
