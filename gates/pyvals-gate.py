#!/usr/bin/env python3
"""pyvals-gate.py -- does the PythonProgram harvest still read a `vals` key anything passes?

    .venv/bin/python gates/pyvals-gate.py
    .venv/bin/python gates/pyvals-gate.py --plant

The harvest is discovered, not named by line: a function assigned onto
`PythonProgram.__call__` that calls `kw.get("vals", ...)`. The signature a caller
is judged against is the one installed at that call, not the class method the
assignment replaced. A `Class.__call__ = fn` in the same function, where `fn`
reads `kw.get("vals")`, installs that signature until a later assignment replaces
it. A caller under that assignment is `wrapped-caller` and is not `LIVE-CALLER`.
A caller that passes `vals=` with the wrapper not installed is still
`LIVE-CALLER`. "Has vals" means a parameter named `vals`, or the body calling
`.get("vals")`. `**kw` swallows a key; it does not name one, and it is not
acceptance.

The caller population is an os.walk of `.py` files. glob is not used. `.bend` is
not walked, so a Bend `Args.vals` is out of population by construction. A hit is
a call with keyword `vals` whose callee is bound, in that file, to the hooked
class: a constructor, `__new__`, or `.runtime()` on the device whose `ops_*.py`
passes that class into `Compiled`. `helper_test_op(..., vals=)` is a different
function. `var_vals=` is a different key. Retained trees (`.agents/slop/`,
`runs/`, `gates/artifacts/`) are not live callers.

Exit FAIL if a live caller passes `vals=` into a signature that lacks it, the
wrapper not being installed at that call. Exit PASS with row `KEY-REAL` if the
caller is under the installed wrapper and the wrapper reads the key. Exit FAIL
with row `DEAD-READER` if the harvest reads a key the class signature does not
accept and no caller passes it — that is not PASS. Exit PASS if the class
signature accepts `vals` and a caller passes it, or the harvest defaults to `()`
and the signature accepts the key and nobody passes it. A walk that saw no
`.py` file is DEAD. A harvest or a signature that cannot be read is REFUSED.

The two paths in `CONTROL` are the calls commit `ec9bcf31a` stopped passing
`vals=` into. They are a control, not a population: the walk must not report
them as live callers. They are not edited here.
"""
from __future__ import annotations

import ast
import os
import sys
import tempfile
import warnings
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402

VERDICTS = {0: "PASS", 1: "FAIL", 3: "REFUSED", 5: "DEAD"}
PLANTS = {
  0: ["--plant"],
  1: ["--expect", "fail"],
  3: ["--expect", "refuse"],
  5: ["--expect", "dead"],
}

SKIP = frozenset({".git", ".venv", "node_modules", "__pycache__", "references"})
RETAINED = (".agents/slop/", "runs/", "gates/artifacts/")
# The brief's control, not the population. Two calls that used to pass vals= and no longer do.
CONTROL = (
  "extra/gemm/triton_nv_matmul.py",
  "test/external/external_benchmark_op_conv.py",
)
KEY = "vals"


def walk_py(root: Path):
  """os.walk + endswith. Not glob. .bend is never yielded."""
  for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = sorted(d for d in dirnames if d not in SKIP)
    for name in sorted(filenames):
      if name.endswith(".py"):
        yield Path(dirpath) / name


def parse(path: Path):
  with warnings.catch_warnings():
    warnings.simplefilter("ignore", SyntaxWarning)
    return ast.parse(path.read_text(encoding="utf-8", errors="replace"))


def parents(tree):
  out = {}
  for node in ast.walk(tree):
    for child in ast.iter_child_nodes(node):
      out[child] = node
  return out


def rel_of(path: Path, root: Path):
  try:
    return path.relative_to(root).as_posix()
  except ValueError:
    return path.as_posix()


def frozen(rel):
  return rel.startswith(RETAINED)


