# gates/amdev-gate.bend -- the gate driver for `tinybendygrad/runtime/support/am/amdev.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/runtime/support/am/amdev.bend as P

import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/runtime/support/am/amdev.bend as Q
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, Q.v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(Q.v)]))
def srow(nm: String, Q.v: String) -> IO(Unit): IO.print(String.concat([nm, "=", Q.v]))

# A `|`-JOIN, written out because Bend has no list comprehension. The separator
# is emitted BEFORE each element, so a one-element list reads `|x` -- which is
# what the oracle's `"|" + join(...)` produces, and the two agree by construction.
def jgo(n: Nat, +xs: List<&2, U32>, +sep: String, acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+m:
      match xs:
        case Nil{}: acc
        case x <> t: jgo(m, t, sep, String.concat([acc, String.concat([sep, U32.show(x)])]))

def jgs(n: Nat, +xs: List<&2, String>, +sep: String, acc: String) -> String:
  match n:
    case 0n: acc
    case 1n+m:
      match xs:
        case Nil{}: acc
        case x <> t: jgs(m, t, sep, String.concat([acc, String.concat([sep, x])]))

def jrow(nm: String, +xs: List<&2, U32>) -> IO(Unit): srow(nm, jgo(List.length(&2, U32, xs), xs, "|", ""))

# ONE ROW PER ELEMENT, for every list where WHICH element is wrong matters more
# than how many there are. A join hides a missing element inside a length change.
# A Nat has no `show`, so the element index is rendered through the same helper
# `aspm.at` uses -- one conversion for the whole file.
def aspm.index_str(i: Nat) -> String: U32.show(U32.from_nat(i))

def amaprow.go(n: Nat, +nm: String, +xs: List<&2, U32>, +i: Nat) -> IO(Unit):
  match n:
    case 0n: IO.print("")
    case 1n+m:
      match xs:
        case Nil{}: IO.print("")
        case x <> t:
          do IO<Unit>:
            urow(String.concat([nm, "_", aspm.index_str(i)]), x)
            amaprow.go(m, nm, t, Nat.add(i, 1n))

def amaprow(nm: String, +xs: List<&2, U32>) -> IO(Unit):
  amaprow.go(List.length(&2, U32, xs), nm, xs, 0n)

def jrow_s(nm: String, +xs: List<&2, String>) -> IO(Unit): srow(nm, jgs(List.length(&2, String, xs), xs, "|", ""))

# the nine structs the gate reads, one def each, so the dispatch is a table and
# not a `match` on a computed value. The key is the struct's index and the slot is
# its field's, so every field is its own ROW: an inverted list then shows up as
# two rows disagreeing rather than as a count that happens to match.
def gate.pick(xs: List<&2, String>, slot: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, xs, slot), "?")

def gate.sa(slot: Nat) -> String: gate.pick(P.sf.common_firmware_header.names(), slot)
def gate.sb(slot: Nat) -> String: gate.pick(P.sf.binary_header.names(), slot)
def gate.sc(slot: Nat) -> String: gate.pick(P.sf.ip_discovery_header.names(), slot)
def gate.sd(slot: Nat) -> String: gate.pick(P.sf.die_header.names(), slot)
def gate.se(slot: Nat) -> String: gate.pick(P.sf.ip_v4.names(), slot)
def gate.sfh(slot: Nat) -> String: gate.pick(P.sf.gc_info_v1_0.names(), slot)
def gate.sg(slot: Nat) -> String: gate.pick(P.sf.psp_fw_bin_desc.names(), slot)
def gate.sh(slot: Nat) -> String: gate.pick(P.sf.smc_soft_pptable_entry.names(), slot)
def gate.si(slot: Nat) -> String: gate.pick(P.sf.psp_firmware_v2_1.names(), slot)

def gate.field(key: Nat, slot: Nat) -> String:
  match key:
    case 0n: gate.sa(slot)
    case 1n: gate.sb(slot)
    case 2n: gate.sc(slot)
    case 3n: gate.sd(slot)
    case 4n: gate.se(slot)
    case 5n: gate.sfh(slot)
    case 6n: gate.sg(slot)
    case 7n: gate.sh(slot)
    case _: gate.si(slot)

# ONE FIELD NAME of one struct. The rows are emitted in DECLARATION order, so a
# transposition in the table moves the two rows that swapped and nothing else --
# which is the point of gating names and not counts.
def sfrow(nm: String, key: Nat, slot: Nat) -> IO(Unit):
  srow(nm, gate.field(key, slot))

# the trace rows. Each is a count plus the ordered addresses and the ordered
# VALUES, never a boolean: an all-True gate on a sequence says nothing, and
# `ops_webgpu`'s M23 measured that its matcher had been answering True to
# everything.
#
# THE `amd_*` PREFIX SAYS WHICH amdev.py CALL each trace is. There are eight of
# them here, and every one was produced by amdev.py's own method over the
# matching fixture.

# ONE FIXTURE, WALKED ONCE, because `Q.aspm.walk` takes five arguments and writing
# them out at every call site is how a row ends up walking a DIFFERENT fixture
# than the row beside it.
def aspm_fx.link() -> P.Tr: Q.aspm.walk(Q.aspm_fx.link_first(), Q.aspm_fx.link_links(), Q.aspm_fx.link_nexts(), Q.aspm_fx.lnkctl(), P.Tr.of())
def aspm_fx.chain() -> P.Tr: Q.aspm.walk(Q.aspm_fx.chain_first(), Q.aspm_fx.chain_links(), Q.aspm_fx.chain_nexts(), Q.aspm_fx.lnkctl(), P.Tr.of())
def aspm_fx.zero() -> P.Tr: Q.aspm.walk(Q.aspm_fx.zero_first(), Q.aspm_fx.zero_links(), Q.aspm_fx.zero_nexts(), Q.aspm_fx.lnkctl(), P.Tr.of())
def aspm_fx.loop() -> P.Tr: Q.aspm.walk(Q.aspm_fx.loop_first(), Q.aspm_fx.loop_links(), Q.aspm_fx.loop_nexts(), Q.aspm_fx.lnkctl(), P.Tr.of())

