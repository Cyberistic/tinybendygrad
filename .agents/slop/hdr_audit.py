#!/usr/bin/env python3
"""HEADER-CLAIM AUDIT for a .bend file: every ASSERTION the prose makes, checked.

The failure this exists for is a header that claims something no check reads. The
compiler cannot see prose and the gate rows cannot see prose, so a false claim
survives every check the repo has. Three claims recur and all three are checked
here:

  * a NAME -- a def, a row, a Python function. Does it exist?
  * a LINE  -- `foo.py:39`. Does line 39 still say what the header says?
  * a COUNT -- "1428 rows", "4059 lines". Does the file still have that many?

`--check` prints one `FALSE` line per claim that does not hold, with the truth,
so an editor can fix the prose without re-deriving anything. `--dead` reports
defs nothing calls. Nothing here writes to a .bend file.

    python3 .agents/slop/hdr_audit.py --check tinybendygrad/runtime/ops_nv.bend
    python3 .agents/slop/hdr_audit.py --dead  tinybendygrad/mixin/rand.bend
"""
import re
import subprocess
import sys
from collections import OrderedDict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DEF_RE = re.compile(r"^(def|type)\s+([A-Za-z_][A-Za-z_0-9]*(?:\.[A-Za-z_0-9]+)*)")
TODO_RE = re.compile(r"TODO\((p\d)\)\s+([A-Za-z_0-9./]+):(\d+)\s+`?([^\s`]*?)`?\s*$")
# a def-ish token in prose: dotted or plain, no spaces
TOKEN_RE = re.compile(r"`([A-Za-z_][A-Za-z_0-9]*(?:\.[A-Za-z_0-9]+)*)`")
# `foo.py:39` or `foo.py:39-51` or `foo.py:387/:511`
PYREF_RE = re.compile(r"`?([A-Za-z_0-9/]+\.py)(?::(\d+))?")
ONLYLINE_RE = re.compile(r"(?<![\w./'`])(:(\d+))")
COUNT_RE = re.compile(r"\b(\d+)\s+(rows|lines|structs|fields|defs|blocks|constants|laws)\b")
# "stage1 and stage2 print the halves, 286 and 334 rows" is a SPLIT, and the sum
# is the claim. Checking either half against the whole is the false positive.
SPLIT_RE = re.compile(r"\b(\d+)\s+and\s+(\d+)\s+(rows|lines)\b")
# "moved 8 rows" is a claim about a MUTATION, not about the file's row count,
# and a mutation table's `name  N  MOVED  rows...` lines are the harness's, so
# both are outside the count grammar.
MOVED_RE = re.compile(r"\b(moved|kills|closes|moves)\s+\d+\s+rows?\b")
MUTATION_RE = re.compile(r"\b(moved|MOVED|EQUIV|BLIND)\b")
RETRACT_RE = re.compile(r"\b(never written|does not exist|no such|previously named|"
                        r"was deleted|is not a def|nothing called it)\b")
# every committed .bend, for cross-file def claims. Loaded once; a header that
# says "ops_webgpu's Tr.pop" is only checkable because the other file is here.
BEND_FILES = [p for p in ROOT.rglob('*.bend')
              if '.agents' not in p.parts and '.git' not in p.parts]
PYMOD = {
    'nv/ip': 'tinygrad/runtime/support/nv/ip.py', 'ip': None,
}


def strip_code(line):
    out, in_str = [], False
    for i, ch in enumerate(line):
        if ch == '"' and (i == 0 or line[i - 1] != '\\'):
            in_str = not in_str
            continue
        if ch == '#' and not in_str:
            break
        if not in_str:
            out.append(ch)
    return ''.join(out)


def header(lines):
    out = []
    for line in lines:
        s = line.lstrip()
        if s.startswith('#') or s == '':
            out.append(line)
        else:
            break
    return out


def comment_blocks(lines):
    """Every `#` block in the file, with its line numbers -- headers, walls and
    mid-file claim blocks all assert the same things, so all of them count."""
    out, cur = [], []
    for i, line in enumerate(lines, 1):
        if line.lstrip().startswith('#'):
            cur.append((i, line))
        else:
            if cur:
                out.append(cur)
            cur = []
    if cur:
        out.append(cur)
    return out


