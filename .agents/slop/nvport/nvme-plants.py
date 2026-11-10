#!/usr/bin/env python3
"""nvme-plants.py -- THE PLANTS FOR `gates/ops-nvme-gate.py`.

    .venv/bin/python .agents/slop/nvport/nvme-plants.py            # all plants
    .venv/bin/python .agents/slop/nvport/nvme-plants.py --list     # names only

A PLANT IS A DELIBERATE DEFECT, MEASURED, AND THEN REVERTED. EVERY RULE THIS
GATE CLAIMS IS PROVED LOAD-BEARING BY BREAKING THE CODE THAT PRODUCES IT AND
WATCHING THE GATE SAY SO.

THE PLANT NEVER EDITS THE TREE. It works on a COPY in a scratch directory and
runs the REAL gate against the copy -- the same shape as
`.agents/slop/nvport/nv-plants.py`, and the same three scratch failures it
had to be taught about:

  1. `bin/bend` RESOLVES `references/bend/bend2/main.ts` RELATIVE TO ITSELF,
     so the scratch needs a `references/`.
  2. The port's IMPORTS must be PRESENT, and they must be COPIES and not
     symlinks -- a symlinked import is refused with "an import path of plain
     names".
  3. The ORACLE READS `test/mockgpu/` -- not for the NVMe rows, but the
     oracle module is imported beside it -- so the scratch copies it.

**A REFUSED IS NOT A RED PLANT.** The harness reports the verdict TOKEN and a
harness that counted exit code 3 as "the row moved" would report twelve
load-bearing plants and have measured NOTHING.

WHAT EACH PLANT IS SHAPED TO CATCH, AND WHY IT IS NOT A NO-OP. Each edit
changes an ARITHMETIC or a COMPARISON, so it changes a VALUE.

  P1  `q.sq_db`: the `2 * qid` stride becomes `qid`.  THE DOORBELLS OF QUEUE
      `qid` ARE ADJACENT, AND A PORT THAT PUTS THE SUBMISSION ONE AT `qid`
      PUTS IT IN THE ADMIN QUEUE'S PAIR.
  P2  `q.next_phase`: the inversion moves to the OLD tail.  **THE PHASE
      FLIPS ON THE SUBMIT THAT WRAPPED THE RING**, AND A PORT THAT CHECKS
      THE OLD TAIL FLIPS ONE SUBMIT EARLY.
  P3  `prp_ptr`: the `(p + 1)` becomes `p`.  **THE POINTER IS FOR PAGE
      `p + 1`**, AND THE PORT THAT WRITES `p` POINTS AT THE PAGE'S OWN
      SLOT.
  P4  `wave_stride`: `entries - 1` becomes `entries`.  **ONE SLOT IS LEFT
      FREE** SO THE RING'S FULL AND EMPTY STATES ARE DISTINGUISHABLE.
  P5  `lba_step`: the shift by `lba_shift` becomes a shift by zero.  **THE
      LBA STEP IS IN BLOCKS AND NOT IN BYTES.**
  P6  `has_third_prp`: `== 2` becomes `>= 2`.  **EXACTLY TWO PAGES** GET A
      THIRD PRP ENTRY, AND `>= 2` GETS THE THREE-PAGE CASE WRONG.
  P7  `max_xfer`: the `min(..., 8)` cap is dropped.  **A DRIVE THAT REPORTS
      A BIGGER MPSz IS CLAMPED**, BECAUSE THE PRP LIST IS BUILT FOR AT MOST
      EIGHT PAGES.
  P8  `lba_shift_index`: the `+ 2` is dropped.  **THE `+ 2` IS THE LOW BYTE
      OF THE FOUR-BYTE ENTRY**, AND A PORT THAT READS THE HIGH BYTE GETS A
      DIFFERENT SHIFT.
  P9  `sqe_words`: the PRP's LOW WORD AND HIGH WORD ARE SWAPPED.  **THE
      FORMAT IS LITTLE-ENDIAN.**
  P10 `cap_timeout_ms`: the `* 500` becomes `* 1`.  **THE MULTIPLIER IS 500**
      AND EVERY DRIVE'S TIMEOUT CHANGES WITH IT.
  P11 `create_cdw10`: the `- 1` is dropped.  **THE SIZE FIELD IS ZERO-BASED**
      AND A PORT THAT PASSES THE ENTRY COUNT CREATES A QUEUE ONE ENTRY
      SHORTER THAN THE DEVICE OFFERS.
  P12 THE CONTROL: a comment-only edit.  A table with no row that CANNOT move
      is a table of coincidences.
"""

