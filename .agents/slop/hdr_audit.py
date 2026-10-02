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
# a backticked SPAN, and then the subset of spans that are CODE rather than a
# name. The span split matters: a regex that runs to the next backtick spans the
# PROSE between two code spans (`` `_broadcasted`'s promotion (x.py:24-34) ``) and
# then reads prose as a citation's content.
SPAN_RE = re.compile(r"`([^`]*)`")
CODEY_RE = re.compile(r"[()=;:]")
IDENT_RE = re.compile(r"[A-Za-z_][A-Za-z_0-9]*")
CODE_FRAG_RE = SPAN_RE
# a CONTENT citation: `mod.py:N` (no range) -- at most four words of connector --
# `quoted code`. The connector cap is what separates a claim about line N from a
# pointer at a region, and the range exclusion is what stops `(upat.py:18-20)` --
# a pointer whose neighbouring span belongs to another module -- being read as a
# quote of upat.py.
CITE_RE = re.compile(
    r"`?([A-Za-z_0-9/]+\.py):(\d+)`?(?![-\d])([^`\n]{0,40}?)`([^`]+)`")


def code_spans(line):
    """The backticked spans of a line that assert CODE, so a Python line
    citation can be checked against what the line says that code contains."""
    out = []
    for span in SPAN_RE.findall(line):
        if span.endswith('.py') or '.py:' in span:
            continue                      # a pointer, not a content claim
        if not CODEY_RE.search(span):
            continue                      # a bare name, e.g. `_broadcasted`
        if len(max(IDENT_RE.findall(span), key=len, default='')) < 4:
            continue                      # `"{0} is {1}"` -- no name to match
        out.append(span)
    return out
PY_KW = {'if', 'else', 'not', 'and', 'or', 'for', 'in', 'is', 'return', 'the',
         'a', 'of', 'to', 'def', 'class', 'lambda', 'None', 'True', 'False'}
ONLYLINE_RE = re.compile(r"(?<![\w./'`])(:(\d+))")
# an INVENTORY row: `#   12  108-125 fold   reduce_collapse   WALL: ...`. The
# numbered column is the Python file's own def index, the next is the Python line
# RANGE and the last identifier before the STATE is the Python symbol. Checking
# the range against the symbol is the only way an inventory row is verified at
# all -- prose says "def by def, against __init__.py's 518 lines" and nothing
# re-reads the 43 rows that follow.
INV_RE = re.compile(
    r"^#\s*(\d+)\s+(\d+)(?:-(\d+))?\s+(\S+)\s+([A-Za-z_][A-Za-z_0-9_./]*)")
COUNT_RE = re.compile(r"\b(\d+)\s+(rows|lines|structs|fields|defs|blocks|constants|laws)\b")
# "stage1 and stage2 print the halves, 286 and 334 rows" is a SPLIT, and the sum
# is the claim. Checking either half against the whole is the false positive.
SPLIT_RE = re.compile(r"\b(\d+)\s+and\s+(\d+)\s+(rows|lines)\b")
# "moved 8 rows" is a claim about a MUTATION, not about the file's row count,
# and a mutation table's `name  N  MOVED  rows...` lines are the harness's, so
# both are outside the count grammar.
MOVED_RE = re.compile(r"\b(moved|kills|closes|moves)\s+\d+\s+rows?\b")
MUTATION_RE = re.compile(r"\b(moved|MOVED|EQUIV|BLIND|rows moved|ROWS MOVED)\b")
RETRACT_RE = re.compile(r"\b(never written|does not exist|no such|previously named|"
                        r"was deleted|is not a def|nothing called it)\b")
# "CPython's `Foo.bar`" names a Python attribute and is checked by the wall pass.
CPYTHON_RE = re.compile(r"\b(CPython|Python'?s?|python'?s?)\b")
# every committed .bend, for cross-file def claims. Loaded once; a header that
# says "ops_webgpu's Tr.pop" is only checkable because the other file is here.
# the TEXT is read once, at import: thirteen agents are live and a concurrent
# `rm` of a scratch .bend between the glob and the read crashed the audit.
BEND_FILES = [(p, p.read_text()) for p in ROOT.rglob('*.bend')
              if '.agents' not in p.parts and '.git' not in p.parts]
