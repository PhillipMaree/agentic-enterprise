# enterprise-platform

End-to-end local development stack for agentic AI and RAG applications: an LLM gateway with PII masking, an MCP tool gateway and registry, document conversion, hybrid lexical/vector search, graph storage, experiment tracking, observability, and a Keycloak identity provider for OIDC auth and token exchange.

The stack is designed so an agentic/RAG app can rely on a small set of local platform surfaces: LiteLLM for model calls, Obot for tools, OpenSearch for hybrid retrieval, FalkorDB for graph context, Docling for document conversion during ingestion, OTel Collector for telemetry, and Keycloak for identity.

Two consumption surfaces, both running the same set of services:

- **Docker Compose** — fastest local loop. `docker compose up -d`.
- **Helm charts** — one chart per service, all named `enterprise-platform-<svc>`,
  installed into the `enterprise-platform` namespace of a local
  [kind](https://kind.sigs.k8s.io/) cluster.

> Dev-only. Auth is off or set to defaults. Do not point any of this at a
> shared cluster as-is.

## Architecture

```mermaid
%%{init: {'theme': 'dark'}}%%
flowchart TB
    subgraph clients [Agentic apps / RAG apps]
        app[Agent / workflow / frontend]
        ingest[Corpus ingestion job]
    end

    subgraph authz [Auth]
        keycloak[Keycloak IdP :18080]
    end

    subgraph ingress [AI and tool ingress]
        litellm[LiteLLM proxy + UI :14000]
        obot[Obot MCP gateway + registry :18090]
        presidio_a[Presidio analyzer]
        presidio_o[Presidio anonymizer]
    end

    subgraph rag [RAG retrieval and knowledge layer]
        docling[Docling document conversion API :15001]
        opensearch[(OpenSearch BM25 + kNN :19200)]
        falkordb[(FalkorDB knowledge graph :16380/:13000)]
    end

    subgraph tracking [Experiment tracking]
        mlflow[MLflow :15000]
    end

    subgraph telemetry [Telemetry plane]
        otel[OTel Collector :14317/:14318]
        tempo[Tempo traces :13200]
        loki[Loki logs :13100]
        prom[Prometheus metrics :19090]
        grafana[Grafana :13001]
    end

    subgraph infra [Shared infrastructure]
        redis[(Redis :16379)]
        postgres[(Postgres :15432)]
        seaweedfs[(SeaweedFS S3 :18333)]
    end

    subgraph bootstrap [One-shot bootstraps]
        pginit[postgres-init]
        s3init[seaweedfs-init]
    end

    app -->|OIDC login + token exchange| keycloak
    app -->|chat completions| litellm
    app -->|tool calls| obot
    app -->|retrieval queries| opensearch
    app -->|graph context / relationships| falkordb
    app -.->|OTLP| otel

    ingest -->|convert PDF/DOCX/etc.| docling
    ingest -->|store raw/derived artifacts| seaweedfs
    ingest -->|index chunks + vectors| opensearch
    ingest -->|write entities / topics / relationships| falkordb

    litellm --> presidio_a
    litellm --> presidio_o
    litellm -->|cache DB1| redis
    litellm -->|usage / keys| postgres
    litellm -.->|OTLP| otel

    mlflow -->|backend store| postgres
    mlflow -->|artifacts| seaweedfs

    s3init -->|create buckets| seaweedfs
    pginit -->|create litellm + equinor_search DBs| postgres

    otel --> tempo
    otel --> loki
    otel --> prom

    tempo -->|trace blocks| seaweedfs
    loki -->|chunks + index| seaweedfs

    grafana --> tempo
    grafana --> loki
    grafana --> prom
```

**Reading the diagram**

- Solid arrows are request/data paths (synchronous).
- Dotted arrows are asynchronous OTLP telemetry.
- Agentic apps call LiteLLM for LLMs, Obot for tools, OpenSearch for hybrid
  retrieval, FalkorDB for graph context, Keycloak for identity, and OTel
  Collector for telemetry.
- Ingestion jobs call Docling to convert source documents, store raw/derived
  artifacts in SeaweedFS when needed, index chunks/vectors in OpenSearch, and
  optionally write entities/topics/relationships into FalkorDB.
- OpenSearch handles lexical/vector retrieval; FalkorDB handles graph structure
  and reasoning context — they are complementary, not redundant.
- `postgres-init` and `seaweedfs-init` are one-shot bootstrap jobs, not runtime
  services.
- SeaweedFS backs MLflow artifacts, Tempo trace blocks, and Loki chunks/index;
  application ingestion jobs may also use it for raw/derived artifact storage.

## RAG and GraphRAG flow

The local stack supports a typical enterprise RAG flow:

1. Source documents are collected by an ingestion job or application code.
2. Docling converts PDFs, DOCX files, and similar formats into structured text/metadata.
3. Raw files and derived artifacts can be stored in SeaweedFS S3.
4. Text chunks and embeddings are indexed in OpenSearch for hybrid BM25 + kNN retrieval.
5. Entities, topics, document relationships, and provenance can be written to FalkorDB for GraphRAG context.
6. The runtime agent retrieves candidate evidence from OpenSearch, enriches it through FalkorDB, calls tools through Obot when needed, and sends generation requests through LiteLLM.
7. All services emit traces/metrics/logs through the OTel/Grafana stack.

The exact chunking strategy and index schema belong in the application layer unless codified elsewhere in this repo.

## Tenant attribution

Usage is partitioned per tenant so one dashboard can break LLM and MCP
consumption down by the agentic client that drove it. Telemetry can only be
sliced by a label it actually carries, so the **client is responsible for
stamping its tenant onto every call** — nothing reads the JWT and labels
metrics for you. The tenant identity originates as the Keycloak `tenant`
claim (the same one that scopes the FalkorDB graph); the client reads it from
its token and forwards it on two surfaces.

**LLM usage → LiteLLM team.** Tenant maps to a LiteLLM *team*: the client
calls LiteLLM with a team-scoped virtual key, and LiteLLM automatically tags
its Prometheus metrics with `team` / `team_alias`. Provision once per tenant
(via the admin UI at `:14000/ui` or the API):

```bash
# 1. a team per tenant
curl -sS http://localhost:14000/team/new \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H 'Content-Type: application/json' \
  -d '{"team_alias":"acme"}'                          # -> returns team_id

# 2. a virtual key bound to that team
curl -sS http://localhost:14000/key/generate \
  -H "Authorization: Bearer $LITELLM_MASTER_KEY" -H 'Content-Type: application/json' \
  -d '{"team_id":"<team_id>"}'                         # -> returns sk-... key
```

The client then sends chat completions with `Authorization: Bearer sk-...`
(the per-tenant key) instead of the master key. No per-request work — the
`team` label rides on every usage metric.

**MCP usage → `tenant` telemetry attribute.** MCP tool calls have no native
per-tenant metric, so the client's OpenTelemetry SDK must carry the tenant on
its spans. The simplest mechanism is a resource attribute set once at startup:

```bash
OTEL_RESOURCE_ATTRIBUTES=tenant=acme,service.name=my-agent
OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:14318    # the OTel collector (HTTP)
```

(or set `tenant` as a span attribute on each tool-call span). The OTel
Collector's [`spanmetrics` connector](config/otel-collector/config.yaml)
derives request/error/latency metrics from those spans with `tenant` as a
dimension, so MCP usage lands in Prometheus alongside the LLM metrics.

Both feed the **Agentic Usage Overview** dashboard
([config/grafana/provisioning/dashboards/agentic-usage-overview.json](config/grafana/provisioning/dashboards/agentic-usage-overview.json)),
whose `$tenant` variable (sourced from the `team` label) filters every panel.
This is a *visual* partition — anyone with Grafana access can switch tenants;
it is not data-path isolation.

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
| [`kubeseal`](https://github.com/bitnami-labs/sealed-secrets) | — | only to (re)seal secrets (`--seal`), not for `--up` |

All credentials default to dev-only values (`admin` / `password` / `any`).
On the Kubernetes path they are stored as **Sealed Secrets** (encrypted,
committed to git, decrypted in-cluster by a controller); on Compose, admin
passwords are file-based secrets under `secrets/compose/`. Real LLM provider
keys never enter the kind cluster or git — see [docs/SECURITY.md](docs/SECURITY.md).

### Path A — Docker Compose (fast local loop)

```bash
# Bootstrap file-based secrets (postgres/keycloak/grafana admin passwords).
for f in postgres_password keycloak_admin_password grafana_admin_password; do
  cp "secrets/compose/$f.example" "secrets/compose/$f"
done

docker compose up -d                            # ~60s to settle
docker compose ps                               # all should be healthy or "Up"
```

Compose defines 19 service entries: 17 long-running containers plus 2 one-shot
bootstrap jobs (`postgres-init` and `seaweedfs-init`). The bootstrap jobs exit
after creating the required Postgres databases/role and SeaweedFS buckets.

> The first Docling conversion can be slower because the CPU image may download
> models into the `docling-models` Docker volume on first use.

> OpenSearch runs with `DISABLE_SECURITY_PLUGIN=true` and listens over plain
> HTTP — intentional for local dev.

State persists to gitignored bind mounts under the repo root and to named
Docker volumes:

```text
./.seaweedfs/
./.redis/
./.postgres/
./.falkordb/
./.opensearch/
./.obot/
./.tempo/
./.loki/
Docker volumes: prometheus-data, grafana-data, docling-models
```

Try it:

```bash
# Chat completion (no real provider needed — uses mock_response when keys are blank)
curl -sS http://localhost:14000/v1/chat/completions \
  -H "Authorization: Bearer sk-dev-master-key-change-me-not-a-secret" \
  -H "Content-Type: application/json" \
  -d '{"model":"claude-fable-5","messages":[{"role":"user","content":"hi"}]}'

# Grafana (admin / password)
open http://localhost:13001

# LiteLLM admin UI (admin / password)
open http://localhost:14000/ui

# MLflow
open http://localhost:15000

# OpenSearch cluster health
curl -sS http://localhost:19200/_cluster/health | jq

# OpenSearch nodes + plugins
curl -sS http://localhost:19200/_nodes/plugins | jq

# Docling UI
open http://localhost:15001
```

Tear down:

```bash
docker compose down                                              # keep data
docker compose down -v
rm -rf .seaweedfs .redis .postgres .falkordb .opensearch .obot .tempo .loki
```

To use real Anthropic / OpenAI models, set the keys in `.env` (the file is
gitignored; `.env.example` documents what's available):

```bash
cp .env.example .env
# edit .env: set ANTHROPIC_API_KEY / OPENAI_API_KEY
docker compose up -d --force-recreate litellm
```

### Startup dependencies

Compose orders startup with `depends_on` health/completion conditions:

- `postgres-init` waits for Postgres healthy, then creates the `litellm` DB,
  the `equinor_search` DB, and the `equinor` role.
- `seaweedfs-init` waits for SeaweedFS healthy, then creates the S3 buckets.
- `litellm` waits for `postgres-init` completed, Redis healthy, and the two
  Presidio sidecars healthy.
- `mlflow`, `tempo`, and `loki` wait for `seaweedfs-init` completed.
- `otel-collector` depends on Tempo, Prometheus, and Loki started.
- `grafana` depends on Tempo, Prometheus, and Loki started.
- OpenSearch and Docling have no Compose-level dependencies, but application
  code will depend on them.

### Path B — Kubernetes (kind + Helm)

This path runs the Helm-charted services inside a local kind cluster — useful
for practicing the Helm install flow and the cross-chart wiring without
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

- reuses an existing `enterprise-platform` kind cluster if present
- installs the **Sealed Secrets controller** into `kube-system` (adopting the
  committed dev sealing key in `secrets/dev/`), then applies the committed
  `SealedSecret`s in [deploy/sealed-secrets/](deploy/sealed-secrets/) — they
  decrypt into the `enterprise-platform-*` Secrets the charts consume (postgres, keycloak
  admin, grafana admin, litellm masterkey, S3 creds)
- runs `helm dependency update` + extracts subchart tarballs (Helm 3.21+
  requires deps unpacked into `charts/<name>/`, not just present as `.tgz`)
- bootstraps SeaweedFS buckets as an in-cluster Job (no host `aws` CLI
  needed) and creates the `litellm` Postgres database
- uses `helm upgrade --install` so re-running is safe

Docker Compose is the most complete local stack. OpenSearch and Docling are
Compose-only until matching Helm charts and CI smoke tests are added.

Try it (run each port-forward in its own terminal):

```bash
kubectl -n enterprise-platform port-forward svc/enterprise-platform-litellm 4000:4000
kubectl -n enterprise-platform port-forward svc/enterprise-platform-grafana 3000:80
kubectl -n enterprise-platform port-forward svc/enterprise-platform-mlflow  5000:5000
```

<details>
<summary>Equivalent manual steps (what <code>deploy.sh --up</code> does under the hood)</summary>

```bash
# 1. Cluster + namespace
kind create cluster --config deploy/kind/kind-config.yaml --name enterprise-platform
kubectl create namespace enterprise-platform

# 1b. Sealed Secrets: adopt the committed dev key, install the controller,
#     then apply the committed SealedSecrets (they decrypt into enterprise-platform-* Secrets).
kubectl apply -f secrets/dev/sealed-secrets-dev-keypair.yaml
helm -n kube-system upgrade --install sealed-secrets sealed-secrets \
  --repo https://bitnami.github.io/sealed-secrets --version 2.17.9 \
  -f deploy/helm/sealed-secrets/values.yaml --wait
kubectl -n kube-system rollout status deploy/sealed-secrets-controller
kubectl apply -f deploy/sealed-secrets/

# 2. For every chart with subchart deps: update + extract
for c in seaweedfs tempo loki prometheus grafana otel-collector mlflow litellm; do
  helm dependency update deploy/helm/$c
  (cd deploy/helm/$c/charts && for t in *.tgz; do tar -xzf "$t"; done)
done

# 3. Shared infrastructure
helm install enterprise-platform-seaweedfs deploy/helm/seaweedfs -n enterprise-platform --wait --timeout 5m
helm install enterprise-platform-redis     deploy/helm/redis     -n enterprise-platform --wait --timeout 5m
helm install enterprise-platform-postgres  deploy/helm/postgres  -n enterprise-platform --wait --timeout 5m
helm install enterprise-platform-falkordb  deploy/helm/falkordb  -n enterprise-platform --wait --timeout 5m

# 4. Bootstrap (buckets via in-cluster Job + litellm DB)
# (see bootstrap_buckets / bootstrap_litellm_db in deploy.sh)

# 5. Telemetry + tracking
helm install enterprise-platform-tempo          deploy/helm/tempo          -n enterprise-platform --wait --timeout 5m
helm install enterprise-platform-loki           deploy/helm/loki           -n enterprise-platform --wait --timeout 8m
helm install enterprise-platform-prometheus     deploy/helm/prometheus     -n enterprise-platform --wait --timeout 5m
helm install enterprise-platform-grafana        deploy/helm/grafana        -n enterprise-platform --wait --timeout 5m
helm install enterprise-platform-otel-collector deploy/helm/otel-collector -n enterprise-platform --wait --timeout 5m
helm install enterprise-platform-mlflow         deploy/helm/mlflow         -n enterprise-platform --wait --timeout 8m

# 6. Data plane (enterprise-platform-litellm-secrets already exists from step 1b — its
#    masterkey is sealed; the kind path is mock-only so no provider keys here)
helm install enterprise-platform-presidio    deploy/helm/presidio    -n enterprise-platform --wait --timeout 5m
helm install enterprise-platform-obot         deploy/helm/obot         -n enterprise-platform --wait --timeout 8m
helm install enterprise-platform-litellm deploy/helm/litellm -n enterprise-platform --wait --timeout 10m
```

</details>

## Services

Compose defines 19 service entries: 17 long-running containers plus 2 one-shot
bootstrap jobs (`postgres-init`, `seaweedfs-init`).

| Plane | Service | Purpose | Image | Helm chart |
| --- | --- | --- | --- | --- |
| Infra | SeaweedFS | S3-compatible object store | `chrislusf/seaweedfs:4.29` | [deploy/helm/seaweedfs/](deploy/helm/seaweedfs/) |
| Infra | Redis | KV + JSON + Search (LangGraph checkpointer, LiteLLM cache) | `redis:latest` (Redis 8) | [deploy/helm/redis/](deploy/helm/redis/) |
| Infra | Postgres | Relational store (LiteLLM usage, MLflow, LangGraph) | `postgres:latest` | [deploy/helm/postgres/](deploy/helm/postgres/) |
| Infra | FalkorDB | Property-graph DB (GraphRAG) | `falkordb/falkordb:latest` | [deploy/helm/falkordb/](deploy/helm/falkordb/) |
| Search | OpenSearch | Hybrid BM25 + kNN vector search store | `opensearchproject/opensearch:2.18.0` | Compose only |
| Ingestion | Docling | Document conversion API/UI (PDF/DOCX/… → structured text) | `quay.io/docling-project/docling-serve-cpu:latest` | Compose only |
| Bootstrap | postgres-init | One-shot: creates `litellm` + `equinor_search` DBs and `equinor` role | `postgres:latest` | (job) |
| Bootstrap | seaweedfs-init | One-shot: creates SeaweedFS buckets | `amazon/aws-cli:latest` | (job) |
| Auth | Keycloak | OIDC IdP + token exchange for the agent chain (`agentic-dev` realm) | `quay.io/keycloak/keycloak:26.1` | [deploy/helm/keycloak/](deploy/helm/keycloak/) |
| Data | LiteLLM | OpenAI-compatible LLM proxy + Presidio PII masking | `ghcr.io/berriai/litellm:v1.87.2` | [deploy/helm/litellm/](deploy/helm/litellm/) |
| Data | Presidio analyzer | PII detection sidecar for LiteLLM | `mcr.microsoft.com/presidio-analyzer:2.2.361` | [deploy/helm/presidio/](deploy/helm/presidio/) |
| Data | Presidio anonymizer | PII redaction sidecar for LiteLLM | `mcr.microsoft.com/presidio-anonymizer:2.2.361` | [deploy/helm/presidio/](deploy/helm/presidio/) |
| Data | Obot | MCP gateway + registry + chat UI; deploys MCP servers as k8s workloads | `ghcr.io/obot-platform/obot:latest` | [deploy/helm/obot/](deploy/helm/obot/) |
| Tracking | MLflow | Experiment + artifact tracking | `ghcr.io/mlflow/mlflow:v2.18.0` | [deploy/helm/mlflow/](deploy/helm/mlflow/) |
| Telemetry | OTel Collector | OTLP fan-out to tempo/loki/prometheus | `otel/opentelemetry-collector-contrib:latest` | [deploy/helm/otel-collector/](deploy/helm/otel-collector/) |
| Telemetry | Tempo | Traces backend (S3) | `grafana/tempo:latest` | [deploy/helm/tempo/](deploy/helm/tempo/) |
| Telemetry | Loki | Logs backend (S3) | `grafana/loki:latest` | [deploy/helm/loki/](deploy/helm/loki/) |
| Telemetry | Prometheus | Metrics (remote-write + scrape) | `prom/prometheus:latest` | [deploy/helm/prometheus/](deploy/helm/prometheus/) |
| Telemetry | Grafana | UI with auto-provisioned datasources | `grafana/grafana:11.6.3` | [deploy/helm/grafana/](deploy/helm/grafana/) |

Presidio is two services on Compose (`presidio-analyzer` and
`presidio-anonymizer`); both are covered by the single
[presidio](deploy/helm/presidio/) Helm chart.

## Ports (host → container)

Compose publishes every service on a **`1xxxx`** host port (the well-known
port prefixed with `1`). This deliberately avoids the standard ports so the
Compose stack and the kind port-forwards (which use the plain ports — `4000`,
`5000`, `3000`…) can run side by side without clashing. Container ports are
unchanged; this only affects what you type on `localhost`.

| Host | Service | What it is |
| ---: | --- | --- |
| 19333 | seaweedfs | SeaweedFS master |
| 19080 | seaweedfs | SeaweedFS volume (18080 taken by keycloak) |
| 18888 | seaweedfs | SeaweedFS filer |
| 18333 | seaweedfs | SeaweedFS S3 gateway |
| 16379 | redis | Redis (RESP) |
| 15432 | postgres | Postgres |
| 16380 | falkordb | FalkorDB (RESP, graph) |
| 13000 | falkordb | FalkorDB Browser UI |
| 19200 | opensearch | Hybrid BM25 + kNN vector search API |
| 15001 | docling | Document conversion API/UI |
| 18080 | keycloak | Keycloak OIDC IdP |
| 14000 | litellm | LiteLLM proxy + UI |
| 18090 | obot | Obot MCP Gateway + Registry + UI (container port 8080) |
| 15000 | mlflow | MLflow UI + API |
| 14317 | otel-collector | OTLP gRPC |
| 14318 | otel-collector | OTLP HTTP |
| 18889 | otel-collector | Collector /metrics (container 8888) |
| 13200 | tempo | Tempo query API |
| 13100 | loki | Loki push + query API |
| 19090 | prometheus | Prometheus UI + remote-write |
| 13001 | grafana | Grafana UI (13000 taken by falkordb) |

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
| [deploy/helm/keycloak/realm-agentic-dev.json](deploy/helm/keycloak/realm-agentic-dev.json) | volume mount | configmap via `.Files.Get` | Keycloak `agentic-dev` realm: clients, scopes, token-exchange, demo users. Single source — both surfaces read the same file (not dual-stated). |

> OpenSearch and Docling are currently configured directly in
> `docker-compose.yaml`. There are no repo-managed `config/opensearch/` or
> `config/docling/` directories.

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
| `LITELLM_UI_USERNAME` / `LITELLM_UI_PASSWORD` | `admin` / `password` | Compose | Admin UI login at `:14000/ui` |
| `KEYCLOAK_ADMIN_USERNAME` | `admin` | Compose | Keycloak bootstrap admin user at `:18080` |
| `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` | empty | Compose | Upstream provider keys; leave blank to use `mock_response`. Local-only — never enter the kind cluster |

The **keycloak** and **grafana** admin passwords (and the Postgres server
password) are no longer env vars — they are file-based secrets under
`secrets/compose/` (copy the `*.example` files to bootstrap). See
[docs/SECURITY.md](docs/SECURITY.md).

For Helm, credentials are **Sealed Secrets** (encrypted, committed, decrypted
in-cluster) — see [docs/SECURITY.md](docs/SECURITY.md) and
[deploy/sealed-secrets/](deploy/sealed-secrets/).

OpenSearch and Docling currently run with local-dev defaults defined in
`docker-compose.yaml`; no `.env` override is required unless configuration is
extended.

## Chart-level READMEs

Each Helm chart has its own README with prerequisites and per-service options:

**Infra**
- [SeaweedFS](deploy/helm/seaweedfs/README.md)
- [Redis](deploy/helm/redis/README.md)
- [Postgres](deploy/helm/postgres/README.md)
- [FalkorDB](deploy/helm/falkordb/README.md)

**Auth**
- [Keycloak](deploy/helm/keycloak/README.md)

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

OpenSearch and Docling have no Helm charts — they are Compose-only.

## CI

**One workflow per push** that builds **every charted service** in dependency
layers — parallel where independent.
[deploy.yaml](.github/workflows/deploy.yaml) is the trigger workflow; on
every push it runs all chart jobs (no paths-filter — the whole stack is
built each time), ordered only by their hard dependencies:

```text
changes  (always: build every service)
   ├─► seaweedfs           ┐
   ├─► redis               │  Layer 0 — no chart deps. Parallel.
   ├─► postgres            │
   ├─► falkordb            │
   ├─► keycloak            │
   ├─► presidio            │
   ├─► obot                │
   ├─► prometheus          │
   ├─► grafana             │
   └─► otel-collector      ┘
        ↓
   ├─► tempo               │  Layer 1 — needs seaweedfs.
   └─► loki                │
        ↓
   └─► mlflow              │  Layer 2 — needs postgres + seaweedfs.
        ↓
   └─► litellm             │  Layer 3 — needs postgres + redis +
                           │            presidio + otel-collector.
        ↓
   └─► e2e (full stack)    │  Runs once every service is up.
        ↓
   └─► gate                │  The single required check for branch
                           │  protection. Green only if every job
                           │  above passed.
```

**No fail-fast.** A service that fails its smoke test shows red on its own;
sibling jobs still run to completion, so one failure no longer cancels the
others — you see the full per-service result in a single graph. A dependent
(e.g. `tempo`) skips only when a dependency it actually needs (`seaweedfs`)
failed. The **`gate`** job aggregates the lot and is red if any job failed;
`gate` is the **only required status check** on `main`, so a merge is allowed
exactly when the whole stack is green.

**Each chart job** calls the reusable
[`_deploy-chart.yaml`](.github/workflows/_deploy-chart.yaml), which:

1. Spins up an **ephemeral kind cluster**
2. Runs `./deploy.sh --up <chart>` (which installs the chart's hard
   deps automatically — same code path as local dev)
3. Runs the chart's smoke test from
   [.github/scripts/smoke-&lt;chart&gt;.sh](.github/scripts/) — these are
   **integration tests**, not just health probes (S3 GET, redis
   `PING` + `MODULE LIST`, PII analyze/anonymize round trip, OTLP
   trace round trip, MLflow REST round trip, LiteLLM chat completion
   with `mock_response`, etc.)

**OpenSearch and Docling are not in CI.** They are Compose-only: there are no
`deploy/helm/opensearch/` or `deploy/helm/docling/` charts, and no
`smoke-opensearch.sh` or `smoke-docling.sh` scripts under
[.github/scripts/](.github/scripts/), so neither is built or smoke-tested by
the workflow.

- TODO: add Helm charts and CI smoke tests for OpenSearch and Docling.
- TODO: add an OpenSearch smoke test verifying cluster health and kNN plugin availability.
- TODO: add a Docling smoke test verifying API/UI health and a minimal conversion.

**LiteLLM mocking**: CI sets `LITELLM_USE_MOCK_MODELS=1`, which makes
`deploy.sh` overlay [values.ci-mock.yaml](deploy/helm/litellm/values.ci-mock.yaml)
when installing LiteLLM. Every model returns canned `mock_response`
text — the proxy exercises auth + Postgres logging + OTel emission
without hitting Anthropic/OpenAI. No repo secrets needed.

**The e2e job** runs the full chain test
([smoke-stack-e2e.sh](.github/scripts/smoke-stack-e2e.sh)):
drive a chat completion through LiteLLM (mock model), then verify
the resulting metrics arrived in Prometheus. Catches cross-chart
regressions that per-chart tests can't.

## Security notes

Dev-only defaults are insecure by design (`admin` / `password` / `any`) — see
[docs/SECURITY.md](docs/SECURITY.md) for how secrets are handled on each path
(file-based Compose secrets under `secrets/compose/`; Sealed Secrets for Helm).

OpenSearch runs with the security plugin disabled
(`DISABLE_SECURITY_PLUGIN=true`) and listens over plain HTTP on port 19200.
Docling exposes a local conversion API/UI on port 15001. Both are intentional
for laptop development only and must not be exposed directly in shared or
production environments.

## Production deploy

[ci-and-deploy.yaml](.github/workflows/ci-and-deploy.yaml) promotes a validated
commit to the remote **k3s** cluster. Validation itself lives in
[deploy.yaml](.github/workflows/deploy.yaml) (the build-all flow + `gate`); this
workflow is wired to it with a `workflow_run` trigger, so it only ever deploys a
commit that already went green.

- **Validation and promotion are separate workflows.** `deploy.yaml` builds and
  smoke-tests the whole stack on every push; `ci-and-deploy.yaml` does nothing
  but the prod deploy.
- **Merging to `main` triggers a production deploy over Tailscale.** When
  `deploy.yaml` finishes **successfully on `main`**, its `workflow_run` event
  fires `deploy-prod`, which deploys the exact SHA that passed. A failed `gate`
  never reaches prod; `workflow_dispatch` can promote manually.
- **The GitHub runner joins Tailscale temporarily.** `deploy-prod` brings up
  a short-lived, OAuth-authenticated `tag:ci` node via
  [`tailscale/github-action@v4`](https://github.com/tailscale/github-action).
  The node is torn down when the job ends.
- **Deployment happens by SSH into the k3s VM.** Over the tailnet the runner
  SSHes to the VM, pins the host key with `ssh-keyscan` (StrictHostKeyChecking
  stays on), checks out the **exact commit SHA that passed validation**
  (`git fetch` → `checkout` → `reset --hard` to the upstream run's `head_sha` —
  not "latest main"), and runs the deploy **locally on the VM**. The Kubernetes
  API is never exposed publicly — it is reachable only over Tailscale + SSH.

### Two deploy scripts: dev (kind) vs prod (k3s)

The prod deploy script is **separate** from the kind deploy script:

- [`deploy.sh`](deploy.sh) — the **kind/dev + CI** path. Creates (or reuses) a
  kind cluster, switches to its `kind-<name>` context, applies the **dev**
  sealing key, and installs the full stack. Used locally and by both CI
  workflows.
- [`scripts/deploy-prod.sh`](scripts/deploy-prod.sh) — the **k3s/prod** path,
  run on the VM by `deploy-prod`. It **sources** `deploy.sh` to reuse the exact
  same chart catalog and `helm upgrade --install` logic (so the two can't
  drift), but it **never creates a kind cluster or switches context** — it
  refuses to run if the current context is `kind-*`, verifies reachability with
  `kubectl get nodes`, and uses **prod** SealedSecrets/cert material from
  `secrets/prod/` rather than the dev key. It is idempotent (every chart goes
  in via `helm upgrade --install`).

> **Prod SealedSecrets.** `deploy-prod.sh` assumes the Sealed Secrets
> controller and its **prod private key** are already installed on the k3s
> cluster (managed out of band — never committed; auto-installing would mint a
> new key and orphan existing secrets). It applies prod-sealed SealedSecrets
> from `deploy/sealed-secrets/prod/` if present. The committed SealedSecrets in
> `deploy/sealed-secrets/` are **dev-sealed** and will not decrypt in prod —
> seal prod copies with the prod cert and commit them there:
> `./deploy.sh --seal --env prod <name> <out.yaml> --from-literal=k=v`.

### Required GitHub secrets

| Secret | Purpose |
| --- | --- |
| `PROD_HOST` | VM tailnet address (e.g. `100.x.y.z`) |
| `PROD_USER` | SSH user on the VM |
| `PROD_SSH_KEY` | Private SSH key for that user (written to a `0600` file, never echoed) |
| `TS_OAUTH_CLIENT_ID` | Tailscale OAuth client id for the ephemeral `tag:ci` node |
| `TS_OAUTH_SECRET` | Tailscale OAuth client secret |

### VM repo access

`deploy-prod` runs `git fetch` / `checkout` / `reset --hard` in `APP_DIR` on
the VM (default `/opt/enterprise-platform`). The workflow deliberately does **not**
embed any token in the SSH script. The VM must already be able to reach this
private repo by one of:

- **a)** an existing checkout at `APP_DIR` whose `origin` is authenticated
  (the deploy step then just fetches/resets — no clone), or
- **b)** a deploy key configured on the VM (e.g. an SSH deploy key in
  `~/.ssh` for `ubuntu-vm-server`), letting the initial `git clone` succeed.

> **TODO — VM repo access.** Confirm `APP_DIR` and provision (a) or (b) on the
> VM before the first prod deploy. Until then the `git clone`/`fetch` step will
> fail for a private repo.

### Production secrets with Sealed Secrets

Prod credentials are managed **GitOps-style**: only encrypted
[`SealedSecret`](https://github.com/bitnami-labs/sealed-secrets) manifests live
in the repo, never raw values.

- **Never commit raw secrets** — no `kind: Secret`, `.env`, private keys,
  tokens, passwords, kubeconfigs, or literal/base64 values. Only
  `kind: SealedSecret` YAML belongs in `deploy/sealed-secrets/prod/`. CI enforces
  this with [`scripts/check-no-raw-secrets.sh`](scripts/check-no-raw-secrets.sh)
  (a failing check fails the `gate`, so it can't merge). Temporary raw inputs are
  gitignored — delete them after sealing.
- The prod cluster runs the Sealed Secrets controller in `kube-system`, holding
  the **prod private key**. The matching **public cert** is committed at
  [secrets/prod/sealed-secrets-public-cert.pem](secrets/prod/sealed-secrets-public-cert.pem),
  and `./deploy.sh --seal --env prod` seals against it.
- On deploy, `scripts/deploy-prod.sh` applies everything in
  `deploy/sealed-secrets/prod/`, then waits for the derived Secrets. If that
  directory is empty it continues only when the required Secrets already exist
  live, and **fails fast** if any are missing.

The five Secrets are
`enterprise-platform-{postgres,keycloak-admin,grafana-admin,litellm-secrets,s3-creds}`.
Two helper scripts create and seal them; real values stay on your machine and
only the encrypted output is committed.

**1. Generate the random internal secrets.**
[`scripts/gen-prod-secrets.sh`](scripts/gen-prod-secrets.sh) mints strong random
values for everything with no external source (Postgres/Keycloak/Grafana admin
passwords, the LiteLLM master key, the S3 access/secret keys), writes the matching
SeaweedFS S3 identities JSON, and emits a source-able env file **outside the repo**
(mode `0600`, default `~/.enterprise-platform-prod.env`). It does **not** touch the
real provider keys — keep `ANTHROPIC_API_KEY` / `OPENAI_API_KEY` in your own shell
or profile; the seal step reads them straight from the environment.

```bash
export ANTHROPIC_API_KEY=...                 # real provider keys — your shell only, never the env file
export OPENAI_API_KEY=...
scripts/gen-prod-secrets.sh                  # writes ~/.enterprise-platform-prod.env + -s3-identities.json
```

Prefer to set everything by hand? Copy
[secrets/prod/prod-secrets.env.example](secrets/prod/prod-secrets.env.example)
out of the repo instead and replace every `<PLACEHOLDER>`.

**2. Source the values and seal.**
[`scripts/seal-prod-secrets.sh`](scripts/seal-prod-secrets.sh) reads every
required var from the environment (aborting **before** sealing anything if one is
missing or `S3_IDENTITIES_FILE` is unreadable), verifies the committed cert
matches the live prod controller, then seals all five SealedSecrets into
`deploy/sealed-secrets/prod/`.

```bash
set -a; source ~/.enterprise-platform-prod.env; set +a
scripts/seal-prod-secrets.sh                 # SKIP_CERT_CHECK=1 to seal without cluster access
```

**3. Commit only the encrypted output.**

```bash
scripts/check-no-raw-secrets.sh
git add deploy/sealed-secrets/prod/*.sealedsecret.yaml
```

The per-secret key lists and the equivalent **manual** `./deploy.sh --seal`
commands (one secret at a time, e.g. to rotate a single key) are in
[deploy/sealed-secrets/prod/README.md](deploy/sealed-secrets/prod/README.md).

### Recommended branch protection

Protect `main` so the production deploy can only ever run on a validated
commit: require the **`gate`** check (from
[deploy.yaml](.github/workflows/deploy.yaml)) to pass before merge — `gate` is
green only when every service job and the full-stack `e2e` test passed.
Optionally add a required reviewer to the **production** GitHub Environment for
a manual approval gate before `deploy-prod` runs.

> **Note.** Validation runs once. `deploy.yaml` (build-all + the required
> `gate` check) on every push is the single source of truth; `ci-and-deploy.yaml`
> no longer re-runs its own kind validation — it promotes to prod via
> `workflow_run`, only after `deploy.yaml` succeeds on `main`.
