"""A THROW-AWAY CHECKER. It re-census's the LIVE tree and prints the rows for the
files in the slice, so an edit's effect is measured, not guessed."""
import csv, subprocess, sys, collections
from pathlib import Path

BASE = Path(__file__).resolve().parents[3]
OUT = BASE / ".agents/slop" / "unclaimed3" / "now.rows"
subprocess.run([sys.executable, "gates/bendcite-gate.py", "--rows", str(OUT),
                "--report"], cwd=BASE, stdout=subprocess.DEVNULL, check=False)
rows = list(csv.DictReader(OUT.open(), delimiter="\t"))
slice_files = sorted({l.split("\t")[0] for l in
                      Path("/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/slices/unclaimed3.rows")
                      .read_text().split("\n")[1:] if l.strip()})
c = collections.Counter(r["verdict"] for r in rows)
print("TREE-WIDE:", dict(c))
mine = [r for r in rows if r["rel"] in slice_files]
cm = collections.Counter(r["verdict"] for r in mine)
print("MY 18 FILES:", dict(cm))
print("  UNCLAIMED in my files:", sum(1 for r in mine if r["verdict"] == "UNCLAIMED"))
print("  BAD (WRONG-LINE/DANGLING/ABSENT) in my files:",
      sum(1 for r in mine if r["verdict"] in ("WRONG-LINE", "DANGLING-LINE", "ABSENT-FILE")))
want = sys.argv[1] if len(sys.argv) > 1 else ""
for r in mine:
  if r["verdict"] == "RESOLVES":
    continue
  if want and want not in r["rel"]:
    continue
  print(f"  {r['verdict']:20s} {r['rel']}:{r['at']} -> {r['subject']}:{r['lo']}-{r['hi']}"
        f"  tier={r['tier']}  at={r['at_line']}  claims={r['claim'][:90]}")
  print(f"      why: {r['why'][:250]}")
  print(f"      line: {r['line'][:150]}")
