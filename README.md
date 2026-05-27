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

![agentic-platform architecture](docs/img/architecture.png)

<details>
<summary>Mermaid source (re-render with <code>mmdc -i README.md -o docs/img/architecture.png</code> or view via the GitHub renderer)</summary>

```mermaid
flowchart TB
    subgraph clients [Agentic apps]
        app[Your agent / workflow]
    end

    subgraph data [Data plane]
        direction LR
        litellm[LiteLLM proxy :4000]
        mcp[Obot MCP Gateway :8090]
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

</details>

**Reading the diagram**

- Solid arrows are request-path (synchronous: PII redaction, cache, DB writes, S3 puts).
- Dotted arrows are OTLP telemetry (asynchronous, fire-and-forget).
- The **agentic app's only required outbound surfaces** are LiteLLM (LLM calls),
  the MCP gateway (tools), and the OTel collector (telemetry). Everything
  else is internal to the platform.
- **SeaweedFS is the S3 backend for everything**: MLflow artifacts, Tempo
  trace blocks, Loki chunks + index. One object store, four buckets.

## Getting Started

Two ways to run the stack locally. Pick one. Both end with the same set of
services reachable on `localhost`, with the same credentials.

### Prerequisites

| Tool | Compose path | Kubernetes path |
|---|---|---|
| Docker Engine 25+ | required | required (kind runs in Docker) |
| Docker Compose v2 | required | — |
| [kind](https://kind.sigs.k8s.io/) | — | required |
| `kubectl` | — | required |
| [Helm](https://helm.sh/) 3.15+ | — | required |
| `aws` CLI | — | one-time bucket bootstrap |

All credentials default to dev-only values (`admin` / `password` / `any`).
Override anything that matters via `.env` (Compose) or a Kubernetes Secret.

### Path A — Docker Compose (fast local loop)

```bash
docker compose up -d                            # 14 services, ~60s to settle
docker compose ps                               # all should be healthy or "Up"
```

State persists to gitignored bind mounts under the repo root:
`./.seaweedfs/`, `./.redis/`, `./.postgres/`, `./.falkordb/`, `./.tempo/`,
`./.loki/`. Prometheus + Grafana use named Docker volumes.

Try it:

```bash
# Chat completion (no real provider needed — uses mock_response when keys are blank)
curl -sS http://localhost:4000/v1/chat/completions \
  -H "Authorization: Bearer sk-dev-master-key-change-me-not-a-secret" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-sonnet-4-6","messages":[{"role":"user","content":"hi"}]}'

# Grafana (admin / admin)
open http://localhost:3001

# LiteLLM admin UI (admin / password)
open http://localhost:4000/ui

# MLflow
open http://localhost:5000
```

Tear down:

```bash
docker compose down                                              # keep data
docker compose down -v && rm -rf .seaweedfs .redis .postgres \
  .falkordb .tempo .loki                                         # full wipe
```

To use real Anthropic / OpenAI models, set the keys in `.env` (the file is
gitignored; `.env.example` documents what's available):

```bash
cp .env.example .env
# edit .env: set ANTHROPIC_API_KEY / OPENAI_API_KEY
docker compose up -d --force-recreate litellm
```

### Path B — Kubernetes (kind + Helm)

This path runs the same services inside a local kind cluster — useful for
practicing the Helm install flow and the cross-chart wiring without
provisioning a real cluster. All orchestration is wrapped in
[deploy.sh](deploy.sh):

```bash
./deploy.sh --up                 # full stack (creates kind cluster if absent)
./deploy.sh --up <chart>         # one chart + its hard deps (idempotent)
./deploy.sh --status             # show current state
./deploy.sh --down <chart>       # uninstall one chart
./deploy.sh --down               # uninstall all + delete kind cluster
```

The script:

- reuses an existing `agentic-platform` kind cluster if present
- runs `helm dependency update` + extracts subchart tarballs (Helm 3.21+
  requires deps unpacked into `charts/<name>/`, not just present as `.tgz`)
- bootstraps SeaweedFS buckets as an in-cluster Job (no host `aws` CLI
  needed), creates the `litellm` Postgres database, and creates the
  `platform-litellm-secrets` Secret automatically
- uses `helm upgrade --install` so re-running is safe

Try it (run each port-forward in its own terminal):

```bash
kubectl -n agentic-platform port-forward svc/platform-litellm 4000:4000
kubectl -n agentic-platform port-forward svc/platform-grafana 3000:80
kubectl -n agentic-platform port-forward svc/platform-mlflow  5000:5000
```

<details>
<summary>Equivalent manual steps (what <code>deploy.sh --up</code> does under the hood)</summary>

```bash
# 1. Cluster + namespace
kind create cluster --config deploy/kind/kind-config.yaml --name agentic-platform
kubectl create namespace agentic-platform

# 2. For every chart with subchart deps: update + extract
for c in seaweedfs tempo loki prometheus grafana otel-collector mlflow litellm; do
  helm dependency update deploy/helm/$c
  (cd deploy/helm/$c/charts && for t in *.tgz; do tar -xzf "$t"; done)
