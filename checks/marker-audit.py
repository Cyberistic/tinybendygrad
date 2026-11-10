#!/usr/bin/env python3
"""Classify every `TODO(p3)` marker in the port as BACKLOG or NAMED WALL.

    .venv/bin/python .agents/slop/marker-audit.py

A marker's ENTRY is its line plus the comment lines that continue it, which is
where the reason lives. The first version of this read only 14 raw lines ahead and
missed every entry whose reason runs longer -- and it counted PROSE that merely
REFERENCES a `TODO(p3)` (`# ... is # TODO(p3) ops.py:1181 in ops.bend`) as if it
were a marker. Between them those two bugs reported 162 unexplained markers in
`uop/` when a large share of them are walls with the reason already written down.

A marker is a NAMED WALL when its entry says why, in the file's own vocabulary:
a `refused:unported` declaration, a named dependency, a missing upstream, or an
explicit `-- reason` / `is P3` / `needs ...` clause. Everything else is BACKLOG.
"""
import pathlib
import re
import sys

WALL = re.compile(
    r'refused:unported|'
    r'not ported|NOT PORTED|unported|'
    r'\bwall\b|'
    r'\bdeferred\b|\bblocked\b|\bBLOCKED\b|'
    r'\bdepends on\b|\bneeds (?:a|an|the|`|it)\b|'
    r'\bis (?:P\d|not ported|NOT)\b|'
    r'\bno (?:Bend|port|substrate)\b|'
    r'\bcannot\b|\bunexpressible\b|'
    r'--\s+\S|--\s*$',
    re.I)

REASON = re.compile(r'--\s*\S')

MARKER = re.compile(r'^\s*#\s*(?:TODO\(p3\)|WALL\(p3\))')
# THE second marker form is `WALL(p3)`, AND it is a spelling of the same concept.
#
# MEASURED 2026-11-10: `tinybendygrad/` CARRIES 149 `WALL(p3)` OCCURRENCES IN 17 FILES,
# OF which 105 ARE markers (THE other 44 ARE references -- A line that names a marker rather
# THAN being one).  - AND `schedule/rangeify.bend` ALONE has 30, WHICH is why the ledger'S
# `MARKERFORM` ITEM said "30" AND measured it in one file.  - AND every one of the 105 STATES
# A reason (MEASURED with this file's OWN `WALL` PATTERN), - SO accepting the form adds 105
# WALLS and 0 BACKLOG -- AND a population that moves by 105 WALLS and 0 WORK is a population
# THAT was blind, NOT a population that was wrong.
#
# - AND this is a doctrine-1 REPAIR, NOT a doctrine-1 VIOLATION.  THE old rule declared its
# POPULATION by a spelling (`if 'TODO(p3)' not in l`), WHICH is exactly what doctrine 1
# FORBIDS; THE new rule declares it by the marker concept, WHICH has two spellings, AND the
# SPELLINGS are a set and not a list of one.  - AND which spelling the port uses is the
# CALLER's, NOT the auditor's -- AND the caller (THE ledger's `MARKERFORM` ITEM) HAS ruled:
# THE port's FORM is to stay, SO the instrument accepts both.
#
# - AND the `TODO(p3)` FORM is not weakened: A line that references a marker rather than
# BEING one is still excluded, AND that test (`MARKER.match` ON the first line) IS unchanged.
MARKER_FORMS = ('TODO(p3)', 'WALL(p3)')
# - AND the `WALL(p3)` SPELLING collides with the `WALL` REASON pattern, AND that is the
# SECOND half of the same defect.  `WALL`'s PATTERN has `\bwall\b` IN it (THE WORD "wall" IS
# HOW a *REASON* READS: "this is a WALL"), - SO a `WALL(p3)` MARKER matches `WALL` THROUGH
# ITS own spelling and every such marker is a "WALL" WHETHER or not it states a reason.
# MEASURED 2026-11-10 BY planting one: A `# WALL(p3) PLANTED-MARKER  rangeify.py:999
# some_symbol  more text.` LINE -- WITH no reason at all -- WAS classified wall, NOT
# BACKLOG, - SO the classifier could not see a reason-FREE marker of the new form, AND a
# CLASSIFIER that cannot say "no" IS a classifier that says "yes" TO everything.
#
# - AND `TODO(p3)` NEVER had this problem (`TODO` IS not in the `WALL` PATTERN), - SO the
# FIX is to remove the marker's OWN token before the reason is looked for -- AND to remove it
# IN both forms, SO the two spellings are classified by the same rule.  - AND the token
# REMOVED is exactly the marker token, NOT the WORD "wall" IN general, BECAUSE a marker may
# SAY "WALL" IN its reason and that is a real reason.
MARKER_TOKEN = re.compile(r'\b(?:TODO|WALL)\(p3\)')


