#!/usr/bin/env python3
# Probe 4: the error messages, their line numbers, and the f-string spec escapes.
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
  ("unterminated single", 'x = "abc\n'),
  ("unterminated single line 3", 'a\nb\nx = "abc\n'),
  ("unterminated triple", 'x = """abc\n'),
  ("unterminated triple empty", 'x = """\n'),
  ("unterminated single eof", 'x = "abc'),
  ("unterminated fstring", 'x = f"abc\n'),
  ("unterminated fstring eof", 'x = f"abc'),
  ("lone } in ftext", 'x = f"a}b"\n'),
  ("lone } in ftext line 3", 'a\nb\nx = f"}"\n'),
  ("bad cont", 'x = 1 \\ 2\n'),
  ("bad cont eof", 'x = 1 \\'),
  ("nonprintable", 'x = \x01\n'),
  ("fspec backslash d", 'x = f"{a:\\d}"\n'),
  ("fspec backslash quote", 'x = f"{a:\\"}"\n'),
  ("fspec backslash brace", 'x = f"{a:\\{b}}"\n'),
  ("ftext backslash brace", 'x = f"a\\{b}"\n'),
  ("ftext backslash nl", 'x = f"""a\\\nb"""\n'),
  ("ftriple newline", 'x = f"""a\nb"""\n'),
  ("fspec single quote", "x = f\"{a:'}\"\n"),
  ("ftext CR", 'x = f"a\rb"\n'),
  ("fspec CR", 'x = f"{a:\rb}"\n'),
  ("empty file", ''),
  ("no trailing nl", 'x = 1'),
  ("name then quote", 'x=1;"""d"""\n'),
  ("lone cr line", 'x = 1\ry = 2\n'),
  ("lone cr in string", 'x = "a\rb"\n'),
  ("crlf in string", 'x = "a\r\nb"\n'),
  ("cr in comment", 'x = 1 # c\r\ny = 2\n'),
  ("cont crlf", 'x = 1 \\\r\ny = 2\n'),
  ("cont lone cr", 'x = 1 \ry = 2\n'),
  ("0x_1", 'a = 0x_1\n'),
  ("1_abc", 'a = 1_abc\n'),
  ("0b_1", 'a = 0b_1\n'),
  ("<>", 'a = <>\n'),
  ("nonascii ident", 'a = é\n'),
  ("line cont in string tri", 'x = """a\\\nb"""\n'),
  ("esc quote in fstring", 'x = f"a\\"b"\n'),
  ("fstring after dot", 'x = 1.f\n'),
  ("j after j", 'a = 1jj\n'),
  ("e after e", 'a = 1ee\n'),
  ("dot dot dot", 'a = 1...\n'),
  ("dot dot eq", 'a = 1..=2\n'),
  ("arrow", 'a = 1->2\n'),
  ("star star eq", 'a = 1**=2\n'),
  ("lt lt eq", 'a = 1<<=2\n'),
  ("eq eq", 'a = ==2\n'),
  ("lone backslash", 'a = \\\n'),
]:
  run(src, label)
