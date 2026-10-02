#!/usr/bin/env python3
"""rebase-plan.py -- which vendored files must be RE-VENDORED TOGETHER, and in what order.

WHY THIS EXISTS. UPSTREAM-PIN.md used to say "re-vendor just that one file". That is
wrong, and the failure was measured four times before the advice was removed:

  ops.py alone           -> ImportError: axis_to_pos   (postrange.py at the PIN imports it;
                                                             78d482262 DELETES it from ops.py)
  hcq2.py + ops_metal.py -> ImportError: encode_submit (six other files need it)
  cstyle.py alone        -> dtypes.i8 absent            (the i8 rename in 793abbb16)
  cstyle.py + dtype.py   -> the unit's own oracle dies: KeyError dtypes.fp8e4m3, 210 rows -> 0

The common shape is not "big commit". It is NAME-LEVEL: upstream moved a name across a
module boundary in the same commit that moved its user. Per-FILE vendoring cannot express
that; per-COMMIT and per-MODULE-CLOSURE vendoring can. This script computes the closure
from the source, so the sequence is derived, not guessed.

WHAT IT COMPUTES, in order:
  1. top-level defs/classes/assignments per file, at the PIN and at HEAD   (the module API)
  2. `from tinygrad.x.y import a, b` edges, at the PIN and at HEAD         (the import edges)
  3. COUPLING, at THREE LEVELS. A is coupled to B iff, at either revision of A, A
     REFERENCES something of B's that moved in the window:
       (a) NAME level   -- `from tinygrad.x import n`, n added/removed/rebound in B
       (b) ATTR level   -- `Cls.member` where member was added to / removed from a class
                           B defines. This is what the name-level pass MISSES and what
                           actually killed the cstyle gate: HEAD cstyle.py uses
                           `dtypes.i8`, and PIN dtype.py has no `i8` (793abbb16 renamed
                           int8 -> i8 while keeping int8 as a legacy alias, so BOTH
                           directions exist at once).
       (c) SIG level    -- a def/method's parameter list changed. A call site with the old
                           arity is a TypeError, which no name diff will show.
     Levels (a) and (b) are UNDIRECTIONAL SYMMETRIC: both revisions of the importer are
     checked, because re-vendoring produces a MIXED tree and either half can be the stale
     one. Level (c) is reported as a warning on the batch, not an edge, because a
     signature change is only a coupling if the caller is also in the batch.
     A file that references nothing that moved is INDEPENDENT and can move alone.
  4. connected components of the coupling graph, restricted to files upstream changed.
     Each component is one batch. Batches are independent of each other.
  5. inside a component, a topological order by module depth (imports first) so the batch
     is vendored in an order where every name a file needs already exists.

  usage: python3 .agents/slop/rebase-plan.py [--json] [--pin SHA] [--head REF] [--only F]
"""
import argparse, ast, json, re, subprocess, sys
from collections import defaultdict

REPO = __import__("pathlib").Path(__file__).resolve().parents[2]


def sh(*a):
  r = subprocess.run(a, cwd=REPO, capture_output=True, text=True)
  return r.stdout if r.returncode == 0 else ""


def blob(rev, path):
  r = subprocess.run(["git", "show", f"{rev}:{path}"], cwd=REPO, capture_output=True)
  return r.stdout.decode("utf-8", "replace") if r.returncode == 0 else None


def pkg_of(path):
  """tinygrad/uop/ops.py -> tinygrad.uop.ops  (the module `from X import n` names)."""
  s = path[len("tinygrad/"):-len(".py")]
  return "tinygrad." + s.replace("/", ".").replace(".__init__", "")


def path_of(module):
  s = module[len("tinygrad."):].replace(".", "/")
  return f"tinygrad/{s}.py"


def api(src):
  """Top-level NAMES a module binds, and enough shape to tell 'moved' from 'present'.

  Returns {name: (kind, value_repr)}. Kind is one of def/class/assign/import/other.
  We compare (kind, value) so a reassignment with a different RHS counts as moved.
  """
  out = {}
  if src is None:
    return out
  try:
    tree = ast.parse(src)
  except SyntaxError:
    return {"__PARSE_ERROR__": ("other", "")}
  for n in tree.body:
    if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
      out[n.name] = ("def", "")
    elif isinstance(n, ast.ClassDef):
      out[n.name] = ("class", "")
    elif isinstance(n, ast.Assign):
      for t in n.targets:
        if isinstance(t, ast.Name):
          out[t.id] = ("assign", ast.dump(n.value)[:400])
    elif isinstance(n, ast.AnnAssign) and isinstance(n.target, ast.Name):
      out[n.target.id] = ("assign", ast.dump(n.value)[:400] if n.value else "")
    elif isinstance(n, ast.ImportFrom):
      for a in n.names:
        out[a.asname or a.name] = ("import", f"{n.module}.{a.name}")
    elif isinstance(n, ast.Import):
      for a in n.names:
        out[a.asname or a.name] = ("import", a.name)
  return out


