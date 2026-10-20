#!/usr/bin/env python3
"""phase-taxonomy-gate.py -- the tree's PRIORITY TAXONOMY: is it declared, and can it be
RE-DERIVED from the tree's own layout?

    .venv/bin/python gates/phase-taxonomy-gate.py            # the census
    .venv/bin/python gates/phase-taxonomy-gate.py --search   # the DECLARATION SEARCH alone
    .venv/bin/python gates/phase-taxonomy-gate.py --plant    # three states, no `.bend` run

WHAT THIS GATE IS FOR, IN ONE SENTENCE. The tree writes `TODO(p3)` on 827 sites today and
`TODO(p1)`, `TODO(p4)`, `TODO(p6)`, `TODO(pN)`, `TODO(delete)`, `TODO(port)` on one site each,
and NOBODY says what the scale means at the point of use. The tree says so about itself:
`.agents/TODO.md` -- *"An undefined priority scale is why 1,026 markers have no order"* and
*"The p-scale IS defined, as phases of the port plan, in `.agents/TODO.md` lines 917-928 and
nowhere else"*. The line numbers are stale and the ONE gloss of the MEANING -- *"A `# TODO(p3)`
in the tree means 'a phase owns this', not 'nobody knows'" -- lived in
`tinybendygrad/engine/jit.bend`'s SECTION 10 and was DELETED on 2026-10-06
(`git log --all -S 'a phase owns this' -- tinybendygrad/engine/jit.bend`). MEASURED 2026-10-20:
`git show HEAD:tinybendygrad/engine/jit.bend | grep 'phase owns this'` answers rc=1, and the
file's OWN header still cites "Section 9", "Section 10" and "Section 11" -- a file of 434 lines
whose last section header is SECTION 3. The gloss is gone and the citation to it is not.

THE CLAIM, IN THREE CLAUSES, EACH DECIDED BY A COMMAND AND NONE OF THEM A COUNT.

  C1 DECLARED   the tree declares the phase -> directory assignment SOMEWHERE, and every
                declaration it finds AGREES with every other on the phases they share.
  C2 COVERED    every tag value in use names a phase the tree DECLARES.
  C3 OBEDIENT   every tagged site sits in the directory its own tag names.

C3 IS THE ONE THAT GOES RED, AND IT IS THE ONE THE BRIEF ASKED FOR: a census that goes red when
the tree's LAYOUT and the MARKERS disagree. It is green-able, and green is reachable: retag the
markers to their own phase, or re-cut the phase table to the layout, and it passes. Today it is
RED, and that is a MEASUREMENT, not a defect this file invents.

WHAT THE GATE DOES NOT CLAIM. It does not claim the phases are the right phases, and it does not
claim the markers are the wrong ones -- it measures whether the two agree and reports which
number is bigger. It transcribes NO expected value: the phase -> directory assignment is LOADED
BY PATH from the tree's own table and PARSED, and the marker population is DISCOVERED by
`os.walk` + `endswith` (never `glob`, which returns `[]` on a tree where `.bend` is on disk).
Every number it prints is a count of something it just walked.

THE DECLARATION IS FOUND BY SHAPE, NOT BY PATH. A phase table is a markdown table with a row
whose first cell is `P<n>` and whose other cells name paths that RESOLVE under the port. That
rule is what separates the port's phase table from the OTHER tables in the tree that also number
themselves P1..P9 -- `.agents/slop/SCHEDULE-BODIES.md`'s Bend-rule priorities and
`.agents/slop/sched-stage2.md`'s gate-sweep priorities -- and it is why the rule is a rule and not
a list: both of those tables are IN the tree, both are P1..P9, and a hand list of "the phase
table" would have had to say which of them it meant.

EXIT STATUS, `gates/gatekit.py`'s five: 0 PASS · 1 FAIL · 3 REFUSED (no declaration found: the
precondition, a taxonomy, is absent) · 5 DEAD (no `.bend` file, so nothing was compared).
"""
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from gatekit import DEAD, FAIL, PASS, REFUSED, verdict_of  # noqa: E402

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
PORT_NAME = "tinybendygrad"

