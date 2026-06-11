# agentic-enterprise-falkordb

Minimal Helm chart that deploys **[FalkorDB](https://www.falkordb.com/)**
(`falkordb/falkordb:latest`) into the `agentic-enterprise` namespace.

FalkorDB is a Redis-protocol graph database — drop-in replacement for the
deprecated RedisGraph module. It serves the property-graph workload for
agentic GraphRAG / KG flows.

> Dev-only. No auth, single replica. Do not install in a shared cluster.

## Install

```bash
helm install agentic-enterprise-falkordb deploy/helm/falkordb \
  --namespace agentic-enterprise --create-namespace \
  --wait --timeout 5m
```

## Ports

| Port | Purpose |
| ---- | ------- |
| 6379 | Redis protocol (graph commands via `redis-cli`) |
| 3000 | FalkorDB Browser web UI |

## Reach the service

```bash
# Redis protocol
kubectl -n agentic-enterprise port-forward svc/agentic-enterprise-falkordb 6379:6379
redis-cli -h 127.0.0.1 -p 6379 GRAPH.QUERY mygraph "CREATE (n:Person {name:'Alice'})"
redis-cli -h 127.0.0.1 -p 6379 GRAPH.LIST

# Browser UI
kubectl -n agentic-enterprise port-forward svc/agentic-enterprise-falkordb 3000:3000
# open http://localhost:3000
```

If you already deployed `agentic-enterprise-redis` and forwarded `6379` locally, pick
a different host port for FalkorDB, e.g.
`kubectl -n agentic-enterprise port-forward svc/agentic-enterprise-falkordb 6380:6379`.

## Uninstall

```bash
helm uninstall agentic-enterprise-falkordb -n agentic-enterprise
kubectl delete pvc agentic-enterprise-falkordb -n agentic-enterprise
```
