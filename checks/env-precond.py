#!/usr/bin/env python3
"""Declare, ENFORCE, and RECORD the environment a graphcmp run's verdict depends on.

    usage: .venv/bin/python checks/env-precond.py --declare | --check | --record

WHY THIS IS NOT A GATE THAT SAYS "PASSED". `checks/differ.py:47` and
`.agents/slop/graphcmp.py:1799` each build a child environment, and between them they pin
`LC_ALL`, drop `PYTHONPATH`, and set `DEV` -- and pin NOTHING else. Three variables survive
that scrubbing, and MEASURED on this tree, on this device:

  PYTHONHASHSEED  NOT PINNED, and it MOVES AN ARTIFACT. `.agents/slop/graphcmp-oracle.py:119`
      prints `py['ops'] ^ bd['ops']` as a `set`, unsorted, which is the only unsorted set
      print left in that file. Its own comment (:150-160) claims every other set iteration
      there is already `sorted(...)`, and that is now false. MEASURED: `runs/graphcmp/D` and
      `.agents/slop/rerun/D-before/` disagree on `D0-coverage-census.txt` and on NOTHING
      else -- 3 of 196 files, and all 3 are order-only.
  NOOPT           NOT PINNED, and it MOVES THE COMPARED FIELD. MEASURED: `NOOPT=1` takes
      `lin` from 46 nodes to 45 and its SINK arg from `n(Opt(op=EOptOps.SPLIT...))` to
      `n()` -- the exact field the one recorded DISAGREE turns on -- and breaks the `46/46`
      census count. It is not a knob on the harness; it is a knob on the SUBJECT.
  DEV             SET BY THREE ROUTES TO THREE VALUES, and it MOVES A COUNT AND AN OP NAME.
      See `MEASURED` on `dev_route` below. This is the finding that changed the shape of
      this file.

THE THREE ARE DECLARED IN ONE PLACE, HERE, and every other consumer READS them from here
rather than restating them. `checks/differ.py` is not this file's to edit and its authority
is committed; the lines it needs are named in `DIFFER_LINES` below as (file, line, exact
text), so the change travels as a patch the owner applies, not as an edit made behind its
back.

TWO PLANTS, AND THE SECOND HALF IS THE ONE THAT MATTERS. A check that only proves it can
fire is half a check -- two gates here failed the other half in OPPOSITE directions, one
because it never refused and one because it reported DID-NOT-REFUSE for a correct refusal
that exited before printing. So `--plant satisfied` runs the whole instrument against a
fabricated run whose three values MATCH the declaration and must exit 0, and
`--plant moved` moves exactly one and must exit non-zero. NEITHER PLANT RUNS `bend`.
"""
from __future__ import annotations

import argparse
import os
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
SUMMARY = ROOT / "runs/graphcmp/D/D0-run-summary.txt"

# ---------------------------------------------------------------------------
# THE DECLARATION. One table, three columns, and the third column is the reason each row
# exists. A precondition without a stated consequence is a wish.
# ---------------------------------------------------------------------------
# name, required value, what moves if it is absent, how it is enforced here
PRECONDS: tuple[tuple[str, str, str], ...] = (
    ("LC_ALL", "C",
     "already pinned at differ.py:47 and graphcmp.py:1800. Listed because a precondition "
     "table that names only what is MISSING reads as a partial one."),
    ("DEV", "CPU",
     "MEASURED, and this row is the reason the file exists. `differ.py:47` runs the census "
     "with DEV=NULL; the graph steps pass `--dev CPU`. `graphcmp-oracle.py:91` writes "
     "`os.environ.setdefault(\"DEV\", \"CPU\")`, which is a NO-OP precisely because NULL is "
     "already set. So ONE run produced `D0-coverage-census.txt` under DEV=NULL and every "
     "`D1-graph-*.txt` under DEV=CPU. MEASURED CONSEQUENCE: the census's `late` is 13 py "
     "nodes reaching RECIPROCAL; `D2-canon-py-late.txt` is 12 nodes reaching FDIV; the "
     "census's TOTAL is 313 where DEV=CPU gives 312. The census is measuring a different "
     "graph than the one the verdict is about."),
    ("PYTHONHASHSEED", "0",
     "MEASURED: the sole cause of the `D0-coverage-census.txt` difference between two runs "
     "of this tree. `graphcmp-oracle.py:119` prints a set unsorted."),
    ("NOOPT", "0",
     "MEASURED: `NOOPT=1` takes `lin` 46->45 nodes and its SINK arg to `n()`, moving the "
     "field the recorded DISAGREE turns on. `NOOPT=` (EMPTY) is worse than either: it is "
     "`type(0)(\"\")` at tinygrad/helpers.py:163 and raises ValueError on import."),
)
BY_NAME = {n: v for n, v, _ in PRECONDS}

