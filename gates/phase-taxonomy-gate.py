#!/usr/bin/env python3
"""phase-taxonomy-gate.py -- the tree's PRIORITY TAXONOMY: is it declared, and do the tree's
own markers agree with the tree's own layout?

    .venv/bin/python gates/phase-taxonomy-gate.py            # the census and the clauses
    .venv/bin/python gates/phase-taxonomy-gate.py --search    # the DECLARATION SEARCH alone
    .venv/bin/python gates/phase-taxonomy-gate.py --plant     # the states that move the verdict

WHAT THIS GATE IS FOR, IN ONE SENTENCE. The tree writes a phase tag on 730 of its 761
markers -- `TODO(p3)`, `WALL(p3)`, `DONE(p3)` -- and 31 sites that say something else, and
NOBODY says what the scale means at the point of use. The tree says so ABOUT ITSELF, in
three places, and this gate READS those places instead of guessing:

  `.agents/TODO.md:10438`                              -- "`p3` is a DEFAULT, not a phase."
  `.agents/slop/WALLMAP.md:325`                        -- "`p3` is not a phase. It is a default."
  `.agents/slop/notes/bend2-constraints.md:24665` (W-6) -- the same, with the count.

THE CLAIM, IN FIVE CLAUSES, EACH DECIDED BY A COMMAND AND NONE OF THEM A COUNT.

  C1 DECLARED   the tree declares the phase -> directory assignment SOMEWHERE, and every
                declaration it finds AGREES with every other on the phases they share.
  C2 COVERED    every tag value in use is CLASSIFIED, and every PHASE-shaped tag names a
                phase the tree DECLARES.  A tag that does not name a phase is a
                DISPOSITION -- an instruction, a stopping point, or a subject label -- and
                is NOT judged as one.
  C3 DEFAULT    the tree's own DOCUMENTS name one phase-shaped tag as the default, and the
                tree's own LAYOUT agrees with them.
  C4 LOCATED    every tag that is not the default is a PHASE CLAIM, and every claim names
                the phase that OWNS THE WORK and is located: it sits in that phase's own
                directory, or in a SHARED file -- one the table assigns to no phase, which
                serves every phase. A tag naming a phase the table gives NO directory owns
                no work to own, so it is SPELLED like a phase claim and is not one; the
                marker says so at the point of use, and a marker that does not is RED.
  C5 PARTIES    a `P<n>/<X>` compound names two PARTIES; only an OWNERSHIP claim whose two
                parties disagree with the table is a conflict.

COUNT is the population a clause measured on PASS and the number of things that broke it on
FAIL, so a reader can tell a clause that measured a lot from one that measured one thing.

WHAT C4 MEASURED BEFORE, AND WHY IT WAS WRONG (2026-10-23). C4 was "every claim sits in a
directory the table assigns to the phase it names", and it was red on 3 of 3 claims it
judged: `helpers.bend:438` (`TODO(p6)`), `helpers.bend:2573` (`TODO(p4)`) and
`runtime/ops_metal.bend:277` (`TODO(p1)`). **All three were FALSE POSITIVES, and the tree
says why, in three places and two files.** `helpers.bend` is a SHARED file -- the table
assigns it to no phase, and it serves every phase -- and its two claims name the phase that
OWNS THE WORK (`P6` = `runtime/`, whose ContextVar work the note describes at
`helpers.bend:52`; `P4` = `engine/`, whose clock the note asks for). And `p1` names a
phase the table gives NO directory, so it cannot be naming ownership of work at all: the
tree's own ledger calls it "a severity" (`.agents/TODO.md:11110`,
`.agents/slop/WALLMAP.md:328`). **⇒ A CLAUSE THAT IS RED ON EVERY CLAIM IT JUDGES IS NOT
A CLAUSE, IT IS A CHARGE, AND THE TREE'S OWN DOCUMENTS SAY WHAT IT WAS CHARGING.** The
clause now measures the question the tree's documents answer, and it can still go red in
every class: a claim in ANOTHER phase's directory, a claim naming a phase that owns no
work with no declaration, and a declaration that contradicts the table.

WHAT CHANGED, AND WHY (2026-10-21). The old C3 was "every tagged site sits in the directory
its own tag names". That is the gloss `tinybendygrad/engine/jit.bend`'s SECTION 10 used to
carry -- *"A `# TODO(p3)` in the tree means 'a phase owns this'"* -- DELETED on 2026-10-06
(`564733bed`), and the gate that measures it was written fourteen days LATER (`f978bca3b`,
"keep the phase map, so C3 can go red"). MEASURED 2026-10-21, that clause was red on 441 of
633 sites, and 439 of the 441 were `p3` markers: `p3` is the DEFAULT, so a `p3` marker in
`runtime/` contradicts nothing. **The old clause was the deleted gloss, re-measured.** C4 is
the same claim with the default excluded, and it is red on 3 sites -- each one a finding a
human can act on, not a number that means "the tree disagrees with itself 441 times".

THE OLD C5, AND WHY IT WAS WRONG. It compared the right-hand word of a compound against the
phase table's cell STEMS BY NAME (`stem_of("viz/") == "viz"`, so `P3/VIZ` "contradicted"
`viz/` at P8) and could not tell a FEATURE from a DIRECTORY. MEASURED 2026-10-21: all six
`P3/VIZ` sites are trailing labels on a wall about upstream's `pyrender` round-trip, whose
consumers are all in `tinygrad/uop/`, and the ONE compound in the tree that is an ownership
statement -- `schedule/memory.bend:1686`, *"P6/runtime owns the allocator"* -- AGREES with
the table. The markers are obedient; the READING was wrong. C5 now reads a compound as two
PARTIES and only contradicts the table when the compound ASSERTS OWNERSHIP and the two
parties disagree.

THE POPULATION IS WIDER THAN IT WAS. The old grammar matched `# TODO(...)` only, and the
tree also writes `# WALL(p3)` (105) and `# DONE(p3)` (20) and three `# WALL(nn_pool_*)` --
128 sibling sites the old population EXCLUDED, so the old gate measured a subset and said so
nowhere. The marker VERBS are DISCOVERED, not listed: a verb is a marker verb iff at least
one of its sites carries the UPSTREAM CITATION the tree's own brief gives as the marker
grammar (`# TODO(p3) <file>.py:<line>  <name>`, `.agents/slop/brief-port.md:177`). Quoted
upstream Python -- `# len(shape)`, `# ADD(u32)` -- never cites an upstream line, so the
citation separates the two without a hand list of verbs. MEASURED 2026-10-21 that yields
exactly `TODO`, `WALL` and `DONE`, 761 sites, and leaves 389 sites of quoted code out.

WHAT THE GATE DOES NOT CLAIM. It does not claim the phases are the right phases, and it does
not claim the markers are the wrong ones -- it measures whether the tree's own documents,
the tree's own markers and the tree's own layout agree. It transcribes NO expected value:
the phase -> directory assignment is LOADED BY PATH from the tree's own table and PARSED,
the default is READ from the tree's own documents by shape, and the marker population is
DISCOVERED by `os.walk` + `endswith` (never `glob`, which returns `[]` on a tree where `.bend`
is on disk). Every number it prints is a count of something it just walked.

EXIT STATUS, `gates/gatekit.py`'s five: 0 PASS · 1 FAIL · 3 REFUSED (a precondition was
absent: no phase table, or no document saying which tag is the default) · 5 DEAD (no marker
at all, so nothing was compared). A CLAUSE that could not run prints SKIP, and the gate as a
whole exits 3: a clause that measured nothing is a refusal, not a pass.
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
# ANY `# VERB(tag)` at the start of a comment line -- the WIDE shape, which also matches quoted
# upstream Python. The CITATION below is what separates a marker from a quotation.
MARK = re.compile(r"^\s*#\s*([A-Za-z_][A-Za-z0-9_]*)\(\s*([^)]*?)\s*\)")
# THE MARKER GRAMMAR THE TREE'S OWN BRIEF GIVES: `# TODO(p3) <file>.py:<line>  <name>`
# (`.agents/slop/brief-port.md:177`). A verb that appears in THAT form at least once is a
# MARKER VERB; a verb that only ever appears in quoted upstream code is not.
CITED = re.compile(r"^\s*#\s*[A-Za-z_][A-Za-z0-9_]*\([^)]*\)\s+[A-Za-z0-9_./]+\.(?:py|bend)\s*:")
# A PHASE TOKEN IN A HEADING: `## Phase P0 -- toolchain`, `## Phases P3-P8 -- the port`.
PHASE_HEAD = re.compile(r"^#{1,6}\s+Phases?\s+P(\d)\b", re.I)
# A TABLE ROW WHOSE FIRST CELL IS A PHASE.
PHASE_ROW = re.compile(r"^\|\s*P(\d)\s*\|(.*)$")
# A BACKTICKED TOKEN -- how the table names its directories.
CODE = re.compile(r"`([^`]+)`")
# AN UPSTREAM CITATION, for the DERIVED DEMAND table.
CITE = re.compile(r"\b([a-z_][a-z0-9_]*)\.py:\d+")
# A PHASE/NAME compound in prose (`P3/VIZ`). The right slot is a PARTY, not a subordinate.
ANNOT = re.compile(r"\bP(\d+)/([A-Za-z][A-Za-z0-9_]*)")
# AN OWNERSHIP VERB. The compound is the SUBJECT of one of these iff it ASSERTS OWNERSHIP;
# anything else is a trailing label. This is a closed-class English vocabulary, not a list of
# this tree's names, and it is the ONLY lexical list in this file.
OWNERS = re.compile(r"^\s*(?:is\s+|are\s+)?(owns?|owned|belongs\s+to|is\s+responsible\s+for)\b",
                    re.I)
# A CANONICAL phase tag: `p` and digits, and nothing else.
CANON = re.compile(r"^p(\d+)$")
# A tag that STARTS like a phase tag but is not one: `P3` (wrong case), `p3a`. Such a tag is
# MALFORMED, not a disposition -- it is spelled as a phase claim and is not one.
PHASEISH = re.compile(r"^[Pp]\d")
# A DOCUMENT THAT DECLARES THE DEFAULT: it names a phase-shaped tag and says of it that it
# IS a default, or is NOT a phase. MEASURED 2026-10-21, 8 lines in the tree match and all 8
# name `p3`; three of them are the tree's own documents and five quote them.
DEFAULT_DECL = re.compile(
  r"(?<![A-Za-z0-9\-])p(\d)(?![A-Za-z0-9\-])[^\n]{0,24}?\b(?:is|are)\b[^\n]{0,24}?"
  r"\b(?:default|not a phase)\b", re.I)
# A MARKER THAT SAYS WHAT ITS OWN TAG IS, AT THE POINT OF USE. This is the sentence the
# gate's own header asks for -- "NOBODY says what the scale means at the point of use" --
# and it is the tree's OWN word for the one marker that is spelled like a phase claim and
# is not one (`.agents/TODO.md:11110`: "`p1` ... = 'this file ports a superseded upstream'
# -- a severity").
#
# THE PHRASE IS NOT "not a phase", AND THE REASON IS MEASURED, NOT STYLISTIC:
# `DEFAULT_DECL` reads "pN ... is a default | not a phase" out of the tree's PROSE to find
# the DEFAULT, and it reads `.bend` files as well as `.md` ones. A marker that said "not a
# phase" would be a SECOND default declaration and would take C3 red. "NOT A PHASE CLAIM"
# carries the same meaning and is not in `DEFAULT_DECL`'s vocabulary.
NOT_A_CLAIM = re.compile(r"\bNOT A (?:WORK|PHASE) CLAIM\b", re.I)

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


def scan(port):
  """ONE walk of the port. `(claims, mentions, annots, sites, verbs, compounds)`.

  claims/mentions/annots are the TODO grammar the oracle reads. `sites` is the WIDENED
  population -- every `# VERB(tag)` whose verb is a MARKER VERB -- and `verbs` is the
  discovered verb vocabulary. A verb is a marker verb iff one of its sites CITES an upstream
  line, which is the marker grammar the tree's own brief gives.
  """
  claims, mentions, annots, sites, compounds = [], [], [], [], []
  byverb = defaultdict(list)
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
        compounds.append({"rel": rel, "line": number, "phase": int(m.group(1)),
                          "name": m.group(2), "tail": line[m.end():], "text": line.strip()})
      mark = MARK.match(line)
      if mark:
        byverb[mark.group(1)].append((rel, number, mark.group(2), line))
  verbs = {v for v, found in byverb.items() if any(CITED.match(l) for _r, _n, _t, l in found)}
  for verb in sorted(verbs):
    for rel, number, tag, line in byverb[verb]:
      sites.append((rel, number, verb, tag, line.strip()))
  sites.sort()
  return claims, mentions, annots, sites, verbs, compounds


def census(root):
  """Everything, as data. `root` is the repo root: it holds `tinybendygrad/` and the tree's
  own documents."""
  port = root / PORT_NAME
  assign, universe, evidence = declarations(root, port)
  claims, mentions, annots, sites, verbs, compounds = scan(port)
  return {"root": root, "port": port, "assign": assign, "sources": assign, "universe": universe,
          "evidence": evidence, "claims": claims, "mentions": mentions, "annots": annots,
          "sites": sites, "verbs": verbs, "compounds": compounds}


def tag_class(tag):
  """PHASE -- `p` and digits. MALFORMED -- spelled like a phase and is not one (`P3`, `p3a`).
  DISPOSITION -- does not name a phase: an instruction (`delete`), a stopping point (`port`),
  or a subject label (`nn_pool_4d`). The gate does NOT need to tell those three apart, and
  does not pretend to: the tree explains them at `mixin/rand.bend:253` (delete),
  `extra/datasets/__init__.bend:14` (port) and `nn/pool.bend:420` (nn_pool_*), and a tag that
  names no phase is not a phase claim under any of those readings."""
  if CANON.match(tag):
    return "PHASE"
  if PHASEISH.match(tag):
    return "MALFORMED"
  return "DISPOSITION"


def spread_of(c):
  """For every phase-shaped tag in use: the set of phase directories its sites sit in. This
  is the LAYOUT witness -- a tag spread over many phase directories cannot be naming any one
  of them, so it is the DEFAULT the tree's brief shows filled in."""
  out = {}
  for rel, _number, _verb, tag, _text in c["sites"]:
    if tag_class(tag) != "PHASE":
      continue
    phase = phase_of(rel, c["assign"])
    out.setdefault(tag, set())
    if phase is not None:
      out[tag].add(phase)
  return out


