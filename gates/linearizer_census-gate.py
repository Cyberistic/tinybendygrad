#!/usr/bin/env python3
"""linearizer_census-gate.py -- CPython vs the port for `codegen/late/linearizer.py`.

    .venv/bin/python gates/linearizer_census-gate.py
    .venv/bin/python gates/linearizer_census-gate.py --refresh     # rewrite the pins

71 ROWS, THREE LANES (the oracle, `bend` interpreted, `bend` natively compiled), TWO DECLARED
DIVERGENCES OF ONE CLASS. Before this gate `tinybendygrad/codegen/late/linearizer.bend` had
**NO GATE AT ALL**: MEASURED, `grep -rl linearizer gates/*-gate.py` answers zero files and
`grep -rl regalloc gates/*-gate.py` answers zero files, so 488 ported defs across the two
files of `codegen/late/` were ungated. The port's own header named its acceptance test

    diff <(python3 /tmp/opencode/late-oracle.py) <(./bin/bend tinybendygrad/codegen/late.bend)

and MEASURED, all three parts of that line are dead. `/tmp/opencode/late-oracle.py` does not
exist; `tinybendygrad/codegen/late.bend` has been a DIRECTORY since the 1:1 split (the
header's own first paragraph says so); and `/tmp` is not a place a gate's input may live --
`AGENTS.md` records 180 of the 333 paths `.agents/TOOLS.md` names deleted from swept trees,
85 of them under `.agents/slop/`. So the port's 71 rows had never been compared to CPython by
anything. This gate is that comparison, and `gates/regalloc_census-gate.py` is its sibling.

WHY THESE ROWS AND NOT OTHERS. `linearize` returns an ORDERED LIST of UOps -- a toposort
with a priority heap on top -- so a count cannot see a reordering and a multiset cannot see
one either. Every row class is therefore either the ordered sequence itself (`lin_srcs`,
`lin_ord`, `lin_nkey`, the `linc_*` family) or ONE ROW PER NODE OF THAT SEQUENCE (`lin_u<i>`,
carrying op + run_count + priority + nkey), or the edge list in POSITIONS (`lin_edg`,
`linc_edg`, `cfg_edges`) -- the form that catches a src permutation, the defect class that
made `tn_isfinite` read `CMPNE(MUL, CONST)` where CPython reads `CMPNE(CONST, CONST)` while
two existing gates called it PASS. `gatekit` diffs ORDERED lists, so a defect has no total to
cancel inside.

THE POPULATION IS DISCOVERED, NOT LISTED. `linearizer.bend` builds its rows by `String.concat`
over helpers inside a `do IO<Unit>` block, so no regex over its source can enumerate them
without becoming a second implementation of the gate. BOTH SIDES ARE RUN instead, and the
gatekit row COUNT is what holds the population: a row present on one lane and not the other
is DEAD or FAIL before any value is compared, and a row class that changes size is a count
failure. The oracle prints in the port's order because `gatekit` filters and diffs by
position, and `rows_hold()` re-checks that the two lanes' row NAMES agree IN ORDER on every
run, so a reordered `main()` is red before a value is compared.

WHAT IS A SCOPE AGREEMENT AND NOT A CARVE-OUT. `TUPLE_ORDER=0`: `linearizer.py:36` sorts on
`priorities[x] + (x.tuplize if TUPLE_ORDER else ())` and `helpers.TUPLE_ORDER` is a ContextVar
defaulting to 1. The port names the `=1` lane a wall -- `x.tuplize` is a recursive structural
key holding a `repr` and a dtype -- so the oracle asks CPython for the `=0` lane inside
`Context(TUPLE_ORDER=0)`. Both lanes are then the same lane. MEASURED, the two differ over
this fixture: CPython's `=1` order is `PARAM CONST CAST ALLOC SPECIAL BUFFER CONST CAST ADD
STORE RANGE:0 END CONST CAST ADD STORE RANGE:1 END SINK` and its `=0` order is `PARAM CONST
CAST ALLOC SPECIAL BUFFER ADD CONST CAST STORE RANGE:0 END CONST CAST ADD STORE RANGE:1 END
SINK`, so comparing against the default would be comparing against a lane the port does not
claim.

THE ORACLE HAS ONE TRANSCRIPTION AND IT IS CHECKED ON EVERY RUN. `po_*` reads the priority
ladder, which lives inside `linearize`'s body: CPython exports no `priority_of`, so
`ladder_check()` in the oracle predicts the order `linearize` returns over two fixtures of
independent leaves and calls `linearize` to see whether it agrees, exiting 2 -- a gatekit
REFUSED -- on a mismatch. A mistyped constant is a dead gate and never a green row.

THE PINS FILE IS GIT-RESIDENT AND BESIDE THE GATE. `gates/artifacts/` is `.gitignore`d, is
emptied by `Gate.__init__` and is unlinked from when a run is not green, so a divergence list
read from there is destroyed by the first red run and there is then nothing left to edit.
`--refresh` is its ONLY writer and it REFUSES to pin a row that lands in no declared class:
a pins file that grows a difference nobody has looked at is a weakened instrument wearing a
gate's clothes.
"""

