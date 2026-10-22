#!/usr/bin/env python3
"""dtypeeven-plant.py -- the PLANT for `gates/dtypeeven-gate.py`, and it is a TEXT EDIT.

    .venv/bin/python gates/dtypeeven-plant.py

WHAT THIS PLANTS, AND WHY IT IS A TEXT EDIT.  The gate's subject is the port's
`dtypes.*` NAMES, and the defect it exists to catch is a name the port can spell and
upstream cannot.  So the plant adds one: a `def dtypes.index()` -- the name upstream's
`dtypes` does not have and the port used to carry -- and the GATE MUST GO RED.

THE BYTES COME FROM THE WORKING TREE AND NEVER FROM `git show HEAD:`.  A plant that reads
HEAD plants nothing the moment HEAD carries the defect's fix, and the fix for THIS defect
is "delete the name" -- so a HEAD-reading plant would be green from the moment it was
committed.  Three units scored green under `--falsify` tonight for exactly that reason.

THE PLANT NEVER TOUCHES THE REAL FILE.  It writes the edited text into a MIRROR tree and
points the gate at that tree with `TINYGRAD_ROOT`.  A plant that edits its subject leaves
the tree wrong if it dies between the edit and the revert, and the subject here is a file
another unit is working on.

THE MIRROR HARD-LINKS, AND NOT SYMLINKS, AND THE REASON IS BEND'S OWN IMPORT RESOLUTION.
`references/bend/bend2/bend.ts:962` makes the PROJECT ROOT the entry file's directory and
`bend.ts:1000` requires every import to be a PLAIN NAME relative to it -- and
`book_file` answers `fs.realpathSync(file)`, which RESOLVES A SYMLINK.  So a mirror whose
`LAWS/` is a symlink makes the import resolve into the REAL tree, the relative path comes
back as `../../..`, and the compiler refuses the file with "an import path of plain
names" -- a refusal about the MIRROR and not about the edit.  MEASURED here, and that is
why the mirror hard-links.

FOUR CASES AND TWO SHAPES, AND EACH ONE ASSERTS WHAT IT IS.

  PLANT-DIVERGENCE    a `dtypes.<name>` the port cannot spell upstream's way -> the gate
                      goes RED and NAMES the name.  THE FIRST DIRECTION.
  PLANT-STALE-SPELL   the port's `to_dtype` accepts a name upstream cannot spell -> the
                      gate goes RED.  THE OTHER DIRECTION: a declared omission that is no
                      longer true is a stale declaration.
  PLANT-STALE-POLICY  the port's own DECLARATION says `legacy-alias=ALL` while the tree
                      spells none of them -> the gate goes RED, because a declaration the
                      gate does not read is a declaration nobody checks.
  CONTROL             a whole-line comment at COLUMN 0 -> the gate stays GREEN and the
                      comment-stripped bytes are UNCHANGED.  A control that edits more
                      than it meant to is not a control.
  WRONG-SHAPE-A       a comment appended to the FIRST part of a `case` line that carries
                      a pattern and a body DELETES the body, and the file still COMPILES
                      -- which is the dangerous part: only the comment-stripped proof
                      catches it, and the compiler does not.
  WRONG-SHAPE-B       a whole-line comment at COLUMN 0 does NOT break a bend file.

THE COMMENT-STRIPPED PROOF IS `checks/port-compile-gate.py`'s OWN `strip_comments()`,
imported BY PATH, and the BLANK-LINE DROP is the fix `gates/ptx_render_census-gate.py`
made for exactly this reason: a comment on its own line is a blank line once the comment
is stripped, and comparing LINE LISTS would call the most comment-only edit there is "not
comment-only".
"""

import importlib.util
import os
import subprocess
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PORT = ROOT / "tinybendygrad" / "dtype.bend"
GATE = HERE / "dtypeeven-gate.py"
PY = ROOT / ".venv" / "bin" / "python"

PASS, FAIL, REFUSED = 0, 1, 3

# THE ANCHORS, AND THEY ARE TEXT.  Every one of them is checked to be PRESENT before the
# plant runs, and a missing anchor is a REFUSAL and not a fallback: the plant is a text
# edit on the working tree, so an anchor that moved means the plant must be re-anchored,
# NOT that it should read git for a version the anchor used to be in.
DIVERGENCE_ANCHOR = "def dtypes.weakint() -> S.Dt: S.weakint()\n"
DIVERGENCE_PLANT = DIVERGENCE_ANCHOR + "def dtypes.index() -> S.Dt: S.weakint()\n"
SPELL_ANCHOR = '    case "void": Some{S.void()}\n'
SPELL_PLANT = '    case "index": Some{S.weakint()}\n' + SPELL_ANCHOR
POLICY_ANCHOR = "#   DTYPES-POLICY: legacy-alias=NONE\n"
POLICY_PLANT = "#   DTYPES-POLICY: legacy-alias=ALL\n"