def t_aspm() -> IO(Unit):
  do IO<Unit>:
    urow("ama_aspm_link_n", P.Tr.n(Q.aspm.walk(Q.aspm_fx.link_first(), Q.aspm_fx.link_links(), Q.aspm_fx.link_nexts(), Q.aspm_fx.lnkctl(), P.Tr.of())))
    urow("ama_aspm_link_rd_n", P.Tr.count(P.OP_CFG_RD(), P.Tr.calls(Q.aspm.walk(Q.aspm_fx.link_first(), Q.aspm_fx.link_links(), Q.aspm_fx.link_nexts(), Q.aspm_fx.lnkctl(), P.Tr.of()))))
    urow("ama_aspm_link_wr_n", P.Tr.count(P.OP_CFG_WR(), P.Tr.calls(Q.aspm.walk(Q.aspm_fx.link_first(), Q.aspm_fx.link_links(), Q.aspm_fx.link_nexts(), Q.aspm_fx.lnkctl(), P.Tr.of()))))
    amaprow("ama_aspm_link_rd", P.Tr.addrs(P.OP_CFG_RD(), P.Tr.calls(Q.aspm.walk(Q.aspm_fx.link_first(), Q.aspm_fx.link_links(), Q.aspm_fx.link_nexts(), Q.aspm_fx.lnkctl(), P.Tr.of()))))
    amaprow("ama_aspm_link_sz", P.Tr.sizes(P.OP_CFG_RD(), P.Tr.calls(Q.aspm.walk(Q.aspm_fx.link_first(), Q.aspm_fx.link_links(), Q.aspm_fx.link_nexts(), Q.aspm_fx.lnkctl(), P.Tr.of()))))
    amaprow("ama_aspm_link_val", P.Tr.vals(P.OP_CFG_WR(), P.Tr.calls(Q.aspm.walk(Q.aspm_fx.link_first(), Q.aspm_fx.link_links(), Q.aspm_fx.link_nexts(), Q.aspm_fx.lnkctl(), P.Tr.of()))))
    amaprow("ama_aspm_link_wr", P.Tr.addrs(P.OP_CFG_WR(), P.Tr.calls(Q.aspm.walk(Q.aspm_fx.link_first(), Q.aspm_fx.link_links(), Q.aspm_fx.link_nexts(), Q.aspm_fx.lnkctl(), P.Tr.of()))))
    amaprow("ama_aspm_chain_rd", P.Tr.addrs(P.OP_CFG_RD(), P.Tr.calls(aspm_fx.chain())))
    urow("ama_aspm_chain_n", P.Tr.n(aspm_fx.chain()))
    urow("ama_aspm_chain_wr_n", P.Tr.count(P.OP_CFG_WR(), P.Tr.calls(aspm_fx.chain())))
    urow("ama_aspm_zero_n", P.Tr.n(aspm_fx.zero()))
    amaprow("ama_aspm_zero_rd", P.Tr.addrs(P.OP_CFG_RD(), P.Tr.calls(aspm_fx.zero())))
    urow("ama_aspm_loop_n", P.Tr.n(aspm_fx.loop()))
    amaprow("ama_aspm_loop_rd", P.Tr.addrs(P.OP_CFG_RD(), P.Tr.calls(aspm_fx.loop())))

# The fixture's short name is `init`/`fini`/`norw`/`req0`/`reqff`, and the rows
# are `amb_<short>_<what>`. `mbtag` is called with the COUNT row's own name so the
# two cannot drift apart.
def mbtag(+cnt: String, +nm: String, +req: U32, +wait_ready: Bool) -> IO(Unit):
  do IO<Unit>:
    urow(cnt, P.Tr.n(P.mb.request(req, wait_ready, P.Tr.of())))
    jrow(String.concat(["amb_", nm, "_mb_wr"]), P.Tr.addrs(P.OP_MB_WR(), P.Tr.calls(P.mb.request(req, wait_ready, P.Tr.of()))))
    jrow(String.concat(["amb_", nm, "_mb_val"]), P.Tr.vals(P.OP_MB_WR(), P.Tr.calls(P.mb.request(req, wait_ready, P.Tr.of()))))
    jrow(String.concat(["amb_", nm, "_mm_addr"]), P.Tr.addrs(P.OP_MM_WR(), P.Tr.calls(P.mb.request(req, wait_ready, P.Tr.of()))))
    jrow(String.concat(["amb_", nm, "_mm_val"]), P.Tr.vals(P.OP_MM_WR(), P.Tr.calls(P.mb.request(req, wait_ready, P.Tr.of()))))
    jrow(String.concat(["amb_", nm, "_wait_val"]), P.Tr.addrs(P.OP_WAIT(), P.Tr.calls(P.mb.request(req, wait_ready, P.Tr.of()))))
    jrow(String.concat(["amb_", nm, "_wait_tmo"]), P.Tr.sizes(P.OP_WAIT(), P.Tr.calls(P.mb.request(req, wait_ready, P.Tr.of()))))

def t_mailbox() -> IO(Unit):
  do IO<Unit>:
    mbtag("amb_init_n", "init", 1, True{})
    mbtag("amb_fini_n", "fini", 3, True{})
    mbtag("amb_norw_n", "norw", 1, False{})
    mbtag("amb_req0_n", "req0", 0, True{})
    mbtag("amb_reqff_n", "reqff", 255, True{})
    urow("amb_lease1", P.mb.lease(1))
    urow("amb_lease3", P.mb.lease(3))
    urow("amb_lease0", P.mb.lease(0))
    urow("amb_leaseff", P.mb.lease(255))
    urow("amb_first", P.mb.first())
    urow("amb_last", P.mb.last())
    urow("amb_word1", P.mb.word_of(1, P.mb.first()))
    urow("amb_word1b", P.mb.word_of(1, P.mb.last()))
    urow("amb_word3b", P.mb.word_of(3, P.mb.last()))

def t_readvram() -> IO(Unit):
  do IO<Unit>:
    urow("amv_rv_n", P.Tr.n(P.rv.read(4096, 16, P.Tr.of())))
    jrow("amv_rv_wreg", P.Tr.addrs(P.OP_WREG(), P.Tr.calls(P.rv.read(4096, 16, P.Tr.of()))))
    jrow("amv_rv_val", P.Tr.vals(P.OP_WREG(), P.Tr.calls(P.rv.read(4096, 16, P.Tr.of()))))
    jrow("amv_rv_rreg", P.Tr.addrs(P.OP_RREG(), P.Tr.calls(P.rv.read(4096, 16, P.Tr.of()))))
    urow("amv_rv_hi0", P.rv.hi(4096))
    urow("amv_rv_lo0", P.rv.lo(4096))
    urow("amv_rv_hi1", P.rv.hi(4100))
    urow("amv_rv_lo1", P.rv.lo(4100))
    urow("amv_rv_hi4", P.rv.hi(2147483648))
    urow("amv_rv_lo4", P.rv.lo(2147483648))
    # the MISALIGNED window refuses, so the trace is EMPTY and `refused` is set:
    # `addr % 4 == 0 and size % 4 == 0` (:348) runs before any word is read.
    urow("amv_rv_bad_n", P.Tr.n(P.rv.read(4095, 16, P.Tr.of())))
    row("amv_rv_bad_refused", P.Tr.refused(P.rv.read(4095, 16, P.Tr.of())))
    urow("amv_rv_bad2_n", P.Tr.n(P.rv.read(4096, 15, P.Tr.of())))
    row("amv_rv_bad2_refused", P.Tr.refused(P.rv.read(4096, 15, P.Tr.of())))
    row("amv_rv_ok_refused", P.Tr.refused(P.rv.read(4096, 16, P.Tr.of())))

