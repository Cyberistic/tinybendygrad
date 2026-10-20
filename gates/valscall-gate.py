#!/usr/bin/env python3
"""valscall-gate.py -- calls that still expect ProgramInfo.vals.

    .venv/bin/python gates/valscall-gate.py
    .venv/bin/python gates/valscall-gate.py --plant

The population is an os.walk of .py files. glob is not used. .bend is not
walked, so Args.vals / Prog.vals / hwid.vals in a .bend file are out of
population by construction. The same names in a .py file are not hits either:
they are different methods.

A hit is a call of .vals that is one of:

  .arg.vals(...)          ProgramInfo is the program UOp's arg (ast.arg, ps.arg)
  a ProgramInfo binding   the receiver is ProgramInfo or assigned from it
  .vals({})               the empty-dict call, unless the receiver is Args, Prog,
                          hwid, or an instance of a class in this file that defines vals

Classification, and a hit that is none of these is UNCLASSIFIED:

  UPSTREAM     under tinygrad/, test/, or extra/, and git hash-object of the file
               equals refs/remotes/upstream/master:<path>. Not fetched. Not edited.
  OURS-LIVE    this tree owns the bytes, the path is not frozen, and the call would
               raise AttributeError on current ProgramInfo. A file under an upstream
               home whose blob does not match is this, not UPSTREAM: the match is
               the distinction, and a failed match is not a pass.
  FROZEN       under .agents/slop/, runs/, or gates/artifacts/. A retained transcript.
               Not a failure of the live class. Not edited.
  WITNESS      the call is the body of a try that catches AttributeError and asserts
               "vals". It is the proof the method is gone, not a use. Not a failure.

Exit FAIL if any OURS-LIVE hit remains. Exit PASS if every hit is UPSTREAM, FROZEN,
or WITNESS. A hit that cannot be classified, a .py file that does not parse, or a
missing upstream ref when an upstream-home hit needs it, is REFUSED, not PASS.
A walk that saw no .py file emitted nothing: DEAD.
"""
from __future__ import annotations

import ast
import os
import subprocess
import sys
import tempfile
import warnings
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402

# gate-surface reads these by ast, not by import.
VERDICTS = {0: "PASS", 1: "FAIL", 3: "REFUSED", 5: "DEAD"}
PLANTS = {
    0: ["--plant"],
    1: ["--expect", "fail"],
    3: ["--expect", "refuse"],
    5: ["--expect", "dead"],
}

SKIP = frozenset({".git", ".venv", "node_modules", "__pycache__"})
UPSTREAM_HOME = ("tinygrad/", "test/", "extra/")
RETAINED = (".agents/slop/", "runs/", "gates/artifacts/")
OTHER = frozenset({"Args", "Prog", "hwid"})
UPSTREAM_REF = "refs/remotes/upstream/master"
GIT = ("git", "--no-optional-locks")


def walk_py(root: Path):
  """os.walk + endswith. Not glob. .bend is never yielded."""
  for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = sorted(d for d in dirnames if d not in SKIP)
    for name in sorted(filenames):
      if name.endswith(".py"):
        yield Path(dirpath) / name


def _run(argv, cwd):
  return subprocess.run(argv, cwd=cwd, capture_output=True, text=True)


def git_match(root: Path):
  """(rel, path) -> match|differ|absent|unref|unhashed. Does not fetch."""
  ref = _run([*GIT, "rev-parse", "--verify", "--quiet", UPSTREAM_REF], root)
  have = ref.returncode == 0 and bool(ref.stdout.strip())

  def match(rel, path):
    if not have:
      return "unref"
    up = _run([*GIT, "rev-parse", "--verify", "--quiet", f"{UPSTREAM_REF}:{rel}"], root)
    live = _run([*GIT, "hash-object", "--", str(path)], root)
    if live.returncode != 0 or not live.stdout.strip():
      return "unhashed"
    if up.returncode != 0:
      return "absent"
    return "match" if up.stdout.strip() == live.stdout.strip() else "differ"

  return match


def parents(tree):
  out = {}
  for node in ast.walk(tree):
    for child in ast.iter_child_nodes(node):
      out[child] = node
  return out


def root_name(node):
  while isinstance(node, ast.Attribute):
    node = node.value
  return node.id if isinstance(node, ast.Name) else ""


def is_programinfo(node):
  if isinstance(node, ast.Name):
    return node.id == "ProgramInfo"
  if not isinstance(node, ast.Call):
    return False
  func = node.func
  if isinstance(func, ast.Name):
    return func.id == "ProgramInfo"
  return isinstance(func, ast.Attribute) and func.attr == "ProgramInfo"


def bound_names(tree, pred):
  found = set()
  for node in ast.walk(tree):
    if isinstance(node, ast.Assign):
      value, targets = node.value, node.targets
    elif isinstance(node, ast.AnnAssign) and node.value is not None:
      value, targets = node.value, [node.target]
    else:
      continue
    if not pred(value):
      continue
    for target in targets:
      if isinstance(target, ast.Name):
        found.add(target.id)
  return found


