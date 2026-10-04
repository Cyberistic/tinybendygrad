#!/usr/bin/env python3
"""mop-mut.py -- the MEASURED mutation table for tinybendygrad/uop/movement.bend.

One textual edit at a time on the working file, re-checked, re-run, and diffed against the
clean 26-row gate.  A mutation that does not compile is REPORTED as such, because "the
refused edit" is a result too, and so is "this edit moves nothing".

Every mutation here is a REVERT of one of the file's own fixes, so the row set it moves is
the set of rows that fix was load-bearing for.  That is the claim the table has to earn:
`M1` reverting `hop_self` must move the rows the gate reads for it, and a mutation that
moves a row nobody expected is itself the finding.

`movement.bend` IMPORTS `fold.bend`, and other agents own `fold.bend`, so a run that
overlaps a `fold.bend` edit measures a moving target and every row "moves".  Each mutation
therefore re-establishes the BASELINE before it counts: the clean gate is re-captured and
the gate only accepted if it still equals the 26 rows `mop-truth3.py` prints.  If a
neighbour's edit is in flight the run ABORTS with a message rather than publishing a
table, because "26 rows moved" for M6 is a symptom, not a finding.

    python3 .agents/slop/mop-mut.py
"""
import subprocess, sys, os, shutil, time

import tempfile
SANDBOX = tempfile.mkdtemp(prefix='mop-mut-')
SRC = 'tinybendygrad'
ORACLE = '.agents/slop/notes/mop-truth3.py'
# THE SANDBOX IS A FULL COPY OF `tinybendygrad/`, not just of the one file.
# `movement.bend` imports `fold.bend`, and other agents own `fold.bend`, so a run that
# edits the working file while a neighbour is mid-edit corrupts THEIR work AND measures a
# moving target -- which is what produced a run where every row "moved".  A copy has no
# neighbour, so the run is repeatable and touches nothing anyone else owns.  The imports
# are all RELATIVE (`./ops.bend`, `./../helpers.bend`), so a copy of the tree is a
# self-contained program and `bend` resolves them inside the copy.
F = os.path.join(SANDBOX, SRC, 'uop', 'movement.bend')
BAK = os.path.join(SANDBOX, 'movement.bend')

def stage():
  shutil.copytree(SRC, os.path.join(SANDBOX, SRC), ignore=shutil.ignore_patterns('__pycache__'))
  shutil.copy(F, BAK)
  # A snapshot is only useful if the tree it snapshots is GREEN.  Other agents own
  # `fold.bend` and edit it in place, so a copy taken mid-edit does not check and every
  # mutation after it is measured against a file that cannot compile.  Poll for the tree to
  # check, and only then freeze it -- which is also why the sandbox is a copy at all.
  for _ in range(int(os.environ.get('MOP_MUT_WAIT', '40'))):
    r = subprocess.run(['./bin/bend', F, '--check-only'], capture_output=True, text=True)
    if 'ALL PROOFS CHECK' in (r.stdout + r.stderr): return True
    time.sleep(15)
  return False

def run():
  r = subprocess.run(['./bin/bend', F], capture_output=True, text=True)
  return r.stdout + r.stderr

def checks():
  r = subprocess.run(['./bin/bend', F, '--check-only'], capture_output=True, text=True)
  return 'ALL PROOFS CHECK' in (r.stdout + r.stderr)

