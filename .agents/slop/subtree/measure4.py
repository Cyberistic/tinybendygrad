"""PART 4 -- are the two deeper files GATES, and does any gate consume them?

`entry_reason()` classifies both as `sh-selfref`, which is an ENTRY class. The brief says
"sh-selfref calling them is evidence they are gates". This MEASURES it instead of inferring it:
a reference is a reference only if some gate's source names the path, and a consumer is a
consumer only if it is the thing the tree runs.

Also: does `gate-surface.py` -- which calls `discover()` -- actually EXCLUDE these two from its
census, and does it PRINT the ceiling? Read `gates/gate-surface.py:284-294`: it computes
`only_walk` and prints each `WALK-ONLY` path. So the ceiling IS visible there. The question is
whether the OTHER consumers print it.
"""
import importlib.util
import os
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent / "census4.rows"
rows = []

DEEPER = ["gates/oracles/beautiful-mnist-oracle.sh", "gates/oracles/mixin-op-oracle.sh"]


def emit(*c):
    rows.append("\t".join(str(x) for x in c))


def by_path(p, name):
    spec = importlib.util.spec_from_file_location(name, p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def referenced_by():
    """Every `.py`/`.sh` in the tree whose SOURCE names one of the deeper files' basenames."""
    skip = {".venv", ".git", "__pycache__", "references", "node_modules", "tinybendygrad"}
    for rel in DEEPER:
        stem = Path(rel).stem
        hits = []
        for dirpath, dirnames, filenames in os.walk(ROOT):
            dirnames[:] = [d for d in dirnames if d not in skip]
            for fn in filenames:
                if not fn.endswith((".py", ".sh", ".md")):
                    continue
                p = Path(dirpath) / fn
                try:
                    text = p.read_text(errors="replace")
                except OSError:
                    continue
                if stem not in text:
                    continue
                for i, line in enumerate(text.splitlines(), 1):
                    if stem in line:
                        hits.append(f"{p.relative_to(ROOT)}:{i}: {line.strip()[:100]}")
        emit("REFERENCED", rel, len(hits))
        for h in hits:
            emit("REFERENCED", f"{rel} <-", h)


def head_of_deeper():
    """The first 12 lines of each deeper file, verbatim. This is what makes the
    'they are gates' claim checkable by a reader instead of by my classification."""
    for rel in DEEPER:
        p = ROOT / rel
        emit("HEAD", rel, f"bytes={p.stat().st_size}")
        for i, line in enumerate(p.read_text(errors='replace').splitlines()[:12], 1):
            emit("HEAD", f"{rel}:{i}", line.rstrip())


def entry_vs_lib_split():
    """If `discover()` were recursive, where would each deeper file LAND? `entry_reason()` is the
    classifier, so the answer is the classifier's verdict, not a guess."""
    gp = by_path(ROOT / "gates" / "gates-pop.py", "gp4")
    for rel in DEEPER:
        p = ROOT / rel
        reason = gp.entry_reason(p)
        emit("CLASS", rel, f"entry_reason={reason} "
                           f"is_entry={reason in ('py-main', 'sh-dispatch', 'sh-selfref')}")


def ceiling_visibility():
    """Which consumers PRINT a second, deeper projection beside `discover()`'s number."""
    consumers = {
        "gates/gates-pop.py": None,
        "gates/gate-surface.py": None,
        ".agents/slop/hooks/run.py": None,
        ".agents/slop/hooks/cost.py": None,
        ".agents/slop/plantthe46/reach.py": None,
        ".agents/slop/onemodule/probe.py": None,
    }
    for rel in consumers:
        p = ROOT / rel
        if not p.is_file():
            emit("VISIBLE", rel, "ABSENT")
            continue
        text = p.read_text(errors="replace")
        has_oswalk = bool(re.search(r"os\.walk", text))
        prints_only = bool(re.search(r"only_walk|walk-only|WALK-ONLY|walk_control", text))
        prints_two = bool(re.search(r"vs\b|versus|recursive `os\.walk`", text))
        emit("VISIBLE", rel,
             f"os.walk_in_source={has_oswalk} names_the_control={prints_only} "
             f"prints_two_counts={prints_two}")


def gate_surface_control_line():
    """Read the exact print at `gates/gate-surface.py:288-294` so the report can quote the
    line a reader would see, not a paraphrase of it."""
    src = (ROOT / "gates" / "gate-surface.py").read_text().splitlines()
    for i in range(283, 296):
        emit("SURFACE", f"{i + 1}", src[i].rstrip())


def denom_of_gate_surface():
    """The census `gate-surface` reports, computed WITHOUT running any gate: its `report()`
    would exec every declaring gate, so this reproduces only the two pure projections plus the
    clause-I population split. The number is a MEASUREMENT OF THE POPULATION, not a verdict."""
    gs = by_path(ROOT / "gates" / "gate-surface.py", "gs4")
    gp = by_path(ROOT / "gates" / "gates-pop.py", "gp4b")
    entries, libs = gs.population(ROOT)
    disc = {str(p.relative_to(ROOT)) for p in list(entries) + list(libs)}
    control = gs.walk_control(ROOT, gp.HOMES)
    only_walk = sorted(control - disc)
    only_disc = sorted(disc - control)
    emit("SURFACE_POP", "discover_entries", len(entries))
    emit("SURFACE_POP", "discover_libs", len(libs))
    emit("SURFACE_POP", "discover_total", len(disc))
    emit("SURFACE_POP", "walk_control_total", len(control))
    emit("SURFACE_POP", "only_walk", len(only_walk))
    emit("SURFACE_POP", "only_discover", len(only_disc))
    for r in only_walk:
        emit("SURFACE_POP", "WALK-ONLY", r)
    for r in only_disc:
        emit("SURFACE_POP", "DISCOVER-ONLY", r)
    # Which of the census's per-gate rows are the deeper files? They have no row at all.
    rows_by_file = {}
    for p in entries:
        if p.suffix != ".py":
            continue
        rows_by_file[str(p.relative_to(ROOT))] = None
    emit("SURFACE_POP", "entry_points_with_no_census_row_for_deeper_files",
         [r for r in DEEPER if r not in rows_by_file])


def main():
    emit("PART4", "field", "value")
    referenced_by()
    head_of_deeper()
    entry_vs_lib_split()
    ceiling_visibility()
    gate_surface_control_line()
    denom_of_gate_surface()
    OUT.write_text("\n".join(rows) + "\n")
    print("\n".join(r for r in rows
                    if r.startswith(("CLASS", "VISIBLE", "SURFACE_POP", "HEAD", "SURFACE",
                                    "REFERENCED"))))


if __name__ == "__main__":
    main()