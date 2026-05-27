#!/usr/bin/env bash
# Full-stack chain test: drive a request through LiteLLM (mock model so
# no provider call), then verify metrics show up in Prometheus.
set -euo pipefail
source "$(dirname "$0")/_common.sh"

kubectl -n "$NAMESPACE" port-forward svc/platform-litellm           4000:4000 >/tmp/pf-litellm.log 2>&1 &
kubectl -n "$NAMESPACE" port-forward svc/platform-prometheus-server 9090:80   >/tmp/pf-prom.log 2>&1 &
trap 'jobs -p | xargs -r kill 2>/dev/null || true' EXIT
wait_for_port 4000
wait_for_port 9090
wait_for_http http://localhost:4000/health/readiness
wait_for_http http://localhost:9090/-/ready

MASTER_KEY="$(kubectl -n "$NAMESPACE" get secret platform-litellm-secrets -o jsonpath='{.data.masterkey}' | base64 -d)"

# Fire a few mock-model requests so Prometheus has scrape samples.
for i in 1 2 3; do
  curl -fsS http://localhost:4000/v1/chat/completions \
    -H "Authorization: Bearer ${MASTER_KEY}" \
    -H 'Content-Type: application/json' \
    -d '{"model":"mock-model","messages":[{"role":"user","content":"hi"}]}' \
    | tee /tmp/chat-$i.json
  grep -q '"ok"' /tmp/chat-$i.json
done

# Verify LiteLLM metrics reached Prometheus.
for i in $(seq 1 30); do
  RESP="$(curl -fsS 'http://localhost:9090/api/v1/query?query=%7B__name__%3D~%22litellm_.%2B%22%7D')"
  echo "$RESP" | grep -q '"result":\[{' && { echo "litellm metrics in Prometheus"; exit 0; }
  sleep 3
done
echo "no litellm_* metrics in Prometheus"
exit 1
