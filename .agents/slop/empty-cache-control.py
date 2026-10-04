#!/usr/bin/env python3
"""empty-cache-control.py -- the control for the SECOND HALF of the cache rule.

    .venv/bin/python .agents/slop/empty-cache-control.py          # exit 1 on any FAIL

A CACHE OLDER THAN ITS SOURCE IS NOT A READING, and neither is a cache that RECORDS NOTHING.
`wire_parse.read_fresh_cache` had the first half and not the second, so an empty cache -- which
is what a CRASHED lane leaves behind -- read `({}, 'fresh')`: the freshest file in the directory,
because bend stack-overflows about one run in twenty and prints zero rows, and an mtime cannot
tell a crash from a measurement. The sibling `rebase-scan-oracles.cached()` refused it all along
at rebase-scan-oracles.py:109, so the correction existed -- in one consumer of three-plus.

WHY THIS FILE AND NOT substrate-audit.py:s2(), which already asserts this. s2() is correct and
this does not replace it. s2() lives inside the audit that NAMED the defect, so it and the defect
share an author; a control that a later edit can relax is not a control. This file asserts one
property, prints every state it built, and its expectations come from CALLING the sibling
rather than from transcribing what the sibling says.

THE EXPECTATIONS ARE CALLED, NEVER TYPED. State 3's answer is checked against
`rebase_scan_oracles.cached()` executed on the same state, so the oracle is a second CPython
implementation that already had the rule. Transcribing `(None, 'empty')` here would have made
this file agree with `wire_parse.py` by construction, which is the exact failure
agent-core.md records for `nv_query_litter`: the port and the oracle were both wrong, and the
differ reported 0 disagreements over one mistake made twice.

WHAT IT REACHES, NAMED. `read_fresh_cache` is called DIRECTLY -- five times, once per state --
so no consumer stands between this control and the shared function. The only consumer it enters
is `rebase_scan_oracles.cached()`, and only because that function is the oracle it calls. It does
NOT reach wire-rows.py, wire-pair.py, wire-survey.py or wire-sweep.py. A control aimed at a
consumer is how this defect outlived a fix in another one; that is why the assertions here are on
the shared function and not on any of them.

THE DENOMINATOR IS FIVE STATES, NOT ONE, AND STATE 4 IS THE ONE THAT KEEPS THE REST HONEST.
A reader that answered 'empty' to everything -- a reader broken by this fix -- passes state 3 and
fails states 4 and 5. Reporting only state 3 would have been an unexplained zero wearing a
passing grade: it cannot tell "refuses a crash" from "refuses everything". State 4 also settles
the other direction of the trap, because an empty ANSWER must be distinguishable from a reader
that has not started: state 4 puts real rows in and gets them back out, so 'empty' in the output
above means a refusal, not a dead reader.

  usage: .venv/bin/python .agents/slop/empty-cache-control.py
"""
import os, pathlib, sys, tempfile

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import wire_parse


def load_scan():
  """rebase-scan-oracles.py, LOADED, never restated -- a test that re-implements the rule under
  test is testing the test, and `cached()` below is the whole oracle. This is the second copy of
  this exact bootstrap (rebase-gate-selftest.py:64 has the first; every file here is hyphenated,
  so the loader cannot be reached by `import`). Everything past the bootstrap is imported:
  `load_module`, `rows`, and `cached` all come from the owner."""
  import importlib.util
  spec = importlib.util.spec_from_file_location(
    "rebase_scan_oracles", HERE / "rebase-scan-oracles.py")
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m


scan = load_scan()
# THE GATE'S PARSER, imported, never copied -- wire_parse.py's own header says a reader that
# keeps only one emitter looks clean on the other, and two parsers make agreement a coincidence.
rows = scan.rows

PORT = "control/port.bend"
# Both emitters, because this tree has both. The spaced name is the whole reason
# wire_parse.rows exists; a control that only used `name=value` would not notice its removal.
ORACLE_TEXT = "PTX tensor_cores sm_75 = 2\ncontrol_tight=clean\n"
# Named so the printed denominator cannot drift from the states below: it did, once, as a
# literal `5` next to a variable-length list of assertions.
STATES = ("missing", "stale", "empty", "rows", "both")


