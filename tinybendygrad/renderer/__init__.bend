# tinybendygrad/renderer/__init__.bend -- tinygrad/renderer/__init__.py.
#
# ===========================================================================
# THE CONVENTIONS. `wgsl.bend` reads this header and nothing else. It is here
# rather than in a notes file because `__init__.py` is where the shared base
# lives, and a renderer that skips these re-learns every one of them by failing.
#
# 1. A RENDERER IS A `Data` RECORD OF ITS OPTIONS -- not a class, not a table of
#    closures. Python's `self.type_map` / `self.barrier` / `self.kernel_typedef`
#    are class attributes and a subclass is the base with fields replaced; Bend
#    has no inheritance, so `Data` plus one constructor def per device IS the
#    inheritance. Nothing mutates after construction.
#
# 2. THE GATE IS A STRING DIFF, NEVER A BOOLEAN ABOUT STRINGS. `String.concat`
#    drops a literal silently, so `render(..) == "..."` is not a claim. Every row
#    prints its answer BESIDE the CPython string, so a dropped ", " is a DIFF.
#    A count row is necessary and nowhere near sufficient.
#
# 3. A `Data` RECORD MAY NOT HOLD A `Maybe` FIELD. Flatten to a `Bool` plus the
#    payload and let the `False` arm be the `None`. `Renderer.global_max` is
#    `tuple|None`, so it is `has_gmax: Bool` plus `gmax: List<&2, U32>`.
#
# 4. A `match` MAY ONLY SCRUTINISE A PARAMETER OR A PATTERN BINDER. `match
#    fold.dt(ar, tb, i):` is refused -- "a match cannot scrutinize a computed
#    value: give it its own def". EVERY reader is therefore two defs: the arena
#    read, then a `.of` that matches the `Maybe`. There is no third way.
#
# 5. A PARAM IS AFFINE UNLESS PREFIXED `+`, AND A `let` IS AFFINE TOO. A value
#    read twice is a `+` parameter; a value bound to a `let` and read twice is
#    RECOMPUTED, not bound. `+` cannot be spelled on a closure type or a `Maybe`
#    parameter, so the two-`Maybe` readers pass the `Maybe` to a separate `.of`.
#
# 6. A RECORD LITERAL AND A RECORD PATTERN BOTH MUST NAME EVERY FIELD. There is
#    no projection syntax in Bend 2.0.34 (`pa.slot` is "expected : a defined
#    name"), so a `ParamArg` with one field changed is thirteen
#    `O.ParamArg.*(pa)` calls. AND THE FIELD ORDER IS ops.bend's DECLARATION
#    order, not the header's prose order: `volatile, image, buffer,
#    bind_on_realize, val`. Read the declaration.
#
# 7. A `do IO<Unit>:` BODY MUST END WITH A BARE TERM, not a `_ : Unit <- ...`
#    binding, and a def whose body is a `do` block must be the LAST def in the
#    file. MEASURED on 2.0.34 while writing this file; both errors are parse
#    errors with unhelpful locations. `main` is therefore last.
#
# 8. A RECURSIVE ARENA REBUILD MUST BE BUILT ON THE INNER NODE'S ARENA --
#    `O.Found.ar(inner)`, never the arena handed in. An arena only GROWS, so the
#    passed arena is a PREFIX and the inner node's index is not in it; the outer
#    node's src0 then points past the end and `Arena.arg` answers the bottom's
#    `ABad`. It typechecks, it runs, and it prints a plausible wrong answer.
#    MEASURED: `INDEX float src0=?` where CPython prints `float`.
#
# 9. A SELF-CALL MUST BE LEXICALLY INSIDE THE DEF THAT OWNS THE FUEL MATCH. A
#    def may only call defs above it, so a helper that HOLDS the self-call cannot
#    be separated from the recursion -- that is mutual recursion and Bend refuses
#    it, and `hoist.py` reports "no progress" after eight rounds. So the guard
#    Bool is a PARAMETER of the recursive def (a `match` may scrutinise a
#    parameter) and the self-call is one expression in one arm. The non-recursive
#    rebuild helper goes ABOVE the recursion, which is legal for exactly this
#    reason.
#
# 10. GIVE THE WALLS NAMES. A rule that cannot be answered returns the marker
#     CPython prints for "not applicable" and says so in a comment, rather than a
#     plausible wrong string. The one that matters under this file:
#     `Ops.SHRINK`'s DTYPE is DEFERRED in `fold.bend` (`marg` -> `zip` ->
#     `ssimplify`), so asking the fold for a SHRINK's dtype answers `None`, and
#     a renderer that needs it has no value to render. That is `fold.bend`'s to
#     own; `cstyle.bend` records it where it bites.
#
# 11. `u.max_numel()` IS `prod(to_max_shape(shape))` AND `to_max_shape` IS A
#     SYMBOLIC `vmax` -- a WALL (`TODO(p3) ops.py:1886` in the port). The shape
#     the port CAN answer is the CONCRETE one, whose every dim is an `SInt` `SI`
#     rather than a symbolic `SU`, so `max_numel` here is the product of the
#     concrete dims and a shape carrying an `SU` is the case this file does not
#     have. Name the two cases apart rather than answering 1 for both.
#
# 12. A GATE ROW IS ONLY WORTH ITS COST IF A MUTATION MOVES IT. The mutation
#     table at the foot of `cstyle.bend` is the evidence that the rows bite.
# ===========================================================================

