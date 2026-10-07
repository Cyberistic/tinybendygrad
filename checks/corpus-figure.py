#!/usr/bin/env python3
"""Measure the corpus and refuse to let its figure rot. `checks/corpus-figure.py`

    usage: .venv/bin/python checks/corpus-figure.py [--write]

THE CLAIM, WITH ITS DENOMINATOR.  `graphcmp.GRAPHS` declares **N** graphs; every one of them
builds; the set **UNION** of the ops they reach is **K of len(Ops)**. This prints all three, plus
the per-graph SUM, which is **not** the figure — and it is printed precisely because the sum is
the wrong number and the wrong number is what keeps getting written down.

WHY IT EXISTS, MEASURED.  The corpus figure existed in **at least nine** forms across the reports
at once: `13`, `34`, `35`, `43`, `54`, `59`, `60`, `61`, `73` and `77 of 77` — and `25 graphs`
against a measured `22`. **Three of them are arithmetically impossible as a coverage claim:
`588 of 77`, `372 of 77` and `0 of 77`.** Those three are the giveaway: **a figure larger than its
denominator is a PER-GRAPH SUM COMPARED AGAINST A SET.** Summing `ops-reached` across graphs counts
`BUFFER` once per graph that has one. *MEASURED HERE: the sum is 157 against a union of 53.*

A figure that nine documents disagree about is not documentation, and a figure nobody can
reproduce is not a measurement. This is the instrument that settles it, so the next disagreement
costs one command instead of an afternoon.

DENOMINATOR HANDLING, WHICH IS THE WHOLE POINT.  `len(Ops)` is read off the LIVE
`tinygrad.uop.ops.Ops`, so a new upstream op cannot age the answer silently — which is exactly how
the 34/35 pair happened. A graph that fails to build is **printed and counted separately**, never
skipped quietly: a coverage figure that silently drops a graph understates the coverage it claims.
"""
from __future__ import annotations
from pathlib import Path

import argparse
import importlib.util
import pathlib
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]

# THE DEVICE IS A DECLARED PRECONDITION OF THIS FIGURE, AND THIS IS WHERE IT IS ENFORCED.
#
# WHY A NEW CONDITION HERE AND NOT A FOURTH VIEW OF AN EXISTING ONE.  The conditions
# `checks/differ.py` pins all ask about THE COMPARISON: `graphs` how many graphs exist,
# `graphs-agree` how many rows agreed, `not-comparable` whether every graph was PUT TO the
# comparison, `expect-moved` whether the table's assertions held, `graphs-unset` whether
# anybody wrote a row.  **THIS ONE ASKS ABOUT THE CONDITIONS THE MEASUREMENT WAS TAKEN
# UNDER, WHICH IS NONE OF THOSE.** All five were measured to be `OK` on `DEV=CPU`, `DEV=NULL`
# and `DEV=METAL` alike (MEASURED: `not-comparable=0` and the `RUN HEALTH` line printed OK in
# all three), which is exactly why none of them can stand in for it -- **five conditions that
# agree across three devices are not five views of the sixth, they are five conditions blind
# to it.** That is also why `graphs-unanswered` was correctly NOT added: it would have asked
# `graphs-agree`'s question again.
#
# WHY IT IS NOT A SECOND SOURCE OF TRUTH.  The pin is DECLARED once, in `checks/devpin.py`'s
# `PINNED_DEV`, and READ here -- not re-derived from `runs/graphcmp/D/`, which would make the
# gate's precondition a fact about the artifact it is gating, which is the failure `differ.py`
# already paid for once ("a pin no code consults cannot fail" -> the reverse, "a pin derived
# from its own output cannot fail either").  MEASURED: `runs/graphcmp/D/D0-run-summary.txt`
# records no device at all (`grep -i 'dev|cpu|metal|device' ... ; echo rc=$?` -> `rc=1`),
# so there is nothing there to read even in principle.
#
# MEASURED 2026-10-06, this instrument, this tree, one command and three answers:
#   DEV=CPU    CPYTHON-SIDE UNION : 61 of 77   (g_late reaches FDIV)
#   DEV=NULL   CPYTHON-SIDE UNION : 60 of 77   (a / b stays MUL(a, RECIPROCAL(b)))
#   DEV=METAL  CPYTHON-SIDE UNION : 60 of 77
# `g_late` reads `Device.default.renderer.code_for_op.keys()` (graphcmp.py:1441-1448), so the
# op set is a property of the BACKEND.  **A COVERAGE FIGURE WHOSE DENOMINATOR MOVES WITH THE
# MACHINE IS A MEASUREMENT OF THE HOST.**
def pinned_dev() -> str:
    """`checks/devpin.py`'s `PINNED_DEV` -- the one declaration of the device."""
    spec = importlib.util.spec_from_file_location("devpin", ROOT / "checks/devpin.py")
    if spec is None or spec.loader is None:                    # `ty`: both are Optional, and
        raise SystemExit("checks/devpin.py has no importable spec -- the pin is unreadable")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.PINNED_DEV


