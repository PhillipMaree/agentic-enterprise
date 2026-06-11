# agentic-enterprise-seaweedfs

Umbrella Helm chart that deploys [SeaweedFS](https://github.com/seaweedfs/seaweedfs)
in `allInOne` mode with the S3 gateway enabled, for the `agentic-enterprise` namespace.

Rendering is delegated to the upstream `seaweedfs/seaweedfs` chart; this chart
only ships `values.yaml` overrides tuned for local dev on kind.

> Dev-only. S3 auth is disabled. Do not install this chart in any shared
> cluster as-is.

## Prerequisites

- A running Kubernetes cluster (this repo's [kind config](../../kind/kind-config.yaml)).
- Helm 3.15+.

## Install

```bash
helm dependency update deploy/helm/seaweedfs
helm install agentic-enterprise-seaweedfs deploy/helm/seaweedfs \
  --namespace agentic-enterprise --create-namespace \
  --wait --timeout 5m
```

## Default ports (cluster-internal)

| Port | Purpose |
| ---- | ------- |
| 9333 | Master |
| 8080 | Volume |
| 8888 | Filer  |
| 8333 | S3 gateway |

The chart emits a single `Deployment` and one `Service` named
`agentic-enterprise-seaweedfs-all-in-one` exposing all the ports above.

Port-forward the S3 endpoint to your host:

```bash
kubectl -n agentic-enterprise port-forward svc/agentic-enterprise-seaweedfs-all-in-one 8333:8333
```

## Enabling S3 auth

For shared environments you must enable authentication. Create a secret with
the SeaweedFS [identities config](https://github.com/seaweedfs/seaweedfs/wiki/Amazon-S3-API#authentication)
and set:

```yaml
seaweedfs:
  allInOne:
    s3:
      enableAuth: true
      existingConfigSecret: <secret-name>
```

## Uninstall

```bash
helm uninstall agentic-enterprise-seaweedfs -n agentic-enterprise
kubectl delete pvc -n agentic-enterprise -l app.kubernetes.io/instance=agentic-enterprise-seaweedfs
```
