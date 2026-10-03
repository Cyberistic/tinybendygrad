#!/usr/bin/env python3
"""THE NAMING GATE: `def` names stay consistent with upstream tinygrad. ENFORCED.

The owner ruling this enforces, quoted from `agent-core.md`:

    2. DEF NAMES MATCH UPSTREAM EXACTLY, WHEREVER POSSIBLE. The standard is
       explicit: anyone familiar with tinygrad should feel at home here and not
       have to map anything. So port `Schedule.kernelize` as `kernelize`, not
       `sch_kernelize`. Do not invent a prefix to avoid a collision.

A consistency claim a human recomputes by hand drifts; this one fails instead.

    python3 .agents/slop/naming-gate.py            # report + enforce (exit 1 on violation)
    python3 .agents/slop/naming-gate.py -v         # add the per-entry evidence
    python3 .agents/slop/naming-gate.py --update   # rewrite the ledger skeleton

──────────────────────────────────────────────────────────────────────────────
RENAMED vs ABSENT. Conflating them is how a naming gate becomes a churn
machine that blocks real work, so they are different verdicts.
──────────────────────────────────────────────────────────────────────────────

  RENAMED  a port def whose stem is `<affix> + <upstream name>`, where upstream
           DEFINITELY binds that bare name in the sibling `.py`. This is the
           divergence the ruling forbids: a reader who knows tinygrad has to
           map something before the file is usable.  FAILS unless adjudicated.

  ABSENT   upstream binds the name; the port has nothing for it.  PASSES.
           An unported name is MISSING IMPLEMENTATION, not a misnomer. There are
           ~1,090 of them, they are a different and much larger piece of work,
           and a name that is ABSENT cannot be misnamed.

──────────────────────────────────────────────────────────────────────────────
THE EXEMPTION IS FOR AN EXACT AFFIX, NOT FOR A CONCEPT.
──────────────────────────────────────────────────────────────────────────────

The ledger is keyed `(file, upstream_name, affix)`. That precision is not
decoration; a first draft keyed it on `(file, upstream_name)` and the gate's own
test caught the hole immediately. With the coarser key, the moment
`codegen/gpudims.py :: group_gpudims` had been reviewed ONCE (its affix is `pm_`,
which is upstream's own prefix), ANY later affix of that name was silently
admitted: renaming `pm_group_gpudims` to `selftest_group_gpudims` left the gate
green. The self-test planted exactly that and it passed when it had to fail.

So an exemption says "this exact affix, on this exact name, in this exact file,
is reviewed" -- and nothing else. Change the prefix and the gate goes red.

──────────────────────────────────────────────────────────────────────────────
THE DETECTOR NEVER SUPPRESSES. It only proposes; the ledger adjudicates.
──────────────────────────────────────────────────────────────────────────────

An earlier draft dropped every upstream name with more than one affix hit, on
the theory that a fan-out is not a rename. MEASURED WRONG: that rule hid 6 of
the 9 renames this gate was built to catch (`transcendental.py`'s `shl`/`shr`,
`elementwise.py`'s `remint`, `datasets.py`'s `cifar`, `dsl.py`'s `DPP`/`SDWA`,
plus `cstyle.py`'s `_ocml` and `render.py`'s `precedence`). A gate that cannot
fail on the thing it exists for is worse than no gate.

Two guards remain, and both are about DEGENERACY rather than semantics:

  * affix length >= 3. With no guard the detector reports 582 pairs from 94
    upstream names, because upstream `dsl.py` binds the one-letter names `s`
    and `v`, so `src`, `S_OFF`, `LDS` and `VOP2_FNOLIT` all "rename" them.
  * `__all__` is excluded upstream: it is a re-export manifest, and no `.bend`
    file would ever carry it, so counting it manufactures "missing" names out
    of a bookkeeping line.

──────────────────────────────────────────────────────────────────────────────
THE GC4 TRAP: upstream binds rewrite tables by ASSIGNMENT, not by `def`.
──────────────────────────────────────────────────────────────────────────────

    pm_simplify_ranges = PatternMatcher([...])

is upstream's own top-level name and it is NOT a `def`. A census matching only
`^(async )?(def|class)` misses every one of them, which is how the previous unit
measured "11 of 13 of its renames invisible" and then handed over a wrong count.
Upstream extraction is therefore an AST walk over module body collecting
`def`/`class`/assignment targets.

Note what this implies for the gate: `pm_` is UPSTREAM's own prefix (92+
upstream names are assignments beginning `pm_`), so a port that writes
`pm_group_gpudims` is CONSISTENT, and stripping the prefix would invent a name.

──────────────────────────────────────────────────────────────────────────────
THE PORT STEM: compare the text AFTER THE LAST DOT.
──────────────────────────────────────────────────────────────────────────────

Upstream has no module qualifier -- it writes `Schedule.kernelize` as a plain
`kernelize` in its own file. The port writes `def Sch.kernelize`, and 102 of 128
`.bend` files already disambiguate cross-file collisions with
`import ./x.bend as A` (a bare `import ./a.bend` is a PARSE ERROR). So the
qualifier is the disambiguator and is NOT part of the name: compare the stem
after the final dot, and report a name that survives only as a qualifier as
QUALIFIED. Reading `L.foo` as `L` -- which is what `slop_1to1.py` did -- compares
the wrong string and hides every qualified port of a bare upstream name.
"""
import ast
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
PY, BEND = os.path.join(ROOT, 'tinygrad'), os.path.join(ROOT, 'tinybendygrad')
LEDGER = os.path.join(HERE, 'naming-gate-baseline.txt')

