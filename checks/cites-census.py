#!/usr/bin/env python3
"""cites-census.py -- a census of the references THIS TREE makes INTO ITSELF.

THE SUBJECT is the opposite direction from the prune that prompted it.  That prune asked
"does a live instrument name a deleted path" and got `0` twice.  This asks the question
nobody counted: **the tree asserts things about its own files, and how many of those
assertions are still true?**

FOUR LANES, EACH WITH ITS OWN DENOMINATOR, AND NO LANE IS A POPULATION BY NAME:

  A  positional-ast   every AST tuple/list of shape (str, int, str) in every committed
                      `.py`.  This is the `(path, line, must_contain)` shape that
                      `checks/disagree-gate.py` DELETED from its own table.
  B  positional-prose `path:NNN` in prose.  No needle, so it is an EXISTENCE claim only.
  C  content-prose    a path and, on the same line, a quoted span that is not itself a
                      path: "it must contain X".
  D  numeric-prose    a path and, on the same line after it, `N lines|rows|files|bytes`.
  E  mention          a path with no predicate.  COUNTED, AND NEVER A VERDICT.

and one non-lane:

  U  unclassified     a path-shaped span this matcher refuses to decide.

FIVE VERDICTS, REPORTED AS TOKENS, NEVER AS EXIT CODES: PASS 0, FAIL 1, REFUSED 3,
SKIP 4, DEAD 5.  AN ABSENT SUBJECT IS `REFUSED`, NEVER A SILENT PASS AND NEVER A `FAIL`:
this census cannot distinguish "the file moved" from "the citation never described the
file", and guessing either way is the fault it exists to measure.

LANE B IS THE POINT OF THE INSTRUMENT.  It reports PASS for a citation whose position
exists and whose SUBJECT NEVER SAID WHAT THE CITATION SAYS, because it has no way to know
that -- so lane B's PASS count is a count of claims that CANNOT FAIL.  Run `--selftest`:
the plants include one that proves exactly this.
"""

from __future__ import annotations

import argparse
import ast
import os
import re
import subprocess
import sys
import tempfile
import tokenize
import warnings
from collections import Counter
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXTS = (".md", ".py")

PASS, FAIL, REFUSED, SKIP, DEAD = "PASS", "FAIL", "REFUSED", "SKIP", "DEAD"
EXITS = {PASS: 0, FAIL: 1, REFUSED: 3, SKIP: 4, DEAD: 5}

# THE EXTRACTORS DECLARE THEIR OWN POPULATION.  `git ls-tree -r HEAD` is git's own
# declaration of the tree.  `git ls-files` reads the INDEX, which this repo arms with
# intent-to-add placeholders BY DESIGN (`jj git colocation`), so it answers hundreds of
# paths HEAD does not contain -- and `git diff --cached` names 0.
def committed(exts: tuple[str, ...] = EXTS) -> list[str]:
  r = subprocess.run(["git", "ls-tree", "-r", "HEAD", "--name-only"], cwd=ROOT,
                     capture_output=True, text=True)
  if r.returncode != 0:
    print(f"{REFUSED}: git ls-tree rc={r.returncode}: {r.stderr.strip()}")
    sys.exit(EXITS[REFUSED])
  return sorted(p for p in r.stdout.splitlines() if p.endswith(exts))


def on_disk(exts: tuple[str, ...] = EXTS) -> list[str]:
  """A DIRECTORY WALK, the second admissible population.  Kept so the two can be
  DIFFERED: a census that reports one population and never notices the other is the
  `differ.declared()` fault with the import removed."""
  out = []
  for dirpath, dirnames, filenames in os.walk(ROOT):
    dirnames[:] = [d for d in dirnames if d not in (".git", ".venv", "__pycache__")]
    for fn in filenames:
      if fn.endswith(exts):
        out.append(str(Path(dirpath, fn).relative_to(ROOT)))
  return sorted(out)


# ---------------------------------------------------------------- token shapes