import Base
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../LAWS/spec.bend as S

# ===========================================================================
# `with_storage` -- __init__.py:11-13
#
#     def with_storage(x:UOp, dt:DType) -> UOp:
#       if x.op in {Ops.PARAM, Ops.BUFFER, Ops.ALLOC}: return x.replace(arg=replace(x.arg, dtype=dt))
#       return x.replace(src=(with_storage(x.src[0], dt),)+x.src[1:])
#
# "an access takes its dtype from the buffer it indexes, so accessing at another
# dtype restates the storage on the buffer that owns it" -- the comment above it
# is the SPEC, and the two arms are the spec's two halves: the three storage ops
# restate the dtype on the node that OWNS the storage, and everything else
# restates it on its FIRST src. src[1:] is COPIED, never visited.
#
# IT RETURNS THE ARENA, per the port's rule that a rewrite returns the arena and
# not a pair. The recursion is on the graph, which is not a tree, so the fuel is
# the FIRST parameter of the self-call and the budget is `Arena.budget` -- nodes
# PLUS edges, the same bound `UOp.toposort` uses. Under-running it returns the
# input arena unchanged, which is a wrong answer rather than a crash.
#
# `leaf` IS A PARAMETER and not a computed `match` scrutinee, for convention 9:
# the two arms and the recursion have to be in ONE def, so the Bool that picks
# the arm is a parameter and the `match` may scrutinise it.
# ===========================================================================

def with_storage.fuel(f: O.Found) -> Nat: O.Arena.budget(O.Found.ar(f))

def with_storage.is_store(op: O.Op) -> Bool:
  match op:
    case O.OpsPARAM{}: True{}
    case O.OpsBUFFER{}: True{}
    case O.OpsALLOC{}: True{}
    case _: False{}

# `replace(x.arg, dtype=dt)`. Thirteen accessors, because there is no projection
# syntax -- convention 6.
def with_storage.arg(+pa: O.ParamArg, dt: S.Dt) -> O.ParamArg:
  O.ParamArg{O.ParamArg.slot(pa), dt, O.ParamArg.size(pa), O.ParamArg.vmin_vmax(pa), O.ParamArg.multiple_of(pa),
    O.ParamArg.name(pa), O.ParamArg.addrspace(pa), O.ParamArg.device(pa), O.ParamArg.volatile(pa),
    O.ParamArg.image(pa), O.ParamArg.buffer(pa), O.ParamArg.bind_on_realize(pa), O.ParamArg.val(pa)}

def with_storage.arg.of(a: O.Arg, dt: S.Dt) -> O.Arg:
  match a:
    case O.AParam{pa}: O.AParam{with_storage.arg(pa, dt)}
    case _: a

# THE STORAGE ARM. No srcs: a PARAM/BUFFER/ALLOC carries its storage in `arg`,
# and the arm replaces `arg` alone. Factored out because it holds NO self-call,
# so it is legal above the recursion.
def with_storage.leaf(+ar: O.Arena, dt: S.Dt, +i: U32) -> O.Found:
  O.UOp.new(ar, O.Arena.op(ar, i), Nil{}, with_storage.arg.of(O.Arena.arg(ar, i), dt), O.Arena.tag(ar, i))

