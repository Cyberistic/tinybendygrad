import io, re, sys
p = 'tinybendygrad/runtime/ops_metal.bend'
s = open(p).read()
i = s.index("def pmb_m1.ok(at: U32) -> Bool:")
new = r'''# ONE RULE'S CANDIDATE: the arena it would have grown into, the answer it
# would have given, whether it FIRES, and the next rule index. Four things in
# one `Data` record because a `Data` record may not hold a `Maybe` and the scan
# may not scrutinise a computed value -- device.bend's `Step` shape, with the
# arena added because M1 and M2 both ALLOCATE.
type PmbStep is Data:
  PmbStep{ar: D.Bar, got: U32, fires: Bool, k: Nat}

def PmbStep.ar(s: PmbStep) -> D.Bar:
  match s:
    case PmbStep{ar, got, fires, k}: ar

def PmbStep.got(s: PmbStep) -> U32:
  match s:
    case PmbStep{ar, got, fires, k}: got

def PmbStep.fires(s: PmbStep) -> Bool:
  match s:
    case PmbStep{ar, got, fires, k}: fires

def PmbStep.k(s: PmbStep) -> Nat:
  match s:
    case PmbStep{ar, got, fires, k}: k

# The scan's state: the arena, whether a rule has answered, what it answered,
# and the NEXT RULE INDEX. The index is a FIELD and not a second parameter
# because a self-call's fuel may not feed both the self-call and the dispatch,
# and because `Nat` is not `Data` and cannot take a `+` -- `PmbRun.k` is a def
# rather than a field read for the same reason `Tr.calls` is.
type PmbRun is Data:
  PmbRun{ar: D.Bar, made: Bool, got: U32, k: Nat}

def PmbRun.ar(r: PmbRun) -> D.Bar:
  match r:
    case PmbRun{ar, made, got, k}: ar

def PmbRun.made(r: PmbRun) -> Bool:
  match r:
    case PmbRun{ar, made, got, k}: made

def PmbRun.got(r: PmbRun) -> U32:
  match r:
    case PmbRun{ar, made, got, k}: got

def PmbRun.k(r: PmbRun) -> Nat:
  match r:
    case PmbRun{ar, made, got, k}: k

# THE THREE METAL RULES, and each is one `PmbStep`. `ne` is `b.max_numel()`, the
# ONE input M1's guard reads, and it is a parameter rather than a field because a
# UOp's `max_numel` is a graph read (WALL 5) and its VALUE is all the decision
# uses. M1's guard is `> 4`; M2's is `isinstance(b.tag, tuple) and b.tag[0] ==
# "mtl_icb"`, which the `icb` field already is.
def pmb_m1.fires(+n: PmbNode, ne: U32) -> Bool:
  Bool.and(pmb_m1(n), dev.wants_slots(ne))

# M1 and M2 ALLOCATE, so their step grows the arena. The Buffer is a HOST
# `uint64` of `b.max_numel()` elements, which is :218's `new_slots` shape and
# :251's ICB header shape -- and `mt_pmb_grew` is the row that says a rule that
# FIRES and a rule that is KEPT are the same growth.
def pmb_grow(ar: D.Bar, ne: U32) -> D.Bar:
  D.BFound.ar(D.bnew(ar, D.Bn{0, MTL_DEV(), ne, S.uint64(), 0, 0, False{}, 0,
                             D.Bspec{False{}, True{}, False{}, True{}, False{}}}))

def pmb_step1(ar: D.Bar, fires: Bool, ne: U32) -> PmbStep:
  Bool.pick(PmbStep, fires, PmbStep{pmb_grow(ar, ne), PMB_SLOTS(), True{}, 2n},
            PmbStep{ar, PMB_NONE(), False{}, 2n})

def pmb_step2(ar: D.Bar, fires: Bool, ne: U32) -> PmbStep:
  Bool.pick(PmbStep, fires, PmbStep{pmb_grow(ar, ne), PMB_ICB(), True{}, 3n},
            PmbStep{ar, PMB_NONE(), False{}, 3n})

def pmb_step(k: Nat, ar: D.Bar, n: PmbNode, ne: U32) -> PmbStep:
  match k:
    case 0n: PmbStep{ar, PMB_SELS(), pmb_m0(n), 1n}
    case 1n: pmb_step1(ar, pmb_m1.fires(n, ne), ne)
    case _: pmb_step2(ar, pmb_m2(n), ne)

# FIRST-WINS, spelled out: a rule's answer replaces the accumulator only if it
# FIRES and the accumulator is still empty. `PmbRun.made` is the whole of
# `ops.bend`'s `pm_keep`, and it is what makes M0 beat M1 on a node that is BOTH
# an `mtl_sel` and a `slots` PARAM -- which cannot happen, because
# `UPat(Ops.PARAM, tag="mtl_sel")` and `tag="slots"` are DIFFERENT tags, and
# `mt_pmb_both` is the fixture that proves the two patterns are exclusive.
def pmb_keep(+r: PmbRun, s: PmbStep) -> PmbRun:
  Bool.pick(PmbRun, Bool.and(PmbStep.fires(s), Bool.not(PmbRun.made(r))),
            PmbRun{PmbStep.ar(s), True{}, PmbStep.got(s), PmbStep.k(s)}, r)

# `Nat` FUEL is the first parameter because a self-call must be visibly
# decreasing, and it may not feed both the self-call and the rule dispatch.
def pmb_go(fuel: Nat, ar: D.Bar, n: PmbNode, ne: U32, +r: PmbRun) -> PmbRun:
  match fuel:
    case 0n: r
    case 1n+p:
      +s = pmb_step(PmbRun.k(r), ar, n, ne)
      pmb_go(p, ar, n, ne, pmb_keep(r, s))

def pmb_metal(ar: D.Bar, n: PmbNode, ne: U32) -> PmbRun:
  pmb_go(3n, ar, n, ne, PmbRun{ar, False{}, PMB_NONE(), 0n})

# `+ self.pm_bufferize` -- the TAIL of :220, and it is `device.bend`'s OWN scan
# called, not a second copy of it. `Compiled`'s three rules read `is_param`,
# `tag="timeline"` and `name="b"`, and the first two are the `PmbNode` fields
# that carry them across.
def pmb_tail(ar: D.Bar, n: PmbNode) -> PmbRun:
  +p = D.pmb_bufferize(ar, D.param(PmbNode.par(n), PmbNode.tl(n), PmbNode.named_b(n), False{}))
  PmbRun{D.Pmb.ar(p), True{}, D.Pmb.got(p), 0n}

# THE WHOLE OF :216-220. The `+` IS a list concatenation and `rewrite` is
# FIRST-WINS, so Metal's three rules are consulted BEFORE device.bend's three --
# and this is the only place that ordering is written down.
def pm_bufferize(ar: D.Bar, n: PmbNode, ne: U32) -> PmbRun:
  +a = pmb_metal(ar, n, ne)
  Bool.pick(PmbRun, PmbRun.made(a), a, pmb_tail(PmbRun.ar(a), n))
'''
s = s[:i] + new
open(p, 'w').write(s)
print("ok")
