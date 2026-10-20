#!/usr/bin/env python3
"""gates/pincensus-plant.py -- THE PLANT THAT CAN FAIL, AND ITS UNBROKEN CONTROL.

A census that has never been attacked is a printer. This file attacks `gates/pincensus-gate.py`
with a pin value that is KNOWN to be wrong and requires the census to say so.

TWO PRIOR PLANTS IN THIS TREE FAILED IN WAYS THIS ONE IS SHAPED AGAINST, so both are named:

  * "the lane emitted nothing while the check scored it as a successful plant." A plant whose
    subject disappears is not a pass, it is a DEAD lane. So the target is DISCOVERED from the
    census's own CURRENT rows at run time, never named here, and if no such row exists this
    file REFUSES instead of inventing one.
  * "the first negative was vacuous -- flattening both sides to one constant." A control and
    a plant that both say the same constant compare equal whatever the comparator does. So
    the two sides carry DIFFERENT, explicitly compared values, and `same_value` is itself an
    assertion: if the mutation did not take, the plant FAILS.

EVERY PLANT NEEDS AN UNBROKEN CONTROL, and the control here is stricter than "the plant fired":
the CONTROL is a byte-for-byte copy of the corpus with NOTHING mutated, and it must reproduce
the live census's verdict for that exact row. A comparator that says MISMATCH for everything
passes a bare plant and fails this one.

THE MUTATION IS APPLIED TO COPIES. The real tree is opened read-only and never written; the
plant's two corpora are scratch directories holding a COPY of the one file that carries the
target pin. That is affordable only because `pincensus-pop.readers` is SCOPED TO THE DEFINING
FILE: the row's class and currency depend on that file alone, so copying it copies the verdict.
A reader test that searched the whole tree would have made this plant need a whole-tree copy.

THE FALSIFICATION CLAUSE, WHICH IS THE POINT OF THE FILE: if `pincensus-gate.currency` stops
recomputing the subject's digest -- if it reports the PINNED string back, or if a subject goes
missing and it degrades to "no measurement" instead of MISMATCH -- then the control still reads
CURRENT, the plant reads something else or nothing at all, and the run exits FAIL. There is no
arrangement of this code in which the plant passes by not looking.
"""
import argparse
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

PASS, FAIL, REFUSED, DEAD = 0, 1, 3, 5


def load_gate():
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "pincensus_gate", os.path.join(HERE, "pincensus-gate.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def row_for(rows, where):
    """-> the one row at `where`, or None. `where` is file:line, which the census keys on."""
    got = [r for r in rows if r["where"] == where]
    return got[0] if len(got) == 1 else (None if not got else got[0])


def copy_one(rel, dest, root=ROOT):
    """-> a scratch root holding a COPY of `rel` at its repo-relative path. Read-only on the
    real tree: the source is opened once, for reading, and the bytes go to the scratch."""
    dst = os.path.join(dest, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(os.path.join(root, rel), "rb") as fh:
        raw = fh.read()
    with open(dst, "wb") as fh:
        fh.write(raw)
    return raw


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--root", default=ROOT,
                    help="the tree under census. Explicit because a copy of THIS FILE placed "
                         "elsewhere computes its own ROOT from __file__ and would census the "
                         "wrong directory -- which is how a sabotage check of this file came "
                         "back REFUSED for a reason that had nothing to do with the sabotage.")
    args = ap.parse_args()
    root = args.root
    gate = load_gate()
    live_rows, _ = gate.census(root, root)

    # THE TARGET IS DISCOVERED, NEVER NAMED. The first OURS-origin row whose currency the
    # census DECIDED by hashing something -- CURRENT or MISMATCH -- outside `.agents/slop/`,
    # which holds finished units' copies and whose rows are shadows of the real gates.
    target = next((r for r in live_rows
                   if r.get("origin") == "OURS" and r["currency"] in ("CURRENT", "MISMATCH")
                   and not r["where"].startswith(".agents/slop/")), None)
    if target is None:
        print("pincensus-plant: REFUSED -- no decidable OURS-origin pin to plant into.\n"
              "  The census decided nothing by hashing, so there is no control to break.",
              file=sys.stderr)
        return REFUSED

    where = target["where"]
    rel = where.rsplit(":", 1)[0]
    print(f"pincensus-plant: target DISCOVERED at {where} ({target['what']}), "
          f"live currency {target['currency']}")
    print(f"  detail: {target['detail']}")

    base = tempfile.mkdtemp(prefix="pincensus-plant-")
    try:
        control = os.path.join(base, "control")
        planted = os.path.join(base, "planted")
        os.makedirs(control)
        os.makedirs(planted)
        original = copy_one(rel, control, root)
        copy_one(rel, planted, root)

        # THE MUTATION: the same length, a different digest, applied to the COPY ONLY. The
        # subject is hashed from the REAL tree, so the planted pin is now wrong about a file
        # that has not changed -- which is exactly what a stale pin looks like.
        old_hex, new_hex = target["value"], ("0" * len(target["value"]))
        mutated = original.replace(old_hex.encode(), new_hex.encode())
        if mutated == original:
            print(f"pincensus-plant: DEAD -- the mutation did not take: {old_hex} is not in "
                  f"{rel}. A plant that cannot be applied proves nothing.", file=sys.stderr)
            return DEAD
        with open(os.path.join(planted, rel), "wb") as fh:
            fh.write(mutated)

        control_rows, _ = gate.census(control, root, scratch=True)
        plant_rows, _ = gate.census(planted, root, scratch=True)
        c, p = row_for(control_rows, where), row_for(plant_rows, where)

        if c is None or p is None:
            print("pincensus-plant: FAIL -- a side produced no row for the target, so the "
                  "plant compared nothing.", file=sys.stderr)
            return FAIL
        if c["value"] == p["value"]:
            print(f"pincensus-plant: FAIL -- VACUOUS: both sides carry {c['value']}. Two "
                  "copies of one constant compare equal whatever the comparator does.",
                  file=sys.stderr)
            return FAIL
        if c["currency"] != target["currency"]:
            print(f"pincensus-plant: FAIL -- THE CONTROL IS NOT UNBROKEN: an unmutated copy "
                  f"read {c['currency']} where the live tree reads {target['currency']}.",
                  file=sys.stderr)
            return FAIL

        fired = p["currency"] == "MISMATCH" and c["currency"] != "MISMATCH"
        print(f"  CONTROL (unmutated copy) : {c['value'][:16]}... -> {c['currency']}")
        print(f"  PLANT   (mutated copy)   : {p['value'][:16]}... -> {p['currency']}")
        print("  non-vacuous              : the two values differ, asserted above")
        print(f"  THE PLANT {'FIRED' if fired else 'DID NOT FIRE'}")
        if not fired:
            print("pincensus-plant: FAIL -- the census did not report a planted-stale digest "
                  "as MISMATCH. Either it is not re-deriving, or it degrades to NO-MEASUREMENT, "
                  "and both are the failure this plant exists to catch.", file=sys.stderr)
            return FAIL
        return PASS
    finally:
        shutil.rmtree(base, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())