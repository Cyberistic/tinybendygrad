#!/usr/bin/env python3
"""unsorted-gap -- reclass the UNSORTED load-bearing paths loadgap left.

    .venv/bin/python gates/unsorted-gap.py
    .venv/bin/python gates/unsorted-gap.py --plant

`gates/loadgap-gate.py` is LOADED BY PATH. The set is its UNSORTED rows,
re-derived. PRIOR is a comparison, not a population: if the count is not 13 the
tree moved, and a path is not dropped to keep 13.

THE CLASS IS THE CITER'S, not a list of paths. See `RULE`. STILL-UNSORTED fails.
PASS only when every unsorted path is REDIRECT, CHECKER, or DATA. GONE-NOTE,
MEASURED-OVER, and BOUND-NAME are printed and are not a pass. Nothing is dropped.

The plant is on copies. A redirect of a `.txt` under the swept tree is REDIRECT,
not REQUIRED and not a program. A `.rows` path cited as a file to read is DATA.
A path cited as the program (`python` plus the path) is not DATA even if
mis-suffixed, and is STILL-UNSORTED: loadgap owns REQUIRED. A REQUIRED path from
the live census is not reclassed. "is gone" is GONE-NOTE, not STILL-UNSORTED and
not REQUIRED; the word must be AFTER the path, and a filename does not supply it. A
MEASURED sentence that names the path as the instrument, and does not run it, is
MEASURED-OVER; a filename does not supply MEASURED either. A module-level
assignment of the path that is not `ORACLE =` is BOUND-NAME. An existing file is
not in the set.
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

LOADGAP = HERE / "loadgap-gate.py"
# A comparison, not a population. The count below is re-derived.
PRIOR = 13
REDIRECT = "REDIRECT"
CHECKER = "CHECKER"
DATA = "DATA"
STILL = "STILL-UNSORTED"
GONE = "GONE-NOTE"
MEASURED = "MEASURED-OVER"
BOUND = "BOUND-NAME"
CLASSES = (REDIRECT, CHECKER, DATA, GONE, MEASURED, BOUND, STILL)
# Printed, and not a pass. FAIL while any path sits outside these.
PASS_AT = (REDIRECT, CHECKER, DATA)
DATA_SUFFIX = (".txt", ".rows", ".bin")
# The program is the operand of one of these, or `./path` as the command.
RUNNER = re.compile(r"(?i)(?:python3?|sh|bash|bend)\s+([^\s`'\"|&;<>]+)")
# A shell redirect whose target is a token. `2>&1` and `>=` do not name a path.
REDIR = re.compile(r"""(?:^|[\s;|&])(\d?>>?)\s*[`'\"]?([^\s`'\";|&<>]+)""")
# After the path: it reads a row, or it re-derives from a row. Not a wider verb list.
READS_ROW = re.compile(r"(?i)\breads?\b.{0,80}\b(?:a|the|printed)\s+row\b")
REDERIVES_ROW = re.compile(
    r"(?i)\bre-derives\b.{0,200}\bfrom\b.{0,80}\b(?:the\s+)?(?:printed\s+)?row\b")
PRODUCES_ROW = re.compile(r"(?i)\bproduces?\b.{0,80}\brow\b")
RULE = (
    "A path is classed from its load citers only (role load). A # comment's span is "
    "loadgap's paragraph; any other citer's span is its line. The path is the program "
    "when a load citer runs it (python, python3, sh, bash, or bend whose operand is the "
    "path, or `./path` as the command). A program citation is STILL-UNSORTED: REQUIRED is "
    "loadgap's. "
    "Otherwise REDIRECT when a load citer sends stdout to the path (`>` or `>>`, and "
    "the path is not the program). Otherwise CHECKER when a load citer's span, after "
    "the path, says the path reads a row or re-derives from a row, and does not say it "
    "produces one. Otherwise GONE-NOTE when every load citer's span says, after the path "
    "and after path tokens are blanked, that the path is gone, absent, or never committed. "
    "A filename does not supply the word, and neither does a word that is not after the "
    "path, nor a later sentence that does not contain the path. Otherwise MEASURED-OVER "
    "when every load "
    "citer's span says MEASURED and names the path as the instrument of that measurement "
    "(the path sits in that MEASURED clause, introduced by '(', ',', ';', or 'in') and "
    "the span does not run it. The word is read after path tokens are blanked, so a "
    "filename does not supply it. Otherwise BOUND-NAME when every load citer is a "
    "module-level assignment of the path to a name other than ORACLE. An ORACLE = "
    "binding stays REQUIRED: this gate does not reclass it. Otherwise DATA when the "
    "path ends in .txt, .rows, or .bin. GONE-NOTE, MEASURED-OVER, and BOUND-NAME are "
    "printed and are not a pass. Anything else is STILL-UNSORTED, printed, and not a skip."
)


def git(args: list[str]) -> subprocess.CompletedProcess:
  env = {k: v for k, v in os.environ.items() if k != "GIT_INDEX_FILE"}
  return subprocess.run(["git", *args], cwd=ROOT, capture_output=True, text=True, env=env)


def load_loadgap():
  """Import the classifier by path. `gates/` is not a package."""
  if not LOADGAP.is_file():
    return None
  spec = importlib.util.spec_from_file_location("unsorted_loadgap", LOADGAP)
  if spec is None or spec.loader is None:
    return None
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  need = ("load_census", "derive_set", "paragraph", "UNSORTED", "REQUIRED")
  if not all(hasattr(mod, name) for name in need):
    return None
  if not callable(mod.load_census) or not callable(mod.derive_set) or not callable(mod.paragraph):
    return None
  return mod


def _parse(body: str):
  try:
    with warnings.catch_warnings():
      warnings.simplefilter("ignore", SyntaxWarning)
      return ast.parse(body)
  except SyntaxError:
    return None


def _clean(token: str) -> str:
  """Quotes and a trailing sentence mark. A leading dot is part of `.agents`, not punctuation."""
  return token.strip("`'\"").rstrip(",.;:)")


def is_program(text: str, path: str) -> bool:
  """The text runs `path`. A mention, and a redirect target, are not a program."""
  for m in RUNNER.finditer(text):
    tok = _clean(m.group(1))
    if tok == path or tok == "./" + path:
      return True
  cmd = re.compile(r"(?:^|[;&|\n])\s*\./" + re.escape(path) + r"(?![\w./-])")
  return cmd.search(text) is not None


def redirect_to(text: str, path: str) -> bool:
  """Stdout is sent to `path`, and `path` is not the program of that text."""
  if is_program(text, path):
    return False
  for m in REDIR.finditer(text):
    if _clean(m.group(2)) == path:
      return True
  return False


def _after(span: str, path: str) -> str:
  at = span.find(path)
  if at < 0:
    return ""
  return span[at + len(path):]


def reads_row(span: str, path: str) -> bool:
  """The span names `path` as what reads a row, and not as what produces one."""
  if path not in span or is_program(span, path) or redirect_to(span, path):
    return False
  after = _after(span, path)
  if PRODUCES_ROW.search(after):
    return False
  return READS_ROW.search(after) is not None or REDERIVES_ROW.search(after) is not None


_MARK = "\x00"
_INTRODUCED = re.compile(r"(?:\(|,|;|\bin)$")


def gone_note(lg, span: str, path: str) -> bool:
  """The sentence says the path is gone, after the path. A filename, and a later sentence, do not count."""
  if path not in span or is_program(span, path):
    return False
  marked = span.replace(path, _MARK)
  for hit in re.finditer(re.escape(_MARK), marked):
    after = marked[hit.end():]
    end = re.search(r"\.(?:\s|$)", after)
    clause = after[:end.start()] if end else after
    if lg.says_missing(clause):
      return True
  return False


def measured_over(lg, span: str, path: str) -> bool:
  """MEASURED names `path` as the instrument of that measurement, and the span does not run it."""
  if path not in span or is_program(span, path):
    return False
  # The hits are searched in the BLANKED span, so a FILENAME cannot supply the word: a decoy
  # path whose name carries MEASURED is not the measurement, and the subject is not named by it.
  blank = lg.blanked(span.replace(path, _MARK))
  for hit in re.finditer(r"\bMEASURED\b", blank):
    after = blank[hit.end():]
    end = re.search(r"\.(?:\s|$)", after)
    clause = after[:end.start()] if end else after
    at = clause.find(_MARK)
    if at < 0:
      continue
    before = re.sub(r"[\s#`'\"]+", " ", clause[:at]).rstrip()
    if _INTRODUCED.search(before):
      return True
  return False


def bound_name(body: str, n: int, path: str) -> bool:
  """A module-level assignment of `path` to a name other than ORACLE. See `RULE`."""
  tree = _parse(body)
  if tree is None:
    return False
  for node in tree.body:
    if getattr(node, "lineno", None) != n:
      continue
    if isinstance(node, ast.Assign) and len(node.targets) == 1:
      target, value = node.targets[0], node.value
    elif isinstance(node, ast.AnnAssign):
      target, value = node.target, node.value
    else:
      return False
    if not isinstance(target, ast.Name) or target.id == "ORACLE":
      return False
    return isinstance(value, ast.Constant) and value.value == path
  return False


def _shared(keys: list[str], matched: list[str], missing: list[str]) -> bool:
  """Every load citer shows the structure. A missing body cannot be shown to."""
  return bool(keys) and not missing and len(matched) == len(keys)


def _line(body: str, n: int) -> str:
  lines = body.splitlines()
  if 1 <= n <= len(lines):
    return lines[n - 1]
  return ""


def _span(lg, body: str, n: int) -> str:
  line = _line(body, n)
  if line.lstrip().startswith("#"):
    return lg.paragraph(body.splitlines(), n)
  return line


def _load(citers: list[tuple[str, int, str]]) -> list[tuple[str, int]]:
  return [(rel, n) for rel, n, role in citers if role == "load"]


def class_of(path: str, citers: list[tuple[str, int, str]], bodies: dict[str, str], lg) -> tuple[str, list[str]]:
  """`(class, deciding citers)`. See `RULE`. A missing body cannot be shown to be a class."""
  load = _load(citers)
  if not load:
    return STILL, []
  seen: list[tuple[str, str, str]] = []
  gone: list[str] = []
  measured: list[str] = []
  bound: list[str] = []
  missing: list[str] = []
  for rel, n in load:
    body = bodies.get(rel)
    key = f"{rel}:{n}"
    if body is None:
      seen.append((key, "", ""))
      missing.append(key)
      continue
    line, span = _line(body, n), _span(lg, body, n)
    seen.append((key, line, span))
    if gone_note(lg, span, path):
      gone.append(key)
    if measured_over(lg, span, path):
      measured.append(key)
    if bound_name(body, n, path):
      bound.append(key)
  keys = [key for key, _line, _span in seen]
  if any(is_program(span or line, path) for _k, line, span in seen):
    return STILL, [key for key, line, span in seen if is_program(span or line, path)]
  redirected = [key for key, line, span in seen if redirect_to(span or line, path)]
  if redirected:
    return REDIRECT, redirected
  checked = [key for key, _line, span in seen if reads_row(span, path)]
  if checked:
    return CHECKER, checked
  if _shared(keys, gone, missing):
    return GONE, gone
  if _shared(keys, measured, missing):
    return MEASURED, measured
  if _shared(keys, bound, missing):
    return BOUND, bound
  # A missing body cannot show that the citer does not run the path, so it is not DATA.
  if path.endswith(DATA_SUFFIX) and not missing:
    return DATA, keys
  return STILL, keys


def _citers(row: dict) -> list[tuple[str, int, str]]:
  out = []
  for c in row["citers"]:
    rel, _, ns = c.rpartition(":")
    out.append((rel, int(ns), row["roles"].get(c, "load")))
  return out


def classify(rows: list[dict], bodies: dict[str, str], lg) -> list[dict]:
  out = []
  for r in rows:
    kind, why = class_of(r["path"], _citers(r), bodies, lg)
    out.append({**r, "uclass": kind, "why": why})
  return out


def _bodies(dang, fs: Path) -> dict[str, str]:
  bodies, _deriv = dang.namer_population(fs)
  return dict(bodies)


def derive(lg, nb, dang, fs: Path) -> tuple[dict, list[dict], list[dict]]:
  """`(census, loadgap rows, unsorted rows)`. The unsorted set is not trimmed to PRIOR."""
  got, rows = lg.derive_set(nb, dang, fs)
  unsorted = [r for r in rows if r.get("gap") == lg.UNSORTED]
  return got, rows, unsorted


def _show_line(line: str) -> str:
  return line or "(line absent)"


def report(got: dict, rows: list[dict], bodies: dict[str, str], lg) -> None:
  head = git(["rev-parse", "HEAD"]).stdout.strip()
  stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
  n = len(rows)
  print(f"unsorted-gap   HEAD {head}   {stamp}")
  print("  COMMAND        .venv/bin/python gates/unsorted-gap.py")
  print("  DERIVED        loadgap-gate derive_set(), gap UNSORTED")
  print(f"  CENSUS         {got.get('stamp', '-')}")
  if n == PRIOR:
    print(f"  TREE           unmoved from the prior reading {PRIOR}")
  else:
    print(f"  TREE MOVED     prior reading {PRIOR}, this reading {n}. No path was dropped to keep {PRIOR}.")
  print(f"  UNSORTED       {n}")
  print(f"  RULE           {RULE}")
  by = {k: [r for r in rows if r["uclass"] == k] for k in CLASSES}
  for label in CLASSES:
    print(f"  {label:<16} {len(by[label])}")
  for label in CLASSES:
    print(f"  {label} NAMED  {len(by[label])}")
    for r in by[label]:
      print(f"    {r['path']}")
      shown = False
      for rel, nline, role in _citers(r):
        if role != "load":
          continue
        shown = True
        line = _line(bodies.get(rel, ""), nline)
        print(f"      {rel}:{nline}")
        print(f"        {_show_line(line)}")
      if not shown:
        print("      (no load citer)")
      print(f"      class {r['uclass']}")
      print(f"        citers {', '.join(r['why']) if r['why'] else '-'}")


def check(rows: list[dict]) -> tuple[int, str]:
  if not rows:
    return DEAD, "UNSORTED 0; a pass over nothing is not a pass"
  bad = [r["path"] for r in rows if r["uclass"] not in CLASSES]
  if bad:
    return FAIL, f"{len(bad)} path(s) carry no class: {bad[:5]}"
  tally = Counter(r["uclass"] for r in rows)
  if sum(tally[k] for k in CLASSES) != len(rows):
    return FAIL, f"classes sum to {sum(tally[k] for k in CLASSES)} over {len(rows)}"
  if any(r["uclass"] not in PASS_AT for r in rows):
    return FAIL, (f"{len(rows)} unsorted, " + " ".join(f"{k}={tally[k]}" for k in CLASSES))
  return PASS, (f"{len(rows)} unsorted, " + " ".join(f"{k}={tally[k]}" for k in CLASSES))


def _plant_path(leaf: str) -> str:
  """Built by concatenation, so this file does not cite the plant path as one token."""
  return ".agents" + "/" + "slop/unsorted-plant/" + leaf


def _insert_header(text: str, block: str) -> str:
  """Insert `block` after the shebang, closed by a lone `#` so the writer's header is another paragraph."""
  lines = text.splitlines(keepends=True)
  i = 1 if lines and lines[0].startswith("#!") else 0
  body = block if block.endswith("\n") else block + "\n"
  if not body.endswith("#\n"):
    body += "#\n"
  lines.insert(i, body)
  return "".join(lines)


def _append(text: str, block: str) -> str:
  """A module-level statement after the writer's last line. A comment is not an assignment."""
  if not text.endswith("\n"):
    text += "\n"
  return text + (block if block.endswith("\n") else block + "\n")


def _writer(surveyed: dict) -> str | None:
  writers = sorted({n for ns in surveyed["subjects"].values() for n in ns
                    if n.endswith(".py") and n.startswith("gates/") and (ROOT / n).is_file()
                    and n not in ("gates/loadgap-gate.py", "gates/unsorted-gap.py")})
  parsing = [w for w in writers if _parse((ROOT / w).read_text(errors="replace")) is not None]
  if not parsing:
    return None
  parsing.sort(key=lambda w: (ROOT / w).stat().st_size)
  return parsing[0]


def _print_check(name: str, ok: bool, detail: str) -> bool:
  print(f"  {'OK  ' if ok else 'FAIL'}  {name}")
  print(f"        {detail}")
  return ok


def _copy_unsorted(lg, nb, dang, writer: str, text: str) -> tuple[list[dict], list[dict], dict[str, str]] | None:
  try:
    ast.parse(text)
  except SyntaxError as exc:
    print(f"PLANT REFUSED: the copy namer does not parse: {exc}")
    return None
  with tempfile.TemporaryDirectory(prefix="unsorted-plant.") as tmp:
    copy = Path(tmp) / "repo"
    dest = copy / writer
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(text)
    try:
      _got, rows, unsorted = derive(lg, nb, dang, copy)
      bodies = _bodies(dang, copy)
    except Exception as exc:  # noqa: BLE001 -- a plant that hides this scores success on nothing
      print(f"PLANT REFUSED: derive did not answer: {type(exc).__name__}: {exc}")
      return None
  return rows, unsorted, bodies


def _row(rows: list[dict], path: str) -> dict | None:
  for r in rows:
    if r["path"] == path:
      return r
  return None


def _ours(lg, row: dict | None, bodies: dict[str, str]) -> str | None:
  if row is None:
    return None
  kind, _why = class_of(row["path"], _citers(row), bodies, lg)
  return kind


PLANT_REQUIRED = (
    "PLANT a redirect of a .txt is REDIRECT",
    "FALSIFY that redirect is not REQUIRED",
    "FALSIFY that redirect path is not the program",
    "FALSIFY the same path as the program is not REDIRECT",
    "PLANT a .rows path cited as a file to read is DATA",
    "FALSIFY python of a mis-suffixed path is not DATA",
    "FALSIFY python of a mis-suffixed path is STILL-UNSORTED",
    "FALSIFY loadgap owns that program citation as REQUIRED",
    "PLANT a path that reads a row is CHECKER",
    "FALSIFY a path that produces a row is not CHECKER",
    "CONTROL a live REQUIRED path is not reclassed as DATA",
    "PLANT is gone is GONE-NOTE",
    "FALSIFY is gone is not STILL-UNSORTED",
    "FALSIFY is gone is not REQUIRED",
    "FALSIFY a filename does not supply gone",
    "FALSIFY a decoy filename does not supply gone",
    "FALSIFY absent before the path is not GONE-NOTE",
    "FALSIFY a later sentence does not supply gone",
    "PLANT a MEASURED sentence is MEASURED-OVER",
    "FALSIFY a MEASURED sentence that does not name the path is not MEASURED-OVER",
    "FALSIFY a MEASURED sentence that runs the path is not MEASURED-OVER",
    "FALSIFY a filename does not supply MEASURED",
    "FALSIFY a decoy filename does not supply MEASURED",
    "PLANT a module-level assignment is BOUND-NAME",
    "FALSIFY ORACLE = is not BOUND-NAME",
    "FALSIFY ORACLE = stays REQUIRED",
    "FALSIFY a nested assignment is not BOUND-NAME",
    "CONTROL a live REQUIRED path is not reclassed",
    "CONTROL an existing file is not in the set",
)


def plant(lg, nb, dang, surveyed: dict, live_rows: list[dict], live_bodies: dict[str, str]) -> int:
  """The shapes, on copies, plus the falsifications and the live REQUIRED control."""
  writer = _writer(surveyed)
  required = [r for r in live_rows if r.get("gap") == lg.REQUIRED]
  if writer is None or not required:
    print(f"PLANT REFUSED: writer={writer} required={len(required)}")
    return REFUSED
  redir = _plant_path("x.txt")
  data = _plant_path("in.rows")
  ran = _plant_path("ran.rows")
  reader = _plant_path("reads.sh")
  maker = _plant_path("makes.sh")
  noted = _plant_path("noted.sh")
  namedgone = _plant_path("gone.sh")
  early = _plant_path("early.py")
  latgone = _plant_path("latgone.py")
  measured_p = _plant_path("measured.py")
  aside = _plant_path("aside.py")
  ranm = _plant_path("ranm.py")
  worded = _plant_path("MEASURED.py")
  decoym = _plant_path("decoym.py")
  decoyg = _plant_path("decoyg.py")
  bind = _plant_path("bind.py")
  nested = _plant_path("nested.py")
  # Joined at runtime, so this file does not cite either path as one token.
  deeper = "oracles/" + "planted-deeper.py"
  exist = "gates/" + "gatekit.py"
  own = LOADGAP.read_text(errors="replace") + (HERE / "unsorted-gap.py").read_text(errors="replace")
  own_toks = set(dang.tokens(own))
  already = set(surveyed.get("dangling", [])) | set(surveyed.get("subjects", {}))
  fresh = (redir, data, ran, reader, maker, noted, namedgone, early, latgone, measured_p,
           aside, ranm, worded, decoym, decoyg, bind, nested)
  for path in fresh:
    if path in own_toks or path in already or (ROOT / path).exists():
      print(f"PLANT REFUSED: {path} is already a token, a subject, or a file")
      return REFUSED
  if not (ROOT / exist).is_file():
    print(f"PLANT REFUSED: {exist} is not a file; the existing-file control has nothing to cite")
    return REFUSED
  base = (ROOT / writer).read_text(errors="replace")
  if deeper in base or (ROOT / deeper).is_file():
    print(f"PLANT REFUSED: {deeper} is already in the writer or on disk")
    return REFUSED
  checks: list[tuple[str, bool, str]] = []
  print(f"  PLANT writer={writer}")

  both = _insert_header(base, f"#   other.py > {redir}\n")
  copied = _copy_unsorted(lg, nb, dang, writer, both)
  if copied is None:
    return REFUSED
  rows, unsorted, bodies = copied
  got = _row(rows, redir)
  ours = _ours(lg, got, bodies)
  gap = None if got is None else got.get("gap")
  checks.append(("PLANT a redirect of a .txt is REDIRECT",
                 ours == REDIRECT and _row(unsorted, redir) is not None,
                 f"uclass={ours} gap={gap} path={redir}"))
  checks.append(("FALSIFY that redirect is not REQUIRED",
                 got is not None and gap != lg.REQUIRED and ours != lg.REQUIRED,
                 f"gap={gap} uclass={ours}"))
  checks.append(("FALSIFY that redirect path is not the program",
                 ours == REDIRECT,
                 f"uclass={ours} (REDIRECT is the rule's not-the-program branch)"))
  for name, good, detail in checks:
    _print_check(name, good, detail)

  as_prog = _insert_header(base, f"#   .venv/bin/python {redir} > {redir}\n")
  copied = _copy_unsorted(lg, nb, dang, writer, as_prog)
  if copied is None:
    return REFUSED
  rows, _unsorted, bodies = copied
  got = _row(rows, redir)
  ours = _ours(lg, got, bodies)
  pair = ("FALSIFY the same path as the program is not REDIRECT",
          got is not None and ours == STILL,
          f"uclass={ours} path={redir}")
  checks.append(pair)
  _print_check(*pair)

  read = _insert_header(base, f"# read the rows from {data}\n")
  copied = _copy_unsorted(lg, nb, dang, writer, read)
  if copied is None:
    return REFUSED
  rows, unsorted, bodies = copied
  got = _row(rows, data)
  ours = _ours(lg, got, bodies)
  pair = ("PLANT a .rows path cited as a file to read is DATA",
          ours == DATA and _row(unsorted, data) is not None,
          f"uclass={ours} gap={None if got is None else got.get('gap')} path={data}")
  checks.append(pair)
  _print_check(*pair)

  prog = _insert_header(base, f"# THE GATE. the rows\n#   .venv/bin/python {ran}\n")
  copied = _copy_unsorted(lg, nb, dang, writer, prog)
  if copied is None:
    return REFUSED
  rows, unsorted, bodies = copied
  got = _row(rows, ran)
  ours = _ours(lg, got, bodies)
  gap = None if got is None else got.get("gap")
  in_data = any(r["path"] == ran and r["uclass"] == DATA for r in classify(
      [r for r in unsorted if r["path"] == ran], bodies, lg))
  for name, good, detail in (
      ("FALSIFY python of a mis-suffixed path is not DATA",
       got is not None and ours != DATA and not in_data,
       f"uclass={ours} in-data={in_data} path={ran}"),
      ("FALSIFY python of a mis-suffixed path is STILL-UNSORTED",
       ours == STILL,
       f"uclass={ours}"),
      ("FALSIFY loadgap owns that program citation as REQUIRED",
       gap == lg.REQUIRED and ran not in {r["path"] for r in unsorted},
       f"gap={gap} in-unsorted={ran in {r['path'] for r in unsorted}}"),
  ):
    checks.append((name, good, detail))
    _print_check(name, good, detail)

  chk = _insert_header(base, f"# {reader} reads the row\n")
  copied = _copy_unsorted(lg, nb, dang, writer, chk)
  if copied is None:
    return REFUSED
  rows, unsorted, bodies = copied
  got = _row(rows, reader)
  ours = _ours(lg, got, bodies)
  pair = ("PLANT a path that reads a row is CHECKER",
          ours == CHECKER and _row(unsorted, reader) is not None,
          f"uclass={ours} gap={None if got is None else got.get('gap')} path={reader}")
  checks.append(pair)
  _print_check(*pair)

  made = _insert_header(base, f"# {maker} produces the row\n")
  copied = _copy_unsorted(lg, nb, dang, writer, made)
  if copied is None:
    return REFUSED
  rows, _unsorted, bodies = copied
  got = _row(rows, maker)
  ours = _ours(lg, got, bodies)
  pair = ("FALSIFY a path that produces a row is not CHECKER",
          got is not None and ours != CHECKER,
          f"uclass={ours} path={maker}")
  checks.append(pair)
  _print_check(*pair)

  live_bad = []
  for r in required:
    kind, _why = class_of(r["path"], _citers(r), live_bodies, lg)
    if kind == DATA:
      live_bad.append(r["path"])
  pair = ("CONTROL a live REQUIRED path is not reclassed as DATA",
          bool(required) and not live_bad,
          f"required={len(required)} reclassed-data={live_bad or '-'} "
          + " ".join(r["path"] for r in required))
  checks.append(pair)
  _print_check(*pair)

  stolen = []
  for r in required:
    kind, _why = class_of(r["path"], _citers(r), live_bodies, lg)
    if kind in (DATA, GONE, MEASURED, BOUND):
      stolen.append(f"{r['path']}={kind}")
  pair = ("CONTROL a live REQUIRED path is not reclassed",
          bool(required) and not stolen,
          f"required={len(required)} reclassed={stolen or '-'} "
          + " ".join(r["path"] for r in required))
  checks.append(pair)
  _print_check(*pair)

  noted_txt = _insert_header(base, f"# the witness {noted} is gone\n")
  copied = _copy_unsorted(lg, nb, dang, writer, noted_txt)
  if copied is None:
    return REFUSED
  rows, unsorted, bodies = copied
  got = _row(rows, noted)
  ours = _ours(lg, got, bodies)
  gap = None if got is None else got.get("gap")
  for name, good, detail in (
      ("PLANT is gone is GONE-NOTE",
       ours == GONE and _row(unsorted, noted) is not None,
       f"uclass={ours} gap={gap} path={noted}"),
      ("FALSIFY is gone is not STILL-UNSORTED",
       ours == GONE and ours != STILL,
       f"uclass={ours}"),
      ("FALSIFY is gone is not REQUIRED",
       got is not None and gap != lg.REQUIRED and ours != lg.REQUIRED,
       f"gap={gap} uclass={ours}"),
  ):
    checks.append((name, good, detail))
    _print_check(name, good, detail)

  named = _insert_header(base, f"# see {namedgone}\n")
  copied = _copy_unsorted(lg, nb, dang, writer, named)
  if copied is None:
    return REFUSED
  rows, unsorted, bodies = copied
  got = _row(rows, namedgone)
  ours = _ours(lg, got, bodies)
  pair = ("FALSIFY a filename does not supply gone",
          got is not None and ours == STILL and ours != GONE,
          f"uclass={ours} path={namedgone}")
  checks.append(pair)
  _print_check(*pair)

  early_txt = _insert_header(base, f"# the witness is absent; the file {early} is on disk\n")
  copied = _copy_unsorted(lg, nb, dang, writer, early_txt)
  if copied is None:
    return REFUSED
  rows, unsorted, bodies = copied
  got = _row(rows, early)
  ours = _ours(lg, got, bodies)
  pair = ("FALSIFY absent before the path is not GONE-NOTE",
          got is not None and ours == STILL and ours != GONE,
          f"uclass={ours} path={early}")
  checks.append(pair)
  _print_check(*pair)

  latgone_txt = _insert_header(base, f"# the witness {latgone} is on disk. The oracle is gone.\n")
  copied = _copy_unsorted(lg, nb, dang, writer, latgone_txt)
  if copied is None:
    return REFUSED
  rows, unsorted, bodies = copied
  got = _row(rows, latgone)
  ours = _ours(lg, got, bodies)
  pair = ("FALSIFY a later sentence does not supply gone",
          got is not None and ours == STILL and ours != GONE,
          f"uclass={ours} path={latgone}")
  checks.append(pair)
  _print_check(*pair)

  decoyg_txt = _insert_header(base, f"# the witness {decoyg}, and the decoy absent.py, is on disk.\n")
  copied = _copy_unsorted(lg, nb, dang, writer, decoyg_txt)
  if copied is None:
    return REFUSED
  rows, unsorted, bodies = copied
  got = _row(rows, decoyg)
  ours = _ours(lg, got, bodies)
  pair = ("FALSIFY a decoy filename does not supply gone",
          got is not None and ours == STILL and ours != GONE,
          f"uclass={ours} path={decoyg}")
  checks.append(pair)
  _print_check(*pair)

  over = _insert_header(base, f"# MEASURED over the packets ({measured_p})\n")
  copied = _copy_unsorted(lg, nb, dang, writer, over)
  if copied is None:
    return REFUSED
  rows, unsorted, bodies = copied
  got = _row(rows, measured_p)
  ours = _ours(lg, got, bodies)
  pair = ("PLANT a MEASURED sentence is MEASURED-OVER",
          ours == MEASURED and _row(unsorted, measured_p) is not None,
          f"uclass={ours} gap={None if got is None else got.get('gap')} path={measured_p}")
  checks.append(pair)
  _print_check(*pair)

  later = _insert_header(base, f"# MEASURED the count was 4. The note names {aside}.\n")
  copied = _copy_unsorted(lg, nb, dang, writer, later)
  if copied is None:
    return REFUSED
  rows, _unsorted, bodies = copied
  got = _row(rows, aside)
  ours = _ours(lg, got, bodies)
  pair = ("FALSIFY a MEASURED sentence that does not name the path is not MEASURED-OVER",
          got is not None and ours != MEASURED and ours == STILL,
          f"uclass={ours} path={aside}")
  checks.append(pair)
  _print_check(*pair)

  ran_m = _insert_header(base, f"# MEASURED .venv/bin/python {ranm}\n")
  copied = _copy_unsorted(lg, nb, dang, writer, ran_m)
  if copied is None:
    return REFUSED
  rows, unsorted, bodies = copied
  got = _row(rows, ranm)
  ours = _ours(lg, got, bodies)
  pair = ("FALSIFY a MEASURED sentence that runs the path is not MEASURED-OVER",
          got is not None and ours != MEASURED and ours == STILL
          and ranm in {r["path"] for r in unsorted},
          f"uclass={ours} gap={None if got is None else got.get('gap')}")
  checks.append(pair)
  _print_check(*pair)

  byname = _insert_header(base, f"# see {worded}\n")
  copied = _copy_unsorted(lg, nb, dang, writer, byname)
  if copied is None:
    return REFUSED
  rows, _unsorted, bodies = copied
  got = _row(rows, worded)
  ours = _ours(lg, got, bodies)
  pair = ("FALSIFY a filename does not supply MEASURED",
          got is not None and ours != MEASURED and ours == STILL,
          f"uclass={ours} path={worded}")
  checks.append(pair)
  _print_check(*pair)

  decoym_txt = _insert_header(
      base, f"# MEASURED the count was 4. The decoy MEASURED.py, {decoym} is a file.\n")
  copied = _copy_unsorted(lg, nb, dang, writer, decoym_txt)
  if copied is None:
    return REFUSED
  rows, unsorted, bodies = copied
  got = _row(rows, decoym)
  ours = _ours(lg, got, bodies)
  pair = ("FALSIFY a decoy filename does not supply MEASURED",
          got is not None and ours != MEASURED and ours == STILL,
          f"uclass={ours} path={decoym}")
  checks.append(pair)
  _print_check(*pair)

  assigned = _append(base, f'DEEPER = "{deeper}"\n')
  copied = _copy_unsorted(lg, nb, dang, writer, assigned)
  if copied is None:
    return REFUSED
  rows, unsorted, bodies = copied
  got = _row(rows, deeper)
  ours = _ours(lg, got, bodies)
  pair = ("PLANT a module-level assignment is BOUND-NAME",
          ours == BOUND and _row(unsorted, deeper) is not None
          and (None if got is None else got.get("gap")) != lg.REQUIRED,
          f"uclass={ours} gap={None if got is None else got.get('gap')} path={deeper}")
  checks.append(pair)
  _print_check(*pair)

  oracle_eq = _append(base, f'ORACLE = "{bind}"\n')
  copied = _copy_unsorted(lg, nb, dang, writer, oracle_eq)
  if copied is None:
    return REFUSED
  rows, unsorted, bodies = copied
  got = _row(rows, bind)
  ours = _ours(lg, got, bodies)
  gap = None if got is None else got.get("gap")
  for name, good, detail in (
      ("FALSIFY ORACLE = is not BOUND-NAME",
       got is not None and ours != BOUND,
       f"uclass={ours} gap={gap}"),
      ("FALSIFY ORACLE = stays REQUIRED",
       gap == lg.REQUIRED and bind not in {r["path"] for r in unsorted},
       f"gap={gap} in-unsorted={bind in {r['path'] for r in unsorted}}"),
  ):
    checks.append((name, good, detail))
    _print_check(name, good, detail)

  held = _append(base, f"def _hold():\n    DEEPER = \"{nested}\"\n")
  copied = _copy_unsorted(lg, nb, dang, writer, held)
  if copied is None:
    return REFUSED
  rows, unsorted, bodies = copied
  got = _row(rows, nested)
  ours = _ours(lg, got, bodies)
  pair = ("FALSIFY a nested assignment is not BOUND-NAME",
          got is not None and ours == STILL and ours != BOUND
          and _row(unsorted, nested) is not None,
          f"uclass={ours} gap={None if got is None else got.get('gap')}")
  checks.append(pair)
  _print_check(*pair)

  cited = _insert_header(base, f"# see {exist}\n")
  copied = _copy_unsorted(lg, nb, dang, writer, cited)
  if copied is None:
    return REFUSED
  rows, unsorted, _bodies_c = copied
  in_set = any(r["path"] == exist for r in rows) or any(r["path"] == exist for r in unsorted)
  pair = ("CONTROL an existing file is not in the set",
          not in_set,
          f"in-set={in_set} path={exist}")
  checks.append(pair)
  _print_check(*pair)

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
  lg = load_loadgap()
  if lg is None:
    print("REFUSED: gates/loadgap-gate.py did not load; the set was not re-derived", file=sys.stderr)
    return REFUSED
  nb = lg.load_census()
  if nb is None:
    print("REFUSED: loadgap could not load noblob-census derive()", file=sys.stderr)
    return REFUSED
  dang = nb.load_dangling()
  if dang is None:
    print("REFUSED: noblob-census could not load the dangling generator", file=sys.stderr)
    return REFUSED
  try:
    surveyed = dang.census(ROOT)
    got, rows, unsorted = derive(lg, nb, dang, ROOT)
    bodies = _bodies(dang, ROOT)
  except Exception as exc:  # noqa: BLE001 -- reported, not hidden
    print(f"REFUSED: the census could not be taken: {type(exc).__name__}: {exc}", file=sys.stderr)
    return REFUSED
  if not surveyed.get("subjects"):
    print("DEAD: census() named no subjects")
    return DEAD
  classed = classify(unsorted, bodies, lg)
  report(got, classed, bodies, lg)
  code, why = check(classed)
  print(f"  {why}")
  print(f"  VERDICT {VERDICT[code]}")
  if args.plant:
    return plant(lg, nb, dang, surveyed, rows, bodies)
  return code


if __name__ == "__main__":
  sys.exit(main())
