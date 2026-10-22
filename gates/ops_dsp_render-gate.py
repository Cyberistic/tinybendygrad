#!/usr/bin/env python3
"""ops_dsp_render-gate.py -- `tinybendygrad/runtime/ops_dsp.bend` against CPython.

    .venv/bin/python gates/ops_dsp_render-gate.py
    .venv/bin/python gates/ops_dsp_render-gate.py --port <path>   # for the plant

497 ROWS, THREE LANES, **NO DECLARED DIVERGENCES**: 497 COMPARED.

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
place.  It lives beside this gate, at `gates/ops_dsp_render-oracle.py`, and it has
been EDITED -- the edits are listed in ITS header, one per adjudicated row.

THE THIRTY, ADJUDICATED.  They used to be DECLARED and PINNED on both sides, which
is honest and is also a licence without a basis: a declared divergence is a
statement that "this row differs, and here is why", and nobody had said why for
these thirty.  Every one of them now has a VERDICT, and the verdict is on the
side that was wrong, with the upstream line that says so.  THE ORACLE WAS WRONG ON
23, THE PORT WAS WRONG ON 11, AND FOUR OF THE THIRTY WERE WRONG ON BOTH SIDES.
EVERY ONE OF THEM IS NOW A COMPARED ROW.

  THE PORT'S OWN RESIDUAL (7 rows), each with the upstream line:
    `dsp_m_boiler`     the boilerplate's first line is 106 characters --
                        ops_dsp.py:243 `mockdsp_boilerplate` -- and the port said 65.
    `dsp_rpc_scs`      FIVE of the seven `sc` selectors were wrong:
                        ops_dsp.py:214 `0x13050100`, :219 `0x9010000`, :225
                        `0x4010200`, :232 `0x1f020100`, :236 `0x2010100`.  The
                        port's values (0x0BE00000, 0x09002600, 0x04004000,
                        0x01DC0000, 0x02010000) are in NO upstream revision --
                        `git log --all -S` finds no such constant in
                        `tinygrad/runtime/ops_dsp.py` at all -- so the port's
                        listener never reached upstream's arms.
    `dsp_rpc_reply_io` the same cause: the row reads the ins/outs out of
                        SC_OPEN, and SC_OPEN was 0x0BE00000.
    `dsp_rpc_seek_err` the same cause: the row names SC_SEEK.
    `dsp_rpc_pad`      the port's `8 - (off mod 8)` is not upstream's expression
                        and contradicts its own comment: ops_dsp.py:201 is
                        `round_up(in_ptr + 4, 8)`, the OBJECT POINTER.  The row
                        is renamed `dsp_rpc_objptr` on both sides, because a row
                        named `pad` that asserts a pointer says one thing and
                        means another.
    `dsp_rpc_unknown`  ops_dsp.py:239 is `f"Unknown op: {sc=:X}"` -- UPPERCASE
                        hex, so 255 is `FF` -- and the port printed the decimal.
    `dsp_mp_nstdin`    `mprog.nstdin` IGNORED its `nbufs` and always summed the
                        three-buffer fixture, so `nstdin(0, 0)` answered 6 where
                        ops_dsp.py:283-286's own arithmetic says 0.

  BOTH SIDES WRONG (4 rows):
    `dsp_ion`          the port's ION_SYSTEM_HEAP_ID was 0 -- `INVALID_HEAP_ID` --
                        where `tinygrad/runtime/autogen/qcom_dsp.py`'s
                        `enum_ion_heap_ids` says `(ION_SYSTEM_HEAP_ID:=25)`, so
                        the port asked ION for the INVALID heap and its
                        `heap_id_mask` was 1<<0 instead of 1<<25; and the ORACLE's
                        row asserted `heap_id_mask = 1` while also asserting
                        `ION_SYSTEM_HEAP_ID = 25` in the same list, where
                        ops_dsp.py:81 is `heap_id_mask=1<<ION_SYSTEM_HEAP_ID`.
    `dsp_cmd_m`        ops_dsp.py:121-122 interpolates `{f.name}` and ops_dsp.py:111
    `dsp_cmd_r`        interpolates `{self.link_ld.name}` -- TWO TEMPFILE NAMES, so
    `dsp_cmd_cc`       no fixed path is upstream's.  The oracle's rows carried
                        `/tmp/x` and `/tmp/ld`, and the port's carried an empty
                        `-o` and a `/tmp/dsp_link.ld` the port never creates.  Both
                        sides now carry `<TMP>` in the slot, and the oracle CHECKS
                        its transcription against upstream's own source.

  THE ORACLE'S OWN SEAM (19 rows), with the upstream line:
    `dsp_vt_vox_3_1`   the formula was `{nb} * 8`, which DROPS the value index.
                        ops_dsp.py:68 is `for i,(v,(_,_,dt,_)) in enumerate(zip(vals,
                        self.signature[len(bufs):]), start=len(bufs)):
                        struct.pack_into(unwrap(dt.fmt), var_vals_mv, i*8, v)` --
                        `i` STARTS AT `len(bufs)`, so the offset is `(nbufs + j) * 8`.
                        The four `j == 0` fixtures cannot see the difference and
                        `vox_3_1` can.  A LATER VERSION OF THIS VERY FILE spells it
                        `({nb} + {j}) * 8` and says why.
    `dsp_link_line`    the formula dropped the parentheses: ops_dsp.py:106 is
    `dsp_link_line2`   `f'.{n} : ALIGN(4096) {{ *(.{n}) }}'`, an input-section
    `dsp_link_script`  pattern, and not `*.{n}`.
    `dsp_fp`           the row asserted the NUL-BEARING string and ops_dsp.py:143
    `dsp_fp_len`       is `fp = "file:///tinylib?entry&_modver=1.0&_dom=cdsp\0"`
                        -- a NAME and a TERMINATOR, and the port's `String` cannot
                        hold a NUL, so the two sides were asserting different
                        claims.  Both now assert the NAME and the three lengths.
    `dsp_ol_handle`    the row was the LITERAL `"0,1"`, which `str()` prints as
                        the TUPLE `(0, 1)` -- a different SHAPE from the lane's
                        list.  It is derived from the real `open_lib` call now.
    `dsp_exec_*` (8)   `_install` recorded EVERY `FASTRPC_IOCTL_INVOKE` as
                        RPC_INVOKE, so the trace could not say OPEN from CLOSE.
                        ops_dsp.py:146 is `sc=rpc_sc(method=0, ins=2, outs=2)` and
                        ops_dsp.py:152 is `sc=rpc_sc(method=1, ins=1, outs=2)`, and
                        those two `sc`s are how upstream tells them apart -- there
                        is ONE ioctl for open, invoke-attrs and close.  The remap
                        the gate's prose claimed and the code did not do is now
                        done.
    `dsp_free_r_n`     the `os.close` fake recorded only the three descriptors
    `dsp_free_r_order` the harness knew about, so upstream's `os.close(
                        storage.buf.share_info.fd)` (ops_dsp.py:90) was SWALLOWED.
    `dsp_alloc_m_n`    `_alloc(mock=True)` never set `MOCKDSP`, so the "mock"
                        fixture took the REAL arm (ops_dsp.py:79) and counted the
                        real arm's three calls.
    `dsp_rpc_cnt`      the row was a HAND-LISTED literal of sixteen numbers, and
                        it had EIGHT arms where upstream's chain (ops_dsp.py:213
                        -238) has SEVEN.  It is GENERATED from that chain now.

THE PIN.  This port tracks an upstream that has since moved, and the oracle reads
the PINNED `tinygrad/` that `gates/renderkit.py` extracts from git at run time.
THE RE-PIN WAS MEASURED AND IT IS NOT THE FIX: re-pinning to the tree's HEAD
(`a741a469f`, upstream 002630241) moves TWO of the 497 rows -- `dsp_e_ag_off1` and
`dsp_e_ag_mm2`, because upstream PR #18649 changed the `off`/`mmap` index from
the PARAM index to a compacted GLOBAL counter -- and it fixes NONE of the thirty,
because the `vox_*` bug was in the ORACLE'S FORMULA and not in upstream.  So the
re-pin is a TWO-ROW TRADE FOR ZERO FIXES, the port would have to change its index
semantics to take it, and the honest shape is to fix the oracle's formula and
KEEP the pin.  A per-row-set pin -- a list of the rows that differ -- is the
SECOND COPY OF THE ANSWER the pin exists to avoid, and it would have to be
re-derived by hand every time upstream moved.
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

# NO DECLARED DIVERGENCES.  The thirty this gate used to declare are ADJUDICATED:
# every one of them has a verdict (the port's or the oracle's, and four were both)
# and is now a COMPARED row.  A declaration is a CLAIM -- "these two sides differ
# here" -- and a claim can go stale, so `renderkit` REFUSES a declaration whose
# two sides are the same row instead of excluding it from the diff.  See the
# header for the verdicts and the upstream line behind each one.
DIVERGES = {}


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", default=str(HERE.parent / PORT))
    ap.add_argument("--oracle", default=str(HERE.parent / ORACLE))
    args = ap.parse_args()
    code = render_gate("ops_dsp_render", args.port, args.oracle, ROWS, DIVERGES)
    if code == PASS:
        # THE COUNTS ARE DERIVED, not written down: a gate that compares 467
        # instead of 497 is a gate that MEASURED LESS, and that has to be
        # visible in the gate's own line.
        print(f"ops_dsp_render-gate: {ROWS} rows, 3 lanes byte-identical over "
              f"{ROWS - len(DIVERGES)} COMPARED rows, {len(DIVERGES)} DECLARED "
              f"divergences -- the thirty this gate used to declare are "
              f"ADJUDICATED (23 the oracle's, 11 the port's, four both), and a "
              f"declaration that goes stale is REFUSED, not trusted")
    return code


if __name__ == "__main__":
    raise SystemExit(main())
