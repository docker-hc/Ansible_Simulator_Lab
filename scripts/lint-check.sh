#!/bin/bash
# ============================================================
# Lab Lint & Verification Script
# Run before every git commit
# Usage: bash scripts/lint-check.sh
# ============================================================

LAB="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$LAB" || exit 1

PASS=0
FAIL=0

run_check() {
  local name=$1
  local cmd=$2
  echo "━━━ ${name} ━━━"
  if eval "$cmd" > /tmp/lint-output 2>&1; then
    echo "✓ ${name} passed"
    PASS=$((PASS + 1))
  else
    echo "✗ ${name} FAILED"
    cat /tmp/lint-output
    FAIL=$((FAIL + 1))
  fi
  echo ""
}

echo ""
echo "╔══════════════════════════════════════╗"
echo "║  Lab Lint & Verification Check       ║"
echo "╚══════════════════════════════════════╝"
echo ""

run_check "yamllint" \
  "yamllint -c .yamllint.yml playbooks/ roles/ group_vars/ host_vars/"

run_check "ansible-lint" \
  "ansible-lint playbooks/"

run_check "ansible syntax-check" \
  "for p in playbooks/*.yml; do ansible-playbook --syntax-check \$p; done"

run_check "ansible inventory graph" \
  "ansible-inventory --graph"

run_check "vault encrypted" \
  "head -1 group_vars/vault.yml | grep -q ANSIBLE_VAULT"

run_check "vault_pass not tracked by git" \
  "! git ls-files | grep -q vault_pass"

run_check "shellcheck on scripts" \
  "shellcheck scripts/lint-check.sh"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Results: ${PASS} passed, ${FAIL} failed"
echo ""
if [ "$FAIL" -eq 0 ]; then
  echo "✓ All checks passed — safe to commit and push"
  exit 0
else
  echo "✗ Fix failures before committing"
  exit 1
fi