# `x.replace(src=(with_storage(x.src[0], dt),)+x.src[1:])` -- a new node whose
# src[0] is the recursion's answer and whose src[1:] is the OLD tail, copied.
#
# CONVENTION 8 IS THE WHOLE REASON THIS DEF EXISTS AS A SEPARATE ONE: the outer
# node is built on `O.Found.ar(inner)`, never on `ar`.
def with_storage.rebuild(+ar: O.Arena, dt: S.Dt, +i: U32, +inner: O.Found) -> O.Found:
  O.UOp.new(O.Found.ar(inner), O.Arena.op(ar, i),
    List.append(&2, U32, [O.Found.i(inner)], O.Arena.src_from(ar, i, 1)),
    O.Arena.arg(ar, i), O.Arena.tag(ar, i))

# THE ONE SELF-RECURSIVE DEF. Its self-call is on the SHRINKING `p`, which is
# the FIRST parameter, so the call is decreasing left to right.
def with_storage(fuel: Nat, +ar: O.Arena, +dt: S.Dt, +i: U32, store: Bool) -> O.Found:
  match fuel:
    case 0n: O.Found{ar, i}
    case 1n+p:
      match store:
        case True{}: with_storage.leaf(ar, dt, i)
        case False{}: with_storage.rebuild(ar, dt, i,
          with_storage(p, ar, dt, O.Arena.src0(ar, i), with_storage.is_store(O.Arena.op(ar, O.Arena.src0(ar, i)))))

def with_storage.at(+f: O.Found, dt: S.Dt) -> O.Found:
  with_storage(with_storage.fuel(f), O.Found.ar(f), dt, O.Found.i(f), with_storage.is_store(O.Arena.op(O.Found.ar(f), O.Found.i(f))))

# ===========================================================================
# `Estimates` -- __init__.py:15-61.
#
#     ops:sint = 0   # number of FLOPS used in the Kernel
#     lds:sint = 0   # bytes accessed in loads and stores
#     mem:dict[tuple[UOp, Ops], sint] = {}   # total bytes, counted ONCE
#
# `sint` is `UOp|int` and has NO Bend spelling, so the port carries the COUNT as
# a `U32`. That is not a shortcut: the ONLY caller is `do_estimates`
# (codegen/__init__.py:437) and it passes `lin.src` -- the LINEARIZED list -- on
# which there is no RANGE, no END, no BACKEDGE and no SPECIAL, so `mults` is 1
# at every step and the `mult_stack` never pushes. The symbolic branch of
# `mults` (`UOp.simplify` is `# TODO(p3) ops.py:513`; the `vmax` under
# `to_max_shape` is `# TODO(p3) ops.py:1886`) is unreachable from that call site,
# so counting the linear list needs none of it.
#
# THE `mem` DICT IS THE ONE PLACE THE PORT'S SHAPE DEPARTS FROM 1:1, and the
# departure is load-bearing rather than cosmetic. Python keys it by
# `(buffer, op)`, so a buffer that is both READ and WRITTEN carries TWO counts
# that `sum(mem.values())` adds. A `Data` record cannot key a `Map` by a pair --
# there is no hasher for a pair and no tuple key -- so the key is the buffer
# index alone, which is the SAME `U32.show` identity `Ctx` uses, and the op is
# DROPPED. `estimates` below therefore returns the sum over buffers, and a
# buffer read-then-written contributes ONE count where CPython contributes two.
# That is a real disagreement on a real kernel and it is stated rather than
# hidden. Splitting it needs a two-word key, which is a P3 change to the
# substrate's `Map`, not to this file.
# ===========================================================================

type Estimates is Data:
  Estimates{ops: U32, lds: U32, mem: U32}

def Estimates.of(o: U32, l: U32, m: U32) -> Estimates: Estimates{o, l, m}

def Estimates.ops(a: Estimates) -> U32:
  match a:
    case Estimates{ops, lds, mem}: ops

def Estimates.lds(a: Estimates) -> U32:
  match a:
    case Estimates{ops, lds, mem}: lds

def Estimates.mem(a: Estimates) -> U32:
  match a:
    case Estimates{ops, lds, mem}: mem


# `def __add__(self, o)` -- __init__.py:23. Three `U32.add`s; the method is
# exactly them.
def Estimates.add(+a: Estimates, +b: Estimates) -> Estimates:
  Estimates{U32.add(Estimates.ops(a), Estimates.ops(b)), U32.add(Estimates.lds(a), Estimates.lds(b)),
    U32.add(Estimates.mem(a), Estimates.mem(b))}

# `def simplify(self)` -- __init__.py:24: `Estimates(ssimplify(ops),
# ssimplify(lds), ssimplify(mem))`. `ssimplify` on a plain int is the IDENTITY,
# and the port's counter IS a plain int, so this returns its argument and says
# so. Reproducing a `simplify` that cannot simplify anything would be a lie about
# the substrate; returning the record is the honest answer and the gate pins it.
def Estimates.simplify(a: Estimates) -> Estimates: a

