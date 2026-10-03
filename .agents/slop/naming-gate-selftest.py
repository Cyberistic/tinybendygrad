#!/usr/bin/env python3
"""THE NAMING GATE'S OWN TEST. A gate never seen red is not known to work.

    python3 .agents/slop/naming-gate-selftest.py

It copies `tinygrad/` and `tinybendygrad/` into a scratch mirror, runs the real
gate there, and plants REAL divergences. Nothing is mocked: the detector reads
the same Python and the same Bend in every case, so a planted rename exercises
the production path end to end.

Five cases, and the order matters -- each one mutates the mirror the previous
case left behind, and the FINAL case restores the original, which is also the
no-op control:

  1 CLEAN          must PASS. If the committed tree is not clean, nothing below
                   means anything.
  2 NO-OP CONTROL  two consecutive runs byte-identical. Catches locale
                   collation and set-iteration order leaking into the output --
                   `sort`/`comm` are locale-colating HERE and fabricate diffs
                   even on a no-op, which is why only a no-op control exposes it.
  3 PLANTED RENAME a VERBATIM port def gets a `pfx_` prefix. MUST FAIL, and the
                   failure must NAME that def: a gate that goes red without
                   saying why is not a gate either.
  4 BLANK REASON   a ledger line with no reason. MUST FAIL. An unreviewed
                   exemption is not an exemption.
  5 STALE AMNESTY  a ledger line for a candidate that no longer exists. MUST
                   FAIL. Stale amnesty is unearned amnesty.
  6 RESTORED       back to the clean tree. MUST PASS again, and must match
                   case 2 byte for byte.
  7 ABSENT IS SAFE an upstream name with no port counterpart must NOT fail the
                   gate. This is the case that keeps the gate from becoming a
                   churn machine: unported code is not a naming violation.
"""
import filecmp
import os
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
MIRROR_PARENT = tempfile.mkdtemp(prefix='naming-gate-selftest.')

# A def that is VERBATIM today, so planting a rename on it is a pure rename.
# `codegen/gpudims.py` is used because it is small, has a sibling .bend, and is
# not in the do-not-edit list, so the mirror's copy is safe to mutate.
PLANT_FILE = 'tinybendygrad/codegen/gpudims.bend'
PLANT_MATCH = re.compile(r'^def (pm_group_gpudims)\(', re.M)
PLANT_NEW = 'selftest_group_gpudims'

failures = []


def check(label, ok, detail=''):
    print('  %-4s %s%s' % ('ok' if ok else 'FAIL', label,
                          '' if ok else '\n         ' + detail))
    if not ok:
        failures.append(label)


def run_gate(mirror):
    env = dict(os.environ, LC_ALL='C')
    p = subprocess.run([sys.executable, os.path.join(mirror, '.agents/slop/naming-gate.py')],
                       capture_output=True, text=True, env=env, cwd=mirror)
    return p.returncode, p.stdout + p.stderr


