# gates/rangeify-gate.bend -- THE GATE DRIVER for `tinybendygrad/schedule/rangeify.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. THE PORT FILE CARRIES THE PORT AND
# THIS FILE CARRIES THE INSTRUMENT, AND THE TREE's OWN CONVENTION SAYS SO:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# THE ROWS ARE PURE CONSUMERS: THEY CALL THE PORT's DEFS AND DEFINE
# NOTHING THAT THE PORT NEEDS.

import Base
import ./../tinybendygrad/schedule/rangeify.bend as P
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/uop/movement.bend as M

def t_nv_rs_is_src0() -> U32:
  P.b2u(U32.is_eq(M.hop_ix(P.nv_rewrite(P.g_ar(P.g()), P.g_rs(P.g()))), P.g_b4(P.g())))
def t_noopf_e_nx() -> U32: P.b2u(P.is_noop_after_dep(P.g_ar(P.g()), P.g_e1(P.g())))
def t_sk_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, P.sk_table()))
def t_ct8b_devnone() -> U32: P.b2u(P.rf_dev_is_none(P.G.fx(P.g()), M.mp_src(P.ar_of(P.g_mstb(P.g())), P.g_mstb(P.g()), 0)))
# THE REBUILD, as the src op SEQUENCE. py: `ct8_ix_ms_devless out=INDEX/nsrc1/
# srcops=[CONST]` and `ct8_ix_ms_rng out=INDEX/nsrc2/srcops=[CONST,RANGE]`, and
# `Ops.CONST.value` is 58 while `Ops.RANGE.value` is 53 -- both asked of CPython.
# The two rows are ".58" and ".58.53", and the difference IS the `src[1:]` half,
# which a count could not see.
# the fully-ported `dg_3` body: an INDEX of an ALU PARAM answers the PARAM
def t_dg_ixpa_ans() -> U32:
  P.b2u(U32.is_eq(M.hop_ix(P.dg_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_ipa(P.g()))), P.g_pa(P.g())))
# and its negative: an INDEX of a GLOBAL PARAM does NOT answer. The row prints
# the ABSENCE, so it is `_none` and its 1 is the passing value.
def t_ab4_stg2() -> U32: P.b2u(P.ab_4_claim(P.g_ar(P.g()), P.g_st2(P.g())))
# `ab_7`: the CALL keeps its arity and its src0 becomes the RESHAPE's src0.
def t_ab7_cli_nsrc() -> U32:
  M.mp_nsrc(M.hop_ar(P.ab_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_cli(P.g()))),
            M.hop_ix(P.ab_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_cli(P.g()))))
# THE ARG ROWS, and why they had to be written at all. `mp_replace` was widened from
# `(op, ar, self, src)` to `(op, arg, ar, self, src)` because `UOp.replace` (ops.py:252)
# takes `arg` as a KWARG -- `kwargs.pop("arg", self.arg)` -- so a rule that replaces only
# `src` passes the node's OWN arg. Four call sites here were left on the 4-arg form and
# the file stopped compiling.
#
# THE COMPILED FILE IS NOT EVIDENCE, and neither is any row that already existed. `cli`,
# `af` and `mst` are all given `ANone` by this fixture, and an AFTER's and an MSTACK's
# arg is `None` in CPython TOO (measured: `raf_after_arg_is_none = 1`,
# `mstack_arg_is_none = 1`), so `eq_arg(rebuilt_arg, original_arg)` on any of them is
# `eq_arg(ANone, ANone)` -- TRUE for a port that preserves the arg AND for one that
# hardcodes `ANone`, which is the mistake that silences this type error. A CALL's arg is a
# `Kernel`, so `clik` is the node that separates the two and `clik0` is the negative one
# row from it at the same shape.
#
# `eq_arg(x, y)` DISPATCHES ON `x` and matches `y` (ops.bend:2308), so the expected arg
# goes first. `py=` from `.agents/slop/rf-arg-oracle.py`, which reports
# `arg_is_own_kernel=1` and `arg_is_none=0` for the rebuild.
# the negative, the twin with no arg, one row from the positive at the same shape:
# py: `arg_is_own_kernel=0 arg_is_none=1`. So `ab7_clik_arg` is not passing because
# every CALL rebuilds to a Kernel.
def t_ab7_clik0_arg() -> U32:
  P.b2u(O.eq_arg(O.AKernel{O.KernelInfo.of()},
               M.mp_arg(M.hop_ar(P.ab_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_clik0(P.g()))),
                        M.hop_ix(P.ab_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_clik0(P.g()))))))
# the OTHER repaired site a CALL reaches, `no_indexing_calls` (rangeify.py:158).
# py: `nic_clik` nsrc=2, `arg_is_own_kernel=1`, `nic_claim_clik=1` (first-wins:
# exactly one pattern claims it, so this is not another rule's answer).
def t_aprt_pgloT_none() -> U32: P.b2u(O.UOp.is_none(M.hop_ix(P.aprt_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_pgt(P.g())))))
def t_nic_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, P.nic_table()))
def t_mops_root2() -> U32: P.t_root_n(P.ct_entry(2n))
def t_rb_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, P.rb_table()))
def t_aprt_r0t_none() -> U32: P.b2u(Bool.not(O.UOp.is_none(M.hop_ix(P.aprt_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_r0t(P.g()))))))
def t_ab4_stg3() -> U32: P.b2u(P.ab_4_claim(P.g_ar(P.g()), P.g_st3(P.g())))
def t_ct4d_tail() -> U32: P.b2u(P.rf_stage_tail(P.g_ar(P.g()), P.g_ct4d(P.g()), P.g_ixb4(P.g())))
# THE CLAIM AS A BOOL, restricted to one entry: "tag 4's rule claims a STAGE".
# This is the row that M21 moves, and it is the row the table's op sets had wrong
# for tags 0, 1, 2, 5 and 8. `ct_root4` and `ct_root5` are 1; the five INDEX/AFTER/
# END entries are 0.
def t_ct_root(e: O.PMEntry) -> U32: P.b2u(O.op_in(O.PMEntry.ops(e), O.OpsSTAGE{}))
# THE ROOT/SUB ROWS. `mops_root0/1/2` are the pdict KEYS of the three `pm_mops`
# rules (17, 13, 55) and `mops_child_fb` is the PATTERN's child set (6 ops). They
# are DIFFERENT facts and the port had them as one, which is the whole defect.
def t_nic_calls_ans() -> U32: P.b2u(Bool.not(O.UOp.is_none(M.hop_ix(P.nic_rewrite(P.g_ar(P.g()), P.g_cls(P.g()))))))
# THE ROOT/SUB ROWS. `mops_root0/1/2` are the pdict KEYS of the three `pm_mops`
# rules (17, 13, 55) and `mops_child_fb` is the PATTERN's child set (6 ops). They
# are DIFFERENT facts and the port had them as one, which is the whole defect.
def t_mops_rules() -> U32: 3
def t_noopf_b4() -> U32: P.b2u(P.is_noop_after_dep(P.g_ar(P.g()), P.g_b4(P.g())))
# the INDEX arm: the CALL's src0 becomes the STAGE, so the arity is 2 and the
# src0 is NOT the INDEX's src0 (which is the CALL's own INDEX).
def t_nic_calli_nsrc() -> U32:
  M.mp_nsrc(M.hop_ar(P.nic_rewrite(P.g_ar(P.g()), P.g_cli(P.g()))), M.hop_ix(P.nic_rewrite(P.g_ar(P.g()), P.g_cli(P.g()))))