import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, gate, PY, BEND, ROOT

HERE = Path(__file__).resolve().parent
DRIVER = ROOT / "tinybendygrad" / "codegen" / "late" / "linearizer.bend"
ORACLE = HERE / "linearizer_census-oracle.py"
PINS = HERE / "linearizer_census-pins.rows"
ROWS = 71


# ===========================================================================
# THE DIVERGENCE POPULATION -- declared in a file beside the gate, PINNED on both sides,
# written by `--refresh` and by nothing else.
# ===========================================================================
def _pins():
    if not PINS.is_file():
        return None, (f"{PINS.name} is MISSING -- a gate's declared divergences must live in "
                      f"git, beside the gate, not in `gates/artifacts/`. Run --refresh.")
    pins = {}
    for ln in PINS.read_text().splitlines():
        if not ln.strip() or ln.startswith("#"):
            continue
        parts = ln.split("\t")
        if len(parts) != 4:
            return None, f"{PINS.name}: a line is not row<TAB>class<TAB>oracle<TAB>port: {ln!r}"
        row, cls, py_v, port_v = parts
        pins[row] = (cls, (f"{row}={py_v}", f"{row}={port_v}"))
    return pins, ""


# A divergence needs a CLASS before it can be pinned. `--refresh` refuses an unclassed row,
# and `classes_hold()` re-derives each pin's class from the lanes on EVERY run, so a pinned
# row that stops being its class is a red run and not a stale sentence.
CLASSES = [
    ("ORPHAN-CONST", r"^(ix|ix_len)$",
     "A FIXTURE DEFECT, NOT AN INSTRUMENT CARVE-OUT. `lt_fix` (linearizer.bend:867-904) "
     "opens with `+c1a = O.UOp.const(O.Arena.empty(), O.CInt{1})` and then "
     "`+c1 = lt_i32(1, O.Found.ar(c1a))`, and `lt_i32` (:864) is "
     "`lt_i32.go(O.UOp.const(ar, O.CInt{...}), ar)` -- it mints its OWN const from the arena "
     "it is handed instead of reading the one it was given. `UOp.const` (ops.bend:2961) is "
     "`UOp.new(ar, OpsCONST{}, Nil{}, APy{v}, TNone{})` and `UOp.new` (:2700) APPENDS, so "
     "arena index 0 is ORPHANED. MEASURED FROM THE PORT'S OWN ROWS: `lt_lst` is "
     "`[1,2,7,8,9,11,12,5,6,16,17,3,4,10,14,15,18,13,19]` and `lt_lst_call` is "
     "`[9,1,2,11,20,21]`, and their union is {1..21} MINUS {0} -- index 0 is the only one of "
     "the 22 neither toposort names. CPython's own walk of the same two sinks finds 21. This "
     "is the STALE-ARENA shape (nine fixes this session) with a benign outcome: nothing "
     "re-reads index 0, so today it costs a row and not a wrong answer. The fix is `lt_i32` "
     "taking the const it is given, and the pin has to move with it."),
    ("UNEXPLAINED", r"^.*$",
     "NO CLASS. A row that differs and matches none of these is a real divergence with no "
     "reason attached; `--refresh` refuses to pin it rather than record a difference nobody "
     "has looked at."),
]


