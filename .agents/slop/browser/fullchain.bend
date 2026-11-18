# .agents/slop/browser/fullchain.bend -- THE WHOLE CHAIN, AS ONE MEASUREMENT.
#
# THE QUESTION: **CAN THE PORT GET FROM ITS OWN `schedule()` ALL THE WAY TO
# COMPILED C, WITH NO LINK SUPPLIED BY A HARNESS?**
#
# THE LINKS, AND WHERE EACH ONE LIVES:
#   1. `run_rangeify` + the six engine stages  `schedule/rangify.bend` (rr_kernel_graph)
#   2. `create_schedule`                       `schedule/__init__.bend` (schedule)
#   3. `linearize`                             `codegen/late/linearizer.bend:836`
#   4. `kuconv.convert`                        `renderer/kuconv.bend:432`
#   5. `C.render`                              `renderer/cstyle.bend:2297`
#
# **AND EVERY ONE OF THEM EXISTS. WHAT THIS FILE ASKS IS WHETHER THEY COMPOSE.**
# A chain whose every link is measured and whose JOINTS are not is the class this
# tree calls "a row that cannot go red" one level up: each part works, and the
# question is the composition.
#
# **AND THE COMPOSITION IS THE THING NOBODY HAS MEASURED.** `cpuseam` measured
# links 4 and 5 on FIVE REAL MNIST KERNELS, with the `KU` list supplied by a
# GENERATED fixture (`gen/<name>.bend`) rather than by link 3. `realize.bend`
# measured links 1 and 2 on its own program and answered `rz_lin_n=0`, because
# the sink was never rangeified. **AND `.agents/slop/browser/schedbridge.bend`
# then measured that rangeifying the sink gives `bridge_lin_ranged=1`.** So this
# file is the LAST measurement: does that one kernel render?
import Base
import ./../../../tinybendygrad/schedule/__init__.bend as SCH
import ./../../../tinybendygrad/schedule/rangify.bend as RR
import ./../../../tinybendygrad/schedule/realize.bend as RZ
import ./../../../tinybendygrad/codegen/late/linearizer.bend as LIN
import ./../../../tinybendygrad/renderer/kuconv.bend as KC
import ./../../../tinybendygrad/renderer/cstyle.bend as C
import ./../../../tinybendygrad/uop/ops.bend as O
import ./../../../tinybendygrad/uop/fold.bend as F
import ./../../../tinybendygrad/uop/weak.bend as WK
import ./../../../tinybendygrad/codegen/kernel.bend as KR

# THE SCHEDULED KERNEL, in the port's own two names: the arena and the kernel.
type Chain is Data:
  Chain{ar: O.Arena, k: U32}

def chain_pick(outs: List<&2, U32>, ar: O.Arena) -> Chain:
  match outs:
    case Nil{}: Chain{ar, 0}
    case k <> _: Chain{ar, k}

def chain_sched() -> Chain:
  +q = RZ.rz_built()
  +kg = RR.rr_kernel_graph(RZ.RZProg.ar(q), RZ.RZProg.sink(q))
  +l = SCH.schedule(O.Found.ar(kg), O.Found.i(kg))
  # **AND `Lin.out` IS BOUND TO A `+` LOCAL AND THEN PASSED TO A DEF, NOT
  # MATCHED DIRECTLY** -- a `match` cannot scrutinize a local binder, which is
  # one of the four Bend facts `.agents/slop/imagenet2/REPORT.md` measured.
  chain_pick(SCH.Lin.out(l), SCH.Lin.ar(l))

# THE KERNEL's OWN SRC LIST, which is what `linearize` takes: `lst` is the list
# of arena indices to render, and for a kernel that is its BODY.
def chain_ar(+cc: Chain) -> O.Arena:
  match cc:
    case Chain{ar, k}: ar

def chain_k(+cc: Chain) -> U32:
  match cc:
    case Chain{ar, k}: k

# THE SRCs OF THE KERNEL, as an index list. A STORE-carried kernel has its
# sources directly; an END has one src (the STORE). **AND `SCH.sc_srcs` IS THE
# PORT's OWN READER, so this is not a second spelling of the arena's layout.**
# THE KERNEL IS A `CALL` NOW, AND ITS BODY IS `src[0]` -- upstream's `k.body`
# (`schedule/__init__.py:75` builds the CALL as `ret.sink(...).call(*bufs)`, so
# `src[0]` is the SINK). `do_to_program`'s first rule linearizes THE SINK
# (`codegen/__init__.py:456`), not the CALL: a CALL is the schedule's unit and a
# SINK is the renderer's.
def chain_body(+ar: O.Arena, +k: U32) -> U32: SCH.sc_src0(ar, k)

