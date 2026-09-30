#!/usr/bin/env python3
# Probe 3: the f-string literal escapes, and the last few shapes.
import token, tokenize, io

def dump(src, label, all_types=True):
  print("=" * 70)
  print(label)
  try:
    for t in tokenize.generate_tokens(io.StringIO(src).readline):
      print("  %-14s %-22r %s %s" % (token.tok_name[t.type], t.string, t.start, t.end))
  except Exception as e:
    print("  RAISED %s: %s" % (type(e).__name__, e))

for label, src in [
  ("fstring escaped quote", 'x = f"a\\"b"\n'),
  ("fstring escaped brace", 'x = f"a\\{b}"\n'),
  ("fstring spec close", 'x = f"{a:}}}"\n'),
  ("fstring double brace in spec", 'x = f"{a:{{}}"\n'),
  ("fstring spec nested close", 'x = f"{a:{w}}}"\n'),
  ("fstring literal newline", "x = f'a\nb'\n"),
  ("fstring literal backslash end", 'x = f"a\\"\n'),
  ("triple str backslash newline", 'x = """a\\\nb"""\n'),
  ("triple str quote", 'x = """a"b"""\n'),
  ("single str backslash newline", "x = 'a\\\nb'\n"),
  ("single str two backslashes", "x = 'a\\\\'\n"),
  ("raw str backslash quote", 'x = r"a\\"b"\n'),
  ("single str embedded quote", "x = 'a'b'\n"),
  ("triple str 4 quotes", 'x = """"\n'),
  ("triple str 5 quotes", 'x = """""\n'),
  ("fstring two fields no sep", 'x = f"{a}{b}"\n'),
  ("fstring field with dict", 'x = f"{ {\'a\': 1} }"\n'),
  ("fstring fmt in fmt", 'x = f"{a:{w}{w}}"\n'),
  ("fstring nested triple", "x = f\"\"\"{f'''{a}'''}\"\"\"\n"),
  ("fstring conversion only", 'x = f"{a!r:{w}}"\n'),
  ("number 09", 'a = 09\n'),
  ("number 0_1", 'a = 0_1\n'),
  ("number 0x", 'a = 0x\n'),
  ("number 1e", 'a = 1e\n'),
  ("number 1e+5", 'a = 1e+5\n'),
  ("number 1_e5", 'a = 1_e5\n'),
  ("number 1.5j", 'a = 1.5j\n'),
  ("number .5j", 'a = .5j\n'),
  ("number 1.j", 'a = 1.j\n'),
  ("tabs and cr", 'a\t=\t1\r\n'),
]:
  dump(src, label)
