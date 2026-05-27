#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

kubectl -n "$NAMESPACE" port-forward svc/${RELEASE} 5000:5000 >/tmp/pf.log 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
wait_for_port 5000
wait_for_http http://localhost:5000/health

EXP_RESP="$(curl -fsS -X POST http://localhost:5000/api/2.0/mlflow/experiments/create \
  -H 'Content-Type: application/json' -d '{"name":"ci-probe-'"$(date +%s)"'"}')"
EXP_ID="$(echo "$EXP_RESP" | grep -oE '"experiment_id":"[0-9]+"' | grep -oE '[0-9]+')"
[ -n "$EXP_ID" ] || { echo "no experiment_id in $EXP_RESP"; exit 1; }

RUN_RESP="$(curl -fsS -X POST http://localhost:5000/api/2.0/mlflow/runs/create \
  -H 'Content-Type: application/json' \
  -d "{\"experiment_id\":\"${EXP_ID}\",\"start_time\":$(date +%s000)}")"
RUN_ID="$(echo "$RUN_RESP" | grep -oE '"run_id":"[a-f0-9]+"' | grep -oE '[a-f0-9]{32}')"
[ -n "$RUN_ID" ] || { echo "no run_id in $RUN_RESP"; exit 1; }

curl -fsS -X POST http://localhost:5000/api/2.0/mlflow/runs/log-metric \
  -H 'Content-Type: application/json' \
  -d "{\"run_id\":\"${RUN_ID}\",\"key\":\"ci_score\",\"value\":0.99,\"timestamp\":$(date +%s000),\"step\":0}"

curl -fsS "http://localhost:5000/api/2.0/mlflow/runs/get?run_id=${RUN_ID}" | tee /tmp/run.json
grep -q ci_score /tmp/run.json
grep -q 0.99     /tmp/run.json
