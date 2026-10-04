# ===========================================================================
# THE TWELVE -- __init__.py:82-301. THE RULE BODIES, in the order they unblock.
#
# The header deferred this region on THREE clauses, and the measurement in
# `.agents/slop/lintable/06-UNBLOCKED.md` found TWO of the three false, so the
# order below is what the measurement said and not what the header said:
#
#   * C1 "every rule is a graph_rewrite" -- FALSE for FOUR of the fifteen:
#     `is_store_after`, `assert_all_same_devices`, `canonicalize_call_body` and
#     `apply_binds` are plain functions with NO table at all.
#   * C2 "...over the arena with a PYTHON ctx DICT" -- the WEAKER of the two
#     live claims, and it fails twice over. FIVE of the twelve take NO ctx at
#     all (`lower_sink_to_linear`, `copy_kernel_to_store`,
#     `simplify_copy_kernel`, `assert_all_same_devices`, `apply_binds`), and the
#     TWO that do take one take the SAME `CallifyCtx` whose `dict` field is one
#     of four and is not the load-bearing one -- `collect_stores` writes
#     `stores`, a LIST, and never reads `allocs`.
#   * C3, the linear rule table -- held for 8 of 15 and is the WEAKEST claim of
#     the three: 12 were never behind it.
#
# WHAT IS HERE: EIGHT of the twelve, under UPSTREAM NAMES. The four that are
# not, and their `file:line` walls, are at the end of this block. Of the
# remaining three of the fifteen that the table unblocked
# (`create_new_buffer` :90, `resolve_linear_call` :103, `transform_to_call` :261)
# none lives in this file, so the honest count against the DENOMINATOR OF FIFTEEN
# is ELEVEN present and FOUR walls.
#
# `sb-oracle.py` computes every expectation below from CPython. None is typed,
# and `SCHEDULE-BODIES.md` carries the lane comparison.
# ===========================================================================

# ---------------------------------------------------------------------------
# 1. `is_store_after` -- __init__.py:217-218. NO ctx, NO table, NO fold, and it
# is the FIRST of the twelve with NO WALL AT ALL:
#
#     def is_store_after(u:UOp) -> bool:
#       return u.op is Ops.AFTER and (u.src[0].unsharded_base.op is not Ops.ALLOC
#                                     or u.src[1].op is Ops.STORE)
#
# `UOp.unsharded_base` (ops.py:792) is already in ops.bend and the fuel is
# `Arena.budget`, which is EXACT for a walk that cannot revisit a node.
# `sc_src(ar, u, 1)` answers 0 -- the bottom NOOP -- where Python raises
# IndexError, and `isa_SA_E` is the row that pins the rescue onto `src[1]` and
# NOT onto `nsrc`: SA_E is an AFTER with TWO srcs and its second is an END, so
# it answers False.
# ---------------------------------------------------------------------------
def is_store_after(+ar: O.Arena, +u: U32) -> Bool:
  Bool.and(sc_is_after(ar, u),
    Bool.or(Bool.not(sc_is(ar, O.UOp.unsharded_base(O.Arena.budget(ar), ar, sc_src0(ar, u)), O.OpsALLOC{})),
      sc_is(ar, sc_src(ar, u, 1), O.OpsSTORE{})))

# ---------------------------------------------------------------------------
# 2. `CallifyCtx` -- __init__.py:192-197. THE C2 CLAUSE, and this is the whole
# of it: a dataclass of a list, a dict, a set and another list.
#
#     @dataclass
#     class CallifyCtx:
#       replacements: list[UOp] = field(default_factory=list)
#       allocs: dict[UOp, UOp] = field(default_factory=dict)
#       views: set[UOp] = field(default_factory=set)
#       stores: list[UOp] = field(default_factory=list)
#
# All four are append-only `List`s IN PYTHON'S FIELD ORDER, because the order
# decides WHICH list a rule body writes: `collect_stores` writes `stores`,
# `canonicalize_alloc` writes `allocs`, `replace_input_buffer` writes
# `replacements` and `contiguous_mops_to_view` writes `views`. A record whose
# fields are re-ordered answers the RIGHT list while the gate says it wrote the
# wrong one, so `cs_reps`/`cs_allocs`/`cs_views` are rows and not decoration.
# `allocs` is the `dict[UOp,UOp]` and it is an ASSOCIATION LIST `Aa{b,v}`, one
# entry per key, because Bend's `Map` is String-keyed and this dict is keyed by
# the node -- the same bill `ka_go` pays for `children`.
#
# `views` is a Python `set` and `set.add` DEDUPLICATES while `list.append` does
# NOT. `cs_dup2` is the identity row for `stores`; no row covers `views` because
# no body ported here writes it.
# ---------------------------------------------------------------------------
type Aa is Data:
  Aa{b: U32, v: U32}

