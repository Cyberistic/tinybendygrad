#!/usr/bin/env python3
"""MUTATION TABLE for tinybendygrad/runtime/support/usb.bend.

The harness applies ONE edit to a scratch copy, runs the INTERPRETED lane, and
diffs WHOLE `name=value` LINES -- not row NAMES. agent-core.md records a
name-comparing harness that reported 0 for all 30 mutations in one unit and 0 for
all 68 in another.

A mutation that moves NOTHING is a BLIND SPOT and is reported with a reason, not
closed with a row that encodes the bug. `0` is a REQUEST FOR A FIXTURE, not a
coverage claim (ops_nv M30); some zeros are THEOREMS and must be called theorems
(ops_amd's `floor(floor(a/b)/c) == floor(a/(b*c))`); and some are genuinely
UNFIXABLE (pc.find answers `len` on a miss and an index on a hit, so `found < len`
and `found != len` are the same predicate over every possible answer).

Usage: usb-mutate.py [id ...]     (no ids runs all)
"""
import io
import os
import re
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
BEND = os.path.join(ROOT, "tinybendygrad/runtime/support/usb.bend")
BIN = os.path.join(ROOT, "bin/bend")


def run(path):
    r = subprocess.run([BIN, path], capture_output=True, text=True)
    if r.returncode != 0:
        return None
    d = {}
    for line in r.stdout.split("\n"):
        line = line.rstrip()
        if "=" not in line or line.startswith("usb-done"):
            continue
        nm, _, v = line.partition("=")
        d[nm.strip()] = v
    return d


