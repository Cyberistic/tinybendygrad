# codegen/late/linearizer.bend -- port of tinygrad/codegen/late/linearizer.py
#
# ONE BEND FILE PER UPSTREAM .py, AT THE SAME PATH. This was `codegen/late.bend`
# until the 1:1 ruling; `codegen/late/regalloc.bend` and `codegen/late/gater.bend` are
# the other two slices, the rows are the SAME rows, and 128 before the split is 128
# across the three after it.
#
# THIS FILE ALSO CARRIES THE SHARED SUBSTRATE. `linearizer.py` needs an assoc list
# (`out_degree`, `priorities`, `nkey`, `CFGContext.deps`, `CFGContext.nesting`) and so
# does every other table in the lowerer, and Bend's `Map` is string-keyed only while
# all seven of regalloc's dicts are `U32`-keyed -- so ONE `RaTb` serves them all. It
# has no upstream counterpart, so it lives in the FIRST of the three files in Python's
# order and `regalloc.bend` imports it as `LT`. `gater.bend` needs none of it.
#
# THE DEF-BY-DEF MAP FOR ALL THREE FILES follows, whole; each of the other two points
# back at it rather than repeating it.
#
# `regalloc.py:69`'s `assert` -- bend has no assert form and no row can see an assert
# fire. TWO VALUES ARE ALSO NOT CARRIED and both are named below: `Register.size`
# (W5, unobservable because `Register.__repr__` is the name) and the three renderer
# hooks' own bodies (`assign_spill_slot`, `fill`, `spill`), which are
# `NotImplementedError` in tinygrad's own base class and which the ORACLE supplies.
#
#   tinygrad/codegen/late/linearizer.py    96 lines   -> lt_*, lt_cfg_*, se_*   96/96
#   tinygrad/codegen/late/regalloc.py     118 lines   -> ra_*, rw_*          117/118
#   tinygrad/codegen/late/gater.py         29 lines   -> gt_*                    29/29
#
# THE DEF-BY-DEF MAP, and every row names the Python line it is a row for:
#
#   linearizer.py:8-51    linearize            lt_linearize            lin_u<i> x19
#   linearizer.py:11,16-17 out_degree          lt_deg                  (via lin_u<i>)
#   linearizer.py:20      run_count=prod(...)  lt_rc                    rc_* x6
#   linearizer.py:24-32   the priority ladder  lt_po / lt_po_op         po_* x9
#   linearizer.py:26      extra=u.arg.slot     -- NOT A FIELD            lin_exmix
#   linearizer.py:36      nkey / the sort      LtKey, lt_srt, lt_key    lin_nkey, lin_ord
#   linearizer.py:39-46   the heap loop        lt_hp.*, lt_hq.*         lin_u<i> x19
#   linearizer.py:46      newlst[::-1]         -- elided, see the header
#   linearizer.py:48-50   DEBUG_LINEARIZE      DROPPED (env-gated)
#   linearizer.py:53-81   CFGContext           cfg_ctx, cfg_sib, cfg_ed cfg_* x5
#   linearizer.py:68      the nesting scan     cfg_nest.*               (via cfg_*)
#   linearizer.py:77      the zipped dispatch  cfg_bucket               (via cfg_*)
#   linearizer.py:80      the assert           W3                       --
#   linearizer.py:83-85   pm_add_control_flow  cfg_tbl, cfg_rewrite     cfg_hits, cfg_tbl_*
#   linearizer.py:87-91   do_split_ends        se_rngs_of, se_split     se_rngs, se_ops,
#                                                                        se_len, se_nsrc
#   linearizer.py:89      the `else s.ranges`  W1                       --
#   linearizer.py:93-96   pm_split_ends        se_tbl, se_fired         se_tbl_*, se_fired,
#                                                                        se_miss
#   regalloc.py:8         PSEUDO_OPS           ra_is_pseudo, ra_pseudo_n rw_pseudo_n
#   regalloc.py:10-12     vdef                 ra_at, ra_rdef            (via ra<t>_lr)
#   regalloc.py:13-21     the ctor             ra_st0, RaSt.*            --
#   regalloc.py:22-29     live_range + loops   ra_lr.*, ra_hi, ra_lastuse ra<t>_lr
#   regalloc.py:32-37     the five dicts       RaSt (7 tables + in)      ra<t>_spills,
#                                                                        ra<t>_before
#   regalloc.py:39-45     alloc                ra_dist, ra_linv,         ra<t>_a<i>,
#                         (first-wins max)     ra_alloc.*, ra_del        ra1_a7 v ra0_a7
#   regalloc.py:48-53     fill                 ra_fill.*, ra_slot        ra<t>_spills,
#                                                                        ra<t>_before
#   regalloc.py:55-63     the uses             ra_use.*, ra_uses.*       ra<t>_a<i>
#   regalloc.py:64-77     the defs             ra_def.*, ra_k, ra_tw     ra<t>_a<i>,
#                                                                        ra1_a7
#   regalloc.py:80-90     the RANGE prologue   ra_pro.*, Su, su_le,      ra2_*
#                                                ra_blk, ra_w.*
#   regalloc.py:93-97     the END epilogue     ra_epi.*, ra_head, ra_pop ra2_spills,
#                                                                        ra2_before
#   regalloc.py:99-114    regalloc_rewrite     rw_*                      rw_none
#   regalloc.py:116-118   pm_regalloc_rewrite  ra_tbl, ra_tbl_len,      rw_tbl_len,
#                         (the TABLE)          ra_tbl_ops               rw_tbl_ops
#   gater.py:5-7          move_where_load      gt_w.*, gt_mwl.*         gt_mwl_* x4
#   gater.py:6-7          the dtype predicates W4                       --
#   gater.py:9-29         pm_move_gates_       gt_tbl, gt_ops           gt_tbl_len,
#                         from_index                                     gt_ops0..5
#
# ---------------------------------------------------------------------------
# WHY THIS UNIT IS THE TAIL OF THE LOWERER, and what that buys it. `linearizer`
# folds the axis structure, `regalloc` assigns registers and `gater` decides
# which branches survive. All three are PURE FUNCTIONS OF THE KERNEL'S UOP LIST,
# so a CPython oracle can be handed the same inputs and the two lanes diffed row
# for row -- there is no device, no driver and no codegen cache in the way.
# `regalloc`'s two renderer hooks are the exception and are named below.
#
# ---------------------------------------------------------------------------
# THE INTERFACE, CONSUMED NOT INVENTED. `codegen/kernel.bend` already owns
# `pm_to_program`, whose table carries a PROGRAM gaining a LINEAR, a SOURCE and a
# BINARY one `graph_rewrite` at a time (kernel.bend:466-472), and whose stage
# dispatch is keyed on ARITY with the INS read only to discriminate the two
# two-src rules (kernel.bend:802-865). This file owns what those rules CALL:
#     :429 do_linearize         -> linearize(sink)        -> lt_linearize
#     :436 LinearScanRegallocContext(lin_ctx, lst, ctx)     -> ra_run
#     :376 pm_add_control_flow  -> CFGContext(sink)        -> lt_cfg / lt_acf
#     :366 pm_split_ends        -> do_split_ends           -> lt_se / lt_pm_se
# and `ops.bend`'s arena readers (`Arena.op/src/srcs/nsrc/arg/tag`,
# `Arena.src_without_body`, `UOp.new`) rather than a parallel shape. Every record
# field below is read by a HAND-WRITTEN reader def (constraint 27), because there
# is no `value.field` and no generated projection.
#
# ---------------------------------------------------------------------------
# THE FOUR WALLS, each at the file and line that owns it. W1 and W3 are the SAME
# lowerer wall the coordinator named -- `itertools.product` over a shape plus
# `permute`/`reshape`/`reduce`, which `uop/fold.bend` cannot answer for
# PAD/SHRINK/EXPAND/FLIP (`fold.bend:1620-1626`) -- arriving from two more
# directions. Nothing here answers them and nothing here pretends to.
#
#  W1 `u.ranges` and `r.vmax`  -- linearizer.py:20, :89
#     `run_count = prod([int(r.vmax)+1 for r in u.ranges])`. `u.ranges` is not in
#     `fold.bend` at all (`fold.bend`'s TODO at :2480-2482 is `vmin`/`vmax`/
#     `_min_max`), and `vmax` needs `_min_max`, whose wall is ARITHMETIC:
#     `helpers.bend` has `i64_add/sub/cmp` and NOT `i64_mul/div/mod`. So `lt_rc`
#     IS ported -- it is `prod` over a list of `vmax`es -- and the CALLER that
#     produces the list is the wall. The `lin_vm` row hands `lt_rc` the lists and
#     the `lin_u<i>` rows carry its answers, so the FOLD is gated and the WALL is
#     named. `rc_*` are five more, because on `lin` it only ever sees `[]`, `[3]`
#     and `[15]` -- three cases that cannot tell a product from a sum.
#
#  W2 `x.tuplize` -- linearizer.py:36
#     `sorted(lst, key=lambda x: priorities[x]+(x.tuplize if TUPLE_ORDER else ()))`
#     and `tuplize` is `(self.op.value, repr(self.arg), self.dtype,
#     *src.tuplize)` recursively (ops.py:322-324) -- a structural key holding a
#     `repr` of an arbitrary arg and a dtype value. `TUPLE_ORDER` is a real
#     ContextVar (helpers.py:280, default 1) and setting it 0 makes the key the
#     STABLE `(run_count, priority)` pair, which is exactly `List.sort` with `<=`,
#     measured stable. So this file ports the `TUPLE_ORDER=0` lane exactly and
#     names the `=1` lane W2. `lin_ties=47` of 171 pairs is how much W2 decides
#     on the fixture, and it is a ROW rather than a claim because the whole
#     `TUPLE_ORDER=1` order rests on it.
#
#  W3 `x.backward_slice_with_self` -- linearizer.py:80
#     `assert y.src[1] not in x.backward_slice_with_self`, a backward reachability
#     walk over `src` with a set. It is the ONLY use and the line above it is the
#     `TODO: this can happen! it causes infinite loop in shufflenet` -- so the
#     assert guards exactly the cycle this arena cannot represent (ops.bend's
#     header: the range graph HAS back-edges). `lt_cfg` computes the edges WITHOUT
#     it: the edge COUNT and the edge PAIR are both gated, and the missing check
#     is recorded here instead of being silently satisfied.
#
#  W4 a dtype and an addrspace as VALUES -- linearizer.py:27, gater.py:6-7,25-28
#     `u.addrspace == AddrSpace.LOCAL` is a `Maybe<&2, S.Addr>` out of
#     `F.fold.addr`, and `a.src[0].dtype == l.dtype` compares two `Maybe<&2,
#     S.Dt>`. bend 2.0.34 mis-parses `Maybe<&2, S.Dt>` in a def signature at the
#     position a helper would need it (the notes' "Maybe<&2, S.Dt> in a def
#     signature is position-sensitive"), so a dtype cannot be CARRIED and
#     therefore cannot be compared. Every rule below takes its predicate as a
#     `Bool` PARAMETER, which is the shape the notes prescribe, and the predicate
#     itself is W4.
#
# ---------------------------------------------------------------------------
# THE GATE. Every row is DERIVED FROM PYTHON by the oracle named at the foot; the
# interpreted lane, the native lane and CPython must print the same rows in the
# same order, so
#   diff <(python3 /tmp/opencode/late-oracle.py) <(./bin/bend tinybendygrad/codegen/late.bend)
# is the acceptance test and NEITHER side can be nudged to match the other.
# The per-UOP gate shape and the two identity rows are described here; regalloc's
# half of the same paragraph is in `regalloc.bend`'s header.
#
import Base
import ./../../helpers.bend as H
import ./../../LAWS/spec.bend as S
import ./../../uop/ops.bend as O
import ./../../uop/fold.bend as F
import ./../kernel.bend as KER

# ===========================================================================
# ONE ASSOC LIST FOR EVERY TABLE IN THE FILE. `v` is a scalar answer and `vs` a
# list answer, and a FLAT PAIR LIST for the two `dict[int, dict[Register,
# Register]]` tables (regalloc.py:34-35) where `[v,r,v,r,...]` is the inner dict.
#
# ONE type rather than seven, and NOT a generic container: the seven Python dicts
# are all "key is a U32", and Bend's `Map` is string-keyed only (constraints,
# section 3) so a `List` of records is the substrate's own answer. A `Data`
# wrapper is the recurring Bend shape for a table a walk reads while walking.
# ===========================================================================
type RaTb is Data:
  RaTb{es: List<&2, RaEn>}

type RaEn is Data:
  RaEn{k: U32, v: U32, vs: List<&2, U32>}

def RaTb.es(t: RaTb) -> List<&2, RaEn>:
  match t:
    case RaTb{es}: es

def RaEn.k(e: RaEn) -> U32:
  match e:
    case RaEn{k, v, vs}: k

def RaEn.v(e: RaEn) -> U32:
  match e:
    case RaEn{k, v, vs}: v

def RaEn.vs(e: RaEn) -> List<&2, U32>:
  match e:
    case RaEn{k, v, vs}: vs

# `dict.get(k, default)`. `defaultdict(int)` reads as 0, `live_inv.get(r)` as
# `None` and `ctx.edges.get(x)` as `None`, and index 0 is this file's `None`
# exactly as `UOp.is_none` says it is.
def tb_get.hit(hit: Bool, v: U32, rest: U32) -> U32:
  Bool.pick(U32, hit, v, rest)

def tb_get.go(+k: U32, rest: List<&2, RaEn>) -> U32:
  match rest:
    case Nil{}   : 0
    case +e <> r : tb_get.hit(U32.is_eq(RaEn.k(e), k), RaEn.v(e), tb_get.go(k, r))

def tb_get(+t: RaTb, k: U32) -> U32:
  tb_get.go(k, RaTb.es(t))

def tb_has.hit(hit: Bool, rest: Bool) -> Bool:
  Bool.pick(Bool, hit, True{}, rest)

def tb_has.go(+k: U32, rest: List<&2, RaEn>) -> Bool:
  match rest:
    case Nil{}   : False{}
    case +e <> r : tb_has.hit(U32.is_eq(RaEn.k(e), k), tb_has.go(k, r))

def tb_has(+t: RaTb, k: U32) -> Bool:
  tb_has.go(k, RaTb.es(t))

# THE LIST VALUE, because `lr[v]` and `reals[i]` and `insert_before[i]` are LISTS
# and `tb_get` cannot hand one back.
def tb_vs.hit(hit: Bool, vs: List<&2, U32>, rest: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, hit, vs, rest)

