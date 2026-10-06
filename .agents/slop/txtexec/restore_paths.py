#!/usr/bin/env python3
"""What the MANIFEST restore commands become after the rename. Do not rewrite -- measure."""
import csv
import subprocess

HEAD = "4d0a2b258"
PRE = "b504abf77"
rows = list(csv.DictReader(open(".agents/slop/oracles259/MANIFEST.tsv"), delimiter="\t"))


def resolves(ref, path):
    return subprocess.run(["git", "cat-file", "-e", f"{ref}:{path}"],
                          capture_output=True).returncode == 0


at_head = [r["path"] for r in rows if resolves(HEAD, r["path"])]
at_pre = [r["path"] for r in rows if resolves(PRE, r["path"])]
print(f"restore old-path resolves at HEAD {HEAD}: {len(at_head)}/{len(rows)}  {at_head}")
print(f"restore old-path resolves at PRE  {PRE}: {len(at_pre)}/{len(rows)}")
