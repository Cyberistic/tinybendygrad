#!/usr/bin/env python3
"""mixin-op-plant.py -- THE PLANT, THE CONTROL, AND THE TWO WRONG SHAPES.

    .venv/bin/python gates/mixin-op-plant.py

WHAT IT PLANTS, AND WHY IT IS THE ROW THAT HAD TO BE ADDED.

`0eee58d9d` named the gap this file closes: "AND NO ROW CAN SEE IT ... CLOSING IT
NEEDS A ROW THAT PRINTS A CONST's VALUE, WHICH NO ROW PRINTS TODAY."  The `val_*`
rows in `tinybendygrad/mixin/op.bend` are that row, and THIS is the measurement
that says they are not a label.

  PLANT   the port's DENOMINATOR CONST carries n+1 instead of n.  The VALUE ROW
          MUST MOVE -- and the SIGNATURE rows MUST NOT.  **THAT is the whole
          claim: a wrong denominator is invisible to every signature row, because
          a signature prints `CONST/0` and the payload lives in the node's ARG.**
          A plant that moved the signature rows would be planting a different
          defect; a plant that moved NOTHING would be planting nothing.

  CONTROL a comment of the same size on a one-statement line.  It must move
          NOTHING, and the proof that it moved nothing but a comment is the
          COMMENT-STRIPPED BYTES -- and that proof DROPS BLANK LINES, because a
          whole-line comment IS a blank line once the comment is gone.

  WRONG-SHAPE-A  a comment BETWEEN an opener and its first element DELETES the
          first element.  The file still COMPILES -- which is the dangerous part,
          because the compiler does not catch it -- and only the comment-stripped
          proof does.

  WRONG-SHAPE-B  a whole-line comment AT COLUMN 0 does not break a bend file.

EVERY ARM IS A TEXT EDIT ON THE WORKING TREE'S BYTES, AND NEVER A READ OF
`git show HEAD:`.  A plant that reads HEAD plants nothing the moment HEAD carries
the fix: the text it would plant would be the FIXED text, and the arm would be
green.  Three units scored green under `--falsify` for exactly that reason.

THE COPY.  Bend resolves `import ./x.bend` relative to the FILE's own directory,
so the copy sits BESIDE the original -- `tinybendygrad/mixin/op.mut.bend`, which
`.gitignore:34` already ignores -- and it is DELETED in a `finally`.  **AND IT
MATTERS FOR MORE THAN TIDINESS:** `checks/differ.py`'s `substrate_entries()`
walks `tinybendygrad/` and hashes every file it finds, so a `*.mut.bend` left
behind MOVES THE CORPUS's FRESHNESS PIN.  That is measured in this tree.

THE COMMENT-STRIPPER IS `checks/port-compile-gate.py`'s OWN, IMPORTED BY PATH.  A
second copy would be a second copy of the question, and the two would drift.
"""
import importlib.util
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from bendlock import bend_lock  # noqa: E402

BEND = ROOT / "bin" / "bend"
SUBJECT = ROOT / "tinybendygrad" / "mixin" / "op.bend"
COPY = ROOT / "tinybendygrad" / "mixin" / "op.mut.bend"

# THE PLANT: THE DENOMINATOR'S VALUE.  `mo_divn` is `x.div(n)` for a Python `int`
# `n` -- `mean`'s `denominator` and `var`'s `smax(n - correction, 0)` -- and the
# CONST it builds IS that value.
PLANT_OLD = "  mo_div(t, mo_const_t(t, mo_ki(n)))"
PLANT_NEW = "  mo_div(t, mo_const_t(t, mo_ki(U32.add(n, 1))))"

# THE CONTROL: A COMMENT OF THE SAME SIZE, ON THE SAME LINE, WHICH CARRIES ONE
# STATEMENT.  It must move NOTHING.
CONTROL_NEW = PLANT_OLD + "  # control: a comment of the same size, and no code"

# WRONG-SHAPE-A: A LINE THAT CARRIES AN OPENER AND ITS FIRST ELEMENT.  The
# comment swallows the first element, and the file still COMPILES.
SHAPE_A_OLD = '  IO.print(String.concat(["two_rules_sm=", mo_sig.of(T.Tensor.ar(a), T.Tensor.u(a)),'
SHAPE_A_NEW = '  IO.print(String.concat([  # a comment between the opener and the first element'