def default_declaration(root):
  """The tree's own documents saying which tag is the DEFAULT. `{tag: [path:line, ...]}`,
  read by shape: a line that names a phase-shaped tag and says of it that it IS a default or
  is NOT a phase. This is a DECLARATION, loaded from the tree the way the phase table is --
  not a list, and not a number this file transcribed."""
  found = defaultdict(list)
  for path in walk(root, PROSE_EXT):
    for number, line in enumerate(read(path).splitlines(), 1):
      for m in DEFAULT_DECL.finditer(line):
        found[f"p{m.group(1)}"].append(f"{path.relative_to(root)}:{number}")
  return dict(found)


def tag_census(c, classes, default):
  """One row per tag value in use: how many sites, in how many files, in how many phases, and
  what CLASS the tag is. Every field is a count or a set the walk just produced."""
  bytag = defaultdict(list)
  for rel, number, verb, tag, text in c["sites"]:
    bytag[tag].append((rel, number, verb, text))
  rows = []
  for tag, sites in sorted(bytag.items(), key=lambda kv: (-len(kv[1]), kv[0])):
    files = {s[0] for s in sites}
    phases = Counter(phase_of(s[0], c["assign"]) for s in sites)
    cited = Counter()
    for _rel, _number, _verb, text in sites:
      cited.update(CITE.findall(text))
    phase = int(CANON.match(tag).group(1)) if CANON.match(tag) else None
    kind = classes[tag]
    if kind == "PHASE" and tag == default:
      kind = "DEFAULT"
    rows.append({"tag": tag, "kind": kind, "sites": len(sites), "files": len(files),
                 "phase": phase, "phases": dict(phases), "cited": len(cited),
                 "verbs": sorted({s[2] for s in sites}),
                 "inside": phases.get(phase, 0) if phase is not None else 0,
                 "example": sites[0][3][:90]})
  return rows


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


