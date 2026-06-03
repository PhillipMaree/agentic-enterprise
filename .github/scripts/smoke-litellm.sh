#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

# The litellm Deployment and its Prisma `*-migrations` Job share the same
# app.kubernetes.io/{name,instance} labels, so `port-forward deploy/...`
# (like svc/...) can resolve to the short-lived migrations pod — which never
# listens on 4000, so every request returns 000 until we time out. Pick the
# proxy pod explicitly: only ReplicaSet-managed pods carry pod-template-hash;
# the Job pod does not. Wait for the rollout first so exactly one is Running.
kubectl -n "$NAMESPACE" rollout status deploy/${RELEASE} --timeout=180s
POD="$(kubectl -n "$NAMESPACE" get pod \
  -l "app.kubernetes.io/instance=${RELEASE},pod-template-hash" \
  --field-selector=status.phase=Running \
  -o jsonpath='{.items[0].metadata.name}')"
[ -n "$POD" ] || { echo "no Running proxy pod for ${RELEASE}" >&2; exit 1; }
echo "port-forwarding pod/${POD}"
kubectl -n "$NAMESPACE" port-forward "pod/${POD}" 4000:4000 >/tmp/pf.log 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
wait_for_port 4000
wait_for_http http://localhost:4000/health/readiness || { cat /tmp/pf.log >&2; exit 1; }

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