type CallifyCtx is Data:
  CallifyCtx{replacements: List<&2, U32>, allocs: List<&2, Aa>, views: List<&2, U32>, stores: List<&2, U32>}

def CallifyCtx.of() -> CallifyCtx:
  CallifyCtx{Nil{}, Nil{}, Nil{}, Nil{}}

def CallifyCtx.replacements(x: CallifyCtx) -> List<&2, U32>:
  match x:
    case CallifyCtx{replacements, allocs, views, stores}: replacements

def CallifyCtx.allocs(x: CallifyCtx) -> List<&2, Aa>:
  match x:
    case CallifyCtx{replacements, allocs, views, stores}: allocs

def CallifyCtx.views(x: CallifyCtx) -> List<&2, U32>:
  match x:
    case CallifyCtx{replacements, allocs, views, stores}: views

def CallifyCtx.stores(x: CallifyCtx) -> List<&2, U32>:
  match x:
    case CallifyCtx{replacements, allocs, views, stores}: stores

def Aa.b(x: Aa) -> U32:
  match x:
    case Aa{b, v}: b

def Aa.v(x: Aa) -> U32:
  match x:
    case Aa{b, v}: v

# `ctx.allocs.get(b, None)` -- the ONE reader of `allocs` a ported body needs.
def ag_pick(hit: Bool, acc: Maybe<&2, U32>, v: U32) -> Maybe<&2, U32>:
  match hit:
    case True{} : Some{v}
    case False{}: acc

def ag_go(+as: List<&2, Aa>, +b: U32, acc: Maybe<&2, U32>) -> Maybe<&2, U32>:
  match as:
    case Nil{}       : acc
    case Aa{j, v} <> t: ag_go(t, b, ag_pick(U32.is_eq(j, b), acc, v))

def aa_get(c: CallifyCtx, +b: U32) -> Maybe<&2, U32>:
  ag_go(CallifyCtx.allocs(c), b, None{})

# `ctx.allocs[b] = v`. INSERT if absent and REPLACE if present -- Python's
# `dict[k] = v` does both -- so the walk needs the `found` accumulator `ka_go`
# uses: without it a second write leaves TWO entries for ONE key, and `ca_n3` is
# the row that sees it.
def ap_tail(found: Bool, +b: U32, +v: U32) -> List<&2, Aa>:
  match found:
    case True{} : Nil{}
    case False{}: [Aa{b, v}]

def ap_pick(hit: Bool, r: List<&2, Aa>, j: U32, old: U32, +v: U32) -> List<&2, Aa>:
  match hit:
    case True{} : List.append(&2, Aa, [Aa{j, v}], r)
    case False{}: List.append(&2, Aa, [Aa{j, old}], r)

def ap_go(+as: List<&2, Aa>, found: Bool, +b: U32, +v: U32) -> List<&2, Aa>:
  match as:
    case Nil{}        : ap_tail(found, b, v)
    case Aa{j, old} <> t:
      r = ap_go(t, Bool.or(found, U32.is_eq(j, b)), b, v)
      ap_pick(U32.is_eq(j, b), r, j, old, v)

def aa_put(c: CallifyCtx, +b: U32, +v: U32) -> CallifyCtx:
  CallifyCtx.of(CallifyCtx.replacements(c),
    ap_go(CallifyCtx.allocs(c), False{}, b, v),
    CallifyCtx.views(c), CallifyCtx.stores(c))

# `b in ctx.allocs`
def aa_has(+as: List<&2, Aa>, +b: U32) -> Bool:
  match as:
    case Nil{}       : False{}
    case Aa{j, _} <> t: Bool.or(U32.is_eq(j, b), aa_has(t, b))

# ---------------------------------------------------------------------------
# 3. `collect_stores` -- __init__.py:220-221. NEEDS ctx, and it is one of only
# TWO of the twelve that do:
#
#     def collect_stores(ctx:CallifyCtx, u:UOp):
#       if is_store_after(u): ctx.stores.append(u)
#
# Python returns None on BOTH arms and the rewriter reads that as "no rewrite",
# so the ANSWER is `None{}` twice and the only effect is the append. A rule body
# that mutated the ctx and returned the node would be a DIFFERENT rule, so the
# ctx and the answer come back TOGETHER in `Cw`: Python's one-call-one-side-effect
# signature cannot be spelled, and splitting it into two defs would let a caller
# drop one of them.
# ---------------------------------------------------------------------------
type Cw is Data:
  Cw{c: CallifyCtx, a: Maybe<&2, U32>}

