# enterprise-platform-loki

Umbrella chart over `grafana/loki` in single-binary mode (`SingleBinary`).
Stores chunks + tsdb index in SeaweedFS S3 (`loki-logs` bucket).

## Prereqs

- `enterprise-platform-seaweedfs` installed.
- The `loki-logs` bucket exists (created by the seaweedfs-init job).

## Install

```bash
helm dependency update deploy/helm/loki
helm install enterprise-platform-loki deploy/helm/loki \
  --namespace enterprise-platform --create-namespace \
  --wait --timeout 5m
```

Push endpoint inside the cluster: `http://enterprise-platform-loki:3100/loki/api/v1/push`.

## Uninstall

```bash
helm uninstall enterprise-platform-loki -n enterprise-platform
kubectl delete pvc -l app.kubernetes.io/instance=enterprise-platform-loki -n enterprise-platform
```
