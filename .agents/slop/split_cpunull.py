#!/usr/bin/env python3
"""Split runtime/ops_cpu_null.bend into runtime/ops_cpu.bend + runtime/ops_null.bend.

Same discipline as split_late.py: def bodies move VERBATIM, so a row is a row, and the
union of the two files' rows in Python's order is the 308 the one file printed.

Anything BOTH halves need lives in `ops_cpu.bend` -- the FIRST of the pair in Python's
order -- and `ops_null.bend` imports it as `C`. Three such blocks had to MOVE rather
than simply stay where they were, and each move is named at its slice:

  * the seam-call TAGS and the TRACE (`CALL_*`, `Call`, `Tr`, `Tr.*`) sat between the
    two halves and are shared: ops_null.py's `EMULATE` assert emits through `Tr`;
  * `Sub` + `nr.submit_graph` sat in the NULL half but ops_cpu.py:24 also carries a
    signature, and a NULL definition cannot be imported BY the CPU half;
  * `nth`/`subnames`/`ilist` sat inside the CPU gate, and `nr_ts_offset` is a NULL row
    that needs `nth`.

After the split `ops_cpu_null.bend` is GONE, so this script reads the pre-split
snapshot, which is checked in beside it.
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from qualify import declared, qualifier, hits, entries

ROOT = 'tinybendygrad/runtime'
ORIG = f'{ROOT}/ops_cpu_null.bend' if os.path.exists(f'{ROOT}/ops_cpu_null.bend') \
    else '.agents/slop/ops_cpu_null-pre-split.bend'
src = open(ORIG).read().split('\n')

def L(a, b):
    assert 1 <= a <= b <= len(src), f'BAD SLICE {a}..{b} of {len(src)}'
    return src[a-1:b]

HDR      = L(1, 130)
SUBSTR   = L(136, 343)   # Cn, cn_*, pk.offsets, Ca, Cam, Cr, cpu.* -- arch/slot tables
NULL_PRE = L(344, 344)   # `nr.has_copy_queue` -- a NULL fact, declared beside CPU's for
                          # the contrast; it moves with NULL and CPU's comment says so
TRACE    = L(346, 516)   # CALL_*, Call, Tr + Tr.* -- the seam tags and the trace
CPU_BODY = L(517, 973)   # Prog, prog.*, lvp, Cpu
SUB_MOVED= L(1063, 1080)# `Sub` + `nr.submit_graph` -- the seven-node doorbell graph,
                          # which the CPU half's signature rows also need
NULL_BODY= L(974, 1062) + L(1081, 1755)
VOCAB    = L(1756, 1840) # CALL_NAME_*, call_name, row/urow/lrow/rlist, fx_init, sig7
GATE_PRE = L(1841, 1905) # the GATE paragraph, the row printers, the CPU fixtures
SHARED_G = L(2028, 2046) # `nth`, `subnames`, `ilist` -- the three TOTAL readers
CPU_GATE = L(1906, 2027) + L(2047, 2115)
NULL_GATE= L(2116, 2467)
MAIN     = L(2468, 2481)
MUT_PRE  = L(2482, 2500) # the mutation-table preamble
MUT_NULL = L(2501, 2513) # the two NULL zeros, M28 `EvA.step` and M53 `nr.zero_of.go`
MUT_CTRL = L(2514, 2517) # M60, the comment-only CONTROL
MUT_TAIL = L(2518, 2536) # WHAT THIS GATE STILL DOES NOT SEE

assert MAIN[0].startswith('def main') and MAIN[2].strip().startswith('a : Unit') \
   and MAIN[7].strip().startswith('f : Unit')
MAIN_CPU  = [MAIN[0], MAIN[1]] + MAIN[2:7]                    # a..e
MAIN_CPU[-1] = re.sub(r'^(\s*)\w+(\s*:\s*Unit\s*<-\s*)', r'\1', MAIN_CPU[-1])
# f..j plus `cn-done=1`, which is already unbound and IS the pair's last row
MAIN_NULL = ['def main() -> IO(Unit):', '  do IO<Unit>:'] + MAIN[7:13]

CPU_SIDE = SUBSTR + TRACE + SUB_MOVED + CPU_BODY + VOCAB + GATE_PRE + SHARED_G + CPU_GATE + MAIN_CPU
shared = declared(CPU_SIDE)
NULL_SIDE = NULL_PRE + NULL_BODY + NULL_GATE + MAIN_NULL
print('ops_cpu names ops_null reaches for:', hits(shared, '\n'.join(NULL_SIDE)))
q = qualifier(shared, 'C')
NULL_BODY, NULL_GATE, MAIN_NULL = q(NULL_PRE + NULL_BODY), q(NULL_GATE), q(MAIN_NULL)

# the 109 measured entries are interleaved (M1 nr, M2 nr, ... M6 cpu, ...), so they
# are parsed into entries and each is filed by the def it names.
NULL_RE = re.compile(r'\b(nr\.|nprog\.|ndev\.|nalloc\.|EvA?\.|EvQ\.|Nul\.|pk_?\w|subat|'
                     r'subnames|nr_|Zz\.|Nk\.|evids|evtab|cmds\(|NSTORE|NEXEC|NCOPY|'
                     r'NWAIT|NTIMESTAMP)')
ENTS = entries(L(2538, len(src)), 2538)
e_cpu  = [l for e in ENTS if not NULL_RE.search(' '.join(e)) for l in e]
e_null = [l for e in ENTS if     NULL_RE.search(' '.join(e)) for l in e]
assert len(e_cpu) + len(e_null) == sum(len(e) for e in ENTS)
print('mutation entries: cpu=%d null=%d of %d' %
      (sum(1 for e in ENTS if e[0] not in e_null), sum(1 for e in ENTS if e[0] in e_null), len(ENTS)))

CPU_HDR = '''# tinybendygrad/runtime/ops_cpu.bend -- port of tinygrad/runtime/ops_cpu.py
#
# ONE BEND FILE PER UPSTREAM .py, AT THE SAME PATH. This was `ops_cpu_null.bend`,
# which held `ops_cpu.py` (96 lines) AND `ops_null.py` (70 lines); the 1:1 ruling
# gives each its own file. `runtime/ops_null.bend` is the other half and the rows are
# the SAME rows -- 308 across the pair before the split, 308 after.
#
# ops_cpu.py is the backend EVERY OTHER BACKEND INHERITS FROM. It has no renderer of
# its own, it owns the `arch` string every Clang target shares, and its `Program` is
# the one that mmaps a machine-code blob and calls it. `ops_null.py` is the DEGENERATE
# case: `NullQueue` writes FOUR words per command into a bytearray and the emulated
# device computes NOTHING. Eleven of the thirteen ops answer all-zero and TWO DO NOT
# -- `eye` and `arange` -- and both are in `ops_null.bend`'s gate with their CPython
# answers, so a port claiming "everything is zero" is caught by two rows.
#
# THE SPLIT, restated because it is the whole discipline here: a def EITHER BUILDS THE
# ARGUMENT of one device call OR RECORDS that call in the trace. There is no third
# kind. Every seam is a trace tag and nothing else, so the ORDER and IDENTITY of the
# seam calls are gateable even though none of them is made.
#
# THIS FILE ALSO CARRIES WHAT BOTH HALVES NEED, and `ops_null.bend` imports it as `C`:
#   * `Cn`/`cn_slot`/`cn_walk` -- ops_cpu.py:70's `struct.pack_into` slot walk, with
#     the CORRECT `iter_sig` semantics; see the `device.bend` DEFECT report below,
#     which is why they are declared here and not read from `device.bend`.
#   * `Ca`/`Cam`/`Ca.lookup` -- the `.get(m, m)` arch map. TWO callers share the scan
#     -- ops_cpu.py:91's arch map and ops_null.py:62's EMULATE map -- and they are the
#     same shape with different tables, which is why it is one def and not two.
#   * `Tr`/`Tr.*`/`Call` and the eleven `CALL_*` seam tags -- ops_null.py's `EMULATE`
#     assert records through them, which is what `nr_assert_post_bad` measures.
#     `CALL_ASSERT_EMULATE` is the one tag that belongs to NULL and it is declared
#     here because that is where every tag is declared.
#   * `Cr` -- ops_cpu.py:90's four-renderer table, which ops_null.py:65-66's is a
#     twenty-row relative of.
#   * `nth`/`subnames`/`ilist` -- the three TOTAL readers the positional rows need.
#   * the row printers `row/srow/urow/nrow/lrow/rlist` and `CALL_NAME_*`.
# None of the substrate has an upstream counterpart of its own, so it lives in the
# FIRST of the pair in Python's order rather than being duplicated.
#
''' + '\n'.join(HDR[45:130])

NULL_HDR = '''# tinybendygrad/runtime/ops_null.bend -- port of tinygrad/runtime/ops_null.py
#
# ONE BEND FILE PER UPSTREAM .py, AT THE SAME PATH. This was `ops_cpu_null.bend`,
# which held `ops_cpu.py` AND `ops_null.py`; the 1:1 ruling gives each its own file.
# `runtime/ops_cpu.bend` is the other half and the rows are the SAME rows -- 308 across
# the pair before the split, 308 after. The unit's THE GATE paragraph, its FIXTURES
# paragraph and the `device.bend` DEFECT REPORT are in `ops_cpu.bend`'s head.
#
# ops_null.py is the DEGENERATE BACKEND: `NullQueue` writes FOUR words per command
# into a bytearray and the emulated device computes NOTHING. Eleven of the thirteen ops
# answer all-zero and TWO DO NOT -- `eye` and `arange` -- and both are in the gate with
# their CPython answers, so a port claiming "everything is zero" is caught by two rows.
#
# THE SPLIT, restated because it is the whole discipline here: a def EITHER BUILDS THE
# ARGUMENT of one device call OR RECORDS that call in the trace. There is no third
# kind, and that is what puts the `raise` in the trace, so a refusal appears as a
# TRUNCATED trace and no step needs a guard of its own.
#
# ONE DEVIATION FROM ops_webgpu.bend, deliberate. There a `raise` lives INSIDE a loop of
# calls, so it had to be a flag and a refusal showed as a TRUNCATED trace. Neither
# refusal here is inside such a loop -- ops_null.py's two (`_copyout`'s panic,
# `__init__`'s EMULATE assert) are both TERMINAL -- so `C.Tr.refused` is set once by
# the assert and the device's trace is then EMPTY: the same observable for a different
# reason, and `nr_assert_trace_n` is the row that pins it.
#
# THE SUBSTRATE IS IMPORTED, NOT COPIED: `C.Tr`/`C.Tr.*` (the trace), `C.CALL_PING` (the
# seam tag the `EMULATE` assert probes with), `C.Cn`/`C.cn_slot` (the slot walk the
# kernargs layout shares with ops_cpu.py:70), `C.Cr`, `C.nth` and the row printers live
# in `ops_cpu.bend` and every use here is `C.`. `Ca`/`Cam` are there too because
# ops_cpu.py:91's arch map and ops_null.py:62's EMULATE map are the same scan.
#
# `nr.has_copy_queue` is a NULL fact -- `ops_null.py` does not override
# `@property def has_copy_queue` at all, so NULL inherits `Compiled`'s `True` while
# `ops_cpu.py:84` returns `False`. `C.cpu.has_copy_queue` is the other half of that
# pair and it lives in `ops_cpu.bend` beside the comment explaining why two rows exist.
#
# ONE FILE IN HERE IS NOT MINE TO MOVE. `pk`/`Pk`/`fx_pk`/`pkend` and the `pk_*` rows
# port `pack_args`, which is `runtime/support/hcq2.py:78-83` -- a file with its own
# `.bend` and another unit's. They stay here because `ops_null.py:29-30` builds the
# kernargs through them. THE FIX IS TO MOVE THEM to `runtime/support/hcq2.bend`;
# flagged here and in the report, not done, because hcq2.bend is read-only here.
#
'''

open(f'{ROOT}/ops_cpu.bend', 'w').write(
    CPU_HDR +
    '\n'.join(['import Base', 'import ../helpers.bend as H', 'import ../device.bend as D',
               'import ../LAWS/spec.bend as S']) + '\n\n' +
    '\n'.join(SUBSTR + [''] + TRACE + [''] + SUB_MOVED + [''] + CPU_BODY + [''] + VOCAB + [''] +
    GATE_PRE + [''] + SHARED_G + [''] + CPU_GATE + [''] + MAIN_CPU + [''] +
    MUT_PRE + MUT_CTRL + MUT_TAIL + e_cpu))

open(f'{ROOT}/ops_null.bend', 'w').write(
    NULL_HDR +
    '\n'.join(['import Base', 'import ../helpers.bend as H', 'import ../device.bend as D',
               'import ../LAWS/spec.bend as S', 'import ./ops_cpu.bend as C']) + '\n\n' +
    '\n'.join(NULL_BODY + [''] + NULL_GATE + [''] + MAIN_NULL + [''] + MUT_NULL +
    ['#', "# THE MEASURED ENTRIES for the rules above. The other 109 - these and the",
     "# CPU half's, which is in `ops_cpu.bend` - are filed by the def each names;",
     "# `cn-mutate.py` walked them in order M1..M109 across the pre-split file.",
     '#',
     '#   M28    0  EvA.step: last-wins becomes first-wins  (argued above)',
     '#   M53    0  nr.zero_of.go: last-wins becomes first-wins (argued above)'] +
    e_null))

print('gate groups: cpu=%d null=%d' % (len(MAIN_CPU) - 2, len(MAIN_NULL) - 2))