# `Estimates.from_uops` -- __init__.py:26-61, over the LINEARIZED list.
#
# FOUR of the six op arms survive the linearization and the other two do not:
#   LOAD  (non-REG)  -> lds += max_numel * itemsize * mults      [mults == 1]
#   STORE (non-REG)  -> lds += max_numel * itemsize * mults      [src[1] is void,
#                                                             so it is the BUFFER]
#   ALU             -> flops += (2 if MULACC else 1) * max_numel
#   LOAD/STORE      -> mem[(buf, op)] capped at buf.max_numel * itemsize
# and RANGE / END / BACKEDGE / SPECIAL -- the four `mults` arms -- never appear.
# `ignore_indexing` additionally removes the INDEX/SHRINK subtrees from `flops`,
# and that needs a MULTI-ROOT toposort, which `UOp.toposort` (one root) does not
# provide; the two INDEX arms of `from_uops` are therefore the `TODO(p3)` below
# and `ignore_indexing` is a NO-OP here, which is visible: a kernel with INDEX
# nodes over ALU nodes reports the ALU flops CPython would exclude.
#
# `is_alu` is `GroupOp.ALU`, which in ops.bend is a set of EIGHTEEN constructors.
# It is spelled as the match rather than a membership test because `GroupOp` is
# not a value here.
def is_alu(op: O.Op) -> Bool:
  match op:
    case O.OpsADD{}: True{}
    case O.OpsMUL{}: True{}
    case O.OpsSUB{}: True{}
    case O.OpsFDIV{}: True{}
    case O.OpsPOW{}: True{}
    case O.OpsSHR{}: True{}
    case O.OpsSHL{}: True{}
    case O.OpsCDIV{}: True{}
    case O.OpsMAX{}: True{}
    case O.OpsCMOD{}: True{}
    case O.OpsXOR{}: True{}
    case O.OpsCMPEQ{}: True{}
    case O.OpsCMPNE{}: True{}
    case O.OpsCMPLT{}: True{}
    case O.OpsOR{}: True{}
    case O.OpsAND{}: True{}
    case O.OpsTHREEFRY{}: True{}
    case O.OpsNEG{}: True{}
    case O.OpsEXP2{}: True{}
    case O.OpsLOG2{}: True{}
    case O.OpsSQRT{}: True{}
    case O.OpsRECIPROCAL{}: True{}
    case O.OpsTRUNC{}: True{}
    case O.OpsSIN{}: True{}
    case O.OpsFLOORDIV{}: True{}
    case O.OpsFLOORMOD{}: True{}
    case O.OpsMULACC{}: True{}
    case O.OpsWHERE{}: True{}
    case _: False{}

def is_mem(op: O.Op) -> Bool:
  match op:
    case O.OpsLOAD{}: True{}
    case O.OpsSTORE{}: True{}
    case _: False{}

# ===========================================================================
# `Renderer` -- __init__.py:63-87.
#
# The class carries FIFTEEN attributes, and the three that are TABLES Python
# fills from a `dict` literal are the reason this file cannot be a record
# without thought:
#
#   `type_map: dict[DType, str]`  -> `Map<&2, String>` keyed by the dtype's
#       NAME. Two `DType`s with one name are the same `dtypes` singleton in
#       Python, so the name IS the identity -- the same argument `Ctx` makes for
#       a UOp.
#   `code_for_op: dict[Ops, Callable]` -> a `U32` DEVICE TAG plus a `match`. A
#       callable is not representable, and a per-op dispatch is exactly what
#       `cstyle.bend`'s `code_for_op.of` is.
#   `extra_matcher: PatternMatcher|None` -> a `Bool` has-matcher, and the matcher
#       itself is `cstyle.bend`'s tables.
#
# `supported_dtypes` is the ONE method with no table:
#
#     return set(dtypes.all) - ({dtypes.double} if dtypes.long in EMULATED_DTYPES.tolist(dtypes) else set())
#
# `EMULATED_DTYPES` is `ContextVar("EMULATED_DTYPES", "")` and `tolist` of the
# empty string is `[]`, so `long in []` is False and `double` is KEPT: the base
# answer is `dtypes.all` VERBATIM. That is a row the gate pins, and it is why
# the emulated set is a PARAMETER rather than an assumption -- with `long` in it
# the base drops `double`, and the fixture that says so is one argument away.
# ===========================================================================

