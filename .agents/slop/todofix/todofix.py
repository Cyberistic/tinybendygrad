#!/usr/bin/env python3
"""todofix.py -- move a stale `file:line` citation to the line the gate found it on.

    .venv/bin/python .agents/slop/todofix/todofix.py [--apply]

THE ORACLE IS `gates/todo-cite-gate.py` AND IT IS NOT MINE. This script does not decide what
is true; it reads the gate's own rows (`file:line  cited:line  ...  how=...  is declared at
:N`) and rewrites the CITED number in the NAMED source line. Then the gate is run again and
the count is compared -- a rewrite the gate does not accept is a rewrite that did not happen.

THREE REFUSALS, because a script that edits 290 lines in a port this size must be narrow:
  * only `how=` classes whose row carries the corrected line (symbol-moved, snippet-moved,
    symbol-out-of-range). The judgement classes (`no-symbol`, `symbol-absent`,
    `symbol-vs-snippet`, `no-file`) are PRINTED AND LEFT ALONE.
  * only a line that already carries a citation marker (`TODO(`, `WALL(`, `PORTED`,
    `symbol=`). A rewrite that lands on code is refused, counted, and named.
  * only the FIRST occurrence of `basename:old`, so a line citing two lines of one file moves
    one of them per pass. The gate decides whether it moved.
"""
import re
import subprocess
import sys
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
GATE = ROOT / "gates" / "todo-cite-gate.py"
ROW = re.compile(r"^ {2}(\S+):(\d+) {2}(\S+):(\d+) {2}(.*)$")
FIXABLE = {"symbol-moved", "snippet-moved", "symbol-out-of-range"}
MARKER = ("TODO(", "WALL(", "PORTED", "symbol=", "DONE(")


def run_gate() -> tuple[str, Counter]:
  out = subprocess.run([str(ROOT / ".venv" / "bin" / "python"), str(GATE)],
                       cwd=ROOT, capture_output=True, text=True)
  text = out.stdout + out.stderr
  rows = Counter()
  for line in text.splitlines():
    m = ROW.match(line)
    if not m:
      continue
    body = m.group(5)
    how = (re.search(r"how=([a-z-]+)", body) or [None, "?"])[1] if "how=" in body else "?"
    rows[how] += 1
  return text, rows


def plan(text: str) -> list[tuple[Path, int, str, int, int]]:
  """(file, lineno, cited basename, old line, new line) for the fixable rows."""
  todo: list[tuple[Path, int, str, int, int]] = []
  for line in text.splitlines():
    m = ROW.match(line)
    if not m:
      continue
    f, ln, cited, old, body = m.group(1), int(m.group(2)), m.group(3), int(m.group(4)), m.group(5)
    how = (re.search(r"how=([a-z-]+)", body) or [None, None])[1]
    if how not in FIXABLE:
      continue
    at = re.search(r"(?:declared|snippet is) at :(\d+)", body)
    if not at:
      continue
    todo.append((ROOT / f, ln, Path(cited).name, old, int(at.group(1))))
  return todo


def main() -> int:
  apply = "--apply" in sys.argv
  text, before = run_gate()
  todo = plan(text)
  print(f"before: {sum(before.values())} rows  {dict(before)}")
  print(f"planned: {len(todo)} citation moves")

  refused, done = [], 0
  for path, lineno, base, old, new in todo:
    lines = path.read_text().splitlines(keepends=True)
    src = lines[lineno - 1]
    if not any(mk in src for mk in MARKER):
      refused.append(f"{path.relative_to(ROOT)}:{lineno} -- no citation marker")
      continue
    needle = f"{base}:{old}"
    if needle not in src:
      refused.append(f"{path.relative_to(ROOT)}:{lineno} -- no {needle!r}")
      continue
    lines[lineno - 1] = src.replace(needle, f"{base}:{new}", 1)
    done += 1
    if apply:
      path.write_text("".join(lines))
  print(f"rewritten: {done}  refused: {len(refused)}")
  for r in refused[:10]:
    print(f"  REFUSED {r}")
  if not apply:
    print("(dry run -- pass --apply)")
    return 0
  text, after = run_gate()
  print(f"after: {sum(after.values())} rows  {dict(after)}")
  return 0 if sum(after.values()) < sum(before.values()) else 1


if __name__ == "__main__":
  sys.exit(main())
