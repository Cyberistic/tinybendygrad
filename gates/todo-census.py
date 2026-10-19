#!/usr/bin/env python3
"""todo-census.py -- every `TODO` site in `tinybendygrad/**/*.bend`, ONE ROW PER SITE, and a
CLASS FOR EACH ROW THAT IS DECIDED BY A COMMAND AND NOT BY READING.

    .venv/bin/python gates/todo-census.py                 # census + summary
    .venv/bin/python gates/todo-census.py --rows          # the per-site table
    .venv/bin/python gates/todo-census.py --root <dir>    # walk a COPY (the plant does this)

WHAT THE UNIT IS, BECAUSE THAT IS THE WHOLE ARGUMENT. The reader of "there are 929 TODOs" will
assume a count of TASKS. This gate's unit is a SITE: one line of one `.bend` file that contains
the token `TODO`. Those are different units, they differ by a factor of roughly nine, and
conflating them is the error. The summary therefore prints the site count, the line count and the
file count side by side, and every number carries the command that produced it.

WHAT A CLASS MAY NOT BE. A census that forces every row into a class is not a census, so
`UNDECIDED` is a first-class verdict with its own row, not a remainder swept into a bucket. The
strongest available test -- "the subject upstream STILL HAS and the port DOES NOT" -- needs a
symbol name, and 599 of the 758 cited sites carry NO mechanically extractable one, so for those
the question cannot be asked by a command at all and the row is `UNDECIDED`. That is reported as
a count, not as a defect in the tree.

THE FOURTH CLASS. The three classes this gate was asked for are gap, deliberate non-goal and
per-file compile note. The population contains a fourth: lines that name another TODO. A line in
`viz/serve.bend` that reads "it is `ops.bend:3455 # TODO(p3) ops.py:76`" is PROSE ABOUT a TODO,
not a TODO, and it inflates any census that counts the string. It is decidable by a command --
the line cites a `.bend` path and no upstream `X.py:NNN` -- so it is a class, not a note.

THE CLASSES, EACH WITH THE COMMAND THAT DECIDES IT. Precedence is top-down and every row also
carries its raw features, so a reader can re-cut the table without re-reading the tree.

  XREF      the line cites a `.bend` path and resolves no upstream `X.py:NNN`
  FRAG      the containing file has no `def main` AND no other `.bend` imports it
  NONG      no resolvable upstream citation AND the comment block carries a reason marker
  GAP       an upstream `X.py:NNN` resolves AND the port file has no `def <ident>`
  UNDECIDED none of the above

WHY "UPSTREAM STILL HAS" IS NOT CHECKED. It is checked -- `ident` is searched in the whole cited
upstream file -- but it is only reachable for the minority of rows whose symbol is in backticks
next to the citation. Adding it as a hard requirement would move ~500 rows from `GAP` to
`UNDECIDED` and turn the instrument into a null result, so `GAP` records what it measured (the
citation resolves, the port has no such def) and the residual is stated in the summary.

THE REVERSE CHECK. A `GAP` that a gate already covers and that is green is a DONE thing, not an
open one. So every `GAP` row is looked up in the instrument population (`gates/`, `checks/`,
`oracles/` -- a directory walk, never a hand list) by its citation and by its symbol. This is the
half nobody does, and it is the half that decides whether 700 rows are work.

WHAT THIS GATE DOES NOT CLAIM. It does not claim the classes are right; it claims each one is
reproducible from the features printed beside it. It runs no `bend`, transcribes no expected
value, and modifies nothing outside `--root`.
"""
import argparse
import os
import re
import sys
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
UPSTREAM = os.path.join(REPO, "tinygrad")

SITE = re.compile(r"\bTODO\b")
TAG = re.compile(r"TODO\(([^)]*)\)")
CITE = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)\.py:(\d+)")
BENDREF = re.compile(r"([A-Za-z0-9_./-]+\.bend)(?::(\d+))?")
IDENT = re.compile(r"`([A-Za-z_][A-Za-z0-9_]*)`")
IMPORT = re.compile(r"(?:^|\s)(?:from|import)\s+([A-Za-z0-9_.]+)")
DEFMAIN = re.compile(r"^def main\b", re.M)

# A reason marker is a word that commits the author to a cause. Its ABSENCE is never read as
# "no reason"; it only stops the row from being claimed as a documented non-goal.
REASON = re.compile(
  r"\b(?:because|since|intentional|deliberate|non-?goal|by design|on purpose|"
  r"upstream (?:has|still|does)|not ported|will not|never|instead of|so that)\b",
  re.I,
)

CLASSES = ("GAP", "NONG", "FRAG", "XREF", "UNDECIDED")

