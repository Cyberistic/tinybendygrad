#!/usr/bin/env python3
# Probe 6: the f-string escape rules, text and spec, single and triple quoted.
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
  ("rbrace in text", 'x = f"a\\}b"\n'),
  ("lbrace in text", 'x = f"a\\{b}"\n'),
  ("bs nl single", 'x = f"a\\\nb"\n'),
  ("bs nl text single", 'x = f"a\\\nb" c = 1\n'),
  ("bs nl triple", 'x = f"""a\\\nb"""\n'),
  ("bs nl spec single", 'x = f"{a:\\\n}"\n'),
  ("bs nl spec triple", 'x = f"""{a:\\\n}"""\n'),
  ("bs quote text", 'x = f"a\\"b"\n'),
  ("bs quote spec", 'x = f"{a:\\"}"\n'),
  ("bs bs text", 'x = f"a\\\\b"\n'),
  ("bs bs spec", 'x = f"{a:\\\\}"\n'),
  ("bs x text", 'x = f"a\\qb"\n'),
  ("bs brace brace", 'x = f"{{\\}}"\n'),
  ("cr in text", 'x = f"a\rb"\n'),
  ("cr in spec", 'x = f"{a:\rb}"\n'),
  ("crlf in text", 'x = f"a\r\nb"\n'),
  ("crlf in spec", 'x = f"{a:\r\nb}"\n'),
  ("nested triple", "x = f\"\"\"{f'''{a}'''}\"\"\"\n"),
  ("quote in spec triple", 'x = f"""{a:"x"}"""\n'),
  ("spec triple end", 'x = f"""{a:>10}"""\n'),
  ("text triple quote1", 'x = f"""a"b"""\n'),
  ("text triple quote4", 'x = f""""\n'),
  ("text quote then brace", 'x = f"a"{}"\n'),
  ("spec then text quote", 'x = f"{a}b"\n'),
  ("spec brace brace", 'x = f"{a:{{}}"\n'),
  ("spec close close", 'x = f"{a:}}"\n'),
  ("text close close", 'x = f"a}}"\n'),
  ("conversion", 'x = f"{a!s}"\n'),
  ("conversion bad", 'x = f"{a!q}"\n'),
  ("equals", 'x = f"{a=}"\n'),
  ("equals spec", 'x = f"{a=:>10}"\n'),
  ("nested fstring spec", "x = f\"{a:{f'{w}'}}\"\n"),
  ("field with comment", 'x = f"{a # c\n}"\n'),
  ("empty spec", 'x = f"{a:}"\n'),
  ("nl in text triple spec", 'x = f"""{a:\n}""" c = 1\n'),
  ("open brace in text", 'x = f"{"\n'),
  ("close brace text", 'x = f"}"\n'),
  ("close brace then brace", 'x = f"}}" c = 1\n'),
  ("close brace in spec then", 'x = f"{a:}}}" c = 1\n'),
]:
  run(src, label)