# the MSTACK arm: the CALL's src0 is a MSTACK whose srcs were both stripped, and
# `strip(SH1) = SH1` while `strip(SH0) = B4`, so the arity is still 2.
def t_eng_tables() -> U32: P.eng_table_n()
# THE ORDER NOTE. A sweep reproduces the DFS's ORDER only where the order is
# not observable, and the order is observable exactly where upstream threads a
# `ctx` COUNTER. This is a CONSTANT, not a measurement, and it says so.
def t_ren7_arg0() -> U32: P.ren_axis0(7, P.g_ar(P.g()), P.g_r0t(P.g()))
# THE GATE. Every row is DERIVED FROM PYTHON by `.agents/slop/rf-rows.py`, so a row here can
# be WRONG rather than merely restate this file. `1`/`0` is a Bool, and a `0` that is a
# positive claim is a real answer (`ren_none` is a `True` result meaning "no node"), not a
# failure.
#
# THE FIXTURE, and what each node is FOR. `b4` and `bx` are TWO GLOBAL BUFFERs of 4 int32
# with different slots, so `STORE(b4, bx)` is a two-src STORE whose srcs are DIFFERENT nodes
# -- which is the whole point of `rb_diff`, and is why the fixture needs two buffers and not
# one. `stg2` is a two-src STAGE and `stg3` a three-src one; they differ in exactly the
# property `flatten_bufferize` (236) tests, and `stg2` is ALSO the node two `pm_add_buffers`
# rules claim. `after1`/`after`/`afterk` are an AFTER with one removable dep, with two, and
# with none, so `remove_noop_afters` has all three of its answers in one arena. `b2u` is
# `Bool -> U32` because `Bool` will not `U32.show`, and it is used by every row, which is why
# it sits above the fixture rather than inside `main`.
def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))
def t_ren7_next() -> U32: P.rf_renumber_next(7)
# `renumber_range` writes `ARange{[n], <the old AxisType>}` and this reads the
# `n` back OUT of the REWRITTEN node's arg -- so the row tests the construction
# and not the parameter that went into it, which is the only way a rule that
# ignored `n` could be caught.
# the AxisType half: `r.arg[1:]` KEEPS it, and `ren_axis_weak` is the row that
# says the port preserved it rather than rebuilding the arg from scratch.
def t_dg_r0t_ans() -> U32:
  P.b2u(Bool.not(O.UOp.is_none(M.hop_ix(P.dg_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_r0t(P.g()))))))
# the AxisType of the node `rf_renumber` BUILT. A rule that rebuilt the whole arg
# would leave this at whatever it hard-coded, so this is the row for `r.arg[1:]`.
def t_nic_b4_ans() -> U32: P.b2u(Bool.not(O.UOp.is_none(M.hop_ix(P.nic_rewrite(P.g_ar(P.g()), P.g_b4(P.g()))))))
# the INDEX arm: the CALL's src0 becomes the STAGE, so the arity is 2 and the
# src0 is NOT the INDEX's src0 (which is the CALL's own INDEX).
def t_rej_ab8() -> U32: U32.from_nat(List.length(&2, O.Op, O.PMEntry.rej(P.ab_entry(8n))))
# `ct_entry(n)` / `dg_entry(n)` / `ab_entry(n)` are declared ABOVE, beside the
# `mops_root*` rows that need them, so a reject-set row and a root-set row read
# the TABLE through one reader.
# the four rows that close the fixture gaps, and what each one is for. Each was
# added because a MEASURED mutation moved nothing, and a row that cannot fail is
# not a row. `rf-mut.py` in `.agents/slop/` re-measures all of them.
#
#   raf_aftn_is_src0 -- `src[0]` KEPT UNCONDITIONALLY. `aftn` is an AFTER whose BODY is
#       itself a dead dep, so Python keeps TWO srcs (the body and the END) and a
#       port that filters `src[0]` too keeps ONE. `raf_after_nsrc` cannot see this
#       because `af`'s src0 is a BUFFER and a BUFFER is not a dead dep either way;
#       this node is the one that can.
#   ab8_stc0_none -- `arg == Invalid`, not `op is CONST`. `sti` is the Invalid store
#       and `sts`/`std` are stores with a BUFFER as src[1], so no two-src STORE in
#   nv_rsaf_ans -- `rf_is_bufid5`'s SIX-op set. `rs` and `rsi` are RESHAPEs over a
#       BUFFER, so a set reduced to {BUFFER} is indistinguishable from the real
#       one. `rsaf` is a RESHAPE over an AFTER, which is a different member.
#   dg_r0t_ans -- `dg_6`, i.e. `renumber_range` REACHED through the dispatch. Every
#       other `dg` row exercises a rule whose answer is "no node", so a table entry
#       with the WRONG op set is invisible. This is the row that makes `dg_6` real.
#   ren_axis_out -- the AxisType of the REWRITTEN node, not of the input. Reading
#       the input (which is what this file did first) cannot see a rule that
#       rebuilt the arg from scratch.
def t_mops_root1() -> U32: P.t_root_n(P.ct_entry(1n))
def t_eng_stages() -> U32: P.eng_stage_n()
# THE REFUSAL, which is the `!=` on the two tails: CT4D's STAGE tail is R1 and its
# INDEX's is R0. Two rows, the comparison itself and the absent answer, so a rule
# that ignored the comparison would move the second and not the first.
# py: `ct4A_fn tails_eq=1` / `ct4D_fn tails_eq=0 out=None`.
def t_ct4a_tail() -> U32: P.b2u(P.rf_stage_tail(P.g_ar(P.g()), P.g_ct4a(P.g()), P.g_ixb4(P.g())))
def t_nic_clik_arg() -> U32:
  P.b2u(O.eq_arg(O.AKernel{O.KernelInfo.of()},
               M.mp_arg(M.hop_ar(P.nic_rewrite(P.g_ar(P.g()), P.g_clik(P.g()))),
                        M.hop_ix(P.nic_rewrite(P.g_ar(P.g()), P.g_clik(P.g()))))))
# the two reject sets, spelled: `ct_4` is `{INDEX}` and `dg_3` is `{PARAM}`, and a
# MISSPELLING of either turns a necessary condition into a false one.
def t_ct5b_pat() -> U32: P.b2u(P.ct_5_claim(P.g_ar(P.g()), P.g_ct5b(P.g())))
# the ANSWER, and it is the `DType.const` + `_mop` wall. py:
# `ct5_stg_of_const out=EXPAND/nsrc2/srcops=[CONST,CONST]`, so the CPython answer's
# src op SEQUENCE is ".58.58" -- recorded here and in the oracle, NOT restated as a
# Bend row, because a row comparing a literal with itself cannot fail.
def t_noopf_nx() -> U32: P.b2u(P.is_noop_after_dep(P.g_ar(P.g()), P.g_nx(P.g())))
def t_dg2_palu() -> U32: P.b2u(P.rf_param_alu(P.G.fx(P.g()), P.g_pa(P.g())))
# `ab_4`'s CLAIM -- a STRICT two-src STAGE -- and `fb`'s `len(x.src) == 2`. These two are
# the two halves of the two-rules-one-node node, and they are separate rows because a
# mutation that drops EITHER one destroys the fixture.
# THE CLAIM COUNT, and why it is a SEPARATE FOLD from the scan. `claim_n` counts how many
# rules of a table CLAIM the node -- the `rf_claimed` half of the `try` WITHOUT the
# dispatch -- so it counts patterns that MATCH rather than rewrites that fired. A scan
# stops at the first answer; a count must not, and that difference is the only reason a
# first-wins bug is visible to a gate at all.
#
# `claim_n` IS AN OP-SET COUNT, and the distinction is load-bearing: `PMEntry.ops` is
# `pdict`'s key, so it is the ROOT op and nothing else. `ab_4`'s src test (a STRICT
# two-src STAGE) lives in its body, so `claim_n` alone counts BOTH `stg2` and `stg3` as
# claimed by tags 3 and 4 -- MEASURED, and `claim_ops_stg2`/`claim_ops_stg3` are the two
# rows that show it. `claim_full` adds the src half back and separates them.
def t_ct5k_pat() -> U32: P.b2u(P.ct_5_claim(P.g_ar(P.g()), P.g_ct5k(P.g())))
# ... and the row that makes M12 sharp. Every other RANGE in the fixture is
# AXIS_WEAK, so "rebuild the AxisType" and "read it off the node" are the same
# function over the rest of the fixture and M12 moved nothing. RGT's input axis is
# `AXIS_DEVICE`, so the two spellings differ here and nowhere else.
def t_ren_axis_out_dev() -> U32:
  P.b2u(O.eq_axis(P.rf_axis(M.hop_ar(P.rf_renumber(P.g_ar(P.g()), P.g_rgt(P.g()), 3)), M.hop_ix(P.rf_renumber(P.g_ar(P.g()), P.g_rgt(P.g()), 3))), O.AXIS_DEVICE{}))
