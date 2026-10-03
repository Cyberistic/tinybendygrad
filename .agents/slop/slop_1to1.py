#!/usr/bin/env python3
"""THE 1:1 AUDIT, the owner's ruling made executable.

ONE `.bend` per upstream `.py`, AT THE SAME PATH. This counts the violations and says
which kind each one is, so the number in a report is reproducible instead of quoted.

    python3 .agents/slop/slop_1to1.py
    python3 .agents/slop/slop_1to1.py --names    # also the def-name correspondence

`runtime/autogen/` is EXCLUDED and that is a decision worth stating: it is ~150k lines
of vendored ctypes bindings, `runtime/support/autogen.bend` exists, and no unit has
ever been asked to port `amd_gpu.py` line by line. `llm/` and `viz/` are excluded for
the same reason -- neither has a `.bend` tree and both are tools, not the library.
"""
import os, re, sys

EXCLUDE_DIRS  = {'__pycache__', 'reference', '.git'}
EXCLUDE_PATH  = ('runtime/autogen', 'llm', 'viz')

def core_py():
    out = []
    for root, dirs, files in os.walk('tinygrad'):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS]
        rel = os.path.relpath(root, 'tinygrad').replace(os.sep, '/')
        if rel == '.': rel = ''
        if any(rel == e or rel.startswith(e + '/') for e in EXCLUDE_PATH): continue
        for f in files:
            if f.endswith('.py'): out.append(rel + '/' + f)
    return sorted(out)

def nlines(p): return len(open(p).read().split('\n')) - 1
def bend_for(rel): return 'tinybendygrad/' + rel[:-3] + '.bend'

def top_level_defs(path):
    """every top-level `def`/`class`, plus every top-level `NAME = ...` binding

    GC4, MEASURED HERE, NOT ASSUMED. This used to match only
    `^(?:async\\s+)?(?:def|class)`, which is a regex over column 0 -- and
    upstream binds essentially every rewrite table by ASSIGNMENT:

        pm_simplify_ranges = PatternMatcher([...])

    so those names were invisible to `--names`. A prior unit measured 11 of
    13 of its renames invisible for exactly this reason. Tree-wide, before
    the fix: 1132 def/class names, 388 assigned names, and the 388 were not
    in the denominator at all.

    Two consequences, both of which are why this is an AST walk now:

      * the regex could not see `x: int = 1`, `a = b = 1`, or a name first
        assigned by a plain `def` and rebound later; the AST sees the binding
        either way, and the set union collapses them as it should.
      * `__all__` is excluded. It is a re-export manifest, not a definition,
        and no `.bend` file would ever carry it -- counting it would
        manufacture "missing" names out of a bookkeeping line.
    """
    import ast
    out = set()
    try: tree = ast.parse(open(path).read())
    except SyntaxError: return out
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            out.add(node.name)
        elif isinstance(node, ast.Assign):
            out |= {t.id for t in node.targets
                    if isinstance(t, ast.Name) and t.id != '__all__'}
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            if node.target.id != '__all__': out.add(node.target.id)
    return out

def bend_defs(path):
    """every top-level Bend def, as (STEMS, QUALIFIERS)

    THE STEM TRAP, and this function used to walk straight into it: a dotted
    `A.b` was read as `A` (`split('.')[0]`). Upstream has NO module qualifier --
    it writes `Schedule.kernelize` as a plain `kernelize` in its own file -- and
    the port writes `def Sch.kernelize`. The qualifier is the disambiguator and
    is NOT part of the name, so the comparison must be against the text AFTER
    the final dot. Reading `L.foo` as `L` compares the wrong string and silently
    hides every qualified port of a bare upstream name.

    102 of 128 `.bend` files already disambiguate with `import ./x.bend as A`
    (a bare `import ./a.bend` is a PARSE ERROR), so `def A.name` plus an alias
    solves most collisions with NO prefix at all. Check both before renaming.

    The name correspondence is now a GATE, not a number someone recomputes:
    `.agents/slop/naming-gate.py` fails on any rename without a written ruling.
    This function answers the OTHER question -- how much is unported.
    """
    stems, quals = set(), set()
    if not os.path.exists(path): return stems, quals
    for l in open(path):
        m = re.match(r'\s*(?:def|struct|type)\s+([A-Za-z_][\w.]*)', l)
        if not m: continue
        parts = m.group(1).split('.')
        stems.add(parts[-1])
        quals.update(parts[:-1])
    return stems, quals

py = core_py()
miss = [(r, nlines('tinygrad/' + r)) for r in py if not os.path.exists(bend_for(r))]
init = [m for m in miss if m[0].endswith('__init__.py')]
real = [m for m in miss if not m[0].endswith('__init__.py')]
print('core upstream .py             %4d   (no runtime/autogen, llm, viz)' % len(py))
print('with a .bend at the same path  %4d' % (len(py) - len(miss)))
print('violations                    %4d   = %d trivial __init__.py + %d real (%d lines)'
      % (len(miss), len(init), len(real), sum(n for _, n in real)))
for r, n in real: print('   %-46s %5d' % (r, n))

if '--names' in sys.argv:
    print('\nTHE NAME CORRESPONDENCE, per file. IT IS A CORRESPONDENCE, NOT A SCORE: a')
    print('bend def with NO upstream counterpart is a port-local record or one of its')
    print('readers, and the naming rule simply does not apply to it. `local` is that')
    print('count; `verbatim` is upstream names the port reproduces exactly, either')
    print('bare or under a module qualifier (`def Sch.kernelize` keeps the name).')
    print('\nRENAMED is deliberately NOT counted here. It has its own gate:')
    print('`naming-gate.py` fails on any rename that lacks a written ruling, which')
    print('is the only way the number stops drifting back.')
    tv = tu = tq = tr = 0
    for rel in py:
        up = top_level_defs('tinygrad/' + rel)
        bd, bq = bend_defs(bend_for(rel))
        if not bd and not bq: continue
        verbatim = (up & bd) | (up & bq)
        renamed = {u for u in up - verbatim
                   if any(s != u and (s.endswith(u) or s.startswith(u)) for s in bd)}
        tv += len(verbatim); tu += len(up); tq += len(renamed)
        print('  %-42s upstream=%4d bend=%4d verbatim=%3d local=%4d renamed=%3d  %s'
              % (rel, len(up), len(bd), len(verbatim), len(bd) - len(verbatim),
                 len(renamed), ' '.join(sorted(verbatim)[:6])))
    print('\n  TOTAL upstream top-level bindings %d, reproduced verbatim %d (%.1f%%)'
          % (tu, tv, 100.0 * tv / max(tu, 1)))
    print('  bindings with a RENAME candidate %d -- see naming-gate.py for the ruling'
          % tq)
