import re

READERS = {
'BArg': '''

# THE READERS. A LOCALLY-DECLARED `Data` RECORD HAS NO PROJECTION SYNTAX AT ALL,
# so `BArg.addr(b)` is "a defined name" until `def BArg.addr` is written by hand.
# MEASURED on 2.0.34 with a three-field record: `BArg.image(b)` and `BArg.name(b)`
# are both refused, and so is a field whose NAME ENDS IN `_` -- which is the
# `volatile` escape of bend2-constraints rule 25 turning out to have no
# projection even after it, so the escape buys the reader and costs nothing else.
# An IMPORTED record's projections DO exist -- `O.Arena.op(ar, i)` and
# `O.ParamArg.slot(pa)` are the whole of `renderer/__init__.bend`'s vocabulary --
# so this is a rule about where the type was DECLARED and not about its kind.
# Each reader is one `match` naming EVERY field, which is convention 6 and is also
# why adding a field to one of these records is a one-line change per reader.
''',
'Uses': '''
''',
'Emit_': '''
''',
'RkIn': '''
''',
}

def readers(ty, fields, pat):
    out = []
    for f in fields:
        out.append(f"def {ty}.{f}(x: {ty}) -> {tys[f]}:")
        out.append("  match x:")
        out.append(f"    case {pat}: {f}")
        out.append("")
    return '\n'.join(out)

TYS = {
 'BArg': {'name': 'String', 'dtype': 'S.Dt', 'addr': 'S.Addr', 'mutable': 'Bool', 'volatile_': 'Bool', 'image': 'Bool'},
 'Uses': {'half': 'Bool', 'bf16': 'Bool', 'fp8': 'Bool', 'nonfinite': 'Bool', 'special': 'Bool', 'half_any': 'Bool'},
 'Emit_': {'uses': 'Uses', 'vecs': 'List<&2, String>', 'ockl': 'List<&2, String>', 'ocml': 'List<&2, String>',
           'caller': 'List<&2, String>', 'has_prefix': 'Bool'},
 'RkIn': {'pref': 'List<&2, String>', 'has': 'Bool', 'bufs': 'List<&2, BArg>', 'body': 'List<&2, String>'},
}
BIND = {'BArg': 'b', 'Uses': 'u', 'Emit_': 'e', 'RkIn': 'i'}
PARS = {
 'BArg': "case BArg{name, dtype, addr, mutable, volatile_, image}:",
 'Uses': "case Uses{half, bf16, fp8, nonfinite, special, half_any}:",
 'Emit_': "case Emit_{uses, vecs, ockl, ocml, caller, has_prefix}:",
 'RkIn': "case RkIn{pref, has, bufs, body}:",
}

p = 'tinybendygrad/renderer/cstyle.bend'
L = open(p).read().split('\n')
out = []
i = 0
while i < len(L):
    line = L[i]
    out.append(line)
    m = re.match(r'^type ([A-Za-z_][A-Za-z0-9_]*) is Data:', line)
    if m and m.group(1) in TYS:
        ty = m.group(1)
        # copy the type's continuation lines (they are indented)
        i += 1
        while i < len(L) and L[i].startswith('  ') and not L[i].strip().startswith('#'):
            out.append(L[i]); i += 1
        out.append(READERS[ty].rstrip('\n'))
        if ty == 'BArg':
            pass
        for f, rt in TYS[ty].items():
            out.append(f"def {ty}.{f}({BIND[ty]}: {ty}) -> {rt}:")
            out.append(f"  match {BIND[ty]}:")
            out.append(f"    {PARS[ty]} {f}")
            out.append("")
        continue
    i += 1
open(p, 'w').write('\n'.join(out))
print("inserted readers")