# THE MARKER GRAMMAR. A CLAIM is the tag at the START of a comment line; a MENTION is the same
# token anywhere else. THE DIFFERENCE IS NOT COSMETIC: MEASURED 2026-10-20, the tree's only
# `TODO(pN)` is at `tinybendygrad/mixin/rand.bend:42`, inside the PROSE sentence *"Each
# `TODO(pN)` below is the tracker."* -- there is NO `TODO(pN)` marker anywhere, and a census
# that counts the mention reports a tag that no marker carries.
CLAIM = re.compile(r"^\s*#\s*TODO\(\s*([^)]*?)\s*\)")
MENTION = re.compile(r"TODO\(\s*([^)]*?)\s*\)")
# A PHASE TOKEN IN A HEADING: `## Phase P0 -- toolchain`, `## Phases P3-P8 -- the port`.
PHASE_HEAD = re.compile(r"^#{1,6}\s+Phases?\s+P(\d)\b", re.I)
# A TABLE ROW WHOSE FIRST CELL IS A PHASE.
PHASE_ROW = re.compile(r"^\|\s*P(\d)\s*\|(.*)$")
# A BACKTICKED TOKEN -- how the table names its directories.
CODE = re.compile(r"`([^`]+)`")
# AN UPSTREAM CITATION, for the DERIVED DEMAND table.
CITE = re.compile(r"\b([a-z_][a-z0-9_]*)\.py:\d+")
# A PHASE/NAME annotation in prose (`P3/VIZ`). Matched against a phase-table cell; a hit on a
# different phase is a contradiction the table cannot settle, including on continuation lines
# that are not themselves `TODO` claims.
ANNOT = re.compile(r"\bP(\d+)/([A-Za-z][A-Za-z0-9_]*)")

# THE DECLARATION SEARCH COVERS PROSE AND PORT CODE. The gloss that WAS the definition lived in
# a `.bend` file, so a search that only read `.md` would have missed it.
PROSE_EXT = (".md", ".bend")
# DIRECTORIES THAT ARE NOT THE TREE'S OWN TEXT: a git object store, an upstream CLONE, a
# virtualenv, a build cache. `references/` is a clone of upstream (`.gitignore:2`).
SKIP_DIRS = {".git", ".jj", "references", ".venv", "__pycache__", "node_modules",
             ".ruff_cache", "tinygrad.egg-info", "runs"}


def walk(root, exts):
  """DISCOVERED, never listed: `os.walk` + `endswith`. `glob('*.bend')` returns `[]` when the
  `.bend` files are on disk, and this tree has them on disk."""
  found = []
  for dirpath, dirs, names in os.walk(root):
    dirs[:] = [d for d in dirs if d not in SKIP_DIRS]
    for name in names:
      if name.endswith(exts):
        found.append(Path(dirpath) / name)
  return sorted(found)


def read(path):
  try:
    return path.read_text(encoding="utf-8", errors="replace")
  except OSError:
    return ""


def resolves(cell, port):
  """Does a table cell name something that EXISTS in the port? A directory, or a top-level
  file the table names by its UPSTREAM name (`device.py` -> `device.bend`, `tensor` ->
  `tensor.bend`). A cell that names a DEF (`cks_dev.same`) resolves to nothing, which is how
  the other P1..P9 tables in this tree are excluded without naming them."""
  cell = cell.strip().rstrip("/")
  if not cell:
    return None
  if (port / cell).is_dir():
    return cell + "/"
  stem = cell[:-3] if cell.endswith(".py") else cell
  if "/" not in stem and (port / f"{stem}.bend").is_file():
    return f"{stem}.bend"
  return None


def phase_of(relpath, assign):
  """The phase the assignment gives a file. LONGEST match wins, so `runtime/support/` cannot
  be claimed by a phase that only names `runtime/`'s parent."""
  parts = relpath.split("/")
  best = (0, None)
  for phase, cells in assign.items():
    for cell in cells:
      cand = [x for x in cell.split("/") if x]
      if parts[:len(cand)] == cand and len(cand) > best[0]:
        best = (len(cand), phase)
  return best[1]


