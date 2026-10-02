#!/usr/bin/env python3
"""rf-arg-mutate.py -- the mutation table for the `mp_replace` ARG repair in
tinybendygrad/schedule/rangeify.bend.

HARNESS CONTRACT, and why it is spelled out: this diffs WHOLE `name=value`
LINES. A harness that compares only row NAMES reported 0 for all 30 mutations in
one unit and 0 for all 68 in another, because the name is printed whether or not
its value moved.

The mutated file must stay in `tinybendygrad/schedule/` because a scratch copy in
another directory cannot resolve a relative import (`import ./../uop/ops.bend`),
which produced 22 phantom blind spots in one unit. So the harness mutates
`rangeify_work.bend` IN PLACE and restores it from a pristine baseline after every
step -- including on failure.

EVERY mutation here is a way of satisfying the type error that is NOT the repair.
The repair passes each rule's OWN node's arg. `ANone{}` is the obvious wrong
answer, and M6 -- passing a DIFFERENT node's arg -- is the one that distinguishes
"preserves its own arg" from "passes some arg"."""
import subprocess, sys, shutil, os, re

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
# the mutated file MUST sit beside the real one: a copy in another directory
# cannot resolve `import ./../uop/ops.bend`, which produced 22 phantom blind
# spots in one unit.  It is a WORK file, deleted at the end of the session, and
# rebuilt from the real file whenever it is absent -- so this harness never
# depends on state a mid-session death would destroy, and never leaves a stray
# 2800-line duplicate in the source tree for the coordinator to commit.
REAL = os.path.join(REPO, 'tinybendygrad/schedule/rangeify.bend')
TARGET = os.path.join(REPO, 'tinybendygrad/schedule/rangeify_work.bend')
PRISTINE = os.path.join(REPO, '.agents/slop/rangeify_work.pristine.bend')
BEND = os.path.join(REPO, 'bin/bend')

MUTATIONS = [
  # (id, label, old, new, note)
  ("M1", "rf_remove_noop_afters.of: own arg -> ANone",
   "case True{} : M.mp_replace(M.mp_op(ar, self), M.mp_arg(ar, self), ar, self, raf.keep_srcs(ar, self))",
   "case True{} : M.mp_replace(M.mp_op(ar, self), O.ANone{}, ar, self, raf.keep_srcs(ar, self))",
   "the repaired site, answered with the OTHER legal arg"),

  ("M2", "ab_7: own arg -> ANone",
   "M.mp_replace(M.mp_op(ar, self), M.mp_arg(ar, self), ar, self, ab_7_srcs(ar, self))",
   "M.mp_replace(M.mp_op(ar, self), O.ANone{}, ar, self, ab_7_srcs(ar, self))",
   "the repaired site, answered with the OTHER legal arg"),

  ("M3", "rf_no_indexing_calls.fin: own arg -> ANone",
   "M.mp_replace(M.mp_op(Bld.ar(b), self), M.mp_arg(Bld.ar(b), self), Bld.ar(b), self, Bld.ys(b))",
   "M.mp_replace(M.mp_op(Bld.ar(b), self), O.ANone{}, Bld.ar(b), self, Bld.ys(b))",
   "the repaired site, answered with the OTHER legal arg"),

  ("M4", "ct_8.of: own arg -> ANone",
   "case True{} : M.mp_replace(M.mp_op(ar, self), M.mp_arg(ar, self), ar, self,",
   "case True{} : M.mp_replace(M.mp_op(ar, self), O.ANone{}, ar, self,",
   "the repaired site, answered with the OTHER legal arg"),

  ("M5", "ab_7: own arg -> ANOTHER node's arg (its src0's)",
   "M.mp_replace(M.mp_op(ar, self), M.mp_arg(ar, self), ar, self, ab_7_srcs(ar, self))",
   "M.mp_replace(M.mp_op(ar, self), M.mp_arg(ar, M.mp_src0(ar, self)), ar, self, ab_7_srcs(ar, self))",
   "separates 'keeps its OWN arg' from 'passes some arg'"),

  ("M6", "ab_7: own arg -> the arg of a DIFFERENT fixture node (clik0's twin, af)",
   "M.mp_replace(M.mp_op(ar, self), M.mp_arg(ar, self), ar, self, ab_7_srcs(ar, self))",
   "M.mp_replace(M.mp_op(ar, self), M.mp_arg(ar, M.mp_src0(ar, M.mp_src(ar, self, 1))), ar, self, ab_7_srcs(ar, self))",
   "a non-Kernel arg, so the arg ROWS must go red too"),

  ("M7", "nic: own arg -> ANone (the nic twin of M2)",
   "M.mp_replace(M.mp_op(Bld.ar(b), self), M.mp_arg(Bld.ar(b), self), Bld.ar(b), self, Bld.ys(b))",
   "M.mp_replace(M.mp_op(Bld.ar(b), self), O.ANone{}, Bld.ar(b), self, Bld.ys(b))",
   "duplicate of M3, kept separate so a row moving one and not the other is visible"),

  ("M8", "revert to the PRE-REPAIR arg order (the original defect shape)",
   "M.mp_replace(M.mp_op(ar, self), M.mp_arg(ar, self), ar, self, ab_7_srcs(ar, self))",
   "M.mp_replace(M.mp_op(ar, self), ar, self, ab_7_srcs(ar, self))",
   "the 4-arg form that made the file stop compiling"),

  # ---- the ct_table `.f` inversion, measured rather than asserted ------------
  # For a `.f` pattern CPython rewrites the OUTER node (`name="idx"` on the
  # `.f(Ops.INDEX)`), so the accept set must be the outer op.  ct_table entry 4
  # carries `[OpsSTAGE]` (the sub-pattern's op) while `rf_same_tail` requires
  # `self.op is OpsINDEX`, so `ok` is False and `ct_4` can never fire.
  ("M9", "ct_table[4]: accept set {STAGE} -> {INDEX} (the outer node CPython rewrites)",
   "O.PMEntry{4, [O.OpsSTAGE{}],     [O.OpsINDEX{}]},          # 118  idx.f(STAGE)",
   "O.PMEntry{4, [O.OpsINDEX{}],     [O.OpsSTAGE{}]},          # 118  idx.f(STAGE)",
   "does the gate see ct_4 being UNBLOCKED, or is the subset test inert?"),

  ("M10", "ct_table[8]: accept set {MSTACK} -> {INDEX} (the outer node CPython rewrites)",
   "O.PMEntry{8, [O.OpsMSTACK{}],    [O.OpsMSTACK{}]}]         # 127  MSTACK.f(INDEX)",
   "O.PMEntry{8, [O.OpsINDEX{}],    [O.OpsMSTACK{}]}]         # 127  MSTACK.f(INDEX)",
   "the same inversion on the deviceless-MSTACK rule"),

  # ---- the falsity of the two rows the comments promise ---------------------
  ("M11", "ct_4: force its CLAIM test True (would a row see it?)",
   "def ct_4(+fx: F.Folded, +ar: O.Arena, +self: U32) -> M.Hop:\n  ct_4.of(rf_same_tail(ar, self), ar, self)",
   "def ct_4(+fx: F.Folded, +ar: O.Arena, +self: U32) -> M.Hop:\n  ct_4.of(True{}, ar, self)",
   "ct_4's comment promises a `ct_4_ans` row; does one exist in main?"),
]


