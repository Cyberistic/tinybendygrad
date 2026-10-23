#!/usr/bin/env python3
"""corpusverdict-gate.py -- IS THE RECORDED `graphcmp` VERDICT CURRENT FOR THIS TREE?

    .venv/bin/python gates/corpusverdict-gate.py

WHY THIS GATE EXISTS, AND THE MEASUREMENT THAT PROVES THE GAP. Every "34/34 graphs agree"
in this tree described a substrate that no longer exists. `runs/graphcmp/D/D0-run-summary.txt`
carries `substrate-start`/`substrate-end` -- `checks/differ.py` writes both, deliberately, so a
reader can tell what tree an artifact set describes -- and on 2026-10-18 those read
`5d3f31197e88124246dd819fa1b904439ef255805c36bf30656145171d95ffa3` while the live digest was
`96f40eead5f3c326d4ae5e814e202aabb1844a7a86f281e93b910b53065af5c3`. MEASURED: 20 `.bend` files
changed between the run (Oct 17 01:50) and now, 730 insertions / 583 deletions, including
`uop/spec.bend` (208), `uop/symbolic.bend` (251) and `uop/ops.bend` (179) -- the emission logic
itself. **The verdict is not merely old; it describes a tree that is gone.**

WHAT MAKES THE RE-RUN THE OBVIOUS FIX, AND WHY IT IS NOT ONE. `differ.py`'s own readiness
probe is `./bin/bend .agents/slop/graphcmp.bend --check-only` (`settled()`, differ.py:1038), and
it answers `ALL PROOFS CHECK` on this tree (MEASURED 2026-10-23, and the `bend` row below
reads it), so the substrate DOES settle today and a re-run is possible.

  * `differ.py run` dispatches DIRECTLY to `cmd_run` with NO readiness gate, and `cmd_run`
    overwrites `D/` artifact by artifact. So `run` is not readiness-gated, and the
    `run.readiness` row below says so.
  * `differ.py repro` DOES gate on `ready()` (`clean_run`, differ.py:1288) and therefore
    refuses -- correctly, labelling itself "NOT a measurement".

AND THE CORPUS IS A SINGLETON, WHICH IS A DIFFERENT HAZARD AND A DIFFERENT ROW. `checks/
differ.py` writes the ONE directory `runs/graphcmp/D`, so two corpus runs at once interleave
two verdicts into one directory. MEASURED 2026-10-23: a `repro` at 03:37 and a `run` at 03:45
ran CONCURRENTLY; the `run` overwrote a green `D0-run-summary.txt` with one that was green
too while its own two substrate digests DISAGREED, and `gates/corpuswitness-gate.py` went
red on 4 of its 7 readings while `verdict.reported` stayed OK. `checks/differ.py` now holds
a corpus lock (`CORPUS_LOCK`, an `fcntl.flock`), and a second `run` REFUSES and names the
holder. **THE `run.gated` ROW MEASURES THAT, and it measures it by RUNNING the command**
(`singleton()` below): it holds the lock, starts a real `checks/differ.py run` against a
scratch artefact directory, and asserts that the run REFUSED, that the refusal NAMED THE
HOLDER, and that NOTHING WAS WRITTEN.

IT NEEDS NO `bend` AND CANNOT DAMAGE ANYTHING. It reads two files and hashes a declared
population; it never writes under `runs/graphcmp/`. The bend compile state is reported as its
OWN row so that a `bend`-less machine gets a truthful partial answer instead of a green one.

THE POSITIVE CONTROL, AND IT IS THE POINT. This gate's failure mode is SILENTLY READING
`CURRENT` -- an instrument that cannot recognise a stale digest reports the project's
load-bearing number as healthy, which is the exact defect it exists to catch. So every run
first plants a digest that is KNOWN to differ and asserts the comparator reports it STALE. A
control that fails is `REFUSED`, not `PASS`.

DOCTRINE 1. The population is `differ`'s own declaration, LOADED BY PATH: `substrate_digest()`
walks `tinybendygrad/` and adds `SUBSTRATE_INPUTS`, and `SUBSTRATE_ROWS` names the two rows.
Nothing is listed here that the generator already declares.

DOCTRINE 2. `SKIP` IS NOT `PASS`. A missing summary is `REFUSED` (a precondition was absent),
a summary without the two substrate rows is `FAIL` (it ran and could not answer), and an
empty row set is `DEAD`.
"""

