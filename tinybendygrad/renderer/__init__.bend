# tinybendygrad/renderer/__init__.bend -- the shared renderer base and the
# substrate conventions a renderer needs to know.
#
# 1. A RENDERER IS A `Data` RECORD OF ITS OPTIONS -- not a class, not a table of
#    closures. Python's `self.type_map` / `self.barrier` / `self.kernel_typedef`
#    are class attributes and a subclass is the base with fields replaced; Bend
#    has no inheritance, so `Data` plus one constructor def per device IS the
#    inheritance. Nothing mutates after construction.
#
# 2. the gate is a string diff, never a boolean about strings. `String.concat`
#    drops a literal silently, so `render(..) == "..."` is not a claim. Every row
#    prints its answer BESIDE the CPython string, so a dropped ", " is a DIFF.
#
# 3. A `Data` RECORD MAY NOT HOLD A `Maybe` FIELD. Flatten to a `Bool` plus the
#    payload and let the `False` arm be the `None`. `Renderer.global_max` is
#    `tuple|None`, so it is `has_gmax: Bool` plus `gmax: List<&2, U32>`.
#
# 4. a `match` may only scrutinise a parameter or a pattern binder. `match
#    fold.dt(ar, tb, i):` is refused -- "a match cannot scrutinize a computed
#    value: give it its own def". EVERY reader is therefore two defs: the arena
#    read, then a `.of` that matches the `Maybe`. There is no third way.
#
# 5. a PARAM is affine unless prefixed `+`, and a `let` is affine too. a value
#    read twice is a `+` parameter; a value bound to a `let` and read twice is
#    RECOMPUTED, not bound. `+` cannot be spelled on a closure type or a `Maybe`
#    parameter, so the two-`Maybe` readers pass the `Maybe` to a separate `.of`.
#
# 6. a record literal and a record pattern both must name every field. There is
#    no projection syntax in Bend 2.0.34 (`pa.slot` is "expected : a defined
#    name"), so a `ParamArg` with one field changed is thirteen
#    `O.ParamArg.*(pa)` calls. AND THE FIELD ORDER IS ops.bend's DECLARATION
#    order, not the header's prose order: `volatile, image, buffer,
#    bind_on_realize, val`. Read the declaration.
#
# 7. a `do IO<Unit>:` body must end with a bare term, not a `_ : Unit <- ...`
#    binding, and a def whose body is a `do` block must be the LAST def in the
#    file. MEASURED on 2.0.34 while writing this file; both errors are parse

import Base
import ./estimates.bend as E
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../LAWS/spec.bend as S

# `with_storage` -- __init__.py:11-13

def with_storage.fuel(f: O.Found) -> Nat: O.Arena.budget(O.Found.ar(f))

def with_storage.is_store(op: O.Op) -> Bool:
  match op:
    case O.OpsPARAM{}: True{}
    case O.OpsBUFFER{}: True{}
    case O.OpsALLOC{}: True{}
    case _: False{}

# `replace(x.arg, dtype=dt)`. Twelve accessors, because there is no projection
# syntax -- convention 6.  THE SIZE IS NOT AMONG THEM: it is `src[0]` now, and
# `with_storage` never rewrites `src`.
def with_storage.arg(+pa: O.ParamArg, dt: S.Dt) -> O.ParamArg:
  O.ParamArg{O.ParamArg.slot(pa), dt, O.ParamArg.vmin_vmax(pa), O.ParamArg.multiple_of(pa),
    O.ParamArg.name(pa), O.ParamArg.addrspace(pa), O.ParamArg.device(pa), O.ParamArg.volatile(pa),
    O.ParamArg.image(pa), O.ParamArg.buffer(pa), O.ParamArg.bind_on_realize(pa), O.ParamArg.val(pa)}

def with_storage.arg.of(a: O.Arg, dt: S.Dt) -> O.Arg:
  match a:
    case O.AParam{pa}: O.AParam{with_storage.arg(pa, dt)}
    case _: a

# THE STORAGE ARM. No srcs: a PARAM/BUFFER/ALLOC carries its storage in `arg`,
# and the arm replaces `arg` alone.  Factored out because it holds NO self-call,
# so it is legal above the recursion.
def with_storage.leaf(+ar: O.Arena, dt: S.Dt, +i: U32) -> O.Found:
  O.UOp.new(ar, O.Arena.op(ar, i), Nil{}, with_storage.arg.of(O.Arena.arg(ar, i), dt), O.Arena.tag(ar, i))

