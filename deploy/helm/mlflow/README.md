# agentic-enterprise-mlflow

Umbrella chart over `community-charts/mlflow`. Uses the existing
agentic-enterprise-postgres `mlflow` database as the backend store, and SeaweedFS
S3 (`mlflow-artifacts` bucket) for artifacts.

## Prereqs

- `agentic-enterprise-postgres` installed (the `mlflow` database is created by default).
- `agentic-enterprise-seaweedfs` installed and the `mlflow-artifacts` bucket exists.

## Install

```bash
helm dependency update deploy/helm/mlflow
helm install agentic-enterprise-mlflow deploy/helm/mlflow \
  --namespace agentic-enterprise --create-namespace \
  --wait --timeout 5m
```

## Reach the UI

```bash
kubectl -n agentic-enterprise port-forward svc/agentic-enterprise-mlflow 5000:5000
# open http://localhost:5000
```

## Uninstall

```bash
helm uninstall agentic-enterprise-mlflow -n agentic-enterprise
```