def t_dg_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, P.dg_table()))
def t_mops_child_fb() -> U32: U32.from_nat(List.length(&2, O.Op, P.MOPS_FB()))
def t_fb_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, P.fb_table()))
# `dg_2`'s three conjuncts, one row each, because they are three DIFFERENT
# reasons a PARAM is not a kernel-local slot and only the first is about the tag.
def t_dg2_pat() -> U32: P.b2u(P.rf_param_tagged(P.g_ar(P.g()), P.g_pgt(P.g())))
def t_nv_b4_none() -> U32: P.b2u(O.UOp.is_none(M.hop_ix(P.nv_rewrite(P.g_ar(P.g()), P.g_b4(P.g())))))
# `STORE(x,x)` -> NOOP. TWO rows: the op and the arity, because a NOOP with a src
# would be a different bug and `rb_self_nsrc = 0` is what says "no srcs".
def t_aprt_paluT_none() -> U32: P.b2u(O.UOp.is_none(M.hop_ix(P.aprt_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_pat(P.g())))))
def t_ct8r0_arg() -> U32:
  P.b2u(O.eq_arg(O.ARange{[7], O.AXIS_LOOP{}},
               P.ct8_arg(P.ct_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_ct8r0(P.g())))))
# the axis type is read back OUT of the REBUILT node, and the fallback arm is
# `AXIS_WEAK` so that a rule which rebuilt the arg from scratch -- or answered
# `None`, whose arg is `ANone` -- FAILS this row instead of passing it.
def t_ct5k_claim() -> U32: P.ct_claim_n(P.ct_table(), P.ar_of(P.g_ct5k(P.g())), P.g_ct5k(P.g()))
def t_aprt_b4_none() -> U32: P.b2u(O.UOp.is_none(M.hop_ix(P.aprt_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_b4(P.g())))))
# THE FULL CLAIM, and the row the brief demands: 2 for the two-src STAGE (tags 3
# and 4) and 1 for the three-src one (tag 3 only, because `ab_4`'s src is a STRICT
# two-tuple). Two rules claim ONE node, they DISAGREE, and a first-wins->
# conjunction mutation moves these two and nothing else.
def t_claim_ab_stg2() -> U32: P.claim_full(P.ab_table(), P.G.fx(P.g()), P.g_ar(P.g()), P.g_st2(P.g()))
def t_eng_a() -> String: String.join(P.eng_fixture_rows(P.efx_a(), "a", 14n), "\n")
def t_aprt_none() -> U32: P.b2u(Bool.not(O.UOp.is_none(M.hop_ix(P.aprt_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_r0(P.g()))))))
def t_claim_ops_stg3() -> U32: P.claim_n(P.ab_table(), P.g_ar(P.g()), P.g_st3(P.g()))
# THE FULL CLAIM, and the row the brief demands: 2 for the two-src STAGE (tags 3
# and 4) and 1 for the three-src one (tag 3 only, because `ab_4`'s src is a STRICT
# two-tuple). Two rules claim ONE node, they DISAGREE, and a first-wins->
# conjunction mutation moves these two and nothing else.
def t_nv_rsaf_ans() -> U32:
  P.b2u(U32.is_eq(M.hop_ix(P.nv_rewrite(P.g_ar(P.g()), P.g_rsaf(P.g()))), P.g_af(P.g())))
# -- ct_5: the claim on all three arms, and the claim PREDICATE alone ----------
# py: `ct5_const_claim = 2`, `ct5_cast_claim = 2`, `ct5_buf_claim = 1` -- the
# BUFFER child is claimed by tag 3 ALONE and the CONST/CAST children by 3 and 5.
def t_ct5c_claim() -> U32: P.ct_claim_n(P.ct_table(), P.ar_of(P.g_ct5c(P.g())), P.g_ct5c(P.g()))
# THE ARG ROWS, and why they had to be written at all. `mp_replace` was widened from
# `(op, ar, self, src)` to `(op, arg, ar, self, src)` because `UOp.replace` (ops.py:252)
# takes `arg` as a KWARG -- `kwargs.pop("arg", self.arg)` -- so a rule that replaces only
# `src` passes the node's OWN arg. Four call sites here were left on the 4-arg form and
# the file stopped compiling.
#
# THE COMPILED FILE IS NOT EVIDENCE, and neither is any row that already existed. `cli`,
# `af` and `mst` are all given `ANone` by this fixture, and an AFTER's and an MSTACK's
# arg is `None` in CPython TOO (measured: `raf_after_arg_is_none = 1`,
# `mstack_arg_is_none = 1`), so `eq_arg(rebuilt_arg, original_arg)` on any of them is
# `eq_arg(ANone, ANone)` -- TRUE for a port that preserves the arg AND for one that
# hardcodes `ANone`, which is the mistake that silences this type error. A CALL's arg is a
# `Kernel`, so `clik` is the node that separates the two and `clik0` is the negative one
# row from it at the same shape.
#
# `eq_arg(x, y)` DISPATCHES ON `x` and matches `y` (ops.bend:2308), so the expected arg
# goes first. `py=` from `.agents/slop/rf-arg-oracle.py`, which reports
# `arg_is_own_kernel=1` and `arg_is_none=0` for the rebuild.
def t_ab7_clik_nsrc() -> U32:
  M.mp_nsrc(M.hop_ar(P.ab_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_clik(P.g()))),
            M.hop_ix(P.ab_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_clik(P.g()))))