# `runtime/autogen` is ~150k lines of vendored ctypes bindings; `llm/` and `viz/`
# have no `.bend` tree at all. Stated rather than left implicit, because a gate
# whose denominator is unexplained is not a gate.
EXCLUDE_SUBTREE = ('runtime/autogen', 'llm', 'viz')
EXCLUDE_DIRNAME = {'__pycache__', 'reference', '.git'}
MIN_AFFIX = 3

DEF_LINE = re.compile(r'^\s*(?:def|struct|type)\s+([A-Za-z_][\w.]*)')


def upstream_names(path):
    """Top-level BINDINGS, not just `def`s. See the GC4 note in the docstring."""
    out = set()
    try:
        tree = ast.parse(open(path).read())
    except (SyntaxError, UnicodeDecodeError, ValueError):
        return out
    for node in tree.body:
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            out.add(node.name)
        elif isinstance(node, ast.Assign):
            out |= {t.id for t in node.targets
                    if isinstance(t, ast.Name) and t.id != '__all__'}
        elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
            if node.target.id != '__all__':
                out.add(node.target.id)
    return out


def port_names(path):
    """STEMS (text after the final dot) and QUALIFIERS (text before it)."""
    stems, quals = set(), set()
    if not os.path.exists(path):
        return stems, quals
    for line in open(path):
        m = DEF_LINE.match(line)
        if not m:
            continue
        parts = m.group(1).split('.')
        stems.add(parts[-1])
        quals.update(parts[:-1])
    return stems, quals


def pairs():
    """Every upstream `.py` with a sibling `.bend`, as (relpy, absbend)."""
    out = []
    for root, dirs, files in os.walk(PY):
        dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRNAME]
        rel = os.path.relpath(root, PY).replace(os.sep, '/')
        if rel == '.':
            rel = ''
        if any(rel == e or rel.startswith(e + '/') for e in EXCLUDE_SUBTREE):
            continue
        for f in sorted(files):
            if not f.endswith('.py'):
                continue
            bend = os.path.join(BEND, rel, f[:-3] + '.bend')
            if os.path.exists(bend):
                # never a leading slash: os.path.join(PY, '/x.py') would
                # DISCARD PY and read the filesystem root instead.
                out.append(('%s/%s' % (rel, f) if rel else f, bend))
    return sorted(out)


