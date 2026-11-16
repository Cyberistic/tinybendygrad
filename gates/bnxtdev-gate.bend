# gates/bnxtdev-gate.bend -- the gate driver for `tinybendygrad/runtime/support/rdma/bnxtdev.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/runtime/support/rdma/bnxtdev.bend as P

import ./../tinybendygrad/runtime/support/rdma/bnxtdev.bend as Q
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def brow(nm: String, v: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))

def sep(ix: U32) -> String: Bool.pick(String, U32.is_zero(ix), "", " ")

# a space-separated join with no trailing space, because the oracle prints
# Python's `" ".join(...)` and a trailing space would make every list row
# disagree for a reason that is not arithmetic.
#
# ONE self-call, not two. `show_go`/`show_tail` looked right and is MUTUAL
# RECURSION, which Bend refuses -- and the error names the callee, not the
# cycle. The position rides in as a `U32` parameter and the separator is a
# `Bool.pick` on it, so there is a single self-recursive def.
def show_go(n: Nat, +ix: U32, xs: List<&2, U32>) -> String:
  match n:
    case 0n: ""
    case 1n+m:
      match xs:
        case Nil{}: ""
        case h <> t: String.concat([sep(ix), U32.show(h), show_go(m, U32.inc(ix), t)])

def join_u32(+xs: List<&2, U32>) -> String: show_go(List.length(&2, U32, xs), 0, xs)

def lrow(nm: String, xs: List<&2, U32>) -> IO(Unit): IO.print(String.concat([nm, "=", join_u32(xs)]))

def names_go(n: Nat, +ix: U32, xs: List<&2, String>) -> String:
  match n:
    case 0n: ""
    case 1n+m:
      match xs:
        case Nil{}: ""
        case h <> t: String.concat([sep(ix), h, names_go(m, U32.inc(ix), t)])

def join_str(+xs: List<&2, String>) -> String:
  names_go(List.length(&2, String, xs), 0, xs)

def nrow(nm: String, xs: List<&2, String>) -> IO(Unit): IO.print(String.concat([nm, "=", join_str(xs)]))

# THE LOGGING TABLE. `BNXT_BACKING_STORE`, :11, and what drives it,
# `setup_backing_store`, :91-108.
#
#   BNXT_BACKING_STORE = ((0, 64), (1, 0), (2, 128), (3, 0), (4, 2), (5, 0),
#                         (6, 0), (14, 1024), (15, 0))
#
# nine (type, extra) pairs, and two things about the table are not visible in
# THE LITERAL. First, TYPES 7..13 ARE ABSENT: the type numbers are not 0..8,
# so an index-into-the-table is NOT a type, and `bs_index_of` has to SEARCH.
# `bs_absent_7` is the row that says type 7 is not in the table -- the negative
# case, one row from its opposite. Second, the last entry's extra is 0 and the
# penultimate's is 1024, so a table that is off by one place puts 1024 on type
# 15, which is the type whose count is COPIED rather than computed.
#
# `bs_row_*` is the fixture table for `bs_count_of`: the caps that
# `func_backing_store_qcaps_v2` returns, transcribed per type from
# `.agents/slop/bnxt_oracle.py`'s `FIX`, and every field the port reads is
# printed beside its use so a wrong field cannot hide behind a right sum.

def BS_TYP() -> List<&2, U32>: [0, 1, 2, 3, 4, 5, 6, 14, 15]
def BS_EXTRA() -> List<&2, U32>: [64, 0, 128, 0, 2, 0, 0, 1024, 0]
def BS_LEN() -> U32: 9

# The index is a `List.get`, not a chain of `Bool.pick`s: an absent type
# answers `BS_LEN()`, which `List.get` past the end turns into 0, and that is
# the same 0 an absent type's `extra` is. Eight nested picks were the first
# spelling and it was one paren away from a silent mis-pairing.
def bs.extra_at(i: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, BS_EXTRA(), U32.to_nat(i)), 0)

def bs.typ_at(i: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, BS_TYP(), U32.to_nat(i)), 0)

# THE SEARCH, and `BS_LEN()` is the not-found answer -- a type number that is
# not in the table indexes past the end. `bs_absent_*` rows are the negative
# case for it.
# The fuel is the LIST LENGTH and the position rides beside it as a plain
# parameter, which is `Tr.count.go`'s shape. Binding the position from the
# countdown instead (`U32.from_nat(i)`) needs the scrutinee twice and the
# `-i` that admits that kills the `0n` arm.
def bs.index_at.go(n: Nat, +ix: U32, +typs: List<&2, U32>, +hit: U32, +typ: U32) -> U32:
  match n:
    case 0n: hit
    case 1n+m:
      match typs:
        case Nil{}: hit
        case h <> t: bs.index_at.go(m, U32.inc(ix), t,
          Bool.pick(U32, U32.is_eq(h, typ), ix, hit), typ)

def bs.index_at(+typs: List<&2, U32>, typ: U32) -> U32:
  bs.index_at.go(List.length(&2, U32, typs), 0, typs, BS_LEN(), typ)

def bs.index_of(typ: U32) -> U32: bs.index_at(BS_TYP(), typ)

def bs.extra_of(typ: U32) -> U32: bs.extra_at(bs.index_of(typ))

# :96 -- `counts[typ] = counts[0] if typ == 15 else max(min_num_entries,
# sum(splits) + extra)`. THREE facts and they are all in this one line:
#   1. type 15 REUSES type 0's count verbatim -- it does not read `extra` and
#      it does not take the `max`. `bs_count_15_is_zero_count` is the row.
#   2. `max(min_num_entries, sum + extra)`: the FIRMWARE's floor wins when the
#      sum is smaller. `bs_count_4_floor_wins` and `bs_count_0_sum_wins` are
#      the two rows and they sit one entry apart on purpose.
#   3. `extra` is the TABLE's per-type second element, found by SEARCH.
def BS_TYPE15() -> U32: 15
def BS_TYPE0() -> U32: 0

def bs.count_of(+typ: U32, mne: U32, sum_splits: U32, c0: U32) -> U32:
  Bool.pick(U32, U32.is_eq(typ, BS_TYPE15()), c0,
    U32.max(mne, U32.add(sum_splits, bs.extra_of(typ))))

# :98 -- `for instance in [i for i in range(8) if caps.instance_bit_map >> i & 1] or [0]`.
# a zero bitmap means the TYPE has a single instance 0, which is the `or [0]`
# and is not a special case of the scan -- it is the scan's answer when the
# scan finds nothing. `bs_instances_*` rows run six bitmaps, two of them zero.
def bs.inst_bit(ibm: U32, i: U32) -> Bool: U32.is_ne(U32.and(U32.shrn(ibm, U32.to_nat(i)), 1), 0)

