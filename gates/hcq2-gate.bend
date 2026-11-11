# gates/hcq2-gate.bend -- THE GATE DRIVER for `tinybendygrad/runtime/support/hcq2.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. THE PORT FILE CARRIES THE PORT AND
# THIS FILE CARRIES THE INSTRUMENT, AND THE TREE's OWN CONVENTION SAYS SO:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# THE ROWS ARE PURE CONSUMERS: THEY CALL THE PORT's DEFS AND DEFINE
# NOTHING THAT THE PORT NEEDS.

import Base
import ./../tinybendygrad/runtime/support/hcq2.bend as P
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/device.bend as D
import ./../tinybendygrad/LAWS/spec.bend as S

def Ecopyq() -> List<&2, P.E>: [P.E{1, 1, 1, 2}, P.E{1, 2, 3, 1}]
# :159 `(so := (i % STAGING_SLOTS) * chunk * it)` -- where copy `i` lands. Two
# slots, so the slot alternates, and the `* it` is the byte offset inside it.
def staging_slot_at(i: U32, +it: U32) -> U32:
  U32.mul(U32.mod(i, P.STAGING_SLOTS()), U32.mul(P.staging_chunk(it), it))
# ===========================================================================
# THE TYPES.
# ===========================================================================
# ONE recorded call. `a`/`b`/`c` are the argument the def around it BUILT:
#   WAIT/SIGNAL   a = the slot index (2*i), b = the value waited on / stored
#   TIMESTAMP     a = the slot index
#   BARRIER       a = 0
#   CALL          a = the batch tag
#   COPY          a = dst, b = src, c = n
#   LOOP          a = vmax, b = the trip byte count
#   SUBMIT        a = the queue index, b = the command count
#   FENCE         a = ndevs, b = nsigs
#   RAISE         a = the raise site
# There is deliberately no field for a call's identity in the graph; that is
# what the defs around this record build, and the gate reads it off the record
# a def RETURNS.
# The machine state of the FFI seam. `bad_at` is the ORDINAL of the refusal that
# should fire (0 = never), so one fixture reaches each raise site in turn. The
# raise is INSIDE the trace (see `Tr.emit.go`), so a refusal is a TRUNCATION
# and needs no guard of its own at the call site.
# hcq2.py:366-377 `HWQueue.blob` / `HWQueue.patches`, as VALUES. Bend has no
# mutation, so `q` answers a fresh `Qd` and the caller threads it. `blob` is the
# DEVICE-VISIBLE byte stream and `ps` are `(offset, label)` patch sites -- the
# pairs `self.patches.append((len(self.blob), w))` makes.
# ONE argument of `HWQueue.q`. `lo`/`hi` are the two halves of the value (see
# wall 4: a u64 is not one number here), `sz` the `w.dtype.itemsize` or the BINARY
# length, and `lab` the patch LABEL, which is the word's identity in the gate.
#
# `W_INT` is a bare Python int (`:375`'s `(c, 4)` -- ALWAYS four bytes);
# `W_CONST` is a CONST or a CAST of one (`:375`'s `(c.val, w.dtype.itemsize)`);
# `W_BINARY` is `Ops.BINARY` (`:370`, appended VERBATIM); `W_WORD` is anything
# else (`:371-373`, a patch plus zero bytes). The ladder is `:369-376` exactly.
def f_cmd() -> List<&2, P.Fld>:
  [P.Fld{0, "flags", 0, 8}, P.Fld{1, "cmdlist", 8, 8}, P.Fld{2, "cmdsize", 16, 4},
   P.Fld{3, "numcmds", 20, 4}, P.Fld{4, "objlist", 24, 8}, P.Fld{5, "objsize", 32, 4},
   P.Fld{6, "numobjs", 36, 4}, P.Fld{7, "synclist", 40, 8}, P.Fld{8, "syncsize", 48, 4},
   P.Fld{9, "numsyncs", 52, 4}, P.Fld{10, "context_id", 56, 4}, P.Fld{11, "timestamp", 60, 4}]
def bz_reg_devcall() -> List<&2, D.Lk>: [D.Lk{D.to_name(["CPU", "call"]), 1, 4}]
# THE ROWS for one case. The result is destructured ONCE -- a `match` may not
# scrutinise a record's fields at a CALL SITE, so a def that reads five fields
# of `Bz` reads them in one `match` and prints five rows.
def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))
# a list of U32 as `0 4 8 16 24 28`, which is exactly how the oracle prints
# `[o for o, _ in layout_args(...)]` -- so the two strings are compared, not
# the two numbers.
# THE separator goes in front of every element and the first one is dropped.
# The obvious shape -- "no separator on the first element", decided by
# `List.is_empty(acc)` -- IS WRONG IN BOTH LANES, and the reason is worth
# recording: see THE `+` ALIASES BETWEEN TWO ARGUMENTS above. `String.length(sep)`
# is the drop count, so a two-character separator works with no extra def.
def urow(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))
def bz_rows(+nm: String, r: P.Bz) -> IO(Unit):
  match r:
    case P.Bz{ar, level, kind, buf, nb, dev}:
      do IO<Unit>:
        a : Unit <- urow(String.concat(["bz_lvl_", nm]), level)
        b : Unit <- urow(String.concat(["bz_kind_", nm]), kind)
        c : Unit <- urow(String.concat(["bz_buf_", nm]), buf)
        d : Unit <- urow(String.concat(["bz_bytes_", nm]), nb)
        e : Unit <- srow(String.concat(["bz_dev_", nm]), dev)
        IO.pure(Unit, Unit{})
# THE TWELVE CASES, in the CPython oracle's order. The two lanes are compared
# BY THE NUMBER: the slot, the level, the kind and the byte count.
def ONE16() -> List<&2, U32>: [2]
def peer_slot_bytes(profile: Bool) -> U32: U32.mul(2, P.peer_slot_words(profile))
# ===========================================================================
# `ctx.last` (:226) and `ctx.prev` (:225). `last[(dev, q)] = tag` is OVERWRITTEN,
# so `last` holds the LAST tag of each queue and `prev[tag]` is whatever tag held
# the slot before it -- NONE for the first call on a queue. :249 is the only
# reader of `prev` and it is the NV QMD-chaining workaround, so nothing in these
# fixtures reads it. `hq2_b*_prev` is the row that says so out loud rather than
# leaving it untested, and `prev_or_self` is :249's `p` when it is not None.
# ===========================================================================
# THE batch fixtures. Five SHAPES, because ONE fixture cannot tell a first-WINS
# RULE FROM A LAST-WINS RULE and the `signal_tags` rule at :230 is exactly that:
# it reads `self.last`, which holds ONE tag per queue. `three` is three queues,
# `two` is two calls on ONE queue with overlapping buffers, `fifo` is two calls
# on one queue with DISJOINT buffers, `copyq` is two queues, `revis` is three
# calls on one queue.
def Ethree() -> List<&2, P.E>: [P.E{1, 1, 1, 2}, P.E{1, 2, 2, 3}, P.E{1, 3, 3, 1}]
def staging_copies(max_numel: U32, +it: U32) -> U32:
  U32.div(U32.add(max_numel, U32.sub(P.staging_chunk(it), 1)), P.staging_chunk(it))
# :159 `(so := (i % STAGING_SLOTS) * chunk * it)` -- where copy `i` lands. Two
# slots, so the slot alternates, and the `* it` is the byte offset inside it.
def dev_name(n: U32) -> String:
  match n:
    case 1: "NV"
    case 2: "QCOM"
    case 3: "CUDA"
    case 4: "NULL"
    case 5: "METAL"
    case 6: "AMD"
    case _: ""