def run_bend(path):
  p = subprocess.run([BEND, path, '--check-only'], cwd=REPO,
                     capture_output=True, text=True)
  return p.stdout + p.stderr


def gate(path):
  """the row output, as whole `name=value` lines"""
  p = subprocess.run([BEND, path], cwd=REPO, capture_output=True, text=True)
  out = p.stdout + p.stderr
  d = {}
  for line in out.splitlines():
    m = re.match(r'^([a-z0-9_]+)=(\S+)$', line.strip())
    if m: d[m.group(1)] = m.group(2)
  return d


def restore():
  shutil.copyfile(PRISTINE, TARGET)


if not os.path.exists(TARGET):
  shutil.copyfile(REAL, TARGET)
if not os.path.exists(PRISTINE):
  shutil.copyfile(TARGET, PRISTINE)

restore()
compile_head = run_bend(TARGET).splitlines()[0] if run_bend(TARGET).strip() else '(empty)'
print(f"baseline compile: {compile_head}")

# the substrate must be settled before a baseline is trusted
subprocess.run([BEND, TARGET, '--check-only'], cwd=REPO, capture_output=True)
base = gate(TARGET)
print(f"baseline rows: {len(base)}\n")

results = []
for mid, label, old, new, note in MUTATIONS:
  restore()
  src = open(TARGET).read()
  if old not in src:
    results.append((mid, label, "PATTERN-NOT-FOUND", [], note)); continue
  open(TARGET, 'w').write(src.replace(old, new, 1))
  head = run_bend(TARGET).splitlines()[0] if run_bend(TARGET).strip() else '(empty)'
  if 'ALL PROOFS CHECK' not in head:
    results.append((mid, label, f"DID NOT COMPILE: {head}", [], note)); restore(); continue
  got = gate(TARGET)
  moved = sorted([k for k in set(base) | set(got) if base.get(k) != got.get(k)])
  results.append((mid, label, f"compiled; {len(moved)} rows moved", moved, note))
  restore()

print(f"{'ID':4} {'MUTATION':52} {'RESULT':34} ROWS MOVED BY NAME")
print("-" * 150)
for mid, label, res, moved, note in results:
  print(f"{mid:4} {label:52} {res:34} {', '.join(moved) if moved else '(NONE -- blind spot)'}")
  print(f"     note: {note}")