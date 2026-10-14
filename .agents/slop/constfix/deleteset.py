#!/usr/bin/env python3
"""What would the CORRECTED resolver delete that the CURRENT one does not? THE DELIVERABLE.

    usage: .venv/bin/python .agents/slop/constfix/deleteset.py [--tree ROOT] [--window 60]

THE QUESTION. `checks/sweep.py:self_output_dirs()` feeds `house_excluded`, which removes a
directory from the citation corpus AND from the walk. Removing evidence makes rows uncited,
and an uncited row is one `DELETE` away. **SO EVERY ADDITIONAL DIRECTORY THIS FINDER NAMES IS
A DIRECTORY THE SWEEP IS ENTITLED TO DESTROY, AND THAT IS WHY THE FIX WAS DEFERRED THREE
TIMES.** This script computes the delta and prints every path in it. It deletes nothing.

**ONE FROZEN POPULATION AND ONE FROZEN CLOCK, OR THE DELTA IS A CONFOUND.** `--plan`'s own
header says it: "DELETING 366 / 44 / 0 at 0, 60 and 1440 minutes" on one unedited tree. Two
sequential `--plan` runs would confound the resolver change with the clock and with five units
writing into `.slop` while it runs. So the row population, the liveness overlay, `tracked`,
`copies` and `declared` are each computed ONCE and handed to both classifiers; the ONLY thing
that differs between the two passes is `self_output_dirs`. **A DELTA MEASURED ACROSS TWO RUNS
IS A DELTA MEASURED ACROSS TWO MOMENTS.**
"""
from __future__ import annotations

import argparse
import collections
import importlib.util
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import writecensus as wc  # noqa: E402


def load(path: str):
    spec = importlib.util.spec_from_file_location("sweep", path)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    return m


def corrected(root: str) -> tuple[str, ...]:
    """The corrected resolver's answer about WRITES, ungated by the read census.

    `checks/sweep.py` ships `_slop_write_targets`, which is a directory walk over the instrument
    ASTs and nothing else. There is no literal anywhere in this file or in `sweep.py` that
    names one of the directories, and `--prove` checks that by AST rather than by assertion."""
    return tuple(sorted(wc.gate()._slop_write_targets(root)))


def gated(root: str) -> tuple[str, ...]:
    """What `checks/sweep.py` ACTUALLY excludes after the read refusal lands."""
    return wc.gate().self_output_dirs(root)