def declarations(root, port):
  """THE SEARCH. Returns `(assign, universe, evidence)`.

  assign    phase -> {cell -> set of `path:line` that declared it}. The sources stay: collapsing
            to `sorted(cells)` yields a list of names, and that list is what `report` and
            `verdicts` then index with a string.
  universe  the set of phase numbers the tree DECLARES at all (table rows and headings)
  evidence  one record per candidate shape found, so the search is REPORTED and not asserted

  A candidate is a markdown table row whose first cell is `P<n>` AND at least one of whose other
  cells resolves under the port. Rows whose cells resolve to NOTHING are reported and NOT used:
  that is how `.agents/slop/SCHEDULE-BODIES.md` (Bend-rule priorities) and
  `.agents/slop/sched-stage2.md` (gate-sweep priorities) are excluded -- they are P1..P9 tables
  that are not about phases.
  """
  assign, universe, evidence = defaultdict(dict), set(), []
  for path in walk(root, PROSE_EXT):
    lines = read(path).splitlines()
    for number, line in enumerate(lines, 1):
      head = PHASE_HEAD.match(line)
      if head:
        universe.add(int(head.group(1)))
        evidence.append(("HEADING", path, number, line.strip()))
        continue
      row = PHASE_ROW.match(line)
      if not row:
        continue
      phase = int(row.group(1))
      universe.add(phase)
      cells = CODE.findall(row.group(2))
      resolved = [r for r in (resolves(c, port) for c in cells) if r]
      if not resolved:
        evidence.append(("TABLE-NOT-A-PHASE-TABLE", path, number, line.strip()))
        continue
      for cell in resolved:
        assign[phase].setdefault(cell, set()).add(f"{path.relative_to(root)}:{number}")
      evidence.append(("TABLE", path, number, line.strip()))
  return {p: dict(cells) for p, cells in assign.items()}, universe, evidence


def markers(port):
  """THE MARKER POPULATION, DISCOVERED. `(claims, mentions, annots)`.
  claims and mentions are `(relpath, line, tag, text)`. annots are `(relpath, line, phase, name)`
  for every `P<n>/<name>`, including continuation lines that are not claims."""
  claims, mentions, annots = [], [], []
  for path in walk(port, ".bend"):
    rel = str(path.relative_to(port))
    for number, line in enumerate(read(path).splitlines(), 1):
      claim = CLAIM.match(line)
      if claim:
        claims.append((rel, number, claim.group(1), line.strip()))
      for m in MENTION.finditer(line):
        mentions.append((rel, number, m.group(1), line.strip()))
      for m in ANNOT.finditer(line):
        annots.append((rel, number, int(m.group(1)), m.group(2)))
  return claims, mentions, annots


def census(root):
  """Everything, as data. `root` is the repo root: it holds `tinybendygrad/` and the tree's
  own documents."""
  port = root / PORT_NAME
  assign, universe, evidence = declarations(root, port)
  claims, mentions, annots = markers(port)
  return {"port": port, "assign": assign, "sources": assign, "universe": universe,
          "evidence": evidence, "claims": claims, "mentions": mentions, "annots": annots}