def tb_vs.go(+k: U32, rest: List<&2, RaEn>) -> List<&2, U32>:
  match rest:
    case Nil{}   : Nil{}
    case +e <> r : tb_vs.hit(U32.is_eq(RaEn.k(e), k), RaEn.vs(e), tb_vs.go(k, r))

def tb_vs(+t: RaTb, k: U32) -> List<&2, U32>:
  tb_vs.go(k, RaTb.es(t))

# `es.setdefault(k, [...]).insert(0, x)` and `.append(x)` are ONE def with a Bool
# arm, because the two DIRECTIONS are the difference between a live range in
# index order and one in reverse (regalloc.py:26 and :28) and spelling them apart
# is the whole content of those two lines.
def tb_ins.cat(pre: Bool, +old: List<&2, U32>, +vs: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, pre, List.append(&2, U32, vs, old), List.append(&2, U32, old, vs))

# THE MISS ARM APPENDS and the hit arm REWRITES IN PLACE, which is what keeps a
# key at its first-insertion position; and the miss arm MUST carry the whole
# walked prefix, not the tail. Returning the tail is a `del` -- and a silent one,
# because the table still answers `1` for the key that survived and only the keys
# before the miss are gone, so the row that counts a lookup still passes. So the
# walk CONSES the head instead of recursing past it. `Bool.pick` is strict, so
# both arms run and every value they share is `+` (droppable, therefore duplicable
# -- a bare binder is Lone and a second read is refused).
def tb_ins.go(+pre: Bool, +k: U32, +v: U32, +vs: List<&2, U32>, rest: List<&2, RaEn>) -> List<&2, RaEn>:
  match rest:
    case Nil{}  : List.append(&2, RaEn, [RaEn{k, v, vs}], rest)
    case +e <> +r : Bool.pick(List<&2, RaEn>, U32.is_eq(RaEn.k(e), k),
                   List.append(&2, RaEn, [RaEn{k, v, tb_ins.cat(pre, RaEn.vs(e), vs)}], r),
                   List.append(&2, RaEn, [e], tb_ins.go(pre, k, v, vs, r)))

def tb_ins(pre: Bool, t: RaTb, k: U32, v: U32, vs: List<&2, U32>) -> RaTb:
  RaTb{tb_ins.go(pre, k, v, vs, RaTb.es(t))}

def tb_put(t: RaTb, k: U32, v: U32, vs: List<&2, U32>) -> RaTb:
  tb_ins(False{}, t, k, v, vs)

# `k` is a REGISTER INDEX, so the pair list is a `U32` list at stride two and
# `tb_put`'s `vs` field is the whole answer. `dict[k] = v` is REPLACE-or-APPEND
# and it is `tb_ins.go` with the pair as the unit, down to the cons and the `+`.
# `case _ <> _` is the CONS cover and it MUST BE LAST: it is the only cover bend
# accepts for the one-element list, since `case _ <>` cannot cover `Nil{}` (rule
# 7). A pair list is EVEN by construction, so the arm is unreachable and its
# answer is Python's `KeyError` default.
def tb_pget.go(vs: List<&2, U32>, +k: U32) -> U32:
  match vs:
    case Nil{}       : 0
    case +x <> y <> r : Bool.pick(U32, U32.is_eq(x, k), y, tb_pget.go(r, k))
    case _ <> _      : 0

def tb_pget(vs: List<&2, U32>, k: U32) -> U32:
  tb_pget.go(vs, k)

def tb_pput.go(+k: U32, +r: U32, vs: List<&2, U32>) -> List<&2, U32>:
  match vs:
    case Nil{}         : List.append(&2, U32, [k, r], vs)
    case +x <> y <> +q  : Bool.pick(List<&2, U32>, U32.is_eq(x, k),
                       List.append(&2, U32, [x, r], q),
                       List.append(&2, U32, [x, y], tb_pput.go(k, r, q)))
    case _ <> _       : List.append(&2, U32, [k, r], vs)

def tb_pput(vs: List<&2, U32>, k: U32, r: U32) -> List<&2, U32>:
  tb_pput.go(k, r, vs)

# `reals.setdefault(i, {})[v] = live[v]`: append-or-replace inside one bucket.
# `dict[b] = vs` -- REPLACE a bucket's list. `tb_put` is the APPEND primitive and
# this table needs BOTH: `insert_before.setdefault(i, []).append(...)` (:35, :52)
# appends and `reals.setdefault(i, {})[v] = live[v]` (:34, :63, :77) REPLACES.
# Written with `tb_put` the second one answers `old ++ new`, so a bucket written
# three times carries five pairs and `ra<t>_a<i>` prints the same virtual three
# times -- a row with the right LENGTH and the wrong GRAPH.
def tb_vput.go(+t: RaTb, +b: U32, +vs: List<&2, U32>, rest: List<&2, RaEn>) -> List<&2, RaEn>:
  match rest:
    case Nil{}   : List.append(&2, RaEn, [RaEn{b, 0, vs}], rest)
    case +e <> +r : Bool.pick(List<&2, RaEn>, U32.is_eq(RaEn.k(e), b),
                   List.append(&2, RaEn, [RaEn{b, 0, vs}], r),
                   List.append(&2, RaEn, [e], tb_vput.go(t, b, vs, r)))

def tb_vput(+t: RaTb, b: U32, vs: List<&2, U32>) -> RaTb:
  RaTb{tb_vput.go(t, b, vs, RaTb.es(t))}

def tb_pset.put(t: RaTb, +b: U32, vs: List<&2, U32>, k: U32, r: U32) -> RaTb:
  tb_vput(t, b, tb_pput(vs, k, r))

def tb_pset(+t: RaTb, +b: U32, k: U32, r: U32) -> RaTb:
  tb_pset.put(t, b, tb_vs(t, b), k, r)

def tb_keys.go(rest: List<&2, RaEn>, +acc: List<&2, U32>) -> List<&2, U32>:
  match rest:
    case Nil{}   : acc
    case e <> r  : tb_keys.go(r, List.append(&2, U32, acc, [RaEn.k(e)]))

def tb_keys(+t: RaTb) -> List<&2, U32>:
  tb_keys.go(RaTb.es(t), Nil{})

def tb_new() -> RaTb:
  RaTb{Nil{}}

# `List.append(a, A, xs, ys)` is `xs ++ ys`. TWO shapes with OPPOSITE results,
# and both are in this file, which is why both are named at their call sites:
# with the accumulator as a PARAMETER it appends in WALK ORDER (`lt_deg`, and the
# `ra` table walks), and with the TAIL'S ANSWER as the first argument the head
# lands LAST. Measured: `rc_*` rows, `lt_emit`'s `newlst`, and `lt_se`'s END chain.
# `u32_none()` IS Python's `None` for this port, and it is the same convention
# kernel.bend uses: `UOp.is_none` is index 0 and every "unset" here is 0xFFFFFFFF,
# which is a value no table in this file ever stores as a KEY.
def u32_none() -> U32:
  4294967295

def b2u(+b: Bool) -> U32:
  Bool.pick(U32, b, 1, 0)

def at(xs: List<&2, U32>, n: Nat) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, xs, n), 0)

def nlen(xs: List<&2, U32>) -> Nat:
  List.length(&2, U32, xs)

