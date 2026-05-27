# platform-prometheus

Umbrella chart over `prometheus-community/prometheus`. Strips out the
default sidekick charts (alertmanager, kube-state-metrics, node-exporter,
pushgateway) — for dev/kind they're noise.

## Install

```bash
helm dependency update deploy/helm/prometheus
helm install platform-prometheus deploy/helm/prometheus \
  --namespace agentic-platform --create-namespace \
  --wait --timeout 5m
```

Internal service: `platform-prometheus-server:80` (the upstream chart
exposes Prometheus on port 80 by default).

## Uninstall

```bash
helm uninstall platform-prometheus -n agentic-platform
kubectl delete pvc -l app.kubernetes.io/instance=platform-prometheus -n agentic-platform
```
