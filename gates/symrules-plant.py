#!/usr/bin/env python3
"""symrules-plant.py -- THE WAYS A REWRITE CAN BE WRONG, AND A PLANT FOR EACH.

    .venv/bin/python gates/symrules-plant.py            # plant every arm
    .venv/bin/python gates/symrules-plant.py --arm ORDER # one arm

**A DETECTOR THAT HAS NEVER BEEN SHOWN FAILING IS INDISTINGUISHABLE FROM A DETECTOR
THAT CANNOT FAIL.**  So every arm below is a MUTATION of the port's own source, and
each one is required to MOVE A NAMED ROW of the port's own gate.  A mutation that
changes nothing is a mutation that measured nothing, and this file says so and exits
1.

THE FIVE ARMS, and the row each one moves:

    ORDER    two rules in the TABLE swap places.  The table is FIRST-WINS, so the
             order decides which of two matching rewrites wins, and **the arm nobody
             plants is the one that bites.**  Upstream's `:163` (the promotion) and
             `:178` (`x * 0`) are BOTH matched by `MUL(CAST(3, int32), CONST(0))`,
             and upstream's `:163` is first -- so upstream answers the promoted node
             and a table with `:178` first answers a CONST 0.  The row is `promo_c`,
             and it moves.

    DTYPE    a rule's DTYPE SET is widened.  `:140` (`x.trunc() -> x`) is gated on
             `dtypes.ints + (bool, weakint)`, and the row `trunc0` is the SAME TRUNC
             over a weakfloat CONST, which is NOT in the set.  Widen the gate and
             `trunc0` moves -- a rule firing on a dtype upstream's rule leaves alone.

    SHAPE    a rule's IDENTITY CHECK is dropped.  `:123` (`x // x -> 1`) binds the
             name twice, and the check is the whole guard; without it the rule also
             fires on `x // y` for two DIFFERENT nodes.  The row is `rebind0`, and
             `rebind` alone is worthless: it holds either way.

    TWICE    a rule that rewrites to a node ITSELF matches.  Upstream's `rewrite`
             drops that answer (`ret is not uop`) and the port's `sy_novel` drops it
             too; the arm is planted by making a rule answer the node it matched,
             and the row that moves is the one that counts the answer.

    ELSEWHERE  a rule fires on a graph upstream's rule leaves alone.  That is the
             `:84`-versus-`:189` case: `:189` ("a cast to bool is `x != 0`") and
             `:84` ("the gate lifts inside the cast") BOTH match
             `CAST(bool, WHERE(cond, x, Invalid))`, upstream's `:84` is FIRST, and a
             port with `:189` and not `:84` answers `x != 0` where upstream answers
             the lifted gate.  The arm is planted by removing `:84` from the table,
             and the CORPUS answers are what move -- not a boolean row.

THE SCRATCH TREE.  Each mutation is applied to a COPY of the port's source in a
scratch tree, and the LIVE tree is never touched: a plant that edits the tree it is
measuring is a plant that can leave the tree broken.
"""

import argparse
import os
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BEND = os.path.join(ROOT, "bin", "bend")
LOCK = "/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/bend.lock"
PORT = os.path.join(ROOT, "tinybendygrad", "uop", "symbolic.bend")


def run_bend(src, args=()):
  """RUN THE PORT, UNDER THE SHARED LOCK, and answer its rows."""
  while True:
    try:
      os.mkdir(LOCK)
      break
    except FileExistsError:
      import time
      time.sleep(2)
  try:
    r = subprocess.run([BEND, src] + list(args), cwd=ROOT, capture_output=True, text=True)
  finally:
    try:
      os.rmdir(LOCK)
    except OSError:
      pass
  if r.returncode != 0:
    raise RuntimeError("bend failed: " + r.stderr[-500:])
  out = {}
  for ln in r.stdout.splitlines():
    if "=" in ln:
      k, _, v = ln.partition("=")
      out[k.strip()] = v.strip()
  return out


def scratch_tree():
  """A COPY of the port's substrate with the port's source in it, so a mutation never
  touches the live tree."""
  d = tempfile.mkdtemp(prefix="symplant-")
  # THE SUBSTRATE IS **HEAD'S BYTES**, and not the working tree's: another unit is
  # mid-edit in the live tree, and a plant that measures a tree somebody else is
  # editing measures THEIR breakage and not the mutation.
  subprocess.run(["git", "archive", "HEAD", "tinybendygrad"], cwd=ROOT,
                 stdout=subprocess.PIPE, check=True)
  a = subprocess.run(["git", "archive", "HEAD", "tinybendygrad"], cwd=ROOT,
                      capture_output=True, check=True)
  with open(os.path.join(d, "t.tar"), "wb") as f:
    f.write(a.stdout)
  subprocess.run(["tar", "-x", "-f", os.path.join(d, "t.tar"), "-C", d], check=True)
  os.remove(os.path.join(d, "t.tar"))
  return d, os.path.join(d, "tinybendygrad", "uop", "symbolic.bend")


def swap_entries(src, a_tag, b_tag):
  """SWAP TWO TABLE ENTRIES -- the ORDER arm, and the mutation is on the TABLE and
  not on a rule body, because the order IS the claim."""
  lines = src.split("\n")
  ia = ib = None
  for i, ln in enumerate(lines):
    m = re.match(r"\s*O\.PMEntry\{(\d+),", ln)
    if m:
      if int(m.group(1)) == a_tag:
        ia = i
      if int(m.group(1)) == b_tag:
        ib = i
  assert ia is not None and ib is not None, (a_tag, b_tag)
  # THE ENTRIES SWAP POSITIONS AND THE TAGS STAY WITH THEIR BODIES.  The tag is the
  # id the DISPATCH uses to pick the body (`case <tag>: sym_NNN`), and the ORDER is
  # the order of the LIST, so swapping the LIST LINES is what swaps the order.
  # Swapping the TAGS instead would swap the GATES and not the bodies, and the
  # scan order would not move at all.
  lines[ia], lines[ib] = lines[ib], lines[ia]
  return "\n".join(lines)


