#!/usr/bin/env python3
"""dtype-pri-mutate.py -- the mutation table for `void`'s priority and for
CustomFunction's (dtype, shape).

RULE: the harness diffs WHOLE `name=value` LINES, never row names. A name-comparing
harness reported 0 for all 30 mutations in one unit and 0 for all 68 in another.

RULE 73: a mutation that does not typecheck is NOT a blind spot. It is reported as
`TYPECHECK FAIL` and skipped -- the compiler already refused it, so nothing could
have observed it.

The scratch copy lives BESIDE the file it is a copy of, not under $TMPDIR: a scratch
copy elsewhere cannot resolve `./ops.bend` and produces phantom blind spots (measured
once, 22 of them, in another unit).
"""
import os
import re
import shutil
import subprocess
import sys
import patch_not_apply as PNA

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SLOP = os.path.join(REPO, ".agents", "slop")
BASE = ".agents/slop/fold-rows-after.txt"

# (label, file-to-patch, old, new, expect-a-row-to-move)
MUTATIONS = [
    # --- Defect 2: the CUSTOM_FUNCTION arm -------------------------------------
    ("M1 revert the arm to `late()` (the bug as it shipped)",
     "tinybendygrad/uop/fold.bend",
     "case O.OpsCUSTOM_FUNCTION{}: cfun_ds(arg)",
     "case O.OpsCUSTOM_FUNCTION{}: late()", ["cfun_u64"]),
    ("M2 void CustomFunction gets a shape () instead of None",
     "tinybendygrad/uop/fold.bend",
     "case S.Dt{_, _, S.CVoid{}, _}: late()",
     "case _: Some{dt_of_nil(dt)}", ["cfun_void"]),
    ("M3 every CustomFunction is void (ignore arg.dtype entirely)",
     "tinybendygrad/uop/fold.bend",
     "case O.ACustom{cf}: cfun_ds.shape(O.CustomFunction.dtype(cf))",
     "case O.ACustom{cf}: cfun_ds.shape(S.void())", ["cfun_u64"]),
    ("M4 every CustomFunction has shape () (never the None arm)",
     "tinybendygrad/uop/fold.bend",
     "case S.Dt{_, _, S.CVoid{}, _}: late()",
     "case _: Some{dt_of_nil(dt)}\n    case S.Dt{_, 0, S.CVoid{}, _}: Some{dt_of_nil(dt)}",
     ["cfun_void"]),

    # --- the commutativity fix --------------------------------------------------
    ("M5 least_upper tests only the LEFT mask again",
     "tinybendygrad/uop/fold.bend",
     "Bool.or(U32.is_zero(ma), U32.is_zero(mb))",
     "U32.is_zero(ma)", ["promo_void_right"]),
    ("M6 least_upper tests only the RIGHT mask",
     "tinybendygrad/uop/fold.bend",
     "Bool.or(U32.is_zero(ma), U32.is_zero(mb))",
     "U32.is_zero(mb)", ["promo_void_left"]),
    ("M7 the AND drops a zero mask's partner entirely",
     "tinybendygrad/uop/fold.bend",
     "least_upper.pick(Bool.or(U32.is_zero(ma), U32.is_zero(mb)), U32.and(ma, mb))",
     "least_upper.pick(Bool.or(U32.is_zero(ma), U32.is_zero(mb)), ma)", ["meet_and"]),

    # --- `bnd_lim`, the ONLY site that arms on `Dt{0, 0, S.CVoid{}}` -------------
    ("M8 bnd_lim's void arm falls to bnd_flt (+-inf)",
     "tinybendygrad/uop/fold.bend",
     "case S.Dt{0, 0, S.CVoid{}, _}: bnd_bool(top)",
     "case S.Dt{0, 0, S.CVoid{}, _}: bnd_flt(top)", ["bnd_void_is_bool"]),
    ("M9 bnd_lim's void arm's PRIORITY LITERAL moves 0 -> 1 (the silent class)",
     "tinybendygrad/uop/fold.bend",
     "case S.Dt{0, 0, S.CVoid{}, _}: bnd_bool(top)",
     "case S.Dt{1, 0, S.CVoid{}, _}: bnd_bool(top)", ["bnd_void_is_bool"]),

    # --- THE DATASET. THE QUESTION WAS: is void's priority load-bearing? ---------
    ("M10 `void`'s STORED PRIORITY 0 -> 16, in LAWS/spec.bend",
     "tinybendygrad/LAWS/spec.bend",
     'def void() -> Dt: Dt{0, 0, CVoid{}, "void"}',
     'def void() -> Dt: Dt{16, 0, CVoid{}, "void"}', ["pri_three_way", "bnd_void_is_bool"]),
    ("M11 `void`'s stored priority 0 -> 1, adjacent to bool/weakint",
     "tinybendygrad/LAWS/spec.bend",
     'def void() -> Dt: Dt{0, 0, CVoid{}, "void"}',
     'def void() -> Dt: Dt{1, 0, CVoid{}, "void"}', ["pri_three_way", "bnd_void_is_bool"]),
    ("M12 `void` gets weakint's priority+bits (a REAL collision of 3 fields)",
     "tinybendygrad/LAWS/spec.bend",
     'def void() -> Dt: Dt{0, 0, CVoid{}, "void"}',
     'def void() -> Dt: Dt{0, 800, CVoid{}, "void"}', ["bnd_void_is_bool"]),

    # --- promo_mask's void arm, for contrast: it is `case _`, so pri cannot move it
    ("M13 promo_mask's void mask 0 -> bool's 524287",
     "tinybendygrad/uop/fold.bend",
     "    case _: 0\n\n# the rank -> dtype half",
     "    case _: 524287\n\n# the rank -> dtype half",
     ["promo_void_left", "promo_void_right"]),
]


