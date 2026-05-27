#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

kubectl -n "$NAMESPACE" port-forward svc/${RELEASE} 3200:3200 4318:4318 >/tmp/pf.log 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
wait_for_port 3200
wait_for_port 4318
wait_for_http http://localhost:3200/ready '200|503'

TRACE_ID="0123456789abcdef0123456789abcdef"
NOW_NS="$(date +%s)000000000"
NEXT_NS="$(($(date +%s)+1))000000000"

curl -fsS -X POST http://localhost:4318/v1/traces \
  -H 'Content-Type: application/json' \
  -d "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"ci-probe\"}}]},\"scopeSpans\":[{\"spans\":[{\"traceId\":\"${TRACE_ID}\",\"spanId\":\"0123456789abcdef\",\"name\":\"ci-test-span\",\"kind\":1,\"startTimeUnixNano\":\"${NOW_NS}\",\"endTimeUnixNano\":\"${NEXT_NS}\"}]}]}]}"

# Tempo flushes blocks every ~10s. Poll for the trace.
for i in $(seq 1 30); do
  CODE="$(curl -s -o /tmp/trace.json -w '%{http_code}' "http://localhost:3200/api/traces/${TRACE_ID}")"
  if [ "$CODE" = 200 ] && grep -q ci-test-span /tmp/trace.json; then
    echo "trace round-tripped"
    exit 0
  fi
  sleep 2
done
echo "trace never appeared in Tempo"
cat /tmp/trace.json || true
exit 1
