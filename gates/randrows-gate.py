#!/usr/bin/env python3
"""randrows-gate.py -- a frozen rand oracle that exists is not a check.

    .venv/bin/python gates/randrows-gate.py
    .venv/bin/python gates/randrows-gate.py --plant

`oracles/tinybendygrad_mixin_rand.bend.rows` is in HEAD. A resolve test stops
there and prints PASS. The defect is the opposite: nothing regenerates the
file, and a fraction quoted next to its name may not be its row count.

WHAT IS RE-DERIVED. Data rows, not `wc -l`. A blank line, a `#` comment, and a
leading line with no `=` are not rows. The count is taken from the bytes, on
every run, including a copy.

WHAT IS A CLAIM. A fraction after the filename, up to the next different path,
that either leads the span or whose clause says stale/rows/lines. Discovered
by `os.walk`, not a list of numbers. The denominator is compared to the
re-derived row count. The numerator is a staleness count, and this file does
not invent one.

WHAT IS A GENERATOR. A `.py` file, other than this one, whose code (not a
docstring) names the subject and defines `rows()`. None does. No generator is
REFUSED, not PASS: the staleness numerator was not re-derived. A denominator
that disagrees is FAIL, which is a completed measurement and outranks the
refusal. A generator that is found is called and diffed in memory; this file
does not write `oracles/`.

EXIT: 0 PASS, 1 FAIL, 3 REFUSED, 5 DEAD. DEAD is an empty emission. A PASS
over no rows is rewritten to DEAD -- a silent success is not a success.
"""
from __future__ import annotations

import ast
import importlib.util
import os
import re
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
from gatekit import DEAD, FAIL, PASS, REFUSED, VERDICT  # noqa: E402

SUBJECT = "oracles/tinybendygrad_mixin_rand.bend.rows"
BASE = SUBJECT.rsplit("/", 1)[-1]
SKIP = frozenset({".git", ".venv", "references", "runs", "node_modules", "__pycache__"})
SUFFIX = (".py", ".md", ".bend", ".rows", ".sh", ".mjs")
PATH = re.compile(r"[A-Za-z0-9_][A-Za-z0-9_.+-]*(?:/[A-Za-z0-9_.+-]+)+\.[A-Za-z0-9]+")
FRAC = re.compile(r"(\d+)\s+of\s+(\d+)|(\d+)/(\d+)", re.I)
WORD = re.compile(r"stale|rows|lines", re.I)

# gate-surface reads these by ast, not by import. Names are gatekit's.
EXIT_SURFACE = VERDICTS = {0: "PASS", 1: "FAIL", 3: "REFUSED", 5: "DEAD"}  # VERDICTS: legacy alias of EXIT_SURFACE
PLANTS = {0: ["--plant"], 1: ["--expect", "fail"], 3: ["--expect", "refuse"], 5: ["--expect", "dead"]}
RED_IS = "FINDING"


def count_rows(text: str) -> dict[str, int]:
  """Data rows. A header is a first line with no `=`, and it is not a row."""
  raw = text.splitlines()
  blank = comment = rows = 0
  for line in raw:
    stripped = line.strip()
    if not stripped:
      blank += 1
    elif stripped.startswith("#"):
      comment += 1
    elif "=" in line:
      rows += 1
  header = int(bool(raw) and not raw[0].strip().startswith("#") and "=" not in raw[0])
  return {"lines": len(raw), "blank": blank, "comment": comment, "rows": rows, "header": header}


def _walk(root: Path):
  for dirpath, dirnames, filenames in os.walk(root):
    dirnames[:] = sorted(d for d in dirnames if d not in SKIP)
    for fn in sorted(filenames):
      if fn.endswith(SUFFIX):
        yield Path(dirpath) / fn


def _span(text: str, at: int, key: str) -> str:
  rest = text[at + len(key):]
  stop = len(rest)
  for match in PATH.finditer(rest):
    if not match.group(0).endswith(BASE):
      stop = match.start()
      break
  return rest[:min(stop, 900)]