def t_pcie() -> IO(Unit):
  do IO<Unit>:
    urow("ampc_hi0", P.pc.addr_hi(4660, 0))
    urow("ampc_hi1", P.pc.addr_hi(4660, 1))
    urow("ampc_hi2", P.pc.addr_hi(4660, 2))
    urow("ampc_hi3", P.pc.addr_hi(4660, 3))
    urow("ampc_hi4", P.pc.addr_hi(4660, 4))
    urow("ampc_hi5", P.pc.addr_hi(4660, 5))
    urow("ampc_hi_max", P.pc.addr_hi(4660, 4294967295))
    urow("ampc_lo0", P.pc.addr_lo(4660, 0))
    urow("ampc_lo2", P.pc.addr_lo(4660, 2))
    urow("ampc_hi_mask2", P.pc.mask_hi(P.pc.addr_hi(4660, 2)))
    row("ampc_has0", P.pc.has_hi(P.pc.addr_hi(4660, 0)))
    row("ampc_has2", P.pc.has_hi(P.pc.addr_hi(4660, 2)))
    urow("ampc_index0", P.pc.index(0))
    urow("ampc_index1234", P.pc.index(4660))
    urow("ampc_index_max", P.pc.index(1073741823))
    # the ORDER: INDEX2 lo, INDEX2_HI, DATA2, INDEX2_HI zero -- four entries for
    # P.aid 2 and TWO for P.aid 0, and dropping the last store is a silently wrong
    # register on the NEXT call rather than a visible error here.
    urow("ampc_w2_n", P.Tr.n(P.pc.write(4660, 3735928559, 2, P.Tr.of())))
    jrow("ampc_w2_reg", P.Tr.addrs(P.OP_REG_WR(), P.Tr.calls(P.pc.write(4660, 3735928559, 2, P.Tr.of()))))
    jrow("ampc_w2_val", P.Tr.vals(P.OP_REG_WR(), P.Tr.calls(P.pc.write(4660, 3735928559, 2, P.Tr.of()))))
    urow("ampc_w0_n", P.Tr.n(P.pc.write(4660, 3735928559, 0, P.Tr.of())))
    jrow("ampc_w0_reg", P.Tr.addrs(P.OP_REG_WR(), P.Tr.calls(P.pc.write(4660, 3735928559, 0, P.Tr.of()))))
    urow("ampc_pf_w_n", P.Tr.n(P.pc.wreg(4660, 3735928559, P.Tr.of())))
    jrow("ampc_pf_w_reg", P.Tr.addrs(P.OP_REG_WR(), P.Tr.calls(P.pc.wreg(4660, 3735928559, P.Tr.of()))))
    jrow("ampc_pf_w_val", P.Tr.vals(P.OP_REG_WR(), P.Tr.calls(P.pc.wreg(4660, 3735928559, P.Tr.of()))))
    urow("ampc_pf_r_n", P.Tr.n(P.pc.rreg(4660, P.Tr.of())))
    urow("ampc_pf_r_wns", P.Tr.count(P.OP_REG_WR(), P.Tr.calls(P.pc.rreg(4660, P.Tr.of()))))
    jrow("ampc_pf_r_reg", P.Tr.addrs(P.OP_REG_WR(), P.Tr.calls(P.pc.rreg(4660, P.Tr.of()))))

def t_rlcg() -> IO(Unit):
  do IO<Unit>:
    urow("amrl_pair_hi_r", P.rlcg.pair_hi(4660, True{}))
    urow("amrl_pair_hi_w", P.rlcg.pair_hi(4660, False{}))
    urow("amrl_pair_hi_max_r", P.rlcg.pair_hi(4294967295, True{}))
    urow("amrl_pair_hi_max_w", P.rlcg.pair_hi(4294967295, False{}))
    # the 64-bit scratch word's TWO words, for one fixture
    urow("amrl_pair_lo", 43981)
    urow("amrl_word_hi_r", P.rlcg.pair_hi(4660, True{}))
    urow("amrl_word_hi_w", P.rlcg.pair_hi(4660, False{}))
    # the ORDER: the low word is stored FIRST, then the high one
    jrow("amrl_pair_bend_order", P.Tr.addrs(P.OP_PAIR_LO(), P.Tr.calls(P.rlcg.write(43981, 268440116, P.Tr.of()))))
    jrow("amrl_pair_bend_vals", P.Tr.vals(P.OP_PAIR_LO(), P.Tr.calls(P.rlcg.write(43981, 268440116, P.Tr.of()))))
    jrow("amrl_pair_hiaddr", P.Tr.addrs(P.OP_PAIR_HI(), P.Tr.calls(P.rlcg.write(43981, 268440116, P.Tr.of()))))
    jrow("amrl_pair_hivals", P.Tr.vals(P.OP_PAIR_HI(), P.Tr.calls(P.rlcg.write(43981, 268440116, P.Tr.of()))))
    # the GRBM selection: CNTL picks SCRATCH_REG2 and INDEX picks SCRATCH_REG3
    urow("amrl_scratch_cntl", P.rlcg.scratch_of(0, 0))
    urow("amrl_scratch_index", P.rlcg.scratch_of(65536, 0))
    urow("amrl_scratch_other", P.rlcg.scratch_of(1234, 0))
    row("amrl_is_grbm_cntl", P.rlcg.is_grbm(0, 0))
    row("amrl_is_grbm_index", P.rlcg.is_grbm(65536, 0))
    row("amrl_is_grbm_other", P.rlcg.is_grbm(1234, 0))
    urow("amrl_rsv", P.RLCG_RSV_MASK())
    urow("amrl_err", P.RLCG_ERR_MASK())

# THE ROWS.

# THE ROWS. Each def is a `do IO<Unit>:` block of bare statements ending in a
# bare term -- a `match` inside a `do` block is refused, which is why every
# dispatch above is its own def and never happens here.

# the two-way lookups. :400 builds a value -> name dict and :382 needs a name ->
# value, so the port carries both directions of BOTH tables. A one-way table
# cannot catch itself being built the wrong way up, which is why `ops_nv`'s audit
# of 219 constants found 33 wrong in a file already printing 590 green rows.
#
# `hw_id_map` is the other one, and it is NOT injective: hw_id 108 is both
# P.NBIO_HWIP (14) and NBIF_HWID (26), so the INVERSE :391 builds keeps only the
# last -- and the harvest table at :393 depends on which one that is.

# value -> name, i.e. `hwid_names`. The comprehension drops a LATER duplicate, so
# the table holds the FIRST occurrence's slot only if the values are unique --
# they are not, once, and `hwid_of` finds the FIRST match like `dict` would.
# the walked list is the first `+` parameter, so the self-call shrinks before it
# touches anything else; the parallel list rides along because the answer is an
# INDEX into it rather than a value.
# LAST MATCH, not first and not "a" match. `:400`'s comprehension is
# `{Q.v: k.removesuffix('_HWID') for k, Q.v in vars(am).items() ...}` and a dict
# assignment OVERWRITES, so for a value with two keys the LATER key wins -- and
# `UVD_HWID` and `VCN_HWID` are BOTH 12. `best` starts at the LENGTH, so "no
# match" is out of range and `List.get` answers None, which is the absent case.
#
# `i` and `best` are SEPARATE because the first version carried one counter: it
# counted PAST the match, so every lookup answered the last element of the table
# and the gate caught it because `amh_of_1` said MP0 and `amh_rev_gc` said 255.
def hwid.slot.go(n: Nat, +vals: List<&2, U32>, +names: List<&2, String>, +want: U32,
                 +i: Nat, +best: Nat) -> Nat:
  match n:
    case 0n: best
    case 1n+m:
      match vals:
        case Nil{}: best
        case v <> t: hwid.slot.go(m, t, names, want, Nat.add(i, 1n),
          Bool.pick(Nat, U32.is_eq(v, want), i, best))

def hwid.slot(+n: Nat, +names: List<&2, String>, +vals: List<&2, U32>, +want: U32) -> Nat:
  hwid.slot.go(n, vals, names, want, 0n, n)

def hwid.at(n: Nat, +names: List<&2, String>, +vals: List<&2, U32>, +want: U32) -> String:
  Maybe.default(&2, String, List.get(&2, String, names, hwid.slot(n, names, vals, want)), "?")

def hwid.of(Q.v: U32) -> String: hwid.at(List.length(&2, String, Q.hwid.names()), Q.hwid.names(), Q.hwid.vals(), Q.v)

def hwid.name_of(Q.v: U32) -> String: hwid.of(Q.v)