def is_named(d: S.Dt, nm: String) -> Bool:
  match d:
    case S.Dt{pri, bits, cls, s}: String.eq(s, nm)

def eq_dt(a: S.Dt, b: S.Dt) -> Bool: O.eq_dt(a, b)

def emu_has.go(emu: List<&2, S.Dt>, +d: S.Dt, ok: Bool) -> Bool:
  match emu:
    case Nil{}: ok
    case h <> t: emu_has.go(t, d, Bool.or(ok, eq_dt(h, d)))

def emu_has(emu: List<&2, S.Dt>, d: S.Dt) -> Bool: emu_has.go(emu, d, False{})

# `dtypes.long in EMULATED_DTYPES.tolist(dtypes)`, separated so the gate pins
# the ONE question the base asks on its own.
def emulated_long(emu: List<&2, S.Dt>) -> Bool: emu_has(emu, S.int64())

# `dtypes.all` -- dtype.py's `dtypes.all`, REBUILT HERE FROM `S.Dt`'s OWN
# CONSTRUCTORS rather than read from `dtype.bend`. That is a departure and the
# reason is measured, not stylistic: `./bin/bend tinybendygrad/dtype.bend
# --check-only` prints `SOME PROOFS FAIL -- 14 defs rely on unsafe or foreign
# code` (Dt.bf16, Dt.fp16, Dt.fp8_from, Dt.fp8_to, Dt.i64_trunc, the four
# i64 divide/mod helpers, float_to_bf16, float_to_fp16, float_to_fp8,
# fp8_to_float), so ANY importer of it fails its own gate -- `nn/optim.bend` is
# in the same state on this tree. `LAWS/spec.bend`, where `S.Dt`'s constructors
# live, is GREEN, and `dtypes.all` is six constructors and two appends:
#
#     all = floats + ints + [bool]
#     floats = fp8s + [half, bfloat16, single, double]
#     ints   = uints + sints
#
# so the honest move is to read it from the file that checks. The ORDER is
# dtype.py's own declaration order and the gate's `sd empty` row is CPython's
# `','.join(d.name for d in dtypes.all)` -- the same string, so a reordering or
# a drop here is a diff rather than a silent divergence. `dtype.bend` failing
# its own `--check-only` is a defect in that file and it is REPORTED, not fixed:
# it is not this unit's file.
def dtypes_u32() -> List<&2, S.Dt>: [S.uint8(), S.uint16(), S.uint32(), S.uint64()]

def dtypes_sint() -> List<&2, S.Dt>: [S.int8(), S.int16(), S.int32(), S.int64()]

def dtypes_int() -> List<&2, S.Dt>:
  List.append(&2, S.Dt, dtypes_u32(), dtypes_sint())

def dtypes_fp8() -> List<&2, S.Dt>:
  [S.fp8e4m3(), S.fp8e5m2(), S.fp8e4m3fnuz(), S.fp8e5m2fnuz()]

def dtypes_float() -> List<&2, S.Dt>:
  List.append(&2, S.Dt, dtypes_fp8(), [S.half(), S.bfloat16(), S.single(), S.double()])

def dtypes_all() -> List<&2, S.Dt>:
  List.append(&2, S.Dt, List.append(&2, S.Dt, dtypes_float(), dtypes_int()), [S.boolean()])

# `{dtypes.double} if dtypes.long in EMULATED_DTYPES.tolist(dtypes) else set()` --
# the ONE conditional in the base `supported_dtypes`, and it is a conjunction of
# TWO independent questions: is `long` emulated, and is this dtype `double`. A
# reader that folded them into one test would drop a dtype other than `double`,
# and `sd emu long` is the row that would show it.
def emu_drop(emu: List<&2, S.Dt>, d: S.Dt) -> Bool:
  Bool.and(emulated_long(emu), is_named(d, "double"))

def supported_dtypes.go(+emu: List<&2, S.Dt>, ds: List<&2, S.Dt>, +acc: List<&2, S.Dt>) -> List<&2, S.Dt>:
  match ds:
    case Nil{}: acc
    case +h <> t: supported_dtypes.go(emu, t, Bool.pick(List<&2, S.Dt>, emu_drop(emu, h), acc, List.append(&2, S.Dt, acc, [h])))