def classify_all(sw, f, rows, live, live_dirs) -> dict[str, str]:
    """`sweep.classify` with the walk and the CLOCK frozen, so the two passes differ only in
    the resolver. Written out rather than called because `classify` re-reads mtimes."""
    out = {}
    for rel, _sz in rows:
        v = sw.verdict_for(rel, f.mentioned, f, live_dirs)
        if rel in live and v not in ("PROTECTED", "LIVE-UNIT"):
            v = "LIVE"
        out[rel] = v
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    here = os.path.dirname(os.path.abspath(__file__))
    ap.add_argument("--tree", default=os.path.dirname(os.path.dirname(os.path.dirname(here))))
    ap.add_argument("--window", type=int, default=60, help="liveness window, applied ONCE to both")
    ap.add_argument("--prove", action="store_true",
                    help="prove the corrected answer is derived and not written down")
    args = ap.parse_args()
    root = args.tree

    sw = load(os.path.join(root, "checks/sweep.py"))
    original = wc.previous_resolver_dirs(root)
    fixed = corrected(root)
    refused = wc.gate().self_output_conflicts(root)
    gate_answer = gated(root)

    if args.prove:
        print("PROVE: the three discovered directories are not written down anywhere.")
        print("      A first `--prove` printed its own contradiction -- it reported `residue`")
        print("      as a literal in `checks/sweep.py` and then claimed none was there. Both")
        print("      halves were right: `checks/sweep.py:621` and `:798` are")
        print("      `spec_from_file_location(\"residue\", .../checks/residue.py)`, a MODULE")
        print("      NAME, and a bare first component is not a PATH. So the check is by SHAPE --")
        print("      a directory claim is a literal of exactly `.agents/slop/<component>`.\n")
        import ast as _ast
        found = {d.rsplit("/", 1)[1] for d in fixed}

        def literals(path):
            return [(n.lineno, n.value) for n in _ast.walk(_ast.parse(open(path).read()))
                    if isinstance(n, _ast.Constant) and isinstance(n.value, str)]

        for label, path in (("checks/sweep.py", os.path.join(root, "checks/sweep.py")),
                            (".agents/slop/constfix/deleteset.py", os.path.abspath(__file__)),
                            (".agents/slop/constfix/writecensus.py",
                             os.path.join(here, "writecensus.py"))):
            claims = [(ln, v) for ln, v in literals(path)
                      if v.startswith(wc.SLOP_PREFIX + "/")
                      and v[len(wc.SLOP_PREFIX) + 1:]                     # a non-empty tail
                      and "/" not in v[len(wc.SLOP_PREFIX) + 1:]
                      and "." not in v[len(wc.SLOP_PREFIX) + 1:]]
            collisions = [(ln, v) for ln, v in literals(path) if v in found]
            print(f"  {label}")
            print(f"    DIRECTORY-SHAPED exclusion literals: "
                  f"{[f'{v!r}@{ln}' for ln, v in claims] or 'NONE'}")
            print(f"    bare first-component literals (module NAMES, not paths): "
                  f"{[f'{v!r}@{ln}' for ln, v in collisions] or 'NONE'}")
        print(f"\n  the resolver named: {sorted(found)}")
        print(f"  `SELF` = {wc.gate().SELF!r} is a DECLARED literal and is NOT one of them; "
              f"`checks/sweep.py:153` says why it is written down rather than discovered.")
        print(f"  census input is `_instrument_files()` = os.walk over checks/ + gates/: "
              f"{len(sw._instrument_files(root))} files")
        print(f"  and a glob would find the same number today "
              f"({len(sw._instrument_files(root))}), so the walk is insurance, not a fix.")
        return 0

    # ---- FROZEN ONCE, SHARED BY EVERY PASS. ----
    rows = sw.walk_residue(root)
    live = sw.live_set(args.window, root)
    live_dirs = sw.live_units(args.window, root)
    print(f"# frozen population: {len(rows)} rows under {sw.RESIDUE_ROOTS}; "
          f"liveness window {args.window}m -> {len(live)} files, {len(live_dirs)} unit dirs")
    print(f"# self_output_dirs, PREVIOUS  : {original}")
    print(f"# corrected resolver, WRITES  : {fixed}")
    print(f"# corrected resolver, REFUSED (written AND read): {refused}")
    print(f"# self_output_dirs, AS SHIPPED (writes - reads)  : {gate_answer}")

    # ---- THREE PASSES, ONE FROZEN POPULATION, ONE FROZEN CLOCK. ----
    # The resolver alone, and the resolver as shipped, are DIFFERENT QUESTIONS and the whole
    # point of this script is to price both. Pricing only the shipped one would hide the two
    # destructions the read refusal is currently preventing; pricing only the raw one would
    # report a destruction that does not land.
    passes = {}
    for name, answer in (("PREVIOUS", original), ("WRITES-ONLY", fixed), ("AS SHIPPED", gate_answer)):
        sw.self_output_dirs = lambda r=root, a=answer: a        # explicit, not the default
        passes[name] = classify_all(sw, sw.Facts(root), rows, live, live_dirs)
        print(f"# pass {name:12s} excluded {answer}")
    sw.self_output_dirs = lambda r=root: gate_answer

    v_old = passes["PREVIOUS"]
    v_new = passes["WRITES-ONLY"]
    v_ship = passes["AS SHIPPED"]
    f_old = sw.facts(root)

    print(f"# mentioned filenames: {len(f_old.mentioned)} (one corpus, printed once)")
    print(f"\n# {'bucket':16s}{'previous':>10s}{'writes-only':>13s}{'as shipped':>12s}{'delta':>8s}")
    co = collections.Counter(sw.bucket(v) for v in v_old.values())
    cn = collections.Counter(sw.bucket(v) for v in v_new.values())
    cs = collections.Counter(sw.bucket(v) for v in v_ship.values())
    for b in sorted(set(co) | set(cn) | set(cs)):
        print(f"# {b:16s}{co[b]:10d}{cn[b]:13d}{cs[b]:12d}{cs[b] - co[b]:+8d}")
    print(f"# {'TOTAL':16s}{sum(co.values()):10d}{sum(cn.values()):13d}{sum(cs.values()):12d}"
          f"{sum(cs.values()) - sum(co.values()):+8d}")

    for label, verdicts in (("WRITES-ONLY (resolver alone, no read refusal)", v_new),
                            ("AS SHIPPED (resolver minus the read refusal)", v_ship)):
        newly = sorted(r for r in verdicts if verdicts[r] == "DELETE" and v_old.get(r) != "DELETE")
        saved = sorted(r for r in verdicts if v_old.get(r) == "DELETE" and verdicts[r] != "DELETE")
        print(f"\n# {label}")
        print(f"#   NEWLY DELETE: {len(newly)}")
        for r in newly:
            print(f"#     {r:66s} was {v_old.get(r)}")
        print(f"#   NO LONGER DELETE: {len(saved)}")
        for r in saved[:30]:
            print(f"#     {r:66s} now {verdicts[r]}")
        if len(saved) > 30:
            print(f"#     ... and {len(saved) - 30} more")
    return 0



if __name__ == "__main__":
    sys.exit(main())
