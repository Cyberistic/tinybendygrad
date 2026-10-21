#!/usr/bin/env python3
"""phase-taxonomy-matrix.py -- the CROSS-TABULATION behind `gates/phase-taxonomy-gate.py`'s
C3, and the `P<n>/<X>` NOTATION CENSUS behind its `annotation_conflict` row.

    .venv/bin/python oracles/phase-taxonomy-matrix.py            # everything, printed
    .venv/bin/python oracles/phase-taxonomy-matrix.py --rows     # also write the .rows

WHAT THIS IS FOR. `gates/phase-taxonomy-gate.py` prints two numbers that need a HUMAN:
`C3 OBEDIENT` (how many tagged sites sit outside their tag's phase) and
`annotation_conflict name=VIZ` (six markers say VIZ is P3, the table puts `viz/` at P8).
This file turns both into the SHAPE they have, because a count cannot be argued with and a
matrix can:

  1. THE MATRIX. Rows are the phase a MARKER NAMES; columns are the phase of the DIRECTORY
     the marker SITS IN. The diagonal is obedience, the off-diagonal is "contradiction".
     If the off-diagonal is one fat row and nothing else, the markers make no per-phase
     claims, and the matrix has no per-phase structure to contradict.

  2. THE OWN-PHASE TEST. If `TODO(pN)` named the phase that owns the site, then P4's own
     directories would carry `p4` markers, P5's would carry `p5`, and so on. The matrix
     answers that directly: the OFF-DIAGONAL is where the evidence is, and the DIAGONAL
     for P4..P8 is EMPTY.

  3. THE TEMPLATE TEST. `.agents/slop/brief-port.md:177` gives the marker GRAMMAR as a
     literal template: `# TODO(p3) <file>.py:<line>  <name>`. This file measures how many
     markers are that template verbatim, and how many of them name their OWN file's
     upstream counterpart -- a self-reference that carries no phase information at all.

  4. THE NOTATION CENSUS. Every `P<n>/<X>` in the tree, with what `<X>` resolves to: a
     PHASE (P6), a TABLE CELL (`runtime/`), or a FEATURE (`VIZ`). The gate's
     `annotation_conflicts` compares `<X>` against the table's cell STEMS by NAME, so it
     needs to know which kind of `<X>` it is looking at.

  5. THE IMPORT-ORDER CORROBORATION. The phase table is a porting ORDER. This file checks
     it against the port's own import DAG, because a plan and a structure are different
     things and only one of them is derivable from the tree.

NOTHING HERE IS TRANSCRIBED. The phase -> directory assignment is LOADED from the tree's own
table by `phase-taxonomy-gate.py`'s `declarations()`; the marker population is DISCOVERED by
`os.walk` + `endswith(".bend")` (never `glob`, which returns `[]` on a tree where `.bend` is on
disk). Every number below is a count of something this file just walked.
"""
import importlib.util
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

# THE GATE IS THE SOURCE OF THE DECLARATION. Load it BY PATH (its filename is not a module
# name) rather than copying its phase table, its marker grammar or its `phase_of`: a second
# copy of the list is a contract with no generator and rots without anyone noticing.
_spec = importlib.util.spec_from_file_location(
    "phase_taxonomy_gate", ROOT / "gates" / "phase-taxonomy-gate.py")
_gate = importlib.util.module_from_spec(_spec)
sys.modules["phase_taxonomy_gate"] = _gate
_spec.loader.exec_module(_gate)

CLAIM = _gate.CLAIM
# THE SIBLING MARKER FORMS. `phase-taxonomy-gate.py`'s CLAIM grammar is `# TODO(...)` and
# NOTHING ELSE, but the tree also writes `# WALL(p3)` and `# DONE(p3)`: same tag vocabulary,
# different verb. The population the gate measures is a SUBSET of what the tree writes.
FORM = re.compile(r"^\s*#\s*(TODO|WALL|DONE)\(\s*([^)]*?)\s*\)")
# THE TEMPLATE, as `.agents/slop/brief-port.md:177` gives it: `# TODO(p3) <file>.<ext>:<line>`.
TPL = re.compile(r"^\s*#\s*(?:TODO|WALL|DONE)\([^)]*\)\s+([A-Za-z0-9_./]+)\s*[:(]")
# AN IMPORT LINE in the port's own source. `import Base` is the built-in; every other
# import names a sibling `.bend` file by a path relative to the importing file.
IMP = re.compile(r"^import\s+(\S+)\.bend\s+as\s+\S+")