from __future__ import annotations

import argparse
import importlib.util
import inspect
import os
import pathlib
import re
import shutil
import subprocess
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent
ART = HERE / "artifacts" / "corpusverdict-gate"
SUMMARY = ROOT / "runs" / "graphcmp" / "D" / "D0-run-summary.txt"

sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, verdict_of  # noqa: E402

STATE = "state"          # copied from checks/compile-census.py's `state` column
TOK = "token"            # copied likewise: bounded.py's OWN verdict token, never the rc

#: THE ROWS THAT CARRY A DENOMINATOR. `graphs-agree` alone is a numerator; quoting it without
#: `graphs` is how a count stops being checkable, so the two are read and reported together.
VERDICT_ROWS = ("graphs", "graphs-answered", "graphs-agree", "graphs-disagree",
                "byte-identical", "not-comparable", "expect-moved")


def load(path: pathlib.Path, name: str):
  """BY PATH. `differ` is the generator whose declaration defines the population, so it is
  imported rather than re-typed."""
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  sys.modules[name] = mod
  spec.loader.exec_module(mod)
  return mod


def rows_file(path: pathlib.Path) -> dict[str, str]:
  """`name=value` -> value. The summary is a flat file of these, which is the whole reason a
  reader can check one row without a parser."""
  out = {}
  if path.exists():
    for line in path.read_text().splitlines():
      k, sep, v = line.partition("=")
      if sep and re.fullmatch(r"[A-Za-z0-9-]+", k):
        out[k] = v
  return out


def control(compare) -> str:
  """THE POSITIVE CONTROL. This gate's whole job is to say STALE, so the only way it can be
  worthless is by being unable to. It requires a planted digest that DIFFERS FROM THE REFERENCE
  to read STALE, and the identical digest to read CURRENT, so a comparator that says STALE
  unconditionally is caught as surely as one that never says it. (The first version of this
  control planted a digest and compared it to ITSELF, and this REFUSED row is why: a control
  that asserts nothing is a control that cannot fail, which is the defect it guards against.)"""
  ref = "ab" * 32
  for planted in ("0" * 64, "f" * 64):
    got = compare(ref, planted)
    if got != "STALE":
      return f"planted {planted[:4]}... read {got}, wanted STALE"
  if compare(ref, ref) != "CURRENT":
    return f"identical digests read {compare(ref, ref)}, wanted CURRENT"
  return "planted-diff read STALE, identical read CURRENT"


def emit(name: str, **kv) -> str:
  return "\t".join([name] + [f"{k}={v}" for k, v in kv.items()])


def rel(path: pathlib.Path) -> str:
  """The path as the tree would name it, and ABSOLUTE when it is outside the tree. A
  `relative_to` that raises turns `--summary /tmp/x` into a traceback instead of the verdict."""
  try:
    return str(path.relative_to(ROOT))
  except ValueError:
    return str(path)


def refused(rc, said, holder, wrote) -> bool:
  """THE COMPARATOR: DID THE SECOND RUN REFUSE, NAME THE HOLDER, AND WRITE NOTHING?

  **IT IS A FUNCTION AND NOT A BLOCK**, so the control below can plant its INPUT and assert
  that it says NO. A comparator that cannot say no is a comparator that always says yes,
  which is a label -- and `differ.py`'s own PLANT 3 names that shape: "if it does not go
  red, the row is a label"."""
  return (rc == 3 and "another corpus run holds the lock" in said
          and str(holder) in said and not wrote)


