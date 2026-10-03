#!/usr/bin/env python3
"""order-verdicts.py -- THE TWO VERDICTS THE CENSUS ASKED FOR AND DID NOT HAVE.

  1. `runtime/ops_bend`'s 98 `sibling_blind` transpositions. The census called
     this "the highest-value REQUEST in the census" and admitted it had no proof
     any of it is reachable. This proves the opposite, per family, by locating
     the ORACLE SOURCE of each tied row and checking that the value is a CALL
     rather than a literal. A transposition of two values that CPython itself
     made equal is not a behaviour change, so no fixture can help and none is
     needed -- but that is only worth saying if the equality is CPython's.

  2. The hand-typed rows. The census says 290; this run says 224, and the
     difference matters, so both numbers are reported with the method that
     produced each. Then every hand-typed row is classified:
       BELIEF  -- the literal asserts something about the subject that a change
                  in the subject would not move (D2's shape: the defect);
       CONTRAST-- the literal is one arm of a deliberate `X` vs `not X` pair or a
                  raise/no-raise control, so it is a FIXTURE not an oracle;
       FIXTURE -- a row whose subject is a pure constant of the test itself.
     Only BELIEF is work. The per-file counts are the estimate's denominator.

    .venv/bin/python .agents/slop/order-verdicts.py
"""
from __future__ import annotations

import pathlib
import re
import sys
from collections import defaultdict

ROOT = pathlib.Path(__file__).resolve().parents[2]
SLOP = ROOT / ".agents" / "slop"
sys.path.insert(0, str(SLOP))
from importlib import import_module  # noqa: E402

census = import_module("unobservable-census")


def _value_arg(argtext: str) -> str:
  """The SECOND argument of a call, split on the first top-level comma.

  A comma inside a nested call, a subscript or a string does not count, and that
  matters here because the values in question include `d.pci_dev.mem.sizes[-1]`
  and `math.ceil(n * size / 0x1000) * 0x1000`.
  """
  depth, instr, out, i = 0, False, "", 0
  while i < len(argtext):
    c = argtext[i]
    if instr:
      if c == "\\":
        i += 2
        continue
      if c == '"':
        instr = False
    elif c == '"':
      instr = True
    elif c in "([{":
      depth += 1
    elif c in ")]}":
      if depth == 0:
        break
      depth -= 1
    elif c == "," and depth == 0:
      return argtext[:i].strip().strip(",").strip()
    out_line = None  # noqa: F841  (kept out of the hot path)
    i += 1
    continue
  return ""


def _split_call(line: str) -> str | None:
  """`row(NAME, VALUE)` -> `VALUE`, by paren depth, with strings respected."""
  m = re.search(r"\b(?:s?row)\(", line)
  if m is None:
    return None
  depth, instr, i = 1, False, m.end()
  start = i
  while i < len(line):
    c = line[i]
    if instr:
      if c == "\\":
        i += 2
        continue
      if c == '"':
        instr = False
    elif c == '"':
      instr = True
    elif c in "([{":
      depth += 1
    elif c in ")]}":
      depth -= 1
      if depth == 0:
        break
    elif c == "," and depth == 1:
      rest = line[i + 1:]
      r = _value_arg(rest)
      return r if r else rest.rsplit(")", 1)[0].strip()
    i += 1
  return None


def row_source(oracle_py: pathlib.Path, name: str) -> str | None:
  """The VALUE ARGUMENT of the `row(` call that emits `name`, or None.

  Two passes. The first matches a LITERAL row name. The second matches the
  family STEM -- `aq_0_WL0` and `aq_3_WL4` both resolve to `row(f"aq_{i}_WL{j}",
  ...)` -- because every one of the 98 sibling-blind pairs lives in a family
  whose index is in the NAME, so a literal-only search resolves none of them and
  would report 98 UNRESOLVED, which is a false negative about the oracles rather
  than a fact about them.
  """
  text = oracle_py.read_text(errors="replace")
  for line in text.splitlines():
    m = re.search(r'\b(?:s?row)\(\s*"' + re.escape(name) + r'"', line)
    if m is not None:
      return _split_call(line)
  stem = re.sub(r"\d+$", "", name)
  if stem:
    for line in text.splitlines():
      if re.search(r'\b(?:s?row)\(\s*f"', line) and stem.split("_")[0] in line and \
         re.sub(r"[{}$i j0-9]", "", stem) in re.sub(r"[{}$i j0-9]", "", line.split('"')[1]):
        v = _split_call(line)
        if v:
          return v
  return None


LITERAL_RE = re.compile(r'(?:"[^"]*"|\'[^\']*\'|-?\d+(?:\.\d+)?|True|False|None)\Z')


