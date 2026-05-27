#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

kubectl -n "$NAMESPACE" port-forward svc/${RELEASE} 3000:80 >/tmp/pf.log 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
wait_for_port 3000
wait_for_http http://localhost:3000/api/health

# Grafana's health JSON uses spaces around the colon — use a permissive
# pattern instead of `"database":"ok"` (no spaces).
curl -fsS http://localhost:3000/api/health | tee /tmp/health.json
grep -qE '"database"[[:space:]]*:[[:space:]]*"ok"' /tmp/health.json

# Provisioned datasources land regardless of whether their backends are
# up (config-only at this point).
curl -fsS -u admin:change-me http://localhost:3000/api/datasources | tee /tmp/ds.json
grep -q '"name":"Prometheus"' /tmp/ds.json
grep -q '"name":"Loki"'       /tmp/ds.json
grep -q '"name":"Tempo"'      /tmp/ds.json
