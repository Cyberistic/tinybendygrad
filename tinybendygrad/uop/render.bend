# render.bend -- tinygrad/uop/render.py.
# the first string-building unit in the port. Everything ported so far was data:

# WHAT base.bend HAS, MEASURED 2026-09-30 against bend 2.0.34

#       `renderer`'s CAST arm, `str(x.dtype)[7:]` (render.py:102), which strips
# `tinygrad/uop/spec.py:41` now PRINTS `render_uir(lst)` under `DEBUG >= 3` instead of
# EXECUTING a rendered string. `render_uir` is `tinygrad/uop/render.py:65
# (tinygrad/uop/ops.py:1147 symbol=render_uir). So there is NO upstream round trip to port, and
# DEPENDENCIES. `render.py:3-4` imports NINE names -- eight from `uop.ops` and
#                             consumer's identity (`render.py:163`:
# so all four were open until now. Everything below is MEASURED, and every
# `# TODO(p3) render.py:102  renderer` -- not ported -- so the arm has no def in this file.
# THE WORKING TREE IS A BROKEN HYBRID, and every measurement above had to be
# `UOp.range(4, AxisType.WEAK, 0)`, which is NEITHER end's answer. MEASURED:

import Base
import ./ops.bend as O
import ./f32_repr.bend as FR
import ./fold.bend as F
import ./../helpers.bend as H
import ./../LAWS/spec.bend as S
import ./../renderer/estimates.bend as E

def sint_show.half(x: U32) -> Bool: U32.is_ge(x, 2147483648)

def sint_show.pick(neg: Bool, x: U32) -> String:
  match neg:
    case True{}: String.concat(["-", U32.show(U32.sub(0, x))])
    case False{}: U32.show(x)

def sint_show(+x: U32) -> String: sint_show.pick(sint_show.half(x), x)

# kernel carries it. MEASURED, `exp32` on the Metal lane rendered `1.442695f` where CPython

def f32_repr(+x: F32) -> String: FR.repr(x)

def sint_i64.of(fits: Bool, +x: H.I64) -> String:
  Bool.pick(String, fits, sint_show(H.lo32(x)), H.i64_show(H.hi32(x), H.lo32(x)))

def i64_fits_i32(+x: H.I64) -> Bool:
  U32.is_eq(H.hi32(x), H.match_hi(H.i32_is_neg(H.lo32(x))))

def sint_i64(+x: H.I64) -> String:
  sint_i64.of(i64_fits_i32(x), x)

# `ConstFloat.__repr__` / `ConstFloat.__str__` are both `float.__repr__(self)`, and
# `InvalidType.__repr__` is "Invalid".
def const_repr.cfloat(+f: F32) -> String:
  String.concat(["ConstFloat(", f32_repr(f), ")"])

def const_repr(c: O.Const) -> String:
  match c:
    case O.CBool{b}: Bool.show(b)
    case O.CInt{i}: sint_i64(i)
    case O.CFloat{f}: const_repr.cfloat(f)
    case O.CInvalid{}: "Invalid"