def compound_census(c):
  """EVERY `P<n>/<X>` compound, read as TWO PARTIES.

  The right slot is a party, and there are three kinds: a PHASE (`P3/P6` -- "P3 owns P6" is
  not a sentence, so the compound cannot mean ownership), a DIRECTORY (`P6/runtime`), or a
  FEATURE (`P3/VIZ` -- the visualization feature, whose upstream consumers are all in
  `tinygrad/uop/`, NOT under `tinygrad/viz/`). A compound CONTRADICTS the phase table only
  when it ASSERTS OWNERSHIP -- the compound is the subject of an ownership verb -- and the two
  parties disagree about the table. A name that COLLIDES with a table cell's stem is a
  collision, not a contradiction, and it is REPORTED as one."""
  index = {}
  for phase, cells in c["assign"].items():
    for cell in cells:
      index.setdefault(stem_of(cell), (phase, cell))
  universe = c["universe"]
  rows = []
  for comp in c["compounds"]:
    name = comp["name"]
    if re.fullmatch(r"P\d+", name):
      kind, resolved = "PHASE", f"P{name[1:]}" + ("" if int(name[1:]) in universe else " (undeclared)")
    elif name.casefold() in index:
      cellphase, cell = index[name.casefold()]
      kind, resolved = "CELL", f"{cell} -> P{cellphase}"
    else:
      kind, resolved = "FEATURE", "no table cell of that name"
    owner = OWNERS.match(comp["tail"])
    position = f"OWNS:{owner.group(1)}" if owner else "LABEL"
    conflict = ""
    if owner and kind == "CELL":
      cellphase, cell = index[name.casefold()]
      if cellphase != comp["phase"]:
        conflict = (f"the claim says P{comp['phase']} owns {cell}, and the table puts {cell} "
                    f"at P{cellphase}")
    rows.append({**comp, "kind": kind, "resolved": resolved, "position": position,
                 "conflict": conflict})
  return rows


