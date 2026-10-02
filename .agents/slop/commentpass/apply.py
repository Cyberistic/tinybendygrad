#!/usr/bin/env python3
"""Apply comment-block replacements.  A replacement is keyed by (file, start,
end) in 1-based line numbers of the file AS IT IS NOW, and MUST carry
expect_first -- the exact text of the block's first line.  If it does not match,
the edit is REFUSED, so a stale key can never silently rewrite the wrong text.

Then it verifies the file's non-comment lines are byte-identical to the snapshot
in .agents/slop/commentpass/before/.
"""
import sys, os, json, re

BEFORE = '.agents/slop/commentpass/before/'

def noncomment(lines):
    return [l for l in lines if not l.strip().startswith('#')]

def main(spec_path):
    with open(spec_path) as f:
        specs = json.load(f)
    byfile = {}
    for s in specs:
        byfile.setdefault(s['file'], []).append(s)
    total_del = 0; total_add = 0
    for path, ss in sorted(byfile.items()):
        with open(path, encoding='utf-8') as f:
            lines = f.read().split('\n')
        before_noncomment = noncomment(lines)
        # apply in REVERSE start order so earlier indices stay valid
        for s in sorted(ss, key=lambda x: -x['start']):
            a, b = s['start'] - 1, s['end']
            seg = lines[a:b]
            if seg[0] != s['expect_first']:
                sys.exit(f'REFUSED {path}:{s["start"]}\n  expected {s["expect_first"]!r}\n  found    {seg[0]!r}')
            if any(not l.strip().startswith('#') for l in seg):
                sys.exit(f'REFUSED {path}:{s["start"]} block contains a non-comment line')
            lines[a:b] = s['new']
            total_del += b - a
            total_add += len(s['new'])
        after_noncomment = noncomment(lines)
        if after_noncomment != before_noncomment:
            n = 0
            for i, (x, y) in enumerate(zip(before_noncomment, after_noncomment)):
                if x != y:
                    n += 1
                    if n < 5: sys.exit(f'REFUSED {path}: NON-COMMENT LINE CHANGED\n  {x!r}\n  {y!r}')
            sys.exit(f'REFUSED {path}: {n} non-comment lines differ (len {len(before_noncomment)} -> {len(after_noncomment)})')
        snap = BEFORE + path
        if os.path.exists(snap):
            with open(snap, encoding='utf-8') as f:
                sl = f.read().split('\n')
            if noncomment(sl) != after_noncomment:
                sys.exit(f'REFUSED {path}: non-comment lines differ from the BEFORE SNAPSHOT')
        with open(path, 'w', encoding='utf-8') as f:
            f.write('\n'.join(lines))
        print(f'ok  {path}  {len(ss)} blocks, -{sum(s["end"]-s["start"]+1 for s in ss)} +{sum(len(s["new"]) for s in ss)}')
    print(f'TOTAL replaced lines: -{total_del} +{total_add}  net {total_add-total_del}')

if __name__ == '__main__':
    main(sys.argv[1])