def hooked_of(target):
  """`(class name, module alias or "")` for `Alias.Class.__call__` or `Class.__call__`."""
  if not isinstance(target, ast.Attribute) or target.attr != "__call__":
    return None
  inner = target.value
  if isinstance(inner, ast.Name):
    return inner.id, ""
  if isinstance(inner, ast.Attribute) and isinstance(inner.value, ast.Name):
    return inner.attr, inner.value.id
  return None


def enclosing_function(parent, node):
  while node is not None:
    node = parent.get(node)
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)):
      return node
  return None


def module_of(tree, alias):
  """Import alias -> dotted module. `from tinygrad.runtime import ops_python as OPY`."""
  if not alias:
    return ""
  for node in ast.walk(tree):
    if isinstance(node, ast.ImportFrom) and node.module:
      for item in node.names:
        if (item.asname or item.name) == alias:
          return f"{node.module}.{item.name}" if item.asname else node.module
    if isinstance(node, ast.Import):
      for item in node.names:
        if (item.asname or item.name) == alias:
          return item.name
  return ""


def module_path(root: Path, dotted):
  if not dotted:
    return None
  path = root.joinpath(*dotted.split(".")).with_suffix(".py")
  return path if path.is_file() else None


def class_import(tree, class_name):
  for node in ast.walk(tree):
    if isinstance(node, ast.ImportFrom) and node.module:
      for item in node.names:
        if item.name == class_name:
          return node.module
  return ""


def find_class(tree, class_name):
  for node in ast.walk(tree):
    if isinstance(node, ast.ClassDef) and node.name == class_name:
      return node
  return None


def call_method(cls):
  if cls is None:
    return None
  for item in cls.body:
    if isinstance(item, ast.FunctionDef) and item.name == "__call__":
      return item
  return None


def base_name(cls):
  if cls is None or not cls.bases:
    return ""
  base = cls.bases[0]
  if isinstance(base, ast.Name):
    return base.id
  if isinstance(base, ast.Subscript) and isinstance(base.value, ast.Name):
    return base.value.id
  if isinstance(base, ast.Attribute):
    return base.attr
  return ""


def sig_names(fn):
  args = fn.args
  return [a.arg for a in [*args.posonlyargs, *args.args, *args.kwonlyargs] if a.arg != "self"]


def kw_gets(fn):
  found = []
  for node in ast.walk(fn):
    if not (isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.func.attr == "get"):
      continue
    if node.args and isinstance(node.args[0], ast.Constant) and isinstance(node.args[0].value, str):
      found.append((node.args[0].value, node))
  return found


def empty_default(node):
  if len(node.args) < 2:
    return False
  default = node.args[1]
  if isinstance(default, ast.Tuple) and not default.elts:
    return True
  return (isinstance(default, ast.Call) and isinstance(default.func, ast.Name)
          and default.func.id == "tuple" and not default.args and not default.keywords)


def assignment_pairs(node):
  """Simple `a = b` and the unpack `a, b = c, d`. The live harvest is the second form."""
  if not isinstance(node, ast.Assign):
    return
  for target in node.targets:
    if (isinstance(target, (ast.Tuple, ast.List)) and isinstance(node.value, (ast.Tuple, ast.List))
        and len(target.elts) == len(node.value.elts)):
      yield from zip(target.elts, node.value.elts)
    else:
      yield target, node.value


def find_harvests(tree):
  """Every wrapper assigned onto `Class.__call__`. Tuple unpacks count: the live site is one."""
  parent = parents(tree)
  found = []
  for node in ast.walk(tree):
    if not isinstance(node, ast.Assign):
      continue
    owner = enclosing_function(parent, node)
    body = owner.body if owner is not None else tree.body
    for target, value in assignment_pairs(node):
      hooked = hooked_of(target)
      if hooked is None or not isinstance(value, ast.Name):
        continue
      for stmt in body:
        if isinstance(stmt, ast.FunctionDef) and stmt.name == value.id:
          found.append((hooked[0], hooked[1], stmt, node.lineno))
          break
  return found