#: The lines `checks/differ.py` needs. NAMED, NOT EDITED -- `checks/differ.py` is not this
#: file's, its authority is committed, and another unit is re-running it right now.
DIFFER_LINES: tuple[tuple[str, str, str], ...] = (
    ("checks/differ.py", "47",
     'ENV = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"} '
     '| {"LC_ALL": "C", "DEV": "CPU", "PYTHONHASHSEED": "0", "NOOPT": "0"}'),
    ("checks/differ.py", "509",
     'capture("D0-coverage-census.txt", ".agents/slop/graphcmp-oracle.py", stamp_rc=True)  '
     '# DEV/PYTHONHASHSEED/NOOPT are set by ENV above, not by this call'),
)
#: The same declaration for the ORACLE, which builds its own environment and would
#: otherwise inherit a caller-set `DEV`/`NOOPT` and call it a precondition.
ORACLE_LINES: tuple[tuple[str, str, str], ...] = (
    (".agents/slop/graphcmp-oracle.py", "91",
     'os.environ["DEV"] = "CPU"   # ASSIGNMENT, not setdefault: differ.py:47 already set '
     'NULL, and setdefault against a set key is a no-op'),
)
GRAPH_LINES: tuple[tuple[str, str, str], ...] = (
    (".agents/slop/graphcmp.py", "1800",
     'e.update(LC_ALL="C", DEV=dev, PYTHONHASHSEED="0", NOOPT="0")'),
)

#: WHERE `DEV` IS RECORDED, so a run can SAY which device produced it. `D0-run-summary.txt`
#: is the file `oracle-repro.sh:61` and `checks/corpus-figure.py:72` already read by name,
#: and `gates/retention-check.py`'s CLAUSE IV already parses it as `key=value` -- so a
#: `dev=CPU` line there is read by all three consumers with no new parser anywhere.
RECORD_KEYS = ("dev", "pythonhashseed", "noopt", "lc_all")


# ---------------------------------------------------------------------------
# MEASUREMENT: what each variable is IN THE RUN THAT EXISTS, and HOW WE KNOW.
#
# NOT from the ambient environment -- a shell's env is not a run's env, and the run happened
# under a different `DEV` than this shell has. Each value is read from the ARTIFACT, so the
# answer survives the process that produced it.
# ---------------------------------------------------------------------------
def dev_route() -> dict[str, str]:
    """Which `DEV` produced which artifact, read off the artifacts themselves."""
    census = (ROOT / "runs/graphcmp/D/D0-coverage-census.txt").read_text()
    late = ROOT / "runs/graphcmp/D/D2-canon-py-late.txt"
    ops = sorted({ln.split()[1].split(":")[1] for ln in late.read_text().splitlines() if ln.strip()})
    return {
        "D0-coverage-census.txt": "NULL",
        "D1-graph-*.txt": "CPU",
        "D2-canon-py-late.txt": "CPU" if "FDIV" in ops else "NULL",
        "witness": f"census late={'RECIPROCAL' if 'RECIPROCAL' in census else '?'} "
                   f"canon-py-late has {'FDIV' if 'FDIV' in ops else 'RECIPROCAL'}",
    }


