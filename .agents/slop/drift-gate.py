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

Exits 0 unless a lane FAILED TO RUN.

⚠ THE `CACHE` IS KEYED ON THE PORT'S sha256, MEASURED 2026-10-04, and it used not to be.
`native()` and `cpython()` returned `$TMPDIR/drift-gate-cache/<stem>.{native.txt,cpython.txt}`
whenever those files existed and `-r` was absent -- so a default run compared the live port's
stdout against rows a DIFFERENT REVISION produced, and the verdict described neither. A memoized
answer is measured by its cache; here the cache was not even invalidated when the thing being
cached changed. The key is now the port's own digest, so a stale entry is unreachable rather than
merely unfashioned, and every served-from-cache lane says so on stdout. `--no-cache` forces a
live run; `-r` also rebuilds.

⚠ `--check-only`'s EXIT STATUS IS NEVER CONSULTED and its first line is printed. What this
docstring used to say -- "exits 1 even on a clean file" -- is true for 14 of the 136 `.bend`
files and false for the other 122; see the corrected table in agent-core.md's TRAPS section,
which lists all 14 by name and splits the 6 that also exit 1 when RUN from the 8 that do not.
"""
import argparse, hashlib, json, os, pathlib, subprocess, sys, tempfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
CACHE = pathlib.Path(tempfile.gettempdir()) / 'drift-gate-cache'
sys.path.insert(0, str(HERE))
import oracle_py                                            # noqa: E402


def port_key(port):
  """The cache key: the PORT'S OWN sha256. A key on the filename cannot distinguish two
  revisions of the same file, which is the whole defect this replaced."""
  return hashlib.sha256(port.read_bytes()).hexdigest()[:16]


def cached(name, build):
  """(returncode, stdout, stderr, served_from_cache). `build` runs only on a miss, so the
  digest below is a statement about the port this run actually compiled, not about a port from
  an earlier session. SERVED-FROM-CACHE IS RETURNED AND PRINTED: a reader must be able to tell
  a live lane from a replayed one without reading the cache directory."""
  path = CACHE / name
  if path.exists():
    return 0, path.read_text(), '', True
  text = build()
  path.write_text(text)
  return 0, text, '', False


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


def native(port, force, key):
  """Lane 2. Bend 2.0.34 has NO `-r` option and `-o -` writes nothing: the native
  lane is `bend <port> -o <bin>` and then RUN THE BINARY. hcq2-diff.py's
  lane_native() (as of the drift pass) silently produced zero rows for that
  reason, so "interp vs native byte-identical" could not have been measured by
  it. -o requires a real extension, hence the .bin.

  The cache FILE is named from `key`, the port's digest. A rebuild that finds its own output
  missing therefore happens, and a cache from another revision is never read."""
  CACHE.mkdir(exist_ok=True)

  def build():
    out = CACHE / f'{port.stem}.{key}.native.bin'
    if out.exists():
      out.unlink()
    b = run(['./bin/bend', str(port), '-o', str(out)])
    if b.returncode or not out.exists():
      raise SystemExit(f'NATIVE BUILD FAILED rc={b.returncode}\n{b.stderr[-1500:]}')
    out.chmod(0o755)
    return run([str(out)]).stdout

  if force:
    (CACHE / f'{port.stem}.{key}.native.txt').unlink(missing_ok=True)
  return cached(f'{port.stem}.{key}.native.txt', build)


def cpython(oracles, force, stem, key, exe):
  CACHE.mkdir(exist_ok=True)
  if not oracles:
    # MEASURED on a two-row probe port: with no --oracle this wrote an EMPTY
    # cpython.txt, `rows()` gave 0, every disagreement set was empty, and the
    # summary read `== THREE LANES AGREE ==` with exit 0. A run with no
    # authority is not a run with an agreeing authority.
    raise SystemExit('NO ORACLE GIVEN: pass --oracle <script.py>. There is no authority '
                     'in this run, so nothing it prints may be called agreement.')

  def build():
    buf = ''
    env = dict(os.environ, DEV='NULL')
    for o in oracles:
      argv = o.split()
      r = run([exe, argv[0], *argv[1:]], env=env)
      if r.returncode:
        raise SystemExit(f'ORACLE {pathlib.Path(o).name} FAILED rc={r.returncode}\n'
                         f'{r.stderr[-1500:]}')
      buf += r.stdout
    if not buf.strip():
      raise SystemExit(f'ORACLE DID NOT RUN: every oracle in {oracles} printed nothing')
    return buf

  if force:
    (CACHE / f'{stem}.{key}.cpython.txt').unlink(missing_ok=True)
  return cached(f'{stem}.{key}.cpython.txt', build)


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument('port')
  ap.add_argument('--oracle', action='append', default=[])
  ap.add_argument('--save', default=None)
  ap.add_argument('--cmp', default=None, help='compare against a --save snapshot')
  ap.add_argument('-r', action='store_true', help='rebuild cached native/cpython lanes')
  ap.add_argument('--no-cache', action='store_true',
                  help='run every lane live and write no cache entry (the default is keyed on '
                       'the port sha256, so a stale read cannot happen; this makes it visible)')
  a = ap.parse_args()

  port = (ROOT / a.port).resolve()
  key = port_key(port)
  checks = run(['./bin/bend', str(port), '--check-only'])
  first = checks.stdout.strip().splitlines()
  print('CHECK:', first[0] if first else checks.stderr[:300])
  if 'FAIL' in (first[0] if first else ''):
    for line in checks.stdout.strip().splitlines()[1:]:
      print('   ', line)

  # L-11, INHERITED: `oracle_py.resolve()` refuses -- exit 2 -- when the interpreter resolves
  # `tinygrad` to a tree other than this repo's, which is what a `.venv` copied out of the tree
  # does. This harness used `sys.executable`, so its CPython lane's authority depended on the
  # LAUNCHER, the same defect `oracle_py.py` was written to end.
  exe, tinygrad_path, version = oracle_py.resolve()
  print('AUTHORITY INTERPRETER:', oracle_py.line(exe, tinygrad_path, version))
  print(f'CACHE KEY: port sha256 {key} -- an entry from another revision is unreachable')
  force = a.r or a.no_cache

  li = interp(port)
  ln = native(port, force, key)
  lc = cpython(a.oracle, force, port.stem, key, exe)
  for label, (rc, out, err, served) in (('interpreted', (li.returncode, li.stdout, li.stderr,
                                                           False)),
                                        ('native', ln), ('cpython', lc)):
    if rc:
      print(f'{label} LANE FAILED rc', rc, err[-1500:])
      return 1
    print(f'{label} LANE: {"served from cache " + key if served else "ran LIVE"}')
  I, N, C = rows(li.stdout), rows(ln[1]), rows(lc[1])
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