# WRONG-SHAPE-B: A WHOLE-LINE COMMENT AT COLUMN 0, BETWEEN A `case` ARM HEADER AND
# THE CONTINUATION OF ITS BODY.
SHAPE_B_OLD = """    case d <> +t: mo_reduced.go(t, axis, n,
      Bool.pick(U32, mo_iaxis(axis, mo_at(ds, n)), U32.mul(acc, mo_dim_u32(d)), acc))"""
SHAPE_B_NEW = """    case d <> +t: mo_reduced.go(t, axis, n,
# a comment inserted at column 0, between a case arm header and its body
      Bool.pick(U32, mo_iaxis(axis, mo_at(ds, n)), U32.mul(acc, mo_dim_u32(d)), acc))"""

# THE ROWS THE PLANT MUST MOVE, AND THE ROWS IT MUST NOT.
VALUE_ROWS = ("val_mean0", "val_mean0_2d", "val_var0")
SIGNATURE_ROWS = ("mean0", "mean0_2d", "var0", "mean0kd", "std0")


def load_port_compile():
  """`checks/port-compile-gate.py` BY PATH, for its `strip_comments()`."""
  spec = importlib.util.spec_from_file_location("port_compile", ROOT / "checks" / "port-compile-gate.py")
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


def code_only(text: str) -> str:
  """THE FILE WITH EVERY COMMENT REMOVED AND EVERY BLANK LINE DROPPED.

  The comment removal is `checks/port-compile-gate.py`'s own `strip_comments()`,
  imported by path and not re-implemented -- it is the house's stripper and it
  knows that a `#` inside a string is not a comment.  The BLANK-LINE DROP is this
  file's addition, and it is what makes the proof cover a WHOLE-LINE comment: a
  comment on its own line contributes a line that is empty once the comment is
  stripped, and comparing LINE LISTS would call that "not comment-only" -- which
  is the most comment-only edit there is.
  """
  pc = load_port_compile()
  return "\n".join(l for l in pc.strip_comments(text).split("\n") if l.strip())


def lane(path: Path):
  """THE COMPILER, UNDER THE LOCK.  `bin/bend`, never bare `bend`."""
  with bend_lock():
    return subprocess.run([str(BEND), str(path)], capture_output=True, text=True, cwd=str(ROOT))


def rows_of(text: str) -> dict:
  """{row name: row text}.  A lane's row is `<name>=<value>`."""
  out = {}
  for line in text.splitlines():
    if not line.strip():
      continue
    name, sep, _ = line.partition("=")
    if sep:
      out[name] = line
  return out


def refuse(why):
  print(f"== REFUSED, NOT A VERDICT: mixin-op-plant: {why}", file=sys.stderr)
  raise SystemExit(3)


