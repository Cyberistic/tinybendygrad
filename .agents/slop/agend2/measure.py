#!/usr/bin/env python
"""Re-measure every measured claim AGENTS.md carries. Read-only. No bend."""
import os, re, subprocess, json, sys, glob
ROOT = subprocess.run(['git','rev-parse','--show-toplevel'],capture_output=True,text=True).stdout.strip()
os.chdir(ROOT)

def run(cmd):
    p = subprocess.run(cmd, shell=True, capture_output=True, text=True)
    return p.returncode, p.stdout, p.stderr

def read(p):
    try:
        return open(p, encoding='utf-8', errors='replace').read()
    except FileNotFoundError:
        return None

def lines(p):
    t = read(p)
    return None if t is None else len(t.splitlines())

def grepcount(pattern, p, fixed=False):
    t = read(p)
    if t is None: return None
    if fixed:
        return t.count(pattern)
    return len(re.findall(pattern, t))

R = {}
def rec(k, v): R[k] = v

# --- timestamps ---
rc, out, _ = run("date '+%Y-%m-%dT%H:%M:%S%z'")
rec('now', out.strip())
rc, out, _ = run('git rev-parse --short HEAD'); rec('head', out.strip())

# --- .txt (no-txt.py) ---
t = read('.agents/slop/agend2/notxt.out')
m = re.search(r'(\d+) \.txt FILE\(S\)', t)
rec('notxt_hard', int(m.group(1)) if m else None)
m = re.search(r'(\d+) `\.txt` EXCUSED', t)
rec('notxt_excused', int(m.group(1)) if m else None)
m = re.search(r'and (\d+) more', t)
rec('notxt_sampled_then_more', int(m.group(1)) if m else None)
# how many printed
rec('notxt_printed_rows', sum(1 for l in t.splitlines() if l.startswith('    ') and not l.strip().startswith('...')))

# --- declared() ---
sys.path.insert(0, 'checks')
try:
    import differ
    rec('differ_declared', len(differ.declared()))
except Exception as e:
    rec('differ_declared_err', repr(e))

# .txt in runs/graphcmp/D
rec('graphcmp_txt_on_disk', len(glob.glob('runs/graphcmp/D/*.txt')))
rec('graphcmp_D_exists', os.path.isdir('runs/graphcmp/D'))

# --- 103 stale citation witnesses ---
for f, lo, hi in [('checks/README.md', 51, 58), ('checks/no-txt.py', 19, 30)]:
    ls = (read(f) or '').splitlines()
    seg = ls[lo-1:hi]
    nums = re.findall(r'\b(103|139)\b', '\n'.join(seg))
    rec(f'{f}:{lo}-{hi}_103or139', nums)

# --- oracles ---
rec('oracles_rows', len(glob.glob('oracles/**/*.rows', recursive=True)))
rec('oracles_txt', glob.glob('oracles/**/*.txt', recursive=True))

# --- TOOLS.md extractor output ---
t = read('.agents/slop/agend2/tools.out') or ''
def gv(label):
    m = re.search(re.escape(label)+r':\s*(\d+)', t)
    return int(m.group(1)) if m else None
for lbl in ['distinct paths','present','absent','absent instruments','absent oracles',
            'absent under .agents/slop/','total lines','lines naming >=1 path']:
    rec('tools_'+lbl.replace(' ','_'), gv(lbl))

# --- ruff ---
rc, out, err = run('/opt/homebrew/bin/ruff check . 2>&1 | tail -2')
rec('ruff_tail', out.strip())
m = re.search(r'Found (\d+) errors', out)
rec('ruff_count', int(m.group(1)) if m else None)
rc, out, err = run('/opt/homebrew/bin/ruff --version'); rec('ruff_version', out.strip())

# --- files / lines ---
rec('viz_readme_lines', lines('tinygrad/viz/README.md'))
rec('substrate_py_lines', lines('checks/substrate.py'))
rec('substrate_check_sh_lines', lines('checks/substrate-check.sh'))
rec('docs_env_vars_exists', os.path.exists('docs/env_vars.md'))
rec('gatekit_py_lines', lines('gates/gatekit.py'))
rec('run_port_mm_sh_exists', os.path.exists('checks/run-port-mm.sh'))

# --- gates/*.py vs *.sh ---
rec('gates_py', len(glob.glob('gates/*.py')))
rec('gates_sh', len(glob.glob('gates/*.sh')))
rec('gates_oracles_sh', len(glob.glob('gates/oracles/*.sh')))
rec('checks_sh', len(glob.glob('checks/*.sh')))

# --- PCIDevice ---
rc, out, _ = run("rg -l 'PCIDevice' tinygrad/ | wc -l"); rec('pcidevice_files', out.strip())
rc, out, _ = run("rg -n 'class PCIDevice' tinygrad/runtime/support/system.py"); rec('pcidevice_class_line', out.strip())
rc, out, _ = run("rg -n 'class PCIIface\\(PCIIfaceBase\\)' tinygrad/runtime/ops_amd.py tinygrad/runtime/ops_nv.py"); rec('pciiface_lines', out.strip())

