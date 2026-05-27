# platform-mlflow

Umbrella chart over `community-charts/mlflow`. Uses the existing
platform-postgres `mlflow` database as the backend store, and SeaweedFS
S3 (`mlflow-artifacts` bucket) for artifacts.

## Prereqs

- `platform-postgres` installed (the `mlflow` database is created by default).
- `platform-seaweedfs` installed and the `mlflow-artifacts` bucket exists.

## Install

```bash
helm dependency update deploy/helm/mlflow
helm install platform-mlflow deploy/helm/mlflow \
  --namespace agentic-platform --create-namespace \
  --wait --timeout 5m
```

## Reach the UI

```bash
kubectl -n agentic-platform port-forward svc/platform-mlflow 5000:5000
# open http://localhost:5000
```

## Uninstall

```bash
helm uninstall platform-mlflow -n agentic-platform
```
