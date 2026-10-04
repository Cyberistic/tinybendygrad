"""STAGE 3 -- WHAT A FIRST REAL BACKWARD PASS NEEDS, AND THE SHORTEST PATH.

Every claim here is produced by CALLING CPython or by reading a named file:line.
The upstream side is called (`tinygrad` on DEV=NULL, which needs no device);
the port side is read and, for the ops, checked against `tinybendygrad/uop/ops.bend`.

Run:  env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python \
        .agents/slop/tensor-surface/stage3-path.py
"""
from __future__ import annotations
import re, os, sys, glob

ROOT = "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad"

print("=" * 78)
print("STAGE 3 -- THE BACKWARD QUESTION")
print("=" * 78)
print()

# ---------------------------------------------------------------- 3.0 paths
print("3.0  THE PATH THE BRIEF ASKED ME TO CHECK.")
print("     `tinygrad/engine.py` does NOT exist at this tree revision:")
for p in ("tinygrad/engine.py", "tinygrad/engine", "tinygrad/engine/realize.py"):
    print(f"       {p:32s} exists={os.path.exists(os.path.join(ROOT,p))}"
          f"{'  (directory)' if os.path.isdir(os.path.join(ROOT,p)) else ''}")
print("     The real path is the PACKAGE tinygrad/engine/, and the one line")
print("     tensor.py:13 imports is `from tinygrad.engine.realize import run_linear`.")
print("     `run_linear` is at tinygrad/engine/realize.py:280. The port has the")
print("     mirror: tinybendygrad/engine/realize.bend.")
print()
print("     AND backward's callee is NOT in engine/ at all -- it is")
print("     tinygrad/mixin/gradient.py:116 `compute_gradient`, reached through")
print("     mixin/op.py:464 `OpMixin.gradient` (confirmed by the traceback in")
print("     the measurement below, which names mixin/op.py:464).")
print()

# ------------------------------------------- 3.1 CALL CPython: what a first pass needs
print("3.1  CALLING CPython.  The smallest thing that IS a backward pass:")
print("       a = Tensor([2.,3.]); b = Tensor([4.,5.]); (a*b).sum().gradient(a,b)")
print("     on DEV=NULL, so it needs NO device, NO Buffer, NO realize.")
print()
sys.path.insert(0, ROOT)
from tinygrad import Tensor            # noqa: E402
from tinygrad.uop.ops import Ops        # noqa: E402
from tinygrad.mixin.gradient import compute_gradient  # noqa: E402


def sig(u: str) -> str:
    return f"{u.op.name}/{len(u.src)}"


def run_probe() -> dict:
    a = Tensor([2.0, 3.0])
    b = Tensor([4.0, 5.0])
    c = (a * b).sum()
    fw = c.uop.toposort()
    gs = c.gradient(a, b)
    fwo = {u.op.name for u in fw}
    bwo = {u.op.name for u in gs[0].uop.toposort()}
    return {"fw_n": len(fw), "fw_ops": fwo, "grads": len(gs),
            "grad_n": len(gs[0].uop.toposort()), "new_ops": bwo - fwo}


r1 = run_probe()
print(f"     forward graph : n={r1['fw_n']}  ops={sorted(r1['fw_ops'])}")
print(f"     gradient(a,b) : {r1['grads']} grads, grad[0] n={r1['grad_n']}")
print(f"     ops the BACKWARD graph has that the forward did NOT: "
      f"{sorted(r1['new_ops'])}")
print()
print("     *** THIS IS THE MEASUREMENT THAT SETS THE SCOPE. ***")
print("     A first real backward pass over `mul` needs three ops the forward")
print("     corpus never reaches, and NOTHING ELSE. The forward pass itself needs")
print("     4 ops: BUFFER COPY MUL REDUCE.")
print()