PYMOD = {
    'nv/ip': 'tinygrad/runtime/support/nv/ip.py', 'ip': None,
}
PYFILE = re.compile(r"[A-Za-z_0-9./-]+\.py\b")
# directories that hold COPIES or venvs, never the source a header cites
SCRATCH = {'.agents', '.git', '.venv', 'references', '__pycache__',
           'tinygrad.egg-info'}


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
    """The file's claim block. Usually the leading comment, but a file that puts
    its `import`s first has NO leading comment, and returning empty for it made
    three big files (`PROOF.bend`, `sz.bend`, `tensor.bend`, 1675 and 1583 lines)
    report zero claims checked. Their first claim block is the header.
    """
    out = []
    for line in lines:
        s = line.lstrip()
        if s.startswith('#') or s == '':
            out.append(line)
        else:
            break
    if out:
        return out
    for blk in comment_blocks(lines):
        if blk[0][0] <= 40:
            return [l for _, l in blk]
    return []


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


prefer = None
# the `.py` paths the audited file names as the thing it ports, filled in per file
PORT_TARGETS = []


def pyfile(name, _busy=False):
    """A `.py` name as the header writes it -> a real path, or None.

    Headers write the module SHORT -- `examples/beautiful_mnist.py`,
    `mixin/op.py` -- so the whole repo is searched, not just `tinygrad/`, and a
    directory-qualified short name is preferred over a bare basename.

    A BARE basename with more than one match is resolved by the audited file's
    OWN PORT TARGET: a `.bend` that is `tinygrad/mixin/rand.bend` reaches
    `mixin/`, not `codegen/decomp/`. Passing `prefer` is how that is expressed,
    and a basename that STILL does not resolve is reported rather than guessed --
    guessing is how a stale wall survives.
    """
    if name.startswith('tinygrad/') or name.startswith('references/'):
        return ROOT / name
    # a DIRECTORY-QUALIFIED name is its own disambiguation. `prefer` must never
    # override it: `uop/spec.bend` citing `schedule/__init__.py:182` was resolved
    # against `uop/__init__.py` (135 lines) and reported as an out-of-range ref,
    # which is a false problem caused by the audit, not by the header.
    # `.agents/slop/opstree/` holds a COPY of tinygrad, so an unfiltered rglob
    # makes `render.py` ambiguous and the audit reports a false problem. Scratch
    # trees are not sources; exclude them the way `references/` is excluded.
    # The filter is applied BEFORE every branch, because a directory-qualified
    # name is still ambiguous against a scratch copy of the same directory.
    hits = [p for p in ROOT.rglob(Path(name).name) if p.suffix == '.py'
            and not SCRATCH & set(p.parts)]
    if '/' in name:
        parts = tuple(name.split('/'))
        hits = [p for p in hits if p.parts[-len(parts):] == parts]
        return hits[0] if len(hits) == 1 else None
    if len(hits) == 1:
        return hits[0]
    # the audited file's OWN PORT TARGET disambiguates a bare basename. A .bend
    # states its target in its first line -- "kernel.bend -- tinygrad/codegen/
    # __init__.py" -- so a bare `__init__.py` or `op.py` resolves to the module
    # that file says it ports, and this repo has sixty `__init__.py`.
    same = {pyfile(m, _busy=True) for m in PORT_TARGETS} if not _busy else set()
    same = [t for t in same if t and t.name == Path(name).name]
    if len(same) == 1:
        return same[0]
    # prefer the module that lives in the same package as the audited .bend
    if prefer:
        tag = Path(prefer).parts[-2]
        tagged = [p for p in hits if tag in p.parts]
        if len(tagged) == 1:
            return tagged[0]
    return None


def bendfile(name):
    """A `.bend` name as a header writes it -> a real path, or None."""
    hits = list(ROOT.rglob(name))
    hits = [h for h in hits if '.agents' not in h.parts]
    return hits[0] if len(hits) == 1 else (hits[0] if hits else None)


def is_code_frag(frag):
    """Is a quoted span CODE rather than PROSE that happened to be quoted?

    The test is structural, not lexical: a quote of source has a bracket or an
    assignment in it, or is a single dotted NAME. A quote of English does not --
    and the difference matters because `ops.py:497 ranges` P3, and says why:
    `_ranges` pairs the citation with the PROSE between it and the next quote,
    which a looser test accepts and this one does not.
    """
    if frag != frag.strip():
        return False
    if any(c in frag for c in '()[]{}='):
        return True
    return len(frag.split()) <= 2 and not any(c in frag for c in ':,')


