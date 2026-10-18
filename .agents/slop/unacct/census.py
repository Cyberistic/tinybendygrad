#!/usr/bin/env python3
"""THE STATE CENSUS OF ONE RUN OF `runs/graphcmp/D`, AND THE CONTROL THAT MAKES IT TRUSTWORTHY.

READ-ONLY AND MECHANICS-FREE: nothing here compiles, imports the port, spawns a subprocess or
runs `differ.py`. It reads artifacts that already exist and asks each one which of five states it
is in -- the five `gatekit.py:60` names, applied to a corpus of graphs:

  AGREE / DISAGREE  the artifact carries a `VERDICT:` line and it says so
  REFUSED           the artifact ran and emitted NO `VERDICT:` line (a refusal, not a verdict)
  UNSET             the graph has no row in `differ.WANT`, so nobody said what it should be
  MISSING           no artifact at all
  DEAD              -- reserved; see the report. Nothing in this run reaches it.

THE POPULATIONS ARE DISCOVERED, NOT NAMED. `graphcmp.GRAPHS` and `differ.WANT`/`CONTROLS`/`STAB`
are read out of their own sources with `ast.parse` (no import: importing `graphcmp.py` resolves a
Device). A hand list would be the seventh member of the class this census measures -- a population
declared by a shape rather than by the generator that owns it.

THE CONTROL IS NOT OPTIONAL AND ITS SCOPE IS WRITTEN DOWN HERE, NOT IN A PROSE CLAIM:
this census must reproduce `graphs-agree=31` and `graphs-disagree=2` from the artifacts alone, and
must classify `loop` as REFUSED. If it does not, it prints CONTROL=FAIL and writes no rows.

Usage: .venv/bin/python .agents/slop/unacct/census.py [--root REPO]
"""
from __future__ import annotations

import argparse
import ast
import re
import sys
from pathlib import Path

# differ.py's own primitives, re-implemented from its source so the census and the run agree by
# construction rather than by coincidence. Each is a one-liner there; each is quoted here because a
# re-typed regex that drifts from the one in the gate is a second opinion with no generator.
def verdict(text: str) -> str:
    """differ.py:999 -- `re.findall(r"VERDICT: [A-Z]*", ...)[-1].split()[1]`, else "".

    THE LAST match, because a report carries the verdict twice and the operative line is the
    bottom one. A file with NO `VERDICT:` at all yields "", which is the refusal signal.
    """
    found = re.findall(r"VERDICT: [A-Z]*", text)
    return found[-1].split()[1] if found else ""


def files_with(paths: list[Path], needle: str) -> int:
    """differ.py:496 -- `sum(needle in f.read_text(errors="replace") for f in D.glob(pattern))`.

    A FILE count, not a line count, and not a last-verdict count: a file carrying both AGREE and
    DISAGREE counts in BOTH columns. That is the arithmetic the summary reports and this census
    must reproduce, so the same predicate is used here.
    """
    return sum(needle in p.read_text(errors="replace") for p in paths)


def lines_with(path: Path, needle: str) -> int:
    """differ.py:473 -- `grep -c`: LINES containing the needle."""
    return sum(needle in ln for ln in path.read_text(errors="replace").splitlines())


def anchored(path: Path, regex: str) -> int:
    """differ.py:478 -- the regex twin of `lines_with`; a LINE count, bool-wrapped."""
    return sum(bool(re.search(regex, ln)) for ln in path.read_text(errors="replace").splitlines())


# ---- the populations, declared by their own generators and read WITHOUT importing them --------

def literal_assignment(src: str, name: str, root: Path):
    """The value assigned to `name` at module scope, as a literal, via `ast.parse`.

    NO IMPORT: `graphcmp.py` binds a Device at import time and `differ.py` reads the substrate
    digest. A census of a completed run must not move the machine it is measuring.
    """
    tree = ast.parse(src, filename=str(root))
    for node in tree.body:
        if isinstance(node, ast.Assign) and any(
            isinstance(t, ast.Name) and t.id == name for t in node.targets
        ):
            return node.value
    raise SystemExit(f"REFUSED: no module-scope `{name} =` in {root}")


def keys_of(node: ast.Dict) -> list[str]:
    if not isinstance(node, ast.Dict):
        raise SystemExit(f"REFUSED: expected a dict literal, got {type(node).__name__}")
    return [k.value for k in node.keys if isinstance(k, ast.Constant)]


def keyset(node) -> set[str]:
    return set(keys_of(node))


def constants(node) -> list[str]:
    """Every string Constant under a literal expression. `CONTROLS` is a tuple and `STAB` a tuple
    of 2-tuples, so a `.values` accessor would only work for the dict case."""
    return [n.value for n in ast.walk(node) if isinstance(n, ast.Constant)
            and isinstance(n.value, str)]


def summary(D: Path) -> dict[str, str]:
    """`D0-run-summary.txt` as a dict. A summary row is `key=value`, per four consumers."""
    out = {}
    for ln in (D / "D0-run-summary.txt").read_text(errors="replace").splitlines():
        if "=" in ln:
            k, v = ln.split("=", 1)
            out[k] = v
    return out


