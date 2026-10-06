#!/usr/bin/env python
"""Execute the four NON-bend instruments in SCRATCH and capture rc/stdout/stderr.

Only the four that do not compile bend are executed. Deps that still exist on
disk are copied into the scratch tree at their original relative paths; subjects
that do not exist are named, not fabricated. Read-only on the live tree.
"""
import os, shutil, subprocess

ROOT = subprocess.run(['git', 'rev-parse', '--show-toplevel'],
                      capture_output=True, text=True).stdout.strip()
os.chdir(ROOT)
SC = '.agents/slop/inst13/tree'
PY = os.path.abspath('.venv/bin/python')
NODE = shutil.which('bend')  # placeholder; node resolved below
NODE = shutil.which('node') or 'node'

# 1. copy the dependencies that still exist into the scratch tree
DEPS = [
    '.agents/slop/rebase-gate.py',
    '.agents/slop/cstyle-gate.py',
    '.agents/slop/rebase-gate-selftest.py',
]
for d in DEPS:
    if os.path.exists(d):
        shutil.copy(d, os.path.join(SC, d))
        print('dep copied ', d)
    else:
        print('dep MISSING', d)
# whole xd2 dir (e2e_gpu_probe imports cdp.mjs + serve.mjs)
if os.path.isdir('.agents/slop/xd2'):
    shutil.copytree('.agents/slop/xd2', os.path.join(SC, '.agents/slop/xd2'),
                    dirs_exist_ok=True)
    print('xd2 copied')

# 2. symlink the live .bend tree + bin so walking instruments see real subjects
for link, target in (('tinybendygrad', os.path.abspath('tinybendygrad')),
                     ('bin', os.path.abspath('bin'))):
    p = os.path.join(SC, link)
    if not os.path.exists(p):
        os.symlink(target, p)
        print('symlinked', link, '->', target)


def run(label, argv, cwd=None, timeout=180):
    print(f'\n######## {label}\n$ {" ".join(argv)}')
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout,
                           cwd=cwd)
        rc, out, err = p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired as e:
        rc, out, err = 'TIMEOUT', e.stdout or '', e.stderr or ''
    print(f'--- rc={rc}')
    print('--- stdout ---'); print(out[-4000:] if isinstance(out, str) else out)
    print('--- stderr ---'); print(err[-4000:] if isinstance(err, str) else err)
    return rc, out, err


# 3. execute
run('substrate-audit.py', [PY, os.path.join(SC, '.agents/slop/substrate-audit.py')])
run('cstyle-shapes-selftest.py', [PY, os.path.join(SC, '.agents/slop/cstyle-shapes-selftest.py')])
run('pin-tables.py (bare)', [PY, os.path.join(SC, '.agents/slop/pin-tables.py')])
run('pin-tables.py --out scratch', [PY, os.path.join(SC, '.agents/slop/pin-tables.py'),
                                    '--out', '/tmp/pins'])
run('e2e_gpu_probe.mjs', [NODE, os.path.join(SC, '.agents/slop/e2e_gpu_probe.mjs')],
    timeout=150)