# the rebuild kept the node's OWN Kernel arg -- py: `arg_is_own_kernel=1`
# THE ROWS, one line per group; every `py=` is printed by CPython, never typed.
#
#  noopf_*  `is_noop_after_dep` (246). Five nodes because the rule is a TWO-OP recursion
#      and one arm is not enough to see it: `noopf_e_n0 = 1` is the descent and
#      `noopf_nx = 0` is the arm that stops it.
#  raf_*  `remove_noop_afters` (249). THREE rows for one rule because its three answers
#      are three different SHAPES -- a rebuilt AFTER, an EXISTING node, and no answer at
#      all -- and `raf_after1_is_src0` proves the second: it is `1` only because the
#      index is COMPARED, which is also why a rewrite here need not intern anything.
#  szs_*  `strip_zero_offset_shrink` (140). `szs_sh1_is_src0 = 0` is the NEGATIVE side,
#      asked as "is it the src0 index" rather than "is the answer absent" -- asking for
#      the absence would be satisfied by any wrong-but-present answer.
#  nic_*  `no_indexing_calls` (143), one row per arm. `nic_calls = 0` is the identity
#      case and it is a REAL answer: a SHRINK with offset 1 strips to itself, so the
#      rebuild IS the CALL and `hop_self` drops it.
#  nv_*  `pm_no_views` (165). `nv_rsi = 0` is the pattern's rejection of a RESHAPE over an
#      INDEX: the pattern is the test and the body is only the answer.
#  rb_*  `pm_remove_bufferize` (131-138). `rb_self_is_noop` and `rb_diff` are the two
#      sides of the ONE identity check in this file, so between them they are all of
#      `upat.py:100-105` as it applies here.
#  aprt_*  `pm_add_param_range_tags` (330). `aprt_empty = 0` is the idempotence row and
#      `aprt_paluT = 0` is the ALU row, and they are different: the first is
#      `ret is not uop`, the second is the `addrspace` conjunct.
#  ren_*  `renumber_range` (299). `ren_arg0`/`ren_next` and `ren7_*` are the two-sided
#      counter rows, and the gate feeds CPython's `ctx.range`.
#  dg_*  `to_define_global` (311-328). `dg_ixpa_ans` is the ONE row that is a
#      fully-ported rule BODY answering a node; `dg_ixpg_ans` is its negative.
#  *_len  the COUNT rows, one per table, so a MISSING rule shows. `ct_len = 9` and
#      `ab_len = 10` are BECAUSE the foreign prefixes are counted in, and `mops_len = 3`
#      and `fb_len = 1` are what make the composition arithmetic checkable.
#  claim_*  the CLAIM COUNT of one fixture node per table. `claim_ab_stg2 = 2` IS the
#      two-rules-claim-one-node row, measured by `.agents/slop/rf-claims.py`, which walks
#      every `UPat.match` over the fixture and reports the only node two rules claim.
#  rej_*  the reject sets that are NON-EMPTY and load-bearing. A MISSPELLED one turns a
#      necessary condition into a false one and the rule then skips a node it should
#      claim, and nothing else in the file would notice.
def t_lay() -> U32: U32.from_nat(List.length(&2, U32, P.G.ix(P.g())))
# THE TABLE READERS, hoisted above every row that uses them: the n-th entry of a
# table, so a reject-set row and a root-set row are both reads of the TABLE
# rather than restatements of it. `Maybe.default` answers a missing index with a
# `0`-tagged entry, so an out-of-range read is a `0` and not a crash.
def t_mstc_claim() -> U32: P.ct_claim_n(P.ct_table(), P.ar_of(P.g_mstc(P.g())), P.g_mstc(P.g()))
# `s.device is None` -- the fold's OUTER `Maybe`, and the two rows are the
# refusal pair: CT8D's `s` is a CONST and CT8B's is a device-carrying BUFFER.
# py: `ct8_devless_s device_is_none=1`, `ct8_dev_s device_is_none=0`.
def t_ct8r_srcops() -> U32:
  P.t_srcops_eq(P.hop_srcops(P.ct_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_ct8r(P.g()))), ".58.53")
# and the answer is a NEW node rather than the input: py `ct8_ix_ms_devless
# is_self=0`. A rule that rebuilt nothing would answer `self` and this would be 0.
def t_ct4d_none() -> U32: P.b2u(O.UOp.is_none(M.hop_ix(P.ct_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_ct4d(P.g())))))
# -- ct_5: the claim on all three arms, and the claim PREDICATE alone ----------
# py: `ct5_const_claim = 2`, `ct5_cast_claim = 2`, `ct5_buf_claim = 1` -- the
# BUFFER child is claimed by tag 3 ALONE and the CONST/CAST children by 3 and 5.
def t_ren_axis_in_dev() -> U32: P.b2u(O.eq_axis(P.rf_axis(P.g_ar(P.g()), P.g_rgd(P.g())), O.AXIS_DEVICE{}))
def t_aprt_pglob() -> U32: P.b2u(Bool.not(O.UOp.is_none(M.hop_ix(P.aprt_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_pg(P.g()))))))
# the OTHER repaired site a CALL reaches, `no_indexing_calls` (rangeify.py:158).
# py: `nic_clik` nsrc=2, `arg_is_own_kernel=1`, `nic_claim_clik=1` (first-wins:
# exactly one pattern claims it, so this is not another rule's answer).
def t_nic_clik_nsrc() -> U32:
  M.mp_nsrc(M.hop_ar(P.nic_rewrite(P.g_ar(P.g()), P.g_clik(P.g()))),
            M.hop_ix(P.nic_rewrite(P.g_ar(P.g()), P.g_clik(P.g()))))
def t_ren_next() -> U32: P.rf_renumber_next(0)
def t_szs_sh1_is_src0() -> U32:
  P.b2u(U32.is_eq(M.hop_ix(P.strip_zero_offset_shrink(P.g_ar(P.g()), P.g_sh1(P.g()))), P.g_b4(P.g())))
def t_mops_root0() -> U32: P.t_root_n(P.ct_entry(0n))
def t_ab8_stc0_none() -> U32: P.b2u(O.UOp.is_none(M.hop_ix(P.ab_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_stc0(P.g())))))
def t_ren_untagged_none() -> U32: P.b2u(O.UOp.is_none(M.hop_ix(P.rf_renumber(P.g_ar(P.g()), P.g_r0(P.g()), 0))))
# the two reject sets, spelled: `ct_4` is `{INDEX}` and `dg_3` is `{PARAM}`, and a
# MISSPELLING of either turns a necessary condition into a false one.
def t_rej_ct4() -> U32: U32.from_nat(List.length(&2, O.Op, O.PMEntry.rej(P.ct_entry(4n))))
def t_fb_sym_stg3() -> U32: P.b2u(P.rf_fb_sym(P.g_ar(P.g()), P.g_st3(P.g())))
# `ab_8`: a STORE of an Invalid constant is a NOOP with no srcs, and a STORE of
# anything else is not rewritten. `ab_8_sti`/`ab_8_std` are the two sides.
def t_aprt_palu_none() -> U32: P.b2u(O.UOp.is_none(M.hop_ix(P.aprt_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_pa(P.g())))))
def t_nic_callm_ans() -> U32: P.b2u(Bool.not(O.UOp.is_none(M.hop_ix(P.nic_rewrite(P.g_ar(P.g()), P.g_clm(P.g()))))))
def t_ct8r_axis() -> U32: P.b2u(O.eq_axis(P.ct8_axis_n(P.ct_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_ct8r(P.g()))), O.AXIS_LOOP{}))
def t_eng_b() -> String: String.join(P.eng_fixture_rows(P.efx_b(), "b", 13n), "\n")
# THE COUNTS. The number of stages the engine drives is SEVEN
# (`get_kernel_graph`, rangeify.py:341-376), and the number of TABLES it can
# drive is EIGHT of this file's ten -- `fb` and `dg` are not in
# `get_kernel_graph`'s seven rewrites.
def t_rb_self_nsrc() -> U32:
  M.mp_nsrc(M.hop_ar(P.rb_rewrite(P.g_ar(P.g()), P.g_sts(P.g()))), M.hop_ix(P.rb_rewrite(P.g_ar(P.g()), P.g_sts(P.g()))))
# THE OTHER SIDE of the identity check. `STORE(B4, BX)` is a two-src STORE whose
# srcs are DIFFERENT nodes, and the rule must NOT fire: without `upat.py:100-105`
# this row would be 1 and every real store would be deleted.
# the AxisType of the node `rf_renumber` BUILT. A rule that rebuilt the whole arg
# would leave this at whatever it hard-coded, so this is the row for `r.arg[1:]`.
def t_ren_axis_out() -> U32:
  P.b2u(O.eq_axis(P.rf_axis(M.hop_ar(P.rf_renumber(P.g_ar(P.g()), P.g_r0t(P.g()), 3)), M.hop_ix(P.rf_renumber(P.g_ar(P.g()), P.g_r0t(P.g()), 3))), O.AXIS_WEAK{}))
