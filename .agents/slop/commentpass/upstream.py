#!/usr/bin/env python3
"""Classify bend comment lines as UPSTREAM (textually present in tinygrad/**/*.py)
or OURS. Reports per-block and per-line volumes.

METHOD
------
1. Build the upstream corpus: every *.py under tinygrad/, '#'-stripped and
   whitespace-collapsed, one big string per file, plus a global string.
   Docstrings are NOT removed -- that only ADDS text to the corpus, which can
   only create false POSITIVES (and is reported).
2. Normalise each bend comment line the same way: strip leading '#' and
   whitespace, collapse internal whitespace.
3. A line is UPSTREAM iff
     len(normalised) >= 15  AND  >= 3 content tokens  AND  the normalised
   string occurs in the global upstream corpus.
   The length and token floors exist to stop `# ok`, `# TODO`, `# note` and
   common English fragments from matching by accident.
4. A block is UPSTREAM only if EVERY one of its lines classifies UPSTREAM.
   Partial blocks are MIXED and are reported separately -- those are where
   an agent added our commentary to an upstream comment.
"""
import sys, os, re, random
from collections import Counter

WORD = re.compile(r'[A-Za-z_][A-Za-z0-9_.$]*')

def norm(s):
    s = s.strip()
    s = re.sub(r'^#+\s*', '', s)
    s = s.replace('`', '').replace('*', '')
    return re.sub(r'\s+', ' ', s).strip()

def content_tokens(s):
    return [w for w in WORD.findall(s) if len(w) >= 4]

def load_corpus(root='tinygrad', mode='comments'):
    """mode='comments' -> corpus is ONLY Python comment text (the thing we must
    keep verbatim).  mode='all' -> every line, which matches quoted code and is
    only useful for showing how badly mode='all' over-reports."""
    files = []
    for dp, dn, fn in os.walk(root):
        if '.git' in dp: continue
        for f in fn:
            if f.endswith('.py'):
                files.append(os.path.join(dp, f))
    parts = []
    for p in files:
        with open(p, encoding='utf-8', errors='replace') as fh:
            raw = fh.read().split('\n')
        if mode == 'comments':
            keep = [re.sub(r'^\s*#+\s?', '', l) for l in raw if l.strip().startswith('#')]
        else:
            keep = [re.sub(r'#.*$', '', l) for l in raw]
        parts.append(norm('\n'.join(keep)))
    return files, {p: x for p, x in zip(files, parts)}, norm('\n'.join(parts))

def classify_line(n, corpus):
    if len(n) < 15: return False
    if len(content_tokens(n)) < 3: return False
    return n in corpus

def main():
    bend_files = sys.argv[1:]
    upfiles, uper, uglobal = load_corpus()
    print(f'upstream corpus: {len(upfiles)} .py files, {len(uglobal)} normalized chars')
    tot_lines = Counter()
    tot_blocks = Counter()
    per_file = []
    samples = {'UP': [], 'OUR': [], 'MIX': []}
    for p in bend_files:
        with open(p, encoding='utf-8', errors='replace') as fh:
            lines = fh.read().split('\n')
        bl = []
        i, n = 0, len(lines)
        while i < n:
            if lines[i].strip().startswith('#'):
                j = k = i
                while j < n:
                    if lines[j].strip().startswith('#'): k = j; j += 1
                    elif lines[j].strip() == '': j += 1
                    else: break
                bl.append((i, k)); i = k + 1
            else: i += 1
        cl = [l for l in lines if l.strip().startswith('#')]
        our_lines = 0; up_lines = 0; mixed_blocks = 0; pure_up = 0; pure_our = 0
        for (a, b) in bl:
            seg = lines[a:b+1]
            cls = [classify_line(norm(l), uglobal) for l in seg]
            nu = sum(cls)
            up_lines += nu; our_lines += len(cls) - nu
            if all(cls): pure_up += 1
            elif any(cls):
                mixed_blocks += 1
                samples['MIX'].append((p, a+1, b+1))
            else: pure_our += 1
        per_file.append((p, len(cl), up_lines, our_lines, len(bl), pure_up, mixed_blocks, pure_our))
        tot_lines['up'] += up_lines; tot_lines['our'] += our_lines
        tot_blocks['up'] += pure_up; tot_blocks['mix'] += mixed_blocks; tot_blocks['our'] += pure_our
    print()
    print(f"{'file':40s} {'cmt':>6s} {'UPSTR':>7s} {'OURS':>6s} {'blk':>4s} {'UPb':>4s} {'MIXb':>5s} {'OURb':>5s}")
    for (p, c, u, o, b, pu, mx, po) in per_file:
        print(f"{p.replace('tinybendygrad/','').replace('.agents/slop/commentpass/before/',''):40s} {c:6d} {u:7d} {o:6d} {b:4d} {pu:4d} {mx:5d} {po:5d}")
    T = tot_lines['up'] + tot_lines['our']
    print()
    print(f"TOTAL comment lines {T}:  UPSTREAM-text {tot_lines['up']} ({100.0*tot_lines['up']/T:.1f}%)  "
          f"OURS {tot_lines['our']} ({100.0*tot_lines['our']/T:.1f}%)")
    B = tot_blocks['up'] + tot_blocks['mix'] + tot_blocks['our']
    print(f"TOTAL blocks {B}:  all-upstream {tot_blocks['up']}  mixed {tot_blocks['mix']}  all-ours {tot_blocks['our']}")
    print()
    print('MIXED blocks (upstream text with our commentary attached) -- first 40:')
    for (p, a, b) in samples['MIX'][:40]:
        print(f'  {p}:{a}-{b}')
    print(f'  ... {len(samples["MIX"])} total')

if __name__ == '__main__':
    main()