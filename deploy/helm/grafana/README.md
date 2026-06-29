# enterprise-platform-grafana

Umbrella chart over `grafana/grafana`. Datasources for Tempo, Loki, and
Prometheus are auto-provisioned with Tempo↔Loki and Tempo↔Metrics
correlations pre-wired (matches [config/grafana/provisioning/datasources/datasources.yaml](../../../config/grafana/provisioning/datasources/datasources.yaml)).

## Install

```bash
helm dependency update deploy/helm/grafana
helm install enterprise-platform-grafana deploy/helm/grafana \
  --namespace enterprise-platform --create-namespace \
  --wait --timeout 5m
```

## Reach the UI

```bash
kubectl -n enterprise-platform port-forward svc/enterprise-platform-grafana 3000:80
# open http://localhost:3000 — admin / change-me (from values.yaml)
```

## Dashboards

Drop dashboard JSON into a ConfigMap labelled `grafana_dashboard=1` and
the sidecar picks it up automatically. See [the chart docs](https://github.com/grafana/helm-charts/tree/main/charts/grafana#sidecar-for-dashboards).

## Uninstall

```bash
helm uninstall enterprise-platform-grafana -n enterprise-platform
kubectl delete pvc -l app.kubernetes.io/instance=enterprise-platform-grafana -n enterprise-platform
```