def verdicts(c):
  """THE FIVE CLAUSES. Each is a count and a verdict, never a bare boolean."""
  assign, universe = c["assign"], c["universe"]
  sites = c["sites"]
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
  # C2: every tag value in use is classified, and every PHASE-shaped tag names a DECLARED
  # phase. A tag that names no phase is a DISPOSITION and is not judged as one.
  tags = sorted({t for _r, _n, _v, t, _x in sites})
  classes = {t: tag_class(t) for t in tags}
  uncovered = [t for t in tags
               if classes[t] == "PHASE" and int(CANON.match(t).group(1)) not in universe]
  malformed = [t for t in tags if classes[t] == "MALFORMED"]
  broken = uncovered + malformed
  if not assign:
    c2 = ("SKIP", 0, "no phase table, so there is nothing to judge the tags against")
  elif broken:
    why = []
    if uncovered:
      why.append(f"tags that name no declared phase: {uncovered}")
    if malformed:
      why.append(f"tags spelled like a phase but not one: {malformed}")
    c2 = ("FAIL", len(broken), "; ".join(why))
  else:
    c2 = ("PASS", len(tags), "")
  # C3: the tree's own DOCUMENTS name the default, and the tree's own LAYOUT agrees.
  declared = default_declaration(c["root"])
  named = sorted(declared)
  spread = spread_of(c)
  default = None
  if not named:
    c3 = ("REFUSED", 0, "no document in the tree says which phase-shaped tag is the default")
  elif len(named) > 1:
    c3 = ("FAIL", len(named),
          f"the tree's documents name more than one default: {named} "
          f"({ {t: declared[t][:3] for t in named} })")
  else:
    default = named[0]
    mine = len(spread.get(default, ()))
    rivals = {t: len(s) for t, s in spread.items() if t != default}
    worst = max(rivals, key=rivals.get) if rivals else None
    if rivals and rivals[worst] > mine:
      c3 = ("FAIL", 1, f"the documents call {default} the default, but {worst} sits in "
                      f"{rivals[worst]} phase directories and {default} in {mine}")
    else:
      c3 = ("PASS", len(declared[default]), "")
  # C4: every tag that is not the default is a PHASE CLAIM, and every claim is LOCATED.
  #
  # WHAT "LOCATED" MEANS, AND WHY IT IS NOT "SITS IN THE PHASE'S DIRECTORY". A claim
  # names the phase that OWNS THE WORK -- that is the tree's own reading of the two
  # singletons (`helpers.bend:438` `TODO(p6)` is P6's `runtime/` ContextVar work;
  # `helpers.bend:2573` `TODO(p4)` is P4's `engine/` clock) -- and a phase owns work
  # only in a directory the table assigns to it. So a claim is located when the site is
  # in the phase's own directory OR the site is in a SHARED file: a file the table
  # assigns to NO phase, which serves every phase, and is therefore in nobody's phase
  # and in no WRONG phase. The table is what makes a file shared, so a ledger that
  # stopped calling `helpers.bend` shared would take this clause red on the spot.
  #
  # THE SECOND CLASS: a tag that names a phase the table gives NO directory cannot be
  # naming ownership of work -- that phase owns none to own -- so it is SPELLED like a
  # phase claim and is not one. The tree says so at the point of use (the marker
  # declares itself, `NOT_A_CLAIM`), and a marker that does NOT declare it is RED: an
  # unexplained phase-shaped tag is a finding, not a free pass. And the declaration
  # cannot be used as an escape hatch: a marker that declares itself while naming a
  # phase that DOES own work contradicts the table, and that is RED too.
  offenders, held, located = [], [], 0
  if not assign:
    c4 = ("SKIP", 0, "no phase table, so no claim can be located")
  elif c3[0] == "REFUSED":
    c4 = ("SKIP", 0, "C3 could not identify the default, so no claim can be judged")
  else:
    for rel, number, _verb, tag, text in sites:
      if classes[tag] != "PHASE" or tag == default:
        continue
      phase = int(CANON.match(tag).group(1))
      if phase not in universe:
        continue  # a phase the tree does not declare is C2's business, not a claim to place
      dirs = sorted(assign.get(phase, ()))
      declares = bool(NOT_A_CLAIM.search(text))
      here = phase_of(rel, assign)
      if not dirs:
        # THE PHASE OWNS NO WORK. A tag naming it cannot be naming work ownership.
        if declares:
          held.append({"rel": rel, "line": number, "tag": tag, "phase": phase,
                       "class": "DISPOSITION", "reason": "OWNS-NO-WORK-DECLARED",
                       "dirs": dirs, "site_in": here})
        else:
          offenders.append({"rel": rel, "line": number, "tag": tag, "phase": phase,
                            "reason": "OWNS-NO-WORK", "dirs": dirs, "site_in": here})
        continue
      if declares:
        # The marker says it is not a phase claim, and the tag names a phase that OWNS
        # work. One of the two is wrong, and the table is the one that can be checked.
        offenders.append({"rel": rel, "line": number, "tag": tag, "phase": phase,
                          "reason": "DECLARES-NOT-A-CLAIM", "dirs": dirs, "site_in": here})
        continue
      if here == phase:
        located += 1
        continue
      if here is None:
        held.append({"rel": rel, "line": number, "tag": tag, "phase": phase,
                     "class": "SHARED", "reason": "SHARED-SERVES-EVERY-PHASE",
                     "dirs": dirs, "site_in": here})
        continue
      offenders.append({"rel": rel, "line": number, "tag": tag, "phase": phase,
                        "reason": "OTHER-PHASE", "dirs": dirs, "site_in": here})
    considered = located + len(held) + len(offenders)
    c4 = ("PASS", considered, "") if not offenders else (
      "FAIL", len(offenders), f"{len(offenders)} phase claims are not located")
  # C5: a compound names two parties; only an OWNERSHIP claim whose parties disagree is a
  # conflict.
  compounds = compound_census(c)
  conflicts = [r for r in compounds if r["conflict"]]
  c5 = ("PASS", len(compounds), "") if not conflicts else (
    "FAIL", len(conflicts), f"{len(conflicts)} ownership claims disagree with the table")
  parts = [("C1 DECLARED", c1), ("C2 COVERED", c2), ("C3 DEFAULT", c3), ("C4 LOCATED", c4),
           ("C5 PARTIES", c5)]
  return parts, {"classes": classes, "default": default, "declared": declared,
                 "spread": spread, "offenders": offenders, "held": held,
                 "compounds": compounds, "conflicts": conflicts, "tags": tags}


