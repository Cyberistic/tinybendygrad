#!/usr/bin/env python3
r"""THE FOUR HARNESS CLASSES, walked.  For each, the question is ONE: can the process's exit
code change when its child lane answers REFUSED / DEAD / nothing?  A `return <CONSTANT>` whose
body only *prints* a refusal count is a lane that RAN AND DID NOT ANSWER -- the MAYBE-NONE
MEANING, one process up from the shape the census grades.  Measured from the AST, no subprocess."""
import ast, os, re, sys
from collections import Counter
from pathlib import Path
ROOT = Path(__file__).resolve().parents[3]
GATES, CHECKS = ROOT / "gates", ROOT / "checks"

# a name that COUNTS a child verdict.  Derived from the tree's own vocabulary, not invented:
VERDICT_WORDS = ("refus", "refuse", "dead", "skip", "unmoved", "moved_any", "zero", "expect",
                 "bad", "fail", "failcount", "n_refused", "gaps", "uncov", "missing")
REFUSE_CTR = re.compile(r"^\s*(\w+)\s*(?:\+=|=)\s*.*\b(refus|dead|skip|unmoved|expected\b|gap|missing|bad|fail)", re.I)

def const_returns(fn):
    """[(lineno, const or None)] -- every `return` in fn, with the value when it is a literal."""
    stack, out, seen = list(fn.body), [], set()
    while stack:
        n = stack.pop()
        if id(n) in seen: continue
        seen.add(id(n))
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.Lambda)): continue
        if isinstance(n, ast.Return): out.append((n.lineno, n.value))
        stack.extend(ast.iter_child_nodes(n))
    return out

def counters(fn):
    """{name: line} for every `x = 0` / `x += 1` that the file's own vocabulary calls a refusal."""
    out = {}
    for n in ast.walk(fn):
        if isinstance(n, ast.Assign) and isinstance(n.value, ast.Constant) and n.value.value == 0 \
           and len(n.targets) == 1 and isinstance(n.targets[0], ast.Name):
            out[n.targets[0].id] = n.lineno
        if isinstance(n, ast.AugAssign) and isinstance(n.target, ast.Name):
            out.setdefault(n.target.id, n.lineno)
    return out

def verdict_counter_lines(src, fn):
    """Lines inside fn that INCREMENT a counter, by name match."""
    L = src.splitlines(); hits = {}
    for n in ast.walk(fn):
        if isinstance(n, ast.AugAssign) and isinstance(n.target, ast.Name):
            nm = n.target.id
            if any(w in nm.lower() for w in VERDICT_WORDS): hits.setdefault(nm, n.lineno)
        if isinstance(n, ast.Assign) and len(n.targets) == 1 and isinstance(n.targets[0], ast.Name):
            nm = n.targets[0].id
            if any(w in nm.lower() for w in VERDICT_WORDS) and isinstance(n.value, ast.Constant) \
               and isinstance(n.value.value, int):
                hits.setdefault(nm, n.lineno)
    return hits

rows = []
def grade(p, cls):
    try: tree = ast.parse(p.read_text(errors="replace"))
    except Exception: return
    src = p.read_text(errors="replace")
    for fn in ast.walk(tree):
        if not isinstance(fn, ast.FunctionDef): continue
        if fn.name not in ("main", "run"): continue
        body_names = {n.id for n in ast.walk(fn) if isinstance(n, ast.Name)}
        vc = verdict_counter_lines(src, fn)
        # the counter must be LIVE: read by a print/f-string after being incremented
        printed = set()
        for n in ast.walk(fn):
            if isinstance(n, ast.JoinedStr) or (isinstance(n, ast.Call) and isinstance(n.func, ast.Attribute)):
                printed |= {x.id for x in ast.walk(n) if isinstance(x, ast.Name)}
            if isinstance(n, ast.Call):
                printed |= {x.id for x in ast.walk(n) if isinstance(x, ast.Name)}
        live = sorted(k for k in vc if k in printed)
        rs = const_returns(fn)
        lastv = rs[-1][1] if rs else None
        const0 = isinstance(lastv, ast.Constant) and lastv.value == 0
        dep = any(isinstance(v, ast.Name) or (isinstance(v, ast.IfExp)) for _l, v in rs)
        rows.append(dict(cls=cls, file=str(p.relative_to(ROOT)), fn=f"{fn.name}@{fn.lineno}",
                         last_return_line=rs[-1][0] if rs else None,
                         last_return="CONST 0" if const0 else (ast.unparse(lastv)[:28] if lastv is not None else "NONE"),
                         ret_depends_on_var=dep, verdict_counters=live,
                         n_returns=len(rs)))

def emitted(cls, pat):
    n = 0
    for d in (GATES, CHECKS):
        for f in sorted(d.glob(pat)): yield cls, f

for cls, pat in (("mutate", "*-mutate.py"), ("gen", "*-gen.py"), ("oracle", "*-oracle.py")):
    for _c, f in emitted(cls, pat): grade(f, cls)

# ---- the fourth class: shell harnesses, read as text (checks/*.sh is not this unit's grant)
sh = sorted(CHECKS.glob("*.sh"))
VERD = {"PASS": "0", "FAIL": "1", "REFUSED": "3", "SKIP": "4", "DEAD": "5"}
shrows = []
for f in sh:
    t = f.read_text(errors="replace")
    ex = re.findall(r"^\s*(?:exit\s+([0-9]+)|\|\|\s*exit\s+([0-9]+))", t, re.M)
    codes = sorted({a or b for a, b in ex if (a or b)})
    named = [c for c in codes if c in VERD.values()]
    shrows.append((f.name, codes, len(named)))

print(f"{'class':<7} {'file':<44} {'main':<18} {'last return':<30} {'dep?':<5} verdict counters")
for r in sorted(rows, key=lambda r: (r["cls"], r["file"])):
    flag = "CONST0" if r["last_return"] == "CONST 0" else ""
    print(f"{r['cls']:<7} {r['file']:<44} {r['fn']:<18} {r['last_return']:<30} "
          f"{str(r['ret_depends_on_var']):<5} {','.join(r['verdict_counters'])} {flag}")
print("\ncounts by class:", dict(Counter(r['cls'] for r in rows)))
print("CONST-0-last-return by class:",
      dict(Counter(r['cls'] for r in rows if r['last_return'] == 'CONST 0')))
print("\n=== checks/*.sh (READ ONLY, not this unit's grant)")
byn = Counter()
for name, codes, n_named in shrows:
    byn["named" if n_named else "unnamed"] += 1
    print(f"  {name:<34} exit codes {codes}  gatekit-named {n_named}")
print("shell harness summary:", dict(byn), f"of {len(sh)} files")
