#!/usr/bin/env python3
"""x86_isa-gate.py -- THE PORT'S x86 ROWS AGAINST CPython's, BYTE FOR BYTE.

    .venv/bin/python gates/x86_isa-gate.py
    .venv/bin/python gates/x86_isa-gate.py --no-plants

FOUR LANES, AND THE THIRD IS THE ONE A DIFF CANNOT DO.

  1. `py`  CPython's own answer, computed by `gates/x86_isa-oracle.py` from the LIVE
     `tinygrad/renderer/isa/x86.py`.
  2. `bd`  THE PORT's answer, `bin/bend tinybendygrad/renderer/isa/x86.bend`.
  3. `bn`  THE SAME PORT, COMPILED, so the two are compared and not the same file read
     twice.
  4. `gen` THE PORT'S OWN SOURCE against the GENERATOR'S OUTPUT.  A diff cannot see a
     row that is missing from BOTH lanes: if the port drops a row and the oracle drops
     it too, the two lanes agree and the diff is GREEN.  So the port's `Gate.rowsN()`
     blocks are compared against what `gates/x86_isa-oracle.py gate` GENERATES, and the
     generator is the only thing that says what the row set IS.

THE `py=` HALF IS DERIVED, AND THAT IS THE POINT OF THE WHOLE EXERCISE.  Every row is
`rd(NAME, EXPR)`, and `rd` puts the PORT'S OWN VALUE in BOTH halves: a row cannot
disagree with itself, so the `py=` half is not an independent witness and never was
meant to be.  THE WITNESS IS CPython's lane, and the assertion is the BYTE DIFF between
the two.  A LITERAL `py=` half -- what this file's rows used to carry -- was a
TRANSCRIPTION of CPython's answer, and a transcription is a second copy of the thing
the port is being asked about: it cannot see CPython move.  The port's op table is the
proof, and it is in this tree's history: the base was 78 when upstream's `Ops` enum
numbered 78, upstream's enum shrank, and the LITERAL rows went on saying 78 while the
PORT's own `op_num` said 76 -- 264 rows, all of them green, all of them wrong.

THE ORACLE IS NOT A TRANSCRIPTION EITHER, AND THAT IS WHY IT IS REPAIRED RATHER THAN
COPIED.  It asks CPython for every value: `X86Ops`'s own `.value`, `to_int`'s own
answer, `encode`'s own bytes read out of its LIVE FRAME, `asm_str`'s own text.

THE FIVE VERDICTS ARE `gatekit`'s: PASS 0, FAIL 1, REFUSED 3, SKIP 4, DEAD 5.  A lane
that emitted no rows is DEAD, not PASS, and an input that is not there is REFUSED, not
FAIL.  "A GATE THAT EXITS 0 HAVING MEASURED NOTHING IS WORSE THAN NO GATE."

THE PLANT LANE IS NOT OPTIONAL.  A derived row cannot disagree with itself, so the
plant that a LITERAL row can fire -- a `py=` literal beside a correct table -- is
STRUCTURALLY IMPOSSIBLE here, and the plant that CAN fire is the one that matters: a
row's VALUE put wrong, with the port still self-consistent, must still go RED.  That
is `gates/x86_isa-plant.py`, and it is the proof that the lane is not a
self-consistency check.
"""
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from bendlock import bend_lock  # noqa: E402
from gatekit import ART, DEAD, FAIL, PASS, REFUSED, SKIP  # noqa: E402

NAME = "x86_isa-gate"
OUT = ART / NAME
DRIVER = ROOT / "tinybendygrad" / "renderer" / "isa" / "x86.bend"
ORACLE = HERE / "x86_isa-oracle.py"
PLANT = HERE / "x86_isa-plant.py"
PY = ROOT / ".venv" / "bin" / "python"
BEND = ROOT / "bin" / "bend"
WARM = "ALL PROOFS CHECK"


def say(msg):
  print(f"{NAME}: {msg}", file=sys.stderr)


def refuse(why):
  print(f"== REFUSED, NOT A VERDICT: {NAME}: {why}", file=sys.stderr)
  return REFUSED


def run(argv, **kw):
  return subprocess.run(argv, capture_output=True, text=True, cwd=str(ROOT), **kw)


def warm():
  """`--check-only`'s FIRST LINE, never its exit status.  `gatekit._warm`'s rule: an
  EMPTY file typechecks, so the exit status alone would call a truncated driver warm."""
  with bend_lock() as waited:
    if waited:
      say(f"waited {waited}s for the bend lock")
    r = run([str(BEND), str(DRIVER), "--check-only"])
  first = (r.stdout or "").splitlines()[:1]
  return bool(first) and first[0].strip() == WARM, r


def oracle_rows():
  """CPython's lane.  `(bytes, why)` -- `why` is set when the lane could not answer."""
  r = run([str(PY), str(ORACLE), "rows"])
  if r.returncode != 0:
    said = " | ".join(l.strip() for l in (r.stderr or "").splitlines() if l.strip())[:300]
    return None, f"the oracle failed rc={r.returncode}: {said}"
  if not r.stdout.strip():
    return None, "the oracle ran and emitted no rows"
  return r.stdout, None


def port_rows():
  """THE PORT's lane, through the lock.  `(bytes, why)`."""
  with bend_lock() as waited:
    if waited:
      say(f"waited {waited}s for the bend lock")
    r = run([str(BEND), str(DRIVER)])
  if r.returncode != 0:
    said = " | ".join(l.strip() for l in (r.stderr or "").splitlines()
                      if l.strip() and not l.startswith("bend "))[:300]
    return None, f"the port lane failed rc={r.returncode}: {said}"
  if not r.stdout.strip():
    return None, "the port lane ran and emitted no rows"
  return r.stdout, None


