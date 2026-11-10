#!/usr/bin/env python3
"""nv-plants.py -- THE PLANTS FOR `gates/ops-nv-gate.py`.

    .venv/bin/python .agents/slop/nvport/nv-plants.py            # all plants
    .venv/bin/python .agents/slop/nvport/nv-plants.py --list     # names only

A PLANT IS A DELIBERATE DEFECT, MEASURED, AND THEN REVERTED. The tree's rule
is that a row which cannot go red is worse than no row, because it is trusted;
so every rule this gate claims is proved load-bearing by breaking the code that
produces it and watching the gate say so.

THE PLANT NEVER EDITS THE TREE. Every plant works on a COPY in a scratch
directory and runs the REAL gate against the copy, so a plant cannot leave the
tree broken. `.agents/slop/citefix-runtime/plant.py` does the same and says
why: "edits a COPY (never `git show HEAD:`)".

WHAT EACH PLANT IS SHAPED TO CATCH, AND WHY IT IS NOT A NO-OP. Each edit
changes an ARITHMETIC or a COMPARISON, so it changes a VALUE. A rename would
change a row NAME and the gate would report a missing row, which is a different
failure and a much easier one to make pass by accident.

  P1  `nvm.word`: `typ << 28` becomes `typ << 29`.  The command header's four
      fields, and the header is in EVERY word stream.
  P2  `arch_low.at`: `v >> 4` becomes `v >> 1`.  The SM version decode's nibble
      shift, and `sass_of` has the SAME `>> 4` -- so this plant moves the ARCH
      rows and leaves the SASS rows alone, which is what makes the two tables
      separable.
  P3  `qmd.ver.of`: `>=` becomes `>`.  The single comparison that picks the QMD
      generation, so it moves the Blackwell rows and nothing else.
  P4  THE CONTROL: a comment-only edit.  A table with no row that CANNOT move
      is a table of coincidences, and this is the row that says the other
      plants mean something.
  P5  `qmd.slot.ok`: `and` becomes `or`.  The release-slot guard refuses only
      when BOTH slots are busy.
  P6  `pc.find`: the miss sentinel `!=` becomes `<`.  THE BLIND SPOT the port's
      own mutation table records as M13 -- it moved ZERO rows, because
      `pc.find` answers `len` on a miss and an index below it on a hit, which
      makes `found < len` and `found != len` THE SAME PREDICATE over every
      possible answer. **A PLANT THAT DOES NOT GO RED IS A FINDING, NOT A
      FAILURE OF THE PLANT**, and this script REPORTS it as such.
  P7  `iowr.cmd`: the size mask is dropped.  An 8 KiB struct encodes as if it
      were empty.
  P8  `to_name.join.parts`: the separator is appended to the head too.
      `String.split` DROPS the separator, so it has to be put back.
"""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PORT = ROOT / "tinybendygrad/runtime/ops_nv.bend"
GATE = ROOT / "gates/ops-nv-gate.py"
ORACLE = ROOT / "gates/ops-nv-oracle.py"

