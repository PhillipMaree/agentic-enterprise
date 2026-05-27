#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

kubectl -n "$NAMESPACE" port-forward svc/${RELEASE} 4000:4000 >/tmp/pf.log 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
wait_for_port 4000
wait_for_http http://localhost:4000/health/readiness

curl -fsS http://localhost:4000/health/readiness | tee /tmp/ready.json
grep -q '"healthy"' /tmp/ready.json

# /metrics is public per `require_auth_for_metrics_endpoint: false`.
# Trailing slash because LiteLLM redirects /metrics → /metrics/.
curl -fsSL -o /tmp/metrics.txt http://localhost:4000/metrics
grep -q '^# HELP' /tmp/metrics.txt

# Mock chat completion (CI runs deploy.sh with LITELLM_USE_MOCK_MODELS=1).
MASTER_KEY="$(kubectl -n "$NAMESPACE" get secret platform-litellm-secrets -o jsonpath='{.data.masterkey}' | base64 -d)"
curl -fsS http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer ${MASTER_KEY}" \
  -H 'Content-Type: application/json' \
  -d '{"model":"mock-model","messages":[{"role":"user","content":"hi"}]}' \
  | tee /tmp/chat.json
grep -q '"ok"' /tmp/chat.json
