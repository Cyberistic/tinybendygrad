#!/usr/bin/env python3
"""PROVE the protocol: simulate a corpus addition and measure what breaks.

Safe to run anywhere: imports only the standard library + differ.py's PINS/WANT
(definitions, not the script's __main__).  Does NOT import tinygrad or run bend.
"""

import sys
sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/checks")

from differ import WANT, PINS  # type: ignore

# Simulate the corpus BEFORE the addition (25 graphs, the real set)
GRAPHS_BEFORE = set(WANT) | {"alu", "bit", "bw", "move", "where"}
assert len(GRAPHS_BEFORE) == 25, f"Expected 25 graphs, got {len(GRAPHS_BEFORE)}"
assert PINS["graphs"] == "25", f"PINS graphs expected 25, got {PINS['graphs']}"

graphs_before = sorted(GRAPHS_BEFORE)
unset_before = [g for g in graphs_before if g not in WANT]
print("=== BEFORE (25 graphs, 20 in WANT) ===")
print(f"  graphs         = {len(graphs_before)}")
print(f"  in WANT        = {len(WANT)}")
print(f"  unset          = {len(unset_before)}  ({', '.join(unset_before)})")
print(f"  graphs-answered= {len(graphs_before) - len(unset_before)}")
print(f"  PINS['graphs'] = {PINS['graphs']}  -- MATCHES" if len(graphs_before) == int(PINS['graphs']) else "  MISMATCH!")
print()

# --- ADD ONE DUMMY GRAPH "wmma" ---
# Simulate adding it to GRAPHS but NOT yet to WANT
GRAPHS_AFTER = GRAPHS_BEFORE | {"wmma"}
WANT_AFTER = dict(WANT)  # no "wmma" entry yet

graphs_after = sorted(GRAPHS_AFTER)
unset_after = [g for g in graphs_after if g not in WANT_AFTER]

print("=== AFTER ADDING 'wmma' (26 graphs, still 20 in WANT) ===")
print(f"  graphs         = {len(graphs_after)}")
print(f"  in WANT        = {len(WANT_AFTER)}")
print(f"  unset          = {len(unset_after)}  ({', '.join(unset_after)})")
print(f"  graphs-answered= {len(graphs_after) - len(unset_after)}")
print()

pin_graphs = int(PINS["graphs"])
print(f"  PINS['graphs']        = {PINS['graphs']}  (live: {len(graphs_after)})  {'MATCH' if pin_graphs == len(graphs_after) else '**MISMATCH**'}")
pin_unset = int(PINS["graphs-unset"])
print(f"  PINS['graphs-unset']  = {PINS['graphs-unset']}  (live: {len(unset_after)})  {'MATCH' if pin_unset == len(unset_after) else '**MISMATCH**'}")
pin_answered = int(PINS["graphs-answered"])
live_answered = len(graphs_after) - len(unset_after)
print(f"  PINS['graphs-answered']= {PINS['graphs-answered']}  (live: {live_answered})  {'MATCH' if pin_answered == live_answered else '**MISMATCH**'}")
print()

# Now simulate adding "wmma" to WANT with AGREE expectation
WANT_FIXED = dict(WANT)
WANT_FIXED["wmma"] = "AGREE"
unset_fixed = [g for g in graphs_after if g not in WANT_FIXED]

print("=== AFTER ADDING 'wmma' TO WANT (26 graphs, 21 in WANT) ===")
print(f"  graphs         = {len(graphs_after)}")
print(f"  in WANT        = {len(WANT_FIXED)}")
print(f"  unset          = {len(unset_fixed)}  ({', '.join(unset_fixed) if unset_fixed else 'NONE'})")
print(f"  graphs-answered= {len(graphs_after) - len(unset_fixed)}")
print()

# The correct PINS after the fix
print("=== PINS THAT MUST BE UPDATED ===")
print(f"  \"graphs\": \"{len(graphs_after)}\"           (was \"{PINS['graphs']}\")")
print(f"  \"graphs-unset\": \"{len(unset_fixed)}\"        (was \"{PINS['graphs-unset']}\")")
print(f"  \"graphs-answered\": \"{len(graphs_after) - len(unset_fixed)}\"  (was \"{PINS['graphs-answered']}\")")
print()

# --- WHICH GATE GOES RED WHEN A COUNT IS LEFT STALE ---
# The check in corpus-figure.py's run_health() reads D0-run-summary.txt
# and compares every pin.  Let's simulate a stale summary:
print("=== GATE THAT GOES RED ===")
print("File: `checks/corpus-figure.py` function `run_health()` (line 143)")
print()
summary = {
    "graphs": "26", "graphs-unset": "5", "graphs-answered": "21",
    "graphs-agree": "22",
}
print("  If D0-run-summary.txt says graphs=26 but PINS still says 25:")
print("  corpus-figure.py reports: `RUN HEALTH : **FAILED**`")
print(f"    graphs=26 (expected {PINS['graphs']})  -- RED")
print()
print("  Also goes red:")
print("  - checks/env-precond.py --check  (reads summary against its own PINS)")
print("  - checks/differ.py cmd_run's pinned values mismatch")

# Exit code: 1 means a mismatch was detected
live_vs_pin = sum([
    len(graphs_after) != int(PINS["graphs"]),
    len(unset_after) != int(PINS["graphs-unset"]),
    live_answered != int(PINS["graphs-answered"]),
])
print(f"\nPin mismatches detected: {live_vs_pin}")
sys.exit(live_vs_pin)