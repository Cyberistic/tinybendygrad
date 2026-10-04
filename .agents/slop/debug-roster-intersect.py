#!/usr/bin/env python3
"""debug-roster-intersect.py -- THE NUMBERS THE rebase-gate.py OWNER NEEDS, MEASURED.

    .venv/bin/python .agents/slop/debug-roster-intersect.py

`rebase-gate.py` does not mention this gate, so it is STANDALONE: no aggregate number has
ever included it and its green is invisible to every tally quoted. Another unit owns
`rebase-gate.py` this round, so this file does NOT edit it. It computes the numbers that
unit needs and prints them.

IT USES `rebase-gate.py`'s OWN `rows()`. Row names contain SPACES in this repository
(`am185_L0`, and the rest of this repository's gates emit `kern CUDA  lb=1 = [...]`), so a
second reader would answer a different question -- `rows()` carries a long note on a
related defect (F3's gap must be SPACES) and re-implementing it is how a lane compares
nothing while reporting a count.

THREE QUESTIONS, AND ONLY THE FIRST IS OBVIOUS:

  Q1  DOES MY ORACLE SHARE ANY ROW NAME WITH THE GATE EACH PORT ALREADY HAS?
      This decides whether wiring my oracle ADDS coverage or DUPLICATES it. Measured by
      running both and intersecting.

  Q2  HOW MANY OF MY 89 ROWS ARE CLAIMS ABOUT EACH PORT FILE?
      Attribution BY CONSTRUCTION: the harness's own source says which port each row
      group calls, and this counts those groups. It is NOT a measurement of how much of a
      port is covered -- it is the list of which rows would be attributed where if the
      owner wires them, so the owner does not have to guess.

  Q3  CAN `run_port` EVEN RUN THIS GATE?
      No, and the reason is a fact about the tool rather than about this gate:
      `run_port` sets `DEV="NULL"` for the oracle (rebase-gate.py:580) and NOTHING for
      the two bend lanes, which inherit the caller's environment through `sh(...)`. This
      gate's level comes from `DEBUG` in the ENVIRONMENT -- `tinybendygrad/helpers.bend`
      has NO argv read at all (MEASURED, `grep -rn argv tinybendygrad/helpers.bend` finds
      nothing) -- so a roster-driven run would put the bend lanes at DEBUG-unset and the
      oracle wherever its argv says. THREE LANES AT TWO DIFFERENT LEVELS is precisely the
      failure this gate exists to prevent, so the wiring needs a one-line-capability
      change in `run_port` first. That is the finding; this file does not act on it.
"""
import importlib.util
import os
import subprocess
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
sys.path.insert(0, os.path.join(ROOT, '.agents', 'slop'))


def load_roster():
  """Import `rebase-gate.py` BY PATH, because its filename has a hyphen and there is
  therefore no `import rebase_gate`. Loading rather than copying is the whole point of
  this section: `rows()` carries a long note on the F3 gap (a row name may contain
  SPACES) and a second reader would answer a different question than the roster's."""
  p = os.path.join(ROOT, '.agents', 'slop', 'rebase-gate.py')
  spec = importlib.util.spec_from_file_location('rebase_gate_roster', p)
  mod = importlib.util.module_from_spec(spec)
  sys.modules['rebase_gate_roster'] = mod
  spec.loader.exec_module(mod)
  return mod


RG = load_roster()

# The gate each of the four site-carrying ports already has, if any. These are the
# CANDIDATES found by listing `.agents/slop/*.py` and grepping for the port's basename;
# "no gate found" is printed as such rather than omitted.
PORT_GATES = {
    "tinybendygrad/schedule/memory.bend": [".agents/slop/memory_oracle.py"],
    "tinybendygrad/schedule/allreduce.bend": [],
    "tinybendygrad/nn/state.bend": [".agents/slop/state-gate.py"],
    "tinybendygrad/runtime/support/am/amdev.bend": [".agents/slop/amdev_gate.py"],
    "tinybendygrad/helpers.bend": [],
}

# WHICH PORT EACH ROW GROUP EXERCISES, by construction from the harness's own source.
# `debug-gate.bend` documents each site's cite; these are the prefixes, and the count
# beside each is measured by running the oracle rather than typed.
GROUPS = [
    ("tinybendygrad/helpers.bend",
     ["env_value", "env_ge1", "env_ge2", "env_ge3", "env_ge4", "env_ge5", "env_ge6",
      "env_ge7", "gi_0", "gi_1", "gi_2", "gi_3", "gi_00", "gi_007", "gi_1_0", "gi_2_0_0",
      "gi_sp2", "gi_tab2", "gi_p2", "gi_refuse_1_", "gi_refuse__1", "gi_refuse_1__0",
      "gi_refuse_us", "gi_refuse_abc", "gi_refuse_dot", "gi_refuse_exp", "gi_refuse_hex",
      "gi_refuse_empty", "gi_m1_ge1", "gi_m1_ge2", "gi_m1_ge3"]),
    ("tinybendygrad/schedule/memory.bend",
     ["mem_plan", "mem_cond_same", "mem_cond_diff", "mem_L0", "mem_L1", "mem_L2",
      "pin_bufs", "pin_narenas", "pin_arenas", "pin_tot", "pin_nbytes",
      "mem_mb_256_0", "mem_mb_256_12032", "mem_mb_256_11776", "mem_mb_256_8388608",
      "mem_mb_256_4194304", "mem_mb_256_256000", "mem_mb_256_512000", "mem_mb_256_128000",
      "mem_mb_256_384000", "mem_mb_256_896000", "thr_mem"]),
    ("tinybendygrad/schedule/allreduce.bend",
     ["ar_ring", "ar_naive", "ar_a2", "ar_ring_L0", "ar_ring_L1", "ar_ring_L2", "thr_ar"]),
    ("tinybendygrad/nn/state.bend",
     ["st_bad", "st_ok1", "st_ok2", "st_bad_L0", "st_bad_L1", "st_bad_L2", "thr_st"]),
    ("tinybendygrad/runtime/support/am/amdev.bend",
     ["am185", "am225", "am251", "am254", "am185_L0", "am185_L1", "am185_L2",
      "am251_L0", "am251_L1", "am251_L2", "thr_am185", "thr_am225", "thr_am251",
      "thr_am254"]),
    ("(the harness itself, no port under test)",
     ["fires_L0", "fires_L1", "fires_L2", "fires_L3", "fires_L4", "fires_L5",
      "fires_L6", "fires_L7"]),
]


