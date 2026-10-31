# .agents/slop/browser/kudump.bend -- THE `KU` LIST, NODE BY NODE.
#
# **⇒ AND THIS IS THE INSTRUMENT FOR D2 AND D3.** `fullchain.bend` renders
# `Lidx0 < ;` and `weakint`, and those are TWO FIELDS OF ONE `KU` RECORD: the
# RANGE's `srcs` (which name its trip count's CONST) and its `dtype`. A C text
# that is wrong names neither. **⇒ SO THE KU LIST IS DUMPED AND EACH FIELD IS
# READ.**
#
# **⇒ AND THE ORDER OF DEFS HERE IS DEPENDENCY ORDER, WHICH BEND REQUIRES**:
# "a def may call only a def declared ABOVE it"
# (`.agents/slop/imagenet2/REPORT.md`, measured).
import Base
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/schedule/rangify.bend as RR
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/codegen/late/linearizer.bend as LIN
import ./../../../tinybendygrad/renderer/kuconv.bend as KC
import ./../../../tinybendygrad/renderer/cstyle.bend as C
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/LAWS/spec.bend as S
import ./../../../tinybendygrad/helpers.bend as H

# THE CLASS NAMES ARE THE PORT's OWN SEVEN ARMS (`spec.bend:67`):
# `CVoid CBool CUint CSint CFloat CWeakFloat CWeakInt`. **⇒ AND `CWeakInt` IS THE
# ONE D3 IS ABOUT**: a `weakint` and an `i32` are BOTH 32 BITS and differ ONLY
# in this field, which is why a row that dumped the bits alone cannot see it.
def kd_cls(+c: S.Cls) -> String:
  match c:
    case S.CFloat{}: "F"
    case S.CWeakFloat{}: "WF"
    case S.CUint{}: "U"
    case S.CSint{}: "I"
    case S.CWeakInt{}: "WI"
    case S.CBool{}: "B"
    case S.CVoid{}: "V"

# **⇒ AND THE CLASS IS READ THROUGH ITS OWN DEF, BECAUSE A `match` CANNOT
# SCRUTINIZE A COMPUTED VALUE** -- "give it its own def", which is one of the
# four Bend facts `.agents/slop/imagenet2/REPORT.md` measured.
def kd_dt_cls(d: S.Dt) -> String: kd_cls(S.Dt.cls(d))

def kd_addr(+a: S.Addr) -> String:
  match a:
    case S.AGlobal{}: "G"
    case S.ALocal{}: "L"
    case S.AReg{}: "R"
    case _: "A"

# **⇒ AND A CONST IS DUG BY ARM, NOT PRINTED BY A `show`** -- `Const`
# (`ops.bend:800`) has FOUR arms and no `show` def in the port.
def kd_const(+v: O.Const) -> String:
  match v:
    case O.CInt{i}: String.concat([U32.show(H.lo32(i)), "/", U32.show(H.hi32(i))])
    case O.CFloat{f}: U32.show(F32.bits(f))
    case O.CBool{b}: Bool.show(b)
    case O.CInvalid{}: "inv"

def kd_arg(+a: C.KUArg) -> String:
  match a:
    case C.KANone{}: "-"
    case C.KAConst{v}: String.concat(["c", kd_const(v)])
    case C.KAParam{slot, name, volatile_, bytes}: String.concat(["p", U32.show(slot)])
    case C.KARange{axis, ids}: String.concat(["r", U32.show(U32.from_nat(List.length(&2, U32, ids)))])
    case C.KAIndex{off, is_add}: String.concat(["x", U32.show(off)])
    case C.KASink{name}: String.concat(["s", name])

# THE OP's OWN NAME. **⇒ AND `gate.code` IS NOT ENOUGH**: it has NO ARM for
# `LOAD`, `INDEX`, `SHRINK`, `REDUCE` or `RANGE`, so five different ops all
# print `0` and a dump that used it alone could not tell them apart. **⇒ AND
# THE NAME IS `render/__init__.bend`'s own op list, read by INDEX.**
def kd_op(+op: O.Op) -> String:
  O.Ops.name.of(op)

# ONE `KU`, AS EVERY FIELD THE RENDERER READS.
def kd_ku(+k: C.KU) -> String:
  String.concat([kd_op(C.KU.op(k)), ":",
                 U32.show(S.Dt.bits(C.KU.dtype(k))), ":",
                 kd_dt_cls(C.KU.dtype(k)), ":",
                 kd_addr(C.KU.addr(k)), ":",
                 U32.show(C.KU.numel(k)), ":",
                 U32.show(U32.from_nat(List.length(&2, U32, C.KU.srcs(k)))), ":",
                 kd_arg(C.KU.arg(k))])

def kd_rows.go(+ks: List<&2, C.KU>, +acc: List<&2, String>) -> List<&2, String>:
  match ks:
    case Nil{}: acc
    case k <> t: kd_rows.go(t, List.append(&2, String, acc, [kd_ku(k)]))

# THE SCHEDULED KERNEL, AND ITS BODY's TOPOSORT -- the same three links
# `fullchain.bend` runs, so the KU list here IS the one that renders.
def kd_pick(outs: List<&2, U32>, ar: O.Arena) -> O.Found:
  match outs:
    case Nil{}: O.Found{ar, 0}
    case k <> _: O.Found{ar, k}

def kd_sched() -> O.Found:
  +q = RZ.rz_built()
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +l = SCH.schedule(O.Found.ar(kg), O.Found.i(kg))
  kd_pick(SCH.Lin.out(l), SCH.Lin.ar(l))

# THE TOPOSORT's OWN OPS, so a difference between `lst` and the KU list is
# LOCALISED to `linearize` rather than guessed at.
def kd_lst_ops.go(+xs: List<&2, U32>, +ar: O.Arena, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: kd_lst_ops.go(t, ar, List.append(&2, String, acc, [kd_op(SCH.sc_op(ar, x))]))

# THE KERNEL's `srcs` LIST, AS OPS. **⇒ AND THIS LOCALISES A MISSING SUBTREE**:
# if `k` is a STORE and its `srcs` are INDEX and REDUCE, then a toposort that
# does not contain a REDUCE has dropped it, and that is `toposort`'s defect and
# not `kuconv`'s.
def kd_srcs.go(+xs: List<&2, U32>, +ar: O.Arena, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: kd_srcs.go(t, ar, List.append(&2, String, acc, [kd_op(SCH.sc_op(ar, x))]))

def kd_rows() -> List<&2, String>:
  +f = kd_sched()
  +ar = O.Found.ar(f)
  +k = O.Found.i(f)
  +lst = O.UOp.toposort(O.Arena.budget(ar), ar, k)
  +lin = LIN.linearize(ar, lst, Nil{}, k)
  +kus = KC.kuconv.convert(F.folded(ar), lin)
  +hdr : List<&2, String> = [String.concat(["k_op=", kd_op(SCH.sc_op(ar, k)), " nsrc=", U32.show(SCH.sc_nsrc(ar, k))]),
          String.concat(["k_srcs=", String.join(kd_srcs.go(SCH.sc_srcs(ar, k), ar, Nil{}), ",")]),
          String.concat(["topo_n=", U32.show(U32.from_nat(List.length(&2, U32, lst)))]),
          String.concat(["linear_n=", U32.show(U32.from_nat(List.length(&2, U32, lin)))]),
          String.concat(["topo_ops=", String.join(kd_lst_ops.go(lst, ar, Nil{}), ",")])]
  List.append(&2, String, hdr, kd_rows.go(kus, Nil{}))

def kd_emit.go(+xs: List<&2, String>) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit, Unit{})
    case x <> t:
      do IO<Unit>:
        _ : Unit <- IO.print(String.concat(["ku=", x]))
        kd_emit.go(t)

def main() -> IO(Unit): kd_emit.go(kd_rows())
