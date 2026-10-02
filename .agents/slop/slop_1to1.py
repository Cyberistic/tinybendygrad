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
    """every top-level Bend def; a dotted `A.b` reads as `A`"""
    out = set()
    if not os.path.exists(path): return out
    for l in open(path):
        m = re.match(r'(?:def|struct|type)\s+([A-Za-z_][\w.]*)', l)
        if m: out.add(m.group(1).split('.')[0])
    return out

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
    print('count; `verbatim` is upstream names the port reproduces exactly.')
    tv = tu = 0
    for rel in py:
        up, bd = top_level_defs('tinygrad/' + rel), bend_defs(bend_for(rel))
        if not bd: continue
        tv += len(up & bd); tu += len(up)
        print('  %-42s upstream=%4d bend=%4d verbatim=%3d local=%4d  %s'
              % (rel, len(up), len(bd), len(up & bd), len(bd) - len(up & bd),
                 ' '.join(sorted(up & bd)[:6])))
    print('\n  TOTAL upstream top-level defs %d, reproduced verbatim %d (%.1f%%)'
          % (tu, tv, 100.0 * tv / max(tu, 1)))
