#!/usr/bin/env bash
# Smoke: the Sealed Secrets controller is up in kube-system and the committed
# SealedSecrets decrypt into the Secrets the stack charts consume.
set -euo pipefail
source "$(dirname "$0")/_common.sh"

NAMESPACE="${NAMESPACE:-enterprise-platform}"
SECRETS=(enterprise-platform-postgres enterprise-platform-keycloak-admin enterprise-platform-grafana-admin enterprise-platform-litellm-secrets enterprise-platform-s3-creds)

echo "=== controller Ready in kube-system ==="
kubectl -n kube-system rollout status deploy/sealed-secrets-controller --timeout=120s

echo "=== committed SealedSecrets present ==="
kubectl -n "$NAMESPACE" get sealedsecret "${SECRETS[@]}"

echo "=== decryption proof: derived Secrets exist ==="
for s in "${SECRETS[@]}"; do
  kubectl -n "$NAMESPACE" get secret "$s" >/dev/null
  echo "  ok: $s"
done

# Spot-check a value round-trips to its expected dev default.
PW="$(kubectl -n "$NAMESPACE" get secret enterprise-platform-postgres -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d)"
[ "$PW" = "password" ] || { echo "enterprise-platform-postgres POSTGRES_PASSWORD did not decrypt as expected" >&2; exit 1; }
echo "decryption verified (enterprise-platform-postgres POSTGRES_PASSWORD)"