SPAN = re.compile(r"[A-Za-z0-9_.@^~][A-Za-z0-9_.@^~:+*/-]*")
FILENAME = re.compile(r"^[A-Za-z0-9_.^~+-]+\.[A-Za-z0-9]+$")
LINENO = re.compile(r"^\d+(-\d+)?$")
REV = re.compile(r"^[0-9a-f]{7,40}\^?:")
UNIT = re.compile(r"\b(\d+)\s+(lines?|rows?|files?|bytes?)\b")
QUOTED = re.compile(r"`([^`]{4,})`|\"([^\"]{4,})\"|'([^']{4,})'")
# A DIGEST, A REV, AN EXIT STATUS AND A COMMAND ARE NOT FILE CONTENT.  Asking whether a
# file "contains" `46c52f30d` or `rc=0` or `git rev-parse HEAD` is a question about a
# DIFFERENT KIND of claim, and answering it FAIL is a lie about what was asked.  These
# were 8 of the 23 classifier faults in a hand-labelled sample of 36.
DIGEST = re.compile(r"^[0-9a-f]{7,64}$")
EXITSTATUS = re.compile(r"^(rc=|exit\s)\d*\b")
COMMAND = re.compile(r"^(git|cc|wc|grep|find|diff|clang|bend|pytest|ruff|python|node)\b")

# THE RULE THE FIRST CHECK OF THIS SUBJECT BROKE.  A token must carry a `/` to be a PATH.
# `ops.py:1398` is a BASENAME and names every `ops.py` in the tree; `denom/` is a
# DIRECTORY and its trailing slash is a SUFFIX, not a path; and a string that merely
# APPEARS in an instrument is not a citation, it is a mention (lane E).
#
# *** THE ORDER IS THE WHOLE FIX, AND GETTING IT WRONG IS INVISIBLE. ***  An earlier
# revision of this file tested the WHOLE token against FILENAME first, so `checks/differ.py:670`
# and `ops.py:1398` both failed that test, both returned None, and lanes B, C and D
# reported `NOTHING TO JUDGE` over a tree that cites positions on every page -- an
# instrument that measured nothing and still printed a clean-looking summary.  The locator
# must be PEELED FIRST and the SUBJECT judged second.
REVSEG = re.compile(r"^[0-9a-f]{7,40}\^?$")
NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")


def token_kind(tok: str) -> tuple[str, str] | None:
  """`(kind, subject)` for one span, or None when it is not a reference at all.

  kind is one of: anchor (a `DEF:`/`AT:` locator, already undriftable -- lane E),
  glob, dir (a trailing slash is a SUFFIX), position, basename (a NAME, not a path),
  file, or unclassified.

  *** THE SUBJECT IS JUDGED WITHOUT ITS LOCATOR. ***  An earlier revision appended
  `:670` and then asked whether `differ.py:670` matched a FILENAME shape; it does not,
  so every positional citation returned None and lane B read `NOTHING TO JUDGE`.  And an
  earlier revision still classified every SPAN, which made `the`, `and` and `or` into
  1,604,391 "unclassified" -- a number four orders of magnitude above the population it
  claimed to describe.  A matcher that classifies ordinary words is measuring itself."""
  t = tok.rstrip("*").rstrip(".").rstrip(",")
  if t.startswith(("DEF:", "AT:")):
    return "anchor", t
  parts = [p for p in t.split(":") if p]
  if not parts:
    return None
  if REVSEG.match(parts[0]):
    parts = parts[1:]                       # `ad117c928^:path` names a BLOB
  loc = ""
  if len(parts) > 1 and LINENO.match(parts[-1]):
    loc, parts = ":" + parts[-1], parts[:-1]
  elif len(parts) > 1 and NAME.match(parts[-1]):
    loc, parts = ":" + parts[-1], parts[:-1]  # a DEF locator, resolvable by parser
  if not parts:
    return None
  base = ":".join(parts)
  if "*" in base:
    return "glob", base + loc
  if base.endswith("/"):
    return "dir", base
  slashed = "/" in base
  if not FILENAME.match(base.rsplit("/", 1)[-1]):
    # A slash with no extension is a DIRECTORY NAME, and the first check of this subject
    # counted exactly that as a citation.  No slash and no extension is an ENGLISH WORD.
    return ("unclassified/directory-name", base) if slashed else None
  if loc:
    return ("position" if slashed else "basename"), base + loc
  return ("file" if slashed else "basename"), base


