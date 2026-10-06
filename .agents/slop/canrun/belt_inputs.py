import importlib.util, pathlib, sys
REPO = pathlib.Path('checks').resolve().parents[0]
SLOP = REPO / '.agents' / 'slop'
for tag, p in (('rebase-gate.py', SLOP/'rebase-gate.py'), ('eq/eq-census2.py', SLOP/'eq'/'eq-census2.py')):
    if not p.is_file():
        print(f'{tag:20} ABSENT -> refuse() rc 3, not a traceback')
        continue
    mod_name = 'probe_' + tag.replace('/', '_').replace('.', '_')
    spec = importlib.util.spec_from_file_location(mod_name, str(p))
    m = importlib.util.module_from_spec(spec); sys.modules[mod_name] = m
    try:
        spec.loader.exec_module(m)
        print(f'{tag:20} LOADS CLEAN -> Answer 2 reached the right file')
    except Exception as e:
        print(f'{tag:20} LOAD RAISED {type(e).__name__}: {e}')
