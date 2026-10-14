#!/usr/bin/env python3
"""regalloc_census-gate.py -- CPython vs the port for `codegen/late/regalloc.py`.

    .venv/bin/python gates/regalloc_census-gate.py
    .venv/bin/python gates/regalloc_census-gate.py --refresh     # rewrite the pins

48 ROWS, THREE LANES (the oracle, `bend` interpreted, `bend` natively compiled), ZERO
DECLARED DIVERGENCES. Before this gate `tinybendygrad/codegen/late/regalloc.bend` had **NO
GATE AT ALL**: MEASURED, `grep -rl regalloc gates/*-gate.py` answers zero files, so its 203
ported defs were ungated. Its sibling `gates/linearizer_census-gate.py` is the other half of
the same 488 defs in `codegen/late/`.

WHAT THIS LAYER RETURNS, AND WHY THE ROWS HAVE THIS FORM. `LinearScanRegallocContext` returns
five DICTS keyed by PROGRAM POINT (`live_range`, `locals`, `spills`, `reals`,
`insert_before`) and `regalloc_rewrite` returns `(nx, before + [nx] + after)`. So the answer
is a MAP, not a toposort -- the case the census brief flags -- and a count cannot see it: a
wrong assignment has the right number of pairs, the right pairs' KEYS and the wrong real
register. MEASURED, `ra0_a7` says `v4>10->rcx>1` and `ra1_a7` says `v4>10->rdx>2`: one number
moved, out of three pairs, on a fixture pair that is identical except for `is_two_address`.

So every row is either the map AT ONE PROGRAM POINT (`ra<t>_a<i>`, one row per key of
`reals`, carrying every virtual live there and the REAL register each took) or a per-key LIST
(`ra<t>_lr`, the live range as the ordered index list it is -- `vdef` reads `live_range[v][0]`,
so the order IS the value and a set would be a different answer). Printed pairs are SORTED AS
TEXT, and that is load-bearing rather than cosmetic: `ra2_a4` is `v0>3 v2>5 v5>4` sorted as
text and `v0 v5 v2` by intern position, so the two orders disagree and the port sorts the
same strings the oracle does.

WHAT THE ORACLE SUPPLIES, AND WHY IT IS NOT THE PORT'S BUSINESS. `LinearContext.assign_spill_
slot`, `ISARenderer.fill` and `ISARenderer.spill` all `raise NotImplementedError("arch
specific")` in tinygrad's own base class (`renderer/isa/__init__.py:37,47,48`) and
`is_two_address` is `return False` (:46). The oracle subclasses both, and `ra0`/`ra1` are the
SAME uop list with `is_two_address` False and True. The slot spelling `slot:<name>` is the
PORT's alphabet, so it lives in the oracle and not in `regalloc.py`.

THE POPULATION IS DISCOVERED, NOT LISTED. `regalloc.bend` builds its rows by `String.concat`
over helpers inside a `do IO<Unit>` block, so no regex over its source can enumerate them
without becoming a second implementation of the gate. BOTH SIDES ARE RUN, the gatekit row
COUNT holds the population, and `rows_hold()` re-checks that the two lanes' row NAMES agree
IN ORDER on every run -- a `main()` that reordered two row classes is red before a value is
compared, which a count alone would miss.

ZERO DIVERGENCES IS A MEASUREMENT AND NOT AN ABSENCE. `gates/regalloc_census-pins.rows` is
written by `--refresh` and holds ZERO quads, and `--refresh` REFUSES to write a pins file
carrying a row that lands in no declared class -- so the zero is the result of a comparison
that ran, not a declaration that there was nothing to compare. `classes_hold()` re-derives
the divergence set from the lanes on every run and a row that STARTS differing without a pin
is a red run in the other direction.
"""

import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import Gate, gate, PY, BEND, ROOT

HERE = Path(__file__).resolve().parent
DRIVER = ROOT / "tinybendygrad" / "codegen" / "late" / "regalloc.bend"
ORACLE = HERE / "regalloc_census-oracle.py"
PINS = HERE / "regalloc_census-pins.rows"
ROWS = 48


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