def cited_line_holds(f, hdr_line, ln):
    """Does `f:ln` contain the code the citing line says it does?

    "`ops.py:1609` is `if not early_reject.issubset(ler): continue`" is a claim
    about CONTENT, and an in-range check cannot see it: in-range `ops.py:1609` sat
    on a blank line while the sentence it belonged to was three lines off.

    The connector class excludes digits, `.`, `:` and `(`, so it cannot walk past
    a SECOND citation on the same line and pair one ref with another's fragment.
    Every content citation on the line is checked, not just the first.
    """
    src_lines, ok = None, True
    # a `TODO(pN) mod.py:N sym` wall is checked by its OWN pass, against the
    # symbol at that line; the content check would pair it with the prose that
    # follows and read the prose as the quote.
    if 'TODO(p' in hdr_line:
        return True
    # a line naming TWO Python files cannot attribute a quote to either: "`sort`
    # -> `.contiguous()` (elementwise.py:59) is `graph_rewrite` (ops.py:1880)"
    # offers three citations and three quotes in one sentence.
    if len(set(PYFILE.findall(hdr_line))) > 1:
        return True
    for m in CITE_RE.finditer(hdr_line):
        gap, frag = m.group(3), m.group(4)
        # the gap between a ref and its quote is a CONNECTOR, and a connector
        # holds no parentheses and no second ref: `(`# TODO(p3) ops.py:513`) and
        # the whole` pairs 513 with the NEXT span, not with its own. The lazy
        # `{0,40}?` plus the paren test is what stops that, because a regex
        # backtracks an optional backtick and finds a quote further along.
        if ('(' in gap or ')' in gap or '.py' in gap
                or not re.fullmatch(r'[\s]*(is|are|was|were|reads?|says?|--'
                                    r'|[:,=])?[\s]*', gap)):
            continue
        # a CONNECTOR is not a SENTENCE: `, into two lists.` between a citation
        # and its quote means the quote belongs to the next clause, and the
        # prose-shaped gap is how a type name (`Maybe`) gets read as a quote of
        # the cited line.
        if ', ' in gap or '. ' in gap or ':' in gap:
            continue
        if not is_code_frag(frag) or '.py' in frag or ONLYLINE_RE.match(frag):
            continue
        if src_lines is None:
            src_lines = f.read_text().splitlines()
        ln = int(m.group(2))
        if ln > len(src_lines):
            continue
        cited_ids = set(IDENT_RE.findall('\n'.join(src_lines[ln - 1:ln + 1])))
        # a fragment names an ATTRIBUTE half the time -- `dtypes.weaks` for a
        # line that reads `weaks = (weakint, weakfloat)` -- so the last segment
        # of a dotted identifier is also a thing the line can hold.
        frag_ids = set(IDENT_RE.findall(frag)) - PY_KW
        frag_ids |= {t.split('.')[-1] for t in frag.split() if '.' in t}
        if not frag_ids & cited_ids:
            ok = False
    return ok


# `tinygrad/codegen/gpudims.py   97 lines   gpu dims (late)` -- a per-file LINE
# COUNT for a PYTHON file, which COUNT_RE cannot check (it counts .bend lines,
# .bend rows and .bend defs) and which is the claim that actually goes stale:
# two headers in this tree disagreed with `wc -l` here.
PYCOUNT_RE = re.compile(r"([A-Za-z_0-9/]+\.py)\s+(\d+)\s+lines")
# "the three Python files' 421 lines" is a SUM over a named subset and the tool
# cannot tell which subset, so it is reported as unchecked rather than as a
# falsehood against the .bend's own line count.
PYSUM_RE = re.compile(r"\bPython files?\b")


