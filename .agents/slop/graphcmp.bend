# graphcmp.bend -- THE PORT SIDE OF THE CANONICAL GRAPH NORMAL FORM.
#
# WHAT THIS FILE IS. `.agents/slop/graphcmp.py` needs a graph in a form BOTH sides emit
# identically, because a raw `repr` diff compares two tinygrad COMMITS and not
# port-vs-tinygrad. Measured in `.agents/slop/pin-tree-oracle-report.md`: the SAME node
# is `CallInfo(None, 'f', False, False)` at the pin and `CallInfo(None, 'f', False,
# False, ...)` at head; `dtypes.float` at one commit and `dtypes.f32` at the next;
# `UOp.range(4, AxisType.WEAK, 0, 1)` against `UOp(Ops.RANGE, (c1,), (AxisType.WEAK,
# 0, 1))`. A pretty diff over those is a diff over two upstream trees.
#
# So this file emits the NORMAL FORM: op, dtype name, shape, arg nesting depth, tag, a
# STRUCTURAL arg, and the ordered child edges. The rules and their `tinygrad/...:line`
# citations live in graphcmp.py's header, which is the single place they are written
# down; this file is the port-side IMPLEMENTATION of them.
#
# IT IS A HARNESS, not a port. It READS `tinybendygrad/uop/ops.bend` and
# `tinybendygrad/uop/fold.bend` and PRINTS. It adds nothing to either and edits neither.
#
# THE WIRE FORMAT is one line per arena node, eight self-delimiting chunks:
#
#     <id> <op> <dtype> <shape> <depth> <tag> <arg> <src>
#
# A chunk is `<bytecount>:<bytes>`, so the COUNT OF SPACES IS NOT A FORMAT -- the reader
# walks the counts. `.agents/slop/pin-tree-oracle-report.md` records `^(\S+) = ` on row
# names silently dropping 216 of 228 rows because the names contain spaces (`PTX
# tensor_cores sm_75`), and two lanes emitting `name=value` against `name = [value]`
# matching ZERO rows and reporting a clean zero. Neither can survive this format.
#
# BEND SHAPE OF EVERY PATTERN BELOW, so a reader does not have to rediscover them: a
# record pattern binds POSITIONALLY with bare names (`case ADt{y1}` at ops.bend:1715),
# there is no `field: binder` form, and a binder may only be REBOUND by `match`ing it --
# never by a field projection, which does not exist (ops.bend:1101-1106).
import ./../../tinybendygrad/uop/ops.bend as O
import ./../../tinybendygrad/uop/fold.bend as F
import ./../../tinybendygrad/helpers.bend as H
import ./../../tinybendygrad/LAWS/spec.bend as S
import ./../../tinybendygrad/uop/render.bend as R

# ===========================================================================
# THE CHUNK. `<bytecount>:<bytes>`. `String.length` counts CHARACTERS, which is byte
# length only while the bytes are ASCII; every string emitted below is a dtype name, an
# op name, an axis name, a device tag, a kernel name or a numeric literal, and
# graphcmp.py REFUSES a non-ASCII chunk instead of reading a short count and then
# mis-parsing the rest of the line.
def chunk.at(+s: String, n: Nat) -> String:
  String.concat([U32.show(U32.from_nat(n)), ":", s])

def chunk(+s: String) -> String:
  chunk.at(s, String.length(s))

# ===========================================================================
# THE ATOMS. Each is `<tag><body>`, so two atoms of different types can never render the
# same text: `None` is `N` and the int zero is `i0`, not `N0`.
#
# dname: `S.Dt`'s FOURTH FIELD is tinygrad's own `DType.name`; `dt.nm` is the bare member
#   (`f32`) and CPython's `DType.__repr__` is `f"dtypes.{self.name}"` (dtype.py:67). The
#   normal form takes the BARE name, so `dtypes.` is a decoration BOTH sides drop rather
#   than a prefix one side keeps.
def dname(d: S.Dt) -> String:
  match d:
    case S.Dt{pri, bits, cls, nm}: nm

def addr(a: S.Addr) -> String:
  match a:
    case S.AGlobal{}: "GLOBAL"
    case S.ALocal{}: "LOCAL"
    case S.AReg{}: "REG"
    case S.Aalu{}: "ALU"

