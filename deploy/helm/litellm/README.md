# enterprise-platform-litellm

Umbrella chart over `berriai/litellm-helm` (pulled from
`oci://ghcr.io/berriai/litellm-helm`).

PII masking via Presidio is wired up — every prompt goes through
`enterprise-platform-presidio-analyzer` + `enterprise-platform-presidio-anonymizer` before
hitting the upstream provider.

## Prereqs

- `enterprise-platform-postgres` + `enterprise-platform-redis` + `enterprise-platform-presidio` + `enterprise-platform-otel-collector` installed.
- The `litellm` database exists in enterprise-platform-postgres (run once):
  ```bash
  kubectl -n enterprise-platform exec deploy/enterprise-platform-postgres -- \
    psql -U postgres -c "CREATE DATABASE litellm"
  ```
- `enterprise-platform-litellm-secrets` (key `masterkey`) — decrypted from the committed
  SealedSecret [deploy/sealed-secrets/litellm.sealed.yaml](../../sealed-secrets/litellm.sealed.yaml)
  by the Sealed Secrets controller (`deploy.sh` does this automatically). The
  kind path is **mock-only**, so no provider keys live in the cluster — real
  Anthropic/OpenAI keys are prod-only. See [docs/SECURITY.md](../../../docs/SECURITY.md).

## Install

```bash
helm dependency update deploy/helm/litellm
helm install enterprise-platform-litellm deploy/helm/litellm \
  --namespace enterprise-platform --create-namespace \
  --wait --timeout 5m
```

## Reach the proxy

```bash
kubectl -n enterprise-platform port-forward svc/enterprise-platform-litellm 4000:4000
# OpenAI-compatible: http://localhost:4000/v1/chat/completions
# UI:                http://localhost:4000/ui
```

## Uninstall

```bash
helm uninstall enterprise-platform-litellm -n enterprise-platform
# enterprise-platform-litellm-secrets is owned by its SealedSecret; remove both if desired:
kubectl -n enterprise-platform delete sealedsecret,secret enterprise-platform-litellm-secrets
```