def accepts(fn):
  """A named parameter, or the body reading the key. `**kw` is neither."""
  names = sig_names(fn)
  reads = [key for key, _node in kw_gets(fn)]
  kwarg = fn.args.kwarg.arg if fn.args.kwarg else ""
  return KEY in names or KEY in reads, names, kwarg, reads


def aliases_of(tree, hooked):
  names = {hooked}
  for node in ast.walk(tree):
    if isinstance(node, ast.ImportFrom):
      for item in node.names:
        if item.name == hooked:
          names.add(item.asname or item.name)
  return names


def device_key(node):
  if not (isinstance(node, ast.Subscript) and isinstance(node.value, ast.Name) and node.value.id == "Device"):
    return ""
  sl = node.slice
  if isinstance(sl, ast.Constant) and isinstance(sl.value, str):
    return sl.value.split(":")[0].upper()
  return ""


def assignments(stmt):
  if isinstance(stmt, ast.Assign):
    for target in stmt.targets:
      yield target, stmt.value
  elif isinstance(stmt, ast.AnnAssign) and stmt.value is not None:
    yield stmt.target, stmt.value


def is_ctor(node, aliases):
  if not isinstance(node, ast.Call):
    return False
  func = node.func
  if isinstance(func, ast.Name) and func.id in aliases:
    return True
  if isinstance(func, ast.Attribute) and func.attr in aliases:
    return True
  if isinstance(func, ast.Attribute) and func.attr == "__new__":
    inner = func.value
    if isinstance(inner, ast.Name) and inner.id in aliases:
      return True
    if isinstance(inner, ast.Attribute) and inner.attr in aliases:
      return True
  return False


def runtime_dev(node, devices, runtime_devices):
  if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute) or node.func.attr != "runtime":
    return ""
  recv = node.func.value
  dev = devices.get(recv.id, "") if isinstance(recv, ast.Name) else device_key(recv)
  return dev if dev in runtime_devices else ""


def is_program(node, aliases, devices, runtime_devices):
  return is_ctor(node, aliases) or bool(runtime_dev(node, devices, runtime_devices))


def kw_set(call):
  return {kw.arg for kw in call.keywords if kw.arg}


_NEST = (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef, ast.If, ast.For, ast.AsyncFor,
         ast.While, ast.With, ast.AsyncWith, ast.Try)


def calls_in(stmt):
  """Calls in this statement, not in a nested body. The body walker enters those itself."""
  stack = list(ast.iter_child_nodes(stmt))
  while stack:
    node = stack.pop()
    if isinstance(node, _NEST):
      continue
    if isinstance(node, ast.Call):
      yield node
    stack.extend(ast.iter_child_nodes(node))


def child_bodies(stmt):
  if isinstance(stmt, (ast.If, ast.For, ast.AsyncFor, ast.While)):
    return [stmt.body, stmt.orelse]
  if isinstance(stmt, (ast.With, ast.AsyncWith)):
    return [stmt.body]
  if isinstance(stmt, ast.Try):
    return [stmt.body, stmt.orelse, stmt.finalbody, *[h.body for h in stmt.handlers]]
  return []


def callee_hit(call, names, attrs):
  func = call.func
  if isinstance(func, ast.Name):
    return func.id in names
  if isinstance(func, ast.Attribute) and isinstance(func.value, ast.Name) and func.value.id == "self":
    return func.attr in attrs
  return False


def bind_target(target, value, names, devices, aliases, runtime_devices):
  dev = device_key(value)
  if dev and isinstance(target, ast.Name):
    devices[target.id] = dev
  if is_program(value, aliases, devices, runtime_devices) and isinstance(target, ast.Name):
    names.add(target.id)


def self_attrs(cls, aliases, runtime_devices):
  attrs = set()
  for item in cls.body:
    if not isinstance(item, ast.FunctionDef):
      continue
    devices = {}
    for stmt in item.body:
      for target, value in assignments(stmt):
        if not is_program(value, aliases, devices, runtime_devices):
          dev = device_key(value)
          if dev and isinstance(target, ast.Name):
            devices[target.id] = dev
          continue
        if isinstance(target, ast.Attribute) and isinstance(target.value, ast.Name) and target.value.id == "self":
          attrs.add(target.attr)
  return attrs


