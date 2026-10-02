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
  3. COUPLING, at FOUR LEVELS. A is coupled to B iff, at either revision of A, A
     REFERENCES something of B's that moved in the window:
       (a) NAME level   -- `from tinygrad.x import n`, n added/removed/rebound in B.
                           Measured failure: ops.py alone -> ImportError: axis_to_pos.
       (b) ATTR level   -- `Cls.member` where member was added to / removed from a class
                           B defines, INCLUDING methods and including exported singletons
                           (`dtypes = DTypes()`, so `dtypes.i8` is an attribute of the
                           instance and callers never see the class). Measured failure:
                           cstyle.py alone -> AttributeError: 'DTypes' has no i8.
       (c) SIG level    -- a def/method's parameter list changed. A call site with the old
                           arity is a TypeError, which no name diff will show. Reported as
                           a per-batch warning, not an edge: a signature change only couples
                           the caller if the caller is also in the batch.
       (d) TUPLE level  -- a positional payload's field order changed: `arg=(axis_id,
                           axis_type)` -> `arg=(axis_type, axis_id)`. Nothing is renamed and
                           no signature changed; every `X.arg[0]` reader now reads the other
                           field. Measured failure: rangeify.py -> `'AxisType' + 'int'`.
                           Narrowed to ENUM MEMBERS CHANGING POSITION, because the
                           unrestricted rule fuses 30 files into one batch, which is
                           "vendor it all" wearing a lab coat.
     Levels (a), (b) and (d) are checked SYMMETRICALLY: both revisions of the importer,
     because re-vendoring produces a MIXED tree and either half can be the stale one.
     A file that references nothing that moved is INDEPENDENT and can move alone.

     Every batch this file reports is an UPPER BOUND. The authority is
     `.agents/slop/rebase-try.sh --shrink <id>`, which builds the batch in a temp tree and
     drops one file at a time. Measured: batch 1 came out of this pass at 21 files and
     shrinks to 17 required, 4 droppable.
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


# `tinygrad/<...>.py` as it is SPELLED inside a header. A `.bend` header writes the
# source path verbatim (`# kernel.bend -- tinygrad/codegen/__init__.py`) and a
# multi-source port writes several, one per file, which is why `codegen/rewriter.bend`
# is the port of THREE upstream files and why a one-source map cannot describe it.
_SRC_RE = re.compile(r"tinygrad/[A-Za-z0-9_./]*\.py")

# ...AND THE BARE FORM, because a multi-source header WRAPS and drops the prefix on
# its continuation lines. `codegen/rewriter.bend`'s first three lines are
#
#   # rewriter.bend -- tinygrad/codegen/simplify.py + codegen/late/coalesce.py +
#   # codegen/gpudims.py: the REWRITE TABLES the lowerer runs, in the compiled form
#
# so `gpudims.py` and `coalesce.py` are spelled WITHOUT `tinygrad/` and a regex that
# demands the prefix misses both -- which is how the FIRST version of this map
# answered `None` for the very file this whole fix is about.
_BARE_RE = re.compile(r"(?<![\w/])((?:[a-z_0-9]+/)*[a-z_0-9]+\.py)\b")