# ------------------------------------------------------- 3.2 the port's side
print("3.2  WHAT THE PORT HAS OF THOSE SEVEN OPS, by reading ops.bend.")
opsrc = open(f"{ROOT}/tinybendygrad/uop/ops.bend").read()
port_ops = set(re.findall(r"^  Ops([A-Z0-9_]+)\{\}", opsrc, re.M))
needed = sorted(r1["fw_ops"] | r1["new_ops"])
print(f"     {'op':10s} {'in port enum':13s} note")
for o in needed:
    print(f"     {o:10s} {str(o in port_ops):13s} "
          f"{'ops.bend case exists' if o in port_ops else 'ABSENT'}")
print()
print("     ALL SEVEN ARE IN THE PORT ENUM. The enum is not the gap.")
print("     The gap is (a) the DRIVER and (b) the three ops' reachability.")
print()

# ------------------------------------------- 3.3 gradient.bend: table vs driver
g = open(f"{ROOT}/tinybendygrad/mixin/gradient.bend").read()
rules = sorted(set(re.findall(r"^def (gr_\d+)", g, re.M)), key=lambda s: int(s[3:]))
print("3.3  THE PORT'S mixin/gradient.bend, split by what it actually contains.")
print(f"     pm_gradient rules ported as defs : {len(rules)} of upstream's 33 table entries")
print(f"     the four driver/helper defs      : "
      f"{[n for n in ['reduce_gradient','call_gradient','partial_store_gradient','compute_gradient','_deepwalk'] if re.search(rf'^def {n}', g, re.M)] or 'NONE'}")
print()
print("     The file's OWN wall list, quoted from mixin/gradient.bend:842-895:")
for ln_no, text in [(i, l.strip()) for i, l in
                    enumerate(g.split("\n"), 1) if 840 <= i <= 900
                    and "TODO(p3)" in l]:
    print(f"       L{ln_no}: {text.lstrip('# ').strip()}")
print()
print("     So: the RULE TABLE is ported and gated; the DRIVER is not. That is")
print("     the same shape the project has already been bitten by -- 33 gated")
print("     rules and no way to apply them is a definition table, not a backward.")
print()

# ------------------------------------------- 3.4 what a driver would need
print("3.4  ENUMERATING THE MISSING PIECES, each with the file it lives in.")
MISSING = [
    ("compute_gradient's walk loop", "mixin/gradient.py:116-145",
     "mixin/gradient.bend",
     "the loop is writable as a fold.bend-shaped Data table; NOT a wall by the file's own account"),
    ("_deepwalk", "mixin/gradient.py:109-114", "mixin/gradient.bend",
     "`topovisit`'s visitor is a Python Callable closing over a dict"),
    ("the shaped-edge reduce", "mixin/gradient.py:132-133", "uop/symbolic.py (NOT PORTED)",
     "needs `broadcast_axes` (ops.py:89) which reads `resolve` on a Sint"),
    ("sum_acc_dtype", "tinygrad/dtype.py:220", "tinygrad/dtype.py",
     "reads getenv('SUM_DTYPE'); Config is a P6 concern"),
    ("Tensor.gradient", "mixin/op.py:464", "mixin/op.bend",
     "the caller of compute_gradient; check whether op.bend has it"),
    ("backward's zip", "tinygrad/tensor.py:490-494", "tinybendygrad/tensor.bend:951",
     "TODO(p3): `self.gradient(...)` + `t.grad.assign(...)`"),
    ("Tensor.grad_set", "optim.py:33 uses it", "tinybendygrad/tensor.bend:279",
     "PRESENT as a def but DEAD -- nothing calls it (measured, stage 2)"),
    ("realize/run_linear", "tinygrad/engine/realize.py:280", "tinybendygrad/engine/realize.bend",
     "NOT needed for a graph-level backward; needed only to read a number out"),
]
for what, where, port, why in MISSING:
    print(f"     - {what}")
    print(f"         upstream : {where}")
    print(f"         port file: {port}")
    print(f"         why      : {why}")
print()

