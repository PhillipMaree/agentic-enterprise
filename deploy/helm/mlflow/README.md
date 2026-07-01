# enterprise-platform-mlflow

Umbrella chart over `community-charts/mlflow`. Uses the existing
enterprise-platform-postgres `mlflow` database as the backend store, and SeaweedFS
S3 (`mlflow-artifacts` bucket) for artifacts.

## Prereqs

- `enterprise-platform-postgres` installed (the `mlflow` database is created by default).
- `enterprise-platform-seaweedfs` installed and the `mlflow-artifacts` bucket exists.

## Install

```bash
helm dependency update deploy/helm/mlflow
helm install enterprise-platform-mlflow deploy/helm/mlflow \
  --namespace enterprise-platform --create-namespace \
  --wait --timeout 5m
```

## Reach the UI

```bash
kubectl -n enterprise-platform port-forward svc/enterprise-platform-mlflow 5000:5000
# open http://localhost:5000
```

## Uninstall

```bash
helm uninstall enterprise-platform-mlflow -n enterprise-platform
```
