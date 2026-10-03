#!/usr/bin/env python3
# fold-rng-mutate.py -- the mutation table for THE RANGES FOLD (`UOp._ranges`,
# ops.py:483, and `UOp.ranges`, ops.py:497) in `tinybendygrad/uop/fold.bend`.
#
# TWO RULES, both measured rather than adopted:
#   * IT DIFFS WHOLE `name=value` LINES. A name-comparing harness reported 0 for all 30
#     mutations in one unit and 0 for all 68 in another.
#   * A `0` IS REPORTED AS A REQUEST FOR A FIXTURE, A THEOREM, OR AN UNFIXABLE. Never
#     closed with a row that encodes the equivalence as a check.
#
# IT RUNS IN A SCRATCH TREE, not in place, and that is a fact about this repo rather than
# a preference: `uop/ops.bend` and `uop/symbolic.bend` are owned by two other agents and
# went transiently uncompilable three times while this table was being measured, so the
# baseline is captured from a copy whose `ops.bend` is pinned at `master` and whose
# `fold.bend` is the file under test. Editing the working tree in place would put this
# harness in a race with two writers.
import os
import shutil
import subprocess
import sys
import tempfile

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(REPO, 'bin/bend')
PIN = 'master'


def jj(*a):
  return subprocess.run(['jj', *a], cwd=REPO, capture_output=True, text=True).stdout


def scratch():
  d = tempfile.mkdtemp(prefix='fold-rng-', dir=os.environ.get('TMPDIR'))
  os.makedirs(os.path.join(d, 'tinybendygrad'))
  shutil.copytree(os.path.join(REPO, 'tinybendygrad/uop'), os.path.join(d, 'tinybendygrad/uop'))
  for rel in ('tinybendygrad/helpers.bend', 'tinybendygrad/LAWS'):
    src, dst = os.path.join(REPO, rel), os.path.join(d, rel)
    if os.path.isdir(src):
      shutil.copytree(src, dst)
    else:
      shutil.copy(src, dst)
  pinned = jj('file', 'show', '-r', PIN, '--', 'tinybendygrad/uop/ops.bend')
  open(os.path.join(d, 'tinybendygrad/uop/ops.bend'), 'w').write(pinned)
  return d, os.path.join(d, 'tinybendygrad/uop/fold.bend')