import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
PORT = ROOT / "tinybendygrad/runtime/ops_nvme.bend"
GATE = ROOT / "gates/ops-nvme-gate.py"
ORACLE = ROOT / "gates/ops-nvme-oracle.py"

# (NAME, OLD, NEW, WHAT IT IS SHAPED TO CATCH)
PLANTS = (
    ("P1_sq_db_stride",
     "def q.sq_db(qid: U32, +db_stride: U32) -> U32:\n  U32.add(NVME_REG_DBS(), U32.mul(U32.mul(2, qid), db_stride))",
     "def q.sq_db(qid: U32, +db_stride: U32) -> U32:\n  U32.add(NVME_REG_DBS(), U32.mul(qid, db_stride))",
     "the `2 * qid` doorbell stride"),
    ("P2_phase_on_old_tail",
     "def q.next_phase(+phase: U32, new_tail: U32) -> U32:\n  Bool.pick(U32, U32.is_zero(new_tail), U32.xor(phase, 1), phase)",
     "def q.next_phase(+phase: U32, new_tail: U32) -> U32:\n  Bool.pick(U32, U32.is_zero(U32.sub(new_tail, 1)), U32.xor(phase, 1), phase)",
     "the phase's inversion on the NEW tail, not the old one"),
    ("P3_prp_ptr_page",
     "def prp_ptr(list_addr: U32, +p: U32) -> U32:\n  U32.add(list_addr, U32.mul(U32.mod(U32.add(p, 1), PRP_LIST_ENTRIES()), 8))",
     "def prp_ptr(list_addr: U32, +p: U32) -> U32:\n  U32.add(list_addr, U32.mul(U32.mod(p, PRP_LIST_ENTRIES()), 8))",
     "the PRP pointer is for page `p + 1`"),
    ("P4_wave_stride",
     "def wave_stride(+entries: U32) -> U32:\n  U32.sub(entries, 1)",
     "def wave_stride(+entries: U32) -> U32:\n  entries",
     "the wave stride leaves ONE SLOT FREE"),
    ("P5_lba_step_blocks",
     "def lba_step(+max_xfer: U32, +lba_shift: U32) -> U32:\n  U32.shrn(max_xfer, U32.to_nat(lba_shift))",
     "def lba_step(+max_xfer: U32, +lba_shift: U32) -> U32:\n  max_xfer",
     "the LBA step is in BLOCKS, not bytes"),
    ("P6_third_prp_exactly_two",
     "def has_third_prp(+nb: U32) -> Bool:\n  U32.is_eq(cmd_pages(nb), 2)",
     "def has_third_prp(+nb: U32) -> Bool:\n  U32.is_ge(cmd_pages(nb), 2)",
     "the third PRP entry is for EXACTLY two pages"),
    ("P7_max_xfer_cap",
     "def max_xfer(+mpsz: U32) -> U32:\n  U32.shln(4096, U32.to_nat(U32.min(mpsz, MPSZ_MAX())))",
     "def max_xfer(+mpsz: U32) -> U32:\n  U32.shln(4096, U32.to_nat(mpsz))",
     "the `min(..., 8)` cap on the maximum transfer"),
    ("P8_lba_shift_low_byte",
     "def lba_shift_index(+nlbaf: U32) -> U32:\n  U32.add(U32.add(128, U32.mul(4, U32.and(nlbaf, 15))), 2)",
     "def lba_shift_index(+nlbaf: U32) -> U32:\n  U32.add(128, U32.mul(4, U32.and(nlbaf, 15)))",
     "the `+ 2` is the LOW byte of the four-byte entry"),
    ("P9_sqe_little_endian",
     "  [cmd_word(opcode, slot), nsid, 0, 0, 0, 0, prp1_lo, prp1_hi,\n   0, 0, cdw10, cdw11, 0, 0, 0, 0]",
     "  [cmd_word(opcode, slot), nsid, 0, 0, 0, 0, prp1_hi, prp1_lo,\n   0, 0, cdw10, cdw11, 0, 0, 0, 0]",
     "the PRP address is LITTLE-ENDIAN"),
    ("P10_timeout_multiplier",
     "def cap_timeout_ms(+lo: U32) -> U32:\n  U32.mul(U32.and(U32.shrn(lo, 24n), 255), 500)",
     "def cap_timeout_ms(+lo: U32) -> U32:\n  U32.mul(U32.and(U32.shrn(lo, 24n), 255), 1)",
     "the timeout's `* 500` multiplier"),
    ("P11_create_zero_based_size",
     "def create_cdw10(+entries: U32, +qid: U32) -> U32:\n  U32.or(U32.shln(U32.sub(entries, 1), 16n), qid)",
     "def create_cdw10(+entries: U32, +qid: U32) -> U32:\n  U32.or(U32.shln(entries, 16n), qid)",
     "the create's size field is ZERO-BASED"),
    ("P12_control_comment_only",
     "# tinybendygrad/runtime/ops_nvme.bend -- port of tinygrad/runtime/ops_nvme.py",
     "# tinybendygrad/runtime/ops_nvme.bend -- port of tinygrad/runtime/ops_nvme.py\n"
     "# PLANT CONTROL: a comment-only edit. It MUST move nothing.",
     "THE CONTROL: a table with no row that CANNOT move is a table of coincidences"),
)