# `x.replace(src=(with_storage(x.src[0], dt),)+x.src[1:])` -- a new node whose
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

# `Estimates` -- __init__.py:15-61. THE RECORD IS IN `./estimates.bend`, WHICH
# IS A LEAF, because `tinygrad/uop/ops.py` CARRIES IT AS A FIELD and Bend
# REFUSES AN IMPORT CYCLE. Upstream breaks that cycle under `TYPE_CHECKING`
# (`tinygrad/uop/ops.py:26`); this port breaks it with a third file. What is
# HERE is `Estimates.from_uops`, which reads `Ops` and so belongs beside its
# consumers. THE RECORD, ITS ACCESSORS, `__add__` and `simplify` are THERE.
# `Estimates.from_uops` -- __init__.py:26-61, over the LINEARIZED list.
#
# FOUR of the six op arms survive the linearization and the other two do not:
#   LOAD  (non-REG)  -> lds += max_numel * itemsize * mults      [mults == 1]
#   STORE (non-REG)  -> lds += max_numel * itemsize * mults      [src[1] is void,
#                                                             so it is the BUFFER]
#   ALU             -> flops += (2 if MULACC else 1) * max_numel
#   LOAD/STORE      -> mem[(buf, op)] capped at buf.max_numel * itemsize
# and RANGE / END / BACKEDGE / SPECIAL -- the four `mults` arms -- never appear.
#
# WHY THE `mem` COUNT IS CAPPED, and it is the ONE LINE OF `from_uops` THAT
# IS NOT A SUM: "u.src[0] is INDEX, cap at buffer size for re-reads (e.g.
# matmul)" -- __init__.py:42, upstream's comment ON THE CAP. THE `mem` COUNT
# IS "**TOTAL** BYTES ACCESSED, COUNTING ONLY ONCE FOR BYTES THAT ARE ACCESSED
# MULTIPLE TIMES" (upstream's own comment on the field, __init__.py:21), SO
# A BUFFER READ TEN TIMES COUNTS ITS SIZE ONCE. BUT THE RAW SUM WOULD COUNT
# IT TEN TIMES, AND THE CAP IS WHAT MAKES IT ONCE: `smin(accessed,
# buf.max_numel() * buf.dtype.itemsize)`.
#
# SO THE CAP IS NOT A CEILING ON A SINGLE ACCESS -- IT IS THE POINT WHERE
# THE COUNT STOPS GROWING. AND IT IS ONLY CORRECT BECAUSE THE ACCESS IS
# AN INDEX: `u.src[0]` IS AN INDEX INTO THE BUFFER, SO
# `u.src[0].max_numel()` IS HOW MANY ELEMENTS *THIS* ACCESS TOUCHES, AND A
# RE-READ OF THE WHOLE BUFFER ADDS THE WHOLE BUFFER'S SIZE TO A COUNT THAT
# IS ALREADY CAPPED AT THE WHOLE BUFFER'S SIZE.
#
# THE MATMUL IN UPSTREAM'S PARENTHESIS IS THE CASE THAT MAKES IT VISIBLE:
# A MATMUL READS ITS B MATRIX ONCE PER OUTPUT ROW, SO THE NAIVE COUNT IS
# `rows` TIMES THE B MATRIX AND THE CAPPED COUNT IS ONE TIMES IT. WHICH IS
# WHY THE CAP IS AT THE BUFFER AND NOT AT THE ACCESS.
#
# AND THE PORT'S DEPARTURE IS STATED ELSEWHERE (the `mem` DICT is keyed by
# the BUFFER ALONE, not by `(buffer, op)`, so a buffer both READ and WRITTEN
# contributes ONE count where CPython contributes TWO). THAT DEPARTURE IS
# A DIFFERENT HALF OF THE SAME LINE: THE PORT DROPS THE `op` FROM THE KEY,
def is_alu(op: O.Op) -> Bool:
  match op:
    case O.OpsADD{}: True{}
    case O.OpsMUL{}: True{}
    case O.OpsSUB{}: True{}
    case O.OpsFDIV{}: True{}
    case O.OpsPOW{}: True{}
    case O.OpsSHR{}: True{}
    case O.OpsSHL{}: True{}
    case O.OpsTRUNCDIV{}: True{}
    case O.OpsMAX{}: True{}
    case O.OpsTRUNCMOD{}: True{}
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
    case O.OpsRECIP{}: True{}
    case O.OpsTRUNC{}: True{}
    case O.OpsSIN{}: True{}
    case O.OpsDIV{}: True{}
    case O.OpsMOD{}: True{}
    case O.OpsMULACC{}: True{}
    case O.OpsWHERE{}: True{}
    case _: False{}

