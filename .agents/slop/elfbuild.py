#!/usr/bin/env python3
# elfbuild.py -- assemble tinybendygrad/runtime/support/elf.bend.
#
# THE PORT IS GENERATED so it cannot be lost to a bad edit, and so the FIXTURES --
# the real ELF bytes -- are always byte-identical to the files in
# .agents/slop/elf/. The hand-written half is the PROLOGUE string below; the
# generated half is the blob table. Nothing here contains an expected VALUE:
# every `py=` in the gate comes from .agents/slop/elf_oracle.py, which CALLS
# tinygrad's own elf.py.
#
#     python3 .agents/slop/elfbuild.py > tinybendygrad/runtime/support/elf.bend
#
# THE ONE THING THIS SCRIPT ENCODES CORRECTLY IS `List.append`. MEASURED, and
# getting it wrong cost the whole first attempt:
#
#   `List.append(&2, U32, xs, ys)` is `xs ++ ys`.
#   probeE:  go(...)  front-pushes -> [0,1,2,3];  List.reverse -> [3,2,1,0].
#
# So a walk that APPENDS in visit order must write `List.append(.., acc, [x])`
# and NOT reverse; a walk that PREPENDS must write `List.append(.., [x], acc)`
# and NOT reverse either -- both compose, and a reverse on top of an append
# double-reverses. The walks below say which one each is.

import sys, os

HERE = os.path.dirname(os.path.abspath(__file__))
FIX = os.path.join(HERE, "elf")

FIXTURES = [
    ("e64.o",       "B_E64_O",   "ELF64 x86-64,  12 sections, SHT_RELA"),
    ("ea64.o",      "B_EA64_O",  "ELF64 aarch64,  11 sections, SHT_RELA"),
    ("e32.o",       "B_E32_O",   "ELF32 i386,     12 sections, SHT_REL"),
    ("n64.o",       "B_N64_O",   "ELF64 x86-64,  15 sections, .rodata/.data/msg"),
    ("na64.o",      "B_NA64_O",  "ELF64 aarch64,  14 sections, 10 relocations"),
    ("n32.o",       "B_N32_O",   "ELF32 i386,     15 sections, 9 relocations"),
    ("j_aarch64.o", "B_JA64_O",  "ELF64 aarch64, THE ONE jit_loader SUCCEEDS on"),
]
REFUSERS = [
    ("r64.so",   "B_R64_SO",   "a real .so -- `.rela.dyn` -> `.dyn` -> StopIteration"),
    ("rx64.exe", "B_RX64_EXE", "a real exe -- symbol names out of the WRONG strtab"),
]

def blobs():
    out = []
    for fn, bn, note in FIXTURES + REFUSERS:
        path = os.path.join(FIX, fn)
        raw = open(path, "rb").read()
        h = raw.hex()
        parts = [h[i:i+110] for i in range(0, len(h), 110)] or [""]
        out.append(f"# {fn} -- {len(raw)} bytes, {note}")
        out.append(f"def {bn}() -> String:")
        out.append("  String.concat([")
        for p in parts:
            out.append(f'    "{p}",')
        out.append('    ""])')
        out.append("")
    return "\n".join(out)

PROLOGUE = open(os.path.join(HERE, "elf_prologue.bend")).read()

sys.stdout.write(PROLOGUE)
sys.stdout.write(blobs())
sys.stdout.write(open(os.path.join(HERE, "elf_main.bend")).read())