def _run_gate(scratch):
    env = dict(os.environ)
    env["TINYGRAD_ROOT"] = str(scratch)
    return subprocess.run([sys.executable, str(scratch / "gates/ops-nvme-gate.py")],
                          capture_output=True, text=True, env=env)


def main():
    if "--list" in sys.argv:
        for n, _, _, _ in PLANTS:
            print(n)
        return 0
    src = PORT.read_text()
    scratch = Path(tempfile.mkdtemp(prefix="nvmeplant-"))
    try:
        shutil.copytree(ROOT / "tinybendygrad", scratch / "tinybendygrad",
                        symlinks=False, ignore=shutil.ignore_patterns("__pycache__"))
        (scratch / "gates").mkdir()
        (scratch / "bin").mkdir()
        os.symlink(ROOT / "bin/bend", scratch / "bin/bend")
        os.symlink(ROOT / ".venv", scratch / ".venv")
        os.symlink(ROOT / "references", scratch / "references")
        shutil.copy(ORACLE, scratch / "gates/ops-nvme-oracle.py")
        shutil.copy(ROOT / "gates/gatekit.py", scratch / "gates/gatekit.py")
        shutil.copy(GATE, scratch / "gates/ops-nvme-gate.py")
        shutil.copytree(ROOT / "test/mockgpu", scratch / "test/mockgpu",
                        symlinks=False, ignore=shutil.ignore_patterns("__pycache__"))
        target = scratch / "tinybendygrad/runtime/ops_nvme.bend"

        for name, old, new, what in PLANTS:
            if old not in src:
                print(f"=== {name} === SKIPPED: the anchor is not in the file")
                print(f"    anchor: {old!r}")
                continue
            target.write_text(src.replace(old, new, 1))
            r = _run_gate(scratch)
            red = r.returncode != 0
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