done

# 3. Shared infrastructure
helm install platform-seaweedfs deploy/helm/seaweedfs -n agentic-platform --wait --timeout 5m
helm install platform-redis     deploy/helm/redis     -n agentic-platform --wait --timeout 5m
helm install platform-postgres  deploy/helm/postgres  -n agentic-platform --wait --timeout 5m
helm install platform-falkordb  deploy/helm/falkordb  -n agentic-platform --wait --timeout 5m

# 4. Bootstrap (buckets via in-cluster Job + litellm DB)
# (see bootstrap_buckets / bootstrap_litellm_db in deploy.sh)

# 5. Telemetry + tracking
helm install platform-tempo          deploy/helm/tempo          -n agentic-platform --wait --timeout 5m
helm install platform-loki           deploy/helm/loki           -n agentic-platform --wait --timeout 8m
helm install platform-prometheus     deploy/helm/prometheus     -n agentic-platform --wait --timeout 5m
helm install platform-grafana        deploy/helm/grafana        -n agentic-platform --wait --timeout 5m
helm install platform-otel-collector deploy/helm/otel-collector -n agentic-platform --wait --timeout 5m
helm install platform-mlflow         deploy/helm/mlflow         -n agentic-platform --wait --timeout 8m

# 6. Data plane
helm install platform-presidio    deploy/helm/presidio    -n agentic-platform --wait --timeout 5m
helm install platform-obot         deploy/helm/obot         -n agentic-platform --wait --timeout 8m
kubectl -n agentic-platform create secret generic platform-litellm-secrets \
  --from-literal=masterkey="$(openssl rand -hex 32)" \
  --from-literal=anthropic-api-key="${ANTHROPIC_API_KEY:-}" \
  --from-literal=openai-api-key="${OPENAI_API_KEY:-}"
