import Base
import ./../../tinybendygrad/helpers.bend as H
import ./../../tinybendygrad/engine/jit.bend as J
import ./../../tinybendygrad/uop/ops.bend as O
import ./../../tinybendygrad/LAWS/spec.bend as S

# arena-sweep-jit.bend -- THE SIZE SWEEP for engine/jit.bend's arena.
#
# THE PRECEDENT THIS EXISTS FOR. `codegen/decomp/dtype.bend`'s `l2i_cdiv.abs` was an
# arena-aliasing defect that AGREED at one node-count configuration and broke at the next,
# and the `pl_step` literal-`0` bug just fixed in `engine/jit.bend` is the same shape: both
# `prune_sig_*` rows read `srcops=Ops.NOOP`, and NOOP is what index 0 answers in EVERY
# arena size, so a single fixture cannot tell a right answer from a wrong one. Padding the
# arena by `k` shifts every real index by `k` while index 0 stays the bottom -- which is the
# ONE configuration that separates them, and it is why `k=0` alone is not evidence.
#
# THE SHAPE. `pad` prepends `k` dummy PARAMs to an EMPTY arena, then `fx_make` runs against
# it unchanged. `k` is a LITERAL, not `IO.args`: `IO.args` is an effect value, not a List,
# and `IO.try(List<&2, String>, IO.args)` is refused, so the caller substitutes the literal.
# That is also the only way a sweep can be READ: one diff per configuration.
#
# WHAT IS PRINTED. The two rows the fix moved, plus the four count rows that must NOT move
# (`prune_hit`'s `kept=1 once=1 need=2` is identical whether the kept list holds the node or
# the literal 0, which is the whole reason the defect was invisible), plus the arena's size
# and the index of the kept node -- so a reader can see the shift rather than infer it.

def pad.go(n: Nat, +ar: O.Arena) -> O.Arena:
  match n:
    case 0n: ar
    case 1n+q:
      +f = O.UOp.new(ar, O.OpsPARAM{}, Nil{},
                     O.AParam{O.ParamArg{0, S.single(), None{}, None{}, None{}, None{},
                                         S.AGlobal{}, Some{S.D1{0}}, False{}, None{}, None{},
                                         False{}, None{}}},
                     O.TNone{})
      pad.go(q, O.Found.ar(f))

def pad(k: U32, +ar: O.Arena) -> O.Arena: pad.go(U32.to_nat(k), ar)

# THE PADDED FIXTURE. Identical to `J.fx_make` in every respect except that it starts from
# `pad(K, Arena.empty())`. It is re-declared here rather than parameterised because
# `fx_make` takes no arena parameter -- the row under test would otherwise need its own
# oracle, and an oracle that is a def of the thing under test is not a test.
def fx_make_padded(k: U32) -> J.Fx:
  +ar = pad(k, O.Arena.empty())
  +f0 = O.UOp.new(ar, O.OpsNOOP{}, Nil{}, O.ANone{}, O.TNone{})
  +f1 = O.UOp.new(O.Found.ar(f0), O.OpsBUFFER{}, Nil{}, O.AParam{J.fx_pa(0, S.single(), 3)}, O.TNone{})
  +f2 = O.UOp.new(O.Found.ar(f1), O.OpsBUFFER{}, Nil{}, O.AParam{J.fx_pa(1, S.single(), 3)}, O.TNone{})
  +f3 = O.UOp.new(O.Found.ar(f2), O.OpsBUFFER{}, Nil{}, O.AParam{J.fx_pa(2, S.single(), 3)}, O.TNone{})
  +f4 = O.UOp.new(O.Found.ar(f3), O.OpsPROGRAM{}, Nil{}, J.fx_prog_arg([0], [1]), O.TNone{})
  +f5 = O.UOp.new(O.Found.ar(f4), O.OpsCALL{}, [O.Found.i(f4), O.Found.i(f1), O.Found.i(f2)],
                  O.ACall{O.CallInfo{None{}, False{}, False{}, S.void()}}, O.TNone{})
  +f6 = O.UOp.new(O.Found.ar(f5), O.OpsUNSHARD{}, [O.Found.i(f1)], O.ANone{}, O.TNone{})
  +f7 = O.UOp.new(O.Found.ar(f6), O.OpsLINEAR{}, [O.Found.i(f5), O.Found.i(f2)], O.ANone{}, O.TNone{})
  +f8 = O.UOp.new(O.Found.ar(f7), O.OpsLINEAR{}, J.fx_pad(9n, O.Found.i(f5), Nil{}), O.ANone{}, O.TNone{})
  +f9 = O.UOp.new(O.Found.ar(f8), O.OpsLINEAR{}, J.fx_pad(10n, O.Found.i(f5), Nil{}), O.ANone{}, O.TNone{})
  J.Fx{O.Found.ar(f9), O.Found.i(f0), O.Found.i(f1), O.Found.i(f2), O.Found.i(f5),
       O.Found.i(f6), O.Found.i(f7), O.Found.i(f8), O.Found.i(f9)}

