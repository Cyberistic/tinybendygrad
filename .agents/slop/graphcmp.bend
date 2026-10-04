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

def axis1(a: O.AxisType) -> String:
  match a:
    # THE TWO DEAD MEMBERS, MARKED. `78d482262` DELETED `AxisType.REDUCE` and
    # `AxisType.UNROLL` upstream and ops.bend:649-654 keeps them because six committed
    # files still construct them. MEASURED at 3138973dc, calling CPython:
    #   `list(AxisType)` == DEVICE GLOBAL LOCAL WARP WEAK LOOP UPCAST PLACEHOLDER,
    # eight members, and `hasattr(AxisType, "REDUCE") is False`.
    # (The earlier claim in graphcmp-report.md that THREE members were port-only is
    # WRONG -- `PLACEHOLDER` exists here. Two, not three.)
    #
    # WHY MARK THEM. `AxisType.name` answers the bare `"REDUCE"`, which is a name no
    # CPython enum can have -- so a node carrying one would report as ONLY-ON-THE-BEND,
    # which is loud enough today. It would NOT be loud if upstream ever ADDS a `REDUCE`
    # back with different meaning, because then the two would render identically and
    # agree for the wrong reason. `X!` cannot be produced by any other spelling, so the
    # answer to "is this member real?" is in the text rather than in a comment.
    case O.AXIS_REDUCE{}: "X!REDUCE"
    case O.AXIS_UNROLL{}: "X!UNROLL"
    case _: String.concat(["X", O.AxisType.name(a)])

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
# MEASURED 2026-10-03 by CALLING CPython, because the positions had drifted and a citation
# that no longer resolves is worse than none: `Device['CPU'].device == 'CPU'`, reached as
# `_Device.__getitem__` (device.py:29) -> `canonicalize` at :30 -> `_canonicalize` at :26 ->
# `__get_canonicalized_item` at :32 -> `get_class`'s `cls(ix)` at :37 (NOT :29, which is
# the `def`) -> `Compiled.__init__`'s `self.device, ... = device, ...` at :396.
#
# THE THREE TABLES ARE NOT ONE AND MUST NOT BE MERGED. Measured, not assumed:
#   * `uop/render.bend:361`  -- the ARENA tag: 0=CPU 1=GPU 2=METAL ... 8=NULL 9=DISK.
#   * `device.bend:720-732` `dev_name` -- `ALL_DEVICES` (device.py:20) by 1-based
#     index: 1=METAL 2=AMD 3=NV 4=CUDA 5=QCOM 6=CL 7=CPU 8=DSP 9=WEBGPU 11=NULL.
#     It is a faithful port of a DIFFERENT upstream object and its rows use it that way
#     (`too_big(.., String.starts_with(dev_name(7), "NULL"))` is device.py:172's
#     `self.device.startswith("NULL")`, where `self.device` is a BUFFER's, not a graph's).
#   * `renderer/cstyle.bend:121` `dev_name` -- the compiler/LANGUAGE index.
# So the tag column is NOT an index into any of those two, and reading one as the other
# would be a wrong answer rather than a unification. (`ALL_DEVICES` itself is device.py:20
# at this pin; `dev_name` moved 702 -> 720 as rows were added above it, which is why the
# position is cited here freshly rather than carried forward.)
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

# Field 11, the device BUFFER, is PRESENCE and nothing else, and the port's payload is
# NOT an identity: MEASURED on the Python side, `Buffer` has no `slot` attribute at all
# and its repr is `<buf real:False device:CPU size:12 dtype:dtypes.f32>` -- a device
# object, carrying the `dtypes.` token R3 exists to drop and an allocation state. So the
# slot number is dropped here too and both sides answer `z` / `N`.
#
# The size, the dtype and the device of a realized buffer are ALREADY fields 2, 3 and 8
# of this same record and are already compared above, so presence is the finest split the
# two sides can both make; the realized-BUFFER row is the one that exercises it.
def bufo(m: Maybe<&2, U32>) -> String:
  match m:
    case Some{_}: "z"
    case _: "N"

# `str(UOp.argstr)` is `repr(self.arg)` (ops.py:274-276) and `ParamArg.__repr__`
# (ops.py:43-50) OMITS every field equal to its default and spells `buffer` as
# `buffer=UOp.new_buffer(...).buffer`, a device object no second process can rebuild. So
# the normal form is NOT a repr: it is EVERY field, by name, in DECLARATION order
# (ops.py:26-42 for ParamArg), with the device Buffer reduced to its PRESENCE (`z` / `N`)
# because `pyrender` itself refuses to render a BUFFER carrying one (render.py:160) and
# because `Buffer` has no slot to name (MEASURED -- see `bufo`). Field NAMES are the
# format: a positional reader would encode the order and pass a swap, and ops.bend:2432-2440
# records that swapping two shape args leaves op, nsrc and the src sequence identical.
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

