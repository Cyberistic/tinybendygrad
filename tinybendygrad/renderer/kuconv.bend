# tinybendygrad/renderer/kuconv.bend -- THE CONVERTER.
#
# the port's own arena -> the renderer's `List<KU>`.
#
# `renderer/cstyle.bend:127` DECLARES `KU` AND `renderer/cstyle.bend:2297`
# consumes a `List<&2, KU>`, and before this file no DEF in the port produced
# ONE: `grep -rn 'KU{' tinybendygrad/ --include='*.bend'` ANSWERED EXACTLY ONE
# hit, the TYPE declaration itself.  so the renderer had no input and the
# PORT HAD NO DEVICE.
#
# the input is an arena and a list of arena indices, and the list is in the
# port's own post-order (children before parents) -- which is what
# `codegen/late/linearizer.bend:836 linearize` returns and what upstream's
# `tinygrad/codegen/late/linearizer.py:8-51 linearize` returns.
#

# the whole problem is the `srcs` field, and it is a re-indexing.
#
# `KU.srcs` are positions in the `KU` list, not arena indices.  the
# RENDERER'S `r` MAP IS A LIST INDEXED BY POSITION (`cstyle.bend:1896` says so
# in prose) because the list is post-order: every uop's srcs sit at a lower
# INDEX, SO A POSITION IS ALSO A "DEFINED BEFORE" MARKER.
#
# so: for each node, each SRC's arena INDEX must become the position of that
# SRC in the `KU` list.  the converter computes that position by searching
# the INDEX list, and that search is the entire delta between "an arena" and
# "A RENDERABLE LIST".
#
# the upstream side of every field, with `file:line`:
#
#   | `KU` field | upstream                        | the port                          |
#   |-------------|---------------------------------|-----------------------------------|
#   | `op`        | `u.op`  (ops.py:253)            | `O.Arena.op(ar, i)` (ops.bend:1385) |
#   | `dtype`     | `u.dtype` (ops.py:239 symbol=dtype) | `F.fold.dt(ar, tb, i)` (uop/fold.bend:4833 symbol=fold.dt) |
#   | `addr`      | `u.addrspace` (ops.py:896)      | `F.fold.addr(ar, tb, i)` (fold.bend:4815) |
#     the port's reader for `addr` is fold.bend:4815 symbol=fold.addr
#   | `numel`     | `u.max_numel()` (movement.py:55)| `prod(shape)` of the fold's shape  |
#   | `shape`     | `u.shape` (movement.py:35)      | `F.fold.shape(ar, tb, i)` (fold.bend:4827) |
#     the port's reader for `shape` is fold.bend:4827 symbol=fold.shape
#   | `arg`       | `u.arg`  (ops.py:253)           | `O.Arena.arg(ar, i)` (ops.bend:1400) |
#   | `srcs`      | `u.src`  (ops.py:253)           | `O.Arena.srcs(ar, i)` (ops.bend:1406), RE-INDEXED |
#   the durable pointer for the `dtype` row is uop/fold.bend:4833 symbol=fold.dt
# the `arg` mapping, one row per `O.Arg` variant the renderer reads:
#
#   | `O.Arg`         | `KUArg`                       | who reads it                |
#   |-----------------|-------------------------------|-----------------------------|
#   | `APy{v}`        | `KAConst{v}`                  | `cstyle.bend:1366` symbol=ku_is_const_at |
#   | `AParam{pa}`    | `KAParam{slot,name,vol,bytes}`| `cstyle.bend:1648` symbol=ku_param_name |
#   | `ARange{ids,at}`| `KARange{at, ids}`            | `cstyle.bend:1614` symbol=ku_range_name |
#   | `AOpLit{op}`    | `KAIndex{0, op == Ops.ADD}`   | `cstyle.bend:2078` symbol=ku_render_index |
#   | `AInt{i}`       | `KAIndex{i, False{}}`          | `cstyle.bend:2078` symbol=ku_render_index |
#   | `AKernel{ki}`   | `KASink{ki.name}`             | `cstyle.bend:1294` symbol=KUArg.sink_name |
#   |                 |                               | `KUArg.sink_name` in `_render.one.go` (`cstyle.bend:2212-2217`) |
#   | everything else | `KANone{}`                    | --                          |
#
# `AOpLit` IS UPSTREAM's `idx.arg == Ops.ADD` TEST (`cstyle.py:174`): the
# INDEX's OWN arg is a BARE `Ops`, and upstream's `ops.py:432` stores it as
# `arg=Ops.ADD`.  THE PORT SPELLS A BARE `Op` AS `AOpLit{op}`
# (`uop/ops.bend:1247` symbol=AOpLit), AND THE CONVERTER COMPARES IT TO `OpsADD` ITSELF.
#
# `AInt` is the other INDEX form: upstream's INDEX carries an integer OFFSET
# WHEN IT IS NOT AN `Ops.ADD` (`ops.py:432`'s `arg` is `int` for the offset
# form), AND THE CONVERTER KEEPS THE OFFSET IN `KAIndex.off`.

