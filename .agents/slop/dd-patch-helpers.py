#!/usr/bin/env python3
# dd-patch-helpers.py -- writes `.agents/slop/ddcheck/helpers.bend`, a LOCAL COPY
# of `tinybendygrad/helpers.bend` with the `ansistrip` BLOCK REPLACED BY A STUB.
#
# WHY IT EXISTS: `helpers.bend` belongs to another agent and is mid-edit. Its
# `ansistrip` section (the ANSI-escape stripper, `helpers.py:48`) does not
# compile -- several three-scrutinee `match`es with a `_` wildcard, which bend
# 2.0.34 refuses ("expected : N patterns (one per scrutinee)") -- and every file
# in `tinybendygrad/` imports `helpers.bend`, so nothing compiles at all.
#
# THE STUB IS SAFE FOR THIS UNIT. `ansistrip` is called by `viz/cli.bend`,
# `viz/serve.bend` and `renderer/ptx.bend` only; nothing in
# `codegen/decomp/{dtype,op,transcendental}.bend`, `uop/ops.bend`,
# `uop/fold.bend` or `LAWS/spec.bend` reaches it. The decomp mirror compiles the
# real `helpers.bend` in every other respect -- every def, table and law outside
# the `ansistrip` span is byte-identical -- so a row that moves here moved in the
# port and not in the stub.
#
# `tinybendygrad/helpers.bend` IS NEVER WRITTEN. DELETE BOTH FILES WHEN IT
# COMPILES AGAIN.
import os
import sys

HEAD = "# ansistrip -- `re.sub("
STUB = """# THE LOCAL STUB -- see .agents/slop/dd-patch-helpers.py. NOT THE PORT: the
# owner of helpers.bend is mid-edit on this block and it does not compile, and
# nothing in this mirror's import graph calls it.
def ansistrip(s: String) -> String:
  s

def ansilen(s: String) -> Nat:
  String.length(s)

def ansipad(+s: String, w: U32) -> String:
  String.concat([s, String.repeat(" ", 0n)])
"""


def main():
    dst = sys.argv[1] if len(sys.argv) > 1 else '.agents/slop/ddcheck/helpers.bend'
    os.makedirs(os.path.dirname(dst) or '.', exist_ok=True)
    lines = open('tinybendygrad/helpers.bend').read().split('\n')
    start = next((i for i, l in enumerate(lines) if l.startswith(HEAD)), None)
    if start is None:
        print("dd-patch-helpers: no ansistrip block found", file=sys.stderr)
        return 1
    # the block runs from the `# ====` line above the header to the next one
    # AFTER its last def, which is `ansipad` -- the header above `make_tuple`
    while not lines[start].startswith('# ====='):
        start -= 1
    last = max(i for i, l in enumerate(lines)
               if l.startswith('def ansistrip(') or l.startswith('def ansilen(')
               or l.startswith('def ansipad('))
    end = next(i for i in range(last, len(lines)) if lines[i].startswith('# ====='))
    open(dst, 'w').write('\n'.join(lines[:start] + STUB.split('\n') + lines[end:]))
    print(f"dd-patch-helpers: stubbed {dst} lines {start + 1}..{end}")
    return 0


if __name__ == '__main__':
    sys.exit(main())