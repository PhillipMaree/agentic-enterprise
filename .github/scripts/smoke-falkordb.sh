#!/usr/bin/env bash
set -euo pipefail

POD="$(kubectl -n "$NAMESPACE" get pod -l app.kubernetes.io/instance="$RELEASE" -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "$NAMESPACE" exec "$POD" -- redis-cli ping | tee /tmp/ping
grep -q PONG /tmp/ping

kubectl -n "$NAMESPACE" exec "$POD" -- redis-cli MODULE LIST | tee /tmp/modules
grep -qi graph /tmp/modules || { echo "Graph module missing"; exit 1; }

kubectl -n "$NAMESPACE" exec "$POD" -- redis-cli GRAPH.QUERY smoke "CREATE (:T {n:1}) RETURN 1"
kubectl -n "$NAMESPACE" exec "$POD" -- redis-cli GRAPH.LIST
