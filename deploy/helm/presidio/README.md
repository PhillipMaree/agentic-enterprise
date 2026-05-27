# platform-presidio

Hand-written chart (no widely-maintained upstream Helm chart for the
Presidio analyzer + anonymizer pair). Both are stateless HTTP services on
container port 3000; this chart emits two Deployments and two Services.

## Install

```bash
helm install platform-presidio deploy/helm/presidio \
  --namespace agentic-platform --create-namespace \
  --wait --timeout 5m
```

## Reach the services

Used internally by `platform-litellm` — no host port-forward needed
under normal operation.

- `platform-presidio-analyzer:3000`
- `platform-presidio-anonymizer:3000`

## Uninstall

```bash
helm uninstall platform-presidio -n agentic-platform
```
