# specreach.bend -- the READER that measures what `gates/opseven.bend` cannot see.
#
#   checks/bounded.py --mb 2048 -- bin/bend gates/specreach.bend
#
# THE NAME, because it was `specreach-probe.bend` first and git refused it. `.gitignore:51` is
# `*probe.bend`, and its own comment says the pattern exists because "does any `.bend` in the tree
# still look like scratch?" is a question a reviewer should not have to ask -- so a name ending in
# `probe.bend` reads as scratch by construction. `git add -f` would have worked and would have been
# exactly the move that rule is written to prevent. The name is `specreach.bend` because that is the
# house shape (`gates/opseven.bend`, `gates/ops-core.bend`) and because a tracked gate driver has no
# business being one `-f` away from not existing.
#
# WHAT IT IS FOR. `gates/opseven.bend` is the only file in the tree that imports `uop/spec.bend`
# (measured: `grep -rn 'import.*uop/spec\.bend' --include='*.bend'` names exactly one file), and its
# twelve fixtures are all `CUSTOM CUSTOMI INS PROGRAM PYLITERAL REWRITE_ERROR SOURCE` shapes. Not one
# of them is a `GETADDR`, and not one of them is a node that `spec.py:204`'s first rule decides. So the
# two entries of `full_table` that the dispatch arithmetic cannot deliver are invisible to it, by
# construction rather than by accident. This file builds the shapes that ARE those entries' business.
#
# TWO FIXTURES, AND EACH ONE IS A ROW THAT CANNOT PASS BY ACCIDENT.
#   GETADDR   `spec.bend`'s own `main_arena` already mints two (`Land.ga_plain`, `Land.ga_after`),
#             both from the same construction upstream's `hcq2.py` uses: a BUFFER (optionally under an
#             AFTER) and `arg` a device. The only rule that accepts one is `spec_hcq`'s `hq_0`.
#   BINARY    one CONST src and a `bytes` arg. `spec_shared`'s BINARY rule demands `src=()`, so a
#             BINARY WITH a src skips it -- and then the only rule left is `spec_program`'s `pr_0`,
#             which is `False` for "a CONST under anything but a CAST".
#
# THE ROWS, AND WHY THERE ARE SO MANY DISPATCH ROWS BESIDE THE VERDICT ROWS. An end-to-end verdict
# alone cannot say WHICH entry answered, and "the answer is wrong" is not actionable. So every
# fixture prints the end-to-end verdict of all six tables AND the per-TAG dispatch answer at each of
# the three seam tags, next to the answer of the rule that tag was MEANT to reach. A tag whose two
# answers differ is the finding; a tag whose two answers agree is the control that says the probe is
# measuring the seam and not something else.
#
# `1` is VTrue, `0` is VFalse, `9` is VSkip (`Sp.show_v`). `VSkip` is the honest spelling of Python's
# `None`, and the first-wins fold means it is what an entry that CANNOT REACH returns.

import Base
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F
import ./../tinybendygrad/uop/spec.bend as Sp

# THE FIXTURE. A BINARY whose ONE src is a bare CONST. `spec_shared`'s BINARY rule is
# `UPat(Ops.BINARY, dtypes.uint8, src=())`, so a BINARY WITH a src skips it, and the next candidate is
# `spec.py:204`'s first `spec_program` rule -- `False` for "a CONST under anything but a CAST". The src
# is a CONST and NOT a CAST, which is the whole point: a CAST here would answer `None` and the fixture
# would exercise nothing. The CONST carries int64 (the port's `Const` has no uint8 arm -- a dtype
# FOLLOWS the value) and the BINARY's dtype FOLLOWS its `bytes` arg, so the two lanes build the same
# node from their own constructors without agreeing on how to spell the constant.
def bin_node() -> O.Found:
  +c = O.UOp.const(O.Arena.empty(), O.CInt{H.i64_of_i32(1)})
  O.UOp.new(O.Found.ar(c), O.OpsBINARY{}, [O.Found.i(c)], O.ABlob{[97, 98, 99, 100]}, O.TNone{})

def row(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))

# ONE FIXTURE, ALL SIX VERDICTS PLUS THE THREE SEAM TAGS. Every table is re-BUILT per use because
# `fu_rewrite`/`kg_rewrite` take their `PMEntrys` by `+`, and a table is affine: it is spent on use.
def probe(+nm: String, +i: U32, +fx: F.Folded) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- row(String.concat([nm, "_sh"]), Sp.show_v(Sp.shared_rewrite(fx, i)))
    b : Unit <- row(String.concat([nm, "_te"]), Sp.show_v(Sp.tensor_rewrite(fx, i)))
    c : Unit <- row(String.concat([nm, "_sp"]), Sp.show_v(Sp.program_rewrite(fx, i)))
    d : Unit <- row(String.concat([nm, "_hq"]), Sp.show_v(Sp.hcq_rewrite(fx, i)))
    e : Unit <- row(String.concat([nm, "_sk"]), Sp.show_v(Sp.kg_rewrite(Sp.kernel_graph_table(), fx, i)))
    f : Unit <- row(String.concat([nm, "_sf"]), Sp.show_v(Sp.fu_rewrite(Sp.full_table(), fx, i)))
    g : Unit <- row(String.concat([nm, "_fu26"]), Sp.show_v(Sp.fu_dispatch(26, fx, i)))
    h : Unit <- row(String.concat([nm, "_sh0"]), Sp.show_v(Sp.sh_dispatch(0, fx, i)))
    i2 : Unit <- row(String.concat([nm, "_fu59"]), Sp.show_v(Sp.fu_dispatch(59, fx, i)))
    j : Unit <- row(String.concat([nm, "_pr0"]), Sp.show_v(Sp.pr_dispatch(0, fx, i)))
    k : Unit <- row(String.concat([nm, "_fu68"]), Sp.show_v(Sp.fu_dispatch(68, fx, i)))
    l : Unit <- row(String.concat([nm, "_hq0"]), Sp.show_v(Sp.hq_dispatch(0, fx, i)))
    m : Unit <- row(String.concat([nm, "_fu69"]), Sp.show_v(Sp.fu_dispatch(69, fx, i)))
    n : Unit <- row(String.concat([nm, "_hq1"]), Sp.show_v(Sp.hq_dispatch(1, fx, i)))
    return Unit{}

# `do` BLOCKS IN THIS TREE ONLY CHAIN `<-`; there is no `x = ...` inside one, so every binding a `do`
# needs is made in a PLAIN def body and handed in as a `+` parameter -- which is also how `spec.bend`
# passes a record it reads more than once (`+fx`, `+n21`).
def ga_rows(+land: Sp.Land) -> IO(Unit):
  do IO<Unit>:
    a : Unit <- probe("ga_plain", Sp.Land.ga_plain(land), Sp.Land.fx(land))
    b : Unit <- probe("ga_after", Sp.Land.ga_after(land), Sp.Land.fx(land))
    return Unit{}

def bin_rows() -> IO(Unit):
  +bn = bin_node()
  probe("bin_u8", O.Found.i(bn), F.folded(O.Found.ar(bn)))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- ga_rows(Sp.main_arena())
    b : Unit <- bin_rows()
    return Unit{}