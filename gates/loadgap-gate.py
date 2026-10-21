#!/usr/bin/env python3
"""loadgap-gate -- class the LOAD-BEARING no-blob paths noblob-census names.

    .venv/bin/python gates/loadgap-gate.py
    .venv/bin/python gates/loadgap-gate.py --plant

`gates/noblob-census.py` is LOADED BY PATH. The set is its LOAD-BEARING rows,
re-derived. PRIOR is a comparison, not a population: if the count is not 27 the
tree moved, and a path is not dropped to keep 27.

THE CLASS IS THE CITER'S, not a list of paths. See `RULE`. REQUIRED fails.
PASS only when every load-bearing path is PROBE or RECIPE-ABSENT. UNSORTED is
printed and fails: an unclassified input must not hide in PASS.

The plant is on copies. A header line `ORACLE: <path>` of a never-committed
path is REQUIRED. The same path cited only from a function named `probe` is
PROBE. A citer that says `absent by design` is RECIPE-ABSENT. A sentence that
says the oracle path is gone is not REQUIRED. A line that binds `ORACLE =` to
the path is REQUIRED. A path that exists is not in the set.
"""
from __future__ import annotations

import argparse
import ast
import importlib.util
import os
import re
import subprocess
import sys
import tempfile
import time
import warnings
from collections import Counter
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402

CENSUS = HERE / "noblob-census.py"
# A comparison, not a population. The count below is re-derived.
PRIOR = 27
REQUIRED = "REQUIRED"
PROBE = "PROBE"
RECIPE = "RECIPE-ABSENT"
UNSORTED = "UNSORTED"
CLASSES = (REQUIRED, PROBE, RECIPE, UNSORTED)
# Exact name. `probe_extra` is a different function and is not this class.
PROBE_FUNC = "probe"
ABSENT = re.compile(r"(?i)absent\s+by\s+design")
# Read from the span after path tokens are blanked. A filename cannot supply the word.
MISSING = re.compile(r"(?i)\b(?:gone|absent)\b|never\s+committed")
ORACLE_BIND = re.compile(r"\bORACLE\s*=")
ORACLE_WORD = re.compile(r"(?i)\boracle\b")
ORACLE_HEADER = re.compile(r"^\s*#\s*ORACLE:\s+\S")
PATH_TOKEN = re.compile(r"(?<![\w./])[\w./-]*\.[\w.-]+")
RUNNER_WORD = re.compile(r"(?i)(?:python3?|sh|bash|bend)\s+(\S+)")
ROW_WORD = re.compile(r"(?i)\brows?\b|\bGATE\b")
SCRIPT_KIND = re.compile(r"(?i)probe|scratch|mutate")
RULE = (
    "A LOAD-BEARING path is classed from its load citers (role load; a plant-class citer "
    "does not decide). The span of a # comment is the contiguous comment paragraph, broken "
    "at a blank line or a lone #; any other citer's span is its line. RECIPE-ABSENT when a "
    "span says absent by design -- the words are read from the span, and no path is listed. "
    "PROBE when every load citer lies in a function named exactly probe, or the path is a "
    "probe, scratch, or mutate script (a component or the basename contains probe, scratch, "
    "or mutate) and every load citer is a note (a # comment or a docstring line) or the citer "
    "file is itself a mutate harness or a slop note. REQUIRED when the path has never existed "
    "and a load citer is a header line ORACLE: <path>, or the line binds ORACLE = to the path, "
    "or the line names the path as the oracle (the word oracle remains after path tokens are "
    "blanked), or a header command runs the path as the program that produces a gate's rows. "
    "A span that says the path is gone, absent, or never committed is not REQUIRED: the words "
    "are read from that span after path tokens are blanked, so a filename does not supply them, "
    "and no path is listed. A line that binds ORACLE = to the path, and a header command that "
    "runs the path, stay REQUIRED. A span that says absent by design wins over REQUIRED. A path "
    "cited only from probe() is PROBE, not REQUIRED. Anything else is UNSORTED, printed, and not a skip."
)


def git(args: list[str]) -> subprocess.CompletedProcess:
  env = {k: v for k, v in os.environ.items() if k != "GIT_INDEX_FILE"}
  return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, env=env)


