# enterprise-platform-otel-collector

Umbrella chart over `open-telemetry/opentelemetry-collector` running the
**contrib** distribution (needs the `loki` and `prometheusremotewrite`
exporters which the core distribution lacks).

Pipelines mirror [config/otel-collector/config.yaml](../../../config/otel-collector/config.yaml).

## Install

```bash
helm dependency update deploy/helm/otel-collector
helm install enterprise-platform-otel-collector deploy/helm/otel-collector \
  --namespace enterprise-platform --create-namespace \
  --wait --timeout 5m
```

Reachable inside the cluster at:

- `enterprise-platform-otel-collector:4317` (OTLP gRPC)
- `enterprise-platform-otel-collector:4318` (OTLP HTTP)

## Uninstall

```bash
helm uninstall enterprise-platform-otel-collector -n enterprise-platform
```
