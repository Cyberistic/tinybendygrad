# tinybendygrad/renderer/kuconv.bend -- the port's own arena -> the renderer's
# `List<KU>`.
#
# `renderer/cstyle.bend` DECLARES `KU` AND CONSUMES A `List<&2, KU>`, AND
# BEFORE THIS FILE NO DEF IN THE PORT PRODUCED ONE -- SO THE RENDERER HAD NO
# INPUT AND THE PORT HAD NO DEVICE.
#
# THE DELTA IS THE `srcs` FIELD, AND IT IS A RE-INDEXING.  `KU.srcs` are
#
# THE UPSTREAM SIDE OF EVERY FIELD, WITH `file:line`:
#
#   | `KU` field | upstream                        | the port                          |
#   |-------------|---------------------------------|-----------------------------------|
#   | `op`        | `u.op`  (ops.py:253)            | `O.Arena.op(ar, i)` (ops.bend:1385) |

import Base
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../LAWS/spec.bend as S
import ./../helpers.bend as H
import ./cstyle.bend as C

# the position map.  `kuconv.pos` answers "at which position in the `KU` list
def kuconv.pos.go(ix: List<&2, U32>, +want: U32, +n: U32) -> U32:
  match ix:
    case Nil{}: 0
    case h <> t: Bool.pick(U32, U32.is_eq(h, want), n, kuconv.pos.go(t, want, U32.add(n, 1)))

def kuconv.pos(ix: List<&2, U32>, want: U32) -> U32:
  kuconv.pos.go(ix, want, 0)

