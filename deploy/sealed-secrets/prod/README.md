# deploy/sealed-secrets/prod

`SealedSecret` manifests for the **production** k3s cluster. Each is encrypted
against the **prod** public cert
([../../../secrets/prod/sealed-secrets-public-cert.pem](../../../secrets/prod/sealed-secrets-public-cert.pem))
and decrypts — only inside the prod cluster, whose controller holds the matching
prod private key — into a `Secret` in the `agentic-enterprise` namespace.

`scripts/deploy-prod.sh` applies everything in this directory before the Helm
charts install, then waits for the derived Secrets.

## Rules

- **Never commit raw secrets.** Only `kind: SealedSecret` YAML belongs here — no
  `kind: Secret`, no `.env`, no private keys, no literal values, no kubeconfigs.
- The values inside a `SealedSecret` are encrypted; the **key names** are
  cleartext. That's expected — list the keys here, never the values.
- `scripts/check-no-raw-secrets.sh` (run in CI) fails the build if a raw
  `kind: Secret` ever lands in this tree.

## Required secrets (names + keys)

Derived from the charts and the committed dev SealedSecrets — do not change names
without updating the charts and `SEALED_SECRET_NAMES` in `deploy.sh`.

### `agentic-enterprise-postgres`  — Postgres (litellm, mlflow, keycloak share it)
- `POSTGRES_USER`
- `POSTGRES_PASSWORD`
- `POSTGRES_DB`

### `agentic-enterprise-keycloak-admin`  — Keycloak bootstrap admin
- `username`
- `password`

### `agentic-enterprise-grafana-admin`  — Grafana admin
- `admin-user`
- `admin-password`

### `agentic-enterprise-litellm-secrets`  — LiteLLM master key + real provider keys
- `masterkey`
- `anthropic-api-key`
- `openai-api-key`

### `agentic-enterprise-s3-creds`  — SeaweedFS S3 creds (seaweedfs, tempo, loki, mlflow, bucket-init)
- `AWS_ACCESS_KEY_ID`
- `AWS_SECRET_ACCESS_KEY`
- `AWS_DEFAULT_REGION`
- `S3_ENDPOINT_URL`
- `seaweedfs_s3_config`  (the SeaweedFS S3 identities JSON — same shape as
  [config/seaweedfs/s3-identities.json](../../../config/seaweedfs/s3-identities.json))

## How to (re)seal — run locally, real values never leave your machine

> **Fast path: seal all five at once.** To create every Secret in one go, use the
> two helper scripts instead of the per-secret commands below:
> `scripts/gen-prod-secrets.sh` mints the random internal values + S3 identities
> JSON into an out-of-repo env file, then (with `ANTHROPIC_API_KEY` /
> `OPENAI_API_KEY` exported) `set -a; source ~/.agentic-enterprise-prod.env; set +a`
> and run `scripts/seal-prod-secrets.sh`. The per-secret commands below are for
> rotating or re-sealing a single secret.

`./deploy.sh --seal --env prod <secret-name> prod/<secret-name>.sealedsecret.yaml --from-literal=KEY=VALUE …`
seals against the committed prod cert and writes the encrypted manifest here.
Replace every `<…>` placeholder with a real value at run time — do **not** paste
real values into chat or commit them.

```bash
mkdir -p deploy/sealed-secrets/prod

./deploy.sh --seal --env prod agentic-enterprise-postgres \
  prod/agentic-enterprise-postgres.sealedsecret.yaml \
  --from-literal=POSTGRES_USER='<POSTGRES_USER>' \
  --from-literal=POSTGRES_PASSWORD='<POSTGRES_PASSWORD>' \
  --from-literal=POSTGRES_DB='<POSTGRES_DB>'

./deploy.sh --seal --env prod agentic-enterprise-keycloak-admin \
  prod/agentic-enterprise-keycloak-admin.sealedsecret.yaml \
  --from-literal=username='<KEYCLOAK_ADMIN_USER>' \
  --from-literal=password='<KEYCLOAK_ADMIN_PASSWORD>'

./deploy.sh --seal --env prod agentic-enterprise-grafana-admin \
  prod/agentic-enterprise-grafana-admin.sealedsecret.yaml \
  --from-literal=admin-user='<GRAFANA_ADMIN_USER>' \
  --from-literal=admin-password='<GRAFANA_ADMIN_PASSWORD>'

./deploy.sh --seal --env prod agentic-enterprise-litellm-secrets \
  prod/agentic-enterprise-litellm-secrets.sealedsecret.yaml \
  --from-literal=masterkey='<LITELLM_MASTER_KEY>' \
  --from-literal=anthropic-api-key='<ANTHROPIC_API_KEY>' \
  --from-literal=openai-api-key='<OPENAI_API_KEY>'

# seaweedfs_s3_config is a JSON file (the S3 identities). Use --from-file:
./deploy.sh --seal --env prod agentic-enterprise-s3-creds \
  prod/agentic-enterprise-s3-creds.sealedsecret.yaml \
  --from-literal=AWS_ACCESS_KEY_ID='<S3_ACCESS_KEY>' \
  --from-literal=AWS_SECRET_ACCESS_KEY='<S3_SECRET_KEY>' \
  --from-literal=AWS_DEFAULT_REGION='<S3_REGION>' \
  --from-literal=S3_ENDPOINT_URL='<S3_ENDPOINT_URL>' \
  --from-file=seaweedfs_s3_config=/path/to/your/prod-s3-identities.json
```

Then commit **only** the generated `*.sealedsecret.yaml` files (the encrypted
output) — never the inputs.

## Cert must match the prod controller

`./deploy.sh --seal --env prod` encrypts with the committed
`secrets/prod/sealed-secrets-public-cert.pem`. Those manifests decrypt **only**
if the prod controller holds the matching private key. Verify the committed cert
matches the live controller before sealing:

```bash
export KUBECONFIG="$HOME/.kube/config"   # the prod k3s kubeconfig
kubeseal --controller-name sealed-secrets-controller \
         --controller-namespace kube-system --fetch-cert \
  | diff - secrets/prod/sealed-secrets-public-cert.pem && echo "cert matches"
```

If they differ, the controller was bootstrapped with a different key — either
re-bootstrap it with the keypair behind the committed cert, or replace the
committed cert with the fetched one and re-seal.
