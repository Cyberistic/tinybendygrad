#!/usr/bin/env python3
"""jit_ref.py -- UPSTREAM's OWN SHAPE, RUN BY PYTHON, TO PROVE THE SHAPE WORKS.

    .venv/bin/python .agents/slop/cpuseam/jit_ref.py r_56_7_2_2

THIS IS THE REFERENCE FOR THE PORT's SEAM, AND IT IS UPSTREAM's OWN CODE PATH:

  1. `cc` WITH UPSTREAM's OWN ARGV (support/compiler_cpu.py:21-22) PRODUCES AN ELF
     OBJECT ON STDOUT.
  2. UPSTREAM's OWN `jit_loader` (support/elf.py:52-86) RELOCATES IT.
  3. AN ANONYMOUS RWX REGION IS MMAPPED (`MAP_JIT` ON APPLE SILICON, WHERE RWX
     PAGES ARE UNREPRESENTABLE -- ops_cpu.py:29-33), THE IMAGE IS COPIED IN, AND
     THE FUNCTION IS CALLED THROUGH THE ADDRESS (ops_cpu.py:46, :61).

⇒ THE POINT IS TO MEASURE THE SHAPE BEFORE PORTING IT: IF THE SHAPE WORKS HERE,
THE PORT's OWN `jit_loader` (runtime/support/elf.bend:1816) HAS A JOB TO DO, AND
IF IT DOES NOT, THE SHAPE IS WRONG AND NO PORTING WILL SAVE IT.

⇒ AND THE `base` IS MEASURED, NOT ASSUMED: UPSTREAM PASSES THE MMAP ADDRESS
(`mv_address(self.mem)`), AND ITS `R_AARCH64_CALL26` ARM SUBTRACTS THAT BASE
WHICH, AT RUNTIME, WOULD LEAVE THE BRANCH TARGET NEAR ZERO. SO THE BASE IS
MEASURED BOTH WAYS AND THE ROWS SAY WHICH ONE RAN.
"""
import ctypes
import mmap
import os
import pathlib
import struct
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent.parent.parent))

MAP_JIT = 0x0800

NAME = sys.argv[1] if len(sys.argv) > 1 else "r_56_7_2_2"
CC = os.environ.get("CC", "clang")
ARCH = ["arm64", "native"]

# UPSTREAM's OWN ARGV (support/compiler_cpu.py:21-22) WITH `arch`'s OWN FLAGS
# (support/compiler_cpu.py:13-16).
ARGV = [CC, "-c", "-x", "c", "-O2", "-fPIC", "-ffreestanding", "-fno-math-errno",
        "-nostdlib", "-fno-ident", "--target=arm64-none-unknown-elf",
        "-ffixed-x18", "-mcpu=native", "-", "-o", "-"]

src = (HERE / "csrc" / f"{NAME}.c").read_text()
lib = subprocess.check_output(ARGV, input=src.encode())
print(f"# {NAME}: cc produced {len(lib)} bytes of ELF, magic={lib[:4]!r}")

from tinygrad.runtime.support.elf import jit_loader  # noqa: E402

# THE BASE, MEASURED BOTH WAYS. UPSTREAM PASSES THE MMAP ADDRESS
# (`jit_loader(lib, base=mv_address(self.mem))`, ops_cpu.py:34) AND ITS
# `R_AARCH64_CALL26` ARM SUBTRACTS THAT BASE -- WHICH, AT RUNTIME, LEAVES THE
# BRANCH TARGET NEAR ZERO. SO THE TWO READINGS ARE BOTH TAKEN AND THE ROWS SAY
# WHICH ONE RAN.
MODE = os.environ.get("JIT_BASE", "zero")
if MODE == "zero":
  image = jit_loader(lib, base=0)
  mem_len = len(image)
else:
  mem_len = len(lib)
  mem = mmap.mmap(-1, mem_len, mmap.MAP_ANON | mmap.MAP_PRIVATE | MAP_JIT,
                  mmap.PROT_READ | mmap.PROT_WRITE | mmap.PROT_EXEC)
  addr = ctypes.addressof(ctypes.c_char.from_buffer(mem))
  image = jit_loader(lib, base=addr)
print(f"# jit_loader(base={MODE}) -> {len(image)} bytes")

if MODE == "zero":
  mem = mmap.mmap(-1, len(image), mmap.MAP_ANON | mmap.MAP_PRIVATE | MAP_JIT,
                  mmap.PROT_READ | mmap.PROT_WRITE | mmap.PROT_EXEC)
addr = ctypes.addressof(ctypes.c_char.from_buffer(mem))
print(f"# addr {addr:#x}")
rt = ctypes.CDLL("/usr/lib/libSystem.B.dylib")
# MEASURED: THE REAL SIGNATURE IS `void pthread_jit_write_protect_np(int
# enabled)` -- ONE ARGUMENT, AND IT TOGGLES THE PROTECTION FOR THE WHOLE
# PROCESS, NOT FOR AN ADDRESS. MEASURED BY THE CRASH: THE FIRST VERSION PASSED
# THE ADDRESS AS THE FLAG, SO `enabled` WAS NON-ZERO, THE PAGES STAYED READ-ONLY
# AND THE WRITE DIED WITH SIGBUS (rc=138). THE HEADER IS
# `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/pthread/pthread.h:588`.
rt.pthread_jit_write_protect_np.argtypes = [ctypes.c_int]
rt.pthread_jit_write_protect_np(0)
print("# write protect off")
mem.write(image)
print("# image written")
rt.pthread_jit_write_protect_np(1)
print("# write protect on")
rt.__clear_cache(ctypes.c_void_p(addr), ctypes.c_void_p(addr + len(image)))
print(f"# mapped at {addr:#x}")

# THE BUFFERS: THE ORACLE's OWN INPUTS.
ins, outs, sizes = [], [], []
for ln in (HERE / "bufs" / f"{NAME}.rows").read_text().splitlines():
    if ln.startswith("sizes "):
        sizes = [int(x) for x in ln.split(" ")[1].split(",")]
    elif ln.startswith("# buf") and " after " in ln:
        outs.append(bytes.fromhex(ln.split(" after ")[1]))
    elif ln.startswith("buf"):
        ins.append(bytes.fromhex(ln.split(" ")[1]))

bufs = [(ctypes.create_string_buffer(b), len(b)) for b in ins]
fn = ctypes.CFUNCTYPE(None, *(ctypes.c_void_p for _ in bufs))(addr)
fn(*[ctypes.cast(b, ctypes.c_void_p) for b, _ in bufs])

ok = 0
for i, (b, n) in enumerate(bufs):
    # `create_string_buffer` ALLOCATES len+1 (THE NUL), SO THE SLICE IS THE BUFFER.
    got = b.raw[:n]
    if got == outs[i]:
        ok += 1
    else:
        print(f"# buf{i} DIFFERS: {len(got)} bytes")
print(f"# {NAME}: output_match={ok}/{len(bufs)}")
raise SystemExit(0 if ok == len(bufs) else 1)
