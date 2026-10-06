#!/usr/bin/env python3
"""THE PLANT POPULATION, BY DISCOVERY, AND EVERY LITERAL PATH EACH ONE NAMES.

    .venv/bin/python .agents/slop/shadowcopies/scanplants.py

A plant is a file under `.agents/slop/` whose basename contains `plant` and ends `.py`
(the brief's two globs, unioned). The population is an `os.walk`, never a hand list --
`checks/sweep.py` paid for that lesson at `LIVE_UNITS`.

For each plant every string constant that LOOKS like a repo-relative path (contains a
`/`, or carries a known extension) is resolved against the repo root. A literal that is
not on disk is DANGLING; one that was once tracked and is now deleted is a STALE RENAME
TARGET. Both are the same defect at different ages. Exit 1 if any plant's named path
dangles, so a caller reading `$?` sees the population is not healthy.
"""
from __future__ import annotations

import ast
import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(subprocess.run(["git", "rev-parse", "--show-toplevel"],
                           capture_output=True, text=True, check=True).stdout.strip())
SLOP = ROOT / ".agents" / "slop"
EXTS = (".py", ".sh", ".bend", ".rows", ".out", ".err", ".md", ".tsv", ".txt",
        ".json", ".mjs", ".js", ".ts", ".rs", ".c")
# A READ probe is a literal the plant does NOT create. We cannot know which those are,
# so we report EVERY literal and its fate, and mark the ones on empty/vanishable ground.
CREATED_HINTS = ("plant", "probe", "mut", "tmp", "scratch", "target", "box")


def plants() -> list[Path]:
    out = []
    for dp, dn, fn in os.walk(SLOP):
        if ".git" in dp.split(os.sep):
            continue
        for f in fn:
            if f.endswith(".py") and "plant" in f.lower():
                out.append(Path(dp) / f)
    return sorted(out)


def literals(src: str) -> list[tuple[int, str]]:
    found = []
    try:
        tree = ast.parse(src)
    except SyntaxError:
        return found
    for node in ast.walk(tree):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            s = node.value
            if s.startswith(("http://", "https://")) or "\n" in s:
                continue
            looks = ("/" in s and any(s.endswith(e) or (e + ".") in s for e in EXTS)) \
                or s.startswith((".agents/", "checks/", "runs/", "oracles/", "gates/",
                                 "tinybendygrad/", ".venv/")) \
                or (Path(s).suffix in EXTS and " " not in s
                    and not s.startswith(("HEAD:", "~", "bend ")))
            if looks:
                found.append((node.lineno, s))
    return found


def tracked(rel: str) -> bool:
    return subprocess.run(["git", "-C", str(ROOT), "ls-files", "--error-unmatch", rel],
                          capture_output=True).returncode == 0


def ever_existed(rel: str) -> bool:
    r = subprocess.run(["git", "-C", str(ROOT), "log", "--all", "--oneline", "--", rel],
                       capture_output=True, text=True)
    return bool(r.stdout.strip())


def rename_sibling(rel: str) -> str | None:
    """The rename signature: the named path is gone but a same-stem sibling with a
    different extension is on disk. This is the `.txt` retirement's fingerprints --
    `.txt` -> `.rows`/`.out`. A rename is not a deletion: the answer moved."""
    p = ROOT / rel
    if p.exists():
        return None
    stripped = ROOT / rel[:-len(".txt")] if rel.endswith(".txt") else None
    if stripped is not None and stripped.is_file():
        return str(stripped.relative_to(ROOT))
    for sib in sorted(p.parent.glob(p.stem + ".*")) if p.parent.is_dir() else []:
        if sib.is_file() and sib.suffix != p.suffix:
            return str(sib.relative_to(ROOT))
    return None


def main() -> int:
    pop = plants()
    rows = []
    dangling_total = []
    for p in pop:
        rel_p = str(p.relative_to(ROOT))
        src = p.read_text(errors="replace")
        mentions_oracles = '"oracles"' in src or "'oracles'" in src or '"oracles/' in src
        for lineno, lit in literals(src):
            lit_clean = lit.lstrip("/")
            if any(c in lit_clean for c in "*?["):
                continue                       # a glob is a pattern, not a path
            bases = [lit_clean]
            # A BARE filename (no slash) is resolved against the two bases a plant here uses
            # for the renamed corpus: the repo root and `oracles/`. The `.txt` retirement
            # moved 258 files under `oracles/` to `.rows`/`.err`/`.bend`/`.md`/`.tsv`, and a
            # plant that names `oracles / "blob-bd.txt"` spells only the basename. The
            # `oracles/` base is only credible for a plant that mentions `oracles`.
            if "/" not in lit_clean:
                bases += [f"{p.parent.relative_to(ROOT)}/{lit_clean}"]
                if mentions_oracles:
                    bases.append(f"oracles/{lit_clean}")
            for base in bases:
                full = ROOT / base
                exists = full.exists()
                sib = rename_sibling(base)
                if exists:
                    state = "on-disk"
                elif sib:
                    state = f"RENAMED->{sib}"
                elif ever_existed(base):
                    state = "deleted-in-history"
                else:
                    state = "never-existed"
                rows.append((rel_p, lineno, base, state, tracked(base)))
                if sib and (base == lit_clean or base.startswith("oracles/")):
                    dangling_total.append((rel_p, lineno, base, sib))
                if exists:
                    break
    print(f"# plants={len(pop)}  literal-paths={len(rows)}")
    print("# plant\tline\tpath\tstate\ttracked")
    for rel_p, lineno, lit, state, tr in rows:
        print(f"{rel_p}\t{lineno}\t{lit}\t{state}\t{'T' if tr else '-'}")
    print()
    print(f"# RENAME-DANGLING (named, gone, same-stem sibling on disk): {len(dangling_total)}")
    for rel_p, lineno, lit, sib in dangling_total:
        print(f"  {rel_p}:{lineno}  {lit}  ->  {sib}")
    return 1 if dangling_total else 0


if __name__ == "__main__":
    sys.exit(main())