def differ_module():
    """`checks/differ.py` BY PATH, for BOTH of its pin tables -- IMPORTED, never re-declared.

    A second copy of a pin list is a contract with no generator: it rots without anyone noticing,
    which is the failure `differ.declared()`'s docstring names for artifact names and this file's
    own history names for graph names. The pins are the run's verdict, and an instrument that
    prints `OK` over a red run because it consulted 3 of the 17 is the defect this loader exists to
    remove -- so it now also asks for `REPRO_PINS`, over a SECOND artifact.

    Loading is side-effect-free (`differ.py` imports only the standard library and runs nothing at
    module scope; `gates/retention-check.py` already imports it the same way for `unhealthy()`),
    so one load answers both questions and there is no second `spec_from_file_location` to rot.
    """
    spec = importlib.util.spec_from_file_location("differ_pins", ROOT / "checks/differ.py")
    if spec is None or spec.loader is None:                    # `ty`: both are Optional, and
        raise SystemExit("checks/differ.py has no importable spec -- the pins are unreadable")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def device_precondition() -> str:
    """THE NEW CONDITION. Returns a line to print and the rc it demands.

    The device has to be read BEFORE `load_graphcmp()`, because `load_tinygrad()` is the call
    that imports tinygrad and `tinygrad.helpers.DEV` is resolved at IMPORT (graphcmp.py:277-280).
    Reading it after would read a value the import already consumed, which is the
    read-after-side-effect shape of the same bug.
    """
    import os
    pin, got = pinned_dev(), os.environ.get("DEV")
    if got == pin:
        return f"DEVICE PRECONDITION : OK -- DEV={pin}, which is the declared pin"
    return (f"DEVICE PRECONDITION : **VIOLATED** -- DEV={got!r} and the declared pin is "
            f"{pin!r}. THIS FIGURE WOULD BE A MEASUREMENT OF THE HOST: `g_late` reads the "
            f"BACKEND's own op table, so the union moves with the device (MEASURED: 61 of 77 "
            f"on CPU, 60 on NULL and METAL). Re-run as `DEV={pin} .venv/bin/python "
            f"checks/corpus-figure.py`, or change the pin in `checks/devpin.py` AND re-take "
            f"the run -- not this figure alone.")


def load_graphcmp():
    """Import the differ by path, then force its DEFERRED tinygrad imports.

    `graphcmp.py` defers every tinygrad import into `load_tinygrad()` so the py side cannot build
    its graph on whatever device happens to open first. **Importing the module is therefore NOT
    enough** — measured: without the call, every graph raises `NameError` and a union over zero
    built graphs prints `0 of 77` beside a denominator that looks perfectly healthy. That is where
    one of the impossible figures in the reports came from.

    NOTE WHAT THIS BYPASSES, because it is the defect this file's pin now names:
    `graphcmp.py:2839` defaults `--dev CPU` and `:2853` writes it into `os.environ["DEV"]`
    inside `main()`. This function never calls `main()`, so **that pin does not run here** and
    `os.environ["DEV"]` is whatever the caller's shell held. `checks/differ.py` IS pinned (it
    goes through `main()`); this file was not, and `device_precondition()` is what makes the
    difference checkable instead of incidental.
    """
    spec = importlib.util.spec_from_file_location("gc", ROOT / ".agents/slop/graphcmp.py")
    gc = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(gc)
    gc.load_tinygrad()
    for n in ("AddrSpace", "DType", "dtypes", "AxisType", "Ops", "ParamArg", "UOp",
              "GroupOp", "Context"):
        setattr(sys.modules["gc"], n, getattr(gc, n))
    return gc