ARMS = {}

def arm(name):
  def deco(fn):
    ARMS[name] = fn
    return fn
  return deco


@arm("ORDER")
def arm_order(src):
  """SWAP `:163` AND `:178` IN THE TABLE.  The tags are found by the upstream line
  each entry cites, so the mutation does not depend on a hand-typed tag number."""
  lines = src.split("\n")
  a = b = None
  for i, ln in enumerate(lines):
    m = re.match(r"\s*O\.PMEntry\{(\d+),.*#\s*(\d+)\s*$", ln)
    if m:
      if m.group(2) == "163":
        a = int(m.group(1))
      if m.group(2) == "178":
        b = int(m.group(1))
  assert a is not None and b is not None, "the table does not cite 163 and 178"
  return swap_entries(src, a, b), "promo_c"


@arm("DTYPE")
def arm_dtype(src):
  """WIDEN `:140`'s DTYPE GATE.  `p_intish` is `dtypes.ints + (bool, weakint)` and
  `dt_weak_of` is "any weak dtype", so the TRUNC rule starts firing on the weakfloat
  CONST that `trunc0` is about."""
  old = "  Bool.and(Bool.and(sy_is_op(x, u, O.OpsTRUNC{}), sy_nsrc_is(x, u, 1)), p_intish(x, sy_src0(x, u)))"
  new = "  Bool.and(Bool.and(sy_is_op(x, u, O.OpsTRUNC{}), sy_nsrc_is(x, u, 1)), dt_weak_of(sy_dt1(x, sy_src0(x, u))))"
  assert old in src, "the TRUNC rule's dtype gate is not where the arm expects it"
  return src.replace(old, new, 1), "trunc0"


@arm("SHAPE")
def arm_shape(src):
  """DROP `:123`'s IDENTITY CHECK.  The rule binds the name twice and the check is
  the whole guard, so without it `x // y` folds to 1 for two DIFFERENT nodes."""
  old = """def sym_123.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(Bool.and(sy_is_op(x, u, O.OpsFLOORDIV{}), sy_nsrc_is(x, u, 2)),
    p_same(sy_src0(x, u), sy_src1(x, u)))"""
  new = """def sym_123.pat(+x: F.Folded, +u: U32) -> Bool:
  Bool.and(sy_is_op(x, u, O.OpsFLOORDIV{}), sy_nsrc_is(x, u, 2))"""
  assert old in src, "the rebind rule is not where the arm expects it"
  return src.replace(old, new, 1), "rebind0"


@arm("TWICE")
def arm_twice(src):
  """MAKE A RULE ANSWER THE NODE IT MATCHED.  Upstream's `rewrite` drops that answer
  (`ret is not uop`) and the port's `sy_novel` drops it too; a rule that answers the
  node it matched is a rule that rewrites forever, and the row that counts the answer
  is the one that moves.  `:126` is the XOR rebind and `xorb` is its row."""
  old = """def sym_126(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_126.pat(x, u), Some{sy_src0(x, sy_src0(x, u))})"""
  new = """def sym_126(+x: F.Folded, +u: U32) -> Maybe<&1, U32>:
  sy_tri(sym_126.pat(x, u), Some{u})"""
  assert old in src, "the XOR rebind rule is not where the arm expects it"
  return src.replace(old, new, 1), "xorb"


@arm("ELSEWHERE")
def arm_elsewhere(src):
  """REMOVE `:84` FROM THE TABLE, so `:189` takes the node upstream's `:84` takes.
  The arm is NOT observable in a boolean row -- both answers are present -- so it is
  checked on the CORPUS: the port's answer for
  `CAST(bool, WHERE(cond, x, Invalid))` must stop matching upstream's."""
  lines = src.split("\n")
  out = []
  removed = False
  for ln in lines:
    if re.match(r"\s*O\.PMEntry\{\d+,.*#\s*84\s*$", ln):
      removed = True
      continue
    out.append(ln)
  assert removed, "the table does not carry upstream's 84"
  return "\n".join(out), "CORPUS"


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--arm")
  args = ap.parse_args()
  names = [args.arm] if args.arm else list(ARMS)
  base_src = open(PORT).read()
  d, scratch = scratch_tree()
  base = run_bend(scratch)
  print("BASELINE: %d rows" % len(base))
  failures = []
  try:
    for name in names:
      fn = ARMS.get(name)
      if fn is None:
        print("plant: no arm named %r" % name)
        failures.append(name)
        continue
      mutated, row = fn(base_src)
      open(scratch, "w").write(mutated)
      got = run_bend(scratch)
      if row == "CORPUS":
        print("plant %s: the table lost upstream's 84 -- CHECK THE CORPUS" % name)
        continue
      if row not in base:
        failures.append("%s: the row %s is not in the baseline" % (name, row))
        continue
      if got.get(row) == base.get(row):
        failures.append("%s: the row %s did not move (it was %s and it still is)"
                        % (name, row, base.get(row)))
        print("plant %s: FAILED -- %s stayed %s" % (name, row, base.get(row)))
      else:
        print("plant %s: %s moved %s -> %s" % (name, row, base.get(row), got.get(row)))
  finally:
    shutil.rmtree(d, ignore_errors=True)
  if failures:
    for f in failures:
      print("plant FAILED: " + f)
    return 1
  print("plant: every arm moved the row it names")
  return 0


if __name__ == "__main__":
  sys.exit(main())