# `--refresh` REFUSES TO PIN A ROW THAT LANDS IN NONE OF THESE, and there is deliberately no
# catch-all: a pins file that grows a difference nobody has looked at is a weakened instrument
# wearing a gate's clothes. An empty file is the correct answer for this gate and it is a
# MEASUREMENT -- see this file's header.
CLASSES = [
    ("UNEXPLAINED", r"^.*$",
     "NO CLASS. A row that differs and matches none of these is a real divergence with no "
     "reason attached; `--refresh` refuses to pin it rather than record a difference nobody "
     "has looked at."),
]


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
        "# divergence list read from there is destroyed by the first red run.",
        "#",
        "# A ZERO-LENGTH FILE IS NOT A MISSING ONE. `_pins()` answers REFUSED for a missing",
        "# file and an empty dict for an empty one, and only the second is a verdict. THIS FILE",
        "# IS EMPTY BECAUSE THE COMPARISON RAN: `--refresh` ran both lanes, compared all 48",
        "# rows, found none differing, and wrote the header and no quads. It is not empty",
        "# because nobody looked.",
        "#",
    ])


def _lines(s):
    return [l for l in s.splitlines() if l.strip()]


def _rows_of(text):
    return {l.split("=", 1)[0]: l.split("=", 1)[1] for l in _lines(text) if "=" in l}


def _lanes():
    lanes = {}
    for tag, argv in (("py", [str(PY), str(ORACLE)]), ("bd", [str(BEND), str(DRIVER)])):
        r = subprocess.run(argv, capture_output=True, text=True, cwd=str(ROOT))
        if r.returncode != 0:
            return None, f"lane {tag} failed rc={r.returncode}: {(r.stderr or '').strip()[:200]}"
        lanes[tag] = r.stdout
    return lanes, ""


def refresh():
    lanes, err = _lanes()
    if lanes is None:
        print(f"--refresh: {err}", file=sys.stderr)
        return 1
    py, bd = _rows_of(lanes["py"]), _rows_of(lanes["bd"])
    if list(py) != list(bd) or len(py) != ROWS:
        print(f"--refresh: the lanes hold {len(py)} and {len(bd)} rows, expected {ROWS} with "
              f"the same names in the same order", file=sys.stderr)
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
    out = [_header(len(rows), ROWS - len(rows))]
    for cls, row, pv, bv in rows:
        out += [f"# {cls} -- {next(w for c, _, w in CLASSES if c == cls)}", "",
                f"{row}\t{cls}\t{pv}\t{bv}"]
    PINS.write_text("\n".join(out) + "\n")
    print(f"--refresh: {PINS.name} rewritten -- {len(rows)} divergences of {ROWS} rows")
    return 0


def rows_hold(lanes):
    a = [l.split("=", 1)[0] for l in _lines(lanes["py"])]
    b = [l.split("=", 1)[0] for l in _lines(lanes["bd"])]
    if a == b:
        return []
    return [f"the lanes' row NAMES differ ({len(a)} vs {len(b)}), first moves "
            f"{[f'{x}->{y}' for x, y in zip(a, b) if x != y][:3]}"]


def classes_hold(lanes):
    py, bd = _rows_of(lanes["py"]), _rows_of(lanes["bd"])
    bad = []
    for row, (cls, pair) in DIVERGES.items():
        for tag, want in (("py", pair[0]), ("bd", pair[1])):
            got = next((l for l in _lines(lanes[tag]) if l.startswith(row + "=")), None)
            if got != want:
                bad.append(f"{tag}'s {row} is {got!r}, pinned {want!r}")
    for row in py:
        if py[row] != bd[row] and row not in DIVERGES:
            bad.append(f"{row} differs and is NOT pinned: py={py[row]!r} bd={bd[row]!r}")
    return bad


DIVERGES, PINS_ERR = _pins()


def build():
    g = Gate("regalloc_census", bend=str(DRIVER), oracle=str(ORACLE), rows=ROWS,
             compared=ROWS - len(DIVERGES),
             diverges={r: p for r, (_, p) in DIVERGES.items()})

    def checks():
        lanes, err = _lanes()
        if lanes is None:
            print(f"regalloc_census: {err}", file=sys.stderr)
            return False
        bad = rows_hold(lanes) + classes_hold(lanes)
        for b in bad:
            print(f"regalloc_census: {b}", file=sys.stderr)
        return not bad

    return g, checks


def main():
    if PINS_ERR:
        print(f"regalloc_census: REFUSED, {PINS_ERR}")
        return 3
    g, checks = build()
    return gate(g, f"regalloc_census: {ROWS} rows, {ROWS - len(DIVERGES)} compared, "
                   f"{len(DIVERGES)} declared divergences", checks)


if __name__ == "__main__":
    if "--refresh" in sys.argv:
        sys.exit(refresh())
    sys.exit(main())