def demand(c):
  """THE DERIVED DEMAND of every tag in use. DERIVED, NOT TRANSCRIBED: every field is a
  count or a set the walk just produced. The VERDICT is a RULE over those fields, and the
  rules are printed with it."""
  bytag = defaultdict(list)
  for rel, number, tag, text in c["claims"]:
    bytag[tag].append((rel, number, text))
  out = []
  for tag, sites in sorted(bytag.items(), key=lambda kv: (-len(kv[1]), kv[0])):
    files = {s[0] for s in sites}
    phases = Counter(phase_of(s[0], c["assign"]) for s in sites)
    cited = Counter()
    for _rel, _number, text in sites:
      cited.update(CITE.findall(text))
    number = tag[1:] if tag.startswith("p") and tag[1:].isdigit() else None
    phase = int(number) if number is not None else None
    assigned = c["assign"].get(phase, []) if phase is not None else []
    inside = sum(1 for s in sites if phase_of(s[0], c["assign"]) == phase) if assigned else 0
    if phase is not None and not assigned:
      verdict = "OFF-SCALE: names a phase the tree does not declare a directory for"
    elif assigned and inside == len(sites):
      verdict = "PHASE: every site sits in the directory its tag names"
    elif assigned:
      verdict = ("NOT-A-PHASE: the tag names a phase, but its sites sit in "
                 f"{len(phases)} different phases")
    else:
      verdict = "DISPOSITION: the tag is not a phase, so it can only be a per-site declaration"
    out.append({"tag": tag, "sites": len(sites), "files": len(files), "phase": phase,
                "phases": dict(phases), "cited": len(cited), "inside": inside,
                "assigned": assigned, "verdict": verdict,
                "example": sites[0][2][:90]})
  return out


def report(c):
  """Print the census. Rows are `name=value`, the grammar `gates/lane-census.py` reads."""
  assign, universe, claims, mentions = c["assign"], c["universe"], c["claims"], c["mentions"]
  print("phase-taxonomy-gate: THE DECLARATION SEARCH (shapes: TABLE, HEADING)")
  print(f"  declaration_candidates={sum(1 for e in c['evidence'] if e[0] == 'TABLE')}")
  print(f"  declaration_rows={sum(1 for e in c['evidence'] if e[0] == 'TABLE')}")
  print(f"  rows_rejected_not_a_phase_table="
        f"{sum(1 for e in c['evidence'] if e[0] == 'TABLE-NOT-A-PHASE-TABLE')}")
  print(f"  phase_headings={sum(1 for e in c['evidence'] if e[0] == 'HEADING')}")
  for shape, path, number, text in c["evidence"]:
    if shape == "TABLE":
      print(f"  TABLE       {path.relative_to(ROOT)}:{number}  {text[:100]}")
  for shape, path, number, text in c["evidence"]:
    if shape == "TABLE-NOT-A-PHASE-TABLE":
      print(f"  NOT-A-PHASE {path.relative_to(ROOT)}:{number}  {text[:90]}")
  for shape, path, number, text in c["evidence"]:
    if shape == "HEADING":
      print(f"  HEADING     {path.relative_to(ROOT)}:{number}  {text[:100]}")
  print()
  print("  THE DECLARED ASSIGNMENT (phase -> directories), AND WHERE EACH CELL WAS DECLARED:")
  for phase in sorted(assign):
    for cell in sorted(assign[phase]):
      print(f"    P{phase} {cell:14s} declared at {', '.join(sorted(c['sources'][phase][cell]))}")
  print(f"  phases_declared={','.join('P' + str(p) for p in sorted(universe))}")
  print()
  print("phase-taxonomy-gate: THE MARKER POPULATION")
  print(f"  bend_files={len(walk(c['port'], '.bend'))}")
  print(f"  tag_claims={len(claims)}")
  print(f"  tag_mentions={len(mentions)}")
  print(f"  tag_values_in_use={len({t for _r, _n, t, _x in claims})}")
  print()
  print("phase-taxonomy-gate: THE DERIVED DEMAND, ONE ROW PER TAG IN USE")
  for row in demand(c):
    print(f"  tag={row['tag']:8s} sites={row['sites']:4d} files={row['files']:3d} "
          f"cited_upstream={row['cited']:3d} inside_own_phase={row['inside']:4d}")
    print(f"      phases_of_sites={row['phases']}")
    print(f"      demand={row['verdict']}")
    print(f"      e.g. {row['example']}")
  print()


def stem_of(cell):
  """The name a phase-table cell is known by, so `viz/` and `P3/VIZ` can be compared."""
  stem = cell.rstrip("/").rsplit("/", 1)[-1]
  if stem.endswith(".py"):
    return stem[:-3].casefold()
  if stem.endswith(".bend"):
    return stem[:-5].casefold()
  return stem.casefold()


