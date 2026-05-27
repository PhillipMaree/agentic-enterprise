#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

# Service is `<release>-obot` (release + chart name).
kubectl -n "$NAMESPACE" port-forward svc/${RELEASE}-obot 8080:8080 >/tmp/pf.log 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
wait_for_port 8080

# 200 = open, 403 = auth required but server up. Both prove the gateway
# is serving HTTP.
wait_for_http http://localhost:8080/api/health '200|401|403'