def range_tuple.go(fuel: Nat, +k: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match fuel:
    case 0n   : acc
    case 1n+p : range_tuple.go(p, U32.add(k, 1), List.append(&2, U32, acc, [k]))

def u32s(t: Nat) -> List<&2, U32>:
  range_tuple.go(t, 0, Nil{})


# ===========================================================================
# `lt_rc` -- `run_count = prod([int(r.vmax)+1 for r in u.ranges])`, linearizer.py:20.
# PORTED as a fold over the vmax LIST. W1 is the CALLER.
# `rc_max` = 65536 is the row that pins the composite key's 26-bit range, since
# `lt_key` is `run_count * 64 + priority_offset` and the offset is 0..25.
# ===========================================================================
def lt_rc.go(vmaxs: List<&2, U32>, +acc: U32) -> U32:
  match vmaxs:
    case Nil{}    : acc
    case v <> +t : lt_rc.go(t, U32.mul(acc, U32.add(v, 1)))

def lt_rc(vmaxs: List<&2, U32>) -> U32:
  lt_rc.go(vmaxs, 1)

# ===========================================================================
# THE PRIORITY LADDER, linearizer.py:24-32. PORTED IN FULL, all eight arms.
#
#     match u.op:
#       case Ops.PARAM: priority, extra = -20, u.arg.slot
#       case Ops.BUFFER | Ops.ALLOC: priority = -17 if u.addrspace == AddrSpace.LOCAL else -18
#       case Ops.LOAD: priority = -1    # place loads early
#       case Ops.STORE: priority = 1    # place stores late
#       case Ops.RANGE: priority = 5    # placing RANGE is good
#       case Ops.END | Ops.BACKEDGE: priority = -5     # placing loop exits is bad
#       case _: priority = 0            # everything else has priority 0
#
# EVERY PRIORITY IS NEGATIVE and Bend has no signed `U32`, so this returns
# `priority + 20`: the OFFSET, on 0..25, order-isomorphic to the priority. The
# `po=` column of every `lin_u<i>` row is that offset and not the priority.
#
# `extra` -- `u.arg.slot` for a PARAM, `None` for everything else -- is NOT a
# field here, and that is a claim rather than an omission: `extra` is only ever
# REACHED when `run_count` AND `priority` are equal, and priority -20 is the
# PARAM's alone, so any two entries that meet at `extra` are both PARAMs and both
# slots. Python would raise `TypeError` comparing `None` with an `int` if that
# were not true, and `lin_exmix=0` is the row that checks it on the fixture.
# `lin_exmix` COUNTS the pairs that tie on (run_count, priority) and disagree on
# whether `extra` is None -- so it is a gate, not a comment.
#
# `# TODO(p3) linearizer.py:50  the DEBUG_LINEARIZE print reads `extra` -- the one
# place Python reads the field, and env-gated.`
#
# W4: the BUFFER/ALLOC arm's `u.addrspace == AddrSpace.LOCAL` is a PARAMETER. The
# arm is `lt_po.w1(local, is_bufalloc)`; `lt_po_glob`/`lt_po_loc` are the two rows.
# ===========================================================================
# THE OP PREDICATES, LEAF FIRST. Seven arms of the ladder would be seven
# two-armed `match`es if each were written out, and each gets ITS OWN row (`po_*`)
# so that a mutation dropping one arm moves exactly that row -- the `k_alu_recip`
# lesson from kernel.bend's mutation table.
def lt_op_is(op: O.Op, want: O.Op) -> Bool:
  O.eq_op(op, want)

def lt_is_param(op: O.Op) -> Bool:
  lt_op_is(op, O.OpsPARAM{})

def lt_is_store(op: O.Op) -> Bool:
  lt_op_is(op, O.OpsSTORE{})

def lt_is_load(op: O.Op) -> Bool:
  lt_op_is(op, O.OpsLOAD{})

def lt_is_range(op: O.Op) -> Bool:
  lt_op_is(op, O.OpsRANGE{})

# THE TWO-ARMED PREDICATES, and `case _:` must be LAST: an arm after a `case _:`
# is DEAD CODE and bend 2.0.34 does not say so.
def lt_is_bufalloc(op: O.Op) -> Bool:
  match op:
    case O.OpsBUFFER{}: True{}
    case O.OpsALLOC{} : True{}
    case _: False{}

def lt_is_exit(op: O.Op) -> Bool:
  match op:
    case O.OpsEND{}     : True{}
    case O.OpsBACKEDGE{}: True{}
    case _: False{}

# W4. `u.addrspace` is `F.fold.addr`'s `Maybe<&2, S.Addr>` and it cannot be
# carried in a signature; so the decision is a `Bool` parameter and THIS is the
# predicate. The half that reads `ParamArg.addrspace` is PORTED -- `S.Addr` is a
# VALUE, not a `Maybe` -- and what is NOT is the `Arg` dispatch for a node whose
# arg is not a `ParamArg`, which `fold.addr` would answer.
def lt_addr_same(ad: S.Addr) -> Bool:
  match ad:
    case S.ALocal{}: True{}
    case _: False{}

def lt_addr_pa(pa: O.ParamArg) -> Bool:
  lt_addr_same(O.ParamArg.addrspace(pa))

def lt_addr_of(a: O.Arg, not_found: Bool) -> Bool:
  match a:
    case O.AParam{pa}: lt_addr_pa(pa)
    case _: not_found

# THE LADDER, five `Bool.pick`s deep because `match` may not scrutinise a CALL.
# The order is PYTHON'S ORDER of the `match u.op:` arms and it is load-bearing:
# `Bool.pick` is strict so every predicate runs on every arm, and the RESULT is
# the first arm that fires. `po_*` rows are one per arm, and `po_add` is the
# default because the ladder's `case _:` arm is priority 0 -> offset 20.
def lt_po.w5(local: Bool, buf: Bool) -> U32:
  Bool.pick(U32, buf, Bool.pick(U32, local, 3, 2), 20)

def lt_po.w4(local: Bool, buf: Bool, store: Bool) -> U32:
  Bool.pick(U32, store, 21, lt_po.w5(local, buf))

def lt_po.w3(local: Bool, buf: Bool, store: Bool, load: Bool) -> U32:
  Bool.pick(U32, load, 19, lt_po.w4(local, buf, store))

def lt_po.w2(local: Bool, buf: Bool, store: Bool, load: Bool, param: Bool) -> U32:
  Bool.pick(U32, param, 0, lt_po.w3(local, buf, store, load))

def lt_po.w1(local: Bool, buf: Bool, store: Bool, load: Bool, param: Bool, range: Bool, exit: Bool) -> U32:
  Bool.pick(U32, range, 25, Bool.pick(U32, exit, 15, lt_po.w2(local, buf, store, load, param)))

def lt_po.of(+a: O.Arena, +i: U32, +op: O.Op, local: Bool) -> U32:
  lt_po.w1(local, lt_is_bufalloc(op), lt_is_store(op), lt_is_load(op), lt_is_param(op), lt_is_range(op), lt_is_exit(op))

def lt_po(+a: O.Arena, +i: U32) -> U32:
  lt_po.of(a, i, O.Arena.op(a, i), lt_addr_of(O.Arena.arg(a, i), False{}))

# `lt_po` is the VALUE `O.Arena`/`O.Arena.arg` is read for, so `local` and `op`
# are parameters of `.of` rather than calls in the argument list: `lt_po.of(a, i,
# O.Arena.op(a, i), lt_addr_of(O.Arena.arg(a, i), False{}))` reads `a` twice and
# `i` twice and both `+`, and bend evaluates arguments left to right so the
# arena's reads are ordered. Named here so the gate's `po_*` rows can call the
# `.of` form with a FIXED op and vary one predicate at a time.
def lt_po_op(+op: O.Op) -> U32:
  lt_po.w1(False{}, lt_is_bufalloc(op), lt_is_store(op), lt_is_load(op),
           lt_is_param(op), lt_is_range(op), lt_is_exit(op))

# `extra` -- `u.arg.slot` for a PARAM and `None` for everything else
# (linearizer.py:26). `u32_none()` is this port's `None`, the same convention as
# `UOp.is_none`, and it is a VALUE rather than an `Option` because the field is
# only ever compared for `is None`.
def lt_extra.slot.of(arg: O.Arg) -> U32:
  match arg:
    case O.AParam{pa}: O.ParamArg.slot(pa)
    case _: u32_none()

def lt_extra.slot(arg: O.Arg) -> U32:
  lt_extra.slot.of(arg)

def lt_extra.of2(isp: Bool, arg: O.Arg) -> U32:
  Bool.pick(U32, isp, lt_extra.slot(arg), u32_none())

def lt_extra.of(isp: Bool, +a: O.Arena, +i: U32) -> U32:
  lt_extra.of2(isp, O.Arena.arg(a, i))

def lt_extra(+a: O.Arena, +i: U32) -> U32:
  lt_extra.of(lt_is_param(O.Arena.op(a, i)), a, i)

# `lt_key` -- `priorities[x]` as ONE `U32`. `rc * 64 + offset` is order-isomorphic
# to the LEXICOGRAPHIC order on `(run_count, priority)` for `rc < 2^26`, because
# the offset is 0..25 < 64. That is what lets `List.sort`'s comparator -- whose
# parameter type is `A -> A -> Bool` with `+` REFUSED, so one field read per
# element -- be a single `U32.is_le`.
def lt_key(rc: U32, po: U32) -> U32:
  U32.add(U32.mul(rc, 64), po)

# ===========================================================================
# `out_degree` -- linearizer.py:11, :16-17. A COUNT OF OCCURRENCES, not a set
# membership: Python's `out_degree[s] += 1` runs once per (consumer, src) PAIR,
# and a node an operator names twice has two edges into it.
# `for u in reversed(lst): for s in u.src_without_body: out_degree[s] += 1`
#
# `reversed(lst)` is `List.reverse` -- the counts are order-independent, but
# transcribing `reversed` is one call and keeps the diff against :17 readable.
# ===========================================================================
# `List.foldl` IS THE SRC LOOP. The inner `for s in u.src_without_body` is a
# 2-ary fold with a top-level step, so it is ONE call and there is no mutual
# recursion -- which is why the outer walk is one def and the inner is a builtin.
def lt_deg.bump.put(+acc: RaTb, n: U32, +s: U32) -> RaTb:
  tb_put(acc, s, U32.add(n, 1), Nil{})

def lt_deg.bump(+acc: RaTb, +s: U32) -> RaTb:
  lt_deg.bump.put(acc, tb_get(acc, s), s)

# `out_degree[v] -= 1`, the heap loop's SECOND use of the same table and the only
# one that DECREMENTS. ONE read of the degree and the `-1` in `.put`, which is why
# it does not need the `.of` split `lt_deg.bump` does not either.
def lt_deg.dec.put(+tb: RaTb, n: U32, v: U32) -> RaTb:
  tb_put(tb, v, U32.sub(n, 1), Nil{})

def lt_deg.dec(+tb: RaTb, +v: U32) -> RaTb:
  lt_deg.dec.put(tb, tb_get(tb, v), v)

# NOT `List.foldl`, and the reason is worth recording: `List.foldl`'s step has
# type `B -> A -> B` with `+` REFUSED on its parameters (measured, and the same
# restriction as `List.sort`'s comparator), while `out_degree[s] += 1` needs BOTH
# of `acc` and `s` twice. A step with `+` cannot be a fold step, so the inner
# loop is its own self-recursive def -- and because that def does not call back,
# it is not a mutual recursion, it is just declared FIRST.
def lt_deg.srcs(ss: List<&2, U32>, +acc: RaTb, ar: O.Arena) -> RaTb:
  match ss:
    case Nil{}   : acc
    case s <> +r : lt_deg.srcs(r, lt_deg.bump(acc, s), ar)

# THE TABLE'S KEY ORDER IS PYTHON'S. `tb_ins.go` rewrites in place and appends on
# a miss, so `out_degree` comes out in first-seen order -- and that is free, not
# incidental: a live range (`regalloc.py:26-28`) IS a per-key list whose order is
# the gate, so a table whose key order is unobservable here is a table that gets
# checked there.
def lt_deg.go(+ar: O.Arena, rest: List<&2, U32>, +acc: RaTb) -> RaTb:
  match rest:
    case Nil{}  : acc
    case u <> +t : lt_deg.go(ar, t, lt_deg.srcs(O.Arena.src_without_body(ar, u), acc, ar))

def lt_deg(ar: O.Arena, lst: List<&2, U32>) -> RaTb:
  lt_deg.go(ar, List.reverse(&2, U32, lst), tb_new())

# THE SORT ELEMENT. `LtKey{k: U32, i: U32}`: the composite key and the node it
# belongs to. ONE field is read by the comparator and the other is never read
# there, which is the whole reason a two-part key is legal at all.
type LtKey is Data:
  LtKey{k: U32, i: U32, rc: U32, ex: U32}

def LtKey.k(x: LtKey) -> U32:
  match x:
    case LtKey{k, i, rc, ex}: k

def LtKey.i(x: LtKey) -> U32:
  match x:
    case LtKey{k, i, rc, ex}: i

# `ex` IS PYTHON'S `extra` -- the PARAM's slot, `u32_none()` for everything else --
# carried ONLY so `lin_exmix` can be computed in the port rather than asserted.
# `+` on a `U32` is free (the notes' rule 30), so a fourth field costs nothing and
# buys the row that says dropping `extra` is sound.
def LtKey.ex(x: LtKey) -> U32:
  match x:
    case LtKey{k, i, rc, ex}: ex

# `rc` RIDES ALONG rather than being re-read from the `vms` table at print time.
# The alternative -- a positional walk over the length-prefixed list -- needs a
# self-call whose first argument is a COMPUTED `List.drop`, and the decrease check
# refuses that ("a self-call may not pass a computed argument in front of the
# tail"). Carrying it is also what makes the comparator's "one field read" free:
# the comparator reads `k` and the printer reads `i` and `rc`.
def LtKey.rc(x: LtKey) -> U32:
  match x:
    case LtKey{k, i, rc, ex}: rc

# ===========================================================================
# THE IDEAL ORDER -- `nkey = {u: i for i, u in enumerate(sorted(lst, key=...))}`,
# linearizer.py:36. So `nkey` IS the POSITION in the sorted list and the whole
# table is the sorted list: `lt_nkey` searches it.
#
# THE SORT KEY IS ONE `U32` (`lt_key`), which is what makes the comparator legal:
# `List.sort`'s comparator type is `A -> A -> Bool` with `+` REFUSED on its
# parameters, so each element may be read exactly ONCE -- and `LtKey` has two
# fields, of which only `k` is read. A two-field comparison key would have to be
# a two-scrutinee `match` over two RECORDS, which is four arms of nothing.
#
# `List.sort` is STABLE and `le` is `<=` (base's `List.merge.step` takes `x`,
# the FIRST run's head, whenever `le(x, y)`), and Python's `sorted` is stable
# too, so TIES fall back to the toposort order in both. That is the whole of the
# `TUPLE_ORDER=0` lane and W2 is the rest.
# ===========================================================================
def lt_kle(x: LtKey, y: LtKey) -> Bool:
  U32.is_le(LtKey.k(x), LtKey.k(y))

def lt_sorted(ks: List<&2, LtKey>) -> List<&2, LtKey>:
  List.sort(LtKey, lt_kle, ks)

def lt_nkey.hit(hit: Bool, +i: U32, rest: U32) -> U32:
  Bool.pick(U32, hit, i, rest)

def lt_nkey.go(srt: List<&2, LtKey>, +i: U32, +u: U32) -> U32:
  match srt:
    case Nil{}       : 0
    case +e <> r     : lt_nkey.hit(U32.is_eq(LtKey.i(e), u), i, lt_nkey.go(r, U32.add(i, 1), u))

def lt_nkey(srt: List<&2, LtKey>, u: U32) -> U32:
  lt_nkey.go(srt, 0, u)


# W1 AGAIN, AND THIS TIME IT IS THE PASS'S OWN CALLER. `vms` is ONE flat list of
# `vmax`es for the WHOLE walk, LENGTH-PREFIXED per list position:
#
#     vms = [ n0, v0, ..., v_{n0-1}, n1, v0, ..., ... ]
#
# A `List<&2, List<&2, U32>>` is not available -- `List` is a `Type` and cannot be
# a list ELEMENT (the notes' FOUR MORE GENERAL RULES, item 1) -- and a bare flat
# list with no prefix would pair a node with ANOTHER node's ranges whenever the
# lengths differ, which is a plausible wrong `rc` everywhere and no error at all.
# `lin_vm` is the row that prints the whole table in the oracle's `;`-separated
# spelling, and `lin_u<i>` carries every `rc` computed from it.
type VM is Data:
  VM{vs: List<&2, U32>, rest: List<&2, U32>}

def VM.vs(x: VM) -> List<&2, U32>:
  match x:
    case VM{vs, rest}: vs

def VM.rest(x: VM) -> List<&2, U32>:
  match x:
    case VM{vs, rest}: rest

def lt_vm.take2(vs: List<&2, U32>, rest: List<&2, U32>) -> VM:
  VM{vs, rest}

def lt_vm.take(+r: List<&2, U32>, +n: Nat) -> VM:
  lt_vm.take2(List.take(&2, U32, r, n), List.drop(&2, U32, r, n))

def lt_vm.go(vms: List<&2, U32>) -> VM:
  match vms:
    case Nil{}    : VM{Nil{}, Nil{}}
    case n <> +r  : lt_vm.take(r, U32.to_nat(n))

# `lt_po` reads `Arena.op` and `Arena.arg` and NOT `fold.addr`: `ParamArg`'s
# addrspace is a `S.Addr` VALUE (ops.bend:705), so W4's "a dtype cannot be
# carried" does not bite the BUFFER/ALLOC arm after all and the predicate is
# PORTED. What W4 still blocks is the `Arg` dispatch for a node whose arg is not
# a `ParamArg`, which `fold.addr` would answer -- `lt_addr_of`'s `case _:` arm.
def lt_keys.put(+acc: List<&2, LtKey>, +u: U32, +ar: O.Arena, +vm: VM) -> List<&2, LtKey>:
  List.append(&2, LtKey, acc, [LtKey{lt_key(lt_rc(VM.vs(vm)), lt_po(ar, u)), u, lt_rc(VM.vs(vm)), lt_extra(ar, u)}])

def lt_keys.go(+ar: O.Arena, lst: List<&2, U32>, +vms: List<&2, U32>, +acc: List<&2, LtKey>) -> List<&2, LtKey>:
  match lst:
    case Nil{}    : acc
    case u <> +t  : lt_keys.go(ar, t, VM.rest(lt_vm.go(vms)),
                              lt_keys.put(acc, u, ar, lt_vm.go(vms)))

def lt_keys(+ar: O.Arena, lst: List<&2, U32>, vms: List<&2, U32>) -> List<&2, LtKey>:
  lt_keys.go(ar, lst, vms, Nil{})


# ===========================================================================
# THE HEAP LOOP, linearizer.py:39-46. PORTED, and `heapq` is a SORTED LIST.
#
#     heap = [(-nkey[sink], sink)];  newlst = []
#     while heap:
#       newlst.append(u := heapq.heappop(heap)[1])
#       for v in u.src_without_body:
#         out_degree[v] -= 1
#         if out_degree[v] == 0: heapq.heappush(heap, (-nkey[v], v))
#     newlst = newlst[::-1]
#
# `nkey` is a BIJECTION onto 0..n-1 (`enumerate(sorted(lst, ...))`), so two heap
# entries never tie and `heapq.heappop` -- the SMALLEST tuple, and the tuple is
# `(-nkey, v)` -- returns the node with the LARGEST `nkey`. So the pop order is
# descending in `nkey` AMONG THE AVAILABLE, and `newlst[::-1]` reverses it.
# `heappush` on a sorted list is a re-sort and `heappop` is taking the head, which
# is the whole port of `heapq`.
#
# READING `-nkey` AS "SMALLEST nkey" IS THE MISTAKE, and it produces a plausible
# list of the right LENGTH with every position wrong -- which is what the first
# version of this file did and what `lin_u<i>` is the row class for.
#
# AND THE ORDER IS NOT A COUNTDOWN, which is the thing worth writing down: a
# descending walk over `nkey` that SKIPS a node whose degree is not yet 0 is not
# the heap, because the heap COMES BACK to it. `nkey` is the IDEAL order, not a
# topological order, so a node can have a SMALLER `nkey` than its consumer: node 2
# (nkey 6) is a src of node 13 (nkey 1) and is released only by popping node 13,
# long after step 6. A countdown version emitted 16 of the 19 nodes and every one
# of them was in the right relative order. That is the worst shape of bug --
# right prefixes, wrong count, no error.
#
# SO THE QUEUE IS THE STATE and the fuel is THE QUEUE'S LENGTH, which is why
# `rem` is `List.length(HP.heap(h))` and not a bound: the `0n` arm IS the `while
# heap:` test. A queue that GROWS cannot be a Bend self-call's shrinking first
# argument, so it travels inside a `Data` record and only `rem` decreases.
type HP is Data:
  HP{heap: List<&2, LtKey>, tb: RaTb}

def HP.heap(h: HP) -> List<&2, LtKey>:
  match h:
    case HP{heap, tb}: heap

def HP.tb(h: HP) -> RaTb:
  match h:
    case HP{heap, tb}: tb

# `heapq.heappush(heap, (-nkey[v], v))` -- the entry is `LtKey{nkey[v], v, 0, 0}`
# because the heap is held SORTED BY `nkey` ASCENDING and `heappop` takes the
# HEAD, which is the LAST. `rc` and `ex` are 0 because the heap never reads them.
# DESCENDING, and stability is irrelevant here (unlike `lt_sorted`, where it is
# load-bearing): every heap entry is a DISTINCT node and `nkey` is a bijection, so
# no two entries tie. The sort is descending so the HEAD is the largest `nkey`,
# which is what `heappop` on `(-nkey, v)` returns.
def lt_hp.kle(x: LtKey, y: LtKey) -> Bool:
  U32.is_ge(LtKey.k(x), LtKey.k(y))

def lt_hp.push(q: List<&2, LtKey>, e: LtKey) -> List<&2, LtKey>:
  List.sort(LtKey, lt_hp.kle, List.append(&2, LtKey, q, [e]))

# THE HEAD'S NODE, which is `enumerate`'s value read at position 0. `lt_srt_node`
# is the general form -- the node at POSITION k -- and it is also `lt_nkey`'s
# inverse, so `lt_srt_node(lt_srt(), k)` is the identity `nkey[at(k)] == k`.
def lt_srt_node(srt: List<&2, LtKey>, +pos: U32) -> U32:
  match srt:
    case Nil{}     : 0
    case +e <> +r  : Bool.pick(U32, U32.is_zero(pos), LtKey.i(e), lt_srt_node(r, U32.sub(pos, 1)))

def lt_hq.head2(+q: List<&2, LtKey>) -> U32:
  lt_srt_node(q, 0)

def lt_hq.head(+h: HP) -> U32:
  lt_hq.head2(HP.heap(h))

# `out_degree[v] -= 1; if out_degree[v] == 0: heappush(...)`. The test reads the
# DECREMENTED table, so `.dec2` is the table and `.hit` the push -- and the push is
# a VALUE, which is what makes `Bool.pick` legal here (it is strict, so the push is
# computed and discarded when `zero` is False, and computing it is total).
def lt_hp.hit(zero: Bool, +s: U32, +h: HP, +srt: List<&2, LtKey>) -> HP:
  Bool.pick(HP, zero, HP{lt_hp.push(HP.heap(h), LtKey{lt_nkey(srt, s), s, 0, 0}), HP.tb(h)}, h)

def lt_hp.dec2(+tb: RaTb, +s: U32, heap: List<&2, LtKey>, +srt: List<&2, LtKey>) -> HP:
  lt_hp.hit(U32.is_zero(tb_get(tb, s)), s, HP{heap, tb}, srt)

def lt_hp.dec(+s: U32, +tb: RaTb, heap: List<&2, LtKey>, +srt: List<&2, LtKey>) -> HP:
  lt_hp.dec2(lt_deg.dec(tb, s), s, heap, srt)

# `for v in u.src_without_body:` -- the queue and the table BOTH change, so the
# accumulator is the `HP` record and the self-call's first argument is the tail.
def lt_hp.ss(ss: List<&2, U32>, +h: HP, +srt: List<&2, LtKey>) -> HP:
  match ss:
    case Nil{}   : h
    case s <> +r : lt_hp.ss(r, lt_hp.dec(s, HP.tb(h), HP.heap(h), srt), srt)

# ONE POP: take the head off the queue, then release its srcs.
def lt_hp.pop(v: U32, +h: HP, +srt: List<&2, LtKey>, ar: O.Arena) -> HP:
  lt_hp.ss(O.Arena.src_without_body(ar, v), HP{List.tail(&2, LtKey, HP.heap(h)), HP.tb(h)}, srt)

# THE STEP'S TWO ANSWERS -- the popped node and the new queue -- which is why `PS`
# exists: `lt_hp.pop` is PURE, so calling it twice would be correct and wasteful,
# and a record is one line.
type PS is Data:
  PS{hp: HP, v: U32}

def PS.hp(p: PS) -> HP:
  match p:
    case PS{hp, v}: hp

def PS.v(p: PS) -> U32:
  match p:
    case PS{hp, v}: v

def lt_hq.step(+h: HP, +srt: List<&2, LtKey>, ar: O.Arena) -> PS:
  PS{lt_hp.pop(lt_hq.head(h), h, srt, ar), lt_hq.head(h)}
# THE STEP IS CALLED TWICE and that is FINE and not an oversight: `lt_hp.pop` is
# PURE, so the second call returns the same `PS`. A `.go` split would be a mutual
# recursion (the step's answer IS the self-call's first argument), which Bend
# refuses, and this is the documented alternative -- "call the pure function twice"
# from the notes' movement.bend entry 13.
# `rem` IS THE REMAINING NUMBER OF POPS and not the queue's length: every node is
# popped EXACTLY ONCE, so `n - pops` reaches 0 exactly when the queue empties, and
# it DECREASES BY ONE per step even when the queue grows -- which the queue's own
# length does not. It is the first parameter because the decrease check reads left
# to right (the notes' rule 5), and the second argument is computed, which is free
# once the first has shrunk.
def lt_hq.go(rem: Nat, +h: HP, +srt: List<&2, LtKey>, +ar: O.Arena, +acc: List<&2, U32>) -> List<&2, U32>:
  match rem:
    case 0n   : acc
    case 1n+p : lt_hq.go(p, PS.hp(lt_hq.step(h, srt, ar)), srt, ar,
                         List.append(&2, U32, acc, [PS.v(lt_hq.step(h, srt, ar))]))

# THE PASS. `linearize(sink)` is `lst` in, `newlst` out, and `lst` is a PARAMETER
# because `sink.toposort(enter_calls=False)` is ops.py:294 -- a graph walk with a
# visited flag, not a list operation, and the file this unit owns does not own it.
# `out_degree` is fed `lst` and NOT the sorted list even though the counts are
# order-independent: the sorted list would make the KEY ORDER observable, and
# `lt_deg`'s own comment says it is not.
def lt_emit(+ar: O.Arena, lst: List<&2, U32>, +srt: List<&2, LtKey>, +sink: U32) -> List<&2, U32>:
  List.reverse(&2, U32, lt_hq.go(List.length(&2, LtKey, srt),
                                HP{lt_hp.push(Nil{}, LtKey{lt_nkey(srt, sink), sink, 0, 0}),
                                   lt_deg(ar, lst)}, srt, ar, Nil{}))

# `linearize` -- linearizer.py:8-51, with the DEBUG print (:48-50) dropped: it is
# env-gated, it prints `multirange_str` (a `UOp.ranges` reader, W1) and it reads
# the `extra` field W2. `# TODO(p3) linearizer.py:48-50  getenv("DEBUG_LINEARIZE")`
def linearize(+ar: O.Arena, +lst: List<&2, U32>, vms: List<&2, U32>, +sink: U32) -> List<&2, U32>:
  lt_emit(ar, lst, lt_sorted(lt_keys(ar, lst, vms)), sink)

# ===========================================================================
# THE GATE FIXTURE. Twenty-two arena indices built in the interning order the
# oracle uses, so `ix` can be diffed row by row and a row that reads the wrong
# index is a DIFFERENT NUMBER rather than a plausible one.
#
# A CONST of int32 is a PAIR in CPython (`UOp.const(b, dt)` is `const.cast(dt)`,
# ops.py:631) and `ops.bend`'s `UOp.const` interns the BARE CONST only, so the
# CAST is built EXPLICITLY here: one node there is two here and every index after
# it is off by one. That is ops.bend's own recorded divergence, and this file
# pays the second node to keep the gate's indices equal to the oracle's.
#
#   1 C1a 2 C1 3 C4a 4 C4 5 C16a 6 C16 7 SP 8 BUFL 9 PRM 10 R_U 11 ADD
#  12 ST 13 ALG 14 EN 15 R_B 16 ADD2 17 ST2 18 EN2 19 SK 20 CALL 21 SK2
#
# `BUFL` is a LOCAL BUFFER and `ALG` a GLOBAL one, because `linearizer.py:27`
# reads `u.addrspace` and the two differ by exactly one unit of offset (3 against
# 2) -- and `lin_u3` and `lin_u5` are the two rows that see it.
#
# `SP` HAS A SRC, like every real kernel (`SPECIAL ['CAST']` in dbg7's dump): a
# src-less SPECIAL makes `_min_max` answer `self.src[0]-1` and raise, so the
# oracle cannot even build a fixture without one.
#
# `R_B`'s SECOND SRC IS `EN`, which is the shape `CFGContext` needs to reach `EN`
# from the SINK. A SINK with a single END child yields NO edges, because
# `zipped` is `zip(order, order[1:])` and `order` then has length one -- measured
# on a real `(a*b+3).relu().sum()` kernel, which is the fixture the first
# version of this file lacked.
# ===========================================================================
def lt_pa(slot: U32, dt: S.Dt, ad: S.Addr) -> O.ParamArg:
  O.ParamArg{slot, dt, None{}, None{}, None{}, None{}, ad, None{}, False{}, None{},
             None{}, False{}, None{}}

def lt_i32.go(+made: O.Found, ar: O.Arena) -> O.Found:
  O.UOp.new(ar, O.OpsCAST{}, [O.Found.i(made)], O.ADt{S.int32()}, O.TNone{})

def lt_i32(c: U32, +ar: O.Arena) -> O.Found:
  lt_i32.go(O.UOp.const(ar, O.CInt{H.i64_of_i32(c)}), ar)

def lt_fix() -> KER.K:
  +c1a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(1)})
  +c1 = lt_i32(1, O.Found.ar(c1a))
  +c4a = O.UOp.const(O.Found.ar(c1), O.CInt{H.i64_of_i32(4)})
  +c4 = lt_i32(4, O.Found.ar(c4a))
  +c16a = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(16)})
  +c16 = lt_i32(16, O.Found.ar(c16a))
  +sp = O.UOp.new(O.Found.ar(c16), O.OpsSPECIAL{}, [O.Found.i(c1)], O.AStr{"0"}, O.TNone{})
  +bufl = O.UOp.new(O.Found.ar(sp), O.OpsBUFFER{}, [O.Found.i(sp)],
                    O.AParam{lt_pa(7, S.single(), S.ALocal{})}, O.TNone{})
  +prm = O.UOp.new(O.Found.ar(bufl), O.OpsPARAM{}, Nil{},
                   O.AParam{lt_pa(0, S.single(), S.AGlobal{})}, O.TNone{})
  +r_u = O.UOp.range_end(O.Found.ar(prm), O.Found.i(c4), [0], O.AXIS_UNROLL{})
  +ad = O.UOp.new(O.Found.ar(r_u), O.OpsADD{}, [O.Found.i(prm), O.Found.i(c1)], O.ANone{}, O.TNone{})
  +st = O.UOp.new(O.Found.ar(ad), O.OpsSTORE{}, [O.Found.i(bufl), O.Found.i(ad), O.Found.i(sp)],
                  O.ANone{}, O.TNone{})
  +al = O.UOp.new(O.Found.ar(st), O.OpsALLOC{}, [O.Found.i(c1)],
                  O.AParam{lt_pa(0, S.single(), S.AGlobal{})}, O.TNone{})
  +en = O.UOp.new(O.Found.ar(al), O.OpsEND{}, [O.Found.i(st), O.Found.i(r_u)], O.ANone{}, O.TNone{})
  +r_b = O.UOp.new(O.Found.ar(en), O.OpsRANGE{}, [O.Found.i(c16), O.Found.i(en)],
                   O.ARange{[1], O.AXIS_LOOP{}}, O.TNone{})
  +ad2 = O.UOp.new(O.Found.ar(r_b), O.OpsADD{}, [O.Found.i(prm), O.Found.i(c16)], O.ANone{}, O.TNone{})
  +st2 = O.UOp.new(O.Found.ar(ad2), O.OpsSTORE{}, [O.Found.i(bufl), O.Found.i(ad2), O.Found.i(sp)],
                   O.ANone{}, O.TNone{})
  +en2 = O.UOp.new(O.Found.ar(st2), O.OpsEND{}, [O.Found.i(st2), O.Found.i(r_b)], O.ANone{}, O.TNone{})
  +sk = O.UOp.new(O.Found.ar(en2), O.OpsSINK{},
                  [O.Found.i(st), O.Found.i(st2), O.Found.i(en2), O.Found.i(al)],
                  O.AKernel{O.KernelInfo.of()}, O.TNone{})
  +cll = O.UOp.new(O.Found.ar(sk), O.OpsCALL{}, [O.Found.i(st), O.Found.i(ad)],
                   O.ACall{O.CallInfo.of()}, O.TNone{})
  +sk2 = O.UOp.new(O.Found.ar(cll), O.OpsSINK{}, [O.Found.i(cll)],
                   O.AKernel{O.KernelInfo.of()}, O.TNone{})
  KER.K{F.folded(O.Found.ar(sk2)),
    [0, O.Found.i(c1a), O.Found.i(c1), O.Found.i(c4a), O.Found.i(c4),
     O.Found.i(c16a), O.Found.i(c16), O.Found.i(sp), O.Found.i(bufl), O.Found.i(prm),
     O.Found.i(r_u), O.Found.i(ad), O.Found.i(st), O.Found.i(al), O.Found.i(en),
     O.Found.i(r_b), O.Found.i(ad2), O.Found.i(st2), O.Found.i(en2), O.Found.i(sk),
     O.Found.i(cll), O.Found.i(sk2)]}

