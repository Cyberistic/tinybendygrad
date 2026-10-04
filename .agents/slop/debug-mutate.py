#!/usr/bin/env python3
"""debug-mutate.py -- does each new row MOVE when the DEBUG threshold is flipped?

    .venv/bin/python .agents/slop/debug-mutate.py

A gate that passes at every level proves nothing about a gate: a port that printed
UNCONDITIONALLY would pass all five levels of `debug-gate.sh`. This flips each
threshold and reports WHICH ROWS MOVED, by name, and an unexplained zero is a zero --
`agent-core.md`'s rule, and the reason this file exists rather than a sentence.

THE TREE IS COPIED FIRST. `agent-core.md`: "NEVER patch the live tree from a harness"
and "several units have lost whole files to tree-patching across restarts". So
`tinybendygrad/` and the gate file are copied into a scratch directory and every
mutation lands THERE. The copy is under `.agents/slop/` (never `$TMPDIR`: an oracle
written to `$TMPDIR` has been gone before the commit) and it is removed at the end.
Relative imports resolve because the scratch tree keeps the same layout --
`.agents/slop/debug-gate.bend` and `tinybendygrad/` are siblings of the same parents.

THE THREE LANES, MEASURED NOT ASSUMED: levels 0, 1 and 2 of the INTERPRETED bend lane.
`debug-gate.sh` already proves the compiled lane agrees with it; running it again per
mutation would triple the cost for nothing.

WHAT COUNTS AS A MOVE: a row whose whole `name=value` line differs from the baseline
AT THE SAME LEVEL. Comparing row NAMES is the trap named in `agent-core.md` -- a
name-comparing harness reported 0 for all 30 mutations in one unit -- so the whole
line is the key, and rows present in one side only count as moved.
"""
import os, shutil, subprocess, sys
import patch_not_apply as PNA

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
SCRATCH = os.path.join(ROOT, '.agents', 'slop', 'debug-mut-work')
BEND = os.path.join(ROOT, 'bin', 'bend')