def addr1(a: S.Addr) -> String:
  String.concat(["S", addr(a)])

def i(x: U32) -> String:
  String.concat(["i", U32.show(x)])

# `H.i64_text` is `hi:lo` (helpers.bend:1696-1699), which is why the shape column reads
# `n(0:4,0:3)` rather than `n(4,3)`: a dim is an `H.I64` and dropping the HIGH word would
# read a shape of `2**32` as `0`. It costs four characters per dim and it is the difference
# between an exact column and one that cannot see a large dimension.

def is64(x: H.I64) -> String:
  String.concat(["l", H.i64_text(x)])

def bstr(s: String) -> String:
  String.concat(["s", s])

def bo(x: Bool) -> String:
  match x:
    case True{}: "b1"
    case _: "b0"

def dt(d0: S.Dt) -> String:
  String.concat(["D", dname(d0)])

def opx(o: O.Op) -> String:
  String.concat(["O", O.Ops.name.of(o)])

# THE DEVICE ATOM, RESOLVED THROUGH THE PORT'S OWN TABLE.
#
# `S.Dev`'s tag is interned, not named (LAWS/spec.bend:85-87, and ops.bend's own note
# that the interning table "is NOT THERE" upstream). The port HAS a reader for it:
# `uop/render.bend:360-364`, `dev_names()`/`dev_name.tag`, the table `render.py`'s
# `dev_repr` is ported through and the one `schedule/__init__.bend:1095` and
# `schedule/memory.bend:998` write their tags against. So this emits the port's NAME and
# NOT its tag, which is the same thing CPython emits (`Compiled.device` is the
# canonicalized `str` the device was opened with, tinygrad/device.py:396 via :26,:29) --
# and the emitted name cannot drift from the table because it IS the table.
#
# THE THREE TABLES ARE NOT ONE AND MUST NOT BE MERGED. Measured, not assumed:
#   * `uop/render.bend:361`  -- the ARENA tag: 0=CPU 1=GPU 2=METAL ... 8=NULL 9=DISK.
#   * `runtime/device.bend:702` `dev_name` -- `ALL_DEVICES` (device.py:20) by 1-based
#     index: 1=METAL 2=AMD 3=NV 4=CUDA 5=QCOM 6=CL 7=CPU 8=DSP 9=WEBGPU 11=NULL.
#     It is a faithful port of a DIFFERENT upstream object and its rows use it that way
#     (`too_big(.., String.starts_with(dev_name(7), "NULL"))` is device.py:172's
#     `self.device.startswith("NULL")`, where `self.device` is a BUFFER's, not a graph's).
#   * `renderer/cstyle.bend:121` `dev_name` -- the compiler/LANGUAGE index.
# So the tag column is NOT an index into any of those two, and reading one as the other
# would be a wrong answer rather than a unification.
def dev1(t: U32) -> String:
  bstr(R.dev_name.tag(t))

