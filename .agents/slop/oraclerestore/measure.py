#!/usr/bin/env python3
"""CRLF, diff size, byte accounting, and the manifest's debt -- all measured, not remembered.

    .venv/bin/python .agents/slop/oraclerestore/measure.py
"""
from __future__ import annotations

import csv
import pathlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[3]
MANIFEST = pathlib.Path(".agents/slop/oracles259/MANIFEST.tsv")
CRLF = b"\r\n"


def main() -> None:
    head = subprocess.run(["git", "show", f"HEAD:{MANIFEST}"], cwd=ROOT,
                          capture_output=True).stdout
    new = MANIFEST.read_bytes()

    print("LINE ENDINGS")
    for name, b in (("HEAD", head), ("WORK", new)):
        bare_lf = b.count(b"\n") - b.count(CRLF)
        print(f"  {name}  CRLF={b.count(CRLF)}  bare-LF={bare_lf}  bytes={len(b)}")
    nul = "YES" if b"\x00" in new else "no"
    print(f"  nul byte present? {nul}")

    diff = subprocess.run(["git", "diff", "--numstat", "--", str(MANIFEST)], cwd=ROOT,
                          capture_output=True, text=True).stdout.strip()
    stat = subprocess.run(["git", "diff", "--stat", "--", str(MANIFEST)], cwd=ROOT,
                          capture_output=True, text=True).stdout.strip().splitlines()[-1]
    print(f"\nDIFF  numstat: {diff}\n      stat   :{stat}")

    with open(MANIFEST, newline="") as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))

    delta = len(new) - len(head)
    rev_growth = sum(len("b504abf77") - len("HEAD") for _ in rows)
    appended = sum(1 + len(r["restore_at_HEAD"]) for r in rows)
    header = 1 + len("restore_at_HEAD")
    print(f"\nBYTE ACCOUNTING  delta={delta}  appended+tab={appended}  rev_growth={rev_growth}"
          f"  header={header}  sum={appended + rev_growth + header}"
          f"  {'MATCH' if delta == appended + rev_growth + header else 'MISMATCH'}")

    absent = [r["path"] for r in rows
              if subprocess.run(["git", "cat-file", "-e", f"HEAD:{r['path']}"],
                                cwd=ROOT, capture_output=True).returncode != 0]
    (ROOT / ".agents/slop/oraclerestore/debt.rows").write_text("".join(p + "\n" for p in absent))
    print(f"\nDEBT  old-name rows absent at HEAD: {len(absent)}/{len(rows)}  (debt.rows)")


if __name__ == "__main__":
    main()
