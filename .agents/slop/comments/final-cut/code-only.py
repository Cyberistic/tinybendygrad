#!/usr/bin/env python3
"""**THE **CODE-ONLY **CHECK**: **A **COMMENT-ONLY **CUT **MUST **NOT **TOUCH **THE **CODE**.

**⇒⇒† AND **THE **NAIVE **CHECK **IS **MISLEADING**: **`git diff | grep -E "^[+-]" | grep -vE
"^[+-]\\s*#"`** **PRINTS **A **BARE **`-`** **AND **A **BARE **`+`** **WHEN **A **BLANK **LINE **MOVES
**BETWEEN **TWO **HUNKS**, **⇒⇒† AND **THAT **IS **A **DIFF **RENDERING **ARTIFACT** **AND **NOT **A
**CHANGE **TO **THE **FILE**.

**⇒⇒† AND **SO **THE **CHECK **THIS **TOOL **DOES **IS **THE **ONE **THAT **CANNOT **BE
**MISLED**: **IT **COMPARES **THE **CODE **LINES **AND **THE **BLANK-LINE **COUNT** **OF **HEAD
**AGAINST **THE **WORKTREE**, **⇒⇒† AND **IT **PRINTS **THE **FIRST **DIFFERING **LINE** **IF
**THERE **IS **ONE**.

    .venv/bin/python .agents/slop/comments/final-cut/code-only.py <file> [...]
    .venv/bin/python .agents/slop/comments/final-cut/code-only.py --against HEAD~1 <file> [...]
"""

import pathlib
import subprocess
import sys


def read(rev: str, path: str) -> str:
  if rev:
    out = subprocess.run(["git", "show", f"{rev}:{path}"], capture_output=True, text=True)
    if out.returncode != 0:
      raise SystemExit(f"cannot read {rev}:{path}: {out.stderr}")
    return out.stdout
  return pathlib.Path(path).read_text()


def main() -> None:
  args = sys.argv[1:]
  rev = "HEAD"
  if args and args[0].startswith("--against="):
    rev = args[0].split("=", 1)[1]
    args = args[1:]
  elif args and args[0] == "--against":
    rev = args[1]
    args = args[2:]
  bad = 0
  for path in args:
    old = read(rev, path)
    new = read("", path)
    old_code = [l for l in old.split("\n") if not l.strip().startswith("#")]
    new_code = [l for l in new.split("\n") if not l.strip().startswith("#")]
    old_blank = sum(1 for l in old.split("\n") if l == "")
    new_blank = sum(1 for l in new.split("\n") if l == "")
    ok = old_code == new_code and old_blank == new_blank
    print(f"{'OK  ' if ok else 'FAIL'} {path}: code {len(old_code)}->{len(new_code)} "
          f"blank {old_blank}->{new_blank}")
    if not ok:
      bad += 1
      if old_code != new_code:
        import difflib
        for line in list(difflib.unified_diff(old_code, new_code, "HEAD", "NOW", lineterm=""))[:40]:
          print("   ", line)
      else:
        print(f"    THE BLANK-LINE COUNT MOVED: {old_blank} -> {new_blank}")
  print(f"\nTHE FILES THAT ARE NOT COMMENT-ONLY: {bad}")
  raise SystemExit(1 if bad else 0)


if __name__ == "__main__":
  main()
