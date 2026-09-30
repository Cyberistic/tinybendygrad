import io, os, sys, token, tokenize
sys.path.insert(0, '.agents/slop/notes')
import importlib.util
spec = importlib.util.spec_from_file_location('cmp', '.agents/slop/notes/sz-toks-cmp.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module.__self__ if False else None
src = open('.agents/slop/notes/sz-toks-cmp.py').read()
src = src[:src.index("if __name__ == '__main__'")]
g = {}
exec(src, g)
p = sys.argv[1]
data = open(p, 'rb').read()
a = g['py_toks'](data)
try:
  b = g['bend_toks'](data)
except Exception as e:
  print("bend raised:", e)
  b = []
print("py", len(a), "bend", len(b))
for i in range(min(len(a), len(b))):
  if a[i] != b[i]:
    print("first diff at token", i)
    print("  py  ", a[i], repr(data[a[i][0]:a[i][1]].decode('utf-8', 'replace')))
    print("  bend", b[i], repr(data[b[i][0]:b[i][1]].decode('utf-8', 'replace')))
    lo = max(0, min(a[i][0], b[i][0]) - 260)
    print("  context:")
    print(repr(data[lo:max(a[i][1], b[i][1]) + 80].decode('utf-8', 'replace')))
    break
else:
  print("no elementwise diff; length differs")