def _fractions(span: str) -> list[tuple[int, int]]:
  found: list[tuple[int, int]] = []
  head = re.sub(r"^[`\s*]+", "", span)
  lead = FRAC.match(head)
  if lead:
    found.append((int(lead.group(1) or lead.group(3)), int(lead.group(2) or lead.group(4))))
  for match in FRAC.finditer(span):
    num = int(match.group(1) or match.group(3))
    den = int(match.group(2) or match.group(4))
    clause = span[max(0, match.start() - 80):match.end() + 24]
    if WORD.search(clause):
      found.append((num, den))
  out = []
  for pair in found:
    if pair not in out:
      out.append(pair)
  return out


def discover_claims(root: Path) -> list[tuple[str, int, int]]:
  """`(site, numerator, denominator)` for fractions bound to the subject."""
  claims = []
  for path in _walk(root):
    try:
      text = path.read_text(errors="replace")
    except OSError:
      continue
    if BASE not in text:
      continue
    rel = path.relative_to(root).as_posix()
    start = 0
    while True:
      at = text.find(SUBJECT, start)
      key = SUBJECT
      if at < 0:
        at = text.find(BASE, start)
        key = BASE
      if at < 0:
        break
      line = text[:at].count("\n") + 1
      for num, den in _fractions(_span(text, at, key)):
        claims.append((f"{rel}:{line}", num, den))
      start = at + len(key)
  return sorted(claims)


def _code_names(src: str, needle: str) -> bool:
  """True when `needle` is a code string, not a docstring."""
  try:
    tree = ast.parse(src)
  except SyntaxError:
    return False
  docs = set()
  for node in ast.walk(tree):
    body = getattr(node, "body", None)
    if not body or not isinstance(body, list):
      continue
    first = body[0]
    if isinstance(first, ast.Expr) and isinstance(getattr(first, "value", None), ast.Constant):
      if isinstance(first.value.value, str):
        docs.add(id(first.value))
  for node in ast.walk(tree):
    if isinstance(node, ast.Constant) and isinstance(node.value, str) and id(node) not in docs:
      if needle in node.value:
        return True
  return False


def discover_generators(root: Path) -> list[str]:
  """`.py` files whose code names the subject and defines `rows()`. Not this file."""
  found = []
  self_rel = Path(__file__).resolve().relative_to(root).as_posix()
  for path in _walk(root):
    if not path.name.endswith(".py"):
      continue
    rel = path.relative_to(root).as_posix()
    if rel == self_rel:
      continue
    try:
      src = path.read_text(errors="replace")
    except OSError:
      continue
    if BASE not in src or "def rows(" not in src:
      continue
    if _code_names(src, BASE):
      found.append(rel)
  return found


def run_generator(root: Path, rel: str):
  """Call `rows()`. A raise is not a diff and not a pass."""
  path = root / rel
  spec = importlib.util.spec_from_file_location("randrows_gen", path)
  if spec is None or spec.loader is None:
    return None
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  produced = mod.rows()
  return produced if isinstance(produced, str) else None


def judge(text, claims, produced):
  """`(exit, lines, disagreements)`. `produced is None` means no generator ran."""
  lines: list[str] = []
  bad: list[str] = []
  if text is None:
    lines.append("file=ABSENT")
    return REFUSED, lines, bad
  counted = count_rows(text)
  lines.append(f"lines={counted['lines']}")
  lines.append(f"rows={counted['rows']}")
  lines.append(f"blank={counted['blank']}")
  lines.append(f"comment={counted['comment']}")
  lines.append(f"header={counted['header']}")
  for site, num, den in claims:
    eq = int(den == counted["rows"])
    lines.append(f"claim={site} {num}/{den} denom_eq_rows={eq}")
    if not eq:
      bad.append(f"{site} {num}/{den} denom {den} != rows {counted['rows']}")
  if produced is None:
    lines.append("generator=ABSENT")
    code = FAIL if bad else REFUSED
  elif produced != text:
    lines.append("generator=DIFF")
    bad.append("generator output != file")
    code = FAIL
  else:
    lines.append("generator=MATCH")
    code = FAIL if bad else PASS
  lines.append(f"disagreements={len(bad)}")
  return code, lines, bad


def settle(code: int, lines: list[str]) -> int:
  """A PASS that printed nothing is DEAD. Silence is not agreement."""
  return DEAD if not lines else code