def vals_owners(tree):
  owners = set()
  for node in ast.walk(tree):
    if isinstance(node, ast.ClassDef) and any(
        isinstance(item, ast.FunctionDef) and item.name == "vals" for item in node.body):
      owners.add(node.name)
  return owners


def ctor_name(node):
  if not isinstance(node, ast.Call):
    return ""
  func = node.func
  return func.id if isinstance(func, ast.Name) else ""


def empty_dict(call):
  return (len(call.args) == 1 and not call.keywords and isinstance(call.args[0], ast.Dict)
          and not call.args[0].keys and not call.args[0].values)


def is_hit(call, bound, owners, instances):
  """A .vals call that resolves to ProgramInfo.vals, ast.arg.vals, or .vals({})."""
  if not (isinstance(call, ast.Call) and isinstance(call.func, ast.Attribute)
          and call.func.attr == "vals"):
    return False
  recv = call.func.value
  if root_name(recv) in OTHER:
    return False
  if isinstance(recv, ast.Name) and (recv.id in owners or recv.id in instances):
    return False
  if isinstance(recv, ast.Attribute) and recv.attr == "arg":
    return True
  if isinstance(recv, ast.Name) and (recv.id in bound or recv.id == "ProgramInfo"):
    return True
  if is_programinfo(recv):
    return True
  return empty_dict(call)


def is_witness(call, parent):
  """Caught AttributeError whose handler asserts the name vals. A proof, not a use."""
  node = parent.get(call)
  while node is not None:
    if isinstance(node, ast.Try):
      in_body = any(sub is call for stmt in node.body for sub in ast.walk(stmt))
      if in_body and _asserts_vals(node):
        return True
      return False
    node = parent.get(node)
  return False


def _asserts_vals(try_node):
  for handler in try_node.handlers:
    kind = handler.type
    name = kind.id if isinstance(kind, ast.Name) else ""
    if name != "AttributeError":
      continue
    for stmt in handler.body:
      if isinstance(stmt, ast.Assert) and "vals" in ast.unparse(stmt):
        return True
  return False


def frozen(rel):
  return rel.startswith(RETAINED)


def classify(rel, path, call, parent, match):
  if frozen(rel):
    return "FROZEN", ""
  if rel.startswith(UPSTREAM_HOME):
    state = match(rel, path)
    if state == "match":
      return "UPSTREAM", " upstream=match"
    if state in ("differ", "absent"):
      return "OURS-LIVE", f" upstream={state}"
    return "UNCLASSIFIED", f" upstream={state}"
  if is_witness(call, parent):
    return "WITNESS", ""
  return "OURS-LIVE", ""


def survey(root: Path, match):
  """Walk root. match is unused for paths outside an upstream home."""
  rows = []
  counts = {k: 0 for k in ("OURS-LIVE", "UPSTREAM", "FROZEN", "WITNESS", "UNCLASSIFIED")}
  files = calls = 0
  parse_bad = []
  if not root.is_dir():
    return REFUSED, [f"root=ABSENT {root}"], counts, 0
  for path in walk_py(root):
    files += 1
    rel = path.relative_to(root).as_posix()
    try:
      with warnings.catch_warnings():
        warnings.simplefilter("ignore", SyntaxWarning)
        tree = ast.parse(path.read_text(encoding="utf-8", errors="replace"))
    except SyntaxError as exc:
      parse_bad.append(f"{rel}:{exc.lineno or 0}")
      continue
    owners = vals_owners(tree)
    instances = bound_names(tree, lambda value: ctor_name(value) in owners)
    bound = bound_names(tree, is_programinfo)
    parent = parents(tree)
    for call in ast.walk(tree):
      if not (isinstance(call, ast.Call) and isinstance(call.func, ast.Attribute)
              and call.func.attr == "vals"):
        continue
      calls += 1
      text = ast.unparse(call)
      if not is_hit(call, bound, owners, instances):
        rows.append((rel, call.lineno, f"not-hit={rel}:{call.lineno} {text}"))
        continue
      kind, detail = classify(rel, path, call, parent, match)
      counts[kind] += 1
      rows.append((rel, call.lineno, f"hit={rel}:{call.lineno} class={kind} call={text}{detail}"))
  rows.sort()
  lines = [row for _, _, row in rows]
  lines.append(f"files={files}")
  lines.append(f"vals-calls={calls}")
  for key in ("OURS-LIVE", "UPSTREAM", "FROZEN", "WITNESS", "UNCLASSIFIED"):
    lines.append(f"{key}={counts[key]}")
  lines.append(f"parse-failed={len(parse_bad)}")
  for bad in parse_bad:
    lines.append(f"parse={bad}")
  if files == 0:
    code = DEAD
  elif parse_bad or counts["UNCLASSIFIED"]:
    code = REFUSED
  elif counts["OURS-LIVE"]:
    code = FAIL
  else:
    code = PASS
  return code, lines, counts, files


def finish(code, lines):
  if not lines:
    code = DEAD
  for line in lines:
    print(line)
  print(f"verdict={VERDICT.get(code, 'REFUSED')}")
  return code


def live():
  code, lines, _counts, _files = survey(ROOT, git_match(ROOT))
  return finish(code, lines)