def fn_reads(scope, name):
  """True if a function in this body reads `kw.get("vals")`. A restore name does not."""
  return any(isinstance(item, ast.FunctionDef) and item.name == name and KEY in [k for k, _n in kw_gets(item)]
             for item in scope)


def note_install(stmt, scope, hooked, installed):
  """`Class.__call__ = fn` installs fn until a later assignment replaces it. Same function only."""
  if not isinstance(stmt, ast.Assign):
    return
  for target, value in assignment_pairs(stmt):
    got = hooked_of(target)
    if got is None or got[0] != hooked or not isinstance(value, ast.Name):
      continue
    installed[0] = fn_reads(scope, value.id)


def scan_body(body, names, devices, attrs, aliases, runtime_devices, rel, hits, shaped,
              hooked, scope, installed, wrapped):
  for stmt in body:
    if isinstance(stmt, (ast.FunctionDef, ast.AsyncFunctionDef)):
      scan_function(stmt, names, devices, attrs, aliases, runtime_devices, rel, hits, shaped, hooked, wrapped)
      continue
    if isinstance(stmt, ast.ClassDef):
      scan_class(stmt, names, devices, aliases, runtime_devices, rel, hits, shaped, hooked, wrapped)
      continue
    note_install(stmt, scope, hooked, installed)
    subs = child_bodies(stmt)
    if subs:
      for sub in subs:
        scan_body(sub, names, devices, attrs, aliases, runtime_devices, rel, hits, shaped,
                  hooked, scope, installed, wrapped)
      continue
    for target, value in assignments(stmt):
      bind_target(target, value, names, devices, aliases, runtime_devices)
    under = installed[0]
    for call in calls_in(stmt):
      if KEY not in kw_set(call):
        continue
      text = ast.unparse(call)
      if len(text) > 72:
        text = text[:69] + "..."
      row = (rel, call.lineno, text)
      if callee_hit(call, names, attrs):
        (wrapped if under else hits).append(row)
      elif "global_size" in kw_set(call) or "local_size" in kw_set(call):
        shaped.append(row)


def scan_function(fn, outer_names, outer_devices, attrs, aliases, runtime_devices, rel, hits, shaped, hooked, wrapped):
  scan_body(fn.body, set(outer_names), dict(outer_devices), attrs, aliases, runtime_devices, rel, hits, shaped,
            hooked, fn.body, [False], wrapped)


def scan_class(cls, outer_names, outer_devices, aliases, runtime_devices, rel, hits, shaped, hooked, wrapped):
  attrs = self_attrs(cls, aliases, runtime_devices)
  for item in cls.body:
    if isinstance(item, ast.FunctionDef):
      scan_function(item, outer_names, outer_devices, attrs, aliases, runtime_devices, rel, hits, shaped, hooked, wrapped)


def file_hits(tree, rel, hooked, runtime_devices):
  aliases = aliases_of(tree, hooked)
  hits, shaped, wrapped = [], [], []
  scan_body(tree.body, set(), {}, set(), aliases, runtime_devices, rel, hits, shaped,
            hooked, tree.body, [False], wrapped)
  return hits, shaped, wrapped


def passes_runtime(tree, hooked):
  """`super().__init__(..., HookedClass)` — the device's runtime class, read off the call."""
  for node in ast.walk(tree):
    if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute) or node.func.attr != "__init__":
      continue
    for arg in [*node.args, *(kw.value for kw in node.keywords)]:
      if isinstance(arg, ast.Name) and arg.id == hooked:
        return True
      if isinstance(arg, ast.Attribute) and arg.attr == hooked:
        return True
  return False


