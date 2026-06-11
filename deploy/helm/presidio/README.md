# agentic-enterprise-presidio

Hand-written chart (no widely-maintained upstream Helm chart for the
Presidio analyzer + anonymizer pair). Both are stateless HTTP services on
container port 3000; this chart emits two Deployments and two Services.

## Install

```bash
helm install agentic-enterprise-presidio deploy/helm/presidio \
  --namespace agentic-enterprise --create-namespace \
  --wait --timeout 5m
```

## Reach the services

Used internally by `agentic-enterprise-litellm` — no host port-forward needed
under normal operation.

- `agentic-enterprise-presidio-analyzer:3000`
- `agentic-enterprise-presidio-anonymizer:3000`

## Uninstall

```bash
helm uninstall agentic-enterprise-presidio -n agentic-enterprise
```