def dt_attr(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

def dt_repr(d: S.Dt) -> String:
  String.append("dtypes.", dt_attr(d))

# `AddrSpace.__repr__` -- `f"{cls.__name__}.{self.name}"`, and `__str__` is `repr(self)`. So
# the `addrspace` column of a ParamArg prints qualified.
def addr_name(a: S.Addr) -> String:
  match a:
    case S.AGlobal{}: "GLOBAL"
    case S.ALocal{}: "LOCAL"
    case S.AReg{}: "REG"
    case S.Aalu{}: "ALU"

def addr_repr(a: S.Addr) -> String:
  String.concat(["AddrSpace.", addr_name(a)])


def dev_names() -> List<&2, String>:
  ["CPU", "GPU", "METAL", "CUDA", "HIP", "CLANG", "LLVM", "PYTHON", "NULL", "DISK"]

def dev_name.tag(t: U32) -> String:
  Maybe.default(&2, String, List.get(&2, String, dev_names(), U32.to_nat(t)), "?")

def dev_repr.tags(tags: List<&2, U32>) -> List<&2, String>:
  match tags:
    case Nil{}: Nil{}
    case t <> r: String.concat(["'", dev_name.tag(t), "'"]) <> dev_repr.tags(r)

def dev_repr.tuple(tags: List<&2, U32>) -> String:
  String.concat(["(", String.join(dev_repr.tags(tags), ", "), ")"])

def dev_repr(d: S.Dev) -> String:
  match d:
    case S.D1{tag}: String.concat(["'", dev_name.tag(tag), "'"])
    case S.Dn{tags}: dev_repr.tuple(tags)

# `ParamArg.__repr__` -- ops.py:40-48. A dataclass with a hand-written repr:

def comma(ok: Bool, s: String) -> String:
  match ok:
    case True{}: String.concat([", ", s])
    case False{}: ""

# MEASURED, and it is the reason the fields are read through ops.bend's
def pa_size(m: Maybe<&2, U32>) -> String:
  match m:
    case Some{v}: String.concat([", ", U32.show(v)])
    case None{}: ""

def pa_vmin_vmax(r: O.PyRange) -> String:
  match r:
    case O.PyRange{lo, hi}: String.concat(["vmin_vmax=(", sint_i64(lo), ", ", sint_i64(hi), ")"])

def pa_vmin_vmax.of1(m: Maybe<&2, O.PyRange>) -> String:
  match m:
    case Some{r}: comma(True{}, pa_vmin_vmax(r))
    case None{}: ""

# `repr((int, int))` -- the image2d case, ops.py:47.
def pa_image(g: O.Img) -> String:
  match g:
    case O.Img{h, w}: String.concat(["image=(", U32.show(h), ", ", U32.show(w), ")"])

def pa_image.of1(m: Maybe<&2, O.Img>) -> String:
  match m:
    case Some{g}: comma(True{}, pa_image(g))
    case None{}: ""

def pa_multiple_of(m: Maybe<&2, U32>) -> String:
  match m:
    case Some{v}: comma(True{}, U32.show(v))
    case None{}: ""

# `repr(str)` is the string in single quotes; ops.py:46 makes this the field
def pa_name(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: comma(True{}, String.concat(["name='", s, "'"]))
    case None{}: ""

def pa_addrspace.is_global(a: S.Addr) -> Bool:
  match a:
    case S.AGlobal{}: True{}
    case _: False{}

def pa_addrspace(+a: S.Addr) -> String:
  comma(Bool.not(pa_addrspace.is_global(a)), String.concat(["addrspace=", addr_repr(a)]))

def pa_device(m: Maybe<&2, S.Dev>) -> String:
  match m:
    case Some{d}: comma(True{}, String.concat(["device=", dev_repr(d)]))
    case None{}: ""

def pa_flag(nm: String, b: Bool) -> String:
  match b:
    case True{}: String.concat([", ", nm, "=True"])
    case False{}: ""

def pa_val(m: Maybe<&2, O.Const>) -> String:
  match m:
    case Some{v}: comma(True{}, String.concat(["val=", const_repr(v)]))
    case None{}: ""

def pa_buffer.size(m: Maybe<&2, U32>) -> String:
  match m:
    case Some{v}: U32.show(v)
    case None{}: "None"

def pa_buffer.device(m: Maybe<&2, S.Dev>) -> String:
  match m:
    case Some{d}: dev_repr(d)
    case None{}: "None"

def pa_buffer.has(m: Maybe<&2, U32>) -> Bool: Maybe.is_some(&2, U32, m)

def pa_buffer.of(has: Bool, slot: U32, dev: String, size: String, dt: String) -> String:
  match has:
    case True{}: String.concat([", buffer=UOp.new_buffer(", dev, ", ", size, ", ", dt, ", ", U32.show(slot), ").buffer"])
    case False{}: ""

# `ParamArg.__repr__` (ops.py:41-49). TWO EDITS, both forced by `72f98ffe0`:
#     size term -- MEASURED, `repr(Tensor.empty(4,3).realize().uop.arg)` is
def pa_tail(+ar: O.Arena, +self: U32, +pa: O.ParamArg) -> List<&2, String>:
  pa_vmin_vmax.of1(O.ParamArg.vmin_vmax(pa)) <> pa_multiple_of(O.ParamArg.multiple_of(pa))
    <> pa_name(O.ParamArg.name(pa)) <> pa_addrspace(O.ParamArg.addrspace(pa)) <> pa_device(O.ParamArg.device(pa))
    <> pa_flag("volatile", O.ParamArg.volatile(pa)) <> pa_image.of1(O.ParamArg.image(pa))
    <> pa_flag("bind_on_realize", O.ParamArg.bind_on_realize(pa)) <> pa_val(O.ParamArg.val(pa))
    <> [pa_buffer.of(pa_buffer.has(O.ParamArg.buffer(pa)), O.ParamArg.slot(pa), pa_buffer.device(O.ParamArg.device(pa)), pa_buffer.size(O.ParamArg.size(ar, self)), dt_repr(O.ParamArg.dtype(pa)))]

def paramarg_repr(+ar: O.Arena, +self: U32, +pa: O.ParamArg) -> String:
  String.concat(["ParamArg(", U32.show(O.ParamArg.slot(pa)), ", ", dt_repr(O.ParamArg.dtype(pa)), String.join(pa_tail(ar, self, pa), ""), ")"])


def u32_list_repr.go(xs: List<&2, U32>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case h <> t: U32.show(h) <> u32_list_repr.go(t)

def u32_list_repr(xs: List<&2, U32>) -> String:
  String.concat(["[", String.join(u32_list_repr.go(xs), ", "), "]"])

# MEASURED (`repr_1tuple` / `repr_0tuple` / `repr_2tuple` in
# was WRONG before this unit and the gate said so the whole time: the baseline row
def u32_tuple_repr(+xs: List<&2, U32>) -> String:
  String.concat(["(", String.join(u32_list_repr.go(xs), ", "),
    Bool.pick(String, Nat.is_eq(List.length(&2, U32, xs), 1n), ",", ""), ")"])

def bool_tuple_repr.go(+xs: List<&2, Bool>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case h <> t: Bool.show(h) <> bool_tuple_repr.go(t)

def bool_tuple_repr(+xs: List<&2, Bool>) -> String:
  String.concat(["(", String.join(bool_tuple_repr.go(xs), ", "),
    Bool.pick(String, Nat.is_eq(List.length(&2, Bool, xs), 1n), ",", ""), ")"])

def peek_str(xs: List<&2, U32>) -> String:
  U32.show(Maybe.default(&2, U32, List.head(&2, U32, xs), 0))

def axis_repr(a: O.AxisType) -> String:
  String.concat(["AxisType.", O.AxisType.name(a)])

# dispatch. MEASURED at both ends (`.agents/slop/xd1/render-oracle.py`):
# `(AxisType.WEAK, 0, 1)` and NOT `(AxisType.WEAK, (0, 1))`. MEASURED at both
def arange_repr(ids: List<&2, U32>, at: O.AxisType) -> String:
  String.concat(["(", axis_repr(at), ", ", String.join(u32_list_repr.go(ids), ", "), ")"])

def awmma_tc(tc: Maybe<&2, List<&2, U32>>) -> String:
  match tc:
    case Some{x}: u32_list_repr(x)
    case _: "None"

def awmma_repr(dims: List<&2, U32>, dt: S.Dt, th: U32, tc: Maybe<&2, List<&2, U32>>) -> String:
  String.concat(["([", String.join(u32_list_repr.go(dims), ", "), "], ", dt_repr(dt), ", ", U32.show(th), ", ", awmma_tc(tc), ")"])

def aink_repr(ins: String, dt: S.Dt) -> String:
  String.concat(["('", ins, "', ", dt_repr(dt), ")"])


def aallred_repr(rop: O.Op, dev: S.Dev) -> String:
  String.concat(["(", O.Ops.name(rop), ", ", dev_repr(dev), ")"])

def areduce_repr(rop: O.Op, num_axes: U32) -> String:
  String.concat(["(", O.Ops.name(rop), ", ", U32.show(num_axes), ")"])

def acall_name(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: String.concat(["'", s, "'"])
    case None{}: "None"

# is four fields and a closing paren, measured at tinygrad/uop/ops.py:1408-1410.
def ci_named() -> O.CallInfo:
  O.CallInfo{Some{"f"}, False{}, False{}, S.int32()}

def ci_weak() -> O.CallInfo:
  O.CallInfo{None{}, False{}, False{}, S.weakint()}

# `CallInfo.__repr__`, HEAD tinygrad/uop/ops.py:1408-1410:
# The PIN (pin/tinygrad/uop/ops.py:1401-1404) appended `, dtype=` when the dtype
def acall_repr(+ci: O.CallInfo) -> String:
  String.concat(["CallInfo(None, ", acall_name(O.CallInfo.name(ci)), ", ", Bool.show(O.CallInfo.precompile(ci)), ", ", Bool.show(O.CallInfo.precompile_backward(ci)), ")"])

def akernel_estimates(m: Maybe<&2, E.Estimates>) -> String:
  match m:
    case None{}: "None"
    case Some{e}: E.Estimates.str(e)
def akernel_applied(xs: List<&2, O.OPT>) -> String:
  match xs:
    case Nil{}: "()"
    case _ <> _: "<Opt>"

# beam=0, optimized=False)`. MEASURED against the vendored upstream: `repr(
def akernel_repr(+ki: O.KernelInfo) -> String:
  String.concat(["KernelInfo(name='", O.KernelInfo.name(ki), "', applied_opts=", akernel_applied(O.KernelInfo.applied_opts(ki)), ", opts_to_apply=None, estimates=", akernel_estimates(O.KernelInfo.estimates(ki)), ", beam=", U32.show(O.KernelInfo.beam(ki)), ", optimized=", Bool.show(O.KernelInfo.optimized(ki)), ")"])

def i64_tuple_repr.go(xs: List<&2, H.I64>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case h <> t: sint_i64(h) <> i64_tuple_repr.go(t)

def i64_tuple_repr(xs: List<&2, H.I64>) -> String:
  String.concat(["(", String.join(i64_tuple_repr.go(xs), ", "), ")"])

def aprogram_vars(xs: List<&2, U32>) -> String:
  match xs:
    case Nil{}: "()"
    case _ <> _: "<UOp>"

def aprogram_repr(+pi: O.ProgramInfo) -> String:
  String.concat(["ProgramInfo(global_size=", i64_tuple_repr(O.ProgramInfo.global_size(pi)), ", local_size=", i64_tuple_repr(O.ProgramInfo.local_size(pi)), ", vars=", aprogram_vars(O.ProgramInfo.params(pi)), ", globals=", u32_tuple_repr(O.ProgramInfo.globals(pi)), ", outs=", u32_tuple_repr(O.ProgramInfo.outs(pi)), ", ins=", u32_tuple_repr(O.ProgramInfo.ins(pi)), ", target=)"])

# CustomFunction is a NEW Arg constructor (ops.bend, uop/ops.py:1394-1397). Upstream it is a
# tinygrad/uop/ops.py:1394-1397. A bare `name, dtype` pair is not that string.
def customfunction_repr(+cf: O.CustomFunction) -> String:
  String.concat(["CustomFunction(name='", O.CustomFunction.name(cf), "', dtype=", dt_repr(O.CustomFunction.dtype(cf)), ")"])

# `UOp.tuplize` -- THE ORDER, ops.py:316. IT IS NOT THE KEY.
# `_UOpTuple` is a `tuple` SUBCLASS (`ops.py:221-226`) whose `__eq__` is IDENTITY and whose `<`
# over `Arena.nodes` -- so no key is wanted. But `uop/symbolic.py:225` is its OTHER consumer,

def arg_repr(+ar: O.Arena, +self: U32, a: O.Arg) -> String:
  match a:
    case O.ANone{}: "None"
    case O.ADt{dt}: dt_repr(dt)
    case O.ACustom{+cf}: customfunction_repr(cf)
    case O.APy{v}: const_repr(v)
    case O.AParam{pa}: paramarg_repr(ar, self, pa)
    case O.ACall{ci}: acall_repr(ci)
    case O.AKernel{ki}: akernel_repr(ki)
    case O.AProgram{pi}: aprogram_repr(pi)
    case O.ARange{ids, at}: arange_repr(ids, at)
    case O.AReduce{rop, num_axes}: areduce_repr(rop, num_axes)
    case O.AOpLit{op}: O.Ops.name(op)
    case O.AWmma{dims, dt, threads, tc}: awmma_repr(dims, dt, threads, tc)
    case O.ATuple{ys}: u32_tuple_repr(ys)
    case O.ABoolList{bs}: bool_tuple_repr(bs)
    case O.AStr{s}: String.concat(["'", s, "'"])
    case O.AInk{ins, dt}: aink_repr(ins, dt)
    case O.AAllred{rop, dev}: aallred_repr(rop, dev)
    case O.ADev{dev}: dev_repr(dev)
    case O.ABlob{bs}: String.concat(["<bytes ", Nat.show(List.length(&2, U32, bs)), ">"])
    case O.AInt{i}: U32.show(i)
    case O.AFloat{f}: f32_repr(f)
    case O.ABad{}: "ABad"

# `tagstr` / `repr(tag)` -- ops.py:275 and render.py:136. `str` and `repr` of a
# one with a flag: `tagstr` is a f-string (render.py:14) and `_render_with_splits`

def tag_str.go(xs: List<&2, U32>) -> List<&2, String>:
  match xs:
    case Nil{}: Nil{}
    case h <> t: "<UOp>" <> tag_str.go(t)

def tag_str(t: O.Tag) -> String:
  match t:
    case O.TNone{}: "None"
    case O.TBool{b}: Bool.show(b)
    case O.TStr{s}: s
    case O.TInt{i}: U32.show(i)
    case O.TTuple{xs}: String.concat(["(", String.join(tag_str.go(xs), ", "), ")"])

def tag_repr(t: O.Tag) -> String:
  match t:
    case O.TNone{}: "None"
    case O.TBool{b}: Bool.show(b)
    case O.TStr{s}: String.concat(["'", s, "'"])
    case O.TInt{i}: U32.show(i)
    case O.TTuple{xs}: String.concat(["(", String.join(tag_str.go(xs), ", "), ")"])

# `UOp.tagstr` -- ops.py:277, `f", tag={self.tag}" if self.tag is not None else ""`
def tag_is_none(t: O.Tag) -> Bool:
  match t:
    case O.TNone{}: True{}
    case _: False{}

def tagstr.of(t: O.Tag, isnone: Bool) -> String:
  Bool.pick(String, isnone, "", String.concat([", tag=", tag_str(t)]))

def tagstr(+t: O.Tag) -> String:
  tagstr.of(t, tag_is_none(t))

# `syms` -- render.py:25. `for debug`: the spelling of each binary operator, and
# COMPARISONS ARE NOT IN THIS TABLE. render.py:82 -- Python chains comparisons

def syms_of(op: O.Op) -> String:
  match op:
    case O.OpsADD{}: "+"
    case O.OpsSUB{}: "-"
    case O.OpsDIV{}: "//"
    case O.OpsMOD{}: "%"
    case O.OpsSHL{}: "<<"
    case O.OpsSHR{}: ">>"
    case O.OpsMUL{}: "*"
    case O.OpsCMPLT{}: "<"
    case O.OpsCMPNE{}: "!="
    case O.OpsAND{}: "&"
    case O.OpsOR{}: "|"
    case O.OpsXOR{}: "^"
    case _: ""

# `precedence` -- render.py:28. Eleven entries, and the readers ask

def precedence_of(op: O.Op) -> U32:
  match op:
    case O.OpsMUL{}: 1
    case O.OpsDIV{}: 1
    case O.OpsMOD{}: 1
    case O.OpsADD{}: 2
    case O.OpsSUB{}: 2
    case O.OpsSHL{}: 3
    case O.OpsSHR{}: 3
    case O.OpsAND{}: 4
    case O.OpsXOR{}: 5
    case O.OpsOR{}: 6
    case _: 99

def has_precedence(op: O.Op) -> Bool: U32.is_lt(precedence_of(op), 99)

# `strip_binary_parens` -- render.py:29.
# call sites (render.py:65 and render.py:113) pass the SAME body,
def sbp_operand(has: Bool, +ar: O.Arena, u: U32, n: U32, p: U32, +s: String) -> String:
  Bool.pick(String, Bool.and(has, U32.is_le(precedence_of(O.Arena.op(ar, O.Arena.src(ar, u, n))), p)), H.strip_parens(s), s)

def sbp_arm(+has: Bool, +ar: O.Arena, +u: U32, +p: U32, +left: String, +right: String) -> String:
  String.concat(["(", sbp_operand(has, ar, u, 0, p, left), syms_of(O.Arena.op(ar, u)), sbp_operand(has, ar, u, 1, p, right), ")"])

def strip_binary_parens(+ar: O.Arena, +u: U32, left: String, right: String) -> String:
  sbp_arm(has_precedence(O.Arena.op(ar, u)), ar, u, precedence_of(O.Arena.op(ar, u)), left, right)

# `range_str` -- ops.py:95. Rebuilt here because it is ABSENT from ops.bend
def range_str.one(+x: U32) -> String:
  Bool.pick(String, sint_show.half(x), String.concat(["m", sint_show(U32.sub(0, x))]), sint_show(x))

def range_str.go(ids: List<&2, U32>) -> List<&2, String>:
  match ids:
    case Nil{}: Nil{}
    case h <> t: range_str.one(h) <> range_str.go(t)

def range_str.of(at: O.AxisType, +ids: List<&2, U32>) -> String:
  String.join(range_str.go(ids), "_")

def range_str.color(f: H.Flags, at: O.AxisType, s: String) -> String:
  H.colored(f, s, H.color_of(O.axis_colors(at)), False{})

# `multirange_str` -- ops.py:99.
def lt_u32(xs: List<&2, U32>, ys: List<&2, U32>) -> Bool:
  match xs:
    case Nil{}: False{}
    case +h <> t:
      match ys:
        case Nil{}: True{}
        case +g <> u: Bool.or(U32.is_lt(h, g), Bool.and(U32.is_eq(h, g), lt_u32(t, u)))

def range_lt.put(idslt: Bool, +xs: List<&2, U32>, atx: O.AxisType, aty: O.AxisType) -> Bool:
  Bool.pick(Bool, idslt, U32.is_lt(O.AxisType.value(atx), O.AxisType.value(aty)), False{})

def range_lt.ids2(y: O.Arg, +xs: List<&2, U32>, atx: O.AxisType) -> Bool:
  match y:
    case O.ARange{ys, aty}: range_lt.put(lt_u32(xs, ys), xs, atx, aty)
    case _: False{}

def range_lt.ids(x: O.Arg, y: O.Arg) -> Bool:
  match x:
    case O.ARange{xs, atx}: range_lt.ids2(y, xs, atx)
    case _: False{}

def range_lt.of(x: O.Arg, y: O.Arg) -> Bool:
  range_lt.ids(x, y)

def range_lt(+ar: O.Arena, x: U32, y: U32) -> Bool:
  range_lt.of(O.Arena.arg(ar, x), O.Arena.arg(ar, y))

def u32_ins(+ar: O.Arena, +x: U32, +acc: List<&2, U32>) -> List<&2, U32>:
  match acc:
    case Nil{}: [x]
    case h <> t: Bool.pick(List<&2, U32>, range_lt(ar, x, h), x <> acc, h <> u32_ins(ar, x, t))

def u32_isort.go(+ar: O.Arena, xs: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case h <> t: u32_isort.go(ar, t, u32_ins(ar, h, acc))

def u32_isort(ar: O.Arena, xs: List<&2, U32>) -> List<&2, U32>: u32_isort.go(ar, xs, Nil{})

def multirange_str.n(+sd: Nat, +n: Nat) -> Nat:
  Bool.pick(Nat, Nat.is_le(n, sd), Nat.sub(sd, n), 0n)

def multirange_str.pad(+s: String, sd: U32) -> String:
  String.concat([s, String.repeat(" ", multirange_str.n(U32.to_nat(sd), String.length(H.ansistrip(s))))])

def range_at.of(a: O.Arg) -> O.AxisType:
  match a:
    case O.ARange{ids, at}: at
    case _: O.AXIS_LOOP{}

def range_at(+ar: O.Arena, u: U32) -> O.AxisType:
  range_at.of(O.Arena.arg(ar, u))

def range_ids.of(a: O.Arg) -> List<&2, U32>:
  match a:
    case O.ARange{ids, at}: ids
    case _: Nil{}

def range_ids(+ar: O.Arena, u: U32) -> List<&2, U32>:
  range_ids.of(O.Arena.arg(ar, u))

def multirange_str.of(+f: H.Flags, +at: O.AxisType, +ids: List<&2, U32>) -> String:
  range_str.color(f, at, range_str.of(at, ids))

def multirange_str.go(+f: H.Flags, +ar: O.Arena, rngs: List<&2, U32>) -> List<&2, String>:
  match rngs:
    case Nil{}: Nil{}
    case +u <> t: multirange_str.of(f, range_at(ar, u), range_ids(ar, u)) <> multirange_str.go(f, ar, t)

def multirange_str(+f: H.Flags, +ar: O.Arena, +rngs: List<&2, U32>, pad: U32) -> String:
  multirange_str.pad(String.join(multirange_str.go(f, ar, u32_isort(ar, rngs)), ","), pad)

# one-entry `MLeaf` REPLACES the leaf and drops the old key, which MEASURED as

type Ctx is Data:
  Ctx{m: Map<&2, String>}

def Ctx.map(c: Ctx) -> Map<&2, String>:
  match c:
    case Ctx{m}: m

def ctx_new() -> Ctx: Ctx{Map.new(&2, String)}

def ctx_put(c: Ctx, u: U32, s: String) -> Ctx:
  Ctx{Map.set(&2, String, Ctx.map(c), U32.show(u), s)}

def ctx_get.of(r: Sigma<&1, &1, Map<&2, String>, _ => String>) -> String:
  match r:
    case Tuple{m, v}: v

def ctx_get(c: Ctx, u: U32) -> String:
  ctx_get.of(Map.get(String, "", Ctx.map(c), U32.show(u)))

def ctx_has.of(r: Sigma<&1, &1, Map<&2, String>, _ => Bool>) -> Bool:
  match r:
    case Tuple{m, b}: b

def ctx_has(c: Ctx, u: U32) -> Bool:
  ctx_has.of(Map.has(&2, String, Ctx.map(c), U32.show(u)))

# `srcs` -- render.py:84.

def srcs.go(+c: Ctx, srcs: List<&2, U32>) -> List<&2, String>:
  match srcs:
    case Nil{}: Nil{}
    case u <> t: ctx_get(c, u) <> srcs.go(c, t)

def srcs_one(+c: Ctx, +srcs: List<&2, U32>) -> String:
  String.concat(["(", ctx_get(c, Maybe.default(&2, U32, List.head(&2, U32, srcs), 0)), ",)"])

def srcs(+c: Ctx, +srcs: List<&2, U32>) -> String:
  Bool.pick(String, Nat.is_eq(List.length(&2, U32, srcs), 1n), srcs_one(c, srcs), String.concat(["(", String.join(srcs.go(c, srcs), ", "), ")"]))

# THE pm_pyrender RULES, compiled. render.py:88-123 is fifteen `UPat`s, and the
def op_lower(op: O.Op) -> String: String.to_lower(O.Ops.name.of(op))

def dt_of.of(m: Maybe<&2, S.Dt>) -> S.Dt:
  match m:
    case Some{d}: d
    case None{}: S.void()

def dt_of(tb: F.Table, ar: O.Arena, u: U32) -> S.Dt:
  dt_of.of(F.fold.dt(ar, tb, u))

# `UOp.tuplize`'s order -- ops.py:316, and the port decides three of its four keys.
# `_UOpTuple` is a `tuple` SUBCLASS (`ops.py:221-226`) whose `__eq__` is IDENTITY and whose `<`
# -- so no key is wanted. But `uop/symbolic.py:225` is its OTHER consumer, `commutative`'s rule
# SIMPLIFIED. `DType.__lt__` (`dtype.py:68`) compares `(priority, bitsize, name, fmt)`, and
# `name -> fmt` IS A FUNCTION over tinygrad's 20 distinct dtype names (MEASURED 2026-11-03:
def ord3(lt: Bool, gt: Bool) -> U32:
  match lt gt:
    case True{} _: 1
    case _ True{}: 2
    case _ _     : 0

def tup_lift(z: Bool, c: U32) -> Maybe<&2, U32>:
  match z:
    case True{} : None{}
    case False{}: Some{c}

def lt_then(z: Bool, a: U32, b: U32) -> U32:
  match z:
    case True{} : b
    case False{}: a

def dt_ord(x: S.Dt, y: S.Dt) -> U32:
  match x y:
    case S.Dt{+p1, +b1, +c1, +n1} S.Dt{+p2, +b2, +c2, +n2}:
      +o1 = ord3(U32.is_lt(p1, p2), U32.is_gt(p1, p2))
      +o2 = ord3(U32.is_lt(b1, b2), U32.is_gt(b1, b2))
      +o3 = ord3(String.is_lt(n1, n2), String.is_gt(n1, n2))
      lt_then(U32.is_zero(o1), o1, lt_then(U32.is_zero(o2), o2, o3))

# ops.py:225) -- in this port that is index equality, because the arena IS the interning.
type TC is Data:
  TCn{a: U32, b: U32}
  TCl{sa: List<&2, U32>, sb: List<&2, U32>}

type TCStep is Data:
  TSa{m: Maybe<&2, U32>}
  TSn{w: TC}

def tc_keys(+tb: F.Table, +ar: O.Arena, +a: U32, +b: U32) -> U32:
  +va = O.Ops.value(O.Arena.op(ar, a))
  +vb = O.Ops.value(O.Arena.op(ar, b))
  +ra = arg_repr(ar, a, O.Arena.arg(ar, a))
  +rb = arg_repr(ar, b, O.Arena.arg(ar, b))
  +k1 = ord3(U32.is_lt(va, vb), U32.is_gt(va, vb))
  +k2 = ord3(String.is_lt(ra, rb), String.is_gt(ra, rb))
  +k3 = dt_ord(dt_of(tb, ar, a), dt_of(tb, ar, b))
  lt_then(U32.is_zero(k1), k1, lt_then(U32.is_zero(k2), k2, k3))

def tc_n_step(c: U32, zero: Bool, +ar: O.Arena, +a: U32, +b: U32) -> TCStep:
  match zero:
    case False{}: TSa{Some{c}}
    case True{} : TSn{TCl{O.Arena.srcs(ar, a), O.Arena.srcs(ar, b)}}

def tc_l_pick(same: Bool, +xt: List<&2, U32>, +yt: List<&2, U32>, x: U32, y: U32) -> TCStep:
  match same:
    case True{} : TSn{TCl{xt, yt}}
    case False{}: TSn{TCn{x, y}}

def tc_l_step(sa: List<&2, U32>, sb: List<&2, U32>) -> TCStep:
  match sa sb:
    case Nil{} Nil{}     : TSa{None{}}
    case Nil{} _         : TSa{Some{1}}
    case _ Nil{}         : TSa{Some{2}}
    case +x <> +xt +y <> +yt: tc_l_pick(U32.is_eq(x, y), xt, yt, x, y)

def tc_step(w: TC, +tb: F.Table, +ar: O.Arena) -> TCStep:
  match w:
    case TCn{+a, +b}:
      +c = tc_keys(tb, ar, a, b)
      tc_n_step(c, U32.is_zero(c), ar, a, b)
    case TCl{sa, sb}: tc_l_step(sa, sb)

# makes, and generous rather than tight because a short fuel is a WRONG ANSWER shaped like a tie.
def tc_fuel(ar: O.Arena) -> Nat: U32.to_nat(U32.add(U32.mul(O.Arena.next(ar), 4), 8))

def tc_go(fuel: Nat, s: TCStep, +tb: F.Table, +ar: O.Arena) -> Maybe<&2, U32>:
  match fuel s:
    case 0n _      : None{}
    case 1n++k TSa{m}: m
    case 1n++k TSn{w}: tc_go(k, tc_step(w, tb, ar), tb, ar)

def uop_tup_cmp(+tb: F.Table, +ar: O.Arena, +a: U32, +b: U32) -> Maybe<&2, U32>:
  tc_go(tc_fuel(ar), TSn{TCn{a, b}}, tb, ar)

# `commutative` -- uop/symbolic.py:227-232, and it is ONE RULE with EIGHT placements.
# "neither less nor greater", and a tie is NOT a flip -- `src[1] < src[0]` is FALSE for a tie
def comm_op(op: O.Op) -> Bool:
  match op:
    case O.OpsADD{}  : True{}
    case O.OpsAND{}  : True{}
    case O.OpsCMPEQ{}: True{}
    case O.OpsCMPNE{}: True{}
    case O.OpsMAX{}  : True{}
    case O.OpsMUL{}  : True{}
    case O.OpsOR{}   : True{}
    case O.OpsXOR{}  : True{}
    case _           : False{}

def dt_weak(d: S.Dt) -> Bool:
  match d:
    case S.Dt{pri, bits, c, nm}:
      match c:
        case S.CWeakInt{}: True{}
        case _           : False{}

def comm_fire(+tb: F.Table, +ar: O.Arena, +x: U32) -> Bool:
  Bool.and(comm_op(O.Arena.op(ar, x)), dt_weak(dt_of(tb, ar, x)))

# `x.src[1] < x.src[0]` AND NOT `<=`: a tie leaves the operands alone.
def comm_flip(m: Maybe<&2, U32>) -> Bool:
  match m:
    case Some{v}: U32.is_eq(v, 1)
    case None{} : False{}

def comm_do(go: Bool, +ar: O.Arena, +x: U32) -> Maybe<&2, O.Found>:
  match go:
    case False{}: None{}
    case True{} :
      +f = O.UOp.new(ar, O.Arena.op(ar, x),
                     List.reverse(&2, U32, O.Arena.srcs(ar, x)),
                     O.Arena.arg(ar, x), O.Arena.tag(ar, x))
      Some{f}

def commutative(+tb: F.Table, +ar: O.Arena, +x: U32) -> Maybe<&2, O.Found>:
  +s1 = Maybe.default(&2, U32, List.head(&2, U32, O.Arena.src_from(ar, x, 1)), 0)
  comm_do(Bool.and(comm_fire(tb, ar, x), comm_flip(uop_tup_cmp(tb, ar, s1, O.Arena.src0(ar, x)))), ar, x)

def ismeta_of(a: O.Arg) -> Bool:
  match a:
    case O.ANone{}: False{}
    case _: True{}

def pmp.fb.args.of(ismeta: Bool, +s: String) -> String:
  Bool.pick(String, ismeta, String.concat([", ", s, ")"]), ")")

def pmp.fb.args(+ar: O.Arena, +u: U32, a: O.Arg, ismeta: Bool) -> String:
  pmp.fb.args.of(ismeta, arg_repr(ar, u, a))

def pmp.fb.of(ismeta: Bool, +ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  String.concat(["UOp(", O.Ops.name(O.Arena.op(ar, u)), ", ", srcs(ctx, O.Arena.srcs(ar, u)), pmp.fb.args(ar, u, O.Arena.arg(ar, u), ismeta)])

def pmp.fb(+ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  pmp.fb.of(ismeta_of(O.Arena.arg(ar, u)), ar, ctx, u)

def val_str.v(v: O.Const) -> String:
  match v:
    case O.CBool{b}: Bool.show(b)
    case O.CInt{i}: sint_i64(i)
    case O.CFloat{f}: f32_repr(f)
    case O.CInvalid{}: "Invalid"

def val_str.of(a: O.Arg) -> String:
  match a:
    case O.APy{v}: val_str.v(v)
    case _: "?"

def val_str(a: O.Arg) -> String: val_str.of(a)

def pmp.const.of(zero: Bool, +ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  Bool.pick(String, zero, String.concat(["UOp.const(", val_str(O.Arena.arg(ar, u)), ")"]), pmp.fb(ar, ctx, u))

def pmp.const(+ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  pmp.const.of(U32.is_zero(O.Arena.nsrc(ar, u)), ar, ctx, u)

def dt_same.of(a: S.Dt, b: S.Dt) -> Bool: O.eq_dt(a, b)

def pmp.cast.of(same: Bool, +ar: O.Arena, tb: F.Table, +ctx: Ctx, +u: U32) -> String:
  Bool.pick(String, same, pmp.fb(ar, ctx, u),
    String.concat([ctx_get(ctx, O.Arena.src0(ar, u)), ".", op_lower(O.Arena.op(ar, u)), "(", dt_repr(dt_of(tb, ar, u)), ")"]))

def dt_same(+tb: F.Table, +ar: O.Arena, +u: U32) -> Bool:
  dt_same.of(dt_of(tb, ar, u), dt_of(tb, ar, O.Arena.src0(ar, u)))

def is_const.of(op: O.Op) -> Bool:
  match op:
    case O.OpsCONST{}: True{}
    case _: False{}

def is_const(ar: O.Arena, u: U32) -> Bool: is_const.of(O.Arena.op(ar, u))

def pmp.special.of(one: Bool, isconst: Bool, +ar: O.Arena, +ctx: Ctx, +u: U32) -> String:
  Bool.pick(String, Bool.not(one), pmp.fb(ar, ctx, u),
# becomes a constructor with the ParamArg inline. MEASURED, and the two halves
    Bool.pick(String, Bool.not(isconst), pmp.fb(ar, ctx, u),
      String.concat(["UOp.special(", val_str(O.Arena.arg(ar, O.Arena.src0(ar, u))), ", ", arg_repr(ar, u, O.Arena.arg(ar, u)), ")"])))

def pmp.special(+ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  pmp.special.of(Nat.is_eq(List.length(&2, U32, O.Arena.srcs(ar, u)), 1n), is_const(ar, O.Arena.src0(ar, u)), ar, ctx, u)

# what a deletion does to a first-wins dispatch, and it is not "the answer changes": a
# BUFFER now reaches NO pyrender rule and lands on rule 15, which is
# `f"UOp({u.op}, {srcs(ctx,u.src)}" + (f", {repr(u.arg)})" if u.arg is not None else ")")`.
# So the printed form stops being a `UOp.new_buffer(...)` CALL and becomes a constructor
# with the ParamArg inline. MEASURED, and the two halves are different failures:
def pmp.copy.of(any: Bool, +ar: O.Arena, +ctx: Ctx, +u: U32) -> String:
  Bool.pick(String, Bool.not(any), pmp.fb(ar, ctx, u),
    String.concat([ctx_get(ctx, O.Arena.src0(ar, u)), ".copy_to_device(", arg_repr(ar, u, O.Arena.arg(ar, u)), ")"]))

def pmp.copy(+ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  pmp.copy.of(Nat.is_le(1n, List.length(&2, U32, O.Arena.srcs(ar, u))), ar, ctx, u)

def pmp.cfn(+ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  String.concat(["UOp(Ops.CUSTOM_FUNCTION, src=", srcs(ctx, O.Arena.srcs(ar, u)), ", arg=", arg_repr(ar, u, O.Arena.arg(ar, u)), ")"])

def reduce_op.of(a: O.Arg) -> String:
  match a:
    case O.AReduce{rop, num_axes}: O.Ops.name(rop)
    case _: "?"

def reduce_op(ar: O.Arena, u: U32) -> String: reduce_op.of(O.Arena.arg(ar, u))

def reduce_axes.of(a: O.Arg) -> U32:
  match a:
    case O.AReduce{rop, num_axes}: num_axes
    case _: 0

def reduce_axes(ar: O.Arena, u: U32) -> U32: reduce_axes.of(O.Arena.arg(ar, u))

def range_tuple.go(n: Nat, +p: Nat, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: acc
    case 1n+q: range_tuple.go(q, Nat.add(p, 1n), List.append(&2, U32, acc, [U32.from_nat(p)]))

def range_tuple(n: U32) -> String:
  String.concat(["(", String.join(u32_list_repr.go(range_tuple.go(U32.to_nat(n), 0n, Nil{})), ", "), ")"])

#     ends. MEASURED, `.agents/slop/xd1/render-rows.py` rows `pyrender range`
#     and becomes a constructor with the arg inline. MEASURED, the three `flat`
def range_tail.of(n: Bool, +ss: List<&2, U32>, +ctx: Ctx) -> String:
  Bool.pick(String, n, String.concat([", src=", srcs(ctx, ss)]), "")

def range_pieces.tail(ids: List<&2, U32>, at: O.AxisType) -> List<&2, String>:
  List.append(&2, String, List.append(&2, String, Nil{}, [peek_str(ids)]), [axis_repr(at)])

def range_pieces(+ar: O.Arena, ctx: Ctx, +u: U32) -> List<&2, String>:
  List.append(&2, String, Nil{}, [val_str(O.Arena.arg(ar, O.Arena.src0(ar, u))),
    peek_str(range_ids(ar, u)), axis_repr(range_at(ar, u))])

def range_one_id(ids: List<&2, U32>) -> Bool:
  Nat.is_eq(List.length(&2, U32, ids), 1n)

def pmp.range.of(any: Bool, isconst: Bool, one: Bool, +ar: O.Arena, +ctx: Ctx, +u: U32) -> String:
  Bool.pick(String, Bool.not(any), pmp.fb(ar, ctx, u),
    Bool.pick(String, Bool.not(isconst), pmp.fb(ar, ctx, u),
      Bool.pick(String, Bool.not(one), pmp.fb(ar, ctx, u),
        String.concat(["UOp.range(", String.join(range_pieces(ar, ctx, u), ", "),
          range_tail.of(Nat.is_le(2n, List.length(&2, U32, O.Arena.srcs(ar, u))), O.Arena.src_from(ar, u, 1), ctx), ")"]))))

def pmp.range(+ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  pmp.range.of(Nat.is_le(1n, List.length(&2, U32, O.Arena.srcs(ar, u))), is_const(ar, O.Arena.src0(ar, u)), range_one_id(range_ids(ar, u)), ar, ctx, u)

def pmp.alu.where(+ar: O.Arena, +ctx: Ctx, +u: U32) -> String:
  String.concat([ctx_get(ctx, O.Arena.src0(ar, u)), ".alu(", O.Ops.name(O.Arena.op(ar, u)), ", ", ctx_get(ctx, O.Arena.src(ar, u, 1)), ", ", ctx_get(ctx, O.Arena.src(ar, u, 2)), ")"])

def pmp.alu.bin(+ar: O.Arena, +ctx: Ctx, +u: U32) -> String:
  String.concat([ctx_get(ctx, O.Arena.src0(ar, u)), ".alu(", O.Ops.name(O.Arena.op(ar, u)), ", ", ctx_get(ctx, O.Arena.src(ar, u, 1)), ")"])

# so the test MEASURED TRUE for a two-src node and FALSE for a three-src one --
def pmp.syms.of(two: Bool, +ar: O.Arena, +ctx: Ctx, +u: U32) -> String:
  Bool.pick(String, two, strip_binary_parens(ar, u, ctx_get(ctx, O.Arena.src0(ar, u)), ctx_get(ctx, O.Arena.src(ar, u, 1))), pmp.alu.bin(ar, ctx, u))

def pmp.syms(+ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  pmp.syms.of(Nat.is_eq(List.length(&2, U32, O.Arena.srcs(ar, u)), 2n), ar, ctx, u)

def arg_clause.of(+ar: O.Arena, +u: U32, ismeta: Bool, a: O.Arg) -> String:
  Bool.pick(String, ismeta, String.concat(["arg=", arg_repr(ar, u, a)]), "")

def sugar_args.go(ar: O.Arena, +ctx: Ctx, u: U32, +ss: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case s <> t: sugar_args.go(ar, ctx, u, t, List.append(&2, String, acc, [ctx_get(ctx, s)]))

# `consumer_map_from_toposort` -- ops.py:110.

def cu32.of(r: Sigma<&1, &1, Map<&2, U32>, _ => U32>) -> U32:
  match r:
    case Tuple{m, v}: v

def cu32(m: Map<&2, U32>, u: U32) -> U32:
  cu32.of(Map.get(U32, 0, m, U32.show(u)))

def chas.of(r: Sigma<&1, &1, Map<&2, U32>, _ => Bool>) -> Bool:
  match r:
    case Tuple{m, b}: b

def chas(m: Map<&2, U32>, u: U32) -> Bool:
  chas.of(Map.has(&2, U32, m, U32.show(u)))

type Cons is Data:
  Cons{seen: Map<&2, U32>, cnt: Map<&2, U32>, who: Map<&2, U32>}

# `to_render` -- render.py:151-164, the decision of which nodes get their own

def not_rendered(op: O.Op) -> Bool: is_const.of(op)

def always_rendered(op: O.Op) -> Bool:
  match op:
    case O.OpsPARAM{}: True{}
    case O.OpsLOAD{}: True{}
    case O.OpsSPECIAL{}: True{}
    case O.OpsRANGE{}: True{}
    case O.OpsSTACK{}: True{}
    case O.OpsBUFFER{}: True{}
    case O.OpsALLOC{}: True{}
    case O.OpsCOPY{}: True{}
    case O.OpsCALL{}: True{}
    case O.OpsWHERE{}: True{}
    case O.OpsEND{}: True{}
    case O.OpsBACKEDGE{}: True{}
    case _: False{}

def op_is_sink_or_store(op: O.Op) -> Bool:
  match op:
    case O.OpsSINK{}: True{}
    case O.OpsSTORE{}: True{}
    case O.OpsREDUCE{}: True{}
    case _: False{}

def tr_set(tr: Map<&2, U32>, u: U32) -> Map<&2, U32>: Map.set(&2, U32, tr, U32.show(u), 1)

def uses.go(+ss: List<&2, U32>, +u: U32, n: U32) -> U32:
  match ss:
    case Nil{}: n
    case +s <> t: uses.go(t, u, U32.add(n, Bool.to_u32(U32.is_eq(s, u))))

# `_render_with_splits` -- render.py:125-141.

type Bind is Data:
  Bind{k: String, v: String}

type RWS is Data:
  RWS{ctx: Ctx, ret: List<&2, Bind>, dep: Map<&2, U32>, trn: Map<&2, U32>}

def op_depth.go(+ss: List<&2, U32>, +dep: Map<&2, U32>, acc: U32) -> U32:
  match ss:
    case Nil{}: acc
    case s <> t: op_depth.go(t, dep, U32.max(acc, cu32(dep, s)))

def rws_dep.of(intr: Bool, d: U32, +dep: Map<&2, U32>, u: U32) -> Map<&2, U32>:
  Map.set(&2, U32, dep, U32.show(u), Bool.pick(U32, intr, 0, d))

def rws_dep(+dep: Map<&2, U32>, u: U32, d: U32, intr: Bool) -> Map<&2, U32>:
  rws_dep.of(intr, d, dep, u)

# Python parser") is why it is not infinity. render.py:140 -- the split keeps
def rws_trn.of(write: Bool, +tr: Map<&2, U32>, u: U32) -> Map<&2, U32>:
  Bool.pick(Map<&2, U32>, write, tr_set(tr, u), tr)

def rws_trn(+tr: Map<&2, U32>, u: U32, d: U32, intr: Bool) -> Map<&2, U32>:
  rws_trn.of(Bool.or(intr, U32.is_gt(d, 100)), tr, u)

def rws_key(last: U32, i: U32, u: U32) -> String:
  Bool.pick(String, U32.is_eq(u, last), "ast", String.concat(["c", U32.show(i)]))

# Python reads here as the FALSE arm. Getting this backwards puts every rendered
def rws_ren.pick(intr: Bool, +ren: String, +last: U32, +i: U32, +u: U32, +ctx: Ctx, +ret: List<&2, Bind>, +dep: Map<&2, U32>, +trn: Map<&2, U32>) -> RWS:
  Bool.pick(RWS, intr,
    RWS{ctx_put(ctx, u, rws_key(last, i, u)), List.append(&2, Bind, ret, [Bind{rws_key(last, i, u), ren}]), dep, trn},
    RWS{ctx_put(ctx, u, ren), ret, dep, trn})

def rws_ren.of(intr: Bool, +ren: String, last: U32, i: U32, +u: U32, +ctx: Ctx, +ret: List<&2, Bind>, +dep: Map<&2, U32>, +trn: Map<&2, U32>) -> RWS:
  rws_ren.pick(intr, ren, last, i, u, ctx, ret, dep, trn)

def rws_ret(st: RWS) -> List<&2, Bind>:
  match st:
    case RWS{ctx, ret, dep, trn}: ret

def last_of(xs: List<&2, U32>) -> U32: Maybe.default(&2, U32, List.last(&2, U32, xs), 0)

def op_depth(+ar: O.Arena, u: U32, +dep: Map<&2, U32>) -> U32:
  U32.add(1, op_depth.go(O.Arena.srcs(ar, u), dep, 0))

def pmp.cast(+ar: O.Arena, +tb: F.Table, ctx: Ctx, +u: U32) -> String:
  pmp.cast.of(dt_same(tb, ar, u), ar, tb, ctx, u)

def arg_clause(+ar: O.Arena, +u: U32, +a: O.Arg) -> String:
  arg_clause.of(ar, u, ismeta_of(a), a)

def sugar_tail(+ar: O.Arena, +u: U32, +acc: List<&2, String>) -> List<&2, String>:
  Bool.pick(List<&2, String>, ismeta_of(O.Arena.arg(ar, u)), List.append(&2, String, acc, [arg_clause(ar, u, O.Arena.arg(ar, u))]), acc)

def sugar_args(+ar: O.Arena, ctx: Ctx, +u: U32, +acc: List<&2, String>) -> List<&2, String>:
  sugar_args.go(ar, ctx, u, O.Arena.src_from(ar, u, 1), sugar_tail(ar, u, acc))
def pmp.sugar.of(zero: Bool, +ar: O.Arena, +ctx: Ctx, +u: U32) -> String:
  Bool.pick(String, zero,
    String.concat(["UOp.", op_lower(O.Arena.op(ar, u)), "(", String.join(sugar_args(ar, ctx, u, Nil{}), ", "), ")"]),
    String.concat([ctx_get(ctx, O.Arena.src0(ar, u)), ".", op_lower(O.Arena.op(ar, u)), "(", String.join(sugar_args(ar, ctx, u, Nil{}), ", "), ")"]))

def pmp.sugar(+ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  pmp.sugar.of(U32.is_zero(O.Arena.nsrc(ar, u)), ar, ctx, u)

def pmp.reduce.of(has: Bool, +ar: O.Arena, +ctx: Ctx, +u: U32) -> String:
  Bool.pick(String, Bool.not(has), pmp.sugar(ar, ctx, u),
    String.concat([ctx_get(ctx, O.Arena.src0(ar, u)), "._rop(", reduce_op(ar, u), ", ", range_tuple(reduce_axes(ar, u)), ")"]))

def pmp.reduce(+ar: O.Arena, ctx: Ctx, +u: U32) -> String:
  pmp.reduce.of(Nat.is_le(1n, U32.to_nat(reduce_axes(ar, u))), ar, ctx, u)

def pmp.go.of(op: O.Op, ar: O.Arena, tb: F.Table, ctx: Ctx, u: U32) -> String:
  match op:
    case O.OpsCONST{}: pmp.const(ar, ctx, u)
    case O.OpsCAST{}: pmp.cast(ar, tb, ctx, u)
    case O.OpsBITCAST{}: pmp.cast(ar, tb, ctx, u)
    case O.OpsSPECIAL{}: pmp.special(ar, ctx, u)
    case O.OpsCOPY{}: pmp.copy(ar, ctx, u)
    case O.OpsCUSTOM_FUNCTION{}: pmp.cfn(ar, ctx, u)
    case O.OpsREDUCE{}: pmp.reduce(ar, ctx, u)
    case O.OpsRANGE{}: pmp.range(ar, ctx, u)
    case O.OpsTRUNCDIV{}: pmp.alu.bin(ar, ctx, u)
    case O.OpsTRUNCMOD{}: pmp.alu.bin(ar, ctx, u)
    case O.OpsWHERE{}: pmp.alu.where(ar, ctx, u)
    case O.OpsADD{}: pmp.syms(ar, ctx, u)
    case O.OpsMUL{}: pmp.syms(ar, ctx, u)
    case O.OpsSHL{}: pmp.syms(ar, ctx, u)
    case O.OpsSHR{}: pmp.syms(ar, ctx, u)
    case O.OpsDIV{}: pmp.syms(ar, ctx, u)
    case O.OpsMOD{}: pmp.syms(ar, ctx, u)
    case O.OpsAND{}: pmp.syms(ar, ctx, u)
    case O.OpsXOR{}: pmp.syms(ar, ctx, u)
    case O.OpsOR{}: pmp.syms(ar, ctx, u)
    case O.OpsCMPLT{}: pmp.syms(ar, ctx, u)
    case O.OpsCMPNE{}: pmp.syms(ar, ctx, u)
    case O.OpsSUB{}: pmp.fb(ar, ctx, u)
    case O.OpsSQRT{}: pmp.sugar(ar, ctx, u)
    case O.OpsINDEX{}: pmp.sugar(ar, ctx, u)
    case O.OpsSTORE{}: pmp.sugar(ar, ctx, u)
    case O.OpsLOAD{}: pmp.sugar(ar, ctx, u)
    case O.OpsSINK{}: pmp.sugar(ar, ctx, u)
    case O.OpsEND{}: pmp.sugar(ar, ctx, u)
    case O.OpsBACKEDGE{}: pmp.sugar(ar, ctx, u)
    case O.OpsAFTER{}: pmp.sugar(ar, ctx, u)
    case O.OpsTHREEFRY{}: pmp.sugar(ar, ctx, u)
    case O.OpsRECIP{}: pmp.sugar(ar, ctx, u)
    case O.OpsEXP2{}: pmp.sugar(ar, ctx, u)
    case O.OpsLOG2{}: pmp.sugar(ar, ctx, u)
    case O.OpsSIN{}: pmp.sugar(ar, ctx, u)
    case O.OpsBARRIER{}: pmp.sugar(ar, ctx, u)
    case O.OpsDETACH{}: pmp.sugar(ar, ctx, u)
    case _: pmp.fb(ar, ctx, u)

def pmp(+ar: O.Arena, tb: F.Table, ctx: Ctx, +u: U32) -> String:
  pmp.go.of(O.Arena.op(ar, u), ar, tb, ctx, u)

def rtag.of(+t: O.Tag, +s: String) -> String:
  Bool.pick(String, tag_is_none(t), s, String.concat([".rtag(", tag_repr(t), ")"]))

def rtag(+t: O.Tag) -> String: rtag.of(t, "")

def ren_str(+ar: O.Arena, tb: F.Table, ctx: Ctx, +u: U32) -> String:
  String.concat([pmp(ar, tb, ctx, u), rtag(O.Arena.tag(ar, u))])

def rws_step.put(+d: U32, +intr: Bool, +ar: O.Arena, +tb: F.Table, last: U32, i: U32, +u: U32, +ctx: Ctx, +ret: List<&2, Bind>, +dep: Map<&2, U32>, +trn: Map<&2, U32>) -> RWS:
  rws_ren.of(intr, ren_str(ar, tb, ctx, u), last, i, u, ctx, ret, rws_dep(dep, u, d, intr), rws_trn(trn, u, d, intr))

def rws_step.of(+ar: O.Arena, +tb: F.Table, last: U32, i: U32, +u: U32, +ctx: Ctx, +ret: List<&2, Bind>, +dep: Map<&2, U32>, +trn: Map<&2, U32>) -> RWS:
  rws_step.put(op_depth(ar, u, dep), chas(trn, u), ar, tb, last, i, u, ctx, ret, dep, trn)

def rws_step(+ar: O.Arena, +tb: F.Table, last: U32, i: U32, +u: U32, +st: RWS) -> RWS:
  match st:
    case RWS{ctx, ret, dep, trn}: rws_step.of(ar, tb, last, i, u, ctx, ret, dep, trn)

def rws.go(lst: List<&2, U32>, +ar: O.Arena, +tb: F.Table, +last: U32, +i: U32, +st: RWS) -> RWS:
  match lst:
    case Nil{}: st
    case +u <> t: rws.go(t, ar, tb, last, U32.add(i, 1), rws_step(ar, tb, last, i, u, st))

def render_with_splits(+ar: O.Arena, +tb: F.Table, +lst: List<&2, U32>, +trn: Map<&2, U32>) -> List<&2, Bind>:
  rws_ret(rws.go(lst, ar, tb, last_of(lst), 0, RWS{ctx_new(), Nil{}, Map.new(&2, U32), trn}))

def ret_row.of(k: String, +v: String) -> String:
  String.concat([k, " = ", Bool.pick(String, H.is_wrapped(v), H.strip_parens(v), v)])

def ret_row(p: Bind) -> String:
  match p:
    case Bind{k, v}: ret_row.of(k, v)

def ret_rows.go(ps: List<&2, Bind>) -> List<&2, String>:
  match ps:
    case Nil{}: Nil{}
    case p <> t: ret_row(p) <> ret_rows.go(t)

def ret_rows(ps: List<&2, Bind>) -> List<&2, String>: ret_rows.go(ps)

def Cons.seen(c: Cons) -> Map<&2, U32>:
  match c:
    case Cons{seen, cnt, who}: seen

def Cons.cnt(c: Cons) -> Map<&2, U32>:
  match c:
    case Cons{seen, cnt, who}: cnt

def Cons.who(c: Cons) -> Map<&2, U32>:
  match c:
    case Cons{seen, cnt, who}: who

def cons_bump.write(u: U32, +s: U32, +c: Cons) -> Cons:
  match c:
    case Cons{seen, cnt, who}: Cons{seen, Map.set(&2, U32, cnt, U32.show(s), U32.add(cu32(cnt, s), 1)), Map.set(&2, U32, who, U32.show(s), u)}

def cons_bump(+ar: O.Arena, +u: U32, +s: U32, +c: Cons) -> Cons:
  Bool.pick(Cons, U32.is_eq(cu32(Cons.who(c), s), u), c, cons_bump.write(u, s, c))

def cons_one(+ar: O.Arena, u: U32, +s: U32, +c: Cons) -> Cons:
  Bool.pick(Cons, chas(Cons.seen(c), s), cons_bump(ar, u, s, c), c)

def cons_add(+ss: List<&2, U32>, +ar: O.Arena, +u: U32, +c: Cons) -> Cons:
  match ss:
    case Nil{}: c
    case +s <> t: cons_add(t, ar, u, cons_one(ar, u, s, c))

def consumers.empty() -> Cons:
  Cons{Map.new(&2, U32), Map.new(&2, U32), Map.new(&2, U32)}

def consumers.mark(+c: Cons, u: U32) -> Cons:
  match c:
    case Cons{seen, cnt, who}: Cons{Map.set(&2, U32, seen, U32.show(u), 1), cnt, who}

def consumers.step(+ar: O.Arena, +u: U32, +c: Cons) -> Cons:
  consumers.mark(cons_add(O.Arena.srcs(ar, u), ar, u, c), u)

def consumers.go(lst: List<&2, U32>, +ar: O.Arena, +c: Cons) -> Cons:
  match lst:
    case Nil{}: c
    case +u <> t: consumers.go(t, ar, consumers.step(ar, u, c))

def consumers.new(+ar: O.Arena, lst: List<&2, U32>) -> Cons:
  consumers.go(lst, ar, consumers.empty())

def uses(+ar: O.Arena, v: U32, u: U32) -> U32: uses.go(O.Arena.srcs(ar, v), u, 0)

def tr_continue.of(+op: O.Op, +ar: O.Arena, +u: U32, +c: Cons) -> Bool:
  Bool.or(not_rendered(op),
    Bool.and(U32.is_eq(cu32(Cons.cnt(c), u), 1), Bool.and(U32.is_eq(uses(ar, cu32(Cons.who(c), u), u), 1), Bool.not(always_rendered(op)))))

def tr_continue(op: O.Op, +ar: O.Arena, u: U32, +c: Cons) -> Bool:
  tr_continue.of(op, ar, u, c)

def tr_keep.of(op: O.Op, +ar: O.Arena, +u: U32, +tr: Map<&2, U32>, +c: Cons) -> Map<&2, U32>:
  Bool.pick(Map<&2, U32>, tr_continue(op, ar, u, c), tr, tr_set(tr, u))

def tr_keep(op: O.Op, +ar: O.Arena, u: U32, +tr: Map<&2, U32>, +c: Cons) -> Map<&2, U32>:
  tr_keep.of(op, ar, u, tr, c)

def tr_all(+ss: List<&2, U32>, +ar: O.Arena, +tr: Map<&2, U32>) -> Map<&2, U32>:
  match ss:
    case Nil{}: tr
    case +s <> t: tr_all(t, ar, tr_set(tr, s))

def tr_of.of(op: O.Op, +ar: O.Arena, u: U32, +tr: Map<&2, U32>) -> Map<&2, U32>:
  match op:
    case O.OpsSINK{}: tr_all(O.Arena.srcs(ar, u), ar, tr)
    case O.OpsSTORE{}: tr_set(tr, O.Arena.src(ar, u, 1))
    case O.OpsREDUCE{}: tr_set(tr, O.Arena.src0(ar, u))
    case _: tr

def tr_of(op: O.Op, ar: O.Arena, u: U32, tr: Map<&2, U32>) -> Map<&2, U32>:
  tr_of.of(op, ar, u, tr)

def tr_push.of(op: O.Op, +op2: O.Op, +ar: O.Arena, u: U32, +tr: Map<&2, U32>) -> Map<&2, U32>:
  Bool.pick(Map<&2, U32>, Bool.not(op_is_sink_or_store(op2)), tr, tr_of(op2, ar, u, tr))

def tr_push(op: O.Op, +ar: O.Arena, +u: U32, +tr: Map<&2, U32>) -> Map<&2, U32>:
  tr_push.of(O.Arena.op(ar, u), op, ar, u, tr)

def to_render.go(lst: List<&2, U32>, +ar: O.Arena, +cs: Cons, +tr: Map<&2, U32>) -> Map<&2, U32>:
  match lst:
    case Nil{}: tr
    case +u <> t: to_render.go(t, ar, cs, tr_keep(O.Arena.op(ar, u), ar, u, tr_push(O.Arena.op(ar, u), ar, u, tr), cs))

def to_render(+ar: O.Arena, +lst: List<&2, U32>, ast: U32) -> Map<&2, U32>:
  to_render.go(lst, ar, consumers.new(ar, lst), tr_set(Map.new(&2, U32), ast))

def pyrender.of(+ar: O.Arena, +tb: F.Table, +ast: U32, +lst: List<&2, U32>) -> String:
  String.join(ret_rows(render_with_splits(ar, tb, lst, to_render(ar, lst, ast))), "\n")

def pyrender(+ar: O.Arena, +tb: F.Table, +ast: U32) -> String:
  pyrender.of(ar, tb, ast, O.UOp.toposort(O.Arena.budget(ar), ar, ast))

def pyr_buffer.pa(a: O.Arg) -> Bool:
  match a:
    case O.AParam{pa}: Maybe.is_some(&2, U32, O.ParamArg.buffer(pa))
    case _: False{}

#   ops.py:497` in ops.bend. `multirange_str` and `range_str` ARE ported here
#   `a.render()`, and `render` is `# TODO(p3) ops.py:1139  def render` in ops.bend; it needs
#   `simplify()` (`# TODO(p3) ops.py:495  def simplify`) and the whole `renderer` matcher, whose
#   by ordering. `render_marg` itself is `x.marg`, which is `# TODO(p3) ops.py:768  def marg`.
# TODO(p3) render.py:7   def pretty_print
# no ranges, and MEASURED, BUF, ADD and C1 all have `ranges == []` here. A node that
def pa1() -> O.ParamArg:
  O.ParamArg{1, S.single(), None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{2}},
    False{}, None{}, None{}, False{}, None{}}

def pa2() -> O.ParamArg:
  O.ParamArg{2, S.int32(), None{}, None{}, Some{"g"}, S.AGlobal{}, None{},
    False{}, None{}, None{}, False{}, None{}}

# the arena fixtures that drive `pyrender`. render.py:143 is the whole repr
def pa3() -> O.ParamArg:
  O.ParamArg{3, S.single(), None{}, None{}, None{}, S.ALocal{}, None{},
    True{}, Some{O.Img{2, 2}}, None{}, False{}, None{}}

# THE TABLE IS IN `.agents/slop/tables/uop-render-2105.md` -- the arena fixtures that drive `pyrender`. render.py:143 is the whole repr
def f_const(+ar: O.Arena, n: U32) -> O.Found: O.UOp.const(ar, O.CInt{H.i64_of_i32(n)})

# `UOp(Ops.RANGE, src=(CONST(end),), arg=(axis_id, at))` -- ops.py:644.
def f_range(+ar: O.Arena, end: U32, ids: List<&2, U32>, at: O.AxisType) -> O.Found:
  O.UOp.new(ar, O.OpsRANGE{}, [end], O.ARange{ids, at}, O.TNone{})

def f_rng_at(+c: O.Found, ids: List<&2, U32>) -> O.Found:
  f_range(O.Found.ar(c), O.Found.i(c), ids, O.AXIS_WEAK{})

def f_rng(ar: O.Arena, n: U32, id: U32) -> O.Found:
  f_rng_at(f_const(ar, n), [id])

def f_rng_ids(ar: O.Arena, n: U32, ids: List<&2, U32>) -> O.Found:
  f_rng_at(f_const(ar, n), ids)

def f_buf_r(+r: O.Found, dev: S.Dev, size: U32) -> O.Found:
  O.UOp.new(O.Found.ar(r), O.OpsBUFFER{}, [O.Found.i(r)],
    O.AParam{O.ParamArg{0, S.int32(), None{}, None{}, None{}, S.AGlobal{}, Some{dev},
      False{}, None{}, None{}, False{}, None{}}}, O.TNone{})

def f_buf(ar: O.Arena, dev: S.Dev, +size: U32) -> O.Found:
  f_buf_r(f_rng(ar, size, 0), dev, size)

# shape is the LANE'S OWN: `rebase-gate.py:377` calls `name = [v]   py=[w]` the
# and the oracle's carried none: MEASURED, the port lane had 49 continuation
def py_cell(nm: String, +ans: String) -> IO(Unit):
  IO.print(String.concat([nm, " = [", ans, "]   py=[", ans, "]"]))

# with one of them has to be shaped the same way. MEASURED: the two differ by
def py_nocol(nm: String, +ans: String) -> IO(Unit):
  IO.print(String.concat([nm, " = [", ans, "]"]))

# MEASURED: 6 of the 80 rows carrying a `py=` literal, and they were exactly
# and WRONG AGAINST THAT CAPTURE.
def py_row(nm: String, +f: O.Found) -> IO(Unit):
  +a = pyrender(O.Found.ar(f), F.UOp.fold(O.Found.ar(f)), O.Found.i(f))
  py_cell(nm, a)

# directions, MEASURED over four bodies x four CallInfo shapes
# `u.body` is `u.src[0]` -- ops.py:562-565 -- and it is a `# TODO(p3)` in
# channel, P6), so in THIS port those two conjuncts are CONSTANT FALSE and the

def pyr_call.body_prog(body: O.Op) -> Bool:
  match body:
    case O.OpsPROGRAM{}: True{}
    case _: False{}

def pyr_call.of(op: O.Op, body: O.Op) -> Bool:
  match op:
    case O.OpsCALL{}: pyr_call.body_prog(body)
    case _: False{}

def pyr_call(+ar: O.Arena, +u: U32) -> Bool:
  pyr_call.of(O.Arena.op(ar, u), O.Arena.op(ar, O.Arena.src0(ar, u)))

def pyr_buffer.of(op: O.Op, a: O.Arg) -> Bool:
  match op:
    case O.OpsBUFFER{}: pyr_buffer.pa(a)
    case _: False{}

# MEASURED unchanged: `78d482262` deleted the rule that RENDERED a BUFFER but
def pyr_buffer(+ar: O.Arena, +u: U32) -> Bool:
  pyr_buffer.of(O.Arena.op(ar, u), O.Arena.arg(ar, u))

def pyr_row(nm: String, b: Bool) -> IO(Unit):
  +a = Bool.show(b)
  py_cell(nm, a)

def g_const() -> O.Found: f_const(O.Arena.empty(), 3)

# RULE 2. The CAST's dtype (`float`) DIFFERS from its src's (`weakint`), which is
def g_cast() -> O.Found:
  +c = f_const(O.Arena.empty(), 3)
  O.UOp.new(O.Found.ar(c), O.OpsCAST{}, [O.Found.i(c)], O.ADt{S.single()}, O.TNone{})

def g_special() -> O.Found:
  +c = f_const(O.Arena.empty(), 4)
  O.UOp.special(O.Found.ar(c), O.Found.i(c), "gidx")

def g_buffer() -> O.Found: f_buf(O.Arena.empty(), S.D1{0}, 4)

def g_copy() -> O.Found:
  +b = f_buf(O.Arena.empty(), S.Dn{[0, 2]}, 4)
  O.UOp.new(O.Found.ar(b), O.OpsCOPY{}, [O.Found.i(b)], O.AStr{"METAL"}, O.TNone{})

def f_bufr(+r: O.Found, pa: O.ParamArg) -> O.Found:
  O.UOp.new(O.Found.ar(r), O.OpsBUFFER{}, [O.Found.i(r)], O.AParam{pa}, O.TNone{})

def g_buflocal() -> O.Found:
  f_bufr(f_rng(O.Arena.empty(), 4, 0),
    O.ParamArg{0, S.int32(), None{}, None{}, None{}, S.ALocal{}, Some{S.D1{0}},
      False{}, None{}, None{}, False{}, None{}})

def g_bufnodev() -> O.Found:
  f_bufr(f_rng(O.Arena.empty(), 4, 0),
    O.ParamArg{0, S.int32(), None{}, None{}, None{}, S.AGlobal{}, None{},
      False{}, None{}, None{}, False{}, None{}})

def g_bufimage() -> O.Found:
  f_bufr(f_rng(O.Arena.empty(), 4, 0),
    O.ParamArg{0, S.int32(), None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
      False{}, Some{O.Img{2, 2}}, None{}, False{}, None{}})

# buffer slot is a registry index, so they are DIFFERENT numbers in every real
def g_bufrefused() -> O.Found:
  f_bufr(f_rng(O.Arena.empty(), 4, 0),
    O.ParamArg{0, S.int32(), None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
      False{}, None{}, Some{9}, False{}, None{}})

# `arg=CustomFunction(name='myfn', dtype=dtypes.void)` (ops.py:1394, render.py:97).
def g_cfn() -> O.Found:
  +a = f_const(O.Arena.empty(), 3)
  +b = f_const(O.Found.ar(a), 4)
  O.UOp.new(O.Found.ar(b), O.OpsCUSTOM_FUNCTION{}, [O.Found.i(a), O.Found.i(b)], O.ACustom{O.CustomFunction.of("myfn")}, O.TNone{})

def g_reduce() -> O.Found:
  +a = f_const(O.Arena.empty(), 1)
  +b = f_const(O.Found.ar(a), 2)
  +s = O.UOp.alu(O.Found.ar(b), O.OpsADD{}, [O.Found.i(a), O.Found.i(b)])
  O.UOp.new(O.Found.ar(s), O.OpsREDUCE{}, [O.Found.i(s)], O.AReduce{O.OpsADD{}, 2}, O.TNone{})

def g_range() -> O.Found: f_rng(O.Arena.empty(), 4, 0)

# RULE 8's NEW GUARD, `len(x.axis_id) == 1`, on the FALSE arm. `flat1` is the
def g_flat1() -> O.Found: f_rng_ids(O.Arena.empty(), 4, [0])

def g_flat2() -> O.Found: f_rng_ids(O.Arena.empty(), 4, [0, 1])

def g_flat3() -> O.Found: f_rng_ids(O.Arena.empty(), 4, [0, 1, 2])

def g_range2() -> O.Found:
  +a = f_const(O.Arena.empty(), 4)
  +b = f_const(O.Found.ar(a), 0)
  O.UOp.new(O.Found.ar(b), O.OpsRANGE{}, [O.Found.i(a), O.Found.i(b)], O.ARange{[0], O.AXIS_LOOP{}}, O.TNone{})

def g_cdiv() -> O.Found:
  +a = f_const(O.Arena.empty(), 7)
  +b = f_const(O.Found.ar(a), 2)
  O.UOp.alu(O.Found.ar(b), O.OpsTRUNCDIV{}, [O.Found.i(a), O.Found.i(b)])

def g_cmod() -> O.Found:
  +a = f_const(O.Arena.empty(), 7)
  +b = f_const(O.Found.ar(a), 2)
  O.UOp.alu(O.Found.ar(b), O.OpsTRUNCMOD{}, [O.Found.i(a), O.Found.i(b)])

def g_where() -> O.Found:
  +a = O.UOp.const(O.Arena.empty(), O.CBool{True{}})
  +b = f_const(O.Found.ar(a), 2)
  +c = f_const(O.Found.ar(b), 3)
  O.UOp.alu(O.Found.ar(c), O.OpsWHERE{}, [O.Found.i(a), O.Found.i(b), O.Found.i(c)])

def g_nest() -> O.Found:
  +a = f_const(O.Arena.empty(), 1)
  +b = f_const(O.Found.ar(a), 2)
  +ab = O.UOp.alu(O.Found.ar(b), O.OpsADD{}, [O.Found.i(a), O.Found.i(b)])
  +m1 = f_const(O.Found.ar(ab), 4294967295)
  +mb = O.UOp.alu(O.Found.ar(m1), O.OpsMUL{}, [O.Found.i(b), O.Found.i(m1)])
  +am = O.UOp.alu(O.Found.ar(mb), O.OpsADD{}, [O.Found.i(a), O.Found.i(mb)])
  +p = O.UOp.alu(O.Found.ar(am), O.OpsMUL{}, [O.Found.i(ab), O.Found.i(am)])
  +c = f_const(O.Found.ar(p), 3)
  O.UOp.alu(O.Found.ar(c), O.OpsADD{}, [O.Found.i(p), O.Found.i(c)])

def g_mul3() -> O.Found:
  +c16 = f_const(O.Arena.empty(), 16)
  +r0 = f_range(O.Found.ar(c16), O.Found.i(c16), [0], O.AXIS_WEAK{})
  +c4 = f_const(O.Found.ar(r0), 4)
  +r1 = f_range(O.Found.ar(c4), O.Found.i(c4), [1], O.AXIS_WEAK{})
  +c3 = f_const(O.Found.ar(r1), 3)
  O.UOp.alu(O.Found.ar(c3), O.OpsMUL{}, [O.Found.i(r0), O.Found.i(r1), O.Found.i(c3)])

def g_xor3() -> O.Found:
  +c8 = f_const(O.Arena.empty(), 8)
  +r0 = f_range(O.Found.ar(c8), O.Found.i(c8), [0], O.AXIS_WEAK{})
  +c4 = f_const(O.Found.ar(r0), 4)
  +r1 = f_range(O.Found.ar(c4), O.Found.i(c4), [1], O.AXIS_WEAK{})
  +c5 = f_const(O.Found.ar(r1), 5)
  O.UOp.alu(O.Found.ar(c5), O.OpsXOR{}, [O.Found.i(r0), O.Found.i(r1), O.Found.i(c5)])

def g_sqrt() -> O.Found: O.UOp.new(O.Arena.empty(), O.OpsSQRT{}, Nil{}, O.ANone{}, O.TNone{})

def g_index() -> O.Found:
  +a = f_const(O.Arena.empty(), 9)
  +c = f_const(O.Found.ar(a), 4)
  +r = f_range(O.Found.ar(c), O.Found.i(c), [0], O.AXIS_WEAK{})
  O.UOp.new(O.Found.ar(r), O.OpsINDEX{}, [O.Found.i(a), O.Found.i(r)], O.ANone{}, O.TNone{})

def g_reduce0() -> O.Found:
  +c16 = f_const(O.Arena.empty(), 16)
  +r0 = f_range(O.Found.ar(c16), O.Found.i(c16), [0], O.AXIS_WEAK{})
  O.UOp.new(O.Found.ar(r0), O.OpsREDUCE{}, [O.Found.i(r0)], O.AReduce{O.OpsADD{}, 0}, O.TNone{})

def g_sub() -> O.Found:
  +a = f_const(O.Arena.empty(), 9)
  +b = f_const(O.Found.ar(a), 4)
  O.UOp.alu(O.Found.ar(b), O.OpsSUB{}, [O.Found.i(a), O.Found.i(b)])

def g_tagged() -> O.Found:
  +a = f_const(O.Arena.empty(), 1)
  +b = f_const(O.Found.ar(a), 2)
  O.UOp.new(O.Found.ar(b), O.OpsADD{}, [O.Found.i(a), O.Found.i(b)], O.ANone{}, O.TStr{"mytag"})

def g_shared() -> O.Found:
  +a = f_const(O.Arena.empty(), 1)
  +b = f_const(O.Found.ar(a), 2)
  +ab = O.UOp.alu(O.Found.ar(b), O.OpsADD{}, [O.Found.i(a), O.Found.i(b)])
  +c = f_const(O.Found.ar(ab), 3)
  +d = O.UOp.alu(O.Found.ar(c), O.OpsSUB{}, [O.Found.i(ab), O.Found.i(c)])
  O.UOp.alu(O.Found.ar(d), O.OpsMUL{}, [O.Found.i(ab), O.Found.i(d)])

def g_fan() -> O.Found:
  +a = f_const(O.Arena.empty(), 1)
  +b = f_const(O.Found.ar(a), 2)
  +ab = O.UOp.alu(O.Found.ar(b), O.OpsADD{}, [O.Found.i(a), O.Found.i(b)])
  +c3 = f_const(O.Found.ar(ab), 3)
  +m1 = O.UOp.alu(O.Found.ar(c3), O.OpsMUL{}, [O.Found.i(ab), O.Found.i(c3)])
  +c4 = f_const(O.Found.ar(m1), 4)
  +m2 = O.UOp.alu(O.Found.ar(c4), O.OpsMUL{}, [O.Found.i(ab), O.Found.i(c4)])
  +c5 = f_const(O.Found.ar(m2), 5)
  +m3 = O.UOp.alu(O.Found.ar(c5), O.OpsMUL{}, [O.Found.i(ab), O.Found.i(c5)])
  +c6 = f_const(O.Found.ar(m3), 6)
  +m4 = O.UOp.alu(O.Found.ar(c6), O.OpsMUL{}, [O.Found.i(ab), O.Found.i(c6)])
  +c7 = f_const(O.Found.ar(m4), 7)
  +m5 = O.UOp.alu(O.Found.ar(c7), O.OpsMUL{}, [O.Found.i(ab), O.Found.i(c7)])
  +c8 = f_const(O.Found.ar(m5), 8)
  +m6 = O.UOp.alu(O.Found.ar(c8), O.OpsMUL{}, [O.Found.i(ab), O.Found.i(c8)])
  +s1 = O.UOp.alu(O.Found.ar(m6), O.OpsADD{}, [O.Found.i(m1), O.Found.i(m2)])
  +s2 = O.UOp.alu(O.Found.ar(s1), O.OpsADD{}, [O.Found.i(s1), O.Found.i(m3)])
  +s3 = O.UOp.alu(O.Found.ar(s2), O.OpsADD{}, [O.Found.i(s2), O.Found.i(m4)])
  +s4 = O.UOp.alu(O.Found.ar(s3), O.OpsADD{}, [O.Found.i(s3), O.Found.i(m5)])
  O.UOp.alu(O.Found.ar(s4), O.OpsADD{}, [O.Found.i(s4), O.Found.i(m6)])

def g_sink() -> O.Found:
  +a = f_const(O.Arena.empty(), 1)
  +b = f_const(O.Found.ar(a), 2)
  +ab = O.UOp.alu(O.Found.ar(b), O.OpsADD{}, [O.Found.i(a), O.Found.i(b)])
  +c = f_const(O.Found.ar(ab), 5)
  +m = O.UOp.alu(O.Found.ar(c), O.OpsMUL{}, [O.Found.i(ab), O.Found.i(c)])
  +s = O.UOp.new(O.Found.ar(m), O.OpsSQRT{}, [O.Found.i(ab)], O.ANone{}, O.TNone{})
  O.UOp.sink(O.Found.ar(s), [O.Found.i(m), O.Found.i(s)])

def g_store() -> O.Found:
  +a = f_const(O.Arena.empty(), 0)
  +b = f_buf(O.Found.ar(a), S.D1{0}, 4)
  O.UOp.new(O.Found.ar(b), O.OpsSTORE{}, [O.Found.i(a), O.Found.i(b)], O.ANone{}, O.TNone{})

def g_reduce2() -> O.Found:
  +c16 = f_const(O.Arena.empty(), 16)
  +r0 = f_range(O.Found.ar(c16), O.Found.i(c16), [0], O.AXIS_WEAK{})
  +c4 = f_const(O.Found.ar(r0), 4)
  +r1 = f_range(O.Found.ar(c4), O.Found.i(c4), [0], O.AXIS_WEAK{})
  O.UOp.new(O.Found.ar(r1), O.OpsREDUCE{}, [O.Found.i(r0), O.Found.i(r1)], O.AReduce{O.OpsMAX{}, 2}, O.TNone{})

# BOTH ways. MEASURED over 4 bodies x 4 CallInfo shapes, 16 refusals

def f_call(ar: O.Arena, +body: O.Found, ci: O.CallInfo) -> O.Found:
  O.UOp.new(ar, O.OpsCALL{}, [O.Found.i(body)], O.ACall{ci}, O.TNone{})

def g_call_noop() -> O.Found:
  +n = O.UOp.new(O.Arena.empty(), O.OpsNOOP{}, Nil{}, O.ANone{}, O.TNone{})
  f_call(O.Found.ar(n), n, O.CallInfo.of())

def g_call_prog() -> O.Found:
  +p = O.UOp.new(O.Arena.empty(), O.OpsPROGRAM{}, Nil{}, O.ANone{}, O.TNone{})
  f_call(O.Found.ar(p), p, O.CallInfo.of())

def g_call_const() -> O.Found:
  +c = f_const(O.Arena.empty(), 3)
  f_call(O.Found.ar(c), c, O.CallInfo.of())

def g_call_named() -> O.Found:
  +n = O.UOp.new(O.Arena.empty(), O.OpsNOOP{}, Nil{}, O.ANone{}, O.TNone{})
  f_call(O.Found.ar(n), n, ci_named())

def rnd_is_set(m: Maybe<&2, String>) -> Bool:
  match m:
    case Some{_}: True{}
    case None{}: False{}

def rnd_named(p: O.ParamArg) -> Maybe<&2, String>:
  match p:
    case O.ParamArg{slot, dtype, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer, bind_on_realize, val}: name

def rnd_letter(op: O.Op) -> String:
  match op:
    case O.OpsPARAM{}: "p"
    case O.OpsALLOC{}: "a"
    case _: "b"

def rnd_param(op: O.Op, +p: O.ParamArg) -> Maybe<&2, String>:
  Bool.pick(Maybe<&2, String>, Bool.not(rnd_is_set(rnd_named(p))),
    Some{String.concat([rnd_letter(op), U32.show(O.ParamArg.slot(p))])},
    rnd_named(p))

# `str(x.val)` AND NOT `const_repr(c)`. Those differ on exactly one arm and the
def rnd_const(c: O.Const) -> String:
  match c:
    case O.CBool{b}: Bool.show(b)
    case O.CInt{i}: sint_i64(i)
    case O.CFloat{f}: f32_repr(f)
    case O.CInvalid{}: "Invalid"


def rnd_of(op: O.Op, arg: O.Arg) -> Maybe<&2, String>:
  match arg:
    case O.AParam{p}: rnd_param(op, p)
    case O.APy{v}: Some{rnd_const(v)}
    case _: None{}

def rnd_pick.of(op: O.Op, arg: O.Arg) -> Maybe<&2, String>: rnd_of(op, arg)

def rnd_leaf(+ar: O.Arena, +i: U32) -> Maybe<&2, String>:
  rnd_pick.of(O.Arena.op(ar, i), O.Arena.arg(ar, i))

#   5 ALLOC    named      the `a<slot>` branch's OPPOSITE name branch
def rnd_pa.put(p: O.ParamArg, nm: Maybe<&2, String>) -> O.ParamArg:
  match p:
    case O.ParamArg{slot, dtype, vmin_vmax, multiple_of, _n, addrspace, device, volatile, image, buffer, bind_on_realize, val}:
      O.ParamArg{slot, dtype, vmin_vmax, multiple_of, nm, addrspace, device, volatile, image, buffer, bind_on_realize, val}

def rnd_pa(slot: U32, nm: Maybe<&2, String>) -> O.ParamArg:
  rnd_pa.put(O.ParamArg.of(slot, S.int32()), nm)

def rnd_ar() -> O.Arena:
  O.Arena.of([
    O.Arena.bottom(),
    O.Node{O.OpsPARAM{}, Nil{}, O.AParam{rnd_pa(3, Some{"i"})}, O.TNone{}, 0},
    O.Node{O.OpsPARAM{}, Nil{}, O.AParam{rnd_pa(7, None{})}, O.TNone{}, 0},
    O.Node{O.OpsBUFFER{}, Nil{}, O.AParam{rnd_pa(1, Some{"buf"})}, O.TNone{}, 0},
    O.Node{O.OpsBUFFER{}, Nil{}, O.AParam{rnd_pa(2, None{})}, O.TNone{}, 0},
    O.Node{O.OpsALLOC{}, Nil{}, O.AParam{rnd_pa(4, Some{"out"})}, O.TNone{}, 0},
    O.Node{O.OpsALLOC{}, Nil{}, O.AParam{rnd_pa(5, None{})}, O.TNone{}, 0},
    O.Node{O.OpsCONST{}, Nil{}, O.APy{O.CInt{H.i64_of_i32(42)}}, O.TNone{}, 0},
    O.Node{O.OpsCONST{}, Nil{}, O.APy{O.CBool{True{}}}, O.TNone{}, 0},
    O.Node{O.OpsCONST{}, Nil{}, O.APy{O.CFloat{1.5}}, O.TNone{}, 0},
    O.Node{O.OpsSPECIAL{}, Nil{}, O.AStr{"gidx"}, O.TNone{}, 0},
])

def rnd_show(m: Maybe<&2, String>) -> String:
  match m:
    case Some{s}: s
    case None{}: "none"

def rnd_row(nm: String, +ar: O.Arena, i: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", rnd_show(rnd_leaf(ar, i))]))

def rnd_rows() -> IO(Unit):
  +ar = rnd_ar()
  do IO<Unit>:
    a : Unit <- rnd_row("rnd_param_named", ar, 1)
    b : Unit <- rnd_row("rnd_param_unnamed", ar, 2)
    c : Unit <- rnd_row("rnd_buffer_named", ar, 3)
    d : Unit <- rnd_row("rnd_buffer_unnamed", ar, 4)
    e : Unit <- rnd_row("rnd_alloc_named", ar, 5)
    f : Unit <- rnd_row("rnd_alloc_unnamed", ar, 6)
    g : Unit <- rnd_row("rnd_const_int", ar, 7)
    h : Unit <- rnd_row("rnd_const_bool", ar, 8)
    i : Unit <- rnd_row("rnd_const_float", ar, 9)
    j : Unit <- rnd_row("rnd_special", ar, 10)
    rnd_row("rnd_unclaimed", ar, 11)

# ==== render.py:18  `print_uops` ===========================================
# ANSI escapes even under `NO_COLOR`. MEASURED: the first oracle draft set
def pu_in(+xs: List<&2, U32>, x: U32) -> Bool: List.contains(U32, U32.is_eq, xs, x)

# THREE arms, and the two tests are in the OPPOSITE order from how they read: the

def pu_val.of(arg: O.Arg) -> String:
  match arg:
    case O.APy{O.CInt{i}}: H.i64_dec(i)
    case O.APy{O.CBool{b}}: Bool.show(b)
    case O.APy{O.CFloat{f}}: f32_repr(f)
    case _: "?"

# THREE arms, and the two tests are in the OPPOSITE order from how they read: the
def pu_val(+ar: O.Arena, +x: U32) -> String:
  pu_val.of(O.Arena.arg(ar, x))

# PRINTED LIST. MEASURED on `pu_index`: the port said `['3', '4']` where CPython says
def pu_pos.go(+xs: List<&2, U32>, +x: U32, +n: U32) -> U32:
  match xs:
    case Nil{}: n
    case h <> t: Bool.pick(U32, U32.is_eq(h, x), n, pu_pos.go(t, x, U32.add(n, 1)))

def pu_pos(+xs: List<&2, U32>, +x: U32, +n: U32) -> U32: pu_pos.go(xs, x, n)

# THREE arms, and the two tests are in the OPPOSITE order from how they read: the
# and CPython's list holds one int and some strs. MEASURED: `['0', '4']` against
def pu_src(+ar: O.Arena, +uops: List<&2, U32>, +x: U32) -> String:
  Bool.pick(String, pu_in(uops, x),
# THREE arms, and the two tests are in the OPPOSITE order from how they read: the
# THREE arms, and the two tests are in the OPPOSITE order from how they read: the
    Bool.pick(String, O.eq_op(O.Arena.op(ar, x), O.OpsCONST{}),
      String.concat(["'", pu_val(ar, x), "'"]), U32.show(pu_pos(uops, x, 0))),
    "'--'")

# THREE arms, and the two tests are in the OPPOSITE order from how they read: the
def pu_srcs.go(+ar: O.Arena, +uops: List<&2, U32>, +t: List<&2, U32>, +acc: String, first: Bool) -> String:
  match t:
    case Nil{}: String.concat([acc, Bool.pick(String, first, "[]", "]")])
    case +h <> r:
      pu_srcs.go(ar, uops, r, String.concat([acc, Bool.pick(String, first, "[", ", "), pu_src(ar, uops, h)]), False{})

def pu_srcs(+ar: O.Arena, uops: List<&2, U32>, +u: U32) -> String:
  pu_srcs.go(ar, uops, O.Arena.srcs(ar, u), "", True{})


def pu_dtype.of(m: Maybe<&2, S.Dt>) -> String:
  match m:
    case Some{d}: dt_repr(d)
    case None{}: "?"

def pu_dtype(+tb: F.Table, +ar: O.Arena, +u: U32) -> String:
  pu_dtype.of(F.UOp.dtype(ar, tb, u))

def pu_line(+f: H.Flags, +rt: F.RTable, +tb: F.Table, +ar: O.Arena, +uops: List<&2, U32>, +i: U32, +u: U32) -> String:
  String.concat([
    H.pad_left(Nat.show(U32.to_nat(i)), 4), " ",
    H.pad_right(O.Ops.name(O.Arena.op(ar, u)), 20), ": ",
    multirange_str(f, ar, F.Rng.rs(F.UOp.ranges(ar, rt, u)), 10), " ",
    H.pad_right(pu_dtype(tb, ar, u), 40), " ",
    H.pad_right(pu_srcs(ar, uops, u), 32), " ",
    arg_repr(ar, u, O.Arena.arg(ar, u))])

def pu_line.go(+f: H.Flags, +rt: F.RTable, +tb: F.Table, +ar: O.Arena, +uops: List<&2, U32>, +t: List<&2, U32>, +acc: List<&2, String>, +i: U32) -> List<&2, String>:
  match t:
    case Nil{}: acc
    case +h <> r: pu_line.go(f, rt, tb, ar, uops, r, List.append(&2, String, acc, [pu_line(f, rt, tb, ar, uops, i, h)]), U32.add(i, 1))

def print_uops(+ar: O.Arena, +uops: List<&2, U32>) -> List<&2, String>:
  pu_line.go(H.Flags.defaults(), F.Ranged.rt(F.ranged(ar)), F.UOp.fold(ar), ar, uops, uops, Nil{}, 0)

# MEASURED, after two rounds of "the oracle is broken".
def pu_pa(slot: U32) -> O.ParamArg:
  O.ParamArg{slot, S.int32(), None{}, None{}, Some{"b"}, S.AGlobal{},
    None{}, False{}, None{}, None{}, False{}, None{}}

def pu_ar() -> O.Arena:
  O.Arena.of([
    O.Arena.bottom(),
    O.Node{O.OpsCONST{}, Nil{}, O.APy{O.CInt{H.i64_of_i32(4)}}, O.TNone{}, 0},
    O.Node{O.OpsRANGE{}, [1], O.ARange{[0], O.AXIS_LOOP{}}, O.TNone{}, 0},
    O.Node{O.OpsBUFFER{}, [1], O.AParam{pu_pa(1)}, O.TNone{}, 0},
    O.Node{O.OpsADD{}, [3, 1], O.ANone{}, O.TNone{}, 0},
    O.Node{O.OpsCONST{}, Nil{}, O.APy{O.CInt{H.i64_of_i32(4)}}, O.TNone{}, 0},
    O.Node{O.OpsCONST{}, Nil{}, O.APy{O.CInt{H.i64_of_i32(8)}}, O.TNone{}, 0}])
# THE TABLE IS IN `.agents/slop/tables/uop-render-2982.md` -- `pu_range`   one BUFFER with a RANGE: the baseline, and the `--` src arm.
def pu_row.go(+nm: String, +ar: O.Arena, xs: List<&2, String>, +acc: String) -> String:
  match xs:
    case Nil{}: acc
    case +h <> t: pu_row.go(nm, ar, t, String.concat([acc, nm, "|", h, "\n"]))

def pu_row.emit(line: String) -> IO(Unit): IO.print(line)

def pu_row(+nm: String, +ar: O.Arena, +uops: List<&2, U32>) -> IO(Unit):
  pu_row.emit(pu_row.go(nm, ar, print_uops(ar, uops), ""))

def pu_rr() -> O.Arena:
  O.Arena.of([
    O.Arena.bottom(),
    O.Node{O.OpsCONST{}, Nil{}, O.APy{O.CInt{H.i64_of_i32(4)}}, O.TNone{}, 0},
    O.Node{O.OpsRANGE{}, [1], O.ARange{[0], O.AXIS_LOOP{}}, O.TNone{}, 0},
    O.Node{O.OpsBUFFER{}, [1], O.AParam{pu_pa(1)}, O.TNone{}, 0},
    O.Node{O.OpsADD{}, [3, 2], O.ANone{}, O.TNone{}, 0}])

def pu_rr_rows(+ar: O.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- pu_row("pu_rrange", ar, [2])
    pu_row("pu_radd", ar, [3, 4, 1, 2])

def pu_rows(+ar: O.Arena) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- pu_row("pu_range", ar, [3])
    b : Unit <- pu_row("pu_missing", ar, [4])
    c : Unit <- pu_row("pu_const", ar, [4, 1])
    d : Unit <- pu_row("pu_index", ar, [3, 4, 1])
    pu_row("pu_constarg", ar, [1, 6])


def main() -> IO(Unit):
  do IO<Unit>:
    pu_rows(pu_ar())
    pu_rr_rows(pu_rr())
    rnd_rows()
    py_row("pyrender const   ", g_const())
    py_row("pyrender cast    ", g_cast())
    py_row("pyrender special ", g_special())
    py_row("pyrender buffer  ", g_buffer())
    py_row("pyrender copy    ", g_copy())
    py_row("pyrender reduce  ", g_reduce())
    py_row("pyrender range   ", g_range())
    py_row("pyrender range2  ", g_range2())
    py_row("pyrender cdiv    ", g_cdiv())
    py_row("pyrender cmod    ", g_cmod())
    py_row("pyrender where   ", g_where())
    py_row("pyrender nest    ", g_nest())
    py_row("pyrender mul3    ", g_mul3())
    py_row("pyrender xor3    ", g_xor3())
    py_row("pyrender sqrt    ", g_sqrt())
    py_row("pyrender index   ", g_index())
    py_row("pyrender reduce0 ", g_reduce0())
    py_row("pyrender sub     ", g_sub())
    py_row("pyrender tagged  ", g_tagged())
    py_row("pyrender shared  ", g_shared())
    py_row("pyrender fan     ", g_fan())
    py_row("pyrender sink    ", g_sink())
    py_row("pyrender store   ", g_store())
    py_row("pyrender reduce2 ", g_reduce2())
    py_row("pyrender flat1   ", g_flat1())
    py_row("pyrender flat2   ", g_flat2())
    py_row("pyrender flat3   ", g_flat3())
    py_row("pyrender buflocal", g_buflocal())
    py_row("pyrender bufnodev", g_bufnodev())
    py_row("pyrender bufimage", g_bufimage())
    # `UOp(Ops.CUSTOM_FUNCTION, ..., arg=CustomFunction("myfn"))`. render.py:97
    # prints `arg={x.arg!r}`; ops.py:1394-1397's dataclass repr is the arg.
    py_row("pyrender cfn     ", g_cfn())
    # THE REFUSAL ROWS. `py=` values MEASURED by `.agents/slop/xd1/
    pyr_row("pyr_call_noop    ", pyr_call(F.Folded.ar(F.folded(O.Found.ar(g_call_noop()))), O.Found.i(g_call_noop())))
    pyr_row("pyr_call_prog    ", pyr_call(F.Folded.ar(F.folded(O.Found.ar(g_call_prog()))), O.Found.i(g_call_prog())))
    pyr_row("pyr_call_const   ", pyr_call(F.Folded.ar(F.folded(O.Found.ar(g_call_const()))), O.Found.i(g_call_const())))
    pyr_row("pyr_call_named   ", pyr_call(F.Folded.ar(F.folded(O.Found.ar(g_call_named()))), O.Found.i(g_call_named())))
    pyr_row("pyr_buffer_plain ", pyr_buffer(F.Folded.ar(F.folded(O.Found.ar(g_buffer()))), O.Found.i(g_buffer())))
    pyr_row("pyr_buffer_held  ", pyr_buffer(F.Folded.ar(F.folded(O.Found.ar(g_bufrefused()))), O.Found.i(g_bufrefused())))
    IO.print("sint_show 0      = [" ++ sint_show(0) ++ "]   py=0")
    IO.print("sint_show 7      = [" ++ sint_show(7) ++ "]   py=7")
    IO.print("sint_show 2**31-1= [" ++ sint_show(2147483647) ++ "] py=2147483647")
    IO.print("sint_show -3     = [" ++ sint_show(4294967293) ++ "] py=-3")
    IO.print("sint_show -2**31 = [" ++ sint_show(2147483648) ++ "] py=-2147483648")
    IO.print("f32_repr 3.0     = [" ++ f32_repr(3.0) ++ "]     py=3.0")
    IO.print("f32_repr 1e30    = [" ++ f32_repr(1000000000000000000000000000000.0) ++ "]     py=1e+30")
    IO.print("f32_repr 0.1     = [" ++ f32_repr(0.1) ++ "]     py=0.1")
    IO.print("const_repr CInt  = [" ++ const_repr(O.CInt{H.i64_of_i32(3)}) ++ "]   py=3")
    IO.print("const_repr CBool = [" ++ const_repr(O.CBool{True{}}) ++ "]   py=True")
    IO.print("const_repr CInv  = [" ++ const_repr(O.CInvalid{}) ++ "]   py=Invalid")
    IO.print("const_repr CFlt  = [" ++ const_repr(O.CFloat{2.5}) ++ "]   py=ConstFloat(2.5)")
    IO.print("dt_repr float    = [" ++ dt_repr(S.single()) ++ "]   py=dtypes.f32")
    IO.print("dt_repr int32    = [" ++ dt_repr(S.int32()) ++ "]   py=dtypes.i32")
    IO.print("addr_repr GLOBAL = [" ++ addr_repr(S.AGlobal{}) ++ "]   py=AddrSpace.GLOBAL")
    IO.print("dev_repr D1(2)   = [" ++ dev_repr(S.D1{2}) ++ "]   py='METAL'")
    IO.print("dev_repr Dn      = [" ++ dev_repr(S.Dn{[0, 2]}) ++ "]   py=('CPU', 'METAL')")
    IO.print("syms_of MUL      = [" ++ syms_of(O.OpsMUL{}) ++ "]   py=*")
    IO.print("prec_of MUL      = [" ++ U32.show(precedence_of(O.OpsMUL{})) ++ "]   py=1")
    IO.print("prec_of TRUNCDIV     = [" ++ U32.show(precedence_of(O.OpsTRUNCDIV{})) ++ "]   py=99")
    IO.print("arg_repr ANone   = [" ++ arg_repr(O.Arena.empty(), 0, O.ANone{}) ++ "]   py=None")
    IO.print("arg_repr ADt     = [" ++ arg_repr(O.Arena.empty(), 0, O.ADt{S.int32()}) ++ "]   py=dtypes.i32")
    IO.print("arg_repr AStr    = [" ++ arg_repr(O.Arena.empty(), 0, O.AStr{"g"}) ++ "]   py='g'")
    # MOVED with `78d482262`. `py=` MEASURED, `.agents/slop/xd1/argrepr.py` row
    IO.print("arg_repr ARng    = [" ++ arg_repr(O.Arena.empty(), 0, O.ARange{[0], O.AXIS_GLOBAL{}}) ++ "]   py=(AxisType.GLOBAL, 0)")
    IO.print("arg_repr ARed    = [" ++ arg_repr(O.Arena.empty(), 0, O.AReduce{O.OpsADD{}, 2}) ++ "]   py=(Ops.ADD, 2)")
    IO.print("arg_repr ATup    = [" ++ arg_repr(O.Arena.empty(), 0, O.ATuple{[1, 2]}) ++ "]   py=(1, 2)")
    # `repr(()) == '()'` are MEASURED at both ends (`.agents/slop/xd1/argrepr.py`),
    IO.print("arg_repr ATup1   = [" ++ arg_repr(O.Arena.empty(), 0, O.ATuple{[7]}) ++ "]   py=(7,)")
    IO.print("arg_repr ATup0   = [" ++ arg_repr(O.Arena.empty(), 0, O.ATuple{Nil{}}) ++ "]   py=()")
    IO.print("arg_repr AInk    = [" ++ arg_repr(O.Arena.empty(), 0, O.AInk{"w", S.single()}) ++ "]   py=('w', dtypes.f32)")
    IO.print("arg_repr AAllred = [" ++ arg_repr(O.Arena.empty(), 0, O.AAllred{O.OpsADD{}, S.D1{2}}) ++ "]   py=(Ops.ADD, 'METAL')")
    IO.print("arg_repr ADev    = [" ++ arg_repr(O.Arena.empty(), 0, O.ADev{S.D1{2}}) ++ "]   py='METAL'")
    IO.print("arg_repr ACALL   = [" ++ arg_repr(O.Arena.empty(), 0, O.ACall{O.CallInfo.of()}) ++ "]   py=CallInfo(None, None, False, False)")
    # the two that the PIN repr printed a dtype for. HEAD ops.py:1408-1410 does
    IO.print("arg_repr ACALL2  = [" ++ arg_repr(O.Arena.empty(), 0, O.ACall{ci_named()}) ++ "]   py=CallInfo(None, 'f', False, False)")
    IO.print("arg_repr ACALL3  = [" ++ arg_repr(O.Arena.empty(), 0, O.ACall{ci_weak()}) ++ "]   py=CallInfo(None, None, False, False)")
    # the bracket. MEASURED, the two disagree by exactly that one character, and
    py_nocol("arg_repr AKern  ", arg_repr(O.Arena.empty(), 0, O.AKernel{O.KernelInfo.of()}))
    py_nocol("arg_repr AProgr ", arg_repr(O.Arena.empty(), 0, O.AProgram{O.ProgramInfo.of()}))
    IO.print("ops_repr ADD     = [" ++ O.Ops.name(O.OpsADD{}) ++ "]   py=Ops.ADD")
    py_nocol("arg_repr AParam1", arg_repr(O.Arena.empty(), 0, O.AParam{pa1()}))
    py_nocol("arg_repr AParam2", arg_repr(O.Arena.empty(), 0, O.AParam{pa2()}))
    py_nocol("arg_repr AParam3", arg_repr(O.Arena.empty(), 0, O.AParam{pa3()}))
    IO.print("tag_str  TStr    = [" ++ tag_str(O.TStr{"x"}) ++ "]   py=x")
    IO.print("tag_repr TStr    = [" ++ tag_repr(O.TStr{"x"}) ++ "]   py='x'")
    IO.print("tag_repr TNone   = [" ++ tag_repr(O.TNone{}) ++ "]   py=None")

# `pyrender` -- render.py:143-167. `lst = list(ast.toposort())`, the to_render
# PREDICATES, which is more useful than an exception anyway: `spec.py:38` calls