# (NAME, OLD, NEW, WHAT IT IS SHAPED TO CATCH)
PLANTS = (
    ("P1_nvm_word_shift",
     "U32.shln(typ, 28n)",
     "U32.shln(typ, 29n)",
     "the command header's four fields"),
    ("P2_arch_low_shift",
     "case True{}: U32.shrn(v, 4n)",
     "case True{}: U32.shrn(v, 1n)",
     "the SM version decode's nibble shift"),
    ("P3_qmd_ver_of",
     "U32.is_ge(compute, CLASS_BLACKWELL_COMPUTE_A())",
     "U32.is_gt(compute, CLASS_BLACKWELL_COMPUTE_A())",
     "the ONE comparison that picks the QMD generation"),
    ("P4_control_comment_only",
     "# tinybendygrad/runtime/ops_nv.bend -- port of tinygrad/runtime/ops_nv.py",
     "# tinybendygrad/runtime/ops_nv.bend -- port of tinygrad/runtime/ops_nv.py\n"
     "# PLANT CONTROL: a comment-only edit. It MUST move nothing.",
     "THE CONTROL: a table with no row that CANNOT move is a table of coincidences"),
    ("P5_qmd_slot_ok",
     "def qmd.slot.ok(busy0: Bool, busy1: Bool) -> Bool: Bool.not(Bool.and(busy0, busy1))",
     "def qmd.slot.ok(busy0: Bool, busy1: Bool) -> Bool: Bool.not(Bool.or(busy0, busy1))",
     "the release-slot guard, which refuses only when BOTH slots are busy"),
    ("P6_pc_find_sentinel",
     "case +x <> t: pc.find.go(k, t, U32.add(at, 1), Bool.pick(U32, pc.same(k, x), at, got))",
     "case +x <> t: pc.find.go(k, t, U32.add(at, 1), Bool.pick(U32, pc.same(k, x), at, got))",
     "THE KNOWN BLIND SPOT (M13) -- see the note below"),
    ("P7_iowr_size_mask",
     "iowr.pack(U32.and(nbytes, IOWR_SIZE_MASK()), U32.and(nr, IOWR_NR_MASK()))",
     "iowr.pack(nbytes, U32.and(nr, IOWR_NR_MASK()))",
     "the 8 KiB struct size mask"),
    ("P8_to_name_separator",
     "case h <> t: to_name.join.parts(t, List.append(&2, String, acc, [String.concat([h, \"_\"])]))",
     "case h <> t: to_name.join.parts(t, List.append(&2, String, acc, [String.concat([h, \"_\", \"_\"])]))",
     "the separator `String.split` drops"),
    ("P9_mock_count",
     "def dev.count(iface: U32, gpus: U32) -> U32:\n  Bool.pick(U32, U32.is_eq(iface, IFACE_MOCK()), 1, gpus)",
     "def dev.count(iface: U32, gpus: U32) -> U32:\n  Bool.pick(U32, U32.is_eq(iface, IFACE_MOCK()), 2, gpus)",
     "`MOCKIface.count = 1` -- the ONE line that separates the mock from the real one"),
    ("P10_mock_selection",
     "def dev.iface_ok(iface: U32, want_mock: Bool) -> Bool:\n  Bool.or(want_mock, Bool.not(dev.is_mock(iface)))",
     "def dev.iface_ok(iface: U32, want_mock: Bool) -> Bool:\n  Bool.or(want_mock, True{})",
     "the \"never fallback to mock ifaces\" rule -- a port that KEEPS the mock "
     "on a real target would benchmark nothing"),
    ("P11_mock_drv_table",
     "Bool.pick(U32, U32.is_ge(major, 615), 615,\n    Bool.pick(U32, U32.is_ge(major, 610), 610,\n      Bool.pick(U32, U32.is_ge(major, 580), 580, 570)))",
     "Bool.pick(U32, U32.is_ge(major, 615), 615,\n    Bool.pick(U32, U32.is_ge(major, 610), 610,\n      Bool.pick(U32, U32.is_ge(major, 580), 580, 580)))",
     "the driver-version table picker -- a port that picked the WRONG constant "
     "table would run against constants the driver does not use"),
    ("P12_mock_classlist_n",
     "def MOCK_CLASSLIST_N() -> U32: 52",
     "def MOCK_CLASSLIST_N() -> U32: 55",
     "THE COUNT THAT WAS WRONG ONCE: the driver's own class list has FIFTY-TWO "
     "entries and the port first said FIFTY-FIVE"),
)

# P6 IS THE BLIND SPOT, and it is planted DIFFERENTLY: the port's own mutation
# table records that changing the miss sentinel moves ZERO rows, because
# `pc.find` answers `len` on a miss and an index below it on a hit, so
# `found < len` and `found != len` are THE SAME PREDICATE over every possible
# answer. The six `nv_find_*` rows that assert `pc.find` are PORT-ONLY -- they
# have no CPython counterpart, because upstream's `_nv_program_cache` is a bare
# dict and `pc.find` is this port's own model of it.
#
# SO THE PLANT THAT MATTERS IS NOT "CHANGE THE VALUE" -- that moves rows and
# proves nothing about the blind spot. IT IS "CHANGE THE PREDICATE SO THE ROWS
# STILL PASS". The edit below replaces the miss sentinel `len` with `len + 1`:
# a miss now answers a value that is NEITHER an index NOR the length, so every
# `found < len` test still holds and every `found != len` test still holds, and
# a defect that a reader would want to catch -- "a miss answers something that
# is not the length" -- is INVISIBLE TO THE ROWS.
#
# THE EXPECTED RESULT IS **GREEN**, and that is the FINDING. A green here is
# not a broken plant; it is the MEASUREMENT of the blind spot, and it is
# reported as such.
P6_OLD = ("def pc.find.at(+k: PKey, +ks: List<&2, PKey>) -> U32:\n"
          "  pc.find.go(k, ks, 0, U32.from_nat(List.length(&2, PKey, ks)))")
P6_NEW = ("def pc.find.at(+k: PKey, +ks: List<&2, PKey>) -> U32:\n"
          "  pc.find.go(k, ks, 0, U32.add(U32.from_nat(List.length(&2, PKey, ks)), 1))")


def _run_gate(scratch):
    """The REAL gate, against the copy. `TINYGRAD_ROOT` points at the scratch."""
    env = dict(os.environ)
    env["TINYGRAD_ROOT"] = str(scratch)
    return subprocess.run([sys.executable, str(scratch / "gates/ops-nv-gate.py")],
                          capture_output=True, text=True, env=env)


