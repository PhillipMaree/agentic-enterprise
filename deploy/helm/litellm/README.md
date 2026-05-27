# platform-litellm

Umbrella chart over `berriai/litellm-helm` (pulled from
`oci://ghcr.io/berriai/litellm-helm`).

PII masking via Presidio is wired up — every prompt goes through
`platform-presidio-analyzer` + `platform-presidio-anonymizer` before
hitting the upstream provider.

## Prereqs

- `platform-postgres` + `platform-redis` + `platform-presidio` + `platform-otel-collector` installed.
- The `litellm` database exists in platform-postgres (run once):
  ```bash
  kubectl -n agentic-platform exec deploy/platform-postgres -- \
    psql -U postgres -c "CREATE DATABASE litellm"
  ```
- Secret with master key + provider keys:
  ```bash
  kubectl -n agentic-platform create secret generic platform-litellm-secrets \
    --from-literal=masterkey="$(openssl rand -hex 32)" \
    --from-literal=anthropic-api-key="$ANTHROPIC_API_KEY" \
    --from-literal=openai-api-key="$OPENAI_API_KEY"
  ```

## Install

```bash
helm dependency update deploy/helm/litellm
helm install platform-litellm deploy/helm/litellm \
  --namespace agentic-platform --create-namespace \
  --wait --timeout 5m
```

## Reach the proxy

```bash
kubectl -n agentic-platform port-forward svc/platform-litellm 4000:4000
# OpenAI-compatible: http://localhost:4000/v1/chat/completions
# UI:                http://localhost:4000/ui
```

## Uninstall

```bash
helm uninstall platform-litellm -n agentic-platform
kubectl -n agentic-platform delete secret platform-litellm-secrets
```
