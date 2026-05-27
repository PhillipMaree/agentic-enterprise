# platform-mcp-gateway

Hand-written chart (no upstream chart for `docker/mcp-gateway`).
Single-replica stateless deployment. Config from values mirrors
[config/mcp-gateway/config.yaml](../../../config/mcp-gateway/config.yaml).

## Install

```bash
helm install platform-mcp-gateway deploy/helm/mcp-gateway \
  --namespace agentic-platform --create-namespace \
  --wait --timeout 5m
```

## Reach the service

```bash
kubectl -n agentic-platform port-forward svc/platform-mcp-gateway 8811:8811
```

## Uninstall

```bash
helm uninstall platform-mcp-gateway -n agentic-platform
```
