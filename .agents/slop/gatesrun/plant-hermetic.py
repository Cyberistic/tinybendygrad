#!/usr/bin/env python3
"""PLANTS for the `hermetic-census.py` TODO. The change is a COMMENT (a latent `.txt` write
flagged, not renamed), so a red/green on the gate's subject is not available. What IS
checkable is the claim the comment makes, in three parts, each a measurement:

  A. ORDERING -- the module-level `refuse()` that exits 3 sits ABOVE both `.txt` sites, so
     the write is unreachable at import. Read off the AST, not off line numbers typed by hand.
  B. STILL REFUSED -- running the file exits 3 and names `isolate.py`; the change is INERT.
  C. UNREACHABLE TWICE -- a copy with the refusal block REMOVED still does not reach the
     write: it dies at `import isolate`. So the guard is not the only thing protecting it,
     which is why the `.txt` is latent and not merely guarded.
"""
from __future__ import annotations
import ast
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
SRC = ROOT / "checks" / "hermetic-census.py"
OK = []


def check(name, cond, detail):
    OK.append(bool(cond))
    print(f"  {'PASS' if cond else 'FAIL'}  {name}: {detail}")


def main():
    src = SRC.read_text()
    tree = ast.parse(src)

    exits = [n.lineno for n in ast.walk(ast.Module(body=tree.body, type_ignores=[]))
             if isinstance(n, ast.Call) and getattr(n.func, "id", "") == "refuse"]
    txt = [i for i, l in enumerate(src.splitlines(), 1)
           if ".txt" in l and not l.lstrip().startswith("#")]
    check("A ordering", exits and txt and max(exits) < min(txt),
          f"module-level refuse() at {sorted(exits)}, .txt sites at {txt}")

    r = subprocess.run([str(ROOT / ".venv/bin/python"), str(SRC)],
                       cwd=ROOT, capture_output=True, text=True)
    check("B still refused", r.returncode == 3 and "isolate.py" in r.stderr,
          f"rc={r.returncode}, names isolate.py={'isolate.py' in r.stderr}")

    # C -- strip the isolate refusal (the three-line block), keep everything else, and run.
    body = re.sub(r"if not any\(p\.is_file\(\).*?cannot produce a denominator without it\.\"\)\n",
                  "", src, flags=re.S)
    check("C guard removed", body != src, "isolate refusal block removed on the copy")
    # The copy must sit where `HERE.parents[0]` IS the repo root (a tempdir does not), or the
    # REPO marker refuses first and the plant measures the wrong guard. `checks/` satisfies it.
    c = ROOT / "checks" / "zz-tmp-hermetic-census.py"
    try:
        c.write_text(body)
        r2 = subprocess.run([str(ROOT / ".venv/bin/python"), str(c)],
                            cwd=ROOT, capture_output=True, text=True)
        reached = "rows-{name}" in r2.stdout
        check("C unreachable twice",
              r2.returncode != 0 and not reached and "isolate" in r2.stderr,
              f"rc={r2.returncode}, wrote rows? {reached}, "
              f"err={(r2.stderr.strip().splitlines() or ['-'])[-1][:70]}")
    finally:
        c.unlink(missing_ok=True)

    print(f"PLANTS {'GREEN' if all(OK) else 'RED'} ({sum(OK)}/{len(OK)})")
    return 0 if all(OK) else 1


if __name__ == "__main__":
    sys.exit(main())