def reason_text(t):
  """THE MARKER's TEXT WITH **THE MARKER's OWN TOKEN** REMOVED, so the reason is READ.

  **AND THIS IS THE WHOLE FIX FOR THE COLLISION**: THE REASON PATTERN IS THEN ASKED ABOUT
  WHAT THE MARKER *SAYS* AND NOT ABOUT HOW THE MARKER IS *SPELLED*.
  """
  return MARKER_TOKEN.sub('', t)


def entries(path):
  """(lineno, text) per marker entry: the line plus its OWN continuation.

  The continuation stops at the next marker. Without that stop every entry
  swallowed the rest of the block, one `--` marked all of them, and the audit
  reported 0 backlog -- the failure mode a classifier that cannot say `no`
  always has.
  """
  lines = path.read_text().split('\n')
  out = []
  for i, l in enumerate(lines):
    # THE population is the marker concept, AND it has two spellings.  THE old rule was
    # `if 'TODO(p3)' not in l`, WHICH is a spelling and therefore blind to the other one.
    if not any(f in l for f in MARKER_FORMS):
      continue
    body = [l]
    for nxt in lines[i + 1:]:
      if not nxt.strip().startswith('#') or MARKER.match(nxt):
        break
      body.append(nxt)
    out.append((i + 1, '\n'.join(body)))
  return out


def shared_reason(path, name):
  """A reason stated ELSEWHERE in the file: the NOT PORTED block.

  `ops.py:1545..1790` are forty-odd bare markers for the `UPat` COMPILER, and the
  wall for all of them is written once in the file's NOT PORTED block rather than
  beside each. Counting those as backlog is wrong in the OTHER direction: it
  inflates the queue with work that is already accounted for and makes the real
  remainder invisible. So a marker whose def NAME is named in a non-marker comment
  in the same file HAS a reason -- it is just not adjacent.
  """
  base = name.split('.')[-1]
  if not base or base.startswith('__'):
    return None
  for l in path.read_text().split('\n'):
    s = l.strip()
    # A marker is not a reason for itself, IN either spelling.
    if not s.startswith('#') or any(f in s for f in MARKER_FORMS):
      continue
    if re.search(r'`\b' + re.escape(base) + r'\b', s):
      return s.lstrip('# ').strip()[:70]
  return None


def main():
  roots = [a for a in sys.argv[1:] if not a.startswith('-')] or ['tinybendygrad']
  files = sorted(p for r in roots for p in pathlib.Path(r).rglob('*.bend'))
  gb = gs = gw = 0
  print(f"{'file':44} {'walls':>6} {'shared':>7} {'BACKLOG':>8}")
  for p in files:
    # A line that REFERENCES a marker rather than being one: the marker text is
    # mid-sentence, so the line does not START with the comment + TODO.
    real = [(n, t) for n, t in entries(p) if MARKER.match(t.split('\n')[0])]
    if not real:
      continue
    walls = [t for _, t in real if WALL.search(reason_text(t))]
    shared, backlog = [], []
    for n, t in real:
      if WALL.search(reason_text(t)):
        continue
      m = re.search(r'\bdef\s+([\w.]+)', t.split('\n')[0])
      nm = m.group(1) if m else ''
      (shared if nm and shared_reason(p, nm) else backlog).append((n, t))
    gb += len(backlog)
    gs += len(shared)
    gw += len(walls)
    print(f"{str(p):44} {len(walls):6} {len(shared):7} {len(backlog):8}")
    for n, t in backlog:
      head = t.split(chr(10))[0].strip()
      print(f"    BACKLOG {p}:{n}  {head[:86]}")
  print(f"{'TOTAL':44} {gw:6} {gs:7} {gb:8}")
  print(f"""
{gb} BACKLOG, {gs} reason stated elsewhere, {gw} walls. Only BACKLOG is work.

  wall    the reason is in the marker's OWN entry. Closed in the only honest sense
          available: it compiles, it prints the gap, nobody mistakes it for flight.
  shared  the reason is written once in the file's NOT PORTED block rather than
          beside each marker. Accounted for; the marker is just not adjacent.
  BACKLOG no reason anywhere. This is the queue, and it is printed above
          unconditionally -- a split that cannot show its own backlog is a split
          nobody can check.""")
  return 0


if __name__ == '__main__':
  sys.exit(main())
