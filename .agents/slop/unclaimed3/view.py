"""A THROW-AWAY VIEWER. It prints each UNCLAIMED row of the slice with the citing
line, the citing comment BLOCK, the cited file's line(s), and the constructs the
cited file declares near the cited line."""
import csv, sys, importlib.util
from pathlib import Path

BASE = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("bc", BASE / "gates" / "bendcite-gate.py")
bc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(bc)
C = bc.Corpus(BASE)

SLICE = Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/slices/unclaimed3.rows")

rows = list(csv.DictReader(SLICE.open(), delimiter="\t"))
want = sys.argv[1] if len(sys.argv) > 1 else ""
for r in rows:
  if want and want not in r["rel"]:
    continue
  print("=" * 100)
  print(f"ROW {r['rel']}:{r['at']}  ->  {r['subject']}:{r['lo']}-{r['hi']}")
  print(f"  target={r['target']}  at_line={r['target']!r} decl={r['decl']} delta={r['delta']}")
  print(f"  claim={r['claim'][:400]}")
  body = C.bodies[r["rel"]]
  at = int(r["at"])
  print(f"  --- citing line {at}:")
  print(f"    {body[at-1]}")
  print(f"  --- cited {r['target']}:{r['lo']}-{r['hi']}:")
  tb = C.bodies[r["target"]]
  lo, hi = int(r["lo"]), int(r["hi"])
  for i in range(max(1, lo - 4), min(len(tb), hi + 4) + 1):
    mark = ">>" if lo <= i <= hi else "  "
    print(f"   {mark}{i:6d}| {tb[i-1]}")
  print("  --- constructs of target near the pointer:")
  for n, d, s, e in C.constructs[r["target"]]:
    if abs(d - lo) < 60 or (s <= lo <= e):
      print(f"     {n:40s} decl={d:6d} span={s}-{e}")