def main():
    mirror = os.path.join(MIRROR_PARENT, 'tree')
    os.makedirs(os.path.join(mirror, '.agents/slop'))
    for d in ('tinygrad', 'tinybendygrad'):
        shutil.copytree(os.path.join(ROOT, d), os.path.join(mirror, d),
                        ignore=shutil.ignore_patterns('__pycache__'))
    shutil.copy(os.path.join(HERE, 'naming-gate.py'),
                os.path.join(mirror, '.agents/slop/naming-gate.py'))
    ledger = os.path.join(HERE, 'naming-gate-baseline.txt')
    ledger_mirror = os.path.join(mirror, '.agents/slop/naming-gate-baseline.txt')
    shutil.copy(ledger, ledger_mirror)

    print('mirror: %s' % mirror)
    original = open(os.path.join(mirror, PLANT_FILE)).read()

    print('\n1 CLEAN TREE')
    code, out = run_gate(mirror)
    check('clean tree PASSES', code == 0 and 'RESULT: PASS' in out,
          'exit=%d\n%s' % (code, out[-600:]))
    check('ABSENT is reported separately from RENAMED',
          'UNPORTED (ABSENT)' in out and 'RENAMED:' in out,
          'the two must not be conflated:\n%s' % out[-600:])
    clean_out = out

    print('\n2 NO-OP CONTROL (two runs must be byte-identical)')
    code2, out2 = run_gate(mirror)
    check('second run is byte-identical', out2 == clean_out and code2 == code,
          'locale collation or set order leaked into the output')

    print('\n3 PLANTED RENAME (%s: %s -> %s)' % (PLANT_FILE, PLANT_MATCH.pattern, PLANT_NEW))
    target = os.path.join(mirror, PLANT_FILE)
    src = open(target).read()
    if not PLANT_MATCH.search(src):
        print('  FAIL   anchor %s not found -- the plant did not apply' % PLANT_MATCH.pattern)
        failures.append('plant anchor missing')
    else:
        open(target, 'w').write(PLANT_MATCH.sub('def %s(' % PLANT_NEW, src, count=1))
        code, out = run_gate(mirror)
        check('planted rename FAILS the gate', code != 0 and 'RESULT: FAIL' in out,
              'exit=%d -- a planted rename must go red\n%s' % (code, out[-600:]))
        check('failure NAMES the planted def', PLANT_NEW in out,
              'a gate that goes red without saying why is not a gate:\n%s' % out[-600:])
        check('failure is reported as a NEW rename', 'NO RULING IN THE LEDGER' in out,
              out[-600:])
    open(target, 'w').write(original)

    print('\n4 BLANK LEDGER REASON (an unreviewed exemption is not an exemption)')
    saved = open(ledger_mirror).read()
    lines = saved.split('\n')
    victim = next(i for i, l in enumerate(lines) if l and not l.startswith('#'))
    fields = lines[victim].split('\t')
    lines[victim] = '\t'.join(fields[:3] + [''])
    open(ledger_mirror, 'w').write('\n'.join(lines))
    code, out = run_gate(mirror)
    check('blank reason FAILS the gate', code != 0 and 'RESULT: FAIL' in out,
          'exit=%d\n%s' % (code, out[-600:]))
    open(ledger_mirror, 'w').write(saved)

    print('\n5 STALE AMNESTY (a ledger line for a candidate that no longer exists)')
    with open(ledger_mirror, 'a') as fh:
        # four fields, because a three-field line is rejected as MALFORMED rather
        # than as stale -- a different failure, and this case tests stale.
        fh.write('codegen/simplify.py\tno_such_upstream_name\tbogus_\tBOGUS\n')
    code, out = run_gate(mirror)
    check('stale ledger line FAILS the gate', code != 0 and 'RESULT: FAIL' in out,
          'exit=%d\n%s' % (code, out[-600:]))
    check('failure says STALE', 'STALE' in out, out[-600:])
    open(ledger_mirror, 'w').write(saved)

    print('\n6 RESTORED (back to clean; must PASS and match case 2 byte for byte)')
    code, out = run_gate(mirror)
    check('restored tree PASSES', code == 0 and 'RESULT: PASS' in out,
          'exit=%d\n%s' % (code, out[-600:]))
    check('restored output identical to the clean run', out == clean_out,
          'the gate is not idempotent')

    print('\n7 AN ABSENT NAME MUST NOT FAIL THE GATE')
    probe = os.path.join(mirror, 'tinybendygrad', 'codegen', 'simplify.bend')
    body = open(probe).read()
    open(probe, 'w').write(body + '\ndef selftest_absent_only_local() -> U32: 0\n')
    code, out = run_gate(mirror)
    check('a port def with no upstream name does NOT fail the gate',
          code == 0 and 'RESULT: PASS' in out,
          'unported/absent code is not a naming violation:\n%s' % out[-600:])
    open(probe, 'w').write(body)

    shutil.rmtree(MIRROR_PARENT, ignore_errors=True)
    print('\n%s' % ('ALL %d CHECKS PASS' % (7 * 2 + 1) if not failures
                    else 'FAILED: %s' % ', '.join(failures)))
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main())