# The COUNT of instances: the popcount, and the `or [0]` makes it 1 when the
# popcount is 0. `U32.popcount` is not in Base 2.0.34's U32, so the count is a
# fold over the eight bits, which is also what `bs.instances` needs.
def bs.count.go(n: Nat, +ix: U32, +ibm: U32, +got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m: bs.count.go(m, U32.inc(ix), ibm,
      U32.add(got, Bool.to_u32(bs.inst_bit(ibm, ix))))

def bs.ninstances(ibm: U32) -> U32: U32.max(1, bs.count.go(8n, 0, ibm, 0))

# The FIRST instance index, and 0 for a zero bitmap -- the whole of the
# `or [0]` in one number.
#
# A fold that overwrites on every hit answers the HIGHEST set bit, not the
# lowest, so the `found` flag is load-bearing and not decoration: a bitmap with
# bits 0 and 2 set must answer 0. `bs_inst_fwd_0` is the row that sees it, and
# `bs_inst_rev_0` is the negative case sitting one bitmap away.
# THE FUEL IS THE FIRST PARAMETER of every self-recursive def -- rule 5, and a
# self-call whose fuel is the fourth argument is refused, not merely slow.
def bs.first_of(n: Nat, +ix: U32, +ibm: U32, +found: Bool, +best: U32) -> U32:
  match n:
    case 0n: best
    case 1n+m: bs.first_of(m, U32.inc(ix), ibm, Bool.or(found, bs.inst_bit(ibm, ix)),
      Bool.pick(U32, Bool.and(Bool.not(found), bs.inst_bit(ibm, ix)), ix, best))

def bs.first_inst(+ibm: U32) -> U32: bs.first_of(8n, 0, ibm, False{}, 0)

# :99 -- `alloc_sysmem(P.ceildiv(n * size, 0x1000) * 0x1000)`. The count is
# ROUNDED UP TO WHOLE PAGES, and `entry_size` multiplies BEFORE the rounding.
def bs.alloc_bytes(n: U32, entry_size: U32) -> U32: U32.mul(P.ceildiv(U32.mul(n, entry_size), P.PAGE()), P.PAGE())

# :107 -- `BS_CFG_ALL_DONE if typ == 15 else 0`. The firmware's "I am finished"
# flag, and it goes on the SAME type whose count is copied.
def bs.flags_of(typ: U32) -> U32:
  Bool.pick(U32, U32.is_eq(typ, BS_TYPE15()), P.FUNC_BACKING_STORE_CFG_V2_REQ_FLAGS_BS_CFG_ALL_DONE(), 0)

# :102 -- the `ctx_init` sweep. `init[caps.ctx_init_offset::size] = bytes([v])
# * len(range(off, len(mem), size))`, so the pattern has a STRIDE of
# `entry_size` starting at `ctx_init_offset`, and the sweep length is the
# count of those positions. `bs.init_stride` is that stride and
# `bs.init_npos` is the count; both are needed and they are not the same
# number, which is exactly the mistake the sweep invites.
def bs.init_npos(+mem_bytes: U32, +off: U32, entry_size: U32) -> U32:
  Bool.pick(U32, U32.is_ge(off, mem_bytes), 0, P.ceildiv(U32.sub(mem_bytes, off), entry_size))

def bs.init_len(npos: U32) -> U32: npos

# THE TRACE. One `CALL_*` per device call, carrying up to TWO U32 arguments:
# `a` is the address or the index and `b` is the value or the length. Two
# arguments is the smallest that covers `self.bar0[i] = w`, `self.db[off] =
# value` and `ring[off:off+n] = data` -- a one-argument trace could not say
# WHICH register got WHICH value, which is the whole of a register write.
#
# `Tr.emit` is the seam: nothing else in this file makes a device call, so the
# trace IS the ordered list of what the seam will do. There is no
# `import "./x.c"`, so this file declares NO foreign effect, and every symbol
# the port names is a LITERAL in the file and greppable.
#
# THE RAISE IS HERE. `Tr.emit` records NOTHING once a refusal has fired and
# `Tr.refuse` is IDEMPOTENT after the first, so one fixture numbering reaches
# EVERY refusal site in turn and a refusal appears as a TRUNCATED TRACE. That
# is why no step below carries a guard of its own.

type Call is Data:
  Call{k: U32, a: U32, b: U32}

type Tr is Data:
  Tr{calls: List<&2, Call>, next: U32, refused: Bool, nth: U32, at: U32}

# the FFI seam, one tag per Python line. See THE FFI SEAMS in the header.
def CALL_PCI_RESET() -> U32: 0
def CALL_PCI_CFG_R() -> U32: 1
def CALL_PCI_CFG_W() -> U32: 2
def CALL_MAP_BAR() -> U32: 3
def CALL_ALLOC() -> U32: 4
def CALL_BARRIER() -> U32: 5
def CALL_BAR0() -> U32: 6
def CALL_RING_W() -> U32: 7
def CALL_RING_R() -> U32: 8
def CALL_WAIT() -> U32: 9
def CALL_HWRM() -> U32: 10
def CALL_RING_ALLOC() -> U32: 11
def CALL_CMDQ() -> U32: 12
def CALL_VNIC() -> U32: 13
def CALL_L2_FILTER() -> U32: 14
def CALL_MR() -> U32: 15
def CALL_FINI() -> U32: 16
def CALL_DB() -> U32: 17
def CALL_REFUSE() -> U32: 18

def Call.k(c: Call) -> U32:
  match c:
    case Call{k, a, b}: k
def Call.a(c: Call) -> U32:
  match c:
    case Call{k, a, b}: a
def Call.b(c: Call) -> U32:
  match c:
    case Call{k, a, b}: b

def Tr.of() -> Tr: Tr{Nil{}, 0, False{}, 0, 0}
def Tr.calls(t: Tr) -> List<&2, Call>:
  match t:
    case Tr{calls, next, refused, nth, at}: calls
def Tr.refused(t: Tr) -> Bool:
  match t:
    case Tr{calls, next, refused, nth, at}: refused

# the refusal ordinal the seam should fail on, 0 = never. `nth` is NOT reset by
# `Tr.reset`, so one fixture numbering covers a whole device lifetime.
def Tr.fail_at(t: Tr, n: U32) -> Tr:
  match t:
    case Tr{calls, next, refused, nth, at}: Tr{calls, next, refused, nth, n}

# an EMPTY trace that keeps `at` and `nth`, so a gate can read one step without
# the device init in front of it and still number its refusals from one.
def Tr.reset(t: Tr) -> Tr:
  match t:
    case Tr{calls, next, refused, nth, at}: Tr{Nil{}, 0, refused, nth, at}

# the id the NEXT emit mints, i.e. what the seam's call returns.
def Tr.here(t: Tr) -> U32:
  match t:
    case Tr{calls, next, refused, nth, at}: next

def Tr.emit.go(+refused: Bool, k: U32, a: U32, b: U32, +calls: List<&2, Call>,
               +next: U32, nth: U32, at: U32) -> Tr:
  Tr{Bool.pick(List<&2, Call>, refused, calls, List.append(&2, Call, calls, [Call{k, a, b}])),
     Bool.pick(U32, refused, next, U32.add(next, 1)), refused, nth, at}

def Tr.emit(k: U32, a: U32, b: U32, t: Tr) -> Tr:
  match t:
    case Tr{calls, next, refused, nth, at}: Tr.emit.go(refused, k, a, b, calls, next, nth, at)

# THE RAISE, and it is idempotent after the first so one fixture numbering
# reaches every site. The failing refusal is NOT recorded, because in Python the
# `assert` replaces it.
def Tr.refuse.go(+refused: Bool, +nth: U32, +at: U32) -> Tr:
  Tr{Nil{}, 0, Bool.or(refused, U32.is_eq(U32.add(nth, 1), at)),
     Bool.pick(U32, refused, nth, U32.add(nth, 1)), at}

def Tr.refuse(t: Tr) -> Tr:
  match t:
    case Tr{calls, next, refused, nth, at}: Tr.refuse.go(refused, nth, at)

# READING THE TRACE. `Tr.count` is how many calls carry a tag -- which is the
# TRUNCATION LENGTH a refusal shows up as. `Tr.seq` is an ordered SUBSEQUENCE
# test, so a trace that contains the right calls in the WRONG ORDER fails.
# `Tr.arg_at` is the argument a call carried, which is what pins "the right
# VALUE reached the right call".

def Tr.count.go(n: Nat, +k: U32, cs: List<&2, Call>, +got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match cs:
        case Nil{}: got
        case Call{kk, aa, bb} <> t: Tr.count.go(m, k, t,
          U32.add(got, Bool.to_u32(U32.is_eq(kk, k))))

def Tr.count(k: U32, +cs: List<&2, Call>) -> U32:
  Tr.count.go(List.length(&2, Call, cs), k, cs, 0)

def Tr.seen(t: Tr) -> U32: U32.from_nat(List.length(&2, Call, Tr.calls(t)))

# The j-th argument of the j-th call carrying tag `k`, or `MISSING` when there
# is none. `MISSING` and a real zero are told apart, which is what lets a row
# say "the doorbell wrote 0" as readily as "no doorbell was written" -- and a
# `MISSING` answer IS the refusal signature.
#
# ONE walk, not two: `sel` picks the field, so `Tr.arg_at` and `Tr.val_at` are
# the same def with `sel` 0 and 1. Two walks differing in one projection is
# copy-paste, and a copy-paste pair is two places for the next bug to live.
def MISSING() -> U32: 4294967295

def Call.sel(+c: Call, w: U32) -> U32: Bool.pick(U32, U32.is_zero(w), Call.a(c), Call.b(c))

def Tr.nth.go(n: Nat, +k: U32, +cs: List<&2, Call>, +j: U32, +w: U32,
              +at: U32, +got: U32) -> U32:
  match n:
    case 0n: got
    case 1n+m:
      match cs:
        case Nil{}: got
        case c <> t: Tr.nth.go(m, k, t, j, w,
          U32.add(at, Bool.to_u32(U32.is_eq(Call.k(c), k))),
          Bool.pick(U32, Bool.and(U32.is_eq(Call.k(c), k), U32.is_eq(at, j)),
            Call.sel(c, w), got))

def Tr.nth(k: U32, +cs: List<&2, Call>, j: U32, w: U32) -> U32:
  Tr.nth.go(List.length(&2, Call, cs), k, cs, j, w, 0, MISSING())

def Tr.arg_at(k: U32, +cs: List<&2, Call>, j: U32) -> U32: Tr.nth(k, cs, j, 0)
def Tr.val_at(k: U32, +cs: List<&2, Call>, j: U32) -> U32: Tr.nth(k, cs, j, 1)

# THE ORDERED SUBSEQUENCE TEST, duplicated from `ops_webgpu.bend` and
# `support/am/ip.bend` because this substrate is a copy and a copy needs its
# own rows. The answer is `at == patlen` and the fuel is the TRACE length, so
# with the fuel set to the PATTERN length a REVERSED pattern would match --
# `has_fwd` / `has_rev` are the rows that catch it.
def Tr.has.step.same2(k1: U32, k2: U32, a1: U32, a2: U32) -> Bool:
  Bool.and(U32.is_eq(k1, k2), U32.is_eq(a1, a2))

def Tr.has.step.hit(same: Bool, +at: Nat) -> Nat:
  match same:
    case True{}: Nat.add(at, 1n)
    case False{}: at

def Tr.has.step(m: Maybe<&2, Call>, +c: Call, +at: Nat) -> Nat:
  match m:
    case None{}: at
    case Some{+want}:
      Tr.has.step.hit(Tr.has.step.same2(Call.k(c), Call.k(want), Call.a(c), Call.a(want)), at)

def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>, +at: Nat) -> Bool:
  match n:
    case 0n: Nat.is_eq(at, patlen)
    case 1n+m:
      match cs:
        case Nil{}: Nat.is_eq(at, patlen)
        case Call{kk, aa, bb} <> t:
          Tr.has.go(m, patlen, t, pat, Tr.has.step(List.get(&2, Call, pat, at), Call{kk, aa, bb}, at))

def Tr.has(+cs: List<&2, Call>, +pat: List<&2, Call>) -> Bool:
  Tr.has.go(List.length(&2, Call, cs), List.length(&2, Call, pat), cs, pat, 0n)

def Tr.seq(t: Tr, pat: List<&2, Call>) -> Bool: Tr.has(Tr.calls(t), pat)

# THE HWRM AND RCFW WORD ARITHMETIC. :55-89 and :130-158.
#
# `hwrm` (:76-89) is a wall for its struct construction (WALL 1) and a seam for
# its transport, but SIX numbers in it are arithmetic and each has a row:
#   :78  `self.seq = (self.seq + 1) & 0xffff` -- the sequence counter WRAPS, and
#        `hwrm_seq_wrap` is the row that crosses 0xffff. A version with a
#        plain `+ 1` would send a sequence id the firmware never matches and
#        every HWRM would time out.
#   :79  `cmpl_ring = P.BNXT_HWRM_NO_CMPL_RING`, `target_id = P.BNXT_HWRM_TARGET`
#   :83  `self.bar0[P.BNXT_CHIMP_COMM // 4 + i] = w` -- the word loop, and the
#        `// 4` is what makes the first word land in bar0 dword 0.
#   :84  `self.bar0[P.BNXT_CHIMP_COMM_TRIGGER // 4] = 1`
#   :86  `(n := resp_len) and seq_id == seq` -- the wait's GATE, and it has
#        three conjuncts: a zero `resp_len` means "not yet", so the gate is not
#        just the sequence match.
#   :87  `ctypes.sizeof(out)` bounded by the 0x1000-byte response buffer

def SEQ_MASK() -> U32: 65535
def CREQ_CONS_MASK() -> U32: 255

def hwrm.seq_of(seq: U32) -> U32: U32.and(U32.add(seq, 1), SEQ_MASK())

# :83 the word loop's bar0 dword index. `P.BNXT_CHIMP_COMM` is 0 so this is `i`,
# and the row says so -- a port that divided the trigger offset by 8 instead
# of 4 would write half as far up the bar.
def hwrm.bar0_at(i: U32) -> U32: U32.add(U32.div(P.BNXT_CHIMP_COMM(), 4), i)
def hwrm.trig_at() -> U32: U32.div(P.BNXT_CHIMP_COMM_TRIGGER(), 4)

# :86 -- `resp_len` nonzero AND `seq_id == seq`. NOT just the sequence match: a
# zero-length response is the firmware saying "not yet", and treating it as
# ready is how a port hangs in a poll loop instead of returning.
def hwrm.gate_ok(resp_len: U32, seq_id: U32, want: U32) -> Bool:
  Bool.and(U32.is_ne(resp_len, 0), U32.is_eq(seq_id, want))

# :142-143 -- the command-queue producer and trigger dwords.
#   self.bar0[(P.RCFW_COMM_BASE_OFFSET + P.RCFW_PF_VF_COMM_PROD_OFFSET) // 4] = prod
#   self.bar0[(P.RCFW_COMM_BASE_OFFSET + P.RCFW_COMM_TRIG_OFFSET) // 4] = TRIG_VAL
# The two `// 4` are the SAME shape as the HWRM bar0 loop's, and they land at
# DIFFERENT dwords 61 apart -- `rcfw_prod_trig_apart` is the row.
def rcfw.prod_at() -> U32: U32.div(U32.add(P.RCFW_COMM_BASE_OFFSET(), P.RCFW_PF_VF_COMM_PROD_OFFSET()), 4)
def rcfw.trig_at() -> U32: U32.div(U32.add(P.RCFW_COMM_BASE_OFFSET(), P.RCFW_COMM_TRIG_OFFSET()), 4)
def rcfw.trig_val() -> U32: P.RCFW_CMDQ_TRIG_VAL()

# :133 `cmd_size = slots := P.ceildiv(ctypes.sizeof(req_t), 16)`. The command is
# a whole number of 16-byte slots and `slots` is BOTH the size field and the
# number of ring writes at :134.
def rcfw.slots_of(req_bytes: U32) -> U32: P.ceildiv(req_bytes, P.SLOT16())

# :136-137 -- `self.cmdq.write_idx += slots` then `prod = write_idx & 0xffff`.
# THE MASK IS NOT COSMETIC: `write_idx` is not reset by anything in this file,
# so it grows past 0xffff and the producer index is its low sixteen bits. The
# FIRST command also carries the FIRMWARE_FIRST flag.
def rcfw.prod_of(write_idx: U32) -> U32: U32.and(write_idx, SEQ_MASK())

def rcfw.first_flag(+prod: U32, first: Bool) -> U32:
  Bool.pick(U32, first, U32.or(prod, U32.shln(1, U32.to_nat(P.FIRMWARE_FIRST_FLAG()))), prod)

# :146 -- `(self.creq.read(ri)[8] & P.CREQ_BASE_V) != (self.creq.read_idx // 256 & 1)`.
# The SAME SHAPE as `P.cqe.ready` (:25) with a different toggle source and a
# different wrap divisor: byte 8 of a CREQ entry against `read_idx // 256`,
# where byte 24 of a CQE is tested against `cons // P.CQ_ENTRIES`.
def creq.ready(toggle: U32, read_idx: U32) -> Bool:
  Bool.not(U32.is_eq(U32.and(toggle, P.CREQ_BASE_V()),
                     U32.and(U32.div(read_idx, P.CREQ_CONSUME()), 1)))

# :153 -- the NQ_ARM doorbell that publishes the CREQ consumer index. Note the
# TWO MASKS: the index is `& 255` and the epoch is `(read_idx // 256) & 1`, so
# the consumer index is 8 bits wide and its epoch is 1 -- NOT the doorbell's
# 24-bit index, and not `CREQ_ENTRIES`.
def rcfw.nq_arm_index(read_idx: U32) -> U32: U32.and(read_idx, CREQ_CONS_MASK())
def rcfw.nq_arm_epoch(read_idx: U32) -> U32: U32.and(U32.div(read_idx, P.CREQ_CONSUME()), 1)

# :154 -- `if ret.type == P.CREQ_BASE_TYPE_QP_EVENT and ret.event <
# P.CREQ_QP_EVENT_EVENT_QP_ERROR_NOTIFICATION: break`. The `while True` SKIPS
# async events, so the command is finished only on a NON-event OR on an event
# past the error-notification threshold. The comparison is `<`, so the
# threshold event itself is NOT a skip -- `rcfw_skip_at_threshold` is the row
# and it is False, one row from `rcfw_skip_below_threshold`.
def rcfw.is_event(ret_type: U32) -> Bool: U32.is_eq(ret_type, P.CREQ_BASE_TYPE_QP_EVENT())

def rcfw.skip(ret_type: U32, ret_event: U32) -> Bool:
  Bool.and(rcfw.is_event(ret_type),
           U32.is_lt(ret_event, P.CREQ_QP_EVENT_EVENT_QP_ERROR_NOTIFICATION()))

# THE DEVICE INDEX ARITHMETIC. `BNXTDev.__init__`, :53-72, `register_mem`,
# :183-189, `_open_l2`, :167-180, and `BNXTQP`, :191-217.

# :66 -- `self.db_off = hwrm("func_qcfg", fid=0xffff).legacy_l2_db_size_kb *
# 1024`. A BYTE offset, and :164 then divides it by 8 because the doorbell
# register is 64 bits wide (`map_bar(2, fmt='Q')`). The two are the SAME
# number at two scales and confusing them rings the wrong queue.
def db_off_of(db_size_kb: U32) -> U32: U32.mul(db_size_kb, 1024)
def db_at(db_off: U32) -> U32: U32.div(db_off, 8)

# :64 -- `int.from_bytes(bytes(caps.mac_address), 'big')`. Big-endian.
#
# a mac is 48 BITS and does not fit in a `U32`. `U32.shrn(x, 32n)` saturates
# TO 0, so a MAC read as one word silently loses its top sixteen bits -- and the
# gate said so: `gid_MAC_HI` printed 0 where CPython says 4386. It is therefore
# carried as TWO halves, `MAC_HI16` and `MAC_LO32`, and the two 24-bit halves
# `int.from_bytes(..., 'big')` produces are assembled from both.
def MAC_HI16() -> U32: 17
def MAC_LO32() -> U32: 573785173

# the top THREE bytes, big-endian: `hi16`'s low byte then `lo32`'s top byte
def mac_hi(hi16: U32, lo32: U32) -> U32:
  U32.or(U32.shln(hi16, 8n), U32.shrn(lo32, 24n))

# the bottom THREE bytes
def mac_lo(lo32: U32) -> U32: U32.and(lo32, 16777215)

# :71 -- `bytes(10) + b'\xff\xff\x0a' + self.mac.to_bytes(6, 'big')[3:]`.
# SIXTEEN bytes, and the last three are the MAC's LOW three -- `mac[3:]` of a
# 6-byte string is bytes 3,4,5. The middle is the literal `\xff\xff\x0a`,
# which lands in `>4I` word 1 as 0x0000ffff because bytes 8 and 9 are still
# inside the ten leading zeros.
def GID_BYTES() -> U32: 16
def GID_W0() -> U32: 0
def GID_W1() -> U32: 0
def GID_W2() -> U32: 65535
def GID_0A() -> U32: 10

def gid_w3(mac_lo24: U32) -> U32: U32.or(U32.shln(GID_0A(), 24n), mac_lo24)

# :72 -- `struct.unpack(">4I", self.local_gid)[::-1]`: four big-endian words,
# REVERSED. The reversal is the point -- the NIC wants the low word first.
def gid_order(w0: U32, w1: U32, w2: U32, w3: U32) -> List<&2, U32>: [w3, w2, w1, w0]

# :72 -- `struct.unpack(">3H", self.mac.to_bytes(6, 'big'))`: THREE 16-bit
# halves, big-endian, in order. The half is chosen by a `Nat` shift amount
# because `U32.shln`/`U32.shrn` take a `Nat` and there is no way to compute one
# -- which is why a bit-packer whose field positions are runtime values is
# unwritable in this Bend, and why these three are literals at the call site.
# `>3H` reads THREE 16-bit halves, so the low one is `& 0xffff` and not the
# whole low word. Without the mask `src_mac_h(lo32, 0n)` answers 0x22334455
# where the source says 0x4455, and `gid_SRCMAC` said so.
def src_mac_h(lo32: U32, sh: Nat) -> U32: U32.and(U32.shrn(lo32, sh), 65535)

def src_mac(hi16: U32, +lo32: U32) -> List<&2, U32>: [hi16, src_mac_h(lo32, 16n), src_mac_h(lo32, 0n)]

# :185-188 -- `log2_pg_size_lvl = level << LVL_SFT | log_page_size << LOG2_SFT`,
# and `P.CMDQ_REGISTER_MR_LVL_SFT` is 0, so the level is NOT shifted at all.
# That zero is a fact about the field and not about the code, and a port that
# "fixed" the missing shift would move the level into the page-size field.
def mr.lvlpg(level: U32, log_page_size: U32) -> U32:
  U32.or(U32.shln(level, U32.to_nat(P.CMDQ_REGISTER_MR_LVL_SFT())),
         U32.shln(log_page_size, U32.to_nat(P.CMDQ_REGISTER_MR_LOG2_PG_SIZE_SFT())))

def mr.lvl_of(lvlpg: U32) -> U32:
  U32.shrn(U32.and(lvlpg, 4294967295),
           U32.to_nat(P.CMDQ_REGISTER_MR_LVL_SFT()))

def mr.log_page_of(lvlpg: U32) -> U32:
  U32.shrn(lvlpg, U32.to_nat(P.CMDQ_REGISTER_MR_LOG2_PG_SIZE_SFT()))

# :204 -- `network_type_en_sqd_async_notify_new_state = state | network_type`.
# The state is 1, 2 or 3 and the network type is 0x80, so the composed field is
# 1, 130 or 131 -- and `qp_newstate_1` and `qp_newstate_2` are the two rows
# that differ only in the state, one apart.
def qp.newstate(state: U32, network_type: U32) -> U32: U32.or(state, network_type)

# :169-174 -- the two `ring_alloc` enable masks, and they are DIFFERENT words
# one line apart: the completion ring sets NQ_RING_ID_VALID alone and the
# receive ring sets it OR'd with RX_BUF_SIZE_VALID. `l2_ring_alloc_enables`
# and `rx_ring_alloc_enables` sit side by side so a port that shared one
# constant cannot pass both.
def ra_l2_enables() -> U32: P.RING_ALLOC_REQ_ENABLES_NQ_RING_ID_VALID()

def ra_rx_enables() -> U32:
  U32.or(P.RING_ALLOC_REQ_ENABLES_NQ_RING_ID_VALID(), P.RING_ALLOC_REQ_ENABLES_RX_BUF_SIZE_VALID())

# :176-177 -- the `vnic_cfg` enable mask: MRU, the default receive ring and the
# default completion ring, three bits, and ALL THREE or the vnic has no length
# and no rings.
def vnic_enables() -> U32:
  U32.or(U32.or(P.VNIC_CFG_REQ_ENABLES_MRU(), P.VNIC_CFG_REQ_ENABLES_DEFAULT_RX_RING_ID()),
         P.VNIC_CFG_REQ_ENABLES_DEFAULT_CMPL_RING_ID())

# :178-180 -- `cfa_l2_filter_alloc`: the PATH_RX flag word is separate from
# the enables word, and conflating them is a filter that matches no traffic.
def l2_filter_flags() -> U32: P.CFA_L2_FILTER_ALLOC_REQ_FLAGS_PATH_RX()

def l2_filter_enables() -> U32:
  U32.or(U32.or(P.CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR(),
                P.CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR_MASK()),
         P.CFA_L2_FILTER_ALLOC_REQ_ENABLES_DST_ID())

# :116 -- `cmdq_size_cmdq_lvl = 256 << P.CMDQ_INIT_CMDQ_SIZE_SFT`, which is 1024,
# and the field is only 16 bits wide, so it survives. The shift is 2 and the
# shift is MEASURED, not assumed.
def cmdq_lvl() -> U32: U32.shln(P.CMDQ_LVL(), U32.to_nat(P.CMDQ_INIT_CMDQ_SIZE_SFT()))
def cmdq_lvl_lo16() -> U32: U32.and(cmdq_lvl(), 65535)

# THE OPERATIONS. Each one EITHER builds the argument of one device call (and
# returns it) OR records the call and hands back the trace. There is no third
# kind, and `Tr.refuse` inside one of them is the port of the Python `assert`
# on the next line.
#
# The Python LINE is on each def, and so is the seam it records, so a reader
# can grep from a row name to the line it came from without leaving the file.
# ===========================================================================# doorbell, :162-164. `System.memory_barrier()` THEN the 64-bit store, and the
# ORDER IS THE PROTOCOL: a doorbell that lands before the ring write is a door
# bell for stale data. `db_seq` is the ordered identity trace for it and
# `db_2halves` says the store is TWO dwords because Python's is one 64-bit
# word and Bend has no U64.
def dev.doorbell(creq_or_qpn: U32, typ: U32, index: U32, epoch: U32, db_off: U32, t: Tr) -> Tr:
  Tr.emit(CALL_DB(), db_at(db_off), P.db.lo(index, epoch),
          Tr.emit(CALL_BARRIER(), 0, 0, t))

# `hwrm`, :76-89. The six emitted calls in order: the sequence bump, the 0x1000
# byte clear, the word loop into bar0, the trigger dword, the wait, and the
# error-code refusal.
def hwrm.begin(seq: U32, t: Tr) -> Tr: Tr.emit(CALL_HWRM(), hwrm.seq_of(seq), 0, t)

def hwrm.clear(t: Tr) -> Tr: Tr.emit(CALL_ALLOC(), P.RESP_BYTES(), P.RESP_BYTES(), t)

def hwrm.word(i: U32, w: U32, t: Tr) -> Tr: Tr.emit(CALL_BAR0(), hwrm.bar0_at(i), w, t)

def hwrm.trig(t: Tr) -> Tr: Tr.emit(CALL_BAR0(), hwrm.trig_at(), 1, t)

def hwrm.wait(t: Tr) -> Tr: Tr.emit(CALL_WAIT(), 10000, 0, t)

# :88 `assert ret.error_code == 0` -- THE FIRST REFUSAL. The trace so far is
# KEPT and everything after it is not, so `hwrm_error_refused` sees a trace
# that ends at the wait with no trigger and no return.
def hwrm.error_ok(error_code: U32) -> Bool: U32.is_zero(error_code)

def hwrm.finish(error_code: U32, +t: Tr) -> Tr:
  Bool.pick(Tr, hwrm.error_ok(error_code), t, Tr.refuse(t))

# `rcfw`, :130-158. The producer/trigger pair and the CREQ loop, in order.
def rcfw.write(write_idx: U32, t: Tr) -> Tr: Tr.emit(CALL_RING_W(), write_idx, P.SLOT16(), t)

def rcfw.prod_write(write_idx: U32, first: Bool, t: Tr) -> Tr:
  Tr.emit(CALL_BAR0(), rcfw.prod_at(), rcfw.first_flag(rcfw.prod_of(write_idx), first),
          Tr.emit(CALL_BARRIER(), 0, 0, t))

def rcfw.trig_write(t: Tr) -> Tr: Tr.emit(CALL_BAR0(), rcfw.trig_at(), rcfw.trig_val(), t)

def rcfw.creq_read(read_idx: U32, t: Tr) -> Tr: Tr.emit(CALL_RING_R(), read_idx, 0, t)

def rcfw.creq_wait(t: Tr) -> Tr: Tr.emit(CALL_WAIT(), 20000, 0, t)

# :155 `assert ret.status == 0` -- THE SECOND REFUSAL, and it fires INSIDE the
# `while True`, so a refused rcfw's trace ends after the CREQ read and before
# the NQ_ARM doorbell. `rcfw_status_refused` is that truncation.
def rcfw.status_ok(status: U32) -> Bool: U32.is_zero(status)

# `poll`, :219-225. READ, then the index bump, then the CQ doorbell, then the
# status check on byte 25. `poll_seq` is the ordered identity trace and
# `poll_cq_slot` / `poll_cq_epoch` are the two doorbell arguments.
def qp.poll_ready(cq_size: U32, cq_stride: U32, read_idx: U32, toggle: U32) -> Bool:
  P.cqe.ready(toggle, read_idx)

def qp.poll_cq_slot(read_idx: U32) -> U32: U32.mod(read_idx, P.CQ_ENTRIES())
def qp.poll_cq_epoch(read_idx: U32) -> U32: P.cqe.epoch(read_idx)

def qp.poll_done(+read_idx: U32, cq_id: U32, db_off: U32, status: U32, +t: Tr) -> Tr:
  # :224 `assert raw[25] == 0` -- THE THIRD REFUSAL. Byte 25 is `status`, the
  # FIFTH field of `struct_cq_base`; `cqe_status_at` pins the offset BY NAME.
  Bool.pick(Tr, U32.is_zero(status),
    dev.doorbell(cq_id, P.DBC_DBC_TYPE_CQ(), qp.poll_cq_slot(read_idx), qp.poll_cq_epoch(read_idx),
                 db_off, Tr.emit(CALL_RING_R(), read_idx, P.CQ_STRIDE(), t)),
    Tr.refuse(t))

# `post_send`, :227-232. FOUR things in order and the order is the protocol:
#   1. the 48-byte work queue element at `i % slots * stride`
#   2. the 8-byte P.msn entry in the AUX table PAST the ring, at `size + i%slots*8`
#   3. the write index bump, which is what makes the doorbell's `n+1` mean the
#      slot AFTER this one
#   4. the SQ doorbell
# `post_send_seq` is the ordered identity trace; `msn_after` and `wi_after` are
# the two pieces of state it advances.
def qp.post_send_seq(+sq_size: U32, +sq_stride: U32, +wi: U32, t: Tr) -> Tr:
  Tr.emit(CALL_RING_W(), Q.q.write_off(wi, sq_size, sq_stride, True{}), P.AUX_ENTRY(),
          Tr.emit(CALL_RING_W(), Q.q.write_off(wi, sq_size, sq_stride, False{}), sq_stride, t))

# the P.msn entry's value is not packed here, deliberately. There was a
# `qp.post_send_msn` that folded `P.msn.hi` and `P.msn.lo` into one `U32` so the
# trace could carry it, and that packing is INVENTED -- it is not a number
# Python ever computes, and it exists only to fill an argument. The P.msn's two
# halves have their own rows (`msn_*_HI` / `msn_*_LO`), which is where a wrong
# 48/24/24 belongs, and `CALL_RING_W` carries the OFFSET and the LENGTH, which
# is what `qp.post_send_seq` writes. `post_send_msn_2_calls` is the row that
# says the P.msn write is the SECOND `CALL_RING_W` and not a third kind of call.

def qp.post_send_psn(psn: U32, size: U32) -> U32: P.msn.next_of(P.msn.mask(psn), size)

# :232 -- `doorbell(qpn, SQ, write_idx % P.RING_ENTRIES, (write_idx // P.RING_ENTRIES) & 1)`
# AFTER the increment, so the doorbell rings the NEXT slot.
def qp.post_send_slot(wi_after: U32) -> U32: U32.mod(wi_after, P.RING_ENTRIES())
def qp.post_send_epoch(wi_after: U32) -> U32: U32.and(U32.div(wi_after, P.RING_ENTRIES()), 1)

# `post_recv`, :234-237. THREE things and there is NO P.msn: a receive consumes no
# packet send numbers, because the psns are the SENDER's. `post_recv_seq` has
# two ring writes' worth of nothing -- one `CALL_RING_W` and one `CALL_DB` --
# and `post_recv_no_msn` is the row that says the P.msn call is absent.
def qp.post_recv_seq(rq_size: U32, +rq_stride: U32, wi: U32, t: Tr) -> Tr:
  Tr.emit(CALL_RING_W(), Q.q.write_off(wi, rq_size, rq_stride, False{}), rq_stride, t)

def qp.post_recv_slot(wi_after: U32) -> U32: U32.mod(wi_after, P.RING_ENTRIES())
def qp.post_recv_epoch(wi_after: U32) -> U32: U32.and(U32.div(wi_after, P.RING_ENTRIES()), 1)

# `register_mem` / `unregister_mem`, :183-189.
def dev.register_mem(level: U32, log_page_size: U32, size: U32, t: Tr) -> Tr:
  Tr.emit(CALL_MR(), mr.lvlpg(level, log_page_size), size, t)

def dev.unregister_mem(key: U32, t: Tr) -> Tr: Tr.emit(CALL_MR(), key, 0, t)

# `fini`, :160 -- one HWRM, `func_drv_unrgtr`.
def dev.fini(t: Tr) -> Tr: Tr.emit(CALL_FINI(), 0, 0, t)

# `_open_l2`, :167-180. Four calls and the two masks that are one line apart.
def dev.open_l2(nq_id: U32, ri: U32, ci: U32, +vnic_id: U32, mac48: U32, t: Tr) -> Tr:
  Tr.emit(CALL_L2_FILTER(), l2_filter_flags(), mac48,
          Tr.emit(CALL_L2_FILTER(), l2_filter_enables(), vnic_id,
            Tr.emit(CALL_VNIC(), vnic_enables(), vnic_id,
              Tr.emit(CALL_VNIC(), P.RING_ALLOC_REQ_RING_TYPE_L2_CMPL(), nq_id, t))))

# `build_pbl`'s trace, :27-37. ONE allocation for the table, a SECOND for the
# top level, and the REFUSAL between them: `pbl_build_seq` shows both
# allocations and `pbl_build_refused` shows the first and nothing else, which
# is what `pbl_deep_ALLOCS == 1` says on the oracle side.
def pbl.build_seq(+n: U32, t: Tr) -> Tr:
  Tr.emit(CALL_ALLOC(), Q.pbl.table_bytes(n), Q.pbl.level_of(n), t)

def pbl.build_top(t: Tr) -> Tr: Tr.emit(CALL_ALLOC(), P.PBL_TOP_BYTES(), P.PBL_MAX_PAGES(), t)

# THE P.PAGE-TABLE REFUSAL, :34. `pbl.build_seq` has already recorded the table
# allocation by the time this runs, so the truncated trace's length IS the
# claim "one allocation happened and then the assert fired".
def pbl.build_check(n: U32, +t: Tr) -> Tr:
  Bool.pick(Tr, Q.pbl.refuses(n), t, Tr.refuse(t))

# THE GATE, PART ONE: the constants, the struct field lists, the 64-bit words
# and the two pack formats.
#
# EVERY `name=value` LINE here must appear, identically, in
# `.agents/slop/bnxt_oracle.txt`, which is produced by CALLING CPython:
#
#   python3 -c "import sys; sys.path.insert(0,'.'); \
#     exec(open('.agents/slop/bnxt_oracle.py').read())" > .agents/slop/bnxt_oracle.txt
#
# and in the NATIVE lane:
#
#   ./bin/bend tinybendygrad/runtime/support/rdma/bnxtdev.bend -o .agents/slop/bnxtdev \
#     && .agents/slop/bnxtdev
#
# the three lanes are diffed, not the row names.
#
# A CONSTANT IS GATED BOTH DIRECTIONS, and that is the point: `c_DBC_DBC_TYPE_RQ`
# says the number is right, and `db_3_HI` says a FUNCTION USING IT is right. A
# file with the right constants and the wrong formula fails the second row; a
# file with the right formula and the wrong constant fails the first. Neither
# row alone can be satisfied by the other's mistake.

# the POPCOUNT and the eight nibbles. Both are folds over a 32-bit word, and
# both are the check that a transposed digit pair cannot survive: the decimal
# `c_BNXT_RTR_MASK=68490669` and the eight nibbles are read off the SAME def,
# so a wrong digit moves a nibble and a wrong def moves both.
#
# THE NIBBLE SHIFT IS A `Nat` PARAMETER, not a computed value -- `U32.shrn`
# takes a `Nat` and there is no way to compute one from a `U32` index, which is
# the general reason a bit-packer with runtime field positions is unwritable.
# The eight nibbles are ONE row joined by spaces, not eight rows, because a
# `do` block cannot be sequenced inside a `match` arm in this Bend and eight
# separate `IO.print` calls is a workaround that says nothing extra.
def mask_pop(v: U32) -> U32: bs.count.go(32n, 0, v, 0)

def mask_nibs.go(n: Nat, +sh: Nat, +v: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+m: mask_nibs.go(m, Nat.add(sh, 4n), v,
      List.append(&2, U32, acc, [U32.shrn(U32.and(U32.shrn(v, sh), 15), 0n)]))

def mask_nibs(v: U32) -> List<&2, U32>: mask_nibs.go(8n, 0n, v, Nil{})

def t_const() -> IO(Unit):
  do IO<Unit>:
    urow("c_BNXT_DEBUG", P.BNXT_DEBUG())
    urow("c_BNXT_ACCESS", P.BNXT_ACCESS())
    urow("c_BNXT_INIT_MASK", P.BNXT_INIT_MASK())
    urow("c_BNXT_RTR_MASK", P.BNXT_RTR_MASK())
    urow("c_BNXT_RTS_MASK", P.BNXT_RTS_MASK())
    urow("c_BNXT_CHIMP_COMM", P.BNXT_CHIMP_COMM())
    urow("c_BNXT_CHIMP_COMM_TRIGGER", P.BNXT_CHIMP_COMM_TRIGGER())
    urow("c_WQE_SIZE", P.WQE_SIZE())
    urow("c_RING_ENTRIES", P.RING_ENTRIES())
    urow("c_CQ_ENTRIES", P.CQ_ENTRIES())
    urow("c_MTU", P.MTU())
    urow("c_BNXT_BACKING_STORE_LEN", BS_LEN())
    # bnxtdev.py:9 the four masks, NIBBLE BY NIBBLE from the least significant
    # end, so a transposed digit pair inside `0x41515ad` cannot hide behind a
    # correct whole. `mask_nib` is the row that does the splitting.
    urow("c_MASK_ACCESS_POP", mask_pop(P.BNXT_ACCESS()))
    urow("c_MASK_INIT_MASK_POP", mask_pop(P.BNXT_INIT_MASK()))
    urow("c_MASK_RTR_MASK_POP", mask_pop(P.BNXT_RTR_MASK()))
    urow("c_MASK_RTS_MASK_POP", mask_pop(P.BNXT_RTS_MASK()))
    lrow("c_MASK_ACCESS_NIBS", mask_nibs(P.BNXT_ACCESS()))
    lrow("c_MASK_INIT_MASK_NIBS", mask_nibs(P.BNXT_INIT_MASK()))
    lrow("c_MASK_RTR_MASK_NIBS", mask_nibs(P.BNXT_RTR_MASK()))
    lrow("c_MASK_RTS_MASK_NIBS", mask_nibs(P.BNXT_RTS_MASK()))
    urow("c_DBC_DBC_XID_MASK", P.DBC_DBC_XID_MASK())
    urow("c_DBC_DBC_PATH_ROCE", P.DBC_DBC_PATH_ROCE())
    urow("c_BNXT_QPLIB_DBR_VALID", P.BNXT_QPLIB_DBR_VALID())
    urow("c_DBC_DBC_INDEX_MASK", P.DBC_DBC_INDEX_MASK())
    urow("c_BNXT_QPLIB_DBR_EPOCH_SHIFT", P.BNXT_QPLIB_DBR_EPOCH_SHIFT())
    urow("c_SQ_SEND_FLAGS_SIGNAL_COMP", P.SQ_SEND_FLAGS_SIGNAL_COMP())
    urow("c_SQ_MSN_SEARCH_START_IDX_SFT", P.SQ_MSN_SEARCH_START_IDX_SFT())
    urow("c_SQ_MSN_SEARCH_NEXT_PSN_SFT", P.SQ_MSN_SEARCH_NEXT_PSN_SFT())
    urow("c_CQ_BASE_TOGGLE", P.CQ_BASE_TOGGLE())
    urow("c_PTU_PTE_VALID", P.PTU_PTE_VALID())
    urow("c_PTU_PTE_LAST", P.PTU_PTE_LAST())
    urow("c_PTU_PTE_NEXT_TO_LAST", P.PTU_PTE_NEXT_TO_LAST())
    urow("c_DBC_DBC_TYPE_SQ", P.DBC_DBC_TYPE_SQ())
    urow("c_DBC_DBC_TYPE_NQ_ARM", P.DBC_DBC_TYPE_NQ_ARM())
    urow("c_DBC_DBC_TYPE_RQ", P.DBC_DBC_TYPE_RQ())
    urow("c_DBC_DBC_TYPE_CQ", P.DBC_DBC_TYPE_CQ())
    urow("c_CMDQ_INIT_CMDQ_SIZE_SFT", P.CMDQ_INIT_CMDQ_SIZE_SFT())
    urow("c_RCFW_COMM_BASE_OFFSET", P.RCFW_COMM_BASE_OFFSET())
    urow("c_RCFW_PF_VF_COMM_PROD_OFFSET", P.RCFW_PF_VF_COMM_PROD_OFFSET())
    urow("c_RCFW_COMM_TRIG_OFFSET", P.RCFW_COMM_TRIG_OFFSET())
    urow("c_RCFW_CMDQ_TRIG_VAL", P.RCFW_CMDQ_TRIG_VAL())
    urow("c_FIRMWARE_FIRST_FLAG", P.FIRMWARE_FIRST_FLAG())
    urow("c_BNXT_HWRM_NO_CMPL_RING", P.BNXT_HWRM_NO_CMPL_RING())
    urow("c_BNXT_HWRM_TARGET", P.BNXT_HWRM_TARGET())
    urow("c_HWRM_MAX_REQ_LEN", P.HWRM_MAX_REQ_LEN())
    urow("c_CREQ_BASE_V", P.CREQ_BASE_V())
    urow("c_CREQ_BASE_TYPE_QP_EVENT", P.CREQ_BASE_TYPE_QP_EVENT())
    urow("c_CREQ_QP_EVENT_EVENT_QP_ERROR_NOTIFICATION", P.CREQ_QP_EVENT_EVENT_QP_ERROR_NOTIFICATION())
    urow("c_RING_ALLOC_REQ_RING_TYPE_NQ", P.RING_ALLOC_REQ_RING_TYPE_NQ())
    urow("c_RING_ALLOC_REQ_RING_TYPE_L2_CMPL", P.RING_ALLOC_REQ_RING_TYPE_L2_CMPL())
    urow("c_RING_ALLOC_REQ_RING_TYPE_RX", P.RING_ALLOC_REQ_RING_TYPE_RX())
    urow("c_RING_ALLOC_REQ_ENABLES_NQ_RING_ID_VALID", P.RING_ALLOC_REQ_ENABLES_NQ_RING_ID_VALID())
    urow("c_RING_ALLOC_REQ_ENABLES_RX_BUF_SIZE_VALID", P.RING_ALLOC_REQ_ENABLES_RX_BUF_SIZE_VALID())
    urow("c_RING_ALLOC_REQ_INT_MODE_MSIX", P.RING_ALLOC_REQ_INT_MODE_MSIX())
    urow("c_VNIC_CFG_REQ_ENABLES_MRU", P.VNIC_CFG_REQ_ENABLES_MRU())
    urow("c_VNIC_CFG_REQ_ENABLES_DEFAULT_RX_RING_ID", P.VNIC_CFG_REQ_ENABLES_DEFAULT_RX_RING_ID())
    urow("c_VNIC_CFG_REQ_ENABLES_DEFAULT_CMPL_RING_ID", P.VNIC_CFG_REQ_ENABLES_DEFAULT_CMPL_RING_ID())
    urow("c_CFA_L2_FILTER_ALLOC_REQ_FLAGS_PATH_RX", P.CFA_L2_FILTER_ALLOC_REQ_FLAGS_PATH_RX())
    urow("c_CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR", P.CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR())
    urow("c_CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR_MASK", P.CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR_MASK())
    urow("c_CFA_L2_FILTER_ALLOC_REQ_ENABLES_DST_ID", P.CFA_L2_FILTER_ALLOC_REQ_ENABLES_DST_ID())
    urow("c_FUNC_BACKING_STORE_CFG_V2_REQ_FLAGS_BS_CFG_ALL_DONE", P.FUNC_BACKING_STORE_CFG_V2_REQ_FLAGS_BS_CFG_ALL_DONE())
    urow("c_CMDQ_REGISTER_MR_LVL_SFT", P.CMDQ_REGISTER_MR_LVL_SFT())
    urow("c_CMDQ_REGISTER_MR_LOG2_PG_SIZE_SFT", P.CMDQ_REGISTER_MR_LOG2_PG_SIZE_SFT())
    urow("c_CMDQ_REGISTER_MR_ACCESS_LOCAL_WRITE", P.CMDQ_REGISTER_MR_ACCESS_LOCAL_WRITE())
    urow("c_CMDQ_REGISTER_MR_ACCESS_REMOTE_WRITE", P.CMDQ_REGISTER_MR_ACCESS_REMOTE_WRITE())
    urow("c_CMDQ_REGISTER_MR_FLAGS_ALLOC_MR", P.CMDQ_REGISTER_MR_FLAGS_ALLOC_MR())
    urow("c_CMDQ_INITIALIZE_FW_FLAGS_HW_REQUESTER_RETX_SUPPORTED", P.CMDQ_INITIALIZE_FW_FLAGS_HW_REQUESTER_RETX_SUPPORTED())
    urow("c_CMDQ_CREATE_QP_TYPE_RC", P.CMDQ_CREATE_QP_TYPE_RC())
    urow("c_CMDQ_MODIFY_QP_QP_TYPE_RC", P.CMDQ_MODIFY_QP_QP_TYPE_RC())
    urow("c_CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4", P.CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4())
    urow("c_CMDQ_MODIFY_QP_PATH_MTU_MTU_4096", P.CMDQ_MODIFY_QP_PATH_MTU_MTU_4096())
    # the four COMPOSED words, which are a different claim from any single
    # constant: each is a mis-pairing risk and one is a line away from another.
    urow("c_L2_ENABLES", vnic_enables())
    urow("c_L2_FILTER_ENABLES", l2_filter_enables())
    urow("c_RING_ALLOC_L2_ENABLES", ra_l2_enables())
    urow("c_RING_ALLOC_RX_ENABLES", ra_rx_enables())
    urow("c_REGISTER_MR_ACCESS", U32.or(P.CMDQ_REGISTER_MR_ACCESS_LOCAL_WRITE(), P.CMDQ_REGISTER_MR_ACCESS_REMOTE_WRITE()))
    # ctypes.sizeof, which :133 and :194 both ask for.
    urow("c_SIZEOF_CQ_BASE", P.SIZEOF_CQ_BASE())
    urow("c_SIZEOF_RESP_HDR", P.SIZEOF_RESP_HDR())
    urow("c_SIZEOF_CMDQ_INIT", P.SIZEOF_CMDQ_INIT())
    urow("c_SIZEOF_CMDQ_ADD_GID", P.SIZEOF_CMDQ_ADD_GID())
    urow("c_SLOTS_CMDQ_ADD_GID", rcfw.slots_of(P.SIZEOF_CMDQ_ADD_GID()))
    urow("c_SIZEOF_CMDQ_INITIALIZE_FW", P.SIZEOF_CMDQ_INITIALIZE_FW())
    urow("c_SLOTS_CMDQ_INITIALIZE_FW", rcfw.slots_of(P.SIZEOF_CMDQ_INITIALIZE_FW()))
    urow("c_SIZEOF_CMDQ_CREATE_CQ", P.SIZEOF_CMDQ_CREATE_CQ())
    urow("c_SLOTS_CMDQ_CREATE_CQ", rcfw.slots_of(P.SIZEOF_CMDQ_CREATE_CQ()))
    urow("c_SIZEOF_CMDQ_CREATE_QP", P.SIZEOF_CMDQ_CREATE_QP())
    urow("c_SLOTS_CMDQ_CREATE_QP", rcfw.slots_of(P.SIZEOF_CMDQ_CREATE_QP()))
    urow("c_SIZEOF_CMDQ_MODIFY_QP", P.SIZEOF_CMDQ_MODIFY_QP())
    urow("c_SLOTS_CMDQ_MODIFY_QP", rcfw.slots_of(P.SIZEOF_CMDQ_MODIFY_QP()))
    urow("c_SIZEOF_CMDQ_REGISTER_MR", P.SIZEOF_CMDQ_REGISTER_MR())
    urow("c_SLOTS_CMDQ_REGISTER_MR", rcfw.slots_of(P.SIZEOF_CMDQ_REGISTER_MR()))
    urow("c_SIZEOF_CMDQ_DEREGISTER_MR", P.SIZEOF_CMDQ_DEREGISTER_MR())
    urow("c_SLOTS_CMDQ_DEREGISTER_MR", rcfw.slots_of(P.SIZEOF_CMDQ_DEREGISTER_MR()))

# the struct field lists, by name and in order.
#
# every field is named at its own call site. That is deliberate and it is the
# whole requirement: a wrong field ORDER moves a row, and a right field COUNT
# with a wrong order STILL moves one, because the row is named after the field
# and not after its position. A walk that printed `f_struct_cq_base_<i>_AT`
# would have been shorter and would have passed a transposed layout.
#
# The lists themselves came out of `_real_fields_` -- `ctypes._fields_` on these
# `c.record` structs is the opaque `('_mem_',)`, so plain ctypes cannot see the
# names at all. `.agents/slop/bnxt_structs.py` reads them off the RUNTIME class.

def nth_at(+xs: List<&2, U32>, i: Nat) -> U32: Maybe.default(&2, U32, List.get(&2, U32, xs, i), 0)

def name_at(+xs: List<&2, String>, i: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, i), "")

def frow(+pfx: String, +nm: String, +ats: List<&2, U32>, +ws: List<&2, U32>, +i: Nat) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat([pfx, "_", nm, "_AT"]), nth_at(ats, i))
    urow(String.concat([pfx, "_", nm, "_W"]), nth_at(ws, i))

