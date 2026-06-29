# enterprise-platform-prometheus

Umbrella chart over `prometheus-community/prometheus`. Strips out the
default sidekick charts (alertmanager, kube-state-metrics, node-exporter,
pushgateway) — for dev/kind they're noise.

## Install

```bash
helm dependency update deploy/helm/prometheus
helm install enterprise-platform-prometheus deploy/helm/prometheus \
  --namespace enterprise-platform --create-namespace \
  --wait --timeout 5m
```

Internal service: `enterprise-platform-prometheus-server:80` (the upstream chart
exposes Prometheus on port 80 by default).

## Uninstall

```bash
helm uninstall enterprise-platform-prometheus -n enterprise-platform
kubectl delete pvc -l app.kubernetes.io/instance=enterprise-platform-prometheus -n enterprise-platform
```
