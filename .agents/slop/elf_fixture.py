#!/usr/bin/env python3
# elf_fixture.py -- emit the fixture + gate blocks for runtime/support/elf.bend
#
# THE FIXTURES ARE REAL ELF FILES. This reads the bytes of the files compiled in
# .agents/slop/elf/ with clang and ld.lld, and emits:
#
#   1. the blob literals, as hex STRINGS (Bend has no file IO in a def and no
#      `bytes` type, so a blob is a String and `elf.u8` is its reader);
#   2. the section-header rows the gate reads -- and those are read FROM THE BLOB
#      by the port's own `elf.shdr_*` defs, not transcribed.
#
# It does NOT emit any expected value. Every `py=` in the gate comes from
# elf_oracle.py, which calls tinygrad's own elf.py.
#
#     python3 .agents/slop/elf_fixture.py > .agents/slop/elf_fixture.txt

import sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "elf")

FIXTURES = [
    # (file, Bend literal name, gate tag)
    ("e64.o",   "B_E64_O",   "e64_o"),
    ("ea64.o",  "B_EA64_O",  "ea64_o"),
    ("e32.o",   "B_E32_O",   "e32_o"),
    ("n64.o",   "B_N64_O",   "n64_o"),
    ("na64.o",  "B_NA64_O",  "na64_o"),
    ("n32.o",   "B_N32_O",   "n32_o"),
    ("j_aarch64.o", "B_JA64_O", "j_a64_o"),
]
# The two that REFUSE inside tinygrad's own reader. They are carried as blobs so
# the port can derive the refusal ITSELF rather than being told it.
REFUSERS = [
    ("r64.so",  "B_R64_SO",  "r64_so"),
    ("rx64.exe", "B_RX64_EXE", "rx64_exe"),
]

def blob_lines(name, path, width=112):
  h = open(path, "rb").read().hex()
  print(f"def {name}() -> String:")
  parts = [h[i:i+width] for i in range(0, len(h), width)]
  if not parts:
    parts = [""]
  print("  String.concat([")
  for p in parts:
    print(f'    "{p}",')
  print('    ""])')

def main():
  print("# ---- BEGIN GENERATED FIXTURES (real ELF bytes, hex) ----")
  for fn, bn, tag in FIXTURES:
    print(f"# {fn}  ({os.path.getsize(os.path.join(FIX, fn))} bytes)")
    blob_lines(bn, os.path.join(FIX, fn))
    print()
  for fn, bn, tag in REFUSERS:
    print(f"# {fn}  ({os.path.getsize(os.path.join(FIX, fn))} bytes) -- a REFUSING fixture")
    blob_lines(bn, os.path.join(FIX, fn))
    print()
  print("# ---- END GENERATED FIXTURES ----")

main()
