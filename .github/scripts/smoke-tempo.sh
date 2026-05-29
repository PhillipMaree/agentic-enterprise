#!/usr/bin/env bash
# Smoke: push an OTLP trace, then query it back through Tempo's HTTP API.
#
# Port mapping notes:
#   - The grafana/tempo chart exposes the HTTP query API on Service port
#     3100 (NOT Tempo's vanilla 3200 — the chart overrides it).
#   - OTLP HTTP receiver is on 4318.
# `/ready` returns 503 until the first trace is ingested, so we don't
# block on it — TCP-readiness via wait_for_port is enough.

set -euo pipefail
source "$(dirname "$0")/_common.sh"

kubectl -n "$NAMESPACE" port-forward svc/${RELEASE} 3100:3100 4318:4318 >/tmp/pf.log 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
wait_for_port 3100
wait_for_port 4318

TRACE_ID="0123456789abcdef0123456789abcdef"
NOW_NS="$(date +%s)000000000"
NEXT_NS="$(($(date +%s)+1))000000000"

curl -fsS -X POST http://localhost:4318/v1/traces \
  -H 'Content-Type: application/json' \
  -d "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"ci-probe\"}}]},\"scopeSpans\":[{\"spans\":[{\"traceId\":\"${TRACE_ID}\",\"spanId\":\"0123456789abcdef\",\"name\":\"ci-test-span\",\"kind\":1,\"startTimeUnixNano\":\"${NOW_NS}\",\"endTimeUnixNano\":\"${NEXT_NS}\"}]}]}]}"

# Tempo flushes blocks every ~10s; poll for the trace via its HTTP API
# on chart port 3100.
for i in $(seq 1 30); do
  CODE="$(curl -s -o /tmp/trace.json -w '%{http_code}' "http://localhost:3100/api/traces/${TRACE_ID}")"
  if [ "$CODE" = 200 ] && grep -q ci-test-span /tmp/trace.json; then
    echo "trace round-tripped"
    exit 0
  fi
  sleep 2
done
echo "trace never appeared (last HTTP $CODE)"
cat /tmp/trace.json 2>/dev/null | head -c 500 || true
exit 1
