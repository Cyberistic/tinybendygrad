#!/usr/bin/env python3
"""drift-gate.py -- the generic THREE-LANE gate driver for drift-closing.

Runs, for one port file:
  lane 1  interpreted   ./bin/bend <port>            (--check-only, first line only)
  lane 2  native        ./bin/bend <port> -o -  then ./bin/bend -r
  lane 3  CPython       one or more oracle scripts with DEV=NULL

and diffs whole `name=value` lines, NOT row indices and NOT row names as the
primary key: agent-core.md records that a name-comparing harness reported 0 for
all 30 mutations in one unit and 0 for all 68 in another.

    python3 .agents/slop/drift-gate.py <port.bend> [--oracle o.py ...] [--save name]

--save writes the three row dicts as JSON so a later run can diff two snapshots
by value. This is how "did any row move?" is answered across a re-vendor.

Exits 0 unless a lane FAILED TO RUN. `--check-only` exits 1 even on a clean file
(14 permanently unfilled dtype.bend laws), so the check exit status is NEVER
consulted -- only its first line, which is printed.
"""
import argparse, json, os, pathlib, subprocess, sys, tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
CACHE = pathlib.Path(tempfile.gettempdir()) / 'drift-gate-cache'


def run(cmd, env=None, timeout=1800, **kw):
  return subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT, timeout=timeout,
                        env=env, **kw)


def rows(text):
  out = {}
  for line in text.splitlines():
    if '=' in line:
      k, v = line.split('=', 1)
      out[k] = v
  return out


def interp(port):
  return run(['./bin/bend', str(port)])


def native(port, force):
  """Lane 2. Bend 2.0.34 has NO `-r` option and `-o -` writes nothing: the native
  lane is `bend <port> -o <bin>` and then RUN THE BINARY. hcq2-diff.py's
  lane_native() (as of the drift pass) silently produced zero rows for that
  reason, so "interp vs native byte-identical" could not have been measured by
  it. -o requires a real extension, hence the .bin."""
  CACHE.mkdir(exist_ok=True)
  out, txt = CACHE / f'{port.stem}.native.bin', CACHE / f'{port.stem}.native.txt'
  if force or not (out.exists() and txt.exists()):
    if out.exists():
      out.unlink()
    b = run(['./bin/bend', str(port), '-o', str(out)])
    if b.returncode or not out.exists():
      print('NATIVE BUILD FAILED', b.returncode, b.stderr[-1500:])
      return b
    out.chmod(0o755)
    txt.write_text(run([str(out)]).stdout)
  return type('R', (), {'returncode': 0, 'stdout': txt.read_text(), 'stderr': ''})()


