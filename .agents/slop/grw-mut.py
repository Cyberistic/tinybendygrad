#!/usr/bin/env python3
"""grw-mut.py -- the MUTATION SET for `codegen/__init__.bend`'s dispatcher.

WHY THIS FILE AND NOT A SHELL LOOP.  `.agents/slop/sched-mut.py` records a
harness that reported 60/60 AGREE for a mutation that never applied: the
heredoc's AssertionError went to stderr, `set -e` was off, `cp` restored the
file, and the comparator measured the UNMUTATED fixture.  So every mutation
here is checked FOUR ways before its number is printed:

  1. the pattern must be PRESENT in the file (else FATAL, run aborts);
  2. the pattern must be ABSENT after the replace (else FATAL);
  3. the mutant must COMPILE (`--check-only` must not name this file);
  4. the mutant must have PRODUCED THE SAME ROW NAMES as the baseline (a
     mutant that printed nothing would report "moved 0" and look like a
     blind spot rather than a harness failure).

and the harness ALSO RUNS A CANARY FIRST: mutation `CANARY` is one that is
known to move rows, and if it moves none the run aborts as a HARNESS FAILURE.
A mutation number is only evidence if the harness has been shown to fail once.

RUN:  python3 .agents/slop/grw-mut.py
"""
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
TARGET = os.path.join(ROOT, "tinybendygrad", "codegen", "__init__.bend")
BEND = os.path.join(ROOT, "bin", "bend")

# The rows this harness diffs.  Whole `name=value` LINES, never row NAMES --
# agent-core.md records a name-comparing harness reporting 0 for all 68
# mutations in one unit.
def rows_of(text):
  out = {}
  for ln in text.splitlines():
    m = re.match(r"^(grw_[A-Za-z0-9_]+)=(.*)$", ln.strip())
    if m:
      out[m.group(1)] = m.group(2)
  return out


def run_bend(path=TARGET):
  r = subprocess.run([BEND, path], capture_output=True, text=True, cwd=ROOT)
  return (r.stdout or "") + (r.stderr or "")


def check_only():
  """`ALL PROOFS CHECK` or nothing.  The gate is on the STRING and not on the
  exit status, because agent-core.md records `bend --check-only` exiting 1 on a
  file that is fine -- and the string is the only answer that distinguishes
  "this file is broken" from "a file it imports is broken".  A mutant that does
  not print it has not been shown to compile, so its rows mean nothing."""
  r = subprocess.run([BEND, TARGET, "--check-only"], capture_output=True, text=True, cwd=ROOT)
  return (r.stdout or "") + (r.stderr or "")


# (id, what it breaks, pattern, replacement)
MUTS = [
  # --- the dispatcher ITSELF -------------------------------------------------
  ("CANARY", "the dispatcher's two arms are exchanged: walk=False takes the one-pass driver",
   "Bool.pick(Rewritten, walk, walk_rewrite.counted(ar, sink, pm, ctx), unified_rewrite(ar, sink, pm, ctx))",
   "Bool.pick(Rewritten, walk, unified_rewrite(ar, sink, pm, ctx), walk_rewrite.counted(ar, sink, pm, ctx))"),
  # --- the fixpoint's stop test ---------------------------------------------
  ("M1", "the stop test is INVERTED, so pass 1 already counts as converged",
   "def unified_rewrite.same(+prev: U32, w: Rewritten) -> Bool: U32.is_eq(prev, Rewritten.index(w, prev))",
   "def unified_rewrite.same(+prev: U32, w: Rewritten) -> Bool: U32.is_ne(prev, Rewritten.index(w, prev))"),
  # --- the pass counter ------------------------------------------------------
  ("M2", "the converged arm reports done+1, so the counter grows on the arm that stopped the loop",
   "case 1n+f: Bool.pick(Rewritten, unified_rewrite.same(prev, w), Rewritten.hit(w, done),",
   "case 1n+f: Bool.pick(Rewritten, unified_rewrite.same(prev, w), Rewritten.hit(w, U32.add(done, 1)),"),
  ("M3", "`passes` reads the RECORD's field instead of the parameter (the shadowing trap)",
   "def Rewritten.hit(w: Rewritten, n: U32) -> Rewritten: match w: case Rewritten{ar, sink, repl, passes, capped}: Rewritten{ar, sink, repl, n, False{}}",
   "def Rewritten.hit(w: Rewritten, n: U32) -> Rewritten: match w: case Rewritten{ar, sink, repl, passes, capped}: Rewritten{ar, sink, repl, passes, False{}}"),
  # --- the bound -------------------------------------------------------------
  ("M4", "the pass bound is 1, and the fixture needs 2 passes, so the cap must fire",
   "def FIXPOINT_PASSES() -> Nat:\n  8n",
   "def FIXPOINT_PASSES() -> Nat:\n  1n"),
  ("M5", "the cap arm reports the FIXPOINT outcome, so a bound is indistinguishable from success",
   "    case 0n: Bool.pick(Rewritten, unified_rewrite.same(prev, w), Rewritten.hit(w, done), Rewritten.cap(w, done))",
   "    case 0n: Bool.pick(Rewritten, unified_rewrite.same(prev, w), Rewritten.hit(w, done), Rewritten.hit(w, done))"),
  # --- the sink read ---------------------------------------------------------
  ("M6", "the total read of the answer's sink falls back instead of reading the Maybe",
   "def Rewritten.index(w: Rewritten, fallback: U32) -> U32: Maybe.default(&2, U32, Rewritten.sink(w), fallback)",
   "def Rewritten.index(w: Rewritten, fallback: U32) -> U32: fallback"),
  # --- the walk arm ----------------------------------------------------------
  ("M7", "the walk arm claims TWO passes, which it never runs",
   "def walk_rewrite.lift(p: (O.Arena & Maybe<&2, U32> & Map<&2, U32>)) -> Rewritten:\n  (ar, r, repl) = p\n  Rewritten{ar, r, repl, 1, False{}}",
   "def walk_rewrite.lift(p: (O.Arena & Maybe<&2, U32> & Map<&2, U32>)) -> Rewritten:\n  (ar, r, repl) = p\n  Rewritten{ar, r, repl, 2, False{}}"),
  # --- the recursion's own pass ---------------------------------------------
  ("M8", "the fixpoint feeds the PREVIOUS sink back into the next pass instead of the one it produced",
   "unified_rewrite.go(f, U32.add(done, 1), Rewritten.index(w, prev), walk_rewrite.pass(Rewritten.index(w, prev), pm, ctx, w), pm, ctx)",
   "unified_rewrite.go(f, U32.add(done, 1), prev, walk_rewrite.pass(Rewritten.index(w, prev), pm, ctx, w), pm, ctx)"),
]


