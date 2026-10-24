#!/usr/bin/env bash
# Proves tenant isolation on a running Baseplate cluster: network boundaries,
# quotas and access rules. Run from the repository root:  ./tests/isolation.sh
#
# Each network check starts a throwaway busybox pod that tries one TCP connection.
set -uo pipefail

passed=0
failed=0
pass() { echo "PASS: $1"; passed=$((passed + 1)); }
fail() { echo "FAIL: $1"; failed=$((failed + 1)); }

# connect <from-namespace> <host> <port>: succeeds if a TCP connection opens.
# connect() {
#   kubectl run "probe-$RANDOM" -n "$1" --image=busybox:1.37 --restart=Never \
#     --rm -i --quiet --command -- nc -z -w 3 "$2" "$3" >/dev/null 2>&1
# }
# Waits SETTLE_SECONDS before connecting: on k3s, network policy rules for a brand-new
# pod are programmed shortly after it starts, so an immediate connection can slip
# through before they apply (see docs/local-cluster-notes.md).
connect() {
  kubectl run "probe-$RANDOM" -n "$1" --image=busybox:1.37 --restart=Never \
    --rm -i --quiet --command -- sh -c "sleep ${SETTLE_SECONDS:-10}; nc -z -w 3 $2 $3" >/dev/null 2>&1
}
expect_blocked() { if connect "$1" "$2" "$3"; then fail "$4"; else pass "$4"; fi; }
expect_open()    { if connect "$1" "$2" "$3"; then pass "$4"; else fail "$4"; fi; }

LEDGERLINE_DB=postgres.tenant-ledgerline.svc.cluster.local
LEDGERLINE_APP=ledgerline.tenant-ledgerline.svc.cluster.local

echo "== Network isolation =="
expect_blocked tenant-podinfo "$LEDGERLINE_DB" 5432 \
  "another tenant (podinfo) cannot reach Ledgerline's database"
expect_blocked tenant-podinfo "$LEDGERLINE_APP" 80 \
  "another tenant (podinfo) cannot call Ledgerline's API directly"
expect_blocked default "$LEDGERLINE_APP" 80 \
  "a pod outside any tenant cannot call Ledgerline"
expect_open tenant-ledgerline postgres 5432 \
  "Ledgerline's own pods still reach their database"
expect_blocked tenant-ledgerline example.com 443 \
  "Ledgerline cannot reach the internet"

code=$(curl -s -o /dev/null -w '%{http_code}' http://ledgerline.localhost/actuator/health/readiness)
[ "$code" = "200" ] && pass "traffic through the ingress controller still works" \
  || fail "ingress traffic returned $code"

echo "== Quotas =="
# A server-side dry run goes through admission (including quota checks) without
# creating anything. 1Gi is under the per-container ceiling (2Gi) but over podinfo's
# whole-namespace quota (256Mi), so only the quota can reject it.
if kubectl run quota-check -n tenant-podinfo --image=busybox:1.37 --restart=Never \
     --dry-run=server --overrides='{"spec":{"containers":[{"name":"quota-check","image":"busybox:1.37","resources":{"requests":{"memory":"1Gi"},"limits":{"memory":"1Gi"}}}]}}' \
     >/dev/null 2>&1; then
  fail "a pod asking for more than the tenant's quota was accepted"
else
  pass "a pod asking for more than the tenant's quota is rejected"
fi

echo "== Access (RBAC) =="
as_dev=(--as=dev-user --as-group=tenant:ledgerline:developers)
[ "$(kubectl auth can-i list pods -n tenant-ledgerline "${as_dev[@]}")" = "yes" ] \
  && pass "Ledgerline developers can see their own pods" || fail "developers can't see their own pods"
[ "$(kubectl auth can-i list pods -n tenant-podinfo "${as_dev[@]}")" = "no" ] \
  && pass "Ledgerline developers cannot see another tenant's pods" || fail "developers can see another tenant"
[ "$(kubectl auth can-i get secrets -n tenant-ledgerline "${as_dev[@]}")" = "no" ] \
  && pass "developers cannot read Secrets, even their own" || fail "developers can read Secrets"
[ "$(kubectl auth can-i delete deployments -n tenant-ledgerline "${as_dev[@]}")" = "no" ] \
  && pass "developers cannot change workloads directly (changes go through Git)" || fail "developers can delete deployments"

echo
echo "$passed passed, $failed failed"
[ "$failed" -eq 0 ]