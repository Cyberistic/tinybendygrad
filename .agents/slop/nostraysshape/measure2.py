#!/usr/bin/env python3
"""Candidate 2: the tree's OWN declaration. The port's rule is "one .bend per
upstream .py, and the header says which". A .bend whose header does not name
itself is not a port target.

Read-only, discovery over tinybendygrad/.
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PORT = ROOT / "tinybendygrad"
FIVE = {
    "runtime/zzdiag.bend",
    "runtime/zzread.bend",
    "runtime/zzsplit.bend",
    "runtime/support/zz_objc_mutant.bend",
    "runtime/support/am/ip_scratch_sweep.bend",
}

# line 1 (or the leading comment block) says "# tinybendygrad/<path>.bend -- port of ..."
HEADER = re.compile(r"^#\s*tinybendygrad/(\S+\.bend)\b", re.M)
IMPORT = re.compile(r"^\s*import\s+([^\s]+\.bend)\b", re.M)


def bend_files() -> list[Path]:
    out = []
    for dp, dn, fn in os.walk(PORT):
        dn[:] = [d for d in dn if d != "__pycache__"]
        out.extend(Path(dp) / f for f in fn if f.endswith(".bend"))
    return sorted(out)


def self_declared(f: Path) -> bool:
    """The file's header names its OWN relative path."""
    rel = str(f.relative_to(PORT))
    text = f.read_text(errors="replace")
    return any(m == rel for m in HEADER.findall(text))


def header_names_other(f: Path) -> list[str]:
    rel = str(f.relative_to(PORT))
    text = f.read_text(errors="replace")
    return [m for m in HEADER.findall(text) if m != rel]


def main() -> int:
    files = bend_files()
    print(f".bend files: {len(files)}")

    no_self = [f for f in files if not self_declared(f)]
    print(f"\n[NO SELF-HEADER] fires on {len(no_self)}/{len(files)}")
    for f in no_self:
        rel = str(f.relative_to(PORT))
        tag = "FIVE" if rel in FIVE else "other"
        first = f.read_text(errors="replace").splitlines()
        head = next((ln for ln in first if ln.strip()), "")
        print(f"  {tag:5} {rel}   first={head!r}")

    print("\n[HEADER NAMES ANOTHER FILE]")
    for f in files:
        o = header_names_other(f)
        if o:
            rel = str(f.relative_to(PORT))
            tag = "FIVE" if rel in FIVE else "other"
            print(f"  {tag:5} {rel} -> {o}")

    # union test
    union = set(no_self) | {f for f in files if header_names_other(f)}
    print(f"\n[UNION no-self OR names-other] fires {len(union)}/{len(files)}")
    rels = sorted(str(f.relative_to(PORT)) for f in union)
    fp = [r for r in rels if r not in FIVE and r != "runtime/zzprobe2.bend"]
    print("  five covered:", sorted(FIVE & set(rels)))
    print("  extra:", fp)
    return 0


if __name__ == "__main__":
    sys.exit(main())