def wc_l(f):
    """`wc -l`, not `splitlines()`: the repo's headers count lines the way every
    header in it is written, and a file whose last line has no newline is `wc -l`
    one shorter than `splitlines()` says. Flagging that is a false problem."""
    return f.read_text().count('\n')


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
        globals()['prefer'] = p
        lines = path.read_text().splitlines()
        hdr = header(lines)
        globals()['PORT_TARGETS'] = PYFILE.findall('\n'.join(hdr))
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

        if mode in ('--inv', '--inv-fix'):
            # A row's PYTHON line range is a claim about ONE file, so a row has to
            # be bound to its file before the range means anything. The binding is
            # the last `#  -- <path>.py ----` section marker above the row; a file
            # with no markers is checked against every `.py` its header names,
            # because then the row's own symbol is the only disambiguator left.
            # Without the binding, `pm_split_ranges 79-82` is "not in
            # coalesce.py, not in gpudims.py, not in simplify.py at 79-82" and the
            # audit cries wolf on every row of a three-file table.
            SEC_RE = re.compile(r"^#\s*--\s*([A-Za-z_0-9./{}-]+\.py)")
            named = [pyfile(m) for m in PYFILE.findall('\n'.join(hdr))]
            named = [t for t in named if t]
            rows, sect = [], None
            for i, l in enumerate(lines, 1):
                s = SEC_RE.match(l)
                if s:
                    nm = s.group(1).strip('{}')
                    sect = pyfile(nm) or pyfile(nm.split('/')[-1])
                    continue
                m = INV_RE.match(l)
                if m:
                    rows.append((i, m, sect))
            print('  %d inventory rows, %d section markers, targets: %s'
                  % (len(rows), sum(1 for l in lines if SEC_RE.match(l)),
                     ', '.join(sorted({str(t.relative_to(ROOT))
                                      for t in named})) or 'NONE'))
            fixes = []
            for i, m, sect in rows:
                num, a, b, kind, sym = (m.group(1), int(m.group(2)),
                                        int(m.group(3) or m.group(2)),
                                        m.group(4), m.group(5))
                sym0 = sym
                if '/' in sym:
                    sym = sym.split('/')[0]
                cand = [sect] if sect else named
                hit = [t for t in cand if sym in
                       '\n'.join(t.read_text().splitlines()[max(0, a - 4):b + 3])]
                if hit:
                    continue
                truth = {}
                for t in cand:
                    src = t.read_text().splitlines()
                    for k, sl in enumerate(src, 1):
                        if re.search(r'^(def |class )?%s\b' % re.escape(sym), sl):
                            truth[t] = k
                            break
                if len(truth) == 1:
                    t, k = next(iter(truth.items()))
                    fixes.append((i, a, b, '%s:%d' % (t.name, k)))
                    print('  FALSE  hdr:%d row %s %s %d-%d `%s` -- it is at %s:%d'
                          % (i, num, kind, a, b, sym0, t.name, k))
                else:
                    print('  FALSE  hdr:%d row %s %s %d-%d `%s` -- not in %s'
                          % (i, num, kind, a, b, sym0,
                             ', '.join(t.name for t in cand) or 'NO TARGET'))
                false_n += 1
            if mode == '--inv-fix':
                print('\n'.join('%d:%d-%d->%s' % f for f in fixes))
            print('  %d inventory claims checked' % len(rows))
            continue

        seen = set()
        claims_n = 0
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
                print('  FALSE  hdr:%d TODO(%s) %s:%d %s -- %s has %d lines'
                      % (i, m.group(1), mod, ln, sym, f, len(src)))
                false_n += 1
                continue
            body_line = src[ln - 1]
            ok = (not sym) or sym in body_line
            if not ok:
                print('  FALSE  hdr:%d TODO(%s) %s:%d %s -- %s:%d is: %s'
                      % (i, m.group(1), mod, ln, sym, f.relative_to(ROOT),
                         body_line.strip()[:66]))
                false_n += 1
        # --- 2. every backticked def-ish token in ANY comment block. A token only
        # CLAIMS a local def if its namespace is one this file defines -- that is
        # what separates `pc.key` (a claim about a local def) from `NVQueue.q`
        # (a Python name) and `U32.or` (a Bend core name).
        printed = '\n'.join(outs)
        # a row is `name=value`, and a header's `` `llvm.code_for_op` `` is a
        # claim about a ROW just as much as about a def. Both count.
        printed_names = {l.split('=')[0].strip() for l in outs}
        # some rows are `NAME key=value` -- `lop.op ADD=...` -- so a header may
        # name the PREFIX and claim a row count. Keep the prefix set too.
        printed_prefix = {n.split()[0] for n in printed_names if ' ' in n}
        ns = {n.split('.')[0].lower() for n in names if '.' in n}
        # a Markdown table whose HEADER names a mutation names its rows after
        # EDITS, not defs: `| dc_s0.pat: drop the ... conjunct | on_s2 | ... |`.
        # `.pat` is not a Bend suffix and the row is a diff, so the table's own
        # header is what makes it a mutation table and nothing else does.
        MUTTAB_RE = re.compile(r"\|\s*(mutation|rows moved|what it catches)\s*\|")
        for blk in comment_blocks(lines):
            muttab = any(MUTTAB_RE.search(l) for _, l in blk)
            for i, line in blk:
                # a line that names a `.py`, or a bare `:NN`, is talking about
                # PYTHON: "`Estimates.from_uops` (:26)" cites a method of a class
                # the same name as a local def, which is a naming coincidence and
                # not a claim about a Bend def.
                if PYFILE.search(line) or ONLYLINE_RE.search(line):
                    continue
                if muttab and line.lstrip('# ').startswith('|'):
                    continue
                for tok in TOKEN_RE.findall(line):
                    key = ('tok', tok)
                    if key in seen or tok in names:
                        continue
                    seen.add(key)
                    claims_n += 1
                    if '.' not in tok or tok.endswith('.'):
                        continue
                    # a `.py` is a FILE, not a def: `function.py`, `op.py:198`
                    if tok.endswith('.py'):
                        continue
                    # `CPython's X.y` names a PYTHON attribute; a dunder cannot be
                    # a Bend def name in any of these files.
                    if '__' in tok or CPYTHON_RE.search(line):
                        continue
                    if tok.split('.')[0].lower() not in ns:
                        continue
                    if tok in printed_names or tok in printed_prefix:
                        continue
                    if tok.lower() in lower:
                        print('  FALSE  hdr:%d `%s` -- the def is spelled `%s`'
                              % (i, tok, lower[tok.lower()]))
                        false_n += 1
                        continue
                    # a claim about ANOTHER .bend file's def is checkable and is
                    # the shape that retires a wall, so resolve it.
                    if any(re.search(r'^(def|type) ' + re.escape(tok) + r'\b', txt, re.M)
                           for _, txt in BEND_FILES):
                        continue
                    # a MUTATION name is a claim about the mutation harness, not
                    # about a def, and a retracted name is a claim about the
                    # draft. Both are true when they say so. The window is the
                    # token's own line and its two neighbours, because prose
                    # WRAPS: "used to name two defs, `a.b` and / `c.d`, that were
                    # never written" puts the retraction on the last line and the
                    # first name two above it, and a per-line test reads the
                    # retraction as not applying to the name it retracts.
                    near = '\n'.join(l for _, l in blk
                                     if i - 2 <= _ <= i + 2)
                    if MUTATION_RE.search(near) or RETRACT_RE.search(near):
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
        # an INVENTORY table -- `#  12  108-125 fold  reduce_collapse  WALL: ...`
        # -- numbers the PYTHON file's defs, so "43 defs" under one is a claim
        # about the table and not about the .bend file's own def count.
        inv_rows = [m for m in (INV_RE.match(l) for l in lines) if m]
        inv_max = max((int(m.group(1)) for m in inv_rows), default=None)
        subject = None
        for i, line in enumerate(hdr, 1):
            # per-file line counts for a PYTHON file, checked against that file
            for pym, pn in PYCOUNT_RE.findall(line):
                pf = pyfile(pym)
                if pf is None:
                    continue
                claims_n += 1
                real = wc_l(pf)
                if int(pn) != real:
                    print('  FALSE  hdr:%d claims %s is %s lines; it is %s'
                          % (i, pym, pn, real))
                    false_n += 1
            if MOVED_RE.search(line) or PYSUM_RE.search(line):
                continue
            # "that is most of why it is 247 lines and this is 1671" -- `it` is
            # `sz.odin`, a file outside this repo, and a count about a file this
            # repo does not hold is not this file's line count.
            ext = re.search(r"\.\w{2,5}\b", line) or re.search(
                r"\.\w{2,5}\b", window)
            if ext and ext.group(0) not in ('.py', '.bend'):
                continue
            # "transcendental.py (277 lines)" is a claim about the PYTHON file and
            # is checked by the TODO/wall pass, not by the `.bend` counter. The
            # window is the four header lines ABOVE this one, which is hdr[i-5:i]:
            # a window ending at hdr[i] starts one line too late and missed the
            # `.py` mention that disqualifies the line, which is how
            # "the three Python files' 421 lines" got charged to `kernel.bend`.
            window = '\n'.join(hdr[max(0, i - 5):i])
            if PYFILE.search(window) and not OTHER.search(line):
                continue
            if SPLIT_RE.search(line):
                m = SPLIT_RE.search(line)
                claims_n += 1
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
            elif subject and (not OTHER.search(window) or PYFILE.search(line)
                              or re.search(r'\bPython\b', line)):
                subject = None
            if subject and subject != path.name:
                c = bend_counts(subject)
                if c:
                    for n, what in COUNT_RE.findall(line):
                        claims_n += 1
                        truth = {'lines': c[0], 'defs': c[1]}.get(what)
                        if truth is None or int(n) == truth:
                            continue
                        print('  FALSE  hdr:%d claims %s is %s %s; it is %s'
                              % (i, subject, n, what, truth))
                        false_n += 1
                    continue
            for n, what in COUNT_RE.findall(line):
                claims_n += 1
                truth = {'rows': len(outs), 'lines': len(lines),
                         'defs': len(defs)}.get(what)
                if truth is None or int(n) == truth:
                    continue
                # "43 defs" printed directly under a 43-row inventory is a claim
                # about the TABLE. The inventory's own last index is the truth.
                if inv_max is not None and what == 'defs' and int(n) == inv_max:
                    continue
                # "37 rows over 35 defs" under a 37-row inventory is a claim
                # about the TABLE, and the table's count is the truth for it
                if inv_max is not None and re.search(
                        r'inventor|rows over|\btable\b', line):
                    if int(n) == inv_max or what == 'defs':
                        continue
                # say what the inventory table says too, so "22 defs" under a
                # 32-row inventory is reported as the contradiction it is
                extra = '' if inv_max is None or int(n) == inv_max else (
                    ', inventory numbers %d' % inv_max)
                print('  FALSE  hdr:%d claims %s %s; file has %s%s'
                      % (i, n, what, truth, extra))
                false_n += 1
        # --- 4. Python line refs, in EVERY comment block, not just the header.
        # A wall is written where the code is, not only at the top: spec.bend
        # cites `spec.py:88` for the BACKEDGE rule in a mid-file gate table and
        # the real UPat is at 89, and the header pass never looked there.
        seen_ref = set()
        for blk in comment_blocks(lines):
            for i, line in blk:
                for mod, ln in PYREF_RE.findall(line):
                    if not ln:
                        continue
                    key = ('ref', mod, ln)
                    if key in seen_ref:
                        continue
                    seen_ref.add(key)
                    claims_n += 1
                    f = pyfile(mod)
                    if f is None:
                        amb = [p for p in ROOT.rglob(Path(mod).name)
                               if p.suffix == '.py' and not SCRATCH & set(p.parts)]
                        note = (' AMBIGUOUS: %s' % ', '.join(
                            str(p.relative_to(ROOT)) for p in amb)) if amb else ''
                        # an ambiguous basename MASKS an out-of-range ref: the
                        # ambiguity is reported instead of the falsehood, and
                        # `helpers.py:1326` in a 646-line helpers.py is exactly
                        # that. So the line count is checked against the LARGEST
                        # candidate, and an ambiguity that cannot hold the line
                        # says so.
                        if amb:
                            mx = max(len(p.read_text().splitlines())
                                     for p in amb)
                            note += ' (longest is %d lines)' % mx
                            if mx < int(ln):
                                print('  FALSE  hdr:%d `%s:%s` -- NO candidate has'
                                      ' that many lines.%s'
                                      % (i, mod, ln, note))
                                false_n += 1
                                continue
                        print('  FALSE  hdr:%d `%s` -- no unique such Python file.%s'
                              % (i, mod, note))
                        false_n += 1
                    elif int(ln) > len(f.read_text().splitlines()):
                        print('  FALSE  hdr:%d `%s:%s` -- %s has %d lines'
                              % (i, mod, ln, f.relative_to(ROOT),
                                 len(f.read_text().splitlines())))
                        false_n += 1
                    elif not cited_line_holds(f, line, int(ln)):
                        src = f.read_text().splitlines()
                        print('  FALSE  hdr:%d `%s:%s` -- that line is: %s'
                              % (i, mod, ln,
                                 src[int(ln) - 1].strip()[:66]))
                        false_n += 1
        # a CLAIM is a name, a line ref or a count, and the per-file total is the
        # only number that says whether a header was audited or merely read.
        print('  %d claims checked' % claims_n)
    print('\n%d FALSE claims' % false_n)
    return 1 if false_n else 0


if __name__ == '__main__':
    sys.exit(main())
