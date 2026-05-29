#!/bin/bash
# run-facts-export.sh — gather VSP facts, diff vs last run, build xlsx + csv, copy to share.
# Run from project root: bash scripts/run-facts-export.sh
#   --baseline DIR   diff against a named baseline (a history snapshot) instead of last run
set -euo pipefail

cd "$(dirname "$0")/.."

SHARE_DIR="/mnt/vm_share/vsp_facts_export"
STAMP="$(date +%Y-%m-%d_%H%M%S)"
PREV_ARG=""
[ "${1:-}" = "--baseline" ] && [ -n "${2:-}" ] && PREV_ARG="--prev $2"

echo "==> Step 1/5: gathering facts from all arrays"
ansible-playbook playbooks/08-export-facts.yml

echo "==> Step 2/5: building Excel workbook (with diff vs previous run)"
python3.11 scripts/facts_to_xlsx.py --raw exports/raw $PREV_ARG

echo "==> Step 3/5: building CSV files"
python3.11 scripts/facts_to_csv.py --raw exports/raw --out exports/csv

echo "==> Step 4/5: archiving this run to history/$STAMP"
mkdir -p "exports/history/$STAMP"
cp -f exports/raw/*.json "exports/history/$STAMP/" 2>/dev/null || true
# keep only the 20 most recent snapshots
ls -1dt exports/history/*/ 2>/dev/null | tail -n +21 | xargs -r rm -rf

echo "==> Step 5/5: copying to shared folder"
if [ -d /mnt/vm_share ]; then
  mkdir -p "$SHARE_DIR/csv"
  cp -f exports/*.xlsx "$SHARE_DIR/" 2>/dev/null || true
  cp -f exports/csv/*.csv "$SHARE_DIR/csv/" 2>/dev/null || true
  echo "  copied to $SHARE_DIR (D:\\vsp_facts_export on Windows)"
else
  echo "  ! /mnt/vm_share not available — skipped copy. Files remain in exports/"
fi

echo "==> Done."
echo "  xlsx: $(ls -1t exports/*.xlsx | head -1)"
ls -1 exports/csv/