def _only(text, rel, state):
  """Survey one synthetic file. state is what the upstream comparer answers."""
  with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    path = root / rel
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    code, lines, counts, _files = survey(root, lambda _rel, _path: state)
    return code, lines, counts


def expect(kind):
  if kind == "dead":
    return finish(PASS, [])
  if kind == "fail":
    code, lines, _counts = _only("info.vals({})\n", "owned/live.py", "absent")
    return finish(code, lines)
  if kind == "refuse":
    code, lines, _counts = _only("info.vals({})\n", "extra/x.py", "unref")
    return finish(code, lines)
  print(f"unknown-expect={kind}", file=sys.stderr)
  return REFUSED


def _has(lines, needle):
  return any(needle in line for line in lines)


def plant():
  """Copies. The live tree is not written. The fixture is read and not edited."""
  bad = []

  def check(name, ok):
    print(f"plant={name} {'OK' if ok else 'BAD'}")
    if not ok:
      bad.append(name)

  text = "info.vals({})\n"
  with tempfile.TemporaryDirectory() as td:
    root = Path(td)
    owned = root / "owned"
    owned.mkdir()
    (owned / "live.py").write_text(text)
    (owned / "args.py").write_text("Args.vals({})\nProg.vals(1)\nhwid.vals(x)\n")
    (owned / "launch.py").write_text('rec = {"vals": launch_vals(ast, var_vals)}\n')
    (owned / "note.bend").write_text(text)
    slop = root / ".agents" / "slop"
    slop.mkdir(parents=True)
    (slop / "live.py").write_text(text)
    runs = root / "runs"
    runs.mkdir()
    (runs / "copy.py").write_text(text)
    code, lines, counts, _files = survey(root, lambda _rel, _path: "absent")
    check("synthetic-hit", _has(lines, "hit=owned/live.py:1 class=OURS-LIVE"))
    check("synthetic-fails", code == FAIL and counts["OURS-LIVE"] == 1)
    check("slop-frozen", _has(lines, "hit=.agents/slop/live.py:1 class=FROZEN"))
    check("runs-frozen", _has(lines, "hit=runs/copy.py:1 class=FROZEN"))
    check("args-not-hit",
          _has(lines, "not-hit=owned/args.py:1 Args.vals({})")
          and _has(lines, "not-hit=owned/args.py:2 Prog.vals(1)")
          and _has(lines, "not-hit=owned/args.py:3 hwid.vals(x)"))
    check("args-not-classed", not any("args.py" in line and "class=" in line for line in lines))
    check("launch-not-hit", not any("launch.py" in line and "class=" in line for line in lines))
    check("bend-not-walked", not any(line.endswith(".bend") or ".bend:" in line for line in lines))

  slop_code, _slop_lines, slop_counts = _only(text, ".agents/slop/live.py", "absent")
  check("frozen-not-a-failure", slop_code == PASS and slop_counts["OURS-LIVE"] == 0
        and slop_counts["FROZEN"] == 1)
  live_code, _live_lines, live_counts = _only(text, "owned/live.py", "absent")
  check("uncaught-is-ours-live", live_code == FAIL and live_counts["OURS-LIVE"] == 1
        and live_counts["WITNESS"] == 0)

  witness = (
      "info = ProgramInfo()\n"
      "try:\n"
      "  info.vals({})\n"
      "except AttributeError as e:\n"
      "  assert 'vals' in str(e)\n"
  )
  wit_code, wit_lines, wit_counts = _only(witness, "owned/witness.py", "absent")
  check("witness-not-ours-live", wit_code == PASS and wit_counts["WITNESS"] == 1
        and wit_counts["OURS-LIVE"] == 0 and _has(wit_lines, "class=WITNESS"))

  up_code, up_lines, up_counts = _only(text, "extra/gemm/x.py", "match")
  check("match-is-upstream", up_code == PASS and up_counts["UPSTREAM"] == 1
        and _has(up_lines, "upstream=match"))
  dif_code, dif_lines, dif_counts = _only(text, "extra/gemm/x.py", "differ")
  check("differ-not-upstream", dif_code == FAIL and dif_counts["OURS-LIVE"] == 1
        and dif_counts["UPSTREAM"] == 0 and _has(dif_lines, "upstream=differ"))
  ref_code, _ref_lines, ref_counts = _only(text, "test/x.py", "unref")
  check("unref-is-refused", ref_code == REFUSED and ref_counts["UNCLASSIFIED"] == 1
        and ref_counts["UPSTREAM"] == 0)

  fix = ROOT / "checks/.e2e-fixture/e2e_mm.py"
  if not fix.is_file():
    check("fixture-present", False)
  else:
    src = fix.read_text(encoding="utf-8", errors="replace")
    _code, lines, counts = _only(src, "owned/fixture.py", "absent")
    check("fixture-has-launch_vals", "launch_vals(" in src)
    check("fixture-launch_vals-not-a-hit",
          counts["OURS-LIVE"] == 0 and not any(line.startswith("hit=") for line in lines))

  print(f"plant-bad={len(bad)}")
  return PASS if not bad else FAIL


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
