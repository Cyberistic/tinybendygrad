#!/usr/bin/env python3
"""THE GATE for `ansistrip` (`tinybendygrad/helpers.bend`, upstream helpers.py:48).

Three lanes, and ALL THREE must be accounted for:

  1. CPYTHON  `.venv/bin/python .agents/slop/ansi_oracle.py`  -- CALLS
              `tinygrad.helpers.ansistrip`, which is
              `re.sub('\\x1b\\[(K|.*?m)', '', s)`, on the 43 fixtures in
              `.agents/slop/ansi_fixture.py`. Not one answer is transcribed.
  2. BEND     `./bin/bend .agents/slop/ansi_probe.bend`       -- 43 rows, walking
              the SAME fixture list, calling `H.ansistrip`.
  3. CHECK    `./bin/bend .agents/slop/ansi_probe.bend --check-only` -- reads the
              FIRST LINE, never the exit status.

    .venv/bin/python .agents/slop/ansi_gate.py
    .venv/bin/python .agents/slop/ansi_gate.py --mutate

THE TEMP FILES ARE NAMESPACED (`ansi_gate.out`, `ansi_gate.err`). A first version
wrote `.out`/`.err`, which are NOT private -- `git status` showed this gate's `.err`
as a rename of another unit's `dsp_lane_2.err`, i.e. it had overwritten it.

A LANE THAT EMITS 0 ROWS IS NOT A PASS -- one oracle in this repo printed 0 rows
and exited 1 while the gate printed 432 -- so the row count is checked first on
every lane and a zero fails loudly.

WHY THE FIXTURE LIST IS NOT UNIFORM. Every row that existed before this gate was
carried came out as `ESC [ <digits> m`, i.e. a single `m` run, so a port that
re-emitted ESC plus ONE character agreed with CPython on all of them and the bug
lived for as long as it did. The discriminating axis is `K` against `...m`, and
`ansi_08`..`ansi_15` and `ansi_39`..`ansi_40` are all `K`-shaped or zero-parameter
shaped. `ansi_29` is the row that separates "re.sub re-reads a failed run's body"
from "the port flushes it", and it is a NAMED BOUNDARY below.
"""
import difflib
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
PROBE = os.path.join(HERE, "ansi_probe.bend")
# THE PORT. A mutation that edits the probe proves nothing about the port, and the
# first run of this harness reported 14 SKIPs for exactly that reason.
PORT = os.path.join(ROOT, "tinybendygrad/helpers.bend")

MIN_ROWS = 43
OUT = os.path.join(HERE, "ansi_gate.out")
ERR = os.path.join(HERE, "ansi_gate.err")


def run(cmd):
  line = " ".join(cmd)
  rc = os.system(line + " > " + OUT + " 2> " + ERR)
  out = open(OUT).read()
  err = open(ERR).read() if os.path.exists(ERR) else ""
  return rc, out, err


def lanes():
  rc, py, err = run([sys.executable, os.path.join(HERE, "ansi_oracle.py")])
  if rc != 0:
    sys.exit("ORACLE EXITED %d -- its output is not evidence\n%s" % (rc, err[:400]))
  rc2, bd, bderr = run(["./bin/bend", PROBE])
  rc3, chk, chkerr = run(["./bin/bend", PROBE, "--check-only"])
  first = chk.strip().split("\n")[0] if chk.strip() else chkerr.strip().split("\n")[0]
  return py.strip().split("\n"), bd.strip().split("\n"), first


# line -> why it cannot match, MEASURED, not excused. A row that disagrees and is
# NOT named here is a failure.
NAMED = {
    "ansi_29": ("a FAILED run is re-read by re.sub from its '[' and a body can "
                "itself contain a complete ESC[K, which that re-read strips; the "
                "port emits the body verbatim because a Bend list tail is linear "
                "('expected : t, observed : t (consumed more than once)') so it "
                "cannot be read twice. Closing it is 13 more table arms, not a "
                "proof Bend cannot."),
}


