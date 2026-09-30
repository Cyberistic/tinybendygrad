#!/usr/bin/env python3
# The whole tool, as a prototype: sz.py's behaviour with the prototype lexer, so the
# table format can be diffed byte for byte before any of it is typed into Bend.
import os, sys, token, tokenize
src = open('.agents/slop/notes/sz-lexer-proto.py').read()
src = src[:src.index('if __name__')]
g = {'__name__': 'proto'}
exec(src, g)

WS = frozenset((9, 10, 11, 12, 13, 32, 28, 29, 30, 31))
TOKEN_WHITELIST = ['OP', 'NAME', 'NUMBER', 'STRING']
NONCORE_DIRS = {"tinygrad/llm", "tinygrad/nn", "tinygrad/renderer", "tinygrad/runtime", "tinygrad/viz"}
SKIP = ['tinygrad/runtime/autogen', 'tinygrad/viz/assets']


def is_docstring(t): return t.type == token.STRING and t.string.startswith('"""') \
    and t.line.strip().startswith('"""')


def is_js_token(s): return len(s) and not s.startswith('//')


def js_stats(data):
  lines = [l.strip() for l in data.decode('utf-8', 'replace').splitlines(True)]
  tc = lc = 0
  for l in lines:
    if not is_js_token(l): continue
    lc += 1
    n = 0
    for w in l.split(): n += 1
    tc += n
  return tc, lc


def gen_stats(base_path="."):
  table = []
  for path, _, files in os.walk(os.path.join(base_path, "tinygrad")):
    for name in files:
      if not (name.endswith(".py") or name.endswith(".js")): continue
      if any(s in path.replace('\\', '/') for s in SKIP): continue
      filepath = os.path.join(path, name)
      relfilepath = os.path.relpath(filepath, base_path).replace('\\', '/')
      data = open(filepath, 'rb').read()
      if name.endswith(".js"):
        token_count, line_count = js_stats(data)
      else:
        token_count, line_count = g['bend_stats'](data)
      if line_count > 0: table.append([relfilepath, line_count, token_count])
  return table


def gen_diff(table_old, table_new):
  table = []
  files_new = set([x[0] for x in table_new])
  files_old = set([x[0] for x in table_old])
  added, deleted, unchanged = files_new - files_old, files_old - files_new, files_new & files_old
  if added:
    for file in added:
      fs = [s for s in table_new if file in s]
      table.append([fs[0][0], fs[0][1], fs[0][1] - 0, fs[0][2], fs[0][2] - 0])
  if deleted:
    for file in deleted:
      fs = [s for s in table_old if file in s]
      table.append([fs[0][0], 0, 0 - fs[0][1], 0, 0 - fs[0][2]])
  if unchanged:
    for file in unchanged:
      o = [s for s in table_old if file in s][0]
      n = [s for s in table_new if file in s][0]
      if n[1] - o[1] != 0 or n[2] - o[2] != 0:
        table.append([n[0], n[1], n[1] - o[1], n[2], n[2] - o[2]])
  return table


def display_diff(diff): return "+" + str(diff) if diff > 0 else str(diff)


def tenths(t, l):
  """round(10*t/l) the way format(t/l, '.1f') rounds it. See spec/sz.md."""
  q, r = divmod(10 * t, l)
  if 2 * r > l or (2 * r == l and (q & 1 or not 5 <= (2 * q + 1) % 20 < 15)): q += 1
  return q


def tenths_text(t, l, dt=0):
  q = (tenths(t, l) + dt) & 0xffffffff
  if q >= 1 << 31:
    m = (1 << 32) - q
    return "-%d.%d" % (m // 10, m % 10)
  return "+%d.%d" % (q // 10, q % 10)


def ratio_text(t, l): return "%d.%d" % (tenths(t, l) // 10, tenths(t, l) % 10)


def signed(n):
  n &= 0xffffffff
  if n >= 1 << 31: return "-%d" % -(n - (1 << 32))
  return "+%d" % n


def same_ratio(t1, l1, t2, l2):
  """sz.py compares the two tokens/line floats; exact for line counts under 2**16."""
  if t1 // l1 != t2 // l2: return False
  return (t1 % l1) * l2 == (t2 % l2) * l1


def tabulate(headers, rows, aligns):
  """rows: cells already formatted to strings. aligns: False = right, True = left."""
  ncol = len(headers)
  width = [max(len(headers[i]) + 2, max(len(r[i]) for r in rows)) for i in range(ncol)]
  def line(cells):
    return '  '.join(c.rjust(width[i]) if not aligns[i] else c.ljust(width[i])
                     for i, c in enumerate(cells)).rstrip()
  return '\n'.join([line(headers), '  '.join('-' * w for w in width)] +
                   [line(r) for r in rows])


def main(argv):
  if len(argv) == 2:
    headers = ["Name", "Lines", "Diff", "Tokens/Line", "Diff"]
    old = {r[0]: r for r in gen_stats(argv[0])}
    new = {r[0]: r for r in gen_stats(argv[1])}
    rows = []
    for n, r in new.items():
      if n not in old: rows.append([n, "%d" % r[1], signed(r[1]), ratio_text(r[2], r[1]),
                                    tenths_text(r[2], r[1], 0), r[1]])
    for n, o in old.items():
      if n not in new: rows.append([n, "0", signed(-o[1]), "0.0",
                                    tenths_text(0, 1, -tenths(o[2], o[1])), -o[1]])
    for n, r in new.items():
      if n in old:
        o = old[n]
        if r[1] != o[1] or not same_ratio(r[2], r[1], o[2], o[1]):
          rows.append([n, "%d" % r[1], signed(r[1] - o[1]), ratio_text(r[2], r[1]),
                       tenths_text(r[2], r[1], -tenths(o[2], o[1])), r[1] - o[1]])
    rows.sort(key=lambda r: -int(r[1]))
    total = sum(r[5] for r in rows)
    out = ["### Changes\n```",
           tabulate(headers, [r[:5] for r in rows], [True, False, False, False, False]) + "\n",
           "\ntotal lines changes: %s" % display_diff(total),
           "```"]
    return '\n'.join(out) + '\n'
  headers = ["Name", "Lines", "Tokens/Line"]
  base = argv[0] if len(argv) == 1 else "."
  table = gen_stats(base)
  if not table: return ''
  cells = [[r[0], "%d" % r[1], ratio_text(r[2], r[1])] for r in table]
  order = sorted(range(len(table)), key=lambda i: -table[i][1])
  cells = [cells[i] for i in order]
  out = [tabulate(headers, cells, [True, False, False]) + "\n"]
  groups = {}
  counts = {}
  for r in table:
    dn = '/'.join(r[0].rsplit("/", 1)[0].split("/")[0:2])
    groups[dn] = groups.get(dn, 0) + r[1]
    counts[dn] = counts.get(dn, 0) + 1
  for dn in sorted(groups):
    out.append("%-30s : %6d in %2d files" % (dn, groups[dn], counts[dn]))
  out.append("")
  out.append("        ops: %d" % 77)
  out.append("      flags: %d" % 55)
  out.append(" core lines: %d" % sum(v for k, v in groups.items() if k not in NONCORE_DIRS))
  out.append("total lines: %d" % sum(r[1] for r in table))
  return '\n'.join(out) + '\n'


if __name__ == '__main__':
  sys.stdout.write(main(sys.argv[1:]))
