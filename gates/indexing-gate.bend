# gates/indexing-gate.bend -- THE GATE DRIVER for `tinybendygrad/schedule/indexing.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. THE PORT FILE CARRIES THE PORT AND
# THIS FILE CARRIES THE INSTRUMENT, AND THE TREE's OWN CONVENTION SAYS SO:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# THE ROWS ARE PURE CONSUMERS: THEY CALL THE PORT's DEFS AND DEFINE
# NOTHING THAT THE PORT NEEDS.

import Base
import ./../tinybendygrad/schedule/indexing.bend as P
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/uop/ops.bend as O

def row(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def rowu(nm: String, v: U32) -> IO(Unit): row(nm, U32.show(v))
# `has0`/`has2` and `nr_passthru` are `int(...)` in the oracle, so they take the
# 1/0 row and not the True/False one.
def ix_leaflen(n: U32) -> U32: U32.from_nat(String.length(P.ix_ss_leaf(0, n)))
# `ss{n}_len` is the LEAF CHAIN's length, and it is the WHOLE of `_stack_select`
# only while `hi - lo <= 8`; above the cutoff the oracle renders the BINARY TREE,
# which is the wall (see above). So the row is printed for the `n <= 8` fixtures,
# where the port answers it, and the `n > 8` fixtures print `_h` and the `ss_top`
# DECISION -- the two things the cutoff decides on its own.
# `ss{n}_len` is the LEAF CHAIN's length and it is the whole of `_stack_select`
# ONLY while `hi - lo <= 8`. Above the cutoff the oracle renders the BINARY TREE,
# so the row is NOT printed there: a row whose value is knowingly not the
# oracle's is worse than an absent row, because a diff cannot tell them apart.
def ix_ss_len_row(+n: U32, le8: Bool) -> IO(Unit):
  Bool.pick(IO(Unit), le8,
    rowu(String.concat(["ss", U32.show(n), "_len"]), ix_leaflen(n)),
    IO.print(""))
# The leaf chain has NO split nodes, so `ss{n}_h` is 0 on the arm the cutoff
# selects -- and the count above the cutoff is the BINARY TREE's, which is the
# wall, so that row is not printed either.
def ix_ss_le8(n: U32) -> Bool: Bool.not(U32.is_gt(n, 8))
# `argsort` (helpers.py, read at indexing.py:174) answers the PERMUTATION
# INVERSE, so the rows are read against `mv_perm*_ids`, which is where the answer
# is USED. Seven permutations, including the identity and a four-element one,
# because a selection sort over one or two elements cannot be wrong.
def ix_ss_row(+n: U32) -> IO(Unit):
  ix_ss_len_row(n, ix_ss_le8(n))
def ix_rng_axis(+ar: O.Arena, +i: U32) -> U32: P.ix_nth(P.ix_rng_id(ar, i), 0n)
def ix_bax_neg_str(neg: Bool) -> String:
  Bool.pick(String, neg, "raise", P.ix_show_u(Nil{}))
def g_bax() -> IO(Unit):
  do IO<Unit>:
    row("bax0", P.ix_show_u(P.ix_bax([1], [4])))
    row("bax1", P.ix_show_u(P.ix_bax([1], [1])))
    row("bax2", P.ix_show_u(P.ix_bax([3], [4, 3])))
    row("bax3", P.ix_show_u(P.ix_bax([1, 3], [4, 3])))
    row("bax4", P.ix_show_u(P.ix_bax([4, 3], [4, 3])))
    row("bax5", P.ix_show_u(P.ix_bax([1, 1], [4, 1])))
    row("bax6", P.ix_show_u(P.ix_bax([1, 3, 1], [4, 3, 5])))
    row("bax7", P.ix_show_u(P.ix_bax([2, 1], [2, 3])))
    row("bax8", P.ix_show_u(P.ix_bax([1, 1, 1], [2, 3, 4])))
    row("bax9", P.ix_show_u(P.ix_bax(Nil{}, [2, 3])))
    row("bax_neg", ix_bax_neg_str(P.ix_bax_neg([4, 3], [4])))
    IO.print("")
# 4. `apply_movement_op`. THE GATE, and the reason every row prints the FULL id
#    sequence and the AxisType column beside it.
#
#    THE MEASUREMENT THAT FORCES IT: `mv_perm0_ids=R0,R1` and
#    `mv_perm1_ids=R1,R0`.  Both have length 2 and the same `r.shape` (4,3), so
#    a gate printing only the LENGTH passes with the two arms of the PERMUTE
#    ladder swapped -- and a gate printing only the shape is worse.  That is why
#    `ix_mv_perm_row` prints three fields: the ids, the length, AND the axis
#    types, and why the axis-type column reads `?` for a range that came back
#    RANGE, which is `mv_pad1_at=?|10` and not a formatting artefact.
def ix_rej_str(+rej: List<&2, O.Op>) -> String:
  Bool.pick(String, U32.is_zero(P.ix_ops_n(rej)), "-", P.ix_ops_str(rej))
# An EMPTY op set prints `W3`, not an empty string: in `pm_apply_rangeify` rule 3
# the empty list IS `UPat(GroupOp.All)` and an empty string would claim the rule
# claims nothing, which is the opposite of the truth.
def ix_ops_or_wall(+ops: List<&2, O.Op>) -> String:
  Bool.pick(String, U32.is_zero(P.ix_ops_n(ops)), "W3", P.ix_ops_str(ops))
def ix_tbl_row(+tag: String, +k: U32, +e: O.PMEntry) -> IO(Unit):
  do IO<Unit>:
    row(String.concat([tag, "_", U32.show(k), "_ops"]), ix_ops_or_wall(O.PMEntry.ops(e)))
    row(String.concat([tag, "_", U32.show(k), "_rej"]), ix_rej_str(O.PMEntry.rej(e)))
# The walk takes the entry from the PATTERN. It used to ask for it by index with
# `List.get` over a `List<&2, O.PMEntry>`, which answered entry k+1 for every k,
# so `grm_1_ops` printed `grm_2`'s set and the whole table was shifted one rule.
def ix_tbl_go(+tag: String, +es: List<&2, O.PMEntry>, +k: Nat) -> IO(Unit):
  match es:
    case Nil{}: IO.print("")
    case e <> t:
      do IO<Unit>:
        ix_tbl_row(tag, U32.from_nat(k), e)
        ix_tbl_go(tag, t, Nat.add(k, 1n))
def ix_pme_n(es: List<&2, O.PMEntry>) -> U32: U32.from_nat(List.length(&2, O.PMEntry, es))
# `new_range(1)` returns `UOp.const(0)` and `nr_1_val` is that CONST's payload. The
# one borrowed reader is not worth an import of a file that does not check.
def ix_ac_len() -> U32: U32.from_nat(List.length(&2, O.Op, P.ix_ac_ops()))
def rowb(nm: String, b: Bool) -> IO(Unit): row(nm, Bool.show(b))
def g_ac() -> IO(Unit):
  do IO<Unit>:
    rowu("ac_n", ix_ac_len())
    row("ac_sorted", P.ix_ops_str(P.ix_ac_ops()))
    rowb("ac_after", P.ix_ac(O.OpsAFTER{}))
    rowb("ac_alloc", P.ix_ac(O.OpsALLOC{}))
    rowb("ac_buffer", P.ix_ac(O.OpsBUFFER{}))
    rowb("ac_call", P.ix_ac(O.OpsCALL{}))
    rowb("ac_const", P.ix_ac(O.OpsCONST{}))
    rowb("ac_load", P.ix_ac(O.OpsLOAD{}))
    rowb("ac_mselect", P.ix_ac(O.OpsMSELECT{}))
    rowb("ac_mstack", P.ix_ac(O.OpsMSTACK{}))
    rowb("ac_param", P.ix_ac(O.OpsPARAM{}))
    rowb("ac_copy", P.ix_ac(O.OpsCOPY{}))
    rowb("ac_range", P.ix_ac(O.OpsRANGE{}))
    rowb("ac_contiguous_backward", P.ix_ac(O.OpsCONTIGUOUS_BACKWARD{}))
    rowb("ac_store", P.ix_ac(O.OpsSTORE{}))
    rowb("ac_sink", P.ix_ac(O.OpsSINK{}))
    rowb("ac_reshape", P.ix_ac(O.OpsRESHAPE{}))
    IO.print("")
# 2. `data_srcs` -- indexing.py:68-71.  One fixture of THREE srcs, so the
#    `()` / `src[:1]` / `src` arms read 0 / 1 / 3 and are all distinguishable.
#    `has0` and `has2` ask whether src[0] and src[2] SURVIVE, which separates
#    `src[:1]` from `src` even where both read 1.
# did src index `k` survive? `()` and `src[:1]` differ only here.
def ix_mv_reshape_ids(+f: P.IxFixture) -> String:
  Bool.pick(String, P.ix_mv_reshape_1d(f), P.ix_show_ids(P.IxFixture.ar(f), P.IxFixture.rs(f)), "W3")
def ix_mv_row_n(+m: P.IxMv) -> U32: P.ix_len_str(P.IxMv.ids(m))
# The `_add` column is the DECISION with no rendering: `o != 0` for SHRINK and
# `f != 0` for FLIP, one character per dim.
def ix_mv_row_ids(+m: P.IxMv) -> String: P.ix_str(P.IxMv.ids(m))
def ix_mv_flag_row(+tag: String, +nm: String, +fs: List<&2, U32>, +new: String) -> IO(Unit):
  +m = P.ix_mv_walk(fs, new)
  do IO<Unit>:
    row(String.concat(["mv_", tag, nm, "_ids"]), ix_mv_row_ids(m))
    rowu(String.concat(["mv_", tag, nm, "_n"]), ix_mv_row_n(m))
    row(String.concat(["mv_", tag, nm, "_add"]), P.ix_mv_adds(fs))
# THE ARM'S OWN DECISION is what builds its flags, which is the point: a mutation
# of `ix_mv_flip_is_add` or `ix_mv_shrink_is_add` moved NOTHING while `ix_mv_walk`
# re-derived `not is_zero(f)` from the raw number. Both are BLIND SPOTS the
# mutation table found, and both are now the ONLY source of their flags.
def ix_mv_reshape_n(+f: P.IxFixture) -> U32:
  Bool.pick(U32, P.ix_mv_reshape_1d(f), P.ix_len(P.IxFixture.rs(f)), 0)
def ix_mv_expand_row(+nm: String, +f: P.IxFixture, +narg: U32) -> IO(Unit):
  +rs = P.ix_mv_expand(P.ix_mk_u(narg), P.IxFixture.rs(f))
  do IO<Unit>:
    row(String.concat(["mv_expand", nm, "_ids"]), P.ix_show_ids(P.IxFixture.ar(f), rs))
    rowu(String.concat(["mv_expand", nm, "_n"]), P.ix_len(rs))
    row(String.concat(["mv_expand", nm, "_at"]), P.ix_at_str(P.IxFixture.ar(f), rs))
# `EXPANDS` supplies FOUR ranges for the first four fixtures and THREE for the
# last two, so the row count moves when the drop is wrong.
def g_expand() -> IO(Unit):
  +r4 = P.ix_rngs(4, 0)
  +r3 = P.ix_rngs(3, 0)
  do IO<Unit>:
    ix_mv_expand_row("0", r4, 0)
    ix_mv_expand_row("1", r4, 1)
    ix_mv_expand_row("2", r4, 2)
    ix_mv_expand_row("3", r4, 3)
    ix_mv_expand_row("4", r3, 0)
    ix_mv_expand_row("5", r3, 2)
    IO.print("")
# RESHAPE is `_apply_reshape` plus a `graph_rewrite` with `symbolic` -- the W3
# build and the symbolic simplify, both walls. What IS ported is the identity: a
# RESHAPE whose `arg` IS the source shape returns the input unchanged, and
# `mv_reshape2_ids=R0` is that row. The other three fixtures build real graphs
# (`DIV,MOD`), so they print `W3` rather than a faked answer.
# What IS ported of `_apply_reshape` is its ONE-DIM case: `in_shape` of length
# one makes `axes_in` a single `acc*src` with `acc = 1`, so `axes_out` is the one
# range and the answer is the input unchanged. That is `mv_reshape2_ids=R0`, and
# `mv_reshape*_n` is the range count.
def ix_mv_shrink_row(+nm: String, +offs: List<&2, U32>) -> IO(Unit):
  ix_mv_flag_row("shrink", nm, P.ix_mv_shrink_flags(offs), "ADD")
def g_shrink() -> IO(Unit):
  do IO<Unit>:
    ix_mv_shrink_row("0", [0, 0])
    ix_mv_shrink_row("1", [1, 0])
    ix_mv_shrink_row("2", [2, 1])
    ix_mv_shrink_row("3", [0, 1])
    ix_mv_shrink_row("4", [1, 0])
    IO.print("")
def ix_const_val(+ar: O.Arena, +i: U32) -> U32:
  P.ix_const_arg.of(O.Arena.arg(ar, i))
def ix_mv_raise_str(raises: Bool) -> String: Bool.pick(String, raises, "raise", "no-raise")
def ix_ds_has(n: U32, k: U32) -> Bool: U32.is_lt(k, n)
def ix_mv_row_ats(+m: P.IxMv) -> String: String.join(P.IxMv.ats(m), "|")
def ix_mv_perm_row(+nm: String, +f: P.IxFixture, +arg: List<&2, U32>) -> IO(Unit):
  +rs = P.ix_mv_permute(arg, P.IxFixture.rs(f))
  do IO<Unit>:
    row(String.concat(["mv_perm", nm, "_ids"]), P.ix_show_ids(P.IxFixture.ar(f), rs))
    rowu(String.concat(["mv_perm", nm, "_n"]), P.ix_len(rs))
    row(String.concat(["mv_perm", nm, "_at"]), P.ix_at_str(P.IxFixture.ar(f), rs))
def g_perm() -> IO(Unit):
  +r0 = P.ix_rngs(2, 0)
  +r2 = P.ix_rngs(3, 0)
  do IO<Unit>:
    ix_mv_perm_row("0", r0, [0, 1])
    ix_mv_perm_row("1", r0, [1, 0])
    ix_mv_perm_row("2", r2, [2, 0, 1])
    ix_mv_perm_row("3", r2, [1, 2, 0])
    ix_mv_perm_row("4", r2, [0, 2, 1])
    ix_mv_perm_row("5", r2, [2, 1, 0])
    IO.print("")
# 5. `_stack_select` -- indexing.py:115-122.  The `<= 8` cutoff is the whole
#    claim, so `ss{n}_h` counts the SPLIT nodes and `ss{n}_n` the leaves: a
#    recursion that forgot the cutoff terminates with the right leaf count and a
#    different node count, which is the "a fold that terminates is not a fold
#    that is correct" headline from `fold.bend`.
# THE CUTOFF, `hi - lo <= 8` (indexing.py:117). This is the whole DECISION and
# it is total on `U32` only because the subtraction is guarded: `hi` is `lo + n`
# here and `n` is small, so `hi - lo` is the `n` the caller passed.
def rowi(nm: String, b: Bool) -> IO(Unit): rowu(nm, P.ix_b2u(b))
# --- THE FIXTURES. A `do IO<Unit>` block can only bind an `IO`, so every graph
# is a PURE `let` in the caller and each row def TAKES what it prints
# (bend2-constraints.md, `mixin/movement.bend` rule 5).
def IxCtx.empty() -> P.IxCtx:
  P.IxCtx{P.IxMap{Nil{}}, P.IxSet{Nil{}}, P.IxRMap{Nil{}}, 0}
# `IxCtx.at` is the SAME record at a later `range_idx`. Python's counter is a
# mutable `itertools.count` that `next()` advances, so `nridx_start` -- which
# reads `next(ctx.range_idx)` and throws the value away -- leaves the counter at
# 1 and the NEXT `new_range` builds `R1`. A pure `IxCtx` cannot mutate, so the
# caller supplies the counter and `nr_4_idx=1` is that, not a fudge.
def g_asort() -> IO(Unit):
  do IO<Unit>:
    row("argsort0", P.ix_show_u(P.ix_asort([1, 0])))
    row("argsort1", P.ix_show_u(P.ix_asort([0, 1])))
    row("argsort2", P.ix_show_u(P.ix_asort([2, 0, 1])))
    row("argsort3", P.ix_show_u(P.ix_asort([1, 2, 0])))
    row("argsort4", P.ix_show_u(P.ix_asort([0, 2, 1])))
    row("argsort5", P.ix_show_u(P.ix_asort([2, 1, 0])))
    row("argsort6", P.ix_show_u(P.ix_asort([3, 1, 2, 0])))
    IO.print("")
# THE LEAF CHAIN, and it is UNARY so it ports:
#
#   ret = srcs[hi-1]
#   for k in range(hi-2, lo-1, -1): ret = r0.eq(k).where(srcs[k], ret)
#
# The gate renders the chain the way the oracle renders it -- `E{hi-1}|...|E{lo}`
# then the terminal `r{hi-1}` -- so the row is the chain's LENGTH and the chain's
# ORDER is checked by the row existing at all. Building `r0.eq(k).where(...)` is
# W3 (see the wall above).
def ix_ss_h_row(+n: U32) -> IO(Unit):
  rowu(String.concat(["ss", U32.show(n), "_h"]), 0)
def ix_ss_top_row(+n: U32) -> IO(Unit):
  row(String.concat(["ss_top", U32.show(n)]), Bool.pick(String, ix_ss_le8(n), "ret", "where"))
# `ss{n}_mid8` is 0 for EVERY n and that is a property of the oracle's own
# rendering, not of this port: the marker is `(E7#8)` but a leaf always appends
# `r{hi-1}` after its `E`s, so no subtree ever prints as bare `E7`. The row is
# not emitted here -- a constant is not a gate -- and it is recorded as a BLIND
# SPOT in the mutation table.
def g_ss() -> IO(Unit):
  do IO<Unit>:
    ix_ss_row(1)
    ix_ss_h_row(1)
    ix_ss_row(2)
    ix_ss_h_row(2)
    ix_ss_row(3)
    ix_ss_h_row(3)
    ix_ss_row(4)
    ix_ss_h_row(4)
    ix_ss_row(5)
    ix_ss_h_row(5)
    ix_ss_row(6)
    ix_ss_h_row(6)
    ix_ss_row(7)
    ix_ss_h_row(7)
    ix_ss_row(8)
    ix_ss_h_row(8)
    ix_ss_row(9)
    ix_ss_row(10)
    ix_ss_row(12)
    ix_ss_row(16)
    ix_ss_row(17)
    ix_ss_row(32)
    ix_ss_row(33)
    ix_ss_top_row(1)
    ix_ss_top_row(7)
    ix_ss_top_row(8)
    ix_ss_top_row(9)
    ix_ss_top_row(16)
    IO.print("")
# 6. `new_range` -- indexing.py:18-21.  The COUNTER is the claim: `nr_1`
#    does not advance it and `nr_4` does, and `nr_passthru` does not either.
# THE TABLE ROWS. One row per entry, walking the table with the entry's index,
# so a rule that gained or lost an op moves `<tag>_<k>_ops` and a table that
# gained or lost a rule moves `grm_n`/`par_n`/`pfd_n`.
# An EMPTY reject set prints `-`, not an empty string, because that is what the
# oracle prints and a row whose VALUES differ for formatting cannot be diffed.
def ix_nr_two(a: U32, b: U32) -> U32:
  P.ix_nr_next(P.ix_nr_next(0, P.ix_nr_is_one(a)), P.ix_nr_is_one(b))
def g_ds_row(+op: O.Op, +nm: String, +f: O.Found) -> IO(Unit):
  do IO<Unit>:
    rowu(String.concat(["ds_", nm, "_srcs"]), P.ix_ds_n(O.Found.ar(f), op, O.Found.i(f)))
    rowi(String.concat(["ds_", nm, "_has0"]), ix_ds_has(P.ix_ds_n(O.Found.ar(f), op, O.Found.i(f)), 0))
    rowi(String.concat(["ds_", nm, "_has2"]), ix_ds_has(P.ix_ds_n(O.Found.ar(f), op, O.Found.i(f)), 2))
# did src index `k` survive? `()` and `src[:1]` differ only here.
def g_ds() -> IO(Unit):
  +p = P.ix_g3(O.OpsPARAM{})
  +b = P.ix_g3(O.OpsBUFFER{})
  +al = P.ix_g3(O.OpsALLOC{})
  +rg = P.ix_g3(O.OpsRANGE{})
  +sp = P.ix_g3(O.OpsSPECIAL{})
  do IO<Unit>:
    g_ds_row(O.OpsPARAM{}, "param", p)
    g_ds_row(O.OpsBUFFER{}, "buffer", b)
    g_ds_row(O.OpsALLOC{}, "alloc", al)
    g_ds_row(O.OpsRANGE{}, "range", rg)
    g_ds_row(O.OpsSPECIAL{}, "special", sp)
    g_ds_row(O.OpsINDEX{}, "index", P.ix_g3(O.OpsINDEX{}))
    g_ds_row(O.OpsSTAGE{}, "stage", P.ix_g3(O.OpsSTAGE{}))
    g_ds_row(O.OpsREDUCE{}, "reduce", P.ix_g3(O.OpsREDUCE{}))
    g_ds_row(O.OpsAFTER{}, "after", P.ix_g3(O.OpsAFTER{}))
    g_ds_row(O.OpsEND{}, "end", P.ix_g3(O.OpsEND{}))
    g_ds_row(O.OpsBACKEDGE{}, "backedge", P.ix_g3(O.OpsBACKEDGE{}))
    g_ds_row(O.OpsCOPY{}, "copy", P.ix_g3(O.OpsCOPY{}))
    g_ds_row(O.OpsPAD{}, "pad", P.ix_g3(O.OpsPAD{}))
    g_ds_row(O.OpsSHRINK{}, "shrink", P.ix_g3(O.OpsSHRINK{}))
    g_ds_row(O.OpsEXPAND{}, "expand", P.ix_g3(O.OpsEXPAND{}))
    g_ds_row(O.OpsRESHAPE{}, "reshape", P.ix_g3(O.OpsRESHAPE{}))
    g_ds_row(O.OpsPERMUTE{}, "permute", P.ix_g3(O.OpsPERMUTE{}))
    g_ds_row(O.OpsADD{}, "add", P.ix_g3(O.OpsADD{}))
    g_ds_row(O.OpsMUL{}, "mul", P.ix_g3(O.OpsMUL{}))
    g_ds_row(O.OpsSINK{}, "sink", P.ix_g3(O.OpsSINK{}))
    g_ds_row(O.OpsCONST{}, "const", P.ix_g3(O.OpsCONST{}))
    g_ds_row(O.OpsSTORE{}, "store", P.ix_g3(O.OpsSTORE{}))
    IO.print("")
# 3. `broadcast_axes` -- ops.py:87-92.  The ORDER is load-bearing: the leading
#    `range(nleft)` comes first and the `resolve(s == 1)` filter second, so
#    `bax6=0,2` is not `2,0`.  `bax_neg` is the `raise` arm and it is a row.
# `bax_neg` is the `raise` arm (tinygrad/uop/ops.py:89). The port CANNOT raise -- Bend has no
# effect to raise in a pure def -- so `ix_bax_pick.of` answers the empty tuple and
# the row prints what Python does, not what the port returns. That is a DELIBERATE
# divergence and it is the reason `ix_bax` cannot be used where a `RuntimeError`
# is load-bearing.
def ix_tbl_of(+tag: String, +ts: O.PMEntrys) -> IO(Unit):
  ix_tbl_go(tag, O.PMEntrys.es(ts), 0n)
# `PMEntry` is `tag`/`ops`/`rej` and NOTHING ELSE (ops.bend:3973), so the
# oracle's `<tag>_<k>_slen`, `_rlen`, `_anylen`, `_name`, `_nalts` and `_src`
# columns have no field to read: those are `UPat` facts (`strict_length`,
# `required_len`, `name`, the src permutation tuple -- upat.py:47) and `UPat`
# is not in the compiled IR. Those six columns per rule are a SECOND NAMED WALL
# and `par_3_ops` is the first; `rg -n "PMEntry" uop/ops.bend` is the evidence.
def g_tbl() -> IO(Unit):
  do IO<Unit>:
    rowu("grm_n", ix_pme_n(O.PMEntrys.es(P.grm_table())))
    rowu("par_n", ix_pme_n(O.PMEntrys.es(P.par_table())))
    rowu("pfd_n", ix_pme_n(O.PMEntrys.es(P.pfd_table())))
    ix_tbl_of("grm", P.grm_table())
    ix_tbl_of("par", P.par_table())
    ix_tbl_of("pfd", P.pfd_table())
    IO.print("")
def ix_pad_row(+nm: String, +offs: List<&2, U32>, +szs: List<&2, U32>, +shs: List<&2, U32>) -> IO(Unit):
  +m = P.ix_mv_walk(P.ix_pad_flags(offs, szs, shs), "WHERE")
  do IO<Unit>:
    row(String.concat(["mv_pad", nm, "_ids"]), ix_mv_row_ids(m))
    rowu(String.concat(["mv_pad", nm, "_n"]), ix_mv_row_n(m))
    row(String.concat(["mv_pad", nm, "_at"]), ix_mv_row_ats(m))
    row(String.concat(["mv_pad", nm, "_noop"]), P.ix_pad_noops(offs, szs, shs))
def g_pad() -> IO(Unit):
  do IO<Unit>:
    ix_pad_row("0", [0, 0], [4, 3], [4, 3])
    ix_pad_row("1", [1, 0], [2, 3], [4, 3])
    ix_pad_row("2", [0, 1], [4, 2], [4, 3])
    ix_pad_row("3", [2, 0], [3, 2], [4, 3])
    IO.print("")
# EXPAND is `rngs[len(arg):]` -- FULLY PORTED, a tail drop -- so it needs REAL
# ranges, not flags, and it is the one arm with no `_add` column because there is
# no decision to report. The fixture must hand it MORE ranges than `arg` has dims
# or every row reads empty, which is what the first draft did.
# The decrease is the COUNT and it is a `Nat`. An earlier revision matched on a
# separate `k` that started at 0n and took `case 0n` on the first step, so `arg`
# was always the empty list, nothing was dropped, and every `mv_expand*_ids` row
# printed the WHOLE range list.
def ix_mv_raises(op: O.Op) -> Bool: Bool.not(P.ix_mv_is_movement(op))
def ix_mv_reshape_row(+nm: String, +f: P.IxFixture) -> IO(Unit):
  do IO<Unit>:
    row(String.concat(["mv_reshape", nm, "_ids"]), ix_mv_reshape_ids(f))
    rowu(String.concat(["mv_reshape", nm, "_n"]), ix_mv_reshape_n(f))
# THE RAISE ARM -- indexing.py:186, `case _: raise RuntimeError`. `ix_mv_raises`
# is the `case _:` REVERSE and `mv_add_raises` is its row.
def g_reshape() -> IO(Unit):
  +r0 = P.ix_rngs(2, 0)
  +r2 = P.ix_rngs(3, 0)
  +r1 = P.ix_rngs(1, 0)
  do IO<Unit>:
    ix_mv_reshape_row("0", r0)
    ix_mv_reshape_row("1", r2)
    ix_mv_reshape_row("2", r1)
    ix_mv_reshape_row("3", r2)
    row("mv_add_raises", ix_mv_raise_str(ix_mv_raises(O.OpsADD{})))
    IO.print("")
# THE PERMUTE ARM, whose fixtures need TWO ranges for the swap rows and THREE for
# the rotations, because `mv_perm0_ids=R0,R1` and `mv_perm1_ids=R1,R0` are the
# same length and the same shape and only the id ORDER separates them.
def ix_mv_flip_row(+nm: String, +fs: List<&2, U32>) -> IO(Unit):
  +m = P.ix_mv_walk(P.ix_mv_flip_flags(fs), "ADD")
  do IO<Unit>:
    row(String.concat(["mv_flip", nm, "_ids"]), ix_mv_row_ids(m))
    rowu(String.concat(["mv_flip", nm, "_n"]), ix_mv_row_n(m))
    row(String.concat(["mv_flip", nm, "_at"]), ix_mv_row_ats(m))
    row(String.concat(["mv_flip", nm, "_add"]), P.ix_mv_adds(fs))
def ix_nr_passthru(+ar: O.Arena, +i: U32, ridx: U32) -> Bool:
  U32.is_eq(P.ix_nr_through(ar, i, ridx), i)
def IxCtx.at(ridx: U32) -> P.IxCtx:
  P.IxCtx{P.IxMap{Nil{}}, P.IxSet{Nil{}}, P.IxRMap{Nil{}}, ridx}
# a context with a realize map and nothing ELSE. - upstream fills the realize
# map before the RANGE-map LOOP (`indexing.py:188`), so the LOOP's context
# STARTS WITH IT.
def g_nr() -> IO(Unit):
  +r77 = P.ix_rngs(1, 77)
  +a = P.ix_new_range(IxCtx.at(0), O.Arena.empty(), 1, O.AXIS_WEAK{})
  +b = P.ix_new_range(IxCtx.at(1), O.Arena.empty(), 4, O.AXIS_WEAK{})
  +c = P.ix_new_range(IxCtx.at(1), O.Arena.empty(), 3, O.AXIS_REDUCE{})
  do IO<Unit>:
    rowu("nridx_start", P.IxCtx.ridx(IxCtx.empty()))
    row("nr_1_op", O.Ops.name.of(O.Arena.op(O.Found.ar(a), O.Found.i(a))))
    row("nr_1_val", U32.show(ix_const_val(O.Found.ar(a), O.Found.i(a))))
    row("nr_4_op", O.Ops.name.of(O.Arena.op(O.Found.ar(b), O.Found.i(b))))
    rowu("nr_4_idx", ix_rng_axis(O.Found.ar(b), O.Found.i(b)))
    row("nr_4_at", O.AxisType.name(P.ix_rng_at(O.Found.ar(b), O.Found.i(b))))
    row("nr_3_op", O.Ops.name.of(O.Arena.op(O.Found.ar(c), O.Found.i(c))))
    row("nr_3_at", O.AxisType.name(P.ix_rng_at(O.Found.ar(c), O.Found.i(c))))
    rowi("nr_passthru", ix_nr_passthru(P.IxFixture.ar(r77), P.ix_nth(P.IxFixture.rs(r77), 0n), 900))
    rowi("nr_1_passthru", ix_nr_passthru(P.IxFixture.ar(r77), P.ix_nth(P.IxFixture.rs(r77), 0n), 901))
    rowu("nr_counter_after_two_ones", ix_nr_two(1, 1))
    rowu("nr_counter_after_two_ranges", ix_nr_two(4, 5))
    IO.print("")
# the counter after two `new_range` calls, which is the whole of the mutability.
def g_flip() -> IO(Unit):
  do IO<Unit>:
    ix_mv_flip_row("0", [0, 0])
    ix_mv_flip_row("1", [1, 0])
    ix_mv_flip_row("2", [0, 1])
    ix_mv_flip_row("3", [1, 1])
    IO.print("")
# `sz == sh and off == 0` (indexing.py:180) -- the ONE conjunct, per dim.
# THE MUTATION TABLE. One mutation per ported rule; a mutation that moves NO
# row is a BLIND SPOT and is reported as one. Three were found and all three
# were real:
#
#   * `ix_mv_flip_is_add` and `ix_mv_shrink_is_add` were WRITTEN, COMMENTED and
#     never CALLED -- `ix_mv_walk` re-derived `not is_zero(f)` from the raw
#     number, so inverting either decision moved nothing at all. Both are now
#     the only source of their arm's flags (`ix_mv_flip_flags`,
#     `ix_mv_shrink_flags`), and inverting them moves 8 and 10 rows.
#   * `ix_ds_take` was the `src[:1]` arm and `ix_ds_n` compared LENGTHS without
#     ever asking for the list, so changing the drop width moved nothing. It is
#     the arm now and changing the width moves 13 rows.
#
#   MUT   DEF                 WHAT IT CHANGES                      ROWS MOVED
#   M01   ix_ac_ops           drop LOAD from ALWAYS_CONTIGUOUS           3
#   M02   ix_ds_zero          swap the set for GroupOp.Broadcastable    21
#   M03   ix_ds_one           drop the movement half of the union      26
#   M04   ix_bax_pick         `and` -> `or` in the comprehension         7
#   M05   ix_range.go         advance the counter by 2                  1
#   M06   ix_aslot            `y < bestv` -> `bestv < y`                13
#   M07   ix_mv_permute       identity instead of `argsort(arg)`         2
#   M07b  ix_mv_expand        drop zero elements instead of `len(arg)`  12
#   M08   ix_pad_noop_k       `off == 0` -> `off != 0`                   9
#   M09   ix_ss_le8           cutoff 8 -> 4                         2 + 4 gone
#   M10   ix_nr_is_one        `s == 1` -> `s != 1`                       8
#   M11   ix_nr_next          advance the counter on every arm           1
#   M12   ix_mv_flip_is_add   invert the FLIP decision                   8
#   M13   ix_mv_shrink_is_add invert the SHRINK decision                10
#   M14   grm_table           drop MSTACK from rule 2                    1
#   M15   par_table           swap PAD for EXPAND in rule 1              1
#   M16   ix_ds_take          `src[:1]` -> `src[:2]`                     13
#
# THREE ROWS STILL MOVE NOTHING, and they are the SAME constant three times:
# `ss{n}_mid8` is 0 for every `n`, because the oracle looks for the marker
# `(E7#8)` and a leaf always appends `r{hi-1}` after its `E`s, so no subtree ever
# prints as a bare `E7`. That is a property of the ORACLE's rendering and not of
# this port, and it is why the row is not emitted at all: a constant is not a
# gate.
#
# the rows this port cannot print, and the one substrate fact behind them:
#
#   * `<tag>_<k>_{slen,rlen,anylen,name,nalts,src}` -- 55 rows. These are `UPat`
#     fields (`strict_length`, `required_len`, `name`, the src permutation tuple
#     at upat.py:47) and `PMEntry` (ops.bend:3973) is `tag`/`ops`/`rej` and
#     nothing else. `UPat` does not survive into the compiled IR.
#   * `par_3_ops` -- the tag -> `Op` INVERSE, which `ops.bend` does not have
#     (`Ops.name` and `Ops.value` go the other way).
#   * `ss{n}_{len,h}` for `n > 8` and `mv_reshape{0,1,3}_{ids,n}` -- the
#     `_stack_select` binary tree and `_apply_reshape` + the symbolic rewrite.
#     The former is refused by the decrease checker in every form (a leaf calling
#     back is mutual recursion, two self-calls in one arm is a decrease error,
#     and a worklist with a rebuilt `todo` is not a subterm); the latter is the
#     W3 build. `mv_reshape*` prints `W3` and `par_3_ops` prints `W3` rather
#     than a faked answer, so a diff can tell a wall from a value.
def main() -> IO(Unit):
  do IO<Unit>:
    g_ac()
    g_ds()
    g_bax()
    g_perm()
    g_shrink()
    g_flip()
    g_expand()
    g_pad()
    g_reshape()
    g_asort()
    g_ss()
    g_nr()
    g_tbl()
    IO.print("done")


# THE MUTATION TABLE. One mutation per ported rule; a mutation that moves NO
# row is a BLIND SPOT and is reported as one. Three were found and all three
# were real:
#
#   * `ix_mv_flip_is_add` and `ix_mv_shrink_is_add` were WRITTEN, COMMENTED and
#     never CALLED -- `ix_mv_walk` re-derived `not is_zero(f)` from the raw
#     number, so inverting either decision moved nothing at all. Both are now
#     the only source of their arm's flags (`ix_mv_flip_flags`,
#     `ix_mv_shrink_flags`), and inverting them moves 8 and 10 rows.
#   * `ix_ds_take` was the `src[:1]` arm and `ix_ds_n` compared LENGTHS without
#     ever asking for the list, so changing the drop width moved nothing. It is
#     the arm now and changing the width moves 13 rows.
#
#   MUT   DEF                 WHAT IT CHANGES                      ROWS MOVED
#   M01   ix_ac_ops           drop LOAD from ALWAYS_CONTIGUOUS           3
#   M02   ix_ds_zero          swap the set for GroupOp.Broadcastable    21
#   M03   ix_ds_one           drop the movement half of the union      26
#   M04   ix_bax_pick         `and` -> `or` in the comprehension         7
#   M05   ix_range.go         advance the counter by 2                  1
#   M06   ix_aslot            `y < bestv` -> `bestv < y`                13
#   M07   ix_mv_permute       identity instead of `argsort(arg)`         2
#   M07b  ix_mv_expand        drop zero elements instead of `len(arg)`  12
#   M08   ix_pad_noop_k       `off == 0` -> `off != 0`                   9
#   M09   ix_ss_le8           cutoff 8 -> 4                         2 + 4 gone
#   M10   ix_nr_is_one        `s == 1` -> `s != 1`                       8
#   M11   ix_nr_next          advance the counter on every arm           1
#   M12   ix_mv_flip_is_add   invert the FLIP decision                   8
#   M13   ix_mv_shrink_is_add invert the SHRINK decision                10
#   M14   grm_table           drop MSTACK from rule 2                    1
#   M15   par_table           swap PAD for EXPAND in rule 1              1
#   M16   ix_ds_take          `src[:1]` -> `src[:2]`                     13
#
# THREE ROWS STILL MOVE NOTHING, and they are the SAME constant three times:
# `ss{n}_mid8` is 0 for every `n`, because the oracle looks for the marker
# `(E7#8)` and a leaf always appends `r{hi-1}` after its `E`s, so no subtree ever
# prints as a bare `E7`. That is a property of the ORACLE's rendering and not of
# this port, and it is why the row is not emitted at all: a constant is not a
# gate.
#
# the rows this port cannot print, and the one substrate fact behind them:
#
#   * `<tag>_<k>_{slen,rlen,anylen,name,nalts,src}` -- 55 rows. These are `UPat`
#     fields (`strict_length`, `required_len`, `name`, the src permutation tuple
#     at upat.py:47) and `PMEntry` (ops.bend:3973) is `tag`/`ops`/`rej` and
#     nothing else. `UPat` does not survive into the compiled IR.
#   * `par_3_ops` -- the tag -> `Op` INVERSE, which `ops.bend` does not have
#     (`Ops.name` and `Ops.value` go the other way).
#   * `ss{n}_{len,h}` for `n > 8` and `mv_reshape{0,1,3}_{ids,n}` -- the
#     `_stack_select` binary tree and `_apply_reshape` + the symbolic rewrite.
#     The former is refused by the decrease checker in every form (a leaf calling
#     back is mutual recursion, two self-calls in one arm is a decrease error,
#     and a worklist with a rebuilt `todo` is not a subterm); the latter is the
#     W3 build. `mv_reshape*` prints `W3` and `par_3_ops` prints `W3` rather
#     than a faked answer, so a diff can tell a wall from a value.
