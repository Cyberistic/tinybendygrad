#!/usr/bin/env python3
"""The cross-file qualifier every 1:1 SPLIT needs, and the four positions that are
NOT call sites. Written once after three splits each lost an hour to a different one.

WHAT IT DOES. When `X`'s defs move into a file that `Y` imports as `A`, every mention
in `Y` of a name declared in `X` -- a CALL, and also a TYPE MENTION -- needs the
`A.` prefix. A type mention needs it because bend 2.0.34 does NOT put an imported
`type` name in scope unqualified: `Baz{f: Foo}` with `Foo` declared in another file
answers "expected: a defined name / observed: Foo", while `Baz{f: A.Foo}` compiles.

THE FOUR POSITIONS THAT ARE NOT CALL SITES. Each of these produced a compile error
that read like a missing def and was not one:

1. `def <name>(` -- a DECLARATION. Qualifying it renames the def and bend rejects it
   with "expected : a fresh name (C is an import's alias)".
2. `case X{f1, f2}` -- the BINDERS are field names. `case Nk{dev, nm, key}` names the
   field `key`; qualifying the `key` inside makes the constructor unreachable. Only
   the CONSTRUCTOR before `{` is a candidate.
2b. `case x <> +r : ...` -- the same trap in POSITIONAL form. `+r` is a linear
   resource binder and it shadows the port's `r`; qualifying it gives `case t <> +T.r`
   and bend answers "expected a quantified datatype after +". So a `case` LINE is
   handled as a pattern line whatever its shape: only an identifier immediately
   followed by `{` is a constructor, everything else that is a bare name in the
   pattern is a binder.
3. `case X{f1, f2}: <body>` / `case <pat>: <body>` -- the BODY after `:` IS a normal
   expression, but a bare binder in it SHADOWS the port's same-named def:
   `case Nk{dev, nm, key}: key` returns the field, and `C.key` turns it into the
   port's `key` def. The shadowed occurrences are skipped BY POSITION -- a sentinel
   character is not a word character, so it does not stop the lookbehind from
   matching and a textual mask silently fails.
4. The whole line is a comment, or a `type ... is` declaration whose NAME is the thing
   being declared.

AND `(?![\\w.])`, not `(?![\\w])`: with the weaker lookahead a bare `Tr` matches the
prefix of `Tr.assert_at`, so a call to a def that lives in the file being written
becomes `C.Tr.assert_at`, which does not exist.

AND NOTHING INSIDE A STRING LITERAL IS EVER SUBSTITUTED. The row count did not catch
this one -- `renderer/tc_ptx.bend`'s gate stayed at 620 lines -- and only the byte diff
did: the PTX register `%r1` inside `"mov.b32 %r0, %r1;"` became `"%T.r1"`, because
`r1` is also a `tc.py` def. Both lanes then agreed, because the row's `py=` half is a
literal in the file and the substitution hit BOTH. A row whose port and whose oracle
are the same string cannot report its own corruption.
"""
import re

CASE  = re.compile(r'^(\s*case\s+)(.*?)(\s*:\s*)(.*)$')
CTOR  = re.compile(r'(?<![\w.])[A-Za-z_][A-Za-z0-9_]*\{')
DEFN  = re.compile(r'^(\s*def\s+)([A-Za-z_][A-Za-z0-9_.]*)(.*)$')
STR   = re.compile(r'"[^"]*"')


def declared(lines):
    """every top-level name a slice of defs declares, dotted names included"""
    out = []
    for l in lines:
        m = re.match(r'\s*def ([A-Za-z_][A-Za-z0-9_.]*)\s*[\(<]', l)
        if m: out.append(m.group(1))
        m = re.match(r'\s*type ([A-Za-z_][A-Za-z0-9_]*)\s+is\b', l)
        if m: out.append(m.group(1))
    return out


