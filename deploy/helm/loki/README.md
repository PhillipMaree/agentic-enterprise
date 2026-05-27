# platform-loki

Umbrella chart over `grafana/loki` in single-binary mode (`SingleBinary`).
Stores chunks + tsdb index in SeaweedFS S3 (`loki-logs` bucket).

## Prereqs

- `platform-seaweedfs` installed.
- The `loki-logs` bucket exists (created by the seaweedfs-init job).

## Install

```bash
helm dependency update deploy/helm/loki
helm install platform-loki deploy/helm/loki \
  --namespace agentic-platform --create-namespace \
  --wait --timeout 5m
```

Push endpoint inside the cluster: `http://platform-loki:3100/loki/api/v1/push`.

## Uninstall

```bash
helm uninstall platform-loki -n agentic-platform
kubectl delete pvc -l app.kubernetes.io/instance=platform-loki -n agentic-platform
```
