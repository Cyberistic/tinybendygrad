import sys
src = open('.agents/slop/notes/sz-lexer-proto.py').read()
g = {'__name__': 'proto'}
exec(src[:src.index('if __name__')], g)
p = sys.argv[1]
data = open(p, 'rb').read()
lines = data.splitlines(True)
offs = [0]
for l in lines: offs.append(offs[-1] + len(l))
def run(f, b):
  try: return f(b)
  except Exception as e: return None
def bad(k):
  b = data[:offs[k]]
  a, c = run(g['py_stats'], b), run(g['bend_stats'], b)
  return a is not None and c is not None and a != c
lo, hi = 0, len(lines)
while lo < hi:
  mid = (lo + hi) // 2
  if bad(mid): hi = mid
  else: lo = mid + 1
k = lo
print("first divergent line prefix", k, "of", len(lines))
b = data[:offs[k]]
print("py ", run(g['py_stats'], b))
print("bend", run(g['bend_stats'], b))
print("--- line", k, "---")
print(repr(lines[k - 1].decode('utf-8', 'replace')))
if k < len(lines): print("--- next ---"); print(repr(lines[k].decode('utf-8', 'replace')))
