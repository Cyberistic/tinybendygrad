# .agents/slop/browser/pre.bend -- THE RANGE MAP ON THE GRAPH IT WAS COMPUTED ON.
# `rng.bend` re-derived `rr_range_map` on `body_low(...)`, which is POST-apply: there the store's dst is a
# BUFFER with a SIZE and `rr_dims` answers nothing, so `shape=`/`dst=` came back empty as an ARTIFACT.
# This probe takes the graph `rz_rebuild` returns -- PRE-apply, the one `rr_kernel_graph` consumes -- and
# prints, for every STORE, both the store's own entry and its VALUE's, side by side.
import Base
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/schedule/rangify.bend as RR
import ./../../../tinybendygrad/schedule/rangeify.bend as RF
import ./../../../tinybendygrad/schedule/indexing.bend as IX
import ./fchainl.bend as CH

def ids.go(+rs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match rs:
    case Nil{}: acc
    case r <> t: ids.go(t, List.append(&2, String, acc, [U32.show(r)]))

def opn2(r: Bool, a: Bool, b: Bool, m: Bool) -> String:
  match r:
    case True{} : "RESHAPE"
    case False{}:
      match a:
        case True{} : "AFTER"
        case False{}:
          match b:
            case True{} : "BUFFER"
            case False{}: Bool.pick(String, m, "MUL", "OTHER")

def opn(+ar: O.Arena, +n: U32) -> String:
  opn2(O.eq_op(O.Arena.op(ar, n), O.OpsRESHAPE{}), O.eq_op(O.Arena.op(ar, n), O.OpsAFTER{}),
       O.eq_op(O.Arena.op(ar, n), O.OpsBUFFER{}), O.eq_op(O.Arena.op(ar, n), O.OpsMUL{}))

def ids(+rs: List<&2, U32>) -> String: String.join(ids.go(rs, Nil{}), ",")

def n2(+xs: List<&2, U32>) -> String: U32.show(U32.from_nat(List.length(&2, U32, xs)))

def vsrc(+ar: O.Arena, +n: U32) -> U32:
  Maybe.default(&2, U32, List.get(&2, U32, O.Arena.srcs(ar, n), 1n), 0)

def rows.go(+ar: O.Arena, +tb: F.Table, +rm: IX.IxRMap, +ns: List<&2, U32>,
            +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t:
      +v = vsrc(ar, n)
      rows.go(ar, tb, rm, t, Bool.pick(List<&2, String>,
        O.eq_op(O.Arena.op(ar, n), O.OpsSTORE{}),
        List.append(&2, String, acc,
          [String.concat([U32.show(n), ":has=", Bool.show(IX.ix_rngm_has(rm, n)),
                          ",inp=", ids(RR.rr_ap_inp.of(IX.ix_rngm_get(rm, n))),
                          ",shape=", ids(RR.rr_p1.shape(ar, tb, n)),
                          ",dst=", ids(IX.rr_dims(ar, tb, O.Arena.src0(ar, n))),
                          " | val=", U32.show(v), ":has=", Bool.show(IX.ix_rngm_has(rm, v)),
                          ",inp=", ids(RR.rr_ap_inp.of(IX.ix_rngm_get(rm, v))),
                          ",shape=", ids(RR.rr_p1.shape(ar, tb, v)),
                          ",v0after=", Bool.show(O.eq_op(O.Arena.op(ar, O.Arena.src0(ar, v)), O.OpsAFTER{})),
                          ",v0dims=", ids(IX.rr_dims(ar, tb, O.Arena.src0(ar, v))),
                          ",v0op=", RF.eng_op_name(O.Arena.op(ar, O.Arena.src0(ar, v))),
                          ",v1dims=", ids(IX.rr_dims(ar, tb, O.Arena.src0(ar, O.Arena.src0(ar, v)))),
                          ",v1op=", RF.eng_op_name(O.Arena.op(ar, O.Arena.src0(ar, O.Arena.src0(ar, v))))])]),
        acc))

def aft.go(+ar: O.Arena, +tb: F.Table, +ns: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t:
      aft.go(ar, tb, t, Bool.pick(List<&2, String>,
        O.eq_op(O.Arena.op(ar, n), O.OpsAFTER{}),
        List.append(&2, String, acc,
          [String.concat([U32.show(n), ":", RF.eng_op_name(O.Arena.op(ar, O.Arena.src0(ar, n))),
                          ":dims=", ids(IX.rr_dims(ar, tb, n)),
                          ":d0=", ids(IX.rr_dims(ar, tb, O.Arena.src0(ar, n)))])]),
        acc))

def rn_i(m: Maybe<&2, IX.IxRngs>) -> String:
  match m:
    case Some{e}: ids(IX.IxRngs.inp(e))
    case _: "none"

def rn_o(m: Maybe<&2, IX.IxRngs>) -> String:
  match m:
    case Some{e}: ids(IX.IxRngs.outp(e))
    case _: "none"

def rsh.go(+ar: O.Arena, +tb: F.Table, +rm: IX.IxRMap, +ns: List<&2, U32>,
           +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t:
      rsh.go(ar, tb, rm, t, Bool.pick(List<&2, String>,
        O.eq_op(O.Arena.op(ar, n), O.OpsRESHAPE{}),
        List.append(&2, String, acc,
          [String.concat([U32.show(n), ":ins=", n2(IX.rr_dims(ar, tb, O.Arena.src0(ar, n))),
                          ",outs=", n2(IX.rr_dims(ar, tb, n)),
                          ",inp=", rn_i(IX.ix_rngm_get(rm, n)),
                          ",out=", rn_o(IX.ix_rngm_get(rm, n))])]),
        acc))

def cons.go(+ar: O.Arena, +ns: List<&2, U32>, +u: U32, +acc: List<&2, String>) -> List<&2, String>:
  match ns:
    case Nil{}: acc
    case n <> t:
      cons.go(ar, t, u, Bool.pick(List<&2, String>,
        F.mem_u32(O.Arena.srcs(ar, n), u),
        List.append(&2, String, acc, [String.concat([U32.show(n), "[", U32.show(U32.from_nat(List.length(&2, U32, O.Arena.srcs(ar, n)))), "]"])]),
        acc))

def r2(p: (O.Arena & RR.RrMap), +sink: U32) -> String:
  (+a, +m) = p
  +tb = F.Folded.t(F.folded(a))
  String.concat([String.join(rows.go(a, tb, IX.IxCtx.rngm(RR.RrMap.ctx(m)),
                       O.UOp.toposort(O.Arena.budget(a), a, sink), Nil{}), " || "),
                 " AFT: ", String.join(aft.go(a, tb, O.UOp.toposort(O.Arena.budget(a), a, sink), Nil{}), " "),
                 " CONS84: ", String.join(cons.go(a, O.UOp.toposort(O.Arena.budget(a), a, sink), U32.from_nat(84n), Nil{}), " "),
                 " RSH: ", String.join(rsh.go(a, tb, IX.IxCtx.rngm(RR.RrMap.ctx(m)),
                                             O.UOp.toposort(O.Arena.budget(a), a, sink), Nil{}), " ")])

def pre() -> String:
  +q = RZ.rz_rebuild(CH.fchain_prog(), False{}, False{})
  +a = RZ.RZProg.ar(q)
  +sink = RZ.RZProg.sink(q)
  r2(RR.rr_range_map(a, F.Folded.t(F.folded(a)), sink), sink)

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["pre=", pre()]))
