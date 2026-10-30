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
import ./../../tinybendygrad/tensor.bend as T
import ./../../tinybendygrad/mixin/movement.bend as MX
# THE THREE MODULES THE `api` GRAPH REACHES BY BEING CALLED INSTEAD OF HAND-BUILT.
# `mixin/creation.bend` is the ALLOC/RESHAPE factory, `mixin/elementwise.bend` is the
# binop and the promotion, and `uop/weak.bend` and `mixin/dtype.bend` are what THEY call.
import ./../../tinybendygrad/mixin/creation.bend as CR
import ./../../tinybendygrad/mixin/elementwise.bend as E

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

# `H.i64_text` is `hi:lo` (helpers.bend:1701-1705), which is why the shape column reads
# `n(0:4,0:3)` rather than `n(4,3)`: a dim is an `H.I64` and dropping the HIGH word would
# read a shape of `2**32` as `0`. It costs four characters per dim and it is the difference
# between an exact column and one that cannot see a large dimension.

# ...AND IT IS UNSIGNED WHERE THE NORMAL FORM IS SIGNED, WHICH NO ROW IN THE CORPUS REACHED
# UNTIL `--graph loop`. CPython's half is `f"{x >> 32}:{x & 0xFFFFFFFF}"` (graphcmp.py:388-393)
# and Python's `>>` on a NEGATIVE int is an ARITHMETIC shift, so its high word is negative;
# `H.i64_text` is `U32.show(hi) ":" U32.show(lo)` and `U32.show` of `0xFFFFFFFF` is
# `4294967295`. MEASURED on the port's own row for the one negative CONST the corpus now has
# (`start * -1`, hcq2.py:78): `l-1:4294967295` on the py side against
# `l4294967295:4294967295` here. The two words are the SAME I64 -- `(2**64 - 1)` is `-1` in
# two's complement -- so the port's VALUE is right and its SPELLING is the other one, and the
# fix belongs in the normal form and not in `helpers.bend`. `hi < 2**31` answers the other
# branch byte-for-byte identically to `U32.show`, so every other row in the corpus is
# untouched -- which is why this sat here: an equality of two renderings that is only an
# equality on the non-negative half of their domain.
# The `.go` split is this file's own idiom for a binder a def needs to READ TWICE
# (`checks` calls it "the `.go`/`.of` split is this one's own trade"), and the compiler
# says so out loud: `Bool.pick(String, H.i32_is_neg(hi), f(hi), g(hi))` on one line is
# "expected : hi / observed : hi (consumed more than once)" at the PARAMETER.
def i64hi.go(neg: Bool, +hi: U32) -> String:
  match neg:
    case True{}: String.concat(["-", U32.show(U32.sub(0, hi))])
    case _: U32.show(hi)

def i64hi(+hi: U32) -> String:
  i64hi.go(H.i32_is_neg(hi), hi)

def is64(+x: H.I64) -> String:
  String.concat(["l", i64hi(H.hi32(x)), ":", U32.show(H.lo32(x))])

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

# `device: str|tuple[str, ...]|None` (ops.py:33), and BOTH sides render the tuple as the
# ONE value it is: `n(` over the comma-joined NAMES, exactly the `n(..)` this file already
# uses for `O.ATuple` and CPython's `_carg` uses for a tuple. It is NOT flattened to
# `sCPU,CPU`: `Dn` is the pair, and the flatten collides on `('CPU',) vs 'CPU'` and on
# `('CPU,CPU',) vs ('CPU','CPU')`, distinctions upstream branches on (PIN ops.py:849,
# :681, :699; spec.py:29, :140) -- ADEV-1. `devs.go` yields `dev1(t)`, which is ALREADY `bstr`'d,
# so this must NOT wrap a second `bstr`: that double prefix printed `ssCPU,sCPU`, a THIRD
# spelling matching neither side (ADEV-2). One value, one renderer.
def devs(ts: List<&2, U32>) -> String:
  String.concat(["n(", String.join(devs.go(ts, Nil{}), ","), ")"])

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

# `movement.py:253` builds the axis arg as `tuple([i in axis_arg for i in range(len(self.shape))])`
# -- a list of BOOLS -- so the port types it `ABoolList{bs: List<&2, Bool>}` (`ops.bend:1217`) and
# `us` above cannot print it: `b1` is not `i1`. This is the `us` twin with `bo` in place of `i`,
# and `bo` is ALREADY this file's `b1`/`b0` renderer, so no spelling is invented here -- only the
# one arm the FLIP's `arg` was missing.
def bos.go(+ys: List<&2, Bool>, acc: List<&2, String>) -> List<&2, String>:
  match ys:
    case Nil{}: acc
    case y <> r: bos.go(r, List.append(&2, String, acc, [bo(y)]))

def bus(ys: List<&2, Bool>) -> String:
  String.concat(["n(", String.join(bos.go(ys, Nil{}), ","), ")"])

# The `n(...)` twin of `mum`: `wmma`'s `tc_upcast_axes` is `None | tuple` (`PIN ops.py:652-654`),
# so absence is `N` and a PRESENT tuple is `n(...)`. `N` and `n()` are different values.
def um(m: Maybe<&2, List<&2, U32>>) -> String:
  match m:
    case Some{x}: us(x)
    case _: "N"

def img2(m: O.Img) -> String:
  match m:
    case O.Img{h, w}: String.concat(["n(", U32.show(h), ",", U32.show(w), ")"])

# `PyRange` is ParamArg's FOURTH field, `vmin_vmax: tuple[int, ...] | None` (ops.py:29), and
# both members are `H.I64`s -- so the column is `r(l0:1,l0:100)` and NOT `r(0:1,0:100)`.
#
# IT WAS THE SECOND ONE, and it is the second measured instance of the same defect in this
# file: `H.i64_text` is only the `hi:lo` PAIR (helpers.bend:1701-1705) and the `l` that
# marks it as an I64 is `is64`'s contribution, one line up. So `rng` formatted a pair and
# forgot the letter. MEASURED by `--graph sym`, the FIRST graph in the corpus with a
# `Some` `vmin_vmax` -- every ParamArg the nine earlier graphs carried had `vmin_vmax=None`,
# so this arm of `mm` had never run and `ParamArg`'s fourth field had never been asked a
# question. Adding `--graph sym` made it `r(0:1,0:100)` against the py side's
# `r(l0:1,l0:100)`, and because `arg` is in the `core` that turned a PARAM into a
# one-sided node and every RESHAPE and the GROUP above it with it -- a four-node cascade
# with the cause in none of them, which is exactly the failure the rung-2/rung-3 design
# exists to prevent and which a LETTER this file already had a def for prevented.
def rng(r: O.PyRange) -> String:
  match r:
    case O.PyRange{lo, hi}: String.concat(["r(", is64(lo), ",", is64(hi), ")"])

def konst(c: O.Const) -> String:
  match c:
    case O.CBool{b}: String.concat(["b", Bool.show(b)])
    # `is64`, NOT `H.i64_text` -- and this arm used to spell the I64 ITSELF, so the two
    # halves of the same column (`dim1`'s shape dims and this) were two renderings and the
    # signed one had to be fixed twice. MEASURED on the one negative CONST the corpus has
    # (`start * -1`, hcq2.py:78): `l-1:4294967295` on the py side, `l4294967295:4294967295`
    # from this arm before. `is64` is the one spelling and it reads the SAME I64.
    case O.CInt{i2}: is64(i2)
    # DEFECT 27, FOUND BY WIDENING (`--graph bw`, 2026-10-04), and this arm is HALF of it.
    # It was `F32.show(f2)`, which is the seven-significant-digit SHORTEST-ROUNDTRIP TEXT of
    # the value -- a `repr` in a structural field, the thing this file exists to forbid -- and
    # `F32.show(1.0)` MEASURES to `1`, so the corpus's first float CONST rendered `f1` here
    # against `fConstFloat(1.0)` on the py side. `F32.bits` is a `law` (base.bend:1701) and
    # MEASURES to the same U32 CPython's `struct.pack('<f', ...)` gives, so BOTH sides spell a
    # float CONST as its IEEE-754 BINARY32 bits and the column becomes EXACT:
    #     F32.bits(1.0) == 1065353216 == struct.unpack('<I', struct.pack('<f', 1.0))[0]
    # It is also the only spelling that separates two different NaNs, which is one of the two
    # distinctions `ConstFloat` documents itself as existing for (dtype.py:12: "distinguishes
    # -0.0 from 0.0 and where nan == nan"). See graphcmp.py's `f32bits` for the py half.
    case O.CFloat{f2}: String.concat(["f", U32.show(F32.bits(f2))])
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
# THE THIRTEEN-TOKEN READER, one `Maybe` per def, because `match` may scrutinise only a
# PARAMETER or a pattern binder and reading a `Maybe` field is a CALL.
#
# THIRTEEN TOKENS AND TWELVE FIELDS, AND THE GAP IS THE MIGRATION. The NORMAL FORM is
# unchanged by 72f98ffe0 -- CPython renders thirteen tokens because `graphcmp.py`'s
# `paramarg(pa, owner)` puts `_size(owner)` at token 2 and reads it off `src[0]`
# (`graphcmp.py:731`, `size_of` at :703) -- so `.of` KEEPS its `size` parameter and it is
# still rendered second. What the move changed is WHERE `paramarg` GETS it: `size` left
# the record (`ops.bend:870` is twelve fields, `slot, dtype, vmin_vmax, ...`), so the
# twelve-field pattern below cannot bind it, and `O.ParamArg.size(ar, self)`
# (`ops.bend:3037`) reaches the owner's `src[0]` instead. THAT is why this def takes the
# arena and the node index: `carg(op, x, owner)` on the CPython side threads the owner
# for exactly this one field, and a def that cannot see the owner cannot see the size.
def paramarg.of(+slot: U32, +dtx: S.Dt, +size: Maybe<&2, U32>, +vmin_vmax: Maybe<&2, O.PyRange>, +multiple_of: Maybe<&2, U32>,
  +name: Maybe<&2, String>, +addrspace: S.Addr, +device: Maybe<&2, S.Dev>, +volatile: Bool, +image: Maybe<&2, O.Img>,
  +buffer: Maybe<&2, U32>, +bind_on_realize: Bool, +val: Maybe<&2, O.Const>) -> String:
  String.concat(["P(", i(slot), ",", dt(dtx), ",", mum(size), ",", mm(vmin_vmax), ",", mum(multiple_of), ",", nm(name),
    ",", addr1(addrspace), ",", dm(device), ",", bo(volatile), ",", imgm(image), ",", bufo(buffer), ","
    bo(bind_on_realize), ",", valm(val), ")"])

def paramarg(+ar: O.Arena, self: U32, pa: O.ParamArg) -> String:
  match pa:
    case O.ParamArg{slot, dtx, vmin_vmax, multiple_of, name, addrspace, device, volatile, image, buffer,
      bind_on_realize, val}:
      paramarg.of(slot, dtx, O.ParamArg.size(ar, self), vmin_vmax, multiple_of, name, addrspace, device, volatile,
        image, buffer, bind_on_realize, val)

def custom_fn(c: O.CustomFunction) -> String:
  match c:
    case O.CustomFunction{cname, cdtype}: String.concat(["cF(", bstr(cname), ",", dt(cdtype), ")"])

# `CallInfo` (ops.py:1392) is NOT a dataclass: a plain class with class-level defaults,
# `grad_fxn` first and `aux` last, and `dtype: DType = dtypes.void` (ops.py:1398). Its
# `__repr__` (ops.py:1394-1397) is `f"CallInfo({gf}, {repr(self.name)}, {self.precompile},
# {self.precompile_backward})"` -- it prints `id(self.grad_fxn)`, a per-process address, and
# it prints the dtype NEVER, not conditionally. The port's record carries the field
# (ops.bend:1114), the FIELD IS LOAD-BEARING (fold.bend:1160 reads a CALL's dtype off
# `CallInfo.dtype`, which is LIMITS.md 2's named divergence from ops.py:130's `src[0]`), and
# the normal form DROPS it -- which is what graphcmp.py's `carg` does too, dropping `grad_fxn`
# and `aux` for the same reason.
#
# THIS ARM USED TO BE CONDITIONAL ON VOID, ON THE CLAIM THAT ops.py:1404 "SUPPRESSES the dtype
# slot when that dtype is void". ops.py:1404 IS THE `precompile_backward` LINE. The claim was
# true of no commit of this tree, and it was invisible for a measured reason and not a lucky
# one: EVERY CALL IN THE CORPUS UNTIL THIS ONE HAD A VOID DTYPE, so both arms printed three
# tokens. MEASURED on all four `cI` rows the py side emits -- `cI(N,b0,b0)` (the anonymous
# `clock_gettime` call, whose body is an `i32` CUSTOM_FUNCTION), two `cI(sdo_get_time_ms,b0,b0)`
# and `cI(shcq_fence,b0,b0)` -- `graphcmp.py`'s arm prints three tokens for the non-void one
# too, and this file printed four. Same shape as the float CONST and the unsigned `hi` above:
# a rendering that agreed with the other side on the half of the domain the corpus had reached.
def callinfo(ci: O.CallInfo) -> String:
  match ci:
    case O.CallInfo{cname, precompile, precompile_backward, cdtype}:
      String.concat(["cI(", nm(cname), ",", bo(precompile), ",", bo(precompile_backward), ")"])

# FOUR SLOTS: name, applied_opts, opts_to_apply, beam -- `KernelInfo`'s own fields in
# DECLARATION order (ops.py:1342-1347) minus `estimates`, which the FORM leaves out
# because the value is None on both sides for every kernel the port can build (the
# port's `do_estimates` is a WALL). MEASURED 2026-10-30: `ops.bend`'s record is
# upstream's SIX fields and `estimates` IS carried -- `Maybe<&2, Estimates>` -- so this
# is a field both sides carry that the form omits, NOT a field the port dropped.
#
# It was TWO here against CPython's THREE, so a SINK could only ever report a
# disagreement that was really "the port renders fewer fields". And `opts_to_apply` was
# dropped on BOTH sides, which is the residual nobody was looking at: upstream WRITES it
# on every `llm/kernels/amd.py` and `nn/__init__.py` SINK as `opts_to_apply=()` -- an
# EMPTY TUPLE, not `None` -- while `KernelInfo.of()` here answers `None` (MEASURED, probe
# `runs/graphcmp/probe/pb-buf-binary.bend` Q1b). Now both sides render it and that
# divergence is a reported one.
#
# THE OPTION LISTS ARE CONTENTS NOW, not counts. ops.bend's `KernelInfo` carries
# `List<&2, OPT>` and `OPT` is the port's own `Opt` (moved down from
# `codegen/opt/postrange.bend` for exactly this); upstream renders it through
# `_carg`'s dataclass arm as `Opt(op=<enum>,axis=<int>,arg=<value>)`, with the
# `name=value` pairs CONCATENATED -- no separators -- and the arg's tuple spelled
# by the generic grammar. So this is that arm, field for field, and the arg's
# three tuple shapes are what CPython has, `OA_SPLIT`'s `top` a `Maybe` because
# upstream's split arg is a 2-tuple `(amt, target)` or a 3-tuple.
def optops(o: O.OPTOPS) -> String:
  match o:
    case O.OPS_TC{}: "EOptOps.TC"
    case O.OPS_SPLIT{}: "EOptOps.SPLIT"
    case O.OPS_PADTO{}: "EOptOps.PADTO"
    case _: "EOptOps.SWAP"

def optarg(a: O.OPTARG) -> String:
  match a:
    case O.OA_NONE{}: "N"
    case O.OA_INT{v}: i(v)
    case O.OA_SPLIT{O.SPL{amt, t, Some{b}}}: String.concat(["n(", i(amt), ",", axis1(t), ",", bo(b), ")"])
    case O.OA_SPLIT{O.SPL{amt, t, None{}}}: String.concat(["n(", i(amt), ",", axis1(t), ")"])
    case O.OA_TC{O.TC{any, sel, lvl, use}}: String.concat(["n(", i(sel), ",", i(lvl), ",", i(use), ")"])

def opt(o: O.OPT) -> String:
  match o:
    case O.OPT{op, axis, arg}:
      String.concat(["Opt(op=", optops(op), "axis=", i(axis), "arg=", optarg(arg), ")"])

def opts.go(+ys: List<&2, O.OPT>, acc: List<&2, String>) -> List<&2, String>:
  match ys:
    case Nil{}: acc
    case o <> r: opts.go(r, List.append(&2, String, acc, [opt(o)]))

def opts(ys: List<&2, O.OPT>) -> String:
  String.concat(["n(", String.join(opts.go(ys, Nil{}), ","), ")"])

def optsm(m: Maybe<&2, List<&2, O.OPT>>) -> String:
  match m:
    case Some{x}: opts(x)
    case _: "N"

