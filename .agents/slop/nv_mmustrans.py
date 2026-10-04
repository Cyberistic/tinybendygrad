#!/usr/bin/env python3
"""nv_mmustrans.py -- DOES A TRANSPOSITION IN ONE OF THE SIX MMU_VER STRUCTS MOVE
ANY ROW?  Measured, not reasoned.

The census found 22 order-sensitive `Fld.of` sites inside v2_pte / v2_pde /
v2_dpd / v3_pte / v3_pde / v3_dpd, and that NONE of those six registers has an
`nv_reg_*_ranges` row -- nor any other row that prints a field's `(start, end)`.
So the question is not whether they are order-sensitive (they are: 22 of 22) but
whether anything in the gate READS the difference.  This transposes one field in
each of the six and reports the rows that moved.

A `0` here is reported as a BLIND SPOT with its reason, never as a pass, and the
baseline control runs first so that a `0` cannot be a broken substrate.

usage: python3 .agents/slop/nv_mmustrans.py
"""
import os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import staged_mut as SM

ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, "tinybendygrad/runtime/support/nv/nvdev.bend")

# One field per MMU_VER struct, chosen so the width changes under the swap:
# `wid(e,s) = e - s + 1` in U32 WRAPS, so every s != e site changes width. These
# are the sites a transposition would land on.
# Each anchor carries its `def nv.reg_*` header, because `Fld.of("aperture", 1, 2)`
# alone occurs FOUR times in this file and an anchor that is not unique would make
# the harness report a mutation it did not make.
CASES = [
    ("v2_pte", 'def nv.reg_v2_pte() -> Rgv: Rgv.of(0, 0, [Fld.of("valid", 0, 0), Fld.of("aperture", 1, 2)',
               'def nv.reg_v2_pte() -> Rgv: Rgv.of(0, 0, [Fld.of("valid", 0, 0), Fld.of("aperture", 2, 1)',
               "2-bit field -> (2,1)"),
    ("v2_pde", 'def nv.reg_v2_pde() -> Rgv: Rgv.of(0, 0, [Fld.of("is_pte", 0, 0), Fld.of("is_pde", 0, 0), Fld.of("valid", 0, 0), Fld.of("aperture", 1, 2)',
               'def nv.reg_v2_pde() -> Rgv: Rgv.of(0, 0, [Fld.of("is_pte", 0, 0), Fld.of("is_pde", 0, 0), Fld.of("valid", 0, 0), Fld.of("aperture", 2, 1)',
               "2-bit field -> (2,1)"),
    ("v2_dpd", 'def nv.reg_v2_dpd() -> Rgv: Rgv.of(0, 0, [Fld.of("is_pte", 0, 0), Fld.of("is_pde", 0, 0), Fld.of("valid", 0, 0), Fld.of("aperture_big", 1, 2)',
               'def nv.reg_v2_dpd() -> Rgv: Rgv.of(0, 0, [Fld.of("is_pte", 0, 0), Fld.of("is_pde", 0, 0), Fld.of("valid", 0, 0), Fld.of("aperture_big", 2, 1)',
               "2-bit field -> (2,1)"),
    ("v3_pte", 'def nv.reg_v3_pte() -> Rgv: Rgv.of(0, 0, [Fld.of("valid", 0, 0), Fld.of("aperture", 1, 2), Fld.of("pcf", 3, 7), Fld.of("kind", 8, 11)',
               'def nv.reg_v3_pte() -> Rgv: Rgv.of(0, 0, [Fld.of("valid", 0, 0), Fld.of("aperture", 1, 2), Fld.of("pcf", 3, 7), Fld.of("kind", 11, 8)',
               "4-bit field -> (11,8), BOOT_42's exact shape"),
    ("v3_pde", 'def nv.reg_v3_pde() -> Rgv: Rgv.of(0, 0, [Fld.of("is_pte", 0, 0), Fld.of("valid", 0, 0), Fld.of("aperture", 1, 2), Fld.of("pcf", 3, 5)',
               'def nv.reg_v3_pde() -> Rgv: Rgv.of(0, 0, [Fld.of("is_pte", 0, 0), Fld.of("valid", 0, 0), Fld.of("aperture", 1, 2), Fld.of("pcf", 5, 3)',
               "3-bit field -> (5,3)"),
    ("v3_dpd", 'def nv.reg_v3_dpd() -> Rgv: Rgv.of(0, 0, [Fld.of("is_pte", 0, 0), Fld.of("valid", 0, 0), Fld.of("aperture_big", 1, 2), Fld.of("pcf_big", 3, 5)',
               'def nv.reg_v3_dpd() -> Rgv: Rgv.of(0, 0, [Fld.of("is_pte", 0, 0), Fld.of("valid", 0, 0), Fld.of("aperture_big", 1, 2), Fld.of("pcf_big", 5, 3)',
               "3-bit field -> (5,3)"),
    # and, for contrast, a site in a register that DOES print its ranges:
    ("boot42-ctl", 'def nv.reg_boot42() -> Rgv: Rgv.of(0, 2560, [Fld.of("minor_extended_revision", 8, 11), Fld.of("minor_revision", 12, 15)',
                   'def nv.reg_boot42() -> Rgv: Rgv.of(0, 2560, [Fld.of("minor_extended_revision", 8, 11), Fld.of("minor_revision", 15, 12)',
                   "CONTROL: BOOT_42 has a `_ranges` row"),
    # and one of the NON-transposable sites, as the other control:
    ("boot0-1bit-ctl", 'def nv.reg_boot0() -> Rgv: Rgv.of(0, 0, [Fld.of("minor_revision", 0, 3), Fld.of("major_revision", 4, 7), Fld.of("architecture_1", 8, 8)',
                      'def nv.reg_boot0() -> Rgv: Rgv.of(0, 0, [Fld.of("minor_revision", 0, 3), Fld.of("major_revision", 4, 7), Fld.of("architecture_1", 8, 9)',
                      "CONTROL: s==e widened to (8,9) -- a WIDTH edit, not a swap"),
]


def main():
    out = []
    with SM.Staged(SRC, "mmut") as unit:
        original = unit.origin()
        base = unit.rows()
        SM.control(base, unit.rows(), "nvdev baseline (no edit)")
        print("baseline: %d name= rows, row-set digest %s\n" % (len(base), SM.row_digest(base)[:16]))
        print("%-12s %-46s %-9s %s" % ("register", "mutation", "moved", "rows"))
        print("-" * 100)
        for tag, find, repl, why in CASES:
            assert original.count(find) == 1, "%s: anchor count %d" % (tag, original.count(find))
            unit.write(original.replace(find, repl, 1))
            t = unit.try_rows()
            unit.write(original)
            if t is None:
                print("%-12s %-46s %-9s %s" % (tag, why, "NPP", "NOT-A-PROGRAM"))
                out.append("| %s | NOT-A-PROGRAM | | %s |" % (tag, why))
                continue
            m = sorted(k for k in set(base) | set(t) if base.get(k) != t.get(k))
            print("%-12s %-46s %-9d %s" % (tag, why, len(m), ",".join(m[:6])))
            out.append("| %s | %d | %s | %s |" % (tag, len(m), ",".join(m), why))
    with open(os.path.join(HERE, "nv_mmustrans.txt"), "w") as fh:
        fh.write("# nv_mmustrans.py -- MEASURED: one transposition per MMU_VER struct.\n")
        fh.write("\n".join(out) + "\n")
    return 0


sys.exit(main())