import re

lines = open('/tmp/mut.txt').read().split('\n')
rows = []
i = 0
while i < len(lines):
    m = re.match(r'^ *(\d+)  (\d+) rows  +(.*)$', lines[i])
    if m and i + 1 < len(lines) and lines[i + 1].strip().startswith('rows:'):
        r = lines[i + 1].strip()[5:].strip().replace(' , ', ', ')
        rows.append((int(m.group(1)), int(m.group(2)), m.group(3).strip(), r))
        i += 2
        continue
    i += 1
assert len(rows) == 31, len(rows)

# one row per mutation, truncated row lists to the first few so the table READS
def short(r, n=6):
    if r == '(none)':
        return '**(none)**'
    parts = [p.strip() for p in r.split(', ')]
    if len(parts) <= n:
        return ', '.join(f'`{p}`' for p in parts)
    return ', '.join(f'`{p}`' for p in parts[:n]) + f', +{len(parts) - n} more'

out = []
out.append('''# ===========================================================================
# THE MUTATION TABLE. THIRTY-ONE MUTATIONS, EVERY ONE OF THEM MEASURED BY
# RE-RUNNING THE FILE, AND EVERY ONE OF THEM MOVES AT LEAST ONE ROW. The driver
# is `.agents/slop/wip/mutate.py`: it restores this file, applies ONE targeted
# edit, re-runs the interpreted lane, diffs every row's `[bend]` half against the
# baseline, and restores the file again. A mutation that does not COMPILE is a
# different outcome from "moved nothing" and both are recorded; none of the 31
# failed to compile and none moved nothing.
#
# EVERY `py=` STRING IS MEASURED, NOT TYPED. The generator
# `.agents/slop/wip/gen_main.py` builds this whole table from live `tinygrad` and
# writes both the row call and its oracle, and `.agents/slop/wip/gate.py` is the
# driver that runs BOTH lanes, checks they are byte-identical, and prints every red
# row's two halves BESIDE each other. The first version of this file had 215
# hand-written `py=` strings, and the gate found 17 of them wrong -- five in the
# ORACLE and twelve in the port.
#
# THE THREE BLIND SPOTS THIS TABLE FOUND, and the rows that closed them, are the
# reason the table is here rather than a summary of it:
#
#   * `var_prefix`/`var_suffix` on METAL moved NOTHING. They are unreachable
#     through `render_kernel` at all -- `MetalRenderer.render_kernel` calls
#     `super()` with `bufs=[]`, so `buftypes` is empty and the two class
#     attributes are read by NOTHING upstream. `buft METAL` is a direct
#     evaluation of upstream's `buftypes` expression with Metal as `self`, which
#     is the only honest way to gate a class attribute no generated kernel reads.
#   * `prefix_clauses`' COUNT moved NOTHING, because no fixture had `vecs` set.
#     `kern2 CUDA vecs` and `kern2 HIP vecs` carry upstream's own
#     `render_vector_prefix` text -- and the two vendors spell it differently, so
#     the two fixtures are separate lists.
#   * the ORDER of HIP's `hip_bfloat16` / `#define half` clauses moved NOTHING,
#     because no fixture had both dtypes. `kern2 HIP bf16h` is that fixture, and
#     it is the ONLY row in the file that pins the order.
#
# THE WIDE ONES ARE THE INTERESTING ONES: `rd_suffix` (77) and `rd_body` (88) are
# `_render_dtype`'s two load-bearing tests and they are shared by nearly every row,
# which is the correct answer -- a mutation in the most-read def SHOULD move the
# most rows. The NARROW ones are the ones to read twice: a single-row mutation is a
# LOCALISED claim, and `float4_style` -> `opt f4style` is the honest shape of that
# (the option table has exactly one reader and the reader is that row).
#
# ROW 26 IS THE GATE'S OWN INSTRUMENT: `esc_row` is what makes a multi-line value
# one printable line, and mutating its separator moves exactly the 30 rows whose
# value can contain a newline -- which is every `kern2` row and nothing else. If it
# moved a `tmap` row the gate would be reading its own escape rather than the
# renderer's output.
# ===========================================================================''')
out.append('')
out.append('| # | mutation | rows moved | the rows (abbreviated) |')
out.append('| --- | --- | --- | --- |')
for k, n, name, r in rows:
    out.append('| %d | `%s` | %d | %s |' % (k, name.replace('|', '\\|'), n, short(r)))
open('/tmp/mutation_table.md', 'w').write('\n'.join(out) + '\n')
print('\n'.join(out[-6:]))
print("rows:", len(rows), "all non-zero:", all(n > 0 for _, n, _, _ in rows))