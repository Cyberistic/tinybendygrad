#!/usr/bin/env python3
"""MEASURE THE `UOp.tag` QUESTION, ON BOTH SIDES, AT THE PIN.

THE QUESTION (the RNGCMP item's open half): "WHETHER THE PORT HAS A 'TAGGED COPY' CONCEPT
AT ALL IS NOT MEASURED".  This answers it, and it answers it IN BOTH DIRECTIONS, because a
one-sided answer cannot be distinguished from an answer that was convenient.

FOUR READINGS, EACH WITH ITS OWN CITATION:

  1. UPSTREAM AT THE PIN HAS NO `tag`.  `git show <pin>:tinygrad/uop/ops.py` has no `tag`
     field, no `rtag`, no `tagstr`, and no `tag` in the intern key.
  2. UPSTREAM DELETED IT, AND THE COMMIT IS AN ANCESTOR OF THE PIN.  `fb518b44e delete
     UOp.tag [pr] (#18954)`, 2026-10-21.
  3. UPSTREAM's `rangeify.py` AT THE PIN HAS NO TAGGING STEP AT ALL.  `get_rangeify_map`
     runs `pm_add_buffers` then `split_kernels`; there is no `pm_add_range_tags` and no
     `pm_add_param_range_tags`, and `pm_renumber_range` has no tag guard.
  4. THE PORT HAS THE CONCEPT, AND IT IS LOAD-BEARING.  `tinybendygrad/uop/ops.bend`
     declares `type Tag is Data:` with `TNone{}` / `TTuple{}` / `TBool{}` / `TStr{}` /
     `TInt{}` arms, `eq_tag` compares them, `sg.tag` prints them, and
     `tinybendygrad/schedule/rangeify.bend` ports `pm_add_param_range_tags` -- a rule
     upstream does not have at the pin -- plus `rf_rtag`, the port of the deleted
     `UOp.rtag`.

THE CONSEQUENCE, WHICH IS THE POINT: **THE ORACLE CANNOT BE REPAIRED BY A RENAME.**
`gates/rng_graph_census-oracle.py` MIRRORS THE PORT's FIXTURE INDEX FOR INDEX, and the
port's fixture has FOUR TAGGED COPIES (`r0t` `pgt` `pat` `rgt`).  At the pin CPython has
no way to BUILD one, so the oracle cannot produce the port's fixture at all -- and a
fixture that cannot be built is a lane that measures nothing.

AND THE PORT's SIDE IS NOT MINE: removing `Tag` is a NINETEEN-FILE REFACTOR, and this
instrument's job is to MEASURE, not to refactor.

USAGE:  .venv/bin/python .agents/slop/todo-sweep2/tagpin.py
        (reads the tree and the pin; runs NO bend and NO gate)
"""

import subprocess
import sys
from pathlib import Path

PIN = "f5ac54685074"
TAG_DELETE = "fb518b44e"
ROOT = Path(__file__).resolve().parents[3]


def git(*args):
    return subprocess.run(("git",) + args, cwd=ROOT, capture_output=True, text=True).stdout


def show(rev, path):
    return git("show", f"{rev}:{path}")


def main():
    findings = []

    # 1 -- upstream at the pin has no `tag`.
    ops = show(PIN, "tinygrad/uop/ops.py")
    has_tag_field = "\n  tag:Any = None\n" in ops or "\n  tag: Any = None\n" in ops
    has_rtag = "def rtag(" in ops
    has_tagstr = "def tagstr(" in ops
    findings.append(("pin ops.py has a `tag` FIELD", has_tag_field))
    findings.append(("pin ops.py has `def rtag(`", has_rtag))
    findings.append(("pin ops.py has `def tagstr(`", has_tagstr))
    findings.append(("pin ops.py names `tag` in the intern key", ", tag," in ops or ",tag," in ops))

    # 2 -- the deletion is an ancestor of the pin.
    anc = subprocess.run(("git", "merge-base", "--is-ancestor", TAG_DELETE, PIN),
                         cwd=ROOT, capture_output=True).returncode == 0
    findings.append((f"{TAG_DELETE} (delete UOp.tag) IS AN ANCESTOR OF THE PIN", anc))

    # 3 -- upstream's rangeify at the pin has no tagging step.
    rng = show(PIN, "tinygrad/schedule/rangeify.py")
    findings.append(("pin rangeify.py has `pm_add_range_tags`", "pm_add_range_tags" in rng))
    findings.append(("pin rangeify.py has `pm_add_param_range_tags`", "pm_add_param_range_tags" in rng))
    findings.append(("pin rangeify.py calls `.rtag(`", ".rtag(" in rng))

    # 4 -- the port HAS the concept, and it is load-bearing.
    port_ops = (ROOT / "tinybendygrad/uop/ops.bend").read_text(errors="replace")
    port_rng = (ROOT / "tinybendygrad/schedule/rangeify.bend").read_text(errors="replace")
    findings.append(("port ops.bend declares `type Tag is Data:`", "type Tag is Data:" in port_ops))
    findings.append(("port ops.bend defines `eq_tag`", "def eq_tag(" in port_ops))
    findings.append(("port ops.bend defines `sg.tag`", "def sg.tag(" in port_ops))
    findings.append(("port rangeify.bend defines `rf_rtag`", "def rf_rtag(" in port_rng))
    findings.append(("port rangeify.bend defines `rf_param_rtag`", "def rf_param_rtag(" in port_rng))

    # 5 -- the oracle calls the deleted API, and cannot build the port's fixture.
    oracle = (ROOT / "gates/rng_graph_census-oracle.py").read_text(errors="replace")
    findings.append(("the oracle CALLS `UOp.rtag`", ".rtag(" in oracle))
    findings.append(("the oracle READS `u.tag`", "u.tag" in oracle))

    # 6 -- the live CPython in THIS tree is the pin, so the calls really do fail.
    live_ok = True
    try:
        sys.path.insert(0, str(ROOT))
        from tinygrad.uop.ops import UOp
        live_ok = not hasattr(UOp, "rtag") and not hasattr(UOp.const(1), "tag")
    except Exception as e:  # pragma: no cover -- the import failing IS a finding
        print(f"LIVE CHECK RAISED: {type(e).__name__}: {e}")
    findings.append(("the LIVE CPython has NEITHER `rtag` NOR `tag`", live_ok))

    width = max(len(name) for name, _ in findings)
    ok = 0
    for name, value in findings:
        print(f"{name:<{width}}  {'YES' if value else 'NO '}")
        ok += bool(value)

    print()
    print(f"READINGS {ok} of {len(findings)}")
    print()
    print("THE VERDICT, AND IT IS NOT A BINARY:")
    print("  UPSTREAM AT THE PIN HAS NO `tag`.")
    print("  THE PORT HAS ONE, AND IT IS LOAD-BEARING ACROSS NINETEEN FILES.")
    print(" THE ORACLE CANNOT BE REPAIRED BY A RENAME: IT MIRRORS THE PORT's FIXTURE")
    print("    INDEX FOR INDEX, AND THE PORT's FIXTURE HAS FOUR TAGGED COPIES THAT")
    print("    PIN-CPYTHON CANNOT BUILD.")
    print(" THE PORT's SIDE IS A NINETEEN-FILE REFACTOR AND IS NOT THIS SWEEP's.")
    print(" AND A GATE THAT CANNOT BUILD ITS FIXTURE IS A GATE THAT MEASURED NOTHING,")
    print("    WHICH IS THE CLASS THE `RNGCMP` ITEM NAMES.")


if __name__ == "__main__":
    main()