# Backticked words are not automatically symbols. `ops.py:581 def index` yields `return` from the
# NEXT line of prose, and a row whose "symbol" is a Python keyword is a row the reverse check
# would match on by accident. These are refused at EXTRACTION, not filtered at the count, so a
# refused symbol becomes UNDECIDED where it belongs instead of becoming a false GAP.
NOT_A_SYMBOL = {
  "return", "ctx", "the", "and", "not", "is", "a", "an", "of", "in", "to", "for", "if",
  "self", "none", "true", "false", "int", "str", "bool", "float", "list", "dict", "set",
  "def", "class", "import", "from", "with", "as", "it", "its", "this", "that", "which",
}


def walk(root, ext):
  """Populations are DISCOVERED (doctrine 1). os.walk + endswith; never glob, which returns []."""
  found = []
  for dirpath, _dirs, names in os.walk(root):
    for name in names:
      if name.endswith(ext):
        found.append(os.path.join(dirpath, name))
  return sorted(found)


def read(path):
  with open(path, encoding="utf-8", errors="replace") as handle:
    return handle.read()


def upstream_index():
  """basename -> [paths]. Discovery, not a list; basename collisions are resolved, not hidden."""
  index = {}
  for path in walk(UPSTREAM, ".py"):
    index.setdefault(os.path.basename(path)[:-3], []).append(path)
  return index


def nonprograms(bends, texts):
  """A file is a PROGRAM if it defines `main` or another `.bend` imports it.

  Keys are relative path stems. Keying by BASENAME collapses `__init__.bend` -- eight distinct
  files -- onto one name, which is the normalisation bug that made a previous census report a
  false positive, so it is not done here.
  """
  mods = {path[len(bends[0].split(os.sep)[0]) + 1:]: path for path in bends}
  stems = {os.path.splitext(os.path.basename(p))[0]: p for p in bends}
  imported = set()
  for text in texts.values():
    for match in IMPORT.finditer(text):
      name = match.group(1)
      target = mods.get(name) or stems.get(name.rsplit(".", 1)[-1])
      if target:
        imported.add(target)
  return {p for p in bends
          if not DEFMAIN.search(texts[p]) and p not in imported}


def comment_block(lines, index):
  """The contiguous run of comment lines around `index`, which is where the reason lives.

  A TODO whose reason is on the next line is a documented non-goal; reading the single line
  would call it undocumented. This walks UP while the previous line is a comment and DOWN while
  the next line is a comment.
  """
  if index >= len(lines) or not lines[index].lstrip().startswith("#"):
    return lines[index] if index < len(lines) else ""
  start = index
  while start > 0 and lines[start - 1].lstrip().startswith("#"):
    start -= 1
  stop = index
  while stop + 1 < len(lines) and lines[stop + 1].lstrip().startswith("#"):
    stop += 1
  return "\n".join(lines[start:stop + 1])


def upstream_lines(index):
  cache = {}

  def at(basename, number):
    key = (basename, number)
    if key not in cache:
      paths = index.get(basename, ())
      cache[key] = any(number <= len(read(p).splitlines()) for p in paths)
    return cache[key]

  def has(basename, symbol):
    key = ("has", basename, symbol)
    if key not in cache:
      cache[key] = any(re.search(r"\b" + re.escape(symbol) + r"\b", read(p))
                       for p in index.get(basename, ()))
    return cache[key]

  return at, has


def census(root):
  bends = walk(root, ".bend")
  texts = {p: read(p) for p in bends}
  fragments = nonprograms(bends, texts)
  upindex = upstream_index()
  at, upstream_has = upstream_lines(upindex)

  rows = []
  for path in bends:
    lines = texts[path].splitlines()
    for number, line in enumerate(lines, 1):
      if not SITE.search(line):
        continue
      tags = TAG.findall(line)
      cites = CITE.findall(line)
      resolves = [(b, n) for b, n in cites if at(b, int(n))]
      block = comment_block(lines, number - 1)
      symbol = None
      for match in CITE.finditer(line):
        found = IDENT.search(line[match.end():])
        if found and found.group(1) not in NOT_A_SYMBOL:
          symbol = found.group(1)
          break
      port_has_def = symbol and re.search(r"^\s*def\s+" + re.escape(symbol) + r"\b",
                                           texts[path], re.M)
      bendref = BENDREF.search(line)
      rows.append({
        "path": os.path.relpath(path, REPO if path.startswith(REPO) else root),
        "line": number,
        "tag": tags[0] if tags else "",
        "cite": f"{cites[0][0]}.py:{cites[0][1]}" if cites else "",
        "cited": len(cites),
        "resolves": len(resolves),
        "symbol": symbol or "",
        "upstream_has": bool(symbol and resolves and upstream_has(resolves[0][0], symbol)),
        "port_has_def": bool(port_has_def),
        "fragment": path in fragments,
        "xref": bool(bendref) and not cites,
        "reason": bool(REASON.search(block)),
        "text": line.strip(),
        "named_by": "",
        "read_by": "",
      })

  for row in rows:
    row["class"] = classify(row)
  return rows, bends, fragments