def Cw.c(x: Cw) -> CallifyCtx:
  match x:
    case Cw{c, a}: c

def Cw.a(x: Cw) -> Maybe<&2, U32>:
  match x:
    case Cw{c, a}: a

def cs_put(hit: Bool, c: CallifyCtx, +u: U32) -> CallifyCtx:
  match hit:
    case True{} : CallifyCtx.of(CallifyCtx.replacements(c), CallifyCtx.allocs(c),
                 CallifyCtx.views(c), List.append(&2, U32, CallifyCtx.stores(c), [u]))
    case False{}: c

def collect_stores(c: CallifyCtx, +ar: O.Arena, +u: U32) -> Cw:
  Cw{cs_put(is_store_after(ar, u), c, u), None{}}

# THE EIGHT CALLS in the gate's order, so `cs_ops2` is an APPEND-ORDER row and
# not a count. `cs_dup2` is the identity row: `stores[1]` and `stores[2]` are the
# same SA_B, so a `set` would answer 2 where the list answers 3.
def cs_run.go(+us: List<&2, U32>, +ar: O.Arena, c: CallifyCtx) -> CallifyCtx:
  match us:
    case Nil{}     : c
    case u <> rest : cs_run.go(rest, ar, Cw.c(collect_stores(c, ar, u)))

def cs_run(c: CallifyCtx, +ar: O.Arena, us: List<&2, U32>) -> CallifyCtx:
  cs_run.go(us, ar, c)

# ---------------------------------------------------------------------------
# 4. `lower_sink_to_linear` -- __init__.py:124-126. NO ctx. THE GUARD is ported
# and the guard is what decides whether the schedule cache is consulted at all:
#
#     function = call.body
#     if function.op is not Ops.SINK or isinstance(function.arg, KernelInfo)
#        or not call.arg.precompile: return None
#
# `UOp.body` (ops.py:562) answers `Maybe<&2,U32>` and its `None{}` is Python's
# `raise`, so a non-CALL answers `None{}` here too. `sc_gate.ker` IS
# `isinstance(arg, KernelInfo)` -- the same reader the toposort gate uses, which
# is why this is one call and not a second `match`.
#
# WHAT IS NOT PORTED, and it is the rest of the function:
#   TODO(p3) __init__.py:127-131  `time.perf_counter` and `function.key` --
#     `function.key` is a `bytes` CONTENT hash of the whole function and
#     nothing in this tree computes one. AGENTS.md says inject time rather than
#     read a clock, so the clock is not the wall; the KEY is.
#   TODO(p3) __init__.py:130-131  `schedule_cache` and `diskcache_get`. THIS is
#     the trap worth naming: `schedule_cache` is a MODULE-LEVEL `dict[bytes,UOp]`
#     read at :130 BEFORE `create_schedule` is called at :135, so a spec run twice
#     in one process answers from the cache and NEVER re-enters the function. A
#     Bend `Map` cache would inherit that memo, and a gate row that called
#     `lower_sink_to_linear` twice in one process would be measuring the cache
#     and not the guard. The guard below is therefore cache-free BY CONSTRUCTION
#     -- it takes no cache at all -- and `lsl_none_*` are real CPython calls of
#     the real function, so they exercise the same early return.
#   TODO(p3) __init__.py:133      `if SPEC: type_verify(function, spec_tensor)`
#   TODO(p3) __init__.py:135      `get_kernel_graph(prepare_rangeify(function))`
#     -- `schedule/rangeify.py` and `schedule/prepare.py`, out of scope.
#   TODO(p3) __init__.py:141-150  the `inspect.stack()` DEBUG block.
# ---------------------------------------------------------------------------
def lsl_pre(arg: O.Arg) -> Bool:
  match arg:
    case O.ACall{ci}: O.CallInfo.precompile(ci)
    case _           : False{}

def lsl_ok(pre: Bool, +ar: O.Arena, +fn: U32) -> Bool:
  Bool.and(Bool.and(sc_is(ar, fn, O.OpsSINK{}), Bool.not(sc_gate.ker(sc_arg(ar, fn)))), pre)

def lsl_of(ok: Bool, fn: U32) -> Maybe<&2, U32>:
  match ok:
    case True{} : Some{fn}
    case False{}: None{}

