#!/usr/bin/env bash
# deploy.sh — install or tear down the agentic-platform on a local kind cluster.
#
# Usage:
#   ./deploy.sh --up                 # full stack
#   ./deploy.sh --up <chart>         # one chart (+ its hard deps, idempotent)
#   ./deploy.sh --down               # uninstall everything, delete cluster
#   ./deploy.sh --down <chart>       # uninstall just one chart
#   ./deploy.sh --status             # show current state
#
# Reuses an existing kind cluster named agentic-platform if present.
# All operations are idempotent — re-running --up is safe.
#
# Env flags:
#   LITELLM_USE_MOCK_MODELS=1   Install LiteLLM with deploy/helm/litellm/
#                               values.ci-mock.yaml overlay so the proxy
#                               returns mock_response text instead of
#                               calling real providers. Used by CI.
#   ANTHROPIC_API_KEY=...       Stored in the platform-litellm-secrets
#   OPENAI_API_KEY=...          Secret by deploy.sh. Without these the
#                               Secret holds `ci-fake` placeholders.

set -euo pipefail

CLUSTER="agentic-platform"
NS="agentic-platform"
KIND_CFG="deploy/kind/kind-config.yaml"
HELM_DIR="deploy/helm"

# Hard install-time deps: chart X cannot be installed unless its
# dep list is already running. (Soft / runtime deps like otel-collector
# wanting tempo to be present aren't here — those just degrade gracefully.)
declare -A HARD_DEPS=(
  [seaweedfs]=""
  [redis]=""
  [postgres]=""
  [falkordb]=""
  [presidio]=""
  [obot]=""
  [prometheus]=""
  [grafana]=""
  [otel-collector]=""
  [tempo]="seaweedfs"
  [loki]="seaweedfs"
  [mlflow]="postgres seaweedfs"
  [litellm]="postgres redis presidio otel-collector"
)

# Charts that install the upstream chart directly via `--repo`, using
# only deploy/helm/<chart>/values.yaml as a `-f` override (no umbrella).
#
# Why: Helm 3.21's CheckDependencies rejects umbrella charts whose
# subchart has its own transitive deps, even when our values disable
# them (e.g. prometheus subchart depends on alertmanager / kube-state-
# metrics, all condition-gated, but Helm errors out before evaluating
# conditions). Installing the upstream chart directly sidesteps the
# whole umbrella validation path.
#
# Format: chart_name -> "repo_url|upstream_chart_name|version"
declare -A DIRECT_CHARTS=(
  [obot]="https://charts.obot.ai|obot|v0.21.1"
  [prometheus]="https://prometheus-community.github.io/helm-charts|prometheus|25.27.0"
  [grafana]="https://grafana.github.io/helm-charts|grafana|8.5.0"
  [loki]="https://grafana.github.io/helm-charts|loki|6.16.0"
  [tempo]="https://grafana.github.io/helm-charts|tempo|1.10.0"
  [otel-collector]="https://open-telemetry.github.io/opentelemetry-helm-charts|opentelemetry-collector|0.96.0"
  [mlflow]="https://community-charts.github.io/helm-charts|mlflow|0.7.19"
  [litellm]="oci://ghcr.io/berriai|litellm-helm|0.1.781"
)

# Install order for a full --up.  Bootstrap jobs slot between phases.
INSTALL_ORDER=(
  seaweedfs redis postgres falkordb           # shared infra
  # >>> bootstrap-buckets + bootstrap-litellm-db here <<<
  tempo loki prometheus grafana otel-collector mlflow  # telemetry / tracking
  presidio obot                                # data-plane sidecars
  # >>> create-litellm-secret here <<<
  litellm                                      # data-plane main
)

# ---------- pretty output -------------------------------------------------

c_red()   { printf "\033[31m%s\033[0m" "$*"; }
c_green() { printf "\033[32m%s\033[0m" "$*"; }
c_blue()  { printf "\033[34m%s\033[0m" "$*"; }
c_dim()   { printf "\033[2m%s\033[0m"  "$*"; }
step()    { echo; echo "$(c_blue "▶") $*"; }
ok()      { echo "  $(c_green "✓") $*"; }
warn()    { echo "  $(c_red "✗") $*" >&2; }

# ---------- cluster -------------------------------------------------------

ensure_cluster() {
  if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
    ok "kind cluster '$CLUSTER' already exists, reusing"
  else
    step "Creating kind cluster '$CLUSTER'"
    kind create cluster --config "$KIND_CFG" --name "$CLUSTER"
  fi
  kubectl config use-context "kind-$CLUSTER" >/dev/null
}

ensure_ns() {
  if kubectl get ns "$NS" >/dev/null 2>&1; then
    ok "namespace '$NS' exists"
  else
    kubectl create namespace "$NS" >/dev/null
    ok "namespace '$NS' created"
  fi
}

# ---------- helm ----------------------------------------------------------

chart_dir() { echo "$HELM_DIR/$1"; }

helm_release() { echo "platform-$1"; }

is_installed() {
  helm -n "$NS" status "$(helm_release "$1")" >/dev/null 2>&1
}

