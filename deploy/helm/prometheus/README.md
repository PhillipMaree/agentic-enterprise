# agentic-enterprise-prometheus

Umbrella chart over `prometheus-community/prometheus`. Strips out the
default sidekick charts (alertmanager, kube-state-metrics, node-exporter,
pushgateway) — for dev/kind they're noise.

## Install

```bash
helm dependency update deploy/helm/prometheus
helm install agentic-enterprise-prometheus deploy/helm/prometheus \
  --namespace agentic-enterprise --create-namespace \
  --wait --timeout 5m
```

Internal service: `agentic-enterprise-prometheus-server:80` (the upstream chart
exposes Prometheus on port 80 by default).

## Uninstall

```bash
helm uninstall agentic-enterprise-prometheus -n agentic-enterprise
kubectl delete pvc -l app.kubernetes.io/instance=agentic-enterprise-prometheus -n agentic-enterprise
```