# THE FUNCTION ANSWERS THE `fn` INDEX and not `call`, because the answer in
# Python is a REWRITTEN `call` and `call.replace(src=(linear,)+call.src[1:])` is
# behind the same key. `lsl_p_*` are the three predicates as separate defs, since
# `lsl_p_*` are rows and a row that is only the conjunction cannot say WHICH
# conjunct moved.
def lower_sink_to_linear(+ar: O.Arena, +call: U32) -> Maybe<&2, U32>:
  lsl_of(lsl_ok(lsl_pre(sc_arg(ar, call)), ar, Maybe.default(&2, U32, O.UOp.body(ar, call), 0)),
    sc_src0(ar, call))

def lower_sink_to_linear.p_sink(pre: Bool, +ar: O.Arena, +call: U32) -> Bool:
  sc_is(ar, Maybe.default(&2, U32, O.UOp.body(ar, call), 0), O.OpsSINK{})

def lower_sink_to_linear.p_ki(pre: Bool, +ar: O.Arena, +call: U32) -> Bool:
  sc_gate.ker(sc_arg(ar, Maybe.default(&2, U32, O.UOp.body(ar, call), 0)))

def lower_sink_to_linear.p_pre(+ar: O.Arena, +call: U32) -> Bool:
  lsl_pre(sc_arg(ar, call))

def lower_sink_to_linear.p_ok(pre: Bool, +ar: O.Arena, +call: U32) -> Bool:
  Bool.and(Bool.and(lower_sink_to_linear.p_sink(pre, ar, call),
    Bool.not(lower_sink_to_linear.p_ki(pre, ar, call))),
    lower_sink_to_linear.p_pre(ar, call))

# ---------------------------------------------------------------------------
# 5. `copy_kernel_to_store` -- __init__.py:161-163, and
# 6. `simplify_copy_kernel` -- __init__.py:165-172. BOTH NO ctx, and BOTH open
# with THE SAME LINE, which is why they share `cks_fire` and why `sck_*` is two
# rows over ONE predicate rather than a merge:
#
#     if dst.device == src.device and not (isinstance(dst.device, str)
#        and dst.device.startswith("DISK")): return None
#
# THE DEVICE IS A TAG, NOT A NAME. `S.Dev` is `D1{tag}` / `Dn{tags}` and the name
# is gone, so `startswith("DISK")` cannot be asked here. `schedule/memory.bend:189`
# already hit this on `startswith(("DISK","CL","WEBGPU"))` and the treatment is a
# PARAMETER: `disk` is the DISK TAG SET and the caller is the device table. So
# `disk=[]` is a PERMITTED answer and the prefix test is PARAMETERISED, not
# ported. `Dn` is a TUPLE and Python's `isinstance(dst.device, str)` is False for
# it, so `Dn` answers False whatever `disk` says -- `cks_disk_n` is that row.
#
# `dst.device` for a PARAM is `self.arg.device` (ops.py:888), read straight off
# the `ParamArg`, so no fold is needed. The general `.device` -- ops.py:889-895's
# STAGE/AFTER/MSELECT/MSTACK arms and the "first src with a device" tail -- IS
# `fold.bend`'s and needs a `Table`:
#   TODO(p3) ops.py:889-895  `.device`'s non-PARAM arms -- `fold.device`.
#
# `dst.store(src)` is `UOp.store` and IS in ops.bend, and `call.replace(src=
# (stored,)+call.src[1:])` is `cks_rep` -- the local `replace` at :971 is
# hard-wired to the linearizer's own shape, so this is its own def.
# ---------------------------------------------------------------------------
def cks_dev(arg: O.Arg) -> Maybe<&2, S.Dev>:
  match arg:
    case O.AParam{pa}: O.ParamArg.device(pa)
    case _            : None{}

def cks_dev.of(+ar: O.Arena, +u: U32) -> Maybe<&2, S.Dev>:
  cks_dev(sc_arg(ar, u))

# the scrutinees are CALLS and a `match` may not scrutinise a call, so they go in
# as parameters -- the same bill `sc_gate.of` pays.
def cks_dev.eq(x: Maybe<&2, S.Dev>, y: Maybe<&2, S.Dev>) -> Bool:
  match x y:
    case Some{p} Some{q}: O.eq_dev(p, q)
    case _            _   : False{}

def cks_dev.same(+ar: O.Arena, +d: U32, +s: U32) -> Bool:
  cks_dev.eq(cks_dev.of(ar, d), cks_dev.of(ar, s))