# (label, file-under-scratch, old, new). Every `old` is asserted to be PRESENT exactly
# once before anything runs, because "pattern absent" silently turns a mutation into a
# no-op and a no-op reports 0 rows and looks like a theorem.
MUT = [
 ("memory.py:59's threshold 1 -> 2 (the level-1 site becomes level-2)",
  "tinybendygrad/schedule/memory.bend",
  "  mem_dbg_text.gate(H.debug_ge(dbg, 1), mem_dbg_text(p))",
  "  mem_dbg_text.gate(H.debug_ge(dbg, 2), mem_dbg_text(p))"),
 ("allreduce.py:16's threshold 2 -> 1 (the level-2 site becomes level-1)",
  "tinybendygrad/schedule/allreduce.bend",
  "  red_dbg_text.gate(H.debug_ge(dbg, 2), red_dbg_text(s, ndev, numel, dt))",
  "  red_dbg_text.gate(H.debug_ge(dbg, 1), red_dbg_text(s, ndev, numel, dt))"),
 ("state.py:260's threshold 2 -> 1",
  "tinybendygrad/nn/state.bend",
  "  sd_dbg_text.gate(Bool.and(H.debug_ge(dbg, 2), sd_fc_dummy(module)),",
  "  sd_dbg_text.gate(Bool.and(H.debug_ge(dbg, 1), sd_fc_dummy(module)),"),
 ("amdev.py:185's threshold 2 -> 3",
  "tinybendygrad/runtime/support/am/amdev.bend",
  "  am_dbg_text.gate(H.debug_ge(dbg, 2), am_dbg_malformed(devfmt))",
  "  am_dbg_text.gate(H.debug_ge(dbg, 3), am_dbg_malformed(devfmt))"),
 ("amdev.py:225's threshold 2 -> 3",
  "tinybendygrad/runtime/support/am/amdev.bend",
  "  am_dbg_text.gate(H.debug_ge(dbg, 2), am_dbg_boot(devfmt))",
  "  am_dbg_text.gate(H.debug_ge(dbg, 3), am_dbg_boot(devfmt))"),
 ("amdev.py:251's threshold 2 -> 3",
  "tinybendygrad/runtime/support/am/amdev.bend",
  "  am_dbg_text.gate(H.debug_ge(dbg, 2), am_dbg_ip(devfmt, ip))",
  "  am_dbg_text.gate(H.debug_ge(dbg, 3), am_dbg_ip(devfmt, ip))"),
 ("amdev.py:254's threshold 2 -> 3",
  "tinybendygrad/runtime/support/am/amdev.bend",
  "  am_dbg_text.gate(H.debug_ge(dbg, 2), am_dbg_final(devfmt))",
  "  am_dbg_text.gate(H.debug_ge(dbg, 3), am_dbg_final(devfmt))"),
 ("`debug_ge`'s `>=` -> `>` (every threshold becomes off-by-one, in all four files)",
  "tinybendygrad/helpers.bend",
  "def debug_ge(dbg: U32, n: U32) -> Bool:\n  U32.is_ge(dbg, n)",
  "def debug_ge(dbg: U32, n: U32) -> Bool:\n  U32.is_gt(dbg, n)"),
 # REPORTED AS A HARNESS BLIND SPOT, NOT CLOSED. `debug_print` is the only new def
 # whose return type is `Unit`, and the gate observes a site by its RETURNED LINE, so
 # nothing about this def is on any row's value path. Both directions of the mutation
 # are therefore invisible: writing `""` and never writing are equally undetectable by a
 # row comparison. The gate's level-0 control is real -- it is `mem_L0` / `ar_ring_L0`
 # and friends, which are EMPTY -- but it tests the SITES' gate, not `debug_print`'s.
 ("`debug_print` writes `""` too (the level-0 control is destroyed)",
  "tinybendygrad/helpers.bend",
  "def debug_print.of(empty: Bool, s: String) -> IO(Unit):\n"
  "  match empty:\n"
  "    case True{}: IO.pure(Unit, Unit{})\n"
  "    case _: IO.print(s)",
  "def debug_print.of(empty: Bool, s: String) -> IO(Unit):\n"
  "  match empty:\n"
  "    case True{}: IO.print(\"\")\n"
  "    case _: IO.print(s)"),
 ("`sd_fc_allowed`'s `not` is dropped (the whitelist test is inverted)",
  "tinybendygrad/nn/state.bend",
  "  Bool.not(sd_fc_allowed(module))",
  "  sd_fc_allowed(module)"),
 # The FIRST attempt at this mutation replaced `mem_dbg_same`'s `is_eq` with `is_lt`,
 # and it moved NOTHING -- correctly so, and the reason is worth keeping: the one plan
 # fixture SAVES bytes (12032 against 11776), so `is_eq` and `is_lt` are BOTH false
 # there and "print only when there is a saving" and "always print" are the same
 # function over every row `mem_plan` can reach. `mem_cond_same` / `mem_cond_diff` are
 # what made the arm reachable; this is the mutation they were added for.
 ("memory.py:59's `!=` condition is dropped (the line prints even with no saving)",
  "tinybendygrad/schedule/memory.bend",
  "def mem_dbg_same(omem: U32, nmem: U32) -> Bool:\n  U32.is_eq(omem, nmem)",
  "def mem_dbg_same(omem: U32, nmem: U32) -> Bool:\n  Bool.and(False{}, U32.is_eq(omem, nmem))"),
 ("`mem_mb`'s rounding `> 5000` -> `>= 5000` (half-UP where the tie is unreachable)",
  "tinybendygrad/schedule/memory.bend",
  "  mem_mb.hundredths.of(U32.is_gt(U32.mod(n, 10000), 5000), U32.div(n, 10000))",
  "  mem_mb.hundredths.of(U32.is_ge(U32.mod(n, 10000), 5000), U32.div(n, 10000))"),
 ("`gi_of_text`'s acceptance `st == MID` -> `st == PEND` (a trailing `_` would pass)",
  "tinybendygrad/helpers.bend",
  "def gi_take(st: U32, v: U32, d: U32) -> U32:\n  match st:\n    case 1: v\n    case _: d",
  "def gi_take(st: U32, v: U32, d: U32) -> U32:\n  match st:\n    case 1: v\n    case 2: v\n    case _: d"),
 ("`gi_tab`'s MID+`_` -> MID (a `_` anywhere between digits is accepted)",
  "tinybendygrad/helpers.bend",
  "  [1, 3, 3, 1, 2, 3, 1, 3, 3, 3, 3, 3]",
  "  [1, 3, 3, 1, 1, 3, 1, 3, 3, 3, 3, 3]"),
 ("`red_mode_name`'s ALL2ALL arm is unreachable (ALL2ALL prints RING)",
  "tinybendygrad/schedule/allreduce.bend",
  "  match m:\n    case 2: \"ALL2ALL\"\n    case 1: \"RING\"\n    case _: \"NAIVE\"",
  "  match m:\n    case 2: \"RING\"\n    case 1: \"RING\"\n    case _: \"NAIVE\""),
 ("`am_dbg_prefix` loses the `am ` (a wrong prefix on all four amdev sites)",
  "tinybendygrad/runtime/support/am/amdev.bend",
  "  String.concat([\"am \", devfmt, \": \"])",
  "  String.concat([devfmt, \": \"])"),
  # ---------------------------------------------------------------------------
  # THE NEW ROWS. Four mutations whose whole purpose is to show that `pin_*`, `fires_*`
  # and `env_ge4..7` are LOAD-BEARING rather than decoration, and one that plants the
  # non-cumulative-DEBUG trap the level extension exists to catch.
  # ---------------------------------------------------------------------------
  ("pin_nbytes' `div 2` -> `div 1` (the `sum(nbytes) * 2` of memory.py:45 is dropped)",
   ".agents/slop/debug-gate.bend",
   "urow(\"pin_nbytes\", U32.div(M.Planned.tot(p), 2))",
   "urow(\"pin_nbytes\", U32.div(M.Planned.tot(p), 1))"),
  ("`fire_join`'s seed `\"\"` -> `\"x\"` (every fires row gains a leading name)",
   ".agents/slop/debug-gate.bend",
   "  fire_join.go(ns, vs, \"\")",
   "  fire_join.go(ns, vs, \"x\")"),
  ("`fire_add` names a site even when it did NOT fire (fires_L0/L1 lose their bite)",
   ".agents/slop/debug-gate.bend",
   "def fire_add.of(empty: Bool, +acc: String, nm: String) -> String:\n  match empty:\n    case True{}: acc",
   "def fire_add.of(empty: Bool, +acc: String, nm: String) -> String:\n  match empty:\n    case True{}: nm"),
  ("`env_rows`'s `env_ge7` reads threshold 6 (the top of the scale is off by one)",
   ".agents/slop/debug-gate.bend",
   "    _ : Unit <- urow(\"env_ge7\", fired_of_ge(d, 7))",
   "    _ : Unit <- urow(\"env_ge7\", fired_of_ge(d, 6))"),
  # THE TRAP, PLANTED DIRECTLY. The named failure is "a port where DEBUG=4 behaves as
  # DEBUG=1", i.e. a DEBUG that STOPS being cumulative as the level rises. Re-levelling
  # the allreduce threshold-2 site from 2 to 4 is that shape: at DEBUG=3 the site goes
  # silent, which upstream it does not. `fires_L3` is the row that must catch it -- it is
  # the only row in this gate whose VALUE is the question "which sites fire at level 3",
  # so without it the mutation moves only `thr_ar` and `ar_ring_L*`.
  ("allreduce.py:16's threshold 2 -> 4 (a NON-CUMULATIVE DEBUG: level 2 goes silent)",
   "tinybendygrad/schedule/allreduce.bend",
   "  red_dbg_text.gate(H.debug_ge(dbg, 2), red_dbg_text(s, ndev, numel, dt))",
   "  red_dbg_text.gate(H.debug_ge(dbg, 4), red_dbg_text(s, ndev, numel, dt))"),
]