def cpython(oracles, force, stem):
  CACHE.mkdir(exist_ok=True)
  out = CACHE / f'{stem}.cpython.txt'
  if not oracles:
    # MEASURED on a two-row probe port: with no --oracle this wrote an EMPTY
    # cpython.txt, `rows()` gave 0, every disagreement set was empty, and the
    # summary read `== THREE LANES AGREE ==` with exit 0. A run with no
    # authority is not a run with an agreeing authority.
    raise SystemExit('NO ORACLE GIVEN: pass --oracle <script.py>. There is no authority '
                     'in this run, so nothing it prints may be called agreement.')
  if force or not out.exists():
    buf = ''
    env = dict(os.environ, DEV='NULL')
    for o in oracles:
      argv = o.split()
      r = run([sys.executable, argv[0], *argv[1:]], env=env)
      if r.returncode:
        print('ORACLE', pathlib.Path(o).name, 'FAILED rc', r.returncode, r.stderr[-1500:])
        return r
      buf += r.stdout
    if not buf.strip():
      raise SystemExit(f'ORACLE DID NOT RUN: every oracle in {oracles} printed nothing')
    out.write_text(buf)
  return type('R', (), {'returncode': 0, 'stdout': out.read_text(), 'stderr': ''})()


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument('port')
  ap.add_argument('--oracle', action='append', default=[])
  ap.add_argument('--save', default=None)
  ap.add_argument('--cmp', default=None, help='compare against a --save snapshot')
  ap.add_argument('-r', action='store_true', help='rebuild cached native/cpython lanes')
  a = ap.parse_args()

  port = (ROOT / a.port).resolve()
  checks = run(['./bin/bend', str(port), '--check-only'])
  first = checks.stdout.strip().splitlines()
  print('CHECK:', first[0] if first else checks.stderr[:300])
  if 'FAIL' in (first[0] if first else ''):
    for line in checks.stdout.strip().splitlines()[1:]:
      print('   ', line)

  li, ln, lc = interp(port), native(port, a.r), cpython(a.oracle, a.r, port.stem)
  for label, r in (('interpreted', li), ('native', ln), ('cpython', lc)):
    if r.returncode:
      print(f'{label} LANE FAILED rc', r.returncode, r.stderr[-1500:])
      return 1
  I, N, C = rows(li.stdout), rows(ln.stdout), rows(lc.stdout)
  print(f'AUTHORITY: {", ".join(a.oracle)} -- live CPython, DEV=NULL')
  print(f'rows: interpreted={len(I)} native={len(N)} cpython={len(C)}')
  # 0 rows is not 0 disagreements. A lane that printed nothing has not agreed with
  # anything, it has said nothing, and the two read identically in a summary.
  dead = [n for n, v in (('interpreted', I), ('native', N), ('cpython', C)) if not v]
  if dead:
    print('LANE DID NOT RUN (0 rows): ' + ', '.join(dead))
    return 1

  dl = sorted(k for k in set(I) & set(N) if I[k] != N[k])
  dis = sorted(k for k in set(I) & set(C) if I[k] != C[k])
  cmp_n, cmp_ln = len(set(I) & set(C)), len(set(I) & set(N))
  print(f'COMPARED: bend-vs-cpython={cmp_n}  interp-vs-native={cmp_ln}')
  print(f'\nLANE DIFF interp vs native: value-disagreements={len(dl)} '
        f'interp-only={len(set(I)-set(N))} native-only={len(set(N)-set(I))}')
  for k in dl[:30]:
    print(f'  differs {k}: interp={I[k]!r} native={N[k]!r}')
  print(f'\nDISAGREEMENTS bend vs cpython ({len(dis)}):')
  for k in dis[:40]:
    print(f'  {k}: bend={I[k]!r} cpython={C[k]!r}')

  if a.save:
    p = CACHE / f'{a.save}.json'
    p.write_text(json.dumps({'I': I, 'N': N, 'C': C}, indent=0, sort_keys=True))
    print('\nSAVED', p)
  if a.cmp:
    old = json.loads((CACHE / f'{a.cmp}.json').read_text())
    for lane, now in (('I', I), ('N', N), ('C', C)):
      was = old.get(lane, {})
      moved = sorted(k for k in set(was) & set(now) if was[k] != now[k])
      gone, new = sorted(set(was) - set(now)), sorted(set(now) - set(was))
      print(f'\nMOVED vs {a.cmp} lane {lane}: {len(moved)} changed, {len(gone)} gone, {len(new)} new')
      for k in moved:
        print(f'  MOVED {k}: {was[k]!r} -> {now[k]!r}')
      for k in gone:
        print(f'  GONE  {k}={was[k]!r}')
      for k in new:
        print(f'  NEW   {k}={now[k]!r}')
    return 0
  # This is a DRIFT REPORT: it exits 0 on a run that found disagreements, because
  # finding them is the job. What it must never do is print a word that reads as a
  # pass over a comparison it did not make, so the verdict line names the counts.
  print(f'\n== {"THREE LANES AGREE" if not dl and not dis and cmp_n and cmp_ln else "PROBLEMS"} =='
        f'  (compared {cmp_n} vs cpython, {cmp_ln} vs native; '
        f'{len(dl)} + {len(dis)} disagree)')
  return 0


if __name__ == '__main__':
  sys.exit(main())