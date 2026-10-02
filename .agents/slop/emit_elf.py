#!/usr/bin/env python3
# emit_elf.py -- assemble tinybendygrad/runtime/support/elf.bend.
#
# The port's HAND-WRITTEN parts (header, types, defs, gate) live in this file as
# two string blocks and the GENERATED parts (the real ELF fixture blobs) are
# emitted from the actual files on disk. That is what keeps the fixtures honest:
# a fixture is a byte-for-byte copy of a file `file(1)` recognises.
#
#     python3 .agents/slop/emit_elf.py > tinybendygrad/runtime/support/elf.bend
#
# EXPECTED VALUES ARE NOT IN HERE. Every `py=` in the gate block comes from
# .agents/slop/elf_oracle.py, which CALLS tinygrad's own elf.py.

import sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "elf")

# (file, Bend def, gate tag, note)
FIXTURES = [
    ("e64.o",       "B_E64_O",   "e64_o",   "ELF64 x86-64,  12 sections, SHT_RELA"),
    ("ea64.o",      "B_EA64_O",  "ea64_o",  "ELF64 aarch64,  11 sections, SHT_RELA"),
    ("e32.o",       "B_E32_O",   "e32_o",   "ELF32 i386,     12 sections, SHT_REL"),
    ("n64.o",       "B_N64_O",   "n64_o",   "ELF64 x86-64,  15 sections, .rodata/.data/msg"),
    ("na64.o",      "B_NA64_O",  "na64_o",  "ELF64 aarch64,  14 sections, 10 relocations"),
    ("n32.o",       "B_N32_O",   "n32_o",   "ELF32 i386,     15 sections, 9 relocations"),
    ("j_aarch64.o", "B_JA64_O",  "j_a64_o", "ELF64 aarch64, THE ONE jit_loader SUCCEEDS on"),
]
REFUSERS = [
    ("r64.so",   "B_R64_SO",   "r64_so",   "a real .so: `.rela.dyn` -> `.dyn` -> StopIteration"),
    ("rx64.exe", "B_RX64_EXE", "rx64_exe", "a real exe: symbol names out of the WRONG strtab"),
]

def blob_lines(fn, bn, note, width=110):
  path = os.path.join(FIX, fn)
  h = open(path, "rb").read().hex()
  parts = [h[i:i+width] for i in range(0, len(h), width)] or [""]
  w = sys.stdout.write
  w(f"# {fn} -- {os.path.getsize(path)} bytes, {note}\n")
  w(f"def {bn}() -> String:\n  String.concat([\n")
  for p in parts:
    w(f'    "{p}",\n')
  w('    ""])\n\n')

emit_fixtures = sys.argv[1:] == ["fixtures"]
if emit_fixtures:
    for fn, bn, tag, note in FIXTURES + REFUSERS:
        blob_lines(fn, bn, note)
    sys.exit(0)

PROLOGUE = open(os.path.join(HERE, "elf_prologue.bend")).read()

out = [PROLOGUE]
sys.stdout.write(PROLOGUE)