# the id of a device NAME, or `NO_HCQ_DEV` for a head that is not an HCQ one.
# `CPU`, `CUDAX` and `""` are the three ways to miss, and `""` is not a miss
# by accident: `all_devices_in((), HCQ_DEVS)` is `set() <= HCQ_DEVS` = True.
def MOCK_STAGING_SIZE() -> U32: 4194304
# :157 `chunk = (STAGING_SIZE // STAGING_SLOTS) // it` -- the staging slot is
# `STAGING_SIZE // STAGING_SLOTS` BYTES, and the chunk is that in ELEMENTS of
# width `it`. Two divides, and the order is the claim.
# AND THE CDTYPE EACH ROW IS CAST TO (hcq2.py:89's `v.cast(flds[n][1])`), which
# is `flds[n][1].itemsize`. A descriptor that carries the right offset and the
# wrong width writes the right bytes at the wrong scale.
def hcq2_dev_n() -> U32: U32.from_nat(List.length(&2, U32, P.HCQ_DEVS()))
# :20's reverse direction -- `all_devices_in` (:38) asks "is every head of this
# device string IN THE SET", and `x.split(":")[0]` is what it asks about.
# `dev_head` is that split, `dev_of` is the reverse lookup, and
# `hc2_hcq_dev_of_*` are the six name rows.
def row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))
def cdtype_sizes() -> List<&2, U32>: [1, 2, 4, 8]
# hcq2.py:131 `STAGING_SIZE, STAGING_SLOTS = (4 if DEV.interface.startswith
# ("MOCK") else 128) << 20, 2`. NOT a mock device, so 128 MiB and 2 slots.
# `sched_timeline` (:239) is the slot AFTER every queue: `2 * nq(dev)`.
def HCQ_CACHE_THRESH() -> U32: 64
# hcq2.py:20 AT PIN `0a5776355` -- the 646-LINE `hcq2.py` this header declares --
# `HCQ_DEVS = frozenset(("NV","QCOM","CUDA","NULL","METAL")) |
# (frozenset(("AMD",)) if HCQ2 else frozenset())`. With HCQ2=1 -- which is what
# this file IS -- the set is the six below, in the source's order.
#
# THE PIN IS named because the constant moved and the set changed with it, and
# this is the only place in the port that says so: `d33d97ca7` ("hipify cuda",
# #18763) added `HIP` on 2026-10-12, `e8308c08f` ("hcq2: schedule with cf",
# #18809) moved the constant OUT of `hcq2.py` and into `device.py:19` on
# 2026-10-14, and `38cbec532` ("move cl to hcq2", #18872) added `CL` on
# 2026-10-19. At upstream HEAD the set is EIGHT members and `hcq2.py:20` is
# not it.
#
# THE six below are the PIN'S set and not a subset by design. At the pin neither
# `HIP` nor `CL` was an HCQ device -- upstream's `ops_hip.py` was 71 lines and
# `ops_cl.py` 130, and the port's `ops_hip.bend`/`ops_cl.bend` are ports of
# exactly those -- so adding them here would claim a queue model those two
# files do not have.
# ===========================================================================
# THE FIXTURES, and each one is a dtype ITEMSIZE list because that is the only
# thing `layout_args` reads (tinygrad/runtime/support/hcq2.py:71 builds `w.dtype` from the word).
#
# `MIXED` is THE FIXTURE. Every uniform list agrees with an implementation that
# advances off the UNROUNDED offset, because with all widths equal to `k` the
# two agree at every step. `MIXED` has a uint16 at slot 8 which ends at 10 and a
# ulong after it which is padded to 16, and that is the ONLY thing in this file
# that can see the walrus. It is the SAME list the PORT's own `ops_nv.bend`
# NO LONGER CARRIES printed.
# ===========================================================================
def t_consts() -> IO(Unit):
  do IO<Unit>:
    urow("hq2_cache_thresh", HCQ_CACHE_THRESH())
    urow("hq2_devs_n", hcq2_dev_n())
    # BOTH DIRECTIONS on the discriminator. `hc2_dev_id_*` is value -> name and
    # `hq2_dev_head_*` is the `x.split(":")[0]` the membership test asks about.
    srow("hq2_dev_name_1", dev_name(P.HCQ_DEV_NV()))
    srow("hq2_dev_name_2", dev_name(P.HCQ_DEV_QCOM()))
    srow("hq2_dev_name_3", dev_name(P.HCQ_DEV_CUDA()))
    srow("hq2_dev_name_4", dev_name(P.HCQ_DEV_NULL()))
    srow("hq2_dev_name_5", dev_name(P.HCQ_DEV_METAL()))
    srow("hq2_dev_name_6", dev_name(P.HCQ_DEV_AMD()))
    urow("hq2_dev_name_0", U32.from_nat(String.length(dev_name(0))))
    urow("hq2_dev_id_NV", P.dev_id("NV"))
    urow("hq2_dev_id_QCOM", P.dev_id("QCOM"))
    urow("hq2_dev_id_CUDA", P.dev_id("CUDA"))
    urow("hq2_dev_id_NULL", P.dev_id("NULL"))
    urow("hq2_dev_id_METAL", P.dev_id("METAL"))
    urow("hq2_dev_id_AMD", P.dev_id("AMD"))
    urow("hq2_dev_id_CPU", P.dev_id("CPU"))
    urow("hq2_dev_id_NVX", P.dev_id("NVX"))
    urow("hq2_dev_id_lower", P.dev_id("nv"))
    srow("hq2_dev_head_NV0", P.dev_head("NV:0"))
    srow("hq2_dev_head_NV01", P.dev_head("NV:0:1"))
    srow("hq2_dev_head_CPU012", P.dev_head("CPU:0:1:2"))
    srow("hq2_dev_head_bare", P.dev_head("AMD"))
    srow("hq2_dev_head_nocolon", P.dev_head("METAL:1"))
    # CDTYPE BOTH WAYS. `hc2_cdtype_*` is size -> dtype and
    # `hq2_cdtype_of_*` is the same four rows from the other direction.
    urow("hq2_cdtype_1", P.cdtype_of(1))
    urow("hq2_cdtype_2", P.cdtype_of(2))
    urow("hq2_cdtype_4", P.cdtype_of(4))
    urow("hq2_cdtype_8", P.cdtype_of(8))
    urow("hq2_cdtype_3", P.cdtype_of(3))
    urow("hq2_cdtype_0", P.cdtype_of(0))
    urow("hq2_cdtype_16", P.cdtype_of(16))
    urow("hq2_cdtype_len", U32.from_nat(List.length(&2, U32, cdtype_sizes())))
    row("hq2_cdtype_roundtrips_1", U32.is_eq(P.cdtype_of(1), 1))
    row("hq2_cdtype_roundtrips_2", U32.is_eq(P.cdtype_of(2), 2))
    row("hq2_cdtype_roundtrips_4", U32.is_eq(P.cdtype_of(4), 4))
    row("hq2_cdtype_roundtrips_8", U32.is_eq(P.cdtype_of(8), 8))
    row("hq2_cdtype_rejects_3", Bool.not(P.cdtype.is(3)))
    row("hq2_cdtype_rejects_16", Bool.not(P.cdtype.is(16)))
    row("hq2_cdtype_accepts_4", P.cdtype.is(4))
    # THE STAGING CONSTANTS, and :157's TWO DIVIDES in that order.
    urow("hq2_staging_size", P.STAGING_SIZE())
    urow("hq2_staging_slots", P.STAGING_SLOTS())
    urow("hq2_mock_staging_size", MOCK_STAGING_SIZE())
    urow("hq2_staging_slot_bytes", P.staging_slot_bytes())
    urow("hq2_chunk_it1", P.staging_chunk(1))
    urow("hq2_chunk_it4", P.staging_chunk(4))
    urow("hq2_chunk_it2", P.staging_chunk(2))
    urow("hq2_chunk_it8", P.staging_chunk(8))
    urow("hq2_copies_1000_it1", staging_copies(1000, 1))
    urow("hq2_copies_1000_it4", staging_copies(1000, 4))
    urow("hq2_copies_big_it2", staging_copies(67108865, 2))
    urow("hq2_copies_big_it1", staging_copies(134217729, 1))
    urow("hq2_slot_at_0_it1", staging_slot_at(0, 1))
    urow("hq2_slot_at_1_it1", staging_slot_at(1, 1))
    urow("hq2_slot_at_2_it1", staging_slot_at(2, 1))
    urow("hq2_slot_at_3_it1", staging_slot_at(3, 1))
    urow("hq2_slot_at_3_it4", staging_slot_at(3, 4))
    IO.pure(Unit, Unit{})
def fld_n(+fs: List<&2, P.Fld>) -> U32: U32.from_nat(List.length(&2, P.Fld, fs))
# :102 `rows = [(flds[n][0], v.cast(flds[n][1]) if isinstance(v, UOp) else
# UOp.const(v, flds[n][1])) for n, v in fields.items()]` -- ONE ROW PER KWARG, in
# kwargs order, at the field's own offset and cast to the field's CDTYPE. The
# `ib` and `cmd` tables below are ops_qcom.py:197-198 verbatim, and
# `hq2_cstruct_ib_rows` / `hq2_cstruct_cmd_rows` are the `<off>:<itemsize>` list.
def fld_at(+fs: List<&2, P.Fld>, nm: String) -> U32:
  P.fld_at.go(List.length(&2, P.Fld, fs), fs, nm, 0)
def head_of(+xs: List<&2, U32>) -> U32: P.head_of.at(List.get(&2, U32, xs, 0n))
def has_kind(+xs: List<&2, P.Ins>, k: U32) -> Bool: Bool.not(U32.is_zero(P.count_kind(xs, k)))
def stamps(+bs: List<&2, P.E>, +tag: U32, +profile: Bool) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, profile, [P.stamp_n(bs, tag, profile),
                                    U32.add(P.stamp_n(bs, tag, profile), 1)], Nil{})
# `ctx.slots[dev]` (:232) `2 * (len(qs) + 1 + (2*len(batch) if profile else 0))`
# -- one signal per queue, plus one scheduler timeline, plus two stamps per call,
# all u64. THE LEADING `2 *` IS THE WHOLE FORMULA.
def ascending(+xs: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}: True{}
    case h <> t: P.asc.go(List.length(&2, U32, t), t, h)
# ===========================================================================
# THE GATE. One row per claim, and every `py=` expectation is the value CPython
# answered when `.agents/slop/hcq2-probe.py` (or `-probe2.py`) CALLED hcq2.py
# with DEV=NULL and no device present. Nothing here is hand-typed: four times in
# this project a hand-typed expectation was the bug, and `nv_query_litter` was
# wrong in the PORT *and* the ORACLE, so "the port and the oracle agree" is not
# corroboration -- it is one mistake copied.
# ===========================================================================
def device_sig_ks(+ks: List<&2, U32>) -> List<&2, U32>: D.iter_sig(ks)
# IS THE OUTPUT ASCENDING? `pack` takes ascending rows as a precondition
# because base.bend has no `sort` without a closure (hcq2.py:80's
# `sorted(args, key=lambda x: x[0])`). This is the row that makes the
# precondition true rather than assumed, and it is checked on the list `pack`
# is actually handed -- not on a list chosen to be sorted.
def MIXED() -> List<&2, U32>: [1, 4, 2, 8, 4, 1]
def layout_ts(+ks: List<&2, U32>, base: U32) -> List<&2, U32>:
  P.layout_k.go(List.length(&2, U32, ks), P.layout(ks, base), Nil{})
# ===========================================================================
# hcq2.py:73-83 `pack_args`. THE WORD SEQUENCE, and two things about it are easy
# to get wrong:
#
#   1. A PAD IS A WORD. `[UOp(Ops.BINARY, arg=bytes(offset - end)), arg]` and
#      `[arg]` are both appended, and `bytes(0)` is `b''` -- which is still a
#      `BINARY` in the output. So `pack_args` of a three-u64 list into 24 bytes
#      is FOUR words, the last of them an EMPTY pad, and dropping it loses a
#      word. `hq2_pack_buf3_0_24` and `hq2_pack_empty_0` are the rows.
#   2. THE trailing pad is `size - end` AND it can be negative. :83 is
#      `bytes(size - end)`; with `end > size` CPython raises `ValueError:
#      negative count`. `hq2_pack_mixed_0_24` is the refusal row -- a gate that
#      cannot see a raise cannot tell a truncation from a short read.
#
# `sorted(args, key=lambda x: x[0])` (:80) IS A WALL: base.bend has no `sort`
# without a closure, and the only in-tree caller is `layout`, whose output is
# ascending BY CONSTRUCTION. So `pack` takes ASCENDING rows as a precondition
# and `hq2_layout_is_ascending` is the row that makes it true rather than an
# assumption.
# ===========================================================================
def layout_at(+ks: List<&2, U32>, base: U32, n: Nat) -> U32:
  P.layout_at.pick(List.get(&2, P.Arg, P.layout(ks, base), n))
def layout_n(+ks: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, P.Arg, P.layout(ks, 0)))
def FIVE32() -> List<&2, U32>: [4, 4, 4, 4, 4]
def lrow(nm: String, +xs: List<&2, U32>) -> IO(Unit):
  srow(nm, P.joined(xs, " "))
def u32s_eq(+a: List<&2, U32>, +b: List<&2, U32>) -> Bool: H.u32_list_eq(a, b)
def BUF3() -> List<&2, U32>: [8, 8, 8]
def INTS() -> List<&2, U32>: [4, 4, 4]
def layout_ks(+ks: List<&2, U32>, base: U32) -> List<&2, U32>:
  P.layout_off.go(List.length(&2, U32, ks), P.layout(ks, base), Nil{})