# FOUR SLOTS: name, applied_opts, opts_to_apply, beam -- `KernelInfo`'s own fields in
# DECLARATION order (ops.py:1342-1347) minus `estimates`, which ops.bend DROPPED (P5,
# `tinygrad.renderer`) and which is None upstream for every kernel the port can build
# (`uop/render.bend:653` pins the literal for the same reason).
#
# It was TWO here against CPython's THREE, so a SINK could only ever report a
# disagreement that was really "the port renders fewer fields". And `opts_to_apply` was
# dropped on BOTH sides, which is the residual nobody was looking at: upstream WRITES it
# on every `llm/kernels/amd.py` and `nn/__init__.py` SINK as `opts_to_apply=()` -- an
# EMPTY TUPLE, not `None` -- while `KernelInfo.of()` here answers `None` (MEASURED, probe
# `runs/graphcmp/probe/pb-buf-binary.bend` Q1b). Now both sides render it and that
# divergence is a reported one.
#
# THE OPTION LISTS ARE COUNTS, NOT CONTENTS, and that is a refusal rather than a
# comparison. ops.bend:978 types both as `List<&2,U32>`; upstream's elements are `Opt`
# dataclasses (`Opt(op=OptOps.TC, axis=0, arg=4)`, codegen/opt/__init__.py:11). MEASURED:
# `KernelInfo.of().applied_opts` is EMPTY and no port file ever writes a non-empty one,
# so `uop/render.bend:655`'s "UOp INDICES" reading of those U32s is UNVERIFIED -- there
# is no construction site to verify it against. So one `q` per option: the count compares,
# the content is a named refusal, and nothing here copies the port's answer into the
# oracle.
def opts.go(+ys: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match ys:
    case Nil{}: acc
    case _ <> r: opts.go(r, List.append(&2, String, acc, ["q"]))

def opts(ys: List<&2, U32>) -> String:
  String.concat(["n(", String.join(opts.go(ys, Nil{}), ","), ")"])

def optsm(m: Maybe<&2, List<&2, U32>>) -> String:
  match m:
    case Some{x}: opts(x)
    case _: "N"

def kernelinfo(ki: O.KernelInfo) -> String:
  match ki:
    case O.KernelInfo{kname, applied_opts, opts_to_apply, beam}:
      String.concat(["kI(", bstr(kname), ",", opts(applied_opts), ",", optsm(opts_to_apply), ",", i(beam), ")"])

def i64s.go(+ys: List<&2, H.I64>, acc: List<&2, String>) -> List<&2, String>:
  match ys:
    case Nil{}: acc
    case y <> r: i64s.go(r, List.append(&2, String, acc, [is64(y)]))

def i64s(ys: List<&2, H.I64>) -> String:
  String.concat(["n(", String.join(i64s.go(ys, Nil{}), ","), ")"])

def bs.go(+bs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match bs:
    case Nil{}: acc
    case b <> r: bs.go(r, List.append(&2, String, acc, [i(b)]))

def blobstr(bs: List<&2, U32>) -> String:
  String.concat(["y n(", String.join(bs.go(bs, Nil{}), ","), ")"])

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
    case O.ARange{ids, at}: String.concat(["rg(", i(depth), ",", axis1(at), ",", us(ids), ")"])
    case O.AReduce{rop, num_axes}: String.concat(["rd(", opx(rop), ",", i(num_axes), ")"])
    case O.AWmma{wdims, wdt, threads, tc}: String.concat(["wm(", us(wdims), ",", dt(wdt), ",", U32.show(threads), ",", us(tc), ")"])
    case O.ATuple{ys}: us(ys)
    case O.AStr{s}: bstr(s)
    case O.AInk{ins, idt}: String.concat(["in(", bstr(ins), ",", dt(idt), ")"])
    case O.AAllred{arop, adev}: String.concat(["al(", opx(arop), ",", dev(adev), ")"])
    case O.ADev{dd}: dev(dd)
    # `ABlob` is `bytes` and it HOLDS THE BYTES (ops.bend:1062 `ABlob{bs: List<&2, U32>}`
    # -- the 2026-10-03 change from a length, recorded at :1793 with the reason), so the
    # CONTENT is compared and not a summary of it. This arm used to be `U32.show(n2)`
    # over a `n2` field that no longer exists -- which is why the probe stopped compiling
    # when `ops.bend` moved, and the fix is a widening rather than a cast: MEASURED,
    # `eq_arg.ABlob` (:1801) compares `bs` element-wise, so the port can answer the
    # question the column is asking.
    case O.ABlob{bs}: blobstr(bs)
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


# THE SHAPE COLUMN, and a CORRECTION found by adding `--graph sink` (2026-10-03).
#
# `u.shape` (ops.py:454-456) is a PROPERTY that raises `RuntimeError` IFF `_shape is None`,
# so it never RETURNS `None`. MEASURED over every op in the upstream no-shape list (ops.py:
# 331-338: IF BARRIER SINK REWRITE_ERROR ENDIF BACKEDGE GROUP LINEAR PROGRAM SOURCE) plus a
# void `INS` and a `PYLITERAL` -- twelve ops, `_shape is None` AND `shape` raises in all
# twelve (`runs/graphcmp/probe/p9-shape-none.py`). So "the op has no shape" and "shape
# raised" are ONE fact upstream, and the faithful spelling of both is `R`.
#
# This def used to answer `N` for its `Some{None}` arm while answering `R` for its outer
# `None`, and the CPython side answers `N` for a value `shape` cannot return. So the two
# sides were using one letter for two different facts. It stayed invisible until a graph
# with a shape-less node existed: `--graph sink` is the first, and it reported
#   MISMATCH SINK  py#2 vs bend#2  shape py=R bend=N
# -- a rung-1 field mismatch on a node whose CORE MATCHED, which by graphcmp.py's own
# measured theorem cannot mean the graphs differ. It means the two `_shape` implementations
# disagree, and the measurement above says which is wrong.
#
# SO: `Some{None}` (this port knows the op has no shape) is `R`, the same as a raise. The
# outer `None` (the fold produced NO `Derived` for this node) is a PORT-ONLY state with no
# upstream counterpart, and it gets `?` -- a letter no upstream reading can produce, so a
# fold that stops settling reads as a hole rather than as an agreement.
def shape_str(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> String:
  match m:
    case None{}: "?"
    case Some{None{}}: "R"
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

# `matmul_of` TAKES AN ARENA and `g_matmul` supplies an empty one, because `--graph
# binblob` hangs a BINARY off this SAME 18-node graph and must not build it twice: two
# builds are two arenas, the ids do not line up, and the report is then a cascade of
# `src` differences with the cause in none of them.
def matmul_of(+ar: O.Arena) -> O.Found:
  +a0 = O.UOp.new(ar, O.OpsALLOC{}, Nil{}, O.AParam{alloc(0, 12)}, O.TNone{})
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

def g_matmul() -> O.Found:
  matmul_of(O.Arena.empty())

# `--graph range` / `--graph rangeflat`: the pair R5 exists for. `Arena.shp` is the
# RANGE-arg tail's nesting COUNT and `ARange{ids, at}` holds the tail's INTS (ops.bend:2500
# "ARange stores the ints only"), so `(ids, depth)` is the whole representation and there
# is no third field. These are the two readings, and CPython's are MEASURED by calling it
# -- `UOp.range(4, (0,1))` is `arg=(AxisType.WEAK, (0, 1))` and `UOp.range(4, 0)` is
# `arg=(AxisType.WEAK, 0)` -- so `range` carries depth 1 and `rangeflat` carries 0.
def g_range() -> O.Found:
  +c4 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  O.UOp.range_shaped(O.Found.ar(c4), O.Found.i(c4), [0, 1], O.AXIS_WEAK{}, 1)

def g_rangeflat() -> O.Found:
  +c4 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  O.UOp.range_end(O.Found.ar(c4), O.Found.i(c4), [0], O.AXIS_WEAK{})

# `--graph cast`: `Tensor.empty(4,3).cast(dtypes.half).uop`, 6 nodes, MEASURED on the py
# side. It is the ONLY fixture in which a `DType` is the WHOLE arg -- every other `D<name>`
# in the corpus is a `ParamArg` FIELD -- so it is the fixture for graphcmp.bend's
# `case O.ADt{ad}: dt(ad)`, which no other graph reached.
def g_cast() -> O.Found:
  +a0 = O.UOp.new(O.Arena.empty(), O.OpsALLOC{}, Nil{}, O.AParam{alloc(0, 12)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r43 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  O.UOp.new(O.Found.ar(r43), O.OpsCAST{}, [O.Found.i(r43)], O.ADt{S.half()}, O.TNone{})

# `--graph special`: `UOp.special(4, "inf")`, 2 nodes, MEASURED. `AStr` on a node that is
# not a `SINK`, so the bare string atom is separated from `KernelInfo.name`'s use of one.
def g_special() -> O.Found:
  +c4 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  O.UOp.new(O.Found.ar(c4), O.OpsSPECIAL{}, [O.Found.i(c4)], O.AStr{"inf"}, O.TNone{})

# `--graph binblob`: `UOp(Ops.BINARY, (matmul,), b"tiny")`, 19 nodes, MEASURED on the py
# side. It exists so the `y` residual is a NUMBER and not a 0: four graphs shipped with
# `bytes py=0 bend=0`, which is a fact about the fixture and not about the port. The blob
# is `ABlob{bs}` with the BYTES (ops.bend:1062 -- `ABlob{bs: List<&2, U32>}`, which is the
# 2026-10-03 CHANGE from a length) so the port CAN now tell two same-length blobs apart and
# `argstr`'s `y` arm renders the LENGTH, which is the one field of the pair still compared
# only as a count. 116/105/110/121 is `b"tiny"`.
def g_binblob() -> O.Found:
  +r = matmul_of(O.Arena.empty())
  O.UOp.new(O.Found.ar(r), O.OpsBINARY{}, [O.Found.i(r)], O.ABlob{[116, 105, 110, 121]}, O.TNone{})

# `Tensor.empty(4,8).sum(axis=1).uop` -- 7 nodes, MEASURED by running the py side, not
# written from the docstring's expectation. Two facts here are worth stating because both
# are the OPPOSITE of the obvious reading:
#   * the sum's accumulator CONST is NOT in this graph. `sum` lowers to a bare `REDUCE`,
#     so there is no `CONST 0` node to re-type and this graph CANNOT test a CONST dtype;
#     and the two CONSTs that ARE here are the shape's `4` and `8`, both `weakint`, the
#     same as the matmul's. The port spells `weakint` as `S.single()` and it agrees.
#   * the PERMUTE is `(1, 0)` on a `(4,8)` giving `(8,4)`, and the REDUCE collapses axis 0,
#     so the result is `(4,)`.
def g_reduce() -> O.Found:
  +a0 = O.UOp.new(O.Arena.empty(), O.OpsALLOC{}, Nil{}, O.AParam{alloc(0, 32)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c8 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(8)})
  +s48 = O.UOp.new(O.Found.ar(c8), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c8)], O.ANone{}, O.TNone{})
  +r48 = O.UOp.new(O.Found.ar(s48), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s48)], O.ANone{}, O.TNone{})
  +p10 = O.UOp.new(O.Found.ar(r48), O.OpsPERMUTE{}, [O.Found.i(r48)], O.ATuple{[1, 0]}, O.TNone{})
  O.UOp.new(O.Found.ar(p10), O.OpsREDUCE{}, [O.Found.i(p10)], O.AReduce{O.OpsADD{}, 1}, O.TNone{})

# ONE BEND PROCESS, EVERY NODE. `Arena.next` is `len(nodes)` (ops.bend:1167) and index 0 is
# the bottom (ops.bend:1162), so the live nodes are 1..next-1 and the toposort is read
# only so the OUTPUT is in a stable order -- the differ pairs structurally, so the order
# is for the reader, not for correctness.
def rows.of(+ar: O.Arena, +tb: F.Table, +f: O.Found) -> IO(Unit):
  rows.go(ar, tb, O.UOp.toposort(O.Arena.budget(ar), ar, O.Found.i(f)))

# `--graph buffer`: `Tensor.empty(4,3).realize().uop` on the Python side, MEASURED to be
# five nodes -- BUFFER CONST CONST STACK RESHAPE -- and built here node for node.
#
# WHY IT EXISTS. A realized BUFFER is the one `ParamArg` field this normal form cannot
# compare by value, and until now that was only ever a CLAIM: no graph either side emitted
# carried a `buffer`. This graph carries one, so the `z` atom is exercised by a real diff
# rather than asserted by a comment, and the ledger's `z` row is measured instead of 0.
#
# The `buffer` slot number is DELIBERATELY 7 and means nothing (see `bufo`): upstream's
# `Buffer` has no slot at all. The ParamArg's OWN `slot` is 1 and DOES mean something --
# it is `UOp.unique_num` -- and it is 1, not 0, because MEASURED (probe p8-slot.py):
#   `Tensor.empty(4,3)`          -> ALLOC , ParamArg.slot 0
#   `.realize()`                 -> BUFFER, ParamArg.slot 1   <-- A DIFFERENT SLOT
#   `Tensor.empty(3,5)`          -> ALLOC , ParamArg.slot 2
# So realize MINTS A FRESH ParamArg (`UOp.new_buffer`, ops.py:1208 `if slot is None: slot
# = next(UOp.unique_num)`) and a realized buffer's slot is not the ALLOC's. Writing 0 here
# because "it was 0 before the realize" is exactly the reading the measurement forbids.
# `bind_on_realize` is False on a BUFFER and True on an ALLOC -- also measured, also here.
def allocbuf(slot: U32, size: U32, bslot: U32) -> O.ParamArg:
  O.ParamArg{slot, S.single(), Some{size}, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, Some{bslot}, False{}, None{}}

def g_buffer() -> O.Found:
  +b0 = O.UOp.new(O.Arena.empty(), O.OpsBUFFER{}, Nil{}, O.AParam{allocbuf(1, 12, 7)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(b0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(b0), O.Found.i(s43)], O.ANone{}, O.TNone{})

# `--graph sink`: `UOp(Ops.SINK, (UOp.const(4),), KernelInfo())` -- MEASURED to be two
# nodes, CONST and SINK, and it exists to exercise two things no other graph reaches: the
# four-slot `kI(..)` arg, and the `R` shape value (a SINK has no shape -- `UOp.shape`
# raises `RuntimeError` at ops.py:455, so the column is `R`, not `N`).
#
# It is built with `KernelInfo.of()` -- the DEFAULT -- because that is the only value both
# sides can produce, and MEASURED: the port's is `{"test", Nil{}, None{}, 0}`, `opts_to_apply`
# is `None` and `applied_opts` is empty. Upstream's default is the same except that
# `opts_to_apply` is `None` too, so `kI(stest,n(),N,i0)` is the ONE `kI` text both sides
# can agree on. `llm/kernels/amd.py` writes `opts_to_apply=()` (an EMPTY TUPLE, not `None`)
# on every SINK it builds, so a real kernelized graph diverges in that slot -- a reported
# one now, and a reported NOTHING before, because both emitters dropped the field.
def g_sink() -> O.Found:
  +c4 = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(4)})
  O.UOp.new(O.Found.ar(c4), O.OpsSINK{}, [O.Found.i(c4)], O.AKernel{O.KernelInfo.of()}, O.TNone{})