def main():
  orig = open(TARGET).read()

  base_out = run_bend()
  base = rows_of(base_out)
  if len(base) < 15:
    print(f"FATAL: baseline produced {len(base)} grw rows, expected >= 15\n{base_out}", file=sys.stderr)
    return 2
  if "ALL PROOFS CHECK" not in check_only():
    print("FATAL: baseline does not print ALL PROOFS CHECK -- the whole run is void",
          file=sys.stderr)
    return 2
  print(f"BASELINE {len(base)} rows, check-only clean")
  print(f"{'id':8} {'moved':6} rows   what")
  blind = []
  harness_dead = False
  for mid, what, pat, rep in MUTS:
    if pat not in orig:
      print(f"FATAL {mid}: PATTERN NOT PRESENT -- {what!r}", file=sys.stderr)
      open(TARGET, "w").write(orig)
      return 2
    open(TARGET, "w").write(orig.replace(pat, rep, 1))
    if pat in open(TARGET).read():
      print(f"FATAL {mid}: PATTERN STILL PRESENT after replace", file=sys.stderr)
      open(TARGET, "w").write(orig)
      return 2
    co = check_only()
    if "ALL PROOFS CHECK" not in co:
      print(f"FATAL {mid}: MUTANT DOES NOT TYPECHECK -- it did not run, so its rows "
            f"would be a blind spot rather than a measurement", file=sys.stderr)
      open(TARGET, "w").write(orig)
      return 2
    mut = rows_of(run_bend())
    if set(mut) != set(base):
      print(f"FATAL {mid}: MUTANT PRINTED A DIFFERENT SET OF ROW NAMES "
            f"(missing {sorted(set(base) - set(mut))}, new {sorted(set(mut) - set(base))}) "
            f"-- it did not run", file=sys.stderr)
      open(TARGET, "w").write(orig)
      return 2
    moved = sorted(k for k in base if base[k] != mut[k])
    tag = "  <-- CANARY" if mid == "CANARY" else ""
    print(f"{mid:8} {len(moved):6} {len(mut):5}   {what}{tag}")
    if moved:
      print(f"{'':8} {'':6} moved: {', '.join(moved)}")
    else:
      blind.append((mid, what))
    if mid == "CANARY" and not moved:
      harness_dead = True
    open(TARGET, "w").write(orig)

  # restore + re-verify
  open(TARGET, "w").write(orig)
  back = rows_of(run_bend())
  same = back == base
  print(f"RESTORED: rows {'IDENTICAL' if same else 'DIFFERENT'} to baseline")
  if blind:
    print("BLIND SPOTS (moved nothing), with reasons:")
    for mid, what in blind:
      print(f"  {mid}: {what}")
  if harness_dead:
    print("HARNESS FAILURE: the CANARY moved nothing, so every number above is suspect.")
    return 3
  print(f"CANARY moved rows, so the harness is armed.")
  return 0 if same else 2


if __name__ == "__main__":
  sys.exit(main())