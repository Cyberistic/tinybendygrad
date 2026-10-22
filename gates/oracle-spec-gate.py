#!/usr/bin/env python3
"""THE PROVENANCE OF `oracles/oracle-spec.rows`: the file is a GENERATOR'S OUTPUT, and the
generator is FAITHFUL to the file it replaced.

    .venv/bin/python gates/oracle-spec-gate.py            # the gate
    .venv/bin/python gates/oracle-spec-gate.py --plant    # the plant and its control

WHY THIS FILE EXISTS, AND IT IS NOT A SECOND COPY OF THE GENERATOR'S OWN CHECK.
`gates/oracle-spec-gen.py --check` answers ONE question: is the file on disk the generator's
output, byte for byte? That is necessary and it is not sufficient. The generator's rows are
CPython's LIVE `tinygrad/uop/spec` -- six table sizes, two `early_reject` sets, and three
verdicts -- and the file they write is a FROZEN COPY of a reading, which is the defect this
whole class is about: "a population is a generator's own declaration, loaded by path".

So there are TWO claims, and only the first one had an instrument:

  1. THE FILE IS THE GENERATOR'S OUTPUT.   `gates/oracle-spec-gen.py --check` answers it.
  2. THE GENERATOR IS FAITHFUL TO WHAT IT REPLACED.  Nothing answered it. It was a claim in
     a docstring and in a commit message, and a claim with no instrument is a LABEL.

Claim 2 is what rules out the hand-edit. If somebody regenerated the file and then typed a
value into one of the OTHER rows, claim 1 would still pass -- the generator would still be
the source of the file -- and the only thing that would notice is the comparison against the
file the generator REPLACED: the generator must reproduce it BYTE FOR BYTE except for the
lengths, and a hand-typed row is a byte that is not there.

THE PIN IS DISCOVERED, NOT WRITTEN. The revision whose file the generator replaced is the
PARENT of the commit that ADDED `gates/oracle-spec-gen.py`, and that commit is FOUND by
`git log --diff-filter=A` -- so this file names no revision and cannot go stale when the
generator moves. A hand-written revision here would be a fixture against an unstated
revision, which is a fixture against nobody.

THE LENGTH ROWS ARE DISCOVERED TOO. The rows that may differ are the ones whose KEY ends in
`_len`, and the count of the ones that DID differ falls out of the comparison and is
printed -- it is not written down here, because a number written down is a number that rots.

THE PLANT, AND WHY IT IS A TEXT EDIT. The plant writes a COPY of the predecessor's rows with
one row changed, and the comparison must go red; the control changes a LENGTH row, and the
comparison must stay green, because the lengths are the permitted exception. The plant never
edits the tree.

`gates/gates-pop.py` clause I DISCOVERS gates by an `if __name__ == "__main__"` AST node, so
this file IS a gate and lands in the ledger. `checks/gatesweep.py` sweeps it by the same
discovery, so it runs without anybody naming it. Its commit message OWES the claim, which
is what `gates/ledgerdue-gate.py` asks for.
"""
import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
HERE = ROOT / "gates"
PY = ROOT / ".venv" / "bin" / "python"
GEN = HERE / "oracle-spec-gen.py"
ORACLE = ROOT / "oracles" / "oracle-spec.rows"
REL_GEN = "gates/oracle-spec-gen.py"
REL_ORACLE = "oracles/oracle-spec.rows"

sys.path.insert(0, str(HERE))
from gatekit import FAIL, PASS, REFUSED  # noqa: E402


def _git(*args: str) -> subprocess.CompletedProcess:
  return subprocess.run(["git", *args], capture_output=True, text=True, cwd=ROOT)


def generator_text() -> str:
  """The generator's rows, from the generator's OWN entry point."""
  p = subprocess.run([str(PY), str(GEN)], capture_output=True, text=True, cwd=ROOT)
  if p.returncode != 0:
    raise RuntimeError(f"the generator failed: {p.stderr[-400:]}")
  return p.stdout


def generator_commit() -> str:
  """The commit that ADDED the generator -- the OLDEST one, because that is the one that
  replaced the hand-written file."""
  p = _git("log", "--diff-filter=A", "--format=%H", "--reverse", "--", REL_GEN)
  lines = [l for l in p.stdout.splitlines() if l.strip()]
  if not lines:
    raise RuntimeError(f"no commit added {REL_GEN}")
  return lines[0]


def predecessor_text(pin: str) -> str:
  """The file at the pin's PARENT -- the one the generator replaced."""
  p = _git("show", f"{pin}^:{REL_ORACLE}")
  if p.returncode != 0:
    raise RuntimeError(f"git show {pin}^:{REL_ORACLE} failed: {p.stderr[-400:]}")
  return p.stdout


def keyed(text: str) -> dict[str, str]:
  """Every `key=value` row of a rows-file, keyed. A `#repro_*` row is a COMMENT that carries
  a row, so the leading `#` is stripped and the key is the rest."""
  out: dict[str, str] = {}
  for line in text.splitlines():
    body = line[1:] if line.startswith("#") else line
    m = re.match(r"^([A-Za-z_][\w]*)=(.*)$", body)
    if m:
      out[m.group(1)] = m.group(2)
  return out


def is_length(key: str) -> bool:
  """A LENGTH row: the key ends in `_len`. Discovered, not listed."""
  return key.endswith("_len")


