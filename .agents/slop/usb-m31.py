import io

NL = chr(10)
OLD = '            head_name(t2, ""), h0)'
NEW = '            h0, head_name(t2, ""))'

L = io.open(".agents/slop/usb-mutate.py").read().split(NL)
a = next(i for i, l in enumerate(L) if l.startswith('    ("M31"'))
b = next(i for i, l in enumerate(L) if l.startswith('    ("M32"'))
entry = [
    '    ("M31", "`sym_at_head`: answer the NEXT symbol instead of this one",',
    "     [(" + repr(OLD) + "," + repr(NEW) + ")],",
    '     "THE OFF-BY-ONE THIS FILE SHIPPED FOR AN HOUR: every order row named the "',
    '     "symbol AFTER the one it meant, every COUNT stayed right, and only the "',
    '     "whole-string order rows plus the CPython oracle could see it. Same class, "',
    '     "one index, same arity, same length."),',
]
L[a:b] = entry
io.open(".agents/slop/usb-mutate.py", "w").write(NL.join(L))
print("M31 replaced")