#!/usr/bin/env python3
"""The port's spec-lane deltas AT A GIVEN `spec.bend`, so a BEFORE and an AFTER are measured
by the SAME instrument.

    .venv/bin/python .agents/slop/speclen/deltas-at.py <spec.bend> [--sections 2,3,6]

WHY THIS EXISTS. `gates/specshadow-map.py` and `gates/specreach-gate.py` both read the port's
`tinybendygrad/uop/spec.bend` BY A HARD-CODED PATH, and the tree's `spec.bend` is under active
edit by another unit -- so a "before" reading taken from the working copy is a reading of the
other unit's work, not of the revision under test. This file asks the SAME instrument about a
DIFFERENT subject, so the two readings differ only in the subject.

THE INSTRUMENTS ARE THE TREE's OWN, NOT COPIES.
  * the deltas: `gates/specshadow-map.py`'s SOURCE is read and its `BEND = ...` line is
    re-pointed at the subject, then exec'd. The map has no `__main__` guard (it raises
    SystemExit at import), so it CANNOT be imported -- re-pointing the source is the only way
    to reuse it, and a re-typed comparison would be a second copy of the question.
  * the tag spaces: `gates/specreach-gate.py` HAS a `__main__` guard, so it is imported by
    path and its module-global `SPEC` is re-pointed. Its `tag_spaces()` re-derives the three
    spellings of every block base FROM THE TABLE SIZES, which is exactly the arithmetic that
    has to be checked.

NOTHING IN THE TREE IS WRITTEN. The subject is a file the caller supplies.
"""
import contextlib
import importlib.util
import io
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent.parent


def _map_run(spec_path: Path) -> str:
  """The map's output, with `BEND` re-pointed at `spec_path`.

  The map's SOURCE is exec'd IN-PROCESS -- not copied to a file -- so `__file__` keeps
  pointing at the real map and `ROOT` (which is derived from it) stays the tree's root.
  """
  src = (ROOT / "gates" / "specshadow-map.py").read_text()
  patched, n = re.subn(r'^BEND = ROOT / "tinybendygrad" / "uop" / "spec\.bend"$',
                       f'BEND = Path("{spec_path}")', src, flags=re.M)
  if n != 1:
    raise SystemExit(f"REFUSED: the map's BEND line was not found ({n} matches) -- the map moved")
  ns = {"__name__": "specshadow_map_at",
        "__file__": str(ROOT / "gates" / "specshadow-map.py")}
  buf = io.StringIO()
  old_argv = sys.argv
  sys.argv = ["specshadow-map.py", "--deltas"]
  try:
    with contextlib.redirect_stdout(buf):
      exec(compile(patched, "<specshadow-map.py@subject>", "exec"), ns)
  except SystemExit:
    pass
  except Exception as exc:  # a section that cannot read an OLD subject still leaves 1-6 printed
    buf.write(f"# (the map raised after section 6: {type(exc).__name__}: {exc})\n")
  finally:
    sys.argv = old_argv
  return buf.getvalue()


def _tag_spaces(spec_path: Path) -> list[str]:
  """`gates/specreach-gate.py`'s `tag_spaces()`, with its subject re-pointed."""
  spec = importlib.util.spec_from_file_location("specreach_gate_at",
                                                ROOT / "gates" / "specreach-gate.py")
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  mod.SPEC = spec_path
  return mod.tag_spaces()


def main() -> int:
  if len(sys.argv) < 2:
    print(__doc__)
    return 2
  subject = Path(sys.argv[1]).resolve()
  out = _map_run(subject)
  print(f"# ===== SUBJECT: {subject} =====")
  keep = ("# 1.", "# 2.", "# 3.", "# 4.", "# 5.", "# 6.")
  printing = False
  for line in out.splitlines():
    if line.startswith(keep):
      printing = True
    elif line.startswith("# 6b.") or line.startswith("# 6c."):
      printing = False
    if printing:
      print(line)
  print("# --- the tag spaces, re-derived from the table sizes ---")
  problems = _tag_spaces(subject)
  if not problems:
    print("tag_spaces: 0 problem(s)")
  for p in problems:
    print(f"  {p}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