def load_census():
  """Import the generator by path. `gates/` is not a package."""
  if not CENSUS.is_file():
    return None
  spec = importlib.util.spec_from_file_location("loadgap_noblob", CENSUS)
  if spec is None or spec.loader is None:
    return None
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  if not callable(getattr(mod, "load_dangling", None)) or not callable(getattr(mod, "derive", None)):
    return None
  return mod


def load_bearing(rows: list[dict], nb) -> list[dict]:
  """Every LOAD-BEARING row. A logged one is kept: the count is not trimmed to PRIOR."""
  return [r for r in rows if r.get("cite") == nb.LOAD]


def _parse(body: str):
  try:
    with warnings.catch_warnings():
      warnings.simplefilter("ignore", SyntaxWarning)
      return ast.parse(body)
  except SyntaxError:
    return None


def header_lines(body: str) -> set[int]:
  """1-based lines of the leading # run. A shebang is skipped. A blank may sit inside it."""
  lines = body.splitlines()
  i = 1 if lines and lines[0].startswith("#!") else 0
  start = None
  end = None
  while i < len(lines):
    s = lines[i].strip()
    if s == "" or s.startswith("#"):
      if s.startswith("#"):
        if start is None:
          start = i
        end = i
      i += 1
      continue
    break
  if start is None:
    return set()
  return set(range(start + 1, end + 2))


def docstring_lines(body: str) -> set[int]:
  tree = _parse(body)
  if tree is None:
    return set()
  out: set[int] = set()
  for node in ast.walk(tree):
    stmts = getattr(node, "body", None)
    if not isinstance(stmts, list) or not stmts:
      continue
    first = stmts[0]
    value = first.value if isinstance(first, ast.Expr) else None
    if (isinstance(value, ast.Constant) and isinstance(value.value, str)
        and value.end_lineno is not None):
      out.update(range(value.lineno, value.end_lineno + 1))
  return out


def probe_lines(body: str) -> set[int]:
  """Lines inside a function named exactly `probe`. A body that does not parse has none."""
  tree = _parse(body)
  if tree is None:
    return set()
  out: set[int] = set()
  for node in ast.walk(tree):
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == PROBE_FUNC:
      if node.end_lineno is not None:
        out.update(range(node.lineno, node.end_lineno + 1))
  return out


def paragraph(lines: list[str], n: int) -> str:
  """The comment paragraph around 1-based `n`, or the line itself when it is not a comment."""
  if n < 1 or n > len(lines) or not lines[n - 1].lstrip().startswith("#"):
    return lines[n - 1] if 1 <= n <= len(lines) else ""

  def comment(i: int) -> bool:
    return 0 <= i < len(lines) and lines[i].lstrip().startswith("#")

  def lone(i: int) -> bool:
    return comment(i) and lines[i].strip() == "#"

  lo = n - 1
  while lo > 0 and comment(lo - 1) and not lone(lo - 1):
    lo -= 1
  hi = n - 1
  while hi + 1 < len(lines) and comment(hi + 1) and not lone(hi + 1):
    hi += 1
  return "\n".join(lines[lo:hi + 1])


def blanked(line: str) -> str:
  """Path tokens removed, so `oracle` inside a filename is not the word oracle."""
  return PATH_TOKEN.sub(" ", line)


def says_missing(span: str) -> bool:
  """The span says the cited path is gone, absent, or never committed. See `RULE`."""
  return MISSING.search(blanked(span)) is not None


def is_script(path: str) -> bool:
  parts = path.split("/")
  return any(SCRIPT_KIND.search(p) for p in parts)


def is_note_site(rel: str, n: int, line: str, docs: set[int]) -> bool:
  """A # comment, a docstring line, a mutate harness, or a slop note. Discovered from the citer."""
  if line.lstrip().startswith("#") or n in docs:
    return True
  name = rel.rsplit("/", 1)[-1]
  return "mutate" in name or rel.startswith(".agents/slop/")