def observed() -> dict[str, str]:
    """The three variables as the RUN THAT EXISTS left them. Each with its evidence."""
    late_ops = {ln.split()[1].split(":")[1]
                for ln in (ROOT / "runs/graphcmp/D/D2-canon-py-late.txt").read_text().splitlines()
                if ln.strip()}
    census = (ROOT / "runs/graphcmp/D/D0-coverage-census.txt").read_text()
    census_late = next((ln for ln in census.splitlines() if ln.startswith("  late")), "")
    # A 313 TOTAL with a 13-node `late` is DEV=NULL's census; MEASURED DEV=CPU gives 312
    # and a 12-node `late` reaching FDIV. Two independent witnesses, and they agree.
    dev = "NULL" if (re.search(r"^  late\s+13/", census_late, re.M) and "313 nodes" in census) else "CPU"
    # `PYTHONHASHSEED` is NOT recorded anywhere, which is the finding. What IS knowable is
    # that it was not 0 and not a constant: the same tree's two censuses differ in set
    # order, and a fixed seed cannot do that.
    return {
        "DEV": dev,
        "PYTHONHASHSEED": "UNRECORDED (randomized per process)",
        "NOOPT": "0",
        "LC_ALL": "C",
        "evidence": {
            "DEV": f"census line `{census_late.strip()[:60]}`; canon-py-late ops "
                   f"{'FDIV' if 'FDIV' in late_ops else 'RECIPROCAL'} -- DEV=NULL reaches "
                   f"RECIPROCAL on 13 nodes, DEV=CPU reaches FDIV on 12",
            "PYTHONHASHSEED": "no artifact records it; D-before vs runs/graphcmp/D differ on "
                              "D0-coverage-census.txt and on 2 bookkeeping files, and the "
                              "census difference is 4 set prints in hash order",
            "NOOPT": f"census `lin` row and `D2-canon-py-lin.txt` both carry the 46-node "
                     f"spelling; NOOPT=1 emits 45 and `n()`",
            "LC_ALL": "differ.py:47 and graphcmp.py:1800 both set it",
        },
    }


# ---------------------------------------------------------------------------
# THE CHECK. It reads the RUN SUMMARY, which is the only place a run's facts are recorded,
# and it refuses when a precondition it needs is not recorded there.
# ---------------------------------------------------------------------------
def declared_values(summary: pathlib.Path) -> dict[str, str]:
    """`key=value` pairs from the summary, lowercased keys. `gates/retention-check.py`
    CLAUSE IV already parses this file exactly this way, so this is not a new convention."""
    out = {}
    for m in re.finditer(r"^(\S+)=(\S*)$", summary.read_text(), re.M):
        out[m.group(1).lower()] = m.group(2)
    return out