# THE PORT of `bufferize_buf`.
def ODD() -> List<&2, U32>: [4, 1, 8]
# `D.iter_sig` on its own -- what `device.bend` holds, read WITHOUT the base
# offset. The cross-check against `layout` is the claim.
def t_layout() -> IO(Unit):
  do IO<Unit>:
    # hcq2.py:74-76. THE CITED FUNCTION. `py=` from hcq2-oracle.py `layout()`,
    # which CALLS `hcq2.layout_args`. The three bases are 0, 256 and 512, and
    # 512 is upstream's `qmd_sz` (tinygrad/runtime/ops_nv.py:135) base.
    lrow("hq2_layout_buf3_0", layout_ks(BUF3(), 0))
    lrow("hq2_layout_buf3_256", layout_ks(BUF3(), 256))
    lrow("hq2_layout_buf3_512", layout_ks(BUF3(), 512))
    lrow("hq2_layout_mixed_0", layout_ks(MIXED(), 0))
    lrow("hq2_layout_mixed_256", layout_ks(MIXED(), 256))
    lrow("hq2_layout_mixed_512", layout_ks(MIXED(), 512))
    lrow("hq2_layout_five32_0", layout_ks(FIVE32(), 0))
    lrow("hq2_layout_five32_256", layout_ks(FIVE32(), 256))
    lrow("hq2_layout_five32_512", layout_ks(FIVE32(), 512))
    # AN `int` IN THE ARGUMENT LIST BECOMES A uint32 (hcq2.py:75), so three ints
    # lay out as 0, 4, 8 -- NOT 0, 8, 16. `hq2_layout_ints_*` is that claim and
    # `hq2_layout_words_ints` is the dtype list behind it.
    lrow("hq2_layout_ints_0", layout_ks(INTS(), 0))
    lrow("hq2_layout_ints_256", layout_ks(INTS(), 256))
    lrow("hq2_layout_ints_512", layout_ks(INTS(), 512))
    lrow("hq2_layout_one16_0", layout_ks(ONE16(), 0))
    lrow("hq2_layout_one16_256", layout_ks(ONE16(), 256))
    lrow("hq2_layout_one16_512", layout_ks(ONE16(), 512))
    lrow("hq2_layout_odd_0", layout_ks(ODD(), 0))
    lrow("hq2_layout_odd_256", layout_ks(ODD(), 256))
    lrow("hq2_layout_odd_512", layout_ks(ODD(), 512))
    # THE KERNEL-ARGUMENT TRACE, which IS the dtype list in order.
    lrow("hq2_layout_words_mixed", layout_ts(MIXED(), 0))
    lrow("hq2_layout_words_ints", layout_ts(INTS(), 0))
    lrow("hq2_layout_words_buf3", layout_ts(BUF3(), 0))
    urow("hq2_layout_buf3_n", layout_n(BUF3()))
    urow("hq2_layout_mixed_n", layout_n(MIXED()))
    urow("hq2_layout_buf0_n", layout_n(Nil{}))
    # The PORT's own `ops_nv.bend` NO LONGER CARRIES these TWO CLAIMS -- it is a
    # header-only file -- so they are re-asked here of `hcq2.layout_args` itself.
    lrow("hq2_layout_opsnv_mixed", layout_ks(MIXED(), 0))
    lrow("hq2_layout_opsnv_buf3var2", layout_ks([8, 8, 8, 4, 4], 512))
    # THE CROSS-IMPLEMENTATION ROW: `D.iter_sig` read on its own, which is what
    # `device.bend` holds. TWO independent readings of the same walrus. See THE
    # WALRUS IS LOAD-BEARING above, and upstream's `iter_sig`
    # (tinygrad/device.py:352 symbol=iter_sig).
    lrow("hq2_layout_sig_mixed", device_sig_ks(MIXED()))
    lrow("hq2_layout_sig_buf3", device_sig_ks(BUF3()))
    lrow("hq2_layout_sig_five32", device_sig_ks(FIVE32()))
    row("hq2_layout_agrees_mixed", u32s_eq(layout_ks(MIXED(), 0), device_sig_ks(MIXED())))
    row("hq2_layout_agrees_buf3", u32s_eq(layout_ks(BUF3(), 0), device_sig_ks(BUF3())))
    row("hq2_layout_agrees_five32", u32s_eq(layout_ks(FIVE32(), 0), device_sig_ks(FIVE32())))
    # THE WALRUS ITSELF: the uint16 at slot 8 ends at 10, so the ulong after it
    # is padded to 16. An implementation that advanced off the UNROUNDED offset
    # answers 0, 4, 6, 8, 16, 19 for this list -- which is what `device.bend:864 symbol=map_ok`
    # did until `7f170f644`. `hq2_layout_ulong_slot` is the narrow claim.
    urow("hq2_layout_ulong_slot", layout_at(MIXED(), 0, 3n))
    urow("hq2_layout_uint16_slot", layout_at(MIXED(), 0, 2n))
    urow("hq2_layout_uchar_slot", layout_at(MIXED(), 0, 0n))
    urow("hq2_layout_uint8_last_slot", layout_at(MIXED(), 0, 5n))
    # AND THE BASE OFFSET IS AN ADDITION, not a shift of the whole list: at 512
    # the first slot is 512 and the gaps are the same.
    urow("hq2_layout_at512_first", layout_at(MIXED(), 512, 0n))
    urow("hq2_layout_at256_first", layout_at(MIXED(), 256, 0n))
    row("hq2_layout_base_is_add", U32.is_eq(layout_at(MIXED(), 512, 0n), U32.add(layout_at(MIXED(), 0, 0n), 512)))
    # THE PRECONDITION `pack` RELIES ON. base.bend has no sort without a
    # closure, and `layout`'s output is ascending BY CONSTRUCTION -- so this row
    # is what makes `hq2_pack_*` mean anything. A DECREASING list would be a
    # different gate, not a silent one.
    row("hq2_layout_is_ascending", ascending(layout_ks(MIXED(), 512)))
    row("hq2_layout_is_ascending_buf3", ascending(layout_ks(BUF3(), 0)))
    row("hq2_layout_is_ascending_one16", ascending(layout_ks(ONE16(), 256)))
    IO.pure(Unit, Unit{})
def to_name2(a: String, b: String) -> String: P.to_name([a, b])
# :158-160 the copy count: `range(0, src.max_numel(), chunk)` has
# `ceildiv(max_numel, chunk)` steps and the LAST one is the remainder.
def bz_al_unnamed(dev: String, dev_ix: U32) -> P.Al:
  P.Al{False{}, "", dev, dev_ix, 16, S.uint8()}
# THE ROWS for one case. The result is destructured ONCE -- a `match` may not
# scrutinise a record's fields at a CALL SITE, so a def that reads five fields
# of `Bz` reads them in one `match` and prints five rows.
def epiname(+bs: List<&2, P.E>, dev: U32) -> String: P.qname(P.epi(bs, dev))
# `D.iter_sig` on its own -- what `device.bend` holds, read WITHOUT the base
# offset. The cross-check against `layout` is the claim.
def pk_str(+xs: List<&2, P.Pk>) -> String: String.drop(String.concat(P.pack_pks(xs, Nil{})), 1n)
# ===========================================================================
# hcq2.py:100-106 `cstruct` / `cfield`. THE QUEUE-DESCRIPTOR PACKING, and the
# two things that matter are the FIELD NAMES and the FIELD ORDER.
#
# :101 `{n: (o, CDTYPE[ctypes.sizeof(t)]) for n, t, o, *_ in struct_t._real_fields_
# if ctypes.sizeof(t)}` is the FIELD TABLE, keyed by NAME. :102 builds `rows`
# from the CALLER'S kwargs, so the ROW ORDER is the kwargs order and not the
# struct order:
#     ops_qcom.py:197  cstruct(struct_kgsl_command_object, gpuaddr=..., size=..., flags=...)
#     ops_qcom.py:198  cstruct(struct_kgsl_gpu_command, cmdlist=..., cmdsize=..., numcmds=...,
#                                        context_id=...)
# `ops_cl`'s unit found `Sig`'s field names INVERTED and a correct computation
# looked wrong, so both directions are rows: `hq2_cstruct_*_order` is
# name-in-source-order and `hq2_cfield_*_at` / `_sz` are name -> offset/size.
#
# The two tables below are the qcom descriptors, MEASURED by calling
# `kgsl.struct_kgsl_command_object._real_fields_` and
# `kgsl.struct_kgsl_gpu_command._real_fields_` (hcq2-oracle.py `cstruct()`).
# ===========================================================================
def Etwo() -> List<&2, P.E>: [P.E{1, 1, 1, 2}, P.E{1, 1, 2, 1}]
def pk_n(+xs: List<&2, P.Pk>) -> U32: U32.from_nat(List.length(&2, P.Pk, xs))
def prev_none_n(+bs: List<&2, P.E>) -> U32: P.prev_none_n.go(List.length(&2, P.E, bs), bs, 0, 0)
def bz_al(name: String, dev: String, dev_ix: U32) -> P.Al:
  P.bz_al_n(name, dev, dev_ix, 16)
# The entry: the PLAIN name, KIND 1 (a CALLABLE), and the slot of THIS
# device's timeline -- slot 8, the slot the arena appends.
def bz_reg_timeline() -> List<&2, D.Lk>: [D.Lk{"timeline", 1, 8}]
# ===========================================================================
# THE FIXTURES. The arena is `device.bend`'s own `lk_arena()` -- slot 0 is the
# bottom, slots 1..6 are the registry's sentinels at 64 bytes each and slot 7
# is the device hook's buffer at 16 bytes -- so the port and the CPython
# oracle agree on the SLOT NUMBERS by construction and not by a convention
# both had to remember.
#
# THE REGISTRY IS THIS FILE'S, because the device-scoped key is a fold of the
# device and `device.bend`'s fixture device is "PYTHON" while this one is a
# device the port's table has an INDEX for: `device.bend`'s `dev_name` is
# 7 = "CPU" and 11 = "NULL", and a buffer the port ALLOCATES lands in a slot,
# and a slot carries an index.
# ===========================================================================
def all_in(+ds: List<&2, String>) -> Bool: P.all_in.go(ds, "", True{})
# ===========================================================================
# hcq2.py:69-76 `layout_args`. THE CITED ONE -- ops_nv.bend names it at :14,
# :181, :205, :1439, :1873 and :1892.
#
#   words = [a if isinstance(a, UOp) else UOp.const(a, dtypes.uint32) for a in args]
#   return [(offset + o, w) for (o,_), w in zip(TinyELF.iter_sig(...), words)]
#
# So it is `iter_sig` and a base offset, and an `int` in the argument list
# becomes a FOUR-byte word (`:75`'s `UOp.const(a, dtypes.uint32)`) -- which is
# why `ints` below lays out as 0, 4, 8 and not 0, 8, 16.
#
# THE WALRUS IS LOAD-BEARING, and it lives in `device.bend`: `iter_sig` yields
# `(offset := round_up(offset, dt.itemsize)), dt; offset += dt.itemsize`, so the
# advance is `round_up(off, k) + k`. upstream's `iter_sig`
# (tinygrad/device.py:352 symbol=iter_sig) IS that walrus, and the PORT's own
# `ops_nv.bend` NO LONGER CARRIES the copy that read it. `device.bend:859-885`
# IS the port's own copy. This file CONSUMES `D.iter_sig` rather than
# re-deriving it, and `hq2_layout_*_matches_device_bend` is the cross-check:
# two independent readings of the same walrus agreeing is the claim.
# ===========================================================================
# THE TWELVE CASES, in the CPython oracle's order. The two lanes are compared
# BY THE NUMBER: the slot, the level, the kind and the byte count.
def bz_reg_plain() -> List<&2, D.Lk>: [D.Lk{"mine", 0, 1}]
def bz_ix_null() -> U32: 11
# --- the batch GEOMETRY readers the gate needs.
def bz_reg_dup() -> List<&2, D.Lk>: D.link_add([D.Lk{"dup", 0, 5}], "dup", 0, 6)
def bz_reg_both() -> List<&2, D.Lk>: D.link_add(P.bz_reg_dev(), "mine", 0, 1)
def bz_reg_call() -> List<&2, D.Lk>: [D.Lk{"call", 1, 3}]
def bz_reg_none() -> List<&2, D.Lk>: Nil{}
# THE ALLOCS. 16 uint8, so a FRESH buffer is 16 bytes and a REGISTERED one is
# the registry's own -- 64. The timeline case's alloc is 64 bytes, so its
# SIZE row says which of the two won.
# hcq2.py:19 AT PIN `0a5776355` `ContextVar("HCQ_CACHE_THRESH", 64)`. :565 reads
# it as `len(linear.src) < HCQ_CACHE_THRESH`.
def bz_tl_arena() -> D.Bar:
  P.bz_tl_arena2(D.bnew(D.lk_arena(), D.root(P.bz_ix_cpu(), 16, S.uint8(), P.bz_tl_spec())))