# --- deleted/kept fixtures ---
for p in ['.agents/slop/xd2/cdp.mjs', '.agents/slop/ops_bend-milestone-expected.txt',
          '.agents/slop/cstyle-live/port.txt', '.agents/slop/schedule-bodies/BEFORE-rows.txt',
          '.agents/slop/e2estage8/verdicts.py', '.agents/slop/diffpy/oracle-run.sh',
          '.agents/slop/diffpy/oracle-repro.sh', 'gates/cstyle-live.rows',
          '.agents/slop/oracle_py.py', '.agents/slop/zero-classify.py',
          '.agents/slop/rebase-gate-selftest.py', '.agents/slop/agend/REPORT.md',
          '.agents/slop/toolsledger/extract.py']:
    rec('exists_'+p, os.path.exists(p))

# --- sb-gate.sh ---
rec('sbgate_SKIP_count', grepcount(r'SKIP', 'checks/sb-gate.sh'))
rec('sbgate_gatekit_count', grepcount(r'gatekit', 'checks/sb-gate.sh'))
rec('sbgate_lines', lines('checks/sb-gate.sh'))

# --- mutate/selftest harnesses in .agents/slop ---
rec('mutate_py', len(glob.glob('.agents/slop/**/*-mutate.py', recursive=True)))
rec('selftest_py', len(glob.glob('.agents/slop/**/*-selftest.py', recursive=True)))

# --- uv.lock packages ---
t = read('uv.lock')
rec('uvlock_name_lines', len(re.findall(r'^name = ', t, re.M)) if t else None)

# --- python versions ---
rc, out, _ = run('.venv/bin/python -VV'); rec('venv_py', out.strip())
rc, out, _ = run('python3 -VV'); rec('path_py3', out.strip())
for mod in ['pytest','mypy','ruff']:
    rc, out, err = run(f'.venv/bin/python -m {mod} --version 2>&1'); rec(f'venv_{mod}', (out+err).strip()[:60])

# --- LAWS/PROOF TODO counts (grep, not bend) ---
rec('laws_todo', grepcount(r'TODO', 'tinybendygrad/LAWS.bend'))
rec('proof_todo', grepcount(r'TODO', 'tinybendygrad/PROOF.bend'))

# --- references / readme ---
rec('references_exists', os.path.exists('references'))
rec('gitignore_has_references', bool(re.search(r'references', read('.gitignore') or '')))
rec('readme_mentions_references', 'references' in (read('README.md') or ''))

# --- ad117c928 ---
rc, out, _ = run("git log -1 --format='%an|%ad|%s' ad117c928"); rec('ad117_meta', out.strip())
rc, out, _ = run("git diff-tree --no-commit-id --name-only -r ad117c928 | wc -l"); rec('ad117_files', out.strip())
rc, out, _ = run("git merge-base --is-ancestor ad117c928 HEAD && echo YES || echo NO"); rec('ad117_ancestor', out.strip())
rc, out, _ = run("git show 'ad117c928^:tinygrad/uop/ops.py' | sed -n '1398p;1404p'"); rec('pin_ops_1398_1404', out.rstrip())
rc, out, _ = run("git rev-parse --verify 46c52f30d^{commit} 2>&1 | head -1"); rec('46c52f30d', out.strip())

# --- e2e.py return 4 line ---
ls = (read('checks/e2e.py') or '').splitlines()
rec('e2e_return4_lines', [i+1 for i,l in enumerate(ls) if l.strip()=='return 4'])
ls = (read('checks/e2e.sh') or '').splitlines()
rec('e2esh_exit4_lines', [i+1 for i,l in enumerate(ls) if 'exit 4' in l])

# --- hosted shims ---
rec('graphcmp_run_sh_root', os.path.exists('graphcmp-run.sh'))
rec('graphcmp_run_sh_slop', os.path.exists('.agents/slop/graphcmp-run.sh'))
rec('graphcmp_repro_sh_slop', os.path.exists('.agents/slop/graphcmp-repro.sh'))

# --- peakrss census ---
rec('peakrss_census_exists', os.path.exists('.agents/slop/peakrss/census.txt'))
rec('substrate_md_exists', os.path.exists('.agents/slop/substrate/SUBSTRATE.md'))
rec('peakrss_md_exists', os.path.exists('.agents/slop/PEAKRSS.md'))

# --- no-txt.py and txrowners ---
rc, out, _ = run('.venv/bin/python checks/no-txt.py 2>&1 | tail -1'); rec('notxt_lastline', out.strip())

# --- corpus-figure DEV behaviour (needs no bend? it must not compile) skip run; read run_health ---
t = read('checks/corpus-figure.py') or ''
rec('corpusfigure_reads_selfcheck', 'oracle-selfcheck' in t)
rec('corpusfigure_reads_census_rc', 'census-rc' in t)
rec('corpusfigure_reads_agree', 'graphs-agree' in t)
rec('corpusfigure_line137', (t.splitlines()[136] if len(t.splitlines())>=137 else None))

# --- gates-pop HOMES ---
t = read('gates/gates-pop.py') or ''
rec('gatespop_line95', (t.splitlines()[94] if len(t.splitlines())>=95 else None))

# --- sweep LIVE_UNITS line 266, ORACLE_WORD 658 ---
t = read('checks/sweep.py') or ''
sl = t.splitlines()
rec('sweep_266', sl[265] if len(sl)>=266 else None)
rec('sweep_658', sl[657] if len(sl)>=658 else None)

# --- repro-paths REF ---
t = read('checks/repro-paths.py') or ''
sl = t.splitlines()
rec('repropaths_57', sl[56] if len(sl)>=57 else None)

print(json.dumps(R, indent=1, default=str))
open('.agents/slop/agend2/measured.json','w').write(json.dumps(R, indent=1, default=str))