def read(rel: str) -> str | None:
  """`rev:path` names a BLOB, not a file, and is read with `git show`."""
  if REV.match(rel):
    r = subprocess.run(["git", "show", rel], cwd=ROOT, capture_output=True, text=True)
    return r.stdout if r.returncode == 0 else None
  p = ROOT / rel
  return p.read_text(errors="replace") if p.is_file() else None


def cited(line: str, needle: str) -> bool:
  """`needle in line` is NOT a pin -- it lets a SUPERSET through.  `disagree-gate.py`
  says this and is right; a claim that still passes when the field it blames is renamed
  is a claim that cannot fail."""
  return re.search(re.escape(needle) + r"(?![\w])", line) is not None


# ---------------------------------------------------------------- the lanes

def lane_a(rel: str, text: str) -> list[dict]:
  """(str, int, str) tuple LITERALS, by AST.  Not grep: a comment saying `(path, 1, x)`
  is not an assertion, and a tuple built by a comprehension is not a hand-written one."""
  out = []
  try:
    tree = ast.parse(text)
  except SyntaxError as e:
    return [{"lane": "A", "kind": "unparsed", "file": rel, "subject": str(e)[:60]}]
  for node in ast.walk(tree):
    if not isinstance(node, (ast.Tuple, ast.List)) or len(node.elts) < 3:
      continue
    a, b, c = node.elts[:3]
    if not all(isinstance(x, ast.Constant) for x in (a, b, c)):
      continue
    if not (isinstance(a.value, str) and isinstance(b.value, int)
            and not isinstance(b.value, bool) and isinstance(c.value, str)):
      continue
    out.append({"lane": "A", "kind": "positional-ast", "file": rel,
                "subject": a.value, "line": b.value, "needle": c.value,
                "at": node.lineno})
  return out


def prose(rel: str, text: str) -> list[tuple[int, str]]:
  """(lineno, text) for every PROSE line.  A `.md` is prose; a `.py` contributes its
  COMMENTS (`tokenize`) and its DOCSTRINGS (`ast`).  A `.py` string literal is code and
  belongs to lane A, so it is excluded here by construction, not by taste."""
  if rel.endswith(".md"):
    return [(i, l) for i, l in enumerate(text.splitlines(), 1)]
  out = []
  try:
    for tok in tokenize.generate_tokens(iter(text.splitlines(True)).__next__):
      if tok.type == tokenize.COMMENT:
        out.append((tok.start[0], tok.string))
  except (tokenize.TokenError, IndentationError):
    pass
  try:
    tree = ast.parse(text)
  except SyntaxError:
    return out
  for node in ast.walk(tree):
    if isinstance(node, (ast.Module, ast.ClassDef, ast.FunctionDef, ast.AsyncFunctionDef)):
      doc = ast.get_docstring(node, clean=False)
      if doc:
        out.append((node.body[0].lineno, doc))
  return out