def _why(cls):
    return next(w for c, _, w in CLASSES if c == cls)


def _header(n_div, n_same):
    return "\n".join([
        f"# {PINS.name} -- GENERATED by `{Path(__file__).name} --refresh`, which is its ONLY",
        "# writer. One TAB-separated QUAD per declared divergence:",
        "# `<row>\\t<class>\\t<CPython's value>\\t<the port's value>`.",
        "#",
        f"# {n_div} DIVERGENCES of {ROWS} ROWS, {n_same} OF WHICH AGREE EXACTLY.",
        "#",
        "# GIT-RESIDENT AND BESIDE THE GATE because `gates/artifacts/` is `.gitignore`d, is",
        "# EMPTIED by `Gate.__init__` and is UNLINKED from when a run is not green -- a",
        "# divergence list read from there is destroyed by the first red run and there is then",
        "# nothing left to edit.",
        "#",
        "# THE CLASS COLUMN IS NOT DECORATION. `classes_hold()` re-derives each row's class",
        "# from the lanes on EVERY run, so a pinned row that stops being its class is a red",
        "# run rather than a stale sentence.",
        "#",
        "# A ZERO-LENGTH FILE IS NOT A MISSING ONE. `_pins()` answers REFUSED for a missing",
        "# file and an empty dict for an empty one, and only the second is a verdict.",
        "#",
    ])


def _lines(s):
    return [l for l in s.splitlines() if l.strip()]


def _rows_of(text):
    return {l.split("=", 1)[0]: l.split("=", 1)[1] for l in _lines(text) if "=" in l}


def _lanes():
    """Both lanes, once, by running them. `--refresh` and `classes_hold` share this."""
    lanes = {}
    for tag, argv in (("py", [str(PY), str(ORACLE)]), ("bd", [str(BEND), str(DRIVER)])):
        r = subprocess.run(argv, capture_output=True, text=True, cwd=str(ROOT))
        if r.returncode != 0:
            return None, f"lane {tag} failed rc={r.returncode}: {(r.stderr or '').strip()[:200]}"
        lanes[tag] = r.stdout
    return lanes, ""


def refresh():
    """REWRITE the pins from a fresh pair of lanes. Its only writer.

    It does NOT go through `Gate.run()`, because a refresh is exactly what a run cannot do
    when the pins are wrong: the whole point is to replace them. A row that disagrees and
    lands in NO declared class is REFUSED rather than pinned."""
    lanes, err = _lanes()
    if lanes is None:
        print(f"--refresh: {err}", file=sys.stderr)
        return 1
    py, bd = _rows_of(lanes["py"]), _rows_of(lanes["bd"])
    if list(py) != list(bd) or len(py) != ROWS:
        print(f"--refresh: the lanes hold {len(py)} and {len(bd)} rows and "
              f"{'the same names in the same order' if list(py) == list(bd) else 'DIFFERENT NAMES'},"
              f" expected {ROWS}", file=sys.stderr)
        return 1
    rows, unknown = [], []
    for row in py:
        if py[row] == bd[row]:
            continue
        cls = next((c for c, pat, _ in CLASSES if c != "UNEXPLAINED" and re.search(pat, row)),
                   None)
        (rows if cls else unknown).append((cls, row, py[row], bd[row]))
    if unknown:
        print(f"--refresh: no class for {[r for _, r, _, _ in unknown]} -- declare one before "
              f"refreshing, or a new divergence is pinned with no reason", file=sys.stderr)
        return 1
    out = [_header(len(rows), ROWS - len(rows)), ""]
    last = None
    for cls, row, pv, bv in rows:
        if cls != last:
            out += [f"# {cls} -- {sum(1 for r in rows if r[0] == cls)} rows. {_why(cls)}", ""]
            last = cls
        out.append(f"{row}\t{cls}\t{pv}\t{bv}")
    PINS.write_text("\n".join(out) + "\n")
    print(f"--refresh: {PINS.name} rewritten -- {len(rows)} divergences of {ROWS} rows")
    return 0


