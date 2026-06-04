#!/usr/bin/env bash
# Goes in: scripts/verify-commit-hygiene.sh   (run from anywhere in the repo)
#
# Item 3 confirmation. Checks:
#   1) no __pycache__ / *.pyc tracked by git
#   2) no trailing whitespace in the facts-export playbook (08)
#   3) .gitignore contains the expected guards
#   + bonus: no known secret files tracked
#
# Aggregates all checks then exits non-zero if any failed, so this can also be
# dropped into CI later as a second gate alongside lint.

set -uo pipefail
cd "$(git rev-parse --show-toplevel)" || exit 1

fail=0
pass() { printf '  \033[32mPASS\033[0m  %s\n' "$1"; }
bad()  { printf '  \033[31mFAIL\033[0m  %s\n' "$1"; fail=1; }

echo "== 1. __pycache__ / *.pyc not tracked =="
tracked_py=$(git ls-files | grep -E '(^|/)__pycache__/|\.pyc$' || true)
if [ -z "$tracked_py" ]; then
  pass "no compiled-python artifacts tracked"
else
  bad "tracked — run: git rm -r --cached <path> && commit"
  printf '%s\n' "$tracked_py" | sed 's/^/        /'
fi

echo "== 2. trailing whitespace in 08-export-facts.yml =="
f=$(git ls-files '*08-export-facts.yml' | head -n1)
if [ -z "$f" ]; then
  bad "could not locate 08-export-facts.yml in the repo"
elif grep -nP '[ \t]+$' "$f" >/dev/null 2>&1; then
  bad "trailing whitespace remains in $f:"
  grep -nP '[ \t]+$' "$f" | sed 's/^/        line /'
else
  pass "no trailing whitespace in $f"
fi

echo "== 3. .gitignore guards present =="
guards=( '__pycache__/' '*.pyc' '*.bak' 'wg0.conf' '*.key' '.vault_pass' 'exports/' )
if [ ! -f .gitignore ]; then
  bad ".gitignore missing"
else
  for g in "${guards[@]}"; do
    if grep -qF "$g" .gitignore; then pass ".gitignore has  $g"
    else bad ".gitignore MISSING  $g"; fi
  done
fi

echo "== bonus: no known secret files tracked =="
secrets=$(git ls-files | grep -E '(^|/)(wg0\.conf|\.vault_pass)$|\.key$' || true)
if [ -z "$secrets" ]; then
  pass "no secret files tracked"
else
  bad "secret files tracked — purge from working tree AND history if ever committed"
  printf '%s\n' "$secrets" | sed 's/^/        /'
fi

echo
if [ "$fail" -eq 0 ]; then echo "ALL CHECKS PASSED"; else echo "SOME CHECKS FAILED"; fi
exit "$fail"
