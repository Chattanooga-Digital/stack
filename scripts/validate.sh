#!/usr/bin/env bash
# Parses every stack compose file and checks that .env.example lists each
# required variable. Takes stack names as arguments, or validates all of them.
set -uo pipefail

cd "$(dirname "$0")/.."

if [ "$#" -gt 0 ]; then
  targets=("$@")
else
  targets=()
  for dir in stacks/*/; do targets+=("$(basename "$dir")"); done
fi

required_vars() {
  grep -ohE '\$\{[A-Za-z_][A-Za-z0-9_]*:\?' "$1" \
    | sed -E 's/^\$\{([A-Za-z_][A-Za-z0-9_]*):\?$/\1/' \
    | sort -u
}

status=0

for stack in "${targets[@]}"; do
  compose="stacks/$stack/docker-compose.yml"
  example="stacks/$stack/.env.example"

  if [ ! -f "$compose" ]; then
    echo "FAIL $stack: no $compose"
    status=1
    continue
  fi

  # Required vars fail interpolation when unset OR empty, and .env.example
  # ships them empty on purpose, so config runs against generated placeholders.
  placeholders=$(mktemp)
  required_vars "$compose" | sed 's/$/=validate/' > "$placeholders"

  errors=$(docker compose -f "$compose" --env-file "$placeholders" config --quiet 2>&1)
  rm -f "$placeholders"

  if [ -n "$errors" ]; then
    echo "FAIL $stack: $errors"
    status=1
    continue
  fi

  if [ ! -f "$example" ]; then
    echo "FAIL $stack: no .env.example"
    status=1
    continue
  fi

  undocumented=$(required_vars "$compose" | while read -r var; do
    grep -qE "^#? *$var=" "$example" || echo "$var"
  done)

  if [ -n "$undocumented" ]; then
    echo "FAIL $stack: required but missing from .env.example: $(echo "$undocumented" | tr '\n' ' ')"
    status=1
    continue
  fi

  echo "ok   $stack"
done

exit "$status"
