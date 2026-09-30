import sys
src = open('.agents/slop/notes/sz-lexer-proto.py').read()
g = {'__name__': 'proto'}
exec(src[:src.index('if __name__')], g)
def run(f, b):
  try: return f(b)
  except Exception as e: return ('ERR', str(e)[:60])
snips = [
  b'def _f(torchdtype:\'torch.dtype\') -> DType: # type: ignore [name-defined] # noqa: F821\n',
  b'def _f(x:\'torch.dtype\')\n',
  b'x:\'torch.dtype\'\n',
  b'x -> DType: pass\n',
  b'x: \'torch.dtype\'\n',
  b'return {v:k for k in D.values() if (v:=f(k)) is not None}[t]\n',
  b'x = {v:k for k in D.values()}\n',
  b'if (v:=f(k)) is not None: pass\n',
]
for s in snips:
  print(repr(s), run(g['py_stats'], s), run(g['bend_stats'], s), flush=True)
