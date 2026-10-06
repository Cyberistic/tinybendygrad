#!/usr/bin/env python3
"""Mutate tinybendygrad/sz.bend one edit at a time and report which fixtures move.

The differential against `sz.py` is the gate; this asks the other question, which
the differential cannot: for each edit, does ANY output change? A row that says
`same` is a row the gate cannot see, and that is the useful half of the table.

It never edits the file. Each mutation is written to a scratch copy next to a
symlink to `tinybendygrad/runtime`, compiled with ./bin/bend, run on the fixtures,
and compared with the unmutated binary's output. The source is only read.

    .venv/bin/python .agents/slop/tools/mutate-sz.py [--quick]

Fixtures, and what each one is for:
  tree   this repo, against .venv/bin/python sz.py -- the whole 129-line table
  edge   the two trees from notes/sz-mktrees.py: empty, comments-only, no trailing
         newline, unicode, f-strings, a .js file, a skipped autogen/assets file
  diff   the two edge trees against each other: one file changed, one added, one
         deleted
  order  15 files ALL TIED at 3 lines and 3.0 tokens/line, so the stable sort on
         -lines prints os.walk's order verbatim and any permutation is visible
         (that is the tie the C comment in runtime/sz.c warns about)
"""
import os, shutil, subprocess, sys, tempfile

R = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(
    os.path.abspath(__file__)))))
SRC = R + '/tinybendygrad/sz.bend'
SCRATCH = '/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/mut'
QUICK = '--quick' in sys.argv

# (name, one-line what it breaks, pattern, replacement)
MUTATIONS = [
    ('join: dirs before files', 'os.walk yields files first',
     'List.append(&2, It, a, List.append(&2, It, b, rest))',
     'List.append(&2, It, b, List.append(&2, It, a, rest))'),
    ('join: the rest of the walk is dropped', 'the outer todo is lost',
     'List.append(&2, It, a, List.append(&2, It, b, rest))',
     'List.append(&2, It, a, b)'),
    ('item: a directory is a file', 'readdir order beats is_dir',
     'Bool.pick(IO((List<&2, It> & List<&2, It>)), U32.is_zero(i),',
     'Bool.pick(IO((List<&2, It> & List<&2, It>)), U32.is_eq(i, 1),'),
    ('counted: the skip test is gone', 'autogen and assets are counted',
     'Bool.not(skip(name)))', 'Bool.not(False{}))'),
    ('rows: no line_count > 0 test', 'an empty file becomes a row',
     'Bool.pick(List<&2, Row>, U32.is_gt(Row.lines(rr), 0),',
     'Bool.pick(List<&2, Row>, U32.is_ge(Row.lines(rr), 0),'),
    ('rows: printed with the full path', 'sz.py prints os.path.relpath',
     'sz.lane(is_js(fu), s, rel)', 'sz.lane(is_js(fu), s, fu)'),
    ('root: the walk starts at base', 'sz.py walks base/tinygrad',
     'D{base ++ "/tinygrad", "tinygrad"}', 'D{base, "tinygrad"}'),
    ('fuel: 16777216 steps -> 400', 'below the 289 steps this tree takes',
     'walk(16777216n, Nil{}, ', 'walk(400n, Nil{}, '),
    ('fuel: 16777216 steps -> 100', 'the bound, where it bites',
     'walk(16777216n, Nil{}, ', 'walk(100n, Nil{}, '),
]