# ... and the row that makes M12 sharp. Every other RANGE in the fixture is
# AXIS_WEAK, so "rebuild the AxisType" and "read it off the node" are the same
# function over the rest of the fixture and M12 moved nothing. RGT's input axis is
# `AXIS_DEVICE`, so the two spellings differ here and nowhere else.
# the rebuild kept the node's OWN Kernel arg -- py: `arg_is_own_kernel=1`
def t_ab7_clik_arg() -> U32:
  P.b2u(O.eq_arg(O.AKernel{O.KernelInfo.of()},
               M.mp_arg(M.hop_ar(P.ab_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_clik(P.g()))),
                        M.hop_ix(P.ab_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_clik(P.g()))))))
# the negative, the twin with no arg, one row from the positive at the same shape:
# py: `arg_is_own_kernel=0 arg_is_none=1`. So `ab7_clik_arg` is not passing because
# every CALL rebuilds to a Kernel.
def t_noopf_e_n0() -> U32: P.b2u(P.is_noop_after_dep(P.g_ar(P.g()), P.g_e0(P.g())))
def t_claim_ab_stg3() -> U32: P.claim_full(P.ab_table(), P.G.fx(P.g()), P.g_ar(P.g()), P.g_st3(P.g()))
# THE REBUILD, as the src op SEQUENCE. py: `ct8_ix_ms_devless out=INDEX/nsrc1/
# srcops=[CONST]` and `ct8_ix_ms_rng out=INDEX/nsrc2/srcops=[CONST,RANGE]`, and
# `Ops.CONST.value` is 58 while `Ops.RANGE.value` is 53 -- both asked of CPython.
# The two rows are ".58" and ".58.53", and the difference IS the `src[1:]` half,
# which a count could not see.
def t_ct8d_srcops() -> U32:
  P.t_srcops_eq(P.hop_srcops(P.ct_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_ct8d(P.g()))), ".58")
# the MSTACK arm: the CALL's src0 is a MSTACK whose srcs were both stripped, and
# `strip(SH1) = SH1` while `strip(SH0) = B4`, so the arity is still 2.
def t_nic_callm_src0_nsrc() -> U32:
  M.mp_nsrc(M.hop_ar(P.nic_rewrite(P.g_ar(P.g()), P.g_clm(P.g()))), M.mp_src0(M.hop_ar(P.nic_rewrite(P.g_ar(P.g()), P.g_clm(P.g()))), M.hop_ix(P.nic_rewrite(P.g_ar(P.g()), P.g_clm(P.g())))))
def t_spec() -> U32: P.b2u(P.rf_spec())
# the device REFUSAL as a truncated trace: the answer is absent, and the reason is
# the one conjunct. py: `ct8_ix_dev out=None`.
def t_ct8b_none() -> U32: P.b2u(O.UOp.is_none(M.hop_ix(P.ct_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_ct8b(P.g())))))
# -- ct_7: the CLAIM only; the body is the `_min_max` wall ---------------------
# py: `ct7_ix_after tag7_nbind=1 first_tag=7`. The body CRASHES on that shape
# rather than answering -- see the `ct_7` comment above, `ct7_empty_ended_ranges_
# prod = 1 int` -- so there is no CPython answer to gate and the rows are the
# claim and the claim COUNT. The count is what makes mutation M30 (dropping
# `ct_src.of`'s tag-7 body test) sharp: with only `ct7a_claim` present, M30 moved
# NOTHING, because the predicate is written out longhand and no fold reads it.
def t_ct5b_claim() -> U32: P.ct_claim_n(P.ct_table(), P.ar_of(P.g_ct5b(P.g())), P.g_ct5b(P.g()))
# the PREDICATE on its own, so a table entry with the right op set and a body that
# lost its child test is visible, and the reverse.
def t_ren_arg0() -> U32: P.ren_axis0(0, P.g_ar(P.g()), P.g_r0t(P.g()))
def t_gs_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, P.gs_table()))
# the foreign prefix. `mops_rules` is how many `pm_mops` RULES the composition
# shifts every own tag by, and the ROOT/SUB rows above are its three pdict keys.
def t_lb_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, P.lb_table()))
def t_raf_after_nsrc() -> U32:
  M.mp_nsrc(M.hop_ar(P.remove_noop_afters(P.g_ar(P.g()), P.g_af(P.g()))), M.hop_ix(P.remove_noop_afters(P.g_ar(P.g()), P.g_af(P.g()))))
# the PREDICATE on its own, so a table entry with the right op set and a body that
# lost its child test is visible, and the reverse.
def t_ct5c_pat() -> U32: P.b2u(P.ct_5_claim(P.g_ar(P.g()), P.g_ct5c(P.g())))
def t_ab_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, P.ab_table()))
# `s.device is None` -- the fold's OUTER `Maybe`, and the two rows are the
# refusal pair: CT8D's `s` is a CONST and CT8B's is a device-carrying BUFFER.
# py: `ct8_devless_s device_is_none=1`, `ct8_dev_s device_is_none=0`.
def t_ct8d_devnone() -> U32: P.b2u(P.rf_dev_is_none(P.G.fx(P.g()), M.mp_src(P.ar_of(P.g_mstc(P.g())), P.g_mstc(P.g()), 0)))
def t_fb_two_stg2() -> U32: P.b2u(P.rf_fb_two(P.g_ar(P.g()), P.g_st2(P.g())))
def t_szs_n0_is_self() -> U32:
  P.b2u(U32.is_eq(M.hop_ix(P.strip_zero_offset_shrink(P.g_ar(P.g()), P.g_n0(P.g()))), P.g_n0(P.g())))
def t_ct7b_none() -> U32: P.b2u(O.UOp.is_none(M.hop_ix(P.ct_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_ct7b(P.g())))))
# THE CLAIM COUNT. `claim(h, acc)` asks "did this rule CLAIM the node", which is
# the `rf_claimed` half of the `try` WITHOUT the dispatch -- so it is a count of
# patterns that match, not of rewrites that fired. It is a separate fold from the
# scan because a scan STOPS at the first answer and a count must not.
# and the answer is a NEW node rather than the input: py `ct8_ix_ms_devless
# is_self=0`. A rule that rebuilt nothing would answer `self` and this would be 0.
def t_ct8d_new() -> U32:
  P.b2u(Bool.not(U32.is_eq(M.hop_ix(P.ct_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_ct8d(P.g()))), P.g_ct8d(P.g()))))
