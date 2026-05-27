# platform-tempo

Umbrella chart over `grafana/tempo` (single-binary mode). Stores trace
blocks in SeaweedFS S3 (`tempo-traces` bucket).

## Prereqs

- `platform-seaweedfs` installed (Tempo writes to its S3 endpoint).
- The `tempo-traces` bucket exists (created by the seaweedfs-init job).

## Install

```bash
helm dependency update deploy/helm/tempo
helm install platform-tempo deploy/helm/tempo \
  --namespace agentic-platform --create-namespace \
  --wait --timeout 5m
```

## Reach the service

Tempo's query API is exposed inside the cluster on port 3200. Grafana
queries it directly via the auto-provisioned datasource.

## Uninstall

```bash
helm uninstall platform-tempo -n agentic-platform
kubectl delete pvc -l app.kubernetes.io/instance=platform-tempo -n agentic-platform
```
