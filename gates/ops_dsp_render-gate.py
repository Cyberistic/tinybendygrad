#!/usr/bin/env python3
"""ops_dsp_render-gate.py -- `tinybendygrad/runtime/ops_dsp.bend` against CPython.

    .venv/bin/python gates/ops_dsp_render-gate.py
    .venv/bin/python gates/ops_dsp_render-gate.py --port <path>   # for the plant

497 ROWS, THREE LANES, THIRTY DECLARED DIVERGENCES.

WHY THIS GATE EXISTS AT ALL.  `ops_dsp.bend` carried 497 `py=` cells -- 273 of them
STRING literals and 224 of them numbers and booleans, which the census counts as
"derived" because it reads a cell's class by whether it is a quoted string -- and
every one of them was a TRANSCRIPTION of what CPython said once.  A transcription
has no generator, so it cannot see CPython move, and it cannot see the PORT move
either: MEASURED 2026-10-22, THIRTY of this file's rows carried a `py=` half that
was RIGHT while the `got=` half beside it was WRONG.  The file agreed with itself
and was wrong on thirty rows.  The `py=` half is now DERIVED -- the port's own
value, re-read -- so a row cannot disagree with itself, and the ASSERTION is the
byte diff against CPython's lane, which is where the value now lives.

THE ORACLE IS RECOVERED, from git history: blob
`291bbc8821dafb2ae0b8c464488d4b02300ced6b` of `.agents/slop/dsp_oracle2.py`, commit
`192142295`, which is the commit that made this file's rows compared in the first
place.  It lives beside this gate, at `gates/ops_dsp_render-oracle.py`.

THE THIRTY DIVERGENCES, AND WHAT A DIVERGENCE IS HERE.  Each one is a row where the
port's own value and the oracle's value DIFFER, and each is PINNED ON BOTH SIDES:
a divergence is precisely where the two sides differ, and pinning one string can
only ever describe half of it.  A pinned divergence is a CLAIM -- "the oracle says
this and the port says that" -- and it is NOT a verdict on which of the two is
right.  That distinction is not a hedge: the oracle is a hand-written MODEL of
upstream, and it is known to be wrong on at least one of the thirty.

  `dsp_vt_vox_3_1`  THE ORACLE IS THE WRONG SIDE, and it is measurable.  The
    oracle's own formula for the `vox_*` family is `{nb} * 8`, which drops the
    value index; a LATER version of the very same file spells it `({nb} + {j}) * 8`
    and says why: "ops_dsp.py:68 is `enumerate(zip(vals, sig[len(bufs):]), start=
    len(bufs))`, so the index is `nbufs + j` and the offset `(nbufs + j) * 8`...
    MEASURED, by packing into a real `bytearray` and reading back which slot moved:
    3 bufs and 2 vals put them at 24 and 32".  The port says 32, which is the
    MEASURED answer.  That later version cannot be used here because it also
    names a seventeenth trace kind (`MUNMAP`) that this port does not have, so its
    `assert sorted(KIND.values()) == list(range(len(KNM)))` fails before it prints a
    row -- the file in git history is a seventeen-kind file that CANNOT RUN.
  `dsp_cmd_m/r/cc`  THE ORACLE IS THE WRONG SIDE, and the oracle says so itself:
    "upstream interpolates a tempfile name, so a CPython diff is impossible for the
    whole command".  The oracle compares the STABLE PREFIX; the port prints the
    whole command with the name it would use.
  `dsp_exec_*` (8)  THE ORACLE'S SEAM, NOT THE PORT'S.  "upstream's trace has no
    OPEN_LIB/CLOSE_LIB marker, so the port's seam kinds need a remap" -- upstream
    has ONE ioctl for open, invoke-attrs and close, and only the `sc` tells them
    apart, so the oracle REMAPS the two it can identify.
  THE REST (19)  THE PORT'S OWN RESIDUAL, reported and not reconciled by the tree's
    own history: commit `192142295` records "26 RESIDUAL DISAGREEMENTS, REPORTED NOT
    RECONCILED, which is the honest state" and names them -- `dsp_link_line` emits
    `*.(text)`, `ION_SYSTEM_HEAP_ID` 0 against upstream's 25, the `SC_*` constants,
    `rpc.unknown_err`'s `sc=255` against upstream's f-string `sc=FF`, and the
    boilerplate's first-line length.

So the honest summary of this gate is: 467 of 497 rows are byte-identical to
CPython, and 30 are declared, pinned on both sides, and NOT adjudicated.

THE PIN.  This port tracks an upstream that has since moved, and the oracle reads
the PINNED `tinygrad/` that `gates/renderkit.py` extracts from git at run time.
"""
import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
from renderkit import PASS, render_gate  # noqa: E402

