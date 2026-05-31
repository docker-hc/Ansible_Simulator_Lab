#!/usr/bin/env python3.11
"""
gather_licenses.py — collect license inventory per array via raidcom.

Licenses are not exposed by an Ansible facts module for VSP block arrays,
so we read them with `raidcom get license`, mirroring gather_hba_wwn.py:
the script logs in to each HORCM instance itself using the supplied
credentials (the wrapper only starts/stops HORCM; auth lives here).

Input : --map  "810294:1001,840006:1004,..."   (serial:instance CSV, as hba_map)
        --user / --password  (raidcom user-auth credentials from the vault)
Output: --out  exports/raw/licenses.json

JSON shape mirrors the *_facts raw files so facts_to_xlsx.py loads it the
same way: list of { "serial": <serial>, "ansible_facts": { "licenses": [...] } }.

Parsed against real VSP One B26 output, header:
  PRO_ID STS Type L Cap_Perm(TB) Cap_Used(GB)  -  Term Name
Name is the trailing double-quoted field (may contain spaces).
"""
import argparse
import json
import re
import subprocess
import sys

HEADER_COLS = ["PRO_ID", "STS", "Type", "L", "Cap_Perm_TB",
               "Cap_Used_GB", "Reserved", "Term"]


def _run(cmd):
    return subprocess.run(cmd, capture_output=True, text=True,
                          timeout=60, check=False)


def login(instance, user, password):
    """raidcom -login for one instance; return error string or None."""
    try:
        r = _run(["raidcom", "-login", user, password, "-I" + str(instance)])
    except (subprocess.TimeoutExpired, FileNotFoundError) as exc:
        return f"{type(exc).__name__}: {exc}"
    return None if r.returncode == 0 else (r.stderr or r.stdout or "").strip()


def logout(instance):
    try:
        _run(["raidcom", "-logout", "-I" + str(instance)])
    except Exception:
        pass


def get_license(instance):
    """Run `raidcom get license` for one instance; return (error, rows)."""
    try:
        r = _run(["raidcom", "get", "license", "-I" + str(instance)])
    except (subprocess.TimeoutExpired, FileNotFoundError) as exc:
        return f"{type(exc).__name__}: {exc}", []
    if r.returncode != 0:
        return (r.stderr or "").strip(), []
    return None, parse_license_table(r.stdout)


def parse_license_table(text):
    """Name is the trailing quoted field; leading columns are positional."""
    lines = [ln.rstrip() for ln in text.splitlines() if ln.strip()]
    if not lines:
        return []
    rows = []
    for ln in lines[1:]:                       # skip header
        m = re.match(r'^(.*?)\s+"(.*)"\s*$', ln)
        if m:
            positional, name = m.group(1).split(), m.group(2)
        else:
            parts = ln.split()
            positional, name = parts[:-1], (parts[-1] if parts else "")
        row = dict(zip(HEADER_COLS, positional))
        row["Name"] = name
        row["installed"] = (row.get("STS", "").upper() == "INS")
        rows.append(row)
    return rows


def parse_map(s):
    """Parse 'serial:instance,serial:instance' (same format as hba_map)."""
    out = {}
    for pair in s.split(","):
        pair = pair.strip()
        if not pair:
            continue
        serial, inst = pair.split(":")
        out[serial.strip()] = inst.strip()
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", required=True, help='"serial:instance,..." (hba_map format)')
    ap.add_argument("--user", required=True)
    ap.add_argument("--password", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    try:
        serial_map = parse_map(args.map)
    except ValueError:
        sys.exit(f"bad --map (expected serial:instance,...): {args.map!r}")

    results = []
    for serial, instance in serial_map.items():
        err = login(instance, args.user, args.password)
        if err:
            results.append({"serial": str(serial),
                            "ansible_facts": {"licenses": [], "_error": f"login: {err}"}})
            print(f"  ! login failed {serial} (I{instance}): {err}", file=sys.stderr)
            continue
        gerr, rows = get_license(instance)
        logout(instance)
        results.append({"serial": str(serial),
                        "ansible_facts": {"licenses": rows, "_error": gerr}})
        if gerr:
            print(f"  ! license gather failed {serial} (I{instance}): {gerr}", file=sys.stderr)
        else:
            ins = sum(1 for r in rows if r.get("installed"))
            print(f"  {serial} (I{instance}): {len(rows)} licenses, {ins} installed")

    with open(args.out, "w") as fh:
        json.dump(results, fh, indent=2)
    print(f"wrote {args.out}: {len(results)} arrays")


if __name__ == "__main__":
    main()
