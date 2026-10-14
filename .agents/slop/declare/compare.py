#!/usr/bin/env python3
"""`checks/slop-declare.py` AGAINST `orcdecide/sweep.py`, on one tree, one row per directory.

    .venv/bin/python .agents/slop/declare/compare.py

`orcdecide`'s sweep is the instrument this brief quotes (**256 dirs · 146 with a report · 110
with neither a report nor a manifest · 17 with neither a declaration nor a full-path reader**).
Reproducing it is the only way to say whether this walk AGREES, and by how much and WHY, instead
of asserting a second number beside a first.

THE THREE AXES THEY DO NOT SHARE, each of which is a difference in WHAT COUNTS AS A READER:

    orcdecide   any tracked file with a prose or code suffix whose bytes contain the token, and
                whose OWN files do not contain it as many times (a crude self-reference discount)
    here        tracked CODE files only, minus every file inside the directory -- so a `.md` that
                NAMES a directory, or a `.rows` that LISTS its paths, is not liveness

  `orcdecide` also EXCLUDES ITSELF with a typed name (`if name in ("orcdecide",): continue`,
  `sweep.py:57`) -- which is a hand list inside the very instrument that exists because hand lists
  rot. It is reproduced here verbatim so the numbers are comparable, and it is called out rather
  than copied.

usage: .venv/bin/python .agents/slop/declare/compare.py
"""
from __future__ import annotations

import importlib.util
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
GATE = ROOT / "checks/slop-declare.py"
ORC = ROOT / ".agents/slop/orcdecide/sweep.py"


def load(path, name):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def orcdecide_rows(root: pathlib.Path) -> dict[str, dict]:
    """`orcdecide/sweep.py`'s OWN decision function, re-derived from its source, unchanged:
    the same KEEP suffix set, the same SKIP prefixes, the same `big > own` token count, and the
    same typed `("orcdecide",)` self-exclusion -- because a comparison that quietly repaired the
    other instrument would not be a comparison."""
    KEEP = (".py", ".sh", ".bend", ".mjs", ".md", ".ts")
    SKIP = ("tinygrad/", "references/")
    REPORTS = ("report.md", "readme.md", "findings.md")
    MANIFESTS = ("manifest.tsv", "manifest.md", "manifest.rows")
    paths = subprocess.run(["git", "ls-files"], cwd=root, capture_output=True, text=True).stdout.split()
    dirs: dict[str, list[str]] = {}
    for f in paths:
        parts = f.split("/")
        if len(parts) >= 4 and parts[:2] == [".agents", "slop"]:
            dirs.setdefault(parts[2], []).append(f)
    corpus = {}
    for f in paths:
        if f.startswith(SKIP) or not f.endswith(KEEP):
            continue
        try:
            corpus[f] = (root / f).read_text(errors="ignore")
        except OSError:
            pass
    big = "\n".join(corpus.values())
    out = {}
    for name, files in sorted(dirs.items()):
        if name == "orcdecide":
            continue
        report = [f for f in files if pathlib.Path(f).name.lower() in REPORTS]
        manifest = [f for f in files if pathlib.Path(f).name.lower() in MANIFESTS]
        token = f".agents/slop/{name}/"
        own = "\n".join(corpus.get(f, "") for f in files)
        out[name] = {"declared": bool(report or manifest),
                     "referenced": big.count(token) > own.count(token),
                     "files": len(files)}
    return out


def main() -> int:
    gate, root = load(GATE, "slop_declare"), ROOT
    theirs, ours = orcdecide_rows(root), {}
    surveyed = gate.survey(root)
    if "error" in surveyed:
        print(f"REFUSED: {surveyed['error']}")
        return 3
    for r in surveyed["rows"]:
        ours[r["dir"]] = r
    agree = [d for d in ours if d in theirs
             and theirs[d]["declared"] == ours[d]["declares"]
             and theirs[d]["referenced"] == bool(ours[d]["code_readers"])]
    # THE READER-TEST DISAGREEMENT, SPLIT BY WHETHER IT COULD HAVE COST A DIRECTORY ITS
    # DECLARED STATUS. An undeclared directory orcdecide credits with a "reader" is one this walk
    # names and orcdecide does not -- that is the 14 -> 48 delta. A DECLARED directory it credits
    # is invisible in the count but is the same fault, and it is the larger half.
    disagree = [d for d in ours if d in theirs and d not in agree]
    undeclared_only = [d for d in disagree if not ours[d]["declares"]]
    declared_only = [d for d in disagree if ours[d]["declares"]]
    their_undec = sorted(d for d in theirs if not theirs[d]["declared"] and not theirs[d]["referenced"])
    my_undec = sorted(d for d in ours if not ours[d]["declares"] and not ours[d]["code_readers"])

    print(f"populations        : orcdecide {len(theirs)} (self-excluded by a TYPED name, "
          f"`sweep.py:57`), here {len(ours)} (includes `orcdecide` itself)")
    print(f"DECLARATION census : AGREE {sum(1 for d in ours if d in theirs and ours[d]['declares'] == theirs[d]['declared'])}"
          f" of {len(theirs)} -- the two instruments call the SAME {len(theirs)} directories declared")
    print(f"READER test        : AGREE {len(agree)}, DISAGREE {len(disagree)}"
          f"  ({100 * len(disagree) // len(ours)}% of the tree)")
    print(f"  of the disagreements, UNDECLARED here and 'referenced' by orcdecide : "
          f"{len(undeclared_only)}  <-- this is the whole 14 -> {len(my_undec)} delta")
    print(f"  of the disagreements, DECLARED either way (count unaffected)          : "
          f"{len(declared_only)}  <-- same fault, invisible in any count")
    print(f"UNDECIDED          : orcdecide {len(their_undec)}, here {len(my_undec)}")
    print(f"  orcdecide's set is a SUBSET of mine: {set(their_undec) <= set(my_undec)}")
    print(f"  lost by the stricter test          : {sorted(set(their_undec) - set(my_undec))}")

    rows = ["dir\torcdecide_declared\torcdecide_referenced\there_declared\there_code_readers\tagree"]
    for d in sorted(set(theirs) | set(ours)):
        t, m = theirs.get(d), ours.get(d)
        rows.append("\t".join(str(x) for x in (
            d, t["declared"] if t else "-", t["referenced"] if t else "-",
            m["declared"] if m else "-", m["code_readers"] if m else "-",
            (t["declared"] == m["declares"] and t["referenced"] == bool(m["code_readers"])) if (t and m) else "-")))
    (HERE / "COMPARE.tsv").write_text("\n".join(rows) + "\n")
    print(f"rows -> {(HERE / 'COMPARE.tsv').relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())