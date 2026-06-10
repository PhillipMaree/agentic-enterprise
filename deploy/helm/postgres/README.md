# agentic-enterprise-postgres

Minimal Helm chart that deploys **Postgres** (`postgres:latest`) into the
`agentic-enterprise` namespace.

Includes:

- A single-replica `Deployment` (`strategy: Recreate`).
- A `PersistentVolumeClaim` for `/var/lib/postgresql/data` (5 Gi default).
- A `Secret` with `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`.
- A `ClusterIP` `Service` on port 5432.

> Dev-only. Default credentials are `postgres` / `password` / db `mlflow`.
> Do not install in a shared cluster as-is.

## Install

```bash
helm install agentic-enterprise-postgres deploy/helm/postgres \
  --namespace agentic-enterprise --create-namespace \
  --wait --timeout 5m
```

## Override the credentials

```bash
helm install agentic-enterprise-postgres deploy/helm/postgres \
  --namespace agentic-enterprise --create-namespace \
  --set auth.username=myuser \
  --set auth.password=$(openssl rand -base64 24) \
  --set auth.database=mydb \
  --wait --timeout 5m
```

## Reach the service

```bash
kubectl -n agentic-enterprise port-forward svc/agentic-enterprise-postgres 5432:5432
psql "postgres://postgres:password@127.0.0.1:5432/mlflow" -c "SELECT version();"
```

## Uninstall

```bash
helm uninstall agentic-enterprise-postgres -n agentic-enterprise
kubectl delete pvc agentic-enterprise-postgres -n agentic-enterprise
```