# (label, old, new, what it is testing)
MUT = [
  ("R1", "def RTable.get(t: RTable, +i: U32) -> Rng:",
   "def RTable.get(t: RTable, +i: U32) -> Rng:  \n",
   "SANITY: a no-op edit, expected to move 0. A harness that reports a row-move for a "
   "no-op is reporting the substrate, not the mutation"),
  ("R2", "def set_union.go(xs: List<&2, U32>, ys: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:\n  match ys:\n    case Nil{}: acc\n    case +y <> t: set_union.go(xs, t, Bool.pick(List<&2, U32>, mem_u32(acc, y), acc, List.append(&2, U32, acc, [y])))",
   "def set_union.go(+xs: List<&2, U32>, ys: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:\n  match ys:\n    case Nil{}: acc\n    case +y <> t: set_union.go(xs, t, Bool.pick(List<&2, U32>, mem_u32(xs, y), acc, List.append(&2, U32, acc, [y])))",
   "the union's membership test read against the INPUT instead of the ACCUMULATOR, which is "
   "the set/multiset line: `ADD(r, r)` names one range twice and a dict prints it once. The "
   "SIGNATURE edit rides along because it is what makes the body edit compile at all (the "
   "swap drops one read of `xs`, and a one-use list parameter is a type error) -- and R2b is "
   "the signature ALONE, so R2b's 0 is what makes R2's row-moves the accumulator's"),
  ("R2b", "def set_union.go(xs: List<&2, U32>, ys: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:",
   "def set_union.go(+xs: List<&2, U32>, ys: List<&2, U32>, +acc: List<&2, U32>) -> List<&2, U32>:",
   "SANITY, and it is the control for R2: R2's body edit NEEDS this `+xs` to compile at all "
   "(the `mem_u32(acc, y)` -> `mem_u32(xs, y)` swap drops one read of `xs`, and a one-use "
   "list parameter is a type error). So R2 is a SIGNATURE+body mutation and R2b is the "
   "signature alone, and R2b moving 0 is what makes R2's row-moves the accumulator's"),
  ("R3", "Rng{i, Bool.pick(List<&2, U32>, self, List.append(&2, U32, [Rng.i(r)], Rng.rs(r)), Rng.rs(r)), Rng.ok(r)}",
   "Rng{i, Rng.rs(r), Rng.ok(r)}",
   "the `{self:None} | _ranges` PREPEND dropped, which is `ranges` against `_ranges` and is "
   "invisible from every node that is not itself a RANGE"),
  ("R4", "case +y <> t: set_union.go(xs, t, Bool.pick(List<&2, U32>, mem_u32(acc, y), acc, List.append(&2, U32, acc, [y])))",
   "case +y <> t: set_union.go(xs, t, Bool.pick(List<&2, U32>, mem_u32(acc, y), List.append(&2, U32, [y], acc), acc))",
   "the union PREPENDS, so it is still a set and still correct as a set -- only the "
   "first-occurrence ORDER is wrong, and a gate that sorted its answer could not see it"),
  ("R5", "Bool.pick(Del, is_range.of(O.Arena.op(ar, er)), Del{[er], True{}}, del_of.row(RTable.get(t, er)))",
   "del_of.row(RTable.get(t, er))",
   "the `else` arm everywhere: a RANGE `er` would delete its own live set instead of "
   "itself, so an END's ranges would survive"),
  ("R6", "Bool.pick(Del, is_range.of(O.Arena.op(ar, er)), Del{[er], True{}}, del_of.row(RTable.get(t, er)))",
   "Del{[er], True{}}",
   "the `if` arm everywhere: a non-RANGE `er` would delete ITSELF rather than its live "
   "set, which is the `BACKEDGE`-over-a-STACK row and nothing else in the gate"),
  ("R7", "    case O.OpsBACKEDGE{}: ended_of.one(ar, i)",
   "    case O.OpsBACKEDGE{}: List.take(&2, U32, O.Arena.srcs(ar, i), 1n)",
   "THE INHERITED READER, not the new fold: `ended_of.one` is `src[1:2]` and this makes it "
   "`src[0:1]`, so the `self` ends and the `loop` does not. `rg_er` is the only row that "
   "can see it, and bend2-constraints.md already flags this off-by-one for `ended_ranges`"),
  ("R8", "    case None{}: Del{Nil{}, False{}}",
   "    case None{}: Del{Nil{}, True{}}",
   "THE REFUSAL FLAG: \"no `ended` list\" read as \"no ended ranges\". This is the one "
   "mutation that makes `rg_absent` AGREE with CPython, which is the measurement that the "
   "row is pinning the divergence and not a mistake"),
  ("R9", "case +x <> t: set_del(t, ds, Bool.pick(List<&2, U32>, mem_u32(ds, x), acc, List.append(&2, U32, acc, [x])))",
   "case +x <> t: set_del(t, ds, Bool.pick(List<&2, U32>, mem_u32(ds, x), List.append(&2, U32, [x], acc), acc))",
   "the delete PREPENDS, so it still deletes exactly the right elements and only the "
   "SURVIVORS' order changes -- a Python `pop` does not reorder, and four rows have more "
   "than one survivor"),
  ("R10", "    case _ <> tl: rng_sweep.go(ar, main, tl, U32.add(k, 1), RTable.put(t, rng_of.node(ar, main, t, k)))",
   "    case _ <> tl: rng_sweep.go(ar, main, tl, U32.add(k, 1), RTable.put(t, rng_of.node(ar, main, t, U32.add(k, 2))))",
   "THE INDEX LOCKSTEP, one node out of step: the walk numbers the arena from 0 but STORES "
   "the answer for `k+1`, so every row is off by one and the last node's row is lost. This "
   "is the measurement that the sweep's `k` is the node INDEX and not a counter -- the same "
   "class as bend2-constraints.md's \"index order is not resolution order\", one layer down"),
  ("R12", "    case Some{ers}: rng_dels.go(ar, t, ers, Del{Nil{}, True{}})",
   "    case Some{ers}: Del{Nil{}, True{}}",
   "THE ENDED LIST DROPPED, so no range ever ends. Every row that ends something reads as "
   "if nothing did, and the rows that end nothing do not move -- which is the measurement "
   "that the four pop-arms are carried by the rows rather than by the fold terminating"),
  ("R13", "    case +er <> tl: rng_dels.go(ar, t, tl, del_un(acc, del_of.er(ar, t, er)))",
   "    case +er <> tl: rng_dels.go(ar, t, tl, acc)",
   "THE `else` DELETE SET dropped while the `if` arm is kept: a RANGE `er` still deletes "
   "itself and a non-RANGE `er` deletes nothing. It is R5's mirror image -- the two halves "
   "of the one conditional, separated -- and `rg_er` is the row both of them need"),
  ("R14", "  rng_of.put(i, is_range.of(O.Arena.op(ar, i)), RTable.get(t, i))",
   "  Rng{i, Nil{}, True{}}",
   "THE READER short-circuited to the empty set: `ranges` is the table read plus the "
   "self-prepend, and this answers the empty set for every node whatever the sweep found. "
   "It is the row that says the gate is reading the FOLD and not a constant"),
  ("R15", "    case +er <> tl: rng_dels.go(ar, t, tl, del_un(acc, del_of.er(ar, t, er)))",
   "    case +er <> tl: rng_dels.go(ar, t, tl, del_of.er(ar, t, er))",
   "THE ACCUMULATOR dropped from the ended walk, so each `er` REPLACES the last delete set "
   "instead of adding to it. `rg_barrier` and `rg_er` carry two ended ranges, and only a "
   "delete set that survives the whole walk answers them, so this is the row that the "
   "union over the `for er in ...` loop is an accumulation and not a fold to the last"),
  ("R11", "def rng_union.go(+ar: O.Arena, +t: RTable, ss: List<&2, U32>, +acc: Rng) -> Rng:",
   "def rng_union.go(+ar: O.Arena, +t: RTable, ss: List<&2, U32>, +acc: Rng) -> Rng:  \n",
   "SANITY on the UNION walk's own body, second control: a well-formed edit to a different "
   "def must move nothing"),
]