def faithfulness(old_text: str, gen_text: str) -> tuple[bool, list[str]]:
  """Is the generator FAITHFUL to the file it replaced?

  THE SUBSTITUTION IS THE PROOF: take the OLD file, put the generator's length values in, and
  the result must EQUAL the generator's output byte for byte. Every other row is carried over
  unchanged, so a hand-typed row is a byte that is not there.

  Returns `(ok, notes)`; `notes` is what a reader checks instead of trusting the verdict.
  """
  notes: list[str] = []
  old_rows, gen_rows = keyed(old_text), keyed(gen_text)
  if set(old_rows) != set(gen_rows):
    notes.append(f"the row KEYS differ: only in old {sorted(set(old_rows) - set(gen_rows))}, "
                 f"only in new {sorted(set(gen_rows) - set(old_rows))}")
    return False, notes
  differing = sorted(k for k in old_rows if old_rows[k] != gen_rows[k])
  bad = [k for k in differing if not is_length(k)]
  notes.append(f"rows in both: {len(gen_rows)}   differing rows: {len(differing)}   "
               f"the differing rows: {', '.join(differing) if differing else '(none)'}")
  for k in differing:
    notes.append(f"{k}: {old_rows[k]} -> {gen_rows[k]}")
  if bad:
    notes.append(f"A ROW THAT IS NOT A LENGTH CHANGED: {bad} -- the generator is NOT faithful "
                 f"to the file it replaced, so the file was not merely the port's stale lengths.")
    return False, notes
  rebuilt = []
  for line in old_text.splitlines():
    body = line[1:] if line.startswith("#") else line
    m = re.match(r"^([A-Za-z_][\w]*)=(.*)$", body)
    rebuilt.append(f"{m.group(1)}={gen_rows[m.group(1)]}" if m and is_length(m.group(1)) else line)
  rebuilt_text = "\n".join(rebuilt) + ("\n" if old_text.endswith("\n") else "")
  if rebuilt_text != gen_text:
    notes.append("the old file with the generator's lengths substituted is NOT the generator's "
                 "output, byte for byte")
    for a, b in zip(rebuilt_text.splitlines(), gen_text.splitlines()):
      if a != b:
        notes.append(f"  old+lengths: {a}\n  generator  : {b}")
    return False, notes
  notes.append("the old file with the generator's lengths substituted is the generator's output, "
               "byte for byte : YES")
  return True, notes


def plant() -> int:
  """THE PLANT AND ITS CONTROL. Both are TEXT EDITS of a COPY of the predecessor's rows."""
  bad = 0
  old_text = predecessor_text(generator_commit())
  gen_text = generator_text()
  # the plant: a row that is NOT a length is changed, so the comparison must go red.
  planted = old_text.replace("tag_const=1", "tag_const=0")
  if planted == old_text:
    print("REFUSED: the plant's anchor is not in the predecessor's rows as they stand.")
    return REFUSED
  ok, notes = faithfulness(planted, gen_text)
  print("PLANT    one NON-LENGTH row of the predecessor changed")
  for n in notes:
    print(f"         {n}")
  if ok:
    print("  THE PLANT DID NOT FIRE: a non-length row changed and the comparison stayed green.")
    bad += 1
  # the control: a LENGTH row is changed, and the comparison must stay green -- the lengths
  # are the permitted exception, and a control that edits more than it meant to is no control.
  control = old_text.replace("sh_len=33", "sh_len=99")
  if control == old_text:
    print("  THE CONTROL IS NOT A CONTROL: the control's anchor is not in the predecessor's rows.")
    return FAIL
  ok2, notes2 = faithfulness(control, gen_text)
  print("CONTROL  one LENGTH row of the predecessor changed")
  for n in notes2:
    print(f"         {n}")
  if not ok2:
    print("  THE CONTROL IS NOT A CONTROL: a length row changed and the comparison went red.")
    bad += 1
  print(f"\n=== plant: {'FAIL' if bad else 'PASS'}: {bad} problem(s) ===")
  return FAIL if bad else PASS


def main() -> int:
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("--plant", action="store_true", help="run the plant and its control")
  args = ap.parse_args()
  if args.plant:
    return plant()
  try:
    gen_text = generator_text()
    pin = generator_commit()
    old_text = predecessor_text(pin)
  except RuntimeError as exc:
    print(f"REFUSED: {exc}")
    return REFUSED

  print(f"PROVENANCE  {REL_ORACLE}")
  print(f"            generator   : {REL_GEN}")
  print(f"            the generator was ADDED by {pin[:12]}"
        f"  ({_git('log', '-1', '--format=%s', pin).stdout.strip()})")

  # CLAIM 1: the file on disk is the generator's output. The generator's OWN check answers
  # it, so it is not re-implemented here.
  chk = subprocess.run([str(PY), str(GEN), "--check"], capture_output=True, text=True, cwd=ROOT)
  claim1 = chk.returncode == 0
  print("CLAIM 1     the file is the generator's output, byte for byte : "
        f"{'OK' if claim1 else 'DRIFT'}")
  for line in chk.stdout.splitlines():
    print(f"            {line}")

  # CLAIM 2: the generator reproduces the file it replaced, byte for byte, except the lengths.
  claim2, notes = faithfulness(old_text, gen_text)
  print("CLAIM 2     the generator reproduces the file it replaced, byte for byte, "
        "except the lengths")
  for n in notes:
    print(f"            {n}")

  if not claim2:
    print("\n=== oracle-spec-gate: FAIL: the generator is not faithful to the file it replaced ===")
    return FAIL
  if not claim1:
    print("\n=== oracle-spec-gate: FAIL: the file on disk is not the generator's output ===")
    return FAIL
  print("\n=== oracle-spec-gate: PASS: the file is a generator's output, and the generator is "
        "faithful to the file it replaced ===")
  return PASS


if __name__ == "__main__":
  raise SystemExit(main())
