#!/usr/bin/env python3
"""empty-cache-consumers.py -- what the new clause does to each of the SIX files that call
`read_fresh_cache`, measured by CALLING EACH CONSUMER'S OWN FUNCTION.

    .venv/bin/python .agents/slop/empty-cache-consumers.py       # exit 1 on any DISAGREE

WHY THIS IS SEPARATE FROM empty-cache-control.py. That file asserts the shared function. This
one asks the question that file cannot: a change to a shared function is only safe if no caller
DEPENDED on the old laxness, and "no caller depended on it" is not something you can read off a
diff -- it is a claim about each call site's branch, and each branch has to be run.

THE STATE IS ONE, AND IT IS THE ONLY ONE THAT MATTERS. A port's cache file holds `{}` and is
NEWER than its source. That is what a crashed lane leaves. Every consumer below is entered in
exactly that state, through its own entry point, and the probe records what it did.

WHAT IS OBSERVED IS THE CONSUMER'S OWN EFFECT, NOT THE RETURN VALUE. `wire-rows.bend_rows` and
`wire-pair.bend_rows` return `{}` in both worlds -- before, because that is what the cache said,
and after, because a lane that prints nothing yields nothing -- so the return value cannot tell
the two apart and a harness comparing it would report agreement twice. What differs is whether
the lane was RUN: after the fix the cache file on disk is rewritten with real rows, and before it
is left holding `{}`. That is the observable, and it is the whole difference.

  THE SIX, AND THE DENOMINATOR. Six files import the function; five are tools and one is an audit
  that exists to measure this. Three of the five tool consumers (`wire-rows`, `wire-pair`,
  `wire-survey`) are executed end to end here, and `rebase-scan-oracles` was executed as the
  oracle by empty-cache-control.py. `wire-sweep` is NOT executed and its row says so: its
  `main()` runs every candidate oracle as a subprocess after loading the caches, which is not
  worth two minutes to re-derive a six-line branch. Its verdict is from the source, marked.
  `wire-lanes.py` imports `rows` and `stripped_env` from wire_parse and NOT `read_fresh_cache`,
  so it is not a consumer at all and is listed only to show the grep that excluded it.

  NOTHING HERE IS A CENSUS OF REAL CACHES. Measured on this machine at the time of writing:
  /tmp/rebase-scan holds 76 .json files and rebase-wired-rows holds 33, and ZERO of the 109 hold
  an empty object. So the defect was REACHABLE and was not CURRENTLY EXERCISED on this tree: the
  fix changes no live output today, and every row below is a constructed state. A fix that moves
  nothing on the live tree is not a fix that does nothing -- it is a fix for a lane that has not
  crashed yet, and the control is what exercises it.
"""
import contextlib, io, os, pathlib, sys, tempfile

HERE = pathlib.Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

import wire_parse

FIXTURE = """\
import Base

def main() -> IO(Unit):
  do IO<Unit>:
    _ : Unit <- IO.print("control row = clean")
    IO.print("control_tight=clean")
"""
ROWS = {"control row": "clean", "control_tight": "clean"}


def load(path, name):
  """Every slop filename is hyphenated, so nothing here is importable by name. `rebase-scan-
  oracles.py:61` and `substrate-audit.py:72` each carry a copy of this loader already; this is
  the third, and it is three lines of `importlib` rather than a rule anyone can get wrong."""
  import importlib.util
  spec = importlib.util.spec_from_file_location(name, path)
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m


def state(root, src):
  """The one state: an EMPTY cache, NEWER than its source. Returns the port key, so every
  consumer is handed the same key and the same file."""
  key = str(src)  # absolute, so `REPO / key` in the consumers resolves to THIS fixture
  wire_parse.write_cache(root, key, {})
  cf = wire_parse.cache_file(root, key)
  os.utime(cf, (src.stat().st_mtime + 10, src.stat().st_mtime + 10))
  return key, cf


