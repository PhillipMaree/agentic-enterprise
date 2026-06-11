# agentic-enterprise-otel-collector

Umbrella chart over `open-telemetry/opentelemetry-collector` running the
**contrib** distribution (needs the `loki` and `prometheusremotewrite`
exporters which the core distribution lacks).

Pipelines mirror [config/otel-collector/config.yaml](../../../config/otel-collector/config.yaml).

## Install

```bash
helm dependency update deploy/helm/otel-collector
helm install agentic-enterprise-otel-collector deploy/helm/otel-collector \
  --namespace agentic-enterprise --create-namespace \
  --wait --timeout 5m
```

Reachable inside the cluster at:

- `agentic-enterprise-otel-collector:4317` (OTLP gRPC)
- `agentic-enterprise-otel-collector:4318` (OTLP HTTP)

## Uninstall

```bash
helm uninstall agentic-enterprise-otel-collector -n agentic-enterprise
```
