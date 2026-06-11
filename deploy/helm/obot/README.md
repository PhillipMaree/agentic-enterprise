# agentic-enterprise-obot

Thin wrapper around the upstream `obot/obot` chart from
`https://charts.obot.ai`. **Not an umbrella chart** — Helm 3.21's
`CheckDependencies` rejects obot when used as a subchart dependency
(works for every other chart in this repo). We work around it by
installing the upstream chart directly with this directory's
`values.yaml` as a `-f` override.

Obot is k8s-native: it deploys each configured MCP server as its own
Deployment in a sibling namespace (`<release>-mcp`, i.e.
`agentic-enterprise-obot-mcp` here).

## Install

```bash
./deploy.sh --up obot
```

(or manually:)

```bash
helm upgrade --install agentic-enterprise-obot \
  --repo https://charts.obot.ai obot \
  --version v0.21.1 \
  --namespace agentic-enterprise --create-namespace \
  -f deploy/helm/obot/values.yaml \
  --wait --timeout 8m
```

## Reach the UI

```bash
kubectl -n agentic-enterprise port-forward svc/agentic-enterprise-obot 8080:8080
# open http://localhost:8080
```

## Adding MCP servers

After install, use the Obot UI or its registry API to add MCP servers.
Each new server becomes a Deployment under `agentic-enterprise-obot-mcp`.

## Uninstall

```bash
./deploy.sh --down obot
```
