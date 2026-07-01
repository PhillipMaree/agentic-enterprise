# enterprise-platform-keycloak

Keycloak IdP for the `enterprise-platform` namespace. Runs in **dev mode** (H2,
ephemeral) and imports the `agentic-dev` realm on startup from
[realm-agentic-dev.json](realm-agentic-dev.json).

The realm defines the clients, scopes, audience/tenant mappers and two demo users
that the `agentic-proptech` app relies on:

| Client | Type | Purpose |
|---|---|---|
| `proptech-frontend` | confidential (PKCE) | browser login; mints user tokens with `aud: agent-orchestrator` |
| `agent-orchestrator` | confidential + service account + token-exchange | validates user token, exchanges → `agent-discovery` |
| `agent-discovery` | confidential + service account + token-exchange | validates, exchanges → `mcp-proptech` |
| `mcp-proptech` | confidential (resource server) | validates `aud: mcp-proptech` + `building:read` |

Demo users (password `password`): **alice** (`tenant=acme`), **bob** (`tenant=globex`).
The `tenant` claim is what scopes the FalkorDB graph — not any header.

## Install

```bash
helm -n enterprise-platform upgrade --install enterprise-platform-keycloak deploy/helm/keycloak --wait
```

The Service is `ClusterIP` by default (access via `kubectl port-forward`) — a
LoadBalancer would hang `helm --wait` on a plain kind cluster with no LB provider.
For browser PKCE via cloud-provider-kind, opt in:

```bash
helm -n enterprise-platform upgrade --install enterprise-platform-keycloak deploy/helm/keycloak --wait \
  --set service.type=LoadBalancer --set hostname=http://<external-url>
```

so the token `iss` matches what the browser and the in-cluster validators use.

## Caveats (dev-only)

- Dev mode uses H2 — state is lost on pod restart (realm re-imports). For a durable
  setup, switch to `start` with `KC_DB=postgres` against `enterprise-platform-postgres` and a
  bootstrapped `keycloak` database.
- **Token exchange**: started with `--features=token-exchange` and each agent client
  has `standard.token.exchange.enabled=true`. Depending on the Keycloak point
  release you may need to grant the requesting client permission to exchange to the
  target audience once via the admin console (Clients → agent-* → Permissions) or
  `kcadm`. The realm import sets the toggles; fine-grained exchange permissions are
  the one thing that can need a manual confirm.
