#!/usr/bin/env python3
"""nl-gate-noguard.py -- THE `nir_llvmir` GATE AS IT WAS, and the reason `nl-gate.py` exists.

    .venv/bin/python .agents/slop/eq/nl-gate-noguard.py [--port-stdout F] [--oracle-stdout F]

THIS FILE DELIBERATELY CONTAINS NO COVERAGE GUARD.  It is the value comparison alone: read both
lanes with `rebase-gate.py`'s own `rows()` (imported, never copied), print the two name COUNTS as
decoration, compare every shared name's answer, and print `AGREE` or `BROKEN`.

It is not dead code and it is not a straw man to be laughed at -- it is the CONTROL, and it has to
be a RUNNING detector rather than a stub, because a control run against itself is not a control.
It exists so the same captured bytes can be shown to give DIFFERENT VERDICTS under a gate that has
the guard and a gate that does not.  If both gates agreed, the guard would have proved nothing.

MEASURED, on this lane, pre-rename and with BOTH lanes captured: the `osx=` collapse put 4 of the
205 rows on keys that cannot be addressed, and this file reported

    gated 201   agree 201   disagree []
    AGREE

rc=0.  Four measurements were unreachable by any name, on both sides, under a green verdict.  That
is the entire failure `nl-gate.py`'s `reshape()` exists to make red.

⚠ THE LINE THAT IS BOTH THE POINT AND THE CRIME.  `orr - pr` names NO producer ever printed: it is
the residue of a name after `row()` cut it at the first `=`, so on the pre-rename bytes it is the
four MANUFACTURED keys `sd cpullvm {LLVM,x86_64,arm,riscv64} osx`.  Saying "only it finds" reports
a manufactured name as a found one, which inflates the denominator of everything computed from it.
Kept verbatim as the control's behaviour -- `nl-gate.py` prints the same two sets with the opposite
words ("MANUFACTURES out of a reshape, which NO producer printed") and puts them in `bad`, before
the value comparison runs.
"""
import argparse, hashlib, importlib.util, pathlib, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
# `parents[0]` IS the repo root, and the depth is PROVED by `refuse()` below, not assumed.
# `3f0e70ff1` MOVED this file from `.agents/slop/eq/` to `checks/`, ONE level shallower, and
# carried the constant across without recomputing it -- so `parents[2]` became
# `/Users/cyberistic/src`, which is where every `cwd=REPO` below pointed.  `checks/nl-gate.py`
# is this file's fixed TWIN and carries the identical guard; the two must not be able to drift,
# so they agree on the spelling.  Note the trap: `parents[1]` is ALSO wrong -- it is
# `/Users/cyberistic/src/tries`.
REPO = HERE.parents[0]
PORT = "tinybendygrad/renderer/nir_llvmir.bend"
ORACLE = [".agents/slop/nl/nl-oracle.py", "rows"]
SLOP = REPO / ".agents" / "slop"


def refuse(*why):
  """exit 3 = REFUSED, and NOT a verdict.  `checks/abi_gate.py` rule, in this file's idiom.

  Placed BEFORE the `rebase-gate` load below, because that load used to raise
  `FileNotFoundError` FIRST -- the reader was a SIBLING at `.agents/slop/eq/` -- and an
  assertion DOWNSTREAM of what it asserts cannot turn an exception into a refusal."""
  print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
  sys.exit(3)


# TWO TRACKED MARKERS, so a FURTHER relocation is a refusal rather than a traceback: the
# substrate this root claim rests on, then the two inputs this gate LOADS at import.
if not (REPO / "pyproject.toml").is_file() or not (REPO / "tinybendygrad").is_dir():
  refuse(f"REPO does not hold the tree: {REPO} is not the repo root "
         f"(is `parents[N]` stale after a move?)")
_SWEEP = ("  (swept by 371cc64c9; recoverable from git at 371cc64c9^:%s.  Restoring a swept"
          " instrument is not this file's call.)")
for _p, _at in ((SLOP / "rebase-gate.py", ".agents/slop/rebase-gate.py"),
                (REPO / ORACLE[0], ORACLE[0])):
  if not _p.is_file():
    refuse(f"input absent: {_p}" + _SWEEP % _at
           + "  This gate cannot produce a denominator without it.")