def disagreements(assign):
  """Two rows conflict when they name one phase and different directories.
  The same directories named in two files is agreement, not a second declaration of a different scale."""
  bad = []
  for phase, cells in assign.items():
    by_row = defaultdict(set)
    for cell, sources in cells.items():
      for src in sources:
        by_row[src].add(cell)
    rows = list(by_row.values())
    if any(row != rows[0] for row in rows[1:]):
      bad.append((phase, {src: sorted(got) for src, got in sorted(by_row.items())}))
  return bad


def annotation_conflicts(c):
  """`P<n>/<name>` prose that names a phase-table cell the table assigns to another phase."""
  index = {}
  for phase, cells in c["assign"].items():
    for cell in cells:
      index.setdefault(stem_of(cell), (phase, cell))
  groups = defaultdict(list)
  for rel, number, phase, name in c["annots"]:
    hit = index.get(name.casefold())
    if hit and hit[0] != phase:
      groups[(phase, name.casefold(), hit[0], hit[1])].append(f"{rel}:{number}")
  return groups


def human_sentence(groups, cross):
  """ONE question, and only when the scale cannot be re-derived. None when it can."""
  if groups:
    key, sites = max(groups.items(), key=lambda kv: (len(kv[1]), kv[0]))
    ann, name, table, cell = key
    where = f"{PORT_NAME}/{sites[0]}"
    return (f"{len(sites)} markers say {name.upper()} is P{ann} ({where}) and the phase table "
            f"puts `{cell}` at P{table}: which assignment is the scale?")
  if cross:
    return (f"{len(cross)} tagged sites sit outside the directory their tag names: "
            "is the scale the marker, or the directory?")
  return None


def verdicts(c):
  """C1, C2, C3 -- each a count and a verdict, never a bare boolean."""
  assign, universe, claims = c["assign"], c["universe"], c["claims"]
  # C1: a declaration exists, and every declaration agrees on the phases they share.
  # Agreement is equal directory sets, not "named in one file": two tables that name the
  # same cells are one scale.
  bad = disagreements(assign)
  if not assign:
    c1 = ("REFUSED", 0, "no table in the tree declares a phase -> directory assignment")
  elif bad:
    c1 = ("FAIL", len(bad), f"declarations disagree on: {bad}")
  else:
    c1 = ("PASS", len(assign), "")
  # C2: every tag value in use names a declared phase.
  tags = sorted({t for _r, _n, t, _x in claims})
  uncovered = [t for t in tags
               if not (t.startswith("p") and t[1:].isdigit() and int(t[1:]) in universe)]
  c2 = ("PASS", len(tags) - len(uncovered), "") if not uncovered else (
    "FAIL", len(uncovered), f"tags that name no declared phase: {uncovered}")
  # C3: every tagged site sits in the directory its tag names.
  cross = []
  for rel, number, tag, text in claims:
    if not (tag.startswith("p") and tag[1:].isdigit()):
      continue
    phase = int(tag[1:])
    if not assign.get(phase):
      continue
    if phase_of(rel, assign) != phase:
      cross.append((rel, number, tag))
  c3 = ("PASS", 0, "") if not cross else (
    "FAIL", len(cross), f"{len(cross)} of {len(claims)} tagged sites sit outside their tag's phase")
  return [("C1 DECLARED", c1), ("C2 COVERED", c2), ("C3 OBEDIENT", c3)], cross, uncovered


