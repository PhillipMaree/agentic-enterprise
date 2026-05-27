# agentic-platform

End-to-end local development platform for agentic AI: an LLM gateway with
built-in PII masking, an MCP tool federation gateway, experiment tracking,
and a full traces/logs/metrics observability stack — all glued together so
an agentic app needs to know about one ingress (LiteLLM) and one telemetry
egress (OTel Collector) and nothing else.

Two consumption surfaces, both running the same set of services:

- **Docker Compose** — fastest local loop. `docker compose up -d`.
- **Helm charts** — one chart per service, all named `platform-<svc>`,
  installed into the `agentic-platform` namespace of a local
  [kind](https://kind.sigs.k8s.io/) cluster.

> Dev-only. Auth is off or set to defaults. Do not point any of this at a
> shared cluster as-is.

## Architecture

```mermaid
flowchart TB
    subgraph clients [Agentic apps]
        app[Your agent / workflow]
    end

    subgraph data [Data plane]
        direction LR
        litellm[LiteLLM proxy :4000]
        mcp[MCP Gateway :8811]
        presidio_a[Presidio analyzer]
        presidio_o[Presidio anonymizer]
    end

    subgraph tracking [Experiment tracking]
        mlflow[MLflow :5000]
    end

    subgraph telemetry [Telemetry plane]
        direction LR
        otel[OTel Collector :4317/:4318]
        tempo[Tempo - traces]
        loki[Loki - logs]
        prom[Prometheus - metrics]
        grafana[Grafana :3001]
    end

    subgraph infra [Shared infrastructure]
        direction LR
        redis[(Redis :6379)]
        postgres[(Postgres :5432)]
        falkordb[(FalkorDB :6380/:3000)]
        seaweedfs[(SeaweedFS S3 :8333)]
    end

    app -->|chat completions| litellm
    app -->|tool calls| mcp
    app -.->|OTLP| otel

    litellm --> presidio_a
    litellm --> presidio_o
    litellm -->|cache DB1| redis
    litellm -->|usage / keys| postgres
    litellm -.->|OTLP| otel

    mlflow --> postgres
    mlflow -->|artifacts| seaweedfs

    otel --> tempo
    otel --> loki
    otel --> prom

    tempo -->|blocks| seaweedfs
    loki -->|chunks + index| seaweedfs

    grafana --> tempo
    grafana --> loki
    grafana --> prom

    classDef dataplane fill:#e1f5ff,stroke:#0288d1,color:#01579b
    classDef telemetryplane fill:#fff4e1,stroke:#f57c00,color:#e65100
    classDef trackingplane fill:#f0e8ff,stroke:#7e57c2,color:#4527a0
    classDef infraplane fill:#e8f5e9,stroke:#388e3c,color:#1b5e20

    class litellm,mcp,presidio_a,presidio_o dataplane
    class otel,tempo,loki,prom,grafana telemetryplane
    class mlflow trackingplane
    class redis,postgres,falkordb,seaweedfs infraplane
```

**Reading the diagram**

- Solid arrows are request-path (synchronous: PII redaction, cache, DB writes, S3 puts).
- Dotted arrows are OTLP telemetry (asynchronous, fire-and-forget).
- The **agentic app's only required outbound surfaces** are LiteLLM (LLM calls),
  the MCP gateway (tools), and the OTel collector (telemetry). Everything
  else is internal to the platform.
- **SeaweedFS is the S3 backend for everything**: MLflow artifacts, Tempo
  trace blocks, Loki chunks + index. One object store, four buckets.

## Services

| Plane | Service | Purpose | Image | Helm chart |
| --- | --- | --- | --- | --- |
| Infra | SeaweedFS | S3-compatible object store | `chrislusf/seaweedfs:4.29` | [deploy/helm/seaweedfs/](deploy/helm/seaweedfs/) |
| Infra | Redis | KV + JSON + Search (LangGraph checkpointer, LiteLLM cache) | `redis:latest` (Redis 8) | [deploy/helm/redis/](deploy/helm/redis/) |
| Infra | Postgres | Relational store (LiteLLM usage, MLflow, LangGraph) | `postgres:latest` | [deploy/helm/postgres/](deploy/helm/postgres/) |
| Infra | FalkorDB | Property-graph DB (GraphRAG) | `falkordb/falkordb:latest` | [deploy/helm/falkordb/](deploy/helm/falkordb/) |
| Data | LiteLLM | OpenAI-compatible LLM proxy + Presidio PII masking | `ghcr.io/berriai/litellm:main-stable` | [deploy/helm/litellm/](deploy/helm/litellm/) |
| Data | Presidio (analyzer + anonymizer) | PII detection + redaction sidecars for LiteLLM | `mcr.microsoft.com/presidio-{analyzer,anonymizer}` | [deploy/helm/presidio/](deploy/helm/presidio/) |
| Data | MCP Gateway | Federated MCP tool endpoint | `docker/mcp-gateway:latest` | [deploy/helm/mcp-gateway/](deploy/helm/mcp-gateway/) |
| Tracking | MLflow | Experiment + artifact tracking | `ghcr.io/mlflow/mlflow:v2.18.0` | [deploy/helm/mlflow/](deploy/helm/mlflow/) |
| Telemetry | OTel Collector | OTLP fan-out to tempo/loki/prometheus | `otel/opentelemetry-collector-contrib:latest` | [deploy/helm/otel-collector/](deploy/helm/otel-collector/) |
| Telemetry | Tempo | Traces backend (S3) | `grafana/tempo:latest` | [deploy/helm/tempo/](deploy/helm/tempo/) |
| Telemetry | Loki | Logs backend (S3) | `grafana/loki:latest` | [deploy/helm/loki/](deploy/helm/loki/) |
| Telemetry | Prometheus | Metrics (remote-write + scrape) | `prom/prometheus:latest` | [deploy/helm/prometheus/](deploy/helm/prometheus/) |
| Telemetry | Grafana | UI with auto-provisioned datasources | `grafana/grafana:latest` | [deploy/helm/grafana/](deploy/helm/grafana/) |

## Ports (host → container)

| Host | Service | What it is |
| ---: | --- | --- |
| 9333 | seaweedfs | SeaweedFS master |
| 8080 | seaweedfs | SeaweedFS volume |
| 8888 | seaweedfs | SeaweedFS filer |
| 8333 | seaweedfs | SeaweedFS S3 gateway |
| 6379 | redis | Redis (RESP) |
| 5432 | postgres | Postgres |
| 6380 | falkordb | FalkorDB (RESP, graph) |
| 3000 | falkordb | FalkorDB Browser UI |
| 4000 | litellm | LiteLLM proxy + UI |
| 8811 | mcp-gateway | MCP gateway |
| 5000 | mlflow | MLflow UI + API |
| 4317 | otel-collector | OTLP gRPC |
| 4318 | otel-collector | OTLP HTTP |
| 3200 | tempo | Tempo query API |
| 3100 | loki | Loki push + query API |
| 9090 | prometheus | Prometheus UI + remote-write |
| 3001 | grafana | Grafana UI (3000 is taken by falkordb) |

## Config files

| File | Consumed by (Compose) | Consumed by (Helm) | Documents |
| --- | --- | --- | --- |
| [config/otel-collector/config.yaml](config/otel-collector/config.yaml) | volume mount | mirrored in [otel-collector/values.yaml](deploy/helm/otel-collector/values.yaml) | OTLP pipelines and exporter routing |
| [config/tempo/tempo.yaml](config/tempo/tempo.yaml) | volume mount | mirrored in [tempo/values.yaml](deploy/helm/tempo/values.yaml) | S3 backend + retention |
| [config/loki/loki-config.yaml](config/loki/loki-config.yaml) | volume mount | mirrored in [loki/values.yaml](deploy/helm/loki/values.yaml) | TSDB + S3 storage |
| [config/prometheus/prometheus.yml](config/prometheus/prometheus.yml) | volume mount | mirrored in [prometheus/values.yaml](deploy/helm/prometheus/values.yaml) | Scrape targets |
| [config/grafana/provisioning/](config/grafana/provisioning/) | volume mount | mirrored in [grafana/values.yaml](deploy/helm/grafana/values.yaml) | Datasources + dashboards |
| [config/litellm/config.yaml](config/litellm/config.yaml) | volume mount | mirrored in [litellm/values.yaml](deploy/helm/litellm/values.yaml) | Model list + PII callback + cache |
| [config/mcp-gateway/config.yaml](config/mcp-gateway/config.yaml) | volume mount | mirrored in [mcp-gateway/values.yaml](deploy/helm/mcp-gateway/values.yaml) | MCP server list |
| [config/seaweedfs-init/buckets.sh](config/seaweedfs-init/buckets.sh) | run by `seaweedfs-init` service | document only (see below) | One-shot bucket bootstrap |

> **Implication of the dual-config layout.** Configs live in two places by
> design: `config/*` are bind-mounted into Compose containers; the same
> conceptual settings are re-stated as Helm values in each chart's
> `values.yaml`. When you change one, mirror the change in the other. There
> is no auto-sync.

## Required environment variables

Copy [.env.example](.env.example) to `.env` and fill in:

| Var | Where used | Notes |
| --- | --- | --- |
| `LITELLM_MASTER_KEY` | Compose | API key clients send to LiteLLM. `>=32` chars. |
| `LITELLM_UI_USERNAME` / `LITELLM_UI_PASSWORD` | Compose | Admin UI login at `:4000/ui` |
| `GRAFANA_ADMIN_PASSWORD` | Compose | Admin login for Grafana at `:3001` |
| `ANTHROPIC_API_KEY` | Compose + Helm | Upstream provider key (optional) |
| `OPENAI_API_KEY` | Compose + Helm | Upstream provider key (optional) |

For Helm, store these in a Kubernetes Secret instead — see
[deploy/helm/litellm/README.md](deploy/helm/litellm/README.md) and
[deploy/helm/grafana/values.yaml](deploy/helm/grafana/values.yaml).

## Local dev with Docker Compose

The compose services persist state to gitignored bind mounts under the repo
root: `./.seaweedfs/`, `./.redis/`, `./.postgres/`, `./.falkordb/`,
`./.tempo/`, `./.loki/`. Prometheus + Grafana use named volumes.

```bash
cp .env.example .env                       # then edit secrets
docker compose up -d                       # start everything
docker compose ps                          # check health
docker compose logs -f litellm             # tail one service
docker compose down                        # stop, keep data
docker compose down -v && rm -rf .seaweedfs .redis .postgres .falkordb .tempo .loki  # full wipe
```

Startup order is enforced by `depends_on` + healthchecks:

1. `seaweedfs`, `redis`, `postgres`, `falkordb` come up.
2. `seaweedfs-init` creates the S3 buckets, `postgres-init` creates the
   `litellm` database. Both are one-shot.
3. `tempo`, `loki`, `prometheus`, `mlflow` start once their buckets exist.
4. `otel-collector` starts after the backends.
5. `litellm` starts last (depends on postgres-init, redis, presidio, otel).

Quick connectivity checks:

```bash
curl -sS http://localhost:8333/                       # SeaweedFS S3
redis-cli -h 127.0.0.1 -p 6379 ping                   # Redis
psql "postgres://postgres:password@127.0.0.1:5432/mlflow" -c "SELECT 1"
curl -sS http://localhost:4000/health/readiness       # LiteLLM
curl -sS http://localhost:5000/health                 # MLflow
curl -sS http://localhost:3100/ready                  # Loki
curl -sS http://localhost:3200/ready                  # Tempo
curl -sS http://localhost:9090/-/ready                # Prometheus
curl -sS http://localhost:3001/api/health             # Grafana
```

LiteLLM smoke test (after setting `LITELLM_MASTER_KEY` + `ANTHROPIC_API_KEY`):

```bash
curl -sS http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-sonnet-4-6","messages":[{"role":"user","content":"hi"}]}'
```

## Local k8s dev with kind + Helm

Prerequisites: [kind](https://kind.sigs.k8s.io/), `kubectl`,
[Helm](https://helm.sh/) 3.15+, and the [`aws` CLI](https://aws.amazon.com/cli/)
(for the one-time bucket creation).

```bash
# 1. Cluster + namespace
kind create cluster --config deploy/kind/kind-config.yaml --name agentic-platform
kubectl create namespace agentic-platform

# 2. Shared infra
helm dependency update deploy/helm/seaweedfs
helm install platform-seaweedfs deploy/helm/seaweedfs -n agentic-platform --wait --timeout 5m
helm install platform-redis     deploy/helm/redis     -n agentic-platform --wait --timeout 5m
helm install platform-postgres  deploy/helm/postgres  -n agentic-platform --wait --timeout 5m
helm install platform-falkordb  deploy/helm/falkordb  -n agentic-platform --wait --timeout 5m

# 3. One-time bootstrap (buckets + litellm DB)
kubectl -n agentic-platform port-forward svc/platform-seaweedfs-all-in-one 8333:8333 &
PF=$!
AWS_ACCESS_KEY_ID=any AWS_SECRET_ACCESS_KEY=any aws --endpoint-url http://localhost:8333 \
  s3 mb s3://tempo-traces s3://loki-logs s3://mlflow-artifacts s3://prometheus-blocks
kill $PF

kubectl -n agentic-platform exec deploy/platform-postgres -- \
  psql -U postgres -c "CREATE DATABASE litellm"

# 4. Telemetry + tracking
helm dependency update deploy/helm/otel-collector deploy/helm/tempo deploy/helm/loki deploy/helm/prometheus deploy/helm/grafana deploy/helm/mlflow
helm install platform-tempo          deploy/helm/tempo          -n agentic-platform --wait --timeout 5m
helm install platform-loki           deploy/helm/loki           -n agentic-platform --wait --timeout 5m
helm install platform-prometheus     deploy/helm/prometheus     -n agentic-platform --wait --timeout 5m
helm install platform-grafana        deploy/helm/grafana        -n agentic-platform --wait --timeout 5m
helm install platform-otel-collector deploy/helm/otel-collector -n agentic-platform --wait --timeout 5m
helm install platform-mlflow         deploy/helm/mlflow         -n agentic-platform --wait --timeout 5m

# 5. Data plane (presidio first, then litellm + mcp gateway)
helm install platform-presidio    deploy/helm/presidio    -n agentic-platform --wait --timeout 5m
helm install platform-mcp-gateway deploy/helm/mcp-gateway -n agentic-platform --wait --timeout 5m

# 6. LiteLLM needs a secret BEFORE install (master key + provider keys)
kubectl -n agentic-platform create secret generic platform-litellm-secrets \
  --from-literal=masterkey="$(openssl rand -hex 32)" \
  --from-literal=anthropic-api-key="$ANTHROPIC_API_KEY" \
  --from-literal=openai-api-key="$OPENAI_API_KEY"
helm dependency update deploy/helm/litellm
helm install platform-litellm deploy/helm/litellm -n agentic-platform --wait --timeout 5m

kubectl -n agentic-platform get pods,svc,pvc

# 7. Port-forwards (one per service, separate terminals)
kubectl -n agentic-platform port-forward svc/platform-litellm 4000:4000
kubectl -n agentic-platform port-forward svc/platform-grafana 3000:80
kubectl -n agentic-platform port-forward svc/platform-mlflow  5000:5000

# Tear down
helm uninstall -n agentic-platform $(helm list -n agentic-platform -q)
kind delete cluster --name agentic-platform
```

Chart-level READMEs cover per-service options:

**Infra**
- [SeaweedFS](deploy/helm/seaweedfs/README.md)
- [Redis](deploy/helm/redis/README.md)
- [Postgres](deploy/helm/postgres/README.md)
- [FalkorDB](deploy/helm/falkordb/README.md)

**Data**
- [LiteLLM](deploy/helm/litellm/README.md)
- [Presidio](deploy/helm/presidio/README.md)
- [MCP Gateway](deploy/helm/mcp-gateway/README.md)

**Tracking**
- [MLflow](deploy/helm/mlflow/README.md)

**Telemetry**
- [OTel Collector](deploy/helm/otel-collector/README.md)
- [Tempo](deploy/helm/tempo/README.md)
- [Loki](deploy/helm/loki/README.md)
- [Prometheus](deploy/helm/prometheus/README.md)
- [Grafana](deploy/helm/grafana/README.md)

## CI

Each service has its own workflow under [.github/workflows/](.github/workflows/),
gated by `paths:` filters on its chart directory. Each workflow spins up an
**ephemeral kind cluster** inside the GitHub Actions runner, runs `helm install
--wait`, and performs a service-specific smoke test (S3 GET, `redis-cli ping`,
`pg_isready`, `GRAPH.LIST`).

Workflows currently cover the four infra services
([seaweedfs](.github/workflows/deploy-seaweedfs.yaml),
[redis](.github/workflows/deploy-redis.yaml),
[postgres](.github/workflows/deploy-postgres.yaml),
[falkordb](.github/workflows/deploy-falkordb.yaml)). The new platform charts
do not have CI workflows yet — that's the obvious next chunk.