# (id, description, [(old, new), ...], what it is testing)
MUTATIONS = [
    ("M1", "`usb_wire`: 512 -> 0 in the first add",
     [("U32.add(U32.add(size, SENTINEL_BLOCK()), U32.sub(SLOT(), 1))",
       "U32.add(U32.add(size, 0), U32.sub(SLOT(), 1))")],
     ":253's sentinel block. Eleven fixtures, and every one of them is below SLOT so "
     "the block is what rounds them UP to a whole slot."),
    ("M2", "`usb_wire`: SLOT -> 512 in the divisor",
     [("U32.div(U32.add(U32.add(size, SENTINEL_BLOCK()), U32.sub(SLOT(), 1)), SLOT()), SLOT())",
       "U32.div(U32.add(U32.add(size, SENTINEL_BLOCK()), U32.sub(SLOT(), 1)), 512), 512)")],
     "the SLOT granularity itself, and the three fixtures at SLOT/2SLOT boundaries "
     "are the ones that separate it from 512."),
    ("M3", "`usb_sentinel`: the 0xFFFFFF mask -> 0xFFFF",
     [("U32.and(g, SENTINEL_MASK())", "U32.and(g, 65535)")],
     ":254's 24-bit mask. `usb_sentinel_0` and `usb_sentinel_max24` are the "
     "fixtures that see it; the COLLISION rows are the ones that say why 24 and "
     "not 16."),
    ("M4", "`usb_sentinel`: the 0x51 magic -> 0x50",
     [("U32.or(U32.and(g, SENTINEL_MASK()), SENTINEL_MAGIC())",
       "U32.or(U32.and(g, SENTINEL_MASK()), 1342177280)")],
     "the high byte. This is the constant the differ caught me getting wrong "
     "(1363148800), so the row set has to see a change here."),
    ("M5", "`usb_split`: `full > 1` -> `full >= 1`",
     [("Bool.pick(U32, U32.is_gt(U32.div(nbytes, win), 1), U32.div(nbytes, win), 0)",
       "Bool.pick(U32, U32.is_ge(U32.div(nbytes, win), 1), U32.div(nbytes, win), 0)")],
     ":260's `full if full > 1 else 0` -- the no-one-trip-loops rule. The "
     "`_full1` and `_full1_p1` fixtures are the boundary and they are the only "
     "ones that separate `>` from `>=`."),
    ("M6", "`usb_split`: `nranges` counts full as `full != 0` -> `tail != 0`",
     [("U32.add(Bool.to_u32(U32.is_ne(U32.div(nbytes, win), 0)),\n"
       "                Bool.to_u32(U32.is_ne(U32.mod(nbytes, win), 0)))",
       "U32.add(Bool.to_u32(U32.is_ne(U32.mod(nbytes, win), 0)),\n"
       "                Bool.to_u32(U32.is_ne(U32.div(nbytes, win), 0)))")],
     "THE ZERO, AND IT IS A THEOREM. `nranges` is a two-term SUM, so swapping the "
     "terms cannot change the value for ANY input: no fixture in any file could "
     "separate them. The rule that matters -- that both terms are `!= 0` and not "
     "`> 0` -- is held by `M25` and `M26`, which move 3 rows each."),
    ("M7", "`usb_window`: copyin and copyout share CHUNK",
     [("Bool.pick(U32, is_copyin, CHUNK(), U32.mul(2, CHUNK()))", "CHUNK()")],
     ":257's `CHUNK if host else 2*CHUNK`. The two window rows and the two "
     "split fixtures move, which is the whole point of pairing them."),
    ("M8", "`pcie_byte_en`: `<< offset` -> `<< 0`",
     [("U32.shln(U32.sub(U32.shln(1, sz), 1), U32.to_nat(offset))",
       "U32.shln(U32.sub(U32.shln(1, sz), 1), 0n)")],
     ":118's shift AMOUNT. Five of the eight fixtures use offset 0 and do not "
     "move, so this measures 3 of 8 -- a partial-zero, reported as such."),
    ("M9", "`pcie_read_mask`: `1 << (8*size)` -> `1 << size`",
     [("U32.shln(1, U32.to_nat(U32.mul(8, U32.from_nat(sz))))",
       "U32.shln(1, U32.to_nat(U32.from_nat(sz)))")],
     ":135's mask. `usb_pcie_mask_1` is a THEOREM here (8*1 - 1 == 1 - 1 is false, "
     "so it does move), and `_mask_4` is the row that sees the 1<<32 saturation."),
    ("M10", "`pcie_no_completion`: the second fast path's mask -> the first's",
     [("U32.is_eq(U32.and(fmt_type, FAST_P2_MASK()), FAST_P2_VAL())",
       "U32.is_eq(U32.and(fmt_type, FAST_P1_MASK()), FAST_P1_VAL())")],
     ":122's TWO fast paths becoming one. Only the fixtures that separate 0x30 "
     "from 0x40 can see it."),
    ("M11", "`pcie_cfg_fmt`: `int(bus > 0)` -> `1`",
     [("Bool.to_u32(U32.is_gt(bus, 0))", "1")],
     ":139's bus term. The `_b0` fixtures move and the `_b1`/`_b255` ones do not."),
    ("M12", "`pcie_cfg_addr`: `dev << 19` -> `dev << 18`",
     [("U32.shln(dev, U32.to_nat(CFG_DEV_SHIFT()))",
       "U32.shln(dev, 18n)")],
     ":140's device shift, which is 19 and not the PCI-standard 11. Only the "
     "fixtures with a non-zero device move, so this measures 2 of 10."),
    ("M13", "`pcie_cfg_addr_ok`: drop the `bus >> 8` bound",
     [("Bool.and(Bool.and(U32.is_zero(U32.shrn(byte_addr, 12n)), U32.is_zero(U32.shrn(bus, 8n))),\n"
       "           Bool.and(U32.is_zero(U32.shrn(dev, 5n)), U32.is_zero(U32.shrn(fn, 3n))))",
       "Bool.and(Bool.and(U32.is_zero(U32.shrn(byte_addr, 12n)), True{}),\n"
       "           Bool.and(U32.is_zero(U32.shrn(dev, 5n)), U32.is_zero(U32.shrn(fn, 3n))))")],
     ":138's four bounds. The `usb_cfg_rd_b256` fixture is the one that sees it."),
    ("M14", "`xdata_nchunks`: the `length == 0` guard -> `1`",
     [("Bool.pick(U32, U32.is_zero(length), 0, U32.add(U32.div(U32.sub(length, 1), m), 1))",
       "U32.add(U32.div(U32.sub(length, 1), m), 1)")],
     ":161's loop for an EMPTY read. `usb_xdata_0_nchunks` is the fixture and it "
     "is one row from `_xdata_1_nchunks`."),
    ("M15", "`scsi_padded`: 512 -> 256",
     [("U32.mul(U32.div(U32.add(n, U32.sub(SRAM_ALIGN(), 1)), SRAM_ALIGN()), SRAM_ALIGN())",
       "U32.mul(U32.div(U32.add(n, 255), 256), 256)")],
     ":172's `round_up(len(buf), 512)`. The `_511`/`_512`/`_513` fixtures are the "
     "boundary triple and all three move."),
    ("M16", "`scsi_windex`: the `<< 8` -> `<< 7`",
     [("U32.shln(U32.div(U32.add(scsi_padded(n), U32.sub(SRAM_SLOT(), 1)), SRAM_SLOT()), 8n)",
       "U32.shln(U32.div(U32.add(scsi_padded(n), U32.sub(SRAM_SLOT(), 1)), SRAM_SLOT()), 7n)")],
     ":173's slot-count shift. Only the fixtures whose padded length EXCEEDS "
     "0x4000 have a non-zero count, so this measures 3 of 11."),
    ("M17", "`copyout_second`: drop the explicit clamp (the U32-wrap bug)",
     [("Bool.pick(U32, U32.is_ge(size, CHUNK()), U32.sub(size, CHUNK()), 0)",
       "U32.max(U32.sub(size, CHUNK()), 0)")],
     "THE REGRESSION. `size - CHUNK` wraps in a U32 and `U32.max(4294967295, 0)` "
     "is 4294967295 where Python's `max(-1, 0)` is 0. The differ found this and "
     "`usb_co_chunk_m1_second` / `_wire` are the rows that hold it."),
    ("M18", "`copyout_wire`: drop the second-half sentinel term",
     [("U32.add(U32.add(size, U32.mul(Bool.to_u32(U32.is_gt(copyout_second(size), 0)),\n"
       "                                             SENTINEL_BLOCK())),\n"
       "                        U32.sub(SRAM_ALIGN(), 1))",
       "U32.add(size, U32.sub(SRAM_ALIGN(), 1))")],
     ":375's `(second > 0) ? 512 : 0`. Only the fixtures that SPILL into the "
     "second half move, which is `_chunk_p1` and `_2chunk`."),
    ("M19", "`chunk_end`: `(half + 1) * HALF` -> `half * HALF`",
     [("U32.mul(U32.add(half, 1), HALF())", "U32.mul(half, HALF())")],
     ":338. Every `chunk_rows` fixture moves because both halves share the "
     "derivation."),
    ("M20", "`chunk_sentinel_word`: `end // 4 - 1` -> `end // 4`",
     [("U32.sub(U32.div(chunk_end(half), 4), 1)", "U32.div(chunk_end(half), 4)")],
     ":344's dword index. Five fixtures, five moves -- one row per (half, wire)."),
    ("M21", "`chunk_windex`: `wire // SLOT << 8` -> `wire // SLOT << 4`",
     [("U32.shln(U32.div(wire, SLOT()), 8n)", "U32.shln(U32.div(wire, SLOT()), 4n)")],
     ":348's slot-count shift."),
    ("M22", "`table_size_word`: `+ TABLE_SIZE_OFF` -> `+ 0`",
     [("U32.add(table_addr_word(k, r), TABLE_SIZE_OFF())", "table_addr_word(k, r)")],
     ":321's `+ 8`. Both table columns move together, so the ADDRESS column is the "
     "negative case."),
    ("M23", "`off_of_index_sz`: `el_sz` -> `0`",
     [("def off_of_index_sz(+el_sz: U32) -> U32: el_sz",
       "def off_of_index_sz(+el_sz: U32) -> U32: 0")],
     ":182's integer arm's SIZE, which is `el_sz` and not the slice's extent. "
     "Only the `_int_sz` rows move and NOT the `_slice_sz` rows, which is the "
     "arm separation."),
    ("M24", "`off_of_slice_sz`: `(stop - start)` -> `(stop)`",
     [("U32.mul(U32.sub(stop, start), el_sz)", "U32.mul(stop, el_sz)")],
     ":181's slice extent. `usb_mmio_slice2_9_el4_slice_sz` moves and the "
     "`slice0_4` one does not -- the second is the boundary that separates them."),
    ("M25", "`drained_step`: `> 1` -> `> 0`",
     [("U32.is_gt(U32.and(U32.sub(need, fence), DRAIN_MOD()), 1)",
       "U32.is_gt(U32.and(U32.sub(need, fence), DRAIN_MOD()), 0)")],
     ":334's `> 1`. The `_ahead2` fixture is the boundary and the wrap fixtures "
     "are the negative case."),
    ("M26", "`drained_step`: drop the `& 0xff`",
     [("U32.and(U32.sub(need, fence), DRAIN_MOD())", "U32.sub(need, fence)")],
     "the ONE-BYTE read's reason for existing: without the mask a fence AHEAD of "
     "need wraps into the far side. `usb_drain_wrap_*` is the row set and every "
     "wrap fixture moves."),
    ("M27", "`is_remote_prefix`: `starts_with` -> `contains`",
     [("def is_remote_prefix(+tag: String, +p: String) -> Bool: String.starts_with(tag, p)",
       "def is_remote_prefix(+tag: String, +p: String) -> Bool: String.contains(tag, p)")],
     ":387's `str(p.tag).startswith((...))`. `usb_remote_xusb_host` is the negative "
     "case and it is the ONLY fixture that separates the two."),
    ("M28", "`product_ok`: the second prefix -> the first",
     [("Bool.or(String.starts_with(product, PRODUCT_OK()), String.starts_with(product, PRODUCT_OK2()))",
       "String.starts_with(product, PRODUCT_OK())")],
     ":52's `or`. `usb_prod_as2462_x_either` is the only fixture that moves."),
    ("M29", "`cpl_name`: fall back to `Completer Abort` instead of Reserved",
     [('MSG_CPL_ABORT(),\n    Bool.pick(String, U32.is_eq(cpl_status, CPL_RETRY()), MSG_CPL_RETRY(),\n'
       '      Bool.pick(String, U32.is_eq(cpl_status, CPL_UNSUP()), MSG_CPL_UNSUP(), MSG_CPL_RESERVED())))',
       'MSG_CPL_ABORT(),\n    Bool.pick(String, U32.is_eq(cpl_status, CPL_RETRY()), MSG_CPL_RETRY(),\n'
       '      Bool.pick(String, U32.is_eq(cpl_status, CPL_UNSUP()), MSG_CPL_UNSUP(), MSG_CPL_ABORT())))')],
     ":133's `.get(cpl_status, f'Reserved (0b...)')`. The five statuses with no "
     "map entry are the fixtures and the three with one are the negative case."),
    ("M30", "`reply_ok`: drop the `status == 0` test",
     [("Bool.and(Bool.and(U32.is_eq(sig, MAGIC_USBS()), U32.is_eq(rtag, tag)),\n"
       "           U32.is_zero(status))",
       "Bool.and(U32.is_eq(sig, MAGIC_USBS()), U32.is_eq(rtag, tag))")],
     ":92's three-tuple compare. `usb_reply_ok_nonzero_status` is the fixture, "
     "one row from `usb_reply_ok_exact`."),
    ("M31", "`sym_at_head`: answer the NEXT symbol instead of this one",
     [("def sym_at_head(+h0: String, +t2: List<&2, String>) -> String: h0",
       "def sym_at_head(+h0: String, +t2: List<&2, String>) -> String: head_name(t2, \"\")")],
     "THE OFF-BY-ONE THIS FILE SHIPPED FOR AN HOUR: every order row named the "
     "symbol AFTER the one it meant, every COUNT stayed right, and only the "
     "whole-string order rows plus the CPython oracle could see it. Same class, "
     "one index, same arity, same length. The edit is the whole def body "
      "because `sym_at_head` is the head-at-zero ARM lifted into its own def "
      "exactly so this edit compiles."),
    ("M32", "`usb_enum.device`: the descriptor read AFTER the ref triple",
     [("Bool.pick(Tr, hit,\n    Tr.raise(K_DEV_ADDRESS(), addr, 0, 0,\n"
       "      Tr.raise(K_BUS_NUMBER(), bus, 0, 0,\n"
       "        Tr.emit(K_REF_DEVICE(), 0, 0, 0, Tr.raise(K_GET_DESC(), 0, 0, 0, t)))),\n"
       "    Tr.raise(K_GET_DESC(), 0, 0, 0, t))",
       "Tr.raise(K_GET_DESC(), 0, 0, 0,\n"
       "    Bool.pick(Tr, hit,\n      Tr.raise(K_DEV_ADDRESS(), addr, 0, 0,\n"
       "        Tr.raise(K_BUS_NUMBER(), bus, 0, 0,\n"
       "          Tr.emit(K_REF_DEVICE(), 0, 0, 0, t))), t))")],
     ":33-35 read the descriptor BEFORE the comparison. Four order rows move, and "
     "the oracle is the AST so the direction is not a matter of taste."),
    ("M33", "`usb_open.detach`: emit the detach branch unconditionally",
     [("Bool.pick(Tr, kdrv_active,\n"
       "    Tr.raise(K_RESET_DEVICE(), 0, 0, 0,\n"
       "      Tr.raise(K_DETACH_KDRV(), USB3_IFACE(), 0, 0,\n"
       "        Tr.raise(K_KDRV_ACTIVE(), USB3_IFACE(), 0, 0, t))), t)",
       "Tr.raise(K_RESET_DEVICE(), 0, 0, 0,\n"
       "      Tr.raise(K_DETACH_KDRV(), USB3_IFACE(), 0, 0,\n"
       "        Tr.raise(K_KDRV_ACTIVE(), USB3_IFACE(), 0, 0, t)))")],
     ":55-57's `if libusb_kernel_driver_active`. The `_nodetach` order row moves "
     "and the `_detach` one does not -- and they are ONE call string apart in the "
     "output, so the negative case is right there."),
    ("M34", "`usb_open.after`: `Tr.raise` -> `Tr.emit` on the product read",
     [("Tr.raise(K_STR_ASCII(), USB3_STRING_BUF(), 0, 0,",
       "Tr.emit(K_STR_ASCII(), USB3_STRING_BUF(), 0, 0,")],
     "THE CHECKED/RAW SPLIT. If the string read cannot refuse, then "
     "`usb_open_refuse_4_product` grows to the full seven-call trace and every "
     "later ordinal shifts -- which is exactly what the four `usb_open_refuse_*` "
     "rows are for."),
    ("M35", "`Tr.sym`: the separator `,` -> `|`",
     [('  Tr.sym.go(List.length(&2, Call, Tr.calls(t)), Tr.calls(t), "", ",")',
       '  Tr.sym.go(List.length(&2, Call, Tr.calls(t)), Tr.calls(t), "", "|")')],
     "the ORDER rows' own encoding. Every order row is a whole value, so a "
     "separator that lost a call would still be a different string -- this is the "
     "check that the string is not accidentally insensitive to a dropped element."),
    ("M36", "`enum_nm`: LAST-wins -> FIRST-wins",
     [("case Ent{vv, nn} <> t: enum_nm.go(m, v, t, Bool.pick(String, U32.is_eq(vv, v), nn, hit))",
       "case Ent{vv, nn} <> t: Bool.pick(String, U32.is_eq(vv, v), nn, enum_nm.go(m, v, t, hit))")],
     "the LAST-wins rule the generated dicts have. The ONLY row in the file that "
     "sees it is `usb_synth_n_10`, because 6 is the only value that ever repeats "
     "in twenty-one tables and `LIBUSB_CLASS_IMAGE` is not a table entry at all "
     "-- a one-row fixture for a real rule, BUILT for it."),
    ("M37", "`enum_val`: LAST-wins -> FIRST-wins",
     [("case Ent{vv, nn} <> t: enum_val.go(m, nm, t, Bool.pick(U32, String.eq(nn, nm), vv, hit))",
       "case Ent{vv, nn} <> t: Bool.pick(U32, String.eq(nn, nm), vv, enum_val.go(m, nm, t, hit))")],
     "the same rule the other way, and the ONLY row that sees it is "
     "`usb_synth_v_beta`: no name repeats in the twenty-one live tables, so the "
     "fixture had to be BUILT (`E_SYNTH` carries SYNTH_BETA at 11 and 12) for the "
     "rule to be observable at all."),
    ("M38", "`F_TRANSFER`: swap `status` and `length`",
     [("fields(\"dev_handle flags endpoint type timeout status length actual_length",
       "fields(\"dev_handle flags endpoint type timeout length status actual_length")],
     "THE FIELD-ORDER MUTATION. `ops_cl`'s unit found `Sig`'s field names "
     "INVERTED and this is the same class of bug: `usb_chunk` addresses three of "
     "these by NAME, so a transposed pair writes the timeout where the status "
     "goes. The `usb_fld_*_ix` rows are the ones that see it."),
    ("M39", "`F_DEVICE_DESCRIPTOR`: swap `idVendor` and `idProduct`",
     [("fields(\"bLength bDescriptorType bcdUSB bDeviceClass bDeviceSubClass bDeviceProtocol "
       "bMaxPacketSize0 idVendor idProduct",
       "fields(\"bLength bDescriptorType bcdUSB bDeviceClass bDeviceSubClass bDeviceProtocol "
       "bMaxPacketSize0 idProduct idVendor")],
     "the two names `list_devices` compares, and the pair the comparison cannot "
     "survive being transposed: `usb_list_match_vendor_only` and "
     "`_product_only` are its negative cases."),
    ("M40", "`F_DEVICE_DESCRIPTOR`: drop `bNumConfigurations`",
     [(" iProduct iSerialNumber bNumConfigurations\")", " iProduct iSerialNumber\")")],
     "a DROPPED field. The whole-string row moves and a field COUNT would not -- "
     "which is why the field list is diffed as a string."),
    ("M41", "`CHUNK`: `HALF - 512` -> `HALF`",
     [("def CHUNK() -> U32: U32.sub(HALF(), SENTINEL_BLOCK())",
       "def CHUNK() -> U32: HALF()")],
     ":208's reserved sentinel block. This is the constant that sets HALF-DEPENDENT "
     "arithmetic everywhere, so it is the widest mutation in the file and the row "
     "count says how wide."),
    ("M42", "`CDB_SIZE`: 31 -> 37",
     [("def CDB_SIZE() -> U32: 31", "def CDB_SIZE() -> U32: 37")],
     "`struct.calcsize(\"<IIIBBB16s\")`. 37 is what a reader gets by counting 16s "
     "as four more uint32, and `usb_reply_read_len` (13) is the row that says the "
     "reply disagrees with it."),
    ("M43", "`ep_dir`: `& 128` -> `& 127`",
     [("def ep_dir(+ep: U32) -> U32: U32.and(ep, 128)", "def ep_dir(+ep: U32) -> U32: U32.and(ep, 127)")],
     "the `LIBUSB_ENDPOINT_IN` bit, which the oracle reads from the header as 128."),
    ("M44", "`pcie_cfg_addr`: drop the `fn << 16` term",
     [("U32.or(U32.shln(fn, U32.to_nat(CFG_FN_SHIFT())), U32.and(byte_addr, CFG_BA_MASK()))",
       "U32.and(byte_addr, CFG_BA_MASK())")],
     ":140's FUNCTION nibble. Only the fixtures with a non-zero fn move."),
    ("M45", "`SENTINEL_MASK`: 0xFFFFFF -> 0xFFFFFFFF",
     [("def SENTINEL_MASK() -> U32: 16777215", "def SENTINEL_MASK() -> U32: 4294967295")],
     ":254's mask width, and the row that says why 24 and not 32: the COLLISION "
     "fixture at 2^24 moves and the one at 2^23 does not."),
]