def kernelinfo(ki: O.KernelInfo) -> String:
  match ki:
    case O.KernelInfo{kname, applied_opts, opts_to_apply, estimates, beam, optimized}:
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
#
# THE PATTERN IS EXACT-ARITY, AND THE RECORD HAS **SEVEN** FIELDS. MEASURED 2026-10-22:
# the port's `ProgramInfo` gained `target: H.Target` as its seventh field, and this
# driver still bound SIX, so **THE CORPUS's OWN DRIVER DID NOT COMPILE** and all 34
# graphs were REFUSED -- with the compile error named in `D1-verdicts.txt`. **A BEND
# RECORD PATTERN IS EXACT-ARITY, SO ADDING A FIELD TO A RECORD IS A BREAKING CHANGE IN
# EVERY FILE THAT PATTERNS IT**, and the same change had to be followed in the port's
# own eight patterns and in the realize census's.
#
# AND **THIS LANE IS DEAD, AND IT IS DEAD IN BOTH SIDES.** MEASURED 2026-10-22: the
# corpus's 34 graphs produce **ZERO** `pI(` rows -- the port's artefacts carry none, and
# the oracle's only `pI(` match in its own output is a COMMENT naming the form. So the
# third component below is **NOT EXERCISED AT ALL**, and the corpus cannot see the
# `vars` -> `params` RENAME (`9974c9d9b` / upstream `a6addc2d4`) -- which is a REAL port
# change, because upstream's `params` is **EVERY** param, sorted by slot, where the old
# `vars` was the **ALU-ONLY** list. **THE PORT'S THIRD FIELD IS THE PIN's `params` AND
# THE ORACLE's BRANCH READS `x.vars`, WHICH THE LIVE UPSTREAM DOES NOT HAVE** (measured:
# `hasattr(pi, "vars")` is **False** and `hasattr(pi, "params")` is **True** at the pin)
# -- so that branch is STALE CODE THAT WOULD RAISE IF A GRAPH EVER REACHED IT.
#
# **SO THE ARITY FIX ABOVE WAS NECESSARY (the driver did not compile) AND THE THIRD
# COMPONENT'S SEMANTICS WAS A NAMED DEBT, NOT A GREEN LIGHT.** A graph whose PROGRAM
# carries a BUFFER param would make the two lists differ, and NO SUCH GRAPH EXISTED --
# until `g_prog`, below, which is one.
#
# ###########################################################################
# THE DEBT IS PAID (2026-10-22). `--graph prog` IS A GRAPH WHOSE PROGRAM CARRIES THREE
# BUFFER PARAMS, AND THE THIRD COMPONENT IS NO LONGER A NAMED DEBT.
#
# **THE THIRD COMPONENT IS THE params' FULL `P(...)` RECORDS, AND NOT THEIR SLOT NUMBERS.**
# The port's `ProgramInfo.params` is `List<&2, U32>` of ARENA INDICES (`ops.bend:1042`),
# so the port can only print the SLOTS by looking each node up -- and a slot list would
# have been a ROW THAT COULD NOT GO RED: for a kernel whose params are all buffers,
# `params`' slots and `globals`' slots are THE SAME LIST, so the third component would
# have been a RESTATEMENT of the fourth. **THE FULL `P(...)` RECORD CARRIES WHAT THE SLOT
# LIST CANNOT** -- the ADDRSPACE (`SGLOBAL` against `SALU`), the dtype, the size, the
# device and the name -- and **THE ADDRSPACE IS THE WHO POINT**: upstream's old `vars`
# was the ALU-ONLY list and its `params` is EVERY param (`a6addc2d4`), so the third
# component is where the corpus can SEE that a BUFFER param is in the list at all.
#
# **AND THE `P(...)` SPELLING IS THE CORPUS's OWN**, not a new one: `paramarg` above
# already renders a `ParamArg` in thirteen fields in declaration order, and it is already
# what every PARAM NODE's own `arg` column prints. So the third component is the SAME
# text the graph's own PARAM rows carry, and it is a CROSS-CHECK of the list against the
# nodes rather than a second grammar.
#
# **THE SEVENTH FIELD, `target`, IS NOT IN THE FORM, AND THE LEDGER SAYS SO.**
# `graphcmp.py`'s `ledger_lines` prints a row for it on EVERY report, with the
# measurement: the value is the RENDERER's and its `arch` is the MACHINE's
# (`Device["CPU"].renderer.target` has `arch='arm64,native'` on this machine and
# `ClangCompiler(target.arch.split(","))` compiles for it), so carrying it would make
# the canonical form machine-specific and this file would have to hard-code this
# machine's arch. **THE `pI(` FORM IS A PROPERTY OF THE GRAPH; THE TARGET IS A PROPERTY
# OF THE DEVICE.** The port's `from_sink` still TAKES a target -- `H.Target.of()` -- and
# the port's record still HOLDS it; the FORM just does not print it.
def pparam.of(a: O.Arg, +ar: O.Arena, k: U32) -> String:
  match a:
    case O.AParam{pa}: paramarg(ar, k, pa)
    # THE ARM IS UNREACHABLE BY CONSTRUCTION: the port's `from_sink` appends a node to
    # `params` only when that node's op is `OpsPARAM` (`fs.param.put`), and a PARAM's
    # arg IS an `AParam`. It is spelled rather than left out because a `match` here must
    # be exhaustive, and `N` -- the corpus's absence atom -- reads as "this node has no
    # ParamArg", which is a fact and not a silent agreement.
    case _: "N"

def pparam(+ar: O.Arena, +k: U32) -> String:
  pparam.of(O.Arena.arg(ar, k), ar, k)

def pparam.go(+ar: O.Arena, +ys: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match ys:
    case Nil{}: acc
    case y <> r: pparam.go(ar, r, List.append(&2, String, acc, [pparam(ar, y)]))

def pparams(+ar: O.Arena, ys: List<&2, U32>) -> String:
  String.concat(["n(", String.join(pparam.go(ar, ys, Nil{}), ","), ")"])

def prog_info(+ar: O.Arena, pi: O.ProgramInfo) -> String:
  match pi:
    case O.ProgramInfo{global_size, local_size, params, globals, outs, ins, _tgt}:
      String.concat(["pI(", i64s(global_size), ",", i64s(local_size), ",", pparams(ar, params), ",", us(globals), ",", us(outs),
        ",", us(ins), ")"])

# RANGE's arg is `(axis_type, axis_id)` (ops.py:643) and `axis_id` is `self.arg[1:]`
# (ops.py:498-500), so it is EITHER an int or a tuple of ints. `(WEAK, 0, 1)` and
# `(WEAK, (0, 1))` render the same under `str(arg)` and are DIFFERENT ucache keys
# (ops.py:201 keys on `type(arg)`), so the flat text alone would call two different
# graphs equal. `Arena.depth` (ops.bend:1135) is the nesting count the port already
# carries for exactly this, and it is emitted BOTH as its own field and inside the arg,
# so it cannot hide and the arg stays self-describing.
def argstr(+ar: O.Arena, self: U32, a: O.Arg, depth: U32) -> String:
  match a:
    case O.ANone{}: "N"
    case O.ADt{ad}: dt(ad)
    case O.APy{av}: konst(av)
    case O.AParam{pa}: paramarg(ar, self, pa)
    case O.ACustom{cf}: custom_fn(cf)
    case O.ACall{ci}: callinfo(ci)
    case O.AKernel{ki}: kernelinfo(ki)
    case O.AProgram{pi}: prog_info(ar, pi)
    case O.ARange{ids, at}: String.concat(["rg(", i(depth), ",", axis1(at), ",", us(ids), ")"])
    case O.AReduce{rop, num_axes}: String.concat(["rd(", opx(rop), ",", i(num_axes), ")"])
    # THE MISSING TWENTIETH. `AOpLit` (ops.bend:1079) holds a BARE `Op` -- the `arg` of a
    # `PYLITERAL` is `upat.py:26`'s `self.op[0]` -- so this is the ATOM `opx` already emits
    # and NOT a composite opener: `AReduce`/`AAllred` print `rd(`/`al(` because they hold an
    # `Op` AND pair it, and this one does not. MEASURED, the text is already agreed on the
    # CPython side without a new atom: `ATOMS["ops"]` is `"O"` (graphcmp.py:324) and
    # `_carg`'s `isinstance(x, Ops)` arm (graphcmp.py:603) returns `ATOMS["ops"] + x.name`,
    # so `gc._carg(Ops.INDEX)` is `"OINDEX"` -- byte-identical to what `opx` builds here.
    # That is why this arm RESTORES A SYMMETRY rather than inventing a spelling: the py side
    # could print this value and the bend side had no arm for it, so the file did not check
    # and the port emitted NO ROWS FOR ANY GRAPH AT ALL (`not-comparable=16` meant "never
    # ran", not "disagreed").
    #
    # WHAT IT DOES NOT CLOSE, stated here because an arm that looks finished is the place a
    # reader stops. `upat.py` mints SEVEN `PYLITERAL`s and this arm covers ONE of them:
    # `:26` passes a bare `Ops`, and `:25` / `:36` / `:43` pass a `frozenset` while `:39` /
    # `:44` pass a bare `DType` / `AddrSpace` and `:29` passes `self.arg` whole. The port
    # types only the `:26` one, and the multi-op `UPat((Ops.INDEX, Ops.SHRINK), ...)` form
    # behind `:25` is common in this tree. So `PYLITERAL` remains a PORT GAP in its own
    # right, DISTINCT from the CORPUS GAP that no graph mints one at all -- two different
    # gaps, and the second does not cancel the first.
    #
    # AND THE ARM IS NOT OPTIONAL, WHICH IS THE PART THAT SETTLES "GIVE IT AN ARM OR DELETE
    # `AOpLit`". MEASURED by taking the deletion: it does not compile, because `AOpLit` is
    # spelled in THREE files -- `ops.bend` (the constructor at :1079, `eq_arg.AOpLit` at
    # :1866, the dispatch arm at :1965), `render.bend:714` (`arg_repr`), and this file's
    # `argstr`. Deleting the constructor means deleting all seven sites in a file this work
    # does not own, to REMOVE a payload no graph in the corpus emits (MEASURED: zero rows
    # carry `PYLITERAL` on either side, so the deletion cannot change one byte of output).
    # One arm in one file this work does own is the whole of the difference.
    case O.AOpLit{op}: opx(op)
    case O.AWmma{wdims, wdt, threads, tc}: String.concat(["wm(", us(wdims), ",", dt(wdt), ",", i(threads), ",", um(tc), ")"])
    case O.ATuple{ys}: us(ys)
    case O.ABoolList{bs}: bus(bs)
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
    case O.AInt{n}: i(n)
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

# `dt_str`'s UNSETTLED ARM IS `?` AND NOT `R`, and that is a fix found by `--graph sym`.
#
# `R` is the FAITHFUL rendering of an upstream raise, and `dtype_from_uop` (ops.py:123-190)
# is TOTAL over `Ops` -- it names a dtype for every member and its only failure modes are
# a `raise RuntimeError` on a malformed arg. So on the py side the dtype column is always a
# real name, and `R` there could never mean anything. On this side `F.UOp.dtype` answers
# `None` for a node the fold never settled, and it was rendering that `R` -- the SAME
# letter as `shape_str`'s no-shape case, for a state that is not upstream's.
#
# TWO COLLISIONS IN ONE LETTER, which is what `?` exists for: `shape_str` already had the
# port-only state (`None` = the fold produced no `Derived`), so the dtype column was using
# one letter for two facts while the shape column used two letters for two facts. The
# rule the whole ledger rests on is that a letter is ONE fact, so `dt_str`'s `None` is `?`
# too, and `?` is now registered against BOTH fields in graphcmp.py's LEDGER.
#
# MEASURED, and the change is a widening rather than a retune: no graph in the corpus
# before `sym` emitted `dt_str(None)` at all (every one of the nine earlier graphs settles
# completely -- the probe header printed `settled=True` for all of them), so nothing that
# used to read `R` reads `?` now.
def dt_str(m: Maybe<&2, S.Dt>) -> String:
  match m:
    case Some{d}: dname(d)
    case None{}: "?"

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
    chunk(argstr(ar, k, O.Arena.arg(ar, k), O.Arena.depth(ar, k))), " ", chunk(srclist(ar, k))])

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
def alloc(slot: U32) -> O.ParamArg:
  O.ParamArg{slot, S.single(), None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, True{}, None{}}

