# agentic-infrastructure

General global infrastructure services for supporting agentic AI frameworks,
workflows, and runtime environments.

Each service ships with two consumption surfaces:

- A **Docker Compose** definition for the fastest possible local dev loop.
- A **Helm chart** that deploys the service to a Kubernetes cluster — for now,
  a local [kind](https://kind.sigs.k8s.io/) cluster on your PC. The cluster
  namespace is **`agentic-ai`**.

> All deployments are currently dev-only. Auth is left off (or set to defaults)
> for ergonomics. Do not point these manifests at a shared cluster as-is.

## Services

| Service     | Purpose                                            | Image                       | Helm chart                                            |
| ----------- | -------------------------------------------------- | --------------------------- | ----------------------------------------------------- |
| SeaweedFS   | S3-compatible object store (all-in-one)            | `chrislusf/seaweedfs:4.29`  | [deploy/helm/seaweedfs/](deploy/helm/seaweedfs/)      |
| Redis       | Key-value + RedisJSON + RediSearch (LangGraph checkpointer) | `redis:latest` (Redis 8)    | [deploy/helm/redis/](deploy/helm/redis/)              |
| Postgres    | Relational store (LangGraph checkpointer, MLflow…) | `postgres:latest`           | [deploy/helm/postgres/](deploy/helm/postgres/)        |
| FalkorDB    | Property-graph database for GraphRAG               | `falkordb/falkordb:latest`  | [deploy/helm/falkordb/](deploy/helm/falkordb/)        |

### Ports

| Host port | Container | What it is             |
| --------- | --------- | ---------------------- |
| 9333      | seaweedfs | SeaweedFS master       |
| 8080      | seaweedfs | SeaweedFS volume       |
| 8888      | seaweedfs | SeaweedFS filer        |
| 8333      | seaweedfs | SeaweedFS S3 gateway   |
| 6379      | redis     | Redis (RESP)           |
| 5432      | postgres  | Postgres               |
| 6380      | falkordb  | FalkorDB (RESP, graph) |
| 3000      | falkordb  | FalkorDB Browser UI    |

### Redis modules and LangGraph

The LangGraph Redis checkpointer requires **RedisJSON** and **RediSearch**.
Redis 8 ships these modules natively in the open-source distribution
(`redis:latest`), so no `redis-stack` image is needed. Verify with
`redis-cli MODULE LIST`.

## Local dev with Docker Compose

The compose services persist state to gitignored bind mounts under the repo
root: `./.seaweedfs/`, `./.redis/`, `./.postgres/`, `./.falkordb/`.

```bash
docker compose up -d                       # start everything
docker compose ps                          # check health
docker compose down                        # stop, keep data
docker compose down && rm -rf .seaweedfs .redis .postgres .falkordb  # full wipe
```

Quick connectivity checks:

```bash
curl -sS http://localhost:8333/                       # SeaweedFS S3
redis-cli -h 127.0.0.1 -p 6379 ping                   # Redis
redis-cli -h 127.0.0.1 -p 6379 MODULE LIST            # confirm JSON + SEARCH
psql "postgres://postgres:password@127.0.0.1:5432/mlflow" -c "SELECT 1"
redis-cli -h 127.0.0.1 -p 6380 GRAPH.LIST             # FalkorDB
# RedisInsight (desktop) → 127.0.0.1:6379 for Redis, 127.0.0.1:6380 for FalkorDB
# FalkorDB Browser     → http://localhost:3000
```

## Local k8s dev with kind + Helm

Prerequisites: [kind](https://kind.sigs.k8s.io/), `kubectl`, and
[Helm](https://helm.sh/) 3.15+.

```bash
# 1. Cluster
kind create cluster --config deploy/kind/kind-config.yaml --name agentic-ai

# 2. Install each service (only run the ones you need)
helm dependency update deploy/helm/seaweedfs
helm install agentic-seaweedfs deploy/helm/seaweedfs -n agentic-ai --create-namespace --wait --timeout 5m
helm install agentic-redis     deploy/helm/redis     -n agentic-ai --create-namespace --wait --timeout 5m
helm install agentic-postgres  deploy/helm/postgres  -n agentic-ai --create-namespace --wait --timeout 5m
helm install agentic-falkordb  deploy/helm/falkordb  -n agentic-ai --create-namespace --wait --timeout 5m

kubectl -n agentic-ai get pods,svc,pvc

# 3. Reach a service from the host (port-forward in a separate terminal each)
kubectl -n agentic-ai port-forward svc/agentic-seaweedfs-all-in-one 8333:8333
kubectl -n agentic-ai port-forward svc/agentic-redis                6379:6379
kubectl -n agentic-ai port-forward svc/agentic-postgres             5432:5432
kubectl -n agentic-ai port-forward svc/agentic-falkordb             6380:6379 3000:3000

# Tear down
helm uninstall agentic-seaweedfs agentic-redis agentic-postgres agentic-falkordb -n agentic-ai
kind delete cluster --name agentic-ai
```

Chart-level READMEs cover per-service options (auth toggles, resource tuning):

- [SeaweedFS](deploy/helm/seaweedfs/README.md)
- [Redis](deploy/helm/redis/README.md)
- [Postgres](deploy/helm/postgres/README.md)
- [FalkorDB](deploy/helm/falkordb/README.md)

## CI

Each service has its own workflow under [.github/workflows/](.github/workflows/),
gated by `paths:` filters on its chart directory:

- [deploy-seaweedfs.yaml](.github/workflows/deploy-seaweedfs.yaml)
- [deploy-redis.yaml](.github/workflows/deploy-redis.yaml)
- [deploy-postgres.yaml](.github/workflows/deploy-postgres.yaml)
- [deploy-falkordb.yaml](.github/workflows/deploy-falkordb.yaml)

Each workflow spins up an **ephemeral kind cluster** inside the GitHub
Actions runner, runs the same `helm install --wait` flow as the local steps
above, and then performs a service-specific smoke test (S3 GET, `redis-cli
ping` + `MODULE LIST`, `pg_isready` + `SELECT 1`, `GRAPH.LIST`). This catches
chart regressions before they reach any real cluster; it does not deploy to
your PC.