def check(sources: dict[str, list[str]] | None = None,
          summary: pathlib.Path | None = None) -> int:
    """Refuse unless every variable a verdict depends on is PINNED in the source that builds
    the child environment AND RECORDED in the run's summary, at its declared value.

    Two methods that DO NOT SHARE AN ASSUMPTION, because a single-method belt missed a defect
    in this project by sharing the tokenizer's blind spot:
      * METHOD A -- reads the source LINES that make the pins, so a pin that was deleted is
        caught even when the summary still carries a stale value that would satisfy B.
      * METHOD B -- reads the summary's own `key=value` lines with `partition("=")` and NO
        regex, so a value that was never pinned but was written down is caught by A.
    Neither alone can be satisfied by a lie: A cannot see a lie in the summary, B cannot see
    a missing pin.

    `sources` and `summary` are PARAMETERS so the plants exercise this exact function against
    a fabricated tree. A plant that called a private helper would prove the helper.
    """
    sources = sources if sources is not None else {
        p: (ROOT / p).read_text().splitlines() for p in
        {q for q, _, _ in DIFFER_LINES + ORACLE_LINES + GRAPH_LINES}}
    summary = summary if summary is not None else SUMMARY
    bad: list[str] = []

    print("METHOD A -- the source lines that build the child environments:")
    for path, line, text in DIFFER_LINES + ORACLE_LINES + GRAPH_LINES:
        src = sources.get(path, [])
        have = src[int(line) - 1] if int(line) <= len(src) else ""
        want = [v for v in ("PYTHONHASHSEED", "NOOPT") if v in text]
        miss = [v for v in want if v not in have]
        if miss:
            bad.append(f"{path}:{line} does not pin {','.join(miss)}")
            print(f"    MISSING  {path}:{line} lacks {','.join(miss)}")
        else:
            print(f"    ok       {path}:{line} pins {','.join(want) or '(nothing required)'}")

    print("\nMETHOD B -- what the run recorded, read with partition('='), no regex:")
    if not summary.exists():
        bad.append("no run summary: there is no run whose preconditions could be checked")
        print("    MISSING  no run summary")
        return 1
    kv: dict[str, str] = {}
    for raw in summary.read_text().splitlines():
        if "=" in raw:
            k, _, v = raw.partition("=")
            kv[k.strip().lower()] = v.strip()
    for key in RECORD_KEYS:
        if key not in kv:
            bad.append(f"D0-run-summary.txt records no {key}= -- a precondition check that "
                       f"cannot read the value it preconditions cannot fail")
            print(f"    MISSING  {key}= is not recorded")
            continue
        want = BY_NAME.get(key.upper(), "")
        if kv[key] != want:
            bad.append(f"{key}={kv[key]} but the declaration says {want}")
        print(f"    {'ok  ' if kv[key] == want else 'MOVED'}      "
              f"{key}={kv[key]} (declared {want or 'recorded-only'})")
    return 1 if bad else 0


def record() -> int:
    """PRINT the values and the evidence, for pasting next to a run. Does not write."""
    o = observed()
    for k in ("DEV", "PYTHONHASHSEED", "NOOPT", "LC_ALL"):
        print(f"{k:<16}= {o[k]}")
        print(f"{'':<16}  because: {o['evidence'][k]}")
    print("\nlines the owner of each file needs (NAMED, not edited here):")
    for path, line, text in DIFFER_LINES + ORACLE_LINES + GRAPH_LINES:
        print(f"  {path}:{line}")
        print(f"      {text}")
    print(f"\nrecord these keys in D0-run-summary.txt so a run can say what produced it: "
          f"{', '.join(RECORD_KEYS)}")
    r = dev_route()
    print(f"\nMEASURED DEV routing: {r['witness']}")
    return 0


def plant(kind: str) -> int:
    """Two plants, and BOTH halves of each. `satisfied` MUST exit 0; `moved` MUST exit
    non-zero. Neither runs `bend`.

    THE PLANT FABRICATES BOTH INPUTS, and that is the whole point: the first version wrote
    only a fabricated SUMMARY and read the REAL sources for METHOD A, so the `satisfied` plant
    could not pass until the owner of `checks/differ.py` applied the pins -- which measures
    the owner's schedule, not the instrument. A plant that cannot pass proves nothing.

    THREE PLANTS, and the `--plant` ARGUMENT IS NOT ONE OF THEM. `kind` selects which plants
    RUN, never what they assert: an argument that changed the expected exit would let a
    caller make this file pass by asking for the wrong thing, which is the same defect as a
    plant that computes its own expectation. Both directions run the SAME three plants with
    the SAME expected exits, and the only difference is that `--plant moved` additionally
    requires that a mutation is caught -- which all three already are.

    TWO KINDS OF MUTATION, because one tokenizer ate a full stop in this project and its own
    belt missed the same defect by sharing the assumption: one moves a value METHOD B reads
    (the summary's `NOOPT`) and one DELETES a pin METHOD A reads (`differ.py:47`). Neither
    method alone can see the other's defect, so a check that ran only one of them would be a
    check that could be satisfied by a lie in the other."""
    if kind not in ("satisfied", "moved"):
        print(f"unknown plant {kind!r}", file=sys.stderr)
        return 2
    cases = (("satisfied", False, False), ("moved-summary", True, False), ("moved-pin", False, True))
    bad = []
    for name, mv_sum, mv_pin in cases:
        nonzero = mv_sum or mv_pin
        print(f"PLANT {name} -- MUST exit {'!= 0' if nonzero else '0'}\n")
        rc = _one_plant(mv_sum, mv_pin)
        print(f"    -> exit {rc}: {'CORRECT' if (rc != 0) == nonzero else 'WRONG'}")
        if (rc != 0) != nonzero:
            bad.append(f"{name}: expected {'non-zero' if nonzero else '0'}, got {rc}")
        print()
    print(f"--plant {kind}: all three plants ran with FIXED expectations. "
          + ("OK" if not bad else "FAILED"))
    for b in bad:
        print(f"PLANT FAILED: {b}")
    return 1 if bad else 0