def main():
  # `check` PRINTS and RECORDS in one step, so the tally cannot disagree with the rows above it.
  # It did once: a version that returned a bool and appended at seven call sites reported
  # "-2/5 states hold; 7 FAIL" under seven PASS lines, and that output would have been filed as
  # a failure against a rule that was holding. A counter that can disagree with its own evidence
  # is the same disease as an unexplained zero, wearing a denominator.
  rows_out, fails = [], []

  def check(name, got, want, why):
    ok = got == want
    rows_out.append(1)
    if not ok:
      fails.append(name)
    print(f"  {'PASS' if ok else 'FAIL'} {name:<9} -> {got!r}"
          + ("" if ok else f"   EXPECTED {want!r}")
          + f"    ({why})")
    return got
  with tempfile.TemporaryDirectory() as td:
    root = pathlib.Path(td)
    src = root / "port.bend"
    src.write_text("PROBE SOURCE\n")
    fresh = src.stat().st_mtime + 10  # newer than the source, like a cache written just now
    old = src.stat().st_mtime - 10

    # The row payload is produced by the GATE's reader, so state 4's rows are the ones a real
    # gate would compare and not a dict invented here.
    good = rows(ORACLE_TEXT)
    cf = wire_parse.cache_file(root, PORT)

    print(f"  states built ({len(STATES)}): each is a cache file's bytes + its mtime"
          f" against the source\n")

    cf.unlink(missing_ok=True)
    check("missing", wire_parse.read_fresh_cache(root, PORT, src), (None, "missing"),
          "no cache file at all")

    wire_parse.write_cache(root, PORT, good)
    os.utime(cf, (old, old))
    check("stale", wire_parse.read_fresh_cache(root, PORT, src), (None, "stale"),
          "cache older than its source")

    # STATE 3 -- THE DEFECT. An empty cache NEWER than its source: a lane that crashed.
    wire_parse.write_cache(root, PORT, {})
    os.utime(cf, (fresh, fresh))
    got = check("empty", wire_parse.read_fresh_cache(root, PORT, src), (None, "empty"),
                "a crash filed as a measurement")

    # THE ORACLE, CALLED. rebase-scan-oracles.cached() is a second CPython implementation of the
    # rule that already had this half; run on the SAME state, it must now say the same thing.
    saved, scan.CACHE = scan.CACHE, root
    try:
      check("oracle", got, scan.cached(PORT, src),
            "read_fresh_cache agrees with the sibling, both called")

      # STATE 4 -- THE HEALTHY PATH, which must still be read. Without it, state 3 passes for a
      # reader that refuses everything, and an 'empty' answer could not be told from a dead one.
      wire_parse.write_cache(root, PORT, good)
      os.utime(cf, (fresh, fresh))
      got_good = check("rows", wire_parse.read_fresh_cache(root, PORT, src), (good, "fresh"),
                       "real rows still read: both emitters")
      check("oracle2", got_good, scan.cached(PORT, src),
            "the sibling reads the same real rows")
      if good.get("PTX tensor_cores sm_75") != "2" or good.get("control_tight") != "clean":
        fails.append("the gate's rows() lost a row")
        print(f"  FAIL rows_gate -> {good!r}   (the gate's rows() lost a row)")

      # STATE 5 -- BOTH RULES ON ONE FILE. Empty AND older than its source: the mtime rule is
      # stated first and wins, so the answer names the OLDER file rather than the empty one.
      wire_parse.write_cache(root, PORT, {})
      os.utime(cf, (old, old))
      check("both", wire_parse.read_fresh_cache(root, PORT, src), (None, "stale"),
            "stale is checked before empty, so it names the older file")
    finally:
      scan.CACHE = saved

  n = len(rows_out)
  print(f"\n  {n - len(fails)}/{n} assertions hold;  {len(fails)} FAIL"
        + (f"  ({', '.join(fails)})" if fails else ""))
  print(f"  denominator: {len(STATES)} constructed cache states over {n} assertions, every one")
  print("  of them through `read_fresh_cache` ITSELF. This is NOT a claim about the 82 `{}` files")
  print("  in /tmp/rebase-scan or the live wire caches: nothing here touched them, and a")
  print("  constructed state is not a census.")
  return 1 if fails else 0


if __name__ == "__main__":
  sys.exit(main())