def report(c, detail):
  """Print the census. Rows are `name=value`, the grammar `gates/lane-census.py` reads."""
  assign, universe = c["assign"], c["universe"]
  print("phase-taxonomy-gate: THE DECLARATION SEARCH (shapes: TABLE, HEADING)")
  print(f"  declaration_rows={sum(1 for e in c['evidence'] if e[0] == 'TABLE')}")
  sources = {src.rsplit(":", 1)[0] for cells in assign.values() for srcs in cells.values()
             for src in srcs}
  print(f"  declaration_sources={len(sources)}")
  print(f"  rows_rejected_not_a_phase_table="
        f"{sum(1 for e in c['evidence'] if e[0] == 'TABLE-NOT-A-PHASE-TABLE')}")
  print(f"  phase_headings={sum(1 for e in c['evidence'] if e[0] == 'HEADING')}")
  print()
  print("  THE DECLARED ASSIGNMENT (phase -> directories), AND WHERE EACH CELL WAS DECLARED:")
  for phase in sorted(assign):
    for cell in sorted(assign[phase]):
      print(f"    P{phase} {cell:14s} declared at {', '.join(sorted(c['sources'][phase][cell]))}")
  print(f"  phases_declared={','.join('P' + str(p) for p in sorted(universe))}")
  print()
  print("phase-taxonomy-gate: THE MARKER POPULATION")
  print(f"  bend_files={len(walk(c['port'], '.bend'))}")
  print(f"  marker_verbs={','.join(sorted(c['verbs']))}")
  print(f"  marker_sites={len(c['sites'])}")
  shared = sum(1 for path in walk(c['port'], '.bend')
               if phase_of(str(path.relative_to(c['port'])), assign) is None)
  print(f"  shared_files={shared}  (the table assigns these to NO phase: they serve every "
        "phase, so a claim in one is in nobody's phase and in no WRONG phase)")
  print(f"  marker_sites_by_verb="
        f"{','.join(f'{v}:{n}' for v, n in sorted(Counter(s[2] for s in c['sites']).items()))}")
  print(f"  todo_claims_only={len(c['claims'])}")
  print(f"  tag_mentions={len(c['mentions'])}")
  print(f"  tag_values_in_use={len(detail['tags'])}")
  only_mentions = sorted({t for _r, _n, t, _x in c["mentions"]} - set(detail["tags"]))
  print(f"  tag_values_in_mentions_only={','.join(only_mentions) or 'none'} "
        f"(a tag no MARKER carries: the tree names it, no site uses it)")
  print()
  print("phase-taxonomy-gate: THE DEFAULT, AND ITS TWO WITNESSES")
  print(f"  default_tag={detail['default'] or 'NONE'}")
  print(f"  default_declared_at={','.join(detail['declared'].get(detail['default'], ()))}")
  print(f"  default_layout={detail['default']} sits in "
        f"{len(detail['spread'].get(detail['default'], ()))} phase directories; the other "
        "phase-shaped tags sit in "
        + (", ".join(f"{t} in {len(s)}" for t, s in sorted(detail["spread"].items())
                     if t != detail["default"]) or "none"))
  print()
  print("phase-taxonomy-gate: THE TAG CENSUS, ONE ROW PER TAG VALUE IN USE")
  for row in tag_census(c, detail["classes"], detail["default"]):
    print(f"  tag={row['tag']:12s} class={row['kind']:11s} sites={row['sites']:4d} "
          f"files={row['files']:3d} verbs={','.join(row['verbs']):14s} "
          f"cited_upstream={row['cited']:3d}")
    print(f"      phases_of_sites={row['phases']}")
    print(f"      e.g. {row['example']}")
  print()


