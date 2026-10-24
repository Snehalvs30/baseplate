#!/usr/bin/env bash
# Sends steady traffic to Ledgerline through Traefik for a few minutes and records
# every failed request. Start it, then trigger a rollout while it runs.
#
#   ./tests/load/rollout-test.sh run1-before     (results in docs/rollout/)
#
# Needs: kubectl, k6, openssl. Signs its own token with Ledgerline's JWT secret, read
# from the cluster (the secret External Secrets Operator created from AWS).
set -euo pipefail

LABEL="${1:-run}"
JWT_SECRET=$(kubectl get secret ledgerline-secrets -n tenant-ledgerline -o jsonpath='{.data.jwt-secret}' | base64 -d)
[ -n "${JWT_SECRET}" ] || { echo "Couldn't read Ledgerline's JWT secret from the cluster." >&2; exit 1; }

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
token() {
  local now exp header payload sig
  now=$(date +%s); exp=$((now + 3600))
  header=$(printf '{"alg":"HS256","typ":"JWT"}' | b64url)
  payload=$(printf '{"iss":"ledgerline-dev","aud":["ledgerline-api"],"sub":"%s","iat":%d,"exp":%d,"scope":"%s"}' \
    "$1" "$now" "$exp" "$2" | b64url)
  sig=$(printf '%s.%s' "$header" "$payload" | openssl dgst -sha256 -hmac "$JWT_SECRET" -binary | b64url)
  printf '%s.%s.%s' "$header" "$payload" "$sig"
}
TOKEN=$(token rollout-check "accounts:read accounts:write")

mkdir -p docs/rollout
k6 run --env TOKEN="${TOKEN}" --env BASE=http://ledgerline.localhost \
  --summary-export "docs/rollout/${LABEL}.json" tests/load/rollout.js 2>&1 | tee "docs/rollout/${LABEL}.txt"
