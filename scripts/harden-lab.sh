#!/bin/bash
# harden-lab.sh — apply baseline hardening + tamper detection to the lab.
#
# What it does (each step is idempotent and reports what it changed):
#   1. installs /root/lab-verify.sh (checksum tamper detection)
#   2. writes the first baseline manifest
#   3. installs a daily verify cron (logs to syslog)
#   4. locks playbooks/scripts/roles read-only (with an --unlock mode to edit)
#   5. checks .gitignore guards for secrets (wg0.conf, *.key, vault pass, duckdns)
#   6. AUDITS sshd_config for root-login/password auth — REPORTS only, never
#      edits sshd automatically (avoids locking you out); prints the exact
#      changes to make and how to apply them safely.
#
# Usage:
#   bash harden-lab.sh            # apply hardening + print report
#   bash harden-lab.sh --unlock   # make code writable again to edit
#   bash harden-lab.sh --lock     # re-lock after editing (same as default lock step)
#   bash harden-lab.sh --check    # just run the tamper check, no changes
#   bash harden-lab.sh --status   # show lock state, baseline age, check result
#
# Safe to re-run any time. Does NOT touch sshd, firewalld, or user accounts.

set -uo pipefail

PROJECT="/etc/ansible/Ansible_Simulator_Lab"
VERIFY="/root/lab-verify.sh"
BASELINE="/root/lab-baseline.sha256"
LOCK_DIRS=(playbooks scripts roles)

# ---- colours for the report (fall back to plain if no tty) ----
if [ -t 1 ]; then
  G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; C=$'\e[36m'; B=$'\e[1m'; N=$'\e[0m'
else
  G=""; Y=""; R=""; C=""; B=""; N=""
fi
ok(){   echo "  ${G}OK${N} $*"; }
chg(){  echo "  ${C}->${N} $*"; }
warn(){ echo "  ${Y}!${N} $*"; }
err(){  echo "  ${R}x${N} $*"; }
hr(){   echo "${B}== $* ==${N}"; }

cd "$PROJECT" 2>/dev/null || { err "Project dir not found: $PROJECT"; exit 1; }

# =====================================================================
# Sub-commands that short-circuit
# =====================================================================
case "${1:-apply}" in
  --unlock)
    hr "Unlocking code for editing"
    for d in "${LOCK_DIRS[@]}"; do
      [ -d "$d" ] && { chmod -R u+w "$d"; chg "writable: $d"; }
    done
    echo "Edit, commit, then re-run: bash harden-lab.sh --lock"
    exit 0
    ;;
  --lock)
    hr "Locking code read-only"
    for d in "${LOCK_DIRS[@]}"; do
      [ -d "$d" ] && { chmod -R a-w "$d"; ok "read-only: $d"; }
    done
    [ -x "$VERIFY" ] && { "$VERIFY" baseline >/dev/null && ok "baseline refreshed"; }
    exit 0
    ;;
  --check)
    [ -x "$VERIFY" ] || { err "no $VERIFY — run plain hardening first"; exit 1; }
    exec "$VERIFY" check
    ;;
  --status)
    hr "Lab hardening status"
    # lock state of each managed dir
    locked_any=0; unlocked_any=0
    for d in "${LOCK_DIRS[@]}"; do
      if [ -d "$d" ]; then
        # check the actual permission BITS, not -w (root bypasses -w, giving false 'writable')
        perms=$(stat -c '%A' "$d")
        if [ "${perms:2:1}" = "w" ]; then
          warn "UNLOCKED (writable): $d"; unlocked_any=1
        else
          ok "locked (read-only): $d"; locked_any=1
        fi
      else
        warn "missing: $d"
      fi
    done
    if [ "$unlocked_any" = 1 ] && [ "$locked_any" = 1 ]; then
      warn "mixed state — some dirs writable. Run --lock to re-secure."
    elif [ "$unlocked_any" = 1 ]; then
      warn "code is UNLOCKED — editing allowed. Run --lock when done."
    else
      ok "all code locked read-only"
    fi
    echo
    # baseline presence + age
    if [ -f "$BASELINE" ]; then
      n=$(wc -l < "$BASELINE")
      ts=$(date -r "$BASELINE" '+%Y-%m-%d %H:%M' 2>/dev/null || stat -c '%y' "$BASELINE" | cut -d. -f1)
      ok "baseline: $n files, last refreshed $ts"
    else
      err "no baseline yet — run plain hardening (bash harden-lab.sh)"
    fi
    # tamper check summary
    if [ -x "$VERIFY" ]; then
      if "$VERIFY" check >/dev/null 2>&1; then
        ok "tamper check: clean (matches baseline)"
      else
        warn "tamper check: CHANGES detected — run --check to see them"
      fi
    else
      warn "verify tool not installed yet"
    fi
    # cron presence
    if crontab -l 2>/dev/null | grep -qF "$VERIFY check"; then
      ok "daily verify cron: installed"
    else
      warn "daily verify cron: not installed"
    fi
    exit 0
    ;;
  apply) : ;;  # fall through to full run
  *) err "unknown option: $1"; echo "use: (none) | --status | --check | --unlock | --lock"; exit 1 ;;
