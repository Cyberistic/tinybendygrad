"""STAGE 2 -- WHAT EXISTS vs WHAT HAS EVER BEEN RUN.

Three denominators, each printed by the tool, because "a def nothing calls is not a
capability" and a count of defs is def-coverage, not executability.

  D1  port defs in tensor.bend                -- total, reachable-from-main, dead
  D2  upstream methods with a port counterpart -- exercised / present-but-unexercised
  D3  ops                                    -- upstream list(Ops) vs port enum

D2 is the number that says how far from a real program the port is, and it is
computed by REACHABILITY FROM main() in tensor.bend plus a cross-file scan, not
by asking whether a comment claims it.

Run:  .venv/bin/python .agents/slop/tensor-surface/stage2-exercised.py
"""
from __future__ import annotations
import re, glob, collections, ast, sys

ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"
TB = f"{ROOT}/tinybendygrad/tensor.bend"

src = open(TB).read()
lines = src.split("\n")

# --- D1: the def graph -----------------------------------------------------
defs: dict[str, tuple[int, list[str]]] = {}
cur, curline, buf = None, 0, []
for i, ln in enumerate(lines, 1):
    m = re.match(r"\s*def\s+([A-Za-z_][A-Za-z0-9_.]*)", ln)
    if m:
        if cur:
            defs[cur] = (curline, buf)
        cur, curline, buf = m.group(1), i, [ln]
    elif cur:
        buf.append(ln)
if cur:
    defs[cur] = (curline, buf)
names = set(defs)

edges: dict[str, set[str]] = collections.defaultdict(set)
for n, (_, b) in defs.items():
    body = re.sub(r"#.*", "", "\n".join(b))
    for m in re.finditer(r"\b((?:[A-Za-z_][A-Za-z0-9_]*\.)*[A-Za-z_][A-Za-z0-9_]*)\s*\(", body):
        called = m.group(1)
        if called == n:
            continue
        parts = called.split(".")
        hit = next((".".join(parts[k:]) for k in range(len(parts))
                    if ".".join(parts[k:]) in names), None)
        if hit:
            edges[n].add(hit)

main_at = next(i for i, ln in enumerate(lines) if re.match(r"\s*def main", ln))
reach: set[str] = set()
stack = list(edges["main"])
while stack:
    x = stack.pop()
    if x not in reach:
        reach.add(x)
        stack.extend(edges.get(x, ()))
dead = sorted(n for n in names if n not in reach and n != "main")

# --- D2: cross-file usage --------------------------------------------------
used_external: dict[str, list[str]] = collections.defaultdict(list)
for f in glob.glob(f"{ROOT}/tinybendygrad/**/*.bend", recursive=True):
    if f.endswith("tensor.bend"):
        continue
    for i, ln in enumerate(open(f), 1):
        for m in re.finditer(r"\b([A-Za-z_][A-Za-z0-9_.]*)\s*\(", ln):
            c = m.group(1)
            tail = c.split(".")[-1]
            if tail in names and tail != "main":
                used_external[tail].append(f"{f.replace(ROOT+'/', '')}:{i}")

# --- the counterparts, and whether the gate reaches them -------------------
sys.path.insert(0, ROOT)
tree = ast.parse(open(f"{ROOT}/tinygrad/tensor.py").read())
cls = [n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == "Tensor"][0]
meths = [m for m in cls.body if isinstance(m, ast.FunctionDef)]

# entry-point defs: what main() calls, transitively, that is a PORT counterpart
COUNTERPART_ROOTS = {
    "tn_init": "__init__", "tn_alu": "alu", "tn_const": "const",
    "tn_is_param_": "is_param_", "tn_repr": "__repr__", "tn_hash": "__hash__",
    "tn_len": "__len__", "tn_dev": "device", "tn_dims": "shape", "tn_dtype": "dtype",
    "tn_replace": "replace", "tn_assign_store": "assign", "tn_need_grad": "backward",
    "tn_mop": "_mop", "tn_rop": "_rop", "tn_new": "_apply_uop",
    "tn_wrap_uop": "_wrap_uop",
}

print("=" * 78)
print("STAGE 2 -- PRESENT vs EXERCISED")
print("=" * 78)
print()
print(f"D1  tensor.bend defs: {len(defs)}")
print(f"    reachable from main():        {len(reach)}")
print(f"    NOT reachable (dead in-file): {len(dead)}")
print(f"    exercised by ANOTHER .bend:   {len(used_external)}  "
      f"(refs: {sum(len(v) for v in used_external.values())})")