def t_struct() -> IO(Unit):
  do IO<Unit>:
    nrow("f_struct_cq_base_NAMES", P.struct_cq_base_names())
    nrow("f_struct_hwrm_resp_hdr_NAMES", P.struct_hwrm_resp_hdr_names())
    nrow("f_struct_cmdq_init_NAMES", P.struct_cmdq_init_names())
    nrow("f_struct_cmdq_base_NAMES", P.struct_cmdq_base_names())
    frow("f_struct_cq_base", "reserved64_1", P.struct_cq_base_at(), P.struct_cq_base_w(), 0n)
    frow("f_struct_cq_base", "reserved64_2", P.struct_cq_base_at(), P.struct_cq_base_w(), 1n)
    frow("f_struct_cq_base", "reserved64_3", P.struct_cq_base_at(), P.struct_cq_base_w(), 2n)
    frow("f_struct_cq_base", "cqe_type_toggle", P.struct_cq_base_at(), P.struct_cq_base_w(), 3n)
    frow("f_struct_cq_base", "status", P.struct_cq_base_at(), P.struct_cq_base_w(), 4n)
    frow("f_struct_cq_base", "reserved16", P.struct_cq_base_at(), P.struct_cq_base_w(), 5n)
    frow("f_struct_cq_base", "opaque", P.struct_cq_base_at(), P.struct_cq_base_w(), 6n)
    frow("f_struct_hwrm_resp_hdr", "error_code", P.struct_hwrm_resp_hdr_at(), P.struct_hwrm_resp_hdr_w(), 0n)
    frow("f_struct_hwrm_resp_hdr", "req_type", P.struct_hwrm_resp_hdr_at(), P.struct_hwrm_resp_hdr_w(), 1n)
    frow("f_struct_hwrm_resp_hdr", "seq_id", P.struct_hwrm_resp_hdr_at(), P.struct_hwrm_resp_hdr_w(), 2n)
    frow("f_struct_hwrm_resp_hdr", "resp_len", P.struct_hwrm_resp_hdr_at(), P.struct_hwrm_resp_hdr_w(), 3n)
    frow("f_struct_cmdq_init", "cmdq_pbl", P.struct_cmdq_init_at(), P.struct_cmdq_init_w(), 0n)
    frow("f_struct_cmdq_init", "cmdq_size_cmdq_lvl", P.struct_cmdq_init_at(), P.struct_cmdq_init_w(), 1n)
    frow("f_struct_cmdq_init", "creq_ring_id", P.struct_cmdq_init_at(), P.struct_cmdq_init_w(), 2n)
    frow("f_struct_cmdq_init", "prod_idx", P.struct_cmdq_init_at(), P.struct_cmdq_init_w(), 3n)
    frow("f_struct_cmdq_base", "opcode", P.struct_cmdq_base_at(), P.struct_cmdq_base_w(), 0n)
    frow("f_struct_cmdq_base", "cmd_size", P.struct_cmdq_base_at(), P.struct_cmdq_base_w(), 1n)
    frow("f_struct_cmdq_base", "flags", P.struct_cmdq_base_at(), P.struct_cmdq_base_w(), 2n)
    frow("f_struct_cmdq_base", "cookie", P.struct_cmdq_base_at(), P.struct_cmdq_base_w(), 3n)
    frow("f_struct_cmdq_base", "resp_size", P.struct_cmdq_base_at(), P.struct_cmdq_base_w(), 4n)
    frow("f_struct_cmdq_base", "reserved8", P.struct_cmdq_base_at(), P.struct_cmdq_base_w(), 5n)
    frow("f_struct_cmdq_base", "resp_addr", P.struct_cmdq_base_at(), P.struct_cmdq_base_w(), 6n)
