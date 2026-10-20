#!/usr/bin/env python3
"""rotclaim-gate.py -- a dated record is not a live claim, and the difference is a binding.

    .venv/bin/python gates/rotclaim-gate.py            # FAIL while a live sha remains
    .venv/bin/python gates/rotclaim-gate.py --report   # the census, rc=0
    .venv/bin/python gates/rotclaim-gate.py --plant    # copies; a silent direction is REFUSED

Read against `refs/remotes/upstream/master`. This file does not fetch.

A sha in prose that names the current `tinygrad/` tree is false at the next re-vendor.
A dated record with its own re-derivation command is not. Telling them apart by whether
the sentence says "was" is a prose match, and that is why the pin census over-reports.
The marker is a binding name, which is code:

  * `*_RECORD_DATE` + `*_RECORD_DERIVE`  a dated record. The command must name a commit;
    that commit's author date is read by a second git call and compared to the date.
    `sha256(x) == sha256(x)` cannot fail; this can, because the date and the object
    store are different values.
  * `*_DERIVE`  a function that replaced a deleted sha. Called, not compared to itself.
  * any other hex that prefixes a known `tinygrad/` tree value is a live claim.

A verified record owns only the lines of its own bindings. A sha on the next line is
live. A comment that says "dated record" owns nothing. An unverified record owns
nothing either: the name is not an exemption until the derivation holds.
"""
from __future__ import annotations

import ast
import hashlib
import os
import shlex
import subprocess
import sys
import tempfile
import warnings
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED  # noqa: E402

RECORD_DATE, RECORD_DERIVE, DERIVE = "_RECORD_DATE", "_RECORD_DERIVE", "_DERIVE"
GIT = ("git", "--no-optional-locks")


def load(name, path):
  import importlib.util
  spec = importlib.util.spec_from_file_location(name, path)
  mod = importlib.util.module_from_spec(spec)
  with warnings.catch_warnings():
    warnings.simplefilter("ignore")
    spec.loader.exec_module(mod)
  return mod


def pinned_mod():
  if pinned_mod.mod is None:
    pinned_mod.mod = load("rotclaim_pinned", HERE / "pinned-tree-gate.py")
  return pinned_mod.mod


pinned_mod.mod = None


def git(root, *args):
  r = subprocess.run(GIT + args, cwd=root, capture_output=True, text=True)
  return r.stdout.strip() if r.returncode == 0 else ""