# THE TOPOSORT, as `ops.py:294`'s `toposort(enter_calls=False)` returns it. It is
# a LITERAL and not a walk because the walk is ops.py's and not this file's, and
# a literal that disagrees with the oracle is a GATE ROW (`lin_srcs`) rather than
# a silent difference in every row below it. Read off `lin_srcs`:
#   CONST CAST SPECIAL BUFFER PARAM ADD STORE CONST CAST ADD STORE CONST CAST
#   RANGE:0 END RANGE:1 END ALLOC SINK
def lt_lst() -> List<&2, U32>:
  [1, 2, 7, 8, 9, 11, 12, 5, 6, 16, 17, 3, 4, 10, 14, 15, 18, 13, 19]

# THE IDENTITY SINK'S TOPOSORT: `SINK(CALL(STORE, ADD))` under
# `enter_calls=False`, so the CALL's `src[0]` is NOT walked and the STORE and the
# PARAM are absent. Six nodes, all rc=1, and the sort is already in nkey order --
# so the heap loop must emit it unchanged. It is also the ONLY test of
# `Arena.src_without_body` in the gate.
def lt_lst_call() -> List<&2, U32>:
  [9, 1, 2, 11, 20, 21]

# W1'S INPUT, length-prefixed (`lt_vm`), read off `lin_vm`.
def lt_vm_lst() -> List<&2, U32>:
  [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1, 3, 0, 1, 15, 0, 0, 0]

def lt_vm_call() -> List<&2, U32>:
  [0, 0, 0, 0, 0, 0]

# ===========================================================================
# THE GATE, PART ONE: the linearizer. Every row is DERIVED FROM PYTHON by
# /tmp/opencode/late-oracle.py, which drives tinygrad/codegen/late/linearizer.py
# over this exact fixture and prints its rows in THIS ORDER and with THIS
# SPELLING, so
#   diff <(python3 /tmp/opencode/late-oracle.py) <(./bin/bend tinybendygrad/codegen/late.bend)
# is the acceptance test and NEITHER side can be nudged to match the other.
#
# THE PRINTERS, LEAF FIRST, and there are two because two row classes need two
# alphabets: a `U32` list (`ix`, `lin_nkey`) and a `String` list (`lin_srcs`). A
# shared printer is a shared FORMAT CONTRACT (the notes' rule 22) -- a mutation in
# one invalidates a quarter of the suite, which is the right trade, and it is why
# `lt_u32s` is written once and not three times.
# ===========================================================================
def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def lt_u32s.go(xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}   : acc
    case v <> +r : lt_u32s.go(r, List.append(&2, String, acc, [U32.show(v)]))

def lt_u32s(xs: List<&2, U32>) -> String:
  String.join(lt_u32s.go(xs, Nil{}), " ")

# `lt_lines` IS `print` FOR A LIST OF ROWS, and `String.join` IS the whole of it:
# the oracle prints one row per line, so a block of rows is the rows joined by
# "\n" and `IO.print`'s own newline is the LAST one. `String.join` drops the final
# separator, which is exactly what is wanted here and costs one def instead of a
# string-accumulator fold.
def lt_lines(xs: List<&2, String>) -> String:
  String.join(xs, "\n")

# THE NODE LABEL, which is what pins `lin_srcs`: `RANGE:<axis id>` for a RANGE and
# the op NAME for everything else. CPython has no per-node index in this fork
# (ops.py:842 keeps only the counter), so the toposort is pinned by a label; and
# the three CONST/CAST pairs are told apart by their ADJACENCY -- each is CONST
# then CAST -- which is why a CONST needs no value printed and why building the
# CAST explicitly above is load-bearing rather than cosmetic.
def lt_lab.ids(ids: List<&2, U32>) -> U32:
  at(ids, 0n)

def lt_lab.range.pick(a: O.Arg) -> String:
  match a:
    case O.ARange{ids, at}: String.concat(["RANGE:", U32.show(lt_lab.ids(ids))])
    case _: ""

def lt_lab.range.of(a: O.Arg) -> String:
  lt_lab.range.pick(a)

def lt_lab.range(+ar: O.Arena, +v: U32) -> String:
  lt_lab.range.of(O.Arena.arg(ar, v))

def lt_lab.pick(c: Bool, a: String, +b: String) -> String:
  Bool.pick(String, c, a, b)

def lt_lab.of(+ar: O.Arena, +v: U32) -> String:
  lt_lab.pick(lt_is_range(O.Arena.op(ar, v)), lt_lab.range(ar, v), O.Ops.name.of(O.Arena.op(ar, v)))

# `lin_srcs` SPACES ITS PIECES, so a missing element is a double space and a
# doubled one is a repeat -- `String.join(xs, "")` would make both invisible.
def lt_srcs.go(+ar: O.Arena, ix: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ix:
    case Nil{}   : acc
    case v <> +r : lt_srcs.go(ar, r, List.append(&2, String, acc, [lt_lab.of(ar, v)]))

def lt_srcs(+ar: O.Arena, ix: List<&2, U32>) -> String:
  String.join(lt_srcs.go(ar, ix, Nil{}), " ")

# ===========================================================================
# `lin_edg` -- THE EDGE LIST, IN THE DECLARED TOPOSORT'S OWN POSITIONS. THIS IS
# THE ROW `lin_srcs` COULD NOT BE.
#
# The defect, measured and not argued. `lt_lst()` and `lt_vm_lst()` are LITERALS
# read off CPython, and every other row reads the arena only for a node's OP and
# ARG (`lt_lab`, `lt_extra`, `lt_addr_of`). `lt_deg` walks `Arena.src_without_body`
# but `out_degree` is a COUNT OF OCCURRENCES (linearizer.py:11,16-17), so a
# permutation of one node's srcs leaves it identical. The consequence: swapping
# any src list in `lt_fix()` -- an SINK's, an END's, a RANGE's, either ADD's --
# moves NOTHING, while CPython's answer over the same seven graphs moves in 2, 0,
# 20, 6, 9, 3 and 10 rows (`.agents/slop/order-lin-sweep.sh`). The gate was green
# over an arena that was not the graph its own table describes.
#
# THE ALPHABET IS A POSITION, NOT AN ARENA INDEX, and that is the whole design.
# CPython derives positions from its OWN `toposort`; the port derives them from
# its OWN arena plus its OWN literal. Neither side borrows the other's fixture,
# and CPython's three-node CONST/CAST interning divergence (`lin_fixture`'s
# comment: `UOp.const(1, i32)` is one node here and two in `ops.bend`) stops
# mattering, because a position is a position either way.
# ===========================================================================
# A src the declared toposort does not NAME answers `4294967295`, which is what
# `LtKey.ex`'s "no extra" sentinel already is. A disagreement between the arena
# and `lt_lst` therefore prints a sentinel rather than a plausible number.
def lt_pos.of(ix: List<&2, U32>, +u: U32, +n: U32, missing: U32) -> U32:
  match ix:
    case Nil{}   : missing
    case v <> +r : Bool.pick(U32, U32.is_eq(v, u), n, lt_pos.of(r, u, U32.add(n, 1), missing))

def lt_pos(ix: List<&2, U32>, u: U32) -> U32:
  lt_pos.of(ix, u, 0, 4294967295)

# ONE NODE'S SRCS, each already a position. `lt_u32s` is the same fold over the
# numbers themselves, so this is that fold with `lt_pos` in the step.
def lt_epos.go(+ix: List<&2, U32>, +ar: O.Arena, xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}   : acc
    case s <> +r : lt_epos.go(ix, ar, r, List.append(&2, String, acc, [U32.show(lt_pos(ix, s))]))

# `<position>:<src positions>`, one node per piece. A node with no srcs is
# `5:` and the trailing colon is what says so -- `String.join(xs, "")` would drop
# it and make an edgeless node indistinguishable from a missing one.
def lt_epos(ix: List<&2, U32>, +ar: O.Arena, xs: List<&2, U32>) -> String:
  String.join(lt_epos.go(ix, ar, xs, Nil{}), " ")

def lt_edg.piece(ix: List<&2, U32>, +ar: O.Arena, +n: U32, u: U32) -> String:
  String.concat([U32.show(n), ":", lt_epos(ix, ar, O.Arena.src_without_body(ar, u))])

def lt_edg.go(+ix: List<&2, U32>, rest: List<&2, U32>, +ar: O.Arena, +n: U32,
              +acc: List<&2, String>) -> List<&2, String>:
  match rest:
    case Nil{}   : acc
    case u <> +r : lt_edg.go(ix, r, ar, U32.add(n, 1),
                 List.append(&2, String, acc, [lt_edg.piece(ix, ar, n, u)]))

def lt_edg(+ar: O.Arena, +ix: List<&2, U32>) -> String:
  String.join(lt_edg.go(ix, ix, ar, 0, Nil{}), " ")

def lt_is_sink(op: O.Op) -> Bool:
  lt_op_is(op, O.OpsSINK{})

def lt_is_end(op: O.Op) -> Bool:
  lt_op_is(op, O.OpsEND{})

def lt_is_const(op: O.Op) -> Bool:
  lt_op_is(op, O.OpsCONST{})

def lt_is_cast(op: O.Op) -> Bool:
  lt_op_is(op, O.OpsCAST{})

# THE SORTED LIST, ONCE: `lt_lin_nkey`, `lt_lin_ties` and every `lin_u<i>` need
# it, and three independent sorts of the same keys are three chances to disagree.
def lt_srt.of(k: KER.K) -> List<&2, LtKey>:
  lt_sorted(lt_keys(F.Folded.ar(KER.K.fx(k)), lt_lst(), lt_vm_lst()))

def lt_srt() -> List<&2, LtKey>:
  lt_srt.of(lt_fix())

def lt_srt_call.of(k: KER.K) -> List<&2, LtKey>:
  lt_sorted(lt_keys(F.Folded.ar(KER.K.fx(k)), lt_lst_call(), lt_vm_call()))

def lt_srt_call() -> List<&2, LtKey>:
  lt_srt_call.of(lt_fix())

# ===========================================================================
# THE ROWS. Grouped by the def they test, in that order.
# ===========================================================================
# `ix_len` and `ix` -- THE FIXTURE'S OWN SIZE AND INDEX LIST. The notes' rule
# (mixin/creation, item 4) again: a fixture off by one is a fixture whose rows
# cannot be READ, and four rows of an earlier revision of this file answered 0
# because the CONST/CAST pair was missing from it.
def lt_ix_len.of(k: KER.K) -> U32:
  U32.from_nat(nlen(KER.K.ix(k)))

def lt_ix_len() -> U32:
  lt_ix_len.of(lt_fix())

def lt_ix.of(k: KER.K) -> String:
  lt_u32s(KER.K.ix(k))

def lt_ix() -> String:
  lt_ix.of(lt_fix())

# `rc_*` -- `lt_rc` IS `helpers.prod`, and on `lin` it only ever sees `[]`, `[3]`
# and `[15]`, which cannot tell a product from a sum. These six can, and
# `rc_max=65536` is ALSO the row that pins `lt_key`'s 26-bit run_count range.
def lt_rc_nil() -> U32:
  lt_rc(Nil{})

def lt_rc_1() -> U32:
  lt_rc([3])

def lt_rc_2() -> U32:
  lt_rc([3, 15])

def lt_rc_3() -> U32:
  lt_rc([1, 1, 4])

def lt_rc_max() -> U32:
  lt_rc([15, 15, 15, 15])

def lt_rc_big() -> U32:
  lt_rc([63, 63, 63])

# `po_*` -- ONE ROW PER ARM OF THE LADDER, because a mutation dropping one arm of
# a disjunction moves only the row for that arm (`k_alu_recip`'s lesson).
# `po_bufl` and `po_bufg` are the two halves of `linearizer.py:27`'s conditional.
def lt_po_op2(local: Bool) -> U32:
  lt_po.w5(local, True{})

def lt_po_buf(local: Bool) -> U32:
  lt_po_op2(local)

def lt_po_param() -> U32:
  lt_po_op(O.OpsPARAM{})

def lt_po_bufl() -> U32:
  lt_po_buf(True{})

def lt_po_bufg() -> U32:
  lt_po_buf(False{})

def lt_po_load() -> U32:
  lt_po_op(O.OpsLOAD{})

def lt_po_store() -> U32:
  lt_po_op(O.OpsSTORE{})

def lt_po_range() -> U32:
  lt_po_op(O.OpsRANGE{})

def lt_po_end() -> U32:
  lt_po_op(O.OpsEND{})

def lt_po_backedge() -> U32:
  lt_po_op(O.OpsBACKEDGE{})

def lt_po_add() -> U32:
  lt_po_op(O.OpsADD{})

# `lin_*` -- THE PER-UOP TABLE. One row per uop in the LINEARIZED order carrying
# that node's op, its run_count, its priority offset and its nkey, and `lin_srcs`
# / `lin_vm` pin the two INPUTS the rows are computed from.
def lt_lin_srcs() -> String:
  lt_srcs(F.Folded.ar(KER.K.fx(lt_fix())), lt_lst())

def lt_lin_n() -> U32:
  U32.from_nat(nlen(lt_lst()))

def lt_vm_print(flat: List<&2, U32>) -> String:
  lt_u32s(flat)

def lt_lin_vm() -> String:
  lt_vm_print(lt_vm_lst())

# THE ACCUMULATOR IS A PARAMETER, not the recursive result, and that is the WHOLE
# difference between this row being right and being reversed:
#     List.append(acc, [x])           -- walk order
#     List.append(lt.go(tail), [x])   -- the head lands LAST, so it REVERSES
# Both compile, both run, and the reversed one is a permutation of the right answer
# -- every value present, every position wrong. `lin_ord` is what caught it, and
# the lesson generalises: a row whose oracle is a SET rather than a LIST cannot see
# this at all, which is why `lin_ties` is a separate row and why `lin_ord` (the
# sorted list itself) is gated alongside `lin_nkey`.
def lt_lin_nkey.go(ix: List<&2, U32>, +i: U32, +srt: List<&2, LtKey>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ix:
    case Nil{}   : acc
    case v <> +r : lt_lin_nkey.go(r, U32.add(i, 1), srt,
                                 List.append(&2, U32, acc, [lt_nkey(srt, v)]))

def lt_lin_nkey() -> String:
  lt_u32s(lt_lin_nkey.go(lt_lst(), 0, lt_srt(), Nil{}))

# `lin_ties` -- W2's SIZE. The number of node PAIRS that tie on (run_count,
# priority), which is exactly the number of pairs `x.tuplize` decides under
# `TUPLE_ORDER=1`. 47 of 171 pairs, so the `TUPLE_ORDER=1` order is NOT the
# `TUPLE_ORDER=0` order and W2 is load-bearing rather than cosmetic.
def lt_ties.pair(+done: List<&2, LtKey>, +e: LtKey, n: U32) -> U32:
  match done:
    case Nil{}    : n
    case +d <> +r : lt_ties.pair(r, e, U32.add(n, b2u(U32.is_eq(LtKey.k(d), LtKey.k(e)))))

def lt_ties.go(srt: List<&2, LtKey>, +done: List<&2, LtKey>, n: U32) -> U32:
  match srt:
    case Nil{}   : n
    case +e <> r : lt_ties.go(r, List.append(&2, LtKey, done, [e]), lt_ties.pair(done, e, n))

def lt_lin_ties() -> U32:
  lt_ties.go(lt_srt(), Nil{}, 0)

# `lin_u<i>` -- THE CENTRE OF THE GATE. A reordering bug has the right node COUNT
# and the wrong list, so the per-uop tuple (op, rc, po, nk) is the only thing that
# can see it -- and it is also the row class that says a run_count is wrong rather
# than a priority. The rows are printed by WALKING the answer, so a short answer
# produces FEWER rows and the byte diff shows it as a missing line. `pre` is the
# row class (`lin` or `linc`) because the IDENTITY fixture is this same walk over a
# second sink, and two row classes over one walk is one walk with a prefix.
def lt_lin_u.nm(+pre: String, pos: U32) -> String:
  String.concat([pre, "_u", U32.show(pos)])

def lt_lin_u.tag(+k: KER.K, +v: U32) -> String:
  O.Ops.name.of(O.Arena.op(F.Folded.ar(KER.K.fx(k)), v))

# THE POSITIONAL READ, with `Bool.pick` taking the self-call as an argument, which
# is legal because both arms are total: the discarded branch walks the rest of the
# list and throws the answer away. `+e` because `LtKey.rc(e)` and the `pos` test
# are two reads.
def lt_srt_rc(srt: List<&2, LtKey>, +pos: U32) -> U32:
  match srt:
    case Nil{}     : 0
    case +e <> +r  : Bool.pick(U32, U32.is_zero(pos), LtKey.rc(e), lt_srt_rc(r, U32.sub(pos, 1)))

def lt_lin_u.rc(+srt: List<&2, LtKey>, +v: U32) -> U32:
  lt_srt_rc(srt, lt_nkey(srt, v))

def lt_lin_u.p(+pre: String, pos: U32, +srt: List<&2, LtKey>, +k: KER.K, +v: U32) -> String:
  String.concat([lt_lin_u.nm(pre, pos), "=", lt_lin_u.tag(k, v), " rc=", U32.show(lt_lin_u.rc(srt, v)),
                 " po=", U32.show(lt_po(F.Folded.ar(KER.K.fx(k)), v)),
                 " nk=", U32.show(lt_nkey(srt, v))])

def lt_lin_u.go(+pre: String, ix: List<&2, U32>, +pos: U32, +srt: List<&2, LtKey>, +k: KER.K,
                +acc: List<&2, String>) -> List<&2, String>:
  match ix:
    case Nil{}   : acc
    case v <> +r : lt_lin_u.go(pre, r, U32.add(pos, 1), srt, k,
                              List.append(&2, String, acc, [lt_lin_u.p(pre, pos, srt, k, v)]))

# ONE `IO.print` PER ROW CLASS, so a byte diff against the oracle shows a moved uop
# as a CHANGED line and a lost uop as a MISSING line -- never as a row count alone.
def lt_rows(+pre: String, +ix: List<&2, U32>, +srt: List<&2, LtKey>, +k: KER.K) -> IO(Unit):
  IO.print(lt_lines(lt_lin_u.go(pre, ix, 0, srt, k, Nil{})))

# THE IDENTITY SINK. `linc_*` is `SINK(CALL(STORE, ADD))`: six nodes, every
# priority already in nkey order, so `linearize` must return the input unchanged.
def lt_linc_srcs() -> String:
  lt_srcs(F.Folded.ar(KER.K.fx(lt_fix())), lt_lst_call())

def lt_linc_n() -> U32:
  U32.from_nat(nlen(lt_lst_call()))

def lt_linc_vm() -> String:
  lt_vm_print(lt_vm_call())

def lt_lin_edg() -> String:
  lt_edg(F.Folded.ar(KER.K.fx(lt_fix())), lt_lst())

def lt_linc_edg() -> String:
  lt_edg(F.Folded.ar(KER.K.fx(lt_fix())), lt_lst_call())

def lt_linc_nkey() -> String:
  lt_u32s(lt_lin_nkey.go(lt_lst_call(), 0, lt_srt_call(), Nil{}))

def lt_linc_ties() -> U32:
  lt_ties.go(lt_srt_call(), Nil{}, 0)

def lt_linc_rows() -> IO(Unit):
  lt_rows("linc", linearize(F.Folded.ar(KER.K.fx(lt_fix())), lt_lst_call(), lt_vm_call(), 21),
          lt_srt_call(), lt_fix())

# `lin_exmix` -- WHY `extra` IS NOT A FIELD. The COUNT of node pairs that tie on
# the composite key (run_count, priority) and disagree on whether `extra` is
# `None`. It is 0, so `extra` is never compared ACROSS types and Python -- which
# would raise `TypeError` on `None < int` -- does not raise. It is a gate and not
# a comment because dropping `extra` from `priorities` is only sound while it is
# 0, and `LtKey`'s fourth field exists to make this row computable.
def lt_exmix.hit(+d: LtKey, +e: LtKey) -> Bool:
  Bool.and(U32.is_eq(LtKey.k(d), LtKey.k(e)),
           Bool.xor(U32.is_eq(LtKey.ex(d), 4294967295), U32.is_eq(LtKey.ex(e), 4294967295)))

def lt_exmix.pair(+done: List<&2, LtKey>, +e: LtKey, n: U32) -> U32:
  match done:
    case Nil{}    : n
    case +d <> +r : lt_exmix.pair(r, e, U32.add(n, b2u(lt_exmix.hit(d, e))))

# THE WALK LIST IS THE FIRST PARAMETER and the accumulator is second, so the
# self-call's shrinking argument -- the tail -- is first and the GROWING list
# (`done`) is second. That is the notes' rule 5 read left to right, and it is
# also why this is not the same shape as `lt_ties.go` above: two accumulators
# cannot both be parameters after the tail, so the new `done` is a computed
# argument and the decrease check only ever sees the tail.
# THE CALL MUST PASS THE SORT FIRST. `lt_exmix.go(Nil{}, lt_srt(), 0)` TYPECHECKS
# -- both parameters are the same type -- and answers 0 because the walk list is
# empty, so the row was green and MEASURING NOTHING. Two same-typed parameters in
# a fold are a silent swap, and the row that catches one COUNTS a difference
# rather than testing a predicate.
def lt_exmix.go(walk: List<&2, LtKey>, +done: List<&2, LtKey>, n: U32) -> U32:
  match walk:
    case Nil{}   : n
    case +e <> +r : lt_exmix.go(r, List.append(&2, LtKey, done, [e]), lt_exmix.pair(done, e, n))

def lt_lin_exmix() -> U32:
  lt_exmix.go(lt_srt(), Nil{}, 0)

def lt_linc_exmix() -> U32:
  lt_exmix.go(lt_srt_call(), Nil{}, 0)

def lt_srt_idx.go(srt: List<&2, LtKey>, +acc: List<&2, U32>) -> List<&2, U32>:
  match srt:
    case Nil{}   : acc
    case e <> +r : lt_srt_idx.go(r, List.append(&2, U32, acc, [LtKey.i(e)]))

def lt_srt_idx() -> List<&2, U32>:
  lt_srt_idx.go(lt_srt(), Nil{})

def lt_srt_call_idx() -> List<&2, U32>:
  lt_srt_idx.go(lt_srt_call(), Nil{})

# ===========================================================================
# `CFGContext` -- linearizer.py:53-81, and `pm_add_control_flow` :83-85.
#
# THE THREE TABLES ARE ONE RECORD. `deps` is a U32 -> SET OF U32 map, `nesting`
# and `edges` are U32 -> U32 maps, all three are `RaTb`, and all three are keyed
# by an arena index -- which is why `Cfg` is a two-field `Data` record and not
# three parameters every call site has to keep in step. The walk is
# `for u in sink.toposort()` (:62) and for the `lin` sink `enter_calls=True`
# makes no difference (its only CALL belongs to the separate `linc` sink), so the
# walk list is `lt_lst` again.
#
# THE SET IS A LIST, and that is not a convenience. `deps[u]` is a DICT whose
# ITERATION ORDER decides which range `nesting` claims first, and `cfg_edges` is
# printed in `edges` insertion order, so a membership-only container would throw
# the row away. `|=` keeps an existing key's position and appends a new one, so
# the union is `a ++ [x for x in b if x not in a]` and NOT a fold that rebuilds
# the left side from the right.
# ===========================================================================
type Cfg is Data:
  Cfg{dp: RaTb, ns: RaTb}

def Cfg.dp(c: Cfg) -> RaTb:
  match c:
    case Cfg{dp, ns}: dp

def Cfg.ns(c: Cfg) -> RaTb:
  match c:
    case Cfg{dp, ns}: ns

# `deps[u] |= deps[s]` -- and the two arms are the dict's two behaviours: an
# existing key keeps its slot, a new key takes the next one. `+x` because
# `List.contains` and `[x]` are two reads.
def cfg_cat.a(+xs: List<&2, U32>, +x: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, List.contains(U32, U32.is_eq, xs, x),
            xs, List.append(&2, U32, xs, [x]))

# THE WALK LIST IS FIRST so the decrease check sees the tail (notes' rule 5).
def cfg_cat(ys: List<&2, U32>, +xs: List<&2, U32>) -> List<&2, U32>:
  match ys:
    case Nil{}   : xs
    case +y <> +r : cfg_cat(r, cfg_cat.a(xs, y))

# `for s in u.src: deps[u] |= deps[s]` -- :65, ONE fold over the node's srcs.
def cfg_deps(ss: List<&2, U32>, +deps: RaTb, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}   : acc
    case +s <> +r : cfg_deps(r, deps, cfg_cat(tb_vs(deps, s), acc))

def lt_is_loopend(+op: O.Op) -> Bool:
  Bool.or(lt_is_range(op), lt_is_exit(op))

# :67's `u.op in (Ops.END, Ops.BACKEDGE, Ops.SINK)` is NOT :69's
# `u.op in (Ops.RANGE, Ops.END, Ops.BACKEDGE)` -- the SINK is on the nesting line
# and the RANGE is on the self-add line, and the two sets differ in exactly one op
# each. One predicate for both is a silent bug that drops every SINK's edges.
def lt_is_loopnest(+op: O.Op) -> Bool:
  Bool.or(lt_is_sink(op), lt_is_exit(op))

# `deps[u][u] = None` -- :69, and it runs AFTER the `nesting` scan on the line
# above, so the scan must NOT see `u` in `deps[u]`. The order of these two defs
# is the order of the two lines.
def cfg_self.of(+op: O.Op, u: U32, +d: List<&2, U32>) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, lt_is_loopend(op), List.append(&2, U32, d, [u]), d)

def cfg_self(ar: O.Arena, +u: U32, +d: List<&2, U32>) -> List<&2, U32>:
  cfg_self.of(O.Arena.op(ar, u), u, d)

# `nesting |= {x:u for x in deps[u] if x.op in (END,BACKEDGE) and (u.op is SINK
# or u.src[1] in deps[x]) and x not in nesting}` -- :68. Three conjuncts, and the
# `x not in nesting` one is why this is a `Bool.pick` over a `tb_put` and not a
# put: `|=` keeps the FIRST claim and drops a second. `O.Arena.src(ar, u, 1)` is
# read unconditionally (`Bool.pick` is strict) even when `u` is a SINK; a node
# with fewer than two srcs reads the bottom, whose `deps` bucket is empty, so the
# test answers False either way.
# `u.op is Ops.SINK or u.src[1] in deps[x]` IS A SHORT-CIRCUIT `or`, and
# `Bool.or` IS NOT ONE: it evaluates both sides, so for a SINK it evaluates
# `deps[x]` against `sk.src[1]` and then `Bool.and`s a FALSE into the answer.
# `Bool.pick` reproduces the short-circuit as a VALUE choice -- the discarded
# branch still runs, but its answer is not ANDed in.
def cfg_nest.dep(+ar: O.Arena, +c: Cfg, +u: U32, +x: U32) -> Bool:
  Bool.pick(Bool, lt_is_sink(O.Arena.op(ar, u)),
            True{}, List.contains(U32, U32.is_eq, tb_vs(Cfg.dp(c), x), O.Arena.src(ar, u, 1)))

def cfg_nest.ok(+ar: O.Arena, +c: Cfg, +u: U32, +x: U32) -> Bool:
  Bool.and(lt_is_exit(O.Arena.op(ar, x)),
           Bool.and(cfg_nest.dep(ar, c, u, x), Bool.not(tb_has(Cfg.ns(c), x))))

def cfg_nest.hit(ok: Bool, +c: Cfg, +x: U32, +u: U32) -> Cfg:
  Bool.pick(Cfg, ok, Cfg{Cfg.dp(c), tb_put(Cfg.ns(c), x, u, Nil{})}, c)

def cfg_nest(d: List<&2, U32>, +ar: O.Arena, +c: Cfg, +u: U32) -> Cfg:
  match d:
    case Nil{}   : c
    case +x <> +r : cfg_nest(r, ar, cfg_nest.hit(cfg_nest.ok(ar, c, u, x), c, x, u), u)

# ONE NODE, in PYTHON's order: `deps[u]` is written first (:64-65 and :69) and
# the `nesting` scan runs second (:68), so the scan's ITERATION list is `d` -- the
# bucket BEFORE the self-add -- passed in as an argument rather than re-read from
# the table. BOTH ARMS write the bucket, and that is the load-bearing part: the
# write is `deps[u] = ...` for EVERY node, so folding it into the `if` arm alone
# leaves every CONST, CAST, STORE and RANGE with NO BUCKET, and the whole section
# then reads zero edges. `cfg_edges` is the row that saw it.
def cfg_step.of(+c: Cfg, +ar: O.Arena, +u: U32, +d: List<&2, U32>) -> Cfg:
  Cfg{tb_put(Cfg.dp(c), u, 0, cfg_self(ar, u, d)), Cfg.ns(c)}

def cfg_step.go(+c: Cfg, +ar: O.Arena, +u: U32, +d: List<&2, U32>) -> Cfg:
  Bool.pick(Cfg, lt_is_loopnest(O.Arena.op(ar, u)),
            cfg_nest(d, ar, cfg_step.of(c, ar, u, d), u), cfg_step.of(c, ar, u, d))

def cfg_step(+c: Cfg, +ar: O.Arena, +u: U32) -> Cfg:
  cfg_step.go(c, ar, u, cfg_deps(O.Arena.srcs(ar, u), Cfg.dp(c), Nil{}))

def cfg_go(rest: List<&2, U32>, +ar: O.Arena, +c: Cfg) -> Cfg:
  match rest:
    case Nil{}   : c
    case u <> +r : cfg_go(r, ar, cfg_step(c, ar, u))

def cfg_ctx(ar: O.Arena) -> Cfg:
  cfg_go(lt_lst(), ar, Cfg{tb_new(), tb_new()})

# `siblings.setdefault(vv, []).append(k)` -- :73. One bucket per parent, in
# `nesting` INSERTION order, and the bucket IS the table's `vs` field, so
# `.append(k)` is `tb_put` with `vs = [k]`: `tb_ins.cat` PREPENDS the argument to
# the bucket already there, and the new tail is the whole argument. Walking
# `tb_keys(ns)` rather than `RaTb.es(ns)` is what keeps the insertion order.
#
# THE ACCUMULATOR IS ITS OWN PARAMETER, separate from `ns`, and that is load
# bearing. Handing `put` the SOURCE table -- which typechecks, because both are
# `RaTb` -- makes every iteration rebuild on `nesting` and the answer is the
# nesting table plus one entry per iteration, never merged. `cfg_edges_n` is the
# row that saw it, and it saw 1 where the merge would have given 1 as well: the
# bucket that mattered was never built.
def cfg_sib.put(+acc: RaTb, +ns: RaTb, +u: U32, +k: U32) -> RaTb:
  tb_put(acc, u, k, [k])

def cfg_sib.go(+ns: RaTb, ks: List<&2, U32>, +acc: RaTb) -> RaTb:
  match ks:
    case Nil{}   : acc
    case +k <> +r : cfg_sib.go(ns, r, cfg_sib.put(acc, ns, tb_get(ns, k), k))

def cfg_sib(+ns: RaTb) -> RaTb:
  cfg_sib.go(ns, tb_keys(ns), tb_new())

# `sorted(v, key=lambda x: len([u for u in v if u in deps[x]]))` -- :76. A
# STABLE SORT on a COUNT, so the element is a two-field record (the count key and
# the node) and the comparator is `<=` on the count -- exactly the shape
# `lt_sorted` is for the linearizer's keys. `Sb` is therefore the SECOND
# composite key in this file and it exists for the same reason as the first:
# `List.sort` wants `A -> A -> Bool` and a count is not a field of the element.
type Sb is Data:
  Sb{ks: U32, i: U32}

def Sb.ks(x: Sb) -> U32:
  match x:
    case Sb{ks, i}: ks

def Sb.i(x: Sb) -> U32:
  match x:
    case Sb{ks, i}: i

# `List.sort`'s COMPARATOR TYPE IS `@a -> @b -> Bool` WITH NO ANNOTATION, so a
# comparator's parameters must stay BARE: `+b` is refused with "expected
# @_:Sb -> @_:Sb -> Bool, observed @a:Sb -> @+b:Sb -> Bool". Every comparator here reads
# each field ONCE, which is what `Sb.ks(a)` and not a `match` is for.
def sb_le(a: Sb, b: Sb) -> Bool:
  U32.is_le(Sb.ks(a), Sb.ks(b))

# `reverse=True` -- `sorted(rngs, key=..., reverse=True)` at :90 is the SAME sort
# with the comparison FLIPPED, not a reversal of the output, so `>=` over a stable
# merge is exactly it and equal keys keep their input order.
def sb_ge(a: Sb, b: Sb) -> Bool:
  U32.is_ge(Sb.ks(a), Sb.ks(b))

def cfg_cnt.hit(ok: Bool, +n: U32) -> U32:
  Bool.pick(U32, ok, U32.add(n, 1), n)

def cfg_cnt(+vs: List<&2, U32>, +deps: RaTb, +x: U32, +n: U32) -> U32:
  match vs:
    case Nil{}   : n
    case u <> +r : cfg_cnt(r, deps, x, cfg_cnt.hit(List.contains(U32, U32.is_eq, tb_vs(deps, x), u), n))

def cfg_key(+vs: List<&2, U32>, +deps: RaTb, rest: List<&2, U32>) -> List<&2, Sb>:
  match rest:
    case Nil{}   : Nil{}
    case +x <> +r : List.append(&2, Sb, [Sb{cfg_cnt(vs, deps, x, 0), x}], cfg_key(vs, deps, r))

def cfg_unkey(srt: List<&2, Sb>, +acc: List<&2, U32>) -> List<&2, U32>:
  match srt:
    case Nil{}   : acc
    case +e <> +r : cfg_unkey(r, List.append(&2, U32, acc, [Sb.i(e)]))

def cfg_order(+vs: List<&2, U32>, +deps: RaTb) -> List<&2, U32>:
  cfg_unkey(List.sort(Sb, sb_le, cfg_key(vs, deps, vs)), Nil{})

# `for x,y in zipped: self.edges[y.src[1]] = x` -- :78-81, and BOTH `zipped`
# spellings at :77 are "consecutive pairs of ONE list": the SINK case is the PLAIN
# `order` and the non-SINK case prepends `k.src[1]` to it, so there is ONE walk and
# not a two-arm dispatch. The dispatch is one predicate wide and getting it
# backwards is invisible in the EDGE COUNT on a fixture with one bucket: the SINK
# arm gives 2 pairs over a 2-element list where the non-SINK arm gives 1, and
# `cfg_edges` is the row that names the extra one.
# W3: `assert y.src[1] not in x.backward_slice_with_self` (:80) is NOT PORTED.
# `backward_slice_with_self` is a recursive reachability over UOps and this arena
# has no such reader; :79's own comment says the assert "can happen" on
# shufflenet, so it is a live guard, not a dead one. The claim that dropping it is
# safe ON THIS FIXTURE is `cfg_edges_n` and the shape of `cfg_hits`.
def cfg_edge.put(+ed: RaTb, +ar: O.Arena, x: U32, y: U32) -> RaTb:
  tb_put(ed, O.Arena.src(ar, y, 1), x, Nil{})

# THE RECURSION IS ON THE TAIL AFTER `x`, not after `y`. `zip(xs, xs[1:])` is
# (xs[0],xs[1]), (xs[1],xs[2]), ... and the OVERLAP is the whole of it: recursing
# past `y` answers only the disjoint pairs, so a three-element list gives one edge
# where `zip` gives two. `List.is_empty` on the tail is `zip`'s one-element case
# (it yields nothing) and it is the ONLY guard, because `at(r, 0n)` on an empty
# tail answers 0 -- the bottom -- which would invent an edge.
def cfg_edge(rest: List<&2, U32>, +ed: RaTb, +ar: O.Arena) -> RaTb:
  match rest:
    case Nil{}        : ed
    case +x <> +r     : Bool.pick(RaTb, List.is_empty(&2, U32, r), ed,
                          cfg_edge(r, cfg_edge.put(ed, ar, x, at(r, 0n)), ar))

def cfg_bucket(+ed: RaTb, +ar: O.Arena, +k: U32, +vs: List<&2, U32>) -> RaTb:
  Bool.pick(RaTb, lt_is_sink(O.Arena.op(ar, k)),
            cfg_edge(vs, ed, ar),
            cfg_edge(List.append(&2, U32, [O.Arena.src(ar, k, 1)], vs), ed, ar))

def cfg_edges(rest: List<&2, RaEn>, +ar: O.Arena, +deps: RaTb, +ed: RaTb) -> RaTb:
  match rest:
    case Nil{}   : ed
    case +e <> +r : cfg_edges(r, ar, deps, cfg_bucket(ed, ar, RaEn.k(e), cfg_order(RaEn.vs(e), deps)))

# `nesting` is `dict[child, parent]` and `siblings` is `dict[parent, [child]]` --
# two different keys -- so the regrouping is a real step and NOT the identity, and
# walking `nesting` directly would bucket every child under ITSELF.
def cfg_ed(ar: O.Arena, +c: Cfg) -> RaTb:
  cfg_edges(RaTb.es(cfg_sib(Cfg.ns(c))), ar, Cfg.dp(c), tb_new())

# ===========================================================================
# `pm_add_control_flow` -- linearizer.py:83-85. ONE rule, ONE op, and the whole
# rewrite is `x.src + (edges[x],)`, so the table is two rows and the answer is
# either the new node's src list or `-`.
# ===========================================================================
def cfg_tbl() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsRANGE{}], Nil{}}]

# `.replace` keeps `arg` and `tag` and the arena hash-conses, so a rewrite whose
# `src` is unchanged answers the same index. The `hit` flag is a separate field
# rather than a comparison of indices because the MISS arm does not build a node
# at all -- Python's `else None` is the absence of an edge, and an index
# comparison would confuse "no edge" with "the edge is the node itself".
type Cg is Data:
  Cg{ar: O.Arena, hit: Bool, ix: U32}

def Cg.ar(+c: Cg) -> O.Arena:
  match c:
    case Cg{ar, hit, ix}: ar

def Cg.hit(+c: Cg) -> Bool:
  match c:
    case Cg{ar, hit, ix}: hit

def Cg.ix(+c: Cg) -> U32:
  match c:
    case Cg{ar, hit, ix}: ix

def cfg_rewrite.put(+f: O.Found) -> Cg:
  Cg{O.Found.ar(f), True{}, O.Found.i(f)}

def cfg_rewrite.new(+ar: O.Arena, ed: RaTb, +x: U32) -> Cg:
  cfg_rewrite.put(O.UOp.new(ar, O.OpsRANGE{},
                            List.append(&2, U32, O.Arena.srcs(ar, x), [tb_get(ed, x)]),
                            O.Arena.arg(ar, x), O.Arena.tag(ar, x)))

def cfg_rewrite.pick(hit: Bool, +ar: O.Arena, +ed: RaTb, +x: U32) -> Cg:
  Bool.pick(Cg, hit, cfg_rewrite.new(ar, ed, x), Cg{ar, False{}, x})

def cfg_rewrite(+ar: O.Arena, +ed: RaTb, +x: U32) -> Cg:
  cfg_rewrite.pick(tb_has(ed, x), ar, ed, x)

# ---------------------------------------------------------------------------
# THE `cfg_*` ROWS. `cfg_edges` prints `key/axis->value.op` in `edges` insertion
# order, which is why the assoc list's key order had to be Python's.
# ---------------------------------------------------------------------------
def lt_slash.axis(a: O.Arg) -> U32:
  match a:
    case O.ARange{ids, at}: lt_lab.ids(ids)
    case _: 0

def lt_slash.of(+op: O.Op, +a: O.Arg) -> String:
  Bool.pick(String, lt_is_range(op),
            String.concat(["RANGE/", U32.show(lt_slash.axis(a))]),
            O.Ops.name.of(op))

def lt_slash(+ar: O.Arena, +v: U32) -> String:
  lt_slash.of(O.Arena.op(ar, v), O.Arena.arg(ar, v))

# `List.get` answers a `Maybe` and every table here is non-empty by construction,
# so the table read has ONE `Maybe.default` and every other table read is the
# table itself.
def cfg_entry(ts: List<&2, O.PMEntry>, n: Nat) -> O.PMEntry:
  Maybe.default(&2, O.PMEntry, List.get(&2, O.PMEntry, ts, n), O.PMEntry{0, Nil{}, Nil{}})

def lt_ops_name.go(ops: List<&2, O.Op>, +acc: List<&2, String>) -> List<&2, String>:
  match ops:
    case Nil{}   : acc
    case +o <> +r : lt_ops_name.go(r, List.append(&2, String, acc, [O.Ops.name.of(o)]))

def lt_ops_name(ops: List<&2, O.Op>) -> String:
  String.join(lt_ops_name.go(ops, Nil{}), " ")

def cfg_edges_str(rest: List<&2, RaEn>, +ar: O.Arena, +acc: List<&2, String>) -> List<&2, String>:
  match rest:
    case Nil{}    : acc
    case +e <> +r : cfg_edges_str(r, ar, List.append(&2, String, acc,
                          [String.concat([lt_slash(ar, RaEn.k(e)), "->",
                                          O.Ops.name.of(O.Arena.op(ar, RaEn.v(e)))])]))

def cfg_edges_row(+ar: O.Arena, +ed: RaTb) -> String:
  String.join(cfg_edges_str(RaTb.es(ed), ar, Nil{}), " ")

def cfg_edges_n(+ed: RaTb) -> U32:
  U32.from_nat(nlen(tb_keys(ed)))

# `cfg_hits` -- the rewrite's answer per range, `-` where `edges.get(x)` is None.
# The range pair is the FIXTURE's two RANGEs (`linc` has none) and it is a literal
# for the same reason `lt_lst` is: it is an input, not a computed answer.
def cfg_rngs() -> List<&2, U32>:
  [10, 15]

# `lt_srcs` SPACES its pieces, so this row needs its own COMMA join: the oracle's
# `','.join(u.op.name for u in r2.src)` is a different separator, and reusing the
# space-joined printer would make the row a diff over punctuation.
def cfg_hit.of(+c: Cg, +ar: O.Arena, +r: U32) -> String:
  Bool.pick(String, Cg.hit(c),
            String.concat([U32.show(lt_slash.axis(O.Arena.arg(ar, r))), "->[",
                           String.join(lt_srcs.go(Cg.ar(c), O.Arena.srcs(Cg.ar(c), Cg.ix(c)), Nil{}), ","),
                           "]"]),
            "-")

def cfg_hit(+ar: O.Arena, +ed: RaTb, +r: U32) -> String:
  cfg_hit.of(cfg_rewrite(ar, ed, r), ar, r)

def cfg_hits.go(rs: List<&2, U32>, +ar: O.Arena, +ed: RaTb, +acc: List<&2, String>) -> List<&2, String>:
  match rs:
    case Nil{}    : acc
    case +r <> +t : cfg_hits.go(t, ar, ed, List.append(&2, String, acc, [cfg_hit(ar, ed, r)]))

def cfg_hits(+ar: O.Arena, +ed: RaTb) -> String:
  String.join(cfg_hits.go(cfg_rngs(), ar, ed, Nil{}), " ")

def cfg_tbl_len() -> U32:
  KER.n_of(cfg_tbl())

def cfg_tbl_ops() -> String:
  lt_ops_name(O.PMEntry.ops(cfg_entry(cfg_tbl(), 0n)))

# ===========================================================================
# `do_split_ends` and `pm_split_ends` -- linearizer.py:87-96.
#
# W1: `((s,) if s.op is Ops.RANGE else s.ranges)` -- :89. The `else` half is a
# `UOp.ranges` READER and is NOT PORTED; `se_ranges.of` answers the empty list
# there. The fixture is built so every `e.src[1:]` IS a RANGE (the oracle's own
# comment says the same), so the arm is NAMED and not exercised -- a wall, not a
# closed one. `se_rngs` is the row that would move if the arm were filled in for
# a fixture that had a non-RANGE src, and `se_len` counts the END nodes actually
# BUILT, so a stub that built one END instead of three would be caught.
# ===========================================================================
def se_dup1(+acc: List<&2, U32>, +s: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, List.contains(U32, U32.is_eq, acc, s),
            acc, List.append(&2, U32, acc, [s]))

# `dedup` is `H.dedup_u32` REVERSED, so it is written here rather than shared:
# `dedup` as a SET is order-blind and `dedup` as a LIST is not, and this one is
# the list kind because it feeds a `sorted`.
def se_dedup(ss: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}   : acc
    case +s <> +r : se_dedup(r, se_dup1(acc, s))

def se_ranges.of(+ar: O.Arena, +s: U32) -> List<&2, U32>:
  Bool.pick(List<&2, U32>, lt_is_range(O.Arena.op(ar, s)), [s], Nil{})

def se_rngs(ss: List<&2, U32>, +ar: O.Arena, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}   : acc
    case +s <> +r : se_rngs(r, ar, se_dedup(List.append(&2, U32, se_ranges.of(ar, s), acc), acc))


def se_key(+rngs: List<&2, U32>, +ar: O.Arena, rest: List<&2, U32>) -> List<&2, Sb>:
  match rest:
    case Nil{}   : Nil{}
    case +x <> +r : List.append(&2, Sb, [Sb{lt_slash.axis(O.Arena.arg(ar, x)), x}], se_key(rngs, ar, r))

def se_unkey(srt: List<&2, Sb>, +acc: List<&2, U32>) -> List<&2, U32>:
  match srt:
    case Nil{}   : acc
    case +e <> +r : se_unkey(r, List.append(&2, U32, acc, [Sb.i(e)]))

# `key=lambda x: x.arg, reverse=True` -- :90. `x.arg` for a RANGE is the axis
# tuple, so the key is the axis id and the sort is DESCENDING.
def se_sort(+ar: O.Arena, +rngs: List<&2, U32>) -> List<&2, U32>:
  se_unkey(List.sort(Sb, sb_ge, se_key(rngs, ar, rngs)), Nil{})

# `ret = ret.end(r)` -- :90. `UOp.end` is `UOp(Ops.END, (ret, r), None)`, which
# returns the new ARENA as well as the index, so `Se` carries both. The recursion
# calls the two-call constructor twice because the arena and the index come from
# separate reads; interning makes the two answers the same node so they agree, and
# the alternative -- threading one four-field record -- costs a def for a
# property of the hash-cons.
type Se is Data:
  Se{ar: O.Arena, i: U32}

def Se.ar(x: Se) -> O.Arena:
  match x:
    case Se{ar, i}: ar

def Se.i(x: Se) -> U32:
  match x:
    case Se{ar, i}: i

def Se.of(+f: O.Found) -> Se:
  Se{O.Found.ar(f), O.Found.i(f)}

def se_end(+ret: U32, r: U32, +ar: O.Arena) -> Se:
  Se.of(O.UOp.new(ar, O.OpsEND{}, [ret, r], O.ANone{}, O.TNone{}))

def do_split_ends(rngs: List<&2, U32>, +ret: U32, +ar: O.Arena) -> Se:
  match rngs:
    case Nil{}   : Se{ar, ret}
    case +x <> +t : do_split_ends(t, Se.i(se_end(ret, x, ar)), Se.ar(se_end(ret, x, ar)))

# `do_split_ends` -- :87-91. `ret = e.src[0]` and the range list, sorted descending
# by axis, is the loop's fuel.
def se_rngs_of(+ar: O.Arena, e: U32) -> List<&2, U32>:
  se_sort(ar, se_rngs(O.Arena.src_from(ar, e, 1), ar, Nil{}))

def se_of(+ar: O.Arena, +e: U32) -> Se:
  do_split_ends(se_rngs_of(ar, e), O.Arena.src(ar, e, 0), ar)

# `pm_split_ends` -- :93-96. ONE rule on END, so `se_tbl_len`, `se_tbl_ops` and the
# `se_fired`/`se_miss` pair are the whole table, and the MISS row is the
# non-movement fixture the notes' rule 17 asks for.
def se_tbl() -> List<&2, O.PMEntry>:
  [O.PMEntry{0, [O.OpsEND{}], Nil{}}]

def se_fired(+ar: O.Arena, v: U32) -> U32:
  b2u(lt_is_end(O.Arena.op(ar, v)))

# `se_len` is the COUNT of END nodes in the arena `do_split_ends` BUILT, walked
# over the node list -- not `nlen(rngs)`. The two agree because the loop is
# `for r in sorted(rngs): ret = ret.end(r)`, and counting is the honest gate: a
# `se_len` derived from the range list would still read 3 if the loop body
# stopped building an END.
def se_cnt(rest: List<&2, O.Node>, +n: U32) -> U32:
  match rest:
    case Nil{}    : n
    case +d <> +r : se_cnt(r, Bool.pick(U32, lt_is_end(O.Node.op(d)), U32.add(n, 1), n))

# AND MINUS THE ONE END THE FIXTURE STARTED WITH, because the arena is walked, not
# the graph: `e` is not in `ret`'s toposort but it IS in the arena.
def se_len(+se: Se, skip: U32) -> U32:
  U32.sub(se_cnt(O.Arena.nodes(Se.ar(se)), 0), skip)

def se_nsrc(+se: Se) -> U32:
  O.Arena.nsrc(Se.ar(se), Se.i(se))

# THE TOPOSORT of the built graph, as a LITERAL, for the same reason `lt_lst` is
# one: `toposort` is ops.py's and not this file's, and a literal that disagrees
# is the row `se_ops` rather than a silent difference under it. The LABELS come
# from the arena, so `se_ops` still gates the built graph -- a `se_len` of 3 over
# the wrong three nodes changes it.
#   F2's CONST/CAST, then R2's CONST/CAST and R2, then the first END, then R1's
# CONST/CAST and R1, then the second END, then R0 (whose CONST is already cached)
# and the third END. `e` itself is NOT in `ret`'s graph, so it is absent.
def se_lst() -> List<&2, U32>:
  [5, 6, 1, 2, 9, 11, 3, 4, 8, 12, 7, 13]

def se_lab.of(+op: O.Op, +a: O.Arg) -> String:
  String.concat([O.Ops.name.of(op), "/",
                 Bool.pick(String, lt_is_range(op), U32.show(lt_slash.axis(a)), "-")])

def lt_lab2.go(ix: List<&2, U32>, +ar: O.Arena, +acc: List<&2, String>) -> List<&2, String>:
  match ix:
    case Nil{}   : acc
    case +v <> +r : lt_lab2.go(r, ar, List.append(&2, String, acc, [se_lab.of(O.Arena.op(ar, v), O.Arena.arg(ar, v))]))

def se_lab_str(+ar: O.Arena, ix: List<&2, U32>) -> String:
  String.join(lt_lab2.go(ix, ar, Nil{}), " ")

def se_tbl_len() -> U32:
  KER.n_of(se_tbl())

def se_tbl_ops() -> String:
  lt_ops_name(O.PMEntry.ops(cfg_entry(se_tbl(), 0n)))

# THE `se` FIXTURE. `e = END(F2, R0, R1, R2)` with the three axes in ASCENDING
# order, so `sorted(key=arg, reverse=True)` is a REORDER and not the identity --
# `se_rngs` reading `0 1 2` would be a `sorted` that does nothing. R0 and R2
# share the CONST 4 and R1 has the CONST 8, so the three `CONST/CAST` PAIRS are
# all reachable and `se_ops` shows three of them.
#   1 C4a 2 C4  3 C8a 4 C8  5 C2f 6 F2  7 R0 8 R1 9 R2  10 E
def se_fix() -> KER.K:
  +c4a = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  +c4 = lt_i32(4, O.Found.ar(c4a))
  +c8a = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(8)})
  +c8 = lt_i32(8, O.Found.ar(c8a))
  +c2f = O.UOp.const(O.Found.ar(c8), O.CFloat{2.0})
  +f2 = O.UOp.new(O.Found.ar(c2f), O.OpsCAST{}, [O.Found.i(c2f)], O.ADt{S.single()}, O.TNone{})
  +r0 = O.UOp.new(O.Found.ar(f2), O.OpsRANGE{}, [O.Found.i(c4)], O.ARange{[0], O.AXIS_LOOP{}}, O.TNone{})
  +r1 = O.UOp.new(O.Found.ar(r0), O.OpsRANGE{}, [O.Found.i(c8)], O.ARange{[1], O.AXIS_LOOP{}}, O.TNone{})
  +r2 = O.UOp.new(O.Found.ar(r1), O.OpsRANGE{}, [O.Found.i(c4)], O.ARange{[2], O.AXIS_LOOP{}}, O.TNone{})
  +e = O.UOp.new(O.Found.ar(r2), O.OpsEND{},
                 [O.Found.i(f2), O.Found.i(r0), O.Found.i(r1), O.Found.i(r2)], O.ANone{}, O.TNone{})
  KER.K{F.folded(O.Found.ar(e)),
    [0, O.Found.i(c4a), O.Found.i(c4), O.Found.i(c8a), O.Found.i(c8), O.Found.i(c2f),
     O.Found.i(f2), O.Found.i(r0), O.Found.i(r1), O.Found.i(r2), O.Found.i(e)]}

def se_e(+k: KER.K) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, KER.K.ix(k), 10n), 0)

def se_se(+k: KER.K) -> Se:
  se_of(F.Folded.ar(KER.K.fx(k)), se_e(k))

# `se_rngs` -- the LOOP'S FUEL, printed by axis. It is the row that says the
# `dedup` kept all three and the `reverse=True` sort put them in descending axis
# order, which is the order `ret.end(r)` is called in.
def se_rngs_str(rngs: List<&2, U32>, +ar: O.Arena, +acc: List<&2, String>) -> List<&2, String>:
  match rngs:
    case Nil{}   : acc
    case +r <> +t : se_rngs_str(t, ar, List.append(&2, String, acc, [U32.show(lt_slash.axis(O.Arena.arg(ar, r)))]))

def se_rngs_row(+k: KER.K) -> String:
  String.join(se_rngs_str(se_rngs_of(F.Folded.ar(KER.K.fx(k)), se_e(k)),
                          F.Folded.ar(KER.K.fx(k)), Nil{}), " ")

# The labels come out of the BUILT arena, not the fixture's, so `se_ops` gates the
# chain `do_split_ends` produced and not only the fixture's own nodes.
def se_ops_row(+k: KER.K) -> String:
  se_lab_str(Se.ar(se_se(k)), se_lst())

# THE THREE SHARED READERS of the CFG section. `cfg_ctx` and `cfg_ed` each walk
# the whole graph, and `cfg_hits` rewrites against the SAME `edges` table, so the
# table is read once per row rather than once per row CLASS.
def lt_ar() -> O.Arena:
  F.Folded.ar(KER.K.fx(lt_fix()))

def lt_cfged() -> RaTb:
  cfg_ed(lt_ar(), cfg_ctx(lt_ar()))

def se_ar() -> O.Arena:
  F.Folded.ar(KER.K.fx(se_fix()))
def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row("ix_len", lt_ix_len())
    b : Unit <- srow("ix", lt_ix())
    c : Unit <- row("po_param", lt_po_param())
    d : Unit <- row("po_bufl", lt_po_bufl())
    e : Unit <- row("po_bufg", lt_po_bufg())
    f : Unit <- row("po_load", lt_po_load())
    g : Unit <- row("po_store", lt_po_store())
    h : Unit <- row("po_range", lt_po_range())
    i : Unit <- row("po_end", lt_po_end())
    j : Unit <- row("po_backedge", lt_po_backedge())
    k : Unit <- row("po_add", lt_po_add())
    l : Unit <- row("rc_nil", lt_rc_nil())
    m : Unit <- row("rc_1", lt_rc_1())
    n : Unit <- row("rc_2", lt_rc_2())
    o : Unit <- row("rc_3", lt_rc_3())
    p : Unit <- row("rc_max", lt_rc_max())
    q : Unit <- row("rc_big", lt_rc_big())
    r : Unit <- srow("lin_srcs", lt_lin_srcs())
    s : Unit <- row("lin_n", lt_lin_n())
    t : Unit <- srow("lin_vm", lt_lin_vm())
    t2 : Unit <- srow("lin_edg", lt_lin_edg())
    u : Unit <- srow("lin_nkey", lt_lin_nkey())
    v : Unit <- srow("lin_ord", lt_srcs(F.Folded.ar(KER.K.fx(lt_fix())), lt_srt_idx()))
    w : Unit <- lt_rows("lin", linearize(F.Folded.ar(KER.K.fx(lt_fix())), lt_lst(), lt_vm_lst(), 19),
                        lt_srt(), lt_fix())
    x : Unit <- row("lin_ties", lt_lin_ties())
    y : Unit <- row("lin_exmix", lt_lin_exmix())
    p1 : Unit <- srow("linc_srcs", lt_linc_srcs())
    p2 : Unit <- row("linc_n", lt_linc_n())
    p3 : Unit <- srow("linc_vm", lt_linc_vm())
    p3b : Unit <- srow("linc_edg", lt_linc_edg())
    p4 : Unit <- srow("linc_nkey", lt_linc_nkey())
    p5 : Unit <- srow("linc_ord", lt_srcs(F.Folded.ar(KER.K.fx(lt_fix())), lt_srt_call_idx()))
    p6 : Unit <- lt_linc_rows()
    p7 : Unit <- row("linc_ties", lt_linc_ties())
    p8 : Unit <- row("linc_exmix", lt_linc_exmix())
    q1 : Unit <- srow("cfg_edges", cfg_edges_row(lt_ar(), lt_cfged()))
    q2 : Unit <- row("cfg_edges_n", cfg_edges_n(lt_cfged()))
    q3 : Unit <- srow("cfg_hits", cfg_hits(lt_ar(), lt_cfged()))
    q4 : Unit <- row("cfg_tbl_len", cfg_tbl_len())
    q5 : Unit <- srow("cfg_tbl_ops", cfg_tbl_ops())
    r1 : Unit <- srow("se_rngs", se_rngs_row(se_fix()))
    r2 : Unit <- srow("se_ops", se_ops_row(se_fix()))
    r3 : Unit <- row("se_len", se_len(se_se(se_fix()), 1))
    r4 : Unit <- row("se_nsrc", se_nsrc(se_se(se_fix())))
    r5 : Unit <- row("se_tbl_len", se_tbl_len())
    r6 : Unit <- srow("se_tbl_ops", se_tbl_ops())
    r7 : Unit <- row("se_fired", se_fired(se_ar(), se_e(se_fix())))
    # THE LAST ROW IS UNBOUND and IS the `do IO<Unit>` block's final
    # expression, so there is no trailing `IO.print("")` and the file ends
    # with the LAST ROW's newline -- what the oracle's `print("\n".join(out))`
    # does. A trailing empty line is a one-line diff a reader must notice.
    row("se_miss", se_fired(se_ar(), 7))