def runtime_devices(root: Path, hooked):
  """Device keys whose `ops_*.py` passes the hooked class to `Compiled`. Filename stem is the key,
  which is `device.py`'s own rule (`stem[len("ops_"):].upper()`), not a second list of devices."""
  found = set()
  base = root / "tinygrad" / "runtime"
  if not base.is_dir():
    return found
  for dirpath, dirnames, filenames in os.walk(base):
    dirnames[:] = sorted(d for d in dirnames if d not in SKIP)
    for name in filenames:
      if not (name.startswith("ops_") and name.endswith(".py")):
        continue
      path = Path(dirpath) / name
      try:
        tree = parse(path)
      except SyntaxError:
        continue
      if passes_runtime(tree, hooked):
        found.add(path.stem[len("ops_"):].upper())
  return found


def sig_row(kind, path, root, fn, class_name):
  ok, names, kwarg, reads = accepts(fn)
  rel = rel_of(path, root)
  return (f"{kind}={rel}:{fn.lineno} class={class_name} has-vals={int(ok)} "
          f"kwarg={kwarg or '-'} params={','.join(names) or '-'} body-reads={','.join(reads) or '-'}"), ok


def load_sig(root, harvest_path, harvest_tree, hooked, alias):
  dotted = module_of(harvest_tree, alias) or class_import(harvest_tree, hooked)
  path = module_path(root, dotted)
  if path is None and find_class(harvest_tree, hooked) is not None:
    path = harvest_path
  if path is None:
    return None, None, None, f"signature=ABSENT class={hooked} import={dotted or '-'}"
  try:
    tree = parse(path)
  except SyntaxError as exc:
    return None, None, None, f"signature=PARSE class={hooked} {rel_of(path, root)}:{exc.lineno or 0}"
  cls = find_class(tree, hooked)
  fn = call_method(cls)
  if fn is None:
    return None, None, None, f"signature=NO-CALL class={hooked} file={rel_of(path, root)}"
  row, ok = sig_row("signature", path, root, fn, hooked)
  base_row = ""
  base = base_name(cls)
  if base:
    base_path = module_path(root, class_import(tree, base))
    if base_path is None and find_class(tree, base) is not None:
      base_path = path
    if base_path is not None:
      try:
        base_fn = call_method(find_class(parse(base_path), base))
      except SyntaxError:
        base_fn = None
      if base_fn is not None:
        base_row, _base_ok = sig_row("base", base_path, root, base_fn, base)
  return row, ok, base_row, ""


def judge(has_vals, live_callers, reads_key, default_empty, wrapped=0):
  """Return `(code, row)`. DEAD-READER is a row, and its exit is FAIL.

  `wrapped` is a caller under the installed wrapper. That signature reads the key,
  so the call is not `LIVE-CALLER`. A caller with the wrapper not installed stays
  in `live_callers`.
  """
  if live_callers and not has_vals:
    return FAIL, "LIVE-CALLER"
  if live_callers and has_vals:
    return PASS, "KEY-REAL"
  if wrapped and reads_key:
    return PASS, "KEY-REAL"
  if reads_key and not has_vals:
    return FAIL, "DEAD-READER"
  if default_empty and not live_callers and has_vals:
    return PASS, "DEFAULT-EMPTY"
  if not reads_key and not live_callers:
    return PASS, "NO-READER"
  return REFUSED, "UNCLASSIFIED"