# THE ARG GATE, and it is the one the old fixture could not express. `UOp` does
# not type-check `arg` against `op` -- measured -- so an INDEX carries an
# `ARange`, which is Python's `(axis_id, AxisType)` pair and the `Range` arg the
# brief names, and `idx.replace(src=...)` (ops.py:252) passes `self.arg` through
# unchanged. py: `ct8R_ix_arg_range arg_is_own_range=1 arg_is_none=0`, and the
# ANONE TWIN one row from it: `ct8N_ix_arg_none arg_is_own_range=0 arg_is_none=1`.
def t_nv_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, P.nv_table()))
# THE ORDER NOTE. A sweep reproduces the DFS's ORDER only where the order is
# not observable, and the order is observable exactly where upstream threads a
# `ctx` COUNTER. This is a CONSTANT, not a measurement, and it says so.
def t_eng_order() -> U32: 1
# py: `ct4A_out = BUFFER/nsrc0/srcops=[]` -- CPython answers a node. The port's
# answer is the `UOp.shrink` wall, so this row is the PORT'S absence and the
# divergence is recorded rather than smoothed into an agreeing row.
def t_ct4a_ans() -> U32: P.b2u(O.UOp.is_none(M.hop_ix(P.ct_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_ct4a(P.g())))))
# THE REFUSAL, which is the `!=` on the two tails: CT4D's STAGE tail is R1 and its
# INDEX's is R0. Two rows, the comparison itself and the absent answer, so a rule
# that ignored the comparison would move the second and not the first.
# py: `ct4A_fn tails_eq=1` / `ct4D_fn tails_eq=0 out=None`.
def t_dg2_pg() -> U32: P.b2u(P.rf_param_tagged(P.g_ar(P.g()), P.g_pg(P.g())))
# -- ct_8: the claim, the device gate, the rebuild and THE ARG -----------------
# py: `ct8_devless_claim = 1` and `ct8_bare_mstack claim_n = 0`.
def t_ct8d_claim() -> U32: P.ct_claim_n(P.ct_table(), P.ar_of(P.g_ct8d(P.g())), P.g_ct8d(P.g()))
def t_ct_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, P.ct_table()))
def t_ct8r0_axis() -> U32: P.b2u(O.eq_axis(P.ct8_axis_n(P.ct_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_ct8r0(P.g()))), O.AXIS_LOOP{}))
# the device REFUSAL as a truncated trace: the answer is absent, and the reason is
# the one conjunct. py: `ct8_ix_dev out=None`.
def t_ct4b_claim() -> U32: P.ct_claim_n(P.ct_table(), P.ar_of(P.g_ct4b(P.g())), P.g_ct4b(P.g()))
# py: `ct4A_out = BUFFER/nsrc0/srcops=[]` -- CPython answers a node. The port's
# answer is the `UOp.shrink` wall, so this row is the PORT'S absence and the
# divergence is recorded rather than smoothed into an agreeing row.
def t_nic_calli_ans() -> U32: P.b2u(Bool.not(O.UOp.is_none(M.hop_ix(P.nic_rewrite(P.g_ar(P.g()), P.g_cli(P.g()))))))
def t_raf_after1_is_src0() -> U32:
  P.b2u(U32.is_eq(M.hop_ix(P.remove_noop_afters(P.g_ar(P.g()), P.g_af1(P.g()))), P.g_b4(P.g())))
# -- ct_7: the CLAIM only; the body is the `_min_max` wall ---------------------
# py: `ct7_ix_after tag7_nbind=1 first_tag=7`. The body CRASHES on that shape
# rather than answering -- see the `ct_7` comment above, `ct7_empty_ended_ranges_
# prod = 1 int` -- so there is no CPython answer to gate and the rows are the
# claim and the claim COUNT. The count is what makes mutation M30 (dropping
# `ct_src.of`'s tag-7 body test) sharp: with only `ct7a_claim` present, M30 moved
# NOTHING, because the predicate is written out longhand and no fold reads it.
def t_ct7a_claim() -> U32:
  P.b2u(Bool.and(M.mp_is(P.ar_of(P.g_ct7a(P.g())), P.g_ct7a(P.g()), O.OpsINDEX{}),
               M.mp_is(P.ar_of(P.g_ct7a(P.g())), M.mp_src0(P.ar_of(P.g_ct7a(P.g())), P.g_ct7a(P.g())), O.OpsAFTER{})))
# `ab_8`: a STORE of an Invalid constant is a NOOP with no srcs, and a STORE of
# anything else is not rewritten. `ab_8_sti`/`ab_8_std` are the two sides.
def t_ab8_sti() -> U32:
  P.b2u(M.mp_is(M.hop_ar(P.ab_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_sti(P.g()))),
              M.hop_ix(P.ab_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_sti(P.g()))), O.OpsNOOP{}))
# -- ct_4: the claim on the discriminating shape, and on its mirror ------------
# py: `ct4A_claim = 2` (tags 3 and 4) and `ct4B_claim = 0`.
def t_ct4a_claim() -> U32: P.ct_claim_n(P.ct_table(), P.g_ar(P.g()), P.g_ct4a(P.g()))
def t_ct8r_arg() -> U32:
  P.b2u(O.eq_arg(O.ARange{[7], O.AXIS_LOOP{}},
               P.ct8_arg(P.ct_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_ct8r(P.g())))))
def t_raf_afterk_none() -> U32:
  P.b2u(O.UOp.is_none(M.hop_ix(P.remove_noop_afters(P.g_ar(P.g()), P.g_afk(P.g())))))
def t_stages() -> U32: U32.from_nat(List.length(&2, U32, P.rf_stages()))
def t_fb_two_stg3() -> U32: P.b2u(P.rf_fb_two(P.g_ar(P.g()), P.g_st3(P.g())))
# `END(NOOP)` -> NOOP, a node ALREADY in the arena. Positive because the rule
# returns the bound name, not `uop`, so `ret is not uop` holds.
def t_rb_e_n0() -> U32:
  P.b2u(U32.is_eq(M.hop_ix(P.rb_rewrite(P.g_ar(P.g()), P.g_e0(P.g()))), P.g_n0(P.g())))
def t_rb_ixstg_none() -> U32: P.b2u(O.UOp.is_none(M.hop_ix(P.rb_rewrite(P.g_ar(P.g()), P.g_ixs(P.g())))))
# the ANSWER, and it is the `DType.const` + `_mop` wall. py:
# `ct5_stg_of_const out=EXPAND/nsrc2/srcops=[CONST,CONST]`, so the CPython answer's
# src op SEQUENCE is ".58.58" -- recorded here and in the oracle, NOT restated as a
# Bend row, because a row comparing a literal with itself cannot fail.
def t_ct5c_ans() -> U32: P.b2u(O.UOp.is_none(M.hop_ix(P.ct_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_ct5c(P.g())))))
# -- ct_8: the claim, the device gate, the rebuild and THE ARG -----------------
# py: `ct8_devless_claim = 1` and `ct8_bare_mstack claim_n = 0`.
def t_ab8_std_none() -> U32:
  P.b2u(O.UOp.is_none(M.hop_ix(P.ab_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_sts(P.g())))))
# `ab_7`: the CALL keeps its arity and its src0 becomes the RESHAPE's src0.
def t_rej_dg3() -> U32: U32.from_nat(List.length(&2, O.Op, O.PMEntry.rej(P.dg_entry(3n))))
def t_nv_rsi_none() -> U32: P.b2u(O.UOp.is_none(M.hop_ix(P.nv_rewrite(P.g_ar(P.g()), P.g_rsi(P.g())))))
# the four rows that close the fixture gaps, and what each one is for. Each was
# added because a MEASURED mutation moved nothing, and a row that cannot fail is
# not a row. `rf-mut.py` in `.agents/slop/` re-measures all of them.
#
#   raf_aftn_is_src0 -- `src[0]` KEPT UNCONDITIONALLY. `aftn` is an AFTER whose BODY is
#       itself a dead dep, so Python keeps TWO srcs (the body and the END) and a
#       port that filters `src[0]` too keeps ONE. `raf_after_nsrc` cannot see this
#       because `af`'s src0 is a BUFFER and a BUFFER is not a dead dep either way;
#       this node is the one that can.
#   ab8_stc0_none -- `arg == Invalid`, not `op is CONST`. `sti` is the Invalid store
#       and `sts`/`std` are stores with a BUFFER as src[1], so no two-src STORE in
#   nv_rsaf_ans -- `rf_is_bufid5`'s SIX-op set. `rs` and `rsi` are RESHAPEs over a
#       BUFFER, so a set reduced to {BUFFER} is indistinguishable from the real
#       one. `rsaf` is a RESHAPE over an AFTER, which is a different member.
#   dg_r0t_ans -- `dg_6`, i.e. `renumber_range` REACHED through the dispatch. Every
#       other `dg` row exercises a rule whose answer is "no node", so a table entry
#       with the WRONG op set is invisible. This is the row that makes `dg_6` real.
#   ren_axis_out -- the AxisType of the REWRITTEN node, not of the input. Reading
#       the input (which is what this file did first) cannot see a rule that
#       rebuilt the arg from scratch.
def t_raf_aftn_is_src0() -> U32:
  P.b2u(U32.is_eq(M.hop_ix(P.remove_noop_afters(P.g_ar(P.g()), P.g_aftn(P.g()))), P.g_n0(P.g())))
