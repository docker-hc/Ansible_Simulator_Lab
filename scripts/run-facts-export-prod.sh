#!/bin/bash
# run-facts-export-prod.sh — on-demand VSP facts export against LIVE arrays.
# Read-only: gathers REST facts + raidcom WWN logins, builds xlsx + csv,
# brings HORCM up only for the run and tears it down on any exit.
#
# Prereqs: real command device per array (read-only, user-auth) wired into
#          /etc/horcmN.conf; vault_arrays populated; python3.11 + openpyxl.
# Run:     bash scripts/run-facts-export-prod.sh
set -euo pipefail
cd "$(dirname "$0")/.."

# derive HORCM instances from the vault array list (single source of truth)
INSTANCES=$(ansible localhost -m debug \
  -a "var=vault_arrays" -e @group_vars/vault.yml 2>/dev/null \
  | grep -oP '"horcm_instance":\s*\K[0-9]+' | sort -u | tr '\n' ' ')
[ -z "$INSTANCES" ] && { echo "no horcm_instance values found in vault"; exit 1; }
echo "==> HORCM instances: $INSTANCES"

# bring HORCM up; guarantee shutdown on success, failure, or interrupt
# shellcheck disable=SC2086  # word-splitting intended: one arg per instance
horcmstart.sh $INSTANCES
# shellcheck disable=SC2064,SC2086
trap 'horcmshutdown.sh $INSTANCES >/dev/null 2>&1 || true' EXIT

echo "==> Step 1/4: gathering facts (REST) + HBA WWN logins (raidcom)"
ansible-playbook playbooks/08-export-facts.yml

echo "==> Step 2/4: building Excel workbook (diff vs previous run)"
python3.11 scripts/facts_to_xlsx.py --raw exports/raw

echo "==> Step 3/4: building CSV files"
python3.11 scripts/facts_to_csv.py --raw exports/raw --out exports/csv

echo "==> Step 4/4: archiving run to history (keep last 60)"
STAMP=$(date +%Y-%m-%d_%H%M%S)
mkdir -p "exports/history/$STAMP"
cp -f exports/raw/*.json "exports/history/$STAMP/" 2>/dev/null || true
# shellcheck disable=SC2012
ls -1dt exports/history/*/ 2>/dev/null | tail -n +61 | xargs -r rm -rf

# shellcheck disable=SC2012
echo "==> Done. Workbook: $(ls -1t exports/*.xlsx | head -1)"
