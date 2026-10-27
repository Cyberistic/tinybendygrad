#!/usr/bin/env python3
"""reloc_ref.py -- UPSTREAM's `jit_loader` ON THE FIVE REAL KERNELS.

    .venv/bin/python .agents/slop/cpuseam/reloc_ref.py

IT WRITES, FOR EACH KERNEL:

  * `elf/<name>.hex`   -- THE ELF OBJECT `cc` PRODUCED WITH UPSTREAM's OWN ARGV
    (support/compiler_cpu.py:21-22), AS HEX. THIS IS THE PORT's `jit_loader`'s
    INPUT.
  * `elf/<name>.img`   -- UPSTREAM's OWN `jit_loader` (support/elf.py:52-86)
    OUTPUT, AS HEX. THIS IS THE ORACLE FOR THE PORT's `jit_loader`.

⇒ THE COMPARER IS A BYTE DIFF, AND THE PORT's RELOCATED IMAGE IS WHAT THE
PORT's OWN `runtime/support/elf.bend:1816` PRODUCES FROM THE SAME INPUT.

⇒ THE BASE IS MEASURED BOTH WAYS: `0` AND THE MMAP ADDRESS. UPSTREAM PASSES THE
MMAP ADDRESS AND ITS `R_AARCH64_CALL26` ARM SUBTRACTS THAT BASE, WHICH AT
RUNTIME WOULD LEAVE THE BRANCH TARGET NEAR ZERO -- SO BOTH READINGS ARE TAKEN
AND THE ROWS SAY WHICH ONE RAN.
"""
import os
import pathlib
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent.parent))

KERNELS = ["r_10_98_4", "r_2_14_14_4_4_3_3", "r_4_28_7_4_3_3",
            "r_56_14_2_2", "r_56_7_2_2"]
CC = os.environ.get("CC", "clang")
# UPSTREAM's OWN ARGV (support/compiler_cpu.py:21-22) WITH `arch`'s OWN FLAGS
# (support/compiler_cpu.py:13-16) FOR THIS MACHINE: `platform.machine()` IS
# "arm64" AND UPSTREAM APPENDS ",native" (ops_cpu.py:76).
ARGV = [CC, "-c", "-x", "c", "-O2", "-fPIC", "-ffreestanding", "-fno-math-errno",
        "-nostdlib", "-fno-ident", "--target=arm64-none-unknown-elf",
        "-ffixed-x18", "-mcpu=native", "-", "-o", "-"]

from tinygrad.runtime.support.elf import jit_loader  # noqa: E402

OUT = HERE / "elf"
OUT.mkdir(parents=True, exist_ok=True)
for nm in KERNELS:
    src = (HERE / "csrc" / f"{nm}.c").read_text()
    lib = subprocess.check_output(ARGV, input=src.encode())
    (OUT / f"{nm}.hex").write_text(lib.hex())
    img = jit_loader(lib, base=0)
    (OUT / f"{nm}.img").write_text(img.hex())
    print(f"# {nm}: elf={len(lib)} bytes image={len(img)} bytes "
          f"magic={lib[:4]!r} first8={img[:8].hex()}")
print(f"# wrote {len(KERNELS)} elf hexes and {len(KERNELS)} oracle images to {OUT.name}/")