def census():
    """(counts, candidates, per-file rows).

    `candidates` maps (relpy, upstream_name) -> sorted [(affix, port_stem)].
    An upstream name is a candidate only if it is NEITHER reproduced verbatim as
    a bare stem NOR present as a module qualifier -- both are consistent with
    upstream, which itself has no module qualifier.
    """
    tally = dict(VERBATIM=0, QUALIFIED=0, RENAMED_UNIQUE=0, RENAMED_FANOUT=0, ABSENT=0)
    candidates, rows = {}, []
    for rel, bend in pairs():
        up = upstream_names(os.path.join(PY, rel))
        stems, quals = port_names(bend)
        row = dict(rel=rel, up=len(up), bend=len(stems), absent=0)
        for name in up:
            if name in stems:
                tally['VERBATIM'] += 1
                continue
            if name in quals:
                tally['QUALIFIED'] += 1
                continue
            hits = []
            for s in stems:
                if s == name:
                    continue
                if s.endswith(name) and len(s) - len(name) >= MIN_AFFIX:
                    hits.append((s[:-len(name)], s))
                elif s.startswith(name) and len(s) - len(name) >= MIN_AFFIX:
                    hits.append((s[len(name):], s))
            if hits:
                tally['RENAMED_' + ('UNIQUE' if len(hits) == 1 else 'FANOUT')] += 1
                candidates[(rel, name)] = sorted(hits)
            else:
                tally['ABSENT'] += 1
                row['absent'] += 1
        rows.append(row)
    return tally, candidates, rows


def load_ledger():
    """`file<TAB>name<TAB>affix<TAB>reason`, one line per reviewed RENAME.

    A reason is REQUIRED: an entry with no reason is not an exemption, it is an
    unfinished review, and the gate treats it as a violation.
    """
    out = {}
    if not os.path.exists(LEDGER):
        return out
    for lineno, line in enumerate(open(LEDGER), 1):
        line = line.rstrip('\n')
        if not line or line.lstrip().startswith('#'):
            continue
        parts = line.split('\t')
        if len(parts) != 4:
            sys.exit('ledger line %d is not file<TAB>name<TAB>affix<TAB>reason: %s'
                     % (lineno, line))
        out[(parts[0], parts[1], parts[2])] = parts[3]
    return out