import Base
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../LAWS/spec.bend as S
import ./../helpers.bend as H
import ./cstyle.bend as C


# the position map.  `kuconv.pos` answers "at which position in the `KU` list
# does this arena INDEX stand", and the answer is a search, not a table:
# the list is short (a kernel's worth of nodes) and a table would be a second
# COPY OF THE LIST.
#
# the missing case answers `0`, and `0` is also the position of the first
# node, so a missing SRC is not distinguishable from the first node by the
# answer alone.  that is why the converter's own rows are the BYTE
# comparison and not a count: a converter that dropped a SRC would render a
# different kernel, not a different number of rows.
def kuconv.pos.go(ix: List<&2, U32>, +want: U32, +n: U32) -> U32:
  match ix:
    case Nil{}: 0
    case h <> t: Bool.pick(U32, U32.is_eq(h, want), n, kuconv.pos.go(t, want, U32.add(n, 1)))

def kuconv.pos(ix: List<&2, U32>, want: U32) -> U32:
  kuconv.pos.go(ix, want, 0)

# the re-INDEX itself.  `O.Arena.srcs` gives arena indices; this gives
# POSITIONS.
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
# THE RENDERER SKIP THE DECLARATION (`cstyle.bend:1652` `ku_is_decl`).
def kuconv.dt(+fx: F.Folded, a: U32) -> S.Dt:
  Maybe.default(&2, S.Dt, F.fold.dt(F.Folded.ar(fx), F.Folded.t(fx), a), S.void())

# the addrspace.  the FOLD answers `Maybe<Maybe<S.Addr>>`: the outer one is
# "the FOLD knows this node" and the inner one is "the node has an
# ADDRSPACE" (`ops.py:896` ANSWERS `None` FOR A SINK).  `S.Aalu{}` IS THE
# default because upstream's `Ops.CONST`/`Ops.RANGE`/`Ops.SPECIAL` are alu
# (`ops.py:899`) and a sink's `None` is spelled `ALU` in the renderer's own
# FIXTURE (`gen_kus.py`'s `ADDRS` TABLE MAPS `NONE` TO `S.Aalu{}`).
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
# the `O.Sint` -> `U32` conversion is the one that has to be spelled.
# `O.Sint` IS EITHER A LITERAL (`SI{i}`) OR AN ARENA INDEX (`SU{u}`, A
# SYMBOLIC DIMENSION), AND `KU.shape` IS A `List<&2, U32>`.
#
# the symbolic case is a named limit and not a silent one.  upstream's
# `max_numel` IS `prod(max_shape)` AND `max_shape` REPLACES A SYMBOLIC
# DIMENSION WITH ITS MAXIMUM (`ops.py:1896`'s `to_max_shape`), AND `to_max_shape`
# IS A WALL IN THIS PORT (`renderer/cstyle.bend:60` NAMES IT).  SO A `SU`
# has no `U32` answer here and the converter answers zero, which makes
# the `numel` zero and the kernel wrong.  a concrete shape is fine, and all
# five of the measured CPU kernels have concrete shapes.
# `SI{i}` IS AN `H.I64` AND `KU.shape` IS `U32`, SO THE LOW WORD IS THE
# answer.  a shape dimension bigger than 2^32 is not a thing a kernel has.
#
# `SU{u}` is a symbolic dimension and it has no `U32` answer here: the
# answer is zero, which makes the `numel` zero and the kernel wrong, and
# wrong is the point -- a symbolic dimension that rendered as a plausible
# number would be a kernel that compiles and miscomputes.  see the header.
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
# FOR A PARAM's SIZE IN BYTES (`dump_kernel.py`'s `str(u.max_numel() *
# u.dtype.itemsize)`), AND `S.Dt.itemsize` IS THE PORT's OWN READER
# (`LAWS/spec.bend:176`).
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
# OFFSET: `fold.bend:1704 symbol=sym_dim.of`'s `sym_dim` REFUSES EVERY `Arg` THAT IS NOT A
# CONST, A PARAM OR A SPECIAL, WHERE UPSTREAM's `as_shape` ANSWERS
# `(ssimplify(self),)` FOR AN EXPRESSION (`ops.py:783-786`).  A FOLD THAT DOES
# not settle answers `void` for every node downstream of the refusal, and
# every node downstream of a `SHRINK` is a node the renderer reads.
#
# so the completion pass re-answers, for every node whose FOLD answer was
# void and whose op is not void by nature (a STORE, an end and a sink are
# void and must stay void), the `dtype`, the `shape`, the `numel` and the
# `addr`.
#
# the rules are upstream's own, spelled over the port's own `KU` list, and the
# srcs are read from the already completed list -- which is at lower
# positions, because the list is post-order.
#
#   ops.py:136-138  INDEX          : src[0].dtype
#   ops.py:141-142  LOAD/AFTER/END : src[0].dtype
#   ops.py:152-153  WHERE          : promo_dtype(src[1:])
#   ops.py:163-165  SHL/SHR        : src[0].dtype
#   ops.py:186      Broadcastable  : promo_dtype(src)
#   ops.py:189      Movement       : src[0].dtype
#   ops.py:409      SHRINK         : tuple(sz for _, sz in self.marg)
#
# `promo_dtype` (`ops.py:111-113`) IS `dts[0] if all_same(dts) else
# least_upper_dtype(*dts)`, and the least upper of two dtypes that differ
# is not spelled here: the completion answers the first SRC's dtype when all
# the srcs agree and the first SRC's dtype otherwise, which is the answer
# for every node of the five measured kernels (their srcs agree) and is named
# AS A LIMIT FOR THE OTHERS.