def fixtures(tmp):
  """Build the fixtures under tmp and return [(label, [argv...], py-check)]."""
  mk = os.path.join(R, '.agents/slop/notes/sz-mktrees.py')
  src = open(mk).read().replace("'/tmp/szbase1'", repr(os.path.join(tmp, 'a'))
                                ).replace("'/tmp/szbase2'", repr(os.path.join(tmp, 'b')))
  p = os.path.join(tmp, 'mk.py')
  open(p, 'w').write(src)
  subprocess.run([R + '/.venv/bin/python', p], check=True, cwd=R, capture_output=True)
  o = os.path.join(tmp, 'order', 'tinygrad')
  for d in ('adir', 'adir/inner', 'bdir', 'runtime/autogen', 'viz/assets', 'xdir.py'):
    os.makedirs(os.path.join(o, d), exist_ok=True)
  for n in ('e1', 'e2', 'e3', 'e4', 'e5'):
    open('%s/%s.py' % (o, n), 'w').write('a=1\nb=2\nc=3\n')
  for n in ('g1', 'g2', 'g3', 'other'):
    open('%s/adir/%s.py' % (o, n), 'w').write('d=4\ne=5\nf=6\n')
  for n in ('i1', 'i2'):
    open('%s/bdir/%s.py' % (o, n), 'w').write('g=7\nh=8\ni=9\n')
  open('%s/adir/inner/deep.py' % o, 'w').write('j=1\nk=2\nl=3\n')
  open('%s/runtime/autogen/s.py' % o, 'w').write('z=1\ny=2\n')
  open('%s/viz/assets/s.js' % o, 'w').write('z=1\ny=2\n')
  open('%s/ignored.txt' % o, 'w').write('nope\n')
  open('%s/xdir.py/inside.py' % o, 'w').write('p=1\nq=2\nr=3\n')
  return [('tree', ['.'], True), ('edge', [os.path.join(tmp, 'a')], True),
          ('diff', [os.path.join(tmp, 'a'), os.path.join(tmp, 'b')], True),
          ('order', [os.path.join(tmp, 'order')], True)]


def build(src, out):
  d = tempfile.mkdtemp(dir=SCRATCH)
  f = d + '/sz.bend'
  open(f, 'w').write(src)
  os.symlink(R + '/tinybendygrad/runtime', d + '/runtime')
  r = subprocess.run([R + '/bin/bend', f, '-o', out], capture_output=True, text=True, cwd=R)
  shutil.rmtree(d, ignore_errors=True)
  return r.returncode, (r.stderr or r.stdout).strip().split('\n')[-1][:60]


def run(binary, args):
  p = subprocess.run([binary] + args, capture_output=True, text=True, cwd=R, timeout=1800)
  return p.returncode, p.stdout, p.stderr.strip().split('\n')[-1] if p.stderr.strip() else ''


def py(args):
  p = subprocess.run([R + '/.venv/bin/python', 'sz.py'] + args,
                     capture_output=True, text=True, cwd=R, timeout=1800)
  return p.returncode, '\n'.join(l for l in p.stdout.split('\n')
                                 if not l.startswith('        ops:')
                                 and not l.startswith('      flags:'))


def main():
  os.makedirs(SCRATCH, exist_ok=True)
  tmp = tempfile.mkdtemp(dir=SCRATCH)
  fix = fixtures(tmp)
  base = SCRATCH + '/sz-base'
  src = open(SRC).read()
  rc, err = build(src, base)
  assert rc == 0, 'the unmutated file does not compile: ' + err
  want = {lbl: py(a) for lbl, a, _ in fix}
  got0 = {}
  for lbl, a, _ in fix:
    r = run(base, a)
    got0[lbl] = r
    same = r[:2] == want[lbl]
    print('%-6s exit %d  %3d lines  vs sz.py: %s' % (lbl, r[0], len(r[1].split('\n')), 'same' if same else 'DIFFERS'))
    assert same, 'the unmutated binary disagrees with sz.py on ' + lbl
  print('\n%-40s %s' % ('mutation', '  '.join('%-8s' % l for l, _, _ in fix)))
  for name, _, pat, rep in (MUTATIONS[:1] if QUICK else MUTATIONS):
    if pat not in src:
      print('%-40s PATTERN GONE' % name)
      continue
    out = SCRATCH + '/sz-mut'
    rc, err = build(src.replace(pat, rep), out)
    if rc != 0:
      print('%-40s DOES NOT COMPILE (%s)' % (name, err))
      continue
    cells = []
    for lbl, a, _ in fix:
      g = run(out, a)
      b = got0[lbl]
      if g[:2] == b[:2]:
        cells.append('same')
      elif g[0] != b[0]:
        cells.append('exit%d' % g[0])
      else:
        bl, gl = b[1].split('\n'), g[1].split('\n')
        d = sum(1 for x, y in zip(bl + [''] * 40, gl + [''] * 40) if x != y)
        cells.append('%d rows' % min(d, 9))
    print('%-40s %s' % (name, '  '.join('%-8s' % c for c in cells)))
  shutil.rmtree(tmp, ignore_errors=True)


main()
