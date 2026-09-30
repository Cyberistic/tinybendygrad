#!/usr/bin/env python3
# Fuzz + edge cases for the lexer prototype. The differential test against sz.py is
# the gate; this is how the lexer earns the right to be trusted on the gate.
import io, random, sys, token, tokenize

src = open('.agents/slop/notes/sz-lexer-proto.py').read()
src = src[:src.index('if __name__')]
g = {'__name__': 'proto'}
exec(src, g)
WHITE = (token.OP, token.NAME, token.NUMBER, token.STRING)


def run(f, b):
  try: return ('ok', f(b))
  except Exception as e: return ('err', str(e))


def py(data):
  try: return ('ok', g['py_stats'](data))
  except Exception as e: return ('err', str(e))


def bd(data):
  try: return ('ok', g['bend_stats'](data))
  except Exception as e: return ('err', str(e))


# Tokenizer errors the port deliberately does not reproduce: CPython's extra literal
# validation, its non-printable-character check, and the two EOF errors a TRUNCATED
# file raises (bracket depth and a trailing backslash). None of them fires on a file
# that is valid Python, which is the only thing sz.py is ever pointed at.
IGNORABLE = ('unexpected EOF in multi-line statement', 'unexpected character after line '
             'continuation', 'invalid ', 'f-string: single', 'unterminated string literal',
             'unterminated triple', 'EOF in multi-line string', 'unterminated f-string',
             'invalid decimal', 'invalid hexadecimal', 'was never closed', "expected ']'",
             "expected ':'", 'closing parenthesis', 'f-string: expecting', 'closing quote',
             'EOL while scanning', 'EOF while scanning', 'unindent', 'IndentationError',
             'TabError', 'EOF in multi-line statement', 'Detected', 'unmatched')


def cmp(data, why):
  a, b = py(data), bd(data)
  if a == b: return 'ok'
  if a[0] == 'err' and any(s in a[1] for s in IGNORABLE):
    return 'dropped' if b[0] == 'ok' and any(s in b[1] for s in IGNORABLE) else 'py-err-only'
  print("MISMATCH", why, "\n  py ", a, "\n  bend", b, "\n  src", repr(data[:200]))
  return 'BUG'


EDGE = [
  b'', b'\n', b'   ', b'# just a comment\n', b'# no newline', b'x = 1', b'x = 1\n',
  b'  """doc\n  more"""\nx = 1\n', b'"""module doc"""\n', b"'''not a docstring'''\n",
  b'x = "\xc3\xa9\xe4\xb8\xad"\n', b"x = 'caf\xc3\xa9'\n", b'x = "\n', b"x = 'x\n",
  b'x = """x\n', b'x = """x', b'x = f"{a}"\n', b'x = f"{a}{{}}"\n', b'x = f"""{a}"""\n',
  b'x = f"{a:>{w}}"\n', b'x = f"{a!r:>{w}}"\n', b'x = f"{a=}"\n', b'x = f"{a:=1}"\n',
  b'x = f"{d["k"]}"\n', b"x = f\"{d['k']}\"\n", b"x = f\"{f'{g}'}\"\n",
  b'x = f"a\\"b"\n', b'x = f"a\\{b}"\n', b'x = f"}"\n', b"x = f'a\nb'\n",
  b'x = f"{a:{f\'{w}\'}}"\n', b'x = f"{ {1:2} }"\n', b'x = f"{a[b:c]}"\n',
  b'x = f"""__device__ {w[2]} f({a}, {b}){{\n  asm("mma.{M}")\n  "{{{", ".join(x)}}}, {{{", ".join(y)}}}\n"""\n',
  b'a = 1 + \\\n2\n', b'a = 1\r\nb = 2\r\n', b'\ta = 1\n', b'a = 0x1_f\nb = 1_0.5_0\nc = .5\nd = 1.\ne = 1j\nf = 0o17\ng = 0b1\nh = 1e1_0\n',
  b'a = b"x" b"y"\n', b'a = rb"x" c = BR\'y\' d = f"z" e = rf"q"\n',
  b'a = 00\nb = 09\nc = 0_1\nd = 1abc\ne = 0x1g\n', b'a = a...b\nc = a.b\nd = a@=b\ne = a->b\n',
  b'a = $ ? ` ;\n', b'a = "x" "y"\n', b'if x: pass\nelse:\n  pass\n',
  b'x = {**a, "b": 1}\n', b'x: int = 1\ny: Dict[str, int] = {}\n',
  b'async def f():\n  await g()\n', b'x = lambda *a, **k: 0\n', b'@deco\ndef f(): pass\n',
  b'x = """\xe2\x96\x88"""\n', b'\xef\xbb\xbfx = 1\n', b'x = "\xf0\x9f\x98\x80"\n',
  b'x = 1;y = 2\n', b'x = (1 +\n  2)\n', b'x = 1 \\\n', b'x = f"{x=:{w}}"\n',
  b'match x:\n  case 1: pass\n', b'x = 1_000_000\n', b'x = 1.5e-3\ny = 1.5E+3\n',
]

ALPHA = (b'ab_()[]{}:,.=+-*/%<>!@^&|~?\'"#\\\n\t 0189fFrRbBuUxeEjJ')
TOKENS = [b'f"', b'"""', b"'''", b'{', b'}', b'{{', b'}}', b':', b'!r', b'0x1f', b'1.5e3', b'.5', b'1_0',
          b'name', b'\n', b' ', b'#c\n', b'\\\n', b'\\\\', b'"', b"'", b'=', b'[', b']', b'(', b')',
          b',', b'.', b'->', b'==', b'...', b'x', b'0', b'1', b'9', b'_', b'\r\n']


def rnd_bytes(r):
  return bytes(r.choice(ALPHA) for _ in range(r.randint(1, 40)))


def rnd_tokens(r):
  return b''.join(r.choice(TOKENS) for _ in range(r.randint(1, 14)))


if __name__ == '__main__':
  tally = {}
  for d in EDGE:
    r = cmp(d, 'edge')
    tally[r] = tally.get(r, 0) + 1
  print("edge cases", len(EDGE), tally)
  seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
  rounds = int(sys.argv[2]) if len(sys.argv) > 2 else 4000
  for which in (rnd_bytes, rnd_tokens):
    r = random.Random(seed)
    t = {}
    for i in range(rounds):
      res = cmp(r.choice([rnd_bytes, rnd_tokens])(r), '%s#%d' % (which.__name__, i))
      t[res] = t.get(res, 0) + 1
    print(which.__name__, rounds, t)