def cqe_status_at() -> String: name_at(P.struct_cq_base_names(), 4n)

def cqe_toggle_at() -> String: name_at(P.struct_cq_base_names(), 3n)
def resp_hdr_len_at() -> String: name_at(P.struct_hwrm_resp_hdr_names(), 3n)

def t_offset_names() -> IO(Unit):
  do IO<Unit>:
    srow("f_CQE_TOGGLE_FIELD", cqe_toggle_at())
    srow("f_CQE_STATUS_FIELD", cqe_status_at())
    srow("f_RESP_HDR_FIRST", name_at(P.struct_hwrm_resp_hdr_names(), 0n))
    srow("f_RESP_HDR_LEN_FIELD", resp_hdr_len_at())

def WQE_KIND_AT() -> U32: 16

# WORD 0, AND THE COMMENT `ops_rdma.bend` GETS WRONG. See the header: the code
# at `ops_rdma.bend:1463-1465` is right and the comment at :224-225 is
# INVERTED. These rows print the three bytes out of their places so the claim
# is `kind at 16, flags at 8, type at 0` and not a restatement of `P.wqe.hdr0`.

# WHAT `ops_rdma.bend:237 symbol=P.WQE_KIND` CLAIMS: `type << 16 | flags << 8 | kind`. Both
# the claim and its refutation are rows, so the disagreement is a NUMBER in a
# committed artefact rather than an argument in a commit message.
# `type << 16 | flags << 8 | kind`, with each byte taken from where the REAL
# word has it. It evaluates to 259 for a send and 8388611 for a receive, and the
# real word is 196864 and 196736, so the claim is wrong by three orders of
# magnitude on the send and it is a row rather than a sentence.
def hdr0_comment_says(+recv: Bool) -> U32:
  U32.or(U32.shln(Bool.pick(U32, recv, P.RECV_KIND(), 0), U32.to_nat(WQE_KIND_AT())),
         U32.or(U32.shln(Bool.pick(U32, recv, 0, P.SQ_SEND_FLAGS_SIGNAL_COMP()), 8n), P.WQE_KIND()))

def t_hdr0() -> IO(Unit):
  do IO<Unit>:
    urow("hdr0_SEND_REAL", P.wqe.hdr0(False{}))
    urow("hdr0_SEND_KIND_AT16", U32.and(U32.shrn(P.wqe.hdr0(False{}), 16n), 255))
    urow("hdr0_SEND_FLAGS_AT8", U32.and(U32.shrn(P.wqe.hdr0(False{}), 8n), 255))
    urow("hdr0_SEND_TYPE_AT0", U32.and(P.wqe.hdr0(False{}), 255))
    urow("hdr0_SEND_COMMENT_SAYS", hdr0_comment_says(False{}))
    brow("hdr0_SEND_COMMENT_IS_RIGHT", U32.is_eq(hdr0_comment_says(False{}), P.wqe.hdr0(False{})))
    urow("hdr0_RECV_REAL", P.wqe.hdr0(True{}))
    urow("hdr0_RECV_KIND_AT16", U32.and(U32.shrn(P.wqe.hdr0(True{}), 16n), 255))
    urow("hdr0_RECV_FLAGS_AT8", U32.and(U32.shrn(P.wqe.hdr0(True{}), 8n), 255))
    urow("hdr0_RECV_TYPE_AT0", U32.and(P.wqe.hdr0(True{}), 255))
    urow("hdr0_RECV_COMMENT_SAYS", hdr0_comment_says(True{}))
    brow("hdr0_RECV_COMMENT_IS_RIGHT", U32.is_eq(hdr0_comment_says(True{}), P.wqe.hdr0(True{})))

# THE 64-BIT WORDS, in HALVES. `db_value` (:13-15) and `msn_entry` (:20-24),
# eight cases each, and every one is the REAL function called by the oracle.
# The fixtures are chosen so a mask that is vacuous at one scale shows: the
# P.msn cases straddle 2^24 (`msn_3` at `psn == 0xffffff`), which is what makes
# `& 0xffffff` visible at all.

def db_row(+i: U32, xid: U32, typ: U32, ix: U32, ep: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["db_", U32.show(i), "_HI"]), P.db.hi(xid, typ))
    urow(String.concat(["db_", U32.show(i), "_LO"]), P.db.lo(ix, ep))

def t_db() -> IO(Unit):
  do IO<Unit>:
    db_row(0, 0, P.DBC_DBC_TYPE_SQ(), 0, 0)
    db_row(1, 5, P.DBC_DBC_TYPE_SQ(), 0, 0)
    db_row(2, 74565, P.DBC_DBC_TYPE_RQ(), 1, 0)
    db_row(3, 74565, P.DBC_DBC_TYPE_CQ(), 4097, 1)
    db_row(4, 1048575, P.DBC_DBC_TYPE_NQ_ARM(), 255, 1)
    db_row(5, 7, P.DBC_DBC_TYPE_NQ_ARM(), 256, 0)
    db_row(6, 524287, P.DBC_DBC_TYPE_SQ(), 16777215, 1)
    db_row(7, 524288, P.DBC_DBC_TYPE_RQ(), 4095, 1)

def msn_row(+i: U32, wqe_idx: U32, +psn: U32, +size: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["msn_", U32.show(i), "_HI"]), P.msn.hi(P.msn.slot_of(wqe_idx), P.msn.next_of(P.msn.mask(psn), size)))
    urow(String.concat(["msn_", U32.show(i), "_LO"]), P.msn.lo(P.msn.next_of(P.msn.mask(psn), size), P.msn.mask(psn)))
    urow(String.concat(["msn_", U32.show(i), "_NEXT"]), P.msn.next_of(P.msn.mask(psn), size))

# THE TWO PACKS. Eight words of the send header and seven of the receive, plus
# the lengths and the scatter-gather element. `wqe_1` is the ZERO case and
# `wqe_2` the LARGE one; between them they see `size` in word 2 on the send
# and NO size at all on the receive.

def t_msn() -> IO(Unit):
  do IO<Unit>:
    msn_row(0, 0, 0, 100)
    msn_row(1, 0, 4095, 4096)
    msn_row(2, 1, 4096, 1)
    msn_row(3, 4095, 16777215, 2)
    msn_row(4, 4096, 16777215, 4096)
    msn_row(5, 7, 16777200, 0)
    msn_row(6, 131071, 1, 4096)
    msn_row(7, 4097, 8388608, 8192)

