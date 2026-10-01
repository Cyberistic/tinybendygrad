#!/usr/bin/env python3
"""hoist-loop.py -- drive ./bin/bend and fix the two mechanical classes of error
this file keeps hitting, one compile at a time:

  * "expected : a filled definition ... observed : NAME"  -> NAME is used above
    where it is declared. Move NAME's whole def (and the defs it needs, which the
    compiler will then name in turn) above its first use.
  * "consumed more than once" for parameter P of def D -> add `+` to P.

Prints what it did, so a reviewer can see the diff is mechanical. NEVER run this
on a shared file.
"""
import re, subprocess, sys, os

BEND = './bin/bend'
path = sys.argv[1]
LIMIT = int(sys.argv[2]) if len(sys.argv) > 2 else 40


def compile_err():
    r = subprocess.run([BEND, path, '--check-only'], capture_output=True, text=True)
    return r.stdout + r.stderr


def def_span(text, name):
    """(start, end) of `def name(...)` including its body and trailing blank."""
    m = re.search(r'^def %s\(' % re.escape(name), text, re.M)
    if not m: return None
    i = m.start()
    lines = text[i:].split('\n')
    out = []
    for k, L in enumerate(lines):
        out.append(L)
        if k > 0 and L.startswith('def ') or (k > 0 and L.startswith('type ')):
            break
    # trim the trailing def header that terminated the scan
    if len(out) > 1 and (out[-1].startswith('def ') or out[-1].startswith('type ')):
        out = out[:-1]
    end = i + len('\n'.join(out))
    return (i, end, '\n'.join(out))


for step in range(LIMIT):
    err = compile_err()
    if 'ALL PROOFS CHECK' in err:
        print("CLEAN after %d steps" % step)
        sys.exit(0)
    m = re.search(r'expected : a filled definition.*?\n- observed : (\S+)', err, re.S)
    if m:
        name = m.group(1)
        text = open(path).read()
        sp = def_span(text, name)
        if not sp:
            print("cannot find def", name); sys.exit(1)
        i, e, blk = sp
        rest = text[:i] + text[e:]
        # first use = the first line mentioning `name(` outside the block
        uses = [mm.start() for mm in re.finditer(r'\b%s\(' % re.escape(name), rest)]
        if not uses:
            print("no use of", name); sys.exit(1)
        at = uses[0]
        # walk back to the `def` line that CONTAINS the use, and to the comment
        # block above it, so the moved def lands above a whole def and not inside
        # one. Landing mid-def is what produces "the keyword 'def' cannot head
        # one" -- the second failure this loop has to survive.
        bol = rest.rfind('\n', 0, at) + 1
        linestart = bol
        while True:
            prev_end = rest.rfind('\n', 0, linestart - 1) + 1
            prev = rest[prev_end:linestart]
            if prev.startswith('#') or prev == '':
                linestart = prev_end
                continue
            break
        rest = rest[:linestart] + blk + '\n\n' + rest[linestart:]
        open(path, 'w').write(rest)
        print("hoisted", name)
        continue
    m = re.search(r'expected : (\w+)\n- observed : \1 \(consumed more than once\)', err)
    if m:
        print("AFFINITY ERROR not auto-fixable:", m.group(1)); sys.exit(2)
    print(err[:900]); sys.exit(3)
print("gave up"); sys.exit(4)