def survey(root: Path):
  if not root.is_dir():
    return REFUSED, [f"root=ABSENT {root}"], {}
  files = 0
  parse_bad = []
  harvests = []
  frozen_harvests = []
  for path in walk_py(root):
    files += 1
    rel = rel_of(path, root)
    try:
      tree = parse(path)
    except SyntaxError as exc:
      parse_bad.append(f"{rel}:{exc.lineno or 0}")
      continue
    for hooked, alias, wrapper, lineno in find_harvests(tree):
      gets = [(key, node) for key, node in kw_gets(wrapper) if key == KEY]
      if not gets:
        continue
      bucket = frozen_harvests if frozen(rel) else harvests
      bucket.append((path, rel, tree, hooked, alias, wrapper, lineno, gets))
  lines = [f"files={files}"]
  if files == 0:
    return DEAD, lines, {"files": 0}
  if parse_bad:
    lines.extend(f"parse={bad}" for bad in parse_bad)
    lines.append(f"parse-failed={len(parse_bad)}")
    return REFUSED, lines, {"files": files}
  for _path, hrel, _tree, hooked, _alias, _wrapper, lineno, hgets in frozen_harvests:
    lines.append(f"frozen-harvest={hrel}:{hgets[0][1].lineno if hgets else lineno} class={hooked}")
  if len(harvests) != 1:
    lines.append(f"harvests={len(harvests)}")
    for _path, hrel, _tree, hooked, _alias, _wrapper, lineno, _gets in harvests:
      lines.append(f"harvest-site={hrel}:{lineno} class={hooked}")
    return REFUSED, lines, {"files": files}
  path, rel, tree, hooked, alias, _wrapper, lineno, gets = harvests[0]
  reads = bool(gets)
  default_empty = bool(gets) and all(empty_default(node) for _key, node in gets)
  lines.append(f"harvest={rel}:{gets[0][1].lineno if gets else lineno} class={hooked} "
               f"key={KEY if reads else '-'} reads={int(reads)} default-empty={int(default_empty)}")
  sig, has_vals, base_row, err = load_sig(root, path, tree, hooked, alias)
  if err:
    lines.append(err)
    return REFUSED, lines, {"files": files}
  lines.append(sig)
  if base_row:
    lines.append(base_row)
  devices = runtime_devices(root, hooked)
  lines.append(f"runtime-devices={','.join(sorted(devices)) or '-'}")
  live, frozen_hits, shaped, wrapped = [], [], [], []
  keywords = 0
  for py in walk_py(root):
    prel = rel_of(py, root)
    try:
      ptree = parse(py)
    except SyntaxError:
      continue
    for node in ast.walk(ptree):
      if isinstance(node, ast.Call) and KEY in kw_set(node):
        keywords += 1
    hits, near, wrap = file_hits(ptree, prel, hooked, devices)
    for hit in hits:
      (frozen_hits if frozen(hit[0]) else live).append(hit)
    for hit in wrap:
      if not frozen(hit[0]):
        wrapped.append(hit)
    shaped.extend(near)
  live.sort()
  frozen_hits.sort()
  shaped.sort()
  wrapped.sort()
  for hit_rel, hit_line, text in live:
    lines.append(f"caller={hit_rel}:{hit_line} {text}")
  for hit_rel, hit_line, text in wrapped:
    lines.append(f"wrapped-caller={hit_rel}:{hit_line} {text}")
  for hit_rel, hit_line, text in frozen_hits:
    lines.append(f"frozen-caller={hit_rel}:{hit_line} {text}")
  for hit_rel, hit_line, text in shaped:
    if not any(hit_rel == c[0] and hit_line == c[1] for c in live):
      lines.append(f"not-hook={hit_rel}:{hit_line} {text}")
  lines.append(f"callers={len(live)}")
  lines.append(f"wrapped-count={len(wrapped)}")
  lines.append(f"frozen-callers={len(frozen_hits)}")
  lines.append(f"vals-keywords={keywords}")
  held = 0
  for control in CONTROL:
    named = any(c[0] == control for c in live)
    lines.append(f"control={control} {'caller' if named else 'not-caller'}")
    held += not named
  lines.append(f"control-held={held} of {len(CONTROL)}")
  code, row = judge(has_vals, live, reads, default_empty, len(wrapped))
  lines.append(f"row={row}")
  return code, lines, {"files": files, "callers": len(live), "row": row, "lines": lines}


def finish(code, lines):
  if not lines and code != DEAD:
    code = DEAD
  for line in lines:
    print(line)
  print(f"verdict={VERDICT.get(code, 'REFUSED')}")
  return code


def live():
  code, lines, _info = survey(ROOT)
  return finish(code, lines)