def wqe_row(i: U32, +va_lo: U32, +key: U32, +size: U32) -> IO(Unit):
  do IO<Unit>:
    +s : List<&2, U32> = P.wqe.words(False{}, size, va_lo, 0, key)
    +r : List<&2, U32> = P.wqe.words(True{}, size, va_lo, 0, key)
    +p : String = U32.show(i)
    urow(String.concat(["wqe_", p, "_S_LEN"]), P.WQE_BYTES())
    urow(String.concat(["wqe_", p, "_R_LEN"]), P.WQE_BYTES())
    lrow(String.concat(["wqe_", p, "_S"]), List.take(&2, U32, s, 8n))
    lrow(String.concat(["wqe_", p, "_R"]), List.take(&2, U32, r, 7n))
    urow(String.concat(["wqe_", p, "_S_VA_LO"]), nth_at(s, 8n))
    urow(String.concat(["wqe_", p, "_S_VA_HI"]), nth_at(s, 9n))
    urow(String.concat(["wqe_", p, "_R_VA_LO"]), nth_at(r, 8n))
    urow(String.concat(["wqe_", p, "_R_VA_HI"]), nth_at(r, 9n))

def t_wqe() -> IO(Unit):
  do IO<Unit>:
    wqe_row(0, 4096, 170, 64)
    wqe_row(1, 0, 0, 0)
    wqe_row(2, 3735928559, 4294967295, 4096)

# THE GATE, PART TWO: the page table, the queue, the completion status, the
# logging table, the gid/mac unpacking and the device index arithmetic.
#
# THE P.PAGE-TABLE FIXTURE. The `pbl_q_*` rows need a physical address to
# encode, and the oracle builds one with its `FakePci`: page `i` is
# `0x7a0000000000 + i * 0x1000`, so the high half is 31232 for every entry and
# the low half is `i * 4096`. Those two numbers are a FIXTURE, shared by both
# sides, and nothing is gated on them: what is gated is that
# `Q.pbl.entry_lo_at` turns that address plus the right flags into the entry
# `build_pbl` actually wrote, and that `Q.pbl.entry_hi` leaves the high half
# alone. `pbl_hi_untouched` is the row for the second half of that claim.

def PBL_FIX_HI() -> U32: 31232
def pbl_fix_lo(i: U32) -> U32: U32.mul(i, P.PAGE())

def pbl.alloc0_of(+n: U32) -> U32:
  Bool.pick(U32, U32.is_eq(Q.pbl.level_of(n), 0), 0, Q.pbl.table_bytes(n))

def pbl.alloc1_of(n: U32) -> U32:
  Bool.pick(U32, U32.is_eq(Q.pbl.level_of(n), 2), P.PBL_TOP_BYTES(), 0)

# how many allocations `build_pbl` performs: NONE for the one-page shortcut, ONE
# for a single-level table, TWO for a two-level one, and ONE more attempt at a
# table that will be REFUSED.
# `build_pbl` performs 0, 1 or 2 `alloc_sysmem` calls -- one per LEVEL, and none
# at all for the one-page shortcut -- so the count IS the level. `level_of(n) - 1`
# is the wrong formula and it UNDERFLOWS at level 0: `pbl_q_1_ALLOCS` printed
# 4294967295 and said so.
def pbl.allocs_of(+n: U32) -> U32: Q.pbl.level_of(n)

def pbl_row(+n: U32) -> IO(Unit):
  do IO<Unit>:
    +nm : String = String.concat(["pbl_q_", U32.show(n)])
    urow(String.concat([nm, "_LEVEL"]), Q.pbl.level_of(n))
    brow(String.concat([nm, "_BASE_IS_FIRST"]), U32.is_eq(Q.pbl.level_of(n), 0))
    urow(String.concat([nm, "_ALLOCS"]), pbl.allocs_of(n))
    urow(String.concat([nm, "_ALLOC0"]), pbl.alloc0_of(n))
    # the LAST entry and the one before it, both directions
    urow(String.concat([nm, "_ENTRYLAST_HI"]), Q.pbl.entry_hi(PBL_FIX_HI()))
    urow(String.concat([nm, "_ENTRYLAST_LO"]), Q.pbl.entry_lo_at(pbl_fix_lo(U32.sub(n, 1)), True{}, U32.sub(n, 1), n))
    urow(String.concat([nm, "_ENTRYN1_HI"]), Q.pbl.entry_hi(PBL_FIX_HI()))
    urow(String.concat([nm, "_ENTRYN1_LO"]), Q.pbl.entry_lo_at(pbl_fix_lo(U32.sub(n, 2)), True{}, U32.sub(n, 2), n))
    urow(String.concat([nm, "_ENTRY0_HI"]), Q.pbl.entry_hi(PBL_FIX_HI()))
    urow(String.concat([nm, "_ENTRY0_LO"]), Q.pbl.entry_lo_at(pbl_fix_lo(0), True{}, 0, n))
    urow(String.concat([nm, "_ALLOC1"]), pbl.alloc1_of(n))
    urow(String.concat([nm, "_TOP_BYTES"]), P.PBL_TOP_BYTES())

def t_pbl() -> IO(Unit):
  do IO<Unit>:
    pbl_row(1)
    pbl_row(2)
    pbl_row(511)
    pbl_row(512)
    pbl_row(513)
    pbl_row(1024)
    pbl_row(1025)
    # the one-paddr shortcut returns the address ITSELF: no VALID bit, no
    # allocation, and the value is not an encoded entry at all.
    urow("pbl_one_LEVEL", Q.pbl.level_of(1))
    brow("pbl_one_NOFLAGS", Bool.not(Q.pbl.valid_of(pbl_fix_lo(0))))
    brow("pbl_one_BASE_IS_INPUT", U32.is_eq(Q.pbl.entry_hi(PBL_FIX_HI()), PBL_FIX_HI()))
    # `queue=False`: NO last and NO next-to-last on the final entry.
    urow("pbl_noq_LEVEL", Q.pbl.level_of(4))
    urow("pbl_noq_ENTRYLAST_HI", Q.pbl.entry_hi(PBL_FIX_HI()))
    urow("pbl_noq_ENTRYLAST_LO", Q.pbl.entry_lo_at(pbl_fix_lo(3), False{}, 3, 4))
    urow("pbl_noq_ENTRY0_HI", Q.pbl.entry_hi(PBL_FIX_HI()))
    urow("pbl_noq_ENTRY0_LO", Q.pbl.entry_lo_at(pbl_fix_lo(0), False{}, 0, 4))
    # THE ENCODE/DECODE PAIR. Re-encode a decoded entry and get the original:
    # this is the OTHER DIRECTION the page table has to answer in.
    brow("pbl_hi_untouched", U32.is_eq(Q.pbl.entry_hi(4242), 4242))
    brow("pbl_roundtrip_last", U32.is_eq(Q.pbl.encode(4096, True{}, True{}), 4099))
    brow("pbl_roundtrip_ntl", U32.is_eq(Q.pbl.encode(4096, True{}, False{}), 4101))
    brow("pbl_decode_last", Q.pbl.has_last(4099))
    brow("pbl_decode_ntl", Q.pbl.has_ntl(4101))
    brow("pbl_decode_valid", Q.pbl.valid_of(4097))
    brow("pbl_flags_exclusive", Q.pbl.flags_exclusive(4099))
    brow("pbl_flags_exclusive_ntl", Q.pbl.flags_exclusive(4101))
    brow("pbl_flags_exclusive_neither", Q.pbl.flags_exclusive(4097))
    urow("pbl_decode_addr_last", Q.pbl.addr_of(4099))
    urow("pbl_decode_addr_ntl", Q.pbl.addr_of(4101))
    # THE `len(table_paddrs) <= 512` BOUNDARY. 512 pages is LEGAL and 513
    # refuses, and M10 moved NOTHING until these two rows existed: every other
    # `pbl_q_*` fixture is 1, 2 or 3 pages, so no fixture reached the limit.
    brow("pbl_edge_262144_REFUSED", Q.pbl.refuses(262144))
    brow("pbl_edge_262145_REFUSED", Q.pbl.refuses(262145))
    brow("pbl_edge_differ", Bool.not(Q.pbl.refuses(262144)))
    # the LEVEL at the boundary, not only the refusal: `refuses` is `>` and
    # `level_of` is `<=`, and M10 mutates the `<=`, so only a row that reads
    # `level_of` can see it. Two rows for one boundary is not redundancy, it is
    # two different predicates.
    urow("pbl_edge_262144_LEVEL", Q.pbl.level_of(262144))
    urow("pbl_edge_262145_LEVEL", Q.pbl.level_of(262145))
    brow("pbl_edge_level_differ", Bool.not(U32.is_eq(Q.pbl.level_of(262144), Q.pbl.level_of(262145))))
    # THE REFUSAL, :34. `P.ceildiv(512*512 + 1, 512) == 513 > 512`.
    urow("pbl_deep_LEVEL", Q.pbl.level_of(262145))
    brow("pbl_deep_REFUSED", Q.pbl.refuses(262145))
    brow("pbl_deep_not_refused", Bool.not(Q.pbl.refuses(262144)))
    # ONE allocation happened and THEN the assert fired, which is what the truncated
    # trace length claims. `allocs_of(262144)` is 2 because 512 pages is not
    # over the limit -- the refused case is 262145.
    urow("pbl_deep_ALLOCS", Bool.pick(U32, Q.pbl.refuses(262145), 1, pbl.allocs_of(262145)))

# `0x5a` repeated is what the oracle WRITES into the queue, so a read of the
# first four bytes back is `0x5a5a5a5a` whatever the stride. The row says the
# ring read returns what was written, not a computed offset.
def FILL_BYTE() -> U32: 1515870810

def aq_off(+nm: String, +j: U32, +i: U32, ns: U32, +sz: U32, +stride: U32, aux: Bool) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat([nm, "_W", U32.show(j)]), Q.q.write_off(i, sz, stride, False{}))
    urow(String.concat([nm, "_WL", U32.show(j)]), Q.q.write_len(sz, stride, False{}, stride))
    urow(String.concat([nm, "_WA", U32.show(j)]), Q.q.write_off(i, sz, stride, True{}))

# THE QUEUE. `alloc_queue` (:47-50) and `BNXTQueue.read`/`write` (:42-45), and
# the oracle for these rows calls the REAL `alloc_queue` against a fake PCI and
# reads the slice bounds back out of its MMIO stand-in -- so `aq_*_W*` is the
# offset the source computed, not the offset this file believes it computed.
#
# SIX FIXTURES and between them they separate every claim: a default 16-byte
# queue (256 slots), the same with the aux P.msn table (so `size` is 6144 while
# the queue is still 4096), a 128-byte queue with aux, a 128-byte queue with
# aux FALSE (so `size` is 4096 and the aux base moves with it), a 4096-entry
# 32-byte queue, and a THREE-entry queue where the page default does not apply.

def aq_row(i: U32, +stride: U32, +aux: Bool, +entries: U32) -> IO(Unit):
  do IO<Unit>:
    +nm : String = String.concat(["aq_", U32.show(i)])
    +sz : U32 = Q.q.size_of(stride, entries)
    +ns : U32 = Q.q.slots(sz, stride)
    urow(String.concat([nm, "_SIZE"]), sz)
    urow(String.concat([nm, "_STRIDE"]), stride)
    urow(String.concat([nm, "_LEVEL"]), Q.pbl.level_of(Q.q.pbl_pages_of(Q.q.alloc_of(stride, aux, entries))))
    urow(String.concat([nm, "_ALLOC0"]), Q.q.alloc_of(stride, aux, entries))
    urow(String.concat([nm, "_SLOTS"]), ns)
    +a : Unit <- aq_off(nm, 0, 0, ns, sz, stride, aux)
    +b : Unit <- aq_off(nm, 1, 1, ns, sz, stride, aux)
    +c : Unit <- aq_off(nm, 2, U32.sub(ns, 1), ns, sz, stride, aux)
    +d : Unit <- aq_off(nm, 3, ns, ns, sz, stride, aux)
    +e : Unit <- aq_off(nm, 4, U32.add(ns, 1), ns, sz, stride, aux)
    urow(String.concat([nm, "_RLEN"]), Q.q.read_len(sz, stride))
    urow(String.concat([nm, "_R0"]), FILL_BYTE)
    urow(String.concat([nm, "_RN"]), FILL_BYTE)

def t_aq() -> IO(Unit):
  do IO<Unit>:
    aq_row(0, 16, False{}, 0)
    aq_row(1, 16, True{}, 0)
    aq_row(2, 128, True{}, 0)
    aq_row(3, 128, False{}, 0)
    aq_row(4, 32, False{}, 4096)
    aq_row(5, 16, True{}, 3)
    # the wrap: index == slots and index == slots + 1 come back to the start
    urow("qwrap_SLOTS", 256)
    urow("qwrap_READ", 16)
    brow("qwrap_READ_EQ0", U32.is_eq(Q.q.read_off(256, 4096, 16), Q.q.read_off(0, 4096, 16)))

# THE COMPLETION AND ERROR STATUS. `cqe_ready` (:25) over real 32-byte
# entries, `struct_cq_base` byte 24 BY NAME, the CQE status byte at 25, and
# the CREQ valid bit at byte 8 against `read_idx // 256`.

def cqe_row(i: U32, toggle: U32, cons: U32) -> IO(Unit):
  do IO<Unit>:
    brow(String.concat(["cqe_", U32.show(i), "_READY"]), P.cqe.ready(toggle, cons))

def t_cqe() -> IO(Unit):
  do IO<Unit>:
    cqe_row(0, 0, 0)
    cqe_row(1, 1, 0)
    cqe_row(2, 0, 4096)
    cqe_row(3, 1, 4096)
    cqe_row(4, 1, 1)
    cqe_row(5, 0, 1)
    cqe_row(6, 0, 4097)
    cqe_row(7, 3, 2)
    urow("c_CQE_TOGGLE_MASK", P.CQ_BASE_TOGGLE())
    urow("c_CQE_STATUS_AT", P.CQE_STATUS_AT())
    urow("c_CREQ_V_AT", P.CREQ_TOGGLE_AT())
    # byte 24 is the TOGGLE and byte 25 is the STATUS, BY NAME -- the two the
    # source reads by hand. `P.cqe_toggle_field`/`P.cqe_status_field` are
    # predicates on the name, so these rows cannot pass with the fields
    # transposed.
    brow("cqe_toggle_is_toggle", P.cqe_toggle_field(name_at(P.struct_cq_base_names(), 3n)))
    brow("cqe_status_is_status", P.cqe_status_field(name_at(P.struct_cq_base_names(), 4n)))
    brow("cqe_byte0_is_reserved", Bool.not(P.cqe_toggle_field(name_at(P.struct_cq_base_names(), 0n))))
    # the CREQ shape, :146 -- the same test with byte 8 and a 256-wrap
    brow("creq_ready_0", creq.ready(0, 0))
    brow("creq_ready_1", creq.ready(1, 0))
    brow("creq_ready_256", creq.ready(0, 256))
    brow("creq_ready_257", creq.ready(1, 256))
    urow("creq_nq_arm_index", rcfw.nq_arm_index(300))
    urow("creq_nq_arm_epoch", rcfw.nq_arm_epoch(300))
    urow("creq_nq_arm_index_255", rcfw.nq_arm_index(255))
    urow("creq_nq_arm_index_256", rcfw.nq_arm_index(256))
    # the async-event filter, :154. `event < 192` is the SKIP, so 192 itself is
    # NOT a skip -- the boundary row, one below `rcfq_skip_below`.
    brow("rcfw_skip_0", rcfw.skip(P.CREQ_BASE_TYPE_QP_EVENT(), 0))
    brow("rcfw_skip_191", rcfw.skip(P.CREQ_BASE_TYPE_QP_EVENT(), 191))
    brow("rcfw_skip_192", rcfw.skip(P.CREQ_BASE_TYPE_QP_EVENT(), 192))
    brow("rcfw_skip_not_event", rcfw.skip(0, 0))
    brow("rcfw_skip_event_56", rcfw.is_event(56))
    brow("rcfw_skip_event_0", rcfw.is_event(0))

def bs_typs(+i: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["c_BS_TYP_", U32.show(i)]), bs.typ_at(i))
    urow(String.concat(["c_BS_EXTRA_", U32.show(i)]), bs.extra_at(i))

def bs_typs_all() -> List<&2, U32>: BS_TYP()

# THE LOGGING TABLE, both directions. Nine (type, extra) pairs forward, the
# `counts` derivation that type 15 shares with type 0, the instance bitmap
# walk including two ZERO bitmaps, the `ctx_init` sweep, the alloc rounding and
# the ALL_DONE flag.

def bs_type_rows() -> IO(Unit):
  do IO<Unit>:
    +a : Unit <- bs_typs(0)
    +b : Unit <- bs_typs(1)
    +c : Unit <- bs_typs(2)
    +d : Unit <- bs_typs(3)
    +e : Unit <- bs_typs(4)
    +f : Unit <- bs_typs(5)
    +g : Unit <- bs_typs(6)
    +h : Unit <- bs_typs(7)
    +i : Unit <- bs_typs(8)
    lrow("c_BS_TYPES_ASC", bs_typs_all())