# ---- lane 1: THE GRAPH CORPUS ----------------------------------------------------------------

def graph_census(D: Path, graphs: list[str], want: set[str]) -> list[list[str]]:
    """One row per graph: name, artifact, state, and WHICH summary column counts it.

    STATE is decided from the ARTIFACT alone; `WANT` is consulted only for the UNSET question,
    because "nobody said what this should be" is a fact about the TABLE, not about the port.
    """
    rows = []
    for g in graphs:
        art = D / f"D1-graph-{g}.txt"
        if not art.is_file():
            state, column = "MISSING", "NEITHER"
        else:
            body = art.read_text(errors="replace")
            v = verdict(body)
            if v == "AGREE":
                state, column = "AGREE", "graphs-agree"
            elif v == "DISAGREE":
                state, column = "DISAGREE", "graphs-disagree"
            elif not re.search(r"VERDICT: [A-Z]*", body):
                state, column = "REFUSED", "NEITHER"
            elif v:
                state, column = f"VERDICT-OTHER({v})", "NEITHER"
            else:
                state, column = "VERDICT-EMPTY", "NEITHER"
            if g not in want:
                state, column = "UNSET", column
        rows.append([g, f"runs/graphcmp/D/D1-graph-{g}.txt", state, column])
    return rows


# ---- the other lanes, each against the summary row that is supposed to cover it ---------------

def control_lane(D: Path, controls: list[str]) -> list[list[str]]:
    """`controls=<count of CONTROL VERDICT: OK> of 5` is the ONLY control row.

    So a control that refused (no line) and a control that genuinely failed (a different verdict)
    are the SAME number. Counted here so the report can say whether any such member exists today.
    """
    rows = []
    for g in controls:
        p = D / f"D3-control-{g}.txt"
        if not p.is_file():
            state = "MISSING"
        else:
            body = p.read_text(errors="replace")
            state = "OK" if "CONTROL VERDICT: OK" in body else "NOT-OK"
        rows.append([f"D3-control-{g}", f"runs/graphcmp/D/D3-control-{g}.txt", state,
                     "controls" if state == "OK" else "NEITHER"])
    return rows


def stability_lane(D: Path, stab: list[tuple[str, str]]) -> list[list[str]]:
    """Three summary rows: stable-pairs, stable-failed, stable-differ. Each says `of 5`.

    The fourth state -- BOTH sides 0-row -- is reported by differ.py:649 with the sentence
    "ONE SIDE IS A 0-ROW FAILURE", because the guard is `one_line(a) or one_line(b)`. So the
    artifact names a side the measurement never identified. MEASURED on loop: BOTH sides are
    1 line of `rc=2`, so the sentence is false there, and the refusal is a deterministic
    non-answer rather than the non-reproducibility it claims to be.
    """
    rows = []
    for g, _extra in stab:
        a, b = D / f"D9-stability-{g}-a.txt", D / f"D9-stability-{g}-b.txt"
        if not (a.is_file() and b.is_file()):
            state, col = "MISSING", "NEITHER"
        else:
            na, nb = len(a.read_bytes().splitlines()), len(b.read_bytes().splitlines())
            if na <= 1 and nb <= 1:
                state, col = "REFUSED-BOTH-SIDES", "stable-failed"
            elif na <= 1 or nb <= 1:
                side = "a" if na <= 1 else "b"
                state, col = f"REFUSED-ONE-SIDE({side})", "stable-failed"
            elif a.read_bytes() == b.read_bytes():
                state, col = "BYTE-IDENTICAL", "stable-pairs"
            else:
                state, col = "DIFFER", "stable-differ"
        rows.append([f"D9-stability-{g}", f"runs/graphcmp/D/D9-stability-{g}-{{a,b}}.txt",
                     state, col])
    return rows


def bytediff_lane(D: Path, graphs: list[str]) -> list[list[str]]:
    """Two summary rows: `byte-identical` and `not-comparable`. Both are LINE counts over
    `D2-bytediff.txt`. A graph whose canonical bytes DIFFER is in NEITHER."""
    rows = []
    for g in graphs:
        p = D / f"D2-cmp-{g}.txt"
        if not p.is_file():
            state, col = "MISSING", "NEITHER"
        else:
            first = p.read_text(errors="replace").split("\n", 1)[0]
            if " BYTE-IDENTICAL" in first:
                state, col = "BYTE-IDENTICAL", "byte-identical"
            elif " NOT COMPARED" in first:
                state, col = "NOT-COMPARED", "not-comparable"
            elif " DIFFERS" in first:
                state, col = "DIFFERS", "NEITHER"
            else:
                state, col = "UNRECOGNISED", "NEITHER"
        rows.append([f"D2-cmp-{g}", f"runs/graphcmp/D/D2-cmp-{g}.txt", state, col])
    return rows


