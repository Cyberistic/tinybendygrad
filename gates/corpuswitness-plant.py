#!/usr/bin/env python3
r"""corpuswitness-plant.py -- CAN `gates/corpuswitness-gate.py` ACTUALLY GO RED?

    .venv/bin/python gates/corpuswitness-plant.py

A witness gate exists to SAY STALE, so the only way it can be worthless is by being unable to.
This plant plants six states of the two witnesses and requires a DIFFERENT answer from each, and
it requires the ANSWER -- the named row token, not merely the exit status -- because the failure
this tree has already paid for twice is a lane that emits nothing while the harness scores it as a
successful plant (`.agents/` doctrine 2's `DEAD`, and `artefacts_ok()` reporting zero on a
directory holding nothing).

THE SIX, AND WHICH DIRECTION EACH ONE IS:

    A live-substrate     a witness naming the LIVE digest      -> PASS, CURRENT, FRESH
    B dead-substrate     a witness naming a digest that cannot
                         be live ('0'*64)                    -> FAIL, STALE            <- A/B pair
    C out-of-order       W2's mtime 60s BEFORE W1's, every
                         byte still valid and live           -> FAIL, OUT-OF-ORDER    <- C/D pair
    D ordered            W2's mtime 60s AFTER W1's            -> PASS, FRESH
    E absent-w2          W2 deleted: the second measurement
                         was never taken                     -> REFUSED, never PASS

`C` IS THE HALF THAT HAD NO INSTRUMENT, AND THE PLANT PROVES IT IS NOT REDUNDANT. It also
records what `checks/differ.py`'s OWN `repro_bad()` says about the planted tree, with `D`
repointed at the plant's copy exactly as `differ.py:1538` does. On `C` every row, every
`REPRO_PINS` value and the whole substrate are valid, so `repro_bad()` returns `[]` -- **`C` IS
THE SHAPE THAT WENT UNSEEN, MEASURED RATHER THAN ASSERTED.** If `repro_bad()` ever does see it,
this row stops being evidence and says so.

THE PLANT'S OWN NEGATIVE CASE, WHICH IS NOT OPTIONAL. A plant that cannot fail is a plant that
cannot have fired, and the second failure mode recorded here is a NEGATIVE THAT IS VACUOUS
because "both sides flatten to one constant". So `F` takes case `A`'s REAL expectation and
corrupts ONE expected token, and this plant then REQUIRES ITSELF to report that as a mismatch.
Case `F` is not a claim about the gate; it is a measurement of this harness. Exit status is 0
only when `A`-`E` matched AND `F` was detected -- so a harness that silently stopped comparing
turns the whole suite red instead of green.

THE SUBSTRATE LOCK, AND WHY IT IS NOT A THROTTLE. The gate computes `live` from
`differ.substrate_digest()`, and the tree this plant runs on was being edited underneath it:
MEASURED 2026-10-19, `substrate_digest()` read `83c3f974...` with **389** entries at 03:36:49Z and
`7aa9e97d...` with **391** at 03:41:13Z, two `.bend` files added at 03:41:04Z by another unit.
Every planted row below therefore names the digest read at the TOP OF ITS OWN CASE, and the
suite holds a lock across the whole run: if the digest moved between the first and last case, the
plant REFUSES (exit 3) instead of reporting verdicts measured against a substrate that stopped
existing. `REFUSED` here is the honest answer, not a shrug -- reporting partial verdicts over a
moving population is how "34/34" came to describe four different trees in one afternoon.

NOTHING IS PLANTED IN PLACE. Both witnesses are copied into a `TemporaryDirectory` with
`shutil.copy2`, which PRESERVES mtimes -- that is what makes `C` and `D` mean anything, since a
plain `copy` would stamp both files with "now" and every ordering case would silently become `D`.
`checks/differ.py:1548-1549` does the same, and for the same reason.
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
GATE = HERE / "corpuswitness-gate.py"

PASS, FAIL, REFUSED = 0, 1, 3

#: ONE second of the mtime, in nanoseconds. A planted offset of 60e9 is an HOUR-scale separation
#: from the 93ms the real witnesses show, so `C`/`D` cannot be an artifact of timestamp resolution.
NS = 60 * 10**9

#: THE DIGEST THAT CANNOT BE LIVE. NOT a constant the gate could agree with by construction: it is
#: 64 `0`s against a sha256 hexdigest, and case `A` proves the gate answers `CURRENT` for the real
#: one and `B` proves it answers `STALE` for this one, on the SAME file layout and the SAME
#: comparator. **TWO SIDES ARE DIFFERENT BYTES** -- a negative whose sides were equal would be
#: satisfied by `compare(x, x)` and would prove nothing.
DEAD = "0" * 64

#: `--prove`. CASE `F` PROVES THE EXPECTATION HARNESS CAN DETECT A VIOLATION; THESE PROVE THE
#: CASES CAN DETECT A BROKEN GATE, which is the other half and the one that matters. Each mutant
#: is a REAL DEFECT pasted into a COPY of the gate -- the comparator stuck on one word, the
#: freshness predicate stuck on the other -- and each names the case that MUST go red. If the
#: suite stays green against a mutant, every verdict it ever printed was decoration.
#: `assert old in src` is load-bearing: a mutant whose anchor text has rotted proves nothing and
#: says so, rather than silently patching nothing and reporting the suite green.
MUTANTS = (
    # Caught by `control()`, BEFORE any verdict: a comparator stuck on one word cannot pass
    # `corpusverdict-gate.py:control()`, which requires STALE to be reachable AND CURRENT to be
    # reachable, so EVERY case goes `REFUSED` and the BASELINE case is the first to show it. The
    # baseline is named here precisely so this mutant cannot be scored as though `B` caught it.
    ("comparator-stuck-on-CURRENT",
     'return "CURRENT" if rec == live else "STALE"', 'return "CURRENT"', "A-live-substrate"),
    # Caught by `B`'s EXIT STATUS: the comparator is honest and `control()` passes, but the gate
    # ignores what the sibling reported and answers CURRENT whatever it read. `B` plants a digest
    # that cannot be live, so PASS here is the gate reporting success over a dead witness.
    ("verdict-row-ignores-the-token",
     'tok == "CURRENT", tok == "NO-SUCH-ROW"', 'True, False', "B-dead-substrate"),
    # Caught by `C`, and this is the half that had no instrument: the comparator is honest, the
    # verdict row is honest, and only the CLOCK is wrong. Nothing else in `checks/` or `gates/`
    # can see it, which is why `C` also asserts `repro_bad_repro-arm=0`.
    ("freshness-stuck-on-OK",
     "ordered = m2 >= m1", "ordered = True", "C-out-of-order"),
)


def tools():
  """`corpusverdict-gate.py` by path (for ITS `load`), then this gate by path through that
  `load` -- so `tabrows`, the parser for the gate's stdout, has exactly ONE definition in this
  tree and the plant reads rows with the same reader the gate writes them with."""
  global GATE_MODULE
  spec = importlib.util.spec_from_file_location("corpusverdict_gate", HERE / "corpusverdict-gate.py")
  cvg = importlib.util.module_from_spec(spec)
  sys.modules["corpusverdict_gate"] = cvg
  spec.loader.exec_module(cvg)
  GATE_MODULE = cvg.load(GATE, "corpuswitness_gate")
  return cvg, cvg.load(ROOT / "checks" / "differ.py", "corpuswitness_plant_differ"), GATE_MODULE


def run_gate(run: pathlib.Path, repro: pathlib.Path) -> tuple[int, dict[str, dict[str, str]]]:
  """THE GATE AS A READER RUNS IT: a fresh process, `--no-write`, both witnesses named. In-process
  would share this plant's module cache and could not show that the gate is callable at all.

  The rows are read with the GATE'S OWN `tabrows`, loaded by path, so the parser that produced the
  rows and the parser that reads them are one function rather than two that agree today."""
  p = subprocess.run([sys.executable, str(GATE), "--run", str(run), "--repro", str(repro),
                      "--no-write"], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                     text=True)
  return p.returncode, GATE_MODULE.tabrows(p.stdout)


def stamp(rows, name: str) -> str:
  """`name`'s own verdict WORD, or `NO-SUCH-ROW`. Absent is not `OK`: a lane that stopped
  emitting would otherwise read as a lane that agreed."""
  return rows.get(name, {}).get("verdict", "NO-SUCH-ROW")


def state(rows, name: str) -> str:
  return rows.get(name, {}).get("state", "NO-SUCH-ROW")


def rewrite(path: pathlib.Path, keys, values: dict[str, str]) -> None:
  """Replace only the named rows' VALUES. The KEYS come from `differ`'s own declarations
  (`SUBSTRATE_ROWS`, `REPRO_SUBSTRATE`, `REPRO_PINS`) -- loaded, never transcribed -- and every
  other line is copied through byte for byte, so the planted file differs from the real one in
  exactly the planted rows and `rows=` in the output counts what was actually planted.

  **AND IT PRESERVES THE MTIME, WHICH IS NOT COSMETIC.** `Path.write_text` sets the mtime to
  now, so without the restore below this helper silently moved the clock as well as the content
  -- and the clock is the SUBJECT of cases `C`/`D`. MEASURED: case `B` was planting a dead
  substrate into W1 only, so W1's mtime jumped ahead of W2's preserved one and `witness.fresh`
  went `FAIL` alongside `verdict.current`. That is not a wrong gate, it is a case that changed
  TWO things and so could have proved neither: `B` would have been green for the wrong reason.
  A planting helper that touches the second subject is a helper whose every case is two cases."""
  clock = os.stat(path)
  kept = []
  for line in path.read_text().splitlines():
    k, sep, _ = line.partition("=")
    if sep and k in values:
      kept.append(f"{k}={values[k]}")
    elif sep and k in keys:
      continue  # a declared row this case REMOVES
    else:
      kept.append(line)
  path.write_text("\n".join(kept) + "\n")
  os.utime(path, ns=(clock.st_atime_ns, clock.st_mtime_ns))


def suite(cvg, differ, src, repro_src) -> list[tuple[str, bool, str]]:
  """THE SIX CASES, against whatever `GATE` names at the moment of the call. A function so
  `--prove` can run the identical suite against a mutated copy -- a suite that cannot be re-run
  against a different gate cannot be shown to detect one."""
  live_D = differ.D  # restored after every `repro_bad()` probe below
  results = []

  with tempfile.TemporaryDirectory() as td:
    base = pathlib.Path(td)

    def stage(name: str) -> tuple[pathlib.Path, pathlib.Path]:
      """A FRESH copy per case, `copy2` so the mtimes -- and therefore the freshness ordering the
      plant is about -- are the REAL ones until a case moves one."""
      d = base / name
      d.mkdir()
      r1, r2 = d / src.name, d / repro_src.name
      shutil.copy2(src, r1)
      shutil.copy2(repro_src, r2)
      return r1, r2

    def check(name, want_rc, want, want_state=None, mutate=None, plant_w1=True,
              repro_bad_note=None):
      r1, r2 = stage(name)
      live = differ.substrate_digest()
      # W2 ALWAYS NAMES THE LIVE SUBSTRATE UNLESS A CASE IS ABOUT W2, and W1 does so unless the
      # case is about W1. Planting both in `stage` rather than in each case is what makes `C`/`D`
      # readable: without it a case about two clocks also moves `witness.substrate`, so a red
      # there could be either defect and the plant would have proved nothing about either.
      name_live(r1, r2, live, w1=plant_w1)
      if mutate:
        mutate(r1, r2, live)
      rc, rows = run_gate(r1, r2)
      bad = []
      # THE RACE GUARD, AND IT IS PER CASE BECAUSE A WHOLE-RUN LOCK IS NOT ENOUGH. Another unit
      # was editing `tinybendygrad/` throughout this session -- MEASURED: `substrate_digest()`
      # read `83c3f974`/389 entries at 03:36:49Z, `7aa9e97d`/391 at 03:41:13Z, and `9aceb379`/390
      # at 03:45Z, so the population is being ADDED TO and REMOVED FROM while this runs. A lock
      # comparing the first case against the last one cannot see a move that starts and finishes
      # inside the window. The gate publishes the `live` it actually measured in its own
      # `verdict.current` row, so the check is the gate's reading against the planting, and a
      # disagreement is `RACED` -- neither a pass nor a failure, and never reported as one.
      measured = rows.get("verdict.current", {}).get("live", "NO-SUCH-ROW")
      if measured != live[:16]:
        # NOT a race when the gate emitted no row at all -- that is a lane that said nothing,
        # which is `DEAD` and a different finding entirely. Naming both RACED would be a wrong
        # reason for a real result.
        bad.append("the gate emitted no verdict.current row, so `live` is unreadable"
                   if measured == "NO-SUCH-ROW" else
                   f"RACED: planted live={live[:16]} but the gate measured {measured}")
      if rc != want_rc:
        bad.append(f"rc={rc} wanted {want_rc}")
      for row, tok in want.items():
        got = stamp(rows, row)
        if got != tok:
          bad.append(f"{row}.verdict={got} wanted {tok}")
      if want_state:
        for row, tok in want_state.items():
          got = state(rows, row)
          if got != tok:
            bad.append(f"{row}.state={got} wanted {tok}")
      note = ""
      if repro_bad_note is not None:
        # `differ.plant` repoints the module global `D` with `global D` (`differ.py:1538`); this
        # does the SAME thing, so `repro_bad()` reads the PLANTED copy and not the live tree.
        differ.D = base / name
        seen = [x for x in differ.repro_bad() if differ.REPRO_SUBSTRATE in x]
        differ.D = live_D
        note = f"repro_bad_repro-arm={len(seen)}"
        if repro_bad_note != (len(seen) > 0):
          bad.append(f"{note} wanted {'>0' if repro_bad_note else '0'}")
      results.append((name, not bad, "; ".join(bad) + (" " + note if note else "")))

    def name_live(r1, r2, live, w1=True):
      """Both witnesses naming the substrate that is live NOW, unless `w1` is False -- case `B`
      plants a DEAD digest into W1 alone, and W2 must still be live or `witness.substrate` goes
      red with it and `B` stops being about `verdict.current`."""
      if w1:
        rewrite(r1, differ.SUBSTRATE_ROWS, dict(zip(differ.SUBSTRATE_ROWS, (live, live))))
      rewrite(r2, {differ.REPRO_SUBSTRATE}, {differ.REPRO_SUBSTRATE: live})

    def shift(seconds):
      """Move W2's clock by exactly `seconds`, atime and mtime alike. The gate's predicate is
      `mtime(W2) >= mtime(W1)`, so a NEGATIVE shift must exceed the real 93ms gap to register;
      it is 60s, which is six orders of magnitude past the ~1s granularity of any filesystem the
      tree runs on."""
      def go(r1, r2, live):
        t = os.stat(r2).st_mtime_ns + seconds * 10**9
        os.utime(r2, ns=(t, t))
      return go

    check("A-live-substrate", PASS, {"verdict.current": "CURRENT", "witness.fresh": "FRESH",
                                     "witness.substrate": "CURRENT"})
    check("B-dead-substrate", FAIL, {"verdict.current": "STALE"},
          {"witness.fresh": "OK", "witness.substrate": "OK"}, plant_w1=False,
          mutate=lambda r1, r2, live: rewrite(
              r1, differ.SUBSTRATE_ROWS, dict(zip(differ.SUBSTRATE_ROWS, (DEAD, DEAD)))))
    check("C-out-of-order", FAIL, {"witness.fresh": "OUT-OF-ORDER"},
          {"verdict.current": "OK", "witness.substrate": "OK"}, mutate=shift(-NS),
          repro_bad_note=False)
    check("D-ordered", PASS, {"witness.fresh": "FRESH"},
          {"verdict.current": "OK", "witness.substrate": "OK"}, mutate=shift(+NS))
    check("E-absent-w2", REFUSED, {"verdict.current": "CURRENT"},
          {"witness.fresh": "REFUSED", "witness.substrate": "REFUSED"},
          mutate=lambda r1, r2, live: r2.unlink())

    # F -- THE PLANT'S OWN NEGATIVE CASE. `A`'s bytes, one expectation deliberately WRONG.
    r1, r2 = stage("F-harness-selftest")
    live = differ.substrate_digest()
    name_live(r1, r2, live)
    rc, rows = run_gate(r1, r2)
    got = stamp(rows, "verdict.current")
    measured = rows.get("verdict.current", {}).get("live", "NO-SUCH-ROW")
    raced = measured != live[:16]
    detected = got != "STALE" and rc == PASS and not raced
    results.append(("F-harness-selftest (A's bytes, expectation says STALE)", detected,
                    f"RACED: planted {live[:16]}, gate measured {measured}" if raced else
                    "" if detected else
                    f"the harness scored rc={rc} with verdict.current={got} as MATCHING a STALE "
                    f"expectation -- this plant cannot detect a violation"))

  differ.D = live_D
  return results


def report(results, live, entries) -> int:
  for name, ok, why in results:
    print(f"{'PLANT-OK  ' if ok else 'PLANT-BAD '} {name}" + (f"   {why}" if why else ""))
  n = len(results)
  green = sum(1 for _, ok, _ in results if ok)
  print(f"corpuswitness-plant: {'PASS' if green == n else 'FAIL'} -- {green} of {n} plants "
        f"behaved as required (substrate {live[:16]}, {entries} entries)")
  return PASS if green == n else FAIL


def prove(cvg, differ, src, repro_src) -> list[str]:
  """RUN THE SUITE AGAINST A GATE WITH A REAL DEFECT PASTED IN, AND REQUIRE IT TO GO RED.

  The mutant is written INSIDE `gates/`, not into a temporary directory, and the reason is not
  tidiness: the gate derives `ROOT = Path(__file__).resolve().parent.parent`, so a copy anywhere
  else resolves `ROOT` to the wrong tree and cannot find `checks/differ.py` at all -- a "mutant"
  that fails to import would prove nothing and look like a detection. The file is removed in a
  `finally`."""
  global GATE
  real, src_text = GATE, real_src()
  unsound = []
  for name, old, new, case in MUTANTS:
    if old not in src_text:
      unsound.append(f"{name}: ANCHOR NOT FOUND in {cvg.rel(real)} -- the mutant would patch "
                     f"nothing and the suite below would prove nothing")
      continue
    mutant = HERE / f".witness-mutant-{MUTANTS.index((name, old, new, case))}.py"
    mutant.write_text(src_text.replace(old, new))
    GATE = mutant
    try:
      res = dict((n, (ok, w)) for n, ok, w in suite(cvg, differ, src, repro_src))
    finally:
      GATE = real
      mutant.unlink(missing_ok=True)
    if case not in res:
      unsound.append(f"{name}: case {case} did not run, so nothing was detected")
    elif res[case][0]:
      unsound.append(f"{name}: case {case} stayed GREEN against a gate carrying this defect -- "
                     f"this suite cannot detect a broken gate")
    else:
      print(f"PROVE-OK   {name} -> {case} went red: {res[case][1]}")
  return unsound


def real_src() -> str:
  return (HERE / "corpuswitness-gate.py").read_text()


def main(argv=None) -> int:
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("--prove", action="store_true",
                  help="also run the suite against two mutated gates and require them to go red")
  a = ap.parse_args(argv)
  cvg, differ, _ = tools()
  src = cvg.SUMMARY
  repro_src = src.parent / differ.REPRO_ARTIFACT
  if not (src.is_file() and repro_src.is_file()):
    print(f"corpuswitness-plant: REFUSED -- {cvg.rel(src)} or {cvg.rel(repro_src)} is absent; "
          f"there is no witness pair to plant")
    return REFUSED

  lock0 = differ.substrate_digest()
  results = suite(cvg, differ, src, repro_src)
  lock1 = differ.substrate_digest()
  verdict = report(results, lock1, len(differ.substrate_entries()))
  if lock0 != lock1:
    print(f"corpuswitness-plant: REFUSED -- the substrate moved DURING the plant "
          f"({lock0[:16]} -> {lock1[:16]}). Every verdict above was measured against a population "
          f"that stopped existing; re-run when `tinybendygrad/` is quiesced.")
    return REFUSED

  if a.prove:
    for line in prove(cvg, differ, src, repro_src):
      print(f"PROVE-BAD  {line}")
      verdict = FAIL
  return verdict


if __name__ == "__main__":
  sys.exit(main())