# THE OTHER SIDE of the identity check. `STORE(B4, BX)` is a two-src STORE whose
# srcs are DIFFERENT nodes, and the rule must NOT fire: without `upat.py:100-105`
# this row would be 1 and every real store would be deleted.
def t_rb_diff_none() -> U32: P.b2u(O.UOp.is_none(M.hop_ix(P.rb_rewrite(P.g_ar(P.g()), P.g_std(P.g())))))
# `END(NOOP)` -> NOOP, a node ALREADY in the arena. Positive because the rule
# returns the bound name, not `uop`, so `ret is not uop` holds.
def t_ct7a_cnt() -> U32: P.ct_claim_n(P.ct_table(), P.ar_of(P.g_ct7a(P.g())), P.g_ct7a(P.g()))
# the one node WHERE tag 7's reject set is not its claim. `early_reject` is
# `{AFTER}` and it is satisfied by an AFTER in ANY src, so CT7B is claimed by the
# set test and NOT by the pattern. py: `ct7_ix_after tag7_nbind=1`; and for CT7B
# CPython's `rewrite` returns `None` because tag 6, tag 0 and tag 8 all miss and
# tag 7's pattern fails. Measured in `rf-ct-oracle.py` section 1's shape list.
def t_rej_ct7() -> U32: U32.from_nat(List.length(&2, O.Op, O.PMEntry.rej(P.ct_entry(7n))))
# the one node WHERE tag 7's reject set is not its claim. `early_reject` is
# `{AFTER}` and it is satisfied by an AFTER in ANY src, so CT7B is claimed by the
# set test and NOT by the pattern. py: `ct7_ix_after tag7_nbind=1`; and for CT7B
# CPython's `rewrite` returns `None` because tag 6, tag 0 and tag 8 all miss and
# tag 7's pattern fails. Measured in `rf-ct-oracle.py` section 1's shape list.
def t_ct7b_cnt() -> U32: P.ct_claim_n(P.ct_table(), P.ar_of(P.g_ct7b(P.g())), P.g_ct7b(P.g()))
def t_aprt_len() -> U32: U32.from_nat(List.length(&2, O.PMEntry, P.aprt_table()))
def t_szs_sh0_is_src0() -> U32:
  P.b2u(U32.is_eq(M.hop_ix(P.strip_zero_offset_shrink(P.g_ar(P.g()), P.g_sh0(P.g()))), P.g_b4(P.g())))
def t_noopf_n0() -> U32: P.b2u(P.is_noop_after_dep(P.g_ar(P.g()), P.g_n0(P.g())))
# the AxisType half: `r.arg[1:]` KEEPS it, and `ren_axis_weak` is the row that
# says the port preserved it rather than rebuilding the arg from scratch.
def t_ren_axis_weak() -> U32: P.b2u(O.eq_axis(P.rf_axis(P.g_ar(P.g()), P.g_r0t(P.g())), O.AXIS_WEAK{}))
# the fully-ported `dg_3` body: an INDEX of an ALU PARAM answers the PARAM
# `STORE(x,x)` -> NOOP. TWO rows: the op and the arity, because a NOOP with a src
# would be a different bug and `rb_self_nsrc = 0` is what says "no srcs".
def t_rb_self_is_noop() -> U32:
  P.b2u(M.mp_is(M.hop_ar(P.rb_rewrite(P.g_ar(P.g()), P.g_sts(P.g()))), M.hop_ix(P.rb_rewrite(P.g_ar(P.g()), P.g_sts(P.g()))), O.OpsNOOP{}))
# and its negative: an INDEX of a GLOBAL PARAM does NOT answer. The row prints
# the ABSENCE, so it is `_none` and its 1 is the passing value.
def t_dg_ixpg_none() -> U32:
  P.b2u(O.UOp.is_none(M.hop_ix(P.dg_rewrite(P.G.fx(P.g()), P.g_ar(P.g()), P.g_ipg(P.g())))))
