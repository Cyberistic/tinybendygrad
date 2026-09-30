#!/usr/bin/env python3
# Probe 5: the field rules -- which operator opens a spec, which closes a field.
import tokenize, io

def run(src, label):
  print("=" * 70)
  print(label, repr(src))
  try:
    for t in tokenize.generate_tokens(io.StringIO(src).readline):
      if t.type in (tokenize.OP, tokenize.NAME, tokenize.NUMBER, tokenize.STRING):
        print("  %-16s %-22r %s %s" % (tokenize.tok_name[t.type], t.string, t.start, t.end))
  except Exception as e:
    print("  RAISED %s: %s" % (type(e).__name__, e))

for label, src in [
  ("walrus in field", 'x = f"{a:=1}"\n'),
  ("colon in list", 'x = f"{a[1:2]}"\n'),
  ("colon in tuple", 'x = f"{a[1:2, 3]}"\n'),
  ("dict in field", 'x = f"{ {\'a\': 1} }"\n'),
  ("lambda in field", 'x = f"{lambda: 1}"\n'),
  ("slice in field", 'x = f"{a[1:]}"\n'),
  ("bracket close", 'x = f"{a[1]}"\n'),
  ("nested field", 'x = f"{ {1:2} }"\n'),
  ("spec with dict", 'x = f"{a:{\'k\': 1}}"\n'),
  ("spec with list", 'x = f"{a:[1, 2]}"\n'),
  ("spec depth", 'x = f"{a:{w}}"\n'),
  ("spec then close", 'x = f"{a:>{w}}"\n'),
  ("escape in spec", 'x = f"{a:\\d}"\n'),
  ("escape quote in spec", 'x = f"{a:\\"}"\n'),
  ("escape brace in spec", 'x = f"{a:\\{b}}"\n'),
  ("escape in spec 2", 'x = f"{a:\\}}"\n'),
  ("brace in spec", 'x = f"{a:{}}"\n'),
  ("quote in spec", "x = f\"{a:'x'}\"\n"),
  ("dquote in spec", 'x = f"{a:"x"}"\n'),
  ("nl in spec", 'x = f"""{a:\n}"""\n'),
  ("nl in spec single", 'x = f"{a:\n}"\n'),
  ("triple spec", 'x = f"""{a:"""x"""}"""\n'),
  ("empty field", 'x = f"{}"\n'),
  ("field in field", 'x = f"{a:{b:{c}}}"\n'),
  ("conv and spec", 'x = f"{a!r:>{w}}"\n'),
  ("nested fstring", "x = f\"{f'{g}'}\"\n"),
  ("backslash brace text", 'x = f"a\\{b}"\n'),
  ("backtick", 'a = `b\n'),
  ("dollar", 'a = $b\n'),
  ("at at", 'a = @@\n'),
  ("tilde tilde", 'a = ~~\n'),
  ("caret eq", 'a = ^=\n'),
  ("pipe pipe", 'a = ||\n'),
  ("angle angle eq", 'a = <<=\n'),
  ("arrow arrow", 'a = ->>\n'),
  ("dot dot", 'a = 1..2\n'),
  ("star star", 'a = 1**2\n'),
  ("slash slash", 'a = 1//2\n'),
  ("percent eq", 'a = 1%=2\n'),
  ("amp eq", 'a = &=2\n'),
  ("bang eq", 'a = !=2\n'),
  ("at eq", 'a = @=2\n'),
  ("colon eq", 'a = :=2\n'),
  ("lt eq", 'a = <=2\n'),
  ("gt eq", 'a = >=2\n'),
  ("eq eq", 'a = ==2\n'),
]:
  run(src, label)
