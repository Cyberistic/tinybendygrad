#!/usr/bin/env python3
"""plant.py -- TWO GATES, TWO DEFECTS, PLANTED BOTH WAYS WITH THE NEGATIVE CELLS NAMED.

    .venv/bin/python .agents/slop/restoredinput/plant.py --rows > .agents/slop/restoredinput/plant.rows

THE SHAPE IS `.agents/slop/zerogate/plant.py`, READ AND NOT DUPLICATED: restore a swept input to
its own declared path, run the gate, then RE-READ what is on disk.  The difference is the payload:
`zerogate`'s is a temporary plant it deletes again, and this one's is a RESTORE, because these two
files are two gates' REQUIRED INPUTS and `AGENTS.md` puts a gate's input BESIDE THE GATE IN GIT.
So state 2 asserts the opposite of `zerogate`'s -- both swept paths PRESENT and byte-identical to
`PRE`, and the ONE WRONG PATH ABSENT -- and both halves are re-read from disk, not from a boolean
this file set earlier.

`bend` IS NEVER FORKED.  `checks/hermetic-census.py`'s only `0` runs `census()`, which calls
`isolate.emit(..., "bend")`, and `graphcmp.py:1949` `subprocess.run`s `bin/bend` -- so this plant
reaches `hermetic-census.py` ONLY through argv that stops in `argparse` (`--help`), which exercises
the WHOLE module scope including both refusals and every import, and stops before any graph.  That
limit is REPORTED, not hidden: hermetic-census's `0` and `3` stay UNPLANTED because planting them
needs a machine nobody here owns.
"""
from __future__ import annotations
import hashlib, pathlib, subprocess, sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[2]
PY = str(ROOT / ".venv" / "bin" / "python")
PRE = "371cc64c9^"          # the sweep that removed them; named by both gates' own refusal text

# THE SWEPT INPUTS, BY GATE: {path-under-ROOT: blob-path-at-PRE}.  The blob path is each gate's OWN
# claim, verbatim from its own refusal message -- not a path found by search, because a search finds
# the file's LAST home rather than the one the gate will look at.
SWEPT = {
  ".agents/slop/eq/eq-census2.py": ".agents/slop/eq/eq-census2.py",
  ".agents/slop/hermetic/isolate.py": ".agents/slop/hermetic/isolate.py",
}

# THE TWO PATH SHAPES `checks/hermetic-census.py:71` ACCEPTED, AND WHY THE SECOND IS A PLANT.
# `HERE` is `checks/`, so `checks/isolate.py` is one of the two names the gate's own existence test
# would have accepted -- and the gate would then have CRASHED at `isolate.py:36`, because
# `isolate.REPO = HERE.parents[2]` is stale one level shallower.  That is a cell with a DIFFERENT
# failure from the first, and a fix that only moves `sys.path` cannot see it, so it is measured.
HERMETIC_HOME = ".agents/slop/hermetic/isolate.py"
HERMETIC_ALT = "checks/isolate.py"


def blob(rel: str) -> bytes | None:
  r = subprocess.run(["git", "cat-file", "-p", f"{PRE}:{rel}"], cwd=ROOT, capture_output=True)
  return r.stdout if r.returncode == 0 else None


def present(paths) -> dict:
  return {p: (ROOT / p).is_file() for p in paths}


def sha(p) -> str:
  f = ROOT / p
  return hashlib.sha256(f.read_bytes()).hexdigest()[:12] if f.is_file() else "ABSENT"


TRACEBACK = "Traceback (most recent call last)"


def run(gate: str, argv) -> tuple[int, str, bool]:
  """(rc, verdict TOKEN or `-`, IS-A-CRASH).  A TIMEOUT is SKIP, never a verdict.

  The crash flag comes out of the SAME subprocess as the rc, never a second bare invocation: bare
  argv on `checks/hermetic-census.py` with its input restored runs the WHOLE census and forks
  `bend`, which is the one thing this file must not do.  The flag is also the one distinction a
  refusal must never blur, and the reason `.agents/slop/synonyms` measured that a genuine crash has
  to keep reading DEAD -- a traceback is in the OUTPUT, so it is decidable without the exit
  vocabulary at all."""
  try:
    r = subprocess.run([PY, f"checks/{gate}", *argv], cwd=ROOT, capture_output=True,
                       text=True, timeout=120)
  except subprocess.TimeoutExpired:
    return 4, "SKIP", False
  out = (r.stdout + r.stderr).strip()
  toks = [t for t in ("AGREE", "BROKEN", "AUDIT OK", "AUDIT FAILED", "SELFTEST OK",
                      "SELFTEST FAILED", "REFUSED", "PASS", "FAIL", "DEAD", "SKIP", "OK",
                      "GREEN", "RED") if t in out]
  return r.returncode, (" ".join(sorted(set(toks))) or "-"), TRACEBACK in out


