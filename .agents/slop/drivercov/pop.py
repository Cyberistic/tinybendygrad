"""RE-TAKE `substrate_digest()`'s POPULATION, in-process, by importing the generator itself.

Doctrine 1: the population is the GENERATOR'S OWN DECLARATION, loaded by path. So we ask
`checks/differ.py` for `substrate_entries()` and `SUBSTRATE_INPUTS`/`SUBSTRATE_WALKS` rather
than re-deriving a walk by hand -- a second copy of the list is a contract with no generator.

READ-ONLY. Imports `checks/differ.py`, which compiles nothing: we call `substrate_entries()`
and never `run`/`repro`/`snap`.
"""
import sys, os, json, collections

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.join(ROOT, "checks"))

import differ  # noqa: E402

entries = differ.substrate_entries()
rels = [rel for rel, _ in entries]

def under(prefix):
    return [r for r in rels if r.startswith(prefix)]

tinygrad_py_on_disk = []
tg = os.path.join(ROOT, "tinygrad")
for dp, dn, fn in os.walk(tg):
    dn[:] = [d for d in dn if d != "__pycache__"]
    for f in fn:
        tinygrad_py_on_disk.append(os.path.relpath(os.path.join(dp, f), ROOT).replace(os.sep, "/"))

slop_py_on_disk = []
for dp, dn, fn in os.walk(os.path.join(ROOT, ".agents/slop")):
    dn[:] = [d for d in dn if d != "__pycache__"]
    for f in fn:
        if f.endswith(".py"):
            slop_py_on_disk.append(os.path.relpath(os.path.join(dp, f), ROOT).replace(os.sep, "/"))

tg_in = under("tinygrad/")
tbg_in = under("tinybendygrad/")

out = {
    "total_declared_inputs": len(entries),
    "walks": list(differ.SUBSTRATE_WALKS),
    "named_inputs": list(differ.SUBSTRATE_INPUTS),
    "n_named": len(differ.SUBSTRATE_INPUTS),
    "walk_tinybendygrad": len(tbg_in),
    "walk_tinygrad": len(tg_in),
    "tinygrad_py_on_disk": len([p for p in tinygrad_py_on_disk if p.endswith(".py")]),
    "tinygrad_py_in_digest": len([p for p in tg_in if p.endswith(".py")]),
    "tinygrad_py_uncovered": sorted(p for p in tinygrad_py_on_disk if p.endswith(".py") and p not in set(rels)),
    "slop_py_on_disk": len(slop_py_on_disk),
    "slop_py_in_digest": sorted(p for p in rels if p.startswith(".agents/slop/") and p.endswith(".py")),
    "absent_named": [r for r, b in entries if b == "ABSENT"],
    "digest": differ.substrate_digest(),
    "abs_nonpy_walk_members": sorted(
        p for p in rels if not p.endswith((".py", ".bend", ".sh")))[:20],
    "extension_census": dict(collections.Counter(os.path.splitext(p)[1] or "<none>" for p in rels)),
}
print(json.dumps(out, indent=1))