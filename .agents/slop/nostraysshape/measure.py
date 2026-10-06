#!/usr/bin/env python3
"""Measure what the five missed files have in common, against ALL of tinybendygrad/.

Read-only. Discovery, not a hand list: os.walk over tinybendygrad/.
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PORT = ROOT / "tinybendygrad"
FIVE = [
    "runtime/zzdiag.bend",
    "runtime/zzread.bend",
    "runtime/zzsplit.bend",
    "runtime/support/zz_objc_mutant.bend",
    "runtime/support/am/ip_scratch_sweep.bend",
]

IMPORT = re.compile(r"^\s*import\s+([^\s]+\.bend)\b", re.M)
MAIN = re.compile(r"^\s*def\s+main\s*\(", re.M)


def all_bend() -> list[Path]:
    out = []
    for dp, dn, fn in os.walk(PORT):
        dn[:] = [d for d in dn if d not in {"__pycache__"}]
        out.extend(Path(dp) / f for f in fn if f.endswith(".bend"))
    return sorted(out)


def resolve(src: Path, spec: str) -> Path | None:
    """Resolve an import spec (bare 'Base', or a relative './x.bend')."""
    if spec == "Base":
        return None  # the substrate
    base = (src.parent / spec).resolve()
    return base if base.exists() else None


def main() -> int:
    files = all_bend()
    rel = {f: str(f.relative_to(ROOT)) for f in files}

    # --- import graph -------------------------------------------------------
    imported_by: dict[Path, list[Path]] = {f: [] for f in files}
    imports: dict[Path, list[Path]] = {f: [] for f in files}
    unresolved = []
    for f in files:
        text = f.read_text(errors="replace")
        for spec in IMPORT.findall(text):
            tgt = resolve(f, spec)
            if tgt is None:
                if spec != "Base":
                    unresolved.append((rel[f], spec))
                continue
            if tgt in imported_by:
                imported_by[tgt].append(f)
                imports[f].append(tgt)

    five = [f for f in files if str(f.relative_to(PORT)) in FIVE]
    print(f"port .bend files: {len(files)}")
    print(f"unresolved non-Base imports: {len(unresolved)} {unresolved[:5]}")

    # --- candidate predicates ----------------------------------------------
    def has_main(f: Path) -> bool:
        return bool(MAIN.search(f.read_text(errors="replace")))

    def nothing_imports(f: Path) -> bool:
        return not imported_by[f]

    def imports_nothing(f: Path) -> bool:
        return not imports[f]

    def orphan(f: Path) -> bool:
        return nothing_imports(f) and imports_nothing(f)

    def zz_prefix(f: Path) -> bool:
        return f.name.startswith("zz")

    def residue_suffix(f: Path) -> bool:
        return bool(re.search(r"_mutant|_probe|_scratch|_sweep|_diag|^zz|\.mut$", f.name))

    def names_another_bend(f: Path) -> bool:
        """Header claims to be a port/copy of another file: a docstring path."""
        text = f.read_text(errors="replace")
        return bool(re.search(r"#\s*tinybendygrad/\S+\.bend\b", text))

    cands = {
        "HAS MAIN": has_main,
        "NOTHING IMPORTS IT": nothing_imports,
        "IMPORTS NOTHING": imports_nothing,
        "ORPHAN (neither)": orphan,
        "zz prefix": zz_prefix,
        "residue suffix/zz": residue_suffix,
        "names another .bend in header": names_another_bend,
    }

    print("\n=== candidate predicate vs the five and the other 139 ===")
    for name, pred in cands.items():
        hits = [f for f in files if pred(f)]
        five_hit = [f for f in five if pred(f)]
        fp = [f for f in hits if f not in five]
        print(f"\n[{name}] fires on {len(hits)}/{len(files)}; "
              f"of the five: {len(five_hit)}/5; false positives: {len(fp)}")
        print(f"  five: {[rel[f].replace('tinybendygrad/','') for f in five_hit]}")
        if fp:
            print(f"  FP: {[rel[f].replace('tinybendygrad/','') for f in fp]}")

    print("\n=== the five, one block each ===")
    for f in five:
        text = f.read_text(errors="replace")
        print(f"\n{rel[f]}  ({f.stat().st_size} B, {text.count(chr(10))+1} lines)")
        print(f"  has main: {has_main(f)}   nothing imports: {nothing_imports(f)}   "
              f"imports nothing: {imports_nothing(f)}")
        head = [ln for ln in text.splitlines()[:3]]
        print(f"  head: {head}")
        print(f"  imports: {[rel[t] for t in imports[f]]}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
