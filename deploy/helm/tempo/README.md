# enterprise-platform-tempo

Umbrella chart over `grafana/tempo` (single-binary mode). Stores trace
blocks in SeaweedFS S3 (`tempo-traces` bucket).

## Prereqs

- `enterprise-platform-seaweedfs` installed (Tempo writes to its S3 endpoint).
- The `tempo-traces` bucket exists (created by the seaweedfs-init job).

## Install

```bash
helm dependency update deploy/helm/tempo
helm install enterprise-platform-tempo deploy/helm/tempo \
  --namespace enterprise-platform --create-namespace \
  --wait --timeout 5m
```

## Reach the service

Tempo's query API is exposed inside the cluster on port 3200. Grafana
queries it directly via the auto-provisioned datasource.

## Uninstall

```bash
helm uninstall enterprise-platform-tempo -n enterprise-platform
kubectl delete pvc -l app.kubernetes.io/instance=enterprise-platform-tempo -n enterprise-platform
```