# The entry: the PLAIN name, KIND 1 (a CALLABLE), and the slot of THIS
# device's timeline -- slot 8, the slot the arena appends.
def bufferize(+regs: List<&2, D.Lk>, +hook: D.Hook, +ar: D.Bar, al: P.Al) -> P.Bz:
  match al:
    case P.Al{+has_name, +name, +dev, +dev_ix, +n, +dt}:
      match has_name:
        case False{}: P.bz_unnamed(ar, dev, dev_ix, n, dt)
        case True{}: P.bz_named(regs, hook, ar, name, dev, dev_ix, n, dt)
# ===========================================================================
# THE REGISTRY ENTRY upstream's `hcq2.py:477` sets:
#   `Compiled.link_bufs |= {"timeline": lambda b: Device[b.device].timeline}`
#
# THE wall, AND it is the `Lk` SHAPE. Upstream's entry is a PLAIN name whose
# value is a CALLABLE, and the callable's result depends on the ALLOC's
# DEVICE. The port's registry entry is `D.Lk{name, kind, buf}` -- ONE arena
# slot -- so it cannot hold a per-device result.
#
# THE port has the timeline'S SIZE AND its SPEC: `device.bend`'s
# `timeline_bytes()` is 16, and `device.py:414`'s spec is
# `BufferSpec(host=True, uncached=True, cpu_access=True)`. THE PORT HAS NO
# per-device timeline INSTANCE: upstream's is `Compiled.timeline`, a
# `cached_property` on the device class, and the port has no device object to
# hang one on.
#
# SO the port produces the entry in the shape upstream uses for its other
# PER-DEVICE BUFFERS (`ops_cuda.py:106`, `ops_metal.py:218`,
# `ops_qcom.py:341`): a PLAIN "timeline" entry, KIND 1 -- a CALLABLE -- whose
# slot is THIS device's timeline. On a ONE-device tree that is upstream's
# answer exactly: LEVEL 1, KIND 1. On a MULTI-device tree upstream's lambda
# picks the ALLOC's device's timeline and the port's single slot cannot, and
# THAT is the wall.
#
# THE TIMELINE BUFFER. `Compiled.timeline` is `Buffer(self.device, 16,
# options=BufferSpec(host=True, uncached=True, cpu_access=True),
# initial_value=bytes(16))` -- SIXTEEN BYTES -- and `device.py:430` reads it as
# two u64s (`self.timeline.host.view(fmt='Q')`), which is what `device.bend`'s
# `timeline_size()` = 2 models.
# ===========================================================================
def t_bufferize() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- srow("bz_devname_cpu", D.dev_name(P.bz_ix_cpu()))
    b : Unit <- srow("bz_devname_null", D.dev_name(bz_ix_null()))
    c : Unit <- bz_rows("plain", bufferize(bz_reg_plain(), D.link_buffer_base(), D.lk_arena(), bz_al("mine", "CPU", P.bz_ix_cpu())))
    d : Unit <- bz_rows("dev", bufferize(P.bz_reg_dev(), D.link_buffer_base(), D.lk_arena(), bz_al("mine", "CPU", P.bz_ix_cpu())))
    e : Unit <- bz_rows("both", bufferize(bz_reg_both(), D.link_buffer_base(), D.lk_arena(), bz_al("mine", "CPU", P.bz_ix_cpu())))
    f : Unit <- bz_rows("call", bufferize(bz_reg_call(), D.link_buffer_base(), D.lk_arena(), bz_al("call", "CPU", P.bz_ix_cpu())))
    g : Unit <- bz_rows("devcall", bufferize(bz_reg_devcall(), D.link_buffer_base(), D.lk_arena(), bz_al("call", "CPU", P.bz_ix_cpu())))
    h : Unit <- bz_rows("dup", bufferize(bz_reg_dup(), D.link_buffer_base(), D.lk_arena(), bz_al("dup", "CPU", P.bz_ix_cpu())))
    i : Unit <- bz_rows("none", bufferize(bz_reg_none(), D.link_buffer_base(), D.lk_arena(), bz_al("mine", "CPU", P.bz_ix_cpu())))
    j : Unit <- bz_rows("unnamed", bufferize(bz_reg_none(), D.link_buffer_base(), D.lk_arena(), bz_al_unnamed("NULL", bz_ix_null())))
    k : Unit <- bz_rows("hook", bufferize(bz_reg_none(), D.Hook{True{}, 7}, D.lk_arena(), bz_al("mine", "NULL", bz_ix_null())))
    l : Unit <- bz_rows("shadow", bufferize(bz_reg_plain(), D.Hook{True{}, 7}, D.lk_arena(), bz_al("mine", "NULL", bz_ix_null())))
    m : Unit <- bz_rows("wrongdev", bufferize(P.bz_reg_dev(), D.link_buffer_base(), D.lk_arena(), bz_al("mine", "CPU:0", P.bz_ix_cpu())))
    n : Unit <- bz_rows("timeline", bufferize(bz_reg_timeline(), D.link_buffer_base(), bz_tl_arena(), P.bz_al_n("timeline", "CPU", P.bz_ix_cpu(), 64)))
    IO.pure(Unit, Unit{})
# ===========================================================================
# THE MUTATION TABLE. Every "rows moved" below is the HARNESS's output, not an
# estimate: `.agents/slop/hcq2-mutate.py` applies one edit to a scratch copy,
# runs the INTERPRETED lane, and counts the rows whose VALUE changed. The useful
# column is "rows moved", because a mutation that moves nothing measures what
# this gate does NOT see.
#
# THE harness compares values and not row names. Its first version compared names
# and reported 0 for all thirty edits, which is the M30 trap wearing a different
# hat: a mutation changes what a row SAYS and never what a row is CALLED.
# ===========================================================================
def pack.trail(+as: List<&2, P.Arg>, +size: U32) -> List<&2, P.Pk>:
  P.pack.wrap(U32.is_gt(P.end_of(as), size), U32.sub(size, P.end_of(as)),
            P.pack.go(List.length(&2, P.Arg, as), as, 0, Nil{}))
# ===========================================================================
# THE FIXTURES. The arena is `device.bend`'s own `lk_arena()` -- slot 0 is the
# bottom, slots 1..6 are the registry's sentinels at 64 bytes each and slot 7
# is the device hook's buffer at 16 bytes -- so the port and the CPython
# oracle agree on the SLOT NUMBERS by construction and not by a convention
# both had to remember.
#
# THE REGISTRY IS THIS FILE'S, because the device-scoped key is a fold of the
# device and `device.bend`'s fixture device is "PYTHON" while this one is a
# device the port's table has an INDEX for: `device.bend`'s `dev_name` is
# 7 = "CPU" and 11 = "NULL", and a buffer the port ALLOCATES lands in a slot,
# and a slot carries an index.
# ===========================================================================
def pk_last(+xs: List<&2, P.Pk>) -> P.Pk: Maybe.default(&2, P.Pk, List.last(&2, P.Pk, xs), P.Pk{P.PK_ERR(), 0})
# ===========================================================================
# THE FIXTURES, and each one is a dtype ITEMSIZE list because that is the only
# thing `layout_args` reads (tinygrad/runtime/support/hcq2.py:71 builds `w.dtype` from the word).
#
# `MIXED` is THE FIXTURE. Every uniform list agrees with an implementation that
# advances off the UNROUNDED offset, because with all widths equal to `k` the
# two agree at every step. `MIXED` has a uint16 at slot 8 which ends at 10 and a
# ulong after it which is padded to 16, and that is the ONLY thing in this file
# that can see the walrus. It is the SAME list the PORT's own `ops_nv.bend`
# NO LONGER CARRIES printed.
# ===========================================================================
def t_pack() -> IO(Unit):
  do IO<Unit>:
    # hcq2.py:78-83. `py=` from hcq2-oracle.py `pack()`, which CALLS
    # `hcq2.pack_args` on `hcq2.layout_args` output.
    srow("hq2_pack_buf3_0_24", pk_str(pack.trail(P.layout(BUF3(), 0), 24)))
    srow("hq2_pack_buf3_0_32", pk_str(pack.trail(P.layout(BUF3(), 0), 32)))
    srow("hq2_pack_buf3_0_40", pk_str(pack.trail(P.layout(BUF3(), 0), 40)))
    srow("hq2_pack_mixed_0_32", pk_str(pack.trail(P.layout(MIXED(), 0), 32)))
    srow("hq2_pack_mixed_0_40", pk_str(pack.trail(P.layout(MIXED(), 0), 40)))
    srow("hq2_pack_mixed_0_64", pk_str(pack.trail(P.layout(MIXED(), 0), 64)))
    # A NON-ZERO BASE IS A LEADING PAD of the whole base, because `end` starts
    # at 0 (hcq2.py:79) and not at the first offset.
    srow("hq2_pack_buf3_8_32", pk_str(pack.trail(P.layout(BUF3(), 8), 32)))
    srow("hq2_pack_buf3_8_40", pk_str(pack.trail(P.layout(BUF3(), 8), 40)))
    srow("hq2_pack_buf3_512_536", pk_str(pack.trail(P.layout(BUF3(), 512), 536)))
    # THE REFUSAL: `bytes(size - end)` with `end > size` (hcq2.py:78).
    srow("hq2_pack_mixed_0_24", pk_str(pack.trail(P.layout(MIXED(), 0), 24)))
    row("hq2_pack_refused_24", U32.is_eq(P.Pk.k(pk_last(pack.trail(P.layout(MIXED(), 0), 24))), P.PK_ERR()))
    # THE EMPTY LIST IS ONE WORD, the trailing pad, at every size.
    srow("hq2_pack_empty_0", pk_str(pack.trail(Nil{}, 0)))
    srow("hq2_pack_empty_8", pk_str(pack.trail(Nil{}, 8)))
    srow("hq2_pack_empty_16", pk_str(pack.trail(Nil{}, 16)))
    urow("hq2_pack_empty_len", pk_n(pack.trail(Nil{}, 8)))
    urow("hq2_pack_buf3_len", pk_n(pack.trail(P.layout(BUF3(), 0), 24)))
    urow("hq2_pack_mixed_len", pk_n(pack.trail(P.layout(MIXED(), 0), 32)))
    # AN EMPTY PAD IS STILL A WORD: `bytes(0)` is `b''` and the BINARY is still
    # in the stream. `hq2_pack_buf3_len` is 4 for a three-word list.
    row("hq2_pack_empty_pad_is_word", U32.is_eq(pk_n(pack.trail(P.layout(BUF3(), 0), 24)), 4))
    # `end` IS the last OFFSET PLUS its own itemsize, not the size.
    urow("hq2_end_of_buf3", P.end_of(P.layout(BUF3(), 0)))
    urow("hq2_end_of_mixed", P.end_of(P.layout(MIXED(), 0)))
    urow("hq2_end_of_empty", P.end_of(Nil{}))
    IO.pure(Unit, Unit{})
