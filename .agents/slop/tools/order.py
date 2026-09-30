"""Topologically order the defs of a Bend file, preserving each def's own header.

Bend has no forward references, so a def may only call defs written above it and
mutual recursion is refused.  Hand-ordering a 200-def port is where the compile
cycles go, so this does it -- and it refuses to write unless the set of def names
and the set of bodies are both unchanged, which is the check the earlier scripted
splice in this project failed.
"""
import re
import subprocess
import sys

path, bend = sys.argv[1], sys.argv[2]


def units_of(lines):
    """Split into (header_lines, def_lines) units, in source order."""
    units, i, n = [], 0, len(lines)
    while i < n:
        if not re.match(r'^(def|type) ', lines[i]):
            i += 1
            continue
        # the contiguous comment/blank run directly above is this def's header
        h = i
        while h > 0 and (lines[h - 1].startswith('#') or lines[h - 1].strip() == ''):
            h -= 1
        j = i + 1
        while j < n and (lines[j].strip() == '' or lines[j][:1] in (' ', '\t')):
            j += 1
        units.append([lines[h:i], lines[i:j]])
        i = j
    return units


def name_of(defs):
    m = re.match(r'^(?:def|type) ([\w.]+)', defs[0])
    return m.group(1) if m else None


def main():
    src = open(path).read()
    lines = src.split('\n')
    # the file header and the imports are a fixed prologue: they are not defs and
    # they must stay at the top, so the reordering starts after them
    first = next(i for i, l in enumerate(lines) if re.match(r'^(def|type) ', l))
    while first > 0 and (lines[first - 1].startswith('#') or lines[first - 1].strip() == ''):
        first -= 1
    prologue, units = lines[:first], units_of(lines[first:])
    names = [name_of(u[1]) for u in units]
    assert all(names), 'a def with no name: ' + repr([u for u, nm in zip(units, names) if not nm])

    ident = re.compile(r'[\w.]+')
    deps = {}
    for nm, u in zip(names, units):
        body = '\n'.join(u[1])
        found = set(ident.findall(body))
        # a def's own name inside its body is recursion, not a dependency on itself
        found.discard(nm)
        deps[nm] = {d for d in found if d in names and d != nm}

    # Kahn, stable: among the ready set take the earliest in source order
    out, done = [], set()
    while len(out) < len(units):
        ready = [i for i, nm in enumerate(names) if nm not in done and deps[nm] <= done]
        if not ready:
            # a cycle: fall back to source order for the rest so the file is still
            # written, and let the Bend compiler name the offending pair
            ready = [i for i, nm in enumerate(names) if nm not in done]
        pick = min(ready)
        out.append(units[pick])
        done.add(names[pick])

    # a unit's trailing blank lines overlap the next unit's leading ones, so
    # emitting both DOUBLES the blank run on every pass -- measured: twelve passes
    # turned a 1500-line file into 4.4 million lines. Normalise instead.
    units_out = ['\n'.join([l for l in (h + d) if l.strip() != '']) + '\n' for h, d in out]
    text = '\n'.join(prologue + units_out)
    # SAFETY, and it is not optional. An earlier version of this tool put a
    # trailing comment block -- one with no def after it, so no unit to ride on --
    # at the end of the file and DROPPED IT on the next pass. Three checks:
    #   * the same multiset of DEF NAMES
    #   * the same multiset of def BODIES, comments included
    #   * the same multiset of EVERY non-blank LINE, so a comment block that
    #     belongs to no def cannot go missing
    assert sorted(name_of(u[1]) for u in units) == sorted(name_of(u[1]) for u in out)
    assert sorted('\n'.join(u[1]) for u in units) == sorted('\n'.join(u[1]) for u in out)
    before = sorted(l for l in lines if l.strip() != '')
    after = sorted(l for l in text.split('\n') if l.strip() != '')
    missing = [l for l in before if before.count(l) > after.count(l)]
    assert not missing, 'order.py would DROP %d line(s), first: %r' % (len(missing), missing[:1])
    if text != src:
        open(path, 'w').write(text)
        print(f'reordered {len(units)} defs, {sum(1 for a, b in zip(units, out) if a is not b)} moved')
    else:
        print('already ordered')


main()