# name -> value, the REVERSE. A name that is not in the table is 0, and 0 is not
# a legal hw_id -- so 0 is a usable "absent" and the rows say so.
def hwid.rslot.go(n: Nat, +names: List<&2, String>, +vals: List<&2, U32>, +want: String,
                  +i: Nat, +best: Nat) -> Nat:
  match n:
    case 0n: best
    case 1n+m:
      match names:
        case Nil{}: best
        case s <> t: hwid.rslot.go(m, t, vals, want, Nat.add(i, 1n),
          Bool.pick(Nat, String.eq(s, want), i, best))

def hwid.rslot(+n: Nat, +names: List<&2, String>, +vals: List<&2, U32>, +want: String) -> Nat:
  hwid.rslot.go(n, names, vals, want, 0n, n)

def hwid.nat(n: Nat, +names: List<&2, String>, +vals: List<&2, U32>, +want: String) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, vals, hwid.rslot(n, names, vals, want)), 0)

def hwid.value_of(nm: String) -> U32:
  hwid.nat(List.length(&2, String, Q.hwid.names()), Q.hwid.names(), Q.hwid.vals(), nm)

# hw_ip -> hw_id, the direction :380 reads.
def hwip.slot.go(n: Nat, +hwips: List<&2, U32>, +ids: List<&2, U32>, +want: U32,
                 +i: Nat, +best: Nat) -> Nat:
  match n:
    case 0n: best
    case 1n+m:
      match hwips:
        case Nil{}: best
        case w <> t: hwip.slot.go(m, t, ids, want, Nat.add(i, 1n),
          Bool.pick(Nat, U32.is_eq(w, want), i, best))

def hwip.slot(+n: Nat, +hwips: List<&2, U32>, +ids: List<&2, U32>, +want: U32) -> Nat:
  hwip.slot.go(n, hwips, ids, want, 0n, n)

def hwip.nat(n: Nat, +hwips: List<&2, U32>, +ids: List<&2, U32>, +want: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, ids, hwip.slot(n, hwips, ids, want)), 0)

def hwip.id_of(hwip_n: U32) -> U32:
  hwip.nat(List.length(&2, U32, Q.hwip.hwips()), Q.hwip.hwips(), Q.hwip.ids(), hwip_n)

# THE VERSION LADDER'S ROWS, and the FOUR arithmetic ladders. Every compare is
# measured on a fixture that straddles the boundary, because a ladder whose only
# fixtures are on one side cannot tell `>=` from `>`.

def vsfx(+maj: U32, +min: U32, +rev: U32) -> String:
  String.concat([U32.show(maj), "_", U32.show(min), "_", U32.show(rev)])

def v.pack(+maj: U32, +min: U32, +rev: U32) -> U32:
  U32.or(U32.or(U32.shln(maj, 20n), U32.shln(min, 16n)), rev)

def vrow(+maj: U32, +min: U32, +rev: U32) -> IO(Unit):
  do IO<Unit>:
    srow(String.concat(["vfmt_", vsfx(maj, min, rev)]), Q.v.fmt3(maj, min, rev))
    srow(String.concat(["p2_", vsfx(maj, min, rev)]), Q.v.fmt2(maj, min))
    row(String.concat(["ge1100_", vsfx(maj, min, rev)]), Q.v.ge3(maj, min, rev, 11, 0, 0))
    row(String.concat(["ge1200_", vsfx(maj, min, rev)]), Q.v.ge3(maj, min, rev, 12, 0, 0))
    row(String.concat(["lt1200_", vsfx(maj, min, rev)]), Q.v.lt3(maj, min, rev, 12, 0, 0))
    row(String.concat(["ne131012_", vsfx(maj, min, rev)]), Q.v.ne3(maj, min, rev, 13, 0, 12))
    urow(String.concat(["pack_", vsfx(maj, min, rev)]), v.pack(maj, min, rev))
    urow(String.concat(["rsv_", vsfx(maj, min, rev)]), Q.v.reserved(maj, min, rev))

def t_versions() -> IO(Unit):
  do IO<Unit>:
    vrow(9, 0, 0)
    vrow(9, 4, 0)
    vrow(9, 5, 0)
    vrow(10, 0, 0)
    vrow(10, 3, 0)
    vrow(11, 0, 0)
    vrow(11, 0, 2)
    vrow(12, 0, 0)
    vrow(12, 0, 1)
    vrow(13, 0, 0)
    vrow(13, 0, 11)
    vrow(13, 0, 12)
    vrow(13, 0, 13)
    # the 64-bit pack, which is NOT a version compare and must not be mistaken for
    # one: `U32` has no room for 13 << 20 | 0 << 16 | 12 in any other order.
    urow("amv_max_maj", 13)
    urow("amv_max_min", 0)
    urow("amv_max_rev", 13)
    urow("amv_min_maj", 9)
    urow("amv_min_rev", 0)

# THE PALLOC LADDER (:233) -- 28 entries, each two words plus its alignment, and
# the first NINE need a HIGH word. A `U32` list would be right for nineteen of
# them and wrong for the nine that matter most.

