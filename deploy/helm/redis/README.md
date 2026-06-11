# agentic-enterprise-redis

Minimal Helm chart that deploys **Redis 8** (`redis:8`) into the
`agentic-enterprise` namespace.

Redis 8 bundles the modules required by the LangGraph Redis checkpointer
natively in the open-source distribution:

- **RedisJSON**
- **RediSearch** (Redis Query Engine)
- **RedisTimeSeries**
- **RedisBloom** / probabilistic data structures

No separate `redis-stack` image or module loading is needed. Verify with
`MODULE LIST` after install.

> Dev-only. No auth, `--protected-mode no`, single replica. Do not install
> in a shared cluster as-is.

## Install

```bash
helm install agentic-enterprise-redis deploy/helm/redis \
  --namespace agentic-enterprise --create-namespace \
  --wait --timeout 5m
```

## Ports

| Port | Purpose |
| ---- | ------- |
| 6379 | Redis protocol (RESP) |

## Reach the service

```bash
kubectl -n agentic-enterprise port-forward svc/agentic-enterprise-redis 6379:6379
redis-cli -h 127.0.0.1 -p 6379 ping
redis-cli -h 127.0.0.1 -p 6379 MODULE LIST
```

The free [RedisInsight desktop client](https://redis.io/insight/) is the
recommended way to browse data — there's no in-cluster UI in this chart.

## Uninstall

```bash
helm uninstall agentic-enterprise-redis -n agentic-enterprise
kubectl delete pvc agentic-enterprise-redis -n agentic-enterprise
```
