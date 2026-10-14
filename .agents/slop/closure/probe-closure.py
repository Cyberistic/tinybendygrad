#!/usr/bin/env python
"""MEASUREMENT PROBE, not an instrument. Prints the closure of a `.bend` entry under three
resolvers so the disagreements are visible. `.agents/slop/closure/` is scratch for THIS unit.

  A  `checks/nvrows-deadrow-gate.py:89 import_closure`, LOADED BY PATH (doctrine 1: never a
     second resolver)
  B  A  same, plus the QUOTED-FFI spelling `import "../../../x.c"` that A drops
  C  A basename-only resolver, which is the failure mode A's regex has

Usage: probe-closure.py [entry]   (default: .agents/slop/graphcmp.bend)
"""
import importlib.util, pathlib, re, sys, collections

REPO = pathlib.Path(__file__).resolve().parents[3]
PKG = REPO / "tinybendygrad"
ENTRY = pathlib.Path(sys.argv[1]) if len(sys.argv) > 1 else REPO / ".agents/slop/graphcmp.bend"
if not ENTRY.is_absolute():
    ENTRY = REPO / ENTRY

spec = importlib.util.spec_from_file_location("nvrows", REPO / "checks/nvrows-deadrow-gate.py")
nv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nv)                       # module level is definitions + 3 constants

A = nv.import_closure(PKG, ENTRY)

# B: A, plus the quoted-FFI spelling. Token carries its quotes, so strip them, and keep the
# suffix the author wrote instead of forcing `.bend`.
QUOTED = re.compile(r'^import\s+"([^"]+)"')
def b_closure():
    seen, queue = {ENTRY.resolve()}, [ENTRY.resolve()]
    while queue:
        cur = queue.pop()
        for line in cur.read_text().splitlines():
            t = line.strip()
            m = nv.IMPORT.match(t)
            if not m:
                continue
            tok = m.group(1)
            if tok.startswith('"') and tok.endswith('"'):
                tgt = (cur.parent / tok[1:-1]).resolve()      # suffix AS WRITTEN
            else:
                base = cur.parent if tok.startswith(".") else PKG
                tgt = (base / tok).with_suffix(".bend").resolve()
            if tgt.is_file() and tgt not in seen:
                seen.add(tgt); queue.append(tgt)
    return seen
B = b_closure()

print(f"ENTRY     {ENTRY.relative_to(REPO)}")
print(f"A nvrows  {len(A)} files   (of which .bend: {sum(1 for p in A if p.suffix=='.bend')})")
print(f"B +ffi    {len(B)} files   (A missing: {len(B-A)})")
for p in sorted(B - A):
    print(f"           A DROPS {p.relative_to(REPO)}")

# C: basename-only. How many files in the tree SHARE each basname in A?
by_base = collections.defaultdict(list)
for p in REPO.rglob("*.bend"):
    by_base[p.name].append(p)
amb = {n: v for n, v in by_base.items() if n in {p.name for p in A} and len(v) > 1}
print(f"\nC basename: {len(amb)}/{len({p.name for p in A})} distinct basenames in A are AMBIGUOUS")
for n, v in sorted(amb.items())[:12]:
    print(f"           {n}: {len(v)} files, e.g. {v[0].relative_to(REPO)}")

print("\n--- A, sorted ---")
for p in sorted(A):
    print("   ", p.relative_to(REPO))