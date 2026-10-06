"""Hash the PY side's 25 graphs under the ambient environment.

TWO numbers, because ONE conflates two different answers and this file exists because a
figure that answers a question nobody asked is not a measurement:

  the HASH is over the ROW-SHAPED lines only (`^<int>:<int> `, graphcmp's 8-chunk form).
  A flag that changes it CHANGED THE COMPARISON'S INPUTS.

  the CONTAMINATION COUNT is every other line on stdout.  MEASURED WHY IT IS SEPARATE:
  `DEBUG=1` makes tinygrad print `opened device CPU` and the differ redirects the child's
  STDOUT straight into the artifact (`checks/differ.py:452`), so a DEBUG left in the ambient
  environment lands in `D2-canon-py-*.txt` and every byte-identity verdict after it.  That
  is a verdict-moving precondition too, but it is NOT "the rows changed", and an earlier
  version of this sweep counted it as if it were and named three flags that do not move the
  comparison at all.
"""
import hashlib
import importlib.util
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
_spec = importlib.util.spec_from_file_location("gcmp", str(ROOT / ".agents/slop/graphcmp.py"))
gc = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(gc)
gc.load_tinygrad()
ROW = re.compile(r"^\d+:")   # graphcmp's chunk form is `<len>:<len chars>`, so the second
                            # chunk's payload STARTS WITH AN ATOM LETTER (`2:i1`), never a
                            # digit.  `^\d+:\d+ ` -- the obvious spelling -- matches NOTHING
                            # and would have hashed 312 rows as 0.  MEASURED, not assumed.
h, noise, n_rows = hashlib.sha256(), 0, 0
for g in sorted(gc.GRAPHS):
    for ln in gc.emit_py(g, None):
        if ROW.match(ln):
            h.update(ln.encode())
            h.update(b"\0")
            n_rows += 1
        else:
            noise += 1
    h.update(g.encode())
    h.update(b"\0")
sys.stdout.write(f"{h.hexdigest()} rows={n_rows} nonrows={noise}\n")
