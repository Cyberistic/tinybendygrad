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

MARKER = re.compile(r'^\s*#\s*TODO\(p3\)')


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
    if 'TODO(p3)' not in l:
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
    if not s.startswith('#') or 'TODO(p3)' in s:
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
    walls = [t for _, t in real if WALL.search(t)]
    shared, backlog = [], []
    for n, t in real:
      if WALL.search(t):
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
      print(f"    BACKLOG {p.name}:{n}  {head[:86]}")
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