def main():
    args = sys.argv[1:]
    update, verbose = '--update' in args, '-v' in args
    tally, candidates, rows = census()
    ledger = load_ledger()

    # one rename candidate per (file, name, affix); `port` maps key -> stem
    detected, port = {}, {}
    for (rel, name), hits in candidates.items():
        for affix, stem in hits:
            detected[(rel, name, affix)] = stem
    # A blank or UNREVIEWED reason is not a ruling, it is an unfinished review.
    # So `unadjudicated` means EITHER absent from the ledger OR present but
    # unreviewed -- otherwise --update can mint every exemption in one command
    # and the gate reports a clean tree over an unreviewed ledger.
    unadjudicated = {k: v for k, v in detected.items()
                     if k not in ledger or not ledger[k].strip()
                     or ledger[k].startswith('UNREVIEWED')}
    stale = {k: v for k, v in ledger.items() if k not in detected}

    if update:
        with open(LEDGER, 'w') as fh:
            fh.write('# THE NAMING GATE REVIEW LEDGER -- one line per RENAME:\n')
            fh.write('#\tupstream_file<TAB>upstream_name<TAB>affix<TAB>reason\n')
            fh.write('#\n# Regenerate with `naming-gate-ledger.py`, which asserts full coverage.\n')
            for key in sorted(detected):
                fh.write('%s\t%s\t%s\t%s\n' % (
                    key[0], key[1], key[2],
                    ledger.get(key, '').strip() or 'UNREVIEWED port=' + detected[key]))
        print('ledger rewritten: %d rename(s), %d still UNREVIEWED'
              % (len(detected), len(unadjudicated)))
        return 1 if unadjudicated else 0

    total = sum(tally.values())
    print('=' * 76)
    print('NAMING GATE -- owner ruling: def names match upstream tinygrad exactly')
    print('=' * 76)
    print('\nupstream .py files with a sibling .bend walked      %4d'
          '   (excluded: %s)' % (len(rows), ', '.join(EXCLUDE_SUBTREE)))
    print('\nupstream top-level BINDINGS                         %4d'
          '   (def/class AND assignment targets)' % total)
    print('  VERBATIM     port reproduces the name exactly      %4d   %5.1f%%'
          % (tally['VERBATIM'], 100.0 * tally['VERBATIM'] / max(total, 1)))
    print('  QUALIFIED    name kept, under a module qualifier   %4d' % tally['QUALIFIED'])
    print('  RENAMED/1    <affix> + name, ONE port stem          %4d   <- adjudicated'
          % tally['RENAMED_UNIQUE'])
    print('  RENAMED/n    <affix> + name, SEVERAL port stems      %4d   <- adjudicated'
          % tally['RENAMED_FANOUT'])
    print('  ABSENT       UNPORTED, no counterpart               %4d   %5.1f%%'
          % (tally['ABSENT'], 100.0 * tally['ABSENT'] / max(total, 1)))

    violations = unadjudicated or stale
    print('\n' + '-' * 76)
    print('RENAMED: %d candidates -> %d unadjudicated'
          % (len(detected), len(unadjudicated)))
    print('-' * 76)

    if unadjudicated:
        print('\n*** %d RENAME(S) WITH NO RULING IN THE LEDGER. ***' % len(unadjudicated))
        for key in sorted(unadjudicated):
            print('  %-38s %-20s + %-18s -> %s'
                  % (key[0], key[1], key[2], unadjudicated[key]))
        print('\n  Either rename the port def to the upstream name, or add one ledger')
        print('  line per rename saying why the bare name is unavailable. An exemption')
        print('  covers ONE exact affix: change the prefix and this fires again.')
        print('  Before renaming to dodge a COLLISION, check whether `def A.name`')
        print("  or the importer's `as` alias already solves it: 102 of 128 .bend")
        print('  files use an alias, and a bare `import ./a.bend` is a PARSE ERROR.')
    else:
        print('\nEvery rename candidate carries a ruling. No unadjudicated divergence.')

    if stale:
        print('\n*** %d STALE LEDGER LINE(S): no longer a candidate. ***' % len(stale))
        for key in sorted(stale):
            print('  %-38s %-20s + %-18s (ledger says: %s)'
                  % (key[0], key[1], key[2], stale[key]))
        print('  Stale amnesty is unearned amnesty. Delete the line (--update).')

    adjudicated = [k for k in detected if k in ledger and k not in unadjudicated]
    if adjudicated:
        by_reason = {}
        for key in adjudicated:
            by_reason.setdefault(ledger[key], []).append(key)
        print('\n%d adjudicated rename(s), by reason:' % len(adjudicated))
        for reason in sorted(by_reason):
            print('  %-58s %4d' % (reason, len(by_reason[reason])))
            if verbose:
                for key in sorted(by_reason[reason]):
                    print('        %-34s %-18s + %-16s -> %s'
                          % (key[0], key[1], key[2], detected[key]))

    print('\n' + '-' * 76)
    print('UNPORTED (ABSENT): %d of %d upstream bindings have no counterpart.'
          % (tally['ABSENT'], total))
    print('NOT A NAMING VIOLATION. This gate does not fail on it, and should not:')
    print('it is missing implementation, a different and much larger piece of')
    print('work, and an absent name cannot be misnamed. Fixing renames does not')
    print('move this number; porting the code does.')
    if verbose:
        for row in rows:
            if row['absent']:
                print('    %-40s %4d absent of %4d'
                      % (row['rel'], row['absent'], row['up']))
    print('-' * 76)

    print('\nRESULT: %s' % ('FAIL' if violations else 'PASS'))
    return 1 if violations else 0


if __name__ == '__main__':
    sys.exit(main())