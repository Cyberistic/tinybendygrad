#!/usr/bin/env python3
# Compare the prototype's token boundaries against CPython's, token for token.
# The strongest check available: every OP/NAME/NUMBER/STRING token must have the
# same start and end offset, so a wrong line count cannot hide.
import io, os, sys, token, tokenize

src = open('.agents/slop/notes/sz-lexer-proto.py').read()
src = src[:src.index('if __name__')]
src = src.replace("def bumpm(acc, fromline, endline):\n", "def bumpm(acc, fromline, endline):\n  TR.append((TSTART, acc[0]))\n")
src = src.replace("  n = len(bs)\n  while True:", "  n = len(bs)\n  while True:\n    global TSTART\n    TSTART = acc[0]")
g = {'__name__': 'proto'}
exec(src, g)

WHITE = (token.OP, token.NAME, token.NUMBER, token.STRING)


def py_toks(data):
  text = data.decode('utf-8', 'replace')
  out = []
  for t in tokenize.generate_tokens(io.StringIO(text).readline):
    if t.type not in WHITE: continue
    if t.type == token.STRING and t.string.startswith('"""') and t.line.strip().startswith('"""'): continue
    out.append((t.start[0], t.end[0]))
  return out


def bend_toks(data):
  g['TR'] = []
  g['bend_stats'](data)
  nl = [0] * (len(data) + 2)
  for i, c in enumerate(data):
    nl[i + 1] = nl[i] + (1 if c == 10 else 0)
  return [(nl[a] + 1, nl[b] + 1) for a, b in g['TR']]


def check(data, label):
  try:
    a = py_toks(data)
  except Exception as e:
    return 'py-err', str(e)[:40]
  try:
    b = bend_toks(data)
  except Exception as e:
    return 'bend-err', str(e)[:40]
  if len(a) != len(b):
    k = min(len(a), len(b))
    for i in range(k):
      if a[i] != b[i]: return ('len %d vs %d, first diff at %d: py %r bend %r' % (
        len(a), len(b), i, a[i], b[i]),)
    return ('len %d vs %d' % (len(a), len(b)),)
  for i in range(len(a)):
    if a[i] != b[i]:
      return ('tok %d: py %s  bend %s' % (i, a[i], b[i]),)
  return 'ok', ''


if __name__ == '__main__':
  bad = n = 0
  for root, _, files in os.walk(sys.argv[1] if len(sys.argv) > 1 else 'tinygrad'):
    for f in sorted(files):
      if not f.endswith('.py'): continue
      p = os.path.join(root, f)
      res = check(open(p, 'rb').read(), p)
      v = res[0] if isinstance(res, tuple) else res
      why = res[1] if isinstance(res, tuple) and len(res) > 1 else ''
      n += 1
      if v != 'ok':
        bad += 1
        if bad <= 10: print("BAD", p, v, why)
  print("files", n, "bad", bad)
