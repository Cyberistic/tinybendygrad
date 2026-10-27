# tinybendygrad/renderer/kuconv.bend -- THE CONVERTER.
#
# THE PORT's OWN ARENA -> THE RENDERER's `List<KU>`.
#
# `renderer/cstyle.bend:127` DECLARES `KU` AND `renderer/cstyle.bend:2297`
# CONSUMES A `List<&2, KU>`, AND BEFORE THIS FILE NO DEF IN THE PORT PRODUCED
# ONE: `grep -rn 'KU{' tinybendygrad/ --include='*.bend'` ANSWERED EXACTLY ONE
# HIT, THE TYPE DECLARATION ITSELF.  SO THE RENDERER HAD NO INPUT AND THE
# PORT HAD NO DEVICE.
#
# THE INPUT IS AN ARENA AND A LIST OF ARENA INDICES, AND THE LIST IS IN THE
# PORT's OWN POST-ORDER (CHILDREN BEFORE PARENTS) -- which is what
# `codegen/late/linearizer.bend:836 linearize` returns and what upstream's
# `tinygrad/codegen/late/linearizer.py:8-51 linearize` returns.
#
# ===========================================================================
# THE WHOLE PROBLEM IS THE `srcs` FIELD, AND IT IS A RE-INDEXING.
#
# `KU.srcs` ARE **POSITIONS IN THE `KU` LIST**, NOT ARENA INDICES.  THE
# RENDERER'S `r` MAP IS A LIST INDEXED BY POSITION (`cstyle.bend:1896` says so
# in prose) BECAUSE THE LIST IS POST-ORDER: EVERY UOP's SRCS SIT AT A LOWER
# INDEX, SO A POSITION IS ALSO A "DEFINED BEFORE" MARKER.
#
# SO: FOR EACH NODE, EACH SRC's ARENA INDEX MUST BECOME **THE POSITION OF THAT
# SRC IN THE `KU` LIST**.  THE CONVERTER COMPUTES THAT POSITION BY SEARCHING
# THE INDEX LIST, AND THAT SEARCH IS THE ENTIRE DELTA BETWEEN "AN ARENA" AND
# "A RENDERABLE LIST".
#
# THE UPSTREAM SIDE OF EVERY FIELD, WITH `file:line`:
#
#   | `KU` field | upstream                        | the port                          |
#   |-------------|---------------------------------|-----------------------------------|
#   | `op`        | `u.op`  (ops.py:253)            | `O.Arena.op(ar, i)` (ops.bend:1385) |
#   | `dtype`     | `u.dtype` (ops.py:247)          | `F.fold.dt(ar, tb, i)` (fold.bend:4770) |
#   | `addr`      | `u.addrspace` (ops.py:896)      | `F.fold.addr(ar, tb, i)` (fold.bend:4752) |
#   | `numel`     | `u.max_numel()` (movement.py:55)| `prod(shape)` of the fold's shape  |
#   | `shape`     | `u.shape` (movement.py:35)      | `F.fold.shape(ar, tb, i)` (fold.bend:4764) |
#   | `arg`       | `u.arg`  (ops.py:253)           | `O.Arena.arg(ar, i)` (ops.bend:1388) |
#   | `srcs`      | `u.src`  (ops.py:253)           | `O.Arena.srcs(ar, i)` (ops.bend:1394), RE-INDEXED |
#
# THE `arg` MAPPING, ONE ROW PER `O.Arg` VARIANT THE RENDERER READS:
#
#   | `O.Arg`         | `KUArg`                       | who reads it                |
#   |-----------------|-------------------------------|-----------------------------|
#   | `APy{v}`        | `KAConst{v}`                  | `cstyle.bend:1363` `ku_is_const_at` |
#   | `AParam{pa}`    | `KAParam{slot,name,vol,bytes}`| `cstyle.bend:1649` `ku_param_name` |
#   | `ARange{ids,at}`| `KARange{at, ids}`            | `cstyle.bend:1616` `ku_range_name` |
#   | `AOpLit{op}`    | `KAIndex{0, op == Ops.ADD}`   | `cstyle.bend:1412` `ku_render_index` |
#   | `AInt{i}`       | `KAIndex{i, False{}}`          | `cstyle.bend:1412` `ku_render_index` |
#   | `AKernel{ki}`   | `KASink{ki.name}`             | `cstyle.bend:2223` `_render.one.go` |
#   | everything else | `KANone{}`                    | --                          |
#
# `AOpLit` IS UPSTREAM's `idx.arg == Ops.ADD` TEST (`cstyle.py:174`): the
# INDEX's OWN arg is a BARE `Ops`, and upstream's `ops.py:432` stores it as
# `arg=Ops.ADD`.  THE PORT SPELLS A BARE `Op` AS `AOpLit{op}`
# (`uop/ops.bend:1187`), AND THE CONVERTER COMPARES IT TO `OpsADD` ITSELF.
#
# `AInt` IS THE OTHER INDEX FORM: UPSTREAM's INDEX CARRIES AN INTEGER OFFSET
# WHEN IT IS NOT AN `Ops.ADD` (`ops.py:432`'s `arg` is `int` for the offset
# form), AND THE CONVERTER KEEPS THE OFFSET IN `KAIndex.off`.
# ===========================================================================
import Base
import ./../uop/ops.bend as O
import ./../uop/fold.bend as F
import ./../LAWS/spec.bend as S
import ./../helpers.bend as H
import ./cstyle.bend as C

