#!/usr/bin/env bash
# Standalone smoke: collector is up and accepts OTLP. The full
# trace/log/metric fan-out is exercised in smoke-stack-e2e.sh.
set -euo pipefail
source "$(dirname "$0")/_common.sh"

# Service is `<release>-opentelemetry-collector` (release + chart name).
kubectl -n "$NAMESPACE" port-forward svc/${RELEASE}-opentelemetry-collector 4318:4318 >/tmp/pf.log 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
wait_for_port 4318

# Post a minimal trace. Collector should 200 / 202 regardless of whether
# the downstream Tempo exporter has anywhere to send (it queues internally).
TRACE_ID="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
NOW_NS="$(date +%s)000000000"
NEXT_NS="$(($(date +%s)+1))000000000"
CODE="$(curl -s -o /dev/null -w '%{http_code}' -X POST http://localhost:4318/v1/traces \
  -H 'Content-Type: application/json' \
  -d "{\"resourceSpans\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"ci-probe\"}}]},\"scopeSpans\":[{\"spans\":[{\"traceId\":\"${TRACE_ID}\",\"spanId\":\"bbbbbbbbbbbbbbbb\",\"name\":\"ci-otel-span\",\"kind\":1,\"startTimeUnixNano\":\"${NOW_NS}\",\"endTimeUnixNano\":\"${NEXT_NS}\"}]}]}]}")"
case "$CODE" in
  200|202) echo "otel-collector accepted OTLP trace (HTTP $CODE)" ;;
  *) echo "otel-collector rejected OTLP trace (HTTP $CODE)"; exit 1 ;;
esac