# THE LEVELS, AND WHY THE SET IS WHAT IT IS. The table asks "which rows moved", so a level
# is only worth a run if some mutation can move something there.
#
# LEVEL 6 WAS OMITTED FOR COST AND THAT OMISSION WAS MEASURED TO MATTER. With
# `("0","1","2","3","4","7")`, the mutation "`env_ge7` reads threshold 6" reported ZERO
# moved rows -- not because `env_ge7` cannot be seen but because `DEBUG >= 7` and
# `DEBUG >= 6` AGREE at every level in the set: at 0..4 both are 0, and at 7 both are 1.
# The level that separates them is 6, and it was not in the table. So 6 is in it now, and
# the entry that was a blind spot is a measured 7. **A MUTATION TABLE'S OWN LEVEL SET IS A
# COVERAGE CLAIM, AND A BLIND SPOT IN IT LOOKS IDENTICALLY TO A BLIND SPOT IN THE GATE.**
# The gate's level-6 control (`.agents/slop/debug-gate-control.py` C4) already caught this
# mutation, which is why it read as a gap in the TABLE rather than in the gate -- but a
# reader of the table alone would have concluded the gate could not see it.
#
# Level 5 is still omitted, and that omission is also measured rather than assumed:
# `env_ge5` is `DEBUG >= 5`, which `env_ge7` (threshold 7) already separates from every
# other level in the set, and no mutation in this table reads threshold 5.
LEVELS = ("0", "1", "2", "3", "4", "6", "7")