def classes_hold(lanes):
    """Every pin's class RE-DERIVED from the lanes, and every UNPINNED divergence refused.

    Two directions, because a pins file can rot both ways: a row that stops being its class
    (the reason has died, or the fix moved the row) is a red run, and a row that STARTS
    differing without being pinned is a red run too."""
    py, bd = _rows_of(lanes["py"]), _rows_of(lanes["bd"])
    bad = []
    for row, (cls, pair) in DIVERGES.items():
        for tag, want in (("py", pair[0]), ("bd", pair[1])):
            got = next((l for l in _lines(lanes[tag]) if l.startswith(row + "=")), None)
            if got != want:
                bad.append(f"{tag}'s {row} is {got!r}, pinned {want!r}")
        want_cls = next((c for c, pat, _ in CLASSES if c != "UNEXPLAINED"
                         and re.search(pat, row)), None)
        if want_cls != cls:
            bad.append(f"{row} is pinned as {cls}, which its name no longer says ({want_cls})")
    for row in py:
        if py[row] != bd[row] and row not in DIVERGES:
            bad.append(f"{row} differs and is NOT pinned: py={py[row]!r} bd={bd[row]!r}")
    return bad


def rows_hold(lanes):
    """THE POPULATION, CHECKED AS A SEQUENCE OF NAMES AND NOT AS A COUNT.

    A count alone cannot see a `main()` that reordered two row classes, and the whole file
    is about positions -- so the two lanes' row NAMES must agree IN ORDER."""
    a = [l.split("=", 1)[0] for l in _lines(lanes["py"])]
    b = [l.split("=", 1)[0] for l in _lines(lanes["bd"])]
    if a == b:
        return []
    moved = [f"{x}->{y}" for x, y in zip(a, b) if x != y][:3]
    return [f"the lanes' row NAMES differ ({len(a)} vs {len(b)}), first moves {moved}"]


DIVERGES, PINS_ERR = _pins()

def build():
    """THE GATE AND ITS OWN CHECKS, as a function, because the mutation harness imports this
    module and calls `main()` with `DRIVER` pointed at a COPY. A gate whose verdict lives
    under `if __name__ == '__main__'` cannot be run against a copy at all."""
    n = len(DIVERGES)
    # `gatekit` unpacks each `diverges` value as `(ORACLE's line, PORT's line)`, so the CLASS
    # this file carries alongside every pin has to be STRIPPED here rather than passed through
    # -- and a class string handed to `gatekit` in that slot becomes a pin that never matches,
    # which is a FAIL with a message that names the wrong thing.
    g = Gate("linearizer_census", bend=str(DRIVER), oracle=str(ORACLE), rows=ROWS,
             compared=ROWS - n, diverges={r: p for r, (_, p) in DIVERGES.items()})

    def checks():
        lanes, err = _lanes()
        if lanes is None:
            print(f"linearizer_census: {err}", file=sys.stderr)
            return False
        bad = rows_hold(lanes) + classes_hold(lanes)
        for b in bad:
            print(f"linearizer_census: {b}", file=sys.stderr)
        return not bad

    return g, checks, n


def main():
    if PINS_ERR:
        print(f"linearizer_census: REFUSED, {PINS_ERR}")
        return 3
    g, checks, n = build()
    return gate(g, f"linearizer_census: {ROWS} rows, {ROWS - n} compared, "
                  f"{n} declared divergences", checks)


if __name__ == "__main__":
    if "--refresh" in sys.argv:
        sys.exit(refresh())
    sys.exit(main())