#!/usr/bin/env python3
"""gates/bind-plant.py -- THE PLANT THAT MOVES THE SUBJECT, AND ITS UNBROKEN CONTROL.

A census that has never been attacked is a printer. This file attacks `gates/pincensus-gate.py`
by MOVING THE SUBJECT of a pin and asking whether the census notices -- and then by moving it
BACK and asking whether the census goes green again.

WHY MOVING THE SUBJECT IS THE RIGHT ATTACK, AND IT IS THE ONE THE PIN EXISTS FOR. The subject
is the file a pin is about, and the pin is the literal in the source. A census that re-derived
the pin from its subject would compare `sha256(x)` with `sha256(x)`: A TAUTOLOGY THAT CANNOT
FAIL, WHICH IS WORSE THAN NO INSTRUMENT. This tree has been bitten by exactly that. So the
plant does the one thing a tautology cannot survive -- it moves one side and leaves the other
alone -- and asserts that the census's verdict CHANGED.

**THE PIN DOES NOT MOVE IN THE FIRST PLANT, AND THAT IS THE POINT.** The planted copy carries
the SAME pinned digest as the control, and only the SUBJECT's bytes differ. So a MISMATCH
cannot be explained by "the pin changed": it is the stale-pin condition the pin exists to
notice. The plant asserts that the two sides carry the same `value` and DIFFERENT `currency`,
which is the opposite of the shape that made a prior plant vacuous.

THE CONTROL IS STRICTER THAN "THE PLANT FIRED". The control is a byte-for-byte copy of the
subject and the pin file, and it must reproduce the verdict the real tree gives -- CURRENT for
both content pins, and the run-artifact verdict for the row whose subject is untracked by
design. A comparator that says MISMATCH for everything passes a bare plant and fails this one.

THE REAL TREE IS NEVER WRITTEN. Every mutation is applied to a copy inside a scratch
directory, and the copies are made fresh from the live tree for each step, so a step cannot
inherit the previous step's mutation by accident.

THE FALSIFICATION CLAUSE, WHICH IS THE POINT OF THE FILE: if `pincensus-gate.currency` stops
recomputing the subject's digest -- if it reports the PINNED string back, or if a subject goes
missing and it degrades to "no measurement" instead of MISMATCH -- then the control still reads
CURRENT, the plant reads something else or nothing at all, and the run exits FAIL. There is no
arrangement of this code in which the plant passes by not looking.
"""
import argparse
import importlib.util
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

PASS, FAIL, REFUSED, DEAD = 0, 1, 3, 5

# THE FILES THE PLANT NEEDS, AND WHY EACH ONE IS HERE. The pin file carries the pin AND the
# subject declaration; the subject file carries the bytes the pin is about.
PIN_FILE = "checks/e2e.py"
SUBJECT_FILE = "checks/e2e.sh"
ORACLE_SUBJECT_FILE = ".agents/slop/e2epy/oracle-e2e.sh"
RUN_ARTIFACT_FILE = "checks/differ.py"

# THE ROWS, AND HOW EACH ONE IS EXPECTED TO BEHAVE. `currency` is the EXPECTED verdict of the
# control; a row the census does not produce at all is REFUSED, never a pass.
ROWS = (
    {"file": PIN_FILE, "what": "BODY_SHA", "subject": SUBJECT_FILE, "currency": "CURRENT"},
    {"file": PIN_FILE, "what": "ORACLE_SHA", "subject": ORACLE_SUBJECT_FILE, "currency": "CURRENT"},
    {"file": RUN_ARTIFACT_FILE, "what": "REPRO_PINS", "subject": None,
     "currency": "SUBJECT-IN-GITIGNORED-RUNS"},
)


