#!/usr/bin/env python3
# Build the two trees the diff-mode differential test walks: the edge cases sz.py has
# to survive, then a second tree that changes, adds and deletes files.
import os, shutil, sys

A = '/tmp/szbase1'
B = '/tmp/szbase2'


def put(root, rel, data):
  p = os.path.join(root, rel)
  os.makedirs(os.path.dirname(p), exist_ok=True)
  open(p, 'wb').write(data)


for root in (A, B):
  shutil.rmtree(root, ignore_errors=True)

FILES = {
  'tinygrad/empty.py': b'',
  'tinygrad/comments.py': b'# nothing but a comment\n# and another\n',
  'tinygrad/nonl.py': b'x = 1',
  'tinygrad/unicode.py': b'# caf\xc3\xa9 \xe2\x96\x88\nx = "caf\xc3\xa9"\ny = 1\n',
  'tinygrad/deep/nested/mod.py': b'def f(x):\n  """doc\n  more"""\n  return x + 1\n',
  'tinygrad/deep/nested/tiny.py': b'x=1\n',
  'tinygrad/index.js': b'// a comment\nconst a = 1;\n\nfunction f( ) {\n  return 2;\n}\n',
  'tinygrad/runtime/autogen/skipped.py': b'x = 1\ny = 2\n',
  'tinygrad/viz/assets/skipped.js': b'var x = 1\n',
  'tinygrad/notpython.txt': b'ignored\n',
  'tinygrad/fstrings.py': (
    b'x = f"a{b}c"\n'
    b'y = f"{a:{w}.{p}}"\n'
    b'z = f"""__device__ {w[2]} f({a}, {b}){{\n'
    b'  asm("mma.{M}")\n'
    b'  "{{{", ".join(x)}}}, {{{", ".join(y)}}}\n'
    b'"""\n'
    b'w = f"{d[\'k\']} {g!r:>8} {h=}"\n'
    b'numbers = [0x1_f, 1_000, 1.5e3, .5, 10j]\n'
    b'ops = a@b // c ** d -> e\n'),
  'tinygrad/twenty.py': b'# ' + b'x' * 40 + b'\ny = 2 + 3 + 4 + 5\nz = 6\n',
}
for rel, data in FILES.items():
  put(A, rel, data)

# B: same but a few files differ, one is added, one is deleted
for rel, data in FILES.items():
  put(B, rel, data)
put(B, 'tinygrad/twenty.py', b'# ' + b'x' * 40 + b'\ny = 2 + 3 + 4 + 5\nz = 6\nw = 7\n')
put(B, 'tinygrad/added.py', b'x = 1\ny = 2\n')
os.remove(os.path.join(B, 'tinygrad/comments.py'))
put(B, 'tinygrad/deep/nested/mod.py',
    b'def f(x):\n  """doc"""\n  return x + 1\n')
print("built", A, B)