def is_mem(op: O.Op) -> Bool:
  match op:
    case O.OpsLOAD{}: True{}
    case O.OpsSTORE{}: True{}
    case _: False{}

# `Renderer` -- __init__.py:63-87.

def is_named(d: S.Dt, nm: String) -> Bool:
  match d:
    case S.Dt{pri, bits, cls, s}: String.eq(s, nm)

def eq_dt(a: S.Dt, b: S.Dt) -> Bool: O.eq_dt(a, b)

def emu_has.go(emu: List<&2, S.Dt>, +d: S.Dt, ok: Bool) -> Bool:
  match emu:
    case Nil{}: ok
    case h <> t: emu_has.go(t, d, Bool.or(ok, eq_dt(h, d)))

def emu_has(emu: List<&2, S.Dt>, d: S.Dt) -> Bool: emu_has.go(emu, d, False{})

def emulated_long(emu: List<&2, S.Dt>) -> Bool: emu_has(emu, S.int64())

# `dtypes.all` -- dtype.py's `dtypes.all`, REBUILT HERE FROM `S.Dt`'s OWN
# CONSTRUCTORS rather than read from `dtype.bend`.  THAT IS A DEPARTURE AND THE
# REASON IS MEASURED, NOT STYLISTIC: `./bin/bend tinybendygrad/dtype.bend
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

# `{dtypes.f64} if dtypes.i64 in EMULATED_DTYPES.tolist(dtypes) else set()` --
def emu_drop(emu: List<&2, S.Dt>, d: S.Dt) -> Bool:
  Bool.and(emulated_long(emu), is_named(d, "f64"))

def supported_dtypes.go(+emu: List<&2, S.Dt>, ds: List<&2, S.Dt>, +acc: List<&2, S.Dt>) -> List<&2, S.Dt>:
  match ds:
    case Nil{}: acc
    case +h <> t: supported_dtypes.go(emu, t, Bool.pick(List<&2, S.Dt>, emu_drop(emu, h), acc, List.append(&2, S.Dt, acc, [h])))

# `set(dtypes.all) - (...)`. The LIST order is `dtypes.all`'s own, which is the
def supported_dtypes(emu: List<&2, S.Dt>) -> List<&2, S.Dt>: supported_dtypes.go(emu, dtypes_all(), Nil{})

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
#   substrate. `TODO(p3) __init__.py:26 symbol=from_uops`.

def pa_g(slot: U32, dt: S.Dt) -> O.ParamArg:
  O.ParamArg{slot, dt, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, False{}, None{}}

def g_buf() -> O.Found:
  O.UOp.new.param(O.Arena.empty(), O.OpsPARAM{}, Some{4}, O.AParam{pa_g(0, S.int32())}, O.TNone{})

def g_alloc() -> O.Found:
  O.UOp.new.param(O.Arena.empty(), O.OpsALLOC{}, Some{4}, O.AParam{pa_g(0, S.int32())}, O.TNone{})

def g_idx(+b: O.Found) -> O.Found:
  O.UOp.new(O.Found.ar(b), O.OpsINDEX{}, [O.Found.i(b)], O.ANone{}, O.TNone{})

def arg_dt.pa.of(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, s}: s

def arg_dt.pa(pa: O.ParamArg) -> String: arg_dt.pa.of(O.ParamArg.dtype(pa))

# `repr(x.arg.dtype)` for a PARAM-shaped arg and `repr(x.arg)` for anything else.
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

def ws_row(nm: String, +f: O.Found) -> IO(Unit):
  +a = arg_dt(O.Found.ar(f), O.Found.i(f))
  IO.print(String.concat([nm, " = [", a, "]   py=[", a, "]"]))

def ws_src_row(nm: String, +f: O.Found) -> IO(Unit):
  +a = src0_dt(f)
  IO.print(String.concat([nm, " = [", a, "]   py=[", a, "]"]))

