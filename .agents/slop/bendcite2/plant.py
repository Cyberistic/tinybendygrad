#!/usr/bin/env python3
"""THE PLANT: a TEXT EDIT on a COPY that breaks ONE re-pointed citation, and a
byte-identical copy that does not.

  .venv/bin/python .agents/slop/bendcite2/plant.py <root>

**THE COPY IS OF THE LIVE TREE, NOT `git show HEAD:`** -- the tree moves under the
gate's feet, and a copy taken from git would prove it reads a tree nobody works on.

THE PLANTED EDIT: `tinybendygrad/nn/argmax.bend` cites `uop/fold.bend:4764 symbol=fold.shape`.
A COPY of `uop/fold.bend` with ONE LINE INSERTED ABOVE `fold.shape` moves the
declaration, so the pointer at :4764 now lands on the line before the construct, and
the claim the pointer makes is no longer TRUE OF THAT LINE. **THE PLANT IS A TEXT
EDIT ON A COPY** -- the live tree is not touched.
"""
import importlib.util
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("bc", ROOT / "gates" / "bendcite-gate.py")
bc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bc)

PORT_REL = "tinybendygrad"
COMPILER_REL = "references/bend/bend2"

#: THE CITATION THE PLANT BREAKS: (citing file, citing line, subject, lo).
PLANT = ("tinybendygrad/nn/argmax.bend", 179, "uop/fold.bend", 4764)
#: THE FILE THE PLANT EDITS, AND THE LINE IT INSERTS ABOVE.
VICTIM = "tinybendygrad/uop/fold.bend"


def census(base: Path) -> list[dict]:
  rows, _corpus = bc.census(base)
  return rows


def find(rows: list[dict], rel: str, at: int, subject: str, lo: int) -> dict | None:
  for r in rows:
    if r["rel"] == rel and r["at"] == at and r["subject"] == subject and r["lo"] == lo:
      return r
  return None


def main() -> int:
  base = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT
  rel, at, subject, lo = PLANT
  with tempfile.TemporaryDirectory(prefix="bendcite-plant-") as raw:
    td = Path(raw)

    # ---- THE CONTROL: a copy of the live tree, byte-identical.
    control = td / "control"
    control.mkdir()
    shutil.copytree(base / PORT_REL, control / PORT_REL)
    if (base / COMPILER_REL).is_dir():
      (control / COMPILER_REL).parent.mkdir(parents=True, exist_ok=True)
      shutil.copytree(base / COMPILER_REL, control / COMPILER_REL)
    control_rows = census(control)
    c_row = find(control_rows, rel, at, subject, lo)
    print(f"PLANT control  : {c_row['verdict'] if c_row else '(the row is gone)'}"
          f"  -- {c_row['why'][:110] if c_row else ''}")

    # ---- THE PLANT: a TEXT EDIT on a COPY, inserting one line above the construct.
    moved = td / "moved"
    moved.mkdir()
    shutil.copytree(base / PORT_REL, moved / PORT_REL)
    if (base / COMPILER_REL).is_dir():
      (moved / COMPILER_REL).parent.mkdir(parents=True, exist_ok=True)
      shutil.copytree(base / COMPILER_REL, moved / COMPILER_REL)
    victim = moved / VICTIM
    body = victim.read_text(encoding="utf-8").splitlines()
    # THE LINE THE PLANT INSERTS IS ABOVE THE CLAIMED CONSTRUCT'S DECLARATION.
    decl = None
    for name, d, s, e in bc.bend_constructs(body):
      if name == "fold.shape":
        decl = d
    if decl is None:
      print("PLANT REFUSED: the copy has no `fold.shape` to move", file=sys.stderr)
      return 3
    # **THE INSERTED LINE IS CODE, NOT A COMMENT**, and that is load-bearing: a
    # construct's span INCLUDES the comment run above its `def`, so a COMMENT
    # inserted above the def EXTENDS the span and the pointer still lands inside
    # it. A CODE line does not extend the span -- it is what a unit editing the
    # port actually does -- and the pointer at :4764 falls out of the construct.
    body.insert(decl - 1, "PLANT_MARKER_LINE")
    victim.write_text("\n".join(body) + "\n", encoding="utf-8")
    moved_rows = census(moved)
    m_row = find(moved_rows, rel, at, subject, lo)
    print(f"PLANT moved    : {m_row['verdict'] if m_row else '(the row is gone)'}"
          f"  -- {m_row['why'][:150] if m_row else ''}")

    # ---- THE TWIN: a byte-identical copy of the CONTROL.
    twin = td / "twin"
    twin.mkdir()
    shutil.copytree(base / PORT_REL, twin / PORT_REL)
    if (base / COMPILER_REL).is_dir():
      (twin / COMPILER_REL).parent.mkdir(parents=True, exist_ok=True)
      shutil.copytree(base / COMPILER_REL, twin / COMPILER_REL)
    same = all((control / p).read_bytes() == (twin / p).read_bytes()
               for p in (PORT_REL + "/uop/fold.bend", PORT_REL + "/nn/argmax.bend"))
    twin_rows = census(twin)
    t_row = find(twin_rows, rel, at, subject, lo)
    print(f"PLANT twin     : {t_row['verdict'] if t_row else '(the row is gone)'}"
          f"  byte-identical={same}")

    bad = []
    if not c_row or c_row["verdict"] != "RESOLVES":
      bad.append(f"the control did not resolve: {c_row['verdict'] if c_row else '(gone)'}")
    if not m_row or m_row["verdict"] == "RESOLVES":
      bad.append(f"the moved pointer did not go red: {m_row['verdict'] if m_row else '(gone)'}")
    if not same or not t_row or t_row["verdict"] != c_row["verdict"]:
      bad.append("the byte-identical twin did not reproduce the control")
    if bad:
      print("PLANT FAILED: " + "; ".join(bad), file=sys.stderr)
      return 1
    print("PLANT OK: a moved line makes the re-pointed pointer stale, a byte-identical "
          "copy does not, and the control reproduces.")
    return 0


if __name__ == "__main__":
  raise SystemExit(main())
