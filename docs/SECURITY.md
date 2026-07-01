# Security posture (dev-only)

This is a **local development stack**. Auth is off or set to dev
defaults; nothing here is hardened for a shared or production cluster. This
document explains how secrets are handled so the patterns translate to prod
with a key swap.

## Kubernetes: Sealed Secrets

All stack credentials on the kind/Helm path are managed with
[Bitnami Sealed Secrets](https://github.com/bitnami-labs/sealed-secrets):

```
.env / literals  →  kubectl create secret --dry-run  →  kubeseal --cert
   →  committed SealedSecret YAML  →  controller decrypts  →  Kubernetes Secret
```

- The controller runs in `kube-system` (chart `sealed-secrets@2.17.9` ==
  controller `0.33.1`, matched to the `kubeseal` CLI).
- Committed `SealedSecret`s live in [`deploy/sealed-secrets/`](../deploy/sealed-secrets/)
  and decrypt into the `enterprise-platform-*` Secrets the charts consume.
- `deploy.sh` applies the dev sealing key, installs the controller, waits for
  it to be Ready, applies the SealedSecrets, and waits for the derived Secrets
  — all before any chart that consumes them.

### The committed dev sealing key is PUBLIC

`secrets/dev/sealed-secrets-dev-keypair.yaml` contains the controller's
**private** key. It is committed on purpose so `deploy.sh` and CI reproduce the
same controller key in every fresh, ephemeral kind cluster — otherwise a
committed `SealedSecret` (encrypted against one cluster's key) would not
decrypt in the next.

**Consequence:** anyone with this repo can decrypt every committed dev
`SealedSecret`. That is acceptable *only* because they encrypt known dev
defaults (`password`, `admin`, a dev S3 keypair, the public dev LiteLLM
masterkey). It is **not** real at-rest protection. The value is:

1. no plaintext credentials in `values.yaml` / templates / pod env, and
2. the controller pattern is wired end-to-end, so prod differs only by key.

### Per-environment keys

```
secrets/
  dev/   sealed-secrets-public-cert.pem      (committed)
         sealed-secrets-dev-keypair.yaml     (committed — dev private key, see above)
  prod/  sealed-secrets-public-cert.pem      (committed — PUBLIC cert only)
```

The **prod private key is never committed**. The prod controller owns its own
keypair; only the public cert is exported for devs/CI to seal prod secrets. The
private key stays in the prod cluster, backed to a secure store (cloud KMS,
secret manager, encrypted backup, or restricted ops vault).

### Authoring / rotating secrets

Seal from a local `.env` against a public cert (no running cluster needed):

```bash
./deploy.sh --seal enterprise-platform-postgres postgres.sealed.yaml \
  --from-literal=POSTGRES_USER=postgres \
  --from-literal=POSTGRES_PASSWORD=password \
  --from-literal=POSTGRES_DB=mlflow
# prod: ./deploy.sh --seal --env prod NAME OUT --from-...
```

To **rotate**: regenerate the keypair, reseal every manifest against the new
cert, recommit. A **prod** `SealedSecret` must be sealed against the prod cert
— never the dev cert.

## Provider keys (Anthropic / OpenAI) — never in the dev cluster or git

A Kubernetes Secret is readable in-cluster, so real provider keys are kept out
of the kind cluster entirely:

- The **kind/dev path is mock-only**: LiteLLM runs with
  `LITELLM_USE_MOCK_MODELS=1` (CI sets this), and the committed
  `litellm.sealed.yaml` carries only the masterkey — no provider keys.
- **Real provider keys are prod-only**: sealed against the prod cert
  (`--seal --env prod`), applied only to the prod cluster, decrypted only by
  the prod controller. They are never committed sealed against the public dev
  cert.
- **Local Docker Compose** may use real keys from your own gitignored `.env`
  (your machine, not a shared cluster, not git). LiteLLM has no `_FILE`
  support, so these stay env-based.

## Docker Compose: file-based secrets

Admin passwords are file-based secrets under [`secrets/compose/`](../secrets/compose/)
(gitignored; only `*.example` committed), mounted at `/run/secrets/<name>` and
read via `*_FILE` env vars:

| Service | Env var | Image support |
|---|---|---|
| postgres | `POSTGRES_PASSWORD_FILE` | native |
| keycloak | `KC_BOOTSTRAP_ADMIN_PASSWORD_FILE` | Keycloak 26 (`*_FILE`) |
| grafana | `GF_SECURITY_ADMIN_PASSWORD__FILE` | Grafana (`GF_*__FILE`) |

The Postgres password also appears in `.env` (`POSTGRES_PASSWORD`) because
litellm/mlflow/postgres-init build connection strings from it via env
substitution — keep the `.env` value and `secrets/compose/postgres_password`
in sync.

## What may / may not be committed

**Allowed:** `deploy/sealed-secrets/*.sealed.yaml`; `secrets/dev/*.pem`;
`secrets/dev/sealed-secrets-dev-keypair.yaml` (dev only);
`secrets/prod/*.pem` (public cert only); `secrets/compose/*.example`.

**Never:** `.env` / `.env.*`; unsealed `Secret` manifests; the prod private
key; real provider keys; real S3 keys; any production credential.

## Production

Production must not use the committed dev keypair. Either (1) generate and
rotate its own controller keypair, or (2) use an external secret manager (e.g.
External Secrets Operator) with a real backend. Enable etcd encryption-at-rest
on the prod API server so the decrypted Secrets are also encrypted in storage.