def main():
    if "--list" in sys.argv:
        for n, _, _, _ in PLANTS:
            print(n)
        return 0
    argv = [a for a in sys.argv[1:] if not a.startswith("--")]
    src = PORT.read_text()
    scratch = Path(tempfile.mkdtemp(prefix="nvplant-"))
    try:
        # THE SCRATCH IS A TREE: the gate resolves `bin/bend`, `.venv/bin/python`
        # and the port by ROOT, so the copy needs those to be the REAL ones.
        (scratch / "gates").mkdir()
        (scratch / "bin").mkdir()
        # THE PORT'S OTHER FILES, COPIED AND NOT SYMLINKED.
        # `ops_nv.bend` imports `../helpers.bend`, `../LAWS/spec.bend` and
        # `../device.bend`, so the scratch needs them or the compiler says "no
        # such file" -- MEASURED, and a REFUSED is not a RED PLANT.
        #
        # AND THEY ARE COPIES, NOT SYMLINKS. MEASURED: with the port's imports
        # symlinked into the scratch, the compiler refused with "an import path
        # of plain names" -- it resolves the import through the link and the
        # resolved path is not a plain name. So the scratch holds a COPY of the
        # port's `tinybendygrad/` tree with ONE REAL FILE in it (the port, with
        # the defect), and the copy is what the compiler reads.
        shutil.copytree(ROOT / "tinybendygrad", scratch / "tinybendygrad",
                        symlinks=False, ignore=shutil.ignore_patterns("__pycache__"))
        os.symlink(ROOT / "bin/bend", scratch / "bin/bend")
        os.symlink(ROOT / ".venv", scratch / ".venv")
        # `bin/bend` IS A 2 KB SHIM ONTO `references/bend/bend2/main.ts`, AND IT
        # RESOLVES THAT PATH RELATIVE TO ITSELF -- MEASURED: with the shim
        # symlinked into a scratch tree and no `references/`, every plant came
        # back `REFUSED: Module not found ".../bin/../references/bend/bend2/main.ts"`.
        # A REFUSED IS NOT A RED PLANT, and a harness that counted it as one
        # would report eight load-bearing plants and have measured NOTHING.
        os.symlink(ROOT / "references", scratch / "references")
        shutil.copy(ORACLE, scratch / "gates/ops-nv-oracle.py")
        shutil.copy(ROOT / "gates/gatekit.py", scratch / "gates/gatekit.py")
        shutil.copy(GATE, scratch / "gates/ops-nv-gate.py")
        # THE MOCK DRIVER, BECAUSE THE ORACLE READS IT. `gates/ops-nv-oracle.py`
        # READS `test/mockgpu/nv/nvdriver.py` FOR THE CLASS LIST, THE DRIVER
        # VERSION AND THE GPU COUNT, AND IT READS IT RELATIVE TO THE ROOT --
        # WHICH IN THE SCRATCH IS THE SCRATCH. MEASURED: without this, every
        # plant came back `REFUSED: the oracle failed rc=1` at the driver read,
        # and A REFUSED IS NOT A RED PLANT.
        shutil.copytree(ROOT / "test/mockgpu", scratch / "test/mockgpu",
                        symlinks=False, ignore=shutil.ignore_patterns("__pycache__"))
        (scratch / "test/__init__.py").write_text("")
        target = scratch / "tinybendygrad/runtime/ops_nv.bend"

        for name, old, new, what in PLANTS:
            if name == "P6_pc_find_sentinel":
                old, new = P6_OLD, P6_NEW
            if old not in src:
                print(f"=== {name} === SKIPPED: the anchor is not in the file")
                print(f"    anchor: {old!r}")
                continue
            target.write_text(src.replace(old, new, 1))
            r = _run_gate(scratch)
            red = r.returncode != 0
            if name == "P6_pc_find_sentinel":
                # P6 IS EXPECTED TO BE GREEN. A green here is the MEASUREMENT of
                # the blind spot, not a broken plant, and it is LABELLED so a
                # reader cannot mistake it for a passing plant.
                print(f"=== {name} === rc={r.returncode} "
                      f"{'RED' if red else 'GREEN -- AND THAT IS THE FINDING: the rows CANNOT SEE IT'}")
            else:
                print(f"=== {name} === rc={r.returncode} {'RED' if red else 'GREEN (NOTHING MOVED)'}")
            print(f"    catches: {what}")
            print(f"    stdout: {r.stdout.strip()[:300]}")
            if r.stderr.strip():
                print(f"    stderr: {r.stderr.strip()[:300]}")
            print()
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
