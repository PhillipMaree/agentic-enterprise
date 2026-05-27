#!/usr/bin/env bash
set -euo pipefail

POD="$(kubectl -n "$NAMESPACE" get pod -l app.kubernetes.io/instance="$RELEASE" -o jsonpath='{.items[0].metadata.name}')"
kubectl -n "$NAMESPACE" exec "$POD" -- pg_isready -U postgres
kubectl -n "$NAMESPACE" exec "$POD" -- psql -U postgres -d mlflow -c 'SELECT 1 AS up;'
