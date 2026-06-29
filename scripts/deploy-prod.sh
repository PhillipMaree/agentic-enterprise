#!/usr/bin/env bash
# scripts/deploy-prod.sh — deploy the enterprise-platform to the PRODUCTION k3s
# cluster.
#
# Runs ON the k3s VM (invoked by the prod GitHub Actions workflow over SSH,
# after it checks out the exact ${{ github.sha }}). This is the prod
# counterpart to ../deploy.sh.
#
# deploy.sh is kind/dev-only: it CREATES a kind cluster and switches to the
# kind-<name> kube-context. This script does NEITHER. It deploys against the
# kube-context already active on the VM (the k3s cluster) and reuses
# deploy.sh's Helm chart definitions + install functions so the two paths
# can't drift — it just swaps the cluster bootstrap and the secrets handling.
#
# Idempotent: every chart goes in via `helm upgrade --install`, so re-running
# reapplies current values without recreating anything.
#
# Env overrides:
#   PROD_NAMESPACE   target namespace (default: enterprise-platform, shared with dev)
#   SEALED_DIR_PROD  dir of prod-sealed SealedSecrets (default: deploy/sealed-secrets/prod)

set -euo pipefail

# Resolve repo root from this script's location (scripts/ is one level down).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# k3s writes its kubeconfig to /etc/rancher/k3s/k3s.yaml; the deploy user copies
# it to ~/.kube/config. Non-interactive SSH shells don't load the profile, so
# pin KUBECONFIG here for every kubectl/helm this script (and deploy.sh) runs.
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"

# Reuse deploy.sh's chart catalog (INSTALL_ORDER, HARD_DEPS, DIRECT_CHARTS),
# its install_chart/helm helpers, the bootstrap jobs, and the sealed-secrets
# helpers — WITHOUT running its kind bootstrap. Sourcing is guarded in
# deploy.sh (BASH_SOURCE check) so its CLI dispatch does not fire here.
# shellcheck source=../deploy.sh
source "$REPO_ROOT/deploy.sh"

# ---------- prod overrides ------------------------------------------------
# Reassign globals that the sourced functions read. install_chart, ensure_ns,
# the bootstrap jobs and the sealed-secrets helpers all reference $NS.
NS="${PROD_NAMESPACE:-enterprise-platform}"
# Prod SealedSecrets are sealed with secrets/prod/sealed-secrets-public-cert.pem
# (the committed ones in $SEALED_DIR are DEV-sealed and won't decrypt in prod).
SEALED_DIR_PROD="${SEALED_DIR_PROD:-deploy/sealed-secrets/prod}"

# ---------- prod cluster guards -------------------------------------------

# Hard stop if we're somehow pointed at a kind cluster — prod must never touch
# the dev path's context.
require_not_kind() {
  local ctx; ctx="$(kubectl config current-context 2>/dev/null || true)"
  case "$ctx" in
    kind-*)
      warn "refusing to deploy: current kube-context '$ctx' is a kind cluster"
      exit 1 ;;
  esac
  ok "kube-context: ${ctx:-<current default>}"
}

# The reachability check required of the prod path. Never creates a cluster.
verify_cluster() {
  step "Verifying production k3s reachability"
  kubectl get nodes
  ok "k3s reachable"
}

# ---------- prod sealed secrets -------------------------------------------
# The prod private key is managed OUT OF BAND and never committed. We do NOT
# apply the dev keypair (secrets/dev/...) here. We only (a) confirm the
# controller is up and (b) apply prod-sealed SealedSecrets so they decrypt
# into the enterprise-platform-* Secrets the charts consume.
bootstrap_sealed_secrets_prod() {
  if ! sealed_controller_installed; then
    warn "Sealed Secrets controller not found in $SEALED_NS."
    warn "Install it WITH the prod private key out-of-band before deploying"
    warn "(auto-installing here would mint a NEW key and orphan prod secrets)."
    warn "See the README 'Production deploy' section."
    exit 1
  fi
  ok "Sealed Secrets controller present in $SEALED_NS"

  # Path 1: committed prod SealedSecrets — apply them and wait for the
  # controller to decrypt them into the Secrets the charts consume.
  if [ -d "$SEALED_DIR_PROD" ] && compgen -G "$SEALED_DIR_PROD/*.yaml" >/dev/null 2>&1; then
    step "Applying prod SealedSecrets from $SEALED_DIR_PROD"
    kubectl apply -f "$SEALED_DIR_PROD"
    for s in "${SEALED_SECRET_NAMES[@]}"; do
      wait_for_secret "$s" && ok "Secret $s ready"
    done
    return 0
  fi

  # Path 2: no committed prod SealedSecrets. Never auto-create secrets — decide
  # whether to continue based on what already exists live in the namespace.
  local missing=()
  for s in "${SEALED_SECRET_NAMES[@]}"; do
    kubectl -n "$NS" get secret "$s" >/dev/null 2>&1 || missing+=("$s")
  done

  if [ "${#missing[@]}" -eq 0 ]; then
    warn "No committed prod SealedSecrets in $SEALED_DIR_PROD."
    warn "All required Secrets already exist in '$NS', so deployment continues —"
    warn "but prod secrets are currently managed manually (not in GitOps)."
    warn "To move them into the repo, seal with the prod cert and commit ONLY the"
    warn "sealed YAML (never raw values):"
    warn "  ./deploy.sh --seal --env prod <name> prod/<name>.sealedsecret.yaml --from-literal=k=v"
    warn "  (see deploy/sealed-secrets/prod/README.md)"
    return 0
  fi

  warn "Required production Secrets are missing and no prod SealedSecrets were found:"
  for s in "${missing[@]}"; do warn "  - $s"; done
  warn "Create sealed prod secrets before deploying — do NOT commit raw Secret"
  warn "manifests. See deploy/sealed-secrets/prod/README.md."
  exit 1
}

# ---------- main ----------------------------------------------------------

main() {
  require_not_kind
  verify_cluster
  ensure_ns
  bootstrap_sealed_secrets_prod

  # Same chart catalog and ordering as the dev full --up, installed with
  # `helm upgrade --install` (idempotent). LITELLM_USE_MOCK_MODELS is left
  # unset, so litellm gets its real values.yaml (real provider keys from the
  # prod enterprise-platform-litellm-secrets Secret) — NOT the CI mock overlay.
  step "Deploying charts to '$NS' (helm upgrade --install)"
  for c in "${INSTALL_ORDER[@]}"; do
    install_chart "$c"
  done

  echo
  ok "production deploy complete. snapshot:"
  kubectl -n "$NS" get pods,svc 2>&1 | sed 's/^/    /'
}

main "$@"