def main():
  rows = []
  with tempfile.TemporaryDirectory() as td:
    root = pathlib.Path(td)
    src = root / "fixture.bend"
    src.write_text(FIXTURE)
    key = str(src)

    def record(consumer, called, saw, verdict):
      rows.append((consumer, verdict))
      print(f"  {verdict:<8} {consumer:<22} {called}\n           {saw}")

    # 1. wire-rows.bend_rows -- the harm the brief names: a consumer that reads an empty row set,
    #    compares nothing, and reports agreement.
    wrows = load(HERE / "wire-rows.py", "wire_rows_under_probe")
    wrows.CACHE = root
    _, cf = state(root, src)  # REBUILT per consumer -- see below
    got = wrows.bend_rows(key, tries=1)
    left = __import__("json").loads(cf.read_text())
    record("wire-rows.bend_rows",
           f"returned {len(got)} rows; cache file left holding {len(left)}",
           "RE-MEASURED: the lane ran and the cache was rewritten with rows"
           if got and left else "TRUSTED: the empty cache was read back and the lane never ran",
           "CORRECT" if got and left else "LAX")

    # 2. wire-pair.bend_rows -- same six lines, same consequence, and its own cache dir.
    wpair = load(HERE / "wire-pair.py", "wire_pair_under_probe")
    wpair.CACHE = root
    _, cf = state(root, src)
    got = wpair.bend_rows(key, tries=1)
    left = __import__("json").loads(cf.read_text())
    record("wire-pair.bend_rows",
           f"returned {len(got)} rows; cache file left holding {len(left)}",
           "RE-MEASURED: the lane ran and the cache was rewritten with rows"
           if got and left else "TRUSTED: the empty cache was read back and the lane never ran",
           "CORRECT" if got and left else "LAX")

    # 3. wire-survey.main -- a pure cache reader, so it can be run whole. What changes is the
    #    DENOMINATOR, not the comparison: `set(orows) & set({})` is empty and was skipped before
    #    the fix too, so the disagreement table is identical and only `{len(bend)}/{len(ports)}`
    #    moves. A count that included a crash as a port row-set is the number that was wrong.
    wsurvey = load(HERE / "wire-survey.py", "wire_survey_under_probe")
    wsurvey.BEND = root
    _, cf = state(root, src)
    argv, buf = sys.argv, io.StringIO()
    sys.argv = ["wire-survey.py", key]
    try:
      with contextlib.redirect_stdout(buf):
        wsurvey.main()
    finally:
      sys.argv = argv
    tally = [l for l in buf.getvalue().splitlines() if "port row-sets" in l]
    counted = "1/1" in (tally[0] if tally else "")
    record("wire-survey.main",
           f"reported {tally[0].strip() if tally else 'NOTHING'}",
           "DROPPED the port: a refused cache is not a port row-set, and the denominator "
           "now says so" if not counted else
           "COUNTED the crash as a port row-set it had rows for",
           "CORRECT" if not counted else "LAX")

  # THE STATE IS REBUILT BEFORE EACH CONSUMER, and that is not tidiness. Consumer 1 REPAIRS the
  # cache file in place -- it runs the lane and writes the rows back -- so a probe that built the
  # state once and reused the file handed consumers 2 and 3 a REPAIRED cache and measured the
  # healthy path while calling it the crashed one. It did: the first version of this file
  # reported wire-survey as still counting a crash as a port row-set, on a cache file holding two
  # good rows. An instrument that repairs its own subject measures the repair.


  # The rows that were measured elsewhere, restated with where they came from. Restating a
  # measurement is not the same as making one, so each names the run that produced it.
  print()
  print("  MEASURED ELSEWHERE, restated with provenance (not re-run here):")
  print("    CORRECT   rebase-scan-oracles  executed as the oracle by empty-cache-control.py,")
  print("                                      states 3 and 4, both runs")
  print("    CORRECT   substrate-audit s2()   executed before and after; FAIL -> pass, exit 1 -> 0")
  print("    UNEXECUTED wire-sweep.main       its cache branch is byte-identical to")
  print("                                      wire-survey's (wire-sweep.py:93-98 vs")
  print("                                      wire-survey.py:56-61); main() then runs every")
  print("                                      candidate oracle as a subprocess, so this row")
  print("                                      is from the source and is NOT a measurement")
  print("    NOT A     wire-lanes.py          imports rows + stripped_env only; no cache read")
  print("             CONSUMER")

  n = len(rows)
  bad = [c for c, v in rows if v != "CORRECT"]
  print(f"\n  {n - len(bad)}/{n} EXECUTED consumers behave correctly;"
        + (f"  {len(bad)} still trust an empty cache: {', '.join(bad)}" if bad else "  0 do not"))
  print(f"  denominator: {n} of the 6 importers executed here; 1 measured elsewhere (the oracle),")
  print("  1 not executed and marked as such, 1 excluded because it is not a consumer.")
  return 1 if bad else 0


if __name__ == "__main__":
  sys.exit(main())