def walk(root, exts):
  """DISCOVERED, never listed: `os.walk` + `endswith`."""
  found = []
  for dirpath, dirs, names in os.walk(root):
    dirs[:] = [d for d in dirs if d not in _gate.SKIP_DIRS]
    for name in names:
      if name.endswith(exts):
        found.append(Path(dirpath) / name)
  return sorted(found)


def markers(port):
  """Every `# VERB(tag)` marker line, all three verbs. `(rel, line, verb, tag, text)`."""
  out = []
  for path in walk(port, ".bend"):
    rel = str(path.relative_to(port))
    for number, line in enumerate(_gate.read(path).splitlines(), 1):
      form = FORM.match(line)
      if form:
        out.append((rel, number, form.group(1), form.group(2), line.strip()))
  return out


def tag_phase(tag):
  """The phase a tag NAMES, or None if it names no phase at all."""
  return int(tag[1:]) if tag.startswith("p") and tag[1:].isdigit() else None


def matrix(c, sites):
  """Rows = the phase the marker NAMES. Columns = the phase of the directory it SITS IN.
  `None` in a column means the site is in NO directory the table assigns (a top-level file
  like `helpers.bend`, or `extra/`, which the table does not name).
  A tag that names a phase the table gives NO directory (P1 = "the contract") still gets a
  row: the gate skips it, and a matrix that skipped it would hide the contradiction."""
  assign = c["assign"]
  cells = defaultdict(Counter)
  for rel, tag in sites:
    phase = tag_phase(tag)
    if phase is None:
      continue
    cells[phase][_gate.phase_of(rel, assign)] += 1
  return cells, sorted(assign) + [None]


def print_matrix(title, cells, cols):
  print(title)
  print(f"  {'tag':<6s}" + "".join(f"{('P' + str(c)) if c is not None else '-':<7s}" for c in cols) + "total")
  for phase in sorted(cells):
    row = cells[phase]
    note = "" if phase in cells else ""
    print(f"  p{phase:<5d}" + "".join(f"{row[c]:<7d}" for c in cols) + str(sum(row.values())) + note)
  print()


def own_phase_test(c, cells):
  """THE DECISIVE TEST FOR 'THE TAG NAMES THE PHASE THAT OWNS THE SITE'.
  If that were the rule, each phase's own directories would carry its own tag. This prints
  the diagonal and the off-diagonal separately, so the difference is a NUMBER and not an
  impression -- and it prints the phases that carry NO tag at all, because the NEGATIVE
  result is the evidence."""
  print("OWN-PHASE TEST: for each phase P, how many markers tagged pP sit in P's OWN "
        "directories?")
  print("  phase  own-dir markers   tagged-with-P   off-diagonal   total pP")
  for phase in sorted(set(c["assign"]) | set(cells)):
    row = cells.get(phase, Counter())
    total = sum(row.values())
    if phase not in c["assign"]:
      note = "   <- THE TABLE GIVES THIS PHASE NO DIRECTORY"
    elif not total:
      note = "   <- NO MARKER CARRIES THIS TAG AT ALL"
    else:
      note = ""
    print(f"  P{phase:<5d} {row.get(phase, 0):15d} {row.get(phase, 0):14d} "
          f"{total - row.get(phase, 0):13d} {total:10d}" + note)
  print()


def template_test(sites):
  """How many markers are the brief's template verbatim, and how many of those name their
  OWN file's upstream counterpart."""
  tpl, own = Counter(), Counter()
  for rel, verb, tag, text in sites:
    match = TPL.match(text)
    if not match:
      continue
    tpl[(verb, tag)] += 1
    if Path(match.group(1)).stem == Path(rel).stem:
      own[(verb, tag)] += 1
  print("TEMPLATE TEST: `# TODO(<tag>) <file>.<ext>:<line>` is the form "
        ".agents/slop/brief-port.md:177 gives")
  for verb, tag in sorted(tpl, key=lambda k: (-tpl[k], k)):
    print(f"  {verb:5s} tag={tag:8s} in-template={tpl[(verb, tag)]:4d}  "
          f"names-its-own-file={own[(verb, tag)]:4d}  "
          f"({100 * own[(verb, tag)] / tpl[(verb, tag)]:5.1f}%)")
  print()