def _runner(line: str, path: str, para: str, in_header: bool) -> bool:
  """A header command whose program is `path`, in a paragraph that mentions rows or GATE."""
  if not in_header or path not in line or not ROW_WORD.search(para):
    return False
  for m in RUNNER_WORD.finditer(line):
    if m.group(1).strip("`'\",") == path:
      return True
  return re.search(r"(?<![\w./-])\./" + re.escape(path) + r"(?![\w./-])", line) is not None


def class_of(path: str, citers: list[tuple[str, int, str]], bodies: dict[str, str], never: bool) -> tuple[str, list[str]]:
  """`(class, deciding citers)`. See `RULE`. A missing body cannot be shown to be a class, so it is not one."""
  load = [(rel, n, role) for rel, n, role in citers if role == "load"]
  if not load:
    return UNSORTED, []
  spans: list[tuple[str, str, bool, bool]] = []
  probe_only = True
  notes = True
  for rel, n, _role in load:
    body = bodies.get(rel)
    if body is None:
      probe_only = False
      notes = False
      spans.append((f"{rel}:{n}", "", False, False))
      continue
    lines = body.splitlines()
    line = lines[n - 1] if 1 <= n <= len(lines) else ""
    key = f"{rel}:{n}"
    in_probe = n in probe_lines(body)
    probe_only = probe_only and in_probe
    note = is_note_site(rel, n, line, docstring_lines(body))
    notes = notes and note
    spans.append((key, paragraph(lines, n) if line.lstrip().startswith("#") else line, in_probe, note))
  absent = [key for key, span, _p, _n in spans if ABSENT.search(span)]
  if absent:
    return RECIPE, absent
  if probe_only:
    return PROBE, [key for key, _s, _p, _n in spans]
  if never:
    required = []
    for rel, n, _role in load:
      body = bodies.get(rel)
      if body is None:
        continue
      lines = body.splitlines()
      if not (1 <= n <= len(lines)):
        continue
      line = lines[n - 1]
      para = paragraph(lines, n)
      in_header = n in header_lines(body)
      # A span that says the path is gone does not name it as an oracle that must exist.
      # A binding and a header runner are not that span, and are not demoted.
      missing = says_missing(para)
      hit = False
      if in_header and ORACLE_HEADER.search(line) and path in line and not missing:
        hit = True
      if ORACLE_BIND.search(line) and path in line:
        hit = True
      if path in line and ORACLE_WORD.search(blanked(line)) and not missing:
        hit = True
      if _runner(line, path, para, in_header):
        hit = True
      if hit:
        required.append(f"{rel}:{n}")
    if required:
      return REQUIRED, required
  if is_script(path) and notes:
    return PROBE, [key for key, _s, _p, note in spans if note]
  return UNSORTED, [key for key, _s, _p, _n in spans]


def classify(rows: list[dict], bodies: dict[str, str], nb) -> list[dict]:
  out = []
  for r in rows:
    citers = []
    for c in r["citers"]:
      rel, _, ns = c.rpartition(":")
      citers.append((rel, int(ns), r["roles"].get(c, "load")))
    kind, why = class_of(r["path"], citers, bodies, r["class"] == nb.NEVER)
    out.append({**r, "gap": kind, "why": why})
  return out


def _bodies(dang, fs: Path) -> dict[str, str]:
  bodies, _deriv = dang.namer_population(fs)
  return dict(bodies)


def derive_set(nb, dang, fs: Path) -> tuple[dict, list[dict]]:
  surveyed = dang.census(fs)
  got = nb.derive(dang, surveyed, fs)
  rows = classify(load_bearing(got["rows"], nb), _bodies(dang, fs), nb)
  return got, rows