# `rows.pick` is a `Bool.pick` chain: `Bool.pick` CHOOSES an arm, it does not SEQUENCE
# one, so each rung is one more `Bool.pick` and the default is the matmul.
# `+` on the binder because this body READS `name` TWICE (once per rung). `Bool.pick`
# chooses an arm, so at runtime only one read happens, but `String` is linear and bend
# counts the two static reads -- MEASURED: without `+` this is
# "expected : name / observed : name (consumed more than once)" at `rows.pick3`.
def rows.pick3(+name: String) -> O.Found:
  Bool.pick(O.Found, String.eq(name, "binblob"), g_binblob(),
    Bool.pick(O.Found, String.eq(name, "cast"), g_cast(),
      Bool.pick(O.Found, String.eq(name, "range"), g_range(),
        Bool.pick(O.Found, String.eq(name, "rangeflat"), g_rangeflat(),
          Bool.pick(O.Found, String.eq(name, "special"), g_special(),
            Bool.pick(O.Found, String.eq(name, "buffer"), g_buffer(),
              Bool.pick(O.Found, String.eq(name, "sink"), g_sink(),
                Bool.pick(O.Found, String.eq(name, "reduce"), g_reduce(), g_matmul()))))))))

def rows.pick(name: String) -> O.Found:
  # `match` may scrutinise a PARAMETER or a PATTERN binder, never a computed value and not a
  # local binder either (measured: both `match String.eq(..)` and `match <local>` are compile
  # errors), so a CHOICE between two values is `Bool.pick`.
  rows.pick3(name)

# `IO.args()` LEADS WITH THE PROGRAM NAME (symbolic.bend:2614), so the graph name is the
# head of the TAIL and no argument at all is the default rather than an error.
def fz_name(as: List<String>) -> String:
  Maybe.default(&1, String, List.get(&1, String, as, 0n), "")

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    +f : O.Found <- IO.pure(O.Found, rows.pick(fz_name(List.tail(&1, String, as))))
    +x : F.Folded <- IO.pure(F.Folded, F.folded(O.Found.ar(f)))
    h : Unit <- IO.print(String.concat(["# root=", U32.show(O.Found.i(f)), " nodes=",
      U32.show(O.Arena.next(O.Found.ar(f))), " settled=",
      Bool.show(F.Kahn.settled(F.Folded.ar(x), F.Folded.t(x)))]))
    rows.of(F.Folded.ar(x), F.Folded.t(x), f)