#!/usr/bin/env python3
"""Declare, ENFORCE, and RECORD the environment a graphcmp run's verdict depends on.

    usage: .venv/bin/python checks/env-precond.py --declare | --check | --record

WHY THIS IS NOT A GATE THAT SAYS "PASSED". `checks/differ.py`'s `ENV` (which feeds the
CPython oracle and every `capture`) and `.agents/slop/graphcmp.py`'s `clean_env` (which
feeds `bin/bend`) each build a child environment, and between them they pin `LC_ALL`, drop
`PYTHONPATH`, and set `DEV`. Three variables move the artifacts, and MEASURED on this tree,
on this device:

  PYTHONHASHSEED  WAS NOT PINNED and MOVED AN ARTIFACT; now pinned, and the oracle's real
      fix was a SORT. The oracle printed `py['ops'] ^ bd['ops']` as an unsorted `set`;
      MEASURED then, `runs/graphcmp/D` and `.agents/slop/rerun/D-before/` disagreed on
      `D0-coverage-census.txt` and on NOTHING else -- 3 of 196 files, all order-only. The
      file now SORTS those prints (`graphcmp-oracle.py:233,279`) under its own rule, 'a PIN
      IS A SEED AND a SORT IS A LAW' (:307), so whether a seed still moves the census is
      RE-MEASURABLE rather than settled.
  NOOPT           WAS NOT PINNED and MOVES THE COMPARED FIELD (the CPython oracle, not the
      bend side). MEASURED: `NOOPT=1` takes `lin` from 46 nodes to 45 and its SINK arg from
      `n(Opt(op=EOptOps.SPLIT...))` to `n()` -- the exact field the one recorded DISAGREE
      turns on -- and breaks the `46/46` census count. It is not a knob on the harness; it
      is a knob on the SUBJECT. `differ.py`'s ENV pins it for the oracle; the bend side has
      no reader (see PINS).
  DEV             SET BY THREE ROUTES TO THREE VALUES, and it MOVES A COUNT AND AN OP NAME.
      See `MEASURED` on `dev_route` below. This is the finding that changed the shape of
      this file.

THE THREE ARE DECLARED IN ONE PLACE, HERE, and every other consumer READS them from here
rather than restating them. `checks/differ.py` is not this file's to edit and its authority
is committed; the lines it needs are named in `PINS` below as (file, ANCHOR, tokens), so a
required change travels as a patch the owner applies, not as an edit made behind its back.

THE PINS ARE ANCHORED BY THEIR OWN TEXT, NOT BY A LINE NUMBER. The first revision named
(file, line, exact text), and the line number rotted the moment an edit landed above it: the
census capture was pinned at `checks/differ.py:509` while the call sat at `:513`, a miss that
predated every edit that touched the file. A pin that names a line number is a hand list of
one; a pin that names an anchor survives an edit above it. So METHOD A greps for the ANCHOR
and asserts the tokens on the line it lands on.

AND ONE PIN IS OVER-SPECIFIED, MEASURED RATHER THAN INHERITED. `graphcmp.py`'s `clean_env`
feeds only `bin/bend` -- the `/bin/sh` -> `bun` shim -- and grep finds NO reader of `NOOPT`
or `PYTHONHASHSEED` downstream of it: the port reads five flags (DEBUG, DEFAULT_FLOAT,
DEFAULT_INT, NO_COLOR, SUM_DTYPE; `helpers.bend:308,342-345`) and bun reads none of these. So
`clean_env` pins `LC_ALL` and `DEV`, the declaration asks for exactly that, and demanding the
other two there would be an edit made to satisfy a regex.

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
     "already pinned by `differ.py`'s ENV and `graphcmp.py`'s clean_env (both named in "
     "PINS below). Listed because a precondition table that names only what is MISSING "
     "reads as a partial one."),
    ("DEV", "CPU",
     "MEASURED, and this row is the reason the file exists. `differ.py`'s ENV runs the "
     "census with DEV=NULL; the graph steps pass `--dev CPU`. The oracle's predecessor "
     "wrote `os.environ.setdefault(\"DEV\", \"CPU\")`, a NO-OP precisely because NULL was "
     "already set; today it ASSIGNS `os.environ[\"DEV\"] = graphcmp_dev()` "
     "(`graphcmp-oracle.py:192`), read from graphcmp.py's own `--dev` default. So ONE run "
     "produced `D0-coverage-census.txt` under DEV=NULL and every `D1-graph-*.txt` under "
     "DEV=CPU. MEASURED CONSEQUENCE: the census's `late` is 13 py nodes reaching "
     "RECIPROCAL; `D2-canon-py-late.txt` is 12 nodes reaching FDIV; the census's TOTAL is "
     "313 where DEV=CPU gives 312. The census is measuring a different graph than the one "
     "the verdict is about."),
    ("PYTHONHASHSEED", "0",
     "MEASURED: the cause of the `D0-coverage-census.txt` difference between two runs of "
     "this tree, when the oracle printed a set unsorted. The oracle now SORTS those prints "
     "(`graphcmp-oracle.py:233,279`), so whether a seed still moves the census is "
     "RE-MEASURABLE rather than settled; it stays declared because the run records it."),
    ("NOOPT", "0",
     "MEASURED: `NOOPT=1` takes `lin` 46->45 nodes and its SINK arg to `n()`, moving the "
     "field the recorded DISAGREE turns on. It is a knob on the CPython oracle, not on the "
     "bend side. `NOOPT=` (EMPTY) is worse than either: it is `type(0)(\"\")` at "
     "tinygrad/helpers.py:163 and raises ValueError on import."),
)
BY_NAME = {n: v for n, v, _ in PRECONDS}

#: Every line a child environment's correctness depends on, as (file, ANCHOR, must-carry).
#: The ANCHOR is a literal substring naming the line's JOB, so an edit above it cannot move
#: the pin; `must-carry` is the extra tokens the line is required to contain. NAMED, NOT
#: EDITED -- `checks/differ.py` and `.agents/slop/graphcmp.py` are not this file's.
PINS: tuple[tuple[str, str, tuple[str, ...]], ...] = (
    # differ.py's ENV is what pins the CPython oracle's env, and the oracle reads both.
    ("checks/differ.py", 'ENV = {k: v', ("PYTHONHASHSEED", "NOOPT")),
    # :513, not the :509 the first revision named -- the census capture carries the note
    # that its env comes from ENV above. ANCHORED, so the number is not pinned.
    ("checks/differ.py", 'capture("D0-coverage-census.txt"', ("PYTHONHASHSEED", "NOOPT")),
    # The oracle ASSIGNS DEV (:192), it does not setdefault -- differ.py already set NULL and
    # setdefault against a set key is a no-op.
    (".agents/slop/graphcmp-oracle.py", 'os.environ["DEV"] = DEV', ()),
    # clean_env feeds bin/bend only; no reader of NOOPT/PYTHONHASHSEED exists downstream, so
    # it pins LC_ALL (and DEV, its argument) and the declaration asks for no more.
    (".agents/slop/graphcmp.py", 'e.update(LC_ALL="C", DEV=dev)', ()),
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
    # The summary is where a run RECORDS its env. METHOD B reads it with partition("="), and
    # `observed` reads the same keys, so `--record` and `--check` cannot disagree about what
    # the run left behind.
    rec = declared_values(SUMMARY) if SUMMARY.exists() else {}
    return {
        "DEV": dev,
        "PYTHONHASHSEED": rec.get("pythonhashseed", "UNRECORDED"),
        "NOOPT": rec.get("noopt", "UNRECORDED"),
        "LC_ALL": rec.get("lc_all", "UNRECORDED"),
        "evidence": {
            "DEV": f"census line `{census_late.strip()[:60]}`; canon-py-late ops "
                   f"{'FDIV' if 'FDIV' in late_ops else 'RECIPROCAL'} -- DEV=NULL reaches "
                   f"RECIPROCAL on 13 nodes, DEV=CPU reaches FDIV on 12",
            "PYTHONHASHSEED": f"D0-run-summary.txt records pythonhashseed="
                              f"{rec.get('pythonhashseed', '?')}; the census order it once "
                              "moved is described in the module docstring",
            "NOOPT": f"census `lin` row and `D2-canon-py-lin.txt` both carry the 46-node "
                     f"spelling; NOOPT=1 emits 45 and `n()`; summary records "
                     f"noopt={rec.get('noopt', '?')}",
            "LC_ALL": "differ.py's ENV and graphcmp.py's clean_env both set it",
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
      * METHOD A -- reads the source lines that make the pins, matched by ANCHOR rather than
        line number, so a pin that was deleted or moved is caught even when the summary
        still carries a stale value that would satisfy B.
      * METHOD B -- reads the summary's own `key=value` lines with `partition("=")` and NO
        regex, so a value that was never pinned but was written down is caught by A.
    Neither alone can be satisfied by a lie: A cannot see a lie in the summary, B cannot see
    a missing pin.

    `sources` and `summary` are PARAMETERS so the plants exercise this exact function against
    a fabricated tree. A plant that called a private helper would prove the helper.
    """
    sources = sources if sources is not None else {
        p: (ROOT / p).read_text().splitlines() for p in {q for q, _, _ in PINS}}
    summary = summary if summary is not None else SUMMARY
    bad: list[str] = []

    print("METHOD A -- the source lines that build the child environments, found by anchor:")
    for path, anchor, required in PINS:
        line = next((ln for ln in sources.get(path, []) if anchor in ln), "")
        miss = [t for t in required if t not in line]
        if not line:
            bad.append(f"{path}: no line contains anchor {anchor!r}")
            print(f"    MISSING  {path} has no line containing {anchor!r}")
        elif miss:
            bad.append(f"{path}: {anchor!r} does not pin {','.join(miss)}")
            print(f"    MISSING  {anchor!r} lacks {','.join(miss)}")
        else:
            print(f"    ok       {anchor!r} pins {','.join(required) or '(its own tokens)'}")

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
    print("\nlines each file must carry (NAMED, not edited here):")
    for path, anchor, required in PINS:
        carry = f" must carry {', '.join(required)}" if required else ""
        print(f"  {path}: {anchor!r}{carry}")
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
    (the summary's `NOOPT`) and one REVERTS a pin METHOD A reads (`differ.py`'s `ENV`, whose
    anchored line survives while its tokens do not). Neither
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
    lines_of: dict[str, list[str]] = {}
    for path, anchor, required in PINS:      # fabricate a tree where every pin holds
        lines_of.setdefault(path, []).append(
            anchor + "".join(f' {t}="0"' for t in required))
    if move_pin:      # REVERT the ENV pin: the anchored line survives, its tokens do not
        lines_of["checks/differ.py"][0] = (
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