def same_instant(a, b):
  def parse(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00")).astimezone(timezone.utc).replace(microsecond=0)
  try:
    return parse(a) == parse(b)
  except ValueError:
    return False


def assignments(text):
  """Module-level `NAME = "string"`, by ast. A comment is not a binding."""
  try:
    tree = ast.parse(text)
  except SyntaxError:
    return []
  out = []
  for node in tree.body:
    if not isinstance(node, ast.Assign) or len(node.targets) != 1:
      continue
    target = node.targets[0]
    if not isinstance(target, ast.Name):
      continue
    if not isinstance(node.value, ast.Constant) or not isinstance(node.value.value, str):
      continue
    out.append((target.id, node.lineno, node.end_lineno or node.lineno, node.value.value))
  return out


def records_of(text):
  """`{prefix: {date, derive}}` for complete pairs only. A date with no command is not a record."""
  found = {}
  for name, start, end, value in assignments(text):
    for suffix, key in ((RECORD_DATE, "date"), (RECORD_DERIVE, "derive")):
      if name.endswith(suffix) and len(name) > len(suffix):
        slot = found.setdefault(name[: -len(suffix)], {})
        slot[key] = (start, end, value)
  return {k: v for k, v in found.items() if "date" in v and "derive" in v}


def derives_of(text):
  """A function binding. `*_RECORD_DERIVE` is a command, and the shared suffix is not a match."""
  return {name: value for name, _, _, value in assignments(text)
          if name.endswith(DERIVE) and not name.endswith(RECORD_DERIVE)}


def verify_record(git_root, date, derive):
  """The command names a commit; a second call reads that commit's date. Not the same call twice."""
  argv = shlex.split(derive)
  if not argv or argv[0] != "git":
    return "REFUSED", "derivation is not a git command"
  ran = subprocess.run(argv, cwd=git_root, capture_output=True, text=True)
  commit = ran.stdout.strip()
  if ran.returncode != 0 or not commit:
    return "REFUSED", "derivation did not name a commit"
  if git(git_root, "cat-file", "-t", commit) != "commit":
    return "REFUSED", "derivation did not name a commit object"
  when = git(git_root, "log", "-1", "--format=%aI", commit)
  if not when or not same_instant(when, date):
    return "REFUSED", f"commit date {when or 'absent'} != record date {date}"
  new = git(git_root, "rev-parse", "--verify", "--quiet", f"{commit}:tinygrad")
  old = git(git_root, "rev-parse", "--verify", "--quiet", f"{commit}^:tinygrad")
  if not new or not old:
    return "REFUSED", "a side of the re-vendor did not resolve"
  if new == old:
    return "REFUSED", "the commit did not move tinygrad/"
  return "VERIFIED", f"date matches; the two trees differ ({old[:12]} -> {new[:12]})"


def spans(text, git_root):
  """Lines a verified record owns, and one row per record whether or not it verified."""
  owned, rows = [], []
  for prefix, pair in sorted(records_of(text).items()):
    state, detail = verify_record(git_root, pair["date"][2], pair["derive"][2])
    rows.append({"kind": "record", "name": prefix, "state": state, "detail": detail})
    if state == "VERIFIED":
      owned.append((pair["date"][0], pair["date"][1]))
      owned.append((pair["derive"][0], pair["derive"][1]))
  return owned, rows


def _main_guard(node):
  test = getattr(node, "test", None)
  return isinstance(node, ast.If) and isinstance(test, ast.Compare) and isinstance(test.left, ast.Name) \
      and test.left.id == "__name__"


def loadable(text):
  """Importing a gate must not run it. `sys.path.insert` is not a run; `sys.exit` at module scope is."""
  try:
    tree = ast.parse(text)
  except SyntaxError:
    return False
  for node in tree.body:
    if _main_guard(node):
      continue
    for sub in ast.walk(node):
      func = sub.func if isinstance(sub, ast.Call) else None
      name = func.attr if isinstance(func, ast.Attribute) else (func.id if isinstance(func, ast.Name) else "")
      if name in ("exit", "main"):
        return False
  return True


def run_derive(path, fn_name):
  text = path.read_text(errors="replace")
  if not loadable(text):
    return "REFUSED", "importing this module would run it"
  mod = load("rotclaim_" + path.stem.replace("-", "_"), path)
  fn = getattr(mod, fn_name, None)
  if not callable(fn):
    return "REFUSED", f"{fn_name} is not a function"
  try:
    ok = bool(fn())
  except Exception as exc:
    return "REFUSED", f"{type(exc).__name__}: {exc}"
  return ("OK" if ok else "FAIL"), ""


def site_line(site):
  path, _, line = site.rpartition(":")
  return path, int(line)


def _rel(display_root, path):
  try:
    return str(path.relative_to(display_root))
  except ValueError:
    return str(path)


def _generated(rel):
  """`artifacts/` is where a gate writes, and `.tmp` is staging. A sha there is a run's transcript,
  and reading it as a source claim is the stale-witness defect. Not a list of files."""
  parts = Path(rel).parts
  return "artifacts" in parts or any(p.startswith(".tmp") for p in parts)


def judge(git_root, homes, trees, display_root, run_derives=True, emit_seen=False):
  """The live path and the plant. `run_derives` is off for a temp copy: importing it is not the test.

  With `emit_seen`, every `.py` walked emits a `file` row. A judge that reads nothing and a
  judge that found nothing are the same empty list, and the plant must be able to tell them apart.
  """
  hits = pinned_mod().transcribed(display_root, homes, trees)
  rows = []
  by_file = {}
  for site, literal, _tree in hits:
    path, line = site_line(site)
    if _generated(path):
      continue
    by_file.setdefault(path, []).append((line, literal, site))
  seen = set()
  for home in homes:
    if not home.is_dir():
      continue
    for base, dirnames, files in os.walk(home):
      dirnames[:] = [n for n in dirnames if n not in ("__pycache__", "artifacts") and not n.startswith(".tmp")]
      for fname in files:
        if not fname.endswith(".py"):
          continue
        path = Path(base) / fname
        rel = _rel(display_root, path)
        text = path.read_text(errors="replace")
        owned, recs = spans(text, git_root)
        n_live = 0
        for rec in recs:
          rec["file"] = rel
          rows.append(rec)
        for line, literal, site in by_file.get(rel, []):
          if any(a <= line <= b for a, b in owned):
            continue
          n_live += 1
          rows.append({"kind": "live", "file": site, "literal": literal, "state": "LIVE"})
        if run_derives:
          for name, fn_name in sorted(derives_of(text).items()):
            state, detail = run_derive(path, fn_name)
            rows.append({"kind": "derive", "file": rel, "name": name, "fn": fn_name,
                         "state": state, "detail": detail or "-"})
        if emit_seen:
          rows.append({"kind": "file", "file": rel, "state": "SEEN", "live": n_live})
        seen.add(rel)
  # A hit in a non-.py file has no binding to own it.
  for path, items in sorted(by_file.items()):
    if path in seen:
      continue
    for _line, literal, site in items:
      rows.append({"kind": "live", "file": site, "literal": literal, "state": "LIVE"})
  return rows


def emit(row):
  return "\t".join([row["kind"]] + [f"{k}={v}" for k, v in row.items() if k != "kind"])


def live_rows():
  pinned = pinned_mod()
  trees = pinned.tree_values(ROOT)
  if not trees:
    return []
  return judge(ROOT, pinned.homes(ROOT), trees, ROOT, run_derives=True)


def _count(rows, kind, state=None):
  return sum(1 for r in rows if r["kind"] == kind and (state is None or r["state"] == state))


def assess(text, trees, git_root):
  with tempfile.TemporaryDirectory(prefix="rotclaim-") as td:
    root = Path(td)
    home = root / "gates"
    home.mkdir()
    (home / "fixture.py").write_text(text)
    return judge(git_root, [home], trees, root, run_derives=False, emit_seen=True)


def plant():
  """Copies of the two files, plus copied arguments to `identity_holds`. The comparator is the real one.

  A direction that emits no row is REFUSED, even if every emitted row says OK. That is the
  plant that scores success while measuring nothing.
  """
  pinned = pinned_mod()
  trees = pinned.tree_values(ROOT)
  cur = pinned.resolve(ROOT, "HEAD:tinygrad")
  retired = next((t for t in trees if t != cur), "")
  if not cur or not retired:
    print("rotclaim-gate --plant: REFUSED -- fewer than two tree values, so the plant would test a constant")
    return REFUSED
  decoy = hashlib.sha1(b"rotclaim-not-a-tree").hexdigest()
  if any(t.startswith(decoy) for t in trees):
    print("rotclaim-gate --plant: REFUSED -- the decoy prefixes a real tree")
    return REFUSED
  fresh = (HERE / "corpusfresh-gate.py").read_text()
  flip = (HERE / "groupflip-gate.py").read_text()
  date = records_of(fresh)["REVENDOR"]["date"][2]
  gf = load("rotclaim_groupflip", HERE / "groupflip-gate.py")
  rows = []

  def check(label, got, want):
    if got is None:
      rows.append(f"plant.{label}\tstate=REFUSED\tverdict=SILENT\twanted={want}")
      return
    rows.append(f"plant.{label}\tstate={'OK' if got == want else 'REFUSED'}\tverdict={got}\twanted={want}")

  def classified(text):
    got = assess(text, trees, ROOT)
    if not any(r["kind"] == "file" for r in got):
      return None
    return (_count(got, "live"), next((r["state"] for r in got if r["kind"] == "record"), "ABSENT"))

  # The control is the unmutated copy. Every other direction is that copy, changed in one place.
  check("record-control", classified(fresh), (0, "VERIFIED"))
  check("sha-on-the-next-line-is-live", classified(fresh + f"\n# {retired}\n"), (1, "VERIFIED"))
  kept, skip = [], False
  for ln in fresh.splitlines():
    if ln.startswith("REVENDOR_RECORD_DERIVE"):
      skip = True
      continue
    if skip:
      skip = ln.strip() != ")"
      continue
    if ln.startswith("REVENDOR_RECORD_DATE"):
      continue
    kept.append(ln)
  prose = "\n".join(kept) + f"\n# On 2026-10-20 this was a dated record, MEASURED by git log.\n# {retired}\n"
  check("prose-does-not-exempt", classified(prose), (1, "ABSENT"))
  check("not-a-tree-is-not-a-hit", classified(fresh + f"\n# {decoy}\n"), (0, "VERIFIED"))
  broken = fresh.replace(f'REVENDOR_RECORD_DATE = "{date}"',
                         'REVENDOR_RECORD_DATE = "1999-01-01T00:00:00Z"', 1)
  check("wrong-date-is-not-verified", classified(broken), (0, "REFUSED"))
  broken_sha = broken.replace('REVENDOR_RECORD_DATE = "1999-01-01T00:00:00Z"',
                              f'REVENDOR_RECORD_DATE = "1999-01-01T00:00:00Z"  # {retired}', 1)
  check("unverified-record-does-not-own-its-sha", classified(broken_sha), (1, "REFUSED"))
  check("groupflip-absence", classified(flip), (0, "ABSENT"))
  check("groupflip-sha-put-back", classified(flip + f"\n# {retired}\n"), (1, "ABSENT"))
  check("identity-control", gf.identity_holds(cur, cur, ("slot", "dtype")), True)
  check("identity-diverges", gf.identity_holds(cur, retired, ("slot",)), False)
  check("identity-size", gf.identity_holds(cur, cur, ("slot", "size")), False)
  check("identity-vacuous", gf.identity_holds("", "", ()), False)
  check("record-command-is-not-a-function", "REVENDOR_RECORD_DERIVE" in derives_of(fresh), False)
  check("identity-binding-names-the-function", derives_of(flip).get("IDENTITY_DERIVE"), "vendored_identity")
  try:
    live = gf.vendored_identity()
  except Exception as exc:
    live = f"RAISED {type(exc).__name__}"
  check("identity-live-read", live, True)

  ok = sum(1 for r in rows if "\tstate=OK\t" in r)
  print("\n".join(rows))
  print(f"rotclaim-gate --plant: {'OK' if ok == len(rows) and rows else 'REFUSED'} ({ok} of {len(rows)})")
  return PASS if ok == len(rows) and rows else REFUSED


def main(argv=None):
  warnings.filterwarnings("ignore", category=SyntaxWarning)
  argv = sys.argv[1:] if argv is None else argv
  if "--plant" in argv:
    return plant()
  rows = live_rows()
  if not rows:
    print("rotclaim-gate: DEAD -- no rows")
    return DEAD
  print("\n".join(emit(r) for r in rows))
  live, refused = _count(rows, "live"), sum(1 for r in rows if r["state"] in ("REFUSED", "FAIL"))
  print(f"rotclaim-gate: live={live} refused={refused} rows={len(rows)}")
  if "--report" in argv:
    return PASS
  if live or refused:
    return FAIL
  return PASS


if __name__ == "__main__":
  sys.exit(main())