MUTS = [
  # 1. THE REPORTED INVERSION. `hop_self.of`'s arms swapped, which is the pre-fix state:
  #    `True` KEEPS the answer and `False` drops it, the inverse of ops.py:1610.
  ("M1  `hop_self.of`'s two arms swapped (the reported inversion)",
   "def hop_self.of(drop: Bool, +r: Hop) -> Hop:\n  match drop:\n    case True{}: Hop{hop_ar(r), 0}\n    case False{}: r",
   "def hop_self.of(drop: Bool, +r: Hop) -> Hop:\n  match drop:\n    case True{}: r\n    case False{}: Hop{hop_ar(r), 0}"),

  # 2. THE REPORTED OFF-BY-ONE. `mp_nsrc_ge` as `n < nsrc`, which is `> n` -- the pre-fix
  #    state, and the reason a `>=` call site silently became `>= n + 1`.
  ("M2  `mp_nsrc_ge` back to `n < nsrc` (the reported off-by-one)",
   "def mp_nsrc_ge(ar: O.Arena, i: U32, n: U32) -> Bool:\n  U32.is_ge(mp_nsrc(ar, i), n)",
   "def mp_nsrc_ge(ar: O.Arena, i: U32, n: U32) -> Bool:\n  U32.is_lt(n, mp_nsrc(ar, i))"),

  # 3. `mp_index.pick` answering the VALUE instead of resolving it through the STACK's srcs.
  #    ops.py:223 is `self.src[new_srcs[0].val]`, an INDEX, and the pre-fix code returned
  #    the value itself -- which for `C1` is 1, a different node from C1's index 2.
  ("M3  `mp_index.pick` returns the CONST VALUE, not `Arena.src(self, val)`",
   "def mp_index.pick(sel: Maybe<&1, U32>, ar: O.Arena, self: U32) -> U32:\n  match sel:\n    case Some{v}: mp_src(ar, self, v)\n    case None{}  : 0",
   "def mp_index.pick(sel: Maybe<&1, U32>, ar: O.Arena, self: U32) -> U32:\n  Maybe.default(&1, U32, sel, 0)"),

  # 4. `mp_replace` reading the arg off `self` again. Rule 3 REPLACES the arg, so reading
  #    `x2`'s own arg answers `x2` -- the very node the rule folds away -- and `P2` rewrites
  #    to P1 (22) instead of the composed P3 (24).
  ("M4  `mp_replace` reads the arg off `self` (rule 3's composed arg lost)",
   "def mp_replace(op: O.Op, arg: O.Arg, +ar: O.Arena, +self: U32, src: List<&2, U32>) -> Hop:\n  mp_hit(O.UOp.new(ar, op, src, arg, mp_tag(ar, self)))",
   "def mp_replace(op: O.Op, arg: O.Arg, +ar: O.Arena, +self: U32, src: List<&2, U32>) -> Hop:\n  mp_hit(O.UOp.new(ar, op, src, mp_arg(ar, self), mp_tag(ar, self)))"),

  # 5. Rule 3 composing out of `x2`'s SRCS rather than its `arg`. `mp_srcs` is a list of
  #    NODE INDICES; the generator indexes `x2.arg`.
  ("M5  `mp_3` composes the permutation from `x2`'s SRCS, not its `arg`",
   "      mp_replace(O.OpsPERMUTE{}, O.ATuple{mp_perm(p2, perm)}, ar, x2, mp_srcs(ar, x2))",
   "      mp_replace(O.OpsPERMUTE{}, O.ATuple{mp_perm(mp_srcs(ar, x2), perm)}, ar, x2, mp_srcs(ar, x2))"),

  # 6. `mp_ident.at` reading an arg ELEMENT as an arena index. The elements of `x.arg` are
  #    Python INTS, so the pre-fix `const_is(ar, i, k)` read whatever NODE that index names
  #    -- and `mp_4` never fired at all, so `permute_noop` was 0 under a rule that does fire.
  #    Both the def and its call site are edited, because the pre-fix signature took `ar`.
  ("M6  `mp_ident.at` compares the arg element as an arena index (mp_4 dead)",
   "def mp_ident.at(todo: Maybe<&2, List<&2, U32>>, k: Nat, ok: Bool) -> Bool:\n  match todo ok:\n    case _ False{}        : False{}\n    case None{} True{}    : False{}\n    case Some{Nil{}} True{}: True{}\n    case Some{i <> t} True{}:\n      +kk = k\n      mp_ident.at(Some{t}, 1n+kk, U32.is_eq(i, U32.from_nat(kk)))\n\ndef mp_4(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:\n  mp_4.of(mp_ident.at(arg_tuple(mp_arg(ar, self)), 0n, True{}), ar, self)",
   "def mp_ident.at(todo: Maybe<&2, List<&2, U32>>, +ar: O.Arena, +k: Nat, ok: Bool) -> Bool:\n  match todo ok:\n    case _ False{}        : False{}\n    case None{} True{}    : False{}\n    case Some{Nil{}} True{}: True{}\n    case Some{i <> t} True{}: mp_ident.at(Some{t}, ar, 1n+k, const_is(mp_const(ar, i), k))\n\ndef mp_4(+tb: F.Table, +ar: O.Arena, +self: U32) -> Hop:\n  mp_4.of(mp_ident.at(arg_tuple(mp_arg(ar, self)), ar, 0n, True{}), ar, self)"),

  # 7. `marg.go` appending on the way UP. `List.append(r, [x])` puts x at the END of r
  #    (MEASURED, probe-append.bend), so `step(go(..), ..)` REVERSES the margin -- and a
  #    reversed 2-element margin still has length 2, so only `shrink1_marg` notices.
  #    `marg.step` is renamed too, because swapping the call swaps which argument is `acc`.
  ("M7  `marg.go` appends on the way UP (reverses the merged margin)",
   "def marg.step(x: Marg, y: Marg, acc: List<&2, Marg>) -> List<&2, Marg>:\n  match x y:\n    case Marg{xo, xn} Marg{yo, yn}: List.append(&2, Marg, acc, [Marg{H.i64_add(xo, yo), yn}])\n\n# `zip(x.marg, s.marg)`, which TRUNCATES to the shorter, so an empty side gives an empty\n# margin and `mp_0` then lands on `_mop`'s `len(arg) == 0` early return.\ndef marg.go(ys: List<&2, Marg>, xs: List<&2, Marg>, acc: List<&2, Marg>) -> List<&2, Marg>:\n  match ys xs:\n    case Nil{} _        : acc\n    case _ <> _ Nil{}   : acc\n    case y <> yt x <> xt: marg.go(yt, xt, marg.step(x, y, acc))",
   "def marg.step(acc: List<&2, Marg>, x: Marg, y: Marg) -> List<&2, Marg>:\n  match x y:\n    case Marg{xo, xn} Marg{yo, yn}: List.append(&2, Marg, acc, [Marg{H.i64_add(xo, yo), yn}])\n\n# `zip(x.marg, s.marg)`, which TRUNCATES to the shorter, so an empty side gives an empty\n# margin and `mp_0` then lands on `_mop`'s `len(arg) == 0` early return.\ndef marg.go(ys: List<&2, Marg>, xs: List<&2, Marg>, acc: List<&2, Marg>) -> List<&2, Marg>:\n  match ys xs:\n    case Nil{} _        : acc\n    case _ <> _ Nil{}   : acc\n    case y <> yt x <> xt: marg.step(marg.go(yt, xt, acc), x, y)"),

  # 8. `marg_add` taking `n` from the INNER shrink. `UPat.f` names the OUTER `s`, so
  #    `(o,_),(p,n) in zip(x.marg, s.marg)` reads `n` off the outer. The two agree for S3/S4
  #    (every n is 1), which is why only `shrink1_marg` moves.
  ("M8  `marg_add` takes `n` from the INNER shrink (`n` one axis out)",
   "    case Some{a} Some{b} Some{c} Some{d}: Some{marg(marg_zip(b, a), marg_zip(d, c))}",
   "    case Some{a} Some{b} Some{c} Some{d}: Some{marg(marg_zip(d, c), marg_zip(b, a))}"),

  # 9. `mp_5.one`'s arity test relaxed to `>= 2`. The inner pattern is a two-TUPLE, so
  #    `strict_length` is on and a three-src element does not match.
  ("M9  `mp_5.one`'s strict two-tuple relaxed to `>= 2`",
   "           Bool.and(mp_nsrc_is(ar, x, 2), const_is(mp_const(ar, mp_src(ar, x, 1)), k)))",
   "           Bool.and(mp_nsrc_ge(ar, x, 2), const_is(mp_const(ar, mp_src(ar, x, 1)), k)))"),

  # 10. `mp_0`'s one-axis rank guard dropped, so a TWO-axis merged margin builds a SHRINK
  #     with the FIRST axis only -- a node Python never builds.
  # 10. `mp_0`'s one-axis rank guard dropped, so a TWO-axis merged margin builds a SHRINK
  #     carrying the FIRST axis only -- a node Python never builds. Reached by rewiring the
  #     scrutinee to a `Maybe`, because the pattern's own `Some{m <> Nil{}}` cannot be
  #     widened by an edit that still checks.
  ("M10 `mp_0`'s one-axis rank guard dropped (a 2-axis margin builds a 1-axis SHRINK)",
   "    case True{} Some{m <> Nil{}}   : mp_0.shrink(ar, self, m)\n    # TWO Margs, or none: a merged margin of length 1 is the ONE axis per side that\n    # `shape_to_shape_arg` turns into a bare CONST. The pattern is EXACTLY ONE element\n    # because `<>` on the scrutinee gives the head, and the `Nil{}` is the TAIL -- a\n    # three-scrutinee read of the same list would test the WHOLE list against `Nil{}`.\n    case _ _                        : Hop{ar, 0}",
   "    case True{} Some{m <> _}       : mp_0.shrink(ar, self, m)\n    case _ _                        : Hop{ar, 0}"),

  # 11. THE FIXTURE ADDRESSING. `G.ix` without the bottom's 0, so `G.at(g, n)` is one node
  #     PAST the one the row's comment names -- every result-index row in the file.
  ("M11 `G.ix` without the bottom's 0 (every row addresses the NEXT node)",
   "    [0,\n     O.Found.i(c0),",
   "    [O.Found.i(c0),"),

  # 12. `mp_early`'s subset test `and` -> `or`, which is the other reading of `issubset`.
  ("M12 `mp_early`'s subset test `and` -> `or`",
   "    case o <> t: Bool.and(O.op_in(have, o), mp_early.go(have, t))",
   "    case o <> t: Bool.or(O.op_in(have, o), mp_early.go(have, t))"),

  # 13. A MISSPELLED reject set, which is the failure mode `early_reject` really has.
  ("M13 rule 6's reject set {STACK, CONST} misspelled as {STACK, NOOP}",
   "   O.PMEntry{6, [O.OpsINDEX{}],   [O.OpsSTACK{}, O.OpsCONST{}]},",
   "   O.PMEntry{6, [O.OpsINDEX{}],   [O.OpsSTACK{}, O.OpsNOOP{}]},"),

  # 14. `hop_next`'s first-wins fold turned last-wins, which is the OTHER half of
  #     `PatternMatcher.rewrite` returning the FIRST non-None. Both `hold` (the earlier
  #     rules' answer) and `r` (this rule's) are read twice, so the mutant needs a `+`
  #     binder to compile at all -- which is a finding, not a detail: see (5).
  ("M14 `hop_first`'s first-wins test flipped (last-wins)",
   "def hop_first(+hold: U32, r: U32) -> U32:\n  hop_first.of(O.UOp.is_none(hold), hold, r)",
   "def hop_first(+hold: U32, +r: U32) -> U32:\n  hop_first.of(O.UOp.is_none(r), hold, r)"),

  # 15. A table entry DELETED rather than edited, and the LAST one, so no tag renumbers.
  ("M15 rule 8 (`INDEX on shaped INDEX`) DELETED from the table",
   "   O.PMEntry{7, [O.OpsINDEX{}],   [O.OpsINDEX{}]},    # movement.py:24  x(INDEX(idx1))\n   O.PMEntry{8, [O.OpsINDEX{}],   [O.OpsINDEX{}]}]    # movement.py:27  x(INDEX(buf, idx1_arg))",
   "   O.PMEntry{7, [O.OpsINDEX{}],   [O.OpsINDEX{}]}]    # movement.py:24  x(INDEX(idx1))"),
]