def to_name3(a: String, b: String, c: String) -> String: P.to_name([a, b, c])
# ===========================================================================
# hcq2.py:38 `all_devices_in(d, c) = {x.split(":")[0] for x in to_tuple(d)} <= c`.
# A SUBSET, not a membership: two devices both in HCQ_DEVS is True, and the
# EMPTY device string is the empty set, which is a subset of everything. That
# last one is a fixture, not an oversight -- `hc2_all_in_empty` is a row.
# ===========================================================================
def ins_n(+xs: List<&2, P.Ins>) -> U32: U32.from_nat(List.length(&2, P.Ins, xs))
def Q_COPY1() -> U32: 3
# ONE enqueued call. `w` is the buffer at ranges[0] (WRITTEN) and `r` the buffer
# at ranges[1] (READ).
# ===========================================================================
# hcq2.py:100-106 `cstruct` / `cfield`. THE QUEUE-DESCRIPTOR PACKING, and the
# two things that matter are the FIELD NAMES and the FIELD ORDER.
#
# :101 `{n: (o, CDTYPE[ctypes.sizeof(t)]) for n, t, o, *_ in struct_t._real_fields_
# if ctypes.sizeof(t)}` is the FIELD TABLE, keyed by NAME. :102 builds `rows`
# from the CALLER'S kwargs, so the ROW ORDER is the kwargs order and not the
# struct order:
#     ops_qcom.py:197  cstruct(struct_kgsl_command_object, gpuaddr=..., size=..., flags=...)
#     ops_qcom.py:198  cstruct(struct_kgsl_gpu_command, cmdlist=..., cmdsize=..., numcmds=...,
#                                        context_id=...)
# `ops_cl`'s unit found `Sig`'s field names INVERTED and a correct computation
# looked wrong, so both directions are rows: `hq2_cstruct_*_order` is
# name-in-source-order and `hq2_cfield_*_at` / `_sz` are name -> offset/size.
#
# The two tables below are the qcom descriptors, MEASURED by calling
# `kgsl.struct_kgsl_command_object._real_fields_` and
# `kgsl.struct_kgsl_gpu_command._real_fields_` (hcq2-oracle.py `cstruct()`).
# ===========================================================================
def Q_COPY0() -> U32: 2
def slot_bytes(+bs: List<&2, P.E>, profile: Bool) -> U32: U32.mul(2, P.slot_words(bs, profile))
# THE PEER DEVICE'S SLOTS. `slots['NULL']` is the canonicalized device's slots
# and it has NO queues and NO calls, so it is `2 * (0 + 1 + 2*3)` when profiling
# and `2 * (0 + 1)` when not. It is the row that separates "slots per device"
# from "slots for the whole batch", and the peer exists ONLY because
# `Device.canonicalize('NULL:0')` is `'NULL'`.
def stl(+bs: List<&2, P.E>, dev: U32) -> U32: U32.mul(2, P.nq(bs, dev))
# `stamps` (:240) `(st := len(self.queues[devs[0]])+1+2*tag, st+1) if self.profile
# else ()`. THE `n -> n*2`: TWO stamps per call, starting AFTER the queues and the
# scheduler timeline, which is why the base is `nq + 1` and not `nq`.
def t_geom() -> IO(Unit):
  do IO<Unit>:
    # hcq2.py:232-240. THE `n -> n*2` EXPANSION and the slots formula. `py=`
    # from hcq2-oracle2.py's `hq2_geom*` rows, which CALL `BatchCtx.__post_init__`
    # and `ctx.slot` / `ctx.queue_signal` / `ctx.sched_timeline` / `ctx.stamps`.
    urow("hq2_geom_slots", slot_bytes(Ethree(), False{}))
    urow("hq2_geom_peerslots", peer_slot_bytes(False{}))
    urow("hq2_geom_p_slots", slot_bytes(Ethree(), True{}))
    urow("hq2_geom_p_peerslots", peer_slot_bytes(True{}))
    urow("hq2_geom_slot0", P.qsig(Ethree(), P.DEV_N0(), P.Q_COMPUTE()))
    urow("hq2_geom_slot1", P.qsig(Ethree(), P.DEV_N0(), Q_COPY0()))
    urow("hq2_geom_slot2", P.qsig(Ethree(), P.DEV_N0(), Q_COPY1()))
    urow("hq2_geom_slot3", stl(Ethree(), P.DEV_N0()))
    urow("hq2_geom_p_slot0", P.qsig(Ethree(), P.DEV_N0(), P.Q_COMPUTE()))
    urow("hq2_geom_p_stl", stl(Ethree(), P.DEV_N0()))
    # :237 `shrink((2*i, 2*i+2))` -- TWO u64 per slot, so the width is 2.
    lrow("hq2_geom_p_stamps0", stamps(Ethree(), 0, True{}))
    lrow("hq2_geom_p_stamps1", stamps(Ethree(), 1, True{}))
    lrow("hq2_geom_p_stamps2", stamps(Ethree(), 2, True{}))
    lrow("hq2_geom_p_stamps3", stamps(Ethree(), 3, True{}))
    urow("hq2_geom_p_qsig_c0", P.qsig(Ethree(), P.DEV_N0(), P.Q_COMPUTE()))
    urow("hq2_geom_p_qsig_c1", P.qsig(Ethree(), P.DEV_N0(), Q_COPY1()))
    urow("hq2_geom_stamps0_np", U32.from_nat(List.length(&2, U32, stamps(Ethree(), 0, False{}))))
    urow("hq2_geom_stamps0_p", U32.from_nat(List.length(&2, U32, stamps(Ethree(), 0, True{}))))
    # THE two arms differ by exactly two slots per call, and the peer device by
    # the same amount -- the peer has NO calls and still grows, which is the row
    # that separates `2*len(batch)` from a per-queue count.
    urow("hq2_geom_slots_delta", U32.sub(slot_bytes(Ethree(), True{}), slot_bytes(Ethree(), False{})))
    urow("hq2_geom_slots_delta_p", U32.sub(peer_slot_bytes(True{}), peer_slot_bytes(False{})))
    # `stamps` is `2*len(batch)` in the DELTA but only two per call in the list:
    # tag 3 is past the end of a three-call batch and still answers (10, 11).
    urow("hq2_geom_stamps3_first", head_of(stamps(Ethree(), 3, True{})))
    IO.pure(Unit, Unit{})
def t_name() -> IO(Unit):
  do IO<Unit>:
    # hcq2.py:63. `py=` values are CALLS to `hcq2.to_name`, from probe.py.
    srow("hq2_toname_submit", to_name3("submit", "NV", "COMPUTE:0"))
    srow("hq2_toname_cmdbuf", to_name2("cmdbuf", "COPY:1"))
    srow("hq2_toname_qcom", to_name3("submit", "QCOM", "COPY:0"))
    srow("hq2_toname_colon2", P.to_name(["KERNEL", "Foo:Bar"]))
    srow("hq2_toname_dblcolon", P.to_name(["a:b:c"]))
    srow("hq2_toname_single", P.to_name(["X"]))
    srow("hq2_toname_empty", P.to_name([""]))
    srow("hq2_toname_lower", to_name2("nv", "compute"))
    # THE order of the two halves: the colon fold is on the ORIGINAL case and
    # the lower is LAST, so this is `compute_0` and not `compute:0`.
    srow("hq2_toname_order", to_name2("COMPUTE", "0"))
    # THE empty tail is not a trailing separator, and a part that already
    # contains `_` is not split.
    srow("hq2_toname_under", to_name2("a_b", "c"))
    srow("hq2_toname_noseps", to_name2("a", "b"))
    # :69-70's `to_name("submit", devs[0].split(":")[0], queue.split(":")[0])` --
    # `make_submit`'s NAME, which is the custom-function name and the placeholder
    # tag. probe2.py, `submit_name`.
    srow("hq2_submit_name_null", to_name3("submit", P.dev_head("NULL:0"), P.dev_head("COPY:0")))
    srow("hq2_submit_name_amd", to_name3("submit", P.dev_head("AMD:0"), P.dev_head("COPY:3")))
    srow("hq2_submit_name_cuda", to_name3("submit", P.dev_head("CUDA:1"), P.dev_head("COMPUTE:0")))
    srow("hq2_submit_name_qcom_encdec", to_name3("submit", P.dev_head("QCOM:0"), P.dev_head("ENCDEC:0")))
    IO.pure(Unit, Unit{})
def prev_last(+bs: List<&2, P.E>) -> U32:
  P.prev_last_of(bs, U32.sub(U32.from_nat(List.length(&2, P.E, bs)), 1))
def f_ib() -> List<&2, P.Fld>:
  [P.Fld{0, "offset", 0, 8}, P.Fld{1, "gpuaddr", 8, 8}, P.Fld{2, "size", 16, 8},
   P.Fld{3, "flags", 24, 4}, P.Fld{4, "id", 28, 4}]
def fld_offs(+fs: List<&2, P.Fld>) -> List<&2, U32>:
  P.fld_offs.go(List.length(&2, P.Fld, fs), fs, Nil{})
