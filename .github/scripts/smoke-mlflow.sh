#!/usr/bin/env bash
# Smoke: create an experiment, start a run, log a metric, read it back.
# MLflow returns pretty-printed JSON ("key": value with spaces), so we
# parse it with python instead of grep.

set -euo pipefail
source "$(dirname "$0")/_common.sh"

kubectl -n "$NAMESPACE" port-forward svc/${RELEASE} 5000:5000 >/tmp/pf.log 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
wait_for_port 5000
wait_for_http http://localhost:5000/health

# Use a unique name so re-runs against the same cluster don't clash.
EXP_NAME="ci-probe-$(date +%s)-$$"
EXP_RESP="$(curl -fsS -X POST http://localhost:5000/api/2.0/mlflow/experiments/create \
  -H 'Content-Type: application/json' -d "{\"name\":\"${EXP_NAME}\"}")"
echo "$EXP_RESP"
EXP_ID="$(echo "$EXP_RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin)["experiment_id"])')"
[ -n "$EXP_ID" ] || { echo "no experiment_id"; exit 1; }

RUN_RESP="$(curl -fsS -X POST http://localhost:5000/api/2.0/mlflow/runs/create \
  -H 'Content-Type: application/json' \
  -d "{\"experiment_id\":\"${EXP_ID}\",\"start_time\":$(date +%s000)}")"
echo "$RUN_RESP"
RUN_ID="$(echo "$RUN_RESP" | python3 -c 'import json,sys; print(json.load(sys.stdin)["run"]["info"]["run_id"])')"
[ -n "$RUN_ID" ] || { echo "no run_id"; exit 1; }

curl -fsS -X POST http://localhost:5000/api/2.0/mlflow/runs/log-metric \
  -H 'Content-Type: application/json' \
  -d "{\"run_id\":\"${RUN_ID}\",\"key\":\"ci_score\",\"value\":0.99,\"timestamp\":$(date +%s000),\"step\":0}"

curl -fsS "http://localhost:5000/api/2.0/mlflow/runs/get?run_id=${RUN_ID}" | tee /tmp/run.json
grep -q ci_score /tmp/run.json
grep -q 0.99     /tmp/run.json
