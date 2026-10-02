#!/usr/bin/env python3
# .agents/slop/nv_reshape.py -- convert the gate's `do IO<Unit>:` bodies that try
# to `<-`-bind a PURE value into the shape that compiles.
#
# WHY. Bend's rule (bend2-constraints.md, line 1419) is that a `do IO<Unit>:`
# block can only bind an `IO`. `+r : Rgv <- nv.reg_boot0()` is a pure value, so it
# is refused with
#
#   - expected : @-R:Type -> @k:(@_:Rgv -> IO.OP<R>) -> IO.OP<R>
#   - observed : Rgv
#
# The shape that works, and the one `ip.bend` already uses, is: a PURE def returns
# `List<&2, String>` of "name=value" rows and `emit` prints them in one
# `IO.print`. So each `IP.urow("k", E)` becomes the pure string
# `String.concat(["k=", U32.show(E)])`, each `IP.srow("k", E)` becomes
# `String.concat(["k=", E])`, and each `IP.row("k", E)` becomes the same with
# `Bool.show`. `+x : T <- f(...)` becomes `f(...)` inside a list literal, which
# is a BARE CALL -- legal as a statement in a list, per rule 681.
#
# The transcription of `IP.row` matters: `Bool.show(True{})` and `U32.show(1)` are
# both "True"/"1", so a `row` must not be rewritten as a `urow`.

import re, sys

P = "tinybendygrad/runtime/support/nv/nvdev.bend"
src = open(P).read()

def body_of(defn_name):
    m = re.search(r"^def " + re.escape(defn_name) + r"\(.*?\n(  do IO<Unit>:\n)(.*?)(?=\n\ndef |\n# |\Z)",
                  src, re.S | re.M)
    return m

CONV = [
    (re.compile(r'^(\s*)\+?IP\.urow\((".*?"), (.*)\)$', re.M), 'u'),
    (re.compile(r'^(\s*)\+?IP\.srow\((".*?"), (.*)\)$', re.M), 's'),
    (re.compile(r'^(\s*)\+?IP\.row\((".*?"), (.*)\)$', re.M), 'b'),
]
BIND = re.compile(r'^(\s*)\+\w+ : [\w&<>, ]+ <- (.*)$', re.M)

def convert(body):
    out = body
    for rx, kind in CONV:
        def mk(m):
            ind, key, expr = m.group(1), m.group(2), m.group(3)
            if kind == 'u':
                return f'{ind}String.concat([{key}, "=", U32.show({expr})]),'
            if kind == 'b':
                return f'{ind}String.concat([{key}, "=", Bool.show({expr})]),'
            return f'{ind}String.concat([{key}, "=", {expr}]),'
        out = rx.sub(mk, out)
    def bk(m):
        return f'{m.group(1)}{m.group(2)},'
    out = BIND.sub(bk, out)
    return out

names = re.findall(r"^def (t_\w+)\(", src, re.M)
changed = 0
for n in names:
    m = body_of(n)
    if not m:
        continue
    head, body = m.group(1), m.group(2)
    new = convert(body)
    if new == body:
        continue
    # a `do IO<Unit>:` whose body is now a pure list must be a PURE def:
    # `-> List<&2, String>` and no `do`.
    newbody = "\n".join(("  " + l[2:] if l.startswith("  ") else l) for l in new.split("\n"))
    src = src[:m.start()] + newbody.rstrip() + src[m.end():]
    changed += 1
print(f"rewrote {changed} of {len(names)} t_ bodies")
open(P, "w").write(src)