def density(c, sites):
  """CLAIMS PER FILE and FILES CARRYING ONE, by the phase of the file's directory. A tag
  that named a phase would concentrate; a default tracks how much work a phase has."""
  assign = c["assign"]
  files = Counter()
  for path in walk(c["port"], ".bend"):
    phase = _gate.phase_of(str(path.relative_to(c["port"])), assign)
    if phase is not None:
      files[phase] += 1
  claims, carriers = Counter(), defaultdict(set)
  for rel, verb, tag in sites:
    if verb != "TODO" or tag_phase(tag) is None:
      continue
    phase = _gate.phase_of(rel, assign)
    if phase is None:
      continue
    claims[phase] += 1
    carriers[phase].add(rel)
  print("DENSITY: TODO(p3) PER .bend FILE, BY THE PHASE OF THE FILE'S DIRECTORY")
  print("  phase  files  p3-claims  claims/file  share-claims  share-files  ratio  files-with-p3")
  total_claims = sum(claims.values())
  total_files = sum(files.values())
  for phase in sorted(files):
    share_claims = claims[phase] / total_claims if total_claims else 0.0
    share_files = files[phase] / total_files if total_files else 0.0
    per = claims[phase] / files[phase] if files[phase] else 0.0
    print(f"  P{phase:<5d} {files[phase]:5d} {claims[phase]:9d} {per:11.2f} "
          f"{share_claims:12.3f} {share_files:11.3f} {share_claims / share_files:6.2f} "
          f"{len(carriers.get(phase, ())):10d}")
  print()


def notation(c):
  """EVERY `P<n>/<X>` in the tree, and what `<X>` resolves to.

  `<X>` resolves to ONE OF THREE THINGS, and the difference decides whether the compound
  can be an ownership claim at all:
    PHASE    `P3/P6` -- the right side is a phase. "P3 owns P6" is not a sentence, so the
             compound cannot mean ownership.
    CELL     `P6/runtime` -- the right side is a table cell, and the phrase is
             "P6/runtime owns the allocator": the compound IS the subject of "owns".
    FEATURE  `P3/VIZ` -- the right side is neither. It names a FEATURE.
  """
  assign = c["assign"]
  index = {}
  for phase, cells in assign.items():
    for cell in cells:
      index.setdefault(_gate.stem_of(cell), (phase, cell))
  universe = c["universe"]
  rows = []
  for rel, number, phase, name in c["annots"]:
    if re.fullmatch(r"P\d+", name):
      kind, resolved = "PHASE", f"P{name[1:]}" + ("" if int(name[1:]) in universe else " (undeclared)")
    elif name.casefold() in index:
      cellphase, cell = index[name.casefold()]
      kind, resolved = "CELL", f"{cell} -> P{cellphase}"
    else:
      kind, resolved = "FEATURE", "no table cell of that name"
    text = _gate.read(c["port"] / rel).splitlines()
    tag = None
    for back in range(0, 14):
      index_line = number - 1 - back
      if index_line < 0:
        break
      found = CLAIM.match(text[index_line])
      if found:
        tag = found.group(1)
        break
    rows.append({"rel": rel, "line": number, "phase": phase, "name": name, "kind": kind,
                 "resolved": resolved,
                 "file_phase": _gate.phase_of(rel, assign), "tag": tag,
                 "text": text[number - 1].strip() if number - 1 < len(text) else ""})
  print(f"NOTATION CENSUS: every `P<n>/<X>` in the port ({len(rows)} of them)")
  print("  file:line                       file-phase  tag   kind     X resolves to")
  for row in rows:
    file_phase = f"P{row['file_phase']}" if row["file_phase"] is not None else "-"
    print(f"  {row['rel']}:{row['line']:<5d} {file_phase:>10s} {(row['tag'] or '-'):>5s}  "
          f"{row['kind']:8s} {row['resolved']}")
  print()
  return rows