# `set(dtypes.all) - (...)`. The LIST order is `dtypes.all`'s own, which is the
# dtype.py declaration order and the SAME order CPython's `dtypes.all` has --
# unlike the `set` this function returns, which has none. That is why the gate
# can compare a JOINED STRING against CPython's joined string instead of
# comparing two unordered sets, and why a dropped dtype is a diff.
def supported_dtypes(emu: List<&2, S.Dt>) -> List<&2, S.Dt>: supported_dtypes.go(emu, dtypes_all(), Nil{})

# ===========================================================================
# WHAT IS NOT PORTED, in upstream order, and why. None of these is a Bend wall;
# four are DEVICE FFI, one is the fold's deferred SHRINK and one is a substrate
# gap this file cannot close alone.
#
# * `with_storage` (:11) -- PORTED. Both arms, the fuel, and the arena rebuild.
#   The gate's three rows are CPython's own `with_storage` answers.
# * `Estimates.from_uops` (:26) -- PORTED IN PART. The `mem` DICT keys by
#   `(buffer, op)` and the port keys by buffer alone, so a buffer both read and
#   written contributes one count where CPython contributes two. The `mults`
#   arms are the identity, which is exact for the only call site (a linearized
#   list) and wrong for an unlinearized one -- and `ignore_indexing` is a no-op
#   because the multi-root toposort its `excluded` set needs is not in the
#   substrate. `TODO(p3) __init__.py:26`.
# * `Estimates.__add__` / `.simplify` (:23, :24) -- PORTED, with `simplify` the
#   identity and the reason said out loud.
# * `Renderer.__init__` / `__reduce__` (:81, :82) -- the target is a
#   `helpers.Target` dataclass, `# TODO(p3)` in the port (render.bend records the
#   drop at ops.bend:801). So the renderer record carries the THREE FIELDS every
#   `supported_dtypes` override in `cstyle.py` actually reads -- `arch`, `device`,
#   `interface` -- as `String`s, which is measured: every override in that file
#   is `self.target.arch.startswith(..)` or `int(self.target.arch[3:])`.
#   `self.compiler` is a `Compiler` object: P6.
# * `Renderer.render` / `Renderer.asm` (:83, :84) -- both raise
#   `NotImplementedError`, and Bend has no exceptions. They are the two `Bool`s
#   in the record a caller tests before dispatching, and every subclass
#   OVERRIDES the reader rather than setting a flag, so the flag is the base's
#   answer and nothing else can be true of it. `TODO(p3) __init__.py:83`, `:84`.
# * `Renderer.extra_matcher` (:76) -- a `PatternMatcher` of UOps, which is
#   `cstyle.bend`'s tables (`create_non_native_float_pats`,
#   `pm_manual_bf16_cast`, and each device's own). A `Bool` has-matcher here.
# * `Renderer.code_for_op` (:77) -- `dict[Ops, Callable]`. The tag plus the
#   `match` is `cstyle.bend`'s `code_for_op.of`. `TODO(p3) __init__.py:77`.
# * `Renderer.tensor_cores` (:75) -- `list[TensorCore]` from `renderer/tc.py`,
#   which is not this unit's file and has no port. `TODO(p3) __init__.py:75`.
# * `Renderer.supported_dtypes` (:85) -- PORTED, as above.
#
# TODO(p3) __init__.py:11  with_storage     (done; kept for the line map)
# TODO(p3) __init__.py:26  from_uops        (the (buf, op) mem key; ignore_indexing)
# TODO(p3) __init__.py:75  tensor_cores     (renderer/tc.py is not this unit)
# TODO(p3) __init__.py:77  code_for_op      (a dict of Callables; see cstyle.bend)
# TODO(p3) __init__.py:81  __init__         (Target, Compiler)
# TODO(p3) __init__.py:83  render           (NotImplementedError -> a has-render flag)
# TODO(p3) __init__.py:84  asm              (NotImplementedError -> a has-asm flag)
#
# ===========================================================================
# THE GATE. Every row is diffed against CPython on this `tinygrad/` tree with
# `.venv/bin/python -c "..."`, and the `py=` text IS the oracle -- printed next
# to the answer, never compared as a boolean, because the two things this file
# can most easily get wrong are a JOINED NAME LIST and a joined string, and both
# hide a dropped element inside a `True`.
#
# `sd_*` IS A JOIN, NOT A SET. CPython's `supported_dtypes` returns a `set` with
# no order, so the oracle is `sorted(...)` on the Python side and the port's own
# `dtypes.all` order here, each printed. A dropped dtype moves the string.
# `sd emu long` is the SAME row with one argument changed, and it is the only row
# that can see the `ContextVar` default being an ASSUMPTION rather than a fact:
# `sd empty` pins that `double` is KEPT, `sd emu long` pins that it is DROPPED,
# and a `supported_dtypes` that ignored its parameter would pass the first and
# fail the second.
#
# `ws_*` ARE CPython'S OWN `with_storage` ANSWERS on the fixtures below, so the
# recursion is checked against the reference and not against itself. `ws idx.src0`
# is the row convention 8 exists for: it is the ONLY row whose src0 is a
# REBUILT node, so it is the only row that sees a rebuild built on the wrong
# arena.
# ===========================================================================

