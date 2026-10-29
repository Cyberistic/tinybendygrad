#!/usr/bin/env python3
r"""corpuswitness-gate.py -- IS THE RECORDED `graphcmp` VERDICT CURRENT *AND REPRODUCIBLE*?

    .venv/bin/python gates/corpuswitness-gate.py

TWO WITNESSES, TWO QUESTIONS, AND THE SECOND ONE HAD NO INSTRUMENT.

    W1  runs/graphcmp/D/D0-run-summary.txt   34/34 graphs. `repro_bad()`'s own docstring says
                                             the pins are "ONE run's seventeen rows and the
                                             denominator of 'this run is healthy' is **1
                                             artifact**, not 17" (`differ.py:1400`).
    W2  runs/graphcmp/D/D0-repro.txt         WRITTEN BY `checks/differ.py`'s `cmd_repro` --
                                             "the tree's only INDEPENDENT measurement"
                                             (`differ.py:1403`).  (The function is the
                                             PRODUCER, not the file's content: the artifact
                                             carries `repro-files`/`repro-identical`/
                                             `repro-rc`/`repro-substrate` rows.)

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
non-zero today: its `run.readiness` row is FAIL because `cmd_run` has no readiness gate, which is
a TRUE reading and not this gate's business. Its `substrate` row reads `CURRENT` and its `bend`
row reads `rc=0` at the same moment. A gate that inherited that rc would red a fresh witness for
an unrelated reason -- a wrong reason, which is worse than none.

**AND THE ROW THAT REDS MOVED, AND THIS FILE DID NOT MOVE WITH IT.** `corpusverdict-gate.py`
used to ask, of `differ.cmd_run`'s SOURCE, whether `run` was gated, and to answer that question
in a row called `run.gated`. The corpus is now a real SINGLETON -- it holds an `flock` and a second
run is REFUSED -- and that property is MEASURED by RUNNING the command, in a row that kept the
name `run.gated`. The old source-level question was not dropped: it is now the row
`run.readiness`, and it is still red, because a run that does not wait for the substrate to settle
is a DIFFERENT hazard from two runs interleaving into one directory. **⇒ A DOCSTRING THAT NAMES A
ROW IS A CITATION, AND A CITATION THAT NAMES A ROW MUST MOVE WHEN THE ROW MOVES.**

DOCTRINE 2 -- `SKIP` IS NOT `PASS`, AND A ROW THAT CANNOT BE JUDGED IS NOT EMITTED. An absent
witness is `REFUSED` (a precondition was absent -- the measurement was never taken), a value that
differs is `FAIL` (it ran and got the wrong answer), `FAIL` outranks `REFUSED`, and a gate that
emitted no rows at all is `DEAD`. The comparators are `corpusverdict-gate.py:control()`'s
subject, so this gate cannot report a verdict from a comparator that cannot say `STALE`.

WHAT THIS GATE CLAIMS, AND WHERE THE LINE IS -- AND WHY THE `claim` ROW IS A DERIVATION. **"THE
VERDICT REPRODUCES" IS NOT "THE VERDICT IS CORRECT".** This gate claims exactly the first: two clean
runs produced a byte-identical artifact set, and the witness recording that describes the substrate
that is live now. It **CANNOT SEE CORRECTNESS GO MISSING**, and this tree has already paid for
that once -- `REPRO_PINS`' `d10-transcript` is pinned *because* `repro-rc=rc=0` says nothing about
D10 being right: "a `classify` that regressed to retrying would write `bend attempt 2` in BOTH
runs, so both would AGREE and both checks would pass over a wrong transcript"
(`differ.py:316-321`). Byte-comparing two runs cannot separate "34 graphs agree with CPython"
from "34 graphs agree with CPython identically wrong twice". That claim belongs to
`differ.unhealthy()` and `differ.PINS`; this gate REPORTS the numbers WITH their denominator
while NAMING that judge, rather than restating the verdict as its own. The `claim` row says which
of the two it is, and the PASS line says `REPRODUCIBLE`, never `correct`.

THE `claim` ROW WAS A LITERAL, AND THAT WAS THE DEFECT THIS FILE WAS FOUND WITH.
`judge("claim", True, False, verdict="REPRODUCIBLE")` puts the word in the row BY HAND, so a
witness saying `repro-rc=rc=0` and a witness saying `rc=1` produced a **BYTE-IDENTICAL** `claim`
row: a row that CANNOT GO RED, and `differ.py`'s own PLANT 3 names that shape ("if it does not go
red, the row is a label"). **A HEADLINE THAT CANNOT GO RED IS THE WORST SHAPE A GATE HAS, BECAUSE
IT IS THE ONE ROW EVERYBODY READS.** `witness.substrate` beside it DOES discriminate -- it compares
`repro-rc` against `differ.REPRO_PINS["repro-rc"]` -- so the gate was HALF RIGHT AND HALF FAKE, and
the fake half was the headline.

THE THIRD WAY, AND WHY (a) AND (b) ARE THE SAME THING HERE. The row must report another
instrument's verdict without hardcoding it and without re-deriving it, so there are three
candidate shapes: (a) READ the witness's own row; (b) DERIVE the row from a value the witness
already produces; (c) DROP the row and let the witness's own verdict BE the gate's.
**(a) AND (b) ARE ONE OPERATION IN THIS GATE, AND THE REASON IS THAT THE GATE ALREADY READS THE
WITNESS's OWN ROW.** `witness.substrate` reads `repro-rc` out of `D0-repro.txt` and compares it to
`differ.REPRO_PINS["repro-rc"]` -- the GENERATOR's own declared pin, loaded by path. So "read the
witness's own row" and "derive from a value the witness produces" are the same operation, and it
has ALREADY BEEN DONE, once, in the row that owns it. **A `claim` ROW THAT READ `repro-rc` AGAIN
WOULD BE A SECOND JUDGEMENT OF THE SAME VALUE**, which is the "second comparison implementation"
this file's own header names as the reason a reading is not restated here. **(c) IS WORSE THAN
BOTH, AND ITS COST IS THE PROSE IT WOULD DELETE:** the `claim` row is the only place this gate
says WHAT IT DOES NOT CLAIM (`not_measured=CORRECTNESS`), and an absence is recoverable where a
confident false claim is not.

SO THE ROW IS A DERIVATION -- AND NOT OF THE WITNESS's VERDICT. **THE CLAIM IS THE CONJUNCTION**:
`verdict.current` (the recorded verdict describes THIS tree), `witness.substrate` (the
reproducibility witness holds and names this tree), `witness.fresh` (the witness was taken AFTER
the verdict it describes) and `freshness.source` (the clock that measured that ordering is the
one this gate declares). **`witness.fresh` IS THE CLOCK, AND NO OTHER INSTRUMENT IN THIS TREE
READS ONE** -- `checks/corpus-figure.py` has 0 `st_mtime` occurrences and `checks/differ.py` has 1,
and it is the sentence saying never to. **SO THE ROW IS NOT AN ECHO OF THE WITNESS: A WITNESS THAT
SAYS `rc=0` AND IS FOUR DAYS OLD STILL REDS THIS ROW.** That is the case
`gates/corpuswitness-plant.py`'s `C` plants and its `G` case measures.

NO WRITE UNDER `runs/`, AND NO `bend` OF THIS GATE's OWN. This gate opens two files for reading
and takes their timestamps; it writes only under `gates/artifacts/`. That is the contract
`gates/corpusverdict-gate.py` states for itself, and it is what lets the plant copy the witnesses
into a temporary directory and move their clocks there. **THE BEND PROCESS IS NOT ABSENT, IT IS
INHERITED, AND THE HEADER USED TO SAY IT WAS ABSENT.** Reading 1 means RUNNING the sibling, and
the sibling's own `bend` row probes `./bin/bend .agents/slop/graphcmp.bend --check-only`
(`corpusverdict-gate.py:196-206`). MEASURED 2026-10-20T18:02Z: that probe answers in 0.92 s, 0.99 s
and 1.67 s over three runs, and the whole gate answers in 1.25 s -- **so the gate's cost IS the
bend probe**, and the plant's 9 gate runs per suite are 9 bend probes. The gate reads that row's
verdict about the SUBSTRATE and ignores both that row and its rc; the process is the price of
running the instrument that owns the comparison.
"""