def t_palloc() -> IO(Unit):
  do IO<Unit>:
    urow("palloc_nlv", P.PALLOC_NLV())
    urow("palloc_len", U32.from_nat(P.PALLOC_LEN()))
    urow("palloc_nbig", P.palloc.nbig())
    urow("palloc_1_hi", P.palloc.size_hi(1))
    urow("palloc_1_lo", P.palloc.size_lo(1))
    urow("palloc_1_align", P.palloc.align(1))
    urow("palloc_2_hi", P.palloc.size_hi(2))
    urow("palloc_2_lo", P.palloc.size_lo(2))
    urow("palloc_2_align", P.palloc.align(2))
    urow("palloc_3_hi", P.palloc.size_hi(3))
    urow("palloc_3_lo", P.palloc.size_lo(3))
    urow("palloc_3_align", P.palloc.align(3))
    urow("palloc_4_hi", P.palloc.size_hi(4))
    urow("palloc_4_lo", P.palloc.size_lo(4))
    urow("palloc_4_align", P.palloc.align(4))
    urow("palloc_5_hi", P.palloc.size_hi(5))
    urow("palloc_5_lo", P.palloc.size_lo(5))
    urow("palloc_5_align", P.palloc.align(5))
    urow("palloc_6_hi", P.palloc.size_hi(6))
    urow("palloc_6_lo", P.palloc.size_lo(6))
    urow("palloc_6_align", P.palloc.align(6))
    urow("palloc_7_hi", P.palloc.size_hi(7))
    urow("palloc_7_lo", P.palloc.size_lo(7))
    urow("palloc_7_align", P.palloc.align(7))
    urow("palloc_11_hi", P.palloc.size_hi(11))
    urow("palloc_11_lo", P.palloc.size_lo(11))
    urow("palloc_11_align", P.palloc.align(11))
    urow("palloc_12_hi", P.palloc.size_hi(12))
    urow("palloc_12_lo", P.palloc.size_lo(12))
    urow("palloc_12_align", P.palloc.align(12))
    urow("palloc_13_hi", P.palloc.size_hi(13))
    urow("palloc_13_lo", P.palloc.size_lo(13))
    urow("palloc_13_align", P.palloc.align(13))
    urow("palloc_14_hi", P.palloc.size_hi(14))
    urow("palloc_14_lo", P.palloc.size_lo(14))
    urow("palloc_14_align", P.palloc.align(14))
    urow("palloc_15_hi", P.palloc.size_hi(15))
    urow("palloc_15_lo", P.palloc.size_lo(15))
    urow("palloc_15_align", P.palloc.align(15))
    urow("palloc_16_hi", P.palloc.size_hi(16))
    urow("palloc_16_lo", P.palloc.size_lo(16))
    urow("palloc_16_align", P.palloc.align(16))
    urow("palloc_17_hi", P.palloc.size_hi(17))
    urow("palloc_17_lo", P.palloc.size_lo(17))
    urow("palloc_17_align", P.palloc.align(17))
    urow("palloc_18_hi", P.palloc.size_hi(18))
    urow("palloc_18_lo", P.palloc.size_lo(18))
    urow("palloc_18_align", P.palloc.align(18))
    urow("palloc_19_hi", P.palloc.size_hi(19))
    urow("palloc_19_lo", P.palloc.size_lo(19))
    urow("palloc_19_align", P.palloc.align(19))
    urow("palloc_20_hi", P.palloc.size_hi(20))
    urow("palloc_20_lo", P.palloc.size_lo(20))
    urow("palloc_20_align", P.palloc.align(20))
    urow("palloc_21_hi", P.palloc.size_hi(21))
    urow("palloc_21_lo", P.palloc.size_lo(21))
    urow("palloc_21_align", P.palloc.align(21))
    urow("palloc_22_hi", P.palloc.size_hi(22))
    urow("palloc_22_lo", P.palloc.size_lo(22))
    urow("palloc_22_align", P.palloc.align(22))
    urow("palloc_23_hi", P.palloc.size_hi(23))
    urow("palloc_23_lo", P.palloc.size_lo(23))
    urow("palloc_23_align", P.palloc.align(23))
    urow("palloc_24_hi", P.palloc.size_hi(24))
    urow("palloc_24_lo", P.palloc.size_lo(24))
    urow("palloc_24_align", P.palloc.align(24))
    urow("palloc_25_hi", P.palloc.size_hi(25))
    urow("palloc_25_lo", P.palloc.size_lo(25))
    urow("palloc_25_align", P.palloc.align(25))
    urow("palloc_26_hi", P.palloc.size_hi(26))
    urow("palloc_26_lo", P.palloc.size_lo(26))
    urow("palloc_26_align", P.palloc.align(26))
    jrow("va_shifts", P.va.shifts())
    urow("palloc_va_bits", P.VA_BITS())
    urow("palloc_boot", P.BOOT_SIZE())
    urow("palloc_i0_hi", P.palloc.size_hi(0))
    urow("palloc_i0_lo", P.palloc.size_lo(0))
    urow("palloc_i8_hi", P.palloc.size_hi(8))
    urow("palloc_i8_lo", P.palloc.size_lo(8))
    urow("palloc_i9_hi", P.palloc.size_hi(9))
    urow("palloc_i9_lo", P.palloc.size_lo(9))
    urow("palloc_i10_hi", P.palloc.size_hi(10))
    urow("palloc_i10_lo", P.palloc.size_lo(10))
    urow("palloc_i27_hi", P.palloc.size_hi(27))
    urow("palloc_i27_lo", P.palloc.size_lo(27))
    # the ALIGNMENT ladder: `i >= 9` and not `i > 9`, so index 9 is 2MB and
    # index 10 is 4KB. That single boundary is the whole ladder.
    # the DESCENDING order, which the LIST row already pins positionally: entry
    # `i` of `amp_list` is `lo, align` for index `i`, so the order IS the rows.

# the module ladder (:405-407) and the P.aid alive-mask (:417-421).

def modsrow(+maj: U32, +min: U32, +rev: U32) -> IO(Unit):
  do IO<Unit>:
    srow(String.concat(["mods_", vsfx(maj, min, rev), "_nb"]), P.mods.nb(maj, min, rev))
    urow(String.concat(["mods_", vsfx(maj, min, rev), "_n"]), P.mods.nbase())
    jrow_s(String.concat(["mods_", vsfx(maj, min, rev), "_all"]), P.mods.names6(maj, min, rev))
    jrow(String.concat(["mods_", vsfx(maj, min, rev), "_hwips"]), P.mods.hwips())

def sdraw(+maj: U32, +min: U32, +rev: U32) -> IO(Unit):
  do IO<Unit>:
    row(String.concat(["mods_sd_", vsfx(maj, min, rev), "_add"]), P.mods.sdma(maj, min, rev))
    urow(String.concat(["mods_sd_", vsfx(maj, min, rev), "_n"]), P.mods.n_of(P.mods.sdma(maj, min, rev)))

def t_modules() -> IO(Unit):
  do IO<Unit>:
    modsrow(9, 0, 0)
    modsrow(9, 4, 0)
    modsrow(9, 5, 0)
    modsrow(10, 0, 0)
    modsrow(11, 0, 0)
    modsrow(11, 9, 0)
    modsrow(12, 0, 0)
    modsrow(12, 0, 1)
    modsrow(13, 0, 0)
    # the SDMA gate, :407 -- two versions out of nine tested
    sdraw(4, 4, 0)
    sdraw(4, 4, 1)
    sdraw(4, 4, 2)
    sdraw(4, 4, 3)
    sdraw(4, 4, 4)
    sdraw(4, 4, 5)
    sdraw(4, 5, 0)
    sdraw(4, 2, 0)
    sdraw(5, 0, 0)
# THE MASK ARITHMETIC, on every subset of four slots: 16 fixtures, and each mask
# decides one AID. `am_aid_mask_*` is the row class and `am_aid_alive_*` says which
# of them the {0xf,0x3,0xc} set accepts.
# THE LIST, one AID per row. `P.aid.list4` answers a LIST and `aidsrow` writes one
# row per element, because a joined list cannot be compared element-wise: an
# oracle disagreement about WHICH AID is missing is invisible in a join and
# obvious in a count plus a per-element set.
def aidsrow.go(n: Nat, +nm: String, +xs: List<&2, U32>, +i: Nat) -> IO(Unit):
  match n:
    case 0n: IO.print("")
    case 1n+m:
      match xs:
        case Nil{}: IO.print("")
        case x <> t:
          do IO<Unit>:
            urow(String.concat([nm, "_", aspm.index_str(i)]), x)
            aidsrow.go(m, nm, t, Nat.add(i, 1n))

def aidsrow(nm: String, +xs: List<&2, U32>) -> IO(Unit):
  aidsrow.go(List.length(&2, U32, xs), nm, xs, 0n)

def aidscount(nm: String, +xs: List<&2, U32>) -> IO(Unit):
  urow(String.concat([nm, "_n"]), U32.from_nat(List.length(&2, U32, xs)))