def lane_bcd(rel: str, lines: list[tuple[int, str]]) -> tuple[list[dict], Counter]:
  claims, unclass, seen = [], Counter(), set()
  for lineno, line in lines:
    for m in SPAN.finditer(line):
      tk = token_kind(m.group())
      if tk is None:
        continue
      kind, subject = tk
      if (rel, lineno, subject) in seen:
        continue
      seen.add((rel, lineno, subject))
      if kind == "unclassified/directory-name":
        unclass["directory name used as a citation (the first check's trap)"] += 1
        continue
      if kind == "basename":
        # A NAME IS NOT A PATH.  It is counted, named, and resolved against nothing --
        # there is no rule in this tree that says which `ops.py` a bare `ops.py:1398`
        # means, and inventing one is how a directory name became a citation once already.
        unclass["basename/" + ("position" if ":" in subject else "bare-filename")] += 1
        continue
      if kind in ("glob", "dir", "anchor"):
        claims.append({"lane": "E", "kind": kind, "file": rel, "subject": subject,
                       "at": lineno})
        continue
      rest = line[m.end():]
      if kind == "position":
        base, _, loc = subject.rpartition(":")
        if not LINENO.match(loc):
          unclass["name-locator (resolvable by parser, not by this census)"] += 1
          continue
        claims.append({"lane": "B", "kind": "position-prose", "file": rel,
                       "subject": base, "line": int(loc.split("-")[0]), "at": lineno})
        continue
      # *** A PREDICATE MUST BE ADJACENT TO ITS PATH OR IT IS NOT THIS PATH'S PREDICATE. ***
      # Taken from the quoted spans that START after the path, nearest first, and kept
      # only when nothing but a connector (`carries`, `has`, `:`, `->`) lies between.
      cands = [(a, c) for a, _, c in quoted_spans(line) if a >= m.end()
               and _is_connector(rest[:a - m.end()])]
      needle = next((c for _, c in cands
                     if c.strip("*:_ ") and "/" not in c
                     and token_kind(c) is None), None)
      if needle:
        claims.append({"lane": "C", "kind": "content-prose", "file": rel,
                       "subject": subject, "needle": needle, "at": lineno,
                       "unit": needle_unit(needle), "subjectless": needle.startswith(":")})
        continue
      u = UNIT.search(line, m.end())
      if u and _is_connector(line[m.end():u.start()]):
        claims.append({"lane": "D", "kind": "numeric-prose", "file": rel,
                       "subject": subject, "num": int(u.group(1)),
                       "unit": u.group(2).rstrip("s"), "at": lineno})
      else:
        claims.append({"lane": "E", "kind": "mention", "file": rel, "subject": subject,
                       "at": lineno})
  return claims, unclass


WORD3 = re.compile(r"[A-Za-z]{3,}")


def _is_connector(gap: str) -> bool:
  """A predicate belongs to this path only if nothing but a connector separates them."""
  return len(gap) <= 24 and not WORD3.search(gap)


def quoted_spans(s: str) -> list[tuple[int, int, str]]:
  """QUOTED SPANS WITH THEIR OFFSETS, pairing delimiters POSITIONALLY.

  *** PAIR THEM; DO NOT MATCH THEM. ***  The regex `` `([^`]{4,})` `` pairs the first
  backtick with the second, so in `` `a.md`, BEHIND TWO `b` `` it reports the span
  ", BEHIND TWO " -- a PROSE FRAGMENT -- as the quoted token, and this census then asked
  4,705 times whether some file contains the words "BEHIND TWO".  A backtick in markdown
  is a TOGGLE: the Nth opens and the N+1th closes."""
  out, i = [], 0
  while True:
    a = s.find("`", i)
    if a < 0:
      break
    b = s.find("`", a + 1)
    if b < 0:
      break
    out.append((a, b + 1, s[a + 1:b]))
    i = b + 1
  for m in re.finditer(r"\"([^\"]{4,})\"|'([^']{4,})'", s):
    out.append((m.start(), m.end(), next(g for g in m.groups() if g)))
  return sorted(out)


# ---------------------------------------------------------------- verdicts

def needle_unit(n: str) -> str:
  """Which KIND of claim is this needle?  Only `text` is a question about file content."""
  t = n.strip("*… ")
  return ("digest" if DIGEST.match(t) else
          "exit-status" if EXITSTATUS.match(t) else
          "command" if COMMAND.match(t) else "text")


