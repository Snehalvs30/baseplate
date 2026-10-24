#!/usr/bin/env bash
# Static checks for the platform repository. Runs in CI on every push; run it locally
# before pushing:  ./tests/validate.sh
# Needs: helm, kubeconform, python3 with PyYAML, and network access (remote charts and
# schemas are downloaded).
set -uo pipefail
cd "$(dirname "$0")/.."

OUT=$(mktemp -d)
trap 'rm -rf "$OUT"' EXIT
FAILED=0
step() { echo; echo "== $1"; }
fail() { echo "FAIL: $1"; FAILED=1; }

# Schemas for resource types that aren't built into Kubernetes (ArgoCD Applications,
# External Secrets...), from the community CRD catalog.
CRD_SCHEMAS='https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'
KUBECONFORM=(kubeconform -strict -summary -schema-location default -schema-location "$CRD_SCHEMAS")

step "File names (no trailing spaces or other whitespace)"
bad=$(git ls-files -z | tr '\0' '\n' | grep -E '[[:space:]]$' || true)
if [ -n "$bad" ]; then fail "file names ending in whitespace: $(printf '%q ' $bad)"; else echo "OK"; fi

step "Our Helm charts: lint and render"
render() {   # name, chart, values files...
  local name=$1 chart=$2; shift 2
  local args=()
  for values in "$@"; do args+=(-f "$values"); done
  helm lint "$chart" "${args[@]}" --quiet || fail "helm lint $chart"
  helm template ci "$chart" "${args[@]}" > "$OUT/$name.yaml" || fail "helm template $chart"
}
render footnote tenants/footnote tenants/footnote/values.yaml tenants/footnote/values-local.yaml
render ledgerline tenants/ledgerline tenants/ledgerline/values.yaml tenants/ledgerline/values-local.yaml
render tenancy platform/tenancy platform/tenancy/values.yaml
echo "Rendered: $(ls "$OUT" | tr '\n' ' ')"

step "Kubernetes schemas: rendered charts and plain manifests"
"${KUBECONFORM[@]}" "$OUT"/*.yaml platform/bootstrap/root-application.yaml \
  platform/bootstrap/apps/*.yaml platform/bootstrap/disabled/*.yaml platform/secret-store/*.yaml \
  || fail "kubeconform"

step "ArgoCD Applications"
python3 tests/check_applications.py || fail "Application checks"

step "Remote charts render with our values (checked against each chart's schema)"
if lines=$(python3 tests/check_applications.py --remote-charts "$OUT/remote"); then
  while read -r repo chart version values; do
    [ -z "$repo" ] && continue
    if helm template ci "$chart" --repo "$repo" --version "$version" -f "$values" > /dev/null 2> "$OUT/err"; then
      echo "OK: $chart $version"
    else
      fail "$chart $version doesn't accept our values: $(head -5 "$OUT/err")"
    fi
  done <<< "$lines"
fi

step "Terraform: formatting and validation"
if command -v terraform >/dev/null; then
  terraform fmt -check -recursive infra || fail "terraform fmt (run: terraform fmt -recursive infra)"
  for dir in infra/bootstrap infra/envs/dev infra/envs/prod; do
    if (cd "$dir" && terraform init -backend=false -input=false >/dev/null && terraform validate -no-color >/dev/null); then
      echo "OK: $dir"
    else
      fail "terraform validate $dir"
    fi
  done
else
  echo "SKIPPED: terraform isn't installed"
fi

step "Images are pinned (no :latest, no missing tag)"
unpinned=$(grep -hE '^[[:space:]]*image:' "$OUT"/*.yaml | sed -E 's/^[[:space:]]*image:[[:space:]]*"?([^" ]+)"?.*/\1/' | sort -u \
  | awk -F/ '{ last=$NF } last !~ /:/ || last ~ /:latest$/ { print }')
if [ -n "$unpinned" ]; then fail "unpinned images: $unpinned"; else echo "OK"; fi

echo
if [ "$FAILED" -ne 0 ]; then echo "Validation FAILED"; exit 1; fi
echo "All checks passed"