def defs_and_body(lines):
    defs, body = [], []
    for i, l in enumerate(lines, 1):
        m = DEF_RE.match(l)
        if m:
            defs.append((m.group(2), i))
            body.append(' ' * (len(m.group(1)) + 1) + strip_code(l)[m.end():])
        else:
            body.append(strip_code(l))
    return defs, '\n'.join(body)


def printed_rows(path):
    r = subprocess.run(['./bin/bend', str(path)], cwd=ROOT, capture_output=True, text=True)
    return [l for l in r.stdout.splitlines() if l.strip()]


def pyfile(name):
    """A `.py` name as the header writes it -> a real path, or None."""
    if name.startswith('tinygrad/') or name.startswith('references/'):
        return ROOT / name
    hits = list((ROOT / 'tinygrad').rglob(name))
    return hits[0] if len(hits) == 1 or hits else None


def bendfile(name):
    """A `.bend` name as a header writes it -> a real path, or None."""
    hits = list(ROOT.rglob(name))
    hits = [h for h in hits if '.agents' not in h.parts]
    return hits[0] if len(hits) == 1 else (hits[0] if hits else None)


def bend_counts(name):
    """`def` count and `wc -l` for another .bend file, so a cross-file count
    claim is checked against the file it names and not against the audited one."""
    f = bendfile(name)
    if f is None:
        return None
    txt = f.read_text()
    return (len(txt.splitlines()),
            sum(1 for l in txt.splitlines() if DEF_RE.match(l)))


