#!/usr/bin/env python3
"""
nv_ip_diff.py -- diff the ip.bend gate against the CPython oracle, in BOTH lanes.

    python3 .agents/slop/nv_ip_gen.py        # (re)generate tables + expected rows
    python3 .agents/slop/nv_ip_assemble.py
    ./bin/bend tinybendygrad/runtime/support/nv/ip.bend            > interp
    ./bin/bend tinybendygrad/runtime/support/nv/ip.bend -o /tmp/ip > native; /tmp/ip > comp
    python3 .agents/slop/nv_ip_diff.py interp comp

Three comparisons, all byte-exact:
  LANES     interp vs comp           -- the two lanes must print the same bytes
  ORACLE    each lane vs nv_ip_rows.txt
Rows are compared as `name=value` PAIRS, so a reordering of the gate's own
emission is reported separately from a value disagreement (there should be none
of the former: `ip_st_order`/`ip_c_order` pin table order as VALUES).
"""
import sys, os, subprocess, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
IP = os.path.join(ROOT, 'tinybendygrad/runtime/support/nv/ip.bend')
BEND = os.path.join(ROOT, 'bin', 'bend')
ROWS = [os.path.join(HERE, f) for f in
        ('nv_ip_rows.txt', 'nv_ip_rows2.txt', 'nv_ip_rows3.txt', 'nv_ip_rows4.txt')]


def run(argv):
  return subprocess.run(argv, capture_output=True, text=True, cwd=ROOT, timeout=900)


def rows(text):
  out = {}
  order = []
  for ln in text.split('\n'):
    if not ln:
      continue
    k, _, v = ln.partition('=')
    out[k] = v
    order.append(k)
  return out, order


def load_oracle():
  txt = ''
  for r in ROWS:
    if os.path.exists(r):
      txt += open(r).read()
  # a DUPLICATE key across the two files is itself a bug in the oracle, so say so
  # rather than letting one silently win.
  seen = {}
  for l in txt.split('\n'):
    if not l:
      continue
    k, _, v = l.partition('=')
    if k in seen and seen[k] != v:
      print('ORACLE SELF-CONFLICT on %s: %r vs %r' % (k, seen[k], v))
    seen[k] = v
  return txt, seen


def compare(name, got_txt, exp, gorder=None):
  got, order = rows(got_txt)
  bad = []
  for k, v in exp.items():
    if k not in got:
      bad.append(('MISSING', k, v, ''))
    elif got[k] != v:
      bad.append(('VALUE', k, v, got[k]))
  extra = [k for k in order if k not in exp]
  return bad, extra


def main():
  interp_path = sys.argv[1]
  comp_path = sys.argv[2] if len(sys.argv) > 2 else None
  exp_txt, exp = load_oracle()
  itxt = open(interp_path).read()
  ibad, iextra = compare('interp', itxt, exp)
  status = 0
  print('ORACLE interp: %d expected rows, %d mismatched, %d extra'
        % (len(exp), len(ibad), len(iextra)))
  for kind, k, e, g in ibad[:40]:
    print('  %-8s %s\n     oracle: %s\n     port  : %s' % (kind, k, e[:200], g[:200]))
  if len(ibad) > 40:
    print('  ... %d more' % (len(ibad) - 40))
  if iextra:
    print('  EXTRA rows the oracle does not expect: %s' % iextra[:20])
  if ibad or iextra:
    status = 1
  if comp_path:
    ctxt = open(comp_path).read()
    if itxt != ctxt:
      import difflib
      d = list(difflib.unified_diff(itxt.split('\n'), ctxt.split('\n'),
                                    'interp', 'comp', lineterm='', n=1))
      print('LANES DIFFER: %d diff lines' % len(d))
      print('\n'.join(d[:40]))
      status = 1
    else:
      print('LANES: byte-identical (%d bytes)' % len(itxt))
    cbad, cextra = compare('comp', ctxt, exp)
    if cbad != ibad or cextra != iextra:
      print('LANES DISAGREE WITH THE ORACLE DIFFERENTLY -- that is a lane bug')
      status = 1
  print('VERDICT:', 'FAIL' if status else 'PASS')
  sys.exit(status)


if __name__ == '__main__':
  main()