def cstruct_cmd_rows_k() -> List<&2, U32>: [8, 4, 4, 4]
# the NAMES, in source order -- the direction that a renamed field breaks.
def t_allin() -> IO(Unit):
  do IO<Unit>:
    # hcq2.py:38. `py=` from probe.py `all_devices_in`.
    row("hq2_all_in_nv0", all_in(["NV:0"]))
    row("hq2_all_in_cuda12", all_in(["CUDA:1:2"]))
    row("hq2_all_in_cpu", Bool.not(all_in(["CPU"])))
    row("hq2_all_in_null", all_in(["NULL"]))
    row("hq2_all_in_nv_amd", all_in(["NV:0", "AMD"]))
    row("hq2_all_in_bare", all_in(["NV:0"]))
    row("hq2_all_in_empty", all_in(Nil{}))
    row("hq2_all_in_nvx", Bool.not(all_in(["NVX"])))
    row("hq2_all_in_metal1", all_in(["METAL:1"]))
    # NOT a membership: two devices BOTH in HCQ_DEVS. `hq2_all_in_cpu_nv` is
    # the negative of that and is the row that separates `<=` from `in`.
    row("hq2_all_in_cpu_nv", Bool.not(all_in(["CPU", "NV"])))
    # THE HEAD IS WHAT IS ASKED ABOUT: `AMD:0:1:2` is AMD and `NVX:0` is not NV.
    row("hq2_all_in_amd012", all_in(["AMD:0:1:2"]))
    row("hq2_all_in_nvx0", Bool.not(all_in(["NVX:0"])))
    IO.pure(Unit, Unit{})
def fld_sz(+fs: List<&2, P.Fld>, nm: String) -> U32:
  P.fld_sz.go(List.length(&2, P.Fld, fs), fs, nm, 0)
# `ctypes.sizeof(struct_t)` (:103, :104) -- the sum of the field sizes with the
# tail PADDED to the struct's alignment, which for both qcom descriptors is the
# last offset plus its own size.
# :102 `rows = [(flds[n][0], v.cast(flds[n][1]) if isinstance(v, UOp) else
# UOp.const(v, flds[n][1])) for n, v in fields.items()]` -- ONE ROW PER KWARG, in
# kwargs order, at the field's own offset and cast to the field's CDTYPE. The
# `ib` and `cmd` tables below are ops_qcom.py:197-198 verbatim, and
# `hq2_cstruct_ib_rows` / `hq2_cstruct_cmd_rows` are the `<off>:<itemsize>` list.
def cstruct_ib_rows() -> List<&2, U32>: [8, 16, 24]
def fld_cdts(+fs: List<&2, P.Fld>) -> List<&2, U32>:
  P.fld_cdt.go(List.length(&2, P.Fld, fs), fs, Nil{})
# the REVERSE direction of the field table: an OFFSET NAMES ITS FIELD. A struct
# that shifted a field would still answer every `fld_at` row and would move
# these, and the shift is what a mismatched autogen header looks like.
def fstr(+xs: List<&2, String>) -> String: String.drop(String.concat(P.fstr.go(List.length(&2, String, xs), xs, Nil{})), 1n)
def fld_names(+fs: List<&2, P.Fld>) -> List<&2, String>:
  P.fld_names.go(List.length(&2, P.Fld, fs), fs, Nil{})
def fld_sizeof(+fs: List<&2, P.Fld>) -> U32: P.fld_sizeof.go(List.length(&2, P.Fld, fs), fs, 0, 0)
def fld_name(+fs: List<&2, P.Fld>, at: U32) -> String:
  P.fld_name.go(List.length(&2, P.Fld, fs), fs, at, "")
# THE call goes between the two timestamps, :267's `waits + ts_ins[:1] + [call] +
# ts_ins[1:]`. Read off the STREAM rather than off `call_block`, so a port that
# emitted the call outside the stamps would fail here.
def fld_szs(+fs: List<&2, P.Fld>) -> List<&2, U32>:
  P.fld_szlist.go(List.length(&2, P.Fld, fs), fs, Nil{})
# :101 skips a field of size 0 (`if ctypes.sizeof(t)`), and :104's
# `buf[...]` blob is `bytes(ctypes.sizeof(struct_t))`. BOTH tables have no
# zero-length field, so `hq2_cstruct_*_nfields` and `hq2_cstruct_*_nreal` are the
# SAME number -- and that is the row which says the filter did nothing here
# rather than the row which says it is unnecessary.
def cstruct_cmd_rows() -> List<&2, U32>: [8, 16, 20, 56]
# AND THE CDTYPE EACH ROW IS CAST TO (hcq2.py:89's `v.cast(flds[n][1])`), which
# is `flds[n][1].itemsize`. A descriptor that carries the right offset and the
# wrong width writes the right bytes at the wrong scale.
def fld_real(+fs: List<&2, P.Fld>) -> U32: P.fld_real.go(List.length(&2, P.Fld, fs), fs, 0)
# :101 `CDTYPE[ctypes.sizeof(t)]` -- the field's dtYPE is the unsigned int of
# its SIZE, so `fld_cdts` IS `fld_szs` re-asked. The two lists being the same
# number is the claim; a port that invented a per-field dtype would disagree.
def t_cstruct() -> IO(Unit):
  do IO<Unit>:
    # hcq2.py:100-104. `py=` from hcq2-oracle.py `cstruct()`, which reads
    # `kgsl.struct_kgsl_command_object._real_fields_` and
    # `kgsl.struct_kgsl_gpu_command._real_fields_` THROUGH `hcq2.cstruct`'s own
    # `{n: (o, CDTYPE[ctypes.sizeof(t)])}` comprehension at :101.
    urow("hq2_cstruct_command_object_sizeof", fld_sizeof(f_ib()))
    urow("hq2_cstruct_command_object_nfields", fld_n(f_ib()))
    urow("hq2_cstruct_command_object_nreal", fld_real(f_ib()))
    srow("hq2_cstruct_command_object_order", fstr(fld_names(f_ib())))
    lrow("hq2_cstruct_command_object_offs", fld_offs(f_ib()))
    lrow("hq2_cstruct_command_object_szs", fld_szs(f_ib()))
    lrow("hq2_cstruct_command_object_cdt", fld_cdts(f_ib()))
    urow("hq2_cstruct_gpu_command_sizeof", fld_sizeof(f_cmd()))
    urow("hq2_cstruct_gpu_command_nfields", fld_n(f_cmd()))
    urow("hq2_cstruct_gpu_command_nreal", fld_real(f_cmd()))
    srow("hq2_cstruct_gpu_command_order", fstr(fld_names(f_cmd())))
    lrow("hq2_cstruct_gpu_command_offs", fld_offs(f_cmd()))
    lrow("hq2_cstruct_gpu_command_szs", fld_szs(f_cmd()))
    lrow("hq2_cstruct_gpu_command_cdt", fld_cdts(f_cmd()))
    # :106 `cfield` BOTH DIRECTIONS, name -> offset and name -> size. A field
    # renamed in the autogen header must move the bytes, and a port that looked
    # the offsets up by POSITION would not notice.
    urow("hq2_cfield_command_object_offset_at", fld_at(f_ib(), "offset"))
    urow("hq2_cfield_command_object_size_at", fld_at(f_ib(), "size"))
    urow("hq2_cfield_command_object_flags_at", fld_at(f_ib(), "flags"))
    urow("hq2_cfield_command_object_id_at", fld_at(f_ib(), "id"))
    urow("hq2_cfield_command_object_offset_sz", fld_sz(f_ib(), "offset"))
    urow("hq2_cfield_command_object_size_sz", fld_sz(f_ib(), "size"))
    urow("hq2_cfield_command_object_flags_sz", fld_sz(f_ib(), "flags"))
    urow("hq2_cfield_command_object_id_sz", fld_sz(f_ib(), "id"))
    urow("hq2_cfield_gpu_command_cmdlist_at", fld_at(f_cmd(), "cmdlist"))
    urow("hq2_cfield_gpu_command_cmdsize_at", fld_at(f_cmd(), "cmdsize"))
    urow("hq2_cfield_gpu_command_numcmds_at", fld_at(f_cmd(), "numcmds"))
    urow("hq2_cfield_gpu_command_context_id_at", fld_at(f_cmd(), "context_id"))
    urow("hq2_cfield_gpu_command_cmdlist_sz", fld_sz(f_cmd(), "cmdlist"))
    urow("hq2_cfield_gpu_command_cmdsize_sz", fld_sz(f_cmd(), "cmdsize"))
    urow("hq2_cfield_gpu_command_numcmds_sz", fld_sz(f_cmd(), "numcmds"))
    urow("hq2_cfield_gpu_command_context_id_sz", fld_sz(f_cmd(), "context_id"))
    # AND THE REVERSE: an offset names its field. `hq2_cfield_gpu_command_*` is
    # that pair, and it is the direction a shifted struct breaks first.
    srow("hq2_cfield_name_of_8_cmd", fld_name(f_cmd(), 8))
    srow("hq2_cfield_name_of_56_cmd", fld_name(f_cmd(), 56))
    srow("hq2_cfield_name_of_8_ib", fld_name(f_ib(), 8))
    srow("hq2_cfield_name_of_28_ib", fld_name(f_ib(), 28))
    srow("hq2_cfield_name_of_99_cmd", fld_name(f_cmd(), 99))
    # THE row order is the kwargs order (hcq2.py:102), and ops_qcom.py:197-198
    # are the only in-tree callers, so these two lists are the DESCRIPTOR.
    lrow("hq2_cstruct_ib_rows", cstruct_ib_rows())
    lrow("hq2_cstruct_cmd_rows", cstruct_cmd_rows())
    lrow("hq2_cstruct_cmd_rows_k", cstruct_cmd_rows_k())
    # AND the rows are the fields' OWN offsets, asked of the FIELD table rather
    # than of a constant, so a shifted struct moves them.
    row("hq2_cstruct_cmd_rows_are_fields",
      u32s_eq(cstruct_cmd_rows(), [fld_at(f_cmd(), "cmdlist"), fld_at(f_cmd(), "cmdsize"),
                                  fld_at(f_cmd(), "numcmds"), fld_at(f_cmd(), "context_id")]))
    row("hq2_cstruct_ib_rows_are_fields",
      u32s_eq(cstruct_ib_rows(), [fld_at(f_ib(), "gpuaddr"), fld_at(f_ib(), "size"),
                                 fld_at(f_ib(), "flags")]))
    row("hq2_cstruct_cmd_rows_k_are_fields",
      u32s_eq(cstruct_cmd_rows_k(), [fld_sz(f_cmd(), "cmdlist"), fld_sz(f_cmd(), "cmdsize"),
                                     fld_sz(f_cmd(), "numcmds"), fld_sz(f_cmd(), "context_id")]))
    # :101's `if ctypes.sizeof(t)` -- a zero-length field is SKIPPED -- and both
    # qcom descriptors have none, so nfields and nreal agree here. That is a
    # FIXTURE-WANTING ZERO: the row says the filter exists, not that it fires.
    row("hq2_cstruct_ib_nozero", U32.is_eq(fld_n(f_ib()), fld_real(f_ib())))
    row("hq2_cstruct_cmd_nozero", U32.is_eq(fld_n(f_cmd()), fld_real(f_cmd())))
    IO.pure(Unit, Unit{})