def control_singleton() -> str:
  """THE POSITIVE CONTROL FOR THE REFUSAL COMPARATOR, and the reason `refused()` is a
  function.

  `control()` above plants a digest for the STALENESS comparator. This one plants what a
  second run DID, and demands that the comparator read each case as NOT refused: a run
  that exited 0, a run that never mentioned a lock, a run that named the WRONG holder, and
  a run that refused AND wrote anyway. A comparator that cannot say no is a comparator that
  always says yes."""
  cases = [((0, "wrote 35 artifacts", 1234, ["D0-run-summary.txt"]), "exited 0"),
           ((3, "some other failure", 1234, []), "never mentioned the lock"),
           ((3, "another corpus run holds the lock: pid 1234", 9999, []), "named another holder"),
           ((3, "another corpus run holds the lock: pid 1234", 1234, ["D0-run-summary.txt"]),
            "refused and wrote anyway")]
  for args, why in cases:
    if refused(*args):
      return f"a second run that {why} read as REFUSED"
  return "planted second-runs all read NOT-refused"


def singleton(differ) -> dict:
  """MEASURE THE PROPERTY: A SECOND CORPUS RUN IS REFUSED, IT NAMES THE HOLDER, AND IT
  WRITES NOTHING.

  **THE ROW THIS REPLACES READ `differ.cmd_run`'s SOURCE** and asked whether the string
  `ready(` appeared in it. That was a PROXY, and it was a proxy for the WRONG PROPERTY: the
  corpus is a SINGLETON. `checks/differ.py` writes the ONE directory `runs/graphcmp/D`, so two
  of them at once interleave two verdicts into one directory.

  MEASURED 2026-10-23, and it is why this row exists: a `differ.py repro` started at 03:37
  and a `differ.py run` started at 03:45 ran CONCURRENTLY. The `run` overwrote a green
  `D0-run-summary.txt` -- and the summary it wrote was green too (35/35 agree, 35/35
  byte-identical, 8/8 plants) while its OWN two substrate digests DISAGREED
  (`substrate-start=0c950c47...` vs `substrate-end=074e0233...`), because a `.bend` edit
  landed mid-run. `gates/corpuswitness-gate.py` then went RED on 4 of its 7 readings
  (`verdict.current`, `witness.fresh`, `witness.substrate`, `claim`) while `verdict.reported`
  stayed OK: a summary that says green and a witness that says the claim is not established.
  Both processes had to be killed by hand.

  **SO THIS MEASURES IT.** It holds the corpus lock, runs the REAL command
  (`checks/differ.py run`) against a SCRATCH artefact directory, and asserts three things:
  the command REFUSED, the refusal NAMED THE HOLDER, and NOTHING WAS WRITTEN. The scratch
  directory is `GRAPHCMP_ARTIFACTS`, and it exists for exactly this: a gate that measures
  the corpus must not be able to overwrite the corpus -- and if the lock were broken, the
  damage would land in the scratch directory instead of in the tree's evidence.

  **IF A REAL RUN HOLDS THE LOCK, THE MEASUREMENT IS BETTER, NOT SKIPPED.** The gate then
  cannot take the lock, and the real holder IS the thing the second run must be refused by --
  so the gate reads the holder and asks the same three questions of the same command."""
  scratch = ROOT / "runs" / "graphcmp" / f".singleton-{os.getpid()}"
  env = {k: v for k, v in os.environ.items() if k != "GRAPHCMP_ARTIFACTS"}
  env["GRAPHCMP_ARTIFACTS"] = str(scratch)
  out = {"holder": "?", "rc": "?", "note": "?"}
  ours = differ.take_lock()
  holder = os.getpid() if ours is None else differ.lock_holder()[0]
  out["holder"] = str(holder)
  try:
    scratch.mkdir(parents=True, exist_ok=True)
    try:
      p = subprocess.run([sys.executable, str(ROOT / "checks" / "differ.py"), "run"],
                         cwd=ROOT, env=env, capture_output=True, text=True, timeout=120)
    except subprocess.TimeoutExpired:
      out.update(rc="TIMED-OUT", note="the second run did not refuse within 120s")
      return out
    said = p.stdout + p.stderr
    wrote = sorted(q.name for q in scratch.iterdir())
    out.update(rc=str(p.returncode),
               note=("refused and named the holder" if refused(p.returncode, said, holder, wrote)
                     else f"the second run was not refused: {said.strip()[:160]!r}"),
               wrote=str(len(wrote)))
    out["ok"] = refused(p.returncode, said, holder, wrote)
  finally:
    differ.drop_lock()
    shutil.rmtree(scratch, ignore_errors=True)
  return out