def rows(t):
  # a mutant that crashes prints no `k=v` lines at all, which is a RESULT, not a parse
  # error: `l.split` on a bare line raises and takes the whole run down.
  return dict(l.split('=', 1) for l in t.strip().split('\n') if '=' in l)

def oracle():
  r = subprocess.run(['python3', ORACLE], capture_output=True, text=True)
  # only the leading `name=value` block, which is what the gate prints; the oracle's later
  # `==` sections are diagnostics and several of their lines contain an `=`.
  out = []
  for l in r.stdout.split('\n'):
    if l.startswith('=='): break
    out.append(l)
  return rows('\n'.join(out))

def clean_gate():
  """The clean gate, and it must equal CPython -- or the fixture and the oracle disagree."""
  assert checks(), "the sandbox copy of movement.bend does not check"
  g = rows(run())
  if g != oracle():
    print("the clean gate does not match CPython.\n  bend: %s\n  py:   %s" % (g, oracle()))
    return None
  return g

def main():
  if not stage():
    print("the tree never reached a checking state (a neighbour is mid-edit); nothing measured.")
    return
  base = clean_gate()
  if base is None: return
  open('/tmp/mop_base.txt', 'w').write(run())
  print("clean gate captured and MATCHES CPython: %d rows\n" % len(base))
  results = []
  for name, old, new in MUTS:
    s = open(BAK).read()
    if old not in s:
      results.append((name, PNA.not_applied(), []))
      print("%-72s %s" % (name, PNA.not_applied()))
      continue
    open(F, 'w').write(s.replace(old, new, 1))
    if not checks():
      results.append((name, "DOES NOT CHECK", []))
      print("%-72s DOES NOT CHECK" % name)
      shutil.copy(BAK, F)
      continue
    m = rows(run())
    if not m:
      results.append((name, "RUNS NOTHING", []))
      print("%-72s RUNS NOTHING (the mutant crashes)" % name)
      shutil.copy(BAK, F)
      continue
    moved = sorted(k for k in base if base[k] != m.get(k))
    results.append((name, "ok", moved))
    print("%-72s moved %2d  %s" % (name, len(moved), ','.join(moved)))
    shutil.copy(BAK, F)
    # Re-establish the clean gate after every mutation rather than trusting a baseline
    # captured once up front: a mutant that leaves a LINGERING edit behind is caught here
    # instead of silently colouring the rows that follow it.
    if clean_gate() is None: return
  print("\n| mutation | rows moved | how many |")
  print("| --- | --- | --- |")
  for name, st, moved in results:
    print("| %s | %s | %d |" % (name, ' '.join(moved) if moved else 'NONE', len(moved)))
  assert checks()
  print("\nthe file is restored and still checks")

main()