def judge(c: dict) -> dict:
  if c["lane"] == "A":
    text = read(c["subject"])
    if text is None:
      return {**c, "verdict": REFUSED, "evidence": f"unreadable or absent: {c['subject']}"}
    lines = text.splitlines()
    n = c["line"]
    if n > len(lines):
      return {**c, "verdict": FAIL,
              "evidence": f"{c['subject']} has {len(lines)} lines, cited at :{n}"}
    if cited(lines[n - 1], c["needle"]):
      return {**c, "verdict": PASS, "evidence": f":{n} carries {c['needle'][:48]!r}"}
    near = [i for i, l in enumerate(lines, 1) if cited(l, c["needle"])]
    return {**c, "verdict": FAIL,
            "evidence": f":{n} reads {lines[n-1].strip()[:60]!r}; the text is at "
                        f"{near[:4] or 'NOWHERE'}"}
  if c["lane"] == "B":
    text = read(c["subject"])
    if text is None:
      return {**c, "verdict": REFUSED, "evidence": f"unreadable or absent: {c['subject']}"}
    n = len(text.splitlines())
    if c["line"] > n:
      return {**c, "verdict": FAIL, "evidence": f"{c['subject']} has {n} lines, cited at "
                                               f":{c['line']}"}
    return {**c, "verdict": PASS, "strength": "LOWER-BOUND-ONLY",
            "evidence": f":{c['line']} EXISTS in a {n}-line file; NOTHING checks what it says"}
  if c["lane"] == "C":
    if c.get("unit", "text") != "text":
      return {**c, "verdict": REFUSED,
              "evidence": f"the needle is {c['unit']}, a different KIND of claim: "
                          f"'{c['needle'][:40]}' is not file content"}
    if c.get("subjectless"):
      return {**c, "verdict": REFUSED,
              "evidence": f"the needle {c['needle']!r} is a POSITION, not content"}
    text = read(c["subject"])
    if text is None:
      return {**c, "verdict": REFUSED, "evidence": f"unreadable or absent: {c['subject']}"}
    if c["needle"] in text:
      return {**c, "verdict": PASS, "evidence": f"{c['needle'][:48]!r} occurs"}
    near = [i for i, l in enumerate(text.splitlines(), 1) if cited(l, c["needle"])]
    return {**c, "verdict": FAIL,
            "evidence": f"{c['needle'][:48]!r} is at {near[:4] or 'NOWHERE'} in "
                        f"{c['subject']}"}
  if c["lane"] == "D":
    if c["unit"] != "line":
      return {**c, "verdict": REFUSED,
              "evidence": f"unit {c['unit']!r} has no unambiguous meaning for a file"}
    text = read(c["subject"])
    if text is None:
      return {**c, "verdict": REFUSED, "evidence": f"unreadable or absent: {c['subject']}"}
    n = len(text.splitlines())
    ok = n == c["num"]
    return {**c, "verdict": PASS if ok else FAIL,
            "evidence": f"{c['subject']} has {n} lines, claim says {c['num']}"}
  return {**c, "verdict": SKIP, "evidence": "a mention is not a claim"}


def census(paths: list[str], tree: Path = ROOT) -> tuple[list[dict], Counter]:
  claims, unclass = [], Counter()
  for rel in paths:
    p = tree / rel
    try:
      text = p.read_text(errors="replace")
    except OSError as e:
      claims.append({"lane": "U", "kind": "unreadable", "file": rel, "subject": str(e)[:60]})
      continue
    if rel.endswith(".py"):
      claims += lane_a(rel, text)
    got, un = lane_bcd(rel, prose(rel, text))
    claims += got
    unclass += un
  return claims, unclass


