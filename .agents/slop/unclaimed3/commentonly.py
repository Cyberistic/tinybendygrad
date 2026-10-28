"""THE COMMENT-ONLY PROOF. It imports `checks/port-compile-gate.py`'s
`strip_comments()` BY PATH and compares the stripped code of the WORKING TREE
against `HEAD` for every file the unit touched.

`git show HEAD:<path>` is NOT used for the TREE; it is used for the BASE, which
is what the proof compares against, and the proof is about the WORKING TREE.
"""
import subprocess, sys, importlib.util
from pathlib import Path

BASE = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("pcg", BASE / "checks" / "port-compile-gate.py")
pcg = importlib.util.module_from_spec(spec)
spec.loader.exec_module(pcg)

paths = sys.argv[1:]
ok = True
for rel in paths:
  live = (BASE / rel).read_text(encoding="utf-8")
  head = subprocess.run(["git", "show", f"HEAD:{rel}"], cwd=BASE,
                        capture_output=True, text=True, check=True).stdout
  a = [l for l in pcg.strip_comments(live).split("\n") if l.strip()]
  b = [l for l in pcg.strip_comments(head).split("\n") if l.strip()]
  same = a == b
  # A `D.refuse("...")` PAYLOAD is a STRING, so `strip_comments` blanks it and the
  # hash cannot see it. Those files are reported SEPARATELY.
  payload_diff = live != head
  has_refuse = "D.refuse(" in live
  print(f"{'SAME  ' if same else 'DIFFER'}  {rel}"
        + ("   [carries a D.refuse payload]" if has_refuse else ""))
  if not same:
    ok = False
    import difflib
    for d in list(difflib.unified_diff(b, a, "HEAD", "WORK", lineterm=""))[:20]:
      print("   ", d)
print("ALL COMMENT-ONLY" if ok else "SOME FILES CHANGED CODE")