from __future__ import annotations

import argparse
import contextlib
import io
import importlib.util
import inspect
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


#: THE READINGS THE `claim` ROW IS THE CONJUNCTION OF. NAMED, AND THE NAMES ARE THIS FILE's OWN
#: ROWS: a row of this gate that is not named here is not part of the claim. `control` is a
#: PRECONDITION on the comparator and not a reading of the tree; `freshness.source` is the
#: PROVENANCE of the clock, and it IS a conjunct because a reading taken with an instrument the
#: gate cannot name is not a measurement of anything.
CLAIM_CONJUNCTS = ("verdict.current", "witness.fresh", "freshness.source", "witness.substrate")


def judge_state(reading: str, state: str, **kv) -> str:
  """A row whose STATE IS ALREADY DECIDED -- for the row that DERIVES one from the rows above.

  `judge` takes a BOOLEAN and a boolean cannot carry a third state, and the derived row needs
  three: `FAIL` (a conjunct ran and got the wrong answer), `REFUSED` (a conjunct's precondition
  was absent, so it measured nothing) and `OK`."""
  return cvg().emit(reading, **{cvg().STATE: state, **kv})


def state_of(row: str) -> str:
  """THE `state=` FIELD OF A ROW THIS GATE EMITTED, read back out of the row itself.

  **THE DERIVATION IS OVER THE ROWS, NOT OVER A SECOND COPY OF THE MEASUREMENTS.** The row IS the
  measurement's record, so reading its state back is READING the measurement and not re-deriving
  it -- and the derived row cannot disagree with the rows above it, because it is built out of
  them. `ABSENT` is a value a row can hold and it is not `OK`: a reading that stopped emitting
  must not read as a reading that agreed."""
  for field in row.split("\t")[1:]:
    if field.startswith(cvg().STATE + "="):
      return field.split("=", 1)[1]
  return "ABSENT"