def tally(rows: list[list[str]]) -> dict[str, int]:
    out: dict[str, int] = {}
    for r in rows:
        out[r[3]] = out.get(r[3], 0) + 1
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[3])
    a = ap.parse_args()
    root, D = a.root, a.root / "runs/graphcmp/D"

    gc_src = (root / ".agents/slop/graphcmp.py").read_text(errors="replace")
    df_src = (root / "checks/differ.py").read_text(errors="replace")
    graphs = sorted(keys_of(literal_assignment(gc_src, "GRAPHS", root / ".agents/slop/graphcmp.py")))
    want = keyset(literal_assignment(df_src, "WANT", root / "checks/differ.py"))
    controls = sorted(constants(literal_assignment(df_src, "CONTROLS", root / "checks/differ.py")))
    stab = [(g, "") for g in constants(literal_assignment(df_src, "STAB", root / "checks/differ.py"))
            if g != "--plant" and g != "srcswap"]
    summ = summary(D)

    # ---- THE CONTROL. It gates everything below. --------------------------------------------
    d1 = sorted(D.glob("D1-graph-*.txt"))
    agree = files_with(d1, "VERDICT: AGREE")
    disagree = files_with(d1, "VERDICT: DISAGREE")
    rows = graph_census(D, graphs, want)
    state_of = {r[0]: r[2] for r in rows}
    my_agree = sum(1 for r in rows if r[2] == "AGREE")
    my_disagree = sum(1 for r in rows if r[2] == "DISAGREE")
    claims = [
        ("corpus() size == graphs=", len(graphs), int(summ["graphs"])),
        ("files_with(D1, AGREE) == graphs-agree", agree, int(summ["graphs-agree"])),
        ("files_with(D1, DISAGREE) == graphs-disagree", disagree, int(summ["graphs-disagree"])),
        ("census AGREE == summary graphs-agree", my_agree, int(summ["graphs-agree"])),
        ("census DISAGREE == summary graphs-disagree", my_disagree, int(summ["graphs-disagree"])),
        ("loop is REFUSED", state_of.get("loop"), "REFUSED"),
    ]
    ok = all(g == w for _, g, w in claims)
    print(f"CONTROL={'PASS' if ok else 'FAIL'}")
    for name, got, want_v in claims:
        print(f"  {'ok ' if got == want_v else 'BAD'} {name}: got {got!r} want {want_v!r}")
    if not ok:
        print("REFUSING TO REPORT: the census does not reproduce the summary it audits.")
        return 3

    # ---- the lanes ---------------------------------------------------------------------------
    lanes = {
        "D1-graph (verdict)": rows,
        "D2-cmp (byte diff)": bytediff_lane(D, graphs),
        "D3-control": control_lane(D, controls),
        "D9-stability": stability_lane(D, stab),
    }
    out = Path(__file__).resolve().parent / "graphs.rows"
    with out.open("w") as f:
        f.write("graph\tartifact\tstate\tcounted_in_summary_column\n")
        for r in rows:
            f.write("\t".join(r) + "\n")
    print(f"\nwrote {out} ({len(rows)} graphs, denominator = {len(graphs)})")
    lanes_path = Path(__file__).resolve().parent / "lanes.rows"
    with lanes_path.open("w") as f:
        f.write("lane_member\tartifact\tstate\tcounted_in_summary_column\n")
        for name, rws in lanes.items():
            for r in rws:
                f.write(f"{name}\t{r[1]}\t{r[2]}\t{r[3]}\n")
    print(f"wrote {lanes_path}")
    for name, rws in lanes.items():
        print(f"\n{name}: denominator={len(rws)} {tally(rws)}")
        by_state: dict[str, list[str]] = {}
        for r in rws:
            by_state.setdefault(r[2], []).append(r[0])
        for st, names in sorted(by_state.items()):
            mark = "  " if all(r[3] != "NEITHER" for r in rws if r[2] == st) else "!!"
            print(f" {mark} {st}: {len(names)} {names if len(names) <= 12 else names[:12] + ['...']}")

    # The three summary rows the lanes are supposed to partition, re-derived independently.
    print("\nSUMMARY ROWS, RE-DERIVED FROM THE ARTIFACTS:")
    print(f"  byte-identical={lines_with(D / 'D2-bytediff.txt', 'BYTE-IDENTICAL')} "
          f"summary={summ['byte-identical']}")
    print(f"  not-comparable={lines_with(D / 'D2-bytediff.txt', 'NOT COMPARED')} "
          f"summary={summ['not-comparable']}")
    print(f"  differs(no row)={lines_with(D / 'D2-bytediff.txt', ' DIFFERS')} "
          f"corpus={len(graphs)}")
    print(f"  stable-pairs={anchored(D / 'D9-stability.txt', r': 2 runs BYTE-IDENTICAL$')} "
          f"summary={summ['stable-pairs']}")
    print(f"  stable-failed={lines_with(D / 'D9-stability.txt', 'ONE SIDE IS A 0-ROW FAILURE')} "
          f"summary={summ['stable-failed']}")
    print(f"  stable-differ={anchored(D / 'D9-stability.txt', r': 2 runs DIFFER$')} "
          f"summary={summ['stable-differ']}")
    print(f"  controls={files_with(sorted(D.glob('D3-control-*.txt')), 'CONTROL VERDICT: OK')} "
          f"summary={summ['controls']}")
    return 0


if __name__ == "__main__":
    sys.exit(main())