def pa_g(slot: U32, dt: S.Dt, size: U32) -> O.ParamArg:
  O.ParamArg{slot, dt, Some{size}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, False{}, None{}}

def g_buf() -> O.Found:
  O.UOp.new(O.Arena.empty(), O.OpsPARAM{}, Nil{}, O.AParam{pa_g(0, S.int32(), 4)}, O.TNone{})

def g_alloc() -> O.Found:
  O.UOp.new(O.Arena.empty(), O.OpsALLOC{}, Nil{}, O.AParam{pa_g(0, S.int32(), 4)}, O.TNone{})

def g_idx(+b: O.Found) -> O.Found:
  O.UOp.new(O.Found.ar(b), O.OpsINDEX{}, [O.Found.i(b)], O.ANone{}, O.TNone{})

# `x.arg.dtype` of the answer -- read through the record, so it is `float`
# exactly when the rewrite reached the storage node.
def arg_dt.pa.of(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, s}: s

def arg_dt.pa(pa: O.ParamArg) -> String: arg_dt.pa.of(O.ParamArg.dtype(pa))

# `repr(x.arg.dtype)` for a PARAM-shaped arg and `repr(x.arg)` for anything else.
# The second answer is CPython's `repr(None)`, spelled "None" rather than the
# port's usual "?" marker, and deliberately: the row diffs a STRING, and a row
# whose two sides can never be equal teaches nothing. `Ops.INDEX`'s arg really
# is `ANone{}` here and really is `None` in Python, so "None" is the honest
# answer and not a fudge.
def arg_dt.of(a: O.Arg) -> String:
  match a:
    case O.AParam{pa}: arg_dt.pa(pa)
    case _: "None"

def arg_dt(ar: O.Arena, i: U32) -> String: arg_dt.of(O.Arena.arg(ar, i))

def src0_dt.of(ss: List<&2, U32>, ar: O.Arena) -> String:
  match ss:
    case Nil{}: "none"
    case h <> _: arg_dt(ar, h)

def src0_dt(+f: O.Found) -> String: src0_dt.of(O.Arena.srcs(O.Found.ar(f), O.Found.i(f)), O.Found.ar(f))

def ws_row(nm: String, py: String, +f: O.Found) -> IO(Unit):
  IO.print(String.concat([nm, " = [", arg_dt(O.Found.ar(f), O.Found.i(f)), "]   py=[", py, "]"]))

def ws_src_row(nm: String, py: String, +f: O.Found) -> IO(Unit):
  IO.print(String.concat([nm, " = [", src0_dt(f), "]   py=[", py, "]"]))

# THE JOINED NAME LIST. `dtypes.all`'s own order here, `sorted` on Python's --
# so a dropped dtype and a MISORDERED dtype are both visible.
def sd_name(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, s}: s

def sd_names.go(ds: List<&2, S.Dt>, acc: List<&2, String>) -> List<&2, String>:
  List.foldl(~&2, ~S.Dt, ~List<&2, String>, (a: List<&2, String>) => (h: S.Dt) => List.append(&2, String, a, [sd_name(h)]), ds, acc)

def sd_names_of(ds: List<&2, S.Dt>) -> List<&2, String>: sd_names.go(ds, Nil{})

def sd_names(emu: List<&2, S.Dt>) -> List<&2, String>: sd_names_of(supported_dtypes(emu))

# ONE LINE, AND THAT IS THE POINT. This row printed its answer and its `py=` on
# TWO lines so the `py=` would line up under a 200-character dtype list, and a
# two-line row is INVISIBLE to a row-keyed diff: the mutation harness keys on
# ` = [` followed by `]   py=[`, so a row whose oracle is on the next line is not
# a row at all. MEASURED: `I3 supported_dtypes ignores its emu argument` reported
# "NO ROW MOVED" for four runs while the file was visibly wrong, for exactly this
# reason. The alignment is worth less than being checkable.
def sd_row(nm: String, py: String, emu: List<&2, S.Dt>) -> IO(Unit):
  IO.print(String.concat([nm, " = [", String.join(sd_names(emu), ","), "]   py=[", py, "]"]))