# THE COUNTS. `FIX` is the caps fixture from `.agents/slop/bnxt_oracle.py`, one
# entry per type: (entry_size, min_num_entries, sum of splits, instance bitmap).
# Type 0's count is 128 (64 + 64 splits) and type 15 REUSES it verbatim.
def bs_count(+typ: U32, mne: U32, splits: U32, c0: U32) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["bs_COUNT_", U32.show(typ)]), bs.count_of(typ, mne, splits, c0))

# the `or [0]`: a scan that found nothing answers the single instance 0.
def bs_inst_or_zero(+acc: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, U32.is_eq(U32.from_nat(List.length(&2, U32, acc)), 0), [0], acc)

# the LIST :98 builds, `[i for i in range(8) if ibm >> i & 1] or [0]`. A fold
# that appends, so the order is ASCENDING and the count matches the list.
def bs_inst_list.go(n: Nat, +ix: U32, +ibm: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: bs_inst_or_zero(acc)
    case 1n+m: bs_inst_list.go(m, U32.inc(ix), ibm,
      Bool.pick(List<&2, U32>, bs.inst_bit(ibm, ix),
        List.append(&2, U32, acc, [ix]), acc))

def bs_inst_list(ibm: U32) -> List<&2, U32>: bs_inst_list.go(8n, 0, ibm, Nil{})

def bs_inst(+i: U32, +ibm: U32) -> IO(Unit):
  do IO<Unit>:
    srow(String.concat(["bs_INST_", U32.show(i)]), join_u32(bs_inst_list(ibm)))
    urow(String.concat(["bs_INST_", U32.show(i), "_N"]), bs.ninstances(ibm))

def t_bs() -> IO(Unit):
  do IO<Unit>:
    bs_type_rows()
    # THE FOLD, in table order, and the one row that matters is `bs_COUNT_15`:
    # type 15's count is type 0's, COPIED -- not 64 (its extra), not its own
    # min_num_entries, and not `max`ed against anything.
    bs_count(0, 16, 64, 0)
    bs_count(1, 1, 0, 128)
    bs_count(2, 1, 128, 128)
    bs_count(3, 8, 0, 128)
    bs_count(4, 1, 2, 128)
    bs_count(5, 4, 0, 128)
    bs_count(6, 1, 96, 128)
    bs_count(14, 1, 0, 128)
    bs_count(15, 0, 0, 128)
    brow("bs_count_15_is_zero_count", U32.is_eq(bs.count_of(15, 999, 999, 128), 128))
    brow("bs_count_15_ignores_mne", U32.is_eq(bs.count_of(15, 7, 0, 42), 42))
    # `max(min_num_entries, sum + extra)` -- the floor wins for type 1 and the
    # sum wins for type 2, one entry apart.
    brow("bs_count_1_floor_wins", U32.is_eq(bs.count_of(1, 64, 0, 0), 64))
    brow("bs_count_2_sum_wins", U32.is_eq(bs.count_of(2, 1, 128, 0), 256))
    # the search. Types 7..13 are not in the table, so an index is not a type.
    brow("bs_absent_7", U32.is_eq(bs.index_of(7), BS_LEN()))
    brow("bs_present_7_is_not_0", Bool.not(U32.is_eq(bs.index_of(7), 0)))
    urow("bs_extra_absent_7", bs.extra_of(7))
    urow("bs_index_14", bs.index_of(14))
    urow("bs_extra_14", bs.extra_of(14))
    urow("bs_extra_15", bs.extra_of(15))
    # THE INSTANCE BITMAP, :98, including two ZERO bitmaps whose answer is the
    # single instance 0 from `or [0]`.
    +a : Unit <- bs_inst(0, 1)
    +b : Unit <- bs_inst(1, 0)
    +c : Unit <- bs_inst(2, 4)
    +d : Unit <- bs_inst(3, 255)
    +e : Unit <- bs_inst(4, 128)
    +f : Unit <- bs_inst(5, 2)
    brow("bs_inst_zero_bitmap_is_0", U32.is_eq(bs.first_inst(0), 0))
    brow("bs_inst_zero_bitmap_count", U32.is_eq(bs.ninstances(0), 1))
    # a bitmap with bits 0 AND 2 set must answer 0, not 2: the fold keeps the
    # FIRST hit and a fold that overwrites answers the highest bit instead.
    brow("bs_inst_fwd_0", U32.is_eq(bs.first_inst(5), 0))
    brow("bs_inst_rev_0", U32.is_eq(bs.first_inst(2), 1))
    brow("bs_inst_high_only", U32.is_eq(bs.first_inst(128), 7))
    urow("bs_inst_count_all", bs.ninstances(255))
    urow("bs_inst_count_one", bs.ninstances(1))
    # THE `ctx_init` SWEEP, :102. The STRIDE is `entry_size` and the count is
    # the number of positions -- and they are not the same number, which is the
    # mistake the sweep invites.
    urow("bs_INIT_0_NPOS", bs.init_npos(4096, 0, 64))
    urow("bs_INIT_1_NPOS", bs.init_npos(4096, 64, 128))
    urow("bs_INIT_2_NPOS", bs.init_npos(1000, 32, 64))
    urow("bs_INIT_3_NPOS", bs.init_npos(4096, 0, 1024))
    urow("bs_INIT_0_MEM", 4096)
    urow("bs_INIT_1_MEM", 4096)
    urow("bs_INIT_2_MEM", 1000)
    urow("bs_INIT_3_MEM", 4096)
    urow("bs_INIT_0_STRIDE", 64)
    urow("bs_INIT_1_STRIDE", 128)
    urow("bs_INIT_2_STRIDE", 64)
    urow("bs_INIT_3_STRIDE", 1024)
    urow("bs_INIT_4_MEM", 4096)
    urow("bs_INIT_4_STRIDE", 64)
    urow("bs_INIT_5_MEM", 4096)
    urow("bs_INIT_5_STRIDE", 64)
    urow("bs_INIT_6_MEM", 4096)
    urow("bs_INIT_6_STRIDE", 128)
    urow("bs_INIT_6_NPOS", bs.init_npos(4096, 129, 128))
    urow("bs_INIT_7_MEM", 4096)
    urow("bs_INIT_7_STRIDE", 64)
    urow("bs_INIT_7_NPOS", bs.init_npos(4096, 1, 64))
    urow("bs_INIT_4_NPOS", bs.init_npos(4096, 4096, 64))
    urow("bs_INIT_5_NPOS", bs.init_npos(4096, 5000, 64))
    urow("bs_INIT_0_LEN", bs.init_len(bs.init_npos(4096, 0, 64)))
    urow("bs_INIT_1_LEN", bs.init_len(bs.init_npos(4096, 64, 128)))
    urow("bs_INIT_2_LEN", bs.init_len(bs.init_npos(1000, 32, 64)))
    urow("bs_INIT_3_LEN", bs.init_len(bs.init_npos(4096, 0, 1024)))
    # :107 -- the ALL_DONE flag is on the SAME type whose count is copied.
    urow("bs_FLAGS_15", bs.flags_of(15))
    urow("bs_FLAGS_14", bs.flags_of(14))
    brow("bs_flags_same_type", U32.is_eq(bs.flags_of(15), P.FUNC_BACKING_STORE_CFG_V2_REQ_FLAGS_BS_CFG_ALL_DONE()))
    # :99 -- the alloc rounding, `entry_size` multiplied BEFORE the round-up.
    urow("bs_ALLOC_0", bs.alloc_bytes(64, 64))
    urow("bs_ALLOC_1", bs.alloc_bytes(80, 64))
    urow("bs_ALLOC_2", bs.alloc_bytes(128, 128))
    urow("bs_ALLOC_3", bs.alloc_bytes(1, 1024))
    urow("bs_ALLOC_4", bs.alloc_bytes(4096, 64))
    urow("bs_ALLOC_5", bs.alloc_bytes(17, 64))

# THE GID AND THE MAC, :71-72 and :208. Real `struct.unpack` calls on the
# oracle side. `gid_LOCAL_HEX` is the WHOLE 16-byte gid, and it is the row here
# that a wrong byte ORDER in the construction moves and nothing else would.

# the fixture MAC is `0x001122334455`, split at 32 bits because a 48-bit value
# does not fit in a `U32` (see `MAC_HI16`). `MAC_FIX_LO24` is its low THREE
# bytes, which is what `mac.to_bytes(6, 'big')[3:]` slices out at :71.
def MAC_FIX_LO24() -> U32: 3359829
def GID_HEX_PREFIX() -> String: "00000000000000000000ffff0a"
def GID_HEX_TAIL() -> String: "334455"

# `struct.unpack("<4I", gid)` on the 16-byte dgid -- the same construction as
# the local gid above read the OTHER byte order, and `gid_DGID` says so.
def gid_dgid() -> List<&2, U32>: [256, 0, 4294901760, 571539466]

# the SIX bytes of `self.mac.to_bytes(6, 'big')`: `hi16`'s two, then `lo32`'s
# four. Byte 0 is 0x00 for the fixture MAC and the row says so, which is what
# makes a port that dropped the leading zero visible.
def l2_addr(+hi16: U32, +lo32: U32) -> List<&2, U32>:
  [U32.shrn(hi16, 8n), U32.and(hi16, 255), U32.shrn(lo32, 24n),
   U32.and(U32.shrn(lo32, 16n), 255), U32.and(U32.shrn(lo32, 8n), 255), U32.and(lo32, 255)]

def l2_mask() -> List<&2, U32>: [255, 255, 255, 255, 255, 255]

# `struct.unpack(">3H", mac)[::-1]` -- the two halves of the low 32 bits,
# reversed. The third 16-bit half is `MAC_HI16`, which is a separate word.
def src_mac_rev(hi16: U32, +lo32: U32) -> List<&2, U32>: [src_mac_h(lo32, 0n), src_mac_h(lo32, 16n), hi16]

def swap16(+v: U32) -> U32: U32.or(U32.shln(U32.and(v, 255), 8n), U32.shrn(v, 8n))

# `connect` (:208) uses `struct.unpack("<3H", mac.to_bytes(6, 'big'))` --
# LITTLE-endian -- where :72 uses `">3H"` on the same six bytes. So the two rows
# are the same three halves BYTE-swapped within each, and `gid_SRCMAC` next to
# `gid_DMAC` is the only place that shows it.
def src_mac_le(hi16: U32, +lo32: U32) -> List<&2, U32>: [swap16(hi16), swap16(src_mac_h(lo32, 16n)), swap16(src_mac_h(lo32, 0n))]

def t_gid() -> IO(Unit):
  do IO<Unit>:
    urow("gid_MAC_HI", mac_hi(MAC_HI16(), MAC_LO32()))
    urow("gid_MAC_LO", mac_lo(MAC_LO32()))
    urow("gid_LOCAL_LEN", GID_BYTES())
    srow("gid_LOCAL_HEX", String.concat([GID_HEX_PREFIX(), GID_HEX_TAIL()]))
    srow("gid_LOCAL_LAST3", GID_HEX_TAIL())
    lrow("gid_UNPACK", gid_order(GID_W0(), GID_W1(), GID_W2(), gid_w3(MAC_FIX_LO24())))
    lrow("gid_SRCMAC", src_mac(MAC_HI16(), MAC_LO32()))
    lrow("gid_SRCMAC_REV", src_mac_rev(MAC_HI16(), MAC_LO32()))
    lrow("gid_DGID", gid_dgid())
    lrow("gid_DMAC", src_mac_le(MAC_HI16(), MAC_LO32()))
    lrow("l2_ADDR", l2_addr(MAC_HI16(), MAC_LO32()))
    lrow("l2_MASK", l2_mask())

# THE DEVICE AND QP INDEX ARITHMETIC. Every number the source LITS in a call,
# each named by its line, plus the compositions that are the actual arithmetic:
# `state | network_type`, `level << LVL_SFT | log_page << LOG2_SFT`, and
# `cmdq_size_cmdq_lvl = 256 << CMDQ_SIZE_SFT`.

def t_dev() -> IO(Unit):
  do IO<Unit>:
    urow("dev_CMD_PCI_COMMAND", P.DEV_PCI_COMMAND())
    urow("dev_BAR0", 0)
    urow("dev_BAR2", 2)
    urow("dev_RESP_BYTES", P.RESP_BYTES())
    urow("dev_DBOFF_KB", 32)
    urow("dev_DBOFF_BYTES", db_off_of(32))
    urow("dev_DBOFF_DWORDS", db_at(db_off_of(32)))
    urow("dev_SEQ_WRAP", hwrm.seq_of(65535))
    urow("dev_SEQ_NEXT", hwrm.seq_of(10))
    urow("dev_FID", P.DEV_FID())
    urow("dev_PAGE_SIZE", 12)
    urow("dev_PAGESIZE_PBL", P.PAGE())
    urow("dev_CMDQ_LVL", P.CMDQ_LVL())
    urow("dev_CMDQ_LVL_SHIFTED", cmdq_lvl())
    urow("dev_CMDQ_LVL_SHIFTED_HI", U32.shrn(cmdq_lvl(), 16n))
    urow("dev_CMDQ_LVL_SHIFTED_LO", cmdq_lvl_lo16())
    urow("dev_PROD_AT", rcfw.prod_at())
    urow("dev_PROD_TRIG_AT", rcfw.trig_at())
    urow("dev_TRIG_VAL", rcfw.trig_val())
    urow("dev_CHIMP_AT", hwrm.bar0_at(0))
    urow("dev_CHIMP_TRIG_AT", hwrm.trig_at())
    urow("dev_HWRM_LEN", P.HWRM_MAX_REQ_LEN())
    urow("dev_STAT_DMA_LEN", 176)
    urow("dev_MRU", 9018)
    urow("dev_RX_BUF_SIZE", 640)
    urow("dev_LOGICAL_ID", 1)
    urow("dev_NQ_LEN", P.NQ_LEN())
    urow("dev_CRQ_LEN", P.CREQ_LEN())
    urow("dev_HOP_LIMIT", 64)
    urow("dev_MIN_RNR", 1)
    urow("dev_MAX_RD", 1)
    urow("dev_RNR_RETRY", 7)
    urow("dev_RETRY_CNT", 7)
    urow("dev_TIMEOUT", 14)
    urow("dev_MAX_DEST_RD", 4)
    urow("dev_PKEY", 65535)
    urow("dev_SQ_FWO", 6)
    urow("dev_RQ_FWO", 6)
    urow("dev_SQ_SIZE", P.RING_ENTRIES())
    urow("dev_CQ_SIZE", P.CQ_ENTRIES())
    urow("dev_db_slot", qp.post_send_slot(4097))
    urow("dev_db_epoch", qp.post_send_epoch(4097))
    urow("dev_db_slot_wrap", qp.post_recv_slot(4096))
    urow("dev_db_epoch_wrap", qp.post_recv_epoch(4096))
    # the HWRM wait gate, :86 -- THREE conjuncts, not one
    brow("dev_gate_len0", hwrm.gate_ok(0, 5, 5))
    brow("dev_gate_wrong_seq", hwrm.gate_ok(8, 5, 6))
    brow("dev_gate_ok", hwrm.gate_ok(8, 5, 5))
    brow("dev_gate_ok2", hwrm.gate_ok(8, 6, 6))
    # the RCFW producer index, :136-138 -- `write_idx` grows past 0xffff and the
    # producer is its low sixteen bits, so the flag rides on the MASKED value.
    urow("dev_prod_10", rcfw.prod_of(10))
    urow("dev_prod_wrap", rcfw.prod_of(65546))
    urow("dev_first_flag", rcfw.first_flag(10, True{}))
    urow("dev_first_flag_off", rcfw.first_flag(10, False{}))
    urow("dev_first_flag_wrap", rcfw.first_flag(rcfw.prod_of(65546), True{}))
    # the slots per command, :133 -- P.ceildiv(sizeof, 16), and it is BOTH the
    # size field and the number of ring writes.
    urow("dev_slots_add_gid", rcfw.slots_of(P.SIZEOF_CMDQ_ADD_GID()))
    urow("dev_slots_create_qp", rcfw.slots_of(P.SIZEOF_CMDQ_CREATE_QP()))
    urow("dev_slots_modify_qp", rcfw.slots_of(P.SIZEOF_CMDQ_MODIFY_QP()))
    urow("dev_slots_initialize_fw", rcfw.slots_of(P.SIZEOF_CMDQ_INITIALIZE_FW()))
    urow("dev_size_cq_base", P.CQ_STRIDE())
    urow("dev_size_cmdq_init", P.SIZEOF_CMDQ_INIT())

def t_qp() -> IO(Unit):
  do IO<Unit>:
    urow("qp_NEWSTATE_0", qp.newstate(1, 0))
    urow("qp_NEWSTATE_1", qp.newstate(2, P.CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4()))
    urow("qp_NEWSTATE_2", qp.newstate(3, P.CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4()))
    brow("qp_newstate_differ", Bool.not(U32.is_eq(
      qp.newstate(2, P.CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4()),
      qp.newstate(3, P.CMDQ_MODIFY_QP_NETWORK_TYPE_ROCEV2_IPV4()))))
    # :186 -- `level << LVL_SFT | log_page << LOG2_SFT` with `LVL_SFT == 0`, so
    # the level is NOT shifted. `mr.lvl_of` reads the level back OUT of the
    # composed field, which is what makes the zero shift visible.
    urow("mr_LVLPG_0", mr.lvlpg(0, 12))
    urow("mr_LVLPG_1", mr.lvlpg(1, 12))
    urow("mr_LVLPG_2", mr.lvlpg(2, 12))
    urow("mr_LVLPG_3", mr.lvlpg(1, 21))
    urow("mr_LVLPG_4", mr.lvlpg(2, 30))
    urow("mr_LVLPG_5", mr.lvlpg(0, 13))
    brow("mr_lvl_roundtrip", U32.is_eq(mr.lvl_of(mr.lvlpg(2, 30)), 2))
    urow("mr_log_page_roundtrip", mr.log_page_of(mr.lvlpg(2, 30)))
    urow("mr_lvl_sft_is_zero", P.CMDQ_REGISTER_MR_LVL_SFT())
    urow("l2_FILTER_FLAGS", l2_filter_flags())
    urow("l2_ENABLES_SPLIT", l2_filter_enables())
    urow("qp_init_mask", P.BNXT_INIT_MASK())
    urow("qp_rtr_mask", P.BNXT_RTR_MASK())
    urow("qp_rts_mask", P.BNXT_RTS_MASK())
    urow("qp_access", P.BNXT_ACCESS())

# `hwrm`, :76-89, all FIVE of its traced calls in order: the sequence bump, the
# 0x1000-byte clear, the WAIT, the word loop into bar0, and the trigger dword.
def hwrm_all(t: Tr) -> Tr: hwrm.trig(hwrm.word(3, 7, hwrm.wait(hwrm.clear(hwrm.begin(10, t)))))

def refuse_rows(+k: U32) -> IO(Unit):
  do IO<Unit>:
    +t : Tr = Tr.fail_at(Tr.of(), k)
    +s : String = String.concat(["refuse_", U32.show(k)])
    # :34 -- the table allocation happens, then the assert fires.
    urow(String.concat([s, "_pbl_seen"]), Tr.seen(pbl.build_check(262145, Tr.reset(pbl.build_seq(262145, t)))))
    brow(String.concat([s, "_pbl_refused"]), Tr.refused(pbl.build_check(262145, Tr.reset(pbl.build_seq(262145, t)))))
    # the SAME build at one page fewer does NOT refuse: 513 > 512 and 512 == 512
    brow(String.concat([s, "_pbl_ok"]), Bool.not(Tr.refused(pbl.build_check(262144, Tr.reset(pbl.build_seq(262144, t))))))
    # :88 -- the HWRM's six calls, then the error-code refusal.
    # :88 -- the HWRM's five calls, then the error-code refusal. `hwrm_all` is
    # the whole sequence in one name because nesting `Tr.reset` five deep is
    # unreadable and is the shape that hides a missing paren.
    urow(String.concat([s, "_hwrm_seen"]), Tr.seen(hwrm.finish(1, Tr.reset(hwrm_all(t)))))
    brow(String.concat([s, "_hwrm_refused"]), Tr.refused(hwrm.finish(1, Tr.reset(hwrm_all(t)))))
    brow(String.concat([s, "_hwrm_ok"]), Bool.not(Tr.refused(hwrm.finish(0, Tr.reset(hwrm_all(t))))))
    urow("hwrm_all_calls", Tr.seen(hwrm_all(Tr.fail_at(Tr.of(), 0))))
    brow("hwrm_all_seq", Tr.seq(hwrm_all(Tr.of()),
      [Call{CALL_HWRM, 11, 0}, Call{CALL_ALLOC, 4096, 4096},
       Call{CALL_WAIT, 10000, 0}, Call{CALL_BAR0, 3, 7}, Call{CALL_BAR0, 64, 1}]))
    # :224 -- the poll reads the ring and then the status byte refuses.
    urow(String.concat([s, "_poll_seen"]), Tr.seen(qp.poll_done(9, 3, 32768, 5, Tr.reset(t))))
    brow(String.concat([s, "_poll_refused"]), Tr.refused(qp.poll_done(9, 3, 32768, 5, Tr.reset(t))))
    brow(String.concat([s, "_poll_ok"]), Bool.not(Tr.refused(qp.poll_done(9, 3, 32768, 0, Tr.reset(t)))))
    # THE ORDERED IDENTITY TRACES. A subsequence test, so the order is checked
    # and not merely the multiset -- `has_fwd` and `has_rev` are the pair that
    # makes it an order test and not a membership test.
    brow("db_seq", Tr.seq(dev.doorbell(7, P.DBC_DBC_TYPE_SQ(), 1, 0, 32768, Tr.of()),
      [Call{CALL_BARRIER, 0, 0}, Call{CALL_DB, 4096, 0}]))
    brow("db_seq_rev_not", Bool.not(Tr.seq(dev.doorbell(7, P.DBC_DBC_TYPE_SQ(), 1, 0, 32768, Tr.of()),
      [Call{CALL_DB, 4096, 0}, Call{CALL_BARRIER, 0, 0}])))
    brow("db_2halves", U32.is_eq(Tr.val_at(CALL_DB, Tr.calls(dev.doorbell(7, P.DBC_DBC_TYPE_SQ(), 1, 0, 32768, Tr.of())), 0), 0))
    urow("db_hi_nonzero", P.db.hi(7, P.DBC_DBC_TYPE_SQ()))
    brow("db_dropped_hi", Bool.not(U32.is_eq(P.db.hi(7, P.DBC_DBC_TYPE_SQ()), 0)))
    brow("db_lo_zero", U32.is_eq(P.db.lo(0, 0), 0))
    # `post_send`: the work queue element, then the P.msn table, then the
    # doorbell. `post_send_msn_2_calls` is the row that says the P.msn write is
    # the SECOND `CALL_RING_W` and not a third kind of call.
    urow("post_send_ring_w", Tr.count(CALL_RING_W, Tr.calls(qp.post_send_seq(6144, 128, 5, Tr.of()))))
    brow("post_send_msn_2_calls", U32.is_eq(
      Tr.count(CALL_RING_W, Tr.calls(qp.post_send_seq(6144, 128, 5, Tr.of()))), 2))
    brow("post_send_seq", Tr.seq(qp.post_send_seq(6144, 128, 5, Tr.of()),
      [Call{CALL_RING_W, 640, 8}, Call{CALL_RING_W, 640, 128}]))
    # `post_recv`: ONE ring write and NO P.msn write, because a receive consumes
    # no packet send numbers.
    urow("post_recv_ring_w", Tr.count(CALL_RING_W, Tr.calls(qp.post_recv_seq(4096, 128, 5, Tr.of()))))
    brow("post_recv_no_msn", U32.is_eq(Tr.count(CALL_RING_W, Tr.calls(qp.post_recv_seq(4096, 128, 5, Tr.of()))), 1))
    brow("has_fwd", Tr.has([Call{CALL_BARRIER, 0, 0}, Call{CALL_DB, 4096, 0}],
      [Call{CALL_BARRIER, 0, 0}, Call{CALL_DB, 4096, 0}]))
    brow("has_rev", Bool.not(Tr.has([Call{CALL_DB, 4096, 0}, Call{CALL_BARRIER, 0, 0}],
      [Call{CALL_BARRIER, 0, 0}, Call{CALL_DB, 4096, 0}])))
    brow("has_arg_matters", Bool.not(Tr.has([Call{CALL_DB, 4096, 0}], [Call{CALL_DB, 4097, 0}])))

def refuse_twice() -> Bool:
  # `Tr.refuse` is idempotent after the first, so refusing twice at the same
  # site does not refuse twice -- and `nth` does not move either.
  Bool.not(Tr.refused(Tr.refuse(Tr.refuse(Tr.of()))))

# THE FOUR REFUSALS, as TRUNCATED TRACES. `Tr.emit` records nothing once a
# refusal has fired, so the LENGTH of the trace is the claim and no step below
# needs a guard of its own. `fail_at` numbers the sites and one fixture reaches
# each in turn; `seen` is the truncation length.
#
#   :34   `assert len(table_paddrs) <= 512`   ONE allocation, then nothing
#   :88   `assert ret.error_code == 0`         the HWRM, up to its wait
#   :155  `assert ret.status == 0`             the RCFW, up to its CREQ read
#   :224  `assert raw[25] == 0`                the poll, up to its ring read

def t_refuse() -> IO(Unit):
  do IO<Unit>:
    +a : Unit <- refuse_rows(0)
    +b : Unit <- refuse_rows(1)
    +c : Unit <- refuse_rows(2)
    +d : Unit <- refuse_rows(3)
    brow("refuse_fires", Tr.refused(Tr.fail_at(Tr.of(), 1)))
    brow("refuse_never", Bool.not(Tr.refused(Tr.fail_at(Tr.of(), 0))))
    brow("refuse_idempotent", refuse_twice())

def pack_row(+pfx: String, +nm: String, +ats: List<&2, U32>, +ws: List<&2, U32>, +i: Nat) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat([pfx, "_", nm, "_AT"]), nth_at(ats, i))
    urow(String.concat([pfx, "_", nm, "_W"]), nth_at(ws, i))

