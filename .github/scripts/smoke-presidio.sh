#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

kubectl -n "$NAMESPACE" port-forward svc/${RELEASE}-analyzer   5001:3000 >/tmp/pf-a.log 2>&1 &
kubectl -n "$NAMESPACE" port-forward svc/${RELEASE}-anonymizer 5002:3000 >/tmp/pf-o.log 2>&1 &
trap 'jobs -p | xargs -r kill 2>/dev/null || true' EXIT
wait_for_port 5001
wait_for_port 5002
wait_for_http http://localhost:5001/health
wait_for_http http://localhost:5002/health

curl -fsS -X POST http://localhost:5001/analyze \
  -H 'Content-Type: application/json' \
  -d '{"text":"My email is alice@example.com and phone is 555-123-4567","language":"en"}' \
  | tee /tmp/analyze.json
grep -q EMAIL_ADDRESS /tmp/analyze.json
grep -q PHONE_NUMBER /tmp/analyze.json

curl -fsS -X POST http://localhost:5002/anonymize \
  -H 'Content-Type: application/json' \
  -d "{\"text\":\"My email is alice@example.com and phone is 555-123-4567\",\"analyzer_results\":$(cat /tmp/analyze.json)}" \
  | tee /tmp/anon.json
! grep -q 'alice@example.com' /tmp/anon.json
! grep -q '555-123-4567'      /tmp/anon.json
