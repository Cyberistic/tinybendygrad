#!/usr/bin/env python3
"""nv_table_equiv.py -- IS THE PORTED FIELD TABLE THE SAME TABLE CPython HAS?

The transposition in `nv.reg_boot42` was one wrong pair in 86.  This answers the
question the transposition raises, which is "how many of the OTHER 85 are wrong",
by COMPARING rather than by reading: every `Fld.of(name, s, e)` literal in
nvdev.bend against the `NVReg` table CPython actually holds, field for field and
IN ORDER -- so a transposed pair, a renamed field, a reordered list and a wrong
offset are four different failures and this distinguishes them.

The CPython side is reached through `include()`, i.e. `getattr(getattr(nv_regs,
name), arch or 'regs')`, which is nvdev.py:162.  The arch per register is not
guessed: it is the one nvdev.py passes at :102-104 and :127, and it is stated in
`SRC_OF` with the call site.

A register with NO fields (`NV_PGC6_AON_SECURE_SCRATCH_GROUP_42` is `Nil{}`) has
no `Fld.of` to compare and is reported separately rather than silently skipped.

usage: python3 .agents/slop/nv_table_equiv.py
"""
import importlib
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(ROOT, "tinybendygrad/runtime/support/nv/nvdev.bend")

# port register -> (module, arch, CPython register name), with the nvdev.py line
# that establishes the arch.
SRC_OF = {
    "boot0": ("nv_ref", "regs", "NV_PMC_BOOT_0", "nvdev.py:101"),
    "boot42": ("nv_ref", "regs", "NV_PMC_BOOT_42", "nvdev.py:101"),
    "wpr2": ("dev_fb", "tu102", "NV_PFB_PRI_MMU_WPR2_ADDR_HI", "nvdev.py:102"),
    "scratch": ("dev_gc6_island", "ga102", "NV_PGC6_AON_SECURE_SCRATCH_GROUP_42", "nvdev.py:103"),
    "inval": ("dev_vm", "tu102", "NV_VIRTUAL_FUNCTION_PRIV_MMU_INVALIDATE", "nvdev.py:124"),
    "v2_pte": ("dev_mmu", "tu102", "NV_MMU_VER2_PTE", "nvdev.py:127 (mmu_ver==2)"),
    "v2_pde": ("dev_mmu", "tu102", "NV_MMU_VER2_PDE", "nvdev.py:127 (mmu_ver==2)"),
    "v2_dpd": ("dev_mmu", "tu102", "NV_MMU_VER2_DUAL_PDE", "nvdev.py:127 (mmu_ver==2)"),
    "v3_pte": ("dev_mmu", "gh100", "NV_MMU_VER3_PTE", "nvdev.py:127 (mmu_ver==3)"),
    "v3_pde": ("dev_mmu", "gh100", "NV_MMU_VER3_PDE", "nvdev.py:127 (mmu_ver==3)"),
    "v3_dpd": ("dev_mmu", "gh100", "NV_MMU_VER3_DUAL_PDE", "nvdev.py:127 (mmu_ver==3)"),
}

REG_DEF = re.compile(r"^def nv\.reg_(\w+)\(\) -> Rgv: Rgv\.of\([^,]+, [^,]+, (\[.*\]|Nil\{\})\)\s*$", re.M)
FLD = re.compile(r'Fld\.of\("([^"]+)",\s*(-?\d+),\s*(-?\d+)\)')


def port_tables():
    out = {}
    for m in REG_DEF.finditer(open(SRC).read()):
        out[m.group(1)] = [(f.group(1), int(f.group(2)), int(f.group(3)))
                           for f in FLD.finditer(m.group(2))]
    return out


def main():
    mods = {mn: importlib.import_module("tinygrad.runtime.autogen.nv_regs." + mn)
            for mn in ("nv_ref", "dev_fb", "dev_gc6_island", "dev_vm", "dev_mmu")}
    port = port_tables()
    print("%-9s %-46s %-7s %s" % ("port reg", "CPython table (arch from)", "fields", "verdict"))
    print("-" * 100)
    bad, empty, tot, regs = [], [], 0, 0
    for reg in sorted(SRC_OF):
        mod, arch, name, call = SRC_OF[reg]
        fs = port.get(reg)
        cpy = [(k, a, b) for k, (a, b) in getattr(mods[mod], arch)[name][2].items()]
        if fs is None:
            if not cpy:
                empty.append(reg)
                print("%-9s %-46s %-7d no fields on either side (%s)" % (reg, name, 0, call))
            else:
                bad.append(reg)
                print("%-9s %-46s %-7d *** PORT HAS NO TABLE, CPYTHON HAS %d ***" % (reg, name, len(cpy), call))
            continue
        regs += 1
        tot += len(fs)
        if fs == cpy:
            print("%-9s %-46s %-7d identical, field for field, IN ORDER" % (reg, name, len(fs)))
        else:
            bad.append(reg)
            print("%-9s %-46s %-7d *** MISMATCH ***" % (reg, name, len(fs)))
            if len(fs) == len(cpy):
                for i, (a, b) in enumerate(zip(fs, cpy)):
                    if a != b:
                        print("        [%d] port=%s  cpython=%s" % (i, a, b))
            else:
                print("        port   : %s" % fs)
                print("        cpython: %s" % cpy)
    print()
    print("tables compared : %d" % regs)
    print("fields compared : %d" % tot)
    print("registers with no fields on either side (nothing to compare): %s" % (empty or "none"))
    print("MISMATCHING TABLES: %d %s" % (len(bad), bad))
    return 1 if bad else 0


sys.exit(main())