#!/usr/bin/env python3
"""plant.py -- the PLANT for the UNCLAIMED slice.

**A TEXT EDIT ON A COPY** that breaks ONE re-pointed citation, and a BYTE-IDENTICAL
copy that stays green.  NEVER `git show HEAD:` -- the subject of the plant is a COPY
of the port tree ON DISK, edited as TEXT, so the plant proves the instrument reads
the tree it is pointed at.

THE CITATION CHOSEN IS DISCOVERED, NOT NAMED: the first row in this slice's own
files whose verdict is RESOLVES **BY A DECLARATION** (the cited line IS the
construct's declaration line) and whose claim came from a `symbol=` field this
slice wrote.  THE PLANT INSERTS CODE immediately above the `def`, because the
construct's span INCLUDES the comment run above it and an insertion at the TOP of
the file only shifts the declaration.

THE CONTROL IS A SECOND COPY OF THE SAME SNAPSHOT, so the two arms compare the
same tree and not two trees.
"""
import collections, importlib.util, shutil, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
WORK = Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/work")

spec = importlib.util.spec_from_file_location("bc", ROOT / "gates/bendcite-gate.py")
bc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bc)

MINE = {l.strip() for l in open(WORK / "mine.txt") if l.strip()}
SYMBOL = bc.SYMBOL_FIELD


def main() -> int:
  snap = WORK / "plant-snap"
  if snap.exists():
    shutil.rmtree(snap)
  snap.mkdir(parents=True)
  shutil.copytree(ROOT / "tinybendygrad", snap / "tinybendygrad")
  (snap / "references").mkdir()
  (snap / "references" / "bend").symlink_to(ROOT / "references" / "bend")

  base_rows, corpus = bc.census(snap)
  by = collections.Counter(r["verdict"] for r in base_rows)
  print(f"PLANT control : {dict(by)}")

  target = None
  for r in base_rows:
    if r["rel"] not in MINE or r["verdict"] != "RESOLVES":
      continue
    if "symbol=" not in r.get("line", ""):
      continue
    if not r.get("target", "").startswith("tinybendygrad/"):
      continue
    sym = None
    for m in SYMBOL.finditer(r.get("line", "")):
      sym = m.group(1)
      break
    if not sym:
      continue
    at_decl = [d for (n, d, s, e) in corpus.constructs.get(r.get("target", ""), [])
               if n == sym]
    if not at_decl or at_decl[0] != int(r["lo"]):
      continue
    target = r
    break

  if target is None:
    print("PLANT FAILED: no re-pointed row resolves BY A DECLARATION", file=sys.stderr)
    return 1

  sym = next(SYMBOL.finditer(target["line"])).group(1)
  print(f"PLANT the victim is {target['rel']}:{target['at']} -> "
        f"{target['subject']}:{target['lo']}, and the construct it names is "
        f"`{sym}` declared at {target['target']}:{target['lo']}")

  moved = WORK / "plant-moved"
  if moved.exists():
    shutil.rmtree(moved)
  shutil.copytree(snap, moved)
  victim = moved / target["target"]
  body = victim.read_text(encoding="utf-8").splitlines()
  # THE INSERTION IS CODE, NOT A COMMENT: a comment is ABSORBED into the construct's
  # DOC RUN and the row still resolves, so a comment-only plant cannot fail.
  idx = int(target["lo"]) - 1
  assert body[idx].lstrip().startswith(("def ", "type ", "law ")), body[idx]
  body.insert(idx, "def plant_probe_unused() -> U32: 0")
  victim.write_text("\n".join(body) + "\n")
  moved_rows, _ = bc.census(moved)
  after = next((r for r in moved_rows
                if r["rel"] == target["rel"] and r["at"] == target["at"]
                and r["subject"] == target["subject"] and r["lo"] == target["lo"]), None)
  print(f"PLANT control : {target['verdict']}  (the pointer holds)")
  print(f"PLANT moved   : {after['verdict'] if after else '(the row is gone)'}")
  if after is None or after["verdict"] != "WRONG-LINE":
    print("PLANT FAILED: the moved pointer did not go stale", file=sys.stderr)
    return 1
  moved_v = collections.Counter(r["verdict"] for r in moved_rows)
  print(f"PLANT control : {dict(by)}")
  print(f"PLANT moved   : {dict(moved_v)}")
  if moved_v.get("WRONG-LINE", 0) <= by.get("WRONG-LINE", 0):
    print("PLANT FAILED: the plant did not add a stale pointer", file=sys.stderr)
    return 1

  twin = WORK / "plant-twin"
  if twin.exists():
    shutil.rmtree(twin)
  shutil.copytree(snap, twin)
  twin_rows, _ = bc.census(twin)
  if [r["verdict"] for r in twin_rows] != [r["verdict"] for r in base_rows]:
    print("PLANT FAILED: the byte-identical twin did not reproduce the control",
          file=sys.stderr)
    return 1
  print("PLANT twin    : reproduces the control exactly")

  print("PLANT OK: a moved line makes the pointer stale, a byte-identical copy does not")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
