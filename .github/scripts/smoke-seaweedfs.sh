#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/_common.sh"

kubectl -n "$NAMESPACE" port-forward svc/enterprise-platform-seaweedfs-all-in-one 8333:8333 >/tmp/pf.log 2>&1 &
PF=$!
trap 'kill $PF 2>/dev/null || true' EXIT
wait_for_port 8333

# 2xx/3xx/4xx all prove the gateway is alive (we don't auth).
wait_for_http http://localhost:8333/ '2..|3..|4..'