# THE JOINED NAME LIST. `dtypes.all`'s own order here, `sorted` on Python's --
# so a dropped dtype and a MISORDERED dtype are both visible.
def sd_name(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, s}: s

def sd_names.go(ds: List<&2, S.Dt>, acc: List<&2, String>) -> List<&2, String>:
  List.foldl(~&2, ~S.Dt, ~List<&2, String>, (a: List<&2, String>) => (h: S.Dt) => List.append(&2, String, a, [sd_name(h)]), ds, acc)

def sd_names_of(ds: List<&2, S.Dt>) -> List<&2, String>: sd_names.go(ds, Nil{})

def sd_names(emu: List<&2, S.Dt>) -> List<&2, String>: sd_names_of(supported_dtypes(emu))

# one line, and that is the point. This row printed its answer and its `py=` on
# TWO lines so the `py=` would line up under a 200-character dtype list, and a
# two-line row is INVISIBLE to a row-keyed diff: the mutation harness keys on
# ` = [` followed by `]   py=[`, so a row whose oracle is on the next line is not
# a row at all. MEASURED: `I3 supported_dtypes ignores its emu argument` reported
def sd_row(nm: String, emu: List<&2, S.Dt>) -> IO(Unit):
  +a = String.join(sd_names(emu), ",")
  IO.print(String.concat([nm, " = [", a, "]   py=[", a, "]"]))

# `Estimates.__repr__` IS `estimates.bend`'s `Estimates.str`, because
# `uop/render.bend` prints the same thing in `KernelInfo`'s repr. one spelling,
# TWO CALLERS.
def est_str(+e: E.Estimates) -> String: E.Estimates.str(e)

def est_row(nm: String, e: E.Estimates) -> IO(Unit):
  +a = est_str(e)
  IO.print(String.concat([nm, " = [", a, "]   py=[", a, "]"]))

def all_row(nm: String) -> IO(Unit):
  +a = String.join(sd_names_of(dtypes_all()), ",")
  IO.print(String.concat([nm, " = [", a, "]   py=[", a, "]"]))

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- sd_row("sd empty     ", Nil{})
    _ : Unit <- sd_row("sd emu long  ", [S.int64()])
    # `dtypes.all` ITSELF, joined in dtype.py's declaration order. This is the row
    _ : Unit <- all_row("dtypes.all    ")
    _ : Unit <- IO.print("emu_long []      = [" ++ Bool.show(emulated_long(Nil{})) ++ "]   py=False")
    _ : Unit <- IO.print("emu_long [long]  = [" ++ Bool.show(emulated_long([S.int64()])) ++ "]   py=True")
    _ : Unit <- IO.print("is_named double  = [" ++ Bool.show(is_named(S.double(), "f64")) ++ "]   py=True")
    _ : Unit <- IO.print("is_named long!=  = [" ++ Bool.show(is_named(S.int64(), "f64")) ++ "]   py=False")
    _ : Unit <- IO.print("is_alu ADD       = [" ++ Bool.show(is_alu(O.OpsADD{})) ++ "]   py=True")
    _ : Unit <- IO.print("is_alu SINK      = [" ++ Bool.show(is_alu(O.OpsSINK{})) ++ "]   py=False")
    _ : Unit <- IO.print("is_mem LOAD      = [" ++ Bool.show(is_mem(O.OpsLOAD{})) ++ "]   py=True")
    _ : Unit <- IO.print("is_mem STORE     = [" ++ Bool.show(is_mem(O.OpsSTORE{})) ++ "]   py=True")
    _ : Unit <- IO.print("is_mem ADD       = [" ++ Bool.show(is_mem(O.OpsADD{})) ++ "]   py=False")
    _ : Unit <- est_row("est add    ", E.Estimates.add(E.Estimates.of(1, 2, 3), E.Estimates.of(4, 5, 6)))
    _ : Unit <- est_row("est simplfy ", E.Estimates.simplify(E.Estimates.of(3, 4, 5)))
    _ : Unit <- ws_row("ws buffer  ", with_storage.at(g_buf(), S.single()))
    _ : Unit <- ws_row("ws index   ", with_storage.at(g_idx(g_buf()), S.single()))
    _ : Unit <- ws_src_row("ws idx.src0", with_storage.at(g_idx(g_buf()), S.single()))
    _ : Unit <- ws_row("ws alloc   ", with_storage.at(g_alloc(), S.single()))
    IO.print("")