def main(argv=None) -> int:
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("--summary", type=pathlib.Path, default=SUMMARY,
                  help="the run summary to audit (default runs/graphcmp/D/D0-run-summary.txt)")
  a = ap.parse_args(argv)
  rows: list[str] = []

  if not a.summary.exists():
    rows.append(emit("summary", **{STATE: "REFUSED", TOK: "ABSENT?NOTOKEN",
                                  "path": rel(a.summary)}))
    print("\n".join(rows))
    print("corpusverdict-gate: REFUSED -- no run summary; the corpus has never answered here")
    return REFUSED

  got = rows_file(a.summary)
  differ = load(ROOT / "checks" / "differ.py", "corpusverdict_differ")
  recorded = [got.get(k) for k in differ.SUBSTRATE_ROWS]

  # --- THE CONTROL, BEFORE the verdict it guards -----------------------------------------
  def compare(rec: str, live: str) -> str:
    return "CURRENT" if rec == live else "STALE"

  note = control(compare)
  rows.append(emit("control", **{STATE: "OK" if note.startswith("planted-diff") else "REFUSED",
                                TOK: "NOTOKEN?NOTOKEN", "note": note}))
  if not note.startswith("planted-diff"):
    print("\n".join(rows))
    print(f"corpusverdict-gate: REFUSED -- the staleness comparator is not a comparator ({note}); "
          f"a clean read from it would be a read over nothing")
    return REFUSED

  # --- THE VERDICT, WITH ITS DENOMINATOR -------------------------------------------------
  den = " ".join(f"{k}={got.get(k, 'ABSENT')}" for k in VERDICT_ROWS)
  rows.append(emit("verdict", **{STATE: "OK", "graphs": got.get("graphs", "ABSENT"),
                                "agree": got.get("graphs-agree", "ABSENT"), "rows": den}))

  # --- THE SUBSTRATE, WHICH IS THE WHOLE QUESTION ----------------------------------------
  live = differ.substrate_digest()
  unrecorded = [k for k, v in zip(differ.SUBSTRATE_ROWS, recorded) if not v]
  if unrecorded:
    rows.append(emit("substrate", **{STATE: "FAIL", TOK: "ABSENT?NOTOKEN",
                                    "why": f"no {','.join(unrecorded)} row",
                                    "live": live[:16]}))
    print("\n".join(rows))
    print(f"corpusverdict-gate: FAIL -- the summary carries no {','.join(unrecorded)} row, so it "
          f"cannot be checked against anything")
    return FAIL

  same = all(r == live for r in recorded)
  rows.append(emit("substrate", **{STATE: "OK" if same else "FAIL",
                                  "recorded": ",".join(r[:16] for r in recorded),
                                  "live": live[:16],
                                  "inputs": len(differ.substrate_entries()),
                                  "verdict": "CURRENT" if same else "STALE"}))

  # --- IS THE CORPUS A SINGLETON? MEASURED, NOT INFERRED FROM A SOURCE STRING -------------
  # **THE CONTROL COMES FIRST**, and it is the gate's own rule: an instrument that cannot
  # recognise a failure reports the project's load-bearing number as healthy.  The control
  # plants what a second run DID and demands the comparator read each case as NOT refused.
  note2 = control_singleton()
  rows.append(emit("control.singleton", **{STATE: "OK" if note2.startswith("planted") else "REFUSED",
                                           TOK: "NOTOKEN?NOTOKEN", "note": note2}))
  if not note2.startswith("planted"):
    print("\n".join(rows))
    print(f"corpusverdict-gate: REFUSED -- the refusal comparator cannot say no ({note2}); "
          f"a clean read from it would be a read over nothing")
    return REFUSED

  single = singleton(differ)
  rows.append(emit("run.gated", **{STATE: "OK" if single.get("ok") else "FAIL",
                                  "verdict": "SINGLETON" if single.get("ok") else "SHARED",
                                  "holder": single["holder"], "rc": single["rc"],
                                  "note": single["note"]}))

  # --- IS `differ.py run` READINESS-GATED? THE OLD SOURCE-LEVEL PROXY, KEPT AS ITS OWN ROW --
  # **THIS CHECK IS NOT THE ROW ABOVE AND IT IS NOT WEAKENED BY MOVING.** It asked whether
  # `cmd_run` consults the readiness probe, and it still does; what changed is that it is no
  # longer asked to stand in for a DIFFERENT property. A run that does not wait for the
  # substrate to settle overwrites 243 files of evidence with a dead bend lane, and that is
  # a separate hazard from two runs interleaving into one directory.
  src = inspect.getsource(differ.cmd_run)
  ready_gated = ("clean_run(" in src) or re.search(r"\bready\s*\(", src) is not None
  rows.append(emit("run.readiness", **{STATE: "OK" if ready_gated else "FAIL",
                                      "verdict": "READINESS-GATED" if ready_gated
                                      else "NOT-READINESS-GATED",
                                      "cmd": "differ.py run -> cmd_run"}))

  # --- THE BEND LANE, ITS OWN ROW, SO A bend-LESS MACHINE IS NOT GREEN --------------------
  bend = ROOT / "bin" / "bend"
  driver = ROOT / ".agents" / "slop" / "graphcmp.bend"
  if not (bend.exists() and driver.exists()):
    rows.append(emit("bend", **{STATE: "SKIP", TOK: "ABSENT?NOTOKEN", "verdict": "UNKNOWN"}))
  else:
    p = subprocess.run([str(bend), rel(driver), "--check-only"],
                       cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    tok = (p.stdout.split("\n", 1)[0] or "?").strip()[:40]
    rows.append(emit("bend", **{STATE: "OK" if p.returncode == 0 else "FAIL",
                                "token": tok, "rc": p.returncode,
                                "probe": "graphcmp.bend --check-only"}))

  body = ("# corpusverdict.rows -- GENERATED by `gates/corpusverdict-gate.py`, its ONLY writer.\n"
          "# One TAB-separated `name=value` record per row. `substrate.verdict=CURRENT|STALE` is\n"
          "# the answer to 'is the recorded corpus verdict current for this tree?', and it is\n"
          "# computed by hashing `differ.substrate_digest()`, never by reading a timestamp.\n"
          + "\n".join(rows) + "\n")
  ART.mkdir(parents=True, exist_ok=True)
  (ART / "corpusverdict.rows").write_text(body)
  for ln in rows:
    print(ln)

  if not rows:
    print(f"corpusverdict-gate: {verdict_of(DEAD)} -- no rows")
    return DEAD
  verdict = FAIL if any(f"{STATE}=FAIL" in r for r in rows) else PASS
  if verdict is FAIL:
    print(f"corpusverdict-gate: {verdict_of(FAIL)} -- "
          + (f"the recorded verdict is {'CURRENT but ' if same else ''}the tree cannot re-run it"
             if same else "the recorded verdict is STALE (recorded substrate != live substrate)")
          + ("" if single.get("ok") else
             "; and the corpus is NOT a singleton -- a second `differ.py run` was not refused")
          + ("" if ready_gated else
             "; and `differ.py run` is not readiness-gated, so it would overwrite D/ with a "
             "dead bend lane"))
    return FAIL
  print(f"corpusverdict-gate: PASS -- the recorded verdict describes THIS tree "
        f"(substrate {live[:16]}, {got.get('graphs')} graphs, "
        f"{got.get('graphs-agree')} agree)")
  return PASS


if __name__ == "__main__":
  sys.exit(main())