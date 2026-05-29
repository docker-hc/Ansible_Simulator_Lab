#!/usr/bin/env python3
"""gather_hba_wwn.py — collect HBA WWN logins via raidcom for each array.

Runs on the mgmt node where HORCM instances 1001/1004/1005/1006 are live.
For each array it enumerates ports -> host groups -> HBA WWNs and writes
exports/raw/hba_wwn.json in the same result shape as the module gathers.

Usage:
    python3.11 scripts/gather_hba_wwn.py \
        --map "810294:1001,845666:1004,840006:1005,845665:1006" \
        --user maintenance --password raid-maintenance \
        --out exports/raw/hba_wwn.json
"""

import argparse
import json
import subprocess


def run(args):
    try:
        p = subprocess.run(args, capture_output=True, text=True, timeout=60)
        return p.stdout or ""
    except Exception:
        return ""


def parse_ports(text):
    ports = []
    for line in text.splitlines():
        f = line.split()
        if len(f) >= 3 and f[0].startswith("CL") and f[2] == "TAR":
            if f[0] not in ports:
                ports.append(f[0])
    return ports


def parse_host_grp(text):
    out = []
    for line in text.splitlines():
        f = line.split()
        if len(f) >= 3 and f[0].startswith("CL") and f[1].isdigit():
            out.append((f[1], f[2]))
    return out


def parse_hba_wwn(text):
    out = []
    for line in text.splitlines():
        f = line.split()
        if len(f) >= 4 and f[0].startswith("CL") and f[1].isdigit():
            wwn = f[3]
            nick = f[5] if len(f) >= 6 else ""
            if len(wwn) == 16 and all(c in "0123456789abcdefABCDEF" for c in wwn):
                out.append((wwn, nick))
    return out


def gather_array(serial, inst, user, pw):
    login = ["-login", user, pw]
    ih = f"-IH{inst}"
    records = []
    ports_text = run(["/usr/bin/raidcom", "get", "port", ih] + login)
    for port in parse_ports(ports_text):
        hg_text = run(["/usr/bin/raidcom", "get", "host_grp", "-port", port, ih] + login)
        for gid, gname in parse_host_grp(hg_text):
            wwn_text = run(["/usr/bin/raidcom", "get", "hba_wwn",
                            "-port", f"{port}-{gid}", ih] + login)
            for wwn, nick in parse_hba_wwn(wwn_text):
                records.append({
                    "port_id": port, "host_group_number": gid,
                    "host_group_name": gname, "hba_wwn": wwn,
                    "nickname": nick, "source": "login",
                })
    return records


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--map", required=True, help="serial:inst,serial:inst,...")
    ap.add_argument("--user", default="maintenance")
    ap.add_argument("--password", default="raid-maintenance")
    ap.add_argument("--out", default="exports/raw/hba_wwn.json")
    args = ap.parse_args()
    results = []
    for pair in args.map.split(","):
        if ":" not in pair:
            continue
        serial, inst = pair.split(":", 1)
        recs = gather_array(serial.strip(), inst.strip(), args.user, args.password)
        results.append({"item": {"serial": serial.strip()},
                        "ansible_facts": {"hba_wwns": recs}})
        print(f"  {serial.strip()} (HORCM {inst.strip()}): {len(recs)} HBA WWN login(s)")
    with open(args.out, "w") as fh:
        json.dump(results, fh, indent=2)
    print(f"  wrote {args.out}")


if __name__ == "__main__":
    main()