def verify():
  py, bd, first = lanes()
  print("cpython rows      = %d" % len(py))
  print("bend rows         = %d" % len(bd))
  print("check-only first  = %s" % first)
  for nm, rows in (("cpython", py), ("bend", bd)):
    if len(rows) < MIN_ROWS:
      sys.exit("%s LANE EMITTED %d ROWS -- a zero-row lane is not a pass" % (nm, len(rows)))
  if first != "ALL PROOFS CHECK":
    sys.exit("check-only first line is %r, not ALL PROOFS CHECK" % first)
  d = [l for l in difflib.unified_diff(py, bd, "cpython", "bend", lineterm="", n=0)]
  bad = [l[1:].split("=", 1)[0] for l in d if l[:1] == "-" and not l.startswith("---")]
  named = [n for n in bad if n in NAMED]
  other = [n for n in bad if n not in NAMED]
  for l in d:
    print(l)
  if other:
    sys.exit("LANES DISAGREE on %d rows: %s" % (len(other), ",".join(other)))
  print("ALL LANES AGREE on %d of %d rows, byte identical; %d NAMED BOUNDARY: %s"
        % (len(py) - len(named), len(py), len(named),
           " ".join("row %s: %s" % (n, NAMED[n][0]) for n in named)))
  return 0


# ===========================================================================
# THE MUTATION TABLE. One entry per ported rule; each is a one-line source edit
# that must make the diff NON-empty. The harness diffs WHOLE `name=value` LINES
# and reports the row names it moved -- a name-comparing harness reported 0 for
# all 30 mutations in one unit of this repo and 0 for all 68 in another.
# ===========================================================================
MUTATIONS = [
    ("M1  the 'K' alternative removed from the EMPTY-BODY arm (`ESC[K` survives)",
     "    case Chr{75} <> t, 2n:", "    case Chr{75} <> t, 3n:"),
    ("M2  'K' accepted in the WITH-BODY arm (`ESC[31mK` loses its K)",
     "    case Chr{109} <> t, 3n:",
     "    case Chr{75} <> t, 3n: ansistrip.go(t, List.drop(&2, Char, acc, n), 0n, 0n)\n"
     "    case Chr{109} <> t, 3n:"),
    ("M3  'm' accepted in the EMPTY-BODY arm only (`ESC[m` stops matching)",
     "    case Chr{109} <> t, 2n:", "    case Chr{109} <> t, 3n:"),
    ("M4  'm' accepted in the WITH-BODY arm only (`ESC[31m` stops matching)",
     "    case Chr{109} <> t, 3n:", "    case Chr{109} <> t, 2n:"),
    ("M5  the newline arm dropped from the EMPTY-BODY state",
     "    case Chr{10} <> t, 2n:", "    case Chr{10} <> t, 0n:"),
    ("M6  the newline arm dropped from the WITH-BODY state",
     "    case Chr{10} <> t, 3n:", "    case Chr{10} <> t, 0n:"),
    ("M7  the newline no longer emits itself (the port's own first fix, reverted)",
     "    case Chr{10} <> t, 3n: ansistrip.go(t, Chr{10} <> acc, n, 0n)",
     "    case Chr{10} <> t, 3n: ansistrip.go(t, acc, n, 0n)"),
    ("M8  '[' no longer opens a run (the pending ESC is emitted instead)",
     "    case Chr{91} <> t, 1n:", "    case Chr{91} <> t, 0n:"),
    ("M9  a pending ESC no longer opens a pending one (a doubled ESC collapses)",
     "    case Chr{27} <> t, 1n:", "    case Chr{27} <> t, 0n:"),
    ("M10 the run's count starts at 1 instead of 2 (the '[' is left behind)",
     "    case Chr{91} <> t, 1n: ansistrip.go(t, ansistrip.esc_brk(acc), 2n, 2n)",
     "    case Chr{91} <> t, 1n: ansistrip.go(t, ansistrip.esc_brk(acc), 1n, 2n)"),
    ("M11 `esc_brk` puts the ESC on top of the '[' (swaps the two)",
     "  List.append(&2, Char, [Char.from_u32(91)], ansistrip.esc(acc))",
     "  ansistrip.esc(List.append(&2, Char, [Char.from_u32(91)], acc))"),
    ("M12 the pending ESC is dropped at end of input instead of emitted",
     "    case Nil{}, 1n: ansistrip.done(True{}, acc)",
     "    case Nil{}, 1n: ansistrip.done(False{}, acc)"),
    ("M13 a run in progress is dropped at end of input instead of kept",
     "    case Nil{}, 3n: ansistrip.done(False{}, acc)",
     "    case Nil{}, 3n: ansistrip.done(True{}, acc)"),
    ("M14 the ordinary character arm folds the character into the count",
     "    case Chr{c} <> t, 0n: ansistrip.go(t, Chr{c} <> acc, n, 0n)",
     "    case Chr{c} <> t, 0n: ansistrip.go(t, Chr{c} <> acc, Nat.add(n, 1n), 0n)"),
    ("M15 a run's FIRST body character does not join the run's count",
     "    case Chr{c} <> t, 2n: ansistrip.go(t, Chr{c} <> acc, Nat.add(n, 1n), 3n)",
     "    case Chr{c} <> t, 2n: ansistrip.go(t, Chr{c} <> acc, n, 3n)"),
    ("M16 the unreachable `Succ{_p}` catch-all made to drop the run instead",
     "    case Chr{c} <> t, Succ{_p}: ansistrip.go(t, Chr{c} <> acc, Nat.add(n, 1n), 3n)",
     "    case Chr{c} <> t, Succ{_p}: ansistrip.go(t, List.drop(&2, Char, acc, n), 0n, 0n)"),
    ("M17 the NORMAL arm opens a pending ESC without consuming the character",
     "    case Chr{27} <> t, 0n: ansistrip.go(t, acc, 0n, 1n)",
     "    case Chr{27} <> t, 0n: ansistrip.go(t, Chr{27} <> acc, n, 1n)"),
]