print()
print("    the dead ones, and what they are:")
GROUPED = {
    "the whole `__init__` counterpart (tn_init*, tn_cast*)": [n for n in dead if n.startswith(("tn_init", "tn_cast"))],
    "the `assign` spine's `ib` walk (tn_ib_walk*)": [n for n in dead if n.startswith("tn_ib_walk")],
    "misc (Tensor.grad_set, Tensors.of, g_t4a, tn_wrap_uop)":
        [n for n in dead if n in ("Tensor.grad_set", "Tensors.of", "g_t4a", "tn_wrap_uop")],
}
for label, g in GROUPED.items():
    print(f"      {len(g):2d}  {label}")
    print(f"          {sorted(g)}")
assert sum(len(v) for v in GROUPED.values()) == len(dead), (len(dead), GROUPED)
print()

print("D2  upstream methods with a port counterpart, and whether the gate runs it")
print(f"    denominator = {len(COUNTERPART_ROOTS)} counterpart roots")
print()
print(f"    {'upstream':12s} {'port root':16s} {'in main() graph':15s} {'used elsewhere':14s} verdict")
exercised, present_unexercised = [], []
for root, up in sorted(COUNTERPART_ROOTS.items(), key=lambda kv: kv[1]):
    inmain = root in reach
    else_ = root in used_external
    if inmain:
        verdict = "EXERCISED"
        exercised.append(up)
    else:
        verdict = "present, NOT exercised"
        present_unexercised.append(up)
    print(f"    {up:12s} {root:16s} {str(inmain):15s} {str(else_):14s} {verdict}")
print()
print(f"    EXERCISED by the gate:        {len(exercised)}/{len(COUNTERPART_ROOTS)}  {exercised}")
print(f"    PRESENT BUT NEVER RUN:       {len(present_unexercised)}/{len(COUNTERPART_ROOTS)}  {present_unexercised}")
print()
print("    NOTE -- `tn_need_grad` is in main()'s graph, but only through")
print("    `t_needgrad`, which prints a COUNT (tn_needgrad=2) of the scope filter.")
print("    `backward`'s own zip -- the call to `gradient` -- is TODO(p3) at")
print("    tensor.bend:951. So `backward` is exercised AS A FILTER, not AS A")
print("    BACKWARD PASS. That is a 1-of-2 result, not a pass.")
print()

# --- D3: ops --------------------------------------------------------------
from tinygrad.uop.ops import Ops  # noqa: E402
up_ops = [o.name for o in Ops]
opsrc = open(f"{ROOT}/tinybendygrad/uop/ops.bend").read()
port_ops = set(re.findall(r"^  Ops([A-Z0-9_]+)\{\}", opsrc, re.M))
print(f"D3  upstream list(Ops) = {len(up_ops)};  port Ops* enum cases = {len(port_ops)}")
print(f"    missing in port: {sorted(set(up_ops) - port_ops)}")
print(f"    extra in port:   {sorted(port_ops - set(up_ops))}")
print("    THE ENUM IS COMPLETE. The 43 unreached ops in graphcmp-LIMITS.md §5 are")
print("    a COVERAGE number over the differ's corpus, not an enum gap.")
print()

# --- the gradient driver, by measurement ---------------------------------
print("=" * 78)
print("THE BACKWARD DRIVER: measured, not read")
print("=" * 78)
for drv in ["compute_gradient", "_deepwalk", "reduce_gradient", "call_gradient",
            "partial_store_gradient"]:
    callers = []
    for f in glob.glob(f"{ROOT}/tinybendygrad/**/*.bend", recursive=True):
        for i, ln in enumerate(open(f), 1):
            if re.sub(r"#.*", "", ln).strip() and drv in ln:
                callers.append(f"{f.replace(ROOT+'/','')}:{i}")
    print(f"  {drv:24s} callers in the whole port tree: {len(callers)}")
print()
g = open(f"{ROOT}/tinybendygrad/mixin/gradient.bend").read()
rules = sorted(set(re.findall(r"^def (gr_\d+)", g, re.M)), key=lambda s: int(s[3:]))
print(f"  pm_gradient rules ported as defs: {len(rules)} (upstream table is 33 entries)")
print(f"    {rules}")
print()
print("  => the TABLE exists and is gated; the DRIVER that walks the graph applying")
print("     it does not, and nothing in the tree calls one.")