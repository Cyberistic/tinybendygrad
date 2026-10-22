#!/usr/bin/env python3
"""x86_isa-plant.py -- THE PLANTS FOR THE x86 LANE.

    .venv/bin/python gates/x86_isa-plant.py

TWO ARMS, AND THE SECOND IS THE ONE THE DERIVED SHAPE MAKES NECESSARY.

  A0  THE CONTROL.  A COMMENT-ONLY EDIT.  The port's bytes must be UNCHANGED, so a
      plant that "moves" nothing is not a plant -- and so the diff machinery is shown
      to be measuring the ROWS and not the FILE.

  A1  THE PLANT.  A ROW'S VALUE PUT WRONG.  `Op.base()` -- the number every `op.*` and
      `oprev *` row is numbered FROM -- is moved from 76 to 78, and the port's rows go
      with it.  THE PORT IS STILL SELF-CONSISTENT: the `got=` half says 78 and the
      DERIVED `py=` half says 78, because `rd` puts the port's own value in both.  AND
      THE LANE MUST STILL GO RED, because CPython says 76.

WHY THAT IS THE PLANT AND NOT tc.bend's.  `renderer/tc.bend`'s P2 plants a LITERAL
`py=` half beside a correct table and expects RED, and a derived cell CANNOT FAIL THAT
PLANT: there is no literal to plant, and a row that cannot disagree with itself is a
row that cannot be its own witness.  So the plant that a derived row CAN fail is the
OTHER one -- the row's VALUE, which the port computes, put wrong -- and it is the
stronger claim, because the port is self-consistent throughout and the RED still
comes.

THE POINT OF A1 IS WHAT IT IS NOT.  It is not "the gate catches a broken file"; it is
"the gate is not a SELF-CONSISTENCY CHECK".  A gate that compared the port's `got=`
half with the port's `py=` half would be GREEN on A1, because the two halves agree.
The RED comes from CPython's lane, and only from it.

THE COPY IS BESIDE THE ORIGINAL, AND THE ORIGINAL IS NEVER TOUCHED.  The `.bend` file
imports `./../../LAWS/spec.bend` RELATIVE TO ITS OWN DIRECTORY, so a copy anywhere
else would not compile -- and a copy IN PLACE would be a shared writable path, which
`AGENTS.md` says is the one shape nobody should hold.  So the copy is written beside
the original under a name of its own, and removed in a `finally`.

THE LOCK IS THE TREE'S SHARED ONE.  `gates/bendlock.py` acquires it PER INVOCATION, so
a plant that runs several compilers does not hold it for the whole harness.
"""
import re
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from bendlock import bend_lock  # noqa: E402

DRIVER = ROOT / "tinybendygrad" / "renderer" / "isa" / "x86.bend"
COPY = ROOT / "tinybendygrad" / "renderer" / "isa" / "x86_isa-plant.bend"
ORACLE = HERE / "x86_isa-oracle.py"
PY = ROOT / ".venv" / "bin" / "python"
BEND = ROOT / "bin" / "bend"

PASS, FAIL = 0, 1


def say(msg):
  print(f"x86_isa-plant: {msg}")


def run(argv):
  return subprocess.run(argv, capture_output=True, text=True, cwd=str(ROOT))


def oracle_rows():
  r = run([str(PY), str(ORACLE), "rows"])
  if r.returncode != 0 or not r.stdout.strip():
    return None
  return r.stdout


def port_rows(path):
  """THE PORT'S OWN BYTES, from a COPY, through the lock."""
  with bend_lock() as waited:
    if waited:
      say(f"waited {waited}s for the bend lock")
    r = run([str(BEND), str(path)])
  if r.returncode != 0 or not r.stdout.strip():
    return None
  return r.stdout


def rows_of(text):
  """THE ROW COUNT, and the count is of ROWS.  The port's last row ends in a newline
  and `IO.print` adds one more, so the output ends with a BLANK line."""
  return len([l for l in text.split("\n") if l.strip()])


def differ(a, b):
  al, bl = a.split("\n"), b.split("\n")
  bad = [(x, y) for x, y in zip(al, bl) if x != y]
  if len(al) != len(bl):
    bad += [(x, "<missing>") for x in al[len(bl):]] + [("<missing>", y) for y in bl[len(al):]]
  return bad


def arm(name, mutate, want):
  """ONE ARM.  `want` is `same` or `different` -- the answer the arm must get.

  The arm is measured on a COPY, and the copy is removed whatever happens."""
  src = DRIVER.read_text()
  out, n = mutate(src)
  if n != 1:
    say(f"{name}: REFUSED -- the mutation matched {n} places, expected 1")
    return FAIL
  try:
    COPY.write_text(out)
    got = port_rows(COPY)
  finally:
    COPY.unlink(missing_ok=True)
  if got is None:
    say(f"{name}: REFUSED -- the mutated copy did not run")
    return FAIL
  base = oracle_rows()
  if base is None:
    say(f"{name}: REFUSED -- the oracle did not run")
    return FAIL
  bad = differ(base, got)
  if want == "same":
    if bad:
      say(f"{name}: FAILED -- {len(bad)} lines differ, expected none; first: {bad[:2]}")
      return FAIL
    say(f"{name}: OK -- {rows_of(got)} rows, BYTE-IDENTICAL to CPython's")
    return PASS
  if not bad:
    say(f"{name}: FAILED -- the mutated port's lines are all IDENTICAL to CPython's, so the "
        "lane is a SELF-CONSISTENCY CHECK and not a comparison")
    return FAIL
  # THE PLANT MUST MOVE THE ROWS IT NAMES, NOT JUST ANY ROW.  A mutation that broke
  # the file in some other way would also be "different", and that is not the claim.
  named = [l for l in bad if l[0].startswith("op.")]
  if not named:
    say(f"{name}: FAILED -- the {len(bad)} differing lines are not `op.*` rows: {bad[:2]}")
    return FAIL
  say(f"{name}: OK -- {len(bad)} lines differ from CPython's, {len(named)} of them `op.*` rows")
  say(f"      port:   {named[0][1]}")
  say(f"      oracle: {named[0][0]}")
  return PASS


def m_comment(src):
  """A COMMENT-ONLY EDIT.  The bytes must not move."""
  anchor = "\nimport Base\n"
  marker = "\n# THE PLANT'S CONTROL -- A COMMENT, AND NOTHING ELSE.\nimport Base\n"
  if src.count(anchor) != 1:
    return src, 0
  return src.replace(anchor, marker), 1


def m_base(src):
  """THE PLANT: A ROW'S VALUE PUT WRONG.  The base every op row is numbered from."""
  old = "def Op.base() -> U32: 76"
  if src.count(old) != 1:
    return src, 0
  return src.replace(old, "def Op.base() -> U32: 78"), 1


def main():
  want = oracle_rows()
  if want is None:
    say("REFUSED -- the oracle did not run")
    return 3
  n = rows_of(want)
  say(f"the oracle answered {n} rows")
  bad = 0
  for name, mutate, expect in (("A0 control (a comment)", m_comment, "same"),
                               ("A1 plant  (a wrong VALUE)", m_base, "different")):
    if arm(name, mutate, expect) != PASS:
      bad += 1
  if bad:
    say(f"FAILED: {bad} of 2 arms did not behave as declared")
    return FAIL
  say("all 2 arms OK")
  return PASS


if __name__ == "__main__":
  sys.exit(main())
