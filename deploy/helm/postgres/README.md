# platform-postgres

Minimal Helm chart that deploys **Postgres** (`postgres:latest`) into the
`agentic-platform` namespace.

Includes:

- A single-replica `Deployment` (`strategy: Recreate`).
- A `PersistentVolumeClaim` for `/var/lib/postgresql/data` (5 Gi default).
- A `Secret` with `POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`.
- A `ClusterIP` `Service` on port 5432.

> Dev-only. Default credentials are `postgres` / `password` / db `mlflow`.
> Do not install in a shared cluster as-is.

## Install

```bash
helm install platform-postgres deploy/helm/postgres \
  --namespace agentic-platform --create-namespace \
  --wait --timeout 5m
```

## Override the credentials

```bash
helm install platform-postgres deploy/helm/postgres \
  --namespace agentic-platform --create-namespace \
  --set auth.username=myuser \
  --set auth.password=$(openssl rand -base64 24) \
  --set auth.database=mydb \
  --wait --timeout 5m
```

## Reach the service

```bash
kubectl -n agentic-platform port-forward svc/platform-postgres 5432:5432
psql "postgres://postgres:password@127.0.0.1:5432/mlflow" -c "SELECT version();"
```

## Uninstall

```bash
helm uninstall platform-postgres -n agentic-platform
kubectl delete pvc platform-postgres -n agentic-platform
```
