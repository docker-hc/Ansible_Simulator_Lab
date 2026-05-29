#!/usr/bin/env python3
"""facts_to_csv.py — optional CSV export alongside the xlsx.

Reads exports/raw/*.json from playbooks/08-export-facts.yml and writes:
  exports/csv/summary.csv            one row per array
  exports/csv/<fact_type>.csv        all arrays stacked, first column = serial

Usage:
    python3.11 scripts/facts_to_csv.py [--raw DIR] [--out DIR]
"""

import argparse
import csv
import json
import os
import sys

FACT_TYPES = ["system", "parity_groups", "ports", "pools", "ldevs", "host_groups"]


def load_raw(raw_dir):
    arrays = {}
    for ft in FACT_TYPES:
        path = os.path.join(raw_dir, f"{ft}.json")
        if not os.path.exists(path):
            print(f"  ! missing {path} — skipping {ft}")
            continue
        with open(path) as fh:
            results = json.load(fh)
        for item in results:
            serial = str(item.get("item", {}).get("serial", "unknown"))
            payload = extract_payload(item.get("ansible_facts", {}))
            arrays.setdefault(serial, {})[ft] = payload
    return arrays


def extract_payload(ansible_facts):
    data = {k: v for k, v in ansible_facts.items() if k != "user_consent_required"}
    if not data:
        return {}
    if len(data) == 1:
        return next(iter(data.values()))
    for v in data.values():
        if isinstance(v, list):
            return v
    return data


def flat(value):
    if isinstance(value, (dict, list)):
        return json.dumps(value, separators=(",", ":"))
    if value is None:
        return ""
    return value


def num(payload):
    if isinstance(payload, list):
        return len(payload)
    if isinstance(payload, dict) and payload:
        return 1
    return 0


def write_summary(out_dir, arrays):
    headers = [
        "serial", "model", "microcode", "address",
        "total_capacity", "free_capacity", "efficiency",
        "parity_groups", "ports", "pools", "ldevs", "host_groups",
    ]
    path = os.path.join(out_dir, "summary.csv")
    with open(path, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(headers)
        for serial in sorted(arrays):
            a = arrays[serial]
            sysd = a.get("system", {}) if isinstance(a.get("system"), dict) else {}
            eff = sysd.get("total_efficiency", {})
            eff_ratio = eff.get("total_ratio", "") if isinstance(eff, dict) else ""
            w.writerow([
                serial,
                sysd.get("model", ""),
                sysd.get("microcode_version", ""),
                sysd.get("controller_address", ""),
                sysd.get("total_capacity", ""),
                sysd.get("free_capacity", ""),
                (eff_ratio + ":1") if eff_ratio else "",
                num(a.get("parity_groups")),
                num(a.get("ports")),
                num(a.get("pools")),
                num(a.get("ldevs")),
                num(a.get("host_groups")),
            ])
    print(f"  wrote {path}")


def write_fact_csv(out_dir, fact_type, arrays):
    # Collect a stable union of headers across all arrays for this fact type.
    headers = []
    stacked = []
    for serial in sorted(arrays):
        payload = arrays[serial].get(fact_type, [])
        if isinstance(payload, dict):
            payload = [payload]
        if not isinstance(payload, list):
            continue
        for row in payload:
            if not isinstance(row, dict):
                continue
            for k in row:
                if k not in headers:
                    headers.append(k)
            stacked.append((serial, row))

    path = os.path.join(out_dir, f"{fact_type}.csv")
    with open(path, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["serial"] + headers)
        for serial, row in stacked:
            w.writerow([serial] + [flat(row.get(h, "")) for h in headers])
    print(f"  wrote {path} ({len(stacked)} rows)")




def write_hba_csv(out_dir, raw_dir):
    import json as _j
    path = os.path.join(raw_dir, "hba_wwn.json")
    rows = []
    if os.path.exists(path):
        with open(path) as fh:
            for item in _j.load(fh):
                serial = str(item.get("item", {}).get("serial", ""))
                for r in item.get("ansible_facts", {}).get("hba_wwns", []):
                    rows.append([serial, r.get("port_id", ""), r.get("host_group_number", ""),
                                 r.get("host_group_name", ""), r.get("hba_wwn", ""),
                                 r.get("nickname", ""), r.get("source", "")])
    p = os.path.join(out_dir, "hba_wwn.csv")
    with open(p, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["serial", "port_id", "host_group_number", "host_group_name",
                    "hba_wwn", "nickname", "source"])
        w.writerows(rows)
    print(f"  wrote {p} ({len(rows)} rows)")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--raw", default="exports/raw")
    ap.add_argument("--out", default="exports/csv")
    args = ap.parse_args()

    if not os.path.isdir(args.raw):
        sys.exit(f"raw dir not found: {args.raw} (run 08-export-facts.yml first)")

    arrays = load_raw(args.raw)
    if not arrays:
        sys.exit("no array data found in raw JSON")

    os.makedirs(args.out, exist_ok=True)
    write_summary(args.out, arrays)
    for ft in FACT_TYPES:
        write_fact_csv(args.out, ft, arrays)
    write_hba_csv(args.out, args.raw)
    print(f"  arrays: {', '.join(sorted(arrays))}")


if __name__ == "__main__":
    main()
