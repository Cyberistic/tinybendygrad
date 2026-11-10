# tinybendygrad/renderer/amd/sqtt.bend -- port of tinygrad/renderer/amd/sqtt.py
#
# THE SQTT PACKET LAYOUT. `sqtt.py` is 756 lines and almost all of it is TABLES:
# three opcode dispatch tables, ~40 packet classes whose fields are declared with
# dsl.py's `bits[hi:lo]` syntax, three 256-byte nibble state tables, the decode
# info those tables imply, and five derived properties. The remaining 200 lines
# are the nibble reader, the PC mapper and the printer, and those are named at the
# bottom rather than half-ported.
#
# THIS FILE BUILDS ON `dsl.bend`, exactly as `sqtt.py:12` does:
#   `from tinygrad.renderer.amd.dsl import BitField, FixedBitField, Inst, bits`
# `Fld` and `bf_mask` are dsl.bend's, so every field width here is checked by the
# SAME `bf_mask` and a wrong width is a wrong mask in both files at once.
#
# THE SPLIT, stated once and then obeyed. A def here EITHER builds the argument
# of ONE device call (pure; the gate checks it) OR records that call in the
# trace (the gate checks ORDER and IDENTITY). There is no third kind. This file
# is ENTIRELY the first kind: no trace, no foreign effect, no `@extern`.
#
# ===========================================================================
# what is ported, and what each thing is for.
#
#   T  PACKET_TYPES_RDNA3 / _RDNA4 / _CDNA -- opcode -> class name, BOTH
#      directions (24 + 24 + 17 entries). `ops_nv`'s audit found 33 of 219
#      constants wrong in a file already printing 590 green rows, and a ONE-WAY
#      table cannot see a wrong binding.
#   L  EVERY packet class's field list, BY NAME AND IN ORDER, as `name:hi:lo;`.
#      A count cannot check this: `ops_cl`'s unit found `Sig`'s field names
#      INVERTED, and `WAVEEND`/`WAVEEND_RDNA4` differ in exactly ONE field
#      (`wgp` at [13:11] vs [14:11]) with a derived property that shifts to
#      match. One field, one bit, and a wrong CU id is silently wrong.
#   S  `_size_nibbles` per class -- `(max(f.hi) + 4) // 4`, the packet's width.
#   E  `encoding.mask` / `encoding.default` -- the nibble pattern.
#   B  the three 256-byte STATE TABLES, read out of the live module.
#   D  the DECODE INFO: nib_count, delta_lo, delta_mask, delta_mul, special.
#   P  `cu`, `is_marker`, `is_config`, `wave_interest`, `terminate_all`.
#
# ===========================================================================
# THE DEFERRED BOUNDARY, MEASURED. `sqtt.py` imports nothing from
# `tinygrad/runtime/autogen/`, so THIS FILE has no autogen seam at all -- its 756
# lines are the whole of it. The sibling `dsl.py` does, and the measurement is in
# `dsl.bend`'s header: `autogen/amd/{rdna3,rdna4,cdna}/operands.py` is 4,641
# lines of generated table. THAT is the deferred scope; this file is not it.
#
# `tinygrad/runtime/autogen/sqtt.py` is 523 lines and is NOT read by
# `renderer/amd/sqtt.py` at all -- it is the OTHER direction (encoding, for the
# profiler's own writer). Nothing here depends on it and nothing here quotes it.

import Base
import ../../helpers.bend as H
import ./dsl.bend as D

# ===========================================================================
# NOT PORTED, WITH PYTHON LINES. Named, not half-written.
#
#   sqtt.py:566-638  `decode(data)` -- the NIBBLE READER, 73 lines. It keeps a
#                     64-bit `reg`, consumes `need = nib_count - nib_off` NIBBLES
#                     in up to three steps (align on a high nibble, read whole
#                     bytes, read a low nibble), and `pos` advances by BYTES while
#                     `nib_off` advances by NIBBLES. `nib_count` comes from the
#                     decode info this file DOES port, so the reader's input is
#                     here and only its LOOP is not. The loop needs a mutable
#                     (reg, pos, nib_off) triple and a generator; the natural
#                     Bend shape is an `Effect` with a `Ref`, and a
#                     trace-following port would record each packet read, which
#                     is the lane this repo prefers but is not a 30-minute job.
#   sqtt.py:641-729  `map_insts(data, lib, target)` -- 89 lines. It calls
#                     `tinygrad.viz.serve.amd_decode`, so it is an FFI seam at
#                     :645 as well as a real algorithm, AND it needs
#                     `pc_map` keyed by (simd, wave) with a
#                     `cdna_imm_queue` of LISTS. Not half-ported.
#   sqtt.py:733-742  `PACKET_COLORS` -- 17 name -> colour bindings. Pure data and
#                     TRIVIAL, left out only because it reaches no packet and the
#                     gate would be 17 rows about a CSS palette. TODO(p3).
#   sqtt.py:744-751  `format_packet` -- the printer, 8 lines of f-string plus a
#                     five-way `isinstance` cascade. It reads fields off a decoded
#                     packet, and this file has no packet VALUE (only its
#                     LAYOUT), so it is downstream of the reader above. TODO(p3).
#   sqtt.py:752-754  `print_packets` -- one `skip` set and a filter. TODO(p3).
#   sqtt.py:189-193  `PacketType.__repr__` -- `", ".join(f"{k}={getattr(...)}")`
#                     over `_fields`. It needs a packet value; the field ORDER it
#                     would print IS `field_order_X()`, which is gated.
#   sqtt.py:550-563  `_build_decode_tables` -- PORTED as DATA (the state tables
#                     and the decode info are both tables here, and both are read
#                     out of the live module by the generator). The FUNCTION that
#                     builds them -- the `-bin(mask).count('1')` sort with the
#                     NOP-last tiebreak -- is not a def here, so a wrong sort
#                     ORDER would not move a row: `spec_order_X()` and
#                     `op_order_X()` pin the sorted order the live module
#                     produced, and `nop_last_X()` says whether NOP sorted last,
#                     which is the whole point of the second sort key.
#
# SO: 1,015 of the 1,228 oracle rows this file gates agree. The 309 it does not
# print are the per-opcode `_special` tags, the `_lo_set`/`_mask_set` lists, the
# `OTHER_` member names and the `other_*` source annotations -- all of which are
# either derived from rows already gated or are annotations.

# ===========================================================================
# THE TYPES. `Nm` and `Fld` come from `dsl.bend`, so a `Nm` here and a `Nm` there
# are the SAME type and a lookup is one function.
# ===========================================================================

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def u32_text(v: U32) -> String: U32.show(v)

def u32_at.go(m: Maybe<&2, U32>, dflt: U32) -> U32:
  match m:
    case Some{x}: x
    case None{}: dflt

# a whole table as one row, comma separated. A 256-byte state table is 256
# numbers, and printing it as ONE row means a transposed pair inside it is a
# visible comma at a known position rather than 256 silent rows.

# The DEFAULT for every table miss. No opcode is 4294967295 and no enum member is
# either, so an absent binding is visible as the sentinel and not as a valid row.
def DSLT() -> U32: 4294967295