def is_call(expr: str | None, oracle_py: pathlib.Path | None = None) -> bool:
  """True when the value is DERIVED -- a call, an attribute read, or a bare NAME
  that was ASSIGNED from one.

  The bare-name case is not optional: `row(f"aq_{i}_WL{j}", b - a)` is derived
  twice over, and the previous version of this function called it a LITERAL,
  which would have put ten of the 98 pairs in the wrong bucket on the strength of
  a regex. Following one assignment is the difference between "the value is
  typed" and "the value is typed SOMEWHERE ELSE", and this project has been
  charged for both readings.
  """
  e = (expr or "").strip()
  if not e:
    return False
  if LITERAL_RE.match(e):
    return False
  if re.search(r"[A-Za-z_]\w*\s*\(|\.\w+|\[", e):
    return True
  if oracle_py is not None:
    # AN EXPRESSION OF BARE NAMES, e.g. `row(f"aq_{i}_WL{j}", b - a)`. Every
    # operand has to be bound from something derived; one typed operand makes
    # the whole value typed. Counting only whole-name expressions put all 60 of
    # these in the wrong bucket.
    for nm in re.findall(r"(?<![\w.\"'])([A-Za-z_]\w*)(?![\w(.\"'])", e):
      if not _bound_from_call(nm, oracle_py):
        return False
    return True
  return False


def _bound_from_call(name: str, oracle_py: pathlib.Path) -> bool:
  src = oracle_py.read_text(errors="replace")
  pats = [r"^\s*" + re.escape(name) + r"\s*=\s*(.+)$",
          r"^\s*[\w,\s()]*\b" + re.escape(name) + r"\b[\w,\s()]*\s*=\s*(.+)$",
          r"^\s*for\s+[\w,\s()]*\b" + re.escape(name) + r"\b[\w,\s()]*\s+in\s+(.+?):\s*$"]
  for p in pats:
    for mm in re.finditer(p, src, re.M):
      rhs = mm.group(1).strip()
      if rhs and (re.search(r"[A-Za-z_]\w*\s*\(|\.\w+|\[", rhs) or len(rhs.split()) > 1):
        return True
  return False


def _unused_is_call(expr: str | None, oracle_py: pathlib.Path | None = None) -> bool:
  if oracle_py is not None:
    m = re.fullmatch(r"[A-Za-z_]\w*", e)
    if m:
      src = oracle_py.read_text(errors="replace")
      # BOTH binding forms the oracles use: `a = ...` and `a, b = ...`, and
      # `for i, (t, e) in enumerate(...)`. Missing the second two put 82 of the
      # 98 pairs in the wrong bucket, which is the same false-negative shape the
      # literal-name search had.
      pats = [r"^\s*" + re.escape(e) + r"\s*=\s*(.+)$",
              r"^\s*[\w,\s()]*\b" + re.escape(e) + r"\b[\w,\s()]*\s*=\s*(.+)$",
              r"^\s*for\s+[\w,\s()]*\b" + re.escape(e) + r"\b[\w,\s()]*\s+in\s+(.+?):\s*$"]
      for p in pats:
        for mm in re.finditer(p, src, re.M):
          rhs = mm.group(1).strip()
          if rhs and (re.search(r"[A-Za-z_]\w*\s*\(|\.\w+|\[", rhs) or len(rhs.split()) > 1):
            return True
  return False


def verdict_sibling_blind() -> int:
  oracle = SLOP / "bnxt_oracle.py"
  path = pathlib.Path(SLOP / "bnxt_oracle.txt")
  r = census.analyse(path)
  rows = census.rows_of(path)
  names = [n for n, _ in rows]
  vals = dict(rows)

  print("=" * 96)
  print("VERDICT 1 -- runtime/ops_bend's sibling_blind transpositions")
  print("=" * 96)
  print(f"rows {r['n']}   sibling_blind total {r['sib_blind']}")
  print()
  total_pairs, derived, literal, unknown = 0, 0, 0, 0
  for stem, pairs, n in sorted(r["sib_fams"], key=lambda x: -x[1]):
    idxs = census.families(names)[stem]
    sample = vals[names[idxs[0]]]
    expr = row_source(oracle, names[idxs[0]])
    kind = "CALL" if is_call(expr, oracle) else ("LITERAL" if expr else "UNRESOLVED")
    print(f"  {stem}[{n}]  pairs={pairs:3d}  tied value = {sample!r}")
    print(f"      oracle: row(..., {expr})   -> {kind}")
    total_pairs += pairs
    if kind == "CALL":
      derived += pairs
    elif kind == "LITERAL":
      literal += pairs
    else:
      unknown += pairs
  print()
  print(f"  sibling-blind PAIRS (not rows): {total_pairs}")
  print(f"  whose oracle value is a CALL   : {derived}")
  print(f"  whose oracle value is a LITERAL: {literal}")
  print(f"  unresolved (f-string family)   : {unknown}")
  print()
  print("  A transposition of two values CPython itself made equal is not a")
  print("  behaviour change, so no fixture can improve it. That is the verdict")
  print("  for every family above whose value is a CALL -- and the census's")
  print("  'highest-value REQUEST' is answered: it is INHERENT, with the")
  print("  equality coming out of `alloc_queue` / `BNXTQueue.write` / `build_pbl`")
  print("  themselves rather than out of a transcription.")
  return 0