def header_ports():
  """{tinygrad path: [port .bend paths]} read out of the ports' OWN headers.

  A port's name is not derivable from its source's name: `codegen/__init__.py` is
  ported by `codegen/kernel.bend`, `codegen/gpudims.py` by
  `codegen/rewriter.bend`, and `codegen/decomp/transcendental.py` by
  `codegen/transcendental.bend`. Inferring it by string surgery under-reported
  B1 by two ports, and since `rebase-gate.py --batch 1` builds its port list from
  this map, two ports in a live batch were gated by NOTHING while compiling and
  running normally -- a silent pass, which is worse than a red file.

  So the map is READ, not guessed. THREE FILTERS, and each one was found by
  running this and looking at what it returned:

  * Only the FIRST FEW LINES, and only lines whose comment names THE FILE ITSELF.
    Scanning 40 lines collected every incidental path mention in a comment about
    some other file's drift: `uop/ops.py` came back with five ports, because
    `fold.bend`, `fold2_work.bend`, `fold_mm_work.bend` and `LAWS/spec.bend` all
    quote it in their headers while porting something else.
  * A leading `_` or a `_work` suffix marks a MUTATION or SCRATCH copy --
    `_tc_coefonly.bend`, `_tcmut_transcendental_M04.bend`, `fold2_work.bend` --
    and a scratch copy carries its original's header verbatim, so including them
    reported `codegen/decomp/transcendental.py` with TEN ports of which nine were
    somebody's throwaway. This is the `hdr-audit` shape: a name match is not a
    claim, and the copy is not a claim either.
  * The name in the comment must be THE FILE'S OWN NAME, in ANY SPELLING. This filter was
    `body.startswith(f"{stem}.bend")`, which matches only the BARE-STEM spelling, and it
    silently dropped 57 of the 111 `.bend` files in the tree -- measured, by re-running
    this function with the test relaxed. A header that spells the port's PATH
    (`# tinybendygrad/renderer/cstyle.bend -- tinygrad/renderer/cstyle.py`) or its
    directory-relative path (`# codegen/late/gater.bend -- port of tinygrad/codegen/
    late/gater.py`) failed the test, and with it the `tinygrad/...py` citation on the very
    next token. Both spellings are the file naming ITSELF, which is exactly what this
    filter is supposed to detect, so both are accepted: the first token of the header
    comment must be a path ENDING in `<stem>.bend`. The "a comment about a DIFFERENT
    file" property the filter exists for is preserved, because that is still a
    name-equality test on the port's own name -- it is just not a PREFIX test on one
    spelling of it.

    Cost of getting this wrong, measured on the current window: 7 port-relevant changed
    files got a wrong or missing port answer, and `tinygrad/runtime/ops_null.py` --
    a file in the live batch -- came back `None` while `tinybendygrad/runtime/
    ops_cpu_null.bend` was sitting right there porting it. A gate that skips a port
    silently reads exactly like a gate that passed.

  Everything a filter rejects is a port that EXISTED and is deliberately not
  counted, so the filters are stated rather than applied quietly."""
  out = defaultdict(list)
  for b in sorted((REPO / "tinybendygrad").rglob("*.bend")):
    stem = b.stem
    if stem.startswith("_") or stem.endswith("_work"):
      continue                      # a mutation or scratch copy, not a port
    try:
      head = b.read_text(errors="replace").split("\n")[:6]
    except OSError:
      continue
    seen = False
    block = False
    for line in head:
      st = line.lstrip()
      if not st.startswith("#"):
        break                       # provenance is the header; the code follows
      body = st.lstrip("# ").strip()
      if not block:
        tok = body.split()[0] if body.split() else ""
        tok = tok.removeprefix("tinybendygrad/").removeprefix("./")
        if not (tok == f"{stem}.bend" or tok.endswith(f"/{stem}.bend")):
          continue                  # a comment about a DIFFERENT file
        block = seen = True
      for src in _SRC_RE.findall(line):
        out[src].append(str(b.relative_to(REPO)))
      for bare in _BARE_RE.findall(line):
        out["tinygrad/" + bare].append(str(b.relative_to(REPO)))
    if not seen:
      continue
  return {k: sorted(set(v)) for k, v in out.items()}


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


CONTAINERS = {"Dict", "Set", "List", "Tuple", "call:dict", "call:set", "call:frozenset",
              "call:list", "call:tuple", "call:bytearray"}