def main(argv) -> int:
  rows = "--rows" in argv or argv == ["--rows"]
  out, fails = [], []

  def cell(state, gate, args, want_rc, want_token, label):
    rc, tok, crashed = run(gate, args)
    ok = rc == want_rc and not crashed
    out.append((state, gate, " ".join(args) or "(bare argv)", rc, tok, "YES" if ok else "NO", label))
    if not ok:
      fails.append(f"{state} {gate} [{' '.join(args) or 'bare'}] -> rc={rc} want {want_rc}"
                   + (" AND IT TRACEBACKED" if crashed else ""))
    return rc

  # ---- STATE 0: AT REST.  The tree as committed, both swept inputs ABSENT.  This is the reading
  # that makes every other row mean something, and it is the state the gates sit in today.
  for g, why in (("dup-gate.py", "eq-census2.py absent"), ("hermetic-census.py", "isolate.py absent")):
    rc, tok, crashed = run(g, [])
    ok = rc == 3 and not crashed
    out.append(("at rest (input absent)", g, "(bare argv)", rc, tok, "YES" if ok else "NO",
                f"REFUSED, no traceback: {why}"))
    if not ok:
      fails.append(f"at rest {g} rc={rc} crashed={crashed}, expected 3 and no traceback")

  already = present(SWEPT)
  if any(already.values()):
    print(f"REFUSED: a swept input I was told is absent is PRESENT -- another unit restored it and "
          f"this plant would overwrite their work: {[p for p, v in already.items() if v]}",
          file=sys.stderr)
    return 3

  # ---- STATE 1: BOTH INPUTS RESTORED, byte-identical from PRE.  Every path below is the STEADY
  # state after this unit lands, so every plant is measured in the state a caller will actually see.
  for p, at in SWEPT.items():
    b = blob(at)
    if b is None:
      print(f"REFUSED: no blob at {PRE}:{at}", file=sys.stderr)
      return 3
    f = ROOT / p
    f.parent.mkdir(parents=True, exist_ok=True)
    f.write_bytes(b)
    out.append(("planted", p, f"{PRE}:{at}", 0, "PLANTED", "-",
                f"{len(b)} B, byte-identical: {sha(p)}"))

  # (1) dup-gate.py -- every DECLARED code, each at the argv `checks/dup-gate.py` declares for it.
  #     `0` and `1` use TWO TRACKED lanes the tree already owns, so neither plant needs a file this
  #     plant had to write.  `2` is the defect's own state, bare argv.  `3` is NOT PLANTED: with the
  #     inputs present no argv reaches it, and a plant that measured 2 would be MISPLANT -- a lie.
  cell("planted", "dup-gate.py", ["--compare", "gates/cstyle-live.rows", "gates/cstyle-live.rows"],
       0, "AUDIT OK", "GREEN: a tracked lane compared with itself, 0 duplicate names")
  cell("planted", "dup-gate.py",
       ["--compare", "gates/cstyle-live.rows", "oracles/usb-oracle-BEFORE.rows"],
       1, "AUDIT FAILED", "RED: the tree's OWN lane that already carries 2 duplicate names")
  cell("planted", "dup-gate.py", [], 2, "-",
       "USAGE: argv named neither --compare nor --port/--oracle. VERDICT_OF THIS STATE IS USAGE, "
       "NOT DEAD -- it RAN and it said so")
  cell("planted", "dup-gate.py", ["--port", "gates/cstyle-live.rows",
                                  "--oracle", "gates/cstyle-live.rows"],
       0, "AGREE", "the value lane over the tracked repaired fixture -- zerogate measured this")
  cell("planted", "dup-gate.py", ["--port", "gates/cstyle-live.rows",
                                  "--oracle", "gates/cstyle-live.rows", "--selftest"],
       0, "SELFTEST OK", "the gate's OWN 4-cell selftest: clean/value/name/collide")

  # (2b) THE NEGATIVE PLANT FOR (2), AND IT IS NOT THE OTHER PATH -- it is the DEFECT CLASS.  The
  #      old existence test accepted a file that WAS THERE and could not be loaded, and this gate
  #      then died at `import isolate` with a traceback.  So the negative cell is a REAL file at a
  #      REAL accepted path that RAISES AT IMPORT: `is_file()` is true, the import cannot succeed,
  #      and the gate must REFUSE(3) with no traceback.  A cell that merely renamed the path would
  #      have PASSED on the old code, which is what makes this one a plant.
  alt = ROOT / HERMETIC_ALT
  alt.write_bytes(b"# PRESENT at an accepted path and NOT importable: the defect class itself\n"
                  b"raise RuntimeError('isolate.py is here and cannot be loaded')\n")
  cell("planted-BROKEN", "hermetic-census.py", ["--help"], 3, "REFUSED",
       "NEGATIVE: isolate PRESENT at checks/ and raising at import -> REFUSED(3), NO traceback")
  alt.unlink()

  # (2c) THE POSITIVE CONTROL FOR THE SAME EDIT, because a fix that refuses every path is a gate
  #      that refuses everything: `modulerefuse` MEASURED that class is 9 gates and it is a disease.
  #      Same argv, the input GOOD -> module scope opens, the refusal does not fire, the import does
  #      not raise.  It is NOT a green plant for the census -- that needs `bend` -- and it is
  #      labelled as argparse's help, not as a census.
  cell("planted", "hermetic-census.py", ["--help"], 0, "OK",
       "POSITIVE CONTROL: the same argv with the input GOOD -> module scope reaches the parser, "
       "and the gate is NOT a gate that refuses everything")

  # ---- STATE 2: RESIDUE, asserted FROM DISK and not from a boolean this file set earlier.  The
  # payload here is a RESTORE, not a temporary plant: these are two gates' REQUIRED INPUTS and
  # `AGENTS.md` puts a gate's input BESIDE THE GATE IN GIT, so they are meant to stay.  So the
  # residue contract is the other way round from `zerogate`'s -- the two swept paths must be PRESENT
  # and byte-identical to `PRE`, and the ALT path this file moved a file THROUGH must be ABSENT,
  # because it is the one that is wrong and the one `checks/hermetic-census.py` must refuse.
  same = {p: (sha(p) == sha(p)) and (ROOT / p).read_bytes() == blob(at) for p, at in SWEPT.items()}
  left = [p for p in SWEPT if not same[p]]
  alt_left = (ROOT / HERMETIC_ALT).is_file()
  out.append(("after", ", ".join(SWEPT), "-", 0,
              "RESTORED" if not left else "WRONG BYTES", "YES" if not left else "NO",
              f"{len(SWEPT) - len(left)}/{len(SWEPT)} byte-identical to {PRE}"))
  out.append(("after", HERMETIC_ALT, "-", 0, "ABSENT" if not alt_left else "RESIDUE",
              "YES" if not alt_left else "NO",
              "the path hermetic-census.py must REFUSE: "
              + ("present, which would let a caller put the input where it cannot be imported"
                 if alt_left else "absent")))
  if left:
    fails.append(f"restored input is not byte-identical to {PRE}: {left}")
  if alt_left:
    fails.append(f"RESIDUE: {HERMETIC_ALT} was left behind by the ALT cell")

  w = 15
  if rows:
    print(f"{"state":<23}{'gate':<20}{"argv":<64}{'rc':>3} {'token':<14}{'ok':<4} what")
    for r in out:
      print(f"{r[0]:<23}{r[1]:<20}{r[2]:<64}{r[3]:>3} {r[4]:<14}{r[5]:<4} {r[6]}")
  else:
    print(f"{"state":<23}{'gate':<20}{"argv":<64}{'rc':>3} {'token':<14}{'ok':<4}")
    for r in out:
      print(f"{r[0]:<23}{r[1]:<20}{r[2]:<64}{r[3]:>3} {r[4]:<14}{r[5]:<4}")
  for f in fails:
    print(f"  FAIL {f}")
  print(f"\nPLANT {'OK' if not fails else 'FAILED -- ' + str(len(fails)) + ' cell(s)'}"
        f"   ({len(out)} rows, {sum(1 for r in out if r[5] == 'NO')} not-ok)")
  print("NOT MEASURED HERE, AND NOT FAKED: `hermetic-census.py` reaching 0 or 3.  0 runs "
        "`census()` -> `isolate.emit(..., \"bend\")` -> `graphcmp.py:1949` subprocesses `bin/bend`, "
        "which this unit must not fork; 3 needs an input absent, which is state 0 above.  Both "
        "stay UNPLANTED in the source, and `gates/gate-surface.py` keeps them red.")
  return 0 if not fails else 1


if __name__ == "__main__":
  sys.exit(main(sys.argv[1:]))