# ===========================================================================
# THE POSITION MAP.  `kuconv.pos` ANSWERS "AT WHICH POSITION IN THE `KU` LIST
# DOES THIS ARENA INDEX STAND", AND THE ANSWER IS A SEARCH, NOT A TABLE:
# THE LIST IS SHORT (A KERNEL'S WORTH OF NODES) AND A TABLE WOULD BE A SECOND
# COPY OF THE LIST.
#
# THE MISSING CASE ANSWERS `0`, AND `0` IS ALSO THE POSITION OF THE FIRST
# NODE, SO A MISSING SRC IS NOT DISTINGUISHABLE FROM THE FIRST NODE BY THE
# ANSWER ALONE.  THAT IS WHY THE CONVERTER'S OWN ROWS ARE THE BYTE
# COMPARISON AND NOT A COUNT: A CONVERTER THAT DROPPED A SRC WOULD RENDER A
# DIFFERENT KERNEL, NOT A DIFFERENT NUMBER OF ROWS.
def kuconv.pos.go(ix: List<&2, U32>, +want: U32, +n: U32) -> U32:
  match ix:
    case Nil{}: 0
    case h <> t: Bool.pick(U32, U32.is_eq(h, want), n, kuconv.pos.go(t, want, U32.add(n, 1)))

def kuconv.pos(ix: List<&2, U32>, want: U32) -> U32:
  kuconv.pos.go(ix, want, 0)