def main():
    argv = sys.argv[1:]
    # `--md PATH` writes the table the port's own tail quotes, so the counts in
    # the file are MEASURED BY THIS RUN rather than transcribed by a later hand.
    md = None
    argv = sys.argv[1:]
    while "--md" in argv:
        i = argv.index("--md")
        argv.pop(i)
        md = argv.pop(i)
    want = set(argv)
    base = run(BEND)
    if base is None:
        print("BASELINE FAILED TO RUN")
        sys.exit(2)
    print(f"baseline rows={len(base)}")
    print("| # | rows moved | what it is testing |")
    print("| --- | --- | --- |")
    out = ["| # | rows moved | the edit | what it is testing |",
           "| --- | --- | --- | --- |"]
    for mid, desc, edits, why in MUTATIONS:
        if want and mid not in want:
            continue
        src = io.open(BEND).read()
        ok = True
        for old, new in edits:
            if old not in src:
                print(f"{mid}: EDIT NOT FOUND: {old[:70]!r}")
                ok = False
                break
            src = src.replace(old, new, 1)
        if not ok:
            continue
        with tempfile.NamedTemporaryFile("w", suffix=".bend", delete=False,
                                         dir=os.path.dirname(BEND)) as f:
            f.write(src)
            tmp = f.name
        try:
            got = run(tmp)
        finally:
            os.unlink(tmp)
        if got is None:
            print(f"| {mid} | BUILD-BROKEN | {desc} |")
            out.append(f"| {mid} | BUILD-BROKEN | {desc} | {why} |")
            continue
        moved = sorted(nm for nm in set(base) | set(got)
                       if base.get(nm) != got.get(nm))
        print(f"| {mid} | {len(moved)} | {desc} |")
        print(f"|  |  | rows: {', '.join(moved[:14])}{' ...' if len(moved) > 14 else ''} |")
        print(f"|  |  | tests: {why} |")
        out.append(f"| {mid} | {len(moved)} | {desc} | {why} |")
    if md:
        io.open(md, "w").write("\n".join(out) + "\n")
        print(f"wrote {md}: {len(out) - 2} mutations")


main()