helm_dep_update_if_needed() {
  local chart="$1"
  local dir; dir="$(chart_dir "$chart")"
  # Only run dependency update if Chart.yaml declares dependencies.
  grep -q "^dependencies:" "$dir/Chart.yaml" 2>/dev/null || return 0

  # Run if charts/ is empty OR contains only .tgz with no matching dir.
  local needs_update=0
  if [ ! -d "$dir/charts" ] || [ -z "$(ls -A "$dir/charts" 2>/dev/null)" ]; then
    needs_update=1
  fi
  if [ "$needs_update" = 1 ]; then
    step "helm dependency update $dir"
    helm dependency update "$dir"
  fi

  # Helm 3.21+ requires deps extracted into charts/<name>/ — `helm
  # dependency update` only writes the .tgz, so unpack any tarballs that
  # don't already have a sibling directory. Use the tarball's own top-
  # level entry to discover the chart name (works for both `name-X.Y.Z`
  # and `name-vX.Y.Z` styles, where the basename parse would fail).
  for tgz in "$dir"/charts/*.tgz; do
    [ -f "$tgz" ] || continue
    # tar | head trips pipefail with SIGPIPE — write the full list to a
    # var, then take the first segment, so the pipe stays single-stage.
    local listing name
    listing="$(tar -tzf "$tgz" 2>/dev/null || true)"
    name="${listing%%/*}"
    name="${name%%$'\n'*}"
    [ -n "$name" ] || continue
    if [ ! -d "$dir/charts/$name" ]; then
      tar -xzf "$tgz" -C "$dir/charts"
      ok "extracted $name from $(basename "$tgz")"
    fi
  done
}

install_chart() {
  local chart="$1"
  local rel; rel="$(helm_release "$chart")"
  local dir; dir="$(chart_dir "$chart")"

  if [ ! -d "$dir" ]; then
    warn "chart dir $dir does not exist"
    return 1
  fi

  # Install hard deps first (recursively, idempotent).
  for d in ${HARD_DEPS[$chart]:-}; do
    if ! is_installed "$d"; then
      install_chart "$d"
    fi
  done

  # Pre-install hooks for this chart.
  case "$chart" in
    tempo|loki|mlflow) bootstrap_buckets ;;
    litellm)           bootstrap_litellm_db ; create_litellm_secret ;;
  esac

  # Charts that install directly from the upstream repo (see
  # DIRECT_CHARTS above for why).
  if [ -n "${DIRECT_CHARTS[$chart]:-}" ]; then
    IFS='|' read -r repo upstream version <<<"${DIRECT_CHARTS[$chart]}"

    # Per-chart overlay flags. LITELLM_USE_MOCK_MODELS=1 swaps the
    # production model list for mock_response models — used by CI to
    # exercise the full proxy path without real provider keys.
    local overlay_files=()
    if [ "$chart" = "litellm" ] && [ "${LITELLM_USE_MOCK_MODELS:-0}" = "1" ]; then
      if [ -f "$dir/values.ci-mock.yaml" ]; then
        overlay_files+=(-f "$dir/values.ci-mock.yaml")
        ok "applying $dir/values.ci-mock.yaml (LITELLM_USE_MOCK_MODELS=1)"
      else
        warn "LITELLM_USE_MOCK_MODELS=1 set but $dir/values.ci-mock.yaml missing"
      fi
    fi

    step "helm install $rel (upstream $upstream@$version)"
    # OCI registries are referenced as oci://... and use a different
    # install syntax (no `--repo` flag — the URI IS the chart).
    if [[ "$repo" == oci://* ]]; then
      helm -n "$NS" upgrade --install "$rel" "$repo/$upstream" \
        --version "$version" \
        -f "$dir/values.yaml" \
        "${overlay_files[@]}" \
        --wait --timeout 10m
    else
      helm -n "$NS" upgrade --install "$rel" "$upstream" \
        --repo "$repo" \
        --version "$version" \
        -f "$dir/values.yaml" \
        "${overlay_files[@]}" \
        --wait --timeout 10m
    fi
    return $?
  fi

  # Local-only chart (hand-written or umbrella with no transitive deps).
  helm_dep_update_if_needed "$chart"
  if is_installed "$chart"; then
    ok "$rel already installed (helm upgrade --install would reapply if values changed)"
    helm -n "$NS" upgrade --install "$rel" "$dir" --wait --timeout 8m
  else
    step "helm install $rel"
    helm -n "$NS" install "$rel" "$dir" --wait --timeout 8m
  fi
}

uninstall_chart() {
  local chart="$1"
  local rel; rel="$(helm_release "$chart")"
  if is_installed "$chart"; then
    step "helm uninstall $rel"
    helm -n "$NS" uninstall "$rel"
    # Best-effort PVC cleanup.
    kubectl -n "$NS" delete pvc -l "app.kubernetes.io/instance=$rel" --ignore-not-found >/dev/null 2>&1 || true
  else
    ok "$rel not installed (skipping)"
  fi
}

# ---------- bootstrap jobs ------------------------------------------------

# Bucket bootstrap — run once per cluster lifetime.
bootstrap_buckets() {
  local job="seaweedfs-bucket-init"
  if kubectl -n "$NS" get job "$job" >/dev/null 2>&1; then
    ok "buckets job already exists (assume done)"
    return 0
  fi
  step "Bootstrapping SeaweedFS buckets via in-cluster Job"
  cat <<EOF | kubectl -n "$NS" apply -f -
apiVersion: batch/v1
kind: Job
metadata:
  name: $job
spec:
  backoffLimit: 3
  template:
    spec:
      restartPolicy: OnFailure
      containers:
        - name: bucket-init
          image: amazon/aws-cli:latest
          env:
            - { name: AWS_ACCESS_KEY_ID,     value: any }
            - { name: AWS_SECRET_ACCESS_KEY, value: any }
            - { name: AWS_DEFAULT_REGION,    value: us-east-1 }
          command:
            - /bin/sh
            - -c
            - |
              set -eu
              ENDPOINT=http://platform-seaweedfs-all-in-one:8333
              until aws --endpoint-url \$ENDPOINT s3 ls >/dev/null 2>&1; do
                echo "waiting for seaweedfs s3 endpoint..."
                sleep 2
              done
              for b in tempo-traces loki-logs mlflow-artifacts prometheus-blocks; do
                aws --endpoint-url \$ENDPOINT s3api head-bucket --bucket "\$b" 2>/dev/null \
                  && echo "exists: \$b" \
                  || aws --endpoint-url \$ENDPOINT s3 mb "s3://\$b"
              done
              echo "all buckets ready"
EOF
  kubectl -n "$NS" wait --for=condition=complete --timeout=180s "job/$job"
  ok "buckets bootstrapped"
}

bootstrap_litellm_db() {
  if kubectl -n "$NS" exec deploy/platform-postgres -- \
       psql -U postgres -tc "SELECT 1 FROM pg_database WHERE datname = 'litellm'" 2>/dev/null | grep -q 1; then
    ok "litellm database already exists"
  else
    step "Creating litellm database in platform-postgres"
    kubectl -n "$NS" exec deploy/platform-postgres -- \
      psql -U postgres -c "CREATE DATABASE litellm"
    ok "litellm database created"
  fi
}

create_litellm_secret() {
  if kubectl -n "$NS" get secret platform-litellm-secrets >/dev/null 2>&1; then
    ok "platform-litellm-secrets already exists"
    return 0
  fi
  step "Creating platform-litellm-secrets"
  kubectl -n "$NS" create secret generic platform-litellm-secrets \
    --from-literal=masterkey="$(openssl rand -hex 32)" \
    --from-literal=anthropic-api-key="${ANTHROPIC_API_KEY:-ci-fake}" \
    --from-literal=openai-api-key="${OPENAI_API_KEY:-ci-fake}"
  ok "secret created"
}

# ---------- commands ------------------------------------------------------

cmd_up() {
  local target="${1:-}"
  ensure_cluster
  ensure_ns

  if [ -n "$target" ]; then
    install_chart "$target"
  else
    for c in "${INSTALL_ORDER[@]}"; do
      install_chart "$c"
    done
  fi

  echo
  ok "done. snapshot:"
  kubectl -n "$NS" get pods,svc 2>&1 | sed 's/^/    /'
}

cmd_down() {
  local target="${1:-}"
  if [ -n "$target" ]; then
    uninstall_chart "$target"
    return 0
  fi

  # Full teardown: uninstall in reverse, then delete cluster.
  step "Uninstalling all releases in $NS"
  if kubectl get ns "$NS" >/dev/null 2>&1; then
    for rel in $(helm -n "$NS" list -q 2>/dev/null); do
      helm -n "$NS" uninstall "$rel" || true
    done
    kubectl -n "$NS" delete job --all --ignore-not-found >/dev/null 2>&1 || true
    kubectl -n "$NS" delete secret platform-litellm-secrets --ignore-not-found >/dev/null 2>&1 || true
    kubectl delete namespace "$NS" --ignore-not-found
  fi
  step "Deleting kind cluster $CLUSTER"
  kind delete cluster --name "$CLUSTER" || true
}

cmd_status() {
  if ! kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
    echo "(cluster $CLUSTER not present)"
    return 0
  fi
  kubectl config use-context "kind-$CLUSTER" >/dev/null 2>&1
  if ! kubectl get ns "$NS" >/dev/null 2>&1; then
    echo "(namespace $NS not present)"
    return 0
  fi
  echo "--- helm releases ---"
  helm -n "$NS" list
  echo
  echo "--- pods ---"
  kubectl -n "$NS" get pods
}

# ---------- arg parse -----------------------------------------------------

usage() {
  sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
  exit 1
}

[ $# -lt 1 ] && usage

case "$1" in
  --up)     shift; cmd_up   "${1:-}";;
  --down)   shift; cmd_down "${1:-}";;
  --status) shift; cmd_status;;
  -h|--help) usage;;
  *) usage;;
esac
