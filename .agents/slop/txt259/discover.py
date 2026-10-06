#!/usr/bin/env python3
"""Re-derive the `oracles/**.txt` population BY DISCOVERY, and emit PLAN.tsv + census.out.

NOTHING IS RENAMED OR DELETED. This reads only.

    .venv/bin/python .agents/slop/txt259/discover.py

  population  = os.walk(oracles/) + endswith(".txt") -- a directory walk, not a hand list
  class       = content only, by the census's three-mechanism classifier, IMPORTED BY PATH from
                checks/oracle-txt-census.py, plus an INDEPENDENT tabular/prose probe so a `.tsv` or
                `.md`-shaped file is not silently called a row dump
  reach       = the census instrument's own token-resolved LIVE/STALE/SHADOW/NOTHING
  readers     = git grep of every tracked `.sh`/`.py` for the basename or repo path, as file:line
"""
from __future__ import annotations

import csv
import importlib.util
import os
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parents[3]
ORACLES = ROOT / "oracles"
ME = os.path.relpath(os.path.abspath(__file__), ROOT)


def load(path: pathlib.Path, name: str):
    spec = importlib.util.spec_from_file_location(name, path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


differ = load(ROOT / "checks/differ.py", "differ")
census = load(ROOT / "checks/oracle-txt-census.py", "census")

TAB = re.compile(r"^[^\t]+\t[^\t]+")                 # a line with an embedded TAB
HEADING = re.compile(r"^\s*#{1,6}\s+\S")             # a markdown heading
PROSE_SENT = re.compile(r"[.!?]\s+[A-Z]")            # two sentences on one line


def independent_class(text: str) -> str:
    """A SECOND classifier sharing no threshold with the census, for the ambiguity the task flags:
    a tab-separated table and prose both lack `key=value` rows and both get called rows."""
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if not lines:
        return "empty"
    tabbed = sum(bool(TAB.match(ln)) for ln in lines) / len(lines)
    heads = sum(bool(HEADING.match(ln)) for ln in lines) / len(lines)
    prose = sum(bool(PROSE_SENT.search(ln)) for ln in lines) / len(lines)
    if tabbed >= 0.5:
        return "tsv"
    if heads >= 0.2 or prose >= 0.2:
        return "md"
    return "rows"


def git(*args: str) -> str:
    return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True).stdout


TRACKED = [r for r in git("ls-files").split()
           if pathlib.Path(r).suffix in (".sh", ".py")
           and not r.startswith(("references/", "tinygrad/"))
           and r not in (os.path.relpath(ROOT / "checks/oracle-txt-census.py", ROOT), ME)]
_CODE = {ROOT / r: (ROOT / r).read_text(errors="replace").splitlines()
         for r in TRACKED if (ROOT / r).is_file()}


def readers_for(rel: str) -> list[str]:
    """Every tracked `.sh`/`.py` line naming this file by basename or by repo path."""
    base = pathlib.Path(rel).name
    hits = []
    for path, lines in _CODE.items():
        for i, ln in enumerate(lines, 1):
            if base in ln or rel in ln:
                hits.append(f"{os.path.relpath(path, ROOT)}:{i}")
    return sorted(hits)


def main() -> int:
    txts = sorted(p for p in ORACLES.rglob("*.txt") if p.is_file())
    declared = differ.declared()
    pinned = set(differ.ORACLE_PIN)
    reach = {r["path"]: r for r in census.census()[0]}

    plan = []
    classes: dict[str, int] = {}
    counts = {"LIVE": 0, "SHADOW": 0, "STALE": 0, "NOTHING": 0}
    for p in txts:
        rel = str(p.relative_to(ROOT))
        text = p.read_text(errors="replace")
        cls = census.shape(p, 2.0778)                     # census three-mechanism verdict
        ind = independent_class(text)                     # our second opinion
        if cls == "rowdump" and ind != "rows":
            cls = f"rowdump?/{ind}"                       # census says rows, probe disagrees
        classes[cls] = classes.get(cls, 0) + 1
        row = reach.get(rel, {})
        r = ("LIVE" if row.get("live") else "SHADOW" if row.get("shadow")
             else "STALE" if row.get("stale") else "NOTHING")
        counts[r] += 1
        plan.append(dict(
            path=rel, cls=cls, probe=ind, reach=r,
            readers="; ".join(readers_for(rel)) or "-",
            pin_covers=("declared-boundary" if pathlib.Path(rel).name in declared
                        else "PINNED-BODY" if rel in pinned else "none"),
            new_path=str(p.with_suffix(".rows")).replace(str(ROOT) + "/", ""),
            restore=f"git cat-file blob $(git rev-parse HEAD:{rel}) > {rel}"))

    out = ROOT / ".agents/slop/txt259"
    with open(out / "PLAN.tsv", "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(plan[0]), delimiter="\t")
        w.writeheader()
        w.writerows(plan)

    lines = [
        f"  POPULATION (os.walk oracles/ + endswith .txt): {len(txts)}",
        f"  classes : {classes}",
        f"  reach   : {counts}",
        f"  declared() names any oracles/.txt? "
        f"{[n for n in declared if (ORACLES / n).exists()] or 'NONE'}",
        f"  ORACLE_PIN names any oracles/.txt? "
        f"{[n for n in pinned if (ORACLES / n).exists()] or 'NONE (pins .agents/slop/diffpy/*.sh)'}",
    ]
    print("\n".join(lines))
    (out / "census.out").write_text("\n".join(lines) + "\n")
    print(f"  wrote {out / 'PLAN.tsv'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
