#!/usr/bin/env python3
# Probe: what CPython 3.12's tokenize actually emits for the shapes a hand-rolled
# lexer gets wrong. Not the test; the test is the diff against sz.py.
import token, tokenize, io, sys

def dump(src, label):
  print("=" * 70)
  print(label)
  try:
    for t in tokenize.generate_tokens(io.StringIO(src).readline):
      if t.type in (token.OP, token.NAME, token.NUMBER, token.STRING):
        print("  %-8s %-22r %s %s" % (token.tok_name[t.type], t.string, t.start, t.end))
  except Exception as e:
    print("  RAISED %s: %s" % (type(e).__name__, e))

for label, src in [
  ("fstring plain", 'x = f"a{b}c"\n'),
  ("fstring escaped braces", 'x = f"{{a}} {b} {{"\n'),
  ("fstring conversion", 'x = f"{b!r} {b!s} {b:>{w}}"\n'),
  ("fstring equals", 'x = f"{b=}"\n'),
  ("fstring nested quotes", 'x = f"{d["k"]}"\n'),
  ("fstring nested fstring", 'x = f"{f\'{g}\'}"\n'),
  ("fstring multiline", 'x = f"""\na{b}\nc"""\n'),
  ("fstring backslash expr", 'x = f"{a + \\\n  b}"\n'),
  ("fstring nested braces in spec", 'x = f"{a:{w}.{p}}"\n'),
  ("fstring empty", 'x = f""\n'),
  ("fstring doubled quote", "x = f'{a}'\n"),
  ("docstring", '  """doc\n  more"""\nx = 1\n'),
  ("string with triple later", 'x = """a"""\n'),
  ("assigned triple", 'x = """a"""\n'),
  ("prefixes", "a = rb'x'\nb = BR'x'\nc = rf'x'\nd = fr'x'\ne = b'x'\ng = U'x'\n"),
  ("bad prefix", "a = zr'x'\n"),
  ("numbers", 'a = 1_000\nb = 0x1_f\nc = 1e10\nd = 1_0.5_0\ne = .5\nf = 1.\ng = 1j\nh = 1_0j\ni = 0o17\nj = 0b101\nk = 1e1_0\n'),
  ("name unicode", 'a = caf\u00e9\nb = \u0391\n'),
  ("operators", 'a = a@b\nb = a//b\nc = a->b\nd = a:=b\ne = a**b\nf = ...\ng = a if b else c\n'),
  ("dollar", 'a = $\n'),
  ("unterminated single", "a = 'x\n"),
  ("unterminated triple", 'a = """x\n'),
  ("unterminated single line eof", "a = 'x"),
  ("backslash newline", 'a = 1 + \\\n2\n'),
  ("comment", '# hi\na = 1  # there\n'),
  ("crlf", 'a = 1\r\nb = 2\r\n'),
  ("tab indent", '\ta = 1\n'),
  ("empty", ''),
  ("only comment", '# hi\n'),
  ("no trailing newline", 'a = 1'),
  ("unicode in string", 'a = "\u00e9\u4e2d"\n'),
  ("kwarg string concat", 'a = "x" "y"\n'),
  ("nested fstring braces", 'x = f"{(lambda: 1)()}"\n'),
  ("fstring dict", 'x = f"{ {\'a\':1}[\'a\'] }"\n'),
]:
  dump(src, label)