def rows_of(text):
    out = {}
    for line in text.splitlines():
        m = re.match(r"^([^=]+)=(.*)$", line)
        if m:
            out[m.group(1)] = m.group(2)
    return out


def run_bend(path):
    b = subprocess.run(["./bin/bend", path], cwd=REPO, capture_output=True, text=True)
    return b.returncode, b.stdout + b.stderr


def main():
    base_rc, base_txt = run_bend(os.path.join(REPO, "tinybendygrad/uop/fold.bend"))
    if base_rc != 0:
        print("BASE DOES NOT RUN:\n" + base_txt[:2000])
        return 1
    base = rows_of(base_txt)
    print("baseline rows: %d\n" % len(base))

    for label, target, old, new, expect in MUTATIONS:
        src = os.path.join(REPO, target)
        pristine = src + ".mutbase"
        shutil.copyfile(src, pristine)
        text = open(src).read()
        if old not in text:
            print("%-64s %s" % (label[:64], PNA.not_applied("pattern not found")))
            continue
        open(src, "w").write(text.replace(old, new, 1))
        rc, txt = run_bend(os.path.join(REPO, "tinybendygrad/uop/fold.bend"))
        os.replace(pristine, src)

        if rc != 0:
            first = txt.strip().splitlines()
            first = first[0] if first else ""
            detail = ""
            m = re.search(r"^\d+ \|.*", txt, re.M)
            if m:
                detail = " @ " + m.group(0).strip()
            print("%-64s TYPECHECK FAIL (rule 73: not a blind spot)%s" % (label[:64], detail))
            continue
        got = rows_of(txt)
        moved = [(k, base.get(k), got.get(k)) for k in sorted(set(base) | set(got))
                 if base.get(k) != got.get(k)]
        if not moved:
            print("%-64s *** 0 rows moved -- BLIND SPOT" % label[:64])
            continue
        names = [m[0] for m in moved]
        hit = "as expected" if (expect and set(expect) <= set(names)) else \
              ("UNEXPECTED set" if expect else "")
        print("%-64s moved %d: %s  [%s]" % (label[:64], len(moved), ", ".join(names), hit))
        for n, b, a in moved:
            print("      %-34s %s -> %s" % (n, b, a))
    print("\nbase rows still %d after every restore" % len(rows_of(run_bend(
        os.path.join(REPO, "tinybendygrad/uop/fold.bend"))[1])))
    return 0


if __name__ == "__main__":
    sys.exit(main())