def t_aids() -> IO(Unit):
  do IO<Unit>:
    urow("aids_mask_0123", P.aid.mask(1, 1, 1, 1))
    urow("aids_mask_123", P.aid.mask(0, 1, 1, 1))
    urow("aids_mask_023", P.aid.mask(1, 0, 1, 1))
    urow("aids_mask_3", P.aid.mask(0, 0, 0, 1))
    urow("aids_mask_013", P.aid.mask(1, 1, 0, 1))
    urow("aids_mask_0000", P.aid.mask(0, 0, 0, 0))
    row("ama_alive_0000", P.aid.alive(P.aid.mask(0, 0, 0, 0)))
    row("ama_alive_absent", P.aid.alive(9999))
    # `i & 3` and `i >> 2` are INVERSES, and the base is `aidn * 4`
    urow("ama_base1", U32.from_nat(P.aid.base(1)))
    urow("ama_base2", U32.from_nat(P.aid.base(2)))
    urow("ama_of7", P.aid.of(7))
    urow("ama_of8", P.aid.of(8))
    urow("ama_slot0", P.aid.slot(0))
    urow("ama_slot3", P.aid.slot(3))
    urow("ama_slot4", P.aid.slot(4))
    urow("ama_slot7", P.aid.slot(7))
    # `max((k >> 2 for k in insts), default=0)` -- the default is load-bearing
    urow("aids_full4_maxaid", P.aid.max_aid([0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15]))
    urow("aids_empty_maxaid", P.aid.max_aid(Nil{}))
    urow("aids_one_maxaid", P.aid.max_aid([3]))
    urow("aids_sparse_maxaid", P.aid.max_aid([4, 5, 20, 21, 22, 23]))
    # THE LIST, with the LIVE flags per group. Four groups, so sixteen flags.
    aidsrow("aids_full4", P.aid.list4([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]))
    aidscount("aids_full4", P.aid.list4([1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]))
    aidsrow("aids_half0", P.aid.list4([1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]))
    aidscount("aids_half0", P.aid.list4([1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]))
    aidsrow("aids_none", P.aid.list4([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
    aidscount("aids_none", P.aid.list4([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]))
    aidsrow("aids_halves", P.aid.list4([1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 0, 1, 1, 1, 1]))
    aidscount("aids_halves", P.aid.list4([1, 1, 1, 0, 0, 0, 0, 0, 1, 1, 1, 0, 1, 1, 1, 1]))
    aidsrow("aids_maskc", P.aid.list4([1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]))
    aidscount("aids_maskc", P.aid.list4([1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1]))

# (1) the struct field lists, by name and in order: nine structs, every field,
# one row each. the count rows are here too and they are not the gate -- they are
# there so a reader can see that a transposition left every count alone. That is
# the whole reason the fields are gated by NAME: `ops_cl`'s unit found `Sig`'s
# field names INVERTED, which made a correct computation look wrong, and a count
# gate passes an inversion.
def t_layout() -> IO(Unit):
  do IO<Unit>:
    sfrow("amf_chdr_0", 0n, 0n)
    sfrow("amf_chdr_1", 0n, 1n)
    sfrow("amf_chdr_2", 0n, 2n)
    sfrow("amf_chdr_3", 0n, 3n)
    sfrow("amf_chdr_4", 0n, 4n)
    sfrow("amf_chdr_5", 0n, 5n)
    sfrow("amf_chdr_6", 0n, 6n)
    sfrow("amf_chdr_7", 0n, 7n)
    sfrow("amf_chdr_8", 0n, 8n)
    sfrow("amf_chdr_9", 0n, 9n)
    sfrow("amf_bin_0", 1n, 0n)
    sfrow("amf_bin_5", 1n, 5n)
    sfrow("amf_idisc_0", 2n, 0n)
    sfrow("amf_idisc_4", 2n, 4n)
    sfrow("amf_idisc_9", 2n, 9n)
    sfrow("amf_die_0", 3n, 0n)
    sfrow("amf_die_1", 3n, 1n)
    sfrow("amf_ipv4_0", 4n, 0n)
    sfrow("amf_ipv4_1", 4n, 1n)
    sfrow("amf_ipv4_2", 4n, 2n)
    sfrow("amf_ipv4_3", 4n, 3n)
    sfrow("amf_ipv4_4", 4n, 4n)
    sfrow("amf_ipv4_5", 4n, 5n)
    sfrow("amf_gci_0", 5n, 0n)
    sfrow("amf_gci_1", 5n, 1n)
    sfrow("amf_gci_18", 5n, 18n)
    sfrow("amf_gci_19", 5n, 19n)
    sfrow("amf_pspdesc_0", 6n, 0n)
    sfrow("amf_pspdesc_1", 6n, 1n)
    sfrow("amf_pspdesc_2", 6n, 2n)
    sfrow("amf_pspdesc_3", 6n, 3n)
    sfrow("amf_pptable_0", 7n, 0n)
    sfrow("amf_pptable_1", 7n, 1n)
    sfrow("amf_pptable_2", 7n, 2n)
    sfrow("amf_psp_v2_1_0", 8n, 0n)
    sfrow("amf_psp_v2_1_1", 8n, 1n)
    sfrow("amf_psp_v2_1_2", 8n, 2n)
    # the SCALAR byte offsets, which is the WIDTH of each field
    jrow("amf_chdr_offs", P.sf.common_firmware_header.offs())
    jrow("amf_bin_offs", P.sf.binary_header.offs())
    jrow("amf_idisc_offs", P.sf.ip_discovery_header.offs())
    jrow("amf_ipv4_offs", P.sf.ip_v4.offs())
    jrow("amf_die_offs", P.sf.die_header.offs())
    jrow("amf_pspdesc_offs", P.sf.psp_fw_bin_desc.offs())
    jrow("amf_pptable_offs", P.sf.smc_soft_pptable_entry.offs())
    jrow("amf_psp_v2_1_offs", P.sf.psp_firmware_v2_1.offs())
    jrow("amf_gci_offs", P.sf.gc_info_v1_0.offs())
    # the SCALAR names, i.e. the ORDER `register_fields` claims
    jrow_s("amf_chdr_scalar_names", P.sf.common_firmware_header.onnames())
    jrow_s("amf_bin_scalar_names", P.sf.binary_header.onnames())
    jrow_s("amf_ipv4_scalar_names", P.sf.ip_v4.onnames())
    jrow_s("amf_die_scalar_names", P.sf.die_header.onnames())
    jrow_s("amf_idisc_scalar_names", P.sf.ip_discovery_header.onnames())
    jrow_s("amf_pspdesc_scalar_names", P.sf.psp_fw_bin_desc.onnames())
    jrow_s("amf_pptable_scalar_names", P.sf.smc_soft_pptable_entry.onnames())
    jrow_s("amf_psp_v2_1_scalar_names", P.sf.psp_firmware_v2_1.onnames())
    # the counts, strides and sizes -- NOT the gate, but the control
    urow("amf_pspdesc_stride", 16)
    urow("amf_pptable_stride", 12)
    urow("amf_diehdr_stride", 4)
    urow("amf_ipv4_stride", 7)
    urow("amf_ipv4_head", 8)
    urow("amf_chdr_n", P.sf.common_firmware_header.n())
    urow("amf_chdr_nscalar", P.sf.common_firmware_header.nscalar())
    urow("amf_chdr_size", P.sf.common_firmware_header.size())
    urow("amf_chdr_maxoff", P.sf.common_firmware_header.maxoff())
    urow("amf_bin_n", P.sf.binary_header.n())
    urow("amf_bin_size", P.sf.binary_header.size())
    urow("amf_idisc_n", P.sf.ip_discovery_header.n())
    urow("amf_idisc_nscalar", P.sf.ip_discovery_header.nscalar())
    urow("amf_idisc_size", P.sf.ip_discovery_header.size())
    urow("amf_ipv4_n", P.sf.ip_v4.n())
    urow("amf_ipv4_size", P.sf.ip_v4.size())
    urow("amf_ipv4_maxoff", P.sf.ip_v4.maxoff())
    urow("amf_die_n", P.sf.die_header.n())
    urow("amf_die_size", P.sf.die_header.size())
    urow("amf_die_maxoff", P.sf.die_header.maxoff())
    urow("amf_pspdesc_n", P.sf.psp_fw_bin_desc.n())
    urow("amf_pspdesc_maxoff", P.sf.psp_fw_bin_desc.maxoff())
    urow("amf_pptable_n", P.sf.smc_soft_pptable_entry.n())
    urow("amf_pptable_size", P.sf.smc_soft_pptable_entry.size())
    urow("amf_pptable_maxoff", P.sf.smc_soft_pptable_entry.maxoff())
    urow("amf_psp_v2_1_n", P.sf.psp_firmware_v2_1.n())
    urow("amf_psp_v2_1_maxoff", P.sf.psp_firmware_v2_1.maxoff())
    urow("amf_gci_n", P.sf.gc_info_v1_0.n())
    urow("amf_gci_maxoff", P.sf.gc_info_v1_0.maxoff())

# (2) `hwid_names` (:400) and `hw_id_map` (:380) -- TWO-WAY TABLES, BOTH
# directions, because one direction cannot catch a table built the wrong way up.
def t_tables() -> IO(Unit):
  do IO<Unit>:
    urow("amh_nkeys", Q.hwid.nkeys())
    urow("amh_ndistinct", Q.hwid.ndistinct())
    urow("amh_ncollision", Q.hwid.ncollision())
    urow("amh_collision", Q.hwid.collision())
    jrow_s("amh_collision_names", Q.hwid.collision_names())
    jrow_s("amh_names", Q.hwid.names())
    jrow("amh_vals", Q.hwid.vals())
    # value -> name, the direction :400 builds. UVD_HWID and VCN_HWID are BOTH 12,
    # so the comprehension DROPS UVD and `hwid.name_of(12)` is VCN.
    srow("amh_of_12", hwid.name_of(12))
    srow("amh_of_1", hwid.name_of(1))
    srow("amh_of_2", hwid.name_of(2))
    srow("amh_of_11", hwid.name_of(11))
    srow("amh_of_42", hwid.name_of(42))
    srow("amh_of_108", hwid.name_of(108))
    srow("amh_of_255", hwid.name_of(255))
    srow("amh_of_40", hwid.name_of(40))
    srow("amh_of_34", hwid.name_of(34))
    srow("amh_of_19", hwid.name_of(19))
    srow("amh_of_20", hwid.name_of(20))
    srow("amh_of_21", hwid.name_of(21))
    srow("amh_of_28", hwid.name_of(28))
    srow("amh_of_32", hwid.name_of(32))
    srow("amh_of_90", hwid.name_of(90))
    srow("amh_of_200", hwid.name_of(200))
    srow("amh_of_150", hwid.name_of(150))
    srow("amh_of_7", hwid.name_of(7))
    srow("amh_of_9999", hwid.name_of(9999))
    # the REVERSE, name -> value, which is what a diagnostic's hw_id needs
    urow("amh_rev_mp0", hwid.value_of("MP0"))
    urow("amh_rev_gc", hwid.value_of("GC"))
    urow("amh_rev_sdma0", hwid.value_of("SDMA0"))
    urow("amh_rev_sdma2", hwid.value_of("SDMA2"))
    urow("amh_rev_sdma3", hwid.value_of("SDMA3"))
    urow("amh_rev_osssys", hwid.value_of("OSSSYS"))
    urow("amh_rev_nbif", hwid.value_of("NBIF"))
    urow("amh_rev_uvd", hwid.value_of("UVD"))
    urow("amh_rev_vcn", hwid.value_of("VCN"))
    urow("amh_rev_missing", hwid.value_of("NOSUCHIP"))
    urow("amhw_n", Q.hwip.n())
    urow("amhw_inv_n", Q.hwip.inv_n())
    urow("amhw_max", Q.hwip.max())
    urow("amhw_in_range", Q.hwip.in_range())
    urow("amhw_inv_108", Q.hwip.inv_108())
    jrow("amhw_hwips", Q.hwip.hwips())
    jrow("amhw_ids", Q.hwip.ids())
    jrow("amhw_dupvals", Q.hwip.dupvals())
    urow("amhw_of_gc", hwip.id_of(P.GC_HWIP()))
    urow("amhw_of_hdp", hwip.id_of(P.HDP_HWIP()))
    urow("amhw_of_mp0", hwip.id_of(P.MP0_HWIP()))
    urow("amhw_of_mp1", hwip.id_of(P.MP1_HWIP()))
    urow("amhw_of_sdma0", hwip.id_of(P.SDMA0_HWIP()))
    urow("amhw_of_mmhub", hwip.id_of(P.MMHUB_HWIP()))
    urow("amhw_of_osssys", hwip.id_of(P.OSSSYS_HWIP()))
    urow("amhw_of_nbio", hwip.id_of(P.NBIO_HWIP()))
    urow("amhw_of_unlisted", hwip.id_of(18))
    urow("amhw_of_35", hwip.id_of(35))

def main() -> IO(Unit):
  do IO<Unit>:
    t_layout()
    t_tables()
    t_versions()
    t_palloc()
    t_modules()
    t_aids()
    t_aspm()
    t_mailbox()
    t_readvram()
    t_pcie()
    t_rlcg()
    IO.print("amdev-done=1")

# THE MUTATION TABLE. Every number below is `.agents/slop/amdev_mutate.py`'s own
# output, not an estimate: the harness applies one edit to an IN-TREE scratch
# copy, runs the INTERPRETED lane, and diffs the row values. The useful column is
# "rows MOVED", because a mutation that moves nothing measures what this gate does
# NOT see.
#
# The scratch copy must be in the tree: `import ../../../helpers.bend` is a
# RELATIVE path, so a copy under `$TMPDIR` cannot resolve it and every mutation
# reports "did not compile" for a reason that has nothing to do with the edit.
# That is what the first version of this table did, and it is worth recording
# because it looks exactly like "no mutation moves anything".
#
# id    rows moved  what

# M1             0  the version compare: `>` against `>=` on the MAJOR component.
# M2             8  the RELATIVE shift: `1 << (34 - 32)` is `1 << 2` in the high word, and `1 << 34` in a U32 SATURATES TO 0. This is the ops_amd SQTT-pointer shape.
# M3             8  the P.palloc high word: subtract 32 for the split, not add.
# M4             8  the P.palloc low word: for a 64-bit entry it must be ZERO, and a 1 there would make the allocator hand out 2^32 + n.
# M5             4  :406 `nbio` for ip_ver < (12,0,0) -- moving the boundary to 11.
#                  ['mods_11_0_0_all', 'mods_11_0_0_nb', 'mods_11_9_0_all', 'mods_11_9_0_nb']
# M6             1  the P.palloc 64-bit test reads the NEXT index, so `nbig` counts one too few.
#                  ['palloc_nbig']
# M7             2  the `max((k >> 2 ...), default=0)` fold: the argument order decides which wins.
#                  ['aids_full4_maxaid', 'aids_sparse_maxaid']
# M8             9  :405-407 builds the module list and appends nbio/nbif LAST; prepending it changes which table each IP is keyed by.
# M9             4  the RLC gateway's read/write bit: `(addr | 1<<28) << 32` is a read, `addr << 32` a write. Swapping them is a silently wrong gateway command.
#                  ['amrl_pair_hi_r', 'amrl_pair_hi_w', 'amrl_word_hi_r', 'amrl_word_hi_w']
# M10            2  wreg_pair's ORDER: the LOW word is stored first. This mutation swaps the SLOTS, not the nesting, so it is the argument order.
#                  ['amrl_pair_bend_vals', 'amrl_pair_hivals']
# M11            4  :272 `for i, val in enumerate((req, 0, 0, 0)): mmio[TRN_DW0 + i] = val` -- the REQUEST goes in the FIRST word, so writing the next address's value would put the request one word late.
#                  ['amb_fini_mm_val', 'amb_init_mm_val', 'amb_norw_mm_val', 'amb_reqff_mm_val']
# M12            3  :276 `vf_mailbox[0] = 0` is UNCONDITIONAL -- only the ready wait and the ack are behind `if wait_ready:`. This mutation drops the FALSE arm's store.
#                  ['amb_norw_mb_val', 'amb_norw_mb_wr', 'amb_norw_n']
# M13  EDIT NOT FOUND  :351 `wreg(0x06, caddr >> 31)` -- the high address bit, off by one.
# M14  EDIT NOT FOUND  :352 `(caddr & 0x7FFFFFFF) | 0x80000000` -- dropping the mask keeps the address bit that selects the window half.
# M15            4  the ASPM probe ORDER: `cap` then `cap + 1`. The inner call is evaluated first, so the argument that reads LAST must be the OUTER one. Invisible on every fixture with one read per step.
#                  ['ama_aspm_chain_rd_1', 'ama_aspm_chain_rd_2', 'ama_aspm_loop_rd_1', 'ama_aspm_loop_rd_2']
# M16  EDIT NOT FOUND  :154 `if cap and cap not in seen` -- `not` against `or`.
# M17            1  :154 writes `read_config(...) & ~3`, NOT the mask itself; writing the mask would clear every other Link Control bit.
#                  ['ama_aspm_link_val_0']
# M18           19  the two-way table SEARCH: `:400`'s dict comprehension OVERWRITES, so the LAST duplicate wins (UVD_HWID and VCN_HWID are both 12).
# M19           10  the two-way table's REVERSE direction, which is a different walk.
# M20            0  the AID alive-mask SET {0xf, 0x3, 0xc}: 0xc IS P.AID_ALIVE_C(), so this mutation is a CONTROL. It should move nothing.
# M21            0  the version TAIL compare: reading `ax` on both sides is an EQUIVALENCE, not a bug -- reported as a blind spot, NOT closed with a row.
# M22            0  a comment-only-equivalent edit. THE CONTROL: a table with no row that CANNOT move is a table of coincidences.

# baseline rows: 552
# mutations moving nothing: ['M1', 'M20', 'M21', 'M22']

# M20 and M22 are the controls and M1 and M21 are blind spots, and the two pairs
# are different things:
#
#   * M22 is an equivalent edit and M20 substitutes `P.AID_ALIVE_C()` for its own
#     value 12. Both are EXPECTED to move nothing; a control that moved something
#     would mean the table cannot be trusted.
#
#   * M1 replaces the tail's `bn` with `an` in `Q.v.ge3`. Every fixture has
#     `bn == 0` for the (11,0,0) and (12,0,0) boundaries -- `an` is 11 or 12 and
#     `bn` is 0, so `Q.v.ge2(an, ax, bn, an)` and `Q.v.ge2(an, ax, bn, bn)` agree on
#     all of them. the fixtures are all on one side, so no fixture can separate
#     them. This is `ops_nv`'s lesson: a `0` here is a REQUEST FOR A FIXTURE, not
#     a coverage claim, and a ladder whose boundary fixtures all share a zero in
#     the same slot cannot test that slot. A `(11, 5, 0)` fixture against `(11, 0, 0)`
#     would do it and is NOT in the table.
#
#   * M21 is a THEOREM rather than a hole: reading `ax` on both sides of the same
#     comparison cannot differ, so no fixture over any input can separate it.
#     Reported, not closed.

# THE WALLS, and what is NOT here. `amdev.py` is 421 lines and roughly a third of
# it is `ctypes` marshalling, `fetch_fw` and BAR access; the rest is what is
# above. The four things this port does NOT carry, each with its Python line:
#
#   * `fetch_fw("amdgpu", fname, fw.hashes[fname])` (:112) is a DOWNLOAD and
#     `hashlib.sha256` (:113) is a digest. The FILENAME is ported -- `Q.v.fmt3` and
#     the `psp_`/`smu_`/`sdma_`/`gc_`/`imu_`/`rlc`/`_sos.bin` shapes are rows --
#     and the bytes are the seam's.
#     WALL(p3) runtime/support/am/amdev.py:112  fetch_fw -- BLOCKED: needs `fetch_fw` (a network DOWNLOAD, `fetch_fw("amdgpu", fname, fw.hashes[fname])` :112) and `hashlib.sha256` (:113), both seams; the FILENAME ladder IS ported (`Q.v.fmt3`, :431, plus the `psp_`/`smu_`/`sdma_`/`gc_`/`imu_`/`rlc`/`_sos.bin` rows) and the bytes are the seam's.
#   * `ctypes.addressof` / `from_address` / `from_buffer` (:37 :51 :365 :366 :373
#     :377 :395) is pointer arithmetic over the image. The STRUCT LAYOUTS it reads
#     are ported and gated by name, order and byte offset; the addresses are not.
#     TODO(p3) runtime/support/am/amdev.py:379  symbol=_run_discovery  struct_ip_v4.from_address.
#   * `AMRegister.encode` / `fields_mask` (:17-23) read the BITFIELD LISTS out of
#     `autogen/am/regs/*`, which is `ip.bend`'s file, not this one. `update`'s
#     COMPOSITION -- read, clear the named fields, OR the new encoding -- is the
#     `P.pc.write`-shaped shape this port carries.
#     TODO(p3) runtime/support/am/amdev.py:21  symbol=write  AMRegister.encode / fields_mask.
#   * `AMFirmware.__init__`'s DESCRIPTOR LIST is generated by the oracle over real
#     images (`.agents/slop/amdev_fw.py`) and is ported as its OFFSET/SIZE/TYPE
#     ladder -- but the ladder is a TABLE here, not a def per firmware version,
#     because the nine `GFX_FW_TYPE_*` ids and the four `header_version_major`
#     arms cross-product to more rows than the gate can read. The oracle's
#     `fw_*` rows are the measurement of it; the port's `amv_*` rows are the
#     constants it uses.
#     TODO(p3) runtime/support/am/amdev.py:73  symbol=__init__  the per-image descriptor descent.
#

# WHAT `ops_amd.bend` RECORDED FOR THIS FILE, and whether it is closed. It lists
# amdev.py under its WALL 2 ("PCI / amdev", :737-804) with four TODOs. NONE of
# the four is amdev.py's to answer -- they are `PCIIfaceBase.__init__`'s vendor
# probe, `AMDev.gc_info`'s FIELD READS, `setup_ring`'s ring arithmetic and the
# DRM cu_bitmap, all of which live in `ops_amd.py`. This port carries the HALVES
# of WALL 2 that are amdev.py's: the BAR offsets it maps (:159), the register
# window arithmetic (:301-345), the discovery walk (:356-397) and the scratch
# registers (:314-326). CONTRADICTION, REPORTED AND NOT RECONCILED: `ops_amd.bend`
# says WALL 2 is "the PCI BAR + amdev" and records `AMDev.{sdma,gfx}.setup_ring` as
# unportable; `amdev.py` has no `setup_ring` at all -- the ring arithmetic is
# `AM_SDMA`/`AM_GFX` in `ip.py`. So that TODO belongs to neither file as written,
# and whoever owns the rings should say where.