def plant():
  """THREE STATES, so the reader can see the instrument MOVE. A gate that cannot go red is a
  gate that cannot be wrong, and this one is red today, so the states that matter are the two
  that make it RED and the one that makes it GREEN."""
  import tempfile
  ok = True
  with tempfile.TemporaryDirectory() as td:
    base = Path(td)
    table = ("## Phases P3-P8 -- the port\n\n| phase | directory |\n| --- | --- |\n"
             "| P3 | `uop/` |\n| P6 | `runtime/` |\n")
    # Both phase directories must exist, or the disobey row's `uop/` cell does not resolve
    # and C3 has no directory to disobey.
    for name, where, want in (("plant-obey", "uop/x.bend", PASS),
                              ("plant-disobey", "runtime/x.bend", FAIL)):
      root = base / name
      port = root / "tinybendygrad"
      for directory in ("uop", "runtime"):
        (port / directory).mkdir(parents=True, exist_ok=True)
      (port / where).write_text("# TODO(p3) ops.py:1  demo\n")
      (root / ".agents").mkdir(parents=True, exist_ok=True)
      (root / ".agents" / "TODO.md").write_text(table)
      got = run(root)
      print(f"  {name:18s} rc={got}  expected rc={want}  {'OK' if got == want else 'MISMATCH'}")
      ok = ok and got == want
    root = base / "plant-undeclared"
    (root / "tinybendygrad" / "uop").mkdir(parents=True, exist_ok=True)
    (root / "tinybendygrad" / "uop" / "x.bend").write_text("# TODO(p3) ops.py:1  demo\n")
    got = run(root)
    print(f"  {'plant-undeclared':18s} rc={got}  expected rc={REFUSED}  "
          f"{'OK' if got == REFUSED else 'MISMATCH'}")
    ok = ok and got == REFUSED
  print(f"--plant: {'all 3 states OK' if ok else 'FAILED'}")
  return PASS if ok else FAIL


def run(root):
  """The three clauses and the exit code. `root` is the repo root the census reads."""
  c = census(root)
  if not c["claims"]:
    print("phase-taxonomy-gate: DEAD: no `TODO(...)` claim was found under "
          f"`{c['port']}`, so nothing was compared", file=sys.stderr)
    return DEAD
  parts, cross, uncovered = verdicts(c)
  print("phase-taxonomy-gate: THE THREE CLAUSES")
  for name, (verdict, count, why) in parts:
    print(f"  {name:14s} {verdict:8s} count={count}  {why}")
  if cross:
    print(f"  cross_phase_sites={len(cross)}   e.g. {cross[:3]}")
  if uncovered:
    print(f"  uncovered_tags={uncovered}")
  print("phase-taxonomy-gate: CLUSTERING (a phase tag's sites, against the directory it names)")
  for row in demand(c):
    if row["phase"] is None:
      continue
    outside = row["sites"] - row["inside"]
    print(f"  cluster tag={row['tag']} sites={row['sites']} inside={row['inside']} "
          f"outside={outside} phases={row['phases']}")
  groups = annotation_conflicts(c)
  for key, sites in sorted(groups.items(), key=lambda kv: (-len(kv[1]), kv[0])):
    ann, name, table, cell = key
    print(f"  annotation_conflict name={name.upper()} marker_phase=P{ann} "
          f"table_phase=P{table} cell={cell} sites={len(sites)}")
  sentence = human_sentence(groups, cross)
  if sentence:
    print(f"  human={sentence}")
  # No declaration is a missing precondition, not a failed comparison. C2 can also be red
  # in that state; the exit is still REFUSED.
  if not c["assign"]:
    code = REFUSED
  elif all(v[0] == "PASS" for _n, v in parts):
    code = PASS
  else:
    code = FAIL
  relation = {PASS: "agree", REFUSED: "were not compared (no declaration)"}.get(code, "DISAGREE")
  print(f"phase-taxonomy-gate: {verdict_of(code)} -- the tags and the tree's own layout {relation}")
  return code


def main():
  if not (ROOT / "pyproject.toml").is_file():
    print(f"phase-taxonomy-gate: REFUSED, NOT A VERDICT: `{ROOT}` is not at the repo root "
          f"(no `pyproject.toml`)", file=sys.stderr)
    return REFUSED
  argv = sys.argv[1:]
  if "--plant" in argv:
    return plant()
  if "--search" in argv:
    c = census(ROOT)
    for shape, path, number, text in c["evidence"]:
      print(f"{shape:26s} {path.relative_to(ROOT)}:{number}  {text[:120]}")
    return PASS
  report(census(ROOT))
  return run(ROOT)


if __name__ == "__main__":
  sys.exit(main())