# `Estimates.__repr__` is a dataclass repr, so the oracle is CPython's own
# `Estimates(1,2,3)+Estimates(4,5,6)` printed -- the SAME three-field spelling
# the port emits, and a dropped field shows as a shorter string.
def est_str(+e: Estimates) -> String:
  String.concat(["Estimates(ops=", U32.show(Estimates.ops(e)), ", lds=", U32.show(Estimates.lds(e)),
    ", mem=", U32.show(Estimates.mem(e)), ")"])

def est_row(nm: String, py: String, e: Estimates) -> IO(Unit):
  IO.print(String.concat([nm, " = [", est_str(e), "]   py=[", py, "]"]))

def all_row(nm: String, py: String) -> IO(Unit):
  IO.print(String.concat([nm, " = [", String.join(sd_names_of(dtypes_all()), ","), "]   py=[", py, "]"]))

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- sd_row("sd empty     ", "float8_e4m3,float8_e5m2,float8_e4m3fnuz,float8_e5m2fnuz,half,__bf16,float,double,unsigned char,unsigned short,unsigned int,unsigned long,signed char,short,int,long,bool", Nil{})
    _ : Unit <- sd_row("sd emu long  ", "float8_e4m3,float8_e5m2,float8_e4m3fnuz,float8_e5m2fnuz,half,__bf16,float,unsigned char,unsigned short,unsigned int,unsigned long,signed char,short,int,long,bool", [S.int64()])
    # `dtypes.all` ITSELF, joined in dtype.py's declaration order. This is the row
    # `dtypes_all` above is diffed against, and it is why that list is read from
    # `spec.bend` rather than from `dtype.bend`: the two are claimed to hold the
    # same seventeen dtypes in the same order, and a drop or a swap in either is
    # a visible string difference.
    _ : Unit <- all_row("dtypes.all    ", "float8_e4m3,float8_e5m2,float8_e4m3fnuz,float8_e5m2fnuz,half,__bf16,float,double,unsigned char,unsigned short,unsigned int,unsigned long,signed char,short,int,long,bool")
    _ : Unit <- IO.print("emu_long []      = [" ++ Bool.show(emulated_long(Nil{})) ++ "]   py=False")
    _ : Unit <- IO.print("emu_long [long]  = [" ++ Bool.show(emulated_long([S.int64()])) ++ "]   py=True")
    _ : Unit <- IO.print("is_named double  = [" ++ Bool.show(is_named(S.double(), "double")) ++ "]   py=True")
    _ : Unit <- IO.print("is_named long!=  = [" ++ Bool.show(is_named(S.int64(), "double")) ++ "]   py=False")
    _ : Unit <- IO.print("is_alu ADD       = [" ++ Bool.show(is_alu(O.OpsADD{})) ++ "]   py=True")
    _ : Unit <- IO.print("is_alu SINK      = [" ++ Bool.show(is_alu(O.OpsSINK{})) ++ "]   py=False")
    _ : Unit <- IO.print("is_mem LOAD      = [" ++ Bool.show(is_mem(O.OpsLOAD{})) ++ "]   py=True")
    _ : Unit <- IO.print("is_mem STORE     = [" ++ Bool.show(is_mem(O.OpsSTORE{})) ++ "]   py=True")
    _ : Unit <- IO.print("is_mem ADD       = [" ++ Bool.show(is_mem(O.OpsADD{})) ++ "]   py=False")
    _ : Unit <- est_row("est add    ", "Estimates(ops=5, lds=7, mem=9)", Estimates.add(Estimates.of(1, 2, 3), Estimates.of(4, 5, 6)))
    _ : Unit <- est_row("est simplfy ", "Estimates(ops=3, lds=4, mem=5)", Estimates.simplify(Estimates.of(3, 4, 5)))
    _ : Unit <- ws_row("ws buffer  ", "float", with_storage.at(g_buf(), S.single()))
    _ : Unit <- ws_row("ws index   ", "None", with_storage.at(g_idx(g_buf()), S.single()))
    _ : Unit <- ws_src_row("ws idx.src0", "float", with_storage.at(g_idx(g_buf()), S.single()))
    _ : Unit <- ws_row("ws alloc   ", "float", with_storage.at(g_alloc(), S.single()))
    IO.print("")