def classify(row):
  if row["xref"]:
    return "XREF"
  if row["fragment"]:
    return "FRAG"
  if not row["resolves"] and row["reason"]:
    return "NONG"
  if row["resolves"] and row["symbol"] and not row["port_has_def"]:
    return "GAP"
  return "UNDECIDED"


def instrument_texts():
  """The instrument population. A directory walk -- `gates/`, `checks/`, `oracles/`."""
  paths = walk(os.path.join(REPO, "gates"), ".py") + walk(os.path.join(REPO, "checks"), ".py")
  paths += [p for p in walk(os.path.join(REPO, "oracles"), "")
            if os.path.isfile(p) and not p.endswith((".bend", ".txt"))]
  return {p: read(p) for p in paths}


def covered(rows):
  """REVERSE CHECK, IN TWO SIGNALS, BECAUSE ONE SIGNAL IS LYING.

  `named_by` -- some gate/oracle TEXT contains this row's citation or symbol. This is a MENTION.
  The tree's gate docstrings quote TODO lines verbatim to explain what the gate is about, so this
  signal is satisfied by a gate that has read the sentence and measured nothing at all. Reporting
  it as coverage would be the `artefacts_ok()` error in a new place.

  `read_by` -- some gate/oracle TEXT contains the CONTAINING .bend path. A gate that opens a file
  and prints rows from it exercises that file, which is the strongest claim available without
  RUNNING the gate. It is still not a greenness claim: whether the gate currently passes is a
  separate measurement and is not made here.
  """
  corpus = instrument_texts()
  for row in rows:
    if row["class"] != "GAP":
      continue
    needles = [n for n in (row["cite"], row["symbol"]) if n]
    path = row["path"].split("tinybendygrad/")[-1]
    named = read_by = None
    for file, text in corpus.items():
      if named is None and any(n and n in text for n in needles):
        named = file
      if read_by is None and path in text:
        read_by = file
      if named and read_by:
        break
    row["named_by"] = os.path.relpath(named, REPO) if named else ""
    row["read_by"] = os.path.relpath(read_by, REPO) if read_by else ""


def report(rows, bends, fragments):
  byclass = Counter(r["class"] for r in rows)
  gaps = [r for r in rows if r["class"] == "GAP"]
  named = sum(1 for r in gaps if r["named_by"])
  read = sum(1 for r in gaps if r["read_by"])
  both = sum(1 for r in gaps if r["read_by"])

  print("UNIT: one SITE = one line of one .bend file containing the token TODO.")
  print("COMMAND: .venv/bin/python gates/todo-census.py   (os.walk + endswith('.bend'))")
  print(f"  .bend files walked : {len(bends)}")
  print(f"  files with >=1 TODO: {len({r['path'] for r in rows})}")
  print(f"  SITES (the unit)   : {len(rows)}")
  print(f"  fragment files     : {len(fragments)}")
  print()
  print("CLASS SPLIT (each decided by a command; UNDECIDED is a verdict, not a remainder)")
  for name in CLASSES:
    print(f"  {name:10s} {byclass.get(name, 0):5d}")
  print(f"  {'TOTAL':10s} {sum(byclass.values()):5d}")
  print()
  print("REVERSE CHECK over the GAP rows only")
  print(f"  named_by (a gate's PROSE quotes the citation) {named:5d}  <- weak, not coverage")
  print(f"  read_by  (a gate's text opens the .bend file)  {read:5d}  <- exercises the file")
  print(f"  NEITHER                                    {len(gaps) - both:5d}  <- open")
  print("  read_by is NOT a greenness claim; whether that gate passes is a separate run.")
  print()
  print("TAG HISTOGRAM (the tree's own convention, not mine)")
  for tag, n in Counter(r["tag"] or "(bare)" for r in rows).most_common():
    print(f"  {tag:10s} {n:5d}")


def main():
  ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
  ap.add_argument("--root", default=os.path.join(REPO, "tinybendygrad"),
                  help="directory to walk (default tinybendygrad/)")
  ap.add_argument("--rows", action="store_true", help="print one row per site")
  args = ap.parse_args()

  if not os.path.isdir(args.root):
    print(f"ROOT-ABSENT {args.root}", file=sys.stderr)
    return 3
  rows, bends, fragments = census(args.root)
  covered(rows)
  if args.rows:
    for r in rows:
      print(f"{r['class']:10s} {r['path']}:{r['line']} tag={r['tag'] or '-':5s} "
            f"cite={r['cite'] or '-':18s} sym={r['symbol'] or '-':22s} "
            f"up={int(r['upstream_has'])} portdef={int(r['port_has_def'])} "
            f"read={r['read_by'] or '-'} :: {r['text'][:90]}")
  report(rows, bends, fragments)
  return 0


if __name__ == "__main__":
  sys.exit(main())