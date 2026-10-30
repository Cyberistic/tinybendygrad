#!/usr/bin/env python3
"""THE COVERAGE TABLE -- THREE INSTRUMENTS, THREE SUBJECTS, ONE TREE.

  (1) OP LEVEL     -- the corpus's OWN census (`runs/graphcmp/D/D0-coverage-census.txt`):
                     how many of upstream's 75 `Ops` enum members does a graph reach?
  (2) BEND, DEF    -- the port's `.bend` defs the corpus's bend lane REACHES.  Measured by
                     a static call graph over DEF BODIES (`reach4.py`), seeded from the
                     harness's own defs.  A def counts as reached only when a call site
                     INSIDE A REACHED DEF names it.
  (3) PY, FUNCTION  -- upstream `tinygrad/*.py` functions that EXECUTE while the 35 graph
                     builders run (`sys.setprofile` CALL events).

THE SUBJECT OF (1) IS THE OP SURFACE; (2) AND (3) ARE THE CODE.  A corpus can be 100% of
(1) and a small fraction of (2) and (3) AT THE SAME TIME, and this one is.

RUN: .venv/bin/python .agents/slop/corpuscoverage/COVER.py
"""
import importlib.util, os, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
os.environ["DEV"] = "CPU"

import reach4 as R  # noqa: E402

spec = importlib.util.spec_from_file_location("graphcmp_corpus", ROOT / ".agents/slop/graphcmp.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
mod.load_tinygrad()

# ---------------------------------------------------------------- (3) py side
TINY = str(ROOT / "tinygrad")
seen = {}
current = [None]


def prof(frame, event, arg):
    if event != "call":
        return
    fn = frame.f_code.co_filename
    if not fn.startswith(TINY):
        return
    rel = fn[len(str(ROOT)) + 1:]
    if rel.startswith("tinygrad/"):
        rel = rel[len("tinygrad/"):]
    seen.setdefault(current[0], set()).add((rel, frame.f_code.co_name, frame.f_code.co_firstlineno))


sys.setprofile(prof)
errs = {}
for name in sorted(mod.GRAPHS):
    current[0] = name
    try:
        mod.GRAPHS[name]()
    except Exception as e:
        errs[name] = f"{type(e).__name__}: {e}"
sys.setprofile(None)

allf = set()
for g in seen:
    allf |= seen[g]
pyfiles = {}
for rel, fn, line in allf:
    pyfiles.setdefault(rel, set()).add((fn, line))
up = ROOT / "tinygrad"
pyall = sorted(str(p.relative_to(up)) for p in up.rglob("*.py") if "__pycache__" not in str(p))

# ------------------------------------------------- (2) bend side, static reach
entry = ROOT / ".agents/slop/graphcmp.bend"
cl, port, harness, defs, names_in, seeds, reached = R.analyse(entry)
portdefs = {d for d in defs if d[0] in port}
portreach = {d for d in reached if d[0] in port}
bend_all = {p.resolve() for p in (ROOT / "tinybendygrad").rglob("*.bend")}
bend_out = sorted(bend_all - port)

print("=" * 78)
print("(1) OP LEVEL -- the corpus's own census, verbatim")
print("=" * 78)
cen = ROOT / "runs/graphcmp/D/D0-coverage-census.txt"
for line in cen.read_text().splitlines():
    if line.startswith("# COVERAGE:") or line.startswith("# NOT REACHED") or line.startswith("# DENOMINATOR"):
        print("   " + line.lstrip("# "))

print()
print("=" * 78)
print("(2) BEND SIDE -- the port's .bend modules and defs")
print("=" * 78)
print(f"   port .bend files total                    : {len(bend_all)}")
print(f"   in the corpus's import closure            : {len(port)}")
print(f"   NEVER in the closure                      : {len(bend_out)}")
print(f"   port defs in the closure                  : {len(portdefs)}")
print(f"   of those, REACHED (def-body call graph)   : {len(portreach)}")
print(f"   of those, UNREACHED                       : {len(portdefs) - len(portreach)}")
print()
print("   per-module def reach, closure modules only:")
rows = []
for f in sorted(port):
    tot = len(names_in[f])
    rch = sum(1 for d in portreach if d[0] == f)
    rows.append((rch, tot, f))
for rch, tot, f in sorted(rows, key=lambda r: (r[0] / max(r[1], 1))):
    flag = "   <== FULLY UNREACHED" if tot and rch == 0 else ""
    print(f"     {str(f.relative_to(ROOT)):42s} {rch:4d}/{tot:4d}  ({100.0*rch/max(tot,1):5.1f}%){flag}")
print()
print("   modules NOT in the corpus's import closure, by size (top 15):")
out = []
for p in bend_out:
    n = sum(1 for _ in p.open(errors="replace"))
    out.append((n, str(p.relative_to(ROOT))))
out.sort(reverse=True)
for n, p in out[:15]:
    print(f"     {n:6d}  {p}")
print(f"     ({len(out)} modules, {sum(r[0] for r in out)} LOC)")

print()
print("=" * 78)
print("(3) PY SIDE -- upstream tinygrad functions EXECUTED by the builders")
print("=" * 78)
print(f"   upstream .py files total                  : {len(pyall)}")
print(f"   files with >=1 function executed          : {len(pyfiles)}")
print(f"   files NEVER executed                      : {len(pyall) - len(pyfiles)}")
print(f"   distinct upstream functions run           : {len(allf)}")
if errs:
    print(f"   builders that raised                     : {len(errs)}")
    for k, v in errs.items():
        print(f"      {k}: {v}")
print()
print("   upstream files NEVER executed, non-autogen and non-runtime/ops_*:")
n = 0
for f in pyall:
    if f in pyfiles or "autogen" in f or f.startswith("runtime/ops_"):
        continue
    n += 1
    print(f"      UNTOUCHED tinygrad/{f}")
print(f"      ({n} files)")