def _write(root: Path, rel, text):
  path = root / rel
  path.parent.mkdir(parents=True, exist_ok=True)
  path.write_text(text)
  return path


PROG_LACKS = (
  "class PythonProgram:\n"
  "  def __call__(self, *args, global_size=(1, 1, 1), local_size=(1, 1, 1), wait=False, **kw):\n"
  "    return kw.get('env', ())\n"
)
PROG_HAS = (
  "class PythonProgram:\n"
  "  def __call__(self, *args, vals=(), global_size=(1, 1, 1), local_size=(1, 1, 1), wait=False):\n"
  "    return vals\n"
)
HARVEST = (
  "from prog import PythonProgram\n"
  "def call(self, *bufs, **kw):\n"
  "  return kw.get('vals', ())\n"
  "PythonProgram.__call__ = call\n"
)
CALLER = (
  "from prog import PythonProgram\n"
  "def go():\n"
  "  prog = PythonProgram()\n"
  "  prog(1, vals=(2,))\n"
)
# The call is under the assignment, in the same function. The wrapper reads the key.
INSTALLED_CALL = (
  "from prog import PythonProgram\n"
  "def harvest():\n"
  "  def call(self, *bufs, **kw):\n"
  "    return kw.get('vals', ())\n"
  "  PythonProgram.__call__ = call\n"
  "  prog = PythonProgram()\n"
  "  prog(1, vals=(2,))\n"
)
TUPLE_HARVEST = (
  "from prog import PythonProgram\n"
  "def harvest():\n"
  "  def call(self, *bufs, **kw):\n"
  "    return kw.get('vals', ())\n"
  "  PythonProgram.render, PythonProgram.__call__ = None, call\n"
)


def _tree(prog, caller=False):
  td = tempfile.TemporaryDirectory()
  root = Path(td.name)
  _write(root, "prog.py", prog)
  _write(root, "harvest.py", HARVEST)
  if caller:
    _write(root, "owned/live.py", CALLER)
  return td, root