# --- the batch GEOMETRY readers the gate needs.
def call_between_stamps(+bs: List<&2, P.E>, +profile: Bool) -> Bool:
  P.call_between_stamps.go(List.length(&2, P.Ins, P.queues_of(bs, profile)), P.queues_of(bs, profile),
                         False{}, False{})
def Efifo() -> List<&2, P.E>: [P.E{1, 1, 1, 2}, P.E{1, 1, 3, 4}]
def ins_str(+xs: List<&2, P.Ins>) -> String:
  String.drop(String.concat(P.ins_str.go(List.length(&2, P.Ins, xs), xs, Nil{})), 1n)
def t_batch_one(+bs: List<&2, P.E>, +nm: String) -> IO(Unit):
  do IO<Unit>:
    urow(String.concat(["hq2_b", nm, "_npairs"]), P.npairs(bs))
    urow(String.concat(["hq2_b", nm, "_nq"]), P.nq(bs, P.DEV_N0()))
    urow(String.concat(["hq2_b", nm, "_slots"]), slot_bytes(bs, False{}))
    srow(String.concat(["hq2_b", nm, "_epi"]), epiname(bs, P.DEV_N0()))
    lrow(String.concat(["hq2_b", nm, "_sig_tags"]), P.sig_tags(bs))
    urow(String.concat(["hq2_b", nm, "_prevcnt"]), prev_none_n(bs))
    urow(String.concat(["hq2_b", nm, "_prevlast"]), prev_last(bs))
    urow(String.concat(["hq2_b", nm, "_npeers"]), 1)
    urow(String.concat(["hq2_b", nm, "_stl"]), stl(bs, P.DEV_N0()))
    srow(String.concat(["hq2_b", nm, "_start0"]), ins_str(P.start_ins(P.DEV_N0())))
    urow(String.concat(["hq2_b", nm, "_nqueues"]), U32.add(P.npairs(bs), 1))
    urow(String.concat(["hq2_b", nm, "_nwait0"]), ins_n(P.waits(bs, 0)))
    urow(String.concat(["hq2_b", nm, "_nwait1"]), ins_n(P.waits(bs, 1)))
    urow(String.concat(["hq2_b", nm, "_nwait2"]), ins_n(P.waits(bs, 2)))
    urow(String.concat(["hq2_b", nm, "_qsig0"]), P.qsig(bs, P.DEV_N0(), P.E.q(P.elem(bs, 0))))
    urow(String.concat(["hq2_b", nm, "_qsig1"]), P.qsig(bs, P.DEV_N0(), P.E.q(P.elem(bs, 1))))
    urow(String.concat(["hq2_b", nm, "_qsig2"]), P.qsig(bs, P.DEV_N0(), P.E.q(P.elem(bs, 2))))
    # THE STREAM. `hq2_b*_q_*` is compared against CPython's OWN sequence of
    # `u.op is Ops.INS` + `u.arg[0]` names, so a swapped pair moves the row.
    srow(String.concat(["hq2_b", nm, "_full"]), ins_str(P.queues_of(bs, False{})))
    srow(String.concat(["hq2_b", nm, "_full_p"]), ins_str(P.queues_of(bs, True{})))
    lrow(String.concat(["hq2_b", nm, "_stamps_p0"]), stamps(bs, 0, True{}))
    lrow(String.concat(["hq2_b", nm, "_stamps_p1"]), stamps(bs, 1, True{}))
    lrow(String.concat(["hq2_b", nm, "_stamps_p2"]), stamps(bs, 2, True{}))
    urow(String.concat(["hq2_b", nm, "_slots_p"]), slot_bytes(bs, True{}))
    urow(String.concat(["hq2_b", nm, "_nwait1_p"]), ins_n(P.waits(bs, 1)))
    # THE bump is a `store` AND only the epilogue has one -- :278 against :271.
    # `three` and `two` both answer one bump over four and two queues, so the
    # bump is per DEVICE and not per queue.
    urow(String.concat(["hq2_b", nm, "_bumps"]), P.count_kind(P.queues_of(bs, False{}), P.I_BUMP()))
    urow(String.concat(["hq2_b", nm, "_stores"]), P.count_kind(P.queues_of(bs, False{}), P.I_STORE()))
    urow(String.concat(["hq2_b", nm, "_ts_p"]), P.count_kind(P.queues_of(bs, True{}), P.I_TIMESTAMP()))
    urow(String.concat(["hq2_b", nm, "_calls"]), P.count_kind(P.queues_of(bs, False{}), P.I_CALL()))
    IO.pure(Unit, Unit{})
# the four keys, and `hc2_cdtype_len` is the COUNT row.
def Erevis() -> List<&2, P.E>: [P.E{1, 1, 1, 2}, P.E{1, 1, 3, 4}, P.E{1, 1, 2, 5}]
# ===========================================================================
# `ctx.queues` (:224) -- the queue list PER DEVICE, in FIRST-USE order, because
# `if q not in self.queues.setdefault(devs[0], []): append(q)`. The ORDER is the
# claim: `qsig` numbers the queues by it and the epilogue walks it.
# ===========================================================================
def t_batch() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_batch_one(Ethree(), "three")
    b : Unit <- t_batch_one(Etwo(), "two")
    c : Unit <- t_batch_one(Efifo(), "fifo")
    d : Unit <- t_batch_one(Ecopyq(), "copyq")
    e : Unit <- t_batch_one(Erevis(), "revis")
    # THE COUNTS NO SINGLE FIXTURE SEES. `three` has three queues and `revis` has
    # three calls on ONE, so `nq` answers 3 and 1 -- and a port that counted CALLS
    # would answer 3 and 3. `hq2_b_revis_nq` is that row.
    urow("hq2_b_revis_nq", P.nq(Erevis(), P.DEV_N0()))
    urow("hq2_b_three_nq", P.nq(Ethree(), P.DEV_N0()))
    urow("hq2_b_two_nq", P.nq(Etwo(), P.DEV_N0()))
    # `two` VERSUS `fifo`: SAME queue, overlapping versus disjoint buffers, so the
    # second call's wait count is 1 and 0 on the same shape. Without BOTH, a port
    # that waited for every earlier call would pass `two` and fail `fifo`.
    urow("hq2_b_two_nwait1", ins_n(P.waits(Etwo(), 1)))
    urow("hq2_b_fifo_nwait1", ins_n(P.waits(Efifo(), 1)))
    urow("hq2_b_revis_nwait2", ins_n(P.waits(Erevis(), 2)))
    urow("hq2_b_three_nwait2", ins_n(P.waits(Ethree(), 2)))
    # THE call goes between the two timestamps -- :267's `waits + ts[:1] + [call]
    # + ts[1:]` -- read off the STREAM rather than off `call_block`.
    row("hq2_b_three_call_inside_stamps", call_between_stamps(Ethree(), True{}))
    row("hq2_b_revis_call_inside_stamps", call_between_stamps(Erevis(), True{}))
    row("hq2_b_three_no_stamps_unprofiled", Bool.not(has_kind(P.queues_of(Ethree(), False{}), P.I_TIMESTAMP())))
    IO.pure(Unit, Unit{})
# ===========================================================================
# `bufferize_buf` -- hcq2.py:483-494. THE CONSUMER of the link mechanism.
#
# Upstream, in full (`tinygrad/runtime/support/hcq2.py:483-494` at the pin
# `5c2bf39d6c4b`):
#
#   def bufferize_buf(ctx:LinkCtx, b:UOp) -> UOp:
#     if b.arg.name is None: return UOp.new_buffer(b.device, b.max_numel(), b.dtype)
#     dev, spec = Device[b.device], b.arg.spec or BufferSpec(cpu_access=True)
#
#     owned = Compiled.link_bufs.get(b.arg.name, Compiled.link_bufs.get(to_name(b.device, b.arg.name)))
#     if owned is not None: r = owned if isinstance(owned, Buffer) else owned(b)
#     elif (r:=dev.link_buffer(b)) is not None: pass
#     elif not ctx.use_rt: r = Buffer(dev.device, max(b.max_numel(), 1) * b.dtype.itemsize, options=spec, preallocate=True)
#     else: r = dev.rt_buffer(spec).view(b.nbytes(), dev.rt_allocator(spec).alloc(max(b.nbytes(), 1), alignment=256)).ensure_allocated()
#
#     return UOp.from_buffer(r, b.dtype, HCQ_RUNTIME_DEV.device)
#
# WHAT IT IS: THE LINK. It answers ONE question -- which PHYSICAL buffer does
# this logical ALLOC belong to -- and the answer is a FOUR-WAY, in upstream's
# order:
#
#   0  the alloc has NO name           a FRESH buffer, and it is NOT linked
#   1  the registry, PLAIN name        `link_bufs[b.arg.name]`
#   2  the registry, DEVICE-SCOPED     `link_bufs[to_name(b.device, b.arg.name)]`
#   3  the device's `link_buffer`      `dev.link_buffer(b)`
#   4  nothing                         allocate
#
# THE RESOLUTION IS ALREADY PORTED -- `device.bend`'s `link_resolve`
# (device.bend:1209) answers exactly that four-way, with the same levels and
# the same Buffer-vs-CALLABLE discriminator. WHAT was missing is the consumer:
# upstream's `bufferize_buf` is the ONLY caller of `link_bufs` and
# `link_buffer` (device.bend:1019 symbol=dev_id measures that), so until this existed the
# port carried a mechanism with nothing on the other end of it.
#
# TWO facts the mechanism alone does not carry, AND they are the point:
#
#   1. A linked BUFFER'S SIZE IS the registry'S, NOT the alloc'S. Upstream
#      never resizes a registered buffer to fit the alloc: the `owned` branch
#      hands the registry's buffer straight to `UOp.from_buffer`, and there is
#      no `max_numel` anywhere on that path. A port that sized the result from
#      the alloc would answer 16 where upstream answers 64.
#   2. THE DEVICE OF THE RESULT. `UOp.from_buffer(r, b.dtype,
#      HCQ_RUNTIME_DEV.device)` RE-PLACES a linked buffer on the runtime
#      device, while the unnamed path's `UOp.new_buffer(b.device, ...)` keeps
#      the alloc's own device.
#
# `ctx.use_rt` IS not ported, AND the reason is measured: it chooses the
# ALLOCATION MECHANISM -- a runtime allocator's view or a plain preallocated
# `Buffer` -- and the two agree on the byte count for every alloc
# `UOp.from_buffer` accepts (`assert opaque.nbytes % dtype.itemsize == 0`),
# while the runtime allocator itself is a WALL (`device.py`'s `rt_buffer` /
# `rt_allocator`). So the port allocates `max(max_numel, 1) * itemsize` bytes,
# the size both paths agree on.
#
# THE `+` ON the parameters is not noise. A `U32` is AFFINE and a `Data`
# record is LINEAR, so a value used twice is "consumed more than once" unless
# it is spelled `+` -- the same rule `device.bend` and `helpers.bend` obey.
# AND A DEF MUST BE DEFINED BEFORE IT IS USED: a name that is not yet defined
# resolves to an UNFILLED law, and live code cannot use one.
# ===========================================================================
# THE ALLOC. Upstream's `b` is a UOp and the function reads five things off
# it: `b.arg.name` (the name, or None), `b.device`, `b.max_numel()`, `b.dtype`
# and `b.arg.spec`. `has_name` is a `Bool` and not a `Maybe`, because a `Data`
# record may not hold a `Maybe` field.
#
# `dev` is the device STRING and `dev_ix` the device INDEX, and they are two
# fields because the registry lookup folds the STRING
# (`to_name(b.device, b.arg.name)`) while a buffer the port ALLOCATES lands in
# an arena slot, and a slot carries an INDEX (`device.bend:629 symbol=Bn.dev`).
# `b.arg.spec` IS NOT PORTED: upstream reads `b.arg.spec or
# BufferSpec(cpu_access=True)` and only the allocation path uses it, and no
# alloc in this port names a spec of its own.
# THE ANSWER. `level` is upstream's four-way, `kind` is upstream's
# `isinstance(owned, Buffer)` discriminator (0 a Buffer, 1 a CALLABLE that was
# called with the alloc, 2 neither), `buf` is the ARENA SLOT of the buffer
# that won, `nb` is ITS byte count, `dev` is the device the RESULT is PLACED
# on, and `ar` is the arena the result lives in -- GROWN when the allocation
# path made a buffer, because upstream's `Buffer(...)` creates one and a
# created Buffer is a slot.
# `HCQ_RUNTIME_DEV.device` (tinygrad/helpers.py:249). NOT "CPU:LLVM":
# `_DEV("HCQ_RUNTIME_DEV", "CPU:LLVM")` parses a `Target`, and a Target's
# `.device` is the device part alone. MEASURED: the CPython oracle prints
# `bz_dev_plain=CPU`.
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_consts()
    b : Unit <- t_name()
    c : Unit <- t_allin()
    d : Unit <- t_layout()
    e : Unit <- t_pack()
    f : Unit <- t_cstruct()
    g : Unit <- t_geom()
    h : Unit <- t_batch()
    i : Unit <- t_bufferize()
    IO.print("hq2-done=1")