def summarise(claims: list[dict], unclass: Counter, paths: list[str]) -> str:
  L = Counter(c["lane"] for c in claims)
  V = Counter((c["lane"], c.get("verdict", DEAD)) for c in claims)
  judged = [c for c in claims if c.get("verdict") in (PASS, FAIL, REFUSED)]
  worst = FAIL if any(c["verdict"] == FAIL for c in judged) else (
    REFUSED if any(c["verdict"] == REFUSED for c in judged) else PASS)
  o = [f"POPULATION : {len(paths)} committed .md/.py files (git ls-tree -r HEAD)",
       f"LANE A     : {L['A']}  positional (path, int, str) AST tuple literals",
       f"LANE B     : {L['B']}  `path:NNN` in prose -- EXISTENCE claims, no needle",
       f"LANE C     : {L['C']}  path + quoted content on one line",
       f"LANE D     : {L['D']}  path + `N lines|rows|files|bytes`",
       f"LANE E     : {L['E']}  mentions -- COUNTED, NEVER A VERDICT",
       f"UNCLASSIFIED: {sum(unclass.values())}  " + ", ".join(
         f"{k}={v}" for k, v in sorted(unclass.items()))]
  for lane in "ABCD":
    parts = [f"{v}={V[(lane, v)]}" for v in (PASS, FAIL, REFUSED) if V[(lane, v)]]
    o.append(f"VERDICT {lane}   : {' '.join(parts) or 'NOTHING TO JUDGE'}")
  o += [f"TOTAL       : PASS={sum(V[(l, PASS)] for l in 'ABCD')} "
        f"FAIL={sum(V[(l, FAIL)] for l in 'ABCD')} "
        f"REFUSED={sum(V[(l, REFUSED)] for l in 'ABCD')}",
        f"LOWER-BOUND : {sum(1 for c in judged if c.get('strength'))} claims PASS on "
        f"EXISTENCE and check nothing else -- they CANNOT FAIL",
        f"VERDICT: {worst} (exit {EXITS[worst]})"]
  return "\n".join(o)


# ---------------------------------------------------------------- plants

def selftest(tree: Path) -> int:
  """THE HARNESS COMES FIRST: five claims, and the tree must move its verdict for each.
  A census that cannot fail is the instrument this file was written to catch."""
  cases = []
  with tempfile.TemporaryDirectory(prefix="cites-census-") as tmp:
    d = Path(tmp)
    (d / "s.py").write_text("# a comment is prose\n")
    subj = d / "s.txt"
    subj.write_text("alpha\nbeta\ngamma\n")
    base = [{"lane": "A", "kind": "positional-ast", "file": "s.py", "subject": str(subj),
             "line": 2, "needle": "beta"},
            {"lane": "B", "kind": "position-prose", "file": "s.py", "subject": str(subj),
             "line": 2},
            {"lane": "C", "kind": "content-prose", "file": "s.py", "subject": str(subj),
             "needle": "beta"},
            {"lane": "D", "kind": "numeric-prose", "file": "s.py", "subject": str(subj),
             "num": 3, "unit": "line"},
            {"lane": "C", "kind": "content-prose", "file": "s.py", "subject": str(subj),
             "needle": "alpha"}]
    cases.append(("CONTROL: the scratch tree as built is all PASS",
                  [judge(c)["verdict"] for c in base], [PASS] * 5))
    subj.write_text("beta\ngamma\n")                   # the needle MOVED UP one line
    cases.append(("DRIFT: :2 no longer carries the text the AST lane pins there",
                  [judge(base[0])["verdict"], judge(base[2])["verdict"]], [FAIL, PASS]))
    subj.write_text("alpha\nbeta\ngamma\nnope\n")     # the file GREW
    cases.append(("GROW: a bare position still exists, and still checks nothing else",
                  judge(base[1])["verdict"], PASS))
    cases.append(("SHORTENED: a position past the end of the file is FALSE",
                  judge({**base[1], "line": 99})["verdict"], FAIL))
    cases.append(("NUMERIC: the count moved, and the numeric lane knows",
                  judge(base[3])["verdict"], FAIL))
    subj.unlink()
    cases.append(("ABSENT: an unreadable subject is REFUSED, never a silent pass",
                  judge(base[0])["verdict"], REFUSED))
  fails = 0
  for why, got, want in cases:
    ok = got == want
    fails += not ok
    print(f"[{'   PASS' if ok else '   FAIL'}] {why}\n          got {got}, want {want}")
  print(f"\n=== selftest {'PASS' if not fails else 'FAIL'}: {len(cases)} case(s) run, "
        f"{fails} failed ===")
  return EXITS[PASS if not fails else FAIL]