# THE TWO MOVED ROWS, NAMED. `j_sig` answers a bare string, so the row name is spelled here
# rather than inside the port -- the same shape `rebase-gate.py`'s `rows()` needs, and the
# reason the sweep's first run printed six nameless lines and the oracle assertion refused it.
def sig.row(nm: String, s: String) -> String: String.concat([nm, "=", s])

def prune_count(nm: String, +x: J.Fx, needed: List<&2, U32>, sibufs: List<&2, List<&2, U32>>) -> String:
  sig.row(nm, J.prune_row(x, J.Fx.lin2(x), needed, sibufs))

def pl_replace_p(+ar: O.Arena, +lin: U32, src: List<&2, U32>) -> O.Found:
  O.UOp.new(ar, O.Arena.op(ar, lin), src, O.Arena.arg(ar, lin), O.Arena.tag(ar, lin))

# `k` IS A PARAMETER OF EVERY DEF, NOT A CONSTANT. bend has no globals to bump and no
# `IO.args` spelling (`IO.args` is an effect VALUE and `IO.try(List<&2, String>, IO.args)`
# is refused), so the caller passes it down -- which is what makes the sweep a loop over
# six CONFIGSURATIONS in one program instead of six sed edits of a literal.
# THE HARNESS ITSELF HIT THE BUG CLASS, AND THAT IS WHY THIS DEF HAS ITS OWN SECTIONS.
# The first version read `J.j_sig(J.Fx.ar(x), O.Found.i(J.pl_replace(J.Fx.ar(x), ...)))` --
# a fresh index out of the STALE arena, which is `codegen/__init__.bend:117` verbatim -- and
# it printed `n=0 op=Ops.NOOP nsrc=0 srcops=`. `Arena.node` is TOTAL, so the wrong arena
# answered a NOOP instead of failing, and the ONLY reason it was caught is that the sweep
# asserts its k=0 block against the committed gate BEFORE it compares sizes. A sweep that
# diffs first would have reported "no rows moved" over a probe reading nothing.
def sig.of(+r: O.Found) -> String: J.j_sig(O.Found.ar(r), O.Found.i(r))

def kept.f(+x: J.Fx) -> O.Found:
  J.pl_replace(J.Fx.ar(x), J.Fx.lin2(x),
               J.Prune.kept(J.prune_linear(J.Fx.ar(x), J.Fx.lin2(x), [J.Fx.b1(x)], [[J.Fx.b1(x)], Nil{}])))

def once.f(+x: J.Fx) -> O.Found:
  J.pl_replace(J.Fx.ar(x), J.Fx.lin2(x),
               J.Prune.once(J.prune_linear(J.Fx.ar(x), J.Fx.lin2(x), [J.Fx.b1(x)], [[J.Fx.b1(x)], Nil{}])))

def sweep.run(k: U32, +x: J.Fx) -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["# k=", U32.show(k), " next=", U32.show(O.Arena.next(J.Fx.ar(x))), "\n"]))
    IO.print(sig.row("prune_sig_kept", sig.of(kept.f(x))))
    IO.print(sig.row("prune_sig_once", sig.of(once.f(x))))
    IO.print(prune_count("prune_hit", x, [J.Fx.b1(x)], [[J.Fx.b1(x)], Nil{}]))
    IO.print(prune_count("prune_miss", x, [J.Fx.b0(x)], [[J.Fx.b1(x)], Nil{}]))
    IO.print(prune_count("prune_all", x, Nil{}, [[J.Fx.b1(x)], Nil{}]))
    IO.print(prune_count("prune_none", x, Nil{}, [Nil{}, Nil{}]))

# THE SWEEP LOOP, ON ONE THREADED ARENA PER SIZE. `dd-sweep.sh`'s precedent is a caller
# that loops over sizes outside bend; this is the same sweep with the loop INSIDE, so one
# process prints all six configurations and a stack overflow costs one run rather than six.
# bend overflows on ~1 run in 20 and prints ZERO rows, which is indistinguishable from "not
# started", so the caller retries (arena-sweep.sh).
def sweep.go(xs: List<&2, U32>) -> IO(Unit):
  match xs:
    case Nil{}: IO.pure(Unit, Unit{})
    case +k <> t: IO.bind(Unit, Unit, sweep.run(k, fx_make_padded(k)), _ => sweep.go(t))

# THE SIX SIZES THE BRIEF NAMES: 0, 1, 2, 5, 17, 64. `k=0` is the committed configuration and
# is in the list because a fix that holds only at `k=0` has held at ONE configuration, which
# is the `l2i_cdiv.abs` failure exactly. 1 is in the list because it is the smallest size
# that MOVES the index of a real node, and 2 because a defect that survives 1 is not the one
# this sweep is looking for.
def sizes() -> List<&2, U32>: [0, 1, 2, 5, 17, 64]

def main() -> IO(Unit):
  sweep.go(sizes())