def main():
    mode, files = sys.argv[1], sys.argv[2:]
    false_n = 0
    for p in files:
        path = Path(p)
        lines = path.read_text().splitlines()
        hdr = header(lines)
        defs, body = defs_and_body(lines)
        names = OrderedDict((n, i) for n, i in defs)
        # `Iface.of` is a claim about `iface.of` too: a reader writes the claim in
        # the lower-case namespace the rest of the file uses, so match on the
        # NAMESPACE case-insensitively but report the real spelling.
        lower = {n.lower(): n for n in names}
        outs = printed_rows(path)
        print('=' * 104)
        print('%s\n  %d lines, %d defs, %d rows printed, %d-line header' %
              (p, len(lines), len(defs), len(outs), len(hdr)))

        if mode == '--dead':
            dead = [(n, i) for n, i in defs if n != 'main'
                    and not re.search(r'(?<![A-Za-z_0-9.])' + re.escape(n) + r'(?![A-Za-z_0-9])', body)]
            print('  DEAD %d of %d' % (len(dead), len(defs)))
            for n, i in dead:
                print('    line %-6d %-26s %s' % (i, n, lines[i - 1].strip()[:56]))
            continue

        seen = set()
        # --- 1. `TODO(pN) path.py:N sym` walls: the Python line must still hold it
        for i, line in enumerate(hdr, 1):
            m = TODO_RE.search(line.rstrip())
            if not m:
                continue
            _, mod, ln, sym = m.group(1), m.group(2), int(m.group(3)), m.group(4)
            # a wall spells its symbol with an elided tail -- `_alloc_boot_mem(...)`
            # -- so the `(...)` is not part of what the line has to contain.
            sym = sym.removesuffix('(...)')
            f = pyfile(mod)
            key = ('todo', mod, ln, sym)
            if key in seen:
                continue
            seen.add(key)
            if f is None:
                print('  FALSE  hdr:%d TODO(%s) %s:%d %s -- no such Python file'
                      % (i, m.group(1), mod, ln, sym))
                false_n += 1
                continue
            src = f.read_text().splitlines()
            if ln > len(src):
                print('  FALSE  hdr:%d TODO(%s) %s:%d %s -- file has %d lines'
                      % (i, m.group(1), mod, ln, sym, len(src)))
                false_n += 1
                continue
            body_line = src[ln - 1]
            ok = (not sym) or sym in body_line
            if not ok:
                print('  FALSE  hdr:%d TODO(%s) %s:%d %s -- line is: %s'
                      % (i, m.group(1), mod, ln, sym, body_line.strip()[:66]))
                false_n += 1
        # --- 2. every backticked def-ish token in ANY comment block. A token only
        # CLAIMS a local def if its namespace is one this file defines -- that is
        # what separates `pc.key` (a claim about a local def) from `NVQueue.q`
        # (a Python name) and `U32.or` (a Bend core name).
        printed = '\n'.join(outs)
        printed_names = {l.split('=')[0] for l in outs}
        ns = {n.split('.')[0].lower() for n in names if '.' in n}
        for blk in comment_blocks(lines):
            for i, line in blk:
                for tok in TOKEN_RE.findall(line):
                    key = ('tok', tok)
                    if key in seen or tok in names:
                        continue
                    seen.add(key)
                    if '.' not in tok or tok.endswith('.'):
                        continue
                    if tok.split('.')[0].lower() not in ns:
                        continue
                    if tok in printed_names:
                        continue
                    if tok.lower() in lower:
                        print('  FALSE  hdr:%d `%s` -- the def is spelled `%s`'
                              % (i, tok, lower[tok.lower()]))
                        false_n += 1
                        continue
                    # a claim about ANOTHER .bend file's def is checkable and is
                    # the shape that retires a wall, so resolve it.
                    if any(re.search(r'^(def|type) ' + re.escape(tok) + r'\b',
                                     (f or Path('/dev/null')).read_text(), re.M)
                           for f in BEND_FILES):
                        continue
                    # a MUTATION name is a claim about the mutation harness, not
                    # about a def, and a retracted name is a claim about the
                    # draft. Both are true when they say so.
                    if MUTATION_RE.search(line) or RETRACT_RE.search(line):
                        continue
                    print('  FALSE  hdr:%d `%s` -- not a def here, not a row'
                          % (i, tok))
                    false_n += 1
        # --- 3. counts the header states about ITSELF
        # a count claim about ANOTHER file is checked against that file. This is
        # the shape of the lie that survives: "hcq2.bend is a 29-line STUB"
        # stayed true in this file's prose long after hcq2.bend grew to 2272
        # lines, because nothing reads prose.
        OTHER = re.compile(r"`([A-Za-z_0-9./-]+\.bend)`")
        PYFILE = re.compile(r"[A-Za-z_0-9./-]+\.py\b")
        subject = None
        for i, line in enumerate(hdr, 1):
            if MOVED_RE.search(line):
                continue
            # "transcendental.py (277 lines)" is a claim about the PYTHON file and
            # is checked by the TODO/wall pass, not by the `.bend` counter.
            window = '\n'.join(hdr[max(0, i - 4):i + 1])
            if PYFILE.search(window) and not OTHER.search(line):
                continue
            if SPLIT_RE.search(line):
                m = SPLIT_RE.search(line)
                tot = {'rows': len(outs), 'lines': len(lines)}[m.group(3)]
                if int(m.group(1)) + int(m.group(2)) != tot:
                    print('  FALSE  hdr:%d claims %s+%s %s; file has %s'
                          % (i, m.group(1), m.group(2), m.group(3), tot))
                    false_n += 1
                continue
            named = OTHER.findall(line)
            # the subject of a count is the nearest .bend named within the
            # preceding three header lines: prose wraps, so "it is 2272 lines"
            # sits a line below the `hcq2.bend` that "it" refers to.
            if named:
                subject = named[0]
            elif subject and not OTHER.search(window):
                subject = None
            if subject and subject != path.name:
                c = bend_counts(subject)
                if c:
                    for n, what in COUNT_RE.findall(line):
                        truth = {'lines': c[0], 'defs': c[1]}.get(what)
                        if truth is None or int(n) == truth:
                            continue
                        print('  FALSE  hdr:%d claims %s is %s %s; it is %s'
                              % (i, subject, n, what, truth))
                        false_n += 1
                    continue
            for n, what in COUNT_RE.findall(line):
                truth = {'rows': len(outs), 'lines': len(lines),
                         'defs': len(defs)}.get(what)
                if truth is None or int(n) == truth:
                    continue
                print('  FALSE  hdr:%d claims %s %s; file has %s'
                      % (i, n, what, truth))
                false_n += 1
        # --- 4. Python line refs in the header
        for i, line in enumerate(hdr, 1):
            for mod, ln in PYREF_RE.findall(line):
                if not ln:
                    continue
                f = pyfile(mod)
                if f is None:
                    print('  FALSE  hdr:%d `%s` -- no such Python file' % (i, mod))
                    false_n += 1
                elif int(ln) > len(f.read_text().splitlines()):
                    print('  FALSE  hdr:%d `%s:%s` -- file has %d lines'
                          % (i, mod, ln, len(f.read_text().splitlines())))
                    false_n += 1
    print('\n%d FALSE claims' % false_n)
    return 1 if false_n else 0


if __name__ == '__main__':
    sys.exit(main())