spec = importlib.util.spec_from_file_location("rebase-gate", str(SLOP / "rebase-gate.py"))
_rebase = importlib.util.module_from_spec(spec)
spec.loader.exec_module(_rebase)
rows_shipped = _rebase.rows


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--port-stdout")
  ap.add_argument("--oracle-stdout")
  a = ap.parse_args()
  # ⚠ AN ABSENT CAPTURE IS A REFUSAL, NOT A TRACEBACK.  `--port-stdout`/`--oracle-stdout` name
  # a FILE, and `pathlib.Path(...).read_text()` on an absent file raises `FileNotFoundError`,
  # which reaches a caller as exit **1** -- THE SAME EXIT AS A DISAGREEMENT.  MEASURED
  # 2026-10-29: `--port-stdout /nonexistent/file.rows` answered a `FileNotFoundError` traceback
  # and exit **1**, so "the capture I was told to read is not there" and "the port and the oracle
  # DISAGREE" were the same number to a reader of `$?`.  **THIS FILE'S OWN `refuse()` SAYS WHY
  # THAT IS WRONG**: "a gate that crashes where it should refuse cannot distinguish 'the input is
  # absent' from 'I am broken'", and `checks/abi_gate.py`'s rule is that a missing input is
  # REFUSED (3) and not a verdict at all.  So the read is CHECKED BEFORE it is taken, and the
  # check is AT THE READ SITE rather than at the top of `main()` -- because the module-scope
  # refusal above it is about the tree, and this one is about the two NAMED INPUTS.
  for _flag, _path in (("--port-stdout", a.port_stdout), ("--oracle-stdout", a.oracle_stdout)):
    if _path is not None and not pathlib.Path(_path).is_file():
      refuse(f"input absent: {_path} (named by {_flag})"
             + "  This gate cannot produce a denominator without it.")
  p = (pathlib.Path(a.port_stdout).read_text() if a.port_stdout
       else subprocess.run(["./bin/bend", PORT], cwd=REPO, capture_output=True,
                           text=True).stdout)
  o = (pathlib.Path(a.oracle_stdout).read_text() if a.oracle_stdout
       else subprocess.run([sys.executable] + ORACLE, cwd=REPO, capture_output=True,
                           text=True).stdout)
  pr, orr = rows_shipped(p), rows_shipped(o)
  print(f"port md5={hashlib.md5(p.encode()).hexdigest()[:8]}   "
        f"oracle md5={hashlib.md5(o.encode()).hexdigest()[:8]}   lanes BYTE-IDENTICAL: {p == o}")
  print(f"the SHARED reader (rebase-gate.py:rows()) over each lane: {len(pr)} names on the port, "
        f"{len(orr)} on the oracle -- {len(set(orr) - set(pr))} only it finds, "
        f"{len(set(pr) - set(orr))} only this reader finds, {len(set(pr) & set(orr))} in common")
  print(f"physical rows on stdout: port {len(p.splitlines())}, oracle {len(o.splitlines())}")
  agree, disagree = [], []
  for n in sorted(set(pr) & set(orr)):
    (agree if pr[n] == orr[n] else disagree).append(n)
  print(f"gated {len(agree) + len(disagree)}   agree {len(agree)}   disagree {disagree[:8]}")
  print("AGREE" if not disagree else "BROKEN")
  return 1 if disagree else 0