def kuconv.srcs.go(+ix: List<&2, U32>, ss: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: acc
    case s <> t: kuconv.srcs.go(ix, t, List.append(&2, U32, acc, [kuconv.pos(ix, s)]))

def kuconv.srcs(ix: List<&2, U32>, ss: List<&2, U32>) -> List<&2, U32>:
  kuconv.srcs.go(ix, ss, Nil{})

# the dtype.  `F.fold.dt` is a double-`Maybe` free read: the outer one is
# "the FOLD knows this node", and a node the FOLD does not know has no
# dtype, which upstream also does not have (its `dtype_from_uop` is total
# BECAUSE IT NEVER DEFERS).
#
# `S.void()` is the default because that is what upstream's `Ops.SINK` and
# `Ops.END` answer (`ops.py:247`'s ladder), and a void dtype is what makes
def kuconv.dt(+fx: F.Folded, a: U32) -> S.Dt:
  Maybe.default(&2, S.Dt, F.fold.dt(F.Folded.ar(fx), F.Folded.t(fx), a), S.void())

# the addrspace.  the FOLD answers `Maybe<Maybe<S.Addr>>`: the outer one is
# "the FOLD knows this node" and the inner one is "the node has an
# ADDRSPACE" (`ops.py:896` ANSWERS `None` FOR A SINK).  `S.Aalu{}` IS THE
# default because upstream's `Ops.CONST`/`Ops.RANGE`/`Ops.SPECIAL` are alu
# (`ops.py:899`) and a sink's `None` is spelled `ALU` in the renderer's own
def kuconv.addr.go(m: Maybe<&2, Maybe<&2, S.Addr>>) -> S.Addr:
  match m:
    case Some{x}: Maybe.default(&2, S.Addr, x, S.Aalu{})
    case None{}: S.Aalu{}

def kuconv.addr(+fx: F.Folded, a: U32) -> S.Addr:
  kuconv.addr.go(F.fold.addr(F.Folded.ar(fx), F.Folded.t(fx), a))

# the shape.  `F.fold.shape` is a double-`Maybe` too: the outer one is "the
# FOLD knows this node" and the inner one is "`_shape` is not None"
# (`ops.py:323`).  a `None` shape and an unknown node are the same empty
# list here, and both give a `numel` of one -- which is upstream's answer,
# BECAUSE `max_numel` IS `prod(max_shape)` AND `max_shape` OF AN ABSENT SHAPE
# IS `()` (`movement.py:55`).
#
# `O.Sint` IS EITHER A LITERAL (`SI{i}`) OR A SYMBOLIC DIMENSION (`SU{u}`),
# AND `KU.shape` IS A `List<&2, U32>`.  `SI{i}` IS AN `H.I64` AND `KU.shape`
# IS `U32`, SO THE LOW WORD IS THE answer.
#
# `SU{u}` IS A NAMED LIMIT AND NOT A SILENT ONE: upstream's `max_shape`
# REPLACES A SYMBOLIC DIMENSION WITH ITS MAXIMUM (`ops.py:1861`'s
# `to_max_shape`), AND `to_max_shape` IS A WALL IN THIS PORT
# (`renderer/cstyle.bend` NAMES IT).  SO A `SU` HAS NO `U32` ANSWER HERE AND
# THE CONVERTER ANSWERS ZERO -- WRONG IS THE POINT: A SYMBOLIC DIMENSION THAT
# RENDERED AS A PLAUSIBLE NUMBER WOULD BE A KERNEL THAT COMPILES AND
# MISCOMPUTES.  ALL FIVE OF THE MEASURED CPU KERNELS HAVE CONCRETE SHAPES.
def kuconv.sint(s: O.Sint) -> U32:
  match s:
    case O.SI{i}: H.lo32(i)
    case O.SU{u}: 0

def kuconv.shape.list.go(xs: List<&2, O.Sint>, +acc: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: acc
    case h <> t: kuconv.shape.list.go(t, List.append(&2, U32, acc, [kuconv.sint(h)]))
def kuconv.shape.list(m: Maybe<&2, List<&2, O.Sint>>) -> List<&2, U32>:
  match m:
    case Some{xs}: kuconv.shape.list.go(xs, Nil{})
    case None{}: Nil{}

def kuconv.shape.go(m: Maybe<&2, Maybe<&2, List<&2, O.Sint>>>) -> List<&2, U32>:
  match m:
    case Some{x}: kuconv.shape.list(x)
    case None{}: Nil{}

def kuconv.shape(+fx: F.Folded, a: U32) -> List<&2, U32>:
  kuconv.shape.go(F.fold.shape(F.Folded.ar(fx), F.Folded.t(fx), a))

# the numel.  `prod(shape)`, with an empty shape giving one -- which is
# UPSTREAM'S `prod(())` (`helpers.py`'s `prod` IS 1 ON AN EMPTY TUPLE, AND
# `cstyle.py:162` SAYS SO IN PROSE ABOUT `launch_bounds`).
def kuconv.numel.go(ss: List<&2, U32>, +acc: U32) -> U32:
  match ss:
    case Nil{}: acc
    case h <> t: kuconv.numel.go(t, U32.mul(acc, h))

def kuconv.numel(ss: List<&2, U32>) -> U32:
  kuconv.numel.go(ss, 1)

# the ARG.  the `O.Arg` variant is the discriminator, and each arm is one
# `O.Arg` -> ONE `KUArg`.
#
# `KAParam`'s `bytes` IS `numel * itemsize`, WHICH IS UPSTREAM'S OWN SPELLING
def kuconv.arg.of(nm: U32, dt: S.Dt, arg: O.Arg) -> C.KUArg:
  match arg:
    case O.APy{v}: C.KAConst{v}
    case O.AParam{+pa}: C.KAParam{O.ParamArg.slot(pa), O.ParamArg.name(pa),
      O.ParamArg.volatile(pa), U32.mul(nm, S.Dt.itemsize(dt))}
    case O.ARange{ids, at}: C.KARange{at, ids}
    case O.AOpLit{op}: C.KAIndex{0, O.eq_op(op, O.OpsADD{})}
    case O.AInt{i}: C.KAIndex{i, False{}}
    case O.AKernel{ki}: C.KASink{O.KernelInfo.name(ki)}
    case _: C.KANone{}

def kuconv.arg(+ar: O.Arena, +fx: F.Folded, a: U32, nm: U32, dt: S.Dt) -> C.KUArg:
  kuconv.arg.of(nm, dt, O.Arena.arg(ar, a))

# the completion pass -- and why it is here.
#
# the port's own FOLD does not settle on a program with a symbolic shrink
# OFFSET: `fold.bend:1689 symbol=sym_dim.of`'s `sym_dim` REFUSES EVERY `Arg`
# THAT IS NOT A CONST, A PARAM OR A SPECIAL, WHERE UPSTREAM's `as_shape`
# ANSWERS `(ssimplify(self),)` FOR AN EXPRESSION (`ops.py:783-786`).  A FOLD
def ku_c.src(+done: List<&2, C.KU>, p: U32) -> Maybe<&2, C.KU>:
  List.get(&2, C.KU, done, U32.to_nat(p))

def ku_c.dt0.go(m: Maybe<&2, C.KU>, +k: C.KU) -> S.Dt:
  match m:
    case Some{s}: C.KU.dtype(s)
    case None{}: C.KU.dtype(k)

def ku_c.dt0(+done: List<&2, C.KU>, +k: C.KU) -> S.Dt:
  ku_c.dt0.go(ku_c.src(done, C.KU.src0(k)), k)

def ku_c.sh0.go(m: Maybe<&2, C.KU>, +k: C.KU) -> List<&2, U32>:
  match m:
    case Some{s}: C.KU.shape(s)
    case None{}: C.KU.shape(k)

def ku_c.sh0(+done: List<&2, C.KU>, +k: C.KU) -> List<&2, U32>:
  ku_c.sh0.go(ku_c.src(done, C.KU.src0(k)), k)

def ku_c.ad0.go(m: Maybe<&2, C.KU>, +k: C.KU) -> S.Addr:
  match m:
    case Some{s}: C.KU.addr(s)
    case None{}: C.KU.addr(k)

def ku_c.ad0(+done: List<&2, C.KU>, +k: C.KU) -> S.Addr:
  ku_c.ad0.go(ku_c.src(done, C.KU.src0(k)), k)

# the SRC's shape with its first dimension dropped -- `ops.py:343-346`'s
# `tuple(shp) + self.src[0].shape[len(self.src[1:]):]`, WITH THE INDEX
# exprs' own shapes being empty in every measured kernel.
def ku_c.drop1(+xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: Nil{}
    case _ <> t: t

# the constant value a node carries, following a CAST to its own SRC -- the
# PORT's SPELLING OF UPSTREAM's `ssimplify` (`ops.py:783-786`'s `as_shape`).
def ku_c.cval.src(m: Maybe<&2, C.KU>) -> Maybe<&1, H.I64>:
  match m:
    case Some{s}: C.KUArg.const_int(C.KU.arg(s))
    case None{}: None{}

def ku_c.cval.go(m: Maybe<&1, H.I64>, m2: Maybe<&2, C.KU>) -> Maybe<&1, H.I64>:
  match m:
    case Some{v}: Some{v}
    case None{}: ku_c.cval.src(m2)

def ku_c.cval(+done: List<&2, C.KU>, +k: C.KU) -> Maybe<&1, H.I64>:
  ku_c.cval.go(C.KUArg.const_int(C.KU.arg(k)), ku_c.src(done, C.KU.src0(k)))

def ku_c.promo.step(m: Maybe<&2, C.KU>, +want: S.Dt, +acc: S.Dt) -> S.Dt:
  match m:
    case Some{+s}: Bool.pick(S.Dt, O.eq_dt(C.KU.dtype(s), want), acc, C.KU.dtype(s))
    case None{}: acc

def ku_c.promo.go(+done: List<&2, C.KU>, ss: List<&2, U32>, +want: S.Dt, +acc: S.Dt) -> S.Dt:
  match ss:
    case Nil{}: acc
    case h <> t: ku_c.promo.go(done, t, want, ku_c.promo.step(ku_c.src(done, h), want, acc))

def ku_c.promo(+done: List<&2, C.KU>, +k: C.KU) -> S.Dt:
  ku_c.promo.go(done, C.KU.srcs(k), C.KU.dtype(k), C.KU.dtype(k))

# THE WHERE's PROMO IS OVER `src[1:]` (`ops.py:152-153`), SO THE CONDITION IS
# LEFT OUT.
def ku_c.promo2.go(m: Maybe<&2, C.KU>, +done: List<&2, C.KU>, +k: C.KU) -> S.Dt:
  match m:
    case Some{+s}: ku_c.promo.go(done, ku_c.drop1(C.KU.srcs(k)), C.KU.dtype(s), C.KU.dtype(s))
    case None{}: C.KU.dtype(k)

def ku_c.promo2(+done: List<&2, C.KU>, +k: C.KU) -> S.Dt:
  ku_c.promo2.go(ku_c.src(done, C.KU.src1(k)), done, k)

# the void-by-nature ops: a STORE, an END and a SINK ARE VOID AND MUST STAY
# VOID; EVERY OTHER VOID ANSWER MEANS "THE FOLD REFUSED".
def ku_c.void_op(+op: O.Op) -> Bool:
  Bool.or(Bool.or(O.eq_op(op, O.OpsSTORE{}), O.eq_op(op, O.OpsEND{})),
    Bool.or(O.eq_op(op, O.OpsSINK{}), O.eq_op(op, O.OpsNOOP{})))

def ku_c.refused(+op: O.Op, +k: C.KU) -> Bool:
  Bool.and(Bool.not(ku_c.void_op(op)), O.eq_dt(C.KU.dtype(k), S.void()))

# THE SHRINK's SIZE: `ops.py:409`'s `tuple(sz for _, sz in self.marg)` -- THE
# SIZE IS THE CONSTANT AT `src[2]`, AND UPSTREAM SPELLS IT A CONST-CAST, SO
# THE CONSTANT IS READ THROUGH THE CAST.
def ku_c.size.val(v: Maybe<&1, H.I64>) -> List<&2, U32>:
  match v:
    case Some{n}: [H.lo32(n)]
    case None{}: Nil{}

def ku_c.size.go(m: Maybe<&2, C.KU>, +done: List<&2, C.KU>) -> List<&2, U32>:
  match m:
    case Some{s}: ku_c.size.val(ku_c.cval(done, s))
    case None{}: Nil{}

def ku_c.size(+done: List<&2, C.KU>, +k: C.KU) -> List<&2, U32>:
  ku_c.size.go(ku_c.src(done, C.KU.src2(k)), done)

def ku_c.dt.go(op: O.Op, +done: List<&2, C.KU>, k: C.KU) -> S.Dt:
  match op:
    case O.OpsSHRINK{}: ku_c.dt0(done, k)
    case O.OpsLOAD{}: ku_c.dt0(done, k)
    case O.OpsINDEX{}: ku_c.dt0(done, k)
    case O.OpsAFTER{}: ku_c.dt0(done, k)
    case O.OpsSHL{}: ku_c.dt0(done, k)
    case O.OpsCMPLT{}: S.boolean()
    case O.OpsWHERE{}: ku_c.promo2(done, k)
    case O.OpsADD{}: ku_c.promo(done, k)
    case O.OpsMUL{}: ku_c.promo(done, k)
    case _: C.KU.dtype(k)

def ku_c.sh.go(op: O.Op, +done: List<&2, C.KU>, k: C.KU) -> List<&2, U32>:
  match op:
    case O.OpsSHRINK{}: ku_c.size(done, k)
    case O.OpsLOAD{}: ku_c.sh0(done, k)
    case O.OpsINDEX{}: ku_c.drop1(ku_c.sh0(done, k))
    case O.OpsAFTER{}: ku_c.sh0(done, k)
    case _: C.KU.shape(k)

def ku_c.ad.go(op: O.Op, +done: List<&2, C.KU>, k: C.KU) -> S.Addr:
  match op:
    case O.OpsSHRINK{}: ku_c.ad0(done, k)
    case O.OpsINDEX{}: ku_c.ad0(done, k)
    case O.OpsAFTER{}: ku_c.ad0(done, k)
    case O.OpsLOAD{}: S.Aalu{}
    case O.OpsCMPLT{}: S.Aalu{}
    case O.OpsWHERE{}: S.Aalu{}
    case O.OpsADD{}: S.Aalu{}
    case O.OpsMUL{}: S.Aalu{}
    case O.OpsSHL{}: S.Aalu{}
    case _: C.KU.addr(k)

def ku_c.fill.of(+done: List<&2, C.KU>, +op: O.Op, +k: C.KU) -> C.KU:
  +dt = ku_c.dt.go(op, done, k)
  +sh = ku_c.sh.go(op, done, k)
  +ad = ku_c.ad.go(op, done, k)
  +nm = kuconv.numel(sh)
  C.KU{op, dt, ad, nm, sh, C.KU.arg(k), C.KU.srcs(k)}

def ku_c.fill(+done: List<&2, C.KU>, +k: C.KU) -> C.KU:
  Bool.pick(C.KU, ku_c.refused(C.KU.op(k), k), ku_c.fill.of(done, C.KU.op(k), k), k)

# the pass.  `done` is the completed list, in the same order as the input, so
def ku_c.go(+rest: List<&2, C.KU>, +done: List<&2, C.KU>) -> List<&2, C.KU>:
  match rest:
    case Nil{}: done
    case h <> t:
      +k = ku_c.fill(done, h)
      ku_c.go(t, List.append(&2, C.KU, done, [k]))

def kuconv.ku(+fx: F.Folded, +ix: List<&2, U32>, +a: U32) -> C.KU:
  +ar = F.Folded.ar(fx)
  +op = O.Arena.op(ar, a)
  +dt = kuconv.dt(fx, a)
  +ad = kuconv.addr(fx, a)
  +sh = kuconv.shape(fx, a)
  +nm = kuconv.numel(sh)
  +ag = kuconv.arg(ar, fx, a, nm, dt)
  +ss = kuconv.srcs(ix, O.Arena.srcs(ar, a))
  C.KU{op, dt, ad, nm, sh, ag, ss}

def kuconv.convert.go(+fx: F.Folded, +ix: List<&2, U32>, xs: List<&2, U32>,
                       +acc: List<&2, C.KU>) -> List<&2, C.KU>:
  match xs:
    case Nil{}: acc
    case h <> t: kuconv.convert.go(fx, ix, t,
      List.append(&2, C.KU, acc, [kuconv.ku(fx, ix, h)]))

def kuconv.convert(+fx: F.Folded, +ix: List<&2, U32>) -> List<&2, C.KU>:
  ku_c.go(kuconv.convert.go(fx, ix, ix, Nil{}), Nil{})
