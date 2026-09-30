import io, sys, token, tokenize
src = open('.agents/slop/notes/sz-toks-cmp.py').read()
src = src[:src.index("if __name__ == '__main__'")]
g = {}
exec(src, g)
data = sys.argv[1].encode().decode('unicode_escape').encode('latin-1')
print(repr(data))
print("--- py ---")
text = data.decode('utf-8', 'replace')
for t in tokenize.generate_tokens(io.StringIO(text).readline):
  if t.type in g['WHITE']: print("  %-8s %r %s %s" % (token.tok_name[t.type], t.string, t.start, t.end))
print("--- bend ---")
g['g']['TR'] = []
print(g['bend_toks'](data))
for a, b in g['g']['TR']: print("  %r" % data[a:b])