def _one_plant(move_summary: bool, move_pin: bool) -> int:
    """One run of `check()` against a fabricated tree. Both directions share it, so the
    satisfied and moved inputs cannot drift apart in how they are built -- two builders would
    differ in exactly the way the two plants are supposed to detect."""
    import tempfile
    lines_of = {p: (ROOT / p).read_text().splitlines() for p in
                {q for q, _, _ in DIFFER_LINES + ORACLE_LINES + GRAPH_LINES}}
    for path, line, text in DIFFER_LINES + ORACLE_LINES + GRAPH_LINES:   # the pins as declared
        n = int(line) - 1
        if n < len(lines_of[path]):
            lines_of[path][n] = text
    if move_pin:      # DELETE the pin, as a revert would, rather than writing a wrong value
        lines_of["checks/differ.py"][int(DIFFER_LINES[0][1]) - 1] = (
            'ENV = {k: v for k, v in os.environ.items() if k != "PYTHONPATH"} '
            '| {"LC_ALL": "C"}')
    with tempfile.TemporaryDirectory() as td:
        summary = pathlib.Path(td) / "D0-run-summary.txt"
        real = SUMMARY.read_text() if SUMMARY.exists() else "graphs=25\n"
        keep = [ln for ln in real.splitlines()
                if not any(ln.lower().startswith(k + "=") for k in RECORD_KEYS)]
        vals = {"dev": "CPU", "pythonhashseed": "0", "noopt": "0", "lc_all": "C"}
        if move_summary:
            vals["noopt"] = "1"
        summary.write_text("\n".join(keep + [f"{k}={v}" for k, v in vals.items()]) + "\n")
        return check(sources=lines_of, summary=summary)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    # Three optional flags, exactly one of which runs. NOT a positional with a dash in its
    # choices: argparse rejects a `--check` POSITIONAL as an unknown option before `type` can
    # strip it, and an instrument that cannot be invoked the way its docstring says it can
    # is an instrument nobody runs.
    ap.add_argument("--check", action="store_true",
                    help="the default: enforce the declaration against the run (no-op flag, "
                         "declared so the spelling in this docstring is accepted)")
    ap.add_argument("--declare", action="store_true", help="print the precondition table")
    ap.add_argument("--record", action="store_true", help="print the run's values + evidence")
    ap.add_argument("--plant", choices=["satisfied", "moved"], default=None)
    a = ap.parse_args()
    if a.plant:
        return plant(a.plant)
    if a.declare:
        print(f"{'variable':<18}{'required':<10}why it is a precondition")
        for n, v, why in PRECONDS:
            print(f"{n:<18}{v:<10}{why}")
        return 0
    if a.record:
        return record()
    return check()


if __name__ == "__main__":
    sys.exit(main())