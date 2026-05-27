#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

kubectl -n "$NAMESPACE" port-forward svc/${RELEASE} 3100:3100 >/tmp/pf.log 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
wait_for_port 3100
wait_for_http http://localhost:3100/ready '200|503'

NS_NANO=$(($(date +%s) * 1000000000))
curl -fsS -X POST http://localhost:3100/loki/api/v1/push \
  -H 'Content-Type: application/json' \
  -d "{\"streams\":[{\"stream\":{\"app\":\"ci-probe\"},\"values\":[[\"${NS_NANO}\",\"hello from ci\"]]}]}"

for i in $(seq 1 30); do
  RESP="$(curl -fsS --get \
    --data-urlencode 'query={app="ci-probe"}' \
    --data-urlencode "start=$((NS_NANO - 60000000000))" \
    --data-urlencode "end=$((NS_NANO + 60000000000))" \
    http://localhost:3100/loki/api/v1/query_range)"
  echo "$RESP" | grep -q 'hello from ci' && { echo "log round-tripped"; exit 0; }
  sleep 2
done
echo "log never appeared in Loki"
exit 1
