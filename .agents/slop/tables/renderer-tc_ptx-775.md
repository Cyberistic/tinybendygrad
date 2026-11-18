<!-- FROM: tinybendygrad/renderer/tc_ptx.bend:775 -->
# BLOCK:
# THE ROW ORDER IS THE ORACLE'S, group for group, because the gate is a byte
# diff and a diff is positional. `ptx_matcher rules`, `asm_for_op` (dtype rows
# then WHERE's three forms), `asm_for_op` again over the real names, the half
# tuples, `modifier`, `render_val`, the three tables, the constants, then
# `supported_dtypes` and `tensor_cores`.
# THE ESCAPE, because `PTXRenderer.barrier` contains a real TAB
# ("bar.sync\t0;") and `render_kernel` contains real NEWLINES, and neither is
# visible in a one-line row. CPython's `repr` escapes them and the oracle escapes
# them, so the Bend side escapes them the same way -- which also means a DROPPED
# tab is a diff rather than a shorter line.
# `fmt` -- ptx.py:164, AT THE PIN.
#
#     def fmt(line): return "\t" + line.replace(" ", "\t" if len(line.split(" ")[0]) > 7 else "\t\t", 1)
#
# EVERY line is indented by a TAB and its FIRST space becomes ONE TAB (mnemonic
# longer than seven characters) or TWO. The `1` on `replace` is load-bearing:
# without it EVERY space in the line would become a tab.
#
# the `$` early return is gone, and it is upstream that deleted it. Upstream
# `96397341d` ("dead code cleanups [PR] (#18593)", 2026-10-03) turned
# `return line if line[0]=="$" else "\t" + line.replace(...)` into
# `return "\t" + line.replace(...)`. MEASURED, at that commit's parent `ptx.py`
# held NO OTHER `$` -- ONE occurrence in the whole file, the `fmt` line itself --
# so no line could ever begin with `$` and the branch was DEAD CODE. The port
# kept it, and the two agreed until the 2026-10-16 re-vendor moved the tree
# past that commit. a comment that argues for a behaviour upstream deleted is
# A WRONG BEHAVIOUR WITH A DEFENCE, so this file's own `$` prose went with it.
# `line.split(" ")[0]` -- the mnemonic, i.e. everything before the first space.
# END BLOCK

# THE ROW ORDER IS THE ORACLE'S, group for group, because the gate is a byte
# diff and a diff is positional. `ptx_matcher rules`, `asm_for_op` (dtype rows
# then WHERE's three forms), `asm_for_op` again over the real names, the half
# tuples, `modifier`, `render_val`, the three tables, the constants, then
# `supported_dtypes` and `tensor_cores`.
# THE ESCAPE, because `PTXRenderer.barrier` contains a real TAB
# ("bar.sync\t0;") and `render_kernel` contains real NEWLINES, and neither is
# visible in a one-line row. CPython's `repr` escapes them and the oracle escapes
# them, so the Bend side escapes them the same way -- which also means a DROPPED
# tab is a diff rather than a shorter line.
# `fmt` -- ptx.py:164, AT THE PIN.
#
#     def fmt(line): return "\t" + line.replace(" ", "\t" if len(line.split(" ")[0]) > 7 else "\t\t", 1)
#
# EVERY line is indented by a TAB and its FIRST space becomes ONE TAB (mnemonic
# longer than seven characters) or TWO. The `1` on `replace` is load-bearing:
# without it EVERY space in the line would become a tab.
#
# the `$` early return is gone, and it is upstream that deleted it. Upstream
# `96397341d` ("dead code cleanups [PR] (#18593)", 2026-10-03) turned
# `return line if line[0]=="$" else "\t" + line.replace(...)` into
# `return "\t" + line.replace(...)`. MEASURED, at that commit's parent `ptx.py`
# held NO OTHER `$` -- ONE occurrence in the whole file, the `fmt` line itself --
# so no line could ever begin with `$` and the branch was DEAD CODE. The port
# kept it, and the two agreed until the 2026-10-16 re-vendor moved the tree
# past that commit. a comment that argues for a behaviour upstream deleted is
# A WRONG BEHAVIOUR WITH A DEFENCE, so this file's own `$` prose went with it.
# `line.split(" ")[0]` -- the mnemonic, i.e. everything before the first space.