def native_rows():
  """THE SAME PORT, COMPILED.  `(bytes, why)`."""
  OUT.mkdir(parents=True, exist_ok=True)
  binary = OUT / "gate.bin"
  with bend_lock() as waited:
    if waited:
      say(f"waited {waited}s for the bend lock")
    c = run([str(BEND), str(DRIVER), "-o", str(binary)])
  if c.returncode != 0:
    return None, f"the native compile failed rc={c.returncode}"
  r = run([str(binary)])
  if r.returncode != 0:
    return None, f"the compiled lane failed rc={r.returncode}"
  if not r.stdout.strip():
    return None, "the compiled lane ran and emitted no rows"
  return r.stdout, None


def rows_of(text):
  """THE ROW COUNT, and the count is of ROWS.

  The port's last row ends in a newline and `IO.print` adds one more, so the port's
  output ends with a BLANK line; the oracle's does the same.  Counting LINES would
  report 770 for 769 rows, and a count that is off by the framing is a count nobody
  can check."""
  return len([l for l in text.split("\n") if l.strip()])


def disagree(a, b):
  """The differing lines, and how many.  A diff, not a count."""
  al, bl = a.split("\n"), b.split("\n")
  bad = [(x, y) for x, y in zip(al, bl) if x != y]
  if len(al) != len(bl):
    bad += [(x, "<missing>") for x in al[len(bl):]] + [("<missing>", y) for y in bl[len(al):]]
  return bad


def generator_rows():
  """THE PORT'S OWN ROW SOURCE, and the generator's output for it.

  The port's `Gate.rowsN()` blocks are GENERATED -- `gates/x86_isa-oracle.py gate` --
  and this is the check that says so: the blocks are compared against what the
  generator produces, byte for byte.  It is the ROW SET a diff cannot see."""
  r = run([str(PY), str(ORACLE), "gate"])
  if r.returncode != 0:
    return None, None, "the oracle's `gate` selector failed"
  src = DRIVER.read_text()
  start = src.index("def Gate.rows0() -> List<&2, String>: [")
  end = src.index("# THE TABLE, IN CHUNKS.")
  return src[start:end], r.stdout, None


def live_lane():
  """LANES 1-3: CPython's answer against the port's, twice, byte for byte."""
  if not warm()[0]:
    return refuse(f"the driver is not warm (`--check-only`'s first line is not {WARM!r})")
  OUT.mkdir(parents=True, exist_ok=True)
  for p in OUT.iterdir():
    if p.is_file():
      p.unlink()
  want, why = oracle_rows()
  if want is None:
    return refuse(why)
  (OUT / "py.rows").write_text(want)
  for tag, lane in (("bd", port_rows), ("bn", native_rows)):
    got, why = lane()
    if got is None:
      return DEAD if "emitted no rows" in why else refuse(why)
    (OUT / f"{tag}.out").write_text(got)
    if got != want:
      bad = disagree(want, got)
      say(f"DISAGREE ({tag}): n={len(bad)} of {max(len(want.split(chr(10))), len(got.split(chr(10))))} "
          f"lines; first: {bad[:2]}")
      return FAIL
    print(f"  {tag}: {rows_of(got)} rows, BYTE-IDENTICAL to CPython's")
  return PASS


def generator_lane():
  """LANE 4: THE ROW SET A DIFF CANNOT SEE."""
  got, want, why = generator_rows()
  if why:
    return refuse(why)
  if got != want:
    say("the port's own `Gate.rowsN()` blocks are not what the generator produces")
    return FAIL
  n = len(re.findall(r"^   rd\(", got, re.M))
  print(f"  gen: {n} generated rows match the port's own source")
  return PASS


def plant_lane():
  """LANE 5: THE PLANTS.  A wrong VALUE must go RED; a comment must stay GREEN."""
  if not PLANT.is_file():
    return refuse(f"{PLANT} is missing -- a plant harness with no arms asserts nothing")
  r = run([str(PY), str(PLANT)])
  for line in (r.stdout or "").splitlines():
    print(line)
  if r.stderr.strip():
    for line in r.stderr.splitlines():
      say(line)
  if r.returncode == 0:
    return PASS
  if r.returncode == 1:
    return FAIL
  return refuse(f"the plants refused rc={r.returncode}")


def main(argv):
  only_plants = "--plants" in argv
  no_plants = "--no-plants" in argv
  if only_plants and no_plants:
    return refuse("--plants and --no-plants are both given, so the run would measure nothing")
  code = PASS
  if not only_plants:
    for lane in (live_lane, generator_lane):
      c = lane()
      if c != PASS:
        code = c
        break
  if code == PASS and not no_plants:
    c = plant_lane()
    if c != PASS:
      code = c
  if no_plants and not only_plants:
    print("== SKIPPED: the plant lane was not run (`--no-plants`), and a SKIP IS NOT A PASS")
    return SKIP
  if code == PASS:
    print(f"{NAME}: PASS -- the port's x86 rows and CPython's are BYTE-IDENTICAL, and the "
          "port's own source is the generator's output")
  else:
    print(f"{NAME}: FAIL" if code == FAIL else f"{NAME}: REFUSED")
  return code


if __name__ == "__main__":
  sys.exit(main(sys.argv[1:]))