esac

echo
hr "1. Tamper-detection script"
cat > "$VERIFY" << 'VEOF'
#!/bin/bash
# lab-verify.sh — verify lab files against a known-good checksum baseline.
#   baseline  write a new baseline from current files
#   check     compare current files to the baseline (exit 2 if changed)
BASE=/root/lab-baseline.sha256
PROJ=/etc/ansible/Ansible_Simulator_Lab
cd "$PROJ" || exit 1
scan(){ find playbooks scripts roles group_vars -type f \
  \( -name '*.yml' -o -name '*.yaml' -o -name '*.sh' -o -name '*.py' -o -name '*.cfg' \) \
  -exec sha256sum {} \; 2>/dev/null | sort; }
case "${1:-check}" in
  baseline) scan > "$BASE"; chmod 600 "$BASE"
            echo "baseline written: $(wc -l < "$BASE") files" ;;
  check)    [ -f "$BASE" ] || { echo "no baseline — run: $0 baseline"; exit 1; }
            diff <(scan) "$BASE" >/dev/null 2>&1 && { echo "OK — no changes since baseline"; exit 0; }
            echo "CHANGED since baseline:"
            # show files whose hash differs or that are new/removed
            comm -3 <(scan) "$BASE" | sed 's/^/  /'
            exit 2 ;;
  *) echo "usage: $0 {baseline|check}"; exit 1 ;;
esac
VEOF
chmod 700 "$VERIFY"
ok "installed $VERIFY"

echo
hr "2. First baseline"
"$VERIFY" baseline | sed 's/^/  /'

echo
hr "3. Daily verify cron"
CRON_LINE="0 6 * * * $VERIFY check | logger -t lab-verify"
if crontab -l 2>/dev/null | grep -qF "$VERIFY check"; then
  ok "cron already present"
else
  ( crontab -l 2>/dev/null; echo "$CRON_LINE" ) | crontab -
  chg "added daily check at 06:00 (logs: journalctl -t lab-verify)"
fi

echo
hr "4. Lock code read-only"
for d in "${LOCK_DIRS[@]}"; do
  if [ -d "$d" ]; then
    chmod -R a-w "$d"
    ok "read-only: $d  (edit later: bash harden-lab.sh --unlock)"
  else
    warn "missing dir: $d (skipped)"
  fi
done

echo
hr "5. .gitignore secret guards"
declare -a GUARDS=("wg0.conf" "*.key" ".vault_pass" "duckdns/" "exports/")
touch .gitignore
for g in "${GUARDS[@]}"; do
  if grep -qxF "$g" .gitignore; then
    ok ".gitignore has: $g"
  else
    echo "$g" >> .gitignore
    chg ".gitignore added: $g"
  fi
done
# warn loudly if any secret is already tracked by git
if command -v git >/dev/null && [ -d .git ]; then
  for f in $(git ls-files 2>/dev/null | grep -E 'wg0\.conf$|\.key$|\.vault_pass$' || true); do
    err "SECRET TRACKED IN GIT: $f  — run: git rm --cached $f"
  done
fi

echo
hr "6. SSH audit (report only — sshd is NOT modified)"
SSHD=/etc/ssh/sshd_config
if [ -r "$SSHD" ]; then
  rootlogin=$(grep -Ei '^\s*PermitRootLogin' "$SSHD" | tail -1 | awk '{print $2}')
  passauth=$(grep -Ei '^\s*PasswordAuthentication' "$SSHD" | tail -1 | awk '{print $2}')
  [ -z "$rootlogin" ] && rootlogin="(default: usually prohibit-password)"
  [ -z "$passauth" ] && passauth="(default: usually yes)"
  echo "  current: PermitRootLogin = $rootlogin"
  echo "  current: PasswordAuthentication = $passauth"
  if echo "$rootlogin" | grep -qiE 'yes|prohibit-password' || echo "$passauth" | grep -qiv 'no'; then
    warn "recommended hardening (apply MANUALLY, keeping a second session open):"
    echo "      PermitRootLogin no"
    echo "      PasswordAuthentication no"
    echo "      AuthenticationMethods publickey"
    echo "    then: sshd -t && systemctl reload sshd   (test in a NEW session before closing this one)"
  else
    ok "SSH already key-only / root login restricted"
  fi
else
  warn "cannot read $SSHD (skipped)"
fi

echo
hr "Report"
echo "  Tamper check : $VERIFY check   (daily via cron, log: journalctl -t lab-verify)"
echo "  Edit code    : bash harden-lab.sh --unlock  →  edit  →  commit  →  --lock"
echo "  Baseline     : re-run --lock (or $VERIFY baseline) after every legitimate change"
echo "  SSH          : applied MANUALLY per the audit above (intentionally not automated)"
echo
echo "${B}Hardening applied. Code is read-only; tamper detection is live.${N}"