def import_order(c):
  """THE PHASE TABLE IS A PORTING ORDER. Check it against the port's own import DAG.
  A plan and a structure are different things, and only one of them is derivable."""
  port = c["port"]
  edges = []
  for path in walk(port, ".bend"):
    rel = str(path.relative_to(port))
    for line in _gate.read(path).splitlines():
      match = IMP.match(line)
      if not match:
        continue
      target = (path.parent / (match.group(1) + ".bend")).resolve()
      if target.is_relative_to(port) and target.is_file():
        edges.append((rel, str(target.relative_to(port))))
  matrix_counts = Counter()
  up = []
  for src, dst in edges:
    a = _gate.phase_of(src, c["assign"])
    b = _gate.phase_of(dst, c["assign"])
    if a is None or b is None:
      continue
    matrix_counts[(a, b)] += 1
    if a < b:
      up.append((src, dst, a, b))
  phases = sorted(c["assign"])
  print(f"IMPORT ORDER: {len(edges)} intra-port import edges; the phase table as a "
        f"topological order of them")
  print("      " + "".join(f"P{p:<5d}" for p in phases))
  for a in phases:
    print(f"  P{a:<3d}" + "".join(f"{matrix_counts[(a, b)]:<6d}" for b in phases))
  print(f"  inter-phase edges={sum(matrix_counts.values())}  "
        f"edges that go UP the phase order={len(up)}")
  for src, dst, a, b in up:
    print(f"    UP: {src} -> {dst}  (P{a} imports P{b})")
  # DOES THE IMPORT DEPTH RECOVER THE PHASE NUMBERS? If it did, the table would be
  # DERIVABLE from the tree's own layout and there would be nothing for a human to decide.
  depth = {}
  deps = defaultdict(list)
  for src, dst in edges:
    deps[src].append(dst)

  def level_of(node, stack=()):
    if node in depth:
      return depth[node]
    if node in stack:
      return 0
    children = deps.get(node, ())
    depth[node] = 0 if not children else 1 + max(level_of(c, stack + (node,)) for c in children)
    return depth[node]

  for path in walk(port, ".bend"):
    level_of(str(path.relative_to(port)))
  byphase = defaultdict(list)
  for node, level in depth.items():
    phase = _gate.phase_of(node, c["assign"])
    if phase is not None:
      byphase[phase].append(level)
  print("  import DEPTH (longest chain INTO the file) by phase -- if this recovered the")
  print("  phase NUMBERS, the table would be derivable from the layout:")
  for phase in phases:
    values = byphase.get(phase, [])
    if values:
      print(f"    P{phase}: n={len(values):3d} mean={sum(values) / len(values):5.2f} "
            f"min={min(values)} max={max(values)}")
  print()


def main():
  c = _gate.census(ROOT)
  allmarkers = markers(c["port"])
  todo = [(rel, tag) for rel, _n, verb, tag, _t in allmarkers if verb == "TODO"]
  print(f"phase-taxonomy-matrix: port={c['port'].relative_to(ROOT)} "
        f"bend_files={len(walk(c['port'], '.bend'))}")
  print(f"  markers_all_verbs={len(allmarkers)} "
        f"{dict(Counter(v for _r, _n, v, _t, _x in allmarkers))}")
  print(f"  gate_claims_TODO_only={len(c['claims'])}")
  print()
  print("TAGS IN USE, BY VERB")
  byverb = defaultdict(Counter)
  for _rel, _n, verb, tag, _t in allmarkers:
    byverb[verb][tag] += 1
  for verb in sorted(byverb):
    print(f"  {verb:5s} total={sum(byverb[verb].values()):4d}  {dict(byverb[verb])}")
  print()

  cells, cols = matrix(c, todo)
  print_matrix("MATRIX (the gate's population, `# TODO(...)` claims): rows = the phase the "
               "MARKER NAMES, columns = the phase of the DIRECTORY IT SITS IN", cells, cols)
  own_phase_test(c, cells)
  template_test([(rel, verb, tag, text) for rel, _n, verb, tag, text in allmarkers])
  density(c, [(rel, verb, tag) for rel, _n, verb, tag, _t in allmarkers])
  rows = notation(c)
  import_order(c)

  if "--rows" in sys.argv:
    out = ROOT / "oracles" / "phase-taxonomy-matrix.rows"
    with out.open("w", encoding="utf-8") as fh:
      fh.write("# phase-taxonomy-matrix.rows -- generated by "
               "oracles/phase-taxonomy-matrix.py; do not hand-edit.\n")
      fh.write("# matrix: rows = the phase the MARKER NAMES, columns = the phase of the "
               "DIRECTORY the marker SITS IN; '-' = no assigned directory.\n")
      fh.write("kind\trow\tcol\tcount\n")
      for phase in sorted(cells):
        for col in cols:
          fh.write(f"matrix\tp{phase}\t{('P' + str(col)) if col is not None else '-'}\t"
                   f"{cells[phase][col]}\n")
      fh.write("kind\trel\tline\tmarker_phase\tname\tkind\tresolved\tfile_phase\ttag\ttext\n")
      for row in rows:
        fh.write("annot\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\t{}\n".format(
          row["rel"], row["line"], row["phase"], row["name"], row["kind"], row["resolved"],
          f"P{row['file_phase']}" if row["file_phase"] is not None else "-",
          row["tag"] or "-", row["text"]))
    print(f"wrote {out.relative_to(ROOT)}")
  return 0


if __name__ == "__main__":
  sys.exit(main())
