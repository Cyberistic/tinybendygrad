import sys
src = open('.agents/slop/notes/sz-lexer-proto.py').read()
src = src[:src.index('if __name__')]
src = src.replace("  n = len(bs)\n  while True:",
                  "  n = len(bs)\n  global TRACE\n  while True:\n    TRACE.append((acc[0], st[0], st[1]))\n    if len(TRACE) > 400: TRACE.pop(0)")
g = {'__name__': 'proto'}
exec(src, g)
g['TRACE'] = []
p = sys.argv[1]
data = open(p, 'rb').read()
try:
  print(g['bend_stats'](data), flush=True)
except Exception as e:
  print("raised:", e)
  for t in g['TRACE'][-25:]: print("  at", t, repr(data[t[0]:t[0] + 24].decode('utf-8', 'replace')))