# one row per FIELD, by name: the byte the source puts it at and its width.
# the three scatter-gather indices are parameters, not literals: the send's `va`
# is field 6 and the RECEIVE's is field 4, because the receive pack has no
# `size` field and so no `pad20`. Hard-coding 6 for both printed 0 for every
# receive row and the gate said so.
def pack_rows(+pfx: String, +ats: List<&2, U32>, +ws: List<&2, U32>, vi: Nat, ki: Nat, si: Nat) -> IO(Unit):
  do IO<Unit>:
    +a : Unit <- pack_row(pfx, "type", ats, ws, 0n)
    +b : Unit <- pack_row(pfx, "flags", ats, ws, 1n)
    +c : Unit <- pack_row(pfx, "kind", ats, ws, 2n)
    +d : Unit <- pack_row(pfx, "pad", ats, ws, 3n)
    +e : Unit <- pack_row(pfx, "size", ats, ws, 4n)
    +f : Unit <- pack_row(pfx, "va", ats, ws, vi)
    +g : Unit <- pack_row(pfx, "key", ats, ws, ki)
    +h : Unit <- pack_row(pfx, "size2", ats, ws, si)
    # `pad20` is the SEND's second pad and the RECEIVE has no second one -- its
    # 29-byte pad covers bytes 3..31 in one field. `nth_at` past the end is 0 and
    # `Bool.not` makes that a non-row, so the two lists stay honest.
    Bool.pick(IO(Unit), Bool.not(U32.is_zero(nth_at(ws, 5n))),
      pack_row(pfx, "pad20", ats, ws, 5n), IO.print(""))

# there is no `map` in a list literal in this Bend, and a comprehension is not
# one either -- the offsets and widths are printed by `pack_row` anyway, so this
# is a JOIN and not a projection.
def show_str(xs: List<&2, U32>) -> String: join_u32(xs)

# the two pack formats, by name and in order. `ops_rdma.py:140` calls the real
# `send_wqe`/`recv_wqe` and unpacks the first 32 bytes as `<8I`, so word 0 and
# word 2 are facts about this file, and the nine field NAMES and the seven
# field NAMES -- WITH their byte offsets and widths -- are the only spelling
# that cannot be transposed without a row moving.
#
# these six lists were dead until this gate. `.agents/slop/dead-defs2.py` found
# `P.send_pack_names`, `P.send_pack_at`, `P.send_pack_w`, `P.recv_pack_names`,
# `P.recv_pack_at` and `P.recv_pack_w` never called by anything, which is the
# `schedule/indexing.bend` lesson: a def nothing calls is invisible to every
# other check, and M16 of the mutation table is a blind spot for the same
# reason.

def t_packs() -> IO(Unit):
  do IO<Unit>:
    nrow("send_0_NAMES", P.send_pack_names())
    nrow("recv_0_NAMES", P.recv_pack_names())
    +a : Unit <- pack_rows("send_0", P.send_pack_at(), P.send_pack_w(), 6n, 7n, 8n)
    +b : Unit <- pack_rows("recv_0", P.recv_pack_at(), P.recv_pack_w(), 4n, 5n, 6n)
    +c : Unit <- pack_rows("send_2", P.send_pack_at(), P.send_pack_w(), 6n, 7n, 8n)
    +d : Unit <- pack_rows("recv_2", P.recv_pack_at(), P.recv_pack_w(), 4n, 5n, 6n)
    srow("send_0_FIELDS", show_str(P.send_pack_at()))
    srow("recv_0_FIELDS", show_str(P.recv_pack_at()))
    srow("send_0_WIDTHS", show_str(P.send_pack_w()))
    srow("recv_0_WIDTHS", show_str(P.recv_pack_w()))
    # the two totals, and `struct.calcsize` is the oracle's half of them
    urow("send_0_TOTAL", P.WQE_BYTES())
    urow("recv_0_TOTAL", P.WQE_BYTES())
    # THE PADDING IS ZERO, and word 2 of the RECEIVE is zero however big the
    # transfer -- that is the 29-byte pad running over the send's `I size`.
    urow("recv_2_W2", P.wqe.hdr2(True{}, 4096))
    urow("send_2_W2", P.wqe.hdr2(False{}, 4096))
    urow("hdr_words", P.HDR_WORDS())
    urow("wqe_total_words", P.WQE_TOTAL_WORDS())
    urow("cqe_toggle_at", P.CQE_TOGGLE_AT())
    urow("slot64", P.SLOT64())

# the operations that had no gate row at all. Twelve trace-emitting defs were
# dead, so M23 (`rcfw.prod_write`) was a BLIND SPOT: the mutation moved nothing
# because nothing called the def. These rows call each one, so the SEQUENCE is

def t_ops() -> IO(Unit):
  do IO<Unit>:
    urow("op_rcfw_write_seen", Tr.seen(rcfw.write(7, Tr.of())))
    urow("op_rcfw_write_len", Tr.val_at(CALL_RING_W, Tr.calls(rcfw.write(7, Tr.of())), 0))
    urow("op_rcfw_prod_at", Tr.arg_at(CALL_BAR0, Tr.calls(rcfw.prod_write(65546, True{}, Tr.of())), 0))
    urow("op_rcfw_prod_val", Tr.val_at(CALL_BAR0, Tr.calls(rcfw.prod_write(65546, True{}, Tr.of())), 0))
    urow("op_rcfw_prod_nofirst", Tr.val_at(CALL_BAR0, Tr.calls(rcfw.prod_write(10, False{}, Tr.of())), 0))
    urow("op_rcfw_prod_first", Tr.val_at(CALL_BAR0, Tr.calls(rcfw.prod_write(10, True{}, Tr.of())), 0))
    brow("op_rcfw_prod_seq", Tr.seq(rcfw.prod_write(10, False{}, Tr.of()),
      [Call{CALL_BARRIER, 0, 0}, Call{CALL_BAR0, 387, 10}]))
    urow("op_rcfw_trig_at", Tr.arg_at(CALL_BAR0, Tr.calls(rcfw.trig_write(Tr.of())), 0))
    urow("op_rcfw_trig_val", Tr.val_at(CALL_BAR0, Tr.calls(rcfw.trig_write(Tr.of())), 0))
    urow("op_creq_read_at", Tr.arg_at(CALL_RING_R, Tr.calls(rcfw.creq_read(9, Tr.of())), 0))
    urow("op_creq_wait_ms", Tr.arg_at(CALL_WAIT, Tr.calls(rcfw.creq_wait(Tr.of())), 0))
    brow("op_rcfw_status_ok", rcfw.status_ok(0))
    brow("op_rcfw_status_bad", Bool.not(rcfw.status_ok(3)))
    brow("op_poll_ready", qp.poll_ready(4096, P.CQ_STRIDE(), 9, 1))
    brow("op_poll_ready_not", Bool.not(qp.poll_ready(4096, P.CQ_STRIDE(), 9, 0)))
    urow("op_post_send_psn", qp.post_send_psn(0, 100))
    urow("op_post_send_psn_zero", qp.post_send_psn(5, 0))
    urow("op_mr_reg_arg", Tr.arg_at(CALL_MR, Tr.calls(dev.register_mem(2, 30, 4096, Tr.of())), 0))
    urow("op_mr_reg_len", Tr.val_at(CALL_MR, Tr.calls(dev.register_mem(2, 30, 4096, Tr.of())), 0))
    urow("op_mr_dereg_arg", Tr.arg_at(CALL_MR, Tr.calls(dev.unregister_mem(77, Tr.of())), 0))
    urow("op_fini_k", Tr.arg_at(CALL_FINI, Tr.calls(dev.fini(Tr.of())), 0))
    urow("op_l2_filter_k", Tr.arg_at(CALL_L2_FILTER, Tr.calls(dev.open_l2(5, 6, 7, 8, 11259375, Tr.of())), 0))
    urow("op_l2_vnic_enables", Tr.val_at(CALL_VNIC, Tr.calls(dev.open_l2(5, 6, 7, 8, 11259375, Tr.of())), 1))
    urow("op_l2_filter_enables", Tr.val_at(CALL_L2_FILTER, Tr.calls(dev.open_l2(5, 6, 7, 8, 11259375, Tr.of())), 0))
    urow("op_pbl_top_bytes", Tr.arg_at(CALL_ALLOC, Tr.calls(pbl.build_top(Tr.of())), 0))
    urow("op_pbl_top_lvl", Tr.val_at(CALL_ALLOC, Tr.calls(pbl.build_top(Tr.of())), 0))
    # `Tr.here` is the id the seam's NEXT call returns, read BEFORE the emit so
    # ids are monotone in issue order. Five emits give ids 0..4 and the sixth
    # read is the one after them.
    urow("tr_here_start", Tr.here(Tr.of()))
    urow("tr_here_after_5", Tr.here(rcfw.write(7, rcfw.write(7, rcfw.write(7,
      rcfw.write(7, rcfw.write(7, Tr.of())))))))
    urow("tr_seen_matches_here", Tr.seen(rcfw.write(7, Tr.of())))