def finish(code: int, lines: list[str]) -> int:
  code = settle(code, lines)
  if not lines:
    print("rows=0")
  else:
    for line in lines:
      print(line)
  print(f"verdict={VERDICT[code]}")
  return code


def live() -> int:
  path = ROOT / SUBJECT
  if not path.is_file():
    return finish(*judge(None, [], None)[:2])
  text = path.read_text()
  gens = discover_generators(ROOT)
  produced = None
  if gens:
    try:
      produced = run_generator(ROOT, gens[0])
    except Exception as exc:  # a generator that dies produced nothing to diff
      print(f"generator-raised={type(exc).__name__}", file=sys.stderr)
      produced = None
  code, lines, _bad = judge(text, discover_claims(ROOT), produced if gens else None)
  if gens:
    lines.insert(0, f"generators={len(gens)}")
  else:
    lines.insert(0, "generators=0")
  return finish(code, lines)


def expect(kind: str) -> int:
  """Synthetic inputs. The live tree is not the plant."""
  if kind == "dead":
    return finish(PASS, [])
  body = "a=1\n"
  if kind == "fail":
    return finish(*judge(body, [("synthetic:1", 1, 9)], None)[:2])
  if kind == "refuse":
    return finish(*judge(body, [("synthetic:1", 0, 1)], None)[:2])
  if kind == "pass":
    return finish(*judge(body, [("synthetic:1", 0, 1)], body)[:2])
  print(f"unknown expect {kind}", file=sys.stderr)
  return REFUSED


def plant() -> int:
  """Copies. The live file is read and not written. Each check prints a row."""
  live_path = ROOT / SUBJECT
  before = live_path.read_bytes()
  claims = discover_claims(ROOT)
  gens = discover_generators(ROOT)
  live_code, live_lines, live_bad = judge(before.decode(), claims, None if not gens else "")
  out: list[str] = []

  def emit(name: str, ok: bool) -> None:
    row = f"plant={name} {'OK' if ok else 'BAD'}"
    out.append(row)
    print(row)

  with tempfile.TemporaryDirectory() as td:
    untouched = Path(td) / "untouched.rows"
    dropped_path = Path(td) / "dropped.rows"
    untouched.write_bytes(before)
    data = [ln for ln in before.decode().splitlines() if ln.strip() and not ln.startswith("#") and "=" in ln]
    dropped_path.write_text("\n".join(data[:-1]) + "\n")
    copy_code, copy_lines, copy_bad = judge(untouched.read_text(), claims, None if not gens else "")
    drop_code, drop_lines, drop_bad = judge(dropped_path.read_text(), claims, None if not gens else "")
  intact = live_path.read_bytes() == before
  agree = [("synthetic:1", 0, count_rows(before.decode())["rows"])]
  refuse_code, refuse_lines, _ = judge(before.decode(), agree, None)
  pass_code, pass_lines, _ = judge(before.decode(), agree, before.decode())
  diff_code, diff_lines, _ = judge(before.decode(), agree, before.decode() + "extra=1\n")
  silent = settle(PASS, [])

  emit("live-emits", bool(live_lines))
  emit("unmutated-same", copy_bad == live_bad and copy_code == live_code and bool(copy_lines))
  emit("dropped-not-pass", drop_code != PASS and bool(drop_lines))
  emit("dropped-seen", drop_bad != live_bad)
  emit("refuse-arm", refuse_code == REFUSED and bool(refuse_lines))
  emit("pass-arm", pass_code == PASS and bool(pass_lines))
  emit("diff-arm", diff_code == FAIL and bool(diff_lines))
  emit("silent-not-pass", silent == DEAD)
  emit("live-file-intact", intact)
  if not out:
    print("plant-rows=0")
    return FAIL
  print(f"plant-rows={len(out)}")
  return PASS if all(row.endswith(" OK") for row in out) else FAIL


def main(argv: list[str]) -> int:
  if "--plant" in argv:
    return plant()
  if "--expect" in argv:
    at = argv.index("--expect")
    if at + 1 >= len(argv):
      return REFUSED
    return expect(argv[at + 1])
  return live()


if __name__ == "__main__":
  sys.exit(main(sys.argv[1:]))