def human_sentence(parts, detail):
  """ONE question, and only when the gate's own PREMISE needs a human: the tree's documents
  do not agree on which tag is the default, or do not say at all. A claim that is not LOCATED
  is not a question -- it is a repair, and the gate prints it."""
  byname = {name: (verdict, count, why) for name, (verdict, count, why) in parts}
  verdict, _count, why = byname["C3 DEFAULT"]
  if verdict == "PASS":
    return None
  if verdict == "REFUSED":
    return ("the tree's documents do not say which phase-shaped tag is the DEFAULT, so no "
            "marker can be judged a phase claim: which tag is it?")
  return f"the tree's documents disagree about the DEFAULT: {why}"


def run(root, c=None):
  """The five clauses and the exit code. `root` is the repo root the census reads."""
  c = c if c is not None else census(root)
  if not c["sites"]:
    print("phase-taxonomy-gate: DEAD: no marker was found under "
          f"`{c['port']}`, so nothing was compared", file=sys.stderr)
    return DEAD
  parts, detail = verdicts(c)
  print("phase-taxonomy-gate: THE FIVE CLAUSES")
  for name, (verdict, count, why) in parts:
    print(f"  {name:14s} {verdict:8s} count={count}  {why}")
  for row in detail["offenders"]:
    site = row.get("site_in")
    print(f"  claim_not_located tag={row['tag']} site={row['rel']}:{row['line']} "
          f"says=P{row['phase']} reason={row['reason']} "
          f"site_in={('P' + str(site)) if site is not None else 'no-phase'} "
          f"P{row['phase']}_has={','.join(row['dirs']) or 'NO-DIRECTORY'}")
  for row in detail["held"]:
    site = row.get("site_in")
    print(f"  claim_held tag={row['tag']} site={row['rel']}:{row['line']} "
          f"says=P{row['phase']} class={row['class']} reason={row['reason']} "
          f"site_in={('P' + str(site)) if site is not None else 'no-phase'} "
          f"P{row['phase']}_has={','.join(row['dirs']) or 'NO-DIRECTORY'}")
  groups = defaultdict(list)
  for row in detail["compounds"]:
    groups[(row["position"], row["kind"], row["name"], row["resolved"])].append(row)
  for (position, kind, name, resolved), rows in sorted(groups.items()):
    first = rows[0]
    if position.startswith("OWNS"):
      print(f"  compound_ownership left=P{first['phase']} right={name} kind={kind} "
            f"resolves={resolved} position={position} sites={len(rows)} "
            + (f"CONFLICT: {first['conflict']}" if first["conflict"] else "AGREE"))
    elif kind == "CELL":
      print(f"  compound_label name={name} collides_with={resolved} position=LABEL "
            f"sites={len(rows)} e.g. {first['rel']}:{first['line']} "
            f"(a name collision, not a contradiction)")
  sentence = human_sentence(parts, detail)
  if sentence:
    print(f"  human={sentence}")
  # A FAIL beats a REFUSED beats a PASS: a clause that broke is the verdict, and a clause
  # that could not run means the gate measured nothing on that clause.
  codes = [v[0] for _n, v in parts]
  if not c["assign"]:
    code = REFUSED      # the precondition is absent, so the gate measured nothing
  elif "FAIL" in codes:
    code = FAIL
  elif "REFUSED" in codes or "SKIP" in codes:
    code = REFUSED
  else:
    code = PASS
  relation = {PASS: "agree", REFUSED: "were not compared (a precondition was absent)"}.get(
    code, "DISAGREE")
  print(f"phase-taxonomy-gate: {verdict_of(code)} -- the tree's documents, its markers and "
        f"its layout {relation}")
  return code


