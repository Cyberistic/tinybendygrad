"""THE COMMENT-ONLY PROOF, for the `D.refuse(...)` PAYLOAD files.

`checks/port-compile-gate.py`'s `strip_comments()` blanks a STRING LITERAL by
SPACES, so a payload whose TEXT changed shows up as a length difference in the
blanked region even though no code changed. THIS compares the PURE CODE: the
file with every comment AND every string literal removed, whitespace normalised.
"""
import re, subprocess, sys
from pathlib import Path

BASE = Path(__file__).resolve().parents[3]


def pure_code(text: str) -> list[str]:
  """The file with comments and string literals REMOVED, one entry per code line."""
  out = []
  for ln in text.split("\n"):
    buf, i, in_str = [], 0, False
    while i < len(ln):
      ch = ln[i]
      if in_str:
        if ch == "\\":
          i += 2
          continue
        if ch == '"':
          in_str = False
        i += 1
        continue
      if ch == '"':
        in_str = True
        i += 1
        continue
      if ch == "#":
        break
      buf.append(ch)
      i += 1
    s = "".join(buf).strip()
    if s:
      out.append(s)
  return out


ok = True
for rel in sys.argv[1:]:
  live = (BASE / rel).read_text(encoding="utf-8")
  head = subprocess.run(["git", "show", f"HEAD:{rel}"], cwd=BASE,
                        capture_output=True, text=True, check=True).stdout
  a, b = pure_code(live), pure_code(head)
  same = a == b
  print(f"{'SAME  ' if same else 'DIFFER'}  {rel}   pure code lines: {len(a)}")
  if not same:
    ok = False
    import difflib
    for d in list(difflib.unified_diff(b, a, "HEAD", "WORK", lineterm=""))[:20]:
      print("   ", d)
print("PURE CODE IDENTICAL" if ok else "PURE CODE DIFFERS")