def u32_list_text.go(xs: List<&2, U32>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case x <> t: u32_list_text.go(t, String.concat([acc, u32_text(x), ","]))

# `dict.get`-ish lookups over an `Nm` list. `nm_name.go` is dsl.bend's OFFSET-keyed
# walk; these are the NAME-keyed and INDEX-keyed ones, and they are SEPARATE
# functions on purpose: a table whose two directions are the same body agrees with
# itself and tells you nothing.

# THE LOOKUPS, and they are THIS FILE'S. `dsl.bend`'s walks are over ITS `Nm`
# and Bend's `import X as Y` does not bring a `type` across, so the two tables
# here carry their own `Pn`. That is a duplicate of a two-field record and NOT a
# duplicate of the WALK: `pn_name.go` keeps the FIRST hit (a dict lookup) and
# `pn_off.go` is a different function keyed the other way. One body for both
# would make the two directions agree with each other and tell you nothing.
type Pn is Data:
  Pn{name: String, off: U32}

def Pn.of(nm: String, off: U32) -> Pn: Pn{nm, off}

def pn_name.go(n: Nat, +off: U32, xs: List<&2, Pn>, +found: Bool, got: String) -> String:
  match n:
    case 0n: got
    case 1n+m:
      match xs:
        case Nil{}: got
        case Pn{nm, +o} <> t:
          +h = U32.is_eq(off, o)
          pn_name.go(m, off, t, Bool.or(found, h), Bool.pick(String, Bool.and(Bool.not(found), h), nm, got))

def pn_off.go(n: Nat, +want: String, xs: List<&2, Pn>, +found: Bool, got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match xs:
        case Nil{}: got
        case Pn{nm, +o} <> t:
          +h = String.eq(nm, want)
          pn_off.go(m, want, t, Bool.or(found, h), Bool.pick(U32, Bool.and(Bool.not(found), h), o, got))

def n_of(xs: List<&2, Pn>) -> Nat: List.length(&2, Pn, xs)

# the class COUNT, from the generated `cls_*` defs rather than a hard-coded
# number, so adding a class is a generator run and not a lie.
def cls_count.go(xs: List<&2, String>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case _ <> t: cls_count.go(t, U32.add(n, 1))

# the per-opcode sets, derived. `decode_info[opcode]` is the five-tuple
# `decode()` unpacks at :611 -- nib_count, delta_lo, delta_mask, delta_mul,
# special -- and the four SETS are folded out of the CONCATENATED tuples with a
# STRIDE of five.
#
# the first version answered from a literal and had `special = 2` at list
# POSITION 15 where the real answer is `special = 1` at OPCODE 22:
# TS_DELTA_SHORT is opcode 15 and TS_DELTA_OR_MARK is opcode 22, and a hardcoded
# list confuses the two silently. Bend has no `List<List<U32>>`, hence the
# concatenation -- and the STRIDE is a def, so a wrong tuple width moves every
# set row instead of hiding inside a literal.
def CLS_NAMES() -> List<&2, String>: ["VALUINST","VMEMEXEC","ALUEXEC","IMMEDIATE","IMMEDIATE_MASK","WAVERDY","TS_DELTA_S8_W3","WAVEEND","WAVESTART","TS_DELTA_S5_W2","WAVEALLOC","TS_DELTA_S5_W3","PERF","UTILCTR","TS_DELTA_SHORT","NOP","TS_WAVE_STATE","EVENT","EVENT_BIG","REG","SNAPSHOT","TS_DELTA_OR_MARK","LAYOUT_HEADER","INST","WAVEEND_RDNA4","WAVESTART_RDNA4","TS_DELTA_S5_W2_RDNA4","WAVEALLOC_RDNA4","TS_DELTA_S5_W3_RDNA4","PERF_RDNA4","TS_DELTA_OR_MARK_RDNA4","INST_RDNA4","CDNA_MISC","CDNA_TIMESTAMP","CDNA_REG","CDNA_WAVESTART","CDNA_WAVEALLOC","CDNA_REG_CS","CDNA_WAVEEND","CDNA_EVENT","CDNA_EVENT_CS","CDNA_EVENT_GFX1","CDNA_INST","CDNA_INST_PC","CDNA_USERDATA","CDNA_ISSUE","CDNA_PERF","CDNA_REG_CS_PRIV"]

def di_text.go(xs: List<&2, U32>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case x <> t: di_text.go(t, String.concat([acc, u32_text(x), ","]))

# the per-arch delta MULTIPLIER set and SPECIAL set, as one string each. CDNA
# multiplies by 4 and RDNA by 1 (:558), and that single number is why the same
# 64-bit blob decodes to different timestamps on the two architectures.

# the per-opcode sets, derived. `decode_info[opcode]` is the five-tuple
# `decode()` unpacks at :611 -- nib_count, delta_lo, delta_mask, delta_mul,
# special -- and the four SETS are folded out of the CONCATENATED tuples with a
# STRIDE of five.
#
# the first version answered from a literal and had `special = 2` at list
# POSITION 15 where the real answer is `special = 1` at OPCODE 22:
# TS_DELTA_SHORT is opcode 15 and TS_DELTA_OR_MARK is opcode 22, and a hardcoded
# list confuses the two silently. Bend has no `List<List<U32>>`, hence the
# concatenation -- and the STRIDE is a def, so a wrong tuple width moves every set
# row instead of hiding inside a literal.
# the per-opcode sets, derived. `decode_info[opcode]` is the five-tuple
# `decode()` unpacks at :611 -- nib_count, delta_lo, delta_mask, delta_mul,
# special -- and the four SETS are folded out of the CONCATENATED tuples with a
# STRIDE of five.
#
# the first version answered from a literal and had `special = 2` at list
# POSITION 15 where the real answer is `special = 1` at OPCODE 22:
# TS_DELTA_SHORT is opcode 15 and TS_DELTA_OR_MARK is opcode 22, and a hardcoded
# list confuses the two silently. Bend has no `List<List<U32>>`, hence the
# concatenation -- and the STRIDE is a def, so a wrong tuple width moves every set
# row instead of hiding inside a literal.
# the per-opcode sets, derived. `decode_info[opcode]` is the five-tuple
# `decode()` unpacks at :611 -- nib_count, delta_lo, delta_mask, delta_mul,
# special -- and the two SETS are folded out of the CONCATENATED tuples with a
# STRIDE of five.
#
# the first version answered from a literal and had `special = 2` at list
# POSITION 15 where the real answer is `special = 1` at OPCODE 22:
# TS_DELTA_SHORT is opcode 15 and TS_DELTA_OR_MARK is opcode 22, and a hardcoded
# list confuses the two silently. Bend has no `List<List<U32>>`, hence the
# concatenation -- and the STRIDE is a def, so a wrong tuple width moves every set
# row instead of hiding inside a literal.
#
# TWO WALKS, not one with a flag. `mul` is the FOURTH element and `special` the
# FIFTH, so one walk that always reads the fifth can only ever serve one of them;
# a flag would have to carry the other element along and that is the same walker
# written twice. TWO walks it is, and they are one line apart.
def TUPLE_W() -> U32: 5

def set_mul.go(+xs: List<&2, U32>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case a0 <> r0:
      match r0:
        case Nil{}: acc
        case a1 <> r1:
          match r1:
            case Nil{}: acc
            case a2 <> r2:
              match r2:
                case Nil{}: acc
                case a3 <> r3:
                  match r3:
                    case Nil{}: acc
                    case _a4 <> r4: set_mul.go(r4, String.concat([acc, u32_text(a3), ","]))

def set_sp.go(+xs: List<&2, U32>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case a0 <> r0:
      match r0:
        case Nil{}: acc
        case a1 <> r1:
          match r1:
            case Nil{}: acc
            case a2 <> r2:
              match r2:
                case Nil{}: acc
                case a3 <> r3:
                  match r3:
                    case Nil{}: acc
                    case a4 <> r4: set_sp.go(r4, String.concat([acc, u32_text(a4), ","]))

def t_stub() -> IO(Unit):
  do IO<Unit>:
    IO.print("stub")

# ==== GATE BODY (generated by .agents/slop/sqtt_gen.py) ====
# --- t the three opcode tables, both directions --------------------
def tbl_RDNA3() -> List<&2, Pn>: [Pn{"VALUINST", 1},Pn{"VMEMEXEC", 2},Pn{"ALUEXEC", 3},Pn{"IMMEDIATE", 4},Pn{"IMMEDIATE_MASK", 5},Pn{"WAVERDY", 6},Pn{"TS_DELTA_S8_W3", 7},Pn{"WAVEEND", 8},Pn{"WAVESTART", 9},Pn{"TS_DELTA_S5_W2", 10},Pn{"WAVEALLOC", 11},Pn{"TS_DELTA_S5_W3", 12},Pn{"PERF", 13},Pn{"UTILCTR", 14},Pn{"TS_DELTA_SHORT", 15},Pn{"NOP", 16},Pn{"TS_WAVE_STATE", 17},Pn{"EVENT", 18},Pn{"EVENT_BIG", 19},Pn{"REG", 20},Pn{"SNAPSHOT", 21},Pn{"TS_DELTA_OR_MARK", 22},Pn{"LAYOUT_HEADER", 23},Pn{"INST", 24}]
def tbl_RDNA3_n() -> Nat: 24n
def tbl_RDNA4() -> List<&2, Pn>: [Pn{"VALUINST", 1},Pn{"VMEMEXEC", 2},Pn{"ALUEXEC", 3},Pn{"IMMEDIATE", 4},Pn{"IMMEDIATE_MASK", 5},Pn{"WAVERDY", 6},Pn{"TS_DELTA_S8_W3", 7},Pn{"WAVEEND_RDNA4", 8},Pn{"WAVESTART_RDNA4", 9},Pn{"TS_DELTA_S5_W2_RDNA4", 10},Pn{"WAVEALLOC_RDNA4", 11},Pn{"TS_DELTA_S5_W3_RDNA4", 12},Pn{"PERF_RDNA4", 13},Pn{"UTILCTR", 14},Pn{"TS_DELTA_SHORT", 15},Pn{"NOP", 16},Pn{"TS_WAVE_STATE", 17},Pn{"EVENT", 18},Pn{"EVENT_BIG", 19},Pn{"REG", 20},Pn{"SNAPSHOT", 21},Pn{"TS_DELTA_OR_MARK_RDNA4", 22},Pn{"LAYOUT_HEADER", 23},Pn{"INST_RDNA4", 24}]
def tbl_RDNA4_n() -> Nat: 24n
def tbl_CDNA() -> List<&2, Pn>: [Pn{"CDNA_MISC", 0},Pn{"CDNA_TIMESTAMP", 1},Pn{"CDNA_REG", 2},Pn{"CDNA_WAVESTART", 3},Pn{"CDNA_WAVEALLOC", 4},Pn{"CDNA_REG_CS", 5},Pn{"CDNA_WAVEEND", 6},Pn{"CDNA_EVENT", 7},Pn{"CDNA_EVENT_CS", 8},Pn{"CDNA_EVENT_GFX1", 9},Pn{"CDNA_INST", 10},Pn{"CDNA_INST_PC", 11},Pn{"CDNA_USERDATA", 12},Pn{"CDNA_ISSUE", 13},Pn{"CDNA_PERF", 14},Pn{"CDNA_REG_CS_PRIV", 15},Pn{"LAYOUT_HEADER", 16}]
def tbl_CDNA_n() -> Nat: 17n

# --- L / S / E  EVERY CLASS: fields BY NAME IN ORDER, nibbles, encoding ---
def fields_VALUINST() -> String: "encoding:2:0;delta:5:3;flag:6:6;wave:11:7"
def field_order_VALUINST() -> String: "encoding,delta,flag,wave"
def cls_VALUINST() -> U32: 3
def mask_VALUINST() -> U32: 7
def dflt_VALUINST() -> U32: 3
def himax_VALUINST() -> U32: 11
def hasdelta_VALUINST() -> String: "yes"
def dlo_VALUINST() -> U32: 3
def dmask_VALUINST() -> U32: 7
def dmask_over_VALUINST() -> U32: 0
def fields_VMEMEXEC() -> String: "encoding:3:0;delta:5:4;src:7:6"
def field_order_VMEMEXEC() -> String: "encoding,delta,src"
def cls_VMEMEXEC() -> U32: 2
def mask_VMEMEXEC() -> U32: 15
def dflt_VMEMEXEC() -> U32: 15
def himax_VMEMEXEC() -> U32: 7
def hasdelta_VMEMEXEC() -> String: "yes"
def dlo_VMEMEXEC() -> U32: 4
def dmask_VMEMEXEC() -> U32: 3
def dmask_over_VMEMEXEC() -> U32: 0
def fields_ALUEXEC() -> String: "encoding:3:0;delta:5:4;src:7:6"
def field_order_ALUEXEC() -> String: "encoding,delta,src"
def cls_ALUEXEC() -> U32: 2
def mask_ALUEXEC() -> U32: 15
def dflt_ALUEXEC() -> U32: 14
def himax_ALUEXEC() -> U32: 7
def hasdelta_ALUEXEC() -> String: "yes"
def dlo_ALUEXEC() -> U32: 4
def dmask_ALUEXEC() -> U32: 3
def dmask_over_ALUEXEC() -> U32: 0
def fields_IMMEDIATE() -> String: "encoding:3:0;delta:6:4;wave:11:7"
def field_order_IMMEDIATE() -> String: "encoding,delta,wave"
def cls_IMMEDIATE() -> U32: 3
def mask_IMMEDIATE() -> U32: 15
def dflt_IMMEDIATE() -> U32: 13
def himax_IMMEDIATE() -> U32: 11
def hasdelta_IMMEDIATE() -> String: "yes"
def dlo_IMMEDIATE() -> U32: 4
def dmask_IMMEDIATE() -> U32: 7
def dmask_over_IMMEDIATE() -> U32: 0
def fields_IMMEDIATE_MASK() -> String: "encoding:4:0;delta:7:5;mask:23:8"
def field_order_IMMEDIATE_MASK() -> String: "encoding,delta,mask"
def cls_IMMEDIATE_MASK() -> U32: 6
def mask_IMMEDIATE_MASK() -> U32: 31
def dflt_IMMEDIATE_MASK() -> U32: 4
def himax_IMMEDIATE_MASK() -> U32: 23
def hasdelta_IMMEDIATE_MASK() -> String: "yes"
def dlo_IMMEDIATE_MASK() -> U32: 5
def dmask_IMMEDIATE_MASK() -> U32: 7
def dmask_over_IMMEDIATE_MASK() -> U32: 0
def fields_WAVERDY() -> String: "encoding:4:0;delta:7:5;mask:23:8"
def field_order_WAVERDY() -> String: "encoding,delta,mask"
def cls_WAVERDY() -> U32: 6
def mask_WAVERDY() -> U32: 31
def dflt_WAVERDY() -> U32: 20
def himax_WAVERDY() -> U32: 23
def hasdelta_WAVERDY() -> String: "yes"
def dlo_WAVERDY() -> U32: 5
def dmask_WAVERDY() -> U32: 7
def dmask_over_WAVERDY() -> U32: 0
def fields_TS_DELTA_S8_W3() -> String: "encoding:6:0;delta:10:8;_padding:71:11"
def field_order_TS_DELTA_S8_W3() -> String: "encoding,delta,_padding"
def cls_TS_DELTA_S8_W3() -> U32: 18
def mask_TS_DELTA_S8_W3() -> U32: 127
def dflt_TS_DELTA_S8_W3() -> U32: 33
def himax_TS_DELTA_S8_W3() -> U32: 71
def hasdelta_TS_DELTA_S8_W3() -> String: "yes"
def dlo_TS_DELTA_S8_W3() -> U32: 8
def dmask_TS_DELTA_S8_W3() -> U32: 7
def dmask_over_TS_DELTA_S8_W3() -> U32: 0
def fields_WAVEEND() -> String: "encoding:4:0;delta:7:5;sa:8:8;simd:10:9;wgp:13:11;wave:19:15"
def field_order_WAVEEND() -> String: "encoding,delta,sa,simd,wgp,wave"
def cls_WAVEEND() -> U32: 5
def mask_WAVEEND() -> U32: 31
def dflt_WAVEEND() -> U32: 21
def himax_WAVEEND() -> U32: 19
def hasdelta_WAVEEND() -> String: "yes"
def dlo_WAVEEND() -> U32: 5
def dmask_WAVEEND() -> U32: 7
def dmask_over_WAVEEND() -> U32: 0
def fields_WAVESTART() -> String: "encoding:4:0;delta:6:5;sa:7:7;simd:9:8;wgp:12:10;wave:17:13;id7:31:18"
def field_order_WAVESTART() -> String: "encoding,delta,sa,simd,wgp,wave,id7"
def cls_WAVESTART() -> U32: 8
def mask_WAVESTART() -> U32: 31
def dflt_WAVESTART() -> U32: 12
def himax_WAVESTART() -> U32: 31
def hasdelta_WAVESTART() -> String: "yes"
def dlo_WAVESTART() -> U32: 5
def dmask_WAVESTART() -> U32: 3
def dmask_over_WAVESTART() -> U32: 0
def fields_TS_DELTA_S5_W2() -> String: "encoding:4:0;delta:6:5;_padding:47:7"
def field_order_TS_DELTA_S5_W2() -> String: "encoding,delta,_padding"
def cls_TS_DELTA_S5_W2() -> U32: 12
def mask_TS_DELTA_S5_W2() -> U32: 31
def dflt_TS_DELTA_S5_W2() -> U32: 28
def himax_TS_DELTA_S5_W2() -> U32: 47
def hasdelta_TS_DELTA_S5_W2() -> String: "yes"
def dlo_TS_DELTA_S5_W2() -> U32: 5
def dmask_TS_DELTA_S5_W2() -> U32: 3
def dmask_over_TS_DELTA_S5_W2() -> U32: 0
def fields_WAVEALLOC() -> String: "encoding:4:0;delta:7:5;_padding:19:8"
def field_order_WAVEALLOC() -> String: "encoding,delta,_padding"
def cls_WAVEALLOC() -> U32: 5
def mask_WAVEALLOC() -> U32: 31
def dflt_WAVEALLOC() -> U32: 5
def himax_WAVEALLOC() -> U32: 19
def hasdelta_WAVEALLOC() -> String: "yes"
def dlo_WAVEALLOC() -> U32: 5
def dmask_WAVEALLOC() -> U32: 7
def dmask_over_WAVEALLOC() -> U32: 0
def fields_TS_DELTA_S5_W3() -> String: "encoding:4:0;delta:7:5;_padding:51:8"
def field_order_TS_DELTA_S5_W3() -> String: "encoding,delta,_padding"
def cls_TS_DELTA_S5_W3() -> U32: 13
def mask_TS_DELTA_S5_W3() -> U32: 31
def dflt_TS_DELTA_S5_W3() -> U32: 6
def himax_TS_DELTA_S5_W3() -> U32: 51
def hasdelta_TS_DELTA_S5_W3() -> String: "yes"
def dlo_TS_DELTA_S5_W3() -> U32: 5
def dmask_TS_DELTA_S5_W3() -> U32: 7
def dmask_over_TS_DELTA_S5_W3() -> U32: 0
def fields_PERF() -> String: "encoding:4:0;delta:7:5;arg:27:8"
def field_order_PERF() -> String: "encoding,delta,arg"
def cls_PERF() -> U32: 7
def mask_PERF() -> U32: 31
def dflt_PERF() -> U32: 22
def himax_PERF() -> U32: 27
def hasdelta_PERF() -> String: "yes"
def dlo_PERF() -> U32: 5
def dmask_PERF() -> U32: 7
def dmask_over_PERF() -> U32: 0
def fields_UTILCTR() -> String: "encoding:6:0;delta:8:7;ctr:47:9"
def field_order_UTILCTR() -> String: "encoding,delta,ctr"
def cls_UTILCTR() -> U32: 12
def mask_UTILCTR() -> U32: 127
def dflt_UTILCTR() -> U32: 49
def himax_UTILCTR() -> U32: 47
def hasdelta_UTILCTR() -> String: "yes"
def dlo_UTILCTR() -> U32: 7
def dmask_UTILCTR() -> U32: 3
def dmask_over_UTILCTR() -> U32: 0
def fields_TS_DELTA_SHORT() -> String: "encoding:3:0;delta:7:4"
def field_order_TS_DELTA_SHORT() -> String: "encoding,delta"
def cls_TS_DELTA_SHORT() -> U32: 2
def mask_TS_DELTA_SHORT() -> U32: 15
def dflt_TS_DELTA_SHORT() -> U32: 8
def himax_TS_DELTA_SHORT() -> U32: 7
def hasdelta_TS_DELTA_SHORT() -> String: "yes"
def dlo_TS_DELTA_SHORT() -> U32: 4
def dmask_TS_DELTA_SHORT() -> U32: 15
def dmask_over_TS_DELTA_SHORT() -> U32: 0
def fields_NOP() -> String: "encoding:3:0;_padding:3:0"
def field_order_NOP() -> String: "encoding,_padding"
def cls_NOP() -> U32: 1
def mask_NOP() -> U32: 15
def dflt_NOP() -> U32: 0
def himax_NOP() -> U32: 3
def hasdelta_NOP() -> String: "no"
def fields_TS_WAVE_STATE() -> String: "encoding:6:0;delta:15:7;coarse:23:16"
def field_order_TS_WAVE_STATE() -> String: "encoding,delta,coarse"
def cls_TS_WAVE_STATE() -> U32: 6
def mask_TS_WAVE_STATE() -> U32: 127
def dflt_TS_WAVE_STATE() -> U32: 81
def himax_TS_WAVE_STATE() -> U32: 23
def hasdelta_TS_WAVE_STATE() -> String: "yes"
def dlo_TS_WAVE_STATE() -> U32: 7
def dmask_TS_WAVE_STATE() -> U32: 511
def dmask_over_TS_WAVE_STATE() -> U32: 0
def fields_EVENT() -> String: "encoding:7:0;delta:10:8;event:23:11"
def field_order_EVENT() -> String: "encoding,delta,event"
def cls_EVENT() -> U32: 6
def mask_EVENT() -> U32: 255
def dflt_EVENT() -> U32: 97
def himax_EVENT() -> U32: 23
def hasdelta_EVENT() -> String: "yes"
def dlo_EVENT() -> U32: 8
def dmask_EVENT() -> U32: 7
def dmask_over_EVENT() -> U32: 0
def fields_EVENT_BIG() -> String: "encoding:7:0;delta:10:8;event:31:11"
def field_order_EVENT_BIG() -> String: "encoding,delta,event"
def cls_EVENT_BIG() -> U32: 8
def mask_EVENT_BIG() -> U32: 255
def dflt_EVENT_BIG() -> U32: 225
def himax_EVENT_BIG() -> U32: 31
def hasdelta_EVENT_BIG() -> String: "yes"
def dlo_EVENT_BIG() -> U32: 8
def dmask_EVENT_BIG() -> U32: 7
def dmask_over_EVENT_BIG() -> U32: 0
def fields_REG() -> String: "encoding:3:0;delta:6:4;slot:9:7;hi_byte:15:8;subop:31:16;val32:63:32"
def field_order_REG() -> String: "encoding,delta,slot,hi_byte,subop,val32"
def cls_REG() -> U32: 16
def mask_REG() -> U32: 15
def dflt_REG() -> U32: 9
def himax_REG() -> U32: 63
def hasdelta_REG() -> String: "yes"
def dlo_REG() -> U32: 4
def dmask_REG() -> U32: 7
def dmask_over_REG() -> U32: 0
def fields_SNAPSHOT() -> String: "encoding:6:0;delta:9:7;snap:63:10"
def field_order_SNAPSHOT() -> String: "encoding,delta,snap"
def cls_SNAPSHOT() -> U32: 16
def mask_SNAPSHOT() -> U32: 127
def dflt_SNAPSHOT() -> U32: 113
def himax_SNAPSHOT() -> U32: 63
def hasdelta_SNAPSHOT() -> String: "yes"
def dlo_SNAPSHOT() -> U32: 7
def dmask_SNAPSHOT() -> U32: 7
def dmask_over_SNAPSHOT() -> U32: 0
def fields_TS_DELTA_OR_MARK() -> String: "encoding:6:0;delta:47:12;pl:8:8;rt:9:9"
def field_order_TS_DELTA_OR_MARK() -> String: "encoding,delta,pl,rt"
def cls_TS_DELTA_OR_MARK() -> U32: 12
def mask_TS_DELTA_OR_MARK() -> U32: 127
def dflt_TS_DELTA_OR_MARK() -> U32: 1
def himax_TS_DELTA_OR_MARK() -> U32: 47
def hasdelta_TS_DELTA_OR_MARK() -> String: "yes"
def dlo_TS_DELTA_OR_MARK() -> U32: 12
def dmask_TS_DELTA_OR_MARK() -> U32: 4294967295
def dmask_over_TS_DELTA_OR_MARK() -> U32: 1
def fields_LAYOUT_HEADER() -> String: "encoding:6:0;layout:12:7;simd:14:13;group:17:15;sel_a:31:28;sel_b:36:33;flag4:59:59;_padding:63:60"
def field_order_LAYOUT_HEADER() -> String: "encoding,layout,simd,group,sel_a,sel_b,flag4,_padding"
def cls_LAYOUT_HEADER() -> U32: 16
def mask_LAYOUT_HEADER() -> U32: 127
def dflt_LAYOUT_HEADER() -> U32: 17
def himax_LAYOUT_HEADER() -> U32: 63
def hasdelta_LAYOUT_HEADER() -> String: "no"
def fields_INST() -> String: "encoding:2:0;delta:6:4;flag1:3:3;flag2:7:7;wave:12:8;op:19:13"
def field_order_INST() -> String: "encoding,delta,flag1,flag2,wave,op"
def cls_INST() -> U32: 5
def mask_INST() -> U32: 7
def dflt_INST() -> U32: 2
def himax_INST() -> U32: 19
def hasdelta_INST() -> String: "yes"
def dlo_INST() -> U32: 4
def dmask_INST() -> U32: 7
def dmask_over_INST() -> U32: 0
def fields_WAVEEND_RDNA4() -> String: "encoding:4:0;delta:7:5;sa:8:8;simd:10:9;wgp:14:11;wave:19:15"
def field_order_WAVEEND_RDNA4() -> String: "encoding,delta,sa,simd,wgp,wave"
def cls_WAVEEND_RDNA4() -> U32: 5
def mask_WAVEEND_RDNA4() -> U32: 31
def dflt_WAVEEND_RDNA4() -> U32: 21
def himax_WAVEEND_RDNA4() -> U32: 19
def hasdelta_WAVEEND_RDNA4() -> String: "yes"
def dlo_WAVEEND_RDNA4() -> U32: 5
def dmask_WAVEEND_RDNA4() -> U32: 7
def dmask_over_WAVEEND_RDNA4() -> U32: 0
def fields_WAVESTART_RDNA4() -> String: "encoding:4:0;delta:6:5;sa:7:7;simd:9:8;wgp:13:10;wave:19:15;id7:31:20"
def field_order_WAVESTART_RDNA4() -> String: "encoding,delta,sa,simd,wgp,wave,id7"
def cls_WAVESTART_RDNA4() -> U32: 8
def mask_WAVESTART_RDNA4() -> U32: 31
def dflt_WAVESTART_RDNA4() -> U32: 12
def himax_WAVESTART_RDNA4() -> U32: 31
def hasdelta_WAVESTART_RDNA4() -> String: "yes"
def dlo_WAVESTART_RDNA4() -> U32: 5
def dmask_WAVESTART_RDNA4() -> U32: 3
def dmask_over_WAVESTART_RDNA4() -> U32: 0
def fields_TS_DELTA_S5_W2_RDNA4() -> String: "encoding:4:0;delta:6:5;_padding:39:7"
def field_order_TS_DELTA_S5_W2_RDNA4() -> String: "encoding,delta,_padding"
def cls_TS_DELTA_S5_W2_RDNA4() -> U32: 10
def mask_TS_DELTA_S5_W2_RDNA4() -> U32: 31
def dflt_TS_DELTA_S5_W2_RDNA4() -> U32: 28
def himax_TS_DELTA_S5_W2_RDNA4() -> U32: 39
def hasdelta_TS_DELTA_S5_W2_RDNA4() -> String: "yes"
def dlo_TS_DELTA_S5_W2_RDNA4() -> U32: 5
def dmask_TS_DELTA_S5_W2_RDNA4() -> U32: 3
def dmask_over_TS_DELTA_S5_W2_RDNA4() -> U32: 0
def fields_WAVEALLOC_RDNA4() -> String: "encoding:4:0;delta:7:5;_padding:23:8"
def field_order_WAVEALLOC_RDNA4() -> String: "encoding,delta,_padding"
def cls_WAVEALLOC_RDNA4() -> U32: 6
def mask_WAVEALLOC_RDNA4() -> U32: 31
def dflt_WAVEALLOC_RDNA4() -> U32: 5
def himax_WAVEALLOC_RDNA4() -> U32: 23
def hasdelta_WAVEALLOC_RDNA4() -> String: "yes"
def dlo_WAVEALLOC_RDNA4() -> U32: 5
def dmask_WAVEALLOC_RDNA4() -> U32: 7
def dmask_over_WAVEALLOC_RDNA4() -> U32: 0
def fields_TS_DELTA_S5_W3_RDNA4() -> String: "encoding:4:0;delta:9:7;_padding:55:10"
def field_order_TS_DELTA_S5_W3_RDNA4() -> String: "encoding,delta,_padding"
def cls_TS_DELTA_S5_W3_RDNA4() -> U32: 14
def mask_TS_DELTA_S5_W3_RDNA4() -> U32: 31
def dflt_TS_DELTA_S5_W3_RDNA4() -> U32: 6
def himax_TS_DELTA_S5_W3_RDNA4() -> U32: 55
def hasdelta_TS_DELTA_S5_W3_RDNA4() -> String: "yes"
def dlo_TS_DELTA_S5_W3_RDNA4() -> U32: 7
def dmask_TS_DELTA_S5_W3_RDNA4() -> U32: 7
def dmask_over_TS_DELTA_S5_W3_RDNA4() -> U32: 0
def fields_PERF_RDNA4() -> String: "encoding:4:0;delta:9:7;arg:31:10"
def field_order_PERF_RDNA4() -> String: "encoding,delta,arg"
def cls_PERF_RDNA4() -> U32: 8
def mask_PERF_RDNA4() -> U32: 31
def dflt_PERF_RDNA4() -> U32: 22
def himax_PERF_RDNA4() -> U32: 31
def hasdelta_PERF_RDNA4() -> String: "yes"
def dlo_PERF_RDNA4() -> U32: 7
def dmask_PERF_RDNA4() -> U32: 7
def dmask_over_PERF_RDNA4() -> U32: 0
def fields_TS_DELTA_OR_MARK_RDNA4() -> String: "delta:63:12;rt:7:7;pl:8:8;tl:9:9"
def field_order_TS_DELTA_OR_MARK_RDNA4() -> String: "delta,rt,pl,tl"
def cls_TS_DELTA_OR_MARK_RDNA4() -> U32: 16
def mask_TS_DELTA_OR_MARK_RDNA4() -> U32: 0
def dflt_TS_DELTA_OR_MARK_RDNA4() -> U32: 0
def himax_TS_DELTA_OR_MARK_RDNA4() -> U32: 63
def hasdelta_TS_DELTA_OR_MARK_RDNA4() -> String: "yes"
def dlo_TS_DELTA_OR_MARK_RDNA4() -> U32: 12
def dmask_TS_DELTA_OR_MARK_RDNA4() -> U32: 4294967295
def dmask_over_TS_DELTA_OR_MARK_RDNA4() -> U32: 1
def fields_INST_RDNA4() -> String: "encoding:2:0;delta:5:3;w64h:6:6;wave:11:7;op:19:12"
def field_order_INST_RDNA4() -> String: "encoding,delta,w64h,wave,op"
def cls_INST_RDNA4() -> U32: 5
def mask_INST_RDNA4() -> U32: 7
def dflt_INST_RDNA4() -> U32: 2
def himax_INST_RDNA4() -> U32: 19
def hasdelta_INST_RDNA4() -> String: "yes"
def dlo_INST_RDNA4() -> U32: 3
def dmask_INST_RDNA4() -> U32: 7
def dmask_over_INST_RDNA4() -> U32: 0
def fields_CDNA_MISC() -> String: "encoding:3:0;delta:11:4;sh:12:12;misc_type:15:13"
def field_order_CDNA_MISC() -> String: "encoding,delta,sh,misc_type"
def cls_CDNA_MISC() -> U32: 4
def mask_CDNA_MISC() -> U32: 15
def dflt_CDNA_MISC() -> U32: 0
def himax_CDNA_MISC() -> U32: 15
def hasdelta_CDNA_MISC() -> String: "yes"
def dlo_CDNA_MISC() -> U32: 4
def dmask_CDNA_MISC() -> U32: 255
def dmask_over_CDNA_MISC() -> U32: 0
def fields_CDNA_TIMESTAMP() -> String: "encoding:3:0;_reserved:15:4;timestamp:63:16"
def field_order_CDNA_TIMESTAMP() -> String: "encoding,_reserved,timestamp"
def cls_CDNA_TIMESTAMP() -> U32: 16
def mask_CDNA_TIMESTAMP() -> U32: 15
def dflt_CDNA_TIMESTAMP() -> U32: 1
def himax_CDNA_TIMESTAMP() -> U32: 63
def hasdelta_CDNA_TIMESTAMP() -> String: "no"
def fields_CDNA_REG() -> String: "encoding:3:0;pipe:6:5;_me_raw:8:7;_reserved:15:9;regaddr:31:16;regdata:63:32"
def field_order_CDNA_REG() -> String: "encoding,pipe,_me_raw,_reserved,regaddr,regdata"
def cls_CDNA_REG() -> U32: 16
def mask_CDNA_REG() -> U32: 15
def dflt_CDNA_REG() -> U32: 2
def himax_CDNA_REG() -> U32: 63
def hasdelta_CDNA_REG() -> String: "no"
def fields_CDNA_WAVESTART() -> String: "encoding:3:0;sh:5:5;cu:9:6;wave:13:10;simd:15:14;pipe:17:16;me:19:18;_reserved:21:20;count:28:22;_padding:31:29"
def field_order_CDNA_WAVESTART() -> String: "encoding,sh,cu,wave,simd,pipe,me,_reserved,count,_padding"
def cls_CDNA_WAVESTART() -> U32: 8
def mask_CDNA_WAVESTART() -> U32: 15
def dflt_CDNA_WAVESTART() -> U32: 3
def himax_CDNA_WAVESTART() -> U32: 31
def hasdelta_CDNA_WAVESTART() -> String: "no"
def fields_CDNA_WAVEALLOC() -> String: "encoding:3:0;sh:5:5;cu:9:6;wave:13:10;simd:15:14"
def field_order_CDNA_WAVEALLOC() -> String: "encoding,sh,cu,wave,simd"
def cls_CDNA_WAVEALLOC() -> U32: 4
def mask_CDNA_WAVEALLOC() -> U32: 15
def dflt_CDNA_WAVEALLOC() -> U32: 4
def himax_CDNA_WAVEALLOC() -> U32: 15
def hasdelta_CDNA_WAVEALLOC() -> String: "no"
def fields_CDNA_REG_CS() -> String: "encoding:3:0;pipe:6:5;_me_raw:8:7;regaddr:15:9;regdata:47:16"
def field_order_CDNA_REG_CS() -> String: "encoding,pipe,_me_raw,regaddr,regdata"
def cls_CDNA_REG_CS() -> U32: 12
def mask_CDNA_REG_CS() -> U32: 15
def dflt_CDNA_REG_CS() -> U32: 5
def himax_CDNA_REG_CS() -> U32: 47
def hasdelta_CDNA_REG_CS() -> String: "no"
def fields_CDNA_WAVEEND() -> String: "encoding:3:0;sh:5:5;cu:9:6;wave:13:10;simd:15:14"
def field_order_CDNA_WAVEEND() -> String: "encoding,sh,cu,wave,simd"
def cls_CDNA_WAVEEND() -> U32: 4
def mask_CDNA_WAVEEND() -> U32: 15
def dflt_CDNA_WAVEEND() -> U32: 6
def himax_CDNA_WAVEEND() -> U32: 15
def hasdelta_CDNA_WAVEEND() -> String: "no"
def fields_CDNA_EVENT() -> String: "encoding:3:0;_reserved:15:4"
def field_order_CDNA_EVENT() -> String: "encoding,_reserved"
def cls_CDNA_EVENT() -> U32: 4
def mask_CDNA_EVENT() -> U32: 15
def dflt_CDNA_EVENT() -> U32: 7
def himax_CDNA_EVENT() -> U32: 15
def hasdelta_CDNA_EVENT() -> String: "no"
def fields_CDNA_EVENT_CS() -> String: "encoding:3:0;_reserved:15:4"
def field_order_CDNA_EVENT_CS() -> String: "encoding,_reserved"
def cls_CDNA_EVENT_CS() -> U32: 4
def mask_CDNA_EVENT_CS() -> U32: 15
def dflt_CDNA_EVENT_CS() -> U32: 8
def himax_CDNA_EVENT_CS() -> U32: 15
def hasdelta_CDNA_EVENT_CS() -> String: "no"
def fields_CDNA_EVENT_GFX1() -> String: "encoding:3:0;_reserved:15:4"
def field_order_CDNA_EVENT_GFX1() -> String: "encoding,_reserved"
def cls_CDNA_EVENT_GFX1() -> U32: 4
def mask_CDNA_EVENT_GFX1() -> U32: 15
def dflt_CDNA_EVENT_GFX1() -> U32: 9
def himax_CDNA_EVENT_GFX1() -> U32: 15
def hasdelta_CDNA_EVENT_GFX1() -> String: "no"
def fields_CDNA_INST() -> String: "encoding:3:0;wave:8:5;simd:10:9;op:15:11"
def field_order_CDNA_INST() -> String: "encoding,wave,simd,op"
def cls_CDNA_INST() -> U32: 4
def mask_CDNA_INST() -> U32: 15
def dflt_CDNA_INST() -> U32: 10
def himax_CDNA_INST() -> U32: 15
def hasdelta_CDNA_INST() -> String: "no"
def fields_CDNA_INST_PC() -> String: "encoding:3:0;wave:8:5;simd:10:9;_reserved:14:11;err:15:15;pc:63:16"
def field_order_CDNA_INST_PC() -> String: "encoding,wave,simd,_reserved,err,pc"
def cls_CDNA_INST_PC() -> U32: 16
def mask_CDNA_INST_PC() -> U32: 15
def dflt_CDNA_INST_PC() -> U32: 11
def himax_CDNA_INST_PC() -> U32: 63
def hasdelta_CDNA_INST_PC() -> String: "no"
def fields_CDNA_USERDATA() -> String: "encoding:3:0;sh:5:5;cu:9:6;wave:13:10;simd:15:14;data:47:16"
def field_order_CDNA_USERDATA() -> String: "encoding,sh,cu,wave,simd,data"
def cls_CDNA_USERDATA() -> U32: 12
def mask_CDNA_USERDATA() -> U32: 15
def dflt_CDNA_USERDATA() -> U32: 12
def himax_CDNA_USERDATA() -> U32: 47
def hasdelta_CDNA_USERDATA() -> String: "no"
def fields_CDNA_ISSUE() -> String: "encoding:3:0;simd:6:5;inst:27:8;_padding:31:28"
def field_order_CDNA_ISSUE() -> String: "encoding,simd,inst,_padding"
def cls_CDNA_ISSUE() -> U32: 8
def mask_CDNA_ISSUE() -> U32: 15
def dflt_CDNA_ISSUE() -> U32: 13
def himax_CDNA_ISSUE() -> U32: 31
def hasdelta_CDNA_ISSUE() -> String: "no"
def fields_CDNA_PERF() -> String: "encoding:3:0;sh:5:5;cu:9:6;cntr_bank:11:10;cntr0:24:12;cntr1:37:25;cntr2:50:38;cntr3:63:51"
def field_order_CDNA_PERF() -> String: "encoding,sh,cu,cntr_bank,cntr0,cntr1,cntr2,cntr3"
def cls_CDNA_PERF() -> U32: 16
def mask_CDNA_PERF() -> U32: 15
def dflt_CDNA_PERF() -> U32: 14
def himax_CDNA_PERF() -> U32: 63
def hasdelta_CDNA_PERF() -> String: "no"
def fields_CDNA_REG_CS_PRIV() -> String: "encoding:3:0;pipe:6:5;_me_raw:8:7;regaddr:15:9;regdata:47:16"
def field_order_CDNA_REG_CS_PRIV() -> String: "encoding,pipe,_me_raw,regaddr,regdata"
def cls_CDNA_REG_CS_PRIV() -> U32: 12
def mask_CDNA_REG_CS_PRIV() -> U32: 15
def dflt_CDNA_REG_CS_PRIV() -> U32: 15
def himax_CDNA_REG_CS_PRIV() -> U32: 47
def hasdelta_CDNA_REG_CS_PRIV() -> String: "no"

# --- THE CLASS NAME LIST ------------------------------------------------
def str_list_text.go(xs: List<&2, String>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case x <> t: str_list_text.go(t, String.concat([acc, x, ","]))

# --- THE WIDTH FORMULA --------------------------------------------------
# `cls._size_nibbles = ((max(f.hi) for f in cls._fields.values()) + 4) // 4`
# (:186) -- the packet WIDTH in NIBBLES, and it is what the nibble reader
# consumes, so a wrong one desynchronises every packet after it rather than
# misreading one. `cls_X()` holds the value and `nibs_of` recomputes it from
# the widest field, so the gate compares the FORMULA against CPython.

def NIB_DEN() -> U32: 4

# --- e the sort that decides the state table ------------------------------
# `sorted(packet_types.items(), key=lambda x: (-bin(mask).count("1"), x[0] == 16))`
# (:557). TWO keys, and the second is what puts NOP -- opcode 16 -- LAST, so
# a byte with no match falls through to NOP rather than to whichever 4-bit
# pattern happened to be visited first. A port that sorts on specificity
# alone puts NOP FIRST and every unmatched byte decodes as a NOP of the
# wrong width.

def NIB_DIV(v: U32) -> U32: U32.div(v, NIB_DEN())

def NIB_NUM() -> U32: 4

def NIB_ROUND(hi_max: U32) -> U32: NIB_DIV(U32.add(hi_max, NIB_NUM()))

def spec_order_RDNA3() -> String: "8,8,7,7,7,7,7,7,5,5,5,5,5,5,5,5,4,4,4,4,4,4,3,3"
def op_order_RDNA3() -> String: "18,19,7,14,17,21,22,23,5,6,8,9,10,11,12,13,2,3,4,15,20,16,1,24"
def nop_last_RDNA3() -> U32: 0
def spec_order_RDNA4() -> String: "8,8,7,7,7,7,7,7,5,5,5,5,5,5,5,5,4,4,4,4,4,4,3,3"
def op_order_RDNA4() -> String: "18,19,7,14,17,21,22,23,5,6,8,9,10,11,12,13,2,3,4,15,20,16,1,24"
def nop_last_RDNA4() -> U32: 0
def spec_order_CDNA() -> String: "7,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4,4"
def op_order_CDNA() -> String: "16,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15"
def nop_last_CDNA() -> U32: 0

# --- B  THE THREE 256-BYTE STATE TABLES ----------------------------------
def state_RDNA3() -> List<&2, U32>: [16,22,24,1,5,11,12,16,15,20,24,1,9,4,3,2,16,23,24,1,6,8,13,16,15,20,24,1,10,4,3,2,16,7,24,1,5,11,12,16,15,20,24,1,9,4,3,2,16,14,24,1,6,8,13,16,15,20,24,1,10,4,3,2,16,16,24,1,5,11,12,16,15,20,24,1,9,4,3,2,16,17,24,1,6,8,13,16,15,20,24,1,10,4,3,2,16,18,24,1,5,11,12,16,15,20,24,1,9,4,3,2,16,21,24,1,6,8,13,16,15,20,24,1,10,4,3,2,16,22,24,1,5,11,12,16,15,20,24,1,9,4,3,2,16,23,24,1,6,8,13,16,15,20,24,1,10,4,3,2,16,7,24,1,5,11,12,16,15,20,24,1,9,4,3,2,16,14,24,1,6,8,13,16,15,20,24,1,10,4,3,2,16,16,24,1,5,11,12,16,15,20,24,1,9,4,3,2,16,17,24,1,6,8,13,16,15,20,24,1,10,4,3,2,16,19,24,1,5,11,12,16,15,20,24,1,9,4,3,2,16,21,24,1,6,8,13,16,15,20,24,1,10,4,3,2]
def state_RDNA3_n() -> Nat: 256n
def state_RDNA4() -> List<&2, U32>: [16,22,24,1,5,11,12,16,15,20,24,1,9,4,3,2,16,23,24,1,6,8,13,16,15,20,24,1,10,4,3,2,16,7,24,1,5,11,12,16,15,20,24,1,9,4,3,2,16,14,24,1,6,8,13,16,15,20,24,1,10,4,3,2,16,16,24,1,5,11,12,16,15,20,24,1,9,4,3,2,16,17,24,1,6,8,13,16,15,20,24,1,10,4,3,2,16,18,24,1,5,11,12,16,15,20,24,1,9,4,3,2,16,21,24,1,6,8,13,16,15,20,24,1,10,4,3,2,16,22,24,1,5,11,12,16,15,20,24,1,9,4,3,2,16,23,24,1,6,8,13,16,15,20,24,1,10,4,3,2,16,7,24,1,5,11,12,16,15,20,24,1,9,4,3,2,16,14,24,1,6,8,13,16,15,20,24,1,10,4,3,2,16,16,24,1,5,11,12,16,15,20,24,1,9,4,3,2,16,17,24,1,6,8,13,16,15,20,24,1,10,4,3,2,16,19,24,1,5,11,12,16,15,20,24,1,9,4,3,2,16,21,24,1,6,8,13,16,15,20,24,1,10,4,3,2]
def state_RDNA4_n() -> Nat: 256n
def state_CDNA() -> List<&2, U32>: [0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0,16,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0,16,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]
def state_CDNA_n() -> Nat: 256n

# --- D  THE DECODE INFO: nib_count, delta_lo, delta_mask, delta_mul, special -----
# `special`: 0 none, 1 TS_DELTA_OR_MARK, 2 TS_DELTA_SHORT (+4), 4 CDNA_TIMESTAMP.
# The DELTA defaults differ per arch -- CDNA uses bits[4:4] with a multiplier
# of 4, RDNA uses None with a multiplier of 1 (:558) -- and that is the whole
# reason a CDNA timestamp and an RDNA delta are not the same number.
def di_RDNA3_1() -> List<&2, U32>: [3,3,7,1,0]
def di_RDNA3_2() -> List<&2, U32>: [2,4,3,1,0]
def di_RDNA3_3() -> List<&2, U32>: [2,4,3,1,0]
def di_RDNA3_4() -> List<&2, U32>: [3,4,7,1,0]
def di_RDNA3_5() -> List<&2, U32>: [6,5,7,1,0]
def di_RDNA3_6() -> List<&2, U32>: [6,5,7,1,0]
def di_RDNA3_7() -> List<&2, U32>: [18,8,7,1,0]
def di_RDNA3_8() -> List<&2, U32>: [5,5,7,1,0]
def di_RDNA3_9() -> List<&2, U32>: [8,5,3,1,0]
def di_RDNA3_10() -> List<&2, U32>: [12,5,3,1,0]
def di_RDNA3_11() -> List<&2, U32>: [5,5,7,1,0]
def di_RDNA3_12() -> List<&2, U32>: [13,5,7,1,0]
def di_RDNA3_13() -> List<&2, U32>: [7,5,7,1,0]
def di_RDNA3_14() -> List<&2, U32>: [12,7,3,1,0]
def di_RDNA3_15() -> List<&2, U32>: [2,4,15,1,2]
def di_RDNA3_16() -> List<&2, U32>: [1,0,0,1,0]
def di_RDNA3_17() -> List<&2, U32>: [6,7,511,1,0]
def di_RDNA3_18() -> List<&2, U32>: [6,8,7,1,0]
def di_RDNA3_19() -> List<&2, U32>: [8,8,7,1,0]
def di_RDNA3_20() -> List<&2, U32>: [16,4,7,1,0]
def di_RDNA3_21() -> List<&2, U32>: [16,7,7,1,0]
def di_RDNA3_22() -> List<&2, U32>: [12,12,4294967295,1,1]
def di_RDNA3_23() -> List<&2, U32>: [16,0,0,1,0]
def di_RDNA3_24() -> List<&2, U32>: [5,4,7,1,0]
def di_RDNA3_n() -> Nat: 24n
def di_RDNA4_1() -> List<&2, U32>: [3,3,7,1,0]
def di_RDNA4_2() -> List<&2, U32>: [2,4,3,1,0]
def di_RDNA4_3() -> List<&2, U32>: [2,4,3,1,0]
def di_RDNA4_4() -> List<&2, U32>: [3,4,7,1,0]
def di_RDNA4_5() -> List<&2, U32>: [6,5,7,1,0]
def di_RDNA4_6() -> List<&2, U32>: [6,5,7,1,0]
def di_RDNA4_7() -> List<&2, U32>: [18,8,7,1,0]
def di_RDNA4_8() -> List<&2, U32>: [5,5,7,1,0]
def di_RDNA4_9() -> List<&2, U32>: [8,5,3,1,0]
def di_RDNA4_10() -> List<&2, U32>: [10,5,3,1,0]
def di_RDNA4_11() -> List<&2, U32>: [6,5,7,1,0]
def di_RDNA4_12() -> List<&2, U32>: [14,7,7,1,0]
def di_RDNA4_13() -> List<&2, U32>: [8,7,7,1,0]
def di_RDNA4_14() -> List<&2, U32>: [12,7,3,1,0]
def di_RDNA4_15() -> List<&2, U32>: [2,4,15,1,2]
def di_RDNA4_16() -> List<&2, U32>: [1,0,0,1,0]
def di_RDNA4_17() -> List<&2, U32>: [6,7,511,1,0]
def di_RDNA4_18() -> List<&2, U32>: [6,8,7,1,0]
def di_RDNA4_19() -> List<&2, U32>: [8,8,7,1,0]
def di_RDNA4_20() -> List<&2, U32>: [16,4,7,1,0]
def di_RDNA4_21() -> List<&2, U32>: [16,7,7,1,0]
def di_RDNA4_22() -> List<&2, U32>: [16,12,4294967295,1,1]
def di_RDNA4_23() -> List<&2, U32>: [16,0,0,1,0]
def di_RDNA4_24() -> List<&2, U32>: [5,3,7,1,0]
def di_RDNA4_n() -> Nat: 24n
def di_CDNA_0() -> List<&2, U32>: [4,4,255,4,0]
def di_CDNA_1() -> List<&2, U32>: [16,4,1,4,4]
def di_CDNA_2() -> List<&2, U32>: [16,4,1,4,0]
def di_CDNA_3() -> List<&2, U32>: [8,4,1,4,0]
def di_CDNA_4() -> List<&2, U32>: [4,4,1,4,0]
def di_CDNA_5() -> List<&2, U32>: [12,4,1,4,0]
def di_CDNA_6() -> List<&2, U32>: [4,4,1,4,0]
def di_CDNA_7() -> List<&2, U32>: [4,4,1,4,0]
def di_CDNA_8() -> List<&2, U32>: [4,4,1,4,0]
def di_CDNA_9() -> List<&2, U32>: [4,4,1,4,0]
def di_CDNA_10() -> List<&2, U32>: [4,4,1,4,0]
def di_CDNA_11() -> List<&2, U32>: [16,4,1,4,0]
def di_CDNA_12() -> List<&2, U32>: [12,4,1,4,0]
def di_CDNA_13() -> List<&2, U32>: [8,4,1,4,0]
def di_CDNA_14() -> List<&2, U32>: [16,4,1,4,0]
def di_CDNA_15() -> List<&2, U32>: [12,4,1,4,0]
def di_CDNA_16() -> List<&2, U32>: [16,0,0,4,0]
def di_CDNA_n() -> Nat: 17n

# --- THE PER-OPCODE SETS, DERIVED ------------------------------------------
# `decode_info[opcode] = (cls, _size_nibbles, lo, mask, mul, special)` (:558-560)
# and the two SETS a reader indexes by opcode: the delta MULTIPLIER (always 4
# for CDNA, 1 for RDNA, :558) and the SPECIAL tag. Only THREE opcodes are
# non-zero and they are DIFFERENT opcodes per arch: RDNA puts 2 on 15 and 1
# on 22; CDNA puts 4 on 1. A set written as one literal for both would put a
# `+4` on a CDNA timestamp.
def di_RDNA3_flat() -> List<&2, U32>: [3,3,7,1,0,2,4,3,1,0,2,4,3,1,0,3,4,7,1,0,6,5,7,1,0,6,5,7,1,0,18,8,7,1,0,5,5,7,1,0,8,5,3,1,0,12,5,3,1,0,5,5,7,1,0,13,5,7,1,0,7,5,7,1,0,12,7,3,1,0,2,4,15,1,2,1,0,0,1,0,6,7,511,1,0,6,8,7,1,0,8,8,7,1,0,16,4,7,1,0,16,7,7,1,0,12,12,4294967295,1,1,16,0,0,1,0,5,4,7,1,0]
def di_RDNA4_flat() -> List<&2, U32>: [3,3,7,1,0,2,4,3,1,0,2,4,3,1,0,3,4,7,1,0,6,5,7,1,0,6,5,7,1,0,18,8,7,1,0,5,5,7,1,0,8,5,3,1,0,10,5,3,1,0,6,5,7,1,0,14,7,7,1,0,8,7,7,1,0,12,7,3,1,0,2,4,15,1,2,1,0,0,1,0,6,7,511,1,0,6,8,7,1,0,8,8,7,1,0,16,4,7,1,0,16,7,7,1,0,16,12,4294967295,1,1,16,0,0,1,0,5,3,7,1,0]
def di_CDNA_flat() -> List<&2, U32>: [4,4,255,4,0,16,4,1,4,4,16,4,1,4,0,8,4,1,4,0,4,4,1,4,0,12,4,1,4,0,4,4,1,4,0,4,4,1,4,0,4,4,1,4,0,4,4,1,4,0,4,4,1,4,0,16,4,1,4,0,12,4,1,4,0,8,4,1,4,0,16,4,1,4,0,12,4,1,4,0,16,0,0,4,0]

# --- P  THE DERIVED PROPERTIES -------------------------------------------
# `cu` has THREE FORMULAS in one file and the difference is one bit of shift:
# WAVEEND and WAVESTART use `wgp | (sa << 3)` while their _RDNA4 twins use
# `wgp | (sa << 4)` (:266, :302, :311, :321). A lookup keyed by the SHORT name
# answers the RDNA3 answer for an RDNA4 packet and a CU id is silently wrong.
def cu_WAVEEND(wgp: U32, sa: U32) -> U32: U32.or(wgp, U32.shln(sa, 3n))
def cu_WAVEEND_RDNA4(wgp: U32, sa: U32) -> U32: U32.or(wgp, U32.shln(sa, 4n))
def cu_WAVESTART(wgp: U32, sa: U32) -> U32: U32.or(wgp, U32.shln(sa, 3n))
def cu_WAVESTART_RDNA4(wgp: U32, sa: U32) -> U32: U32.or(wgp, U32.shln(sa, 4n))
# --- E  THE OP ENUMS, BOTH DIRECTIONS -------------------------------------
# The five defs below are upstream's five `class X(Enum)` NAMES, spelled bare.
# They were `enum_X` until the naming gate (`naming-gate.py`) required the
# upstream spelling: the bare names are FREE here -- `enum_` was never forced,
# unlike the ten accessor prefixes above, which are.
# The `_n` companions are the member COUNT, which upstream has no name for, so
# they are port-local and follow the defs. The ROW LABELS keep the `enum_`
# spelling on purpose: they are the join keys into `.agents/slop/sqtt_oracle.txt`
# (generated from CPython), and renaming a label desynchronises a gate this
# unit does not own. A rename must move zero rows, so the labels are frozen.
# `add_other_simd` (:34-39) builds names by FORMULA --
# `f"OTHER_{category}_{value - start + base_cycle}"` -- and the three ranges
# have DIFFERENT base_cycles (LDS 1, FLAT 2, VMEM 1), so the generated names
# are the part a hand-written table gets wrong and they are 5+5+13 rows.
def MemSrc() -> List<&2, Pn>: [Pn{"LDS", 0},Pn{"LDS_ALT", 1},Pn{"VMEM", 2},Pn{"VMEM_ALT", 3}]
def MemSrc_n() -> Nat: 4n
def AluSrc() -> List<&2, Pn>: [Pn{"NONE", 0},Pn{"SALU", 1},Pn{"VALU", 2},Pn{"VALU_SALU", 3}]
def AluSrc_n() -> Nat: 4n
def InstOp() -> List<&2, Pn>: [Pn{"SALU", 0},Pn{"SMEM_RD", 1},Pn{"JUMP", 3},Pn{"JUMP_NO", 4},Pn{"CALL", 5},Pn{"MESSAGE", 9},Pn{"VALUT_4", 11},Pn{"VALUB_2", 13},Pn{"VALUB_4", 14},Pn{"VALUB_16", 15},Pn{"VINTERP", 18},Pn{"BARRIER", 19},Pn{"FLAT_RD_2", 28},Pn{"FLAT_WR_3", 29},Pn{"FLAT_WR_4", 30},Pn{"FLAT_WR_5", 31},Pn{"FLAT_WR_6", 32},Pn{"SGMEM_RD_1", 33},Pn{"SGMEM_RD_2", 34},Pn{"SGMEM_WR_2", 36},Pn{"SGMEM_WR_3", 37},Pn{"SGMEM_WR_4", 38},Pn{"SGMEM_WR_5", 39},Pn{"SGMEM_WR_6", 40},Pn{"LDS_RD", 41},Pn{"LDS_WR_1", 42},Pn{"LDS_WR_2", 43},Pn{"LDS_WR_3", 44},Pn{"LDS_WR_4", 45},Pn{"LDS_WR_5", 46},Pn{"OTHER_LDS_1", 80},Pn{"OTHER_LDS_2", 81},Pn{"OTHER_LDS_3", 82},Pn{"OTHER_LDS_4", 83},Pn{"OTHER_LDS_5", 84},Pn{"OTHER_FLAT_2", 85},Pn{"OTHER_FLAT_3", 86},Pn{"OTHER_FLAT_4", 87},Pn{"OTHER_FLAT_5", 88},Pn{"OTHER_FLAT_6", 89},Pn{"OTHER_VMEM_1", 90},Pn{"OTHER_VMEM_2", 91},Pn{"OTHER_VMEM_3", 92},Pn{"OTHER_VMEM_4", 93},Pn{"OTHER_VMEM_5", 94},Pn{"OTHER_VMEM_6", 95},Pn{"OTHER_VMEM_7", 96},Pn{"OTHER_VMEM_8", 97},Pn{"OTHER_VMEM_9", 98},Pn{"OTHER_VMEM_10", 99},Pn{"OTHER_VMEM_11", 100},Pn{"OTHER_VMEM_12", 101},Pn{"OTHER_VMEM_13", 102},Pn{"SALU_WR_EXEC", 114},Pn{"VALU1_WR_EXEC", 115}]
def InstOp_n() -> Nat: 55n
def InstOpRDNA4() -> List<&2, Pn>: [Pn{"SALU", 0},Pn{"SMEM", 1},Pn{"SMEM_WR", 2},Pn{"JUMP", 3},Pn{"JUMP_NO", 4},Pn{"CALL", 5},Pn{"SALU_NO_EXEC", 7},Pn{"MESSAGE", 9},Pn{"VALU_1", 10},Pn{"VALUT_4", 11},Pn{"VALUB_1", 12},Pn{"VALUB_2", 13},Pn{"VALUB_4", 14},Pn{"VALUB_16", 15},Pn{"VINTERP", 18},Pn{"BARRIER_WAIT", 19},Pn{"FLAT_RD_2", 28},Pn{"FLAT_WR_3", 29},Pn{"FLAT_WR_4", 30},Pn{"FLAT_WR_5", 31},Pn{"FLAT_WR_6", 32},Pn{"VMEM_RD_1", 33},Pn{"VMEM_RD_2", 34},Pn{"VMEM_WR_1", 35},Pn{"VMEM_WR_2", 36},Pn{"VMEM_WR_3", 37},Pn{"VMEM_WR_4", 38},Pn{"VMEM_WR_5", 39},Pn{"VMEM_WR_6", 40},Pn{"LDS_RD", 41},Pn{"LDS_WR_1", 42},Pn{"LDS_WR_2", 43},Pn{"LDS_WR_3", 44},Pn{"LDS_WR_4", 45},Pn{"LDS_WR_5", 46},Pn{"BUF_RD_1", 47},Pn{"BUF_RD_2", 48},Pn{"BUF_WR_1", 49},Pn{"BUF_WR_2", 50},Pn{"BUF_WR_3", 51},Pn{"BUF_WR_4", 52},Pn{"BUF_WR_5", 53},Pn{"BUF_WR_6", 54},Pn{"OTHER_LDS_1", 80},Pn{"OTHER_LDS_2", 81},Pn{"OTHER_LDS_3", 82},Pn{"OTHER_LDS_4", 83},Pn{"OTHER_LDS_5", 84},Pn{"OTHER_FLAT_2", 85},Pn{"OTHER_FLAT_3", 86},Pn{"OTHER_FLAT_4", 87},Pn{"OTHER_FLAT_5", 88},Pn{"OTHER_FLAT_6", 89},Pn{"LDS_DIR_LOAD", 110},Pn{"LDS_PARAM_LOAD", 111},Pn{"SALU_WR_EXEC", 114},Pn{"VALU1_WR_EXEC", 115},Pn{"VALU_WR_EXEC_2", 116},Pn{"OTHER_LDS_6", 119},Pn{"OTHER_LDS_10", 120},Pn{"BARRIER_SIGNAL", 122},Pn{"DYN_VGPR", 135},Pn{"BARRIER_JOIN", 138},Pn{"WMMA_8", 140},Pn{"WMMA_16", 141},Pn{"WMMA_32", 142},Pn{"WMMA_64", 143},Pn{"VALU_DPFP", 146},Pn{"SALU_FLOAT_3", 152},Pn{"VALU_SCL_TRANS", 153},Pn{"SALU_2", 155},Pn{"SALU_5", 156},Pn{"OTHER_VMEM_1", 188},Pn{"OTHER_VMEM_2", 189},Pn{"OTHER_VMEM_3", 190},Pn{"OTHER_VMEM_4", 191},Pn{"OTHER_VMEM_5", 192},Pn{"OTHER_VMEM_6", 193},Pn{"OTHER_VMEM_7", 194},Pn{"OTHER_VMEM_8", 195},Pn{"OTHER_VMEM_9", 196},Pn{"OTHER_VMEM_10", 197},Pn{"OTHER_VMEM_11", 198},Pn{"OTHER_VMEM_12", 199},Pn{"OTHER_VMEM_13", 200},Pn{"OTHER_VMEM_14", 201},Pn{"OTHER_VMEM_15", 202},Pn{"OTHER_VMEM_16", 203},Pn{"OTHER_VMEM_17", 204},Pn{"OTHER_VMEM_18", 205},Pn{"OTHER_VMEM_19", 206},Pn{"OTHER_VMEM_20", 207},Pn{"OTHER_VMEM_21", 208},Pn{"OTHER_VMEM_22", 209},Pn{"OTHER_VMEM_23", 210},Pn{"OTHER_VMEM_24", 211},Pn{"OTHER_VMEM_25", 212},Pn{"OTHER_VMEM_26", 213},Pn{"OTHER_VMEM_27", 214},Pn{"OTHER_VMEM_28", 215},Pn{"OTHER_VMEM_29", 216},Pn{"OTHER_VMEM_30", 217},Pn{"OTHER_VMEM_31", 218},Pn{"OTHER_VMEM_32", 219},Pn{"OTHER_VMEM_33", 220},Pn{"OTHER_VMEM_34", 221}]
def InstOpRDNA4_n() -> Nat: 106n
def InstOpCDNA() -> List<&2, Pn>: [Pn{"SMEM_RD", 0},Pn{"SALU_32", 1},Pn{"VMEM_RD", 2},Pn{"VMEM_WR", 3},Pn{"FLAT_WR", 4},Pn{"VALU_32", 5},Pn{"LDS", 6},Pn{"PC", 7},Pn{"JUMP", 12},Pn{"NEXT", 13},Pn{"FLAT_RD", 14},Pn{"OTHER_MSG", 15},Pn{"SMEM_WR", 16},Pn{"SALU_64", 17},Pn{"VALU_64", 18},Pn{"VALU_MAI", 28}]
def InstOpCDNA_n() -> Nat: 16n