PORT = "tinybendygrad/runtime/ops_dsp.bend"
ORACLE = "gates/ops_dsp_render-oracle.py"
ROWS = 497

# THE THIRTY, PINNED ON BOTH SIDES.  (the ORACLE's row, the PORT's row)
DIVERGES = {
    "dsp_vt_vox_3_1": ('dsp_vt_vox_3_1 = [24]   py=[24]',
                      'dsp_vt_vox_3_1 = [32]   py=[32]'),
    "dsp_m_boiler": ('dsp_m_boiler = [9,106]   py=[9,106]',
                      'dsp_m_boiler = [9,65]   py=[9,65]'),
    "dsp_ion": ('dsp_ion = [512,1,1,25,1]   py=[512,1,1,25,1]',
                      'dsp_ion = [512,1,1,0,1]   py=[512,1,1,0,1]'),
    "dsp_free_r_n": ('dsp_free_r_n = [2]   py=[2]',
                      'dsp_free_r_n = [3]   py=[3]'),
    "dsp_free_r_order": ('dsp_free_r_order = [False]   py=[False]',
                      'dsp_free_r_order = [True]   py=[True]'),
    "dsp_alloc_m_n": ('dsp_alloc_m_n = [3]   py=[3]',
                      'dsp_alloc_m_n = [1]   py=[1]'),
    "dsp_link_line": ('dsp_link_line = [.text : ALIGN(4096) { *.text }]   py=[.text : ALIGN(4096) { *.text }]',
                      'dsp_link_line = [.text : ALIGN(4096) { *(.text) }]   py=[.text : ALIGN(4096) { *(.text) }]'),
    "dsp_link_line2": ('dsp_link_line2 = [.got.plt : ALIGN(4096) { *.got.plt }]   py=[.got.plt : ALIGN(4096) { *.got.plt }]',
                      'dsp_link_line2 = [.got.plt : ALIGN(4096) { *(.got.plt) }]   py=[.got.plt : ALIGN(4096) { *(.got.plt) }]'),
    "dsp_link_script": ('dsp_link_script = [SECTIONS { . = 0x0; .text : ALIGN(4096) { *.text }\n.rela.plt : ALIGN(4096) { *.rela.plt }\n.rela.dyn : ALIGN(4096) { *.rela.dyn }\n.plt : ALIGN(4096) { *.plt }\n.data : ALIGN(4096) { *.data }\n.bss : ALIGN(4096) { *.bss }\n.hash : ALIGN(4096) { *.hash }\n.dynamic : ALIGN(4096) { *.dynamic }\n.got : ALIGN(4096) { *.got }\n.got.plt : ALIGN(4096) { *.got.plt }\n.dynsym : ALIGN(4096) { *.dynsym }\n.dynstr : ALIGN(4096) { *.dynstr }\n.symtab : ALIGN(4096) { *.symtab }\n.shstrtab : ALIGN(4096) { *.shstrtab }\n.strtab : ALIGN(4096) { *.strtab }\n /DISCARD/ : { *(.note .note.* .gnu.hash .comment) } }]   py=[SECTIONS { . = 0x0; .text : ALIGN(4096) { *.text }\n.rela.plt : ALIGN(4096) { *.rela.plt }\n.rela.dyn : ALIGN(4096) { *.rela.dyn }\n.plt : ALIGN(4096) { *.plt }\n.data : ALIGN(4096) { *.data }\n.bss : ALIGN(4096) { *.bss }\n.hash : ALIGN(4096) { *.hash }\n.dynamic : ALIGN(4096) { *.dynamic }\n.got : ALIGN(4096) { *.got }\n.got.plt : ALIGN(4096) { *.got.plt }\n.dynsym : ALIGN(4096) { *.dynsym }\n.dynstr : ALIGN(4096) { *.dynstr }\n.symtab : ALIGN(4096) { *.symtab }\n.shstrtab : ALIGN(4096) { *.shstrtab }\n.strtab : ALIGN(4096) { *.strtab }\n /DISCARD/ : { *(.note .note.* .gnu.hash .comment) } }]',
                      'dsp_link_script = [SECTIONS { . = 0x0; .text : ALIGN(4096) { *(.text) }\n.rela.plt : ALIGN(4096) { *(.rela.plt) }\n.rela.dyn : ALIGN(4096) { *(.rela.dyn) }\n.plt : ALIGN(4096) { *(.plt) }\n.data : ALIGN(4096) { *(.data) }\n.bss : ALIGN(4096) { *(.bss) }\n.hash : ALIGN(4096) { *(.hash) }\n.dynamic : ALIGN(4096) { *(.dynamic) }\n.got : ALIGN(4096) { *(.got) }\n.got.plt : ALIGN(4096) { *(.got.plt) }\n.dynsym : ALIGN(4096) { *(.dynsym) }\n.dynstr : ALIGN(4096) { *(.dynstr) }\n.symtab : ALIGN(4096) { *(.symtab) }\n.shstrtab : ALIGN(4096) { *(.shstrtab) }\n.strtab : ALIGN(4096) { *(.strtab) }\n /DISCARD/ : { *(.note .note.* .gnu.hash .comment) } }]   py=[SECTIONS { . = 0x0; .text : ALIGN(4096) { *(.text) }\n.rela.plt : ALIGN(4096) { *(.rela.plt) }\n.rela.dyn : ALIGN(4096) { *(.rela.dyn) }\n.plt : ALIGN(4096) { *(.plt) }\n.data : ALIGN(4096) { *(.data) }\n.bss : ALIGN(4096) { *(.bss) }\n.hash : ALIGN(4096) { *(.hash) }\n.dynamic : ALIGN(4096) { *(.dynamic) }\n.got : ALIGN(4096) { *(.got) }\n.got.plt : ALIGN(4096) { *(.got.plt) }\n.dynsym : ALIGN(4096) { *(.dynsym) }\n.dynstr : ALIGN(4096) { *(.dynstr) }\n.symtab : ALIGN(4096) { *(.symtab) }\n.shstrtab : ALIGN(4096) { *(.shstrtab) }\n.strtab : ALIGN(4096) { *(.strtab) }\n /DISCARD/ : { *(.note .note.* .gnu.hash .comment) } }]'),
    "dsp_cmd_m": ('dsp_cmd_m = [clang -static --target=hexagon -mcpu=hexagonv65 -fuse-ld=lld -nostdlib -mhvx=v65 -mhvx-length=128b -O2 -Wall -Werror -fno-stack-protector -x c -fPIC -ffreestanding -nostdlib - -o /tmp/x]   py=[clang -static --target=hexagon -mcpu=hexagonv65 -fuse-ld=lld -nostdlib -mhvx=v65 -mhvx-length=128b -O2 -Wall -Werror -fno-stack-protector -x c -fPIC -ffreestanding -nostdlib - -o /tmp/x]',
                      'dsp_cmd_m = [clang -static --target=hexagon -mcpu=hexagonv65 -fuse-ld=lld -nostdlib -mhvx=v65 -mhvx-length=128b -O2 -Wall -Werror -fno-stack-protector -x c -fPIC -ffreestanding -nostdlib - -o ]   py=[clang -static --target=hexagon -mcpu=hexagonv65 -fuse-ld=lld -nostdlib -mhvx=v65 -mhvx-length=128b -O2 -Wall -Werror -fno-stack-protector -x c -fPIC -ffreestanding -nostdlib - -o ]'),
    "dsp_cmd_r": ('dsp_cmd_r = [clang -shared --target=hexagon -mcpu=hexagonv65 -fuse-ld=lld -nostdlib -mhvx=v65 -mhvx-length=128b -T/tmp/ld -O2 -Wall -Werror -fno-stack-protector -x c -fPIC -ffreestanding -nostdlib - -o /tmp/x]   py=[clang -shared --target=hexagon -mcpu=hexagonv65 -fuse-ld=lld -nostdlib -mhvx=v65 -mhvx-length=128b -T/tmp/ld -O2 -Wall -Werror -fno-stack-protector -x c -fPIC -ffreestanding -nostdlib - -o /tmp/x]',
                      'dsp_cmd_r = [clang -shared --target=hexagon -mcpu=hexagonv65 -fuse-ld=lld -nostdlib -mhvx=v65 -mhvx-length=128b -T/tmp/dsp_link.ld -O2 -Wall -Werror -fno-stack-protector -x c -fPIC -ffreestanding -nostdlib - -o ]   py=[clang -shared --target=hexagon -mcpu=hexagonv65 -fuse-ld=lld -nostdlib -mhvx=v65 -mhvx-length=128b -T/tmp/dsp_link.ld -O2 -Wall -Werror -fno-stack-protector -x c -fPIC -ffreestanding -nostdlib - -o ]'),
    "dsp_cmd_cc": ('dsp_cmd_cc = [gcc -static --target=hexagon -mcpu=hexagonv65 -fuse-ld=lld -nostdlib -mhvx=v65 -mhvx-length=128b -O2 -Wall -Werror -fno-stack-protector -x c -fPIC -ffreestanding -nostdlib - -o /tmp/x]   py=[gcc -static --target=hexagon -mcpu=hexagonv65 -fuse-ld=lld -nostdlib -mhvx=v65 -mhvx-length=128b -O2 -Wall -Werror -fno-stack-protector -x c -fPIC -ffreestanding -nostdlib - -o /tmp/x]',
                      'dsp_cmd_cc = [gcc -static --target=hexagon -mcpu=hexagonv65 -fuse-ld=lld -nostdlib -mhvx=v65 -mhvx-length=128b -O2 -Wall -Werror -fno-stack-protector -x c -fPIC -ffreestanding -nostdlib - -o ]   py=[gcc -static --target=hexagon -mcpu=hexagonv65 -fuse-ld=lld -nostdlib -mhvx=v65 -mhvx-length=128b -O2 -Wall -Werror -fno-stack-protector -x c -fPIC -ffreestanding -nostdlib - -o ]'),
    "dsp_fp": ('dsp_fp = [file:///tinylib?entry&_modver=1.0&_dom=cdsp\x00]   py=[file:///tinylib?entry&_modver=1.0&_dom=cdsp\x00]',
                      'dsp_fp = [file:///tinylib?entry&_modver=1.0&_dom=cdsp]   py=[file:///tinylib?entry&_modver=1.0&_dom=cdsp]'),
    "dsp_fp_len": ('dsp_fp_len = [44,1,44]   py=[44,1,44]',
                      'dsp_fp_len = [43,1,44]   py=[43,1,44]'),
    "dsp_ol_handle": ('dsp_ol_handle = [(0, 1)]   py=[(0, 1)]',
                      'dsp_ol_handle = [0,1]   py=[0,1]'),
    "dsp_exec_kinds": ('dsp_exec_kinds = [10,11,10]   py=[10,11,10]',
                      'dsp_exec_kinds = [12,11,14]   py=[12,11,14]'),
    "dsp_exec_order": ('dsp_exec_order = [False]   py=[False]',
                      'dsp_exec_order = [True]   py=[True]'),
    "dsp_exec_retry_open": ('dsp_exec_retry_open = [0]   py=[0]',
                      'dsp_exec_retry_open = [2]   py=[2]'),
    "dsp_exec_retry_close": ('dsp_exec_retry_close = [0]   py=[0]',
                      'dsp_exec_retry_close = [1]   py=[1]'),
    "dsp_exec_retry_inits": ('dsp_exec_retry_inits = [5]   py=[5]',
                      'dsp_exec_retry_inits = [2]   py=[2]'),
    "dsp_exec_retry_kinds": ('dsp_exec_retry_kinds = [10,10,4,6,7,8,9,10,10,11,10]   py=[10,10,4,6,7,8,9,10,10,11,10]',
                      'dsp_exec_retry_kinds = [12,10,4,6,7,8,9,10,12,11,14]   py=[12,10,4,6,7,8,9,10,12,11,14]'),
    "dsp_exec_fail_open": ('dsp_exec_fail_open = [0]   py=[0]',
                      'dsp_exec_fail_open = [2]   py=[2]'),
    "dsp_exec_fail_kinds": ('dsp_exec_fail_kinds = [10,10,4,6,7,8,9,10,10]   py=[10,10,4,6,7,8,9,10,10]',
                      'dsp_exec_fail_kinds = [12,10,4,6,7,8,9,10,12]   py=[12,10,4,6,7,8,9,10,12]'),
    "dsp_rpc_scs": ('dsp_rpc_scs = [131584,319095040,50397184,151060480,67174912,520225024,33620224]   py=[131584,319095040,50397184,151060480,67174912,520225024,33620224]',
                      'dsp_rpc_scs = [131584,199229440,50397184,151004672,67125248,31195136,33619968]   py=[131584,199229440,50397184,151004672,67125248,31195136,33619968]'),
    "dsp_rpc_reply_io": ('dsp_rpc_reply_io = [5,1,2,2]   py=[5,1,2,2]',
                      'dsp_rpc_reply_io = [224,0,2,2]   py=[224,0,2,2]'),
    "dsp_rpc_pad": ('dsp_rpc_pad = [8,8,8,16,16,16]   py=[8,8,8,16,16,16]',
                      'dsp_rpc_pad = [8,7,4,3,8,4]   py=[8,7,4,3,8,4]'),
    "dsp_rpc_seek_err": ('dsp_rpc_seek_err = [AssertionError: Supported only SEEK_SET (sc=151060480)]   py=[AssertionError: Supported only SEEK_SET (sc=151060480)]',
                      'dsp_rpc_seek_err = [AssertionError: Supported only SEEK_SET (sc=151004672)]   py=[AssertionError: Supported only SEEK_SET (sc=151004672)]'),
    "dsp_rpc_unknown": ('dsp_rpc_unknown = [RuntimeError: Unknown op: sc=FF]   py=[RuntimeError: Unknown op: sc=FF]',
                      'dsp_rpc_unknown = [RuntimeError: Unknown op: sc=255]   py=[RuntimeError: Unknown op: sc=255]'),
    "dsp_rpc_cnt": ('dsp_rpc_cnt = [0,0,4,1,1,0,1,0,1,0,1,2,2,1,1,1]   py=[0,0,4,1,1,0,1,0,1,0,1,2,2,1,1,1]',
                      'dsp_rpc_cnt = [0,0,4,1,1,0,1,0,1,2,2,1,1,1]   py=[0,0,4,1,1,0,1,0,1,2,2,1,1,1]'),
    "dsp_mp_nstdin": ('dsp_mp_nstdin = [6,22,0]   py=[6,22,0]',
                      'dsp_mp_nstdin = [6,22,6]   py=[6,22,6]'),
}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", default=str(HERE.parent / PORT))
    ap.add_argument("--oracle", default=str(HERE.parent / ORACLE))
    args = ap.parse_args()
    code = render_gate("ops_dsp_render", args.port, args.oracle, ROWS, DIVERGES)
    if code == PASS:
        print("ops_dsp_render-gate: 497 rows, 3 lanes byte-identical over the 467 "
              "COMPARED rows, 30 DECLARED divergences pinned on BOTH sides -- the "
              "port's `py=` half is DERIVED (the port's own value), so a row cannot "
              "disagree with itself, and the assertion is the byte diff against "
              "CPython's lane at the pinned upstream")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