# the completed SRC at a position.  `done` is in the same order as the `KU`
# LIST, SO POSITION `p` IS POSITION `p`.
def ku_c.src(+done: List<&2, C.KU>, p: U32) -> Maybe<&2, C.KU>:
  List.get(&2, C.KU, done, U32.to_nat(p))

# every reader below is a `.go` pair, because a `match` may not scrutinize a
# computed value and may not scrutinize a local binder (`cstyle.bend`'s own
# HOUSE STYLE, `ku_op_at.go` AND `ku_ptr.go`).
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

# the promo of the srcs' dtypes: the first when they all agree, the first
# regardless otherwise (the named limit above).
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

# the void-by-nature ops, and the test for "the FOLD refused".
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

# one completed node.  the op-specific rules, in upstream's own order.  each
# of the three is a `.go` DEF, because a `match` heads a DEF body and is not a
# TERM.
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
# POSITION `p` IS POSITION `p` IN BOTH.
#
# the argument order is (shrinking, changing), which is `linearizer.bend`'s own
# `lt_deg.go(+ar, rest, +acc)` shape with the unchanged argument dropped: the
# compiler reads the arguments left to right and each is passed unchanged
# UNTIL ONE SHRINKS.
def ku_c.go(+rest: List<&2, C.KU>, +done: List<&2, C.KU>) -> List<&2, C.KU>:
  match rest:
    case Nil{}: done
    case h <> t:
      +k = ku_c.fill(done, h)
      ku_c.go(t, List.append(&2, C.KU, done, [k]))


# one node.  the seven fields, in `KU`'s own order.
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


# the converter.  an arena (through its FOLD) and a list of arena indices in
# post-order, and a `List<&2, KU>` in the same order, with every `srcs`
# RE-INDEXED TO A POSITION.
def kuconv.convert.go(+fx: F.Folded, +ix: List<&2, U32>, xs: List<&2, U32>,
                       +acc: List<&2, C.KU>) -> List<&2, C.KU>:
  match xs:
    case Nil{}: acc
    case h <> t: kuconv.convert.go(fx, ix, t,
      List.append(&2, C.KU, acc, [kuconv.ku(fx, ix, h)]))

def kuconv.convert(+fx: F.Folded, +ix: List<&2, U32>) -> List<&2, C.KU>:
  ku_c.go(kuconv.convert.go(fx, ix, ix, Nil{}), Nil{})
