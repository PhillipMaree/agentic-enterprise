# agentic-enterprise-tempo

Umbrella chart over `grafana/tempo` (single-binary mode). Stores trace
blocks in SeaweedFS S3 (`tempo-traces` bucket).

## Prereqs

- `agentic-enterprise-seaweedfs` installed (Tempo writes to its S3 endpoint).
- The `tempo-traces` bucket exists (created by the seaweedfs-init job).

## Install

```bash
helm dependency update deploy/helm/tempo
helm install agentic-enterprise-tempo deploy/helm/tempo \
  --namespace agentic-enterprise --create-namespace \
  --wait --timeout 5m
```

## Reach the service

Tempo's query API is exposed inside the cluster on port 3200. Grafana
queries it directly via the auto-provisioned datasource.

## Uninstall

```bash
helm uninstall agentic-enterprise-tempo -n agentic-enterprise
kubectl delete pvc -l app.kubernetes.io/instance=agentic-enterprise-tempo -n agentic-enterprise
```
