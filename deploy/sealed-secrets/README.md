# deploy/sealed-secrets

Committed `SealedSecret` manifests for the stack's dev credentials. Each is
encrypted against the **dev** public cert
([secrets/dev/sealed-secrets-public-cert.pem](../../secrets/dev/sealed-secrets-public-cert.pem))
and decrypts — only inside a cluster whose controller holds the matching dev
key — into a normal `Secret` in the `agentic-enterprise` namespace.

`deploy.sh` applies these after the controller is Ready (`apply_sealed_secrets`),
then waits for the derived Secrets before installing the charts that consume
them.

| Manifest | → Secret | Keys | Consumed by |
|---|---|---|---|
| `postgres.sealed.yaml` | `agentic-enterprise-postgres` | `POSTGRES_USER/PASSWORD/DB` | postgres (`envFrom`), litellm (`db.secret`) |
| `keycloak.sealed.yaml` | `agentic-enterprise-keycloak-admin` | `username`, `password` | keycloak (`secretKeyRef`) |
| `grafana.sealed.yaml` | `agentic-enterprise-grafana-admin` | `admin-user`, `admin-password` | grafana (`admin.existingSecret`) |
| `litellm.sealed.yaml` | `agentic-enterprise-litellm-secrets` | `masterkey` | litellm (`masterkeySecretName`) |
| `s3.sealed.yaml` | `agentic-enterprise-s3-creds` | `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`, `S3_ENDPOINT_URL`, `seaweedfs_s3_config` | seaweedfs (`existingConfigSecret`), mlflow/tempo/loki (`envFrom`), bucket-bootstrap Job |

**These hold dev defaults only.** Real provider keys (Anthropic/OpenAI) are never
here — see [docs/SECURITY.md](../../docs/SECURITY.md). To (re)author a sealed
secret from a local `.env`, use `./deploy.sh --seal <name> <output> --from-...`
(seals against the dev cert; `--env prod` uses the prod cert).