def judge(reading: str, ok: bool, absent: bool, **kv) -> str:
  """One reading, one row. `absent` is `REFUSED` and `not ok` is `FAIL`, and they are not the
  same claim: nothing was measured is not a wrong answer.

  **THERE IS NO `token=` FIELD AND THAT IS DELIBERATE.** `corpusverdict-gate.py` carries one
  because its `bend` row is `checks/bounded.py`'s verdict token and must not be confused with a
  gate's rc. No reading here is bounded.py's, so a `token` would have to be invented --
  `OK?OK` would look like a measured verdict token and name no instrument. Absent a field beats
  a fake one: an unread column is notice, a wrong one is a lie somebody quotes."""
  return judge_state(reading, "REFUSED" if absent else ("OK" if ok else "FAIL"), **kv)


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
  # (the `run.readiness` row, about `differ.py run` not being readiness-gated) that has nothing
  # to do with currency.
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

  # --- THE WITNESS's OWN ROWS, READ ONCE -------------------------------------------------------
  # `witness.substrate` JUDGES these rows and the `claim` row REPORTS the one the claim rests on.
  # Reading them twice would be a second parser of one file, and `witness.substrate` already
  # parses them with the sibling's own `rows_file`.
  got = C.rows_file(repro) if repro.is_file() else {}

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

  # --- WHICH INSTRUMENT PRODUCED READING 2, AND IT IS CHECKED RATHER THAN ASSERTED ------------
  # THE ROW USED TO SAY `judge("freshness.source", True, False, ...)` -- A LITERAL `True`, WHICH
  # IS THE SAME DEFECT THE `claim` ROW HAD: a row that cannot go red. The claim is that this
  # gate's only clock still reads the FILESYSTEM, and `inspect.getsource` is the sibling's own
  # instrument for a claim about an instrument's SOURCE (the sibling's `run.readiness` row asks
  # `differ.cmd_run`'s source whether `run` is readiness-gated), so the check is in house style.
  #
  # **THE DOCSTRING IS EXCLUDED ON PURPOSE.** These docstrings TALK ABOUT GIT -- the rule that
  # git is not asked is written down three times above -- so a check that grepped the whole
  # source would read the prose that explains the rule and report it as a violation of it. The
  # RETURN EXPRESSIONS are the code, and they are where the number comes from.
  clock_src = [ln.strip() for ln in inspect.getsource(mtime_ns).splitlines()
               if ln.strip().startswith("return ")]
  clock_ok = bool(clock_src) and all("os.stat" in r and "git" not in r for r in clock_src)
  rows.append(judge("freshness.source", clock_ok, False,
                    via="os.stat().st_mtime_ns", git_asked="NO",
                    why="git-check-ignore-says-.gitignore:262:/runs/-so-git-status-is-blind-here"))

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

  # --- THE REPORTED VERDICT, DERIVED FROM COUNTS THE WITNESS ALREADY WROTE -------------------
  # The state was the literal `True`, so a witness whose `repro-rc` said `rc=0` and whose
  # `repro-identical` said `0` produced the same `state=OK` as one whose counts agreed. `cmd_repro`
  # writes `repro-identical == repro-files` exactly when it writes `repro-rc=rc=0`. Those are
  # different rows of the same witness: the reported word against the verdict the counts entail.
  # OK only when they agree. A missing side is REFUSED (`NO-SUCH-ROW`), not OK -- an absence that
  # reads OK is the literal back again. Not `repro_bad()` (that compares `repro-rc` to a pin) and
  # not `claim` (claim does not read these two counts, so a coherent lie about them stays green
  # there). `VERDICT_ROWS` is still reported, with its denominator, and is not what the state is.
  summary = C.rows_file(run)
  den = " ".join(f"{k}={summary.get(k, 'ABSENT')}" for k in C.VERDICT_ROWS)
  reported = got.get("repro-rc")
  files, identical = got.get("repro-files"), got.get("repro-identical")
  countable = (files is not None and identical is not None
               and files.isdigit() and identical.isdigit())
  derived = ("rc=0" if files == identical else "rc=1") if countable else None
  report = {"graphs": summary.get("graphs", "ABSENT"),
            "agree": summary.get("graphs-agree", "ABSENT"), "rows": den}
  if reported is None or derived is None:
    rows.append(judge("verdict.reported", False, True,
                      reported=reported or "ABSENT", derived=derived or "NO-SUCH-ROW",
                      verdict="NO-SUCH-ROW", **report))
  else:
    cohere = reported == derived
    rows.append(judge("verdict.reported", cohere, False,
                      reported=reported, derived=derived,
                      verdict="AGREE" if cohere else "DISAGREE", **report))

  # --- WHAT IS CLAIMED. THE LINE, IN A ROW, SO IT CANNOT BE LOST IN PROSE. ---------------------
  # AND IT IS A DERIVATION, NOT A WORD. The row used to be `judge("claim", True, False,
  # verdict="REPRODUCIBLE")` -- a LITERAL, so a witness saying `repro-rc=rc=0` and one saying
  # `rc=1` produced a BYTE-IDENTICAL row, and `differ.py`'s own PLANT 3 names that shape: "if it
  # does not go red, the row is a label". **THE CLAIM IS THE CONJUNCTION OF THIS GATE's OWN
  # READINGS**, and one of the conjuncts is the CLOCK, which no other instrument in this tree
  # reads -- so this row is NOT an echo of the witness: a witness that says `rc=0` and is four
  # days old still reds it. See the header for why (a) and (b) are the same operation here.
  by_name = {r.split("\t")[0]: r for r in rows}
  cs = {n: state_of(by_name.get(n, "")) for n in CLAIM_CONJUNCTS}
  cstate = ("FAIL" if any(v == "FAIL" for v in cs.values())
            else "REFUSED" if any(v != "OK" for v in cs.values()) else "OK")
  cverdict = {"OK": "REPRODUCIBLE", "FAIL": "NOT-ESTABLISHED", "REFUSED": "NOT-MEASURED"}[cstate]
  rows.append(judge_state("claim", cstate, **{
    "verdict": cverdict,
    "conjuncts": ",".join(f"{n}:{cs[n]}" for n in CLAIM_CONJUNCTS),
    # THE WITNESS's OWN ROW, SPELLED AS THE WITNESS SPELLS IT -- a hyphen is not a keyword
    # argument's name, so this one field is passed through a dict. It is a REPORT of what the
    # witness recorded, not a second judgement of it: `witness.substrate` is where the pin on
    # this row is checked, against `differ.REPRO_PINS`.
    "repro-rc": got.get("repro-rc", "ABSENT"),
    "means": "the recorded verdict is CURRENT for this tree, the reproducibility witness holds "
             "and names this tree, and the witness was taken AFTER the verdict it describes",
    "not_measured": "CORRECTNESS",
    "correctness_judged_by": "differ.unhealthy()+differ.PINS"}))

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
          f"# `git status`. The `claim` row is the CONJUNCTION of the readings named in its\n"
          f"# `conjuncts` field -- it is DERIVED, and it can go red. `verdict.reported` derives\n"
          f"# `repro-rc` from `repro-files` and `repro-identical` and goes red when they disagree.\n"
          f"# This gate claims REPRODUCIBLE and does not measure CORRECTNESS.\n"
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
  print(f"corpuswitness-gate: PASS -- the claim is ESTABLISHED: the recorded verdict is CURRENT, "
        f"the reproducibility witness holds, and it was taken AFTER that verdict (substrate "
        f"{live[:16]}, W2 is {abs(mtime_ns(repro) - mtime_ns(run)) / 1e6:.1f}ms "
        f"after W1). CORRECTNESS IS NOT MEASURED HERE: {summary.get('graphs')} graphs / "
        f"{summary.get('graphs-agree')} agree is `differ.unhealthy()`'s claim, not this gate's.")
  return PASS


if __name__ == "__main__":
  sys.exit(main())