def load_gate():
    spec = importlib.util.spec_from_file_location(
        "pincensus_gate", os.path.join(HERE, "pincensus-gate.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def rows_by(rows, what):
    """-> the rows of the census for ONE pin name. A name is stable where a line number is
    not: `checks/differ.py` grows, and a plant that names a line number measures the tree's
    edit history instead of its subject."""
    return [r for r in rows if r["what"] == what]


def one(rows, what):
    got = rows_by(rows, what)
    if len(got) != 1:
        return None
    return got[0]


def copy_in(src_root, rel, dest_root):
    dst = os.path.join(dest_root, rel)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copy2(os.path.join(src_root, rel), dst)
    return dst


def build(src_root, dest_root):
    """-> a scratch root holding a copy of every file the plant needs."""
    for rel in (PIN_FILE, SUBJECT_FILE, ORACLE_SUBJECT_FILE, RUN_ARTIFACT_FILE):
        copy_in(src_root, rel, dest_root)


def census(gate, scratch, git_root):
    rows, _ = gate.census(scratch, git_root, scratch=True)
    return rows


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
    ap.add_argument("--root", default=ROOT,
                    help="the tree the copies are made from. Explicit because a copy of THIS "
                         "FILE placed elsewhere computes its own ROOT from __file__ and would "
                         "plant into the wrong directory.")
    args = ap.parse_args()
    root = args.root
    gate = load_gate()

    base = tempfile.mkdtemp(prefix="bind-plant-")
    failures = []
    try:
        # ---------------------------------------------------------------- THE CONTROL
        control_dir = os.path.join(base, "control")
        os.makedirs(control_dir)
        build(root, control_dir)
        control_rows = census(gate, control_dir, root)
        for spec in ROWS:
            row = one(control_rows, spec["what"])
            if row is None:
                print(f"bind-plant: REFUSED -- the census produced no row for {spec['what']}, "
                      f"so there is no control to break.", file=sys.stderr)
                return REFUSED
            if row["currency"] != spec["currency"]:
                print(f"bind-plant: FAIL -- THE CONTROL IS NOT UNBROKEN: {spec['what']} reads "
                      f"{row['currency']} where the tree reads {spec['currency']}.",
                      file=sys.stderr)
                return FAIL
            print(f"  CONTROL {spec['what']:12} {row['currency']}")
            print(f"          {row['detail'][:120]}")

        # ------------------------------------------- PLANT 1: MOVE THE SUBJECT, PIN UNMOVED
        moved_dir = os.path.join(base, "moved-subject")
        os.makedirs(moved_dir)
        build(root, moved_dir)
        for spec in ROWS:
            if not spec["subject"]:
                continue
            path = os.path.join(moved_dir, spec["subject"])
            with open(path, "ab") as fh:
                fh.write(b"\n# MOVED BY THE PLANT\n")
        moved_rows = census(gate, moved_dir, root)
        for spec in ROWS:
            if not spec["subject"]:
                continue
            c = one(control_rows, spec["what"])
            p = one(moved_rows, spec["what"])
            if p is None:
                failures.append(f"{spec['what']}: the planted census produced no row")
                continue
            if c["value"] != p["value"]:
                failures.append(f"{spec['what']}: the PIN moved too ({c['value'][:16]} vs "
                                f"{p['value'][:16]}), so this is not the stale-pin condition")
                continue
            if c["currency"] == p["currency"]:
                failures.append(f"{spec['what']}: moving the subject did not change the verdict "
                                f"({p['currency']}) -- the comparison is VACUOUS")
                continue
            if p["currency"] != "MISMATCH":
                failures.append(f"{spec['what']}: moving the subject read {p['currency']} and not "
                                f"MISMATCH -- it degraded instead of comparing")
                continue
            print(f"  PLANT  {spec['what']:12} {p['currency']}  (subject moved, pin unmoved)")
            print(f"          {p['detail'][:120]}")

        # --------------------------------------------- PLANT 2: MOVE IT BACK, IT GOES GREEN
        back_dir = os.path.join(base, "moved-back")
        os.makedirs(back_dir)
        build(root, back_dir)
        back_rows = census(gate, back_dir, root)
        for spec in ROWS:
            if not spec["subject"]:
                continue
            c = one(control_rows, spec["what"])
            b = one(back_rows, spec["what"])
            if b is None or b["currency"] != c["currency"]:
                failures.append(f"{spec['what']}: moving the subject BACK did not restore "
                                f"{c['currency']} (read {b and b['currency']})")
                continue
            print(f"  BACK   {spec['what']:12} {b['currency']}  (subject moved back)")

        # ------------------------------- PLANT 3: THE RUN-ARTIFACT ROW IS BOUND TO ITS DECLARATION
        decl_dir = os.path.join(base, "decl-moved")
        os.makedirs(decl_dir)
        build(root, decl_dir)
        path = os.path.join(decl_dir, RUN_ARTIFACT_FILE)
        with open(path, encoding="utf-8") as fh:
            body = fh.read()
        moved = body.replace('REPRO_ARTIFACT = "D0-repro.txt"',
                              'REPRO_ARTIFACT = "D0-repro-moved.txt"')
        if moved == body:
            print("bind-plant: DEAD -- the declaration did not move: `REPRO_ARTIFACT` is not "
                  "where this file expects it. A plant that cannot be applied proves nothing.",
                  file=sys.stderr)
            return DEAD
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(moved)
        decl_rows = census(gate, decl_dir, root)
        c = one(control_rows, "REPRO_PINS")
        p = one(decl_rows, "REPRO_PINS")
        if p is None:
            failures.append("REPRO_PINS: the planted census produced no row")
        elif p["detail"] == c["detail"]:
            failures.append("REPRO_PINS: moving the declaration did not change the row -- the "
                            "row is not bound to the declaration")
        elif "D0-repro-moved.txt" not in p["detail"]:
            failures.append(f"REPRO_PINS: the row does not name the moved declaration: "
                            f"{p['detail'][:120]}")
        else:
            print(f"  PLANT  {'REPRO_PINS':12} {p['currency']}  (declaration moved)")
            print(f"          {p['detail'][:120]}")

        # ------------------------ PLANT 4: REMOVE THE DECLARATION AND THE VERDICT MUST CHANGE
        gone_dir = os.path.join(base, "decl-gone")
        os.makedirs(gone_dir)
        build(root, gone_dir)
        path = os.path.join(gone_dir, RUN_ARTIFACT_FILE)
        with open(path, encoding="utf-8") as fh:
            body = fh.read()
        without = body.replace('REPRO_ARTIFACT = "D0-repro.txt"', 'REPRO_ARTIFACT = ""')
        if without == body:
            print("bind-plant: DEAD -- the declaration could not be removed.", file=sys.stderr)
            return DEAD
        with open(path, "w", encoding="utf-8") as fh:
            fh.write(without)
        gone_rows = census(gate, gone_dir, root)
        p = one(gone_rows, "REPRO_PINS")
        if p is None:
            failures.append("REPRO_PINS: removing the declaration produced no row")
        elif p["currency"] == c["currency"]:
            failures.append("REPRO_PINS: removing the declaration did not change the verdict -- "
                            "the verdict does not depend on the declaration")
        else:
            print(f"  PLANT  {'REPRO_PINS':12} {p['currency']}  (declaration removed)")
            print(f"          {p['detail'][:120]}")

        if failures:
            for f in failures:
                print(f"bind-plant: FAIL -- {f}", file=sys.stderr)
            return FAIL
        print("  the control is unbroken, the subject's move is noticed, and moving it back "
              "is green again")
        return PASS
    finally:
        shutil.rmtree(base, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
