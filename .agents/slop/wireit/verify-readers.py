"""An INDEPENDENT AST census of the readers of runs/graphcmp/D. Does not import
checks/runs-artifacts.py -- a shared resolver is exactly what would hide a shared bug."""
import ast, glob, os, sys

# FOUR dirnames: <root>/.agents/slop/wireit/verify-readers.py. THREE resolved ROOT to `.agents`
# and the census printed `instruments scanned : 0` -- the clean confident zero the brief names.
# GUARD THE COMPUTED ROOT, not this script's own directory: a first attempt asserted against
# `dirname(__file__)` (which is `.agents/slop/wireit`, never holding `checks/`) and so fired on
# the CORRECT ROOT too. An assertion that cannot fail on the right answer is a second zero.
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
assert os.path.isdir(os.path.join(ROOT, "checks")), f"ROOT wrong: {ROOT}"
# THE ARTEFACT SET, not its parent. My FIRST reading used "runs/graphcmp", which additionally
# counted `checks/txt-owners.py` (it matches the bare prefix "runs/graphcmp/" in a startswith
# tuple) -- a 9th name that reads the PARENT, not the set. The prefix a census names is part of
# its scope, so it is a constant here and not an argument I can drift.
TARGET = "runs/graphcmp/D"

def lit(n, env, d=0):
    """Deliberately written from the resolve() docstring's list, not copied from it:
    Constant / Name / BinOp(Div,Add) / Subscript(Call(...).parents[n]) / Attribute(receiver) /
    JoinedStr / Tuple / Call(Path,join) -- and the RECEIVER of any attribute call."""
    if d > 8: return None
    if isinstance(n, ast.Constant): return n.value if isinstance(n.value, str) else None
    if isinstance(n, ast.Name): return env.get(n.id)
    if isinstance(n, ast.Attribute): return lit(n.value, env, d+1)
    if isinstance(n, ast.BinOp) and isinstance(n.op, (ast.Div, ast.Add)):
        a, b = lit(n.left, env, d+1), lit(n.right, env, d+1)
        if isinstance(a, str) and isinstance(b, str):
            return os.path.join(a, b) if isinstance(n.op, ast.Div) else a + b
        return None
    if isinstance(n, ast.Subscript):
        i = n.slice.value if isinstance(n.slice, ast.Constant) else None
        if isinstance(i, int):
            # MEASURED, twice today: `Path(__file__).resolve().parents[1]` is a Subscript whose
            # `.value` is a BARE ast.Attribute -- `parents` is a property, not a method, so it is
            # NOT `Call(func=Attribute(attr='parents'))`. Requiring the Call form made this whole
            # branch dead and ROOT resolved to None, which took 4 readers AND the only writer out
            # of the census while every other number stayed confidently clean (5 readers, 0
            # writers, on a tree with 8 and 1). Accept the Attribute, and keep the Call for a
            # spelling that does not occur.
            v = n.value
            if isinstance(v, ast.Attribute) and v.attr == "parents":
                b = lit(v.value, env, d + 1)
                return "/".join([".."] * i) if b == "" else b
            if isinstance(v, ast.Call) and isinstance(v.func, ast.Attribute) and v.func.attr == "parents":
                b = lit(v.func.value, env, d + 1)
                return "/".join([".."] * i) if b == "" else b
        return None
    if isinstance(n, ast.JoinedStr):
        return "".join(v.value for v in n.values
                       if isinstance(v, ast.Constant) and isinstance(v.value, str)) or None
    if isinstance(n, ast.Tuple):
        for e in n.elts:
            if isinstance(e, ast.Constant) and isinstance(e.value, str) and e.value.strip("/"):
                return e.value
        return None
    if isinstance(n, ast.Call):
        fn = n.func.attr if isinstance(n.func, ast.Attribute) else getattr(n.func, "id", "")
        if fn == "Path": return ""
        if fn == "parent":
            p = [lit(a, env, d+1) for a in n.args]
            return os.path.join(*p) + "/.." if any(p) else None
        if fn in ("join", "as_posix"):
            p = [lit(a, env, d+1) for a in n.args]
            return os.path.join(*(x if x is not None else "?" for x in p)) if any(p) else None
        if fn in ("resolve", "absolute", "realpath", "expanduser") and isinstance(n.func, ast.Attribute):
            return lit(n.func.value, env, d+1)
    return None

def env_of(tree):
    e = {}
    for _ in range(4):
        for st in ast.walk(tree):
            if isinstance(st, ast.Assign) and len(st.targets) == 1 and isinstance(st.targets[0], ast.Name):
                if (v := lit(st.value, e)) is not None: e[st.targets[0].id] = v
    return e

def docstrings(tree):
    ids = set()
    for n in ast.walk(tree):
        if isinstance(n, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
            b = getattr(n, "body", None)
            if b and isinstance(b[0], ast.Expr) and isinstance(b[0].value, ast.Constant) \
               and isinstance(b[0].value.value, str): ids.add(id(b[0].value))
    return ids

def under(v):
    """Component comparison at FULL depth, not `p[:2]`. `p[:2] == TARGET.split("/")` compared a
    2-element prefix against a 3-element target and was False for EVERY value, so the whole
    census was structurally incapable of matching once TARGET grew a component -- a comparison
    that returns one constant answer is not a measurement."""
    if not isinstance(v, str): return False
    p = [x for x in v.replace("\\","/").split("/") if x not in ("", ".", "..")]
    w = TARGET.split("/")
    return p[:len(w)] == w

files = sorted(glob.glob(os.path.join(ROOT,"checks","*.py")) + glob.glob(os.path.join(ROOT,"gates","*.py")))
readers, writers, per = set(), set(), {}
for f in files:
    tree = ast.parse(open(f, errors="replace").read())
    env, docs = env_of(tree), docstrings(tree)
    hits = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call): continue
        fn = node.func.attr if isinstance(node.func, ast.Attribute) else getattr(node.func, "id","")
        w = fn in {"makedirs","mkdir","write_text","write_bytes","open","touch","mkstemp",
                   "NamedTemporaryFile","symlink_to","hardlink_to"}
        args = list(node.args) + [k.value for k in node.keywords]
        if isinstance(node.func, ast.Attribute): args.append(node.func.value)  # THE RECEIVER
        for a in args:
            for leaf in (a.elts if isinstance(a, ast.Tuple) else (a,)):
                if isinstance(leaf, ast.Constant) and id(leaf) in docs: continue
                if under(lit(leaf, env)):
                    rel = os.path.relpath(f, ROOT)
                    (writers if w else readers).add(rel)
                    hits.append((node.lineno, fn, "write" if w else "read", lit(leaf, env)))
    if hits: per[os.path.relpath(f, ROOT)] = hits

print(f"instruments scanned : {len(files)}  (checks/*.py + gates/*.py)")
print(f"READERS  : {len(readers)}")
for r in sorted(readers): print(f"   {r:<30} {len(per[r])} site(s)")
print(f"WRITERS  : {len(writers)}  {sorted(writers)}")
print(f"\nsites per file:")
for f, h in sorted(per.items()):
    for ln, fn, role, v in sorted(h): print(f"   {f}:{ln}  {role:<5} .{fn}()  value={v!r}")