def main() -> int:
  if not SUBJECT.is_file():
    refuse(f"{SUBJECT.relative_to(ROOT)} is absent")
  original = SUBJECT.read_text()
  for name, anchor in (("PLANT", PLANT_OLD), ("WRONG-SHAPE-A", SHAPE_A_OLD),
                        ("WRONG-SHAPE-B", SHAPE_B_OLD)):
    if anchor not in original:
      refuse(f"{name}: the anchor is not in {SUBJECT.name} as it stands. THE PLANT IS A TEXT "
             f"EDIT ON THE WORKING TREE, so an anchor that moved means the plant must be "
             f"re-anchored -- NOT that it should fall back to reading git.")

  base_run = lane(SUBJECT)
  if base_run.returncode != 0:
    refuse(f"the port does not run: {base_run.stderr.strip()[:200]}")
  base = rows_of(base_run.stdout)
  print(f"mixin-op-plant.py: the lane answers {len(base)} rows at rest; "
        f"val_mean0 = {base['val_mean0']}\n")

  cases = [
    ("PLANT", original.replace(PLANT_OLD, PLANT_NEW, 1),
     "the denominator's CONST value changed from n to n+1"),
    ("CONTROL", original.replace(PLANT_OLD, CONTROL_NEW, 1),
     "a comment of the same size on a one-statement line"),
    ("WRONG-SHAPE-A", original.replace(SHAPE_A_OLD, SHAPE_A_NEW, 1),
     "a comment between an opener and its first element DELETES the element"),
    ("WRONG-SHAPE-B", original.replace(SHAPE_B_OLD, SHAPE_B_NEW, 1),
     "a whole-line comment at column 0, between a case arm header and its body"),
  ]

  bad = 0
  for name, text, why in cases:
    COPY.write_text(text)
    try:
      run = lane(COPY)
    finally:
      COPY.unlink(missing_ok=True)
    compiled = run.returncode == 0
    rows = rows_of(run.stdout) if compiled else {}
    moved = sorted(n for n, t in rows.items() if base.get(n) != t)
    gone = sorted(n for n in base if n not in rows)
    same_code = code_only(text) == code_only(original)
    print(f"{name:<14} compiled={compiled!s:<5} comment-only={same_code!s:<5} "
          f"moved={len(moved)} gone={len(gone)}  {why}")
    if moved:
      print(f"{'':<14} :: moved: {', '.join(moved[:8])}{' ...' if len(moved) > 8 else ''}")
    if name == "PLANT":
      if not compiled:
        print("  THE PLANT DID NOT COMPILE: it planted nothing.")
        bad += 1
      elif not all(r in moved for r in VALUE_ROWS):
        print(f"  THE PLANT DID NOT MOVE THE VALUE ROWS: {VALUE_ROWS} must move, and "
              f"{sorted(set(VALUE_ROWS) - set(moved))} did not. A value row that cannot see a "
              f"wrong value is a label.")
        bad += 1
      elif any(r in moved for r in SIGNATURE_ROWS):
        print(f"  THE PLANT MOVED A SIGNATURE ROW: {sorted(set(SIGNATURE_ROWS) & set(moved))}. "
              f"The claim is that a wrong DENOMINATOR moves the VALUE row and NO signature row, "
              f"because a signature prints `CONST/0` and not the payload.")
        bad += 1
      else:
        print(f"  THE PLANT FIRED: the value row moved ({', '.join(VALUE_ROWS)}) and NO signature "
              f"row moved ({', '.join(SIGNATURE_ROWS)}). That is the claim: the denominator's "
              f"VALUE was invisible to every signature row before this row existed.")
        print(f"  :: at rest   {base['val_mean0']}")
        for r in VALUE_ROWS:
          if r in rows:
            print(f"  :: planted   {rows[r]}")
    if name == "CONTROL":
      if not compiled:
        print("  THE CONTROL IS NOT A CONTROL: the file did not compile.")
        bad += 1
      elif moved or gone:
        print(f"  THE CONTROL IS NOT A CONTROL: it moved {len(moved)} row(s) and lost "
              f"{len(gone)}.")
        bad += 1
      elif not same_code:
        print("  THE CONTROL IS NOT A CONTROL: it edited more than a comment.")
        bad += 1
      else:
        print("  THE CONTROL HELD: nothing moved, and the comment-stripped bytes are the same.")
    if name == "WRONG-SHAPE-A":
      if same_code:
        print("  THE WRONG SHAPE DID NOT MISBEHAVE: it was comment-only after all, so it is not "
              "a demonstration of anything.")
        bad += 1
      else:
        print(f"  THE WRONG SHAPE MISBEHAVED, and the comment-stripped proof CAUGHT IT: "
              f"compiled={compiled}, {len(moved)} row(s) moved. The compiler did not catch it"
              + ("" if compiled else " either -- but the proof did, which is the point."))
    if name == "WRONG-SHAPE-B":
      if not same_code:
        print("  THE WRONG SHAPE IS NOT COMMENT-ONLY, so it is not the shape this file tolerates.")
        bad += 1
      elif not compiled:
        print("  THE WRONG SHAPE BROKE THE FILE, so it is not the shape this file tolerates.")
        bad += 1
      else:
        print(f"  THE WRONG SHAPE IS TOLERATED: it compiled and moved nothing "
              f"({len(moved)} row(s)).")

  print(f"\n=== plant: {'FAIL' if bad else 'PASS'}: {bad} problem(s) ===")
  return 1 if bad else 0


if __name__ == "__main__":
  sys.exit(main())
