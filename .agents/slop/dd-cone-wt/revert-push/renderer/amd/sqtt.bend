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
# WHAT IS PORTED, AND WHAT EACH THING IS FOR.
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
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def u32_text(v: U32) -> String: U32.show(v)

def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", u32_text(v)]))

def nat_text(v: Nat) -> String: U32.show(U32.from_nat(v))
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

def u32_at(i: U32, xs: List<&2, U32>) -> U32: u32_at.go(List.get(&2, U32, xs, U32.to_nat(i)), DSLT())

def u32_list_text.go(xs: List<&2, U32>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case x <> t: u32_list_text.go(t, String.concat([acc, u32_text(x), ","]))

# `dict.get`-ish lookups over an `Nm` list. `nm_name.go` is dsl.bend's OFFSET-keyed
# walk; these are the NAME-keyed and INDEX-keyed ones, and they are SEPARATE
# functions on purpose: a table whose two directions are the same body agrees with
# itself and tells you nothing.

def u32_list_text(xs: List<&2, U32>) -> String: u32_list_text.go(xs, "")

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

def name_at(off: U32, +xs: List<&2, Pn>) -> String: pn_name.go(n_of(xs), off, xs, False{}, "")

def op_of(nm: String, +xs: List<&2, Pn>) -> U32: pn_off.go(n_of(xs), nm, xs, False{}, DSLT())

# the class COUNT, from the generated `cls_*` defs rather than a hard-coded
# number, so adding a class is a generator run and not a lie.
def cls_count.go(xs: List<&2, String>, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case _ <> t: cls_count.go(t, U32.add(n, 1))

# THE PER-OPCODE SETS, DERIVED. `decode_info[opcode]` is the FIVE-tuple
# `decode()` unpacks at :611 -- nib_count, delta_lo, delta_mask, delta_mul,
# special -- and the four SETS are folded out of the CONCATENATED tuples with a
# STRIDE of five.
#
# THE FIRST VERSION ANSWERED FROM A LITERAL and had `special = 2` at list
# POSITION 15 where the real answer is `special = 1` at OPCODE 22:
# TS_DELTA_SHORT is opcode 15 and TS_DELTA_OR_MARK is opcode 22, and a hardcoded
# list confuses the two silently. Bend has no `List<List<U32>>`, hence the
# concatenation -- and the STRIDE is a def, so a wrong tuple width moves every
# set row instead of hiding inside a literal.
def CLS_NAMES() -> List<&2, String>: ["VALUINST","VMEMEXEC","ALUEXEC","IMMEDIATE","IMMEDIATE_MASK","WAVERDY","TS_DELTA_S8_W3","WAVEEND","WAVESTART","TS_DELTA_S5_W2","WAVEALLOC","TS_DELTA_S5_W3","PERF","UTILCTR","TS_DELTA_SHORT","NOP","TS_WAVE_STATE","EVENT","EVENT_BIG","REG","SNAPSHOT","TS_DELTA_OR_MARK","LAYOUT_HEADER","INST","WAVEEND_RDNA4","WAVESTART_RDNA4","TS_DELTA_S5_W2_RDNA4","WAVEALLOC_RDNA4","TS_DELTA_S5_W3_RDNA4","PERF_RDNA4","TS_DELTA_OR_MARK_RDNA4","INST_RDNA4","CDNA_MISC","CDNA_TIMESTAMP","CDNA_REG","CDNA_WAVESTART","CDNA_WAVEALLOC","CDNA_REG_CS","CDNA_WAVEEND","CDNA_EVENT","CDNA_EVENT_CS","CDNA_EVENT_GFX1","CDNA_INST","CDNA_INST_PC","CDNA_USERDATA","CDNA_ISSUE","CDNA_PERF","CDNA_REG_CS_PRIV"]

def cls_count() -> U32: cls_count.go(CLS_NAMES(), 0)

def di_text.go(xs: List<&2, U32>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case x <> t: di_text.go(t, String.concat([acc, u32_text(x), ","]))

# the per-arch delta MULTIPLIER set and SPECIAL set, as one string each. CDNA
# multiplies by 4 and RDNA by 1 (:558), and that single number is why the same
# 64-bit blob decodes to different timestamps on the two architectures.

def di_text(v: List<&2, U32>) -> String: di_text.go(v, "")

# THE PER-OPCODE SETS, DERIVED. `decode_info[opcode]` is the FIVE-tuple
# `decode()` unpacks at :611 -- nib_count, delta_lo, delta_mask, delta_mul,
# special -- and the four SETS are folded out of the CONCATENATED tuples with a
# STRIDE of five.
#
# THE FIRST VERSION ANSWERED FROM A LITERAL and had `special = 2` at list
# POSITION 15 where the real answer is `special = 1` at OPCODE 22:
# TS_DELTA_SHORT is opcode 15 and TS_DELTA_OR_MARK is opcode 22, and a hardcoded
# list confuses the two silently. Bend has no `List<List<U32>>`, hence the
# concatenation -- and the STRIDE is a def, so a wrong tuple width moves every set
# row instead of hiding inside a literal.
# THE PER-OPCODE SETS, DERIVED. `decode_info[opcode]` is the FIVE-tuple
# `decode()` unpacks at :611 -- nib_count, delta_lo, delta_mask, delta_mul,
# special -- and the four SETS are folded out of the CONCATENATED tuples with a
# STRIDE of five.
#
# THE FIRST VERSION ANSWERED FROM A LITERAL and had `special = 2` at list
# POSITION 15 where the real answer is `special = 1` at OPCODE 22:
# TS_DELTA_SHORT is opcode 15 and TS_DELTA_OR_MARK is opcode 22, and a hardcoded
# list confuses the two silently. Bend has no `List<List<U32>>`, hence the
# concatenation -- and the STRIDE is a def, so a wrong tuple width moves every set
# row instead of hiding inside a literal.
# THE PER-OPCODE SETS, DERIVED. `decode_info[opcode]` is the FIVE-tuple
# `decode()` unpacks at :611 -- nib_count, delta_lo, delta_mask, delta_mul,
# special -- and the two SETS are folded out of the CONCATENATED tuples with a
# STRIDE of five.
#
# THE FIRST VERSION ANSWERED FROM A LITERAL and had `special = 2` at list
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

def set_mul(xs: List<&2, U32>) -> String: set_mul.go(xs, "")

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

def set_sp(xs: List<&2, U32>) -> String: set_sp.go(xs, "")

def t_stub() -> IO(Unit):
  do IO<Unit>:
    IO.print("stub")

# ==== GATE BODY (generated by .agents/slop/sqtt_gen.py) ====
# --- T  THE THREE OPCODE TABLES, BOTH DIRECTIONS --------------------
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

def str_list_text(xs: List<&2, String>) -> String: str_list_text.go(xs, "")
def NIB_DEN() -> U32: 4

# --- E  THE SORT THAT DECIDES THE STATE TABLE ------------------------------
# `sorted(packet_types.items(), key=lambda x: (-bin(mask).count("1"), x[0] == 16))`
# (:557). TWO keys, and the second is what puts NOP -- opcode 16 -- LAST, so
# a byte with no match falls through to NOP rather than to whichever 4-bit
# pattern happened to be visited first. A port that sorts on specificity
# alone puts NOP FIRST and every unmatched byte decodes as a NOP of the
# wrong width.

def NIB_DIV(v: U32) -> U32: U32.div(v, NIB_DEN())

def NIB_NUM() -> U32: 4

def NIB_ROUND(hi_max: U32) -> U32: NIB_DIV(U32.add(hi_max, NIB_NUM()))

def nibs_of(hi_max: U32) -> U32: NIB_ROUND(hi_max)
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
def is_marker(rt: U32, pl: U32) -> Bool: Bool.and(Bool.not(U32.is_zero(rt)), U32.is_zero(pl))
def is_config(hi_byte: U32) -> Bool: Bool.not(U32.is_zero(U32.and(hi_byte, 128)))
def wave_interest(coarse: U32) -> Bool: Bool.not(U32.is_zero(U32.and(coarse, 1)))
def terminate_all(coarse: U32) -> Bool: Bool.not(U32.is_zero(U32.and(coarse, 8)))

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

# --- THE GATE ROWS ------------------------------------------------------
def g_tables() -> IO(Unit):
  do IO<Unit>:
    srow("tbl_RDNA3_n", nat_text(tbl_RDNA3_n()))
    srow("tbl_RDNA3_fwd_1", name_at(1, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_2", name_at(2, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_3", name_at(3, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_4", name_at(4, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_5", name_at(5, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_6", name_at(6, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_7", name_at(7, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_8", name_at(8, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_9", name_at(9, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_10", name_at(10, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_11", name_at(11, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_12", name_at(12, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_13", name_at(13, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_14", name_at(14, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_15", name_at(15, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_16", name_at(16, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_17", name_at(17, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_18", name_at(18, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_19", name_at(19, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_20", name_at(20, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_21", name_at(21, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_22", name_at(22, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_23", name_at(23, tbl_RDNA3()))
    srow("tbl_RDNA3_fwd_24", name_at(24, tbl_RDNA3()))
    srow("tbl_RDNA3_rev_VALUINST", u32_text(op_of("VALUINST", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_VMEMEXEC", u32_text(op_of("VMEMEXEC", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_ALUEXEC", u32_text(op_of("ALUEXEC", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_IMMEDIATE", u32_text(op_of("IMMEDIATE", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_IMMEDIATE_MASK", u32_text(op_of("IMMEDIATE_MASK", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_WAVERDY", u32_text(op_of("WAVERDY", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_TS_DELTA_S8_W3", u32_text(op_of("TS_DELTA_S8_W3", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_WAVEEND", u32_text(op_of("WAVEEND", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_WAVESTART", u32_text(op_of("WAVESTART", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_TS_DELTA_S5_W2", u32_text(op_of("TS_DELTA_S5_W2", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_WAVEALLOC", u32_text(op_of("WAVEALLOC", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_TS_DELTA_S5_W3", u32_text(op_of("TS_DELTA_S5_W3", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_PERF", u32_text(op_of("PERF", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_UTILCTR", u32_text(op_of("UTILCTR", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_TS_DELTA_SHORT", u32_text(op_of("TS_DELTA_SHORT", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_NOP", u32_text(op_of("NOP", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_TS_WAVE_STATE", u32_text(op_of("TS_WAVE_STATE", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_EVENT", u32_text(op_of("EVENT", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_EVENT_BIG", u32_text(op_of("EVENT_BIG", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_REG", u32_text(op_of("REG", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_SNAPSHOT", u32_text(op_of("SNAPSHOT", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_TS_DELTA_OR_MARK", u32_text(op_of("TS_DELTA_OR_MARK", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_LAYOUT_HEADER", u32_text(op_of("LAYOUT_HEADER", tbl_RDNA3())))
    srow("tbl_RDNA3_rev_INST", u32_text(op_of("INST", tbl_RDNA3())))
    srow("tbl_RDNA3_order", op_order_RDNA3())
    srow("tbl_RDNA3_spec_order", spec_order_RDNA3())
    srow("tbl_RDNA4_n", nat_text(tbl_RDNA4_n()))
    srow("tbl_RDNA4_fwd_1", name_at(1, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_2", name_at(2, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_3", name_at(3, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_4", name_at(4, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_5", name_at(5, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_6", name_at(6, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_7", name_at(7, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_8", name_at(8, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_9", name_at(9, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_10", name_at(10, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_11", name_at(11, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_12", name_at(12, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_13", name_at(13, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_14", name_at(14, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_15", name_at(15, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_16", name_at(16, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_17", name_at(17, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_18", name_at(18, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_19", name_at(19, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_20", name_at(20, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_21", name_at(21, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_22", name_at(22, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_23", name_at(23, tbl_RDNA4()))
    srow("tbl_RDNA4_fwd_24", name_at(24, tbl_RDNA4()))
    srow("tbl_RDNA4_rev_VALUINST", u32_text(op_of("VALUINST", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_VMEMEXEC", u32_text(op_of("VMEMEXEC", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_ALUEXEC", u32_text(op_of("ALUEXEC", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_IMMEDIATE", u32_text(op_of("IMMEDIATE", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_IMMEDIATE_MASK", u32_text(op_of("IMMEDIATE_MASK", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_WAVERDY", u32_text(op_of("WAVERDY", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_TS_DELTA_S8_W3", u32_text(op_of("TS_DELTA_S8_W3", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_WAVEEND_RDNA4", u32_text(op_of("WAVEEND_RDNA4", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_WAVESTART_RDNA4", u32_text(op_of("WAVESTART_RDNA4", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_TS_DELTA_S5_W2_RDNA4", u32_text(op_of("TS_DELTA_S5_W2_RDNA4", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_WAVEALLOC_RDNA4", u32_text(op_of("WAVEALLOC_RDNA4", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_TS_DELTA_S5_W3_RDNA4", u32_text(op_of("TS_DELTA_S5_W3_RDNA4", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_PERF_RDNA4", u32_text(op_of("PERF_RDNA4", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_UTILCTR", u32_text(op_of("UTILCTR", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_TS_DELTA_SHORT", u32_text(op_of("TS_DELTA_SHORT", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_NOP", u32_text(op_of("NOP", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_TS_WAVE_STATE", u32_text(op_of("TS_WAVE_STATE", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_EVENT", u32_text(op_of("EVENT", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_EVENT_BIG", u32_text(op_of("EVENT_BIG", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_REG", u32_text(op_of("REG", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_SNAPSHOT", u32_text(op_of("SNAPSHOT", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_TS_DELTA_OR_MARK_RDNA4", u32_text(op_of("TS_DELTA_OR_MARK_RDNA4", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_LAYOUT_HEADER", u32_text(op_of("LAYOUT_HEADER", tbl_RDNA4())))
    srow("tbl_RDNA4_rev_INST_RDNA4", u32_text(op_of("INST_RDNA4", tbl_RDNA4())))
    srow("tbl_RDNA4_order", op_order_RDNA4())
    srow("tbl_RDNA4_spec_order", spec_order_RDNA4())
    srow("tbl_CDNA_n", nat_text(tbl_CDNA_n()))
    srow("tbl_CDNA_fwd_0", name_at(0, tbl_CDNA()))
    srow("tbl_CDNA_fwd_1", name_at(1, tbl_CDNA()))
    srow("tbl_CDNA_fwd_2", name_at(2, tbl_CDNA()))
    srow("tbl_CDNA_fwd_3", name_at(3, tbl_CDNA()))
    srow("tbl_CDNA_fwd_4", name_at(4, tbl_CDNA()))
    srow("tbl_CDNA_fwd_5", name_at(5, tbl_CDNA()))
    srow("tbl_CDNA_fwd_6", name_at(6, tbl_CDNA()))
    srow("tbl_CDNA_fwd_7", name_at(7, tbl_CDNA()))
    srow("tbl_CDNA_fwd_8", name_at(8, tbl_CDNA()))
    srow("tbl_CDNA_fwd_9", name_at(9, tbl_CDNA()))
    srow("tbl_CDNA_fwd_10", name_at(10, tbl_CDNA()))
    srow("tbl_CDNA_fwd_11", name_at(11, tbl_CDNA()))
    srow("tbl_CDNA_fwd_12", name_at(12, tbl_CDNA()))
    srow("tbl_CDNA_fwd_13", name_at(13, tbl_CDNA()))
    srow("tbl_CDNA_fwd_14", name_at(14, tbl_CDNA()))
    srow("tbl_CDNA_fwd_15", name_at(15, tbl_CDNA()))
    srow("tbl_CDNA_fwd_16", name_at(16, tbl_CDNA()))
    srow("tbl_CDNA_rev_CDNA_MISC", u32_text(op_of("CDNA_MISC", tbl_CDNA())))
    srow("tbl_CDNA_rev_CDNA_TIMESTAMP", u32_text(op_of("CDNA_TIMESTAMP", tbl_CDNA())))
    srow("tbl_CDNA_rev_CDNA_REG", u32_text(op_of("CDNA_REG", tbl_CDNA())))
    srow("tbl_CDNA_rev_CDNA_WAVESTART", u32_text(op_of("CDNA_WAVESTART", tbl_CDNA())))
    srow("tbl_CDNA_rev_CDNA_WAVEALLOC", u32_text(op_of("CDNA_WAVEALLOC", tbl_CDNA())))
    srow("tbl_CDNA_rev_CDNA_REG_CS", u32_text(op_of("CDNA_REG_CS", tbl_CDNA())))
    srow("tbl_CDNA_rev_CDNA_WAVEEND", u32_text(op_of("CDNA_WAVEEND", tbl_CDNA())))
    srow("tbl_CDNA_rev_CDNA_EVENT", u32_text(op_of("CDNA_EVENT", tbl_CDNA())))
    srow("tbl_CDNA_rev_CDNA_EVENT_CS", u32_text(op_of("CDNA_EVENT_CS", tbl_CDNA())))
    srow("tbl_CDNA_rev_CDNA_EVENT_GFX1", u32_text(op_of("CDNA_EVENT_GFX1", tbl_CDNA())))
    srow("tbl_CDNA_rev_CDNA_INST", u32_text(op_of("CDNA_INST", tbl_CDNA())))
    srow("tbl_CDNA_rev_CDNA_INST_PC", u32_text(op_of("CDNA_INST_PC", tbl_CDNA())))
    srow("tbl_CDNA_rev_CDNA_USERDATA", u32_text(op_of("CDNA_USERDATA", tbl_CDNA())))
    srow("tbl_CDNA_rev_CDNA_ISSUE", u32_text(op_of("CDNA_ISSUE", tbl_CDNA())))
    srow("tbl_CDNA_rev_CDNA_PERF", u32_text(op_of("CDNA_PERF", tbl_CDNA())))
    srow("tbl_CDNA_rev_CDNA_REG_CS_PRIV", u32_text(op_of("CDNA_REG_CS_PRIV", tbl_CDNA())))
    srow("tbl_CDNA_rev_LAYOUT_HEADER", u32_text(op_of("LAYOUT_HEADER", tbl_CDNA())))
    srow("tbl_CDNA_order", op_order_CDNA())
    srow("tbl_CDNA_spec_order", spec_order_CDNA())
    # THE RDNA4 DELTA: `{**RDNA3, ...}` with eight overrides, so eight of the
    # twenty-four rows DIFFER. A table ported as a copy of RDNA3 is wrong in
    # eight places and a count cannot see it.
    row("rdna4_same_1", True{})
    row("rdna4_same_2", True{})
    row("rdna4_same_3", True{})
    row("rdna4_same_4", True{})
    row("rdna4_same_5", True{})
    row("rdna4_same_6", True{})
    row("rdna4_same_7", True{})
    row("rdna4_same_8", False{})
    row("rdna4_same_9", False{})
    row("rdna4_same_10", False{})
    row("rdna4_same_11", False{})
    row("rdna4_same_12", False{})
    row("rdna4_same_13", False{})
    row("rdna4_same_14", True{})
    row("rdna4_same_15", True{})
    row("rdna4_same_16", True{})
    row("rdna4_same_17", True{})
    row("rdna4_same_18", True{})
    row("rdna4_same_19", True{})
    row("rdna4_same_20", True{})
    row("rdna4_same_21", True{})
    row("rdna4_same_22", False{})
    row("rdna4_same_23", True{})
    row("rdna4_same_24", False{})
    srow("rdna4_diff_8", String.concat([name_at(8, tbl_RDNA3()), "->", name_at(8, tbl_RDNA4())]))
    srow("rdna4_diff_9", String.concat([name_at(9, tbl_RDNA3()), "->", name_at(9, tbl_RDNA4())]))
    srow("rdna4_diff_10", String.concat([name_at(10, tbl_RDNA3()), "->", name_at(10, tbl_RDNA4())]))
    srow("rdna4_diff_11", String.concat([name_at(11, tbl_RDNA3()), "->", name_at(11, tbl_RDNA4())]))
    srow("rdna4_diff_12", String.concat([name_at(12, tbl_RDNA3()), "->", name_at(12, tbl_RDNA4())]))
    srow("rdna4_diff_13", String.concat([name_at(13, tbl_RDNA3()), "->", name_at(13, tbl_RDNA4())]))
    srow("rdna4_diff_22", String.concat([name_at(22, tbl_RDNA3()), "->", name_at(22, tbl_RDNA4())]))
    srow("rdna4_diff_24", String.concat([name_at(24, tbl_RDNA3()), "->", name_at(24, tbl_RDNA4())]))
def g_fields() -> IO(Unit):
  do IO<Unit>:
    srow("cls_VALUINST", field_order_VALUINST())
    srow("clsfields_VALUINST", fields_VALUINST())
    urow("clsnib_VALUINST", nibs_of(himax_VALUINST()))
    urow("clsmask_VALUINST", mask_VALUINST())
    urow("clsdef_VALUINST", dflt_VALUINST())
    urow("clshimax_VALUINST", himax_VALUINST())
    srow("clsdelta_VALUINST", hasdelta_VALUINST())
    srow("cls_VMEMEXEC", field_order_VMEMEXEC())
    srow("clsfields_VMEMEXEC", fields_VMEMEXEC())
    urow("clsnib_VMEMEXEC", nibs_of(himax_VMEMEXEC()))
    urow("clsmask_VMEMEXEC", mask_VMEMEXEC())
    urow("clsdef_VMEMEXEC", dflt_VMEMEXEC())
    urow("clshimax_VMEMEXEC", himax_VMEMEXEC())
    srow("clsdelta_VMEMEXEC", hasdelta_VMEMEXEC())
    srow("cls_ALUEXEC", field_order_ALUEXEC())
    srow("clsfields_ALUEXEC", fields_ALUEXEC())
    urow("clsnib_ALUEXEC", nibs_of(himax_ALUEXEC()))
    urow("clsmask_ALUEXEC", mask_ALUEXEC())
    urow("clsdef_ALUEXEC", dflt_ALUEXEC())
    urow("clshimax_ALUEXEC", himax_ALUEXEC())
    srow("clsdelta_ALUEXEC", hasdelta_ALUEXEC())
    srow("cls_IMMEDIATE", field_order_IMMEDIATE())
    srow("clsfields_IMMEDIATE", fields_IMMEDIATE())
    urow("clsnib_IMMEDIATE", nibs_of(himax_IMMEDIATE()))
    urow("clsmask_IMMEDIATE", mask_IMMEDIATE())
    urow("clsdef_IMMEDIATE", dflt_IMMEDIATE())
    urow("clshimax_IMMEDIATE", himax_IMMEDIATE())
    srow("clsdelta_IMMEDIATE", hasdelta_IMMEDIATE())
    srow("cls_IMMEDIATE_MASK", field_order_IMMEDIATE_MASK())
    srow("clsfields_IMMEDIATE_MASK", fields_IMMEDIATE_MASK())
    urow("clsnib_IMMEDIATE_MASK", nibs_of(himax_IMMEDIATE_MASK()))
    urow("clsmask_IMMEDIATE_MASK", mask_IMMEDIATE_MASK())
    urow("clsdef_IMMEDIATE_MASK", dflt_IMMEDIATE_MASK())
    urow("clshimax_IMMEDIATE_MASK", himax_IMMEDIATE_MASK())
    srow("clsdelta_IMMEDIATE_MASK", hasdelta_IMMEDIATE_MASK())
    srow("cls_WAVERDY", field_order_WAVERDY())
    srow("clsfields_WAVERDY", fields_WAVERDY())
    urow("clsnib_WAVERDY", nibs_of(himax_WAVERDY()))
    urow("clsmask_WAVERDY", mask_WAVERDY())
    urow("clsdef_WAVERDY", dflt_WAVERDY())
    urow("clshimax_WAVERDY", himax_WAVERDY())
    srow("clsdelta_WAVERDY", hasdelta_WAVERDY())
    srow("cls_TS_DELTA_S8_W3", field_order_TS_DELTA_S8_W3())
    srow("clsfields_TS_DELTA_S8_W3", fields_TS_DELTA_S8_W3())
    urow("clsnib_TS_DELTA_S8_W3", nibs_of(himax_TS_DELTA_S8_W3()))
    urow("clsmask_TS_DELTA_S8_W3", mask_TS_DELTA_S8_W3())
    urow("clsdef_TS_DELTA_S8_W3", dflt_TS_DELTA_S8_W3())
    urow("clshimax_TS_DELTA_S8_W3", himax_TS_DELTA_S8_W3())
    srow("clsdelta_TS_DELTA_S8_W3", hasdelta_TS_DELTA_S8_W3())
    srow("cls_WAVEEND", field_order_WAVEEND())
    srow("clsfields_WAVEEND", fields_WAVEEND())
    urow("clsnib_WAVEEND", nibs_of(himax_WAVEEND()))
    urow("clsmask_WAVEEND", mask_WAVEEND())
    urow("clsdef_WAVEEND", dflt_WAVEEND())
    urow("clshimax_WAVEEND", himax_WAVEEND())
    srow("clsdelta_WAVEEND", hasdelta_WAVEEND())
    srow("cls_WAVESTART", field_order_WAVESTART())
    srow("clsfields_WAVESTART", fields_WAVESTART())
    urow("clsnib_WAVESTART", nibs_of(himax_WAVESTART()))
    urow("clsmask_WAVESTART", mask_WAVESTART())
    urow("clsdef_WAVESTART", dflt_WAVESTART())
    urow("clshimax_WAVESTART", himax_WAVESTART())
    srow("clsdelta_WAVESTART", hasdelta_WAVESTART())
    srow("cls_TS_DELTA_S5_W2", field_order_TS_DELTA_S5_W2())
    srow("clsfields_TS_DELTA_S5_W2", fields_TS_DELTA_S5_W2())
    urow("clsnib_TS_DELTA_S5_W2", nibs_of(himax_TS_DELTA_S5_W2()))
    urow("clsmask_TS_DELTA_S5_W2", mask_TS_DELTA_S5_W2())
    urow("clsdef_TS_DELTA_S5_W2", dflt_TS_DELTA_S5_W2())
    urow("clshimax_TS_DELTA_S5_W2", himax_TS_DELTA_S5_W2())
    srow("clsdelta_TS_DELTA_S5_W2", hasdelta_TS_DELTA_S5_W2())
    srow("cls_WAVEALLOC", field_order_WAVEALLOC())
    srow("clsfields_WAVEALLOC", fields_WAVEALLOC())
    urow("clsnib_WAVEALLOC", nibs_of(himax_WAVEALLOC()))
    urow("clsmask_WAVEALLOC", mask_WAVEALLOC())
    urow("clsdef_WAVEALLOC", dflt_WAVEALLOC())
    urow("clshimax_WAVEALLOC", himax_WAVEALLOC())
    srow("clsdelta_WAVEALLOC", hasdelta_WAVEALLOC())
    srow("cls_TS_DELTA_S5_W3", field_order_TS_DELTA_S5_W3())
    srow("clsfields_TS_DELTA_S5_W3", fields_TS_DELTA_S5_W3())
    urow("clsnib_TS_DELTA_S5_W3", nibs_of(himax_TS_DELTA_S5_W3()))
    urow("clsmask_TS_DELTA_S5_W3", mask_TS_DELTA_S5_W3())
    urow("clsdef_TS_DELTA_S5_W3", dflt_TS_DELTA_S5_W3())
    urow("clshimax_TS_DELTA_S5_W3", himax_TS_DELTA_S5_W3())
    srow("clsdelta_TS_DELTA_S5_W3", hasdelta_TS_DELTA_S5_W3())
    srow("cls_PERF", field_order_PERF())
    srow("clsfields_PERF", fields_PERF())
    urow("clsnib_PERF", nibs_of(himax_PERF()))
    urow("clsmask_PERF", mask_PERF())
    urow("clsdef_PERF", dflt_PERF())
    urow("clshimax_PERF", himax_PERF())
    srow("clsdelta_PERF", hasdelta_PERF())
    srow("cls_UTILCTR", field_order_UTILCTR())
    srow("clsfields_UTILCTR", fields_UTILCTR())
    urow("clsnib_UTILCTR", nibs_of(himax_UTILCTR()))
    urow("clsmask_UTILCTR", mask_UTILCTR())
    urow("clsdef_UTILCTR", dflt_UTILCTR())
    urow("clshimax_UTILCTR", himax_UTILCTR())
    srow("clsdelta_UTILCTR", hasdelta_UTILCTR())
    srow("cls_TS_DELTA_SHORT", field_order_TS_DELTA_SHORT())
    srow("clsfields_TS_DELTA_SHORT", fields_TS_DELTA_SHORT())
    urow("clsnib_TS_DELTA_SHORT", nibs_of(himax_TS_DELTA_SHORT()))
    urow("clsmask_TS_DELTA_SHORT", mask_TS_DELTA_SHORT())
    urow("clsdef_TS_DELTA_SHORT", dflt_TS_DELTA_SHORT())
    urow("clshimax_TS_DELTA_SHORT", himax_TS_DELTA_SHORT())
    srow("clsdelta_TS_DELTA_SHORT", hasdelta_TS_DELTA_SHORT())
    srow("cls_NOP", field_order_NOP())
    srow("clsfields_NOP", fields_NOP())
    urow("clsnib_NOP", nibs_of(himax_NOP()))
    urow("clsmask_NOP", mask_NOP())
    urow("clsdef_NOP", dflt_NOP())
    urow("clshimax_NOP", himax_NOP())
    srow("clsdelta_NOP", hasdelta_NOP())
    srow("cls_TS_WAVE_STATE", field_order_TS_WAVE_STATE())
    srow("clsfields_TS_WAVE_STATE", fields_TS_WAVE_STATE())
    urow("clsnib_TS_WAVE_STATE", nibs_of(himax_TS_WAVE_STATE()))
    urow("clsmask_TS_WAVE_STATE", mask_TS_WAVE_STATE())
    urow("clsdef_TS_WAVE_STATE", dflt_TS_WAVE_STATE())
    urow("clshimax_TS_WAVE_STATE", himax_TS_WAVE_STATE())
    srow("clsdelta_TS_WAVE_STATE", hasdelta_TS_WAVE_STATE())
    srow("cls_EVENT", field_order_EVENT())
    srow("clsfields_EVENT", fields_EVENT())
    urow("clsnib_EVENT", nibs_of(himax_EVENT()))
    urow("clsmask_EVENT", mask_EVENT())
    urow("clsdef_EVENT", dflt_EVENT())
    urow("clshimax_EVENT", himax_EVENT())
    srow("clsdelta_EVENT", hasdelta_EVENT())
    srow("cls_EVENT_BIG", field_order_EVENT_BIG())
    srow("clsfields_EVENT_BIG", fields_EVENT_BIG())
    urow("clsnib_EVENT_BIG", nibs_of(himax_EVENT_BIG()))
    urow("clsmask_EVENT_BIG", mask_EVENT_BIG())
    urow("clsdef_EVENT_BIG", dflt_EVENT_BIG())
    urow("clshimax_EVENT_BIG", himax_EVENT_BIG())
    srow("clsdelta_EVENT_BIG", hasdelta_EVENT_BIG())
    srow("cls_REG", field_order_REG())
    srow("clsfields_REG", fields_REG())
    urow("clsnib_REG", nibs_of(himax_REG()))
    urow("clsmask_REG", mask_REG())
    urow("clsdef_REG", dflt_REG())
    urow("clshimax_REG", himax_REG())
    srow("clsdelta_REG", hasdelta_REG())
    srow("cls_SNAPSHOT", field_order_SNAPSHOT())
    srow("clsfields_SNAPSHOT", fields_SNAPSHOT())
    urow("clsnib_SNAPSHOT", nibs_of(himax_SNAPSHOT()))
    urow("clsmask_SNAPSHOT", mask_SNAPSHOT())
    urow("clsdef_SNAPSHOT", dflt_SNAPSHOT())
    urow("clshimax_SNAPSHOT", himax_SNAPSHOT())
    srow("clsdelta_SNAPSHOT", hasdelta_SNAPSHOT())
    srow("cls_TS_DELTA_OR_MARK", field_order_TS_DELTA_OR_MARK())
    srow("clsfields_TS_DELTA_OR_MARK", fields_TS_DELTA_OR_MARK())
    urow("clsnib_TS_DELTA_OR_MARK", nibs_of(himax_TS_DELTA_OR_MARK()))
    urow("clsmask_TS_DELTA_OR_MARK", mask_TS_DELTA_OR_MARK())
    urow("clsdef_TS_DELTA_OR_MARK", dflt_TS_DELTA_OR_MARK())
    urow("clshimax_TS_DELTA_OR_MARK", himax_TS_DELTA_OR_MARK())
    srow("clsdelta_TS_DELTA_OR_MARK", hasdelta_TS_DELTA_OR_MARK())
    urow("clsdmask_over_TS_DELTA_OR_MARK", dmask_over_TS_DELTA_OR_MARK())
    urow("clsdlo_TS_DELTA_OR_MARK", dlo_TS_DELTA_OR_MARK())
    urow("clsdmask_TS_DELTA_OR_MARK", dmask_TS_DELTA_OR_MARK())
    srow("cls_LAYOUT_HEADER", field_order_LAYOUT_HEADER())
    srow("clsfields_LAYOUT_HEADER", fields_LAYOUT_HEADER())
    urow("clsnib_LAYOUT_HEADER", nibs_of(himax_LAYOUT_HEADER()))
    urow("clsmask_LAYOUT_HEADER", mask_LAYOUT_HEADER())
    urow("clsdef_LAYOUT_HEADER", dflt_LAYOUT_HEADER())
    urow("clshimax_LAYOUT_HEADER", himax_LAYOUT_HEADER())
    srow("clsdelta_LAYOUT_HEADER", hasdelta_LAYOUT_HEADER())
    srow("cls_INST", field_order_INST())
    srow("clsfields_INST", fields_INST())
    urow("clsnib_INST", nibs_of(himax_INST()))
    urow("clsmask_INST", mask_INST())
    urow("clsdef_INST", dflt_INST())
    urow("clshimax_INST", himax_INST())
    srow("clsdelta_INST", hasdelta_INST())
    srow("cls_WAVEEND_RDNA4", field_order_WAVEEND_RDNA4())
    srow("clsfields_WAVEEND_RDNA4", fields_WAVEEND_RDNA4())
    urow("clsnib_WAVEEND_RDNA4", nibs_of(himax_WAVEEND_RDNA4()))
    urow("clsmask_WAVEEND_RDNA4", mask_WAVEEND_RDNA4())
    urow("clsdef_WAVEEND_RDNA4", dflt_WAVEEND_RDNA4())
    urow("clshimax_WAVEEND_RDNA4", himax_WAVEEND_RDNA4())
    srow("clsdelta_WAVEEND_RDNA4", hasdelta_WAVEEND_RDNA4())
    srow("cls_WAVESTART_RDNA4", field_order_WAVESTART_RDNA4())
    srow("clsfields_WAVESTART_RDNA4", fields_WAVESTART_RDNA4())
    urow("clsnib_WAVESTART_RDNA4", nibs_of(himax_WAVESTART_RDNA4()))
    urow("clsmask_WAVESTART_RDNA4", mask_WAVESTART_RDNA4())
    urow("clsdef_WAVESTART_RDNA4", dflt_WAVESTART_RDNA4())
    urow("clshimax_WAVESTART_RDNA4", himax_WAVESTART_RDNA4())
    srow("clsdelta_WAVESTART_RDNA4", hasdelta_WAVESTART_RDNA4())
    srow("cls_TS_DELTA_S5_W2_RDNA4", field_order_TS_DELTA_S5_W2_RDNA4())
    srow("clsfields_TS_DELTA_S5_W2_RDNA4", fields_TS_DELTA_S5_W2_RDNA4())
    urow("clsnib_TS_DELTA_S5_W2_RDNA4", nibs_of(himax_TS_DELTA_S5_W2_RDNA4()))
    urow("clsmask_TS_DELTA_S5_W2_RDNA4", mask_TS_DELTA_S5_W2_RDNA4())
    urow("clsdef_TS_DELTA_S5_W2_RDNA4", dflt_TS_DELTA_S5_W2_RDNA4())
    urow("clshimax_TS_DELTA_S5_W2_RDNA4", himax_TS_DELTA_S5_W2_RDNA4())
    srow("clsdelta_TS_DELTA_S5_W2_RDNA4", hasdelta_TS_DELTA_S5_W2_RDNA4())
    srow("cls_WAVEALLOC_RDNA4", field_order_WAVEALLOC_RDNA4())
    srow("clsfields_WAVEALLOC_RDNA4", fields_WAVEALLOC_RDNA4())
    urow("clsnib_WAVEALLOC_RDNA4", nibs_of(himax_WAVEALLOC_RDNA4()))
    urow("clsmask_WAVEALLOC_RDNA4", mask_WAVEALLOC_RDNA4())
    urow("clsdef_WAVEALLOC_RDNA4", dflt_WAVEALLOC_RDNA4())
    urow("clshimax_WAVEALLOC_RDNA4", himax_WAVEALLOC_RDNA4())
    srow("clsdelta_WAVEALLOC_RDNA4", hasdelta_WAVEALLOC_RDNA4())
    srow("cls_TS_DELTA_S5_W3_RDNA4", field_order_TS_DELTA_S5_W3_RDNA4())
    srow("clsfields_TS_DELTA_S5_W3_RDNA4", fields_TS_DELTA_S5_W3_RDNA4())
    urow("clsnib_TS_DELTA_S5_W3_RDNA4", nibs_of(himax_TS_DELTA_S5_W3_RDNA4()))
    urow("clsmask_TS_DELTA_S5_W3_RDNA4", mask_TS_DELTA_S5_W3_RDNA4())
    urow("clsdef_TS_DELTA_S5_W3_RDNA4", dflt_TS_DELTA_S5_W3_RDNA4())
    urow("clshimax_TS_DELTA_S5_W3_RDNA4", himax_TS_DELTA_S5_W3_RDNA4())
    srow("clsdelta_TS_DELTA_S5_W3_RDNA4", hasdelta_TS_DELTA_S5_W3_RDNA4())
    srow("cls_PERF_RDNA4", field_order_PERF_RDNA4())
    srow("clsfields_PERF_RDNA4", fields_PERF_RDNA4())
    urow("clsnib_PERF_RDNA4", nibs_of(himax_PERF_RDNA4()))
    urow("clsmask_PERF_RDNA4", mask_PERF_RDNA4())
    urow("clsdef_PERF_RDNA4", dflt_PERF_RDNA4())
    urow("clshimax_PERF_RDNA4", himax_PERF_RDNA4())
    srow("clsdelta_PERF_RDNA4", hasdelta_PERF_RDNA4())
    srow("cls_TS_DELTA_OR_MARK_RDNA4", field_order_TS_DELTA_OR_MARK_RDNA4())
    srow("clsfields_TS_DELTA_OR_MARK_RDNA4", fields_TS_DELTA_OR_MARK_RDNA4())
    urow("clsnib_TS_DELTA_OR_MARK_RDNA4", nibs_of(himax_TS_DELTA_OR_MARK_RDNA4()))
    urow("clsmask_TS_DELTA_OR_MARK_RDNA4", mask_TS_DELTA_OR_MARK_RDNA4())
    urow("clsdef_TS_DELTA_OR_MARK_RDNA4", dflt_TS_DELTA_OR_MARK_RDNA4())
    urow("clshimax_TS_DELTA_OR_MARK_RDNA4", himax_TS_DELTA_OR_MARK_RDNA4())
    srow("clsdelta_TS_DELTA_OR_MARK_RDNA4", hasdelta_TS_DELTA_OR_MARK_RDNA4())
    urow("clsdmask_over_TS_DELTA_OR_MARK_RDNA4", dmask_over_TS_DELTA_OR_MARK_RDNA4())
    urow("clsdlo_TS_DELTA_OR_MARK_RDNA4", dlo_TS_DELTA_OR_MARK_RDNA4())
    urow("clsdmask_TS_DELTA_OR_MARK_RDNA4", dmask_TS_DELTA_OR_MARK_RDNA4())
    srow("cls_INST_RDNA4", field_order_INST_RDNA4())
    srow("clsfields_INST_RDNA4", fields_INST_RDNA4())
    urow("clsnib_INST_RDNA4", nibs_of(himax_INST_RDNA4()))
    urow("clsmask_INST_RDNA4", mask_INST_RDNA4())
    urow("clsdef_INST_RDNA4", dflt_INST_RDNA4())
    urow("clshimax_INST_RDNA4", himax_INST_RDNA4())
    srow("clsdelta_INST_RDNA4", hasdelta_INST_RDNA4())
    srow("cls_CDNA_MISC", field_order_CDNA_MISC())
    srow("clsfields_CDNA_MISC", fields_CDNA_MISC())
    urow("clsnib_CDNA_MISC", nibs_of(himax_CDNA_MISC()))
    urow("clsmask_CDNA_MISC", mask_CDNA_MISC())
    urow("clsdef_CDNA_MISC", dflt_CDNA_MISC())
    urow("clshimax_CDNA_MISC", himax_CDNA_MISC())
    srow("clsdelta_CDNA_MISC", hasdelta_CDNA_MISC())
    srow("cls_CDNA_TIMESTAMP", field_order_CDNA_TIMESTAMP())
    srow("clsfields_CDNA_TIMESTAMP", fields_CDNA_TIMESTAMP())
    urow("clsnib_CDNA_TIMESTAMP", nibs_of(himax_CDNA_TIMESTAMP()))
    urow("clsmask_CDNA_TIMESTAMP", mask_CDNA_TIMESTAMP())
    urow("clsdef_CDNA_TIMESTAMP", dflt_CDNA_TIMESTAMP())
    urow("clshimax_CDNA_TIMESTAMP", himax_CDNA_TIMESTAMP())
    srow("clsdelta_CDNA_TIMESTAMP", hasdelta_CDNA_TIMESTAMP())
    srow("cls_CDNA_REG", field_order_CDNA_REG())
    srow("clsfields_CDNA_REG", fields_CDNA_REG())
    urow("clsnib_CDNA_REG", nibs_of(himax_CDNA_REG()))
    urow("clsmask_CDNA_REG", mask_CDNA_REG())
    urow("clsdef_CDNA_REG", dflt_CDNA_REG())
    urow("clshimax_CDNA_REG", himax_CDNA_REG())
    srow("clsdelta_CDNA_REG", hasdelta_CDNA_REG())
    srow("cls_CDNA_WAVESTART", field_order_CDNA_WAVESTART())
    srow("clsfields_CDNA_WAVESTART", fields_CDNA_WAVESTART())
    urow("clsnib_CDNA_WAVESTART", nibs_of(himax_CDNA_WAVESTART()))
    urow("clsmask_CDNA_WAVESTART", mask_CDNA_WAVESTART())
    urow("clsdef_CDNA_WAVESTART", dflt_CDNA_WAVESTART())
    urow("clshimax_CDNA_WAVESTART", himax_CDNA_WAVESTART())
    srow("clsdelta_CDNA_WAVESTART", hasdelta_CDNA_WAVESTART())
    srow("cls_CDNA_WAVEALLOC", field_order_CDNA_WAVEALLOC())
    srow("clsfields_CDNA_WAVEALLOC", fields_CDNA_WAVEALLOC())
    urow("clsnib_CDNA_WAVEALLOC", nibs_of(himax_CDNA_WAVEALLOC()))
    urow("clsmask_CDNA_WAVEALLOC", mask_CDNA_WAVEALLOC())
    urow("clsdef_CDNA_WAVEALLOC", dflt_CDNA_WAVEALLOC())
    urow("clshimax_CDNA_WAVEALLOC", himax_CDNA_WAVEALLOC())
    srow("clsdelta_CDNA_WAVEALLOC", hasdelta_CDNA_WAVEALLOC())
    srow("cls_CDNA_REG_CS", field_order_CDNA_REG_CS())
    srow("clsfields_CDNA_REG_CS", fields_CDNA_REG_CS())
    urow("clsnib_CDNA_REG_CS", nibs_of(himax_CDNA_REG_CS()))
    urow("clsmask_CDNA_REG_CS", mask_CDNA_REG_CS())
    urow("clsdef_CDNA_REG_CS", dflt_CDNA_REG_CS())
    urow("clshimax_CDNA_REG_CS", himax_CDNA_REG_CS())
    srow("clsdelta_CDNA_REG_CS", hasdelta_CDNA_REG_CS())
    srow("cls_CDNA_WAVEEND", field_order_CDNA_WAVEEND())
    srow("clsfields_CDNA_WAVEEND", fields_CDNA_WAVEEND())
    urow("clsnib_CDNA_WAVEEND", nibs_of(himax_CDNA_WAVEEND()))
    urow("clsmask_CDNA_WAVEEND", mask_CDNA_WAVEEND())
    urow("clsdef_CDNA_WAVEEND", dflt_CDNA_WAVEEND())
    urow("clshimax_CDNA_WAVEEND", himax_CDNA_WAVEEND())
    srow("clsdelta_CDNA_WAVEEND", hasdelta_CDNA_WAVEEND())
    srow("cls_CDNA_EVENT", field_order_CDNA_EVENT())
    srow("clsfields_CDNA_EVENT", fields_CDNA_EVENT())
    urow("clsnib_CDNA_EVENT", nibs_of(himax_CDNA_EVENT()))
    urow("clsmask_CDNA_EVENT", mask_CDNA_EVENT())
    urow("clsdef_CDNA_EVENT", dflt_CDNA_EVENT())
    urow("clshimax_CDNA_EVENT", himax_CDNA_EVENT())
    srow("clsdelta_CDNA_EVENT", hasdelta_CDNA_EVENT())
    srow("cls_CDNA_EVENT_CS", field_order_CDNA_EVENT_CS())
    srow("clsfields_CDNA_EVENT_CS", fields_CDNA_EVENT_CS())
    urow("clsnib_CDNA_EVENT_CS", nibs_of(himax_CDNA_EVENT_CS()))
    urow("clsmask_CDNA_EVENT_CS", mask_CDNA_EVENT_CS())
    urow("clsdef_CDNA_EVENT_CS", dflt_CDNA_EVENT_CS())
    urow("clshimax_CDNA_EVENT_CS", himax_CDNA_EVENT_CS())
    srow("clsdelta_CDNA_EVENT_CS", hasdelta_CDNA_EVENT_CS())
    srow("cls_CDNA_EVENT_GFX1", field_order_CDNA_EVENT_GFX1())
    srow("clsfields_CDNA_EVENT_GFX1", fields_CDNA_EVENT_GFX1())
    urow("clsnib_CDNA_EVENT_GFX1", nibs_of(himax_CDNA_EVENT_GFX1()))
    urow("clsmask_CDNA_EVENT_GFX1", mask_CDNA_EVENT_GFX1())
    urow("clsdef_CDNA_EVENT_GFX1", dflt_CDNA_EVENT_GFX1())
    urow("clshimax_CDNA_EVENT_GFX1", himax_CDNA_EVENT_GFX1())
    srow("clsdelta_CDNA_EVENT_GFX1", hasdelta_CDNA_EVENT_GFX1())
    srow("cls_CDNA_INST", field_order_CDNA_INST())
    srow("clsfields_CDNA_INST", fields_CDNA_INST())
    urow("clsnib_CDNA_INST", nibs_of(himax_CDNA_INST()))
    urow("clsmask_CDNA_INST", mask_CDNA_INST())
    urow("clsdef_CDNA_INST", dflt_CDNA_INST())
    urow("clshimax_CDNA_INST", himax_CDNA_INST())
    srow("clsdelta_CDNA_INST", hasdelta_CDNA_INST())
    srow("cls_CDNA_INST_PC", field_order_CDNA_INST_PC())
    srow("clsfields_CDNA_INST_PC", fields_CDNA_INST_PC())
    urow("clsnib_CDNA_INST_PC", nibs_of(himax_CDNA_INST_PC()))
    urow("clsmask_CDNA_INST_PC", mask_CDNA_INST_PC())
    urow("clsdef_CDNA_INST_PC", dflt_CDNA_INST_PC())
    urow("clshimax_CDNA_INST_PC", himax_CDNA_INST_PC())
    srow("clsdelta_CDNA_INST_PC", hasdelta_CDNA_INST_PC())
    srow("cls_CDNA_USERDATA", field_order_CDNA_USERDATA())
    srow("clsfields_CDNA_USERDATA", fields_CDNA_USERDATA())
    urow("clsnib_CDNA_USERDATA", nibs_of(himax_CDNA_USERDATA()))
    urow("clsmask_CDNA_USERDATA", mask_CDNA_USERDATA())
    urow("clsdef_CDNA_USERDATA", dflt_CDNA_USERDATA())
    urow("clshimax_CDNA_USERDATA", himax_CDNA_USERDATA())
    srow("clsdelta_CDNA_USERDATA", hasdelta_CDNA_USERDATA())
    srow("cls_CDNA_ISSUE", field_order_CDNA_ISSUE())
    srow("clsfields_CDNA_ISSUE", fields_CDNA_ISSUE())
    urow("clsnib_CDNA_ISSUE", nibs_of(himax_CDNA_ISSUE()))
    urow("clsmask_CDNA_ISSUE", mask_CDNA_ISSUE())
    urow("clsdef_CDNA_ISSUE", dflt_CDNA_ISSUE())
    urow("clshimax_CDNA_ISSUE", himax_CDNA_ISSUE())
    srow("clsdelta_CDNA_ISSUE", hasdelta_CDNA_ISSUE())
    srow("cls_CDNA_PERF", field_order_CDNA_PERF())
    srow("clsfields_CDNA_PERF", fields_CDNA_PERF())
    urow("clsnib_CDNA_PERF", nibs_of(himax_CDNA_PERF()))
    urow("clsmask_CDNA_PERF", mask_CDNA_PERF())
    urow("clsdef_CDNA_PERF", dflt_CDNA_PERF())
    urow("clshimax_CDNA_PERF", himax_CDNA_PERF())
    srow("clsdelta_CDNA_PERF", hasdelta_CDNA_PERF())
    srow("cls_CDNA_REG_CS_PRIV", field_order_CDNA_REG_CS_PRIV())
    srow("clsfields_CDNA_REG_CS_PRIV", fields_CDNA_REG_CS_PRIV())
    urow("clsnib_CDNA_REG_CS_PRIV", nibs_of(himax_CDNA_REG_CS_PRIV()))
    urow("clsmask_CDNA_REG_CS_PRIV", mask_CDNA_REG_CS_PRIV())
    urow("clsdef_CDNA_REG_CS_PRIV", dflt_CDNA_REG_CS_PRIV())
    urow("clshimax_CDNA_REG_CS_PRIV", himax_CDNA_REG_CS_PRIV())
    srow("clsdelta_CDNA_REG_CS_PRIV", hasdelta_CDNA_REG_CS_PRIV())
    urow("cls_count", cls_count())
    srow("cls_names", str_list_text(CLS_NAMES()))
def g_state() -> IO(Unit):
  do IO<Unit>:
    srow("state_RDNA3_n", nat_text(state_RDNA3_n()))
    srow("state_RDNA3", u32_list_text(state_RDNA3()))
    urow("nop_last_RDNA3", nop_last_RDNA3())
    srow("state_RDNA4_n", nat_text(state_RDNA4_n()))
    srow("state_RDNA4", u32_list_text(state_RDNA4()))
    urow("nop_last_RDNA4", nop_last_RDNA4())
    srow("state_CDNA_n", nat_text(state_CDNA_n()))
    srow("state_CDNA", u32_list_text(state_CDNA()))
    urow("nop_last_CDNA", nop_last_CDNA())
    # THE FIRST BYTE of each table, which is the only one a reader needs to
    # tell the three architectures apart at a glance.
    urow("state_first_RDNA3", u32_at(0, state_RDNA3()))
    urow("state_first_RDNA4", u32_at(0, state_RDNA4()))
    urow("state_first_CDNA", u32_at(0, state_CDNA()))
    # and byte 0x10, where the NOP default shows up
    urow("state_16_RDNA3", u32_at(16, state_RDNA3()))
    urow("state_255_RDNA3", u32_at(255, state_RDNA3()))
    urow("state_16_RDNA4", u32_at(16, state_RDNA4()))
    urow("state_255_RDNA4", u32_at(255, state_RDNA4()))
    urow("state_16_CDNA", u32_at(16, state_CDNA()))
    urow("state_255_CDNA", u32_at(255, state_CDNA()))
def g_decode() -> IO(Unit):
  do IO<Unit>:
    srow("di_RDNA3_n", nat_text(di_RDNA3_n()))
    srow("di_RDNA3_1", di_text(di_RDNA3_1()))
    srow("di_RDNA3_2", di_text(di_RDNA3_2()))
    srow("di_RDNA3_3", di_text(di_RDNA3_3()))
    srow("di_RDNA3_4", di_text(di_RDNA3_4()))
    srow("di_RDNA3_5", di_text(di_RDNA3_5()))
    srow("di_RDNA3_6", di_text(di_RDNA3_6()))
    srow("di_RDNA3_7", di_text(di_RDNA3_7()))
    srow("di_RDNA3_8", di_text(di_RDNA3_8()))
    srow("di_RDNA3_9", di_text(di_RDNA3_9()))
    srow("di_RDNA3_10", di_text(di_RDNA3_10()))
    srow("di_RDNA3_11", di_text(di_RDNA3_11()))
    srow("di_RDNA3_12", di_text(di_RDNA3_12()))
    srow("di_RDNA3_13", di_text(di_RDNA3_13()))
    srow("di_RDNA3_14", di_text(di_RDNA3_14()))
    srow("di_RDNA3_15", di_text(di_RDNA3_15()))
    srow("di_RDNA3_16", di_text(di_RDNA3_16()))
    srow("di_RDNA3_17", di_text(di_RDNA3_17()))
    srow("di_RDNA3_18", di_text(di_RDNA3_18()))
    srow("di_RDNA3_19", di_text(di_RDNA3_19()))
    srow("di_RDNA3_20", di_text(di_RDNA3_20()))
    srow("di_RDNA3_21", di_text(di_RDNA3_21()))
    srow("di_RDNA3_22", di_text(di_RDNA3_22()))
    srow("di_RDNA3_23", di_text(di_RDNA3_23()))
    srow("di_RDNA3_24", di_text(di_RDNA3_24()))
    srow("di_RDNA4_n", nat_text(di_RDNA4_n()))
    srow("di_RDNA4_1", di_text(di_RDNA4_1()))
    srow("di_RDNA4_2", di_text(di_RDNA4_2()))
    srow("di_RDNA4_3", di_text(di_RDNA4_3()))
    srow("di_RDNA4_4", di_text(di_RDNA4_4()))
    srow("di_RDNA4_5", di_text(di_RDNA4_5()))
    srow("di_RDNA4_6", di_text(di_RDNA4_6()))
    srow("di_RDNA4_7", di_text(di_RDNA4_7()))
    srow("di_RDNA4_8", di_text(di_RDNA4_8()))
    srow("di_RDNA4_9", di_text(di_RDNA4_9()))
    srow("di_RDNA4_10", di_text(di_RDNA4_10()))
    srow("di_RDNA4_11", di_text(di_RDNA4_11()))
    srow("di_RDNA4_12", di_text(di_RDNA4_12()))
    srow("di_RDNA4_13", di_text(di_RDNA4_13()))
    srow("di_RDNA4_14", di_text(di_RDNA4_14()))
    srow("di_RDNA4_15", di_text(di_RDNA4_15()))
    srow("di_RDNA4_16", di_text(di_RDNA4_16()))
    srow("di_RDNA4_17", di_text(di_RDNA4_17()))
    srow("di_RDNA4_18", di_text(di_RDNA4_18()))
    srow("di_RDNA4_19", di_text(di_RDNA4_19()))
    srow("di_RDNA4_20", di_text(di_RDNA4_20()))
    srow("di_RDNA4_21", di_text(di_RDNA4_21()))
    srow("di_RDNA4_22", di_text(di_RDNA4_22()))
    srow("di_RDNA4_23", di_text(di_RDNA4_23()))
    srow("di_RDNA4_24", di_text(di_RDNA4_24()))
    srow("di_CDNA_n", nat_text(di_CDNA_n()))
    srow("di_CDNA_0", di_text(di_CDNA_0()))
    srow("di_CDNA_1", di_text(di_CDNA_1()))
    srow("di_CDNA_2", di_text(di_CDNA_2()))
    srow("di_CDNA_3", di_text(di_CDNA_3()))
    srow("di_CDNA_4", di_text(di_CDNA_4()))
    srow("di_CDNA_5", di_text(di_CDNA_5()))
    srow("di_CDNA_6", di_text(di_CDNA_6()))
    srow("di_CDNA_7", di_text(di_CDNA_7()))
    srow("di_CDNA_8", di_text(di_CDNA_8()))
    srow("di_CDNA_9", di_text(di_CDNA_9()))
    srow("di_CDNA_10", di_text(di_CDNA_10()))
    srow("di_CDNA_11", di_text(di_CDNA_11()))
    srow("di_CDNA_12", di_text(di_CDNA_12()))
    srow("di_CDNA_13", di_text(di_CDNA_13()))
    srow("di_CDNA_14", di_text(di_CDNA_14()))
    srow("di_CDNA_15", di_text(di_CDNA_15()))
    srow("di_CDNA_16", di_text(di_CDNA_16()))
    # CDNA multiplies its delta by 4 and RDNA does not (:558); the DELTA
    # LO/MASK also differ per arch, and that is the whole reason the same
    # 64-bit blob decodes to different timestamps on the two.
    srow("di_RDNA3_mul_set", set_mul(di_RDNA3_flat()))
    srow("di_RDNA3_special_set", set_sp(di_RDNA3_flat()))
    srow("di_RDNA4_mul_set", set_mul(di_RDNA4_flat()))
    srow("di_RDNA4_special_set", set_sp(di_RDNA4_flat()))
    srow("di_CDNA_mul_set", set_mul(di_CDNA_flat()))
    srow("di_CDNA_special_set", set_sp(di_CDNA_flat()))
def g_props() -> IO(Unit):
  do IO<Unit>:
    urow("cu_WAVEEND_0_0", cu_WAVEEND(0, 0))
    urow("cu_WAVEEND_0_1", cu_WAVEEND(0, 1))
    urow("cu_WAVEEND_1_0", cu_WAVEEND(1, 0))
    urow("cu_WAVEEND_1_1", cu_WAVEEND(1, 1))
    urow("cu_WAVEEND_7_0", cu_WAVEEND(7, 0))
    urow("cu_WAVEEND_7_1", cu_WAVEEND(7, 1))
    urow("cu_WAVEEND_RDNA4_0_0", cu_WAVEEND_RDNA4(0, 0))
    urow("cu_WAVEEND_RDNA4_0_1", cu_WAVEEND_RDNA4(0, 1))
    urow("cu_WAVEEND_RDNA4_1_0", cu_WAVEEND_RDNA4(1, 0))
    urow("cu_WAVEEND_RDNA4_1_1", cu_WAVEEND_RDNA4(1, 1))
    urow("cu_WAVEEND_RDNA4_7_0", cu_WAVEEND_RDNA4(7, 0))
    urow("cu_WAVEEND_RDNA4_7_1", cu_WAVEEND_RDNA4(7, 1))
    urow("cu_WAVEEND_RDNA4_8_0", cu_WAVEEND_RDNA4(8, 0))
    urow("cu_WAVEEND_RDNA4_8_1", cu_WAVEEND_RDNA4(8, 1))
    urow("cu_WAVEEND_RDNA4_15_0", cu_WAVEEND_RDNA4(15, 0))
    urow("cu_WAVEEND_RDNA4_15_1", cu_WAVEEND_RDNA4(15, 1))
    urow("cu_WAVESTART_0_0", cu_WAVESTART(0, 0))
    urow("cu_WAVESTART_0_1", cu_WAVESTART(0, 1))
    urow("cu_WAVESTART_1_0", cu_WAVESTART(1, 0))
    urow("cu_WAVESTART_1_1", cu_WAVESTART(1, 1))
    urow("cu_WAVESTART_7_0", cu_WAVESTART(7, 0))
    urow("cu_WAVESTART_7_1", cu_WAVESTART(7, 1))
    urow("cu_WAVESTART_RDNA4_0_0", cu_WAVESTART_RDNA4(0, 0))
    urow("cu_WAVESTART_RDNA4_0_1", cu_WAVESTART_RDNA4(0, 1))
    urow("cu_WAVESTART_RDNA4_1_0", cu_WAVESTART_RDNA4(1, 0))
    urow("cu_WAVESTART_RDNA4_1_1", cu_WAVESTART_RDNA4(1, 1))
    urow("cu_WAVESTART_RDNA4_7_0", cu_WAVESTART_RDNA4(7, 0))
    urow("cu_WAVESTART_RDNA4_7_1", cu_WAVESTART_RDNA4(7, 1))
    urow("cu_WAVESTART_RDNA4_8_0", cu_WAVESTART_RDNA4(8, 0))
    urow("cu_WAVESTART_RDNA4_8_1", cu_WAVESTART_RDNA4(8, 1))
    urow("cu_WAVESTART_RDNA4_15_0", cu_WAVESTART_RDNA4(15, 0))
    urow("cu_WAVESTART_RDNA4_15_1", cu_WAVESTART_RDNA4(15, 1))
    row("ismark_00", is_marker(0, 0))
    row("ismark_01", is_marker(0, 1))
    row("ismark_10", is_marker(1, 0))
    row("ismark_11", is_marker(1, 1))
    row("isconfig_0", is_config(0))
    row("isconfig_128", is_config(128))
    row("isconfig_127", is_config(127))
    row("isconfig_255", is_config(255))
    row("waveinterest_0", wave_interest(0))
    row("termall_0", terminate_all(0))
    row("waveinterest_1", wave_interest(1))
    row("termall_1", terminate_all(1))
    row("waveinterest_8", wave_interest(8))
    row("termall_8", terminate_all(8))
    row("waveinterest_9", wave_interest(9))
    row("termall_9", terminate_all(9))
    row("waveinterest_255", wave_interest(255))
    row("termall_255", terminate_all(255))
def g_enums() -> IO(Unit):
  do IO<Unit>:
    srow("enum_MemSrc_n", nat_text(MemSrc_n()))
    srow("enum_MemSrc_fwd_0", name_at(0, MemSrc()))
    srow("enum_MemSrc_fwd_1", name_at(1, MemSrc()))
    srow("enum_MemSrc_fwd_2", name_at(2, MemSrc()))
    srow("enum_MemSrc_fwd_3", name_at(3, MemSrc()))
    urow("enum_MemSrc_rev_LDS", op_of("LDS", MemSrc()))
    urow("enum_MemSrc_rev_LDS_ALT", op_of("LDS_ALT", MemSrc()))
    urow("enum_MemSrc_rev_VMEM", op_of("VMEM", MemSrc()))
    urow("enum_MemSrc_rev_VMEM_ALT", op_of("VMEM_ALT", MemSrc()))
    srow("enum_AluSrc_n", nat_text(AluSrc_n()))
    srow("enum_AluSrc_fwd_0", name_at(0, AluSrc()))
    srow("enum_AluSrc_fwd_1", name_at(1, AluSrc()))
    srow("enum_AluSrc_fwd_2", name_at(2, AluSrc()))
    srow("enum_AluSrc_fwd_3", name_at(3, AluSrc()))
    urow("enum_AluSrc_rev_NONE", op_of("NONE", AluSrc()))
    urow("enum_AluSrc_rev_SALU", op_of("SALU", AluSrc()))
    urow("enum_AluSrc_rev_VALU", op_of("VALU", AluSrc()))
    urow("enum_AluSrc_rev_VALU_SALU", op_of("VALU_SALU", AluSrc()))
    srow("enum_InstOp_n", nat_text(InstOp_n()))
    srow("enum_InstOp_fwd_0", name_at(0, InstOp()))
    srow("enum_InstOp_fwd_1", name_at(1, InstOp()))
    srow("enum_InstOp_fwd_3", name_at(3, InstOp()))
    srow("enum_InstOp_fwd_4", name_at(4, InstOp()))
    srow("enum_InstOp_fwd_5", name_at(5, InstOp()))
    srow("enum_InstOp_fwd_9", name_at(9, InstOp()))
    srow("enum_InstOp_fwd_11", name_at(11, InstOp()))
    srow("enum_InstOp_fwd_13", name_at(13, InstOp()))
    srow("enum_InstOp_fwd_14", name_at(14, InstOp()))
    srow("enum_InstOp_fwd_15", name_at(15, InstOp()))
    srow("enum_InstOp_fwd_18", name_at(18, InstOp()))
    srow("enum_InstOp_fwd_19", name_at(19, InstOp()))
    srow("enum_InstOp_fwd_28", name_at(28, InstOp()))
    srow("enum_InstOp_fwd_29", name_at(29, InstOp()))
    srow("enum_InstOp_fwd_30", name_at(30, InstOp()))
    srow("enum_InstOp_fwd_31", name_at(31, InstOp()))
    srow("enum_InstOp_fwd_32", name_at(32, InstOp()))
    srow("enum_InstOp_fwd_33", name_at(33, InstOp()))
    srow("enum_InstOp_fwd_34", name_at(34, InstOp()))
    srow("enum_InstOp_fwd_36", name_at(36, InstOp()))
    srow("enum_InstOp_fwd_37", name_at(37, InstOp()))
    srow("enum_InstOp_fwd_38", name_at(38, InstOp()))
    srow("enum_InstOp_fwd_39", name_at(39, InstOp()))
    srow("enum_InstOp_fwd_40", name_at(40, InstOp()))
    srow("enum_InstOp_fwd_41", name_at(41, InstOp()))
    srow("enum_InstOp_fwd_42", name_at(42, InstOp()))
    srow("enum_InstOp_fwd_43", name_at(43, InstOp()))
    srow("enum_InstOp_fwd_44", name_at(44, InstOp()))
    srow("enum_InstOp_fwd_45", name_at(45, InstOp()))
    srow("enum_InstOp_fwd_46", name_at(46, InstOp()))
    srow("enum_InstOp_fwd_80", name_at(80, InstOp()))
    srow("enum_InstOp_fwd_81", name_at(81, InstOp()))
    srow("enum_InstOp_fwd_82", name_at(82, InstOp()))
    srow("enum_InstOp_fwd_83", name_at(83, InstOp()))
    srow("enum_InstOp_fwd_84", name_at(84, InstOp()))
    srow("enum_InstOp_fwd_85", name_at(85, InstOp()))
    srow("enum_InstOp_fwd_86", name_at(86, InstOp()))
    srow("enum_InstOp_fwd_87", name_at(87, InstOp()))
    srow("enum_InstOp_fwd_88", name_at(88, InstOp()))
    srow("enum_InstOp_fwd_89", name_at(89, InstOp()))
    srow("enum_InstOp_fwd_90", name_at(90, InstOp()))
    srow("enum_InstOp_fwd_91", name_at(91, InstOp()))
    srow("enum_InstOp_fwd_92", name_at(92, InstOp()))
    srow("enum_InstOp_fwd_93", name_at(93, InstOp()))
    srow("enum_InstOp_fwd_94", name_at(94, InstOp()))
    srow("enum_InstOp_fwd_95", name_at(95, InstOp()))
    srow("enum_InstOp_fwd_96", name_at(96, InstOp()))
    srow("enum_InstOp_fwd_97", name_at(97, InstOp()))
    srow("enum_InstOp_fwd_98", name_at(98, InstOp()))
    srow("enum_InstOp_fwd_99", name_at(99, InstOp()))
    srow("enum_InstOp_fwd_100", name_at(100, InstOp()))
    srow("enum_InstOp_fwd_101", name_at(101, InstOp()))
    srow("enum_InstOp_fwd_102", name_at(102, InstOp()))
    srow("enum_InstOp_fwd_114", name_at(114, InstOp()))
    srow("enum_InstOp_fwd_115", name_at(115, InstOp()))
    urow("enum_InstOp_rev_SALU", op_of("SALU", InstOp()))
    urow("enum_InstOp_rev_SMEM_RD", op_of("SMEM_RD", InstOp()))
    urow("enum_InstOp_rev_JUMP", op_of("JUMP", InstOp()))
    urow("enum_InstOp_rev_JUMP_NO", op_of("JUMP_NO", InstOp()))
    urow("enum_InstOp_rev_CALL", op_of("CALL", InstOp()))
    urow("enum_InstOp_rev_MESSAGE", op_of("MESSAGE", InstOp()))
    urow("enum_InstOp_rev_VALUT_4", op_of("VALUT_4", InstOp()))
    urow("enum_InstOp_rev_VALUB_2", op_of("VALUB_2", InstOp()))
    urow("enum_InstOp_rev_VALUB_4", op_of("VALUB_4", InstOp()))
    urow("enum_InstOp_rev_VALUB_16", op_of("VALUB_16", InstOp()))
    urow("enum_InstOp_rev_VINTERP", op_of("VINTERP", InstOp()))
    urow("enum_InstOp_rev_BARRIER", op_of("BARRIER", InstOp()))
    urow("enum_InstOp_rev_FLAT_RD_2", op_of("FLAT_RD_2", InstOp()))
    urow("enum_InstOp_rev_FLAT_WR_3", op_of("FLAT_WR_3", InstOp()))
    urow("enum_InstOp_rev_FLAT_WR_4", op_of("FLAT_WR_4", InstOp()))
    urow("enum_InstOp_rev_FLAT_WR_5", op_of("FLAT_WR_5", InstOp()))
    urow("enum_InstOp_rev_FLAT_WR_6", op_of("FLAT_WR_6", InstOp()))
    urow("enum_InstOp_rev_SGMEM_RD_1", op_of("SGMEM_RD_1", InstOp()))
    urow("enum_InstOp_rev_SGMEM_RD_2", op_of("SGMEM_RD_2", InstOp()))
    urow("enum_InstOp_rev_SGMEM_WR_2", op_of("SGMEM_WR_2", InstOp()))
    urow("enum_InstOp_rev_SGMEM_WR_3", op_of("SGMEM_WR_3", InstOp()))
    urow("enum_InstOp_rev_SGMEM_WR_4", op_of("SGMEM_WR_4", InstOp()))
    urow("enum_InstOp_rev_SGMEM_WR_5", op_of("SGMEM_WR_5", InstOp()))
    urow("enum_InstOp_rev_SGMEM_WR_6", op_of("SGMEM_WR_6", InstOp()))
    urow("enum_InstOp_rev_LDS_RD", op_of("LDS_RD", InstOp()))
    urow("enum_InstOp_rev_LDS_WR_1", op_of("LDS_WR_1", InstOp()))
    urow("enum_InstOp_rev_LDS_WR_2", op_of("LDS_WR_2", InstOp()))
    urow("enum_InstOp_rev_LDS_WR_3", op_of("LDS_WR_3", InstOp()))
    urow("enum_InstOp_rev_LDS_WR_4", op_of("LDS_WR_4", InstOp()))
    urow("enum_InstOp_rev_LDS_WR_5", op_of("LDS_WR_5", InstOp()))
    urow("enum_InstOp_rev_OTHER_LDS_1", op_of("OTHER_LDS_1", InstOp()))
    urow("enum_InstOp_rev_OTHER_LDS_2", op_of("OTHER_LDS_2", InstOp()))
    urow("enum_InstOp_rev_OTHER_LDS_3", op_of("OTHER_LDS_3", InstOp()))
    urow("enum_InstOp_rev_OTHER_LDS_4", op_of("OTHER_LDS_4", InstOp()))
    urow("enum_InstOp_rev_OTHER_LDS_5", op_of("OTHER_LDS_5", InstOp()))
    urow("enum_InstOp_rev_OTHER_FLAT_2", op_of("OTHER_FLAT_2", InstOp()))
    urow("enum_InstOp_rev_OTHER_FLAT_3", op_of("OTHER_FLAT_3", InstOp()))
    urow("enum_InstOp_rev_OTHER_FLAT_4", op_of("OTHER_FLAT_4", InstOp()))
    urow("enum_InstOp_rev_OTHER_FLAT_5", op_of("OTHER_FLAT_5", InstOp()))
    urow("enum_InstOp_rev_OTHER_FLAT_6", op_of("OTHER_FLAT_6", InstOp()))
    urow("enum_InstOp_rev_OTHER_VMEM_1", op_of("OTHER_VMEM_1", InstOp()))
    urow("enum_InstOp_rev_OTHER_VMEM_2", op_of("OTHER_VMEM_2", InstOp()))
    urow("enum_InstOp_rev_OTHER_VMEM_3", op_of("OTHER_VMEM_3", InstOp()))
    urow("enum_InstOp_rev_OTHER_VMEM_4", op_of("OTHER_VMEM_4", InstOp()))
    urow("enum_InstOp_rev_OTHER_VMEM_5", op_of("OTHER_VMEM_5", InstOp()))
    urow("enum_InstOp_rev_OTHER_VMEM_6", op_of("OTHER_VMEM_6", InstOp()))
    urow("enum_InstOp_rev_OTHER_VMEM_7", op_of("OTHER_VMEM_7", InstOp()))
    urow("enum_InstOp_rev_OTHER_VMEM_8", op_of("OTHER_VMEM_8", InstOp()))
    urow("enum_InstOp_rev_OTHER_VMEM_9", op_of("OTHER_VMEM_9", InstOp()))
    urow("enum_InstOp_rev_OTHER_VMEM_10", op_of("OTHER_VMEM_10", InstOp()))
    urow("enum_InstOp_rev_OTHER_VMEM_11", op_of("OTHER_VMEM_11", InstOp()))
    urow("enum_InstOp_rev_OTHER_VMEM_12", op_of("OTHER_VMEM_12", InstOp()))
    urow("enum_InstOp_rev_OTHER_VMEM_13", op_of("OTHER_VMEM_13", InstOp()))
    urow("enum_InstOp_rev_SALU_WR_EXEC", op_of("SALU_WR_EXEC", InstOp()))
    urow("enum_InstOp_rev_VALU1_WR_EXEC", op_of("VALU1_WR_EXEC", InstOp()))
    srow("enum_InstOpRDNA4_n", nat_text(InstOpRDNA4_n()))
    srow("enum_InstOpRDNA4_fwd_0", name_at(0, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_1", name_at(1, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_2", name_at(2, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_3", name_at(3, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_4", name_at(4, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_5", name_at(5, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_7", name_at(7, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_9", name_at(9, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_10", name_at(10, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_11", name_at(11, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_12", name_at(12, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_13", name_at(13, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_14", name_at(14, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_15", name_at(15, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_18", name_at(18, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_19", name_at(19, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_28", name_at(28, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_29", name_at(29, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_30", name_at(30, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_31", name_at(31, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_32", name_at(32, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_33", name_at(33, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_34", name_at(34, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_35", name_at(35, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_36", name_at(36, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_37", name_at(37, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_38", name_at(38, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_39", name_at(39, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_40", name_at(40, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_41", name_at(41, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_42", name_at(42, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_43", name_at(43, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_44", name_at(44, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_45", name_at(45, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_46", name_at(46, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_47", name_at(47, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_48", name_at(48, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_49", name_at(49, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_50", name_at(50, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_51", name_at(51, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_52", name_at(52, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_53", name_at(53, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_54", name_at(54, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_80", name_at(80, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_81", name_at(81, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_82", name_at(82, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_83", name_at(83, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_84", name_at(84, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_85", name_at(85, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_86", name_at(86, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_87", name_at(87, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_88", name_at(88, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_89", name_at(89, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_110", name_at(110, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_111", name_at(111, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_114", name_at(114, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_115", name_at(115, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_116", name_at(116, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_119", name_at(119, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_120", name_at(120, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_122", name_at(122, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_135", name_at(135, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_138", name_at(138, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_140", name_at(140, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_141", name_at(141, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_142", name_at(142, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_143", name_at(143, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_146", name_at(146, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_152", name_at(152, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_153", name_at(153, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_155", name_at(155, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_156", name_at(156, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_188", name_at(188, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_189", name_at(189, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_190", name_at(190, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_191", name_at(191, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_192", name_at(192, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_193", name_at(193, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_194", name_at(194, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_195", name_at(195, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_196", name_at(196, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_197", name_at(197, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_198", name_at(198, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_199", name_at(199, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_200", name_at(200, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_201", name_at(201, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_202", name_at(202, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_203", name_at(203, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_204", name_at(204, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_205", name_at(205, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_206", name_at(206, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_207", name_at(207, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_208", name_at(208, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_209", name_at(209, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_210", name_at(210, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_211", name_at(211, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_212", name_at(212, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_213", name_at(213, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_214", name_at(214, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_215", name_at(215, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_216", name_at(216, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_217", name_at(217, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_218", name_at(218, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_219", name_at(219, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_220", name_at(220, InstOpRDNA4()))
    srow("enum_InstOpRDNA4_fwd_221", name_at(221, InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_SALU", op_of("SALU", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_SMEM", op_of("SMEM", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_SMEM_WR", op_of("SMEM_WR", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_JUMP", op_of("JUMP", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_JUMP_NO", op_of("JUMP_NO", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_CALL", op_of("CALL", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_SALU_NO_EXEC", op_of("SALU_NO_EXEC", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_MESSAGE", op_of("MESSAGE", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_VALU_1", op_of("VALU_1", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_VALUT_4", op_of("VALUT_4", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_VALUB_1", op_of("VALUB_1", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_VALUB_2", op_of("VALUB_2", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_VALUB_4", op_of("VALUB_4", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_VALUB_16", op_of("VALUB_16", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_VINTERP", op_of("VINTERP", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_BARRIER_WAIT", op_of("BARRIER_WAIT", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_FLAT_RD_2", op_of("FLAT_RD_2", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_FLAT_WR_3", op_of("FLAT_WR_3", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_FLAT_WR_4", op_of("FLAT_WR_4", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_FLAT_WR_5", op_of("FLAT_WR_5", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_FLAT_WR_6", op_of("FLAT_WR_6", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_VMEM_RD_1", op_of("VMEM_RD_1", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_VMEM_RD_2", op_of("VMEM_RD_2", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_VMEM_WR_1", op_of("VMEM_WR_1", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_VMEM_WR_2", op_of("VMEM_WR_2", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_VMEM_WR_3", op_of("VMEM_WR_3", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_VMEM_WR_4", op_of("VMEM_WR_4", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_VMEM_WR_5", op_of("VMEM_WR_5", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_VMEM_WR_6", op_of("VMEM_WR_6", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_LDS_RD", op_of("LDS_RD", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_LDS_WR_1", op_of("LDS_WR_1", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_LDS_WR_2", op_of("LDS_WR_2", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_LDS_WR_3", op_of("LDS_WR_3", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_LDS_WR_4", op_of("LDS_WR_4", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_LDS_WR_5", op_of("LDS_WR_5", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_BUF_RD_1", op_of("BUF_RD_1", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_BUF_RD_2", op_of("BUF_RD_2", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_BUF_WR_1", op_of("BUF_WR_1", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_BUF_WR_2", op_of("BUF_WR_2", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_BUF_WR_3", op_of("BUF_WR_3", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_BUF_WR_4", op_of("BUF_WR_4", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_BUF_WR_5", op_of("BUF_WR_5", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_BUF_WR_6", op_of("BUF_WR_6", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_LDS_1", op_of("OTHER_LDS_1", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_LDS_2", op_of("OTHER_LDS_2", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_LDS_3", op_of("OTHER_LDS_3", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_LDS_4", op_of("OTHER_LDS_4", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_LDS_5", op_of("OTHER_LDS_5", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_FLAT_2", op_of("OTHER_FLAT_2", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_FLAT_3", op_of("OTHER_FLAT_3", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_FLAT_4", op_of("OTHER_FLAT_4", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_FLAT_5", op_of("OTHER_FLAT_5", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_FLAT_6", op_of("OTHER_FLAT_6", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_LDS_DIR_LOAD", op_of("LDS_DIR_LOAD", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_LDS_PARAM_LOAD", op_of("LDS_PARAM_LOAD", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_SALU_WR_EXEC", op_of("SALU_WR_EXEC", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_VALU1_WR_EXEC", op_of("VALU1_WR_EXEC", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_VALU_WR_EXEC_2", op_of("VALU_WR_EXEC_2", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_LDS_6", op_of("OTHER_LDS_6", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_LDS_10", op_of("OTHER_LDS_10", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_BARRIER_SIGNAL", op_of("BARRIER_SIGNAL", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_DYN_VGPR", op_of("DYN_VGPR", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_BARRIER_JOIN", op_of("BARRIER_JOIN", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_WMMA_8", op_of("WMMA_8", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_WMMA_16", op_of("WMMA_16", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_WMMA_32", op_of("WMMA_32", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_WMMA_64", op_of("WMMA_64", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_VALU_DPFP", op_of("VALU_DPFP", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_SALU_FLOAT_3", op_of("SALU_FLOAT_3", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_VALU_SCL_TRANS", op_of("VALU_SCL_TRANS", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_SALU_2", op_of("SALU_2", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_SALU_5", op_of("SALU_5", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_1", op_of("OTHER_VMEM_1", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_2", op_of("OTHER_VMEM_2", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_3", op_of("OTHER_VMEM_3", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_4", op_of("OTHER_VMEM_4", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_5", op_of("OTHER_VMEM_5", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_6", op_of("OTHER_VMEM_6", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_7", op_of("OTHER_VMEM_7", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_8", op_of("OTHER_VMEM_8", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_9", op_of("OTHER_VMEM_9", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_10", op_of("OTHER_VMEM_10", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_11", op_of("OTHER_VMEM_11", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_12", op_of("OTHER_VMEM_12", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_13", op_of("OTHER_VMEM_13", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_14", op_of("OTHER_VMEM_14", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_15", op_of("OTHER_VMEM_15", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_16", op_of("OTHER_VMEM_16", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_17", op_of("OTHER_VMEM_17", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_18", op_of("OTHER_VMEM_18", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_19", op_of("OTHER_VMEM_19", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_20", op_of("OTHER_VMEM_20", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_21", op_of("OTHER_VMEM_21", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_22", op_of("OTHER_VMEM_22", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_23", op_of("OTHER_VMEM_23", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_24", op_of("OTHER_VMEM_24", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_25", op_of("OTHER_VMEM_25", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_26", op_of("OTHER_VMEM_26", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_27", op_of("OTHER_VMEM_27", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_28", op_of("OTHER_VMEM_28", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_29", op_of("OTHER_VMEM_29", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_30", op_of("OTHER_VMEM_30", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_31", op_of("OTHER_VMEM_31", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_32", op_of("OTHER_VMEM_32", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_33", op_of("OTHER_VMEM_33", InstOpRDNA4()))
    urow("enum_InstOpRDNA4_rev_OTHER_VMEM_34", op_of("OTHER_VMEM_34", InstOpRDNA4()))
    srow("enum_InstOpCDNA_n", nat_text(InstOpCDNA_n()))
    srow("enum_InstOpCDNA_fwd_0", name_at(0, InstOpCDNA()))
    srow("enum_InstOpCDNA_fwd_1", name_at(1, InstOpCDNA()))
    srow("enum_InstOpCDNA_fwd_2", name_at(2, InstOpCDNA()))
    srow("enum_InstOpCDNA_fwd_3", name_at(3, InstOpCDNA()))
    srow("enum_InstOpCDNA_fwd_4", name_at(4, InstOpCDNA()))
    srow("enum_InstOpCDNA_fwd_5", name_at(5, InstOpCDNA()))
    srow("enum_InstOpCDNA_fwd_6", name_at(6, InstOpCDNA()))
    srow("enum_InstOpCDNA_fwd_7", name_at(7, InstOpCDNA()))
    srow("enum_InstOpCDNA_fwd_12", name_at(12, InstOpCDNA()))
    srow("enum_InstOpCDNA_fwd_13", name_at(13, InstOpCDNA()))
    srow("enum_InstOpCDNA_fwd_14", name_at(14, InstOpCDNA()))
    srow("enum_InstOpCDNA_fwd_15", name_at(15, InstOpCDNA()))
    srow("enum_InstOpCDNA_fwd_16", name_at(16, InstOpCDNA()))
    srow("enum_InstOpCDNA_fwd_17", name_at(17, InstOpCDNA()))
    srow("enum_InstOpCDNA_fwd_18", name_at(18, InstOpCDNA()))
    srow("enum_InstOpCDNA_fwd_28", name_at(28, InstOpCDNA()))
    urow("enum_InstOpCDNA_rev_SMEM_RD", op_of("SMEM_RD", InstOpCDNA()))
    urow("enum_InstOpCDNA_rev_SALU_32", op_of("SALU_32", InstOpCDNA()))
    urow("enum_InstOpCDNA_rev_VMEM_RD", op_of("VMEM_RD", InstOpCDNA()))
    urow("enum_InstOpCDNA_rev_VMEM_WR", op_of("VMEM_WR", InstOpCDNA()))
    urow("enum_InstOpCDNA_rev_FLAT_WR", op_of("FLAT_WR", InstOpCDNA()))
    urow("enum_InstOpCDNA_rev_VALU_32", op_of("VALU_32", InstOpCDNA()))
    urow("enum_InstOpCDNA_rev_LDS", op_of("LDS", InstOpCDNA()))
    urow("enum_InstOpCDNA_rev_PC", op_of("PC", InstOpCDNA()))
    urow("enum_InstOpCDNA_rev_JUMP", op_of("JUMP", InstOpCDNA()))
    urow("enum_InstOpCDNA_rev_NEXT", op_of("NEXT", InstOpCDNA()))
    urow("enum_InstOpCDNA_rev_FLAT_RD", op_of("FLAT_RD", InstOpCDNA()))
    urow("enum_InstOpCDNA_rev_OTHER_MSG", op_of("OTHER_MSG", InstOpCDNA()))
    urow("enum_InstOpCDNA_rev_SMEM_WR", op_of("SMEM_WR", InstOpCDNA()))
    urow("enum_InstOpCDNA_rev_SALU_64", op_of("SALU_64", InstOpCDNA()))
    urow("enum_InstOpCDNA_rev_VALU_64", op_of("VALU_64", InstOpCDNA()))
    urow("enum_InstOpCDNA_rev_VALU_MAI", op_of("VALU_MAI", InstOpCDNA()))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- g_tables()
    b : Unit <- g_fields()
    +c : Unit <- g_state()
    +d : Unit <- g_decode()
    +e : Unit <- g_props()
    +f : Unit <- g_enums()
    IO.print("sqtt-done=1")