def _load_port_compile():
  """`checks/port-compile-gate.py` BY PATH, for its `judge()` and its `strip_comments()`.

  The compile check is that file's, and it reads the VERDICT TOKEN rather than the exit
  status.  A second copy of either here would be a second copy of the question, and the
  two would drift.
  """
  spec = importlib.util.spec_from_file_location("port_compile",
                                                ROOT / "checks" / "port-compile-gate.py")
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def _code_only(pc, text: str) -> str:
  """The file with every comment REMOVED and every blank line DROPPED.

  The comment removal is `checks/port-compile-gate.py`'s own `strip_comments()` -- it
  knows that a `#` inside a string is not a comment.  The BLANK-LINE DROP is
  `gates/ptx_render_census-gate.py`'s fix, copied: a comment on its own line contributes a
  line that is empty once the comment is stripped, and comparing LINE LISTS would call
  that "not comment-only" -- which is the most comment-only edit there is.
  """
  return "\n".join(l for l in pc.strip_comments(text).split("\n") if l.strip())


def _mirror(tmp: Path) -> Path:
  """A tree whose ONLY difference is `tinybendygrad/dtype.bend`.  Returns the port's dir.

  HARD LINKS, AND THE REASON IS IN THIS FILE'S HEADER: bend resolves an import against
  the entry file's directory and `realpath`s it, so a symlinked sibling resolves into the
  REAL tree and the compiler refuses the mirror with "an import path of plain names" -- a
  refusal about the mirror and not about the edit.
  """
  (tmp / "tinygrad").symlink_to(ROOT / "tinygrad")
  dst = tmp / "tinybendygrad"
  for p in sorted((ROOT / "tinybendygrad").rglob("*")):
    out = dst / p.relative_to(ROOT / "tinybendygrad")
    if p.is_dir():
      out.mkdir(parents=True, exist_ok=True)
    else:
      out.parent.mkdir(parents=True, exist_ok=True)
      if p.name != "dtype.bend":
        os.link(p, out)
  return dst


def _run_gate(mirror: Path) -> tuple[int, str]:
  """The gate, pointed at the mirror.  Returns `(rc, output)`."""
  env = {k: v for k, v in os.environ.items() if k != "TINYGRAD_ROOT"}
  env["TINYGRAD_ROOT"] = str(mirror)
  p = subprocess.run([str(PY), str(GATE)], env=env, capture_output=True, text=True, cwd=ROOT)
  return p.returncode, p.stdout + p.stderr


def _compile(pc, path: Path) -> tuple[str, str]:
  """The compile verdict for one file, under the memory ceiling.  The TOKEN is the verdict."""
  state, detail, _ = pc.judge(str(path), 2048, 300)
  return state, detail


def _first_difference(before: list[str], after: list[str]):
  """`(index, before, after)` for the first line that differs, or `None`.

  The lines are the COMMENT-STRIPPED ones, so a difference here is a difference in CODE and
  not a difference in prose.  A line that only one side has counts as a difference with
  the other side's line empty.
  """
  for i in range(max(len(before), len(after))):
    b = before[i] if i < len(before) else ""
    a = after[i] if i < len(after) else ""
    if b != a:
      return i, b, a
  return None