def qualifier(names, alias):
    """names: iterable of names declared in the file being IMPORTED. Returns a function
    that rewrites one list of source lines for the importing file."""
    pat = re.compile(r'(?<![\w.])(%s)(?![\w.])' %
                     '|'.join(re.escape(n) for n in sorted(set(names), key=len, reverse=True)))

    def sub(x):
        return alias + '.' + x.group(1)

    def body(b, spans=()):
        def guarded(x):
            return (x.group(0) if any(s <= x.start() < e for s, e in spans)
                    else alias + '.' + x.group(1))
        return pat.sub(guarded, b)

    def binders(pat_txt):
        """every bare name in a `case` PATTERN is a binder: a field name in the
        `{f1, f2}` form, a resource name in the `x <> +r` form. `case Nil{}`,
        `case _ <> _` and `case Some{+x}` bind nothing that can collide."""
        out = set()
        for part in re.split(r'[,{}\s]+', pat_txt):
            part = part.split('<>')[-1].lstrip('+-').strip()
            if re.fullmatch(r'[A-Za-z_][A-Za-z0-9_]*', part) and part not in ('_', 'Nil'):
                out.add(part)
        return out

    def ctors(pat_txt):
        return {m.group(0)[:-1] for m in CTOR.finditer(pat_txt)}

    def spans_of(txt, mask):
        out = [(m.start(), m.end()) for m in STR.finditer(txt)]
        for name in mask:
            for m in re.finditer(r'(?<![\w.])%s(?![\w.])' % re.escape(name), txt):
                out.append((m.start(), m.end()))
        return out

    def apply_(lines):
        out = []
        # a `case` arm's binder shadows for the WHOLE ARM, which is several lines, so
        # the mask has to survive past the line that introduced it: `case t <> +r :`
        # followed by `+rest = f(r, acc)` on the next line is the same trap as
        # `case Nk{dev, nm, key}: key`, one dedent further out.
        stack = []
        for l in lines:
            indent = len(l) - len(l.lstrip())
            if l.strip() and l.lstrip().startswith('#'):
                out.append(l); continue
            if l.lstrip().startswith('type '):
                out.append(l); continue
            m = CASE.match(l)
            if m:
                head, pat_txt, colon, bod = m.groups()
                # a name in the PATTERN is a BINDER unless it is a CONSTRUCTOR, and the
                # test is the `{` and nothing else -- `case t <> +r` binds a resource
                # named `r` that shadows the port's `r`, and dropping `r` from the mask
                # because `r` is also an imported def is the whole bug.
                mask = binders(pat_txt) - ctors(pat_txt)
                stack = [(i, s) for i, s in stack if i < indent]
                stack.append((indent, mask))
                pspans = spans_of(pat_txt, mask)
                def psub(x):
                    nm = x.group(0)[:-1]
                    if nm not in names or any(s <= x.start() < e for s, e in pspans):
                        return x.group(0)
                    return alias + '.' + nm + '{'
                out.append(head + CTOR.sub(psub, pat_txt) + colon + body(bod, spans_of(bod, mask)))
                continue
            m = DEFN.match(l)
            if m:
                stack = []
                out.append(m.group(1) + m.group(2) + body(m.group(3)))
                continue
            live = set().union(*[s for i, s in stack if i <= indent]) if stack else set()
            out.append(body(l, spans_of(l, live)))
        return out
    return apply_


def hits(names, text, alias=None):
    """which of `names` this text mentions -- the diagnostic a split prints"""
    pat = re.compile(r'(?<![\w.])(%s)(?![\w.])' %
                     '|'.join(re.escape(n) for n in sorted(set(names), key=len, reverse=True)))
    return sorted({m.group(1) for m in pat.finditer(text)})


def entries(lines, first, rx=re.compile(r'#\s+M\d+[a-z]?\s')):
    """the measured-mutation block, parsed into one entry per M-line"""
    out, cur = [], None
    for l in lines:
        if rx.match(l):
            cur = [l]; out.append(cur)
        elif cur is not None:
            cur.append(l)
        elif l.strip() and not l.lstrip().startswith('#'):
            raise SystemExit('mutation list starts mid-entry: ' + l)
    return out