# | # | the edit | rows moved | what it is testing |
# | --- | --- | --- | --- |
# | M1 | to_name.norm: drop the lower-case | 10 |
# | M2 | to_name.go: no `_` between parts | 360  -- GATE DIED |
# | M3 | to_name.go: reverse the accumulator | 0 |
# | M4 | all_in: `or` becomes `and` | 4 |
# | M5 | cdtype_of: 2 becomes 4 | 2 |
# | M6 | layout: the base offset is dropped | 15 |
# | M7 | layout: the itemsize is dropped from Arg.k | 7 |
# | M8 | pack.step: emit the pad even at gap 0 | 12 |
# | M9 | pack.trail: drop the trailing pad | 8 |
# | M10 | pack.trail: no refusal on a short size | 2 |
# | M11 | slot_bytes: drop the leading `2 *` | 13 |
# | M12 | slot_words: the profile arm adds 1 per call, not 2 | 7 |
# | M13 | stamp_n: `nq + 1` becomes `nq` | 20 |
# | M14 | qsig: the slot index is not doubled | 6 |
# | M15 | stl: the timeline slot is at `nq`, not `2*nq` | 4 |
# | M16 | epi: the two arms are swapped | 0 |
# | M17 | sig_tags: FIRST-WINS instead of LAST-WINS | 17 |
# | M18 | sig_tags: no queue signals | 20 |
# | M19 | call_block: the CALL goes BEFORE the pre-timestamp | 5 |
# | M20 | start_ins: the BARRIER is dropped | 15 |
# | M21 | start_n: the peer timeline wait is dropped | 15 |
# | M22 | epi_waits_n: the peer-queue waits are dropped | 10 |
# | M23 | overlaps: a write no longer waits for a prior READ | 10 |
# | M24 | prodq: the FIFO filter is dropped (every dep is its own queue) | 0 |
# | M25 | staging_chunk: one divide instead of two | 5 |
# | M26 | fld_at: the field lookup is by POSITION, not by NAME | 360  -- GATE DIED |
# | M27 | fld_names: drop every name | 2 |
# | M28 | cstruct_cmd_rows: context_id's offset is wrong | 2 |
# | M29 | fstr: no separator between field names | 2 |
# | M30 | control: a comment-only edit | 0 |

# THE two that died are compile errors, NOT answers. `M2` removes one `)` and
# `M26` swaps a name test for a counter test that does not typecheck the same way;
# both are reported as "the gate produced nothing" rather than as "0 rows", which
# is the distinction the harness exists to keep.
#
# ---------------------------------------------------------------------------
# WHAT this gate still does not see. Three are BLIND spots -- a mutation that moved
# nothing -- and each is a `0` that is a REQUEST FOR A FIXTURE or an honestly
# unfixable pair, never a coverage claim.
#
# 1. M3 moved nothing and that is a harness artefact, NOT a result. The edit
#    wraps the `to_name` accumulator in `List.reverse` and every `to_name` row is
#    unchanged. `to_name("submit","NV","COMPUTE:0")` is `submit_nv_compute_0`, so
#    reversing a three-element accumulator MUST change it. Either the edit did not
#    reach the code it names, or `List.reverse` there is an identity, and this
#    report does not claim to know which. IT IS LEFT IN THE TABLE AS A `0` BECAUSE
#    A `0` THAT IS NOT UNDERSTOOD IS STILL A `0`.
#
# 2. M16 -- `epilogue_queue`'s TWO arms are not separable with any fixture. :235 is
#    `"COMPUTE:0" if len(self.queues[dev]) != 1 else self.queues[dev][0]`, so the
#    two arms differ only when the device's queue list does NOT start at
#    `COMPUTE:0`. All five fixtures open with a `COMPUTE:0` call, so `qfirst` and
#    `Q_COMPUTE` are the same number everywhere and swapping them is an
#    EQUIVALENCE. THE fixture that separates them is a batch whose first call is
#    ON `COPY:0`, and it needs a device with no COMPUTE queue at all -- which a
#    NULL batch cannot express because `sched_batches` (:321) always puts a
#    `PROGRAM` call on `COMPUTE:0`. REPORTED, NOT CLOSED.
#
# 3. M24 -- `latest`'s PER-QUEUE `max` IS NEVER EXERCISED. :246 keeps
#    `max(latest.get((d, q), 0), t)` per PRODUCER QUEUE, so the `max` fires only
#    when TWO deps of one call come from the SAME queue. That needs two earlier
#    calls on one queue writing overlapping buffers. The same-queue FIFO filter
#    (:246's `(d, q) != (device, queue)`) means those deps are FILTERED OUT before
#    `max` ever sees them, so under this port's model NO fixture can reach the
#    `max`. `prodq` collapsing to a plain append is therefore an EQUIVALENCE here.
#    IT is the same shape as the `pc.find` BLIND spot ops_webgpu.bend reported:
#    a model whose answer is `len` on a miss and an index below it on a hit makes
#    the two predicates indistinguishable, so no fixture separates them. REPORTED.
#
# 4. THE PER-QUEUE LENGTHS. `hq2_b*_full` is the CONCATENATION of the four queue
#    streams, which pins the total ORDER and every slot index but does not say
#    where one queue ends and the next begins. CPython's per-queue rows
#    (`hq2_b*_q_NULL0_COMPUTE0`) do. An implementation that moved the boundary --
#    attributing one queue's epilogue to the next -- would print the same
#    concatenation. `hq2_b*_nqueues` and `hq2_b*_bumps` see the COUNT and not the
#    boundary.
#
# 5. THE overlap model is total-OVERLAP only. `DepsTracker.access_resources` (:182)
#    works in `(base, lane, offset, end)` ranges so a suballocated buffer that
#    overlaps only partly still waits. This port reduces a call to TWO WHOLE
#    buffers, so `overlaps` is an equality test and a partial overlap is not
#    representable. `E`'s `w`/`r` are buffer IDS and not ranges; giving them an
#    offset and a length is the change that would close this, and it is the same
#    machinery `device.bend`'s Buffer slots already have.
#
# 6. `(dev, q) in peers` IS vacuous in every fixture. See THE second disjunct is
#    VACUOUS: under DEV=NULL every queue of a non-empty batch has a peer, so
#    `signs` is always True and `hq2_b*_sig_tags` pins the LAST-WINS half alone.
#
# 7. `_finalize_batch`'s METADATA. `final_devs`, `final_kerns`, `final_nargs`,
#    `final_table`, `final_tag`, `final_name`, `final_nsubs` and `final_skipwait`
#    are CPython rows with no counterpart here: they read `KernelInfo`,
#    `Device[d].pm_batch` and `HCQInfo`, which is the arena wall.
#
# 8. `HWQueue.q` AND `HWQueue.encode` ARE ported as a plan and not as a gate row.
#    `hcq2.py:355-366`'s word ladder (`W_INT` is always FOUR bytes, `W_BINARY` is
#    appended VERBATIM, anything else is a patch plus zero bytes) is in this file
#    as `q`/`loop_*`, and its CPython counterparts are in
#    `.agents/slop/hcq2-probe2.py`. They are NOT in the 360-row gate, because the
#    trace that would carry them (`Tr`) is the `HWQueue.submit` raise and the qcom
#    FFI, and a trace whose only rows are a `NotImplementedError` measures
#    nothing. The CPython blob hex for each word shape is in the probe; a port
#    that transposed the little-endian byte order would agree with nothing in
#    this file. THAT is the gap and it is the largest one.
#
#    THIS item also carried three names that were never defs, and it is worth
#    naming because the mutation table it points at does not have them either:
#    `pad128`, `rt_patch` and `dword_at` had 2 occurrences each -- this item and
#    the `bufferize_cmdbuf` row -- and ZERO defs, zero rows and zero mutations.
#    So "and in the mutation table" was false. What is true is narrower and is
#    what the row above now says: the 128-byte pad, the `o % 4 == 0` rt-patch
#    filter and the `+ 4 * k` dword stride all still exist UPSTREAM, inside
#    `encode_cmdbuf` (:449, :438, :441), and none of the three is ported as a
#    def here -- they were renamed out of the row by `bdddaad21` and were never
#    written. Three claims removed, and the gap they were hiding is GAP 8, which
#    is above and is still open.

