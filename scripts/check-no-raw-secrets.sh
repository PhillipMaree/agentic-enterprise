#!/usr/bin/env bash
# check-no-raw-secrets.sh — guard against raw secret material under
# deploy/sealed-secrets/. Only `kind: SealedSecret` manifests belong there;
# raw `kind: Secret`, unsealed dumps, .env files etc. must never be committed.
#
# Usage: scripts/check-no-raw-secrets.sh [dir]   (default: deploy/sealed-secrets)
# Exits non-zero (and prints GH-Actions ::error::) if anything raw is found.
set -euo pipefail

DIR="${1:-deploy/sealed-secrets}"
fail=0

[ -d "$DIR" ] || { echo "OK: $DIR does not exist (nothing to check)."; exit 0; }

# 1) Raw `kind: Secret` manifests. `kind: SealedSecret` is a different kind and
#    is explicitly allowed — the anchored regex below does not match it.
raw="$(grep -rEl '^[[:space:]]*kind:[[:space:]]*Secret[[:space:]]*$' "$DIR" 2>/dev/null || true)"
if [ -n "$raw" ]; then
  echo "::error::raw 'kind: Secret' manifest(s) found — commit only kind: SealedSecret:" >&2
  printf '  %s\n' $raw >&2
  fail=1
fi

# 2) Stray unsealed / raw secret files that should never be committed.
stray="$(find "$DIR" -type f \( \
  -name '*.unsealed.yaml' -o -name '*.unsealed.yml' \
  -o -name '*.secret.yaml' -o -name '*.secret.yml' \
  -o -name '*.env' -o -name '*.key' -o -name '*.pem' \) 2>/dev/null || true)"
if [ -n "$stray" ]; then
  echo "::error::unsealed/raw secret file(s) found under $DIR:" >&2
  printf '  %s\n' $stray >&2
  fail=1
fi

if [ "$fail" -eq 0 ]; then
  echo "OK: no raw secrets under $DIR (kind: SealedSecret only)."
fi
exit "$fail"