def rows_of(out):
  d = {}
  for l in out.split('\n'):
    if '=' in l and l.strip():
      k, v = l.split('=', 1)
      d[k] = v.strip()
  return d


def run(gate, level):
  env = dict(os.environ)
  env['DEBUG'] = level
  for tries in range(6):
    p = subprocess.run([BEND, gate], cwd=ROOT, env=env, capture_output=True, text=True)
    r = rows_of(p.stdout)
    if r:
      return r
  return {}


def main():
  if os.path.exists(SCRATCH):
    shutil.rmtree(SCRATCH)
  os.makedirs(os.path.join(SCRATCH, '.agents', 'slop'))
  shutil.copytree(os.path.join(ROOT, 'tinybendygrad'), os.path.join(SCRATCH, 'tinybendygrad'),
                  ignore=shutil.ignore_patterns('__pycache__'))
  shutil.copy(os.path.join(ROOT, '.agents', 'slop', 'debug-gate.bend'),
              os.path.join(SCRATCH, '.agents', 'slop', 'debug-gate.bend'))
  gate = os.path.join(SCRATCH, '.agents', 'slop', 'debug-gate.bend')

  base = {lvl: run(gate, lvl) for lvl in LEVELS}
  for lvl in LEVELS:
    if not base[lvl]:
      print("FATAL: the baseline produced 0 rows at level %s -- a bend stack overflow "
            "looks exactly like this" % lvl, file=sys.stderr)
      return 2
  print("baseline: %d rows at each of levels %s" % (len(base['0']), ", ".join(LEVELS)))

  print("| mutation | rows that moved (level: rows) | how many |")
  print("| --- | --- | --- |")
  zeros = []
  for label, rel, old, new in MUT:
    path = os.path.join(SCRATCH, rel)
    with open(path) as f:
      green = f.read()
    n = green.count(old)
    if n != 1:
      print(PNA.pipe(["(%s -- pattern occurs %d times) %s" % (PNA.not_applied(),
                                                              n, label[:60]),
                      "-", "-"], 3))
      continue
    with open(path, 'w') as f:
      f.write(green.replace(old, new, 1))
    moved = []
    for lvl in LEVELS:
      r = run(gate, lvl)
      if not r:
        moved.append("%s: DID NOT COMPILE" % lvl)
        continue
      for k in sorted(set(r) | set(base[lvl])):
        if r.get(k) != base[lvl].get(k):
          moved.append("%s: %s" % (lvl, k))
    with open(path, 'w') as f:
      f.write(green)
    short = label if len(label) <= 66 else label[:63] + "..."
    print("| %s | %s | %d |" % (short, ", ".join(moved) if moved else "NONE", len(moved)))
    if not moved:
      zeros.append(label)

  shutil.rmtree(SCRATCH)
  print("")
  if zeros:
    print("BLIND SPOTS (mutations that moved nothing), %d:" % len(zeros))
    for z in zeros:
      print("  -", z)
  else:
    print("no blind spots: every mutation moved at least one row")
  return 0


if __name__ == '__main__':
  sys.exit(main())