helm install platform-litellm deploy/helm/litellm -n agentic-platform --wait --timeout 10m
```

</details>

## Services

| Plane | Service | Purpose | Image | Helm chart |
| --- | --- | --- | --- | --- |
| Infra | SeaweedFS | S3-compatible object store | `chrislusf/seaweedfs:4.29` | [deploy/helm/seaweedfs/](deploy/helm/seaweedfs/) |
| Infra | Redis | KV + JSON + Search (LangGraph checkpointer, LiteLLM cache) | `redis:latest` (Redis 8) | [deploy/helm/redis/](deploy/helm/redis/) |
| Infra | Postgres | Relational store (LiteLLM usage, MLflow, LangGraph) | `postgres:latest` | [deploy/helm/postgres/](deploy/helm/postgres/) |
| Infra | FalkorDB | Property-graph DB (GraphRAG) | `falkordb/falkordb:latest` | [deploy/helm/falkordb/](deploy/helm/falkordb/) |
| Data | LiteLLM | OpenAI-compatible LLM proxy + Presidio PII masking | `ghcr.io/berriai/litellm:main-stable` | [deploy/helm/litellm/](deploy/helm/litellm/) |
| Data | Presidio (analyzer + anonymizer) | PII detection + redaction sidecars for LiteLLM | `mcr.microsoft.com/presidio-{analyzer,anonymizer}` | [deploy/helm/presidio/](deploy/helm/presidio/) |
| Data | Obot | MCP gateway + registry + chat UI; deploys MCP servers as k8s workloads | `ghcr.io/obot-platform/obot:latest` | [deploy/helm/obot/](deploy/helm/obot/) |
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
| 8090 | obot | Obot MCP Gateway + UI (container port 8080) |
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
| [config/seaweedfs-init/buckets.sh](config/seaweedfs-init/buckets.sh) | run by `seaweedfs-init` service | document only (see below) | One-shot bucket bootstrap |

> **Implication of the dual-config layout.** Configs live in two places by
> design: `config/*` are bind-mounted into Compose containers; the same
> conceptual settings are re-stated as Helm values in each chart's
> `values.yaml`. When you change one, mirror the change in the other. There
> is no auto-sync.

## Environment variables

All credentials default to dev-only values in `docker-compose.yaml` via
`${VAR:-default}` substitution, so the Compose stack runs without a
`.env` file. Override anything that matters by creating `.env` (gitignored;
see [.env.example](.env.example) for the full list with comments).

| Var | Default | Where used | Notes |
| --- | --- | --- | --- |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` / `POSTGRES_DB` | `postgres` / `password` / `mlflow` | Compose | Shared Postgres for LiteLLM + MLflow |
| `S3_ACCESS_KEY` / `S3_SECRET_KEY` | `any` / `any` | Compose | Must match the identities in [config/seaweedfs/s3-identities.json](config/seaweedfs/s3-identities.json) |
| `LITELLM_MASTER_KEY` | `sk-dev-master-key-change-me-not-a-secret` | Compose | Bearer token clients send to LiteLLM |
| `LITELLM_UI_USERNAME` / `LITELLM_UI_PASSWORD` | `admin` / `password` | Compose | Admin UI login at `:4000/ui` |
| `GRAFANA_ADMIN_PASSWORD` | `admin` | Compose | Grafana admin password at `:3001` |
| `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` | empty | Compose | Upstream provider keys; leave blank to use `mock_response` |

For Helm, credentials go into a Kubernetes Secret instead of `.env` — see
[deploy/helm/litellm/README.md](deploy/helm/litellm/README.md) and
[deploy/helm/grafana/values.yaml](deploy/helm/grafana/values.yaml).

## Chart-level READMEs

Each Helm chart has its own README with prerequisites and per-service options:

**Infra**
- [SeaweedFS](deploy/helm/seaweedfs/README.md)
- [Redis](deploy/helm/redis/README.md)
- [Postgres](deploy/helm/postgres/README.md)
- [FalkorDB](deploy/helm/falkordb/README.md)

**Data**
- [LiteLLM](deploy/helm/litellm/README.md)
- [Presidio](deploy/helm/presidio/README.md)
- [Obot](deploy/helm/obot/README.md)

**Tracking**
- [MLflow](deploy/helm/mlflow/README.md)

**Telemetry**
- [OTel Collector](deploy/helm/otel-collector/README.md)
- [Tempo](deploy/helm/tempo/README.md)
- [Loki](deploy/helm/loki/README.md)
- [Prometheus](deploy/helm/prometheus/README.md)
- [Grafana](deploy/helm/grafana/README.md)

## CI

Each chart has its own workflow under [.github/workflows/](.github/workflows/),
gated by `paths:` filters on its chart directory. Workflows spin up an
**ephemeral kind cluster** inside the GitHub Actions runner, install the
chart (plus any hard dependencies it needs), and run an **integration test**
that exercises the service end-to-end — not just a health probe. Scope is
set by the dependency graph:

| Workflow | Installs | Integration test |
| --- | --- | --- |
| [deploy-seaweedfs.yaml](.github/workflows/deploy-seaweedfs.yaml) | seaweedfs | HTTP GET against the S3 endpoint |
| [deploy-redis.yaml](.github/workflows/deploy-redis.yaml) | redis | `PING` + `MODULE LIST` (verifies RedisJSON + RediSearch) |
| [deploy-postgres.yaml](.github/workflows/deploy-postgres.yaml) | postgres | `pg_isready` + `SELECT 1` |
| [deploy-falkordb.yaml](.github/workflows/deploy-falkordb.yaml) | falkordb | `GRAPH.QUERY` + `GRAPH.LIST` |
| [deploy-presidio.yaml](.github/workflows/deploy-presidio.yaml) | presidio | Analyze a PII string → anonymize → verify redaction |
| [deploy-obot.yaml](.github/workflows/deploy-obot.yaml) | obot | `/api/health` probe |
| [deploy-prometheus.yaml](.github/workflows/deploy-prometheus.yaml) | prometheus | Self-scrape `up` metric returns 1 |
| [deploy-grafana.yaml](.github/workflows/deploy-grafana.yaml) | grafana | `/api/health` + `/api/datasources` returns all three provisioned |
| [deploy-tempo.yaml](.github/workflows/deploy-tempo.yaml) | seaweedfs + tempo | Push OTLP trace → poll Tempo until it appears in S3-backed storage |
| [deploy-loki.yaml](.github/workflows/deploy-loki.yaml) | seaweedfs + loki | Push log → query Loki until it appears |
| [deploy-otel-collector.yaml](.github/workflows/deploy-otel-collector.yaml) | seaweedfs + tempo + loki + prometheus + otel | OTLP trace/log/metric fan-out — verify each lands in its backend |
| [deploy-mlflow.yaml](.github/workflows/deploy-mlflow.yaml) | postgres + seaweedfs + mlflow | Create experiment → log run + metric → read back via REST |
| [deploy-litellm.yaml](.github/workflows/deploy-litellm.yaml) | postgres + redis + presidio + otel + litellm | `POST /v1/chat/completions` with `mock_response` model |
| [deploy-platform-e2e.yaml](.github/workflows/deploy-platform-e2e.yaml) | **the entire stack** | LiteLLM chat → verify trace in Tempo, metrics in Prometheus |

**Why LiteLLM CI uses `mock_response`**: the `mock_response` model param
makes LiteLLM return canned text without calling the upstream provider, so
the CI run exercises the full request path (auth, presidio masking,
Postgres logging, OTel emission) without burning provider credits or
needing real API keys in repo secrets.

**Why an e2e workflow on top of per-chart workflows**: per-chart workflows
catch regressions inside one chart. The e2e workflow catches **cross-chart**
regressions — e.g. "I changed the OTel exporter endpoint and now nothing
reaches Tempo", which all per-chart tests would still pass cleanly. It's
gated on `paths: deploy/helm/**` so any chart change re-runs it.
