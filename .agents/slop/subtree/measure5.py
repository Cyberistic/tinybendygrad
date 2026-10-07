"""PART 5 -- RE-VERIFY the line numbers (the tree is being written live) and test the deeper
files' OWN inputs.

Two things this measures:
  1. `gates/gate-surface.py`'s POPULATION CONTROL print, at the line it is at NOW, with the
     function span of `walk_control` and of the print itself. `AGENTS.md` warns other units are
     editing this tree live, so a line number is a READING WITH A TIMESTAMP, not a fact.
  2. The two deeper files are gates by `entry_reason()`, and each one's lanes name an input.
     `AGENTS.md` records that inputs under `.agents/slop/` were deleted. So: does each deeper
     gate still HAVE the file its own header says it runs?
"""
import importlib.util
import os
import re
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent / "census5.rows"
rows = []
DEEPER = ["gates/oracles/beautiful-mnist-oracle.sh", "gates/oracles/mixin-op-oracle.sh"]


def emit(*c):
    rows.append("\t".join(str(x) for x in c))


def span(path, name):
    import ast
    tree = ast.parse(path.read_text())
    for n in ast.walk(tree):
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == name:
            return n.lineno, n.end_lineno
    return None


def locate(path, pattern):
    """`(lineno, text)` for every line matching `pattern`. Printed so the regex can be checked."""
    return [(i, l.rstrip()) for i, l in enumerate(path.read_text().splitlines(), 1)
            if re.search(pattern, l)]


def git_stamp():
    r = subprocess.run(["git", "rev-parse", "--short", "HEAD"], cwd=ROOT,
                       capture_output=True, text=True)
    return r.stdout.strip() or "(no HEAD)"


def main():
    stamp = f"HEAD={git_stamp()} at {time.strftime('%Y-%m-%dT%H:%M:%S')}"
    emit("PART5", "field", "value")
    emit("STAMP", "reading", stamp)

    gs = ROOT / "gates" / "gate-surface.py"
    gp = ROOT / "gates" / "gates-pop.py"
    emit("SPAN", "gate-surface.py:population", span(gs, "population"))
    emit("SPAN", "gate-surface.py:walk_control", span(gs, "walk_control"))
    emit("SPAN", "gate-surface.py:report", span(gs, "report"))
    emit("SPAN", "gates-pop.py:discover", span(gp, "discover"))
    for i, t in locate(gs, r"POPULATION CONTROL|WALK-ONLY|only_walk = |recursive `os\.walk`"):
        emit("LOCATE", f"gate-surface.py:{i}", t.strip()[:120])
    for i, t in locate(gp, r"h\.iterdir|HOMES\b"):
        emit("LOCATE", f"gates-pop.py:{i}", t.strip()[:120])

    # ---- the deeper gates' own inputs ----
    for rel in DEEPER:
        p = ROOT / rel
        emit("INPUTS", rel, f"exists={p.is_file()} bytes={p.stat().st_size}")
        text = p.read_text(errors="replace")
        # every path-looking token the file mentions, resolved
        toks = set(re.findall(r"[./A-Za-z0-9_-]+\.(?:sh|py|bend|rows)", text))
        for tok in sorted(toks):
            cand = ROOT / tok.lstrip("./")
            alt = ROOT / "oracles" / Path(tok).name
            emit("INPUTS", f"{rel} -> {tok}",
                 f"at_root={cand.is_file()} under_oracles={alt.is_file()} "
                 f"under_slop={(ROOT / '.agents' / 'slop' / Path(tok).name).is_file()}")

    # ---- does the ledger know them? `gates/gates-pop.ledger.tsv` is the DIFF witness ----
    led = gp.parent / "gates-pop.ledger.tsv"
    if led.is_file():
        lines = led.read_text(errors="replace").splitlines()
        emit("LEDGER", "path", str(led.relative_to(ROOT)))
        emit("LEDGER", "rows", len(lines) - 1)
        emit("LEDGER", "header", lines[0])
        for rel in DEEPER:
            emit("LEDGER", f"{rel}_in_ledger", any(rel in l for l in lines))
        # which of the deeper dir's siblings appear?
        emit("LEDGER", "gates_oracles_rows",
             [l.split("\t")[0] for l in lines if "gates/oracles" in l] or "(none)")

    # ---- the census gate's OWN denominator statement ----
    for i, t in locate(gs, r"DENOMINATOR"):
        emit("DENOM", f"gate-surface.py:{i}", t.strip()[:160])

    OUT.write_text("\n".join(rows) + "\n")
    print("\n".join(rows))


if __name__ == "__main__":
    main()