def report(got: dict, rows: list[dict]) -> None:
  head = git(["rev-parse", "HEAD"]).stdout.strip()
  stamp = got.get("stamp") or time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
  n = len(rows)
  print(f"loadgap-gate   HEAD {head}   {stamp}")
  print("  COMMAND        .venv/bin/python gates/loadgap-gate.py")
  print("  DERIVED        noblob-census derive(), cite LOAD-BEARING")
  if n == PRIOR:
    print(f"  TREE           unmoved from the prior reading {PRIOR}")
  else:
    print(f"  TREE MOVED     prior reading {PRIOR}, this reading {n}. No path was dropped to keep {PRIOR}.")
  print(f"  LOAD-BEARING   {n}")
  by = {k: [r for r in rows if r["gap"] == k] for k in CLASSES}
  print(f"  RULE           {RULE}")
  for label in CLASSES:
    print(f"  {label:<16} {len(by[label])}")
  for label in CLASSES:
    print(f"  {label} NAMED  {len(by[label])}")
    for r in by[label]:
      print(f"    {r['path']}")
      print(f"      citers {', '.join(r['why']) if r['why'] else '-'}")


def check(rows: list[dict]) -> tuple[int, str]:
  if not rows:
    return DEAD, "LOAD-BEARING 0; a pass over nothing is not a pass"
  bad = [r["path"] for r in rows if r["gap"] not in CLASSES]
  if bad:
    return FAIL, f"{len(bad)} path(s) carry no class: {bad[:5]}"
  tally = Counter(r["gap"] for r in rows)
  if sum(tally[k] for k in CLASSES) != len(rows):
    return FAIL, f"classes sum to {sum(tally[k] for k in CLASSES)} over {len(rows)}"
  if tally[REQUIRED] or tally[UNSORTED]:
    return FAIL, (f"{len(rows)} load-bearing, " + " ".join(f"{k}={tally[k]}" for k in CLASSES))
  return PASS, (f"{len(rows)} load-bearing, " + " ".join(f"{k}={tally[k]}" for k in CLASSES))


def _plant_path(leaf: str) -> str:
  """Built by concatenation, so this file does not cite the plant path as one token."""
  return ".agents" + "/" + "slop/loadgap-plant/" + leaf


def _insert_header(text: str, line: str) -> str:
  lines = text.splitlines(keepends=True)
  i = 1 if lines and lines[0].startswith("#!") else 0
  lines.insert(i, line if line.endswith("\n") else line + "\n")
  return "".join(lines)


def _writer(surveyed: dict) -> str | None:
  writers = sorted({n for ns in surveyed["subjects"].values() for n in ns
                    if n.endswith(".py") and n.startswith("gates/") and (ROOT / n).is_file()
                    and n != "gates/loadgap-gate.py"})
  parsing = []
  for w in writers:
    if _parse((ROOT / w).read_text(errors="replace")) is None:
      continue
    parsing.append(w)
  if not parsing:
    return None
  parsing.sort(key=lambda w: (ROOT / w).stat().st_size)
  return parsing[0]


def _existing(surveyed: dict) -> str | None:
  for p in sorted(surveyed["head"]):
    if (ROOT / p).is_file():
      return p
  return None


def _print_check(name: str, ok: bool, detail: str) -> bool:
  print(f"  {'OK  ' if ok else 'FAIL'}  {name}")
  print(f"        {detail}")
  return ok


def _copy_rows(nb, dang, writer: str, text: str) -> list[dict] | None:
  try:
    ast.parse(text)
  except SyntaxError as exc:
    print(f"PLANT REFUSED: the copy namer does not parse: {exc}")
    return None
  with tempfile.TemporaryDirectory(prefix="loadgap-plant.") as tmp:
    copy = Path(tmp) / "repo"
    dest = copy / writer
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(text)
    try:
      _got, rows = derive_set(nb, dang, copy)
    except Exception as exc:  # noqa: BLE001 -- a plant that hides this scores success on nothing
      print(f"PLANT REFUSED: derive did not answer: {type(exc).__name__}: {exc}")
      return None
  return rows


def _row(rows: list[dict], path: str) -> dict | None:
  for r in rows:
    if r["path"] == path:
      return r
  return None


PLANT_REQUIRED = (
    "PLANT header ORACLE: line is REQUIRED",
    "FALSIFY that header line is not PROBE and not RECIPE-ABSENT",
    "FALSIFY the same path cited only from probe() is PROBE",
    "FALSIFY that probe() citation is not REQUIRED",
    "PLANT a citer that says absent by design is RECIPE-ABSENT",
    "FALSIFY absent-by-design is not REQUIRED",
    "PLANT a header runner that produces rows is REQUIRED",
    "FALSIFY by design without absent is not RECIPE-ABSENT",
    "CONTROL an existing file is not in the set",
    "PLANT a sentence that the oracle is gone is not REQUIRED",
    "PLANT a sentence that the oracle is absent is not REQUIRED",
    "PLANT a sentence that the oracle was never committed is not REQUIRED",
    "PLANT ORACLE = binding is REQUIRED",
)


