#!/usr/bin/env python3
"""THE COMMENT-ONLY PROOF, for a list of `.bend` files.

Every file must strip to the SAME code hash as `HEAD`, using
`checks/port-compile-gate.py`'s OWN `strip_comments()` -- LOADED BY PATH, because a
second copy of the stripper is a contract with no generator.

    .venv/bin/python .agents/slop/bendcite/comment_only.py FILE...
"""
import hashlib
import importlib.util
import subprocess
import sys
from pathlib import Path

ROOT = Path(".").resolve()
spec = importlib.util.spec_from_file_location("pcg", ROOT / "checks/port-compile-gate.py")
pcg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pcg)


def code_hash(text: str) -> str:
  """THE HASH OF THE CODE, with the blank lines dropped: a comment-only edit necessarily
  moves blank lines around, and a blank line is not code."""
  body = [ln for ln in pcg.strip_comments(text).split("\n") if ln.strip()]
  return hashlib.sha256("\n".join(body).encode()).hexdigest()


def main(files: list[str]) -> int:
  bad = 0
  for rel in files:
    live = (ROOT / rel).read_text(encoding="utf-8")
    head = subprocess.run(["git", "show", f"HEAD:{rel}"], cwd=ROOT, capture_output=True,
                          text=True, check=True).stdout
    a, b = code_hash(live), code_hash(head)
    ok = a == b
    bad += 0 if ok else 1
    print(f"{'COMMENT-ONLY ' if ok else 'CODE CHANGED '} {rel}  live={a[:16]} head={b[:16]}")
  return 1 if bad else 0


if __name__ == "__main__":
  raise SystemExit(main(sys.argv[1:]))
