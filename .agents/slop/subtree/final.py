"""THE FINAL, TIMESTAMPED READING. Every number the report quotes comes from here, once.

One run, one stamp, so a number and its time cannot drift apart -- `AGENTS.md` records a unit
losing 425 rows to a status it read without its rule. This prints the whole table the report
cites and writes it to `final.rows`.
"""
import importlib.util
import os
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
rows = []


def emit(*c):
    rows.append("\t".join(str(x) for x in c))


def by_path(p, name):
    spec = importlib.util.spec_from_file_location(name, p)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main():
    stamp = time.strftime("%Y-%m-%dT%H:%M:%S")
    head = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                          capture_output=True, text=True).stdout.strip()
    emit("FINAL", f"HEAD={head}", f"at={stamp}")
    # `sys.executable`/`sys.version` from THIS process, NOT a `python3` subprocess: AGENTS.md
    # records that PATH's `python3` is 3.14 with no `.pth` while `.venv` is the tree's
    # interpreter, so measuring the interpreter by shelling out measures the wrong one.
    import sys
    emit("FINAL", "interpreter", f"{sys.executable} {sys.version.split()[0]}")

    gp = by_path(ROOT / "gates" / "gates-pop.py", "gp_final")
    entries, libs = gp.discover(ROOT)
    disc = {str(p.relative_to(ROOT)) for p in list(entries) + list(libs)}
    walk = set()
    for home in gp.HOMES:
        h = ROOT / home
        for dirpath, dirnames, filenames in os.walk(h):
            dirnames[:] = [d for d in dirnames if d != "__pycache__"]
            for fn in filenames:
                if fn.endswith(gp.SUFFIXES):
                    walk.add(str((Path(dirpath) / fn).relative_to(ROOT)))

    emit("FINAL", "discover_span", "gates/gates-pop.py:324-342")
    emit("FINAL", "walk_line", "gates/gates-pop.py:337  for p in sorted(h.iterdir()):")
    emit("FINAL", "discard_line", "gates/gates-pop.py:338  if p.suffix not in SUFFIXES "
                                  "or not p.is_file(): continue")
    emit("FINAL", "HOMES", "gates/gates-pop.py:102")
    emit("FINAL", "SUFFIXES", "gates/gates-pop.py:140")
    emit("FINAL", "discover_entries", len(entries))
    emit("FINAL", "discover_libs", len(libs))
    emit("FINAL", "discover_total", len(disc))
    emit("FINAL", "recursive_walk_total", len(walk))
    emit("FINAL", "only_discover", len(disc - walk))
    emit("FINAL", "only_walk", len(walk - disc))
    for r in sorted(walk - disc):
        emit("FINAL", "walk_only_name", r)
        emit("FINAL", "walk_only_reason", gp.entry_reason(ROOT / r))

    # the ledger consequence of the fix, MEASURED not predicted
    led = ROOT / "gates" / "gates-pop.ledger.tsv"
    if led.is_file():
        old = {l.split("\t")[0] for l in led.read_text().splitlines()[1:] if l.strip()}
        emit("FINAL", "ledger_rows_now", len(old))
        emit("FINAL", "ledger_rows_if_recursive", len(old) + len(walk - disc))
        emit("FINAL", "ledger_would_go_red",
             f"--ledger check reports {len(walk - disc)} NEW and returns 1")

    # consumers, re-counted
    skip = {".venv", ".git", "__pycache__", "references", "node_modules", "tinybendygrad",
            ".agents/slop/peakrss", ".agents/slop/subtree"}
    callers = set()
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in skip]
        for fn in filenames:
            if fn.endswith(".py"):
                p = Path(dirpath) / fn
                try:
                    t = p.read_text(errors="replace")
                except OSError:
                    continue
                if ".discover(" in t and ("gates_pop" in t or "gpop" in t or "gp." in t):
                    callers.add(str(p.relative_to(ROOT)))
    emit("FINAL", "consumers_excluding_this_unit", len(callers))
    for c in sorted(callers):
        t = (ROOT / c).read_text(errors="replace")
        emit("FINAL", "  consumer", c,
             f"prints_ceiling={'walk_control' in t or 'only_walk' in t}")
    emit("FINAL", "consumers_printing_the_ceiling",
         sorted(c for c in callers
                if "walk_control" in (ROOT / c).read_text(errors="replace")
                or "only_walk" in (ROOT / c).read_text(errors="replace")))

    (HERE / "final.rows").write_text("\n".join(rows) + "\n")
    print("\n".join(rows))


if __name__ == "__main__":
    main()