# `matmul_of` TAKES AN ARENA and `g_matmul` supplies an empty one, because `--graph
# binblob` hangs a BINARY off this SAME 18-node graph and must not build it twice: two
# builds are two arenas, the ids do not line up, and the report is then a cascade of
# `src` differences with the cause in none of them.
def matmul_of(+ar: O.Arena) -> O.Found:
  +a0 = O.UOp.new.param(ar, O.OpsALLOC{}, Some{12}, O.AParam{alloc(0)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r43 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +c1 = O.UOp.const(O.Found.ar(r43), O.CInt{H.i64_of_i32(1)})
  +s413 = O.UOp.new(O.Found.ar(c1), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c1), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r413 = O.UOp.new(O.Found.ar(s413), O.OpsRESHAPE{}, [O.Found.i(r43), O.Found.i(s413)], O.ANone{}, O.TNone{})
  +a1 = O.UOp.new.param(O.Found.ar(r413), O.OpsALLOC{}, Some{15}, O.AParam{alloc(1)}, O.TNone{})
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
  +a0 = O.UOp.new.param(O.Arena.empty(), O.OpsALLOC{}, Some{12}, O.AParam{alloc(0)}, O.TNone{})
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
  +a0 = O.UOp.new.param(O.Arena.empty(), O.OpsALLOC{}, Some{32}, O.AParam{alloc(0)}, O.TNone{})
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
def allocbuf(slot: U32, bslot: U32) -> O.ParamArg:
  O.ParamArg{slot, S.single(), None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, Some{bslot}, False{}, None{}}

def g_buffer() -> O.Found:
  +b0 = O.UOp.new.param(O.Arena.empty(), O.OpsBUFFER{}, Some{12}, O.AParam{allocbuf(1, 7)}, O.TNone{})
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

# ===========================================================================
# THE FOUR WIDENING GRAPHS (2026-10-04, second pass). Every count, every shape and every
# `arg` below is the CPython side's OWN output, read off
# `emit --side py --graph NAME` and not written from prose -- see the graph table in
# graphcmp.py's header and `runs/graphcmp/D/D1-graph-*.txt`.
#
# WHAT THEY ARE FOR, in the order the limits file asked for them:
#   group    GROUP -- the op that makes a linearized program a GRAPH rather than a tree,
#            and with it the first node in the corpus with more than one parent.
#   commute  SEVEN of the eight commutative ops, so `--equiv` stops being measured on one.
#   indexed  PARAM / INDEX / BARRIER -- the ops that make a program a PROGRAM, and the
#            first non-WEAK axis type in the corpus.
#   sym      a SYMBOLIC dim, twice and DIFFERENTLY -- which measures a limit that was
#            untested, and disagrees on purpose (see `g_sym`).
#
# THE CONST shape STACK IS BUILT BY HAND in three of the four rather than by a helper,
# because `alloc`/`const`/`new` are the only spellings and the ids are load-bearing: the
# arena indices are the toposort positions, so a node built in a different ORDER is a
# different file even though it is the same graph.

# `--graph group`: `UOp.group(sh + sh, sh * sh)`, MEASURED at 8 nodes with the op sequence
# ALLOC CONST CONST STACK RESHAPE ADD MUL GROUP. THE POINT IS THE FAN-IN: `ADD` and `MUL`
# both take `sh`, so `RESHAPE` has TWO parents and `CONST 4` has TWO as well, and each of
# ADD/MUL carries the SAME child index TWICE (`src=n(i5,i5)`). No graph in the corpus
# before this one had any node with more than one parent, so the differ had never placed
# one -- and a differ that only ever saw trees cannot be said to handle a DAG.
#
# **THE CENSUS ABOVE IS AGAINST A SCHEMA THAT NO LONGER EXISTS, AND IT WAS THE FALSE CLAIM
# THAT BROKE THIS DRIVER.** The paragraph it came from read "`UOp.group` is
# `UOp(Ops.GROUP, src=..., **kwargs)` with no arg, ops.py:558-560, and `hasattr(group,
# 'params')` is `False`" -- so this body hand-built `O.OpsGROUP{}`, and upstream `900880433`
# DELETED that constructor. `bin/bend graphcmp.bend --check-only` then answered
# `SOME PROOFS FAIL`, `expected : a declared constructor (... ops.Op declares ... 75 ...)`.
# Upstream REIMPLEMENTED `UOp.group` as `UOp(Ops.STACK).after(*srcs)` (`ops.py:536-538`), so
# the root is now `AFTER` over a BARE `STACK` and the op sequence is
# `STACK ALLOC CONST CONST STACK RESHAPE ADD MUL AFTER`. MEASURED 2026-10-18, py side:
# 10 rows, and `gates/groupflip-gate.py` answers PASS on 11 rows / 0 divergences, so the
# PORT's `UOp.group` already matches. **THE FIX IS TO CALL `O.UOp.group`, THE WAY CPYTHON
# CALLS `UOp.group`, NOT TO SPELL THE NEW NODES OUT BY HAND** -- a hand-written
# `STACK`+`AFTER` would stop testing the port's implementation and start testing my typing.
# The per-graph node counts in the comments below are the same kind of stale census; the
# AUTHORITATIVE, machine-regenerated ones are the `OPS REACHED` rows in
# `runs/graphcmp/D/D1-graph-*.txt`, written by this run.
def g_group() -> O.Found:
  +a0 = O.UOp.new.param(O.Arena.empty(), O.OpsALLOC{}, Some{12}, O.AParam{alloc(0)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r43 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +add = O.UOp.new(O.Found.ar(r43), O.OpsADD{}, [O.Found.i(r43), O.Found.i(r43)], O.ANone{}, O.TNone{})
  +mul = O.UOp.new(O.Found.ar(add), O.OpsMUL{}, [O.Found.i(r43), O.Found.i(r43)], O.ANone{}, O.TNone{})
  O.UOp.group(O.Found.ar(mul), [O.Found.i(add), O.Found.i(mul)])

# `--graph commute`: `UOp.group(a+b, a!=b, a.maximum(b), a&b, a|b, a^b)`, MEASURED at 14
# nodes. SIX commutative ops in one graph, each a single elementwise node over the SAME
# two RESHAPEs -- so each RESHAPE has SIX parents, the widest fan-in in the corpus, and the
# six ops are the ones `GroupOp.Commutative` names that an eager graph can reach.
#
# THE OP NAMES ARE CPython's, MEASURED op by op (`runs/graphcmp/probe/p15-comm.py`), and
# the port's spelling is `O.OpsADD{}` and so on. Two of the six carry a fact worth
# recording rather than re-deriving:
#   * `CMPNE`'s dtype is `bool`, which is the `CMPLT|CMPNE|CMPEQ -> dtypes.bool` arm of
#     `dtype_from_uop` (ops.py:157-158) and the only bool-dtype node the corpus carried
#     before `range`; and its shape is the broadcast of the two srcs, so it also exercises
#     `broadcast_shape` on two equal shapes.
#   * `AND`/`OR`/`XOR` are `f32` here, not ints: MEASURED, `a ^ b` on two f32 ALLOCs emits
#     an `XOR` node with dtype `f32` (`promo_dtype` of f32 and f32), so the port's
#     `promo` path answers f32 and not "the bitwise dtype".
def g_commute() -> O.Found:
  +a0 = O.UOp.new.param(O.Arena.empty(), O.OpsALLOC{}, Some{12}, O.AParam{alloc(0)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +ra = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +a1 = O.UOp.new.param(O.Found.ar(ra), O.OpsALLOC{}, Some{12}, O.AParam{alloc(1)}, O.TNone{})
  +rb = O.UOp.new(O.Found.ar(a1), O.OpsRESHAPE{}, [O.Found.i(a1), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +add = O.UOp.new(O.Found.ar(rb), O.OpsADD{}, [O.Found.i(ra), O.Found.i(rb)], O.ANone{}, O.TNone{})
  +ne = O.UOp.new(O.Found.ar(add), O.OpsCMPNE{}, [O.Found.i(ra), O.Found.i(rb)], O.ANone{}, O.TNone{})
  +mx = O.UOp.new(O.Found.ar(ne), O.OpsMAX{}, [O.Found.i(ra), O.Found.i(rb)], O.ANone{}, O.TNone{})
  +an = O.UOp.new(O.Found.ar(mx), O.OpsAND{}, [O.Found.i(ra), O.Found.i(rb)], O.ANone{}, O.TNone{})
  +orr = O.UOp.new(O.Found.ar(an), O.OpsOR{}, [O.Found.i(ra), O.Found.i(rb)], O.ANone{}, O.TNone{})
  +xo = O.UOp.new(O.Found.ar(orr), O.OpsXOR{}, [O.Found.i(ra), O.Found.i(rb)], O.ANone{}, O.TNone{})
  O.UOp.group(O.Found.ar(xo), [O.Found.i(add), O.Found.i(ne), O.Found.i(mx),
    O.Found.i(an), O.Found.i(orr), O.Found.i(xo)])

# `UOp.param(0, dtypes.float, 8, device="CPU", name="p0")` -- `ops.py:1235-1239`'s
# `UOp.param`, MEASURED: `ParamArg(slot=0, dtype=f32, size=8, name='p0', device='CPU')`
# and everything else at its default. `bind_on_realize` is FALSE on a PARAM (it is the
# ALLOC's flag, and `g_buffer` measures that reading already) and the buffer slot is
# absent, so `bufo` answers `N`.
def paramf(slot: U32, nm: String) -> O.ParamArg:
  O.ParamArg{slot, S.single(), None{}, None{}, Some{nm}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, False{}, None{}}

# `--graph indexed`: `UOp.sink(p.index(UOp.const(0)).barrier(UOp.range(UOp.const(4), 0,
# AxisType.LOOP)), arg=KernelInfo())`, MEASURED at 7 nodes: PARAM CONST INDEX CONST RANGE
# BARRIER SINK.
#
# THREE FACTS THAT ARE NOT THE OBVIOUS READING, all from the py side's own rows:
#   * `INDEX`'s dtype is `f32` and its shape is `()`. `ops.py:143-146` returns
#     `dtypes.float` only when `src[0]` is a PARAM whose shape `is_image_shape`, and
#     returns `b.dtype` otherwise -- so the image arm is NOT taken here and this graph is
#     the fixture for the plain arm. The shape is `tuple()` because `index_ds` builds
#     `src[1:]`'s shapes and then `src[0].shape[1:]`, and `PARAM`'s shape is `(8,)` so
#     its tail past the first dim is empty.
#   * `BARRIER` is `void` with NO shape (`ops.py:334`), so its column is `R` -- the second
#     graph to make `R` live and the first where `R` is neither the root nor a SINK.
#   * the RANGE carries `AxisType.LOOP`, so `XLOOP` is the first non-`WEAK` axis atom in
#     the corpus. `WEAK` is what `range`/`rangeflat` already cover; reusing it here would
#     have looked like coverage and been none.
def g_indexed() -> O.Found:
  +p0 = O.UOp.new.param(O.Arena.empty(), O.OpsPARAM{}, Some{8}, O.AParam{paramf(0, "p0")}, O.TNone{})
  +c0 = O.UOp.const(O.Found.ar(p0), O.CInt{H.i64_of_i32(0)})
  +ix = O.UOp.new(O.Found.ar(c0), O.OpsINDEX{}, [O.Found.i(p0), O.Found.i(c0)], O.ANone{}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(ix), O.CInt{H.i64_of_i32(4)})
  +r = O.UOp.range_end(O.Found.ar(c4), O.Found.i(c4), [0], O.AXIS_LOOP{})
  +bar = O.UOp.new(O.Found.ar(r), O.OpsBARRIER{}, [O.Found.i(ix), O.Found.i(r)], O.ANone{}, O.TNone{})
  O.UOp.new(O.Found.ar(bar), O.OpsSINK{}, [O.Found.i(bar)], O.AKernel{O.KernelInfo.of()}, O.TNone{})

# A scalar ALU PARAM with a value range and NO size -- `UOp.variable(name, 1, 100)`
# (ops.py:1014-1018) with the SLOT SPELLED as 0. The spelling is the whole comment, and it
# belongs HERE as well as on the py side: the port's `ParamArg.slot` is a `U32`
# (ops.bend:871), so Python's `-1` has no port spelling, and the tree has TWO conflicting
# sentinels -- `schedule/__init__.bend:1100` writes 0 and says "The slot is `None` in
# Python's `-1`; nothing in this file reads a slot, so it is 0 here", while
# `uop/ops.bend:3566` calls any slot but 0/1 "the free Variable sentinel" and uses
# `4294967295` for its own absent case. 0 is the one a committed port fixture already
# writes, so it is the one used here; the DISAGREEMENT between the two is reported and not
# reconciled.
#
# `vmin_vmax=(1, 100)` and `multiple_of=1` are `PyRange`/`Some{1}`, `addrspace=ALU` is
# `S.Aalu{}`, and `dtype=weakint` is `S.weakint()` (spec.bend:720) -- MEASURED off the py
# side's own row `P(i0,Dweakint,N,r(l0:1,l0:100),i1,sn,SALU,N,b0,N,N,b0,N)`.
def var(nm: String) -> O.ParamArg:
  O.ParamArg{0, S.weakint(), Some{O.PyRange{H.i64_of_i32(1), H.i64_of_i32(100)}}, Some{1},
    Some{nm}, S.Aalu{}, None{}, False{}, None{}, None{}, False{}, None{}}

# `--graph sym`: `UOp.group(RESHAPE(a, STACK(n, CONST 4)), RESHAPE(a, STACK(m, CONST 4)))`,
# MEASURED at 12 nodes, and THIS GRAPH IS EXPECTED TO DISAGREE. That is its job.
#
# WHY. `uop/fold.bend`'s `marg.of` answers `None{}` -- upstream's `(ssimplify(self),)`
# arm, the `ssimplify` wall -- for a STACK element that is not a CONST, because
# `marg.step`'s `case None{}` clears the `ok` flag; and `shape_str` above spells that
# `None` as `?`. So the port's two RESHAPEs answer `?` where CPython answers `(U,l0:4)`,
# ON MATCHING CORES. By graphcmp.py's own measured theorem a rung-1 field mismatch cannot
# mean "the graphs differ": it means the two `_shape` IMPLEMENTATIONS disagree. So the
# report names `shape` on exactly 2 of 12 nodes and every other column agrees -- which is
# the strongest form this finding can take, and it makes the `?` ledger marker live for
# the first time. `fold.bend:6180` already records the same wall ("nothing in this tree
# can mint one" -- `O.SU` has a constructor and NO caller); this graph is that claim with
# a denominator on it.
#
# THE OTHER HALF IS WHAT THE DIFFER CAN DO, and it is the answer to the symbolic-dim
# limit. The two RESHAPEs' `shape` columns are IDENTICAL (`(U,l0:4)` both) -- so the shape
# field cannot separate them -- but their `arg`/`src` columns do, through ParamArg's sixth
# field (`sn` against `sm`, ops.py:32) and through the STACK's child cores. So `U` is a
# hole in the SHAPE COLUMN alone and not in the differ's identity, and
# `graphcmp.py`'s `conf` measures exactly that (CONFLATION 4).
def g_sym() -> O.Found:
  +a0 = O.UOp.new.param(O.Arena.empty(), O.OpsALLOC{}, Some{12}, O.AParam{alloc(0)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +a1 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +pn = O.UOp.new.param(O.Found.ar(a1), O.OpsPARAM{}, None{}, O.AParam{var("n")}, O.TNone{})
  +sn = O.UOp.new(O.Found.ar(pn), O.OpsSTACK{}, [O.Found.i(pn), O.Found.i(c4)], O.ANone{}, O.TNone{})
  +rn = O.UOp.new(O.Found.ar(sn), O.OpsRESHAPE{}, [O.Found.i(a1), O.Found.i(sn)], O.ANone{}, O.TNone{})
  +pm = O.UOp.new.param(O.Found.ar(rn), O.OpsPARAM{}, None{}, O.AParam{var("m")}, O.TNone{})
  +sm = O.UOp.new(O.Found.ar(pm), O.OpsSTACK{}, [O.Found.i(pm), O.Found.i(c4)], O.ANone{}, O.TNone{})
  +rm = O.UOp.new(O.Found.ar(sm), O.OpsRESHAPE{}, [O.Found.i(a1), O.Found.i(sm)], O.ANone{}, O.TNone{})
  O.UOp.group(O.Found.ar(rm), [O.Found.i(rn), O.Found.i(rm)])

# A PARAM of an arbitrary dtype, volatility and NAME, for the three PROGRAM graphs below.
# `paramf` above is the f32/no-volatility/always-named case and is left alone: it is what
# `g_indexed` and `g_sym` are measured against, and a widened spelling of it would move
# those two fixtures' bytes. `loop` needs `u64` and a volatile PARAM; `lin` needs three
# UNNAMED f32 PARAMs; `gate` needs one named and one unnamed.
def paramd(slot: U32, dtx: S.Dt, nm: Maybe<&2, String>, vol: Bool) -> O.ParamArg:
  O.ParamArg{slot, dtx, None{}, None{}, nm, S.AGlobal{}, Some{S.D1{0}},
    vol, None{}, None{}, False{}, None{}}

# ===========================================================================
# THE THREE PROGRAM GRAPHS (third pass, 2026-10-04). The THIRTEEN above are all VALUES --
# the eager Tensor API, or ops spelled by hand here -- and `graphcmp-LIMITS.md`'s first
# line said so: "These are hand-built graphs, not a kernelized program, and they exercise
# not one of INDEX/BARRIER/GROUP/ENDIF/BACKEDGE/LOAD/STORE." INDEX/BARRIER/GROUP have since
# been reached by hand. THE REMAINING FOUR CANNOT BE, because they are properties of a
# SCHEDULE rather than of an expression, and they arrive here as the OTHER SIDE of three
# graphs whose PY side is a call into tinygrad's own scheduler and codegen.
#
# WHAT THAT MEANS FOR COST, stated where the cost is rather than in a report:
# `tinybendygrad/schedule/__init__.bend` ports only `__init__.py:14-80` and DEFERS `:82-301`
# ("every rule is a `graph_rewrite` over the arena with a PYTHON ctx DICT"), so THE PORT
# CANNOT BUILD A SCHEDULE AT ALL. These three graphs are therefore hand-built HERE too --
# exactly as the other thirteen are -- and what changed is that the PY side stopped being
# hand-built. The bend side's cost is 84 new nodes; the py side's cost was three pipelines
# the corpus had never run.
#
# `LIN`: `full_rewrite_to_sink` of a scheduled `(4,3)@(3,5)` matmul -- **50** nodes, MEASURED
#        off the py side's own rows in `runs/graphcmp/D/D1-graph-lin.txt` on 2026-10-18. The
#        `46` this said was the FIXTURE's count (49, before the `AFTER` below landed) filed as
#        the oracle's -- the same disease as the stale `34`/`77` prose elsewhere in this tree.
#        The first graph here that is a KERNEL. Its LOADs and its STORE are the two ops
#        thirteen graphs of eager IR could not reach, because an eager graph has no memory
#        traffic in it.
# `LOOP`: `hcq_fence` (tinygrad/runtime/support/hcq2.py:405-413) -- **this arm models 25 of
#        CPython's 52 rows** and the only place in this tree that mints a BACKEDGE outside a
#        hand-written fixture: the `.backedge(loop, done < target)` at :411 is a POLL LOOP.
#        THE GAP IS THREE `@uopfunc` CALL BODIES (`do_get_time_ms` twice, `clock_gettime`
#        once), which is 27 rows and 3 of CPython's 4 `CALL` nodes. **IT IS A DECLARED
#        PARTIAL MODEL AND NOT A COMPARISON**, and `graphcmp.py`'s `cmd_diff` says so on
#        stdout with the counts measured off the two row sets rather than written here.
# `GATE`: a gated STORE through the real `pm_linearize_cleanups` -- 15 nodes, root `LINEAR`,
#        and the only route to `Ops.IF`/`Ops.ENDIF` in this tree (codegen/__init__.py:403).
#        The `14` this said was the row count before the size CONST became a named line of
#        the LINEAR below; CPython's LINEAR carries FOURTEEN srcs and this one now does too.

# A weakint CONST of an i32 value, which is every shape literal in `lin`: the py side's rows
# read `CONST weakint l0:4` followed by `CAST i32 Di32`, because `full_rewrite_to_sink`'s
# `sym`/`pm_simplify_ranges` pass turns each range bound into a CAST of a weakint literal.
# The two are separate nodes and the corpus measures that rather than assuming it.
def g_lin() -> O.Found:
  +p0 = O.UOp.new.param(O.Arena.empty(), O.OpsPARAM{}, Some{20}, O.AParam{paramd(0, S.single(), None{}, False{})}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(p0), O.CInt{H.i64_of_i32(4)})
  +c4i = O.UOp.new(O.Found.ar(c4), O.OpsCAST{}, [O.Found.i(c4)], O.ADt{S.int32()}, O.TNone{})
  +ra = O.UOp.range_end(O.Found.ar(c4i), O.Found.i(c4i), [1], O.AXIS_WEAK{})
  +c5 = O.UOp.const(O.Found.ar(ra), O.CInt{H.i64_of_i32(5)})
  +c5i = O.UOp.new(O.Found.ar(c5), O.OpsCAST{}, [O.Found.i(c5)], O.ADt{S.int32()}, O.TNone{})
  +off = O.UOp.new(O.Found.ar(c5i), O.OpsMUL{}, [O.Found.i(ra), O.Found.i(c5i)], O.ANone{}, O.TNone{})
  # A SPLIT RANGE HAS TWO SRCS AND AN INT AXIS ID. MEASURED on the py side's own row 8:
  # `RANGE i32 () depth=i0 rg(i0,XWEAK,n(i2)) src=n(i6,i4)` -- so `src` is
  # `(bound_const, the_range_being_split)` while `arg` is `(WEAK, 2)` with `axis_id` the INT
  # 2, i.e. `depth` 0 and a ONE-element flat tail. `range_end` cannot build it (it takes one
  # src), so it is a bare `UOp.new` with `ARange{[2]}`. MEASURED THE COST OF GUESSING: the
  # first spelling was `range_end(..., [2, 1], WEAK)`, which read `rg(i0,XWEAK,n(i2,i1))`
  # against `rg(i0,XWEAK,n(i2))` with ONE src against two -- and because `arg` is in the
  # `core` that made the node one-sided, and the eight nodes above it moved with it.
  # THE SPLIT RANGE'S BOUND IS AN `AFTER`, NOT THE CAST. `pm_simplify_ranges` rewrites a range
  # bound into `AFTER(bound, prev_range)` and the RANGE then hangs off THAT, so CPython's row
  # pair is `AFTER i32 src=n(i7,i5)` then `RANGE i32 rg(..) src=n(i9)` -- TWO nodes with the
  # RANGE carrying ONE src. This fixture built the RANGE with the two srcs DIRECTLY, which is
  # ONE node and read `RANGE ... src=n(i7,i5)`: 49 rows against CPython's 50. MEASURED on both
  # sides' own rows (`runs/graphcmp/D/D2-cmp-lin.txt`), and the port is right either way --
  # `UOp.range_end` (`ops.bend:3104`) takes `(ar, end, ids, at)` and has no spelling for an
  # intermediate AFTER, so the node is built here with `UOp.new`, which is what every other
  # hand-built op in this file does. IT GOES BELOW `c5i`, not above it: `AFTER` names its
  # bound, and a node that names one which does not exist yet leaves the fold unsettled and
  # the emitter prints TWO rows (`settled=False`), which is the shape this file's own
  # `# root=... settled=` header exists to make visible.
  +af = O.UOp.new(O.Found.ar(off), O.OpsAFTER{}, [O.Found.i(c5i), O.Found.i(ra)], O.ANone{}, O.TNone{})
  +rb = O.UOp.new(O.Found.ar(af), O.OpsRANGE{}, [O.Found.i(af)], O.ARange{[2], O.AXIS_WEAK{}}, O.TNone{})
  +of1 = O.UOp.new(O.Found.ar(rb), O.OpsADD{}, [O.Found.i(off), O.Found.i(rb)], O.ANone{}, O.TNone{})
  +ix0 = O.UOp.new(O.Found.ar(of1), O.OpsINDEX{}, [O.Found.i(p0), O.Found.i(of1)], O.ANone{}, O.TNone{})
  +p1 = O.UOp.new.param(O.Found.ar(ix0), O.OpsPARAM{}, Some{12}, O.AParam{paramd(1, S.single(), None{}, False{})}, O.TNone{})
  +c3 = O.UOp.const(O.Found.ar(p1), O.CInt{H.i64_of_i32(3)})
  +c3i = O.UOp.new(O.Found.ar(c3), O.OpsCAST{}, [O.Found.i(c3)], O.ADt{S.int32()}, O.TNone{})
  +ia = O.UOp.new(O.Found.ar(c3i), O.OpsMUL{}, [O.Found.i(ra), O.Found.i(c3i)], O.ANone{}, O.TNone{})
  +ix1 = O.UOp.new(O.Found.ar(ia), O.OpsINDEX{}, [O.Found.i(p1), O.Found.i(ia)], O.ANone{}, O.TNone{})
  +ld0 = O.UOp.new(O.Found.ar(ix1), O.OpsLOAD{}, [O.Found.i(ix1)], O.ANone{}, O.TNone{})
  +p2 = O.UOp.new.param(O.Found.ar(ld0), O.OpsPARAM{}, Some{15}, O.AParam{paramd(2, S.single(), None{}, False{})}, O.TNone{})
  +ix2 = O.UOp.new(O.Found.ar(p2), O.OpsINDEX{}, [O.Found.i(p2), O.Found.i(rb)], O.ANone{}, O.TNone{})
  +ld1 = O.UOp.new(O.Found.ar(ix2), O.OpsLOAD{}, [O.Found.i(ix2)], O.ANone{}, O.TNone{})
  +m0 = O.UOp.new(O.Found.ar(ld1), O.OpsMUL{}, [O.Found.i(ld0), O.Found.i(ld1)], O.ANone{}, O.TNone{})
  +c1 = O.UOp.const(O.Found.ar(m0), O.CInt{H.i64_of_i32(1)})
  +c1i = O.UOp.new(O.Found.ar(c1), O.OpsCAST{}, [O.Found.i(c1)], O.ADt{S.int32()}, O.TNone{})
  +ia2 = O.UOp.new(O.Found.ar(c1i), O.OpsADD{}, [O.Found.i(ia), O.Found.i(c1i)], O.ANone{}, O.TNone{})
  +ix3 = O.UOp.new(O.Found.ar(ia2), O.OpsINDEX{}, [O.Found.i(p1), O.Found.i(ia2)], O.ANone{}, O.TNone{})
  +ld2 = O.UOp.new(O.Found.ar(ix3), O.OpsLOAD{}, [O.Found.i(ix3)], O.ANone{}, O.TNone{})
  +ob = O.UOp.new(O.Found.ar(ld2), O.OpsADD{}, [O.Found.i(rb), O.Found.i(c5i)], O.ANone{}, O.TNone{})
  +ix4 = O.UOp.new(O.Found.ar(ob), O.OpsINDEX{}, [O.Found.i(p2), O.Found.i(ob)], O.ANone{}, O.TNone{})
  +ld3 = O.UOp.new(O.Found.ar(ix4), O.OpsLOAD{}, [O.Found.i(ix4)], O.ANone{}, O.TNone{})
  +m1 = O.UOp.new(O.Found.ar(ld3), O.OpsMUL{}, [O.Found.i(ld2), O.Found.i(ld3)], O.ANone{}, O.TNone{})
  +a0 = O.UOp.new(O.Found.ar(m1), O.OpsADD{}, [O.Found.i(m0), O.Found.i(m1)], O.ANone{}, O.TNone{})
  +c2 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(2)})
  +c2i = O.UOp.new(O.Found.ar(c2), O.OpsCAST{}, [O.Found.i(c2)], O.ADt{S.int32()}, O.TNone{})
  +ia3 = O.UOp.new(O.Found.ar(c2i), O.OpsADD{}, [O.Found.i(ia), O.Found.i(c2i)], O.ANone{}, O.TNone{})
  +ix5 = O.UOp.new(O.Found.ar(ia3), O.OpsINDEX{}, [O.Found.i(p1), O.Found.i(ia3)], O.ANone{}, O.TNone{})
  +ld4 = O.UOp.new(O.Found.ar(ix5), O.OpsLOAD{}, [O.Found.i(ix5)], O.ANone{}, O.TNone{})
  +c10 = O.UOp.const(O.Found.ar(ld4), O.CInt{H.i64_of_i32(10)})
  +c10i = O.UOp.new(O.Found.ar(c10), O.OpsCAST{}, [O.Found.i(c10)], O.ADt{S.int32()}, O.TNone{})
  +ob2 = O.UOp.new(O.Found.ar(c10i), O.OpsADD{}, [O.Found.i(rb), O.Found.i(c10i)], O.ANone{}, O.TNone{})
  +ix6 = O.UOp.new(O.Found.ar(ob2), O.OpsINDEX{}, [O.Found.i(p2), O.Found.i(ob2)], O.ANone{}, O.TNone{})
  +ld5 = O.UOp.new(O.Found.ar(ix6), O.OpsLOAD{}, [O.Found.i(ix6)], O.ANone{}, O.TNone{})
  +m2 = O.UOp.new(O.Found.ar(ld5), O.OpsMUL{}, [O.Found.i(ld4), O.Found.i(ld5)], O.ANone{}, O.TNone{})
  +a1 = O.UOp.new(O.Found.ar(m2), O.OpsADD{}, [O.Found.i(a0), O.Found.i(m2)], O.ANone{}, O.TNone{})
  +st = O.UOp.new(O.Found.ar(a1), O.OpsSTORE{}, [O.Found.i(ix0), O.Found.i(a1)], O.ANone{}, O.TNone{})
  +e1 = O.UOp.new(O.Found.ar(st), O.OpsEND{}, [O.Found.i(st), O.Found.i(rb)], O.ANone{}, O.TNone{})
  +e0 = O.UOp.new(O.Found.ar(e1), O.OpsEND{}, [O.Found.i(e1), O.Found.i(ra)], O.ANone{}, O.TNone{})
  # THE SINK'S ARG. `applied_opts` is the ONE `Opt` the py side really carries --
  # `Opt(OptOps.SPLIT, axis=2, arg=(0, AxisType.UPCAST))` from `heuristic.py:109`
  # -- spelled with the port's own `O.OPT` (ops.bend) and rendered by `opt` above.
  # The axis is the SECOND split rng's index; the arg is the 2-tuple, so `top` is
  # `None{}` and not `Some{False{}}`. This is the node `lin`'s disagreement was in.
  # THE SINK CARRIES NO TAG. CPython's own row for it reads `1:N` in the tag column
  # (`runs/graphcmp/D/D2-canon-py-lin.txt`, the last row) because `full_rewrite_to_sink`
  # builds `UOp(Ops.SINK, src=(x,), arg=KernelInfo(...))` with no `tag=`. This arm spelled it
  # `O.TInt{1}`, which renders `i1` -- a field difference the differ pairs on and which made
  # `lin` DISAGREE for a reason that is the FIXTURE and not the port. Found while fixing the
  # split range two stanzas up, and it is the same defect: a hand-built node that does not
  # match the row it is supposed to model.
  O.UOp.new(O.Found.ar(e0), O.OpsSINK{}, [O.Found.i(e0)],
    O.AKernel{O.KernelInfo{"r_4_5_3",
      [O.OPT{O.OPS_SPLIT{}, 2, O.OA_SPLIT{O.SPL{0, O.AXIS_UPCAST{}, None{}}}}], None{}, None{}, 0, False{}}}, O.TNone{})

# ===========================================================================
# `--graph prog`: THE FIRST `PROGRAM` IN THE CORPUS, and the first graph whose
# `ProgramInfo` is compared at all.
#
# **WHAT IT IS.** The `lin` kernel -- the SAME fifty nodes, byte for byte -- with ONE
# more node on top: a `PROGRAM` whose arg is a `ProgramInfo`. **THE PORT DOES NOT WRITE
# THE `ProgramInfo` BY HAND: IT CALLS THE PORT'S OWN `ProgramInfo.from_sink`**
# (`tinybendygrad/uop/ops.bend:9250`), which is the function that carries the
# `vars` -> `params` RENAME (`9974c9d9b`). So the comparison is **the port's `from_sink`
# against upstream's `from_sink`**, and not a hand-written literal against upstream's.
# **THE PY SIDE CALLS UPSTREAM's OWN `from_sink` TOO** (`graphcmp.py`'s `g_prog`), over
# the SAME sink the SAME way, so the two sides differ in nothing but the implementation.
#
# **WHY A BUFFER PARAM, AND WHY THAT IS THE POINT.** Upstream's `from_sink` collects
# EVERY `Ops.PARAM` in the sink (`if u.op is Ops.PARAM: _params.append(u)`) and the
# matmul kernel's three params ARE the three BUFFERS -- the output 4x5 (20 elements),
# the left 4x3 (12) and the right 3x5 (15) -- each with `addrspace == AddrSpace.GLOBAL`.
# **THE OLD `vars` WAS THE ALU-ONLY LIST** (`a6addc2d4` changed
# `if u.op is Ops.PARAM and u.addrspace == AddrSpace.ALU` to `if u.op is Ops.PARAM`), so
# this graph's `vars` would have been **EMPTY** and its `params` is all three buffers.
# **THE CORPUS COULD NOT SEE THAT RENAME, BECAUSE NO GRAPH IN IT WAS A `PROGRAM` AT
# ALL** -- MEASURED 2026-10-22, the 34 graphs produced ZERO `pI(` rows, and the oracle's
# own arm read `x.vars`, which does not exist at the pin, so it would have RAISED the
# moment a graph reached it. **A DEAD ARM AND A STALE ARM ARE THE SAME DEFECT SEEN FROM
# TWO SIDES.**
#
# **THE `Maybe` IS THE PORT's OWN REFUSAL, AND IT IS NOT SILENT.** The port's
# `from_sink` answers `None` for a sink whose LAUNCH SIZE is not a CONST (`fs.sp.val`
# cannot hold a symbolic size, and upstream's own `cast(int, ...)` is a lie there), and
# the `None` arm below DROPS the `PROGRAM` node -- so the corpus reports the node as
# ONLY-PY and the reader sees that the port could not build a `ProgramInfo` at all,
# rather than seeing an empty list and reading it as an answer. **IT IS UNREACHABLE FOR
# THIS FIXTURE**: the `lin` sink has no `SPECIAL` at all (MEASURED, its census is
# `END=2 LOAD=6 STORE=1 INDEX=7 RANGE=2 PARAM=3 AFTER=1 MUL=3 SINK=1` and no SPECIAL),
# and the port's size fold only visits a SPECIAL.
def g_prog.of(m: Maybe<&2, O.ProgramInfo>, +lin: O.Found) -> O.Found:
  match m:
    case Some{pi}:
      O.UOp.new(O.Found.ar(lin), O.OpsPROGRAM{}, [O.Found.i(lin)], O.AProgram{pi}, O.TNone{})
    case None{}:
      # THE REFUSAL, AND IT IS LOUD: NO `PROGRAM` NODE AT ALL, so the differ reports it
      # as ONLY-PY and the `pI(` row is absent on this side rather than WRONG.
      lin

def g_prog() -> O.Found:
  +lin = g_lin()
  g_prog.of(O.ProgramInfo.from_sink(O.Found.ar(lin), O.Found.i(lin), H.Target.of()), lin)

# `--graph loop`: `hcq_fence(tv, tv, 0)`, tinygrad's OWN HCQ2 fence kernel, reached by CALLING
# it (`graphcmp.py:1266-1272`). **FIFTY-TWO NODES, ALL FIFTY-TWO BUILT**, node for node, in
# TOPOSORT ORDER -- which is also BUILD order, so the arena index of each node IS its toposort
# position IS the `i<k>` both sides print. `runs/graphcmp/D/D2-canon-py-loop.txt` is the
# specification (52 rows; re-emitted live and byte-identical 2026-10-18T18:50:20Z), and the
# census this block has to reproduce is `CONST=8 INDEX=8 AFTER=7 CALL=4 PARAM=4 BUFFER=3
# ADD=2 CMPLT=2 LOAD=2 MUL=2 SINK=2 AND=1 BACKEDGE=1 CAST=1 CUSTOM_FUNCTION=1 FLOORDIV=1
# NOOP=1 RANGE=1 STORE=1`.
#
# WHAT THE PREVIOUS 25-NODE FIXTURE MODELLED, AND THE THREE WRONG THINGS BESIDES THE 27 IT
# DID NOT MODEL. It modelled `hcq_fence`'s OWN loop body and replaced `get_time_ms` with an
# INVENTED store-and-reload counter (a `tv` PARAM that py does not have, an `i32` CAST, a
# second STORE). So it was wrong in three ways its own comment asserted were right:
#   * THE TWO OUTLINED PARAMs WERE SPELLED BACKWARDS. This block gave `slots` slot 0
#     unvolatile and `tl` slot 1 VOLATILE; py's rows i2/i3 give `tl` slot 1 VOLATILE and
#     `slots` slot 0 unvolatile -- the NAMES are what the differ pairs on, and the old
#     block had `slots` where py has `tl`. `uopfunc`'s own `param(i, n, a)` (ops.py:1318)
#     numbers `enumerate(ins.items())`, so `slots` is 0 and `tl` is 1, and only `tl` is
#     `replace`d with `volatile=True` by hcq2.py:74.
#   * THE OUTER CALL HAD FOUR SRCS (`[sk, p3, p3, p3]`) WHERE py's i52 HAS THREE. `ins` is
#     a DICT with TWO entries (`slots`, `tl`) and both hold the SAME `tv`, so
#     `f.call(*ins.values())` (ops.py:1325) is the body and `tv` twice: `n(i50,i51,i51)`.
#   * THE CALLER'S PARAM WAS NAMED `tv` HERE AND IS UNNAMED IN py's i51 -- `_storage`
#     (graphcmp.py:1088) passes no `name`, and `uopfunc` renumbers only the body's own
#     params.
# The 27 it did not model are, KIND BY KIND, `CUSTOM_FUNCTION` 1 (i13), `CALL` 3 (i17, i29,
# i40), `BUFFER` 3 REG-addrspace placeholders (i8, i12, i38), `PARAM` 2 of them addrspace
# `REG` (i9) / slot 3 (i51), `FLOORDIV` 1 (i24), `CONST` 6 new values (i11,i14,i20,i23,i43,
# i46), `INDEX` 4 (i10,i16,i19,i22), `CAST` 1 (i15), `MUL` 1 (i44), `ADD` 1 (i45), `AND` 1
# (i48), `CMPLT` 1 (i47), `AFTER` 6 (i18,i28,i30,i32,i39,i41) -- and they are NOT exotic:
# they are `@uopfunc`'s `do_get_time_ms` body (hcq2.py:65-69) and `get_time_ms` (hcq2.py:70),
# which the old fixture replaced rather than mirrored.
def regd(slot: U32, nm: Maybe<&2, String>) -> O.ParamArg:
  # `AddrSpace.REG` placeholders and params, which is the ONLY addrspace in this graph with
  # NO device: `UOp.placeholder`'s `assert device is None, "LOCAL and REG placeholders
  # cannot have a device"` (ops.py:1201) is what puts `N` in the device column of i8/i9/i12/
  # i38, and `dm` above is what prints the same `N` the py side's `paramarg` prints. It is
  # the ONLY reason `device_verdict`'s `ONE-SIDE-DEVICE-LESS` used to fire on this graph:
  # py carried four `N`s in that column and the bend side carried none.
  O.ParamArg{slot, S.uint64(), None{}, None{}, nm, S.AReg{}, None{}, False{}, None{}, None{},
    False{}, None{}}

def g_loop() -> O.Found:
  +ar = O.Arena.empty()
  # 1. CONST weakint 1 -- `shape_to_shape_arg((1,))` for every size-1 PARAM/BUFFER, interned.
  # Minted FIRST and explicitly, because `UOp.new.param` below reaches the SAME node through
  # the SAME arena (ops.bend:3036 -> :2998 `shape_to_shape_arg.of`), so this is the index
  # every one of them gets and therefore the `i1` py's row prints as the shape's dim.
  +c1 = O.UOp.const(ar, O.CInt{H.i64_of_i32(1)})
  # 2. `uopfunc`'s `param(1, "tl", tv)`: slot 1, name `tl`, VOLATILE (hcq2.py:74 replaces
  # the arg with `volatile=True`). 3. `param(0, "slots", tv)`: slot 0, name `slots`, not
  # volatile. Both are GLOBAL on CPU and both are size 1.
  +ptl = O.UOp.new.param(O.Found.ar(c1), O.OpsPARAM{}, Some{1},
    O.AParam{O.ParamArg{1, S.uint64(), None{}, None{}, Some{"tl"}, S.AGlobal{}, Some{S.D1{0}},
      True{}, None{}, None{}, False{}, None{}}}, O.TNone{})
  +psl = O.UOp.new.param(O.Found.ar(ptl), O.OpsPARAM{}, Some{1},
    O.AParam{O.ParamArg{0, S.uint64(), None{}, None{}, Some{"slots"}, S.AGlobal{}, Some{S.D1{0}},
      False{}, None{}, None{}, False{}, None{}}}, O.TNone{})
  # 4-6. `target = slots.index(0).load()` (hcq2.py:76).
  +c0 = O.UOp.const(O.Found.ar(psl), O.CInt{H.i64_of_i32(0)})
  +ix0 = O.UOp.new(O.Found.ar(c0), O.OpsINDEX{}, [O.Found.i(psl), O.Found.i(c0)], O.ANone{}, O.TNone{})
  +ld0 = O.UOp.new(O.Found.ar(ix0), O.OpsLOAD{}, [O.Found.i(ix0)], O.ANone{}, O.TNone{})
  # 7. `UOp(Ops.NOOP)` -- the loop's own NOOP, which is void and shapeless (`R`).
  +np = O.UOp.new(O.Found.ar(ld0), O.OpsNOOP{}, Nil{}, O.ANone{}, O.TNone{})
  # 8. `ms = UOp.placeholder((1,), dtypes.u64, addrspace=AddrSpace.REG)` (hcq2.py:70) ->
  #    `UOp._buffer(1, u64, slot, addrspace=REG)` -> a BUFFER with the size CONST as its only
  #    src. `pm_renumber_slots` (ops.py:1913) gave it slot 0; the SECOND one (i38) got 2.
  +ms1 = O.UOp.new.param(O.Found.ar(np), O.OpsBUFFER{}, Some{1}, O.AParam{regd(0, None{})}, O.TNone{})
  # 9. `do_get_time_ms` is ITSELF `@uopfunc`, so `outlined` mints `param(0, "ms", <arg>)`
  #    (ops.py:1318) -- the name and the addrspace are read off the ARGUMENT (`ms.after(dep)`
  #    inherits `AddrSpace.REG` from the placeholder) and the device is None for the reason
  #    `regd` states. This is a PARAM where i8 is a BUFFER, and they are two nodes.
  +pms = O.UOp.new.param(O.Found.ar(ms1), O.OpsPARAM{}, Some{1}, O.AParam{regd(0, Some{"ms"})}, O.TNone{})
  +ix1 = O.UOp.new(O.Found.ar(pms), O.OpsINDEX{}, [O.Found.i(pms), O.Found.i(c0)], O.ANone{}, O.TNone{})
  # 11-12. `ts = UOp.placeholder((2,), dtypes.u64, addrspace=AddrSpace.REG)` (hcq2.py:67).
  # The size CONST 2 is minted by `UOp.new.param`'s own `shape_to_shape_arg`, so it takes the
  # arena index py's row i11 has and the BUFFER the index py's row i12 has -- which is why
  # i8's CONST 1 is spelled out three stanzas up and this one is not.
  +ts = O.UOp.new.param(O.Found.ar(ix1), O.OpsBUFFER{}, Some{2}, O.AParam{regd(0, None{})}, O.TNone{})
  # 13. `UOp.custom_function("clock_gettime", dtype=dtypes.i32)` (hcq2.py:68) -- src=() and the
  #     port's own `O.UOp.custom_function` (ops.bend:5519) is the only route to the node.
  +cf = O.UOp.custom_function(O.Found.ar(ts), "clock_gettime", Nil{}, S.int32())
  # 14-15. `UOp.const(time.CLOCK_MONOTONIC, dtypes.i32)` -- a weakint CONST and a forced
  #     `CAST` to i32, because `UOp.const(b, dtype)` is `UOp.const(b, weakint).cast(dtype)`
  #     and a CAST to `weakint` FOLDS (ops.py:611-613). `CLOCK_MONOTONIC` is 6 ON DARWIN,
  #     which is the machine the rows were emitted on; that is a fact about this host and
  #     not about the port, and it is why the CONST is spelled as the number.
  +c6 = O.UOp.const(O.Found.ar(cf), O.CInt{H.i64_of_i32(6)})
  +c6i = O.UOp.new(O.Found.ar(c6), O.OpsCAST{}, [O.Found.i(c6)], O.ADt{S.int32()}, O.TNone{})
  # 16-17. `...call(UOp.const(...), ts.index(0))` (hcq2.py:68) -- an ANONYMOUS call, so
  #     `CallInfo.name` is None and `callinfo` prints `cI(N,b0,b0)`.
  +ix2 = O.UOp.new(O.Found.ar(c6i), O.OpsINDEX{}, [O.Found.i(ts), O.Found.i(c0)], O.ANone{}, O.TNone{})
  +cl = O.UOp.new(O.Found.ar(ix2), O.OpsCALL{}, [O.Found.i(cf), O.Found.i(c6i), O.Found.i(ix2)],
    O.ACall{O.CallInfo{None{}, False{}, False{}, S.int32()}}, O.TNone{})
  # 18-27. The rest of `do_get_time_ms`: `ts = ts.after(...)`, then
  #     `ms.index(0).store(ts[0] * 1000 + ts[1] // 1000000).sink()` (hcq2.py:68-69). The
  #     STORE'S LEFT IS i10 -- the outlined PARAM -- not the placeholder, which is upstream's
  #     own substitution and not a fixture choice. `CallInfo.cdtype` is `S.int32()` because
  #     the port reads a CALL's dtype off the ARG (fold.bend:1160) where CPython reads it off
  #     `src[0]` (ops.py:130); the two agree here only because `src[0]` IS i32, and the
  #     divergence itself is LIMITS.md 2's, already named.
  +af0 = O.UOp.new(O.Found.ar(cl), O.OpsAFTER{}, [O.Found.i(ts), O.Found.i(cl)], O.ANone{}, O.TNone{})
  +ix3 = O.UOp.new(O.Found.ar(af0), O.OpsINDEX{}, [O.Found.i(af0), O.Found.i(c0)], O.ANone{}, O.TNone{})
  +c1000 = O.UOp.const(O.Found.ar(ix3), O.CInt{H.i64_of_i32(1000)})
  +ml0 = O.UOp.new(O.Found.ar(c1000), O.OpsMUL{}, [O.Found.i(ix3), O.Found.i(c1000)], O.ANone{}, O.TNone{})
  +ix4 = O.UOp.new(O.Found.ar(ml0), O.OpsINDEX{}, [O.Found.i(af0), O.Found.i(c1)], O.ANone{}, O.TNone{})
  +c1e6 = O.UOp.const(O.Found.ar(ix4), O.CInt{H.i64_of_i32(1000000)})
  +fd = O.UOp.new(O.Found.ar(c1e6), O.OpsFLOORDIV{}, [O.Found.i(ix4), O.Found.i(c1e6)], O.ANone{}, O.TNone{})
  +ad0 = O.UOp.new(O.Found.ar(fd), O.OpsADD{}, [O.Found.i(ml0), O.Found.i(fd)], O.ANone{}, O.TNone{})
  +st0 = O.UOp.new(O.Found.ar(ad0), O.OpsSTORE{}, [O.Found.i(ix1), O.Found.i(ad0)], O.ANone{}, O.TNone{})
  +sk0 = O.UOp.new(O.Found.ar(st0), O.OpsSINK{}, [O.Found.i(st0)], O.ANone{}, O.TNone{})
  # 28-31. `get_time_ms(target)` = `ms.after(do_get_time_ms(ms.after(dep)))[0]` (hcq2.py:70)
  #     -- ms.after(dep) is built FIRST and is the CALL's src[1], and the two `do_get_time_ms`
  #     CALLS (i29, i40) share ONE body (i27) because it is the same UOp twice.
  +af1 = O.UOp.new(O.Found.ar(sk0), O.OpsAFTER{}, [O.Found.i(ms1), O.Found.i(ld0)], O.ANone{}, O.TNone{})
  +cl1 = O.UOp.new(O.Found.ar(af1), O.OpsCALL{}, [O.Found.i(sk0), O.Found.i(af1)],
    O.ACall{O.CallInfo{Some{"do_get_time_ms"}, False{}, False{}, S.void()}}, O.TNone{})
  +af2 = O.UOp.new(O.Found.ar(cl1), O.OpsAFTER{}, [O.Found.i(ms1), O.Found.i(cl1)], O.ANone{}, O.TNone{})
  +ix5 = O.UOp.new(O.Found.ar(af2), O.OpsINDEX{}, [O.Found.i(af2), O.Found.i(c0)], O.ANone{}, O.TNone{})
  # 32-33. `UOp.range(UOp(Ops.NOOP).after(start:=get_time_ms(...)), next(UOp.unique_num),
  #     dtype=dtypes.void)` (hcq2.py:76). TWO facts here, both measured on the py rows: the
  #     bound is the AFTER and the RANGE carries ONE src (the OLD fixture hung the RANGE off
  #     the NOOP directly, which is the same class of error `g_lin`'s split-range stanza
  #     documents), and the axis id is 1 -- `pm_renumber_slots` (ops.py:1912) walks the REG
  #     BUFFERs first, so `next(ctx)` reaches the RANGE at 1, not 0.
  +af3 = O.UOp.new(O.Found.ar(ix5), O.OpsAFTER{}, [O.Found.i(np), O.Found.i(ix5)], O.ANone{}, O.TNone{})
  +rg = O.UOp.range_end(O.Found.ar(af3), O.Found.i(af3), [1], O.AXIS_WEAK{})
  # 34-37. `done = tl.after(target, loop).index(0).load()` and `done < target`.
  +af4 = O.UOp.new(O.Found.ar(rg), O.OpsAFTER{}, [O.Found.i(ptl), O.Found.i(ld0), O.Found.i(rg)], O.ANone{}, O.TNone{})
  +ix6 = O.UOp.new(O.Found.ar(af4), O.OpsINDEX{}, [O.Found.i(af4), O.Found.i(c0)], O.ANone{}, O.TNone{})
  +ld1 = O.UOp.new(O.Found.ar(ix6), O.OpsLOAD{}, [O.Found.i(ix6)], O.ANone{}, O.TNone{})
  +lt0 = O.UOp.new(O.Found.ar(ld1), O.OpsCMPLT{}, [O.Found.i(ld1), O.Found.i(ld0)], O.ANone{}, O.TNone{})
  # 38-42. The SECOND `get_time_ms(done)`, argument `done.after`. Its `ms` placeholder is the
  #     same node as i8's apart from the slot, and `pm_renumber_slots` gave IT 2 -- which is
  #     why i8 and i38 are two nodes with two different `arg`s and not one node (py's rows
  #     i8 and i38 differ in exactly the slot and in nothing else).
  +ms2 = O.UOp.new.param(O.Found.ar(lt0), O.OpsBUFFER{}, Some{1}, O.AParam{regd(2, None{})}, O.TNone{})
  +af5 = O.UOp.new(O.Found.ar(ms2), O.OpsAFTER{}, [O.Found.i(ms2), O.Found.i(ld1)], O.ANone{}, O.TNone{})
  +cl2 = O.UOp.new(O.Found.ar(af5), O.OpsCALL{}, [O.Found.i(sk0), O.Found.i(af5)],
    O.ACall{O.CallInfo{Some{"do_get_time_ms"}, False{}, False{}, S.void()}}, O.TNone{})
  +af6 = O.UOp.new(O.Found.ar(cl2), O.OpsAFTER{}, [O.Found.i(ms2), O.Found.i(cl2)], O.ANone{}, O.TNone{})
  +ix7 = O.UOp.new(O.Found.ar(af6), O.OpsINDEX{}, [O.Found.i(af6), O.Found.i(c0)], O.ANone{}, O.TNone{})
  # 43-48. `get_time_ms(done) - start < 30000` (hcq2.py:78) becomes
  #     `now + start * -1 < 30000`, so i43 is a NEGATIVE weakint CONST and `H.i64_of_i32` is
  #     a SIGN-EXTENDING constructor (helpers.bend:1653): 4294967295 is the u32 spelling of
  #     -1 and `i64_text` prints the pair `l-1:4294967295`, which is what py prints and what
  #     `konst` above prints for the same value.
  +cn1 = O.UOp.const(O.Found.ar(ix7), O.CInt{H.i64_of_i32(4294967295)})
  +ml1 = O.UOp.new(O.Found.ar(cn1), O.OpsMUL{}, [O.Found.i(ix5), O.Found.i(cn1)], O.ANone{}, O.TNone{})
  +ad1 = O.UOp.new(O.Found.ar(ml1), O.OpsADD{}, [O.Found.i(ix7), O.Found.i(ml1)], O.ANone{}, O.TNone{})
  +c30k = O.UOp.const(O.Found.ar(ad1), O.CInt{H.i64_of_i32(30000)})
  +lt1 = O.UOp.new(O.Found.ar(c30k), O.OpsCMPLT{}, [O.Found.i(ad1), O.Found.i(c30k)], O.ANone{}, O.TNone{})
  +an = O.UOp.new(O.Found.ar(lt1), O.OpsAND{}, [O.Found.i(lt0), O.Found.i(lt1)], O.ANone{}, O.TNone{})
  # 49-50. `done.backedge(loop, (done < target) & (...)).sink()` -- `.backedge` is
  #     `UOp(Ops.BACKEDGE, src=(self, loop, cond))` (ops.py:620), so src is (the LOAD, the
  #     RANGE, the AND) IN THAT ORDER, and both are `R`: BACKEDGE and SINK have no shape.
  +be = O.UOp.backedge(O.Found.ar(an), O.Found.i(ld1), O.Found.i(rg), O.Found.i(an))
  +sk1 = O.UOp.new(O.Found.ar(be), O.OpsSINK{}, [O.Found.i(be)], O.ANone{}, O.TNone{})
  # 51. The CALLER's `tv`, unnamed: `UOp.param(3, uint64, 1, device="CPU")` with no `name`
  #     (graphcmp.py:1271 `_storage`), GLOBAL on CPU, size 1, not volatile.
  +ptv = O.UOp.new.param(O.Found.ar(sk1), O.OpsPARAM{}, Some{1},
    O.AParam{O.ParamArg{3, S.uint64(), None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
      False{}, None{}, None{}, False{}, None{}}}, O.TNone{})
  # 52. `f.call(*ins.values(), name="hcq_fence")` (ops.py:1325) over a TWO-ENTRY dict whose
  #     values are the SAME `tv`, so src is (body, tv, tv). `CallInfo` carries the port's
  #     fourth field (`cdtype`) and `callinfo` DROPS it -- as does graphcmp.py's own `carg`,
  #     which drops `grad_fxn` and `aux` too. LIMITS.md 2's named divergence is that the
  #     FIELD EXISTS and is what fold.bend:1160 reads the dtype from, not that it prints.
  O.UOp.new(O.Found.ar(ptv), O.OpsCALL{}, [O.Found.i(sk1), O.Found.i(ptv), O.Found.i(ptv)],
    O.ACall{O.CallInfo{Some{"hcq_fence"}, False{}, False{}, S.void()}}, O.TNone{})

# The gated STORE through the real `pm_linearize_cleanups`. FOURTEEN nodes and the root is
# the `LINEAR`, which is forced rather than chosen: `ENDIF`'s only src is the `IF` and
# NOTHING points at the `ENDIF`, so the rewritten SINK's toposort is 12 nodes and does not
# contain it (MEASURED on the py side). The LINEAR's src list is the only thing holding every
# line, so it is also the only root that reaches ENDIF -- and it makes the root's `src` field
# the PROGRAM ORDER of the kernel, which no other graph in the corpus has.
def g_gate() -> O.Found:
  +ar = O.Arena.empty()
  # THE SIZE CONST IS A ROW, AND IT IS ALSO ONE OF THE LINEAR'S LINES. CPython's LINEAR is
  # `src=n(i1,...,i14)` -- FOURTEEN refs, and `i1` is the `weakint l0:16` that `p0`'s size
  # interns. This fixture built that node implicitly, through `UOp.new.param`'s
  # `shape_to_shape_arg` (`ops.bend:3036`), so it had no name to put in the LINEAR's src list
  # and the list read THIRTEEN. MEASURED: 46 chars of refs against 49, and the ONLY byte
  # difference in the whole graph (`runs/graphcmp/D/D2-cmp-gate.txt`, one row). It is emitted
  # here explicitly instead: `UOp.const` interns through the same arena and the same ucache,
  # so it lands on the same index the param's own size would have taken, and the row is
  # unchanged -- what changes is that it now HAS A NAME and can be a line of the program.
  +c16 = O.UOp.const(ar, O.CInt{H.i64_of_i32(16)})
  +p0 = O.UOp.new.param(O.Found.ar(c16), O.OpsPARAM{}, Some{16}, O.AParam{paramd(0, S.single(), Some{"v0"}, False{})}, O.TNone{})
  +bf = O.UOp.new.param(O.Found.ar(p0), O.OpsBUFFER{}, Some{16}, O.AParam{paramd(1, S.single(), None{}, False{})}, O.TNone{})
  +c3 = O.UOp.const(O.Found.ar(bf), O.CInt{H.i64_of_i32(3)})
  +c4 = O.UOp.const(O.Found.ar(c3), O.CInt{H.i64_of_i32(4)})
  +rg = O.UOp.range_end(O.Found.ar(c4), O.Found.i(c4), [0], O.AXIS_WEAK{})
  +ix0 = O.UOp.new(O.Found.ar(rg), O.OpsINDEX{}, [O.Found.i(bf), O.Found.i(rg)], O.ANone{}, O.TNone{})
  +ix1 = O.UOp.new(O.Found.ar(ix0), O.OpsINDEX{}, [O.Found.i(p0), O.Found.i(rg)], O.ANone{}, O.TNone{})
  +lt = O.UOp.new(O.Found.ar(ix1), O.OpsCMPLT{}, [O.Found.i(rg), O.Found.i(c3)], O.ANone{}, O.TNone{})
  # codegen/__init__.py:403 -- the gated STORE `STORE(INDEX, INDEX, gate)` BECOMES
  # `[IF(gate, INDEX), STORE(INDEX, INDEX), ENDIF(IF)]`, so the STORE LOSES its third src and
  # the IF GAINS the INDEX. MEASURED on the py side: `IF src=n(i8,i6)` (gate, index) and
  # `STORE src=n(i6,i7)` -- two srcs, not three.
  +fi = O.UOp.new(O.Found.ar(lt), O.OpsIF{}, [O.Found.i(lt), O.Found.i(ix0)], O.ANone{}, O.TNone{})
  +st = O.UOp.new(O.Found.ar(fi), O.OpsSTORE{}, [O.Found.i(ix0), O.Found.i(ix1)], O.ANone{}, O.TNone{})
  +ed = O.UOp.new(O.Found.ar(st), O.OpsENDIF{}, [O.Found.i(fi)], O.ANone{}, O.TNone{})
  +en = O.UOp.new(O.Found.ar(ed), O.OpsEND{}, [O.Found.i(st), O.Found.i(rg)], O.ANone{}, O.TNone{})
  +sk = O.UOp.new(O.Found.ar(en), O.OpsSINK{}, [O.Found.i(en)], O.AKernel{O.KernelInfo{"gated", Nil{}, None{}, None{}, 0, False{}}}, O.TNone{})
  O.UOp.new(O.Found.ar(sk), O.OpsLINEAR{},
    [O.Found.i(c16), O.Found.i(p0), O.Found.i(bf), O.Found.i(c3), O.Found.i(c4), O.Found.i(rg),
      O.Found.i(ix0), O.Found.i(ix1), O.Found.i(lt), O.Found.i(fi), O.Found.i(st), O.Found.i(ed),
      O.Found.i(en), O.Found.i(sk)], O.ANone{}, O.TNone{})

# `--graph bw`: `(Tensor.empty(4,3) @ Tensor.empty(3,4)).sum().gradient(a, b)`, MEASURED at
# 32 nodes on the py side with the census
# `ALLOC=2 CAST=1 CONST=4 EXPAND=2 GROUP=1 MUL=2 PERMUTE=4 REDUCE=2 RESHAPE=8 STACK=6`.
# It is the corpus's FIRST BACKWARD graph -- everything above is forward -- and it is what
# takes the op census from 34 of 77 to 35 by reaching `EXPAND`.
#
# BUILT IN TOPOSORT ORDER, NODE FOR NODE, and that is the same rule every builder above
# follows and for the same reason: `UOp.toposort` fixes the output order and the ids are
# toposort POSITIONS, so a builder written in any other order produces a canonical file whose
# `id` column is a permutation of the py side's. The differ pairs structurally so the verdict
# would survive it, but `graphcmp-run.sh`'s byte-identity step would not, and a byte-identity
# step that compares two different orderings is a check that cannot fail for the right reason.
#
# THE ALLOC SLOTS ARE 1 THEN 0, which reads backwards and IS what CPython builds: `a` takes
# slot 0 and `b` slot 1 (`UOp.unique_num`, ops.py:842), but the gradient w.r.t. `a` expands
# into `b`'s SHAPE, so `b`'s subtree is visited first and the node at toposort index 1 is the
# slot-1 ALLOC. MEASURED by the py side's own rows, not read off the source order.
#
# THE TWO `OpsCONST`/`OpsCAST`/`OpsEXPAND` NODES AT INDICES 10-14 ARE THE GRADIENT'S SEED,
# and they are why this graph exists. `sum()`'s gradient is `(ctx / ret).broadcast(...)`
# shaped, and the SEED it broadcasts is `UOp.const(1.0)` -- a `weakfloat` CONST carrying a
# `ConstFloat`, which `OpsCAST` re-types to `f32` before the two `OpsEXPAND`s give it the
# `(4,4,3)` shape the MUL needs. So the graph reaches `CAST` (which the corpus had, at
# `cast`/`lin`), `CONST` (which it had at 36 nodes) and `EXPAND` (which it had NOT), and the
# honest count of what it ADDS is one op.
#
# `CFloat` HERE IS THE CONST's VALUE and its BITS SPELLING is `konst`'s business
# (graphcmp.bend:200), not this builder's: `1.0` is `F32.bits(1.0) = 1065353216` and CPython's
# `struct.pack('<f', 1.0)` is the same U32, MEASURED on both sides. The two sides' `repr`s
# were NOT the same and neither was right -- see graphcmp.py's `f32bits`.
def g_bw() -> O.Found:
  #  1  ALLOC slot 1 size 12 -- `b`, visited first because `a`'s gradient expands into it
  +a1 = O.UOp.new.param(O.Arena.empty(), O.OpsALLOC{}, Some{12}, O.AParam{alloc(1)}, O.TNone{})
  +c3 = O.UOp.const(O.Found.ar(a1), O.CInt{H.i64_of_i32(3)})
  +c4 = O.UOp.const(O.Found.ar(c3), O.CInt{H.i64_of_i32(4)})
  +s34 = O.UOp.new(O.Found.ar(c4), O.OpsSTACK{}, [O.Found.i(c3), O.Found.i(c4)], O.ANone{}, O.TNone{})
  +r34 = O.UOp.new(O.Found.ar(s34), O.OpsRESHAPE{}, [O.Found.i(a1), O.Found.i(s34)], O.ANone{}, O.TNone{})
  +c1 = O.UOp.const(O.Found.ar(r34), O.CInt{H.i64_of_i32(1)})
  +s134 = O.UOp.new(O.Found.ar(c1), O.OpsSTACK{}, [O.Found.i(c1), O.Found.i(c3), O.Found.i(c4)], O.ANone{}, O.TNone{})
  +r134 = O.UOp.new(O.Found.ar(s134), O.OpsRESHAPE{}, [O.Found.i(r34), O.Found.i(s134)], O.ANone{}, O.TNone{})
  +p021b = O.UOp.new(O.Found.ar(r134), O.OpsPERMUTE{}, [O.Found.i(r134)], O.ATuple{[0, 2, 1]}, O.TNone{})
  # 10-14  THE SEED: `weakfloat 1.0` -> CAST to f32 -> EXPAND to (4,4) -> EXPAND to (3,4,4).
  # `weakfloat` and not `f32` because `UOp.const(1.0)` defaults to it (MEASURED: the py row
  # reads `dtype=weakfloat`), and the CAST is what re-types it -- which is upstream's own
  # `reduce_gradient` shape, not a fixture choice.
  +c1f = O.UOp.const(O.Found.ar(p021b), O.CFloat{1.0})
  +cf32 = O.UOp.new(O.Found.ar(c1f), O.OpsCAST{}, [O.Found.i(c1f)], O.ADt{S.single()}, O.TNone{})
  +s44 = O.UOp.new(O.Found.ar(cf32), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c4)], O.ANone{}, O.TNone{})
  +x4 = O.UOp.new(O.Found.ar(s44), O.OpsEXPAND{}, [O.Found.i(cf32), O.Found.i(s44)], O.ANone{}, O.TNone{})
  +x34 = O.UOp.new(O.Found.ar(x4), O.OpsEXPAND{}, [O.Found.i(x4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  # MEASURED, and the tuple is `(1,2,0)` rather than the identity because the seed's shape is
  # `(3,4,4)` and the MUL below needs `(4,4,3)` to broadcast against the other operand's
  # `(1,4,3)`. Writing `[0,1,2]` here instead -- which is what a first reading of "the
  # identity permutation" suggests -- compiles, emits 32 rows, and leaves the `?` LEDGER
  # MARKER LIVE ON 17 of the 32 nodes from the MUL down, because `(3,4,3)` against `(3,4,4)`
  # does not broadcast. **The `?` ledger is what caught it and the node count could not**: both
  # readings are 32 nodes with 11 distinct ops, so a count-based gate reads them as the same
  # graph. That is the argument for the ledger existing, in one measured instance.
  +p012 = O.UOp.new(O.Found.ar(x34), O.OpsPERMUTE{}, [O.Found.i(x34)], O.ATuple{[1, 2, 0]}, O.TNone{})
  +mb = O.UOp.new(O.Found.ar(p012), O.OpsMUL{}, [O.Found.i(p021b), O.Found.i(p012)], O.ANone{}, O.TNone{})
  +p102 = O.UOp.new(O.Found.ar(mb), O.OpsPERMUTE{}, [O.Found.i(mb)], O.ATuple{[1, 0, 2]}, O.TNone{})
  # MEASURED: this line took three passes and the error text named NEITHER the mistake NOR
  # what the line meant -- `expected : O.Tag / observed : O.Arg`, with the whole binder
  # context dumped and no location inside the expression. The other 24 `UOp.new` calls in
  # this builder take FIVE arguments (`ar, op, src, arg, tag`) and this one had SIX, because
  # the tuple was written with a trailing `ANone` the arity does not want; the extra
  # argument pushed `TNone` off the end, so the checker read the 5th as an `Arg` and wanted
  # a `Tag`. The port's `arg`/`tag` SPLIT is what made an arity mistake land here as a type
  # error rather than as a silent field swap -- a builder with one `arg` field would have
  # taken six arguments happily and written a wrong graph.
  +rb = O.UOp.new(O.Found.ar(p102), O.OpsREDUCE{}, [O.Found.i(p102)], O.AReduce{O.OpsADD{}, 1}, O.TNone{})
  +s341 = O.UOp.new(O.Found.ar(rb), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c1), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r4_1_3 = O.UOp.new(O.Found.ar(s341), O.OpsRESHAPE{}, [O.Found.i(rb), O.Found.i(s341)], O.ANone{}, O.TNone{})
  +s43 = O.UOp.new(O.Found.ar(r4_1_3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r43b = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(r4_1_3), O.Found.i(s43)], O.ANone{}, O.TNone{})
  # 23  the OTHER ALLOC, slot 0 -- `a`
  +a0 = O.UOp.new.param(O.Found.ar(r43b), O.OpsALLOC{}, Some{12}, O.AParam{alloc(0)}, O.TNone{})
  +r43a = O.UOp.new(O.Found.ar(a0), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +r4_1_3b = O.UOp.new(O.Found.ar(r43a), O.OpsRESHAPE{}, [O.Found.i(r43a), O.Found.i(s341)], O.ANone{}, O.TNone{})
  +ma = O.UOp.new(O.Found.ar(r4_1_3b), O.OpsMUL{}, [O.Found.i(r4_1_3b), O.Found.i(p012)], O.ANone{}, O.TNone{})
  +ra = O.UOp.new(O.Found.ar(ma), O.OpsREDUCE{}, [O.Found.i(ma)], O.AReduce{O.OpsADD{}, 1}, O.TNone{})
  +s143 = O.UOp.new(O.Found.ar(ra), O.OpsSTACK{}, [O.Found.i(c1), O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r143 = O.UOp.new(O.Found.ar(s143), O.OpsRESHAPE{}, [O.Found.i(ra), O.Found.i(s143)], O.ANone{}, O.TNone{})
  +p021a = O.UOp.new(O.Found.ar(r143), O.OpsPERMUTE{}, [O.Found.i(r143)], O.ATuple{[0, 2, 1]}, O.TNone{})
  +r34b = O.UOp.new(O.Found.ar(p021a), O.OpsRESHAPE{}, [O.Found.i(p021a), O.Found.i(s34)], O.ANone{}, O.TNone{})
  O.UOp.group(O.Found.ar(r34b), [O.Found.i(r43b), O.Found.i(r34b)])

# ===========================================================================
# THE FOUR ELEMENTWISE/MOVEMENT GRAPHS (`alu`, `bit`, `where`, `move`). Added after the
# op census said 35 of 77 and 42 of the remaining ops are ELEMENTWISE -- i.e. exactly the
# class a corpus of hand-written value graphs had structurally failed to reach.
#
# WHY THESE FIVE AND NOT ONE BIG ONE. The census is the only place that can tell a cheap
# op from an expensive one, and it says: `alu` is 14 nodes for EIGHT new ops,
# `bit` is 10 for FOUR, `where` is 8 for ONE, `move` is 19 for FOUR, and `flip` is 6 for
# ONE. One graph would have been 55 nodes for the same 18 ops and every one of them would
# have been harder to attribute, because a `?` ledger row would then have covered four ops
# and a fold defect would have been reported against all four.
#
# AND EVERY ONE OF THEM IS `?`-ZERO BY MEASUREMENT, not by design. The port's fold has an
# arm per op for all eighteen (`fold.bend`: `unary_ds` for SQRT/RECIPROCAL/LOG2/EXP2/SIN,
# `thru0` for TRUNC/DETACH/CONTIGUOUS_BACKWARD, `alu_ds` for POW/FLOORDIV/FLOORMOD,
# `shift_ds` for SHL/SHR, `where_ds` for WHERE, `pad_ds`/`shrink_ds`/`flip_ds`/`bitcast_ds`
# for the movements), so nothing here is a new fold obligation -- they are existing arms
# that no graph had reached, which is the same distinction `bw` made about `EXPAND`.

# An ALLOC of an arbitrary dtype. `alloc` above is `f32` because every pre-`bit` fixture
# was `Tensor.empty(..)` on the default float; `bit` needs `int` and retyping the ALLOC
# would have moved every downstream node's dtype too, so the two spellings coexist and
# `alloc` is left byte-for-byte alone (the graphs already measured against it must not
# move).
def allocd(slot: U32, dtx: S.Dt) -> O.ParamArg:
  O.ParamArg{slot, dtx, None{}, None{}, None{}, S.AGlobal{}, Some{S.D1{0}},
    False{}, None{}, None{}, True{}, None{}}

# `--graph alu`: `UOp.group(sqrt(a), reciprocal(a), a**a, log2(a), exp2(a), sin(a),
# trunc(a), detach(a))` over ONE `Tensor.empty(4,3)`. MEASURED at 14 nodes on the py side
# with the census
# `ALLOC=1 CONST=2 DETACH=1 EXP2=1 GROUP=1 LOG2=1 POW=1 RECIPROCAL=1 RESHAPE=1 SIN=1
#  SQRT=1 STACK=1 TRUNC=1`.
#
# EIGHT NEW OPS IN FOURTEEN NODES, and it is the densest graph in the corpus by that
# measure. The shape is deliberately degenerate: every unary op takes the SAME `RESHAPE` as
# its only child and `POW` takes it TWICE (`src=n(i5,i5)`, a repeated child index), so the
# graph's whole content is the eighteen ops' `dtype`/`shape` arms and nothing else. That is
# what makes it a coverage fixture rather than another arithmetic test.
#
# `DETACH` IS NOT A MOVEMENT even though `fold.bend` files it under `thru0` beside them:
# upstream's `shape` (ops.py) is `thru0` for it and so is `CONTIGUOUS_BACKWARD`'s, which
# is why they share an arm and not why they are the same kind of node.
def g_alu() -> O.Found:
  +a0 = O.UOp.new.param(O.Arena.empty(), O.OpsALLOC{}, Some{12}, O.AParam{alloc(0)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r43 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +sq = O.UOp.new(O.Found.ar(r43), O.OpsSQRT{}, [O.Found.i(r43)], O.ANone{}, O.TNone{})
  +rp = O.UOp.new(O.Found.ar(sq), O.OpsRECIPROCAL{}, [O.Found.i(r43)], O.ANone{}, O.TNone{})
  +pw = O.UOp.new(O.Found.ar(rp), O.OpsPOW{}, [O.Found.i(r43), O.Found.i(r43)], O.ANone{}, O.TNone{})
  +lg = O.UOp.new(O.Found.ar(pw), O.OpsLOG2{}, [O.Found.i(r43)], O.ANone{}, O.TNone{})
  +e2 = O.UOp.new(O.Found.ar(lg), O.OpsEXP2{}, [O.Found.i(r43)], O.ANone{}, O.TNone{})
  +sn = O.UOp.new(O.Found.ar(e2), O.OpsSIN{}, [O.Found.i(r43)], O.ANone{}, O.TNone{})
  +tr = O.UOp.new(O.Found.ar(sn), O.OpsTRUNC{}, [O.Found.i(r43)], O.ANone{}, O.TNone{})
  +dt = O.UOp.new(O.Found.ar(tr), O.OpsDETACH{}, [O.Found.i(r43)], O.ANone{}, O.TNone{})
  O.UOp.group(O.Found.ar(dt), [O.Found.i(sq), O.Found.i(rp), O.Found.i(pw),
    O.Found.i(lg), O.Found.i(e2), O.Found.i(sn), O.Found.i(tr), O.Found.i(dt)])

# `--graph bit`: `UOp.group(a<<a, a>>a, a//a, a%a)` over ONE `Tensor.empty(4,3, int)`.
# MEASURED at 10 nodes, census
# `ALLOC=1 CONST=2 FLOORDIV=1 FLOORMOD=1 GROUP=1 RESHAPE=1 SHL=1 SHR=1 STACK=1`.
#
# THE ALLOC IS `int32` AND NOT f32, and that is the point rather than a convenience:
# `shift_ds`/`alu_ds` branch on the operand dtype, so an f32 fixture would have measured a
# different arm than a real integer program does. MEASURED on the py side, the ALLOC's row
# is `P(i0,Di32,i12,...)` and every op below it reads `dt=i32`.
def g_bit() -> O.Found:
  +a0 = O.UOp.new.param(O.Arena.empty(), O.OpsALLOC{}, Some{12}, O.AParam{allocd(0, S.int32())}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r43 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +sl = O.UOp.new(O.Found.ar(r43), O.OpsSHL{}, [O.Found.i(r43), O.Found.i(r43)], O.ANone{}, O.TNone{})
  +sr = O.UOp.new(O.Found.ar(sl), O.OpsSHR{}, [O.Found.i(r43), O.Found.i(r43)], O.ANone{}, O.TNone{})
  +fd = O.UOp.new(O.Found.ar(sr), O.OpsFLOORDIV{}, [O.Found.i(r43), O.Found.i(r43)], O.ANone{}, O.TNone{})
  +fm = O.UOp.new(O.Found.ar(fd), O.OpsFLOORMOD{}, [O.Found.i(r43), O.Found.i(r43)], O.ANone{}, O.TNone{})
  O.UOp.group(O.Found.ar(fm), [O.Found.i(sl), O.Found.i(sr), O.Found.i(fd),
    O.Found.i(fm)])

# `--graph where`: `UOp.group((a<a).where(a,a), (a<a))`. MEASURED at 8 nodes, census
# `ALLOC=1 CMPLT=1 CONST=2 GROUP=1 RESHATE=1 STACK=1 WHERE=1`.
#
# THE COND IS `(a < a)` AND NOT `a`, and that is a MEASURED constraint rather than a style
# choice. `dtype_from_uop`'s WHERE arm (tinygrad/uop/ops.py:158) reads
# `if src[0].dtype != dtypes.bool: raise RuntimeError(...)`, and `row_of` reads `.dtype`
# for EVERY node -- so a `UOp.group(a.where(a,a), ...)` candidate DIES in the emitter. The
# first reach probe did not see it because it counted `n.op.name` and never touched
# `.dtype`, so the op census it printed was a census of a graph that cannot be emitted at
# all. Every candidate after that one is checked through `emit_py`.
def g_where() -> O.Found:
  +a0 = O.UOp.new.param(O.Arena.empty(), O.OpsALLOC{}, Some{12}, O.AParam{alloc(0)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r43 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +lt = O.UOp.new(O.Found.ar(r43), O.OpsCMPLT{}, [O.Found.i(r43), O.Found.i(r43)], O.ANone{}, O.TNone{})
  +wh = O.UOp.new(O.Found.ar(lt), O.OpsWHERE{}, [O.Found.i(lt), O.Found.i(r43), O.Found.i(r43)], O.ANone{}, O.TNone{})
  O.UOp.group(O.Found.ar(wh), [O.Found.i(wh), O.Found.i(lt)])

# `--graph move`: the four MOVEMENT ops the corpus had not reached and can compare --
# `pad(((0,1),(0,2)))`, `shrink(((1,4),(2,5)))`, `contiguous_backward()` and
# `bitcast(int)`. MEASURED at 19 nodes on the py side, census
# `ALLOC=2 BITCAST=1 CONST=7 CONTIGUOUS_BACKWARD=1 GROUP=1 PAD=1 RESHAPE=2 SHRINK=1 STACK=6`.
# FLIP was the fifth and is `g_flip` on its own -- see there for the measured wall.
#
# TWO FACTS THE ROWS CARRY AND A DOCSTRING WOULD NOT HAVE:
#   * `PAD`'s margins are TWO CONST-STACKs of REPEATED children -- `n(i6,i6)` is
#     `STACK(0,0)` and `n(i8,i8)` is `STACK(5,5)` -- so the SAME `CONST 0` node is a child
#     of one and the SAME `CONST 5` of the other, and both are multi-parent nodes. This is
#     the first graph in the corpus where a multi-parent node is a MOVEMENT ARG and not a
#     shape literal reached twice by accident.
#   * `SHRINK`'s third src is `STACK(3,3)` -- the `CONST 3` already interned at index 3 for
#     the `a` shape. So `move` REUSES a CONST across two different subtrees, which is the
#     ucache doing what `UOp.key` (ops.py:269) says it does and what a builder that minted
#     a fresh `CONST 3` would silently get wrong.
def g_move() -> O.Found:
  +ar = O.Arena.empty()
  +a0 = O.UOp.new.param(ar, O.OpsALLOC{}, Some{12}, O.AParam{alloc(0)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r43 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +c0 = O.UOp.const(O.Found.ar(r43), O.CInt{H.i64_of_i32(0)})
  +s00 = O.UOp.new(O.Found.ar(c0), O.OpsSTACK{}, [O.Found.i(c0), O.Found.i(c0)], O.ANone{}, O.TNone{})
  +c5 = O.UOp.const(O.Found.ar(s00), O.CInt{H.i64_of_i32(5)})
  +s55 = O.UOp.new(O.Found.ar(c5), O.OpsSTACK{}, [O.Found.i(c5), O.Found.i(c5)], O.ANone{}, O.TNone{})
  +pd = O.UOp.new(O.Found.ar(s55), O.OpsPAD{}, [O.Found.i(r43), O.Found.i(s00), O.Found.i(s55)], O.ANone{}, O.TNone{})
  +a1 = O.UOp.new.param(O.Found.ar(pd), O.OpsALLOC{}, Some{64}, O.AParam{alloc(1)}, O.TNone{})
  +c8 = O.UOp.const(O.Found.ar(a1), O.CInt{H.i64_of_i32(8)})
  +s88 = O.UOp.new(O.Found.ar(c8), O.OpsSTACK{}, [O.Found.i(c8), O.Found.i(c8)], O.ANone{}, O.TNone{})
  +r88 = O.UOp.new(O.Found.ar(s88), O.OpsRESHAPE{}, [O.Found.i(a1), O.Found.i(s88)], O.ANone{}, O.TNone{})
  +c1i = O.UOp.const(O.Found.ar(r88), O.CInt{H.i64_of_i32(1)})
  +c2i = O.UOp.const(O.Found.ar(c1i), O.CInt{H.i64_of_i32(2)})
  +s12 = O.UOp.new(O.Found.ar(c2i), O.OpsSTACK{}, [O.Found.i(c1i), O.Found.i(c2i)], O.ANone{}, O.TNone{})
  +s33 = O.UOp.new(O.Found.ar(s12), O.OpsSTACK{}, [O.Found.i(c3), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +sk = O.UOp.new(O.Found.ar(s33), O.OpsSHRINK{}, [O.Found.i(r88), O.Found.i(s12), O.Found.i(s33)], O.ANone{}, O.TNone{})
  +cb = O.UOp.new(O.Found.ar(sk), O.OpsCONTIGUOUS_BACKWARD{}, [O.Found.i(r43)], O.ANone{}, O.TNone{})
  # BITCAST IS THE ONLY NODE IN THE CORPUS WHOSE `arg` IS A `DType` AND WHOSE `dtype` IS
  # NOT `cast`'s f16 -- `cast` already covered the `ADt` arm, and this covers it with the
  # dtype CHANGING under it (`f32 -> i32`), which is the case `bitcast_ds` and `cast_ds`
  # share an arm for and must not be confused by.
  +bc = O.UOp.new(O.Found.ar(cb), O.OpsBITCAST{}, [O.Found.i(r43)], O.ADt{S.int32()}, O.TNone{})
  O.UOp.group(O.Found.ar(bc), [O.Found.i(pd), O.Found.i(sk), O.Found.i(cb),
    O.Found.i(bc)])

# `--graph flip`: `a.flip(0)` -- MEASURED at 6 nodes, census
# `ALLOC=1 CONST=2 FLIP=1 RESHAPE=1 STACK=1`.
#
# **THIS GRAPH IS EXPECTED TO DISAGREE, ON ITS `arg` FIELD, AND THE CAUSE IS A PORT
# SPELLING NOT AN ARITHMETIC ONE.** MEASURED, calling CPython:
#     Tensor.empty(4,3).flip(0).uop.arg       ->  (True, False)
#     Tensor.empty(4,3).flip(0,1).uop.arg     ->  (True, True)
#     UOp(Ops.FLIP, (a,), (0,)).shape         ->  ValueError: bad flip on (4, 3), (0,)
# so upstream's FLIP arg is a `tuple[bool, ...]` and upstream REFUSES an int tuple:
# `tinygrad/uop/ops.py:428` reads `if len(ps) != len(self.marg) or not all(isinstance(x,
# bool) for x in self.marg): raise ValueError(...)`, and `tinygrad/mixin/movement.py:254`
# is the only construction site. `tinygrad/uop/spec.py:166` then asserts
# `isinstance(mv.arg, tuple)` for PERMUTE **and** FLIP together -- ONE upstream constructor
# for two arg TYPES, `tuple[int, ...]` for PERMUTE and `tuple[bool, ...]` for FLIP.
#
# THE PORT HAS ONE SPELLING FOR BOTH AND IT IS THE PERMUTE ONE. `tinybendygrad/uop/ops.bend`
# :1066 types the tuple `ATuple{ys: List<&2, U32>}` (its own table at :1031 says
# "PERMUTE/FLIP arg"), so a bool has no representation, and this file's `case O.ATuple{ys}:
# us(ys)` renders `n(i1,i0)` where the py side renders `n(b1,b0)`.
#
# SO IT IS ITS OWN GRAPH AND NOT A FIFTH MEMBER OF `move`. That is the whole reason: a FLIP
# disagreement CASCADES -- `arg` is in the `core`, so the FLIP goes one-sided and so does
# every consumer, and `move`'s GROUP would have been reported as an unexplained one-sided
# node with its real cause three lines up. Measured on the first attempt, which DID put it
# in `move`: `shared-cores=21 ONLY-PY=1 ONLY-BEND=1` plus a rung-2 GROUP pair, and the cause
# was only visible in the rung-3.5 cross-reference. One graph, one cause.
#
# THE ROOT IS THE FLIP, NOT A GROUP OVER IT, and that is UPSTREAM'S RULE rather than a
# choice of mine. `tinygrad/uop/ops.py:559` reads `if len(srcs) == 1 and isinstance(srcs[0],
# UOp): return srcs[0]`, so `graphcmp.py:1386`'s `UOp.group(a.flip(0).uop)` -- ONE src --
# RETURNS THE FLIP AND CREATES NO NODE. MEASURED today, calling CPython: `UOp.group(flip) is
# flip` is `True`, and `emit_py('flip')` answers **29 rows** carrying no `GROUP` at all. The
# `GROUP=1` this census used to carry was INHERITED FROM `move`, where `UOp.group` has FOUR
# srcs and does build one; this graph was split out of `move` and took its wrapper with it.
#
# **AND `FLIP` IS GONE TOO, SO THE 6 ROWS ABOVE WERE AGAINST A SCHEMA THAT NO LONGER EXISTS.**
# Upstream `900880433` ("remove Ops.FLIP", 2026-10-11) deleted `Ops.GROUP` and `Ops.FLIP`
# and kept BOTH behaviours over ops that survived -- `UOp.group` is `UOp(Ops.STACK).after(...)`
# (`ops.py:536-538`) and `Tensor.flip` is a PAD/SHRINK/TRANSPOSE loop (`movement.py:233-267`).
# So this graph's 6 rows became 29 and `g_flip` below no longer has an `OpsFLIP{}` to build.
# MEASURED 2026-10-18: `emit --side py --graph flip` answers **29 rows**, `OPS REACHED` never
# names FLIP, and across the WHOLE corpus `GROUP=0` and `FLIP=0` on 34 of 34 graphs. The
# repair is `MX.mxw_flip` -- THE PORT'S OWN IMPLEMENTATION, called the way CPython calls
# `a.flip(0)`, NOT a hand-written PAD/SHRINK chain transcribed from the py rows, because a
# transcription would stop testing the port and start testing my typing. `gates/groupflip.bend`
# is the instrument that already certifies `mxw_flip` against CPython (11 rows, 0 divergences).
# IT IS THE ONLY SINGLE-SRC GROUP IN THIS FILE, and after that commit it is not a group call
# at all: the other 11 call sites became `O.UOp.group` and every one of those carries 2-8 srcs.
def g_flip() -> O.Found:
  +a0 = O.UOp.new.param(O.Arena.empty(), O.OpsALLOC{}, Some{12}, O.AParam{alloc(0)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r43 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +fb = T.tn_wrap_uop(O.Found.ar(r43), O.Found.i(r43))
  +fk = MX.mxw_flip(fb, [0])
  O.Found{T.Tensor.ar(fk), T.Tensor.u(fk)}

# `rows.pick` is a `Bool.pick` chain: `Bool.pick` CHOOSES an arm, it does not SEQUENCE
# one, so each rung is one more `Bool.pick` and the default is the matmul.
# `+` on the binder because this body READS `name` TWICE (once per rung). `Bool.pick`
# chooses an arm, so at runtime only one read happens, but `String` is linear and bend
# counts the two static reads -- MEASURED: without `+` this is
# "expected : name / observed : name (consumed more than once)" at `rows.pick3`.
def g_getaddr() -> O.Found:
  +ar = O.Arena.empty()
  +a0 = O.UOp.new.param(ar, O.OpsALLOC{}, Some{12}, O.AParam{alloc(0)}, O.TNone{})
  # THE ARENA `UOp.new` RETURNED, NOT THE ONE IT WAS HANDED. Arena is immutable and
  # `UOp.new.of` returns `Found{made, ..}` -- the ALLOC lives in `Found.ar(a0)`, whose
  # index `Found.i(a0)` names it. Passing the PRE-`new` `ar` put `Found.i(a0)` past its
  # end, so `Arena.op` answered the arena BOTTOM (`BAD/NOOP`): peel said "not an ALLOC",
  # getaddr returned `self` unchanged, and the graph was one BAD row. Every other arm
  # threads `O.Found.ar(prev)`; this one was the exception.
  +a1 = O.Found.ar(a0)
  O.UOp.getaddr(O.Arena.budget(a1), a1, O.Found.i(a0), S.D1{0})

# `--graph unshard`: `UOp(Ops.UNSHARD, src=(a.uop, r), arg=(0,))`, 8 nodes. `r` is
# `UOp.range(2, 0, AxisType.DEVICE)`, so its atom is `XDEVICE` -- a non-WEAK axis the
# corpus reaches here for the second time (`indexed` has LOOP). The root is the
# UNSHARD and NOT a GROUP: the py fixture's docstring claims `GROUP=1`, but its own
# rows carry none, so the rows win. `arg=(0,)` is `ATuple`, the same spelling PERMUTE
# and FLIP share.
def g_unshard() -> O.Found:
  +ar = O.Arena.empty()
  +a0 = O.UOp.new.param(ar, O.OpsALLOC{}, Some{12}, O.AParam{alloc(0)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r43 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +c2 = O.UOp.const(O.Found.ar(r43), O.CInt{H.i64_of_i32(2)})
  +rg = O.UOp.range_end(O.Found.ar(c2), O.Found.i(c2), [0], O.AXIS_DEVICE{})
  O.UOp.new(O.Found.ar(rg), O.OpsUNSHARD{}, [O.Found.i(r43), O.Found.i(rg)], O.ATuple{[0]}, O.TNone{})

# `--graph threefry`: `UOp.group(a.threefry(s1).uop, a.threefry(s2).uop)` over three
# `Tensor.empty(4,3,uint64)`, 12 nodes. Three ALLOCs (slots 0,1,2), the shared `(4,3)`
# shape STACK reused by all three RESHAPEs, two THREEFRYs and the GROUP. THREEFRY is
# `uint64` output regardless of input dtype. `allocd` and not `alloc` because the
# dtype is u64, not the f32 `alloc` spells.
def g_threefry() -> O.Found:
  +ar = O.Arena.empty()
  +a0 = O.UOp.new.param(ar, O.OpsALLOC{}, Some{12}, O.AParam{allocd(0, S.uint64())}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r0 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +a1 = O.UOp.new.param(O.Found.ar(r0), O.OpsALLOC{}, Some{12}, O.AParam{allocd(1, S.uint64())}, O.TNone{})
  +r1 = O.UOp.new(O.Found.ar(a1), O.OpsRESHAPE{}, [O.Found.i(a1), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +tf0 = O.UOp.new(O.Found.ar(r1), O.OpsTHREEFRY{}, [O.Found.i(r0), O.Found.i(r1)], O.ANone{}, O.TNone{})
  +a2 = O.UOp.new.param(O.Found.ar(tf0), O.OpsALLOC{}, Some{12}, O.AParam{allocd(2, S.uint64())}, O.TNone{})
  +r2 = O.UOp.new(O.Found.ar(a2), O.OpsRESHAPE{}, [O.Found.i(a2), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +tf1 = O.UOp.new(O.Found.ar(r2), O.OpsTHREEFRY{}, [O.Found.i(r0), O.Found.i(r2)], O.ANone{}, O.TNone{})
  O.UOp.group(O.Found.ar(tf1), [O.Found.i(tf0), O.Found.i(tf1)])

# `--graph mulacc`: `UOp(Ops.MULACC, src=(a.uop, b.uop, c.uop))` over three
# `Tensor.empty(4,3)`, 10 nodes. The root is the MULACC with an `ANone` arg -- no
# GROUP in the py rows, whatever the fixture's docstring says.
def g_mulacc() -> O.Found:
  +ar = O.Arena.empty()
  +a0 = O.UOp.new.param(ar, O.OpsALLOC{}, Some{12}, O.AParam{alloc(0)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r0 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +a1 = O.UOp.new.param(O.Found.ar(r0), O.OpsALLOC{}, Some{12}, O.AParam{alloc(1)}, O.TNone{})
  +r1 = O.UOp.new(O.Found.ar(a1), O.OpsRESHAPE{}, [O.Found.i(a1), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +a2 = O.UOp.new.param(O.Found.ar(r1), O.OpsALLOC{}, Some{12}, O.AParam{alloc(2)}, O.TNone{})
  +r2 = O.UOp.new(O.Found.ar(a2), O.OpsRESHAPE{}, [O.Found.i(a2), O.Found.i(s43)], O.ANone{}, O.TNone{})
  O.UOp.new(O.Found.ar(r2), O.OpsMULACC{}, [O.Found.i(r0), O.Found.i(r1), O.Found.i(r2)], O.ANone{}, O.TNone{})

# `--graph wmma`: `UOp(Ops.WMMA, src=(a, b, acc), arg=((3,4,4), f32, 256, None))`,
# 11 nodes. `a` is `(4,4)`, `b` and `acc` are `(4,3)` and SHARE the `(4,3)` shape
# STACK (the py row's `n(i7)` twice). `UOp.wmma` is the port's own constructor.
#
# THE ONE KNOWN COLUMN DIVERGENCE, stated here because an arm that looks finished is
# where a reader stops. The py arg's FOURTH slot is `None` and renders `N`; the port's
# `AWmma.tc` is a `List<&2, U32>` with no `Maybe` (`ops.bend:1197`), so an absent `tc`
# renders `n()` and `argstr`'s `wm(..)` arm always emits `us(tc)`. The node count and
# every other column agree; only that slot disagrees, and it is a PORT SPELLING GAP
# (the same class as `flip`'s `tuple[bool]`) reported rather than papered over.
def g_wmma() -> O.Found:
  +ar = O.Arena.empty()
  +a0 = O.UOp.new.param(ar, O.OpsALLOC{}, Some{16}, O.AParam{alloc(0)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +s44 = O.UOp.new(O.Found.ar(c4), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c4)], O.ANone{}, O.TNone{})
  +r44 = O.UOp.new(O.Found.ar(s44), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s44)], O.ANone{}, O.TNone{})
  +b0 = O.UOp.new.param(O.Found.ar(r44), O.OpsALLOC{}, Some{12}, O.AParam{alloc(1)}, O.TNone{})
  +c3 = O.UOp.const(O.Found.ar(b0), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r43 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(b0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +acc0 = O.UOp.new.param(O.Found.ar(r43), O.OpsALLOC{}, Some{12}, O.AParam{alloc(2)}, O.TNone{})
  +racc = O.UOp.new(O.Found.ar(acc0), O.OpsRESHAPE{}, [O.Found.i(acc0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  O.UOp.wmma(O.Found.ar(racc), O.Found.i(r44), O.Found.i(r43), O.Found.i(racc), [3, 4, 4], S.single(), 256, None{})

# ===========================================================================
# THE THREE RESTORED GRAPHS' ARMS (2026-10-06). `allred`, `cdiv` and `late` are in
# `graphcmp.py`'s `GRAPHS` and had NO arm here, so each name fell through `rows.pick3`'s
# bottom rung to `g_matmul()` -- the bend side built the MATMUL while the py side built
# the real graph, and `checks/disagree-gate.py:78-80` pinned that as the HARNESS fault
# `NOT A ROW`. These arms are the fix. Py node counts MEASURED with
# `emit --side py --graph NAME`: allred 9, cdiv 10, late 12 -- and the py docstrings'
# own censuses (`g_cdiv` "10 nodes", `g_late` "12") are right, contra the three of the
# five earlier fixtures that were wrong.
#
# `--graph allred`: `Tensor.empty(4,3,f32).uop.copy_to_device(("CPU","CPU"))
# .allreduce(Ops.ADD, ("CPU","CPU"))`, 9 nodes, the ONLY route to `ALLREDUCE` and the
# only multi-device `COPY`. Built through the PORT'S OWN constructors -- `O.UOp.
# copy_to_device` mints the DEVICE RANGE (ops.bend's `device_range_src`) and
# `O.UOp.allreduce` the pair -- so the PORT, not this fixture, is on trial. Toposort
# order: ALLOC CONST CONST STACK RESHAPE CONST RANGE COPY ALLREDUCE.
def g_allred() -> O.Found:
  +ar = O.Arena.empty()
  +a0 = O.UOp.new.param(ar, O.OpsALLOC{}, Some{12}, O.AParam{alloc(0)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r43 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +cp = O.UOp.copy_to_device(O.Found.ar(r43), O.Found.i(r43), None{}, S.Dn{[0, 0]})
  O.UOp.allreduce(O.Found.ar(cp), O.Found.i(cp), O.OpsADD{}, S.Dn{[0, 0]})

# `--graph cdiv`: `UOp.group(a.fmod(b).uop, a.div(b, rounding_mode="trunc").uop)` over two
# `Tensor.empty(4,3,int)` -- 10 nodes, the ONLY route to `CMOD` and `CDIV` (both minted
# from int dtypes only). `b`'s CONST 4 / CONST 3 / STACK are the SHARED shape nodes, so
# `b` adds only its ALLOC and RESHAPE. Order: ALLOC CONST CONST STACK RESHAPE ALLOC
# RESHAPE CMOD CDIV GROUP.
def g_cdiv() -> O.Found:
  +ar = O.Arena.empty()
  +a0 = O.UOp.new.param(ar, O.OpsALLOC{}, Some{12}, O.AParam{allocd(0, S.int32())}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r43 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +b0 = O.UOp.new.param(O.Found.ar(r43), O.OpsALLOC{}, Some{12}, O.AParam{allocd(1, S.int32())}, O.TNone{})
  +rb = O.UOp.new(O.Found.ar(b0), O.OpsRESHAPE{}, [O.Found.i(b0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +cm = O.UOp.new(O.Found.ar(rb), O.OpsCMOD{}, [O.Found.i(r43), O.Found.i(rb)], O.ANone{}, O.TNone{})
  +cd = O.UOp.new(O.Found.ar(cm), O.OpsCDIV{}, [O.Found.i(r43), O.Found.i(rb)], O.ANone{}, O.TNone{})
  O.UOp.group(O.Found.ar(cd), [O.Found.i(cm), O.Found.i(cd)])

# `--graph late`: upstream's OWN late rewrite applied to its own eager graph -- 12 nodes,
# the only route to `SUB`, `NEG`, `CMPEQ` and `FDIV`. The PORT builds the REWRITTEN graph
# directly (it does not implement `get_late_rewrite_patterns`), which is all this fixture
# asks. NEG takes ONE src -- a's RESHAPE, `a.neg()`. Order: ALLOC CONST CONST STACK
# RESHAPE ALLOC RESHAPE SUB NEG CMPEQ FDIV GROUP.
def g_late() -> O.Found:
  +ar = O.Arena.empty()
  +a0 = O.UOp.new.param(ar, O.OpsALLOC{}, Some{12}, O.AParam{alloc(0)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r43 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +b0 = O.UOp.new.param(O.Found.ar(r43), O.OpsALLOC{}, Some{12}, O.AParam{alloc(1)}, O.TNone{})
  +rb = O.UOp.new(O.Found.ar(b0), O.OpsRESHAPE{}, [O.Found.i(b0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +sb = O.UOp.new(O.Found.ar(rb), O.OpsSUB{}, [O.Found.i(r43), O.Found.i(rb)], O.ANone{}, O.TNone{})
  +ng = O.UOp.new(O.Found.ar(sb), O.OpsNEG{}, [O.Found.i(r43)], O.ANone{}, O.TNone{})
  +eq = O.UOp.new(O.Found.ar(ng), O.OpsCMPEQ{}, [O.Found.i(r43), O.Found.i(rb)], O.ANone{}, O.TNone{})
  +fd = O.UOp.new(O.Found.ar(eq), O.OpsFDIV{}, [O.Found.i(r43), O.Found.i(rb)], O.ANone{}, O.TNone{})
  O.UOp.group(O.Found.ar(fd), [O.Found.i(sb), O.Found.i(ng), O.Found.i(eq), O.Found.i(fd)])

# --- THE FOUR REMAINING SUBSTITUTED GRAPHS (2026-10-06). `custom_function`, `mselect`,
# `mstack` and `stage` are in `graphcmp.py`'s `GRAPHS` and had NO arm here either, so each
# name fell through `rows.pick3`'s bottom rung to `g_matmul()` -- the SILENT substitution
# the three arms above just closed for `allred`/`cdiv`/`late`, still open for these four.
# Py node counts MEASURED with `emit --side py --graph NAME`: custom_function 6, mselect 9,
# mstack 8, stage 8.  The py rows are the specification.
#
# `--graph custom_function`: `UOp.custom_function("myfn", Tensor.empty(4,3).uop)` -- 6
# nodes, the only route to `CUSTOM_FUNCTION`. Built through the PORT'S constructor
# `O.UOp.custom_function`, whose `arg` is `ACustom{CustomFunction{"myfn", void}}`; void is
# upstream's own default and renders `cF(smyfn,Dvoid)`. Order: ALLOC CONST CONST STACK
# RESHAPE CUSTOM_FUNCTION.
def g_custom_function() -> O.Found:
  +ar = O.Arena.empty()
  +a0 = O.UOp.new.param(ar, O.OpsALLOC{}, Some{12}, O.AParam{alloc(0)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r43 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  O.UOp.custom_function(O.Found.ar(r43), "myfn", [O.Found.i(r43)], S.void())

# `--graph mselect`: `Tensor.empty(4,3).uop.copy_to_device(("CPU","CPU")).mselect(0)` -- 9
# nodes, the only route to `MSELECT`. `copy_to_device` is the PORT'S constructor and mints
# the DEVICE RANGE (its `k` is None, so the COPY input is the value itself); `mselect` is
# the port's own. Order: ALLOC CONST CONST STACK RESHAPE CONST RANGE COPY MSELECT.
def g_mselect() -> O.Found:
  +ar = O.Arena.empty()
  +a0 = O.UOp.new.param(ar, O.OpsALLOC{}, Some{12}, O.AParam{alloc(0)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r43 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +cp = O.UOp.copy_to_device(O.Found.ar(r43), O.Found.i(r43), None{}, S.Dn{[0, 0]})
  O.UOp.mselect(O.Found.ar(cp), O.Found.i(cp), 0)

# `--graph mstack`: `UOp.mstack(a.uop, b.uop)` over two `Tensor.empty(4,3)` -- 8 nodes.
# The port's `UOp.mstack(ar, self, srcs)` builds `src=(self,)+srcs`, which is upstream's
# `(self,)+srcs`, so `a` is `self` and `b` is the one-element `srcs`. Order: ALLOC CONST
# CONST STACK RESHAPE ALLOC RESHAPE MSTACK.
def g_mstack() -> O.Found:
  +ar = O.Arena.empty()
  +a0 = O.UOp.new.param(ar, O.OpsALLOC{}, Some{12}, O.AParam{alloc(0)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r0 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +a1 = O.UOp.new.param(O.Found.ar(r0), O.OpsALLOC{}, Some{12}, O.AParam{alloc(1)}, O.TNone{})
  +r1 = O.UOp.new(O.Found.ar(a1), O.OpsRESHAPE{}, [O.Found.i(a1), O.Found.i(s43)], O.ANone{}, O.TNone{})
  O.UOp.mstack(O.Found.ar(r1), O.Found.i(r0), [O.Found.i(r1)])

# `--graph stage`: `(Tensor.empty(4,3) + 1).contiguous().uop` -- 8 nodes, the only route to
# `STAGE`. Hand-assembled with `ANone{}`: upstream's `contiguous` mints the node via
# `uop.alu(Ops.STAGE)` and the port's own `UOp.bufferize` answers `ABad{}` where this node's
# arg is `None`, so the `ANone` arm is the one upstream builds. Order: ALLOC CONST CONST
# STACK RESHAPE CONST ADD STAGE.
def g_stage() -> O.Found:
  +ar = O.Arena.empty()
  +a0 = O.UOp.new.param(ar, O.OpsALLOC{}, Some{12}, O.AParam{alloc(0)}, O.TNone{})
  +c4 = O.UOp.const(O.Found.ar(a0), O.CInt{H.i64_of_i32(4)})
  +c3 = O.UOp.const(O.Found.ar(c4), O.CInt{H.i64_of_i32(3)})
  +s43 = O.UOp.new(O.Found.ar(c3), O.OpsSTACK{}, [O.Found.i(c4), O.Found.i(c3)], O.ANone{}, O.TNone{})
  +r43 = O.UOp.new(O.Found.ar(s43), O.OpsRESHAPE{}, [O.Found.i(a0), O.Found.i(s43)], O.ANone{}, O.TNone{})
  +c1f = O.UOp.const(O.Found.ar(r43), O.CFloat{1.0})
  +ad = O.UOp.new(O.Found.ar(c1f), O.OpsADD{}, [O.Found.i(r43), O.Found.i(c1f)], O.ANone{}, O.TNone{})
  O.UOp.new(O.Found.ar(ad), O.OpsSTAGE{}, [O.Found.i(ad)], O.ANone{}, O.TNone{})

# `--graph api`: `Tensor.empty(4,3) + Tensor(1)` -- MEASURED at 9 nodes on the py side,
# census `ADD=1 ALLOC=1 CONST=4 RESHAPE=1 STACK=1`.
#
# **THE FIRST GRAPH IN THE CORPUS WHOSE BEND SIDE IS BUILT BY THE PORT'S OWN TENSOR API.**
# Every other graph here hand-builds its arena node for node, so the corpus tests the
# port's DATA STRUCTURES (`ops.bend`'s `UOp.new`, `fold.bend`'s derived properties) and
# never the port's OPERATIONS.  MEASURED, by a static call graph over DEF BODIES: before
# this graph, `mixin/elementwise.bend` (254 defs), `mixin/dtype.bend` (177),
# `mixin/gradient.bend` (494) and `uop/weak.bend` (258) were **100% UNREACHED** and
# `tensor.bend` was reached on 4 of its 347.  That is 1183 defs of the port's operation
# layer that a 35-graph GREEN corpus says nothing about, and this graph is what reaches
# them.
#
# **WHY A BINARY OP IS THE ONE THAT WORKS, and it is measured rather than chosen.**
# `mixin/elementwise.bend`'s own header says "ONE ARENA PER METHOD" and names
# `O.Arena.merge` as the composition operator: a method builds in its own arena and the
# operands' arenas are MERGED at ENTRY.  A BINARY op merges its two operands' arenas and
# builds the op in the merged arena, so the WHOLE graph lands in ONE arena -- which is
# what this lane needs, because `rows.of` emits one canonical row per arena node.
# MEASURED on the port's side: `CR.cr_empty` + `E.ew_add` produce
# CONST/ALLOC/CONST/CONST/STACK/RESHAPE/CONST/ADD -- the same nine ops, in the same order,
# with the same shapes and the same dtypes as CPython's, and `O.Arena.budget` has enough
# fuel for the toposort.
#
# **AND IT DISAGREES, ON PURPOSE, AND THE DISAGREEMENT IS THE `ParamArg.slot`.**
# MEASURED, the two sides' ALLOCs carry DIFFERENT slots:
#     CPython   ALLOC slot 0
#     the port  ALLOC slot 1
# and the cause is `mixin/creation.bend`'s `cr_alloc` (creation.bend:377), which mints
# `cr_alloc.arg(O.Arena.next(ar), dt, dev)` -- the arena's LENGTH -- where upstream mints
# `next(UOp.unique_num)` (ops.py:1208), a MONOTONE counter.
#
# **THE CORPUS CANNOT SEE THIS DEFECT, AND THE REASON IS STRUCTURAL.**  Every other graph
# here hand-builds its ALLOC and SPELLS the slot itself -- `alloc(slot)` above -- so the
# port's own slot-minting is executed by NOTHING the corpus compares.  A graph whose bend
# side calls `cr_empty` is the first thing in this corpus that can see it, and it sees a
# real divergence.
#
# **THE OPERAND IS A WEAKINT CONST, AND THAT IS THE POINT.**  `Tensor(1)` is `weakint`, so
# upstream PROMOTES it and the ADD's second src is `CONST(weakfloat 1.0)`.  MEASURED on the
# port's side, `E.ew_add` produces the same `weakfloat` CONST.  An operand that needed no
# promotion would reach the binop but NOT the promotion, and the promotion is what reaches
# `mixin/dtype.bend` and `uop/weak.bend`'s evaluation machinery.
#
# **THE SHAPES ARE CHOSEN.**  `(4,3)` and `(3,5)` do NOT broadcast -- CPython RAISES
# `IndexError: shape mismatch` (ops.py:86 `_broadcast_shape`) -- and MEASURED on the port's
# side `E.ew_add` BUILDS IT ANYWAY, a second divergence this fixture deliberately does not
# use, because a fixture that dies on one side cannot be a comparison at all.
def g_api() -> O.Found:
  +ar = O.Arena.empty()
  +a = CR.cr_empty(ar, Some{S.single()}, [4, 3], S.D1{0})
  +s = E.ew_add(a, E.ECon{O.CInt{H.i64_of_i32(1)}}, False{})
  O.Found{T.Tensor.ar(s), T.Tensor.u(s)}

# `IO.args()` LEADS WITH THE PROGRAM NAME (symbolic.bend:2614), so the graph name is the
# head of the TAIL and no argument at all is the default rather than an error.

def rows.pick3(+name: String) -> O.Found:
  Bool.pick(O.Found, String.eq(name, "alu"), g_alu(),
    Bool.pick(O.Found, String.eq(name, "bit"), g_bit(),
      Bool.pick(O.Found, String.eq(name, "where"), g_where(),
        Bool.pick(O.Found, String.eq(name, "move"), g_move(),
          Bool.pick(O.Found, String.eq(name, "flip"), g_flip(),
    Bool.pick(O.Found, String.eq(name, "lin"), g_lin(),
      Bool.pick(O.Found, String.eq(name, "loop"), g_loop(),
        Bool.pick(O.Found, String.eq(name, "gate"), g_gate(),
          Bool.pick(O.Found, String.eq(name, "bw"), g_bw(),
            Bool.pick(O.Found, String.eq(name, "group"), g_group(),
              Bool.pick(O.Found, String.eq(name, "commute"), g_commute(),
                Bool.pick(O.Found, String.eq(name, "indexed"), g_indexed(),
                  Bool.pick(O.Found, String.eq(name, "sym"), g_sym(),
                    Bool.pick(O.Found, String.eq(name, "binblob"), g_binblob(),
                      Bool.pick(O.Found, String.eq(name, "cast"), g_cast(),
                        Bool.pick(O.Found, String.eq(name, "range"), g_range(),
                          Bool.pick(O.Found, String.eq(name, "rangeflat"), g_rangeflat(),
                            Bool.pick(O.Found, String.eq(name, "special"), g_special(),
                              Bool.pick(O.Found, String.eq(name, "buffer"), g_buffer(),
                                Bool.pick(O.Found, String.eq(name, "sink"), g_sink(),
                                  Bool.pick(O.Found, String.eq(name, "reduce"), g_reduce(),
                                    Bool.pick(O.Found, String.eq(name, "threefry"), g_threefry(),
                                      Bool.pick(O.Found, String.eq(name, "mulacc"), g_mulacc(),
                                        Bool.pick(O.Found, String.eq(name, "getaddr"), g_getaddr(),
                                          Bool.pick(O.Found, String.eq(name, "unshard"), g_unshard(),
                                            Bool.pick(O.Found, String.eq(name, "wmma"), g_wmma(),
                                              Bool.pick(O.Found, String.eq(name, "allred"), g_allred(),
                                                Bool.pick(O.Found, String.eq(name, "cdiv"), g_cdiv(),
                                                  Bool.pick(O.Found, String.eq(name, "late"), g_late(),
                                                    Bool.pick(O.Found, String.eq(name, "custom_function"), g_custom_function(),
                                                      Bool.pick(O.Found, String.eq(name, "mselect"), g_mselect(),
                                                        Bool.pick(O.Found, String.eq(name, "mstack"), g_mstack(),
                                                          Bool.pick(O.Found, String.eq(name, "stage"), g_stage(),
                                                            # THE FIRST GRAPH BUILT BY THE PORT'S TENSOR API, and the
                                                            # first to reach the port's OPERATION layer at all.
                                                            Bool.pick(O.Found, String.eq(name, "api"), g_api(),
                                                            # THE FIRST `PROGRAM` IN THE CORPUS. `g_prog` is `g_lin` plus
                                                            # ONE node, and the one node is the one whose `pI(` form the
                                                            # corpus had never compared -- MEASURED 2026-10-22, the 34
                                                            # graphs produced ZERO `pI(` rows.
                                                            Bool.pick(O.Found, String.eq(name, "prog"), g_prog(),
                                                            g_matmul())))))))))))))))))))))))))))))))))))

def rows.pick(name: String) -> O.Found:
  # `match` may scrutinise a PARAMETER or a PATTERN binder, never a computed value and not a
  # local binder either (measured: both `match String.eq(..)` and `match <local>` are compile
  # errors), so a CHOICE between two values is `Bool.pick`.
  rows.pick3(name)

# ===========================================================================
# THE FIVE UNEXERCISED-OPS GRAPHS (2026-10-06). `graphcmp.py`'s `GRAPHS` grew five
# names -- `threefry`, `mulacc`, `getaddr`, `unshard`, `wmma` -- and THIS FILE had no
# arm for any of them, so an unknown name fell through `rows.pick3`'s bottom rung to
# `g_matmul()`: the bend side built the MATMUL while the py side built the real graph
# and the differ compared two different graphs. A dispatcher whose fallback is a REAL
# graph is worse than one that refuses, because it reports a disagreement that is the
# dispatcher and not the port.
#
# Every arm below is the py fixture's OWN emitted rows, read off
# `emit --side py --graph NAME` and mirrored node for node, in TOPOSORT ORDER (the
# `id` column is a toposort position). Node counts MEASURED on the py side:
# threefry 12, mulacc 10, getaddr 2, unshard 8, wmma 11 -- and the fixtures'
# docstrings' own censuses are wrong (mulacc/unshard/wmma say "4 nodes"; the rows are
# 10/8/11), so the ROWS are the specification and the prose is not.
#
# The three RESTORED graphs (`allred`, `cdiv`, `late`) have their own arm block ABOVE,
# beside these five, and the same rule: the py rows are the specification.
#
# (This comment sits AFTER `rows.pick` because the dispatcher was MOVED to its top; the
# eight arms are defined BEFORE `rows.pick3` because a forward reference does not
# compile here -- MEASURED, commit `3ae870111`.)

# `--graph getaddr`: `UOp(Ops.GETADDR, src=(alloc,), arg="CPU")`, 2 nodes. The ALLOC
# is `alloc(0, 12)` -- f32, bind_on_realize True. GETADDR's arg is the port's `ADev`,
# a `S.Dev`, resolved to a NAME through the arena's own device table (`sCPU`).
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
