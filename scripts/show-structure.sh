#!/bin/bash
# show-structure.sh — visualise the Ansible project + lab structure.
# Usage: bash scripts/show-structure.sh [output_file]
#   no arg  -> prints to terminal
#   arg     -> also writes a plain-text snapshot to that file
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-}"
[ -n "$OUT" ] && : > "$OUT"
emit() { if [ -n "$OUT" ]; then printf '%s\n' "$*" | tee -a "$OUT"; else printf '%s\n' "$*"; fi; }
run()  { if [ -n "$OUT" ]; then "$@" 2>&1 | tee -a "$OUT"; else "$@"; fi; }

emit "============================================================"
emit " Ansible Simulator Lab - Project & Lab Structure"
emit " Generated: $(date)"
emit "============================================================"
emit ""
emit "-- Directory tree --"
if command -v tree >/dev/null 2>&1; then
  run tree -L 3 --dirsfirst -I 'exports|__pycache__|*.pyc|.git'
else
  emit "(tree not installed - dnf install -y tree for nicer output; using find)"
  run bash -c "find . -maxdepth 3 -not -path './.git/*' -not -path './exports/*' -not -path '*/__pycache__/*' | sort | sed -e 's|[^/]*/|  |g'"
fi
emit ""
emit "-- Inventory graph (groups -> hosts) --"
run ansible-inventory --graph
emit ""
emit "-- Playbooks --"
run bash -c "ls -1 playbooks/*.yml 2>/dev/null"
emit ""
emit "-- Scripts --"
run bash -c "ls -1 scripts/ 2>/dev/null"
emit ""
emit "-- Installed collections --"
run bash -c "ansible-galaxy collection list 2>/dev/null | grep -v '^#' | grep -v '^$' | head -20"
emit ""
emit "-- HORCM instance map (live) --"
for i in 1001 1004 1005 1006; do
  line=$(raidqry -l -IH${i} 2>/dev/null | grep -v '^No\|^$\|^Group' | head -1 || true)
  emit "  HORCM $i: ${line:-not running}"
done
emit ""
emit "Done."