def run_health(declared: int) -> tuple[bool, str]:
    r"""The RUN's own verdict, or a loud statement that there isn't one.

    Returns `(every pin green, the line to print)`.

    MEASURED 2026-10-05. This function did not exist, and its absence is the whole defect: the
    instrument printed `graphs built 22 / FAILED 0` while `runs/graphcmp/D/D0-run-summary.txt` — which
    `checks/README.md:44` calls "the run's verdict" and `:67` "the only file `repro` reads for health" —
    said `graphs=16  graphs-agree=0  not-comparable=16  stable-failed=5 of 5`, and
    `D0-coverage-census.txt` said **in its own body** `emit bend: 0 rows after 5 attempts -- a FAILURE,
    not a verdict`. `D2-canon-bend-indexed.txt` is **0 bytes**.

    **A COVERAGE FIGURE PRINTED OVER A RUN THAT COMPARED NOTHING IS NOT A COVERAGE FIGURE.** The number
    was not wrong by being miscounted; it was answering a different question and wearing this
    instrument's name. So the run's health is read from the run, and `main` refuses on it.

    MEASURED 2026-10-06, THE POPULATION WAS THE DEFECT. This consulted **3 of the 17** pins
    `checks/differ.py` declares -- `graphs`, `graphs-agree`, `not-comparable` -- and printed
    `RUN HEALTH : OK` over a run red on 4 of 17 (`expect-moved=1` against a pinned `0`,
    `graphs-agree=20` and `byte-identical=20` against `19`, `selfcheck: FAIL` against `OK`).
    Three green pins out of seventeen is not a health verdict, it is a sample, and the sample
    happened to be the green part. **The pins are now IMPORTED from `differ.py` and every one is
    consulted**, so `OK` means the run is green on all 17 -- and a summary with no pins at all
    is 17 ABSENTs, not a pass. The parse is `differ.unhealthy()`'s own (split on the FIRST `=`,
    because nine of the seventeen values contain spaces, which the old `^(\S+)=(\S+)$` regex
    could not see at all).

    MEASURED 2026-10-06, ONE LEVEL UP: A PIN THE INSTRUMENT AND THE ARTIFACT SHARE IS A PIN
    THAT CANNOT SEE A GAP BETWEEN THEM. `checks/differ.py:221` pins `graphs` as the literal
    `"25"`, and the run that produced `runs/graphcmp/D/` wrote `graphs=25`; the corpus had
    grown to **34** (`graphcmp.GRAPHS`, `:1590`). So this printed
    `graphs declared : 34` beside `RUN HEALTH : OK (… graphs=25 …)`, rc=0 -- **the figure and
    the health gate were two witnesses to one stale run, not a comparison of the run to the
    corpus.** `graphs` is therefore NOT treated as a pin here: it is a DISCOVERY
    (`len(gc.GRAPHS)`, the same `gc` this instrument already holds), and it is compared to the
    artifact's `graphs=`. The literal in `differ.py` stays for `differ.unhealthy()`; this
    instrument derives. A corpus that grows now makes the artifact RED until it is re-taken,
    and no hand edit re-pins it -- which is the difference between a population and a list.

    MEASURED 2026-10-07, ONE LEVEL UP AGAIN: **ALL SEVENTEEN PINS READ ONE FILE.** Traced by
    `Path.read_text` under a scratch copy (`.agents/slop/pinindep/layer1.py`): `unhealthy()`
    opened 175 files and exactly ONE of them carried all 17 pin values. So `17 of 17 green` is
    one run's seventeen rows and the DENOMINATOR WAS 1 ARTIFACT, not 17 -- 10 independent
    measurements behind it, all functions of the same run. **A DENOMINATOR OF 1 IS NOT A HEALTH
    VERDICT ABOUT REPRODUCIBILITY, IT IS A VERDICT ABOUT ONE ATTEMPT.** So this now consults the
    SECOND WITNESS too: `differ.REPRO_PINS` (IMPORTED, never re-declared) read from
    `runs/graphcmp/D/D0-repro.txt` by `differ.repro_bad()` -- `cmd_repro`'s two clean runs,
    sha256 over every artifact, byte-compared. **THE DENOMINATOR IS NOW 2 ARTIFACT READS**, and a
    reader cannot be told `17 of 17` without being told whether the second measurement exists,
    because the two verdicts are computed here, side by side, and printed in ONE line.
    """
    summary = Path(__file__).resolve().parents[1] / "runs/graphcmp/D/D0-run-summary.txt"
    if not summary.exists():
        return (False, "RUN HEALTH        : **NO RUN SUMMARY** -- there is no run to corroborate "
                       "anything, so every pin is unknown rather than matched")
    pins = differ_module().PINS
    got = dict(ln.split("=", 1) for ln in summary.read_text(errors="replace").splitlines() if "=" in ln)
    # `graphs` IS DERIVED, NOT PINNED. Every other pin is a fact about the PORT or the RUN that
    # nobody can compute here; the corpus size is neither -- it is `len(gc.GRAPHS)`, a discovery.
    pinned = {k: v for k, v in pins.items() if k != "graphs"}
    red = [f"{k}={got[k]} (expected {pins[k]})" for k in pinned if k in got and got[k] != pins[k]]
    red += [f"{k} ABSENT" for k in pinned if k not in got]
    if "graphs" not in got:
        red.append("graphs ABSENT -- the artifact records no corpus size to compare")
    elif got["graphs"] != str(declared):
        red.append(f"graphs={got['graphs']} but the corpus DECLARES {declared} -- the ARTIFACT "
                   f"and the CORPUS disagree, so the health gate is reading a stale run")
    # THE SECOND WITNESS, CONSULTED HERE AND ONLY HERE, ONCE, OFF ONE IMPORT. `differ.repro_bad()`
    # is a FUNCTION, not a copy of `REPRO_PINS`, so a pin this file did not know about cannot be
    # invisible to it -- the same reason the 17 are imported rather than retyped. AND IT IS A
    # SEPARATE VERDICT, NOT AN 18TH PIN: `differ.unhealthy()` cannot carry it, because
    # `clean_run()` calls `unhealthy()` from INSIDE `cmd_repro`, one run before `D0-repro.txt`
    # exists, so a pin that demanded it there could never pass and would be a gate red forever.
    diff_mod = differ_module()
    repro = diff_mod.repro_bad()
    total, witness = len(pinned) + 1, len(diff_mod.REPRO_PINS)
    if red or repro:
        return (False, f"RUN HEALTH        : **FAILED** -- {total - len(red)} of {total} pins green "
                       f"over ONE artifact, plus {witness - len(repro)} of {witness} over "
                       f"`{diff_mod.REPRO_ARTIFACT}` "
                       f"({'AGREES' if not repro else 'RED'}). RED: {'; '.join(red + repro)}. "
                       f"THE UNION ABOVE IS NOT A VERDICT.")
    return (True, f"RUN HEALTH        : OK -- {total} of {total} pins green AND the SECOND WITNESS "
                  f"agrees: **2 artifact reads**, `D0-run-summary.txt` ({total} of them, one run) "
                  f"and `{diff_mod.REPRO_ARTIFACT}` ({witness} of {witness}, TWO clean runs "
                  f"byte-compared). `graphs` COMPARED TO THE CORPUS, not pinned; all pins "
                  f"IMPORTED from checks/differ.py")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--write", action="store_true", help="also print the CORPUS.md figure block")
    args = ap.parse_args()

    # THE PRECONDITION IS ASKED **FIRST** and its answer is PRINTED WITH THE FIGURE, not
    # instead of it: a refused figure that printed nothing is indistinguishable from an
    # instrument that crashed, and this one has already had that ambiguity once.
    device = device_precondition()
    print(device)
    dev_ok = "OK" in device.split("\n", 1)[0]

    gc = load_graphcmp()
    from tinygrad.uop.ops import Ops
    names = [o.name for o in Ops]

    union: dict[str, int] = {}
    per_graph_sum = 0
    built, broken = 0, {}
    for g in sorted(gc.GRAPHS):
        try:
            nodes = gc.build(gc.emit_py(g, None), "py")[0]
        except Exception as exc:                      # reported, never skipped quietly
            tb = exc.__traceback__
            frame = tb.tb_frame
            while tb.tb_next:
                tb = tb.tb_next
                frame = tb.tb_frame
            broken[g] = f"{type(exc).__name__}: {exc} at {frame.f_code.co_filename.split('/')[-1]}:{frame.f_lineno}"
            continue
        built += 1
        census = gc.ops_census(nodes)
        per_graph_sum += len(census)
        for op, k in census.items():
            union[op] = union.get(op, 0) + k

    missing = [n for n in names if n not in union]
    print(f"graphs declared   : {len(gc.GRAPHS)}")
    print(f"graphs built      : {built}")
    print(f"graphs FAILED     : {len(broken)}")
    for g, why in broken.items():
        print(f"    {g}: {why}")
    print(f"denominator len(Ops) : {len(names)}")
    print(f"CPYTHON-SIDE UNION   : {len(union)} of {len(names)}")
    print(f"  ^^ THIS IS A CENSUS OF **CPYTHON'S** OWN OP INVENTORY OVER THE {len(gc.GRAPHS)} GRAPH DEFINITIONS.")
    print("     IT IS **NOT** A MEASUREMENT OF THE PORT. `gc.build(gc.emit_py(g, None), \"py\")`")
    print("     BUILDS THE CPYTHON SIDE ONLY -- THE PORT IS NEVER INVOKED, SO A RUN IN WHICH")
    print("     `graphs-agree=0` CANNOT AND DOES NOT MOVE THIS NUMBER.")
    health_ok, health = run_health(len(gc.GRAPHS))
    print(health)
    print(f"per-graph SUM        : {per_graph_sum}   <- NOT the figure; it counts an op once "
          f"per graph that has it")
    print(f"NOT reached ({len(missing)}): {' '.join(missing)}")

    if args.write:
        print()
        print("<!-- CORPUS.md FIGURE BLOCK — regenerate with checks/corpus-figure.py -->")
        print(f"- **{len(union)} of {len(names)} ops** reached, by set UNION over "
              f"**{len(gc.GRAPHS)} graphs** ({built} built, {len(broken)} failed)")
        print(f"- the per-graph SUM is **{per_graph_sum}** and is **not** this figure")
        print(f"- not reached: {' '.join(missing)}")

    # A figure that cannot be reproduced is not a measurement. Non-zero exit says so.
    # THE EXIT CODE REFUSES ON THE RUN, NOT ONLY ON THE DECLARATION. A green exit over a failed
    # run is how `graphs built 22 / FAILED 0` was printed beside `graphs-agree=0` for a whole
    # session. **AN INSTRUMENT THAT CANNOT SEE A TOTAL FAILURE IN ITS OWN INPUT IS A FIGURE.**
    # `dev_ok` is ANDed in, not substituted: a run health failure is still a run health failure,
    # and ORing would let a healthy-looking run excuse a floating device (or the reverse).
    # THE REFUSAL IS ON `health_ok`, NOT ON THE ABSENCE OF THE WORD "FAILED": a missing summary
    # returns a line with neither, and the old check let it exit 0 -- a check that measured
    # nothing reporting a pass, which is the `DEAD`-is-not-a-zero doctrine.
    return 0 if dev_ok and built == len(gc.GRAPHS) and health_ok else 1


if __name__ == "__main__":
    sys.exit(main())