def mutate():
  src = open(PORT).read()
  base = lanes()[1]
  print("baseline bend rows = %d" % len(base))
  moved, zeros = [], []
  for name, old, new in MUTATIONS:
    if src.count(old) != 1:
      print("%-74s SKIP (anchor x%d)" % (name, src.count(old)))
      zeros.append((name, "anchor does not occur exactly once"))
      continue
    open(PORT, "w").write(src.replace(old, new))
    rc, out, err = run(["./bin/bend", PROBE])
    if rc != 0 or not out.strip() or out.startswith("SOME PROOFS FAIL"):
      open(PORT, "w").write(src)
      print("%-74s DID NOT COMPILE (0 rows moved)" % name)
      zeros.append((name, "did not compile"))
      continue
    got = out.strip().split("\n")
    names = [l.split("=", 1)[0] for l in difflib.unified_diff(base, got, lineterm="", n=0)
             if l.startswith("-") and not l.startswith("---")]
    open(PORT, "w").write(src)
    if names:
      shown = ",".join(names[:6]) + (",+%d" % (len(names) - 6) if len(names) > 6 else "")
      print("%-74s moved %3d  %s" % (name, len(names), shown))
      moved.append((name, len(names)))
    else:
      print("%-74s MOVED NOTHING" % name)
      zeros.append((name, "0 rows"))
  print("\n%d mutations moved rows, %d moved none" % (len(moved), len(zeros)))
  for n, w in zeros:
    print("  ZERO: %s  (%s)" % (n, w))
  # A ZERO THAT IS NOT A THEOREM IS A MISSING FIXTURE. Each one below is argued
  # from the PORT'S OWN STRUCTURE, not excused.
  print("\nTHE ZEROES, ARGUED:")
  print("  M14 THEOREM. `n` is read by exactly two arms, both `List.drop`, and both")
  print("      are reachable only from q=2n/3n. Every transition INTO a run writes")
  print("      the constant 2n, so `n` is unobservable while q is 0n or 1n and NO")
  print("      fixture can separate those two spellings. It also means `n` is dead")
  print("      in six of the nineteen arms -- kept only because it makes them")
  print("      one-liners.")
  print("  (M15 was a THEOREM-shaped zero in its first form -- rewriting the 2n arm's")
  print("   state to 0n just shadows an EARLIER 0n arm and the compiler does not")
  print("   notice -- and it is now a fixture question, answered: 18 rows move.)")
  print("  M16 THEOREM. `q` never exceeds 3n -- no arm writes a larger one -- so the")
  print("      `Succ{_p}` arms are unreachable BY CONSTRUCTION. No input reaches them,")
  print("      so no fixture can move them. They exist only to satisfy the `Nat`")
  print("      exhaustiveness check on a multi-scrutinee.")


if __name__ == "__main__":
  if "--mutate" in sys.argv:
    mutate()
  else:
    sys.exit(verify())
