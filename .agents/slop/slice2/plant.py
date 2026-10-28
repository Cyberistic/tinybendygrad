#!/usr/bin/env python3
"""THE PLANT: a TEXT EDIT on a COPY that breaks one re-pointed citation, and a
BYTE-IDENTICAL copy that does not.

THE EDIT: `tinybendygrad/uop/ops.bend`'s re-pointed `ax_names_str` citation moves from
`ops.bend:6514 symbol=ax_names_str` back to the STALE `ops.bend:5793` -- so the pointer
no longer lands on the construct. THE CONTROL: the same file, byte for byte, with the
edit NOT applied.

The measurement is `gates/bendcite-gate.py --tree DIR`, on COPIES, because the port
tree is owned by other units and moves under the gate's feet.

**NEVER `git show HEAD:`** -- the copy is of the file ON DISK, so the arm measures the
file and not a revision of it.
"""
import importlib.util, shutil, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path("/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
SL = Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/slice2")

# THE CITATION THAT IS BROKEN, AND THE ONE THAT IS NOT.
TARGET = "tinybendygrad/uop/ops.bend"
STALE = "ops.bend:6514 symbol=ax_names_str"
FRESH = "ops.bend:5793 symbol=ax_names_str"

def build(dst: Path, edit: bool) -> None:
  """A COPY of the port tree, with the ONE edit applied or not."""
  dst.mkdir(parents=True, exist_ok=True)
  shutil.copytree(ROOT / "tinybendygrad", dst / "tinybendygrad", dirs_exist_ok=True)
  ref = ROOT / "references" / "bend" / "bend2"
  if ref.is_dir():
    (dst / "references" / "bend").mkdir(parents=True, exist_ok=True)
    shutil.copytree(ref, dst / "references" / "bend" / "bend2", dirs_exist_ok=True)
  p = dst / TARGET
  text = p.read_text()
  if edit:
    assert STALE in text, f"the stale citation {STALE!r} is not in {TARGET}"
    p.write_text(text.replace(STALE, FRESH, 1))
  return

def judge(dst: Path) -> list[dict]:
  """The gate's own rows for the CITING file, read from its own rows output."""
  out = dst / "rows.tsv"
  subprocess.run([sys.executable, str(ROOT / "gates/bendcite-gate.py"),
                  "--tree", str(dst), "--rows", str(out), "--report"],
                 cwd=ROOT, capture_output=True, text=True)
  import csv
  rows = list(csv.DictReader(open(out), delimiter="\t"))
  return [r for r in rows if r["rel"] == TARGET and r["verdict"] in ("WRONG-LINE", "DANGLING-LINE")]

with tempfile.TemporaryDirectory(prefix="slice2-plant-") as raw:
  td = Path(raw)
  build(td / "control", edit=False)
  build(td / "broken", edit=True)
  # THE BYTE-IDENTICAL COPY: the CONTROL's file, byte for byte.
  build(td / "control-copy", edit=False)
  a = (td / "control" / TARGET).read_bytes()
  b = (td / "control-copy" / TARGET).read_bytes()
  assert a == b, "the byte copy is not byte-identical"
  c = (td / "broken" / TARGET).read_bytes()
  assert a != c, "the broken copy is byte-identical to the control"

  for label in ("control", "control-copy", "broken"):
    stale = judge(td / label)
    print(f"PLANT {label:13s} {TARGET}  stale rows: {len(stale)}")
    for r in stale:
      print(f"    {r['at']}  {r['subject']}:{r['lo']}  claim={r['claim']}  {r['why'][:90]}")

  control = len(judge(td / "control"))
  copy = len(judge(td / "control-copy"))
  broken = len(judge(td / "broken"))
  print()
  if control != 0:
    print(f"PLANT FAILED: the control already has {control} stale row(s)")
    raise SystemExit(1)
  if copy != control:
    print(f"PLANT FAILED: the byte copy moved ({control} -> {copy})")
    raise SystemExit(1)
  if broken == 0:
    print("PLANT FAILED: the broken copy is still green")
    raise SystemExit(1)
  print(f"PLANT OK: the control and its byte copy are green ({control} stale rows), "
        f"and the TEXT EDIT that moves the pointer back to the stale line makes the "
        f"gate RED ({broken} stale row(s)).")