def plant():
  """THE STATES THAT MOVE THE VERDICT, one tree per state. A clause that cannot fail is a
  clause that must not exist, so every clause gets a state that makes it red."""
  import contextlib
  import io
  import tempfile
  ok = True
  table = ("| phase | directory |\n| --- | --- |\n"
           "| P3 | `uop/` |\n| P6 | `runtime/` |\n| P8 | `viz/` |\n")
  default_line = "\n- `p3` is a DEFAULT, not a phase.\n"

  def tree(base, name, table_text, files, prose=""):
    root = base / name
    port = root / "tinybendygrad"
    for directory in ("uop", "runtime", "viz"):
      (port / directory).mkdir(parents=True, exist_ok=True)
    (root / ".agents").mkdir(parents=True, exist_ok=True)
    (root / ".agents" / "TODO.md").write_text(table_text + prose)
    for rel, text in files:
      path = port / rel
      path.parent.mkdir(parents=True, exist_ok=True)
      path.write_text(text)
    return root

  obey = [("uop/x.bend", "# TODO(p3) ops.py:1  demo\n"),
          ("runtime/y.bend", "# TODO(p6) ops.py:2  demo\n")]
  disobey = [("uop/x.bend", "# TODO(p3) ops.py:1  demo\n"),
             ("uop/y.bend", "# TODO(p6) ops.py:2  demo\n")]
  # THE CLASSES C4 NOW MEASURES, each one a state that makes it red or holds it green.
  # `| P1 | "the contract" |` is a phase the tree DECLARES and gives NO DIRECTORY: the cell
  # names no file in the port, so the row is a declared phase with no work to own.
  p1_table = table + "| P1 | \"the contract\" |\n"
  shared = [("helpers.bend", "# TODO(p6) ops.py:2  the phase that owns this work\n")]
  shared_no_work = [("helpers.bend", "# TODO(p1) ops.py:2  a severity, not a claim\n")]
  shared_declared = [("helpers.bend",
                       "# TODO(p1) ops.py:2  NOT A PHASE CLAIM -- a severity: the whole file\n")]
  contradicted = [("runtime/y.bend",
                   "# TODO(p6) ops.py:2  NOT A PHASE CLAIM -- a severity: the whole file\n")]
  states = [
    ("plant-obey", (table, obey, default_line), PASS),
    ("plant-disobey", (table, disobey, default_line), FAIL),
    ("plant-undeclared", ("", obey, default_line), REFUSED),
    ("plant-dead", (table, [("uop/x.bend", "# len(shape) is a python call\n")], default_line),
     DEAD),
    ("plant-offscale", (table, [("uop/x.bend", "# TODO(p3) ops.py:1  demo\n"
                                          "# TODO(p9) ops.py:2  demo\n")], default_line), FAIL),
    ("plant-malformed", (table, [("uop/x.bend", "# TODO(P3) ops.py:1  demo\n")], default_line),
     FAIL),
    ("plant-disagree", (table, [("uop/x.bend", "# TODO(p3) ops.py:1  demo\n")],
                        default_line + "\n| P3 | `runtime/` |\n"), FAIL),
    ("plant-ownership", (table, [("uop/x.bend", "# TODO(p3) ops.py:1  demo\n"
                                               "#   P3/viz owns the renderer.\n")],
                          default_line), FAIL),
    ("plant-default-disagree",
     (table, [("uop/x.bend", "# TODO(p3) ops.py:1  demo\n"),
              ("runtime/y.bend", "# TODO(p3) ops.py:2  demo\n"),
              ("uop/z.bend", "# TODO(p6) ops.py:3  demo\n")],
      "- `p6` is a DEFAULT, not a phase.\n"), FAIL),
    ("plant-no-default", (table, obey, ""), REFUSED),
    ("plant-shared", (table, shared, default_line), PASS),
    ("plant-shared-no-work", (p1_table, shared_no_work, default_line), FAIL),
    ("plant-shared-declared", (p1_table, shared_declared, default_line), PASS),
    ("plant-declares-contradiction", (table, contradicted, default_line), FAIL),
  ]
  with tempfile.TemporaryDirectory() as td:
    base = Path(td)
    for name, (table_text, files, prose), want in states:
      root = tree(base, name, table_text, files, prose)
      buf = io.StringIO()
      with contextlib.redirect_stdout(buf):
        got = run(root)
      print(f"  {name:24s} rc={got}  expected rc={want}  "
            f"{'OK' if got == want else 'MISMATCH'}")
      if got != want:
        ok = False
        print(buf.getvalue())
  print(f"--plant: {'all %d states OK' % len(states) if ok else 'FAILED'}")
  return PASS if ok else FAIL


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
  c = census(ROOT)
  report(c, verdicts(c)[1])
  return run(ROOT, c)


if __name__ == "__main__":
  sys.exit(main())