def run(work, extra=()):
  r = subprocess.run([BEND, work, *extra], capture_output=True, text=True)
  return r.stdout, (r.stdout + r.stderr).splitlines()[0] if (r.stdout + r.stderr).splitlines() else '<none>'


def rows(work):
  out = {}
  for line in run(work)[0].splitlines():
    if ' ' in line:
      k, v = line.split(' ', 1)
      out[k] = v
  return out


def main():
  d, work = scratch()
  src = open(work).read()
  base = rows(work)
  chk = run(work, ('--check-only',))[1]
  if not base:
    print('BASELINE IS EMPTY -- refusing to run')
    return 1
  print(f'scratch {d}\nops.bend pinned at {PIN}\nbaseline: {len(base)} bend rows, {chk!r}')
  moved_total = 0
  for label, old, new, why in MUT:
    if src.count(old) != 1:
      print(f'{label:4s} SKIP -- pattern occurs {src.count(old)}x, not 1')
      continue
    open(work, 'w').write(src.replace(old, new))
    got = rows(work)
    chk = run(work, ('--check-only',))[1]
    moved = sorted(k for k in base if base.get(k) != got.get(k))
    gone = sorted(k for k in base if k not in got)
    lost = f'  ROWS LOST: {len(gone)} {gone[:4]}' if gone else ''
    print(f'{label:4s} moved {len(moved) + len(gone):4d}  {chk!r}{lost}  {moved[:8] if moved else ""}')
    moved_total += len(moved) + len(gone)
    open(work, 'w').write(src)
  open(work, 'w').write(src)
  print(f'\nscratch copy restored byte-identical; {moved_total} row-moves over {len(MUT)} mutations')
  shutil.rmtree(d, ignore_errors=True)
  return 0


if __name__ == '__main__':
  sys.exit(main())