def main() -> int:
  ap = argparse.ArgumentParser(description=__doc__.split("\n")[1])
  ap.add_argument("--selftest", action="store_true")
  ap.add_argument("--rows", default=None, help="write one row per claim here (.rows)")
  ap.add_argument("--sample-fail", type=int, metavar="N", default=0,
                  help="write N evenly-spaced FAIL rows for HAND LABELING. The census "
                       "cannot state its own precision; a human has to, and guessing is "
                       "the fault this file exists to catch.")
  args = ap.parse_args()
  if args.selftest:
    return selftest(ROOT)
  paths = committed()
  disk = on_disk()
  only_disk = [p for p in disk if p not in set(paths)]
  with warnings.catch_warnings():     # other people's SyntaxWarnings are not our verdicts
    warnings.simplefilter("ignore")
    claims, unclass = census(paths)
    judged = [judge(c) for c in claims]
  if args.sample_fail:
    # *** A STRIDE OVER SORTED ROWS IS NOT A SAMPLE. ***  An earlier revision took
    # `fails[::step]` and got 40 rows of which 31 were one file and one heading word
    # (`DELETE`), because the rows are sorted by file and a stride therefore samples
    # whichever files DOMINATE the FAIL count rather than the FAIL population.  The
    # effective population was two files.  STRATIFY BY CLAIMING FILE: one row per file,
    # files taken round-robin, so a single noisy `.md` cannot stand in for 2,000 claims.
    fails = [c for c in judged if c.get("verdict") == FAIL]
    byfile: dict[str, list[dict]] = {}
    for c in fails:
      byfile.setdefault(c["file"], []).append(c)
    order = sorted(byfile, key=lambda f: (-len(byfile[f]), f))
    picked, i = [], 0
    while len(picked) < args.sample_fail and any(byfile.values()):
      f = order[i % len(order)]
      if byfile[f]:
        picked.append(byfile[f].pop(0))
      i += 1
    out = args.rows or ".agents/slop/dangle/sample.rows"
    Path(out).write_text("".join(
      f"{i}\t{c['lane']}\t{c['file']}:{c.get('at','')}\t{c.get('subject','')}\t"
      f"{c.get('needle') or c.get('num','')}\t{c.get('evidence','')}\n"
      for i, c in enumerate(picked, 1)))
    print(f"SAMPLE    : {len(picked)} rows from {len(picked)} of {len(byfile)} FAILING "
          f"FILES ({len(fails)} FAIL rows total) -> {out}")
    print("LABEL THESE: TRUE (the claim is false) or CLASSIFIER (the matcher is wrong).")
    return EXITS[PASS]
  print(summarise(judged, unclass, paths))
  print(f"SCOPE     : {len(disk)} on-disk .md/.py; {len(only_disk)} are NOT in HEAD "
        f"(ignored or intent-to-add) and are NOT censused")
  if args.rows:
    Path(args.rows).write_text("".join(
      f"{c.get('lane')}\t{c.get('kind')}\t{c.get('verdict','-')}\t{c.get('file')}:{c.get('at','')}\t"
      f"{c.get('subject','')}\t{c.get('evidence','')}\n" for c in judged))
    print(f"ROWS      : {len(judged)} rows -> {args.rows}")
  real = [c for c in judged if c.get("verdict") in (PASS, FAIL, REFUSED)]
  worst = FAIL if any(c["verdict"] == FAIL for c in real) else (
    REFUSED if any(c["verdict"] == REFUSED for c in real) else PASS)
  return EXITS[worst]


if __name__ == "__main__":
  sys.exit(main())