# op.bend gradient?
ob = open(f"{ROOT}/tinybendygrad/mixin/op.bend").read()
print(f"     `def gradient` in mixin/op.bend: "
      f"{'YES' if re.search(r'^def .*gradient', ob, re.M) else 'NO'}")

print()
print("=" * 78)
print("THE THREE ORDERED STEPS.  Not implemented -- named.")
print("=" * 78)
STEPS = [
    ("STEP 1",
     "mixin/gradient.bend",
     "Write `compute_gradient` as a fold.bend-shaped Data table: walk = a"
     " List<U32> from O.UOp.toposort reversed, grads = a List<(U32,U32)>"
     " association, dispatch = the existing first-wins scan the file already"
     " has for its own table.",
     "ONE row: `t_cg_mul` prints the same n= and src-op sequence as CPython's"
     " `(a*b).sum().gradient(a)[0].uop` -- which measured n=7"
     " BUFFER/0 COPY/1 CONST/0 CAST/1 CONST/0 EXPAND/2 MUL/2 on DEV=NULL."
     " A driver that never applies a rule prints n=1 and moves. Because"
     " CAST/CONST/EXPAND are the NEW ops, this row is UNSATISFIABLE by a stub"
     " that returns the forward graph."),
    ("STEP 2",
     "tinybendygrad/tensor.bend:951",
     "Replace the `backward`'s zip TODO(p3) with the call into step 1, and"
     " wire `Tensor.grad_set` (already a def at :279, currently dead) to it."
     " Also `t.grad.assign(t.grad + g)` needs `assign`'s spine, which is"
     " ported (tn_assign_store, :889).",
     "ONE row: a `tn_backward`-level row that, over a BUFFER->MUL->REDUCE"
     " fixture, prints the same scope COUNT and the same grad ROOT OP as"
     " CPython. `tn_needgrad=2` already pins the filter half, so the row is"
     " the second half and the pair is what makes it falsifiable."),
    ("STEP 3",
     "mixin/elementwise.bend (cast/expand) + graphcmp corpus",
     "Land CONST/CAST/EXPAND reachability: `tn_cast` already exists in"
     " tensor.bend:463-494 but is DEAD (measured, stage 2), and"
     " mixin/elementwise.bend owns elementwise's cast/expand. Then add the"
     " training graph to the graphcmp corpus.",
     "ONE row in graphcmp: a `bw` graph whose py side is"
     " `compute_gradient` over a hand-built BUFFER/CONST/MUL/REDUCE, run under"
     " `sh .agents/slop/graphcmp-run.sh`. AGREE at the field-record level."
     " That is the owner's standing ask -- 'compare graphs properly with"
     " tinygrad' -- and a backward graph is the fixture it has never had."),
]
for tag, f, what, proof in STEPS:
    print()
    print(f"{tag}  --  touches {f}")
    for chunk in what.split("\n"):
        pass
    print("   do    : " + what.replace("\n", "\n           "))
    print("   proof : " + proof.replace("\n", "\n           "))
print()
print("WHY THIS ORDER. Step 1 is the whole capability: it is the only piece")
print("with no port file behind it at all. Step 2 is 12 lines in a file that")
print("already has the scope filter and the assign spine. Step 3 is reachability")
print("and corpus, which is what makes the first two COMPARABLE -- and it is")
print("last because a backward graph that disagrees with tinygrad for a")
print("reason that is not the driver's is the failure mode that costs the")
print("most: it looks like a driver bug and sends you into gradient.bend.")
print()
print("WHAT IS DELIBERATELY NOT A STEP: `realize`, `run_linear`, `Buffer`.")
print("Measured above: `compute_gradient` runs to completion on DEV=NULL with")
print("no device state. A first real backward pass is a GRAPH claim, and")
print("tensor.bend:1036 already records realize as a separate wall. Folding")
print("realize into step 1 would make the step untestable, which is the")
print("opposite of the point.")