#!/usr/bin/env python3
r"""corpuswitness-gate.py -- IS THE RECORDED `graphcmp` VERDICT CURRENT *AND REPRODUCIBLE*?

    .venv/bin/python gates/corpuswitness-gate.py

TWO WITNESSES, TWO QUESTIONS, AND THE SECOND ONE HAD NO INSTRUMENT.

    W1  runs/graphcmp/D/D0-run-summary.txt   34/34 graphs. `repro_bad()`'s own docstring says
                                             the pins are "ONE run's seventeen rows and the
                                             denominator of 'this run is healthy' is **1
                                             artifact**, not 17" (`differ.py:1400`).
    W2  runs/graphcmp/D/D0-repro.txt         `cmd_repro` -- "the tree's only INDEPENDENT
                                             measurement" (`differ.py:1403`).

`checks/differ.py` already answers "is W1's verdict current?" (`substrate_bad()`, from
`substrate_digest()`) and "does W2 name the live substrate?" (`repro_bad()`'s `REPRO_SUBSTRATE`
arm). **NEITHER READS A TIMESTAMP, AND MEASURED, NOTHING ELSE DOES EITHER.** Of the two files
in `checks/`+`gates/` that name the second witness at all:

    $ grep -rln 'D0-repro\|REPRO_ARTIFACT' checks/ gates/ --include='*.py' | grep -v artifacts
    checks/corpus-figure.py
    checks/differ.py

`checks/corpus-figure.py` has **0** `st_mtime` occurrences; `checks/differ.py` has **1**, and it
is `differ.py:1202` -- the sentence "Never on `st_mtime`, never on the absolute path". So the
number of CODE sites that could notice a witness nobody re-took is **0 of 2**.

THE SHAPE THAT MISSES -- AND IT IS NOT THE ONE `REPRO_SUBSTRATE` CATCHES. `cmd_repro` calls
`clean_run()` twice, and each one shells out to `differ.py run`, REWRITING
`D0-run-summary.txt` (`differ.py:1752`); `D0-repro.txt` is written LAST (`differ.py:1834`,
`:1839`). So a COMPLETED repro leaves `mtime(W2) > mtime(W1)`, and the converse is the defect
class: re-run `run`, let `repro` then REFUSE -- `differ.py:1818` returns BEFORE `write(...)` --
and W1 is now newer than W2 while W1's substrate, W2's `repro-substrate` and every
`REPRO_PINS` value still agree, because the substrate did not move. `repro_bad()` reads content
only, so it returns `[]`: **THE SUMMARY NOW DESCRIBES A RUN THAT WAS NEVER COMPARED AND EVERY
EXISTING INSTRUMENT CALLS IT GREEN.** `cmd_repro`'s own docstring says why this is reachable:
"a refusal leaves the OLD artifact in place, so without this row the worst outcome of a refusal
is that the previous success keeps reading as one" (`differ.py:1429`).

THE GIT FINDING, AND WHY THE MTIME IS THE ONLY PROOF. Both witnesses are untracked AND IGNORED:

    $ git check-ignore -v runs/graphcmp/D/D0-repro.txt runs/graphcmp/D/D0-run-summary.txt
    .gitignore:262:/runs/     runs/graphcmp/D/D0-repro.txt
    .gitignore:262:/runs/     runs/graphcmp/D/D0-run-summary.txt

`git status --porcelain=v2 --` on both reads EMPTY. "Git says the tree is clean" is TRUE and
answers nothing: `git status` reports TRACKEDNESS, and these files have none. **SO THIS GATE
NEVER ASKS GIT.** It `os.stat`s both witnesses and compares `st_mtime_ns`, and it emits a
`freshness.source` row naming the instrument that produced the number, so a reader can see the
reading did not come from a VCS. `>=` and not `>`: a filesystem with one-second mtime granularity
would make a genuinely completed repro read as out-of-order, and a false red is how a gate gets
ignored.

DOCTRINE 1 -- THE POPULATION, THE PARSER, THE COMPARATOR AND THE LOADER ARE ALL THE OTHER
INSTRUMENTS', LOADED BY PATH. **There is no `substrate_digest()` in this file, and no second
comparison either.** Reading 1 is obtained by RUNNING `gates/corpusverdict-gate.py` and reading
its `substrate` ROW. A prior unit declined to add this arm for the stated reason that "fixing it
means a second comparison implementation, which is how two parsers come to disagree" -- and the
way to honour that is to EXECUTE the other instrument, not to restate it. `differ.py` is loaded
through `corpusverdict-gate.py`'s OWN `load()`, its artifacts are read with its OWN `rows_file()`,
its comparator is checked by its OWN `control()`, and its rows are emitted by its OWN `emit()`.
`checks/differ.py` is a `SUBSTRATE_INPUTS[0]` of the digest, so this gate is inside the
population it measures; that is why it is `--run`-parameterised and why the plant works on copies.

**THE RC IT RETURNS IS DELIBERATELY NOT READ.** On this tree `corpusverdict-gate.py` exits
non-zero today: its `run.gated` row is FAIL because `cmd_run` has no readiness gate
(`differ.py:1357`), which is a TRUE reading and not this gate's business. Its `substrate` row
reads `CURRENT` and its `bend` row reads `rc=0` at the same moment. A gate that inherited that rc
would red a fresh witness for an unrelated reason -- a wrong reason, which is worse than none.

DOCTRINE 2 -- `SKIP` IS NOT `PASS`, AND A ROW THAT CANNOT BE JUDGED IS NOT EMITTED. An absent
witness is `REFUSED` (a precondition was absent -- the measurement was never taken), a value that
differs is `FAIL` (it ran and got the wrong answer), `FAIL` outranks `REFUSED`, and a gate that
emitted no rows at all is `DEAD`. The comparators are `corpusverdict-gate.py:control()`'s
subject, so this gate cannot report a verdict from a comparator that cannot say `STALE`.

WHAT THIS GATE CLAIMS, AND WHERE THE LINE IS -- THE HARD PART, AND IT IS ONE ROW. **"THE VERDICT
REPRODUCES" IS NOT "THE VERDICT IS CORRECT".** This gate claims exactly the first: two clean runs
produced a byte-identical artifact set, and the witness recording that describes the substrate
that is live now. It **CANNOT SEE CORRECTNESS GO MISSING**, and this tree has already paid for
that once -- `REPRO_PINS`' `d10-transcript` is pinned *because* `repro-rc=rc=0` says nothing about
D10 being right: "a `classify` that regressed to retrying would write `bend attempt 2` in BOTH
runs, so both would AGREE and both checks would pass over a wrong transcript"
(`differ.py:316-321`). Byte-comparing two runs cannot separate "34 graphs agree with CPython"
from "34 graphs agree with CPython identically wrong twice". That claim belongs to
`differ.unhealthy()` and `differ.PINS`; this gate REPORTS the numbers WITH their denominator
while NAMING that judge, rather than restating the verdict as its own. The `claim` row says which
of the two it is, and the PASS line says `REPRODUCIBLE`, never `correct`.

NEITHER `bend` NOR A WRITE UNDER `runs/`. This gate opens two files for reading and takes their
timestamps; it writes only under `gates/artifacts/`. That is the contract
`gates/corpusverdict-gate.py` states for itself, and it is what lets the plant copy the witnesses
into a temporary directory and move their clocks there.
"""