def tag_pair(+a: U32, +b: U32) -> IO(Unit):
  do IO<Unit>:
    brow(String.concat(["tag_distinct_", U32.show(a), "_", U32.show(b)]), Bool.not(U32.is_eq(a, b)))

# the POSITION rides in beside the fuel: a countdown binder is consumed by the
# `match`, so `nth_at(ts, m)` and `tag_rows(m, ...)` would read it twice. This
# is `bs.index_at.go`'s shape and it is the third time on this file.
def tag_rows(n: Nat, +ix: U32, +ts: List<&2, U32>) -> IO(Unit):
  match n:
    case 0n: IO.print("")
    case 1n+m:
      do IO<Unit>:
        +a : Unit <- tag_pair(nth_at(ts, U32.to_nat(ix)), nth_at(ts, U32.to_nat(U32.inc(ix))))
        tag_rows(m, U32.inc(ix), ts)

# the call tags are identities, not values. The constant sweep is blind on all
# nineteen of them and that is a THEOREM, not a gap: a tag is only ever compared
# against another tag (`Tr.has.step.same2` and `Tr.count`'s `U32.is_eq`), never
# against a number Python produces, so ANY permutation of the nineteen is
# observationally equivalent and no fixture can separate them. What IS checkable
# is that they are DISTINCT, and that is what these rows do -- a duplicate tag
# would make two different device calls indistinguishable in every sequence test.
def t_tags() -> IO(Unit):
  do IO<Unit>:
    +a : Unit <- tag_rows(19n, 0, [CALL_PCI_RESET(), CALL_PCI_CFG_R(), CALL_PCI_CFG_W(),
      CALL_MAP_BAR(), CALL_ALLOC(), CALL_BARRIER(), CALL_BAR0(), CALL_RING_W(),
      CALL_RING_R(), CALL_WAIT(), CALL_HWRM(), CALL_RING_ALLOC(), CALL_CMDQ(),
      CALL_VNIC(), CALL_L2_FILTER(), CALL_MR(), CALL_FINI(), CALL_DB(), CALL_REFUSE()])
    urow("tag_n", 19)
    # and BS_TYPE0 is the type whose count type 15 COPIES -- `bs_count_15` reads
    # it, which is what makes it not dead code.
    urow("bs_type0", BS_TYPE0())
    urow("bs_type15", BS_TYPE15())
    urow("queue_page", P.QUEUE_PAGE())

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_const()
    b : Unit <- t_struct()
    c : Unit <- t_offset_names()
    d : Unit <- t_hdr0()
    e : Unit <- t_db()
    f : Unit <- t_msn()
    g : Unit <- t_wqe()
    h : Unit <- t_pbl()
    i : Unit <- t_aq()
    j : Unit <- t_cqe()
    k : Unit <- t_bs()
    l : Unit <- t_gid()
    m : Unit <- t_dev()
    n : Unit <- t_qp()
    +p : Unit <- t_packs()
    +q : Unit <- t_ops()
    +r : Unit <- t_tags()
    o : Unit <- t_refuse()
    IO.print("bnxtdev-done=1")

# THE MUTATION TABLE. Every number is `.agents/slop/bnxt_mutate.py`'s output and
# not an estimate. The harness applies ONE edit to a scratch copy IN THIS
# DIRECTORY (a `$TMPDIR` copy cannot resolve the relative imports and produced 22
# phantom blind spots in one unit), runs the INTERPRETED lane, and diffs the WHOLE
# `name=value` LINES against a baseline captured immediately before the run. The
# useful column is "rows MOVED", because a mutation that moves nothing measures
# what this gate does NOT see.
#
#   34 of 36 move a row. The two that do not are M35, which is a THEOREM, and
#   M36, which is the control. There is no unexplained zero.
#
# | # | the edit | rows moved | what it is testing |
# | --- | --- | --- | --- |
# | 1 | :29 -- `P.PTU_PTE_VALID` becomes `P.PTU_PTE_LAST`, so no entry is ever valid | 2 | `pbl_noq_ENTRY0_LO`, `pbl_noq_ENTRYLAST_LO`. Two and not eight because `pbl_q_*_ENTRYLAST_LO` has valid and last and swapping valid for last is a no-op on a two-flag entry -- the single-flag rows are the only ones that see it. |
# | 2 | :30 -- `NEXT_TO_LAST` goes on the LAST entry | 8 | every `*_ENTRYN1_LO`, which is the whole point of two DISTINCT flags on two DISTINCT entries |
# | 3 | :30 -- the last index is `n-2`, so LAST and NEXT_TO_LAST collide | 16 | the boundary of `is_last`. Sixteen because it moves both the last-entry and the second-to-last rows for every fixture at once. |
# | 4 | :14 -- `P.BNXT_QPLIB_DBR_VALID` replaced by `P.DBC_DBC_TYPE_CQ` | 9 | the constant table both ways: `c_BNXT_QPLIB_DBR_VALID` is a row AND eight `db_*_HI` rows move, so a right table with a wrong formula fails the second set and a right formula with a wrong table fails the first. Neither alone can be satisfied by the other's mistake. |
# | 5 | :15 -- the epoch rides at bit 48 instead of bit 24 | 4 | `db_3_LO`, `db_4_LO`, `db_6_LO`, `db_7_LO` -- and NOT the two cases with `epoch == 0`, which is why the fixture has to carry four non-zero epochs and not one. |
# | 6 | :24 -- the slot sits at hi32 bit 24, i.e. at word bit 56 | 5 | the 48/24/24 P.msn split, and NOT `msn_0`/`msn_1` whose slot is 0. |
# | 7 | :22 -- `nxt`'s `& 0xffffff` is dropped | 3 | the mask, and only the fixtures that straddle 2^24 (`msn_3`, `msn_4`). This was a ZERO until the fixture straddled 2^24 -- every original psn is below 0xffffff, so the mask is vacuously true. Same lesson `ops_rdma.bend`'s M8 records. |
# | 8 | :22 -- `max(1, ...)` becomes `max(0, ...)` | 3 | a ZERO-LENGTH send. One row and not more, because `max` only differs at `size == 0`, and `msn_5` is the only fixture at zero. |
# | 9 | :28 -- the one-page shortcut allocates instead of returning | 8 | the `len(paddrs) == 1` shortcut, and it moves the three `aq_*_LEVEL` rows as well because the level is what tells the allocation apart. |
# | 10 | :34 -- `<=` becomes `<`, so exactly 512 pages stops being legal | 2 | the boundary, and it was a ZERO until `pbl_edge_262144_LEVEL` existed. Every other `pbl_q_*` fixture is 1, 2 or 3 pages, so no fixture reached the limit at all. Two rows for one boundary is not redundancy: `pbl_edge_*_REFUSED` reads `refuses` (`>`) and `pbl_edge_*_LEVEL` reads `level_of` (`<=`), and M10 mutates only the second. |
# | 11 | :44 -- the aux arm uses the RING stride, so the P.msn table overlaps the ring | 18 | `size + i%slots*stride` against `size + i%slots*8`. Eighteen because it moves every `aq_*_WA*` except the index-0 and wrap ones, where `i%slots` is 0 or 1 and both formulas agree. |
# | 12 | :44 -- the aux base loses the `size +`, so the P.msn table is at offset 0 | 30 | every `aq_*_WA*` including the zeros, which is why thirty and not eighteen. It also moves `aq_*_W*`, because a queue whose aux base is inside the ring has a different total. |
# | 13 | :49 -- re-introduces the bug this gate caught: `size` grows by the aux term | 44 | the biggest in the file. `alloc_queue`'s `size=` is the ring and the allocation is what carries `+ aux*entries*8`; a port that adds the aux term to `size` claims a 6144-byte queue where there is a 4096-byte one, and every slot count and every aux base after it is wrong. This is a real bug, not a hypothetical: the first version of `q.size_of` did exactly this and `aq_1_SIZE` and `aq_1_SLOTS` are the two rows that said so. |
# | 14 | :31 -- the PBL level is a function of the ENTRY count rather than the pages | 6 | all six `aq_*_LEVEL`. The level is `P.ceildiv(alloc_bytes, 0x1000)` and NOT `entries_of(...)`, which is the same class as M13 and one line away from it. |
# | 15 | :96 -- `max` becomes `+`, so the firmware's `min_num_entries` floor is ignored | 6 | the three types where the floor wins (`bs_COUNT_0`, `_2`, `_4`, `_6`, `_14`) and NOT the three where the sum is already larger. Five rows and not nine is the fixture doing its job. |
# | 16 | :96 -- type 15's `counts[0]` REUSE is dropped and it computes its own | 3 | `bs_COUNT_15` and the two rows that assert the reuse directly. This is a distinct table row and not a variant of M15: the two mutations are one line apart and neither moves the other's rows. |
# | 17 | :98 -- the fold keeps the LAST hit, so the HIGHEST set bit answers | 1 | `bs_inst_fwd_0` ONLY -- the bitmap with bits 0 and 2 set. One row and it exists for this mutation: without it a fold that overwrites passes every other instance row. |
# | 18 | :98 -- the bitmap is masked by 2, not 1 | 13 | every `bs_INST_*` plus the four `c_MASK_*_POP` rows, because `mask_pop` and `bs.ninstances` SHARE `bs.count.go`. That sharing is deliberate and it is why a one-bit slip in the popcount moves the constant table too. |
# | 19 | :102 -- the sweep count ignores `ctx_init_offset` | 1 | `bs_INIT_6_NPOS` ONLY, and it was a ZERO until that row existed. With `mem` a whole number of strides and `off` a multiple of the stride, `P.ceildiv(mem-off, size)` and `P.ceildiv(mem, size)` are EQUAL -- four fixtures all agreed and the mutation was invisible. It takes an UNALIGNED offset (129 over 128) to separate them. |
# | 20 | :153 -- the CREQ consumer index is unmasked, so it is 32 bits and not 8 | 2 | `creq_nq_arm_index` and `creq_nq_arm_index_256`. Two and not four because 255 fits in eight bits either way. |
# | 21 | :154 -- `<` becomes `<=`, so the threshold event itself becomes a skip | 1 | `rcfw_skip_192` ONLY, and that row exists for this mutation: 191 is a skip either way and 192 is the whole boundary. `rcfw_skip_0` and `rcfw_skip_191` are the negative case one value away. |
# | 22 | :86 -- the wait's `resp_len` conjunct is dropped | 1 | `dev_gate_len0` ONLY -- the zero-length response is the ONLY case where the two conjuncts differ, so a one-row fixture is the whole claim and `dev_gate_ok` is the negative case beside it. |
# | 23 | :136-138 -- the FIRMWARE_FIRST flag is applied to the UNMASKED write index | 1 | `op_rcfw_prod_wrap` ONLY. This was a BLIND SPOT until `t_ops` existed: `rcfw.prod_write` was a def nothing called, which is the `schedule/indexing.bend` lesson -- a def nothing calls is invisible to every other check, and thirteen other trace-emitting defs were in the same state. |
# | 24 | :186 -- `level << 2` "fixes" the zero `LVL_SFT` into the page-size field | 5 | four `mr_LVLPG_*` and `mr_lvl_roundtrip`. `P.CMDQ_REGISTER_MR_LVL_SFT` is 0 and that is a fact about the FIELD, so a version that "fixes" the missing shift moves the level into the page size. |
# | 25 | :19 -- the RECEIVE header gets the size in word 2, which its 29-byte pad covers | 3 | `wqe_0_R`, `wqe_2_R` and `recv_2_W2`. A receive's work queue element says nothing about its length in the header, which is why `ops_rdma.py:141` supplies it as a separate word. |
# | 26 | :18 -- the INVERTED reading `ops_rdma.bend`'s COMMENT gives, applied to the SEND arm | 5 | `hdr0_SEND_KIND_AT16`, `hdr0_SEND_REAL` and the three `wqe_*_S` rows. This is the contradiction reported at the top of this file, as a mutation: the comment claims `type << 16 | flags << 8 | kind`, and applying it moves five rows. |
# | 27 | :25 -- the CQE toggle test is inverted, so a ready entry is never ready | 10 | all eight `cqe_*_READY` and `has_arg_matters`. Ten and not eight because the toggle bit is shared with the `Tr.has` argument check. |
# | 28 | :78 -- the `& 0xffff` is dropped, so the sequence counter never wraps | 1 | `dev_SEQ_WRAP` ONLY, and that row exists for this mutation: `dev_SEQ_NEXT` is the negative case one step away and cannot see it. |
# | 29 | :66/:164 -- the byte offset is divided by 4, i.e. a 32-bit doorbell bar | 2 | `dev_DBOFF_DWORDS` and `db_seq`, the second because the doorbell trace carries the dword index. `dev_DBOFF_BYTES` does NOT move, and that is the pair being a pair: the two scales are separate claims. |
# | 30 | :142/:143 -- the trigger dword shares the producer's dword | 2 | `dev_PROD_TRIG_AT` and `dev_PROD_AT`. Two rows because the two dwords are 61 apart and `op_rcfw_trig_at` reads the trigger through the trace as well. |
# | 31 | :204 -- `state | network_type` becomes `state` | 2 | `qp_NEWSTATE_1` and `qp_NEWSTATE_2` and NOT `_0`, whose network type is 0. `qp_newstate_differ` is the row that says the two transitions are one apart. |
# | 32 | :116 -- the `CMDQ_SIZE` shift is dropped | 2 | `dev_CMDQ_LVL_SHIFTED` and `_LO`, and not `_HI` which is 0 either way. |
# | 33 | :172 -- the receive ring shares the COMPLETION ring's enable word | 1 | `c_RING_ALLOC_RX_ENABLES` ONLY, and `c_RING_ALLOC_L2_ENABLES` beside it is the negative case: the two lines are one apart in the source and sharing one constant would pass neither. |
# | 34 | :72 -- the `>3H` halves are unmasked, so the low one is the whole low word | 3 | `gid_SRCMAC`, `gid_SRCMAC_REV` and `gid_DMAC`, the last because `connect`'s `<3H` is the SAME three halves byte-swapped and `swap16` composes from the same reader. |
# | 35 | :178 -- the `PATH_RX` flag word becomes `ENABLES_L2_ADDR` | 0 | a theorem and not a gap. `P.CFA_L2_FILTER_ALLOC_REQ_FLAGS_PATH_RX == P.CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR == 1` in autogen/bnxt.py, so the substitution is a no-op over every possible input and no fixture can separate them. It is closed with a claim about the constants (`c_CFA_L2_*_FLAGS_PATH_RX` and `c_CFA_L2_FILTER_ALLOC_REQ_ENABLES_L2_ADDR` are both rows) and not with a row that asserts the swapped word is wrong. |
# | 36 | :27 -- THE CONTROL: a comment-only edit | 0 | a table with no row that CANNOT move is a table of coincidences. |

# THE CONSTANT SWEEP. `.agents/slop/bnxt_sweep.py` puts `+1` on every one of the
# 136 `def NAME() -> U32: V` constant defs, ONE AT A TIME, and diffs the whole
# lines. 134 of 136 move a row. The two that do not are `P.BNXT_HWRM_NO_CMPL_RING`
# and `MISSING`, both `4294967295`, where `+1` OVERFLOWS THE U32 and the mutated
# file does not compile -- that is a limitation of the `+1` method, not a
# coverage gap, and it is reported as `DID NOT COMPILE` rather than counted as a
# blind spot.
#
# `ops_metal`'s sweep found 30 blind of 111, all `CALL_*` tags. On this file the
# nineteen `CALL_*` tags were BLIND at first and are not any more, because
# `t_tags` added `tag_distinct_*` rows. That is the right fix and not a row that
# asserts a tag's number: a tag is an identity, not a value. It is only ever
# compared against another tag, so any permutation of the nineteen is
# observationally equivalent, and what is actually checkable is that they are
# DISTINCT.
#
# `P.QUEUE_PAGE` and `BS_TYPE0` were also blind and both are now read: the first by
# `queue_page` (and its `+1` is a degenerate edit -- `4097 // 16 == 256`), the
# second by `bs_type0`.