def devs.go(+ts: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match ts:
    case Nil{}: acc
    case t <> r: devs.go(r, List.append(&2, String, acc, [dev1(t)]))

# `device: str|tuple[str, ...]|None` (ops.py:33), and CPython's `dev()` renders the tuple
# case as `s` over the comma-joined members -- NOT as a nested value, so this is the same
# flat spelling rather than the `n(..)` this file uses for `O.ATuple`.
def devs(ts: List<&2, U32>) -> String:
  bstr(String.join(devs.go(ts, Nil{}), ","))

def dev(dv: S.Dev) -> String:
  match dv:
    case S.D1{tag}: dev1(tag)
    case S.Dn{tags}: devs(tags)

def u32s.go(+ys: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match ys:
    case Nil{}: acc
    case y <> r: u32s.go(r, List.append(&2, String, acc, [i(y)]))

def us(ys: List<&2, U32>) -> String:
  String.concat(["n(", String.join(u32s.go(ys, Nil{}), ","), ")"])

def img2(m: O.Img) -> String:
  match m:
    case O.Img{h, w}: String.concat(["n(", U32.show(h), ",", U32.show(w), ")"])

def rng(r: O.PyRange) -> String:
  match r:
    case O.PyRange{lo, hi}: String.concat(["r(", H.i64_text(lo), ",", H.i64_text(hi), ")"])

def konst(c: O.Const) -> String:
  match c:
    case O.CBool{b}: String.concat(["b", Bool.show(b)])
    case O.CInt{i2}: String.concat(["l", H.i64_text(i2)])
    case O.CFloat{f2}: String.concat(["f", F32.show(f2)])
    # `Invalid` upstream (dtype.py:32) has no value, and a CONST holding one is a refusal
    # upstream raises on (ops.py:190). One tag, `v`, for it.
    case O.CInvalid{}: "v"

# `Maybe` is CPython's `| None`, and `None` and the empty tuple are DIFFERENT values
# (`vmin_vmax=None` is not `vmin_vmax=()`), so absence gets its own tag `N` and a present
# empty tuple gets `n()`.
def mum(m: Maybe<&2, U32>) -> String:
  match m:
    case Some{x}: i(x)
    case _: "N"

def mm(m: Maybe<&2, O.PyRange>) -> String:
  match m:
    case Some{x}: rng(x)
    case _: "N"

def nm(m: Maybe<&2, String>) -> String:
  match m:
    case Some{x}: bstr(x)
    case _: "N"

def dm(m: Maybe<&2, S.Dev>) -> String:
  match m:
    case Some{x}: dev(x)
    case _: "N"

def imgm(m: Maybe<&2, O.Img>) -> String:
  match m:
    case Some{x}: img2(x)
    case _: "N"

def valm(m: Maybe<&2, O.Const>) -> String:
  match m:
    case Some{x}: konst(x)
    case _: "N"

def bufo(m: Maybe<&2, U32>) -> String:
  match m:
    case Some{x}: String.concat(["realized", U32.show(x)])
    case _: "unrealized"

# `str(UOp.argstr)` is `repr(self.arg)` (ops.py:274-276) and `ParamArg.__repr__`
# (ops.py:43-50) OMITS every field equal to its default and spells `buffer` as
# `buffer=UOp.new_buffer(...).buffer`, a device object no second process can rebuild. So
# the normal form is NOT a repr: it is EVERY field, by name, in DECLARATION order
# (ops.py:26-42 for ParamArg), with the device Buffer reduced to `realized<slot>` /
# `unrealized` because `pyrender` itself refuses to render a BUFFER carrying one
# (render.py:160). Field NAMES are the format: a positional reader would encode the
# order and pass a swap, and ops.bend:2432-2440 records that swapping two shape args
# leaves op, nsrc and the src sequence identical.
# THE THIRTEEN-FIELD READER, one `Maybe` per def, because `match` may scrutinise only a
# PARAMETER or a pattern binder and reading a `Maybe` field is a CALL.
def paramarg.of(+slot: U32, +dtx: S.Dt, +size: Maybe<&2, U32>, +vmin_vmax: Maybe<&2, O.PyRange>, +multiple_of: Maybe<&2, U32>,
  +name: Maybe<&2, String>, +addrspace: S.Addr, +device: Maybe<&2, S.Dev>, +volatile: Bool, +image: Maybe<&2, O.Img>,
  +buffer: Maybe<&2, U32>, +bind_on_realize: Bool, +val: Maybe<&2, O.Const>) -> String:
  String.concat(["P(", i(slot), ",", dt(dtx), ",", mum(size), ",", mm(vmin_vmax), ",", mum(multiple_of), ",", nm(name),
    ",", addr1(addrspace), ",", dm(device), ",", bo(volatile), ",", imgm(image), ",", bufo(buffer), ","
    bo(bind_on_realize), ",", valm(val), ")"])

def paramarg(pa: O.ParamArg) -> String:
  match pa:
    case O.ParamArg{slot, dtx, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer,
      bind_on_realize, val}:
      paramarg.of(slot, dtx, size, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer,
        bind_on_realize, val)

def custom_fn(c: O.CustomFunction) -> String:
  match c:
    case O.CustomFunction{cname, cdtype}: String.concat(["cF(", bstr(cname), ",", dt(cdtype), ")"])

# `CallInfo` (ops.py:1400) is NOT a dataclass: it is a plain class with class-level
# defaults, `grad_fxn` first and `aux` last, and its `__repr__` (ops.py:1408-1410) prints
# `id(self.grad_fxn)` -- a per-process address. The port's record carries FOUR fields
# (ops.bend:1059-1060) where the tree this gate reads has dropped the `dtype` one. Both
# facts show up as a NAMED field mismatch on a CALL node rather than as an agreement by
# accident.
def callinfo(ci: O.CallInfo) -> String:
  match ci:
    case O.CallInfo{cname, precompile, precompile_backward, cdtype}:
      String.concat(["cI(", nm(cname), ",", bo(precompile), ",", bo(precompile_backward), ",", dt(cdtype), ")"])

def kernelinfo(ki: O.KernelInfo) -> String:
  match ki:
    case O.KernelInfo{kname, applied_opts, opts_to_apply, beam}:
      String.concat(["kI(", bstr(kname), ",", U32.show(beam), ")"])

def i64s.go(+ys: List<&2, H.I64>, acc: List<&2, String>) -> List<&2, String>:
  match ys:
    case Nil{}: acc
    case y <> r: i64s.go(r, List.append(&2, String, acc, [is64(y)]))

def i64s(ys: List<&2, H.I64>) -> String:
  String.concat(["n(", String.join(i64s.go(ys, Nil{}), ","), ")"])

# `ProgramInfo.global_size` is `tuple[int|float, ...]` (ops.bend:1352) so its elements are
# `H.I64`; the float case is a `sint`'s and is recorded on `sint_of` there, not here.
def prog_info(pi: O.ProgramInfo) -> String:
  match pi:
    case O.ProgramInfo{global_size, local_size, vars, globals, outs, ins}:
      String.concat(["pI(", i64s(global_size), ",", i64s(local_size), ",", us(vars), ",", us(globals), ",", us(outs),
        ",", us(ins), ")"])

# RANGE's arg is `(axis_type, axis_id)` (ops.py:643) and `axis_id` is `self.arg[1:]`
# (ops.py:498-500), so it is EITHER an int or a tuple of ints. `(WEAK, 0, 1)` and
# `(WEAK, (0, 1))` render the same under `str(arg)` and are DIFFERENT ucache keys
# (ops.py:201 keys on `type(arg)`), so the flat text alone would call two different
# graphs equal. `Arena.depth` (ops.bend:1135) is the nesting count the port already
# carries for exactly this, and it is emitted BOTH as its own field and inside the arg,
# so it cannot hide and the arg stays self-describing.
def argstr(a: O.Arg, depth: U32) -> String:
  match a:
    case O.ANone{}: "N"
    case O.ADt{ad}: dt(ad)
    case O.APy{av}: konst(av)
    case O.AParam{pa}: paramarg(pa)
    case O.ACustom{cf}: custom_fn(cf)
    case O.ACall{ci}: callinfo(ci)
    case O.AKernel{ki}: kernelinfo(ki)
    case O.AProgram{pi}: prog_info(pi)
    case O.ARange{ids, at}: String.concat(["rg(", i(depth), ",", O.AxisType.name(at), ",", us(ids), ")"])
    case O.AReduce{rop, num_axes}: String.concat(["rd(", opx(rop), ",", i(num_axes), ")"])
    case O.AWmma{wdims, wdt, threads, tc}: String.concat(["wm(", us(wdims), ",", dt(wdt), ",", U32.show(threads), ",", us(tc), ")"])
    case O.ATuple{ys}: us(ys)
    case O.AStr{s}: bstr(s)
    case O.AInk{ins, idt}: String.concat(["in(", bstr(ins), ",", dt(idt), ")"])
    case O.AAllred{arop, adev}: String.concat(["al(", opx(arop), ",", dev(adev), ")"])
    case O.ADev{dd}: dev(dd)
    # `ABlob` is `bytes`, and ops.bend:913 says "only its length is read" -- there is no
    # byte STRING in the port to compare, so the normal form compares the LENGTH on both
    # sides and the loss is recorded rather than hidden.
    case O.ABlob{n2}: String.concat(["y", U32.show(n2)])
    case O.AFloat{f2}: String.concat(["f", F32.show(f2)])
    # THE BOTTOM. ops.bend:1154 calls this "a read of an index that was never interned".
    # It is not a node, so it must not read as an agreeing one.
    case O.ABad{}: "BAD"

def tagstr(t: O.Tag) -> String:
  match t:
    case O.TNone{}: "N"
    case O.TBool{tb}: bo(tb)
    case O.TStr{s}: bstr(s)
    case O.TInt{ti}: i(ti)
    case O.TTuple{xs}: us(xs)

# ===========================================================================
# THE SHAPE COLUMN. `u.shape` (ops.py:454-456) is `self._shape` or a raise, and `_shape`
# is `None` for the ten ops that have no shape (ops.py:331-338), so the column is
# THREE-valued and all three are distinct: `N` (the op HAS no shape), `R` (`shape`
# raises) and the dims. A dim is a `sint` (ops.py:1925) -- `int|UOp` -- so a symbolic
# dim is `u` and never a number, which is why a symbolic shape cannot silently read as 0.
# A dim is an `H.I64`, so it carries the same `l` prefix every other I64 does: a shape is
# `(l0:4,l0:3)`, NOT `(0:4,0:3)`, because the high word is part of the value.
def dim1(d: O.Sint) -> String:
  match d:
    case O.SU{u2}: "U"
    case O.SI{di}: String.concat(["l", H.i64_text(di)])

def dimlist.go(+ds: List<&2, O.Sint>, acc: List<&2, String>) -> List<&2, String>:
  match ds:
    case Nil{}: acc
    case d <> r: dimlist.go(r, List.append(&2, String, acc, [dim1(d)]))

def dimlist(ds: List<&2, O.Sint>) -> String:
  String.concat(["(", String.join(dimlist.go(ds, Nil{}), ","), ")"])


def shape_str(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> String:
  match m:
    case None{}: "R"
    case Some{None{}}: "N"
    case Some{Some{ds}}: dimlist(ds)

def dt_str(m: Maybe<&2, S.Dt>) -> String:
  match m:
    case Some{d}: dname(d)
    case None{}: "R"

def srcs.go(+ss: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match ss:
    case Nil{}: acc
    case s <> r: srcs.go(r, List.append(&2, String, acc, [i(s)]))

def srclist(+ar: O.Arena, +k: U32) -> String:
  String.concat(["n(", String.join(srcs.go(O.Arena.srcs(ar, k), Nil{}), ","), ")"])

# ONE NODE, EIGHT CHUNKS. The fold table is passed in rather than re-run per node:
# folding twice is two walks of the whole arena per answer, and this file has 18 rows.
# `k` is `+` because it is read six times and every read is a call into the arena; the
# alternative is six defs, one per field, and a field added later would be added to only
# one of them.
def row(+ar: O.Arena, +tb: F.Table, +k: U32) -> String:
  String.concat([chunk(i(k)), " ", chunk(O.Ops.name.of(O.Arena.op(ar, k))), " ",
    chunk(dt_str(F.UOp.dtype(ar, tb, k))), " ", chunk(shape_str(F.UOp.shape(ar, tb, k))), " ",
    chunk(i(O.Arena.depth(ar, k))), " ", chunk(tagstr(O.Arena.tag(ar, k))), " ",
    chunk(argstr(O.Arena.arg(ar, k), O.Arena.depth(ar, k))), " ", chunk(srclist(ar, k))])

def rows.go(+ar: O.Arena, +tb: F.Table, ks: List<&2, U32>) -> IO(Unit):
  match ks:
    case Nil{}: IO.pure(Unit, Unit{})
    case k <> r:
      do IO<Unit>:
        p : Unit <- IO.print(row(ar, tb, k))
        rows.go(ar, tb, r)

# ===========================================================================
# THE GRAPH. `(Tensor.empty(4,3) @ Tensor.empty(3,5)).uop` -- 18 nodes, built node for
# node, LAZY (never realized), because a realized BUFFER carries a device `Buffer` and
# `pyrender` refuses to render one (render.py:159-160) while the port's `buffer` field is
# a P6 allocator slot with no runtime behind it. The lazy graph is the one graph both
# sides can build: it is ALLOC (not BUFFER), CONST, STACK, RESHAPE, PERMUTE, MUL and
# REDUCE, and every one of those is a constructor the port has.
#
# `Tensor.empty(4,3)` is `ALLOC(ParamArg(0, f32, 12, device=<dev>, bind_on_realize=True))`
# and `Tensor.empty(3,5)` is the same at slot 1 / size 15 -- MEASURED by running the
# Python side, not read off a comment, because a wrong slot is a normal form that differs
# only in a slot number and a slot number is exactly the kind of field a differ is
# supposed to be able to miss.
def alloc(slot: U32, size: U32) -> O.ParamArg:
  O.ParamArg{slot, S.single(), Some{size}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, True{}, None{}}

def g_matmul() -> O.Found:
  +a0 = O.UOp.new(O.Arena.empty(), O.OpsALLOC{}, Nil{}, O.AParam{alloc(0, 12)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r43 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +c1 = O.UOp.const(O.Found.ar(r43), O.CInt{H.i64_of_i32(1)})
  +s413 = O.UOp.new(O.Found.ar(c1), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c1), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r413 = O.UOp.new(O.Found.ar(s413), O.OpsRESHAPE{}, [O.Found.i(r43), O.Found.i(s413)], O.ANone{}, O.TNone{})
  +a1 = O.UOp.new(O.Found.ar(r413), O.OpsALLOC{}, Nil{}, O.AParam{alloc(1, 15)}, O.TNone{})
  +c5 = O.UOp.const(O.Found.ar(a1), O.CInt{H.i64_of_i32(5)})
  +s35 = O.UOp.new(O.Found.ar(c5), O.OpsSTACK{}, [O.Found.i(c3), O.Found.i(c5)], O.ANone{}, O.TNone{})
  +r35 = O.UOp.new(O.Found.ar(s35), O.OpsRESHAPE{}, [O.Found.i(a1), O.Found.i(s35)], O.ANone{}, O.TNone{})
  +s135 = O.UOp.new(O.Found.ar(r35), O.OpsSTACK{}, [O.Found.i(c1), O.Found.i(c3), O.Found.i(c5)], O.ANone{}, O.TNone{})
  +r135 = O.UOp.new(O.Found.ar(s135), O.OpsRESHAPE{}, [O.Found.i(r35), O.Found.i(s135)], O.ANone{}, O.TNone{})
  +p021 = O.UOp.new(O.Found.ar(r135), O.OpsPERMUTE{}, [O.Found.i(r135)], O.ATuple{[0, 2, 1]}, O.TNone{})
  +mul = O.UOp.new(O.Found.ar(p021), O.OpsMUL{}, [O.Found.i(r413), O.Found.i(p021)], O.ANone{}, O.TNone{})
  +p201 = O.UOp.new(O.Found.ar(mul), O.OpsPERMUTE{}, [O.Found.i(mul)], O.ATuple{[2, 0, 1]}, O.TNone{})
  O.UOp.new(O.Found.ar(p201), O.OpsREDUCE{}, [O.Found.i(p201)], O.AReduce{O.OpsADD{}, 1}, O.TNone{})

# ONE BEND PROCESS, EVERY NODE. `Arena.next` is `len(nodes)` (ops.bend:1167) and index 0 is
# the bottom (ops.bend:1162), so the live nodes are 1..next-1 and the toposort is read
# only so the OUTPUT is in a stable order -- the differ pairs structurally, so the order
# is for the reader, not for correctness.
def main() -> IO(Unit):
  do IO<Unit>:
    +f : O.Found <- IO.pure(O.Found, g_matmul())
    +x : F.Folded <- IO.pure(F.Folded, F.folded(O.Found.ar(f)))
    h : Unit <- IO.print(String.concat(["# root=", U32.show(O.Found.i(f)), " nodes=",
      U32.show(O.Arena.next(O.Found.ar(f))), " settled=",
      Bool.show(F.Kahn.settled(F.Folded.ar(x), F.Folded.t(x)))]))
    rows.go(F.Folded.ar(x), F.Folded.t(x), O.UOp.toposort(O.Arena.budget(F.Folded.ar(x)), F.Folded.ar(x),
      O.Found.i(f)))