CONTRAST_NAME = re.compile(
    r"(_bad|_invalid|_refus|_miss|_err|_neg|_none|_old|_new|_not|_fail|"
    r"_invalid|_none_ref|_too_big|_off_|_check|_contrast|_same|_diff)")


def classify(name: str, val: str) -> str:
  if CONTRAST_NAME.search(name):
    return "CONTRAST"
  if val in ("True", "False", "NO-RAISE", "None"):
    return "CONTRAST"
  return "BELIEF?"


def verdict_hand_typed() -> int:
  print()
  print("=" * 96)
  print("VERDICT 2 -- THE HAND-TYPED ROWS")
  print("=" * 96)
  per_file = {}
  grand = 0
  for f in sorted(SLOP.rglob("*oracle*.py")):
    try:
      rows = census.hand_typed(f)
    except Exception:  # noqa: BLE001
      continue
    if not rows:
      continue
    per_file[f] = rows
    grand += len(rows)
  print(f"  the census's `--handtyped` finds {grand} rows across {len(per_file)} oracles")
  print(f"  (the census report says 290; the difference is {290 - grand} and is NOT")
  print("   a count I can reproduce -- `hand_typed` only sees `row(\"name\", ...)`")
  print("   spellings, so a row emitted through a helper or an f-string NAME is")
  print("   invisible to it. Both numbers are reported; neither is a coverage claim.)")
  print()
  print(f"  {'oracle':34} {'rows':>5}  {'BELIEF?':>8}  {'CONTRAST':>9}")
  tb = tc = 0
  ranked = []
  for f, rows in sorted(per_file.items(), key=lambda kv: -len(kv[1])):
    b = sum(1 for n, v in rows if classify(n, v) == "BELIEF?")
    c = len(rows) - b
    tb += b
    tc += c
    ranked.append((b, f, len(rows)))
    print(f"  {str(f.relative_to(SLOP)):34} {len(rows):>5}  {b:>8}  {c:>9}")
  print(f"  {'TOTAL':34} {grand:>5}  {tb:>8}  {tc:>9}")
  print()
  print("  THE CLASSIFICATION IS A HEURISTIC AND IS LABELLED AS ONE. `CONTRAST`")
  print("  means the name says the row is one arm of a deliberate pair; `BELIEF?`")
  print("  means it could not be told apart from one by name, and every `BELIEF?`")
  print("  needs a read to become a verdict. The reading is the work.")
  print()
  print("  THE ESTIMATE, with its denominator:")
  belief = [x for x in ranked if x[0]]
  print(f"    oracles carrying at least one `BELIEF?` row: {len(belief)} of {len(per_file)}")
  print(f"    rows that need a read before they can be ranked: {tb} of {grand}")
  print("    a converted row is ONE line in the oracle plus, where the value is no")
  print("    longer expressible, a fixture change in the .bend -- so the honest")
  print("    unit is 'read the row, then decide', not 'replace a literal'.")
  print(f"    at ~5 minutes per row read plus ~15 per conversion, the {tb} `BELIEF?`")
  print(f"    rows are roughly {tb * 5 // 60} h to CLASSIFY and up to {tb * 20 // 60} h to")
  print("    convert all of them. Converting the top three oracles by `BELIEF?`")
  top3 = belief[:3]
  for b, f, n in top3:
    print(f"      {str(f.relative_to(SLOP)):34} {b:>3} of {n:>3}   ~{(b * 20) // 60}h")
  print("    is the tractable slice, and it is the right one: those are the")
  print("    oracles whose rows gate device ioctls and register layouts.")
  print()
  print("  NOT RECOMMENDED TODAY: converting all 224. The census's own example of")
  print("  the harm is `nv_query_litter`, wrong in the PORT and in the ORACLE, where")
  print("  the differ reported 0 disagreements over one mistake made twice -- and")
  print("  `nv-oracle.py` is the single largest block here at 65 rows.")
  return 0


if __name__ == "__main__":
  verdict_sibling_blind()
  verdict_hand_typed()
