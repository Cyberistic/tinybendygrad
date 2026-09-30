#!/usr/bin/env python3
# Probe 2: the operator table, the error characters, and the number/string edges.
import token, tokenize, io, sys

def dump(src, label, all_types=False):
  print("=" * 70)
  print(label)
  try:
    for t in tokenize.generate_tokens(io.StringIO(src).readline):
      keep = all_types or t.type in (token.OP, token.NAME, token.NUMBER, token.STRING)
      if keep:
        print("  %-14s %-6d %-22r %s %s" % (token.tok_name[t.type], t.type, t.string, t.start, t.end))
  except Exception as e:
    print("  RAISED %s: %s" % (type(e).__name__, e))

print("EXACT_TOKEN_TYPES:")
print(sorted(token.EXACT_TOKEN_TYPES))
print("token types:", sorted((v, k) for k, v in token.tok_name.items() if isinstance(v, int))[:3], "...")
print("all tok_name:", token.tok_name)

for label, src in [
  ("dollar etc", "a = $ ? ` ; @ ! ~ ^ & | \\ \n"),
  ("lone backslash", "a = 1\nb = \\\n"),
  ("ctrl char", "a = \x01\n"),
  ("bom", "\ufeffa = 1\n"),
  ("number edges", "a = 00\nb = 0_0\nc = 1_\nd = 1e\ne = 1.5.5\nf = 1.e3\ng = 0x\nh = 0b\ni = 0o\nj = 1j2\nk = .5.5\nl = 1_0_0\n"),
  ("dot ops", "a = a.b\na = a...b\na = a. . .b\n"),
  ("name after num", "a = 1abc\na = 0x1g\n"),
  ("fstring lone brace", 'x = f"}"\n'),
  ("fstring lone brace2", 'x = f"a}b"\n'),
  ("fstring backslash", 'x = f"a\\nb"\n'),
  ("fstring conv bad", 'x = f"{a!q}"\n'),
  ("fstring colon equals", 'x = f"{a:=1}"\n'),
  ("fstring nested in spec", 'x = f"{a:{f\'{w}\'}}"\n'),
  ("fstring quote reuse", "x = f\"{d['k']}\"\n"),
  ("fstring triple inner", 'x = f"""{a}"""\n'),
  ("fstring single in triple", 'x = f"""{\'a\'}"""\n'),
  ("raw fstring", 'x = rf"\\d{a}"\n'),
  ("fstring newline cont", 'x = f"a\\\nb"\n'),
  ("bytes triple", 'x = b"""a"""\n'),
  ("fstring empty field", 'x = f"{}"\n'),
  ("fstring ws field", 'x = f"{ a }"\n'),
  ("fstring format spec text", 'x = f"{a:>10}"\n'),
  ("str prefix case", "x = F'{a}'\ny = RF'{a}'\n"),
  ("semicolons", "a = 1; b = 2\n"),
  ("decorator", "@foo\ndef f(): pass\n"),
  ("cr only", "a = 1\rb = 2\r"),
  ("formfeed", "a = 1\x0cb = 2\n"),
  ("vertical tab", "a = 1\x0bb = 2\n"),
]:
  dump(src, label, all_types=True)