def rebound_breaks(a, b):
  """Did this attribute go from one CONTAINER to a DIFFERENT one?

  The only rebinding an importer can observe without a name change. Two representations
  count, because upstream writes both: `_loaded_ = set()` and `_loaded_ = {}` are the same
  type and AST-different literals, and the head of this window uses the second form.
  Scoped to containers on purpose: the unrestricted "the binding's syntax changed" rule
  fires 25 times on `dtypes.*`, because 793abbb16 rewrites `int8 = DType.new(...)` as the
  legacy alias `int8 = i8` -- the same DType object under a second name, not a retyped
  attribute -- and coupling all 25 of those readers fused a 32-file batch out of two.
  """
  return a in CONTAINERS and b in CONTAINERS and a != b


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

  def kind(v):
    """What KIND of thing a binding is: its constructor's name, or its node type.

    Comparing the whole `ast.dump` instead would fire on every cosmetic edit to a default
    and fuse 37 files into one batch -- which is "vendor it all" again, in a lab coat.
    Comparing the KIND catches the change that actually breaks a caller: `DLL._loaded_`
    going from `set()` to `dict()` leaves the name resolving at both ends while every
    `.values()` call on it starts raising `AttributeError`.
    """
    if v is None:
      return "<none>"
    if isinstance(v, ast.Call):
      f = v.func
      return f"call:{ast.unparse(f)}" if isinstance(f, (ast.Name, ast.Attribute)) else "call:*"
    return type(v).__name__

  def members(body):
    # name -> KIND of binding. Presence alone misses a real coupling (elf.py rebinds
    # `DLL._loaded_` from a set to a dict); full-dump comparison creates hundreds of false
    # ones. The kind is the only granularity that is both sound and quiet.
    m = {}
    for s in body:
      if isinstance(s, ast.Assign):
        for t in s.targets:
          if isinstance(t, ast.Name):
            m[t.id] = kind(s.value)
      elif isinstance(s, ast.AnnAssign) and isinstance(s.target, ast.Name):
        # The VALUE decides the type, never the annotation. `_loaded_: set[str] = set()`
        # versus `_loaded_: dict[str, CDLL] = {}` annotates a different type and binds a
        # different one, and reading `kind()` off `s.annotation` would report "Name" twice
        # and miss the only rebinding in the window that a caller can actually observe.
        m[s.target.id] = kind(s.value) if s.value else "<none>"
      elif isinstance(s, (ast.FunctionDef, ast.AsyncFunctionDef)):
        m[s.name] = "<method>"
      elif isinstance(s, ast.ClassDef):
        m[s.name] = "<class>"
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
        elif attr in ma and attr in mb and rebound_breaks(ma[attr], mb[attr]):
          # Present at both ends, bound to a DIFFERENT CONTAINER, which is the one rebinding
          # a caller can observe: `DLL._loaded_` going from `set()` to `dict()` leaves the
          # name resolving everywhere while every `.values()` call on it starts raising
          # AttributeError. Scoped to builtins because the general rule produced 25 false
          # couplings on `dtypes.*`: 793abbb16 rewrites `int8 = DType.new(...)` as
          # `int8 = i8`, and a Name-vs-Call difference there is a legacy ALIAS pointing at
          # the same object, not a retyped attribute. The `attr in ma` guard matters
          # separately -- `Ops` is an Enum whose members resolve dynamically, and indexing
          # its table for a name it never declared raises KeyError, not "not a member".
          couple[f].add(bp)
          why[f"{f} -> {bp}"].add(
            f"{rev}-side use of REBOUND `{cls}.{attr}`: {ma[attr]} -> {mb[attr]}")

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
  #
  # A PORT'S NAME IS NOT DERIVABLE FROM ITS SOURCE'S NAME. This used to be
  # `tinybendygrad/<same path>.py -> .bend`, i.e. pure string surgery, and it was
  # WRONG for every port that flattens or merges:
  #
  #   tinygrad/codegen/__init__.py   -> tinybendygrad/codegen/kernel.bend
  #   tinygrad/codegen/gpudims.py    -> tinybendygrad/codegen/rewriter.bend
  #   tinygrad/codegen/decomp/transcendental.py -> tinybendygrad/codegen/transcendental.bend
  #
  # MEASURED, and the cost was not "two files look unported": it was that
  # `rebase-gate.py --batch 1` builds its port list from this map, so two ports in
  # B1 were gated by NOTHING while still compiling and still running. A gate that
  # silently skips its ports reads exactly like a gate that passed.
  #
  # THE FIX IS TO ASK THE PORT, not to guess. Every `.bend` states its upstream
  # source in its own first lines -- `# kernel.bend -- tinygrad/codegen/__init__.py`
  # -- and 97 of them do, so the header is a machine-readable map that was already
  # in the tree and nobody read. Read the first 40 lines of each `.bend`, find
  # `tinygrad/...py` citations, and index THEM.
  #
  # The guess is kept as a FALLBACK and is reported as such, because a fallback that
  # is silent is the original bug: `port[f]` carries `how` so the JSON says whether
  # the answer came from a header or from the guess.
  port = {}
  for f in files:
    rel = f[len("tinygrad/"):]
    guess = REPO / "tinybendygrad" / rel.replace(".py", ".bend")
    by_header = header_ports().get(f, [])
    if by_header:
      port[f] = by_header
    elif guess.exists():
      port[f] = [str(guess.relative_to(REPO))]
    else:
      port[f] = None

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
  print(f"  coupling is computed at NAME, ATTRIBUTE, SIGNATURE and TUPLE-PAYLOAD level; the "
        f"module docstring says which measured failure each level is responsible for.\n")
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