def imports(src):
  """[(module, name)] for every `from tinygrad... import ...`, at any nesting depth,
  because tinygrad defers imports into functions and TYPE_CHECKING blocks."""
  out = []
  if src is None:
    return out
  try:
    tree = ast.parse(src)
  except SyntaxError:
    return out
  for n in ast.walk(tree):
    if isinstance(n, ast.ImportFrom) and n.module and n.module.startswith("tinygrad"):
      for a in n.names:
        out.append((n.module, a.name))
  return out


def classes(src):
  """{name: {dotted-name-reachable members}} for anything a file exposes by name.

  Three shapes, and each one was a hole in an earlier version of this file:

    1. DATA attributes of a ClassDef -- `class AxisType(Enum): REDUCE = auto()`.
    2. A SINGLETON: `class DTypes: i8: Final[DType] = ...` then `dtypes = DTypes()`.
       Callers import the INSTANCE, so `dtypes.i8` resolves against the instance. Without
       this, the 793abbb16 rename (`int8` -> `i8`, keeping `int8` as an alias) is INVISIBLE:
       DTypes' own member set is a strict superset on both sides, and only the per-name
       detail of the singleton's view moves.
    3. METHODS of a ClassDef -- `UPat.custom_function` is a `def` in the class body. Only
       collecting assignments misses it, and then `hcq2.py` looks independent of
       `ops.py` while calling a method that does not exist yet at the pin. That was a REAL
       miss: the empirical probe in rebase-try.sh raised
       `AttributeError: type object 'UPat' has no attribute 'custom_function'` on a batch
       the static pass had called complete.
  """
  out = {}
  if src is None:
    return out
  try:
    tree = ast.parse(src)
  except SyntaxError:
    return out

  def members(body):
    m = set()
    for s in body:
      if isinstance(s, ast.Assign):
        m.update(t.id for t in s.targets if isinstance(t, ast.Name))
      elif isinstance(s, ast.AnnAssign) and isinstance(s.target, ast.Name):
        m.add(s.target.id)
      elif isinstance(s, (ast.FunctionDef, ast.AsyncFunctionDef)):
        m.add(s.name)
      elif isinstance(s, ast.ClassDef):
        m.add(s.name)
    return m

  for n in tree.body:
    if isinstance(n, ast.ClassDef):
      out[n.name] = members(n.body)
  for n in tree.body:
    if isinstance(n, ast.Assign) and isinstance(n.value, ast.Call) \
       and isinstance(n.value.func, ast.Name):
      cls = n.value.func.id
      if cls in out:
        for t in n.targets:
          if isinstance(t, ast.Name):
            out[t.id] = out[cls]
  return out


def attr_refs(src):
  """[(module, class, attr)] -- attribute access `Cls.a` where `Cls` was imported from a
  tinygrad module. This is the resolution that catches `dtypes.i8` and `AxisType.REDUCE`."""
  out = []
  if src is None:
    return out
  try:
    tree = ast.parse(src)
  except SyntaxError:
    return out
  origin = {}
  for n in ast.walk(tree):
    if isinstance(n, ast.ImportFrom) and n.module and n.module.startswith("tinygrad"):
      for a in n.names:
        origin[a.asname or a.name] = n.module
  for n in ast.walk(tree):
    if isinstance(n, ast.Attribute) and isinstance(n.value, ast.Name) and n.value.id in origin:
      out.append((origin[n.value.id], n.value.id, n.attr))
  return out


def signatures(src):
  """{name: parameter-list source} for top-level defs and all class methods."""
  out = {}
  if src is None:
    return out
  try:
    tree = ast.parse(src)
  except SyntaxError:
    return out
  for n in tree.body:
    if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)):
      out[n.name] = ast.unparse(n.args)
    elif isinstance(n, ast.ClassDef):
      for s in n.body:
        if isinstance(s, (ast.FunctionDef, ast.AsyncFunctionDef)):
          out[f"{n.name}.{s.name}"] = ast.unparse(s.args)
  return out


