import sys, token, tokenize, io
p = sys.argv[1]
a, b = int(sys.argv[2]), int(sys.argv[3])
data = open(p, 'rb').read()
src = data.decode('utf-8', 'replace')
for t in tokenize.generate_tokens(io.StringIO(src).readline):
  if t.start[0] < a or t.start[0] > b: continue
  if t.type in (tokenize.COMMENT, tokenize.NL, tokenize.NEWLINE, tokenize.INDENT,
                tokenize.DEDENT, tokenize.ENDMARKER): continue
  print("%-14s %-30r %s %s" % (token.tok_name[t.type], t.string[:28], t.start, t.end))
