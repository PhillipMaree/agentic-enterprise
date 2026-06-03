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
- `platform-litellm-secrets` (key `masterkey`) — decrypted from the committed
  SealedSecret [deploy/sealed-secrets/litellm.sealed.yaml](../../sealed-secrets/litellm.sealed.yaml)
  by the Sealed Secrets controller (`deploy.sh` does this automatically). The
  kind path is **mock-only**, so no provider keys live in the cluster — real
  Anthropic/OpenAI keys are prod-only. See [docs/SECURITY.md](../../../docs/SECURITY.md).

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
# platform-litellm-secrets is owned by its SealedSecret; remove both if desired:
kubectl -n agentic-platform delete sealedsecret,secret platform-litellm-secrets
```