def plant() -> int:
  """THE FOUR CASES AND THE TWO SHAPES.  Every one of them asserts what it is."""
  pc = _load_port_compile()
  original = PORT.read_text()
  for anchor in (DIVERGENCE_ANCHOR, SPELL_ANCHOR, POLICY_ANCHOR):
    if anchor not in original:
      print(f"REFUSED: the plant's anchor {anchor!r} is not in {PORT} as it stands. THE PLANT IS A "
            f"TEXT EDIT ON THE WORKING TREE, so an anchor that moved means the plant must be "
            f"re-anchored -- NOT that it should fall back to reading git.")
      return REFUSED
  # THE CONTROL'S INSERTION POINT: a column-0 comment above an indented body.  The house
  # measured this shape at three insertion points and all three compile.
  lines = original.split("\n")
  indent = next((i for i, ln in enumerate(lines)
                 if i > 0 and ln.startswith("  ") and lines[i - 1].strip()
                 and not lines[i - 1].lstrip().startswith("#")), None)
  control = None
  if indent is not None:
    c = list(lines)
    c.insert(indent, "# a comment inserted at column 0")
    control = "\n".join(c)
  else:
    print("CONTROL  NOT APPLICABLE, AND THAT IS A MEASUREMENT: no indented body follows a "
          "non-comment line in the port's dtype file.")
  # THE WRONG SHAPE A's TARGET: a `case` line carrying a PATTERN and a BODY.  The house's own
  # plant looks for exactly this shape, and the reason a comment there is dangerous is that
  # the arm is left EMPTY and the compiler notices the NEXT case -- so the error points
  # somewhere else.
  two_part = next((ln for ln in lines if ln.startswith("    case ") and ": " in ln
                   and not ln.rstrip().endswith(":")), None)
  shape_a = None
  if two_part is not None:
    head, _, tail = two_part.partition(": ")
    a = list(lines)
    a[lines.index(two_part)] = f"{head}: # a comment appended to the pattern{tail}"
    shape_a = "\n".join(a)
  else:
    print("WRONG-SHAPE-A  NOT APPLICABLE, AND THAT IS A MEASUREMENT: no `case` line of the "
          "port's dtype file carries a pattern and a body on one line.")

  gate_cases = [
    ("PLANT-DIVERGENCE", original.replace(DIVERGENCE_ANCHOR, DIVERGENCE_PLANT, 1),
     "a `dtypes.index()` the port can spell and upstream cannot", ("DIVERGENCE", "index")),
    ("PLANT-STALE-SPELL", original.replace(SPELL_ANCHOR, SPELL_PLANT, 1),
     "the port's `to_dtype` accepts a name upstream cannot spell", ("to_dtype", "index")),
    ("PLANT-STALE-POLICY", original.replace(POLICY_ANCHOR, POLICY_PLANT, 1),
     "the port's own declaration says `legacy-alias=ALL` and the tree spells none of them",
     ("legacy-alias", "ALL")),
  ]
  if control is not None:
    gate_cases.append(("CONTROL", control, "a whole-line comment at column 0", ()))
  # THE TWO SHAPES ARE NOT PLANTS FOR THE GATE.  They are DEMONSTRATIONS about a
  # "comment-only edit", and they are asserted against the COMPILER and the comment-stripped
  # proof -- not against the gate, whose verdict they do not move.
  shape_cases = []
  if shape_a is not None:
    shape_cases.append(("WRONG-SHAPE-A", shape_a,
                         "a comment on the pattern, body on the same line"))
  if control is not None:
    shape_cases.append(("WRONG-SHAPE-B", control, "a whole-line comment at column 0"))

  bad = 0
  with tempfile.TemporaryDirectory() as td:
    mirror = Path(td)
    port_dir = _mirror(mirror)
    probe = port_dir / "dtype.bend"
    for name, text, why, expect in gate_cases:
      probe.write_text(text)
      rc, out = _run_gate(mirror)
      same_code = _code_only(pc, text) == _code_only(pc, original)
      line = out.strip().splitlines()
      detail = next((ln for ln in line if ln.startswith("dtypeeven-gate:") and "census" not in ln),
                    line[-1] if line else "")
      print(f"{name:<20} gate-rc={rc} comment-only={same_code!s:<5} {why}")
      print(f"{'':<20} :: {detail[:150]}")
      if name == "CONTROL":
        if rc != PASS or not same_code:
          print("  THE CONTROL IS NOT A CONTROL: it moved the gate, or it edited more than a "
                "comment.")
          bad += 1
        continue
      if rc == PASS:
        print("  THE PLANT DID NOT FIRE: the gate was green on the defect it plants.")
        bad += 1
        continue
      for token in expect:
        if token not in out:
          print(f"  THE PLANT FIRED BUT DID NOT NAME {token!r}, so a reader cannot tell which "
                f"check caught it.")
          bad += 1
    for name, text, why in shape_cases:
      probe.write_text(text)
      same_code = _code_only(pc, text) == _code_only(pc, original)
      state, cdetail = _compile(pc, probe)
      print(f"{name:<20} compile={state:<12} comment-only={same_code!s:<5} {why}")
      print(f"{'':<20} :: {cdetail[:150]}")
      if name.startswith("WRONG-SHAPE-A"):
        # THE DIRECT MEASUREMENT, AND IT IS NOT "THE FILE BROKE".  The claim is that the
        # comment DELETED THE SECOND PART, and the proof of that is the STRIPPED line: the
        # edited line must be a STRICT PREFIX of the original's, so the tail the comment
        # swallowed is simply not there.  Whether the file still compiles is a separate
        # fact about this subject, and it is printed rather than asserted -- MEASURED here:
        # an empty `case` arm breaks THIS file, where it does not break the file the
        # house's own plant uses.  Either way the comment-stripped proof catches it, and
        # the compiler is not what the proof is for.
        cut = _first_difference(_code_only(pc, original).split("\n"),
                                _code_only(pc, text).split("\n"))
        if cut is None:
          print("  THE WRONG SHAPE DID NOT MISBEHAVE: the comment-stripped code is unchanged, so "
                "it deleted nothing.")
          bad += 1
        else:
          i, before, after = cut
          if not (before.startswith(after) and len(after) < len(before)):
            print(f"  THE WRONG SHAPE DID NOT DELETE A SECOND PART: the stripped line {i + 1} went "
                  f"from {before!r} to {after!r}, and the second part is not gone.")
            bad += 1
          else:
            print(f"{'':<20} :: the second part IS gone: the stripped line {i + 1} is "
                  f"{after!r}, a strict prefix of {before!r}")
      if name.startswith("WRONG-SHAPE-B") and state != "COMPILES":
        print("  THE WRONG SHAPE BROKE THE FILE, so it is not the shape this file tolerates.")
        bad += 1
  print(f"\n=== plant: {'FAIL' if bad else 'PASS'}: {bad} problem(s) ===")
  return FAIL if bad else PASS


if __name__ == "__main__":
  sys.exit(plant())