# `dg_2`'s three conjuncts, one row each, because they are three DIFFERENT
# reasons a PARAM is not a kernel-local slot and only the first is about the tag.
# THE OP-SET COUNT, and the two rows are EQUAL -- that is the point. Both STAGEs
# are claimed by tags 3 and 4 on the op set alone, and the `full` count below is
# what separates them. Without the pair, an op-set count would look like a
# first-wins discriminator and is not one.
def t_claim_ops_stg2() -> U32: P.claim_n(P.ab_table(), P.g_ar(P.g()), P.g_st2(P.g()))
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("lay", t_lay())
    b : Unit <- row("ct_len", t_ct_len())
    c : Unit <- row("rb_len", t_rb_len())
    d : Unit <- row("nic_len", t_nic_len())
    e : Unit <- row("nv_len", t_nv_len())
    f : Unit <- row("lb_len", t_lb_len())
    h : Unit <- row("fb_len", t_fb_len())
    i : Unit <- row("ab_len", t_ab_len())
    j : Unit <- row("dg_len", t_dg_len())
    k : Unit <- row("aprt_len", t_aprt_len())
    l : Unit <- row("sk_len", t_sk_len())
    m : Unit <- row("gs_len", t_gs_len())
    n : Unit <- row("mops_rules", t_mops_rules())
    n0 : Unit <- row("mops_root0", t_mops_root0())
    n1 : Unit <- row("mops_root1", t_mops_root1())
    n2 : Unit <- row("mops_root2", t_mops_root2())
    n3 : Unit <- row("mops_child_fb", t_mops_child_fb())
    n4 : Unit <- row("ct_root3", t_ct_root(P.ct_entry(3n)))
    n5 : Unit <- row("ct_root4", t_ct_root(P.ct_entry(4n)))
    n6 : Unit <- row("ct_root5", t_ct_root(P.ct_entry(5n)))
    n7 : Unit <- row("ct_root6", t_ct_root(P.ct_entry(6n)))
    n8 : Unit <- row("ct_root7", t_ct_root(P.ct_entry(7n)))
    n9 : Unit <- row("ct_root8", t_ct_root(P.ct_entry(8n)))
    o : Unit <- row("stages", t_stages())
    p : Unit <- row("ranges_miss", P.t_ranges_miss())
    q : Unit <- row("noopf_n0", t_noopf_n0())
    r : Unit <- row("noopf_nx", t_noopf_nx())
    s : Unit <- row("noopf_e_n0", t_noopf_e_n0())
    u : Unit <- row("noopf_e_nx", t_noopf_e_nx())
    v : Unit <- row("noopf_b4", t_noopf_b4())
    w : Unit <- row("raf_after_nsrc", t_raf_after_nsrc())
    x : Unit <- row("raf_after1_is_src0", t_raf_after1_is_src0())
    y : Unit <- row("raf_afterk_none", t_raf_afterk_none())
    z : Unit <- row("szs_sh0_is_src0", t_szs_sh0_is_src0())
    aa : Unit <- row("szs_sh1_is_src0", t_szs_sh1_is_src0())
    ab : Unit <- row("szs_n0_is_self", t_szs_n0_is_self())
    ac : Unit <- row("nic_calli_ans", t_nic_calli_ans())
    ad : Unit <- row("nic_calls_ans", t_nic_calls_ans())
    ae : Unit <- row("nic_callm_ans", t_nic_callm_ans())
    af : Unit <- row("nic_b4_ans", t_nic_b4_ans())
    ag : Unit <- row("nic_calli_nsrc", t_nic_calli_nsrc())
    ah : Unit <- row("nic_callm_src0_nsrc", t_nic_callm_src0_nsrc())
    ai : Unit <- row("nv_rs_is_src0", t_nv_rs_is_src0())
    aj : Unit <- row("nv_rsi_none", t_nv_rsi_none())
    ak : Unit <- row("nv_b4_none", t_nv_b4_none())
    al : Unit <- row("rb_self_is_noop", t_rb_self_is_noop())
    am : Unit <- row("rb_self_nsrc", t_rb_self_nsrc())
    an : Unit <- row("rb_diff_none", t_rb_diff_none())
    ao : Unit <- row("rb_e_n0", t_rb_e_n0())
    ap : Unit <- row("rb_ixstg_none", t_rb_ixstg_none())
    aq : Unit <- row("aprt_none", t_aprt_none())
    ar : Unit <- row("aprt_r0t_none", t_aprt_r0t_none())
    as : Unit <- row("aprt_pglob", t_aprt_pglob())
    at : Unit <- row("aprt_pgloT_none", t_aprt_pgloT_none())
    au : Unit <- row("aprt_palu_none", t_aprt_palu_none())
    av : Unit <- row("aprt_paluT_none", t_aprt_paluT_none())
    aw : Unit <- row("aprt_b4_none", t_aprt_b4_none())
    ax : Unit <- row("ren_untagged_none", t_ren_untagged_none())
    ay : Unit <- row("ren_arg0", t_ren_arg0())
    az : Unit <- row("ren_next", t_ren_next())
    ba : Unit <- row("ren7_arg0", t_ren7_arg0())
    bb : Unit <- row("ren7_next", t_ren7_next())
    bc : Unit <- row("ren_axis_weak", t_ren_axis_weak())
    bd : Unit <- row("dg_ixpa_ans", t_dg_ixpa_ans())
    be : Unit <- row("dg_ixpg_none", t_dg_ixpg_none())
    be : Unit <- row("dg2_pat", t_dg2_pat())
    bf : Unit <- row("dg2_pg", t_dg2_pg())
    bg : Unit <- row("dg2_palu", t_dg2_palu())
    bh : Unit <- row("claim_ops_stg2", t_claim_ops_stg2())
    bh2 : Unit <- row("claim_ops_stg3", t_claim_ops_stg3())
    bh3 : Unit <- row("claim_ab_stg2", t_claim_ab_stg2())
    bi : Unit <- row("claim_ab_stg3", t_claim_ab_stg3())
    bj : Unit <- row("ab4_stg2", t_ab4_stg2())
    bk : Unit <- row("ab4_stg3", t_ab4_stg3())
    bl : Unit <- row("fb_two_stg2", t_fb_two_stg2())
    bm : Unit <- row("fb_two_stg3", t_fb_two_stg3())
    bn : Unit <- row("fb_sym_stg3", t_fb_sym_stg3())
    bo : Unit <- row("ab8_sti", t_ab8_sti())
    bp : Unit <- row("ab8_std_none", t_ab8_std_none())
    bq : Unit <- row("ab7_cli_nsrc", t_ab7_cli_nsrc())
    br : Unit <- row("rej_ct4", t_rej_ct4())
    bs : Unit <- row("rej_ct7", t_rej_ct7())
    bt : Unit <- row("rej_dg3", t_rej_dg3())
    bu : Unit <- row("rej_ab8", t_rej_ab8())
    bv : Unit <- row("raf_aftn_is_src0", t_raf_aftn_is_src0())
    bw : Unit <- row("ab8_stc0_none", t_ab8_stc0_none())
    bx : Unit <- row("nv_rsaf_ans", t_nv_rsaf_ans())
    by : Unit <- row("dg_r0t_ans", t_dg_r0t_ans())
    bz : Unit <- row("ren_axis_out", t_ren_axis_out())
    ca : Unit <- row("ab7_clik_nsrc", t_ab7_clik_nsrc())
    cb : Unit <- row("ab7_clik_arg", t_ab7_clik_arg())
    cc : Unit <- row("ab7_clik0_arg", t_ab7_clik0_arg())
    cd : Unit <- row("nic_clik_nsrc", t_nic_clik_nsrc())
    ce : Unit <- row("nic_clik_arg", t_nic_clik_arg())
    cf : Unit <- row("ct4a_claim", t_ct4a_claim())
    cg : Unit <- row("ct4b_claim", t_ct4b_claim())
    ch : Unit <- row("ct4a_ans", t_ct4a_ans())
    ci : Unit <- row("ct4a_tail", t_ct4a_tail())
    cj : Unit <- row("ct4d_tail", t_ct4d_tail())
    ck : Unit <- row("ct4d_none", t_ct4d_none())
    cl : Unit <- row("ct5c_claim", t_ct5c_claim())
    cm : Unit <- row("ct5k_claim", t_ct5k_claim())
    cn : Unit <- row("ct5b_claim", t_ct5b_claim())
    co : Unit <- row("ct5c_pat", t_ct5c_pat())
    cp : Unit <- row("ct5k_pat", t_ct5k_pat())
    cq : Unit <- row("ct5b_pat", t_ct5b_pat())
    cr : Unit <- row("ct5c_ans", t_ct5c_ans())
    cs : Unit <- row("ct8d_claim", t_ct8d_claim())
    ct : Unit <- row("mstc_claim", t_mstc_claim())
    cu : Unit <- row("ct8d_devnone", t_ct8d_devnone())
    cv : Unit <- row("ct8b_devnone", t_ct8b_devnone())
    cw : Unit <- row("ct8d_srcops", t_ct8d_srcops())
    cx : Unit <- row("ct8r_srcops", t_ct8r_srcops())
    cy : Unit <- row("ct8d_new", t_ct8d_new())
    cz : Unit <- row("ct8r_arg", t_ct8r_arg())
    da : Unit <- row("ct8r0_arg", t_ct8r0_arg())
    db : Unit <- row("ct8r_axis", t_ct8r_axis())
    dc : Unit <- row("ct8r0_axis", t_ct8r0_axis())
    dd : Unit <- row("ct8b_none", t_ct8b_none())
    de : Unit <- row("ct7a_claim", t_ct7a_claim())
    df : Unit <- row("ct7a_cnt", t_ct7a_cnt())
    dj : Unit <- row("ct7b_cnt", t_ct7b_cnt())
    dk : Unit <- row("ct7b_none", t_ct7b_none())
    dh : Unit <- row("ren_axis_out_dev", t_ren_axis_out_dev())
    dg : Unit <- row("ren_axis_in_dev", t_ren_axis_in_dev())
    ea : Unit <- IO.print(t_eng_a())
    eb : Unit <- IO.print(t_eng_b())
    es : Unit <- row("eng_stages", t_eng_stages())
    et : Unit <- row("eng_tables", t_eng_tables())
    eo : Unit <- row("eng_order", t_eng_order())
    row("spec", t_spec())