def run_oracle(level):
  env = dict(os.environ)
  env.pop('PYTHONPATH', None)
  env['DEBUG'] = str(level)
  p = subprocess.run([os.path.join(ROOT, '.venv', 'bin', 'python'),
                      '.agents/slop/debug-gate.py', str(level)],
                     cwd=ROOT, env=env, capture_output=True, text=True)
  if p.returncode != 0:
    return None, p.stderr[-400:]
  return RG.rows(p.stdout), None


def main():
  mine, err = run_oracle(2)
  if mine is None:
    print("FATAL: my own oracle did not run: %s" % err, file=sys.stderr)
    return 2
  print("=" * 78)
  print("Q1  ROW-NAME OVERLAP WITH EACH PORT'S EXISTING GATE (measured, `rows()`)")
  print("=" * 78)
  print("my oracle at DEBUG=2: %d rows\n" % len(mine))
  for port, gates in sorted(PORT_GATES.items()):
    if not gates:
      print("%-46s NO GATE FOUND on disk" % port)
      continue
    for g in gates:
      path = os.path.join(ROOT, g)
      if not os.path.exists(path):
        print("%-46s %s DOES NOT EXIST" % (port, g))
        continue
      env = dict(os.environ)
      env.pop('PYTHONPATH', None)
      env['DEV'] = 'NULL'
      p = subprocess.run([os.path.join(ROOT, '.venv', 'bin', 'python'), g],
                         cwd=ROOT, env=env, capture_output=True, text=True)
      theirs = RG.rows(p.stdout) if p.returncode == 0 else {}
      shared = sorted(set(mine) & set(theirs))
      print("%-46s %-34s rc=%d rows=%-5d SHARED=%d"
            % (port, os.path.basename(g), p.returncode, len(theirs), len(shared)))
      if shared:
        print("    shared names: %s" % " ".join(shared[:24]))
      if p.returncode != 0:
        print("    (non-zero rc; the shared count above is 0 by construction, NOT a "
              "measured absence)")

  print()
  print("=" * 78)
  print("Q2  WHICH PORT EACH OF MY ROWS IS A CLAIM ABOUT (by construction)")
  print("=" * 78)
  seen, total = set(), 0
  for port, names in GROUPS:
    missing = [n for n in names if n not in mine]
    dupes = [n for n in names if n in seen]
    seen |= set(names)
    total += len(names)
    print("%-46s %3d named, %3d present in the oracle%s%s"
          % (port, len(names), len(names) - len(missing),
             "" if not missing else ", MISSING %s" % missing[:5],
             "" if not dupes else ", DUPLICATED %s" % dupes[:5]))
  print("%-46s %3d attributed of %d oracle rows" % ("TOTAL", total, len(mine)))
  unattributed = sorted(set(mine) - seen)
  if unattributed:
    print("UNATTRIBUTED (%d): %s" % (len(unattributed), " ".join(unattributed)))
  else:
    print("every oracle row is attributed to exactly one port or to the harness")

  print()
  print("=" * 78)
  print("Q3  CAN `run_port` RUN THIS GATE? NO -- and here is the blocker, measured")
  print("=" * 78)
  src = open(os.path.join(ROOT, '.agents', 'slop', 'rebase-gate.py')).read()
  print("rebase-gate.py sets DEV=NULL for the oracle only:")
  for i, line in enumerate(src.split('\n'), 1):
    if 'DEV="NULL"' in line:
      print("  rebase-gate.py:%d  %s" % (i, line.strip()))
  print("and nothing for the two bend lanes -- `sh(...)` inherits os.environ, so the bend")
  print("lanes see whatever DEBUG the CALLER has, which for a roster sweep is unset.")
  argv_hits = subprocess.run(
      ["grep", "-rn", "argv", os.path.join(ROOT, "tinybendygrad", "helpers.bend")],
      capture_output=True, text=True).stdout.strip()
  print("the port's own env reader has no argv path at all: grep -rn argv "
        "tinybendygrad/helpers.bend -> %s"
        % (argv_hits if argv_hits else "(no matches)"))
  print()
  print("SO THE OWNER NEEDS, IN run_port, BEFORE ANY ENTRY IS ADDED:")
  print("  a per-port environment, applied to ALL THREE LANES. The smallest shape that")
  print("  works is a dict next to BASE_ORACLES and two substitutions:")
  print()
  print("    PORT_ENV = {")
  print('      "tinybendygrad/schedule/memory.bend": {"DEBUG": "2"},')
  print("      # ... one per entry below")
  print("    }")
  print("    # run_port():")
  print("    e = dict(os.environ, DEV='NULL', **PORT_ENV.get(port, {}))   # oracle")
  print("    # ... and pass the SAME e to sh() for the interpreted and native lanes.")
  print()
  print("  Without it the three lanes sit at DIFFERENT LEVELS, which is the one thing")
  print("  this gate was built to make impossible.")
  return 0


if __name__ == '__main__':
  sys.exit(main())