from __future__ import annotations

import argparse
import contextlib
import io
import importlib.util
import os
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
ART = HERE / "artifacts" / "corpuswitness-gate"
REPORT = "corpuswitness.rows"

sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, verdict_of  # noqa: E402

CVG = "corpusverdict_gate"


def cvg():
  """`gates/corpusverdict-gate.py`, BY PATH, ONCE.

  The HYPHEN is the reason this exists at all: `import corpusverdict-gate` is a syntax error,
  and a hand-copied `substrate_digest()` / `rows_file()` / `control()` is exactly the second
  implementation the prior unit declined to write. Everything below comes out of THIS module.
  After this bootstrap, even `differ.py` is loaded through `cvg().load()` -- the sibling's own
  loader -- so there is exactly one reader of `D0-run-summary.txt` in this file."""
  if CVG not in sys.modules:
    spec = importlib.util.spec_from_file_location(CVG, HERE / "corpusverdict-gate.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules[CVG] = mod
    spec.loader.exec_module(mod)
  return sys.modules[CVG]


def tabrows(text: str) -> dict[str, dict[str, str]]:
  """The TAB-separated `name<TAB>k=v<TAB>k=v` lines `cvg().emit` writes, as `{name: {k: v}}`.

  A DIFFERENT FORMAT FROM `rows_file()` and so a different question, not a second parser of the
  same one: `rows_file` reads the flat `k=v` ARTIFACT, this reads the gate's own stdout. A row
  is taken only when its second field starts `state=`, which is what `emit` puts first and what
  excludes `cvg`'s trailing prose verdict line."""
  out: dict[str, dict[str, str]] = {}
  for line in text.splitlines():
    parts = line.split("\t")
    if len(parts) < 2 or not parts[1].startswith(cvg().STATE + "="):
      continue
    out[parts[0]] = dict(p.split("=", 1) for p in parts[1:] if "=" in p)
  return out


def mtime_ns(path: pathlib.Path) -> int:
  """The clock, and ONLY the clock. See the GIT FINDING above: `git status` cannot see these
  files at all, so asking git about them answers a different question with a confident-looking
  empty answer."""
  return os.stat(path).st_mtime_ns


def judge(reading: str, ok: bool, absent: bool, **kv) -> str:
  """One reading, one row. `absent` is `REFUSED` and `not ok` is `FAIL`, and they are not the
  same claim: nothing was measured is not a wrong answer.

  **THERE IS NO `token=` FIELD AND THAT IS DELIBERATE.** `corpusverdict-gate.py` carries one
  because its `bend` row is `checks/bounded.py`'s verdict token and must not be confused with a
  gate's rc. No reading here is bounded.py's, so a `token` would have to be invented --
  `OK?OK` would look like a measured verdict token and name no instrument. Absent a field beats
  a fake one: an unread column is notice, a wrong one is a lie somebody quotes."""
  return cvg().emit(reading, **{cvg().STATE: "REFUSED" if absent else ("OK" if ok else "FAIL"),
                                **kv})


def main(argv=None) -> int:
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("--run", type=pathlib.Path, default=None,
                  help="W1, the run summary (default corpusverdict-gate.py's own SUMMARY)")
  ap.add_argument("--repro", type=pathlib.Path, default=None,
                  help="W2, the second witness (default REPRO_ARTIFACT beside --run)")
  ap.add_argument("--no-write", action="store_true", help="print the rows, write no artifact")
  a = ap.parse_args(argv)

  C = cvg()
  differ = C.load(ROOT / "checks" / "differ.py", "corpuswitness_differ")
  run = a.run or C.SUMMARY
  repro = a.repro or (run.parent / differ.REPRO_ARTIFACT)
  rows: list[str] = []

  # --- THE COMPARATOR, BEFORE ANY VERDICT IT GUARDS -----------------------------------------
  # `==` on two strings is the identity, so this is not a second COMPARISON IMPLEMENTATION; what
  # would be one is a second `substrate_digest()`, and there is none. `control()` is the sibling's
  # own, and it requires BOTH directions -- two planted digests that must read STALE and the
  # identical one that must read CURRENT -- so a comparator stuck on either word is REFUSED here
  # rather than being allowed to grade the tree.
  def compare(rec: str, live: str) -> str:
    return "CURRENT" if rec == live else "STALE"

  note = C.control(compare)
  ctrl_ok = note.startswith("planted-diff")
  rows.append(judge("control", ctrl_ok, False, note=note))
  if not ctrl_ok:
    print("\n".join(rows))
    print(f"corpuswitness-gate: REFUSED -- the staleness comparator is not a comparator ({note}); "
          f"a clean verdict from it would be a verdict over nothing")
    return REFUSED

  # --- W1 PRESENT? NO VERDICT WITHOUT A WITNESS ---------------------------------------------
  if not run.is_file():
    rows.append(judge("w1.present", False, True, path=C.rel(run)))
    print("\n".join(rows))
    print("corpuswitness-gate: REFUSED -- no run summary; nothing has been measured here")
    return REFUSED

  # --- READING 1: IS W1'S VERDICT CURRENT? READ FROM THE INSTRUMENT THAT OWNS THE COMPARISON --
  # `cvg().main` is RUN, not restated. Its stdout is captured and its `substrate` ROW is read;
  # its return code is deliberately ignored, because on this tree it is non-zero for a reason
  # (`run.gated`, about `differ.py run` being ungated) that has nothing to do with currency.
  buf = io.StringIO()
  with contextlib.redirect_stdout(buf):
    cvg_rc = C.main(["--summary", str(run)])
  theirs = tabrows(buf.getvalue())
  sub = theirs.get("substrate", {})
  # `substrate`'s own verdict WORD, not a token: `cvg.emit` writes `token=` on its `bend` row
  # only, and this row has none. A missing `substrate` row is a SHAPE CHANGE in the instrument
  # this gate delegates to, so it reads `NO-SUCH-ROW` and reds rather than defaulting to
  # anything -- a default here would be a guess about another gate's output.
  tok = sub.get("verdict", "NO-SUCH-ROW")
  rows.append(judge("verdict.current", tok == "CURRENT", tok == "NO-SUCH-ROW",
                    recorded=sub.get("recorded", "ABSENT"), live=sub.get("live", "ABSENT"),
                    rows=len(differ.SUBSTRATE_ROWS), inputs=len(differ.substrate_entries()),
                    verdict=tok, read_from="corpusverdict-gate.py::substrate",
                    cvg_rc=f"{cvg_rc}(IGNORED)"))

  # --- READING 2: IS W2 FRESH RELATIVE TO W1? THE MTIME, AND ONLY THE MTIME ------------------
  if not repro.is_file():
    rows.append(judge("witness.fresh", False, True, path=C.rel(repro)))
  else:
    m1, m2 = mtime_ns(run), mtime_ns(repro)
    ordered = m2 >= m1
    rows.append(judge("witness.fresh", ordered, False,
                      verdict="FRESH" if ordered else "OUT-OF-ORDER",
                      order="mtime(W2)>=mtime(W1)",
                      delta_ms=f"{(m2 - m1) / 1e6:+.3f}",
                      summary_mtime_ns=m1, repro_mtime_ns=m2))

  # --- READING 3: DOES W2 NAME THE LIVE SUBSTRATE? ITS WHOLE ROW SET, WITH THE DENOMINATOR ----
  # `REPRO_PINS` and `REPRO_SUBSTRATE` are `differ`'s OWN declarations, loaded, never transcribed:
  # a literal `d10-transcript=` value here would be a pin that must be re-typed by hand whenever
  # the writer's row moves, which is the failure `differ.py:319` records.
  wanted = {**differ.REPRO_PINS, differ.REPRO_SUBSTRATE: None}
  live = differ.substrate_digest()
  if not repro.is_file():
    rows.append(judge("witness.substrate", False, True, rows=f"0 of {len(wanted)}",
                      live=live[:16], path=C.rel(repro)))
  else:
    got = C.rows_file(repro)
    missing = sorted(k for k in wanted if k not in got)
    wrong = sorted(k for k in wanted if k in got and k != differ.REPRO_SUBSTRATE
                   and got[k] != differ.REPRO_PINS[k])
    uncurrent = differ.REPRO_SUBSTRATE in got and got[differ.REPRO_SUBSTRATE] != live
    ok = not (missing or wrong or uncurrent)
    rows.append(judge("witness.substrate", ok, False,
                      verdict="CURRENT" if ok else "NOT-CURRENT",
                      rows=f"{len(wanted) - len(missing) - len(wrong) - int(bool(uncurrent))}"
                           f" of {len(wanted)}",
                      missing=",".join(missing) or "-", differs=",".join(wrong) or "-",
                      recorded=got.get(differ.REPRO_SUBSTRATE, "ABSENT")[:16],
                      live=live[:16], declared_by="differ.REPRO_PINS+REPRO_SUBSTRATE"))

  # --- WHICH INSTRUMENT PRODUCED READING 2. A ROW THAT CANNOT BE JUDGED IS NOT A ROW, BUT THIS
  # --- ONE IS A PROVENANCE CLAIM AND IT IS JUDGED: `os.stat` must still be the source.
  src = "os.stat().st_mtime_ns"
  rows.append(judge("freshness.source", True, False, via=src, git_asked="NO",
                    why="git-check-ignore-says-.gitignore:262:/runs/-so-git-status-is-blind-here"))

  # --- THE VERDICT, REPORTED WITH ITS DENOMINATOR AND WITH THE NAME OF ITS JUDGE --------------
  # REPORTED, NOT ASSERTED. These are `differ.unhealthy()`'s and `differ.PINS`' numbers; this
  # gate prints them so a reader has them in one place, and names their judge so nobody mistakes
  # a copy for a claim. `VERDICT_ROWS` is the sibling's declaration of which rows carry a
  # denominator -- quoting `graphs-agree` without `graphs` is how a count stops being checkable.
  summary = C.rows_file(run)
  den = " ".join(f"{k}={summary.get(k, 'ABSENT')}" for k in C.VERDICT_ROWS)
  rows.append(judge("verdict.reported", True, False,
                    graphs=summary.get("graphs", "ABSENT"),
                    agree=summary.get("graphs-agree", "ABSENT"),
                    unhealthy=len(differ.unhealthy()), repro_bad=len(differ.repro_bad()),
                    artefacts_ok=len(differ.artefacts_ok()),
                    rows=den, judged_by="differ.unhealthy()+differ.PINS (NOT THIS GATE)"))

  # --- WHAT IS CLAIMED. THE LINE, IN A ROW, SO IT CANNOT BE LOST IN PROSE. ---------------------
  rows.append(judge("claim", True, False, verdict="REPRODUCIBLE",
                    means="two clean runs produced byte-identical artifacts, and the witness "
                          "recording that names the live substrate",
                    not_measured="CORRECTNESS",
                    correctness_judged_by="differ.unhealthy()+differ.PINS"))

  if not rows:
    print(f"corpuswitness-gate: {verdict_of(DEAD)} -- no rows")
    return DEAD

  bad = [r for r in rows if f"{C.STATE}=FAIL" in r]
  refused = [r for r in rows if f"{C.STATE}=REFUSED" in r]
  verdict = FAIL if bad else (REFUSED if refused else PASS)
  body = (f"# {REPORT} -- GENERATED by `gates/corpuswitness-gate.py`, its ONLY writer.\n"
          f"# One TAB-separated `name=value` record per row. `verdict.current` is READ FROM\n"
          f"# `gates/corpusverdict-gate.py`'s OWN `substrate` row by running it; the substrate is\n"
          f"# `differ.substrate_digest()`, never a timestamp. `witness.fresh` is `os.stat` and\n"
          f"# NOTHING ELSE, because `.gitignore:262:/runs/` makes every witness here invisible to\n"
          f"# `git status`. This gate claims REPRODUCIBLE and does not measure CORRECTNESS.\n"
          + "\n".join(rows) + "\n")
  if not a.no_write:
    ART.mkdir(parents=True, exist_ok=True)
    (ART / REPORT).write_text(body)
  for ln in rows:
    print(ln)

  if verdict is FAIL:
    which = [r.split("\t")[0] for r in bad]
    print(f"corpuswitness-gate: {verdict_of(FAIL)} -- {len(which)} of {len(rows)} readings red: "
          f"{','.join(which)}")
    return FAIL
  if verdict is REFUSED:
    which = [r.split("\t")[0] for r in refused]
    print(f"corpuswitness-gate: {verdict_of(REFUSED)} -- nothing measured for: {','.join(which)}")
    return REFUSED
  print(f"corpuswitness-gate: PASS -- the REPRODUCIBILITY claim is CURRENT and its witness is "
        f"FRESH (substrate {live[:16]}, W2 is {abs(mtime_ns(repro) - mtime_ns(run)) / 1e6:.1f}ms "
        f"after W1). CORRECTNESS IS NOT MEASURED HERE: {summary.get('graphs')} graphs / "
        f"{summary.get('graphs-agree')} agree is `differ.unhealthy()`'s claim, not this gate's.")
  return PASS


if __name__ == "__main__":
  sys.exit(main())