def cks_disk(disk: List<&2, U32>, m: Maybe<&2, S.Dev>) -> Bool:
  match m:
    case Some{dev}:
      match dev:
        case S.D1{t} : List.contains(U32, U32.is_eq, disk, t)
        case S.Dn{ts}: False{}
    case None{}    : False{}

def cks_fire(disk: List<&2, U32>, +ar: O.Arena, +dst: U32, +src: U32) -> Bool:
  Bool.and(cks_dev.same(ar, dst, src), Bool.not(cks_disk(disk, cks_dev.of(ar, dst))))

def cks_rep(ar: O.Arena, +call: U32, +head: U32) -> O.Found:
  O.UOp.new(ar, sc_op(ar, call),
    List.append(&2, U32, [head], sc_src_from(ar, call, 1)), sc_arg(ar, call), sc_tag(ar, call))

def cks_put(fire: Bool, +ar: O.Arena, +call: U32, +dst: U32, +src: U32) -> Maybe<&2, O.Found>:
  match fire:
    case True{}:
      +st = O.UOp.store(ar, dst, src, None{})
      Some{cks_rep(O.Found.ar(st), call, O.Found.i(st))}
    case False{}: None{}

# `r:UOp|None=None` is the FOURTH parameter and NOBODY PASSES IT -- the two
# patterns at :181 and :184 bind only `call`, `dst`, `src`, `r` -- so it is not a
# parameter here.
def copy_kernel_to_store(disk: List<&2, U32>, +ar: O.Arena, +call: U32, +dst: U32, +src: U32) -> Maybe<&2, O.Found>:
  cks_put(cks_fire(disk, ar, dst, src), ar, call, dst, src)

# THE GUARD OF `simplify_copy_kernel` IS PORTED AND THE RULE IS NOT, so the def
# is `simplify_copy_kernel.ok` and NOT `simplify_copy_kernel`. The answer is a
# SINK and the only way to get one is
#
#     graph_rewrite(ast, sym+pm_mops+pm_flatten_range+pm_simplify_ranges,
#                   ctx={}, name="simplify ranges in copy")
#
# a bottom-up rewrite over FOUR matchers, two of them imported at :168-170.
# Naming a def `simplify_copy_kernel` that answers the guard's BOOLEAN would put
# a WRONG ANSWER under an UPSTREAM NAME and a caller would take it for the rule.
#   TODO(p3) __init__.py:171  the four-matcher bottom_up rewrite -- THE WALL.
#   TODO(p3) __init__.py:168-170  `sym` / `pm_flatten_range` /
#     `pm_simplify_ranges` -- no port. `pm_mops` is `schedule/prepare.bend`'s.
def simplify_copy_kernel.ok(disk: List<&2, U32>, +ar: O.Arena, +dst: U32, +src: U32) -> Bool:
  cks_fire(disk, ar, dst, src)

# ---------------------------------------------------------------------------
# 7. `assert_all_same_devices` -- __init__.py:157-159. NO ctx, NO table:
#
#     devices = dedup([x.device for x in ast.toposort()
#                      if x.op is Ops.PARAM and x.device is not None])
#     if len(devices) >= 2: raise RuntimeError(...)
#
# `UOp.toposort` (ops.bend:2839) is the ungated one, so no `sc_topo` copy is
# needed. `dedup` preserves FIRST-OCCURRENCE order and the arena interns, so two
# structurally equal UOps are ONE index: the dedup is over INDICES and a
# `List.contains` over the kept ones is the same set -- the argument `sc_newks`
# makes for `prev_kernels`.
#
# THE ANSWER IS NOT A BOOLEAN. Python RETURNS None and the RAISE is the whole
# effect, and a rule body must return a node, so `Ads` carries the DEVICES --
# the same treatment `cycles` gets above. `asd_raises` is the `>= 2` THRESHOLD
# and `asd_two` (ONE device) is the row that pins it: a `>= 1` mutation leaves
# every other row green.
#
# THE THREE-WAY SELECTOR IS ONE `match` AND NOT A NESTED ONE, because a `match`
# nested inside a `case h <> t:` LIST arm is REFUSED in bend 2.0.34 (this file's
# rule 1). Class 1 is "a PARAM with a device we have not kept yet".
#   TODO(p3) __init__.py:159  the RuntimeError -- a raise.
# ---------------------------------------------------------------------------
type Ads is Data:
  Ads{ds: List<&2, U32>}

def Ads.ds(x: Ads) -> List<&2, U32>:
  match x:
    case Ads{ds}: ds

