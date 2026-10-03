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

# THE PATCHED FIXTURES. `j_aarch64.o` with EVERY `.rela.text` entry's `r_type`
# set to one relocation type and its `r_addend` set to 0 (`near`) or 2**31
# (`far`), written out by `.agents/slop/elf_reloc_probe.py`. They exist because
# `relocate` is a CLOSURE over `image` and is only ever reached THROUGH
# `jit_loader:85`, so the only way to measure one arm is to give the real
# `jit_loader` a real object file that carries that arm. Everything else in these
# files -- the header, the section table, the symtab, the other relocation fields
# -- is clang/ld.lld's, and the two patched fields are named in the row names
# beside them.
#
# WHY `far` EXISTS AND IS NOT OPTIONAL. On the unmodified fixture the x86-64
# `R_X86_64_PC32` and `R_X86_64_PLT32` arms produce the SAME four bytes, because
# both take their in-range path when `tgt - ploc` fits in a signed 32-bit word, and
# NEITHER trampoline is reached. Setting `r_addend` to 2**31 pushes
# `tgt + r_addend` (elf.py:85) past 2**31 and takes the trampoline arm: MEASURED,
# the `far` image is 232 bytes against the `near` image's 204, and 232 - 204 is
# two 14-byte x86 trampolines.
ARMS = ["R_X86_64_PC32", "R_X86_64_PLT32", "R_AARCH64_ADR_PREL_PG_HI21",
        "R_AARCH64_ADD_ABS_LO12_NC", "R_AARCH64_LDST16_ABS_LO12_NC",
        "R_AARCH64_LDST32_ABS_LO12_NC", "R_AARCH64_LDST64_ABS_LO12_NC",
        "R_AARCH64_LDST128_ABS_LO12_NC", "R_AARCH64_CALL26"]
PATCHED = [(f"jt_{a}_{l}.o", f"B_JT_{a}_{l.upper()}",
            f"j_aarch64.o with every .rela.text r_type={a}, r_addend={'2**31' if l=='far' else '0'}")
           for a in ARMS for l in ("near", "far")]
PATCHED += [(f"jt_none_at_{k}.o", f"B_JT_NONE_AT_{k}",
             f"j_aarch64.o with entry {k}'s r_type neutralised and the rest kept")
            for k in range(4)]

# THE LINK TABLES, MEASURED NOT TRANSCRIBED. `getattr(ctypes.CDLL(path), name)`
# on the four real dylibs, and the answer is written here as a `Link` per library
# carrying the symbols it really exports. So `elf_ls_*` gates the port's SCAN over
# real data; a table invented by the port author would only prove the port agrees
# with itself.
#
# THE ROWS THAT MATTER MOST: `sel_registerName` and `objc_msgSend` are in libobjc
# ONLY, and `runtime/ops_cpu.py:19/21` builds `link_libs=[libm, rt_lib]` without
# it -- so `elf_ls_pair_sel_registerName` is 0 and `elf_ls_trio_sel_registerName`
# is 3. That is DEFECT 3, reported not fixed, because the fix is in ops_cpu.py.
LS_SYMS = ["sel_registerName", "objc_msgSend", "sin", "cos", "sqrt", "malloc", "memcpy",
           "ext_fn", "ext_data", "definitely_not_a_symbol"]
LS_LIBS = [("libm", "/usr/lib/libm.dylib"), ("rt", "/usr/lib/libSystem.dylib"),
           ("objc", "/usr/lib/libobjc.dylib"), ("stub", os.path.join(FIX, "libstub.dylib"))]

def ls_syms():
    import ctypes
    out = []
    for nm, path in LS_LIBS:
        lib = ctypes.CDLL(path)
        syms = []
        for s in LS_SYMS:
            try:
                getattr(lib, s)
                syms.append(s)
            except (OSError, AttributeError):
                pass
        bn = "LIBS_" + {"libm": "M", "rt": "RT", "objc": "OBJC", "stub": "STUB"}[nm]
        out.append(f"# {path} -- exports {len(syms)} of the {len(LS_SYMS)} probed names")
        out.extend(f"def {bn}_SYM{i}() -> String: \"{t}\"" for i, t in enumerate(syms))
        out.append(f"def {bn}() -> Link:")
        out.append(f"  Link.of(\"{nm}\", [{', '.join(f'{bn}_SYM{i}()' for i in range(len(syms)))}])")
        out.append("")
    out.append("# THE TWO LIBRARY LISTS. `ops_cpu.py:19/21` builds the PAIR and cannot")
    out.append("# reach libobjc; the TRIO is the one-line fix, measured above.")
    out.append("def ALL_LIBS() -> List<&2, Link>: [LIBS_M(), LIBS_RT(), LIBS_OBJC(), LIBS_STUB()]")
    out.append("def CPU_PAIR() -> List<&2, Link>: [LIBS_M(), LIBS_RT()]")
    out.append("def CPU_TRIO() -> List<&2, Link>: [LIBS_M(), LIBS_RT(), LIBS_OBJC()]")
    out.append("")
    return "\n".join(out)

def blobs():
    out = []
    for fn, bn, note in FIXTURES + REFUSERS + PATCHED:
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
sys.stdout.write(ls_syms())
sys.stdout.write(blobs())
sys.stdout.write(open(os.path.join(HERE, "elf_main.bend")).read())