def plant(nb, dang, surveyed: dict) -> int:
  """The shapes, on copies, plus the falsifications and the existing-file control."""
  writer = _writer(surveyed)
  control = _existing(surveyed)
  if writer is None or control is None:
    print(f"PLANT REFUSED: writer={writer} control={control}")
    return REFUSED
  never = _plant_path("does-not-exist.py")
  recipe = _plant_path("recipe-absent.bin")
  runner = _plant_path("row-runner.py")
  kept = _plant_path("kept-by-design.py")
  # Concatenated, so this file does not cite the plant path as one token.
  gone = ".agents" + "/" + "slop/" + "gone.py"
  noted = _plant_path("noted.py")
  own = CENSUS.read_text(errors="replace") + (HERE / "loadgap-gate.py").read_text(errors="replace")
  dang_mod = dang
  own_toks = set(dang_mod.tokens(own))
  already = set(surveyed.get("dangling", [])) | set(surveyed.get("subjects", {}))
  for path in (never, recipe, runner, kept, gone, noted):
    if path in own_toks or path in already or (ROOT / path).exists():
      print(f"PLANT REFUSED: {path} is already a token, a subject, or a file")
      return REFUSED
  base = (ROOT / writer).read_text(errors="replace")
  checks: list[tuple[str, bool, str]] = []
  print(f"  PLANT writer={writer}")

  both = _insert_header(base, f"# ORACLE: {never}\n# ORACLE: {control}\n")
  rows = _copy_rows(nb, dang, writer, both)
  if rows is None:
    return REFUSED
  got = _row(rows, never)
  checks.append(("PLANT header ORACLE: line is REQUIRED",
                 got is not None and got["gap"] == REQUIRED,
                 f"gap={None if got is None else got['gap']} path={never}"))
  checks.append(("FALSIFY that header line is not PROBE and not RECIPE-ABSENT",
                 got is not None and got["gap"] not in (PROBE, RECIPE),
                 f"gap={None if got is None else got['gap']}"))
  checks.append(("CONTROL an existing file is not in the set",
                 control not in {r["path"] for r in rows},
                 f"in-rows={control in {r['path'] for r in rows}} path={control}"))
  for name, good, detail in checks:
    _print_check(name, good, detail)

  probed = base + f"\ndef probe():\n    return {never!r}\n"
  rows = _copy_rows(nb, dang, writer, probed)
  if rows is None:
    return REFUSED
  got = _row(rows, never)
  pair = [
      ("FALSIFY the same path cited only from probe() is PROBE",
       got is not None and got["gap"] == PROBE,
       f"gap={None if got is None else got['gap']} path={never}"),
      ("FALSIFY that probe() citation is not REQUIRED",
       got is not None and got["gap"] != REQUIRED,
       f"gap={None if got is None else got['gap']}"),
  ]
  for name, good, detail in pair:
    checks.append((name, good, detail))
    _print_check(name, good, detail)

  absent = _insert_header(base, f"# {recipe} is absent by design\n")
  rows = _copy_rows(nb, dang, writer, absent)
  if rows is None:
    return REFUSED
  got = _row(rows, recipe)
  pair = [
      ("PLANT a citer that says absent by design is RECIPE-ABSENT",
       got is not None and got["gap"] == RECIPE,
       f"gap={None if got is None else got['gap']} path={recipe}"),
      ("FALSIFY absent-by-design is not REQUIRED",
       got is not None and got["gap"] != REQUIRED,
       f"gap={None if got is None else got['gap']}"),
  ]
  for name, good, detail in pair:
    checks.append((name, good, detail))
    _print_check(name, good, detail)

  ran = _insert_header(base, f"# THE GATE. the rows\n#   .venv/bin/python {runner}\n")
  rows = _copy_rows(nb, dang, writer, ran)
  if rows is None:
    return REFUSED
  got = _row(rows, runner)
  checks.append(("PLANT a header runner that produces rows is REQUIRED",
                 got is not None and got["gap"] == REQUIRED,
                 f"gap={None if got is None else got['gap']} path={runner}"))
  _print_check(checks[-1][0], checks[-1][1], checks[-1][2])

  plain = _insert_header(base, f"# {kept} is kept by design\n")
  rows = _copy_rows(nb, dang, writer, plain)
  if rows is None:
    return REFUSED
  got = _row(rows, kept)
  checks.append(("FALSIFY by design without absent is not RECIPE-ABSENT",
                 got is not None and got["gap"] != RECIPE,
                 f"gap={None if got is None else got['gap']} path={kept}"))
  _print_check(checks[-1][0], checks[-1][1], checks[-1][2])

  said = _insert_header(base, f"# the oracle `{gone}` is gone\n")
  rows = _copy_rows(nb, dang, writer, said)
  if rows is None:
    return REFUSED
  got = _row(rows, gone)
  checks.append(("PLANT a sentence that the oracle is gone is not REQUIRED",
                 got is not None and got["gap"] != REQUIRED,
                 f"gap={None if got is None else got['gap']} path={gone}"))
  _print_check(checks[-1][0], checks[-1][1], checks[-1][2])

  for name, line, path in (
      ("PLANT a sentence that the oracle is absent is not REQUIRED",
       f"# the oracle `{noted}` is absent\n", noted),
      ("PLANT a sentence that the oracle was never committed is not REQUIRED",
       f"# the oracle `{noted}` was never committed\n", noted),
  ):
    rows = _copy_rows(nb, dang, writer, _insert_header(base, line))
    if rows is None:
      return REFUSED
    got = _row(rows, path)
    checks.append((name, got is not None and got["gap"] != REQUIRED,
                   f"gap={None if got is None else got['gap']} path={path}"))
    _print_check(checks[-1][0], checks[-1][1], checks[-1][2])

  bound = _insert_header(base, f"ORACLE = [{gone!r}]\n")
  rows = _copy_rows(nb, dang, writer, bound)
  if rows is None:
    return REFUSED
  got = _row(rows, gone)
  checks.append(("PLANT ORACLE = binding is REQUIRED",
                 got is not None and got["gap"] == REQUIRED,
                 f"gap={None if got is None else got['gap']} path={gone}"))
  _print_check(checks[-1][0], checks[-1][1], checks[-1][2])

  missing = [n for n in PLANT_REQUIRED if n not in {c[0] for c in checks}]
  if missing:
    _print_check("plant emitted every required check", False, ", ".join(missing))
    return FAIL
  bad = [n for n, good, _d in checks if not good]
  if bad:
    print(f"  VERDICT FAIL: {'; '.join(bad)}")
    return FAIL
  print("  VERDICT PASS")
  return PASS


def main(argv: list[str] | None = None) -> int:
  ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
  ap.add_argument("--plant", action="store_true", help="the self-test, on copies")
  args = ap.parse_args(argv)
  nb = load_census()
  if nb is None:
    print("REFUSED: gates/noblob-census.py did not load derive(); the set was not re-derived",
          file=sys.stderr)
    return REFUSED
  dang = nb.load_dangling()
  if dang is None:
    print("REFUSED: noblob-census could not load the dangling generator", file=sys.stderr)
    return REFUSED
  try:
    surveyed = dang.census(ROOT)
    got, rows = derive_set(nb, dang, ROOT)
  except Exception as exc:  # noqa: BLE001 -- reported, not hidden
    print(f"REFUSED: the census could not be taken: {type(exc).__name__}: {exc}", file=sys.stderr)
    return REFUSED
  if not surveyed.get("subjects"):
    print("DEAD: census() named no subjects")
    return DEAD
  report(got, rows)
  code, why = check(rows)
  print(f"  {why}")
  print(f"  VERDICT {VERDICT[code]}")
  if args.plant:
    return plant(nb, dang, surveyed)
  return code


if __name__ == "__main__":
  sys.exit(main())
