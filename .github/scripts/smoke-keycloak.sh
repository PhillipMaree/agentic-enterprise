#!/usr/bin/env bash
# Smoke: confirm Keycloak imported the agentic-dev realm and serves its OIDC
# discovery document. The pod's readiness probe is this same endpoint, so the
# helm --wait already gates on it — here we round-trip it through the API and
# assert the issuer + token endpoint are present.
set -euo pipefail
source "$(dirname "$0")/_common.sh"

kubectl -n "$NAMESPACE" port-forward svc/${RELEASE} 8080:8080 >/tmp/pf.log 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
wait_for_port 8080

OIDC="http://localhost:8080/realms/agentic-dev/.well-known/openid-configuration"
# Keycloak boots then imports the realm — give it generous retries.
wait_for_http "$OIDC" '200' 120

curl -fsS "$OIDC" | tee /tmp/oidc.json
grep -q '"issuer"' /tmp/oidc.json
grep -q 'agentic-dev' /tmp/oidc.json
grep -q '"token_endpoint"' /tmp/oidc.json
echo "agentic-dev realm OIDC discovery OK"
