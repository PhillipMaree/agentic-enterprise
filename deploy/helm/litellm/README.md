# agentic-enterprise-litellm

Umbrella chart over `berriai/litellm-helm` (pulled from
`oci://ghcr.io/berriai/litellm-helm`).

PII masking via Presidio is wired up — every prompt goes through
`agentic-enterprise-presidio-analyzer` + `agentic-enterprise-presidio-anonymizer` before
hitting the upstream provider.

## Prereqs

- `agentic-enterprise-postgres` + `agentic-enterprise-redis` + `agentic-enterprise-presidio` + `agentic-enterprise-otel-collector` installed.
- The `litellm` database exists in agentic-enterprise-postgres (run once):
  ```bash
  kubectl -n agentic-enterprise exec deploy/agentic-enterprise-postgres -- \
    psql -U postgres -c "CREATE DATABASE litellm"
  ```
- `agentic-enterprise-litellm-secrets` (key `masterkey`) — decrypted from the committed
  SealedSecret [deploy/sealed-secrets/litellm.sealed.yaml](../../sealed-secrets/litellm.sealed.yaml)
  by the Sealed Secrets controller (`deploy.sh` does this automatically). The
  kind path is **mock-only**, so no provider keys live in the cluster — real
  Anthropic/OpenAI keys are prod-only. See [docs/SECURITY.md](../../../docs/SECURITY.md).

## Install

```bash
helm dependency update deploy/helm/litellm
helm install agentic-enterprise-litellm deploy/helm/litellm \
  --namespace agentic-enterprise --create-namespace \
  --wait --timeout 5m
```

## Reach the proxy

```bash
kubectl -n agentic-enterprise port-forward svc/agentic-enterprise-litellm 4000:4000
# OpenAI-compatible: http://localhost:4000/v1/chat/completions
# UI:                http://localhost:4000/ui
```

## Uninstall

```bash
helm uninstall agentic-enterprise-litellm -n agentic-enterprise
# agentic-enterprise-litellm-secrets is owned by its SealedSecret; remove both if desired:
kubectl -n agentic-enterprise delete sealedsecret,secret agentic-enterprise-litellm-secrets
```
