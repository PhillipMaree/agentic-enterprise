# agentic-enterprise-loki

Umbrella chart over `grafana/loki` in single-binary mode (`SingleBinary`).
Stores chunks + tsdb index in SeaweedFS S3 (`loki-logs` bucket).

## Prereqs

- `agentic-enterprise-seaweedfs` installed.
- The `loki-logs` bucket exists (created by the seaweedfs-init job).

## Install

```bash
helm dependency update deploy/helm/loki
helm install agentic-enterprise-loki deploy/helm/loki \
  --namespace agentic-enterprise --create-namespace \
  --wait --timeout 5m
```

Push endpoint inside the cluster: `http://agentic-enterprise-loki:3100/loki/api/v1/push`.

## Uninstall

```bash
helm uninstall agentic-enterprise-loki -n agentic-enterprise
kubectl delete pvc -l app.kubernetes.io/instance=agentic-enterprise-loki -n agentic-enterprise
```