def tuple_fields(src, kw):
  """{def name: {(shape_id, ((index, 'Cls.MEMBER'), ...))}} for every `f(kw=(a, b, c))`.

  The FOURTH coupling level, and the one no name/attr/sig diff can see. 78d482262 changes
  `UOp.range` so that `arg` goes from `(axis_id, axis_type)` to `(axis_type, axis_id)`. Both
  names still exist, the method signature is unchanged, and rangeify.py still imports
  cleanly -- it dies at RUN time on `x.arg[0] + 1` with an AxisType. A UOp is a tuple
  payload with a fixed positional layout, so a field SWAP is a signature change to the
  tuple, and the readers of that tuple are coupled exactly like the callers of a function.

  Returns only the ENUM-MEMBER POSITIONS, plus a hash of the whole literal as the shape
  identity, because "the same enum members in a different order" is the only rearrangement
  that breaks a positional reader from outside the defining module.
  """
  out = {}
  if src is None:
    return out
  try:
    tree = ast.parse(src)
  except SyntaxError:
    return out
  for fn in [n for n in ast.walk(tree) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef))]:
    shapes = set()
    for n in ast.walk(fn):
      if not isinstance(n, ast.Call):
        continue
      for k in n.keywords:
        if k.arg != kw or not isinstance(k.value, ast.Tuple):
          continue
        members = tuple((i, f"{el.value.id}.{el.attr}")
                        for i, el in enumerate(k.value.elts)
                        if isinstance(el, ast.Attribute) and isinstance(el.value, ast.Name))
        if members:
          shapes.add((ast.dump(k.value), members))
    if shapes:
      out[fn.name] = shapes
  return out


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--pin", default="6c3d401cf324")
  ap.add_argument("--head", default="upstream/master")
  ap.add_argument("--json", action="store_true")
  ap.add_argument("--only", default=None, help="restrict to files whose path contains this")
  a = ap.parse_args()

  pin, head = a.pin, a.head
  files = [f for f in sh("git", "ls-tree", "-r", "--name-only", head, "tinygrad/").split()
           if f.endswith(".py")]
  apis = {rev: {f: api(blob(rev, f)) for f in files} for rev in (pin, head)}
  imps = {rev: {f: imports(blob(rev, f)) for f in files} for rev in (pin, head)}
  clss = {rev: {f: classes(blob(rev, f)) for f in files} for rev in (pin, head)}
  attrs = {rev: {f: attr_refs(blob(rev, f)) for f in files} for rev in (pin, head)}
  sigs = {rev: {f: signatures(blob(rev, f)) for f in files} for rev in (pin, head)}
  by_mod = {rev: {pkg_of(f): f for f in files} for rev in (pin, head)}
  changed = [f for f in sh("git", "diff", "--name-only", pin, head, "--", "tinygrad/").split()
             if f.endswith(".py")]
  if a.only:
    changed = [f for f in changed if a.only in f]
  changed_set = set(changed)

  # ---- per-file API delta ---------------------------------------------------
  api_delta = {}
  for f in files:
    P, H = apis[pin][f], apis[head][f]
    api_delta[f] = {
      "added": sorted(set(H) - set(P)), "removed": sorted(set(P) - set(H)),
      "changed": sorted(k for k in set(P) & set(H) if P[k] != H[k]),
    }

  # ---- coupling edges: A imports name n from B, and n MOVED ------------------
  # For each importer A we use BOTH revisions of A's import list: if head-A imports a name
  # that pin-B does not have, A cannot be vendored without B. If pin-A imports a name that
  # head-B dropped, A cannot be left behind while B moves. Either way: coupled.
  couple = defaultdict(set)      # A -> {B}
  why = defaultdict(set)         # "A -> B" -> {reasons}; a SET because postrange.py
                                 # mentions AxisType.REDUCE eleven times and a reason list
                                 # that repeats itself hides the two that are not repeats.
  for f in files:
    for rev in (pin, head):
      for mod, nm in imps[rev][f]:
        bp = path_of(mod)
        if bp not in apis[pin] or bp not in apis[head]:
          continue
        P, H = apis[pin][bp], apis[head][bp]
        if nm not in P and nm in H:
          couple[f].add(bp)
          why[f"{f} -> {bp}"].add(f"{rev}-side import of NEW name `{nm}`")
        elif nm in P and nm not in H:
          couple[f].add(bp)
          why[f"{f} -> {bp}"].add(f"{rev}-side import of REMOVED name `{nm}`")
        elif P.get(nm) != H.get(nm):
          couple[f].add(bp)
          why[f"{f} -> {bp}"].add(f"{rev}-side import of CHANGED name `{nm}`")

  # ---- level (b): ATTRIBUTE coupling -----------------------------------------
  # Checked symmetrically: a PIN-side reference to something HEAD removed (stale importer)
  # and a HEAD-side reference to something PIN lacks (early importer) are both failures.
  for f in files:
    for rev in (pin, head):
      for mod, cls, attr in attrs[rev][f]:
        bp = path_of(mod)
        if bp not in apis[pin] or bp not in apis[head]:
          continue
        CP, CH = clss[pin][bp], clss[head][bp]
        if cls not in CP or cls not in CH:
          continue
        ma, mb = CP[cls], CH[cls]
        if attr in ma and attr not in mb:
          couple[f].add(bp)
          why[f"{f} -> {bp}"].add(f"{rev}-side use of REMOVED `{cls}.{attr}`")
        elif attr not in ma and attr in mb:
          couple[f].add(bp)
          why[f"{f} -> {bp}"].add(f"{rev}-side use of NEW `{cls}.{attr}`")

  # ---- level (d): POSITIONAL TUPLE-PAYLOAD coupling ---------------------------
  # B writes `f(arg=(a, b))`; B' writes `f(arg=(b, a))`. Nothing is renamed and no
  # signature changed, but every reader of `X.arg[0]` is now reading the other field.
  # 78d482262 does this to `UOp.range`: `arg=(axis_id, axis_type)` -> `(axis_type, axis_id)`.
  #
  # NARROWED DELIBERATELY. The first version of this rule fired on ANY change to ANY `arg=`
  # tuple and fused 30 files into one batch, which is the same mistake as "vendor it all"
  # wearing a lab coat. `hcq2.py` reshaping `make_submit(arg=(devs, queue))` into
  # `(to_tuple(devs), queue)` is a payload change internal to one module and breaks nobody
  # outside it. The change that actually breaks a reader is an ENUM MEMBER CHANGING
  # POSITION: `AxisType.REDUCE` at index 0 becomes `AxisType.WEAK` at index 0, and a reader
  # that adds it to an int now raises TypeError. So the predicate is: the multiset of the
  # tuple's ENUM-MEMBER ELEMENTS is preserved and their indices are not.
  #
  # SECOND NARROWING, AND IT IS THE ONE THAT MATTERS. "Reads `.arg[N]`" alone coupled 30
  # files, because 30 files index `.arg` positionally -- for their OWN payload shapes, on
  # their OWN types. `cstyle.py` reads `.arg[0]` of a `SymbolicOp`, `llvmir.py` of an
  # `LLVMType`; neither has ever heard of `UOp.range`. The predicate that holds is not
  # "reads .arg[N]" but "reads `.arg[N]` ON AN OBJECT WHOSE `arg` PAYLOAD IS THE ONE THAT
  # MOVED". So the reader must ALSO reference the enum class that got repositioned. That
  # is a real filter and it is what makes this level usable: AxisType has 4 referrents with
  # positional .arg reads (rangeify, indexing, prepare, ops itself), not 30.
  reshapers = defaultdict(set)     # file -> {enum class names it repositions}
  for f in files:
    if f not in changed_set:
      continue
    pin_t, head_t = tuple_fields(blob(pin, f), "arg"), tuple_fields(blob(head, f), "arg")
    for fn, sp in pin_t.items():
      after = head_t.get(fn)
      if after is None or after == sp:
        continue
      for _, pa in sp:
        for _, pb in after:
          if pa != pb and {m for _, m in pa} == {m for _, m in pb}:
            reshapers[f].update(m.split(".")[0] for _, m in pa)

  for f, enums in reshapers.items():
    why[f"{f} -> {f}"].add(
      f"repositions {sorted(enums)} members inside an `arg=` tuple")
  for f in files:
    if not reshapers or f in reshapers:
      continue
    src = blob(pin, f) or ""
    if not re.search(r"\.arg\[\s*\d+\s*\]", src):
      continue
    for r, enums in reshapers.items():
      if r == f:
        continue
      named = {e for e in enums if re.search(rf"\b{re.escape(e)}\b", src)}
      if named:
        couple[f].add(r)
        why[f"{f} -> {r}"].add(
          f"reads `.arg[N]` positionally and references {sorted(named)}, "
          f"which {r} repositions inside `arg=`")

  # ---- level (c): SIGNATURE changes, reported per batch as a warning ----------
  sig_delta = {}
  for f in files:
    S, T = sigs[pin][f], sigs[head][f]
    moved = sorted(k for k in set(S) | set(T) if S.get(k) != T.get(k))
    if moved:
      sig_delta[f] = {k: (S.get(k), T.get(k)) for k in moved}

  # ---- components over the coupling graph, restricted to changed files -------
  # A component only counts if it has >=1 changed file; a changed file that is coupled to
  # nothing changed is its own component of size 1 -- INDEPENDENT, move alone.
  und = defaultdict(set)
  for A, Bs in couple.items():
    if A not in changed_set:
      continue
    for B in Bs:
      if B in changed_set:
        und[A].add(B)
        und[B].add(A)

  seen, comps = set(), []
  for f in sorted(changed):
    if f in seen:
      continue
    stack, comp = [f], []
    seen.add(f)
    while stack:
      n = stack.pop()
      comp.append(n)
      for m in und[n]:
        if m not in seen:
          seen.add(m)
          stack.append(m)
    comps.append(sorted(comp))

  # ---- order inside a component: module depth, deepest dependency first -------
  def depth(f):
    mod = pkg_of(f)
    best = 0
    for m, _ in imps[head][f]:
      if m in by_mod[head]:
        d = m.count(".") + 1
        best = max(best, d)
    return best

  batches = []
  for comp in comps:
    ordered = sorted(comp, key=lambda f: (depth(f), f))
    batches.append({
      "id": len(batches) + 1, "files": ordered, "size": len(ordered),
      "edges": [{"from": k.split(" -> ")[0], "to": k.split(" -> ")[1], "why": sorted(v)}
                for k, v in why.items()
                if k.split(" -> ")[0] in comp and k.split(" -> ")[1] in comp],
      "api_delta": {f: api_delta[f] for f in ordered},
      "sig_delta": {f: sig_delta[f] for f in ordered if f in sig_delta},
    })

  # ---- per-file independence verdict, and a port-relevant flag ---------------
  port = {}
  for f in files:
    b = REPO / "tinybendygrad" / f[len("tinygrad/"):].replace(".py", ".bend")
    port[f] = str(b.relative_to(REPO)) if b.exists() else None

  res = {"pin": pin, "head": head, "changed": changed, "batches": batches,
         "independent": [f for f in changed if not und[f]],
         "port": port,
         "api_delta": {f: api_delta[f] for f in changed},
         "sig_delta": sig_delta,
         "coupling_all": {k: sorted(v) for k, v in couple.items() if v}}

  if a.json:
    print(json.dumps(res, indent=2))
    return 0

  print(f"  PIN  {pin[:12]}   HEAD {head}")
  print(f"  changed under tinygrad/: {len(changed)}")
  multi = [b for b in batches if b["size"] > 1]
  solo = [b for b in batches if b["size"] == 1]
  print(f"  batches: {len(batches)}  ({len(multi)} coupled, {len(solo)} independent "
        f"singletons)")
  print(f"  coupling is computed at NAME, ATTRIBUTE and SIGNATURE level; see the module "
        f"docstring for why the name level alone is not enough.\n")
  for b in multi:
    print(f"  BATCH {b['id']}  ({b['size']} files, MUST move together)")
    for e in b["edges"]:
      print(f"      {e['from']}  ->  {e['to']}")
      for r in e["why"]:
        print(f"            {r}")
    print("    vendor order (dependency-first):")
    for f in b["files"]:
      d = api_delta[f]
      n = len(b["sig_delta"].get(f, {}))
      print(f"      {f:<44} +{len(d['added'])} -{len(d['removed'])} ~{len(d['changed'])}"
            f"  sig~{n}  port={port[f] or '-'}")
    for f, sd in b["sig_delta"].items():
      for k, (x, y) in sd.items():
        print(f"      SIG {f}::{k}:  {x}  ->  {y}")
    print()
  if solo:
    print("  INDEPENDENT SINGLETONS (vendor alone, each one its own step):")
    for b in solo:
      f = b["files"][0]
      d = api_delta[f]
      n = len(b["sig_delta"].get(f, {}))
      print(f"      {f:<44} +{len(d['added'])} -{len(d['removed'])} ~{len(d['changed'])}"
            f"  sig~{n}  port={port[f] or '-'}")
      for k, (x, y) in b["sig_delta"].get(f, {}).items():
        print(f"          SIG {k}:  {x}  ->  {y}")
  return 0


if __name__ == "__main__":
  sys.exit(main())