#!/usr/bin/env bash
# scripts/seal-prod-secrets.sh — seal the production SealedSecrets from values
# supplied via environment variables.
#
# Real values are read from the environment at run time and NEVER committed:
# only the encrypted *.sealedsecret.yaml output is written, into
# deploy/sealed-secrets/prod/. If any required variable is unset/empty the
# script aborts BEFORE sealing anything.
#
# Required environment variables (set these in your shell first):
#   POSTGRES_USER  POSTGRES_PASSWORD  POSTGRES_DB
#   KEYCLOAK_ADMIN_USERNAME  KEYCLOAK_ADMIN_PASSWORD
#   GRAFANA_ADMIN_USER  GRAFANA_ADMIN_PASSWORD
#   LITELLM_MASTER_KEY  ANTHROPIC_API_KEY  OPENAI_API_KEY
#   S3_ACCESS_KEY_ID  S3_SECRET_ACCESS_KEY  S3_REGION  S3_ENDPOINT_URL
#   S3_IDENTITIES_FILE   (path to the SeaweedFS S3 identities JSON)
#
# Usage:
#   export ANTHROPIC_API_KEY=...   # …and the rest above
#   scripts/seal-prod-secrets.sh
#
# Env knobs:
#   SKIP_CERT_CHECK=1  skip verifying the committed cert against the live controller
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

OUT_REL="prod"                                  # relative to deploy/sealed-secrets (deploy.sh --seal OUT)
OUT_DIR="deploy/sealed-secrets/$OUT_REL"
CERT="secrets/prod/sealed-secrets-public-cert.pem"

red() { printf '\033[31m%s\033[0m\n' "$*" >&2; }
grn() { printf '\033[32m%s\033[0m\n' "$*"; }

# ---- 1. require all secret-bearing env vars (names only — values stay in env) ----
REQUIRED_VARS=(
  POSTGRES_USER POSTGRES_PASSWORD POSTGRES_DB
  KEYCLOAK_ADMIN_USERNAME KEYCLOAK_ADMIN_PASSWORD
  GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD
  LITELLM_MASTER_KEY ANTHROPIC_API_KEY OPENAI_API_KEY
  S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY S3_REGION S3_ENDPOINT_URL
  S3_IDENTITIES_FILE
)
missing=()
for v in "${REQUIRED_VARS[@]}"; do
  [ -n "${!v:-}" ] || missing+=("$v")
done
if [ "${#missing[@]}" -gt 0 ]; then
  red "Missing required environment variable(s) — nothing was sealed:"
  for v in "${missing[@]}"; do red "  - $v"; done
  red "Set them (e.g. export ANTHROPIC_API_KEY=...) and re-run."
  exit 1
fi
if [ ! -r "$S3_IDENTITIES_FILE" ]; then
  red "S3_IDENTITIES_FILE='$S3_IDENTITIES_FILE' is not a readable file."
  exit 1
fi
[ -f "$CERT" ] || { red "prod cert not found: $CERT"; exit 1; }
command -v kubeseal >/dev/null 2>&1 || { red "kubeseal not installed."; exit 1; }

mkdir -p "$OUT_DIR"

# ---- 2. confirm the committed cert matches the live controller (best-effort) ----
if [ "${SKIP_CERT_CHECK:-0}" != "1" ]; then
  live="$(kubeseal --controller-name sealed-secrets-controller \
                   --controller-namespace kube-system --fetch-cert 2>/dev/null || true)"
  if [ -n "$live" ]; then
    if diff -q <(printf '%s' "$live") "$CERT" >/dev/null 2>&1; then
      grn "prod cert matches the live controller"
    else
      red "ABORT: committed cert ($CERT) does not match the live controller."
      red "SealedSecrets sealed with it would NOT decrypt in prod."
      red "Fix the controller/cert, or re-run with SKIP_CERT_CHECK=1 to seal anyway."
      exit 1
    fi
  else
    grn "(no cluster access to fetch the live cert — sealing against committed $CERT)"
  fi
fi

# ---- 3. seal each secret (values from env; only encrypted output is written) ----
seal_one() {  # name  out-filename  <kubectl create secret args…>
  local name="$1" out="$2"; shift 2
  grn "sealing $name -> $OUT_DIR/$out"
  ./deploy.sh --seal --env prod "$name" "$OUT_REL/$out" "$@"
}

seal_one agentic-enterprise-postgres agentic-enterprise-postgres.sealedsecret.yaml \
  --from-literal=POSTGRES_USER="$POSTGRES_USER" \
  --from-literal=POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  --from-literal=POSTGRES_DB="$POSTGRES_DB"

seal_one agentic-enterprise-keycloak-admin agentic-enterprise-keycloak-admin.sealedsecret.yaml \
  --from-literal=username="$KEYCLOAK_ADMIN_USERNAME" \
  --from-literal=password="$KEYCLOAK_ADMIN_PASSWORD"

seal_one agentic-enterprise-grafana-admin agentic-enterprise-grafana-admin.sealedsecret.yaml \
  --from-literal=admin-user="$GRAFANA_ADMIN_USER" \
  --from-literal=admin-password="$GRAFANA_ADMIN_PASSWORD"

seal_one agentic-enterprise-litellm-secrets agentic-enterprise-litellm-secrets.sealedsecret.yaml \
  --from-literal=masterkey="$LITELLM_MASTER_KEY" \
  --from-literal=anthropic-api-key="$ANTHROPIC_API_KEY" \
  --from-literal=openai-api-key="$OPENAI_API_KEY"

seal_one agentic-enterprise-s3-creds agentic-enterprise-s3-creds.sealedsecret.yaml \
  --from-literal=AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY_ID" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$S3_SECRET_ACCESS_KEY" \
  --from-literal=AWS_DEFAULT_REGION="$S3_REGION" \
  --from-literal=S3_ENDPOINT_URL="$S3_ENDPOINT_URL" \
  --from-file=seaweedfs_s3_config="$S3_IDENTITIES_FILE"

echo
grn "Sealed 5 secrets into $OUT_DIR/. Review, then commit ONLY the encrypted output:"
echo "  scripts/check-no-raw-secrets.sh && git add $OUT_DIR/*.sealedsecret.yaml"
