#!/usr/bin/env python3
"""THE COMMENT-ONLY PROOF, BY THE GATE's OWN `strip_comments()` (loaded BY PATH).

Every file this unit touched must strip to the SAME code hash as `HEAD`, blank lines
dropped -- EXCEPT the files whose edit is inside a `D.refuse("...")` PAYLOAD, which is
a STRING LITERAL and not a comment. Those are listed separately and said so out loud.

  .venv/bin/python .agents/slop/bendcite2/commentonly.py
"""
import hashlib
import importlib.util
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("pcg", ROOT / "checks" / "port-compile-gate.py")
pcg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pcg)


def code_hash(text: str) -> str:
  """The code with the comments gone and the blank lines dropped."""
  body = pcg.strip_comments(text)
  lines = [ln.rstrip() for ln in body.split("\n")]
  return hashlib.sha256("\n".join(ln for ln in lines if ln.strip()).encode()).hexdigest()


def head_text(rel: str) -> str:
  return subprocess.run(["git", "show", f"HEAD:{rel}"], cwd=ROOT, check=True,
                        capture_output=True, text=True).stdout


def main() -> int:
  sys.path.insert(0, str(ROOT / ".agents" / "slop" / "bendcite2"))
  import patch
  import patch_inception
  edited = sorted({rel for rel, _, _ in patch.EDITS}
                   | {"tinybendygrad/extra/models/inception.bend"})
  # THE `D.refuse("...")` FILES: the edit is INSIDE A STRING LITERAL.
  payload = {"tinybendygrad/extra/models/inception.bend"}
  bad = 0
  for rel in edited:
    live = (ROOT / rel).read_text(encoding="utf-8")
    h = head_text(rel)
    same_code = code_hash(live) == code_hash(h)
    same_lines = len(live.splitlines()) == len(h.splitlines())
    if rel in payload:
      print(f"PAYLOAD {rel}: code-hash-same={same_code} lines-same={same_lines}"
            "   (the edit is inside a `D.refuse(\"...\")` STRING LITERAL -- NOT a comment)")
      continue
    if not same_code:
      bad += 1
      print(f"NOT-COMMENT-ONLY {rel}: code hash differs")
    elif not same_lines:
      bad += 1
      print(f"LINE-COUNT CHANGED {rel}: {len(h.splitlines())} -> {len(live.splitlines())}")
    else:
      print(f"COMMENT-ONLY {rel}: code-hash same, {len(live.splitlines())} lines")
  print(f"NON-COMMENT-ONLY FILES: {bad}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
