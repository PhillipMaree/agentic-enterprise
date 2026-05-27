#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

kubectl -n "$NAMESPACE" port-forward svc/${RELEASE}-server 9090:80 >/tmp/pf.log 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
wait_for_port 9090
wait_for_http http://localhost:9090/-/ready

# Self-scrape: up{job=prometheus} should report 1.
for i in $(seq 1 30); do
  RESP="$(curl -fsS 'http://localhost:9090/api/v1/query?query=up%7Bjob%3D%22prometheus%22%7D')"
  if echo "$RESP" | grep -qE '"value":\[[0-9.]+,"1"'; then
    echo "prometheus self-scrape OK"
    exit 0
  fi
  sleep 2
done
echo "prometheus did not self-scrape: $RESP"
exit 1