def plant():
  """Copies. The live tree is not written."""
  bad = []

  def check(name, ok):
    print(f"plant={name} {'OK' if ok else 'BAD'}")
    if not ok:
      bad.append(name)

  td, root = _tree(PROG_LACKS, caller=True)
  try:
    code, lines, info = survey(root)
    # Wrapper is assigned in harvest.py. This caller is in another file, so the
    # wrapper is not installed at the call. Evidence must be emitted, not only scored.
    shown = [line for line in lines if line.startswith(("caller=", "row="))]
    for line in shown:
      print(f"plant-out uninstalled {line}")
    check("wrapper-not-installed-is-fail",
          bool(shown) and code == FAIL and info.get("row") == "LIVE-CALLER"
          and any(line.startswith("caller=owned/live.py:") for line in shown))
    check("caller-is-fail", code == FAIL and info.get("row") == "LIVE-CALLER"
          and any(line.startswith("caller=owned/live.py:") for line in lines))
    check("caller-not-dead-reader", info.get("row") != "DEAD-READER")
  finally:
    td.cleanup()

  td = tempfile.TemporaryDirectory()
  try:
    root = Path(td.name)
    _write(root, "prog.py", PROG_LACKS)
    _write(root, "harvest.py", INSTALLED_CALL)
    code, lines, info = survey(root)
    shown = [line for line in lines if line.startswith(("wrapped-caller=", "caller=", "row=", "harvest="))]
    for line in shown:
      print(f"plant-out installed {line}")
    check("wrapper-installed-not-fail",
          bool(shown) and code == PASS and info.get("row") == "KEY-REAL"
          and any(line.startswith("wrapped-caller=") for line in shown)
          and not any(line.startswith("caller=") for line in shown))
  finally:
    td.cleanup()

  td, root = _tree(PROG_LACKS, caller=False)
  try:
    code, lines, info = survey(root)
    check("no-caller-is-dead-reader", code == FAIL and info.get("row") == "DEAD-READER")
    check("dead-reader-not-pass", code != PASS and "verdict=PASS" not in lines)
  finally:
    td.cleanup()

  td, root = _tree(PROG_HAS, caller=True)
  try:
    code, _lines, info = survey(root)
    check("signature-has-vals-is-pass", code == PASS and info.get("row") == "KEY-REAL")
  finally:
    td.cleanup()

  td = tempfile.TemporaryDirectory()
  try:
    root = Path(td.name)
    _write(root, "prog.py", PROG_LACKS)
    _write(root, "harvest.py", TUPLE_HARVEST)
    _write(root, "owned/live.py", CALLER)
    code, lines, info = survey(root)
    check("tuple-unpack-is-the-harvest", code == FAIL and info.get("row") == "LIVE-CALLER"
          and any(line.startswith("harvest=harvest.py:") for line in lines))
  finally:
    td.cleanup()

  td, root = _tree(PROG_LACKS, caller=False)
  try:
    _write(root, "note.bend", "prog(vals=(1,))\n")
    _write(root, "other.py", "def helper(vals=()):\n  return vals\nhelper(vals=1)\n")
    for control in CONTROL:
      src = ROOT / control
      if not src.is_file():
        check(f"control-present {control}", False)
        continue
      _write(root, control, src.read_text(encoding="utf-8", errors="replace"))
    code, lines, info = survey(root)
    check("bend-not-walked", not any(".bend" in line for line in lines))
    check("helper-not-caller", not any(line.startswith("caller=other.py:") for line in lines))
    check("fixed-copies-not-callers",
          all(f"control={c} not-caller" in lines for c in CONTROL) and info.get("row") == "DEAD-READER")
    check("dead-reader-with-fixed-copies", code == FAIL)
  finally:
    td.cleanup()

  td, root = _tree(PROG_LACKS, caller=False)
  try:
    _write(root, "ops_metal.py", "class MetalDevice:\n  def __init__(self):\n    super().__init__(MetalProgram)\n")
    _write(root, "metal.py",
           "def go():\n  dev = Device['METAL']\n  prg = dev.runtime(b'')\n"
           "  prg(1, global_size=(1, 1, 1), vals=(1,))\n")
    _code, lines, info = survey(root)
    check("other-device-not-hook", not any(line.startswith("caller=metal.py:") for line in lines)
          and info.get("row") == "DEAD-READER")
  finally:
    td.cleanup()

  live_code, live_lines, live_info = survey(ROOT)
  check("live-control",
        all(f"control={c} not-caller" in live_lines for c in CONTROL)
        and not any(line.startswith("caller=extra/gemm/triton_nv_matmul.py:")
                    or line.startswith("caller=test/external/external_benchmark_op_conv.py:")
                    for line in live_lines))
  check("live-ran", live_code in (PASS, FAIL) and "row=" in "".join(f"row={live_info.get('row', '')}"))

  print(f"plant-bad={len(bad)}")
  return PASS if not bad else FAIL


def expect(kind):
  if kind == "dead":
    with tempfile.TemporaryDirectory() as td:
      code, lines, _info = survey(Path(td))
    return finish(code, lines)
  if kind == "fail":
    td, root = _tree(PROG_LACKS, caller=True)
    try:
      code, lines, _info = survey(root)
    finally:
      td.cleanup()
    return finish(code, lines)
  if kind == "refuse":
    with tempfile.TemporaryDirectory() as td:
      root = Path(td)
      _write(root, "harvest.py", HARVEST)
      code, lines, _info = survey(root)
    return finish(code, lines)
  print(f"unknown-expect={kind}", file=sys.stderr)
  return REFUSED


def main(argv):
  if "--plant" in argv:
    return plant()
  if "--expect" in argv:
    at = argv.index("--expect")
    if at + 1 >= len(argv):
      print("expect=ABSENT", file=sys.stderr)
      return REFUSED
    return expect(argv[at + 1])
  return live()


if __name__ == "__main__":
  sys.exit(main(sys.argv[1:]))