# THE VERDICT SURFACE, DECLARED. `gates/gate-surface.py` reads these by AST -- never by import,
# because import RUNS a gate.
#
# ⚠ THE PREVIOUS REVISION SAID "At rest this refuses on the swept oracle: `3` is the one reachable
# code", AND THAT WAS TRUE WHEN IT WAS WRITTEN AND IS FALSE NOW.  `.agents/slop/nl/nl-oracle.py`
# IS PRESENT (24 956 B, tracked), `.agents/slop/rebase-gate.py` IS PRESENT, so the module-scope
# refusal does NOT fire and argv reaches `main()`.  MEASURED 2026-10-29: bare argv exits **0**
# (AGREE over 205 gated rows) and `--port-stdout <a tracked lane>` exits **1** (BROKEN).
#
# ⇒ AND **BOTH PLANTS ARE HERMETIC**, AND THAT IS THE POINT.  `nl-gate.py`'s own header records
# that `tinybendygrad/uop/ops.bend` is in this port's 6-file import closure and is owned by
# another live unit: MEASURED, two consecutive captures printed 206 rows and then ZERO.  **A
# PLANT THAT READS THE LIVE PORT IS A PLANT THAT CAN ANSWER "NO ROWS" INSTEAD OF A VERDICT**,
# and this file's own subject is the CONTROL -- the detector that must keep running.
#
# `PLANTS[0]` IS THE AGREE PLANT: the gate's OWN tracked fixture on BOTH sides.
# `--port-stdout gates/cstyle-live.rows --oracle-stdout gates/cstyle-live.rows`.  MEASURED
# 2026-10-29: **rc 0**, `gated 227   agree 227   disagree []`, `AGREE`, in **0.2 s**, with NO
# `bend` and NO live port.  ⚠ AND THE GREEN IS NOT VACUOUS: the gate reads 227 names out of the
# file with `rebase-gate.py:rows()` and COMPARES 227 values -- it is a comparison that can fail,
# and the rc-1 plant below is the SAME comparison over two lanes that differ.
#
# `PLANTS[1]` IS THE BROKEN PLANT: the SAME tracked fixture against the lane it was captured
# against, `oracles/tinybendygrad_renderer_cstyle.bend.rows`.  MEASURED 2026-10-29: **rc 1**,
# `gated 181   agree 172   disagree ['tmap BASE', 'tmap CLANG', 'tmap CUDA', 'tmap METAL',
# 'tmap OPENCL', 'wmma 16_16_128 fp8', 'wmma 16_16_16 half', 'wmma 16_16_16 i8']`, `BROKEN`.  The
# 9 disagreements are the cstyle lane's `fp8e4m3` -> `float8_e4m3` dtype-NAME rename and its
# `wmma` rows -- **A REAL DISAGREEMENT BETWEEN TWO TRACKED LANES OF THIS TREE**, so the plant
# exercises the value comparison rather than a fabricated disagreement.
#
# `PLANTS[3]` IS THE REFUSAL PLANT, AND IT IS AN ARGV- REACHABLE ONE.  The refusal this gate
# used to carry was the MODULE-SCOPE one -- "input absent: .agents/slop/nl/nl-oracle.py" -- and it
# fired because the oracle was swept.  **THE ORACLE IS PRESENT** (24 956 B, tracked), so that
# refusal no longer fires and `PLANTS[3] = []` became a MISPLANT: bare argv answers 0, not 3.
# **A PLANT THAT NO LONGER REACHES ITS VERDICT IS A FALSE CLAIM.**  The refusal that IS reachable
# is this gate's OWN rule applied at the read site: `--port-stdout`/`--oracle-stdout` NAME an
# input, and an absent input is REFUSED (3) rather than a traceback.  MEASURED 2026-10-29:
# `--port-stdout /nonexistent/file.rows` answered a `FileNotFoundError` traceback and exit **1**
# -- the SAME EXIT AS A DISAGREEMENT, so "the capture is not there" and "the lanes DISAGREE" were
# one number to a reader of `$?` -- and, after the check, it answers
# `== REFUSED, NOT A VERDICT: input absent: /nonexistent/file.rows (named by --port-stdout)` and
# exit **3**.
EXIT_SURFACE = VERDICTS = {0: "AGREE", 1: "BROKEN", 3: "REFUSED"}  # VERDICTS: legacy alias of EXIT_SURFACE
PLANTS = {0: ["--port-stdout", "gates/cstyle-live.rows",
              "--oracle-stdout", "gates/cstyle-live.rows"],
          1: ["--port-stdout", "gates/cstyle-live.rows",
              "--oracle-stdout", "oracles/tinybendygrad_renderer_cstyle.bend.rows"],
          3: ["--port-stdout", "checks/absent-lane.rows"]}


if __name__ == "__main__":
  sys.exit(main())