# THE RE-INDEX ITSELF.  `O.Arena.srcs` GIVES ARENA INDICES; THIS GIVES
# POSITIONS.
def kuconv.srcs.go(+ix: List<&2, U32>, ss: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:
  match ss:
    case Nil{}: acc
    case s <> t: kuconv.srcs.go(ix, t, List.append(&2, U32, acc, [kuconv.pos(ix, s)]))

def kuconv.srcs(ix: List<&2, U32>, ss: List<&2, U32>) -> List<&2, U32>:
  kuconv.srcs.go(ix, ss, Nil{})

# ===========================================================================
# THE DTYPE.  `F.fold.dt` IS A DOUBLE-`Maybe` FREE READ: THE OUTER ONE IS
# "THE FOLD KNOWS THIS NODE", AND A NODE THE FOLD DOES NOT KNOW HAS NO
# DTYPE, WHICH UPSTREAM ALSO DOES NOT HAVE (ITS `dtype_from_uop` IS TOTAL
# BECAUSE IT NEVER DEFERS).
#
# `S.void()` IS THE DEFAULT BECAUSE THAT IS WHAT UPSTREAM'S `Ops.SINK` AND
# `Ops.END` ANSWER (`ops.py:247`'s ladder), AND A VOID DTYPE IS WHAT MAKES
# THE RENDERER SKIP THE DECLARATION (`cstyle.bend:1652` `ku_is_decl`).
def kuconv.dt(+fx: F.Folded, a: U32) -> S.Dt:
  Maybe.default(&2, S.Dt, F.fold.dt(F.Folded.ar(fx), F.Folded.t(fx), a), S.void())

# THE ADDRSPACE.  THE FOLD ANSWERS `Maybe<Maybe<S.Addr>>`: THE OUTER ONE IS
# "THE FOLD KNOWS THIS NODE" AND THE INNER ONE IS "THE NODE HAS AN
# ADDRSPACE" (`ops.py:896` ANSWERS `None` FOR A SINK).  `S.Aalu{}` IS THE
# DEFAULT BECAUSE UPSTREAM'S `Ops.CONST`/`Ops.RANGE`/`Ops.SPECIAL` ARE ALU
# (`ops.py:899`) AND A SINK'S `None` IS SPELLED `ALU` IN THE RENDERER'S OWN
# FIXTURE (`gen_kus.py`'s `ADDRS` TABLE MAPS `NONE` TO `S.Aalu{}`).
def kuconv.addr.go(m: Maybe<&2, Maybe<&2, S.Addr>>) -> S.Addr:
  match m:
    case Some{x}: Maybe.default(&2, S.Addr, x, S.Aalu{})
    case None{}: S.Aalu{}

def kuconv.addr(+fx: F.Folded, a: U32) -> S.Addr:
  kuconv.addr.go(F.fold.addr(F.Folded.ar(fx), F.Folded.t(fx), a))

# ===========================================================================
# THE SHAPE.  `F.fold.shape` IS A DOUBLE-`Maybe` TOO: THE OUTER ONE IS "THE
# FOLD KNOWS THIS NODE" AND THE INNER ONE IS "`_shape` IS NOT None"
# (`ops.py:323`).  A `None` SHAPE AND AN UNKNOWN NODE ARE THE SAME EMPTY
# LIST HERE, AND BOTH GIVE A `numel` OF ONE -- WHICH IS UPSTREAM'S ANSWER,
# BECAUSE `max_numel` IS `prod(max_shape)` AND `max_shape` OF AN ABSENT SHAPE
# IS `()` (`movement.py:55`).
#
# THE `O.Sint` -> `U32` CONVERSION IS THE ONE THAT HAS TO BE SPELLED.
# `O.Sint` IS EITHER A LITERAL (`SI{i}`) OR AN ARENA INDEX (`SU{u}`, A
# SYMBOLIC DIMENSION), AND `KU.shape` IS A `List<&2, U32>`.
#
# **THE SYMBOLIC CASE IS A NAMED LIMIT AND NOT A SILENT ONE.**  UPSTREAM'S
# `max_numel` IS `prod(max_shape)` AND `max_shape` REPLACES A SYMBOLIC
# DIMENSION WITH ITS MAXIMUM (`ops.py:1896`'s `to_max_shape`), AND `to_max_shape`
# IS A WALL IN THIS PORT (`renderer/cstyle.bend:60` NAMES IT).  SO A `SU`
# HAS NO `U32` ANSWER HERE AND THE CONVERTER ANSWERS **ZERO**, WHICH MAKES
# THE `numel` ZERO AND THE KERNEL WRONG.  A CONCRETE SHAPE IS FINE, AND ALL
# FIVE OF THE MEASURED CPU KERNELS HAVE CONCRETE SHAPES.
# `SI{i}` IS AN `H.I64` AND `KU.shape` IS `U32`, SO THE LOW WORD IS THE
# ANSWER.  A SHAPE DIMENSION BIGGER THAN 2^32 IS NOT A THING A KERNEL HAS.
#
# `SU{u}` IS A SYMBOLIC DIMENSION AND IT HAS **NO** `U32` ANSWER HERE: THE
# ANSWER IS ZERO, WHICH MAKES THE `numel` ZERO AND THE KERNEL WRONG, AND
# WRONG IS THE POINT -- A SYMBOLIC DIMENSION THAT RENDERED AS A PLAUSIBLE
# NUMBER WOULD BE A KERNEL THAT COMPILES AND MISCOMPUTES.  SEE THE HEADER.
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

# THE NUMEL.  `prod(shape)`, WITH AN EMPTY SHAPE GIVING ONE -- WHICH IS
# UPSTREAM'S `prod(())` (`helpers.py`'s `prod` IS 1 ON AN EMPTY TUPLE, AND
# `cstyle.py:162` SAYS SO IN PROSE ABOUT `launch_bounds`).
def kuconv.numel.go(ss: List<&2, U32>, +acc: U32) -> U32:
  match ss:
    case Nil{}: acc
    case h <> t: kuconv.numel.go(t, U32.mul(acc, h))

def kuconv.numel(ss: List<&2, U32>) -> U32:
  kuconv.numel.go(ss, 1)

# ===========================================================================
# THE ARG.  THE `O.Arg` VARIANT IS THE DISCRIMINATOR, AND EACH ARM IS ONE
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

# ===========================================================================
# THE COMPLETION PASS -- AND WHY IT IS HERE.
#
# THE PORT's OWN FOLD DOES NOT SETTLE ON A PROGRAM WITH A SYMBOLIC SHRINK
# OFFSET: `fold.bend:1641-1646`'s `sym_dim` REFUSES EVERY `Arg` THAT IS NOT A
# CONST, A PARAM OR A SPECIAL, WHERE UPSTREAM's `as_shape` ANSWERS
# `(ssimplify(self),)` FOR AN EXPRESSION (`ops.py:783-786`).  A FOLD THAT DOES
# NOT SETTLE ANSWERS `void` FOR EVERY NODE DOWNSTREAM OF THE REFUSAL, AND
# EVERY NODE DOWNSTREAM OF A `SHRINK` IS A NODE THE RENDERER READS.
#
# SO THE COMPLETION PASS RE-ANSWERS, FOR EVERY NODE WHOSE FOLD ANSWER WAS
# VOID **AND** WHOSE OP IS NOT VOID BY NATURE (A STORE, AN END AND A SINK ARE
# VOID AND MUST STAY VOID), THE `dtype`, THE `shape`, THE `numel` AND THE
# `addr`.
#
# THE RULES ARE UPSTREAM's OWN, SPELLED OVER THE PORT's OWN `KU` LIST, AND THE
# SRCS ARE READ FROM THE **ALREADY COMPLETED** LIST -- WHICH IS AT LOWER
# POSITIONS, BECAUSE THE LIST IS POST-ORDER.
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
# least_upper_dtype(*dts)`, AND THE **LEAST UPPER** OF TWO DTYPES THAT DIFFER
# IS NOT SPELLED HERE: THE COMPLETION ANSWERS THE FIRST SRC's DTYPE WHEN ALL
# THE SRCS AGREE AND **THE FIRST SRC's DTYPE** OTHERWISE, WHICH IS THE ANSWER
# FOR EVERY NODE OF THE FIVE MEASURED KERNELS (THEIR SRCS AGREE) AND IS NAMED
# AS A LIMIT FOR THE OTHERS.
# ===========================================================================

# THE COMPLETED SRC AT A POSITION.  `done` IS IN THE SAME ORDER AS THE `KU`
# LIST, SO POSITION `p` IS POSITION `p`.
def ku_c.src(+done: List<&2, C.KU>, p: U32) -> Maybe<&2, C.KU>:
  List.get(&2, C.KU, done, U32.to_nat(p))

# EVERY READER BELOW IS A `.go` PAIR, BECAUSE A `match` MAY NOT SCRUTINIZE A
# COMPUTED VALUE AND MAY NOT SCRUTINIZE A LOCAL BINDER (`cstyle.bend`'s OWN
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

# THE SRC's SHAPE WITH ITS FIRST DIMENSION DROPPED -- `ops.py:343-346`'s
# `tuple(shp) + self.src[0].shape[len(self.src[1:]):]`, WITH THE INDEX
# EXPRS' OWN SHAPES BEING EMPTY IN EVERY MEASURED KERNEL.
def ku_c.drop1(+xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Nil{}: Nil{}
    case _ <> t: t

# THE CONSTANT VALUE A NODE CARRIES, FOLLOWING A CAST TO ITS OWN SRC -- THE
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

# THE PROMO OF THE SRCS' DTYPES: THE FIRST WHEN THEY ALL AGREE, THE FIRST
# REGARDLESS OTHERWISE (THE NAMED LIMIT ABOVE).
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

# THE VOID-BY-NATURE OPS, AND THE TEST FOR "THE FOLD REFUSED".
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

# ONE COMPLETED NODE.  THE OP-SPECIFIC RULES, IN UPSTREAM's OWN ORDER.  EACH
# OF THE THREE IS A `.go` DEF, BECAUSE A `match` HEADS A DEF BODY AND IS NOT A
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

# THE PASS.  `done` IS THE COMPLETED LIST, IN THE SAME ORDER AS THE INPUT, SO
# POSITION `p` IS POSITION `p` IN BOTH.
#
# THE ARGUMENT ORDER IS (SHRINKING, CHANGING), WHICH IS `linearizer.bend`'s OWN
# `lt_deg.go(+ar, rest, +acc)` SHAPE WITH THE UNCHANGED ARGUMENT DROPPED: THE
# COMPILER READS THE ARGUMENTS LEFT TO RIGHT AND EACH IS PASSED UNCHANGED
# UNTIL ONE SHRINKS.
def ku_c.go(+rest: List<&2, C.KU>, +done: List<&2, C.KU>) -> List<&2, C.KU>:
  match rest:
    case Nil{}: done
    case h <> t:
      +k = ku_c.fill(done, h)
      ku_c.go(t, List.append(&2, C.KU, done, [k]))

# ===========================================================================
# ONE NODE.  THE SEVEN FIELDS, IN `KU`'s OWN ORDER.
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

# ===========================================================================
# THE CONVERTER.  AN ARENA (THROUGH ITS FOLD) AND A LIST OF ARENA INDICES IN
# POST-ORDER, AND A `List<&2, KU>` IN THE SAME ORDER, WITH EVERY `srcs`
# RE-INDEXED TO A POSITION.
def kuconv.convert.go(+fx: F.Folded, +ix: List<&2, U32>, xs: List<&2, U32>,
                       +acc: List<&2, C.KU>) -> List<&2, C.KU>:
  match xs:
    case Nil{}: acc
    case h <> t: kuconv.convert.go(fx, ix, t,
      List.append(&2, C.KU, acc, [kuconv.ku(fx, ix, h)]))

def kuconv.convert(+fx: F.Folded, +ix: List<&2, U32>) -> List<&2, C.KU>:
  ku_c.go(kuconv.convert.go(fx, ix, ix, Nil{}), Nil{})
