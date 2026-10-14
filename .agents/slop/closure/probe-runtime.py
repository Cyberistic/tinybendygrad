#!/usr/bin/env python
"""THE CLOSURE IS DERIVABLE -- BY EXECUTION, NOT BY INFERENCE.

`probe-pyclosure.py` inferred 87 files by AST and got it WRONG: `tinygrad/Tensor.py:8` reads
`from tinygrad.helpers import cpu_profile, suppress_finalizing, disable_gc, VIZ`, and `VIZ` is
a ContextVar DEFINED at `tinygrad/helpers.py:271`, not the `tinygrad/VIZ/` PACKAGE -- which
exists on disk (`__init__.py`, `serve.py`, `cli.py`, `js/`, `assets/`), so a resolver that treats
every from-import NAME as a candidate module finds a REAL FILE and reports a real edge that the
interpreter never takes.  `tinygrad/Tensor.py:171` is `if VIZ:` -- a truthiness test on an int.

No static resolver can settle that, because `from x import y` is genuinely ambiguous: `y` may be
a submodule or an attribute.  The interpreter settles it for free.  So this asks the question by
IMPORTING and reading `sys.modules`, which is a measurement of what actually got loaded rather
than a guess about what could have been.

It also reports the DIFFERENCE against the AST superset, because a cache key must over-include
if it is to be safe, and an instrument that hides its own over-inclusion is the defect this
project has catalogued twenty times.
"""
import importlib.util, os, pathlib, sys

REPO = pathlib.Path(__file__).resolve().parents[3]
os.environ["DEV"] = "CPU"
sys.path.insert(0, str(REPO))
spec = importlib.util.spec_from_file_location("graphcmp", REPO / ".agents/slop/graphcmp.py")
G = importlib.util.module_from_spec(spec)
sys.modules["graphcmp"] = G
spec.loader.exec_module(G)          # module level only; emits nothing, runs no graph
G.load_tinygrad()                   # the same call `checks/census.py:183` makes

live = {}
for name, mod in list(sys.modules.items()):
    f = getattr(mod, "__file__", None)
    if not f:
        continue
    try:
        p = pathlib.Path(f).resolve()
    except (OSError, ValueError):
        continue
    if p.is_relative_to(REPO):
        live.setdefault(p, name)

py  = sorted(p for p in live if p.suffix == ".py" and p.is_relative_to(REPO / "tinygrad"))
sl  = sorted(p for p in live if p.is_relative_to(REPO / ".agents"))
oth = sorted(p for p in live if p not in py and p not in sl)
print(f"RUNTIME closure (sys.modules after import + load_tinygrad): {len(live)} files under {REPO}")
print(f"  tinygrad/*.py   {len(py)}")
print(f"  .agents/slop/   {len(sl)}  -> {[str(p.relative_to(REPO)) for p in sl]}")
print(f"  other in-repo   {len(oth)}")
print("\n--- tinygrad, RUNTIME ---")
for p in py:
    print("   ", p.relative_to(REPO))

# What the AST superset claimed, and what it got wrong.
sys.path.insert(0, str(REPO / ".agents/slop/closure"))
import probe_pyclosure as A   # noqa: E402
ast_set, _ = A.closure((REPO / ".agents/slop/graphcmp.py").resolve())
live_set = set(live)
print(f"\nAST superset   {len(ast_set)}")
print(f"RUNTIME truth  {len(live_set & set(ast_set))} of those are real")
extra = sorted(ast_set - live_set)
print(f"AST over-count {len(extra)}  (files the AST reaches that a real import does NOT):")
for p in extra:
    print("   ", p.relative_to(REPO))