def asd_cls(ispar: Bool, hasdev: Bool, seen: Bool) -> U32:
  match ispar hasdev seen:
    case True{} True{} True{}  : 0
    case True{} True{} False{} : 1
    case _      _      _       : 0

def asd_go(+kept: List<&2, U32>, +xs: List<&2, U32>, +ar: O.Arena) -> List<&2, U32>:
  match xs:
    case Nil{}     : kept
    case x <> rest :
      match asd_cls(sc_is(ar, x, O.OpsPARAM{}),
                     Maybe.is_some(&2, S.Dev, cks_dev.of(ar, x)),
                     List.contains(U32, U32.is_eq, kept, x)):
        case 1: asd_go(List.append(&2, U32, kept, [x]), rest, ar)
        case _: asd_go(kept, rest, ar)

def assert_all_same_devices(+ar: O.Arena, +ast: U32) -> Ads:
  Ads{asd_go(Nil{}, O.UOp.toposort(O.Arena.budget(ar), ar, ast), ar)}

# `if len(devices) >= 2: raise`. 2147483648 is `>= 2`'s other side: the THRESHOLD
# is two, not one, and `asd_two` is the row that says so.
def assert_all_same_devices.raises(x: Ads) -> Bool:
  Bool.not(U32.is_lt(U32.from_nat(List.length(&2, U32, Ads.ds(x))), 2))

# ---------------------------------------------------------------------------
# 8. `apply_binds` -- __init__.py:110-114. NO ctx. THE THREE-ARM DISPATCH is
# ported and ARM 3 IS NOT, so the def is `apply_binds` and the answer is an ARM
# NUMBER (1, 2, 3) and not a node:
#
#     def apply_binds(si:UOp) -> UOp:
#       if si.op is Ops.CALL and si.body.op is Ops.LINEAR:  return resolve_linear_call(si, binds)
#       if si.op is Ops.CALL and si.body.op is Ops.PROGRAM: return si
#       subs = {v:binds[v.arg.slot] for s in si.src for v in s.variables() if v.arg.slot in binds}
#       return si.replace(src=tuple(s.substitute(subs, ...) for s in si.src))
#
# ARM 3 needs `UOp.variables` and `UOp.substitute` and NEITHER IS IN THE TREE:
# `fold.bend`'s own header names `variables` as one of the three readers waiting
# on the RANGES FOLD, and `ops.py:1239 UOp.substitute` waits behind it.
# `ab_C_LIN` is arm 1, whose recursion target `resolve_linear_call` is already in
# `uop/ops.bend` as tag 42's table, so arm 1 is REACHABLE and is not ported here
# only because it needs `binds` (:107-109), which is `dict[int,UOp]` keyed by a
# Python int -- the same String-keyed-`Map` bill `Aa` pays above.
#   TODO(p3) __init__.py:113  `s.variables()` -- no reader in the tree.
#   TODO(p3) __init__.py:114  `s.substitute`   -- no reader in the tree.
#   TODO(p3) __init__.py:107-109  `binds`, a `dict[int,UOp]` -- arm 1.
# ---------------------------------------------------------------------------
def apply_binds.arm(iscall: Bool, linear: Bool, program: Bool) -> U32:
  match iscall linear program:
    case True{}  True{}  _       : 1
    case True{}  False{} True{}  : 2
    case _       _      _       : 3

def apply_binds.of(iscall: Bool, bop: O.Op) -> U32:
  apply_binds.arm(iscall, O.eq_op(bop, O.OpsLINEAR{}), O.eq_op(bop, O.OpsPROGRAM{}))

def apply_binds(+ar: O.Arena, +si: U32) -> U32:
  apply_binds.of(sc_is(ar, si, O.OpsCALL{}),
    sc_op(ar, Maybe.default(&2, U32, O.UOp.body(ar, si), 0)))

# ---------------------------------------------------------------------------
# 9. `canonicalize_alloc` -- __init__.py:235-237. NEEDS ctx, and it is the
# SECOND and LAST of the two bodies that do:
#
#     def canonicalize_alloc(ctx:CallifyCtx, b:UOp):
#       if b.arg.slot >= 0 and b not in ctx.allocs:
#         ctx.allocs[b] = b.replace(arg=replace(b.arg, slot=-1-len(ctx.allocs)))
#       return ctx.allocs.get(b)
#
# THREE THINGS ARE THE PORT AND ALL THREE HAVE A ROW:
#   * `-1 - len(ctx.allocs)`, so the slots are -1, -2, ... and NOT 0, -1, ...
#     (`ca_slot1`/`ca_slot2`, ONE ROW APART, from fixtures whose incoming slots
#     are 7 and 9 -- so a port that dropped the `-1-` would answer 0 and 1).
#   * the `b not in ctx.allocs` GUARD, so a second call on the same `b` writes
#     nothing and returns the SAME node (`ca_n3`, `ca_repeat`).
#   * `slot >= 0`, so a slot that is ALREADY canonical is left alone and the
#     answer is `None{}` (`ca_neg_none`, `ca_neg_n`). Python's `None` and the
#     rewriter's "no rewrite" are the same value here and NOT by accident.
#
# **`ParamArg.slot` IS A `U32` AND PYTHON'S IS AN `int`.** That is the whole
# difficulty of the third clause: `slot >= 0` is TRUE for every Python int, so the
# only thing it can be excluding is a NEGATIVE slot, and in a `U32` the negative
# range is the TOP half. `ca_neg_*` uses an incoming slot of `-3`, which this file
# writes as `4294967293`, and `ca_slot.of` writes `-1 - n` as `4294967295 - n`.
# A port that read `>= 0` as `!= 0` would answer the same for every slot the
# gate holds, because none of them is 0 -- so `ca_slot1` and `ca_neg_none` are
# the pair that separates the two readings.
#
# `b.replace(arg=replace(b.arg, slot=n))` is `dataclasses.replace` on a
# 13-field `ParamArg`, so `ca_slot.of` rebuilds the record with one field moved.
# `ca_arg.of` answers `None{}` for a non-`AParam`, and that `None{}` is Python's
# AttributeError -- `ca_noarg` is that row, and it is the one place the port is
# total where Python raises.
# ---------------------------------------------------------------------------
def ca_slot.of(x: O.ParamArg, n: U32) -> O.ParamArg:
  match x:
    case O.ParamArg{slot, dtype, size, vmin_vmax, multiple_of, name, addrspace, device,
                    volatile, image, buffer, bind_on_realize, val}:
      O.ParamArg{n, dtype, size, vmin_vmax, multiple_of, name, addrspace, device,
        volatile, image, buffer, bind_on_realize, val}

def ca_arg.of(arg: O.Arg) -> Maybe<&2, O.ParamArg>:
  match arg:
    case O.AParam{pa}: Some{pa}
    case _           : None{}

def ca_arg.slot(arg: O.Arg) -> Maybe<&2, U32>:
  match arg:
    case O.AParam{pa}: Some{O.ParamArg.slot(pa)}
    case _           : None{}

# `slot >= 0` on a Python int is `slot < 2**31` on the port's U32.
def ca_fresh(s: Maybe<&2, U32>, +as: List<&2, Aa>, +b: U32) -> Bool:
  match s:
    case Some{v}: Bool.and(U32.is_lt(v, 2147483648), Bool.not(aa_has(as, b)))
    case None{}  : False{}

# `-1 - len(ctx.allocs)` as a U32: one wrap, and `ca_slot1`/`ca_slot2` are the
# rows that would catch a wrap in the WRONG DIRECTION (`1 - len` answers 1 and 0
# and is still "negative-looking" enough to pass a boolean row).
def ca_slotn(c: CallifyCtx) -> U32:
  U32.sub(4294967295, U32.from_nat(List.length(&2, Aa, CallifyCtx.allocs(c))))

type CaPut is Data:
  CaPut{c: CallifyCtx, a: Maybe<&2, O.Found>}

def CaPut.c(x: CaPut) -> CallifyCtx:
  match x:
    case CaPut{c, a}: c

def CaPut.a(x: CaPut) -> Maybe<&2, O.Found>:
  match x:
    case CaPut{c, a}: a

def ca_new(fresh: Bool, +pa: O.ParamArg, +ar: O.Arena, c: CallifyCtx, +b: U32) -> CaPut:
  match fresh:
    case True{}:
      +f = O.UOp.new(ar, sc_op(ar, b), sc_srcs(ar, b), O.AParam{pa}, sc_tag(ar, b))
      CaPut{aa_put(c, b, O.Found.i(f)), Some{f}}
    case False{}: CaPut{c, None{}}

def canonicalize_alloc(c: CallifyCtx, +ar: O.Arena, +b: U32) -> CaPut:
  match ca_arg.of(sc_arg(ar, b)):
    case Some{pa}:
      ca_new(ca_fresh(ca_arg.slot(sc_arg(ar, b)), CallifyCtx.allocs(c), b),
        ca_slot.of(pa, ca_slotn(c)), ar, c, b)
    case None{}: CaPut{c, None{}}

# THE TWO WALLS THAT REMAIN, each with `file:line`, and each NOT a `graph_rewrite`:
#
# 10. `canonicalize_call_body` -- __init__.py:239-240. NO ctx. IT IS A ONE-LINE
#     BODY WHOSE ONE LINE IS THE REWRITER:
#         c.replace(src=(graph_rewrite(c.body, pm_canonicalize_alloc,
#                                     ctx=CallifyCtx(), bottom_up=True),)+c.src[1:])
#     The `c.replace(src=(X,)+c.src[1:])` half is `cks_rep` above and is PORTED;
#     the `graph_rewrite` half is the bottom_up engine over `PMEntrys`, which is
#     `uop/ops.bend`'s `pm_rewrite_m` and is not exported. There is no ctx work
#     left to do here -- `CallifyCtx` exists above -- so the wall is the ENGINE.
#     TODO(p3) __init__.py:240  `graph_rewrite(..., bottom_up=True)` -- no
#     bottom_up entry point; `ops.bend` has the top-down scan only.
#
# 11. `replace_input_buffer` -- __init__.py:248-250. NEEDS ctx, and it is the
#     ONLY ctx body left, so it is the last C2 item:
#         ctx.replacements.append(b)
#         return b.param_like(len(ctx.replacements)-1)
#     The append is one `List.append` and the `len` is one `List.length`; the
#     mint is the wall. `UOp.param_like` is `TODO(p3) ops.py:1239` in
#     `uop/ops.bend:4398` -- named, unported, and named as a TODO, so this is a
#     recorded deferral and not a gap I found.
#     TODO(p3) ops.py:1239  `UOp.param_like` -- no port. Blocks this body.
#
# 12. `contiguous_mops_to_view` -- __init__.py:199-215. It is the one of the
#     twelve that `06-UNBLOCKED.md` found passes NO ctx on any call, and that is
#     right about the CALL SITES but not about the SIGNATURE: :207 recurses with
#     `ctx` and :213 writes `ctx.views.add(view)`. So it needs ctx, weakly --
#     `if ctx is not None` at :213 makes the write optional.
#     It is the LARGEST of the twelve (17 lines) and every one of its five
#     helpers is missing or walled:
#     TODO(p3) ops.py:559  `all_int(c.shape)` -- `c.shape` needs `fold.bend`'s
#       `UOp.shape` and a whole-arena `Table`; `all_int` itself is
#       `helpers.bend`'s `all_int_nest` over a `Nest`.
#     TODO(p3) ops.py:561  `src.base` is ported; the `while buf.op is BITCAST`
#       peel is `UOp.base` with BITCAST added and is NOT a reader here.
#     TODO(p3) __init__.py:206  `graph_rewrite(src, multi_pm)` --
#       `schedule/multi.py`'s table.
#     TODO(p3) ops.py    `src.contiguous_view()` -- ABSENT from the tree. This is
#       the binding one: `:210` returns None when it is None, so without it the
#       rule has no fallthrough case and answering anything else would be a
#       fabrication.
#     TODO(p3) __init__.py:212  `buf[a:b]` (SHRINK) and `.bitcast`.
#     TODO(p3) __init__.py:214  `.reshape` -- `mixin/movement.bend`'s.
#     TODO(p3) __init__.py:208  `.unshard` -- ABSENT from the tree.
#
# 13. `create_linear_with_vars` -- __init__.py:273-301. NO ctx, and it is the
#     TOP: five `graph_rewrite` passes at :276, :279, :282 plus the two at :240
#     and :267 inside the bodies above, `capturing[0].add_linear` at :297,
#     `memory_plan_rewrite` at :301, `used_vars` at :285 (which needs
#     `UOp.variables`, the same reader arm 3 of `apply_binds` needs) and the
#     `RuntimeError` bind-mismatch check at :292. Porting it before any of the
#     five matchers it calls would be a name with no body.
#     TODO(p3) __init__.py:276  `pm_schedule` -> `lower_sink_to_linear` (ported
#       above) but the PASS is a rewriter.
#     TODO(p3) __init__.py:279  `pm_resolve_linear_call` -> `resolve_linear_call`
#       (in `ops.bend`) + `pm_flatten_linear` from `engine/realize.py`.
#     TODO(p3) __init__.py:282  `pm_copy_from_store` -> the two bodies above plus
#       `assert_all_same_devices`, and the PASS is a rewriter.
#     TODO(p3) __init__.py:285  `used_vars` -- `UOp.variables`.
#     TODO(p3) __init__.py:301  `memory_plan_rewrite` -- `schedule/memory.py`.