def chain_lst(+ar: O.Arena, +k: U32) -> List<&2, U32>:
  # **AND THE LIST IS THE KERNEL's **WHOLE TOPOSORT**, NOT ITS DIRECT SRCS,
  # AND THE DIFFERENCE IS MEASURED.** Upstream's `linearize(sink:UOp)`
  # (`tinygrad/codegen/late/linearizer.py:7`) takes THE KERNEL NODE and does
  # `lst = list(sink.toposort())` INSIDE ITSELF. The port's
  # `linearize(+ar, +lst, vms, +sink)` takes the list, so the CALLER owes the
  # toposort. **AND PASSING THE DIRECT SRCS IS WHAT PRODUCED
  # `void test() { * = ; }`** -- a kernel rendered from two nodes with no
  # CONSTs, no INDEX and no RANGE, which is the shape of an EMPTY BODY and not
  # of a wrong one.
  O.UOp.toposort(O.Arena.budget(ar), ar, chain_body(ar, k))

def chain_nums.go(+ks: List<&2, C.KU>, +acc: List<&2, String>) -> List<&2, String>:
  match ks:
    case Nil{}: acc
    case k <> t: chain_nums.go(t, List.append(&2, String, acc,
      [String.concat([U32.show(C.KU.src0(k)), "/", U32.show(C.KU.numel(k)), "/", U32.show(C.KU.nsrc(k))])]))

def chain_kudump(+ks: List<&2, C.KU>) -> String: String.join(chain_nums.go(ks, Nil{}), " ")

def chain_codes.go(+ar: O.Arena, +xs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: chain_codes.go(ar, t, List.append(&2, String, acc, [U32.show(SCH.gate.code(O.Arena.op(ar, x)))]))

def chain_codes(+ar: O.Arena, +xs: List<&2, U32>) -> String: String.join(chain_codes.go(ar, xs, Nil{}), ",")

def chain_u32s.go(+xs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: chain_u32s.go(t, List.append(&2, String, acc, [U32.show(x)]))

def chain_ksig.go(+ks: List<&2, C.KU>, acc: List<&2, String>) -> List<&2, String>:
  match ks:
    case Nil{}: acc
    case k <> t:
      +opc = U32.show(SCH.gate.code(C.KU.op(k)))
      chain_ksig.go(t, List.append(&2, String, acc,
        [String.concat([opc, ":", String.join(chain_u32s.go(C.KU.srcs(k), Nil{}), ",")])]))

def chain_ksig(+ks: List<&2, C.KU>) -> String: String.join(chain_ksig.go(ks, Nil{}), " ")

def chain_rows(+cc: Chain) -> List<&2, String>:
  +ar = chain_ar(cc)
  +k = chain_k(cc)
  # `full_rewrite_to_sink`'s weak rounds FIRST: a renderer cannot print a `weakint`, and
  # it cannot print a range bound that is a weak CONST either -- the bound is `src0`'s
  # text, so an uncommitted bound renders as the empty string.
  +wc = WK.wk_commit(ar, chain_body(ar, k))
  +war = O.Found.ar(wc)
  +wb = O.Found.i(wc)
  # `pm_reduce_local`'s `lower_reduce`: a REDUCE is not a renderer op upstream either,
  # and it is the last node the port rendered as UNHANDLED.
  +lr = KR.lower_reduce_all(war, wb)
  +ab = KR.alloc_to_buf_all(O.Found.ar(lr), O.Found.i(lr))
  +lar = O.Found.ar(ab)
  +lb = O.Found.i(ab)
  +lst = O.UOp.toposort(O.Arena.budget(lar), lar, lb)
  +lin = LIN.linearize(lar, lst, Nil{}, lb)
  +kus = KC.kuconv.convert(F.folded(lar), lin)
  +src = C.render(C.dev_clang(), True{}, kus)
  [String.concat(["chain_kernel_op=", U32.show(SCH.gate.code(SCH.sc_op(ar, k)))]),
   String.concat(["chain_kernel_nsrc=", U32.show(SCH.sc_nsrc(ar, k))]),
   String.concat(["chain_body=", U32.show(chain_body(ar, k)), " committed=", U32.show(wb), " reduced=", U32.show(lb)]),
   String.concat(["chain_lst_n=", U32.show(U32.from_nat(List.length(&2, U32, lst)))]),
   String.concat(["chain_linear_n=", U32.show(U32.from_nat(List.length(&2, U32, lin)))]),
   String.concat(["chain_ku_n=", U32.show(U32.from_nat(List.length(&2, C.KU, kus)))]),
   String.concat(["chain_lin_ops=", chain_codes(lar, lst)]),
   String.concat(["chain_ku_sig=", chain_ksig(kus)]),
   String.concat(["chain_c_nbytes=", U32.show(U32.from_nat(String.length(src)))]),
   String.concat(["chain_c=", src])]

def chain_emit.go(+xs: List<&2, String>) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit, Unit{})
    case x <> t:
      do IO<Unit>:
        _ : Unit <- IO.print(x)
        chain_emit.go(t)

def main() -> IO(Unit): chain_emit.go(chain_rows(chain_sched()))
