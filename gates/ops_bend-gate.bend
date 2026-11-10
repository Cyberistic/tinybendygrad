# gates/ops_bend-gate.bend -- THE GATE DRIVER for `tinybendygrad/runtime/ops_bend.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. The port file carries the port and
# this file carries the instrument, and the tree's own convention says so:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# And the rows are pure consumers: they call the port's defs and define
# nothing that the port needs.

import Base
import ./../tinybendygrad/runtime/ops_bend.bend as P

# `drop3` IS the old three-NAME spelling, kept beside `drop4` because THE
# DIFFERENCE between dropping three and four is the :188 BUG: the old code left the
# ARG in the srcs, so every :208 walk started from the wrong number.
def drop3(xs: List<&2, U32>) -> List<&2, U32>: P.drop_nat(xs, 3n)

def prog.call(+p: P.Prog, +l: P.Launch, +t: P.Tr) -> P.Tr:
  P.Tr.walk(P.prog.steps(p, l), t)

def compiler.of(src: String) -> String: src

# `has_local = False` :238 -- the scheduler's lever (opt/heuristic.py:163), so it
# is a def rather than a field: a field nothing reads is invisible.
def has_local() -> Bool: False{}

# THE EMPTY STORE: no bytes, bump at 0. A `HostAllocator` over a fresh device has
# nothing mapped either, so 0 is the honest starting answer and not a sentinel.
def store() -> P.Store: P.Store.of(Nil{}, 0)

def alloc_mem(nbytes: U32, s: P.Store) -> P.Mem: P.first.of(P.raw_alloc(nbytes, s))

def alloc_store(nbytes: U32, s: P.Store) -> P.Store: P.second.of(P.raw_alloc(nbytes, s))

# `raw_free`: a NO-OP, and the row says so. See THE ALLOCATOR'S HONEST LIMITS.
# It answers the same `P.Mem`, so a caller that frees the last buffer and reads it
# back gets the bytes rather than a crash -- which is what Python does too.
def raw_free(+m: P.Mem) -> P.Mem: m

def hexdig_ok(+c: U32) -> Bool:
  Bool.or(P.hexdig_digit(c), Bool.or(P.hexdig_lower(c), P.hexdig_upper(c)))


# --- THE GATE ROWS ------------------------------------------------------
# THE GATE. Every expectation below is CPython output, read out of
# `.agents/slop/` by `tools`-less generator `.agents/slop/bend_gate.py`, which
# takes it from `nodes-<case>.txt`, `packet-<case>.txt` and
# `bend_oracle_rows.txt`. NONE of it is a transcription of ops_bend.py: a row
# whose expectation is a re-reading of the Python would agree with a port that
# misread it.
# ==========================================================================

# ---- the fixture: tiny, 13 uops, from the
# renderer input of a REAL kernel. `packet-tiny.txt` is CPython's `encode`.
def NODES_TINY() -> List<&2, P.N>:
  [P.N{"PARAM", "f32", 4, 1, "GLOBAL", "", True{}, [], 1, 1, "(1,)"}, P.N{"PARAM", "f32", 4, 1, "GLOBAL", "", True{}, [], 1, 1, "(1,)"}, P.N{"PARAM", "f32", 4, 1, "GLOBAL", "", True{}, [], 1, 1, "(1,)"}, P.N{"CONST", "weakint", 100, 1, "ALU", "0", True{}, [], 0, 0, "()"}, P.N{"CAST", "i32", 4, 1, "ALU", "", True{}, [4], 0, 0, "()"}, P.N{"INDEX", "f32", 4, 1, "GLOBAL", "", True{}, [2, 5], 0, 0, "()"}, P.N{"LOAD", "f32", 4, 1, "ALU", "", True{}, [6], 0, 0, "()"}, P.N{"INDEX", "f32", 4, 1, "GLOBAL", "", True{}, [3, 5], 0, 0, "()"}, P.N{"LOAD", "f32", 4, 1, "ALU", "", True{}, [8], 0, 0, "()"}, P.N{"INDEX", "f32", 4, 1, "GLOBAL", "", True{}, [1, 5], 0, 0, "()"}, P.N{"ADD", "f32", 4, 1, "ALU", "", True{}, [7, 9], 0, 0, "()"}, P.N{"STORE", "void", 0, 1, "GLOBAL", "", True{}, [10, 11], 0, 0, "()"}, P.N{"SINK", "void", 0, 1, "-", "", True{}, [12], 0, 0, ""}]
# ---- the fixture: fconst, 28 uops, from the
# renderer input of a REAL kernel. `packet-fconst.txt` is CPython's `encode`.
def NODES_FCONST() -> List<&2, P.N>:
  [P.N{"PARAM", "f32", 4, 4, "GLOBAL", "", True{}, [], 1, 4, "(4,)"}, P.N{"PARAM", "f32", 4, 4, "GLOBAL", "", True{}, [], 1, 4, "(4,)"}, P.N{"CONST", "weakint", 100, 1, "ALU", "0", True{}, [], 0, 0, "()"}, P.N{"CAST", "i32", 4, 1, "ALU", "", True{}, [3], 0, 0, "()"}, P.N{"CONST", "weakint", 100, 1, "ALU", "4", True{}, [], 0, 0, "()"}, P.N{"CAST", "i32", 4, 1, "ALU", "", True{}, [5], 0, 0, "()"}, P.N{"SHRINK", "f32", 4, 4, "GLOBAL", "", True{}, [2, 4, 6], 1, 4, "(4,)"}, P.N{"LOAD", "f32", 4, 4, "ALU", "", True{}, [7], 1, 4, "(4,)"}, P.N{"INDEX", "f32", 4, 1, "ALU", "", True{}, [8, 4], 0, 0, "()"}, P.N{"CONST", "weakint", 100, 1, "ALU", "1", True{}, [], 0, 0, "()"}, P.N{"CAST", "i32", 4, 1, "ALU", "", True{}, [10], 0, 0, "()"}, P.N{"INDEX", "f32", 4, 1, "ALU", "", True{}, [8, 11], 0, 0, "()"}, P.N{"CONST", "weakint", 100, 1, "ALU", "2", True{}, [], 0, 0, "()"}, P.N{"CAST", "i32", 4, 1, "ALU", "", True{}, [13], 0, 0, "()"}, P.N{"INDEX", "f32", 4, 1, "ALU", "", True{}, [8, 14], 0, 0, "()"}, P.N{"CONST", "weakint", 100, 1, "ALU", "3", True{}, [], 0, 0, "()"}, P.N{"CAST", "i32", 4, 1, "ALU", "", True{}, [16], 0, 0, "()"}, P.N{"INDEX", "f32", 4, 1, "ALU", "", True{}, [8, 17], 0, 0, "()"}, P.N{"CONST", "weakfloat", 100, 1, "ALU", "0000003f", False{}, [], 0, 0, "()"}, P.N{"CAST", "f32", 4, 1, "ALU", "", True{}, [19], 0, 0, "()"}, P.N{"MUL", "f32", 4, 1, "ALU", "", True{}, [9, 20], 0, 0, "()"}, P.N{"MUL", "f32", 4, 1, "ALU", "", True{}, [12, 20], 0, 0, "()"}, P.N{"MUL", "f32", 4, 1, "ALU", "", True{}, [15, 20], 0, 0, "()"}, P.N{"MUL", "f32", 4, 1, "ALU", "", True{}, [18, 20], 0, 0, "()"}, P.N{"STACK", "f32", 4, 4, "ALU", "", True{}, [21, 22, 23, 24], 1, 4, "(4,)"}, P.N{"SHRINK", "f32", 4, 4, "GLOBAL", "", True{}, [1, 4, 6], 1, 4, "(4,)"}, P.N{"STORE", "void", 0, 4, "GLOBAL", "", True{}, [26, 25], 1, 4, "(4,)"}, P.N{"SINK", "void", 0, 1, "-", "", True{}, [27, 27, 27, 27], 0, 0, ""}]
# ---- the fixture: cmp, 33 uops, from the
# renderer input of a REAL kernel. `packet-cmp.txt` is CPython's `encode`.
def NODES_CMP() -> List<&2, P.N>:
  [P.N{"PARAM", "bool", 1, 4, "GLOBAL", "", True{}, [], 1, 4, "(4,)"}, P.N{"PARAM", "f32", 4, 4, "GLOBAL", "", True{}, [], 1, 4, "(4,)"}, P.N{"CONST", "weakint", 100, 1, "ALU", "0", True{}, [], 0, 0, "()"}, P.N{"CAST", "i32", 4, 1, "ALU", "", True{}, [3], 0, 0, "()"}, P.N{"CONST", "weakint", 100, 1, "ALU", "4", True{}, [], 0, 0, "()"}, P.N{"CAST", "i32", 4, 1, "ALU", "", True{}, [5], 0, 0, "()"}, P.N{"SHRINK", "f32", 4, 4, "GLOBAL", "", True{}, [2, 4, 6], 1, 4, "(4,)"}, P.N{"LOAD", "f32", 4, 4, "ALU", "", True{}, [7], 1, 4, "(4,)"}, P.N{"INDEX", "bool", 1, 1, "GLOBAL", "", True{}, [1, 4], 0, 0, "()"}, P.N{"CONST", "weakint", 100, 1, "ALU", "1", True{}, [], 0, 0, "()"}, P.N{"CAST", "i32", 4, 1, "ALU", "", True{}, [10], 0, 0, "()"}, P.N{"INDEX", "bool", 1, 1, "GLOBAL", "", True{}, [1, 11], 0, 0, "()"}, P.N{"CONST", "weakint", 100, 1, "ALU", "2", True{}, [], 0, 0, "()"}, P.N{"CAST", "i32", 4, 1, "ALU", "", True{}, [13], 0, 0, "()"}, P.N{"INDEX", "bool", 1, 1, "GLOBAL", "", True{}, [1, 14], 0, 0, "()"}, P.N{"CONST", "weakint", 100, 1, "ALU", "3", True{}, [], 0, 0, "()"}, P.N{"CAST", "i32", 4, 1, "ALU", "", True{}, [16], 0, 0, "()"}, P.N{"INDEX", "bool", 1, 1, "GLOBAL", "", True{}, [1, 17], 0, 0, "()"}, P.N{"INDEX", "f32", 4, 1, "ALU", "", True{}, [8, 4], 0, 0, "()"}, P.N{"INDEX", "f32", 4, 1, "ALU", "", True{}, [8, 11], 0, 0, "()"}, P.N{"INDEX", "f32", 4, 1, "ALU", "", True{}, [8, 14], 0, 0, "()"}, P.N{"INDEX", "f32", 4, 1, "ALU", "", True{}, [8, 17], 0, 0, "()"}, P.N{"CONST", "weakfloat", 100, 1, "ALU", "00000040", False{}, [], 0, 0, "()"}, P.N{"CAST", "f32", 4, 1, "ALU", "", True{}, [23], 0, 0, "()"}, P.N{"CMPLT", "bool", 1, 1, "ALU", "", True{}, [24, 19], 0, 0, "()"}, P.N{"CMPLT", "bool", 1, 1, "ALU", "", True{}, [24, 20], 0, 0, "()"}, P.N{"CMPLT", "bool", 1, 1, "ALU", "", True{}, [24, 21], 0, 0, "()"}, P.N{"CMPLT", "bool", 1, 1, "ALU", "", True{}, [24, 22], 0, 0, "()"}, P.N{"STORE", "void", 0, 1, "GLOBAL", "", True{}, [9, 25], 0, 0, "()"}, P.N{"STORE", "void", 0, 1, "GLOBAL", "", True{}, [12, 26], 0, 0, "()"}, P.N{"STORE", "void", 0, 1, "GLOBAL", "", True{}, [15, 27], 0, 0, "()"}, P.N{"STORE", "void", 0, 1, "GLOBAL", "", True{}, [18, 28], 0, 0, "()"}, P.N{"SINK", "void", 0, 1, "-", "", True{}, [29, 30, 31, 32], 0, 0, ""}]

# ---- the packets CPython emitted, as ONE escaped string each.
def PKT_TINY() -> String: "bendexec1 13 3
1: PARAM f32 k:param:4:g
2: PARAM f32 k:param:4:g
3: PARAM f32 k:param:4:g
4: CONST weakint c:0
5: CAST i32 - 4
6: INDEX f32 - 2 5
7: LOAD f32 - 6
8: INDEX f32 - 3 5
9: LOAD f32 - 8
10: INDEX f32 - 1 5
11: ADD f32 - 7 9
12: STORE void - 10 11
13: SINK void - 12
"
def PKT_FCONST() -> String: "bendexec1 28 2
1: PARAM f32 k:param:16:g
2: PARAM f32 k:param:16:g
3: CONST weakint c:0
4: CAST i32 - 3
5: CONST weakint c:4
6: CAST i32 - 5
7: SHRINK f32 - 2 4 6
8: LOAD f32 k:vec:4 7
9: INDEX f32 k:idx:0 8 4
10: CONST weakint c:1
11: CAST i32 - 10
12: INDEX f32 k:idx:0 8 11
13: CONST weakint c:2
14: CAST i32 - 13
15: INDEX f32 k:idx:0 8 14
16: CONST weakint c:3
17: CAST i32 - 16
18: INDEX f32 k:idx:0 8 17
19: CONST weakfloat f:0000003f
20: CAST f32 - 19
21: MUL f32 - 9 20
22: MUL f32 - 12 20
23: MUL f32 - 15 20
24: MUL f32 - 18 20
25: STACK f32 - 21 22 23 24
26: SHRINK f32 - 1 4 6
27: STORE void k:vec:4 26 25
28: SINK void - 27 27 27 27
"
def PKT_CMP() -> String: "bendexec1 33 2
1: PARAM bool k:param:4:g
2: PARAM f32 k:param:16:g
3: CONST weakint c:0
4: CAST i32 - 3
5: CONST weakint c:4
6: CAST i32 - 5
7: SHRINK f32 - 2 4 6
8: LOAD f32 k:vec:4 7
9: INDEX bool - 1 4
10: CONST weakint c:1
11: CAST i32 - 10
12: INDEX bool - 1 11
13: CONST weakint c:2
14: CAST i32 - 13
15: INDEX bool - 1 14
16: CONST weakint c:3
17: CAST i32 - 16
18: INDEX bool - 1 17
19: INDEX f32 k:idx:0 8 4
20: INDEX f32 k:idx:0 8 11
21: INDEX f32 k:idx:0 8 14
22: INDEX f32 k:idx:0 8 17
23: CONST weakfloat f:00000040
24: CAST f32 - 23
25: CMPLT bool - 24 19
26: CMPLT bool - 24 20
27: CMPLT bool - 24 21
28: CMPLT bool - 24 22
29: STORE void - 9 25
30: STORE void - 12 26
31: STORE void - 15 27
32: STORE void - 18 28
33: SINK void - 29 30 31 32
"

# NO reverse, AND the reverse was the bug. `List.append(&2, String, acc, [x])` is
# `acc ++ [x]` -- it APPENDS -- so the trailing `List.reverse` printed every list in
# this file BACKWARDS. MEASURED: `ujoin([10, 11])` printed `11 10` while
# `head([10, 11])` is `10`. Every `lrow` in this file has therefore been showing a
# REVERSED list, which is why `bend_drop4_line` read `11 10` for a srcs list that is
# `[10, 11]` -- and why an `out_bufs` row for a two-element set could not be trusted
# either way.
#
# THE ROW THAT PROVES IT, and it is the same rule `drop_rest` and `map_dec` use:
# APPEND with the accumulator first and do not reverse. A Bend list literal IS in
# order (MEASURED: `head([10, 11])` is 10), so nothing needs reversing.
def ujoin.go(+xs: List<&2, U32>, +acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}:
      acc
    case x <> t:
      ujoin.go(t, List.append(&2, String, acc, [U32.show(x)]))

def ujoin(+xs: List<&2, U32>) -> String: String.join(ujoin.go(xs, Nil{}), " ")

def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def lrow(nm: String, v: List<&2, U32>) -> IO(Unit): srow(nm, ujoin(v))

# ===========================================================================
# THE LAUNCHER. This is where the six SEAM steps of `prog.call` stop being steps.
#
# `subprocess.run([exe, pkt, gx, gy, gz, vals...])` at ops_bend.py:222 is a SEAM
# in the port above, and this is what it is instead. `Process.run` is in
# `references/bend/bend2/base.bend:182` and is a WHOLE-OPERATION FFI -- one
# `import "./effs/process_run.c"` for the whole call, with no per-function binding
# and no `dlopen`. That is the one class of foreign code this port is allowed,
# and MEASURED working: `Process.run("/bin/echo", ["hello","bend"], ...)` answers
# `code=0`, `out="hello bend\n"`, `err=""`.
#
# SO: `ops_bend` CAN launch an executor with no CPython in the path. That is the
# wall the brief predicted -- "Bend cannot bind to C at function granularity" --
# and it is TRUE, and it is also not the wall for THIS device, because a launch
# is one operation rather than several thousand.
#
# WHAT IS STILL A SEAM, and is not claimed otherwise: the `--check-only` note at
# the top of this file says `executor()` is a build plus a cache, and the BUILD
# (`bend ... -o`) is still driven by the harness in `.agents/slop/`. Only the
# LAUNCH is here.
# ===========================================================================

# THE packet directory. - AND it moved on 2026-10-20, WHEN the gate's FIXTURE
# MOVED out of the pruned tree and into GIT BESIDE the gate (`0841bcfb0`,
# "THE flagship gate's FIXTURE moves out of the pruned tree, IN GIT, BESIDE the
# GATE") -- - AND this file was not moved with it, SO the port kept
# WRITING `PACKET.out` INTO `.agents/slop/opsbend-milestone/` WHILE the gate read
# IT FROM `checks/.e2e-fixture/opsbend-milestone/`.
#
# - AND the symptom was a `FileNotFoundError` IN the gate, WITH the port's OWN
# OUTPUT VISIBLE IN THE OLD DIRECTORY -- which is the shape of a stale path and
# not of a broken port.
#
# - AND the directory is the tracked one, because a gate's input belongs
# beside the gate IN GIT: `.agents/slop/` is being pruned and holds no protection.
def PKT_DIR() -> String: "checks/.e2e-fixture/opsbend-milestone"
def PKT_IN() -> String: String.concat([PKT_DIR(), "/PACKET.in"])
def PKT_OUT() -> String: String.concat([PKT_DIR(), "/PACKET.out"])
def PKT_EXE() -> String: String.concat([PKT_DIR(), "/bend-executor"])

# `bend-executor PACKET gx gy gz vals...` -- the v1.1 command line, which is
# `LOCAL SIZE IS NOT A v1 ARGUMENT` (ops_python.bend's own header): the executor
# is warp 1 and reads every `lidxK` as 0. So the argv is the packet and the GRID,
# and nothing else. `P.Prog.nout` is 1 for the milestone -- one work item -- so
# `grid(1, ...)` runs the body exactly once, which is what "one trivial kernel
# over the buffer" means.
def PKT_GRID() -> List<String>: ["1", "1", "1"]

# argv is `PACKET gx gy gz`, and there is no `String.append`, so the four fields
# are ONE literal. `List.append` is `xs ++ ys` -- which is why this is a literal
# and not a concat: the packet must come FIRST and a concat gets that backwards.
# - AND the packet path is spelled, NOT built from `PKT_IN()`, BECAUSE a
# LIST literal'S elements must be constants and a call is not; - SO this is a
# SECOND COPY OF the path, AND it is why the MOVE HAD to touch both places.
def PKT_ARGV() -> List<String>: ["checks/.e2e-fixture/opsbend-milestone/PACKET.in", "1", "1", "1"]

# WRITE THE PACKET: the uop block (`encode`, byte-identical to
# `packet-tiny.txt`) followed by ONE buffer line per PARAM, in uop order -- the
# order `pbufs` pops them (A1). The three lines are the INPUT pattern from
# `.agents/slop/ops_bend-milestone-expected.txt`, which was written BEFORE any run:
#
#     buffer 0   4 efbeadde   a sentinel no correct ADD can produce
#     buffer 1   4 0000803f   1.0f
#     buffer 2   4 00000040   2.0f
def IN_HEX() -> List<&2, String>: ["efbeadde", "0000803f", "00000040"]

def EXPECTED() -> String: "4 00004040\n4 0000803f\n4 00000040\n"

# THE PATTERN, as ONE hex string, and that is not a simplification: a bump
# allocator makes the three buffers CONTIGUOUS (bases 0, 4, 8), so the store is
# exactly the three patterns end to end. One paint instead of three is the same
# write, and the milestone's readback slices each buffer back out -- so a bug in
# the copy-in shows up as a wrong BUFFER rather than a wrong store.
def PATTERN() -> String: String.concat(["efbeadde", "0000803f", "00000040"])

def mem_at(+ms: List<&2, P.Mem>, i: Nat) -> P.Mem:
  Maybe.default(&2, P.Mem, List.get(&2, P.Mem, ms, i), P.Mem.of(0, 0))

# STAGE 1: the packet's THREE buffers, allocated in ONE call. This is not a
# convenience -- it is what `prog.in_bufs` (:200) IS: a LIST of extents, handed
# over in that order, so "allocate the launch's buffers" is one operation and a
# `List<&2, P.Mem>` is the honest answer. The bases are the thing worth gating:
# three buffers all at base 0 is an allocator that does not advance, and a kernel
# over it would read the wrong bytes for reasons the milestone alone cannot
# localise.
#
# ONE CALL rather than three, and the reason is measured: a Bend def cannot
# destructure a computed product ("a match cannot scrutinize a computed value:
# give it its own def"), so three chained `(m, s) = P.raw_alloc(..)` need three
# wrapper defs to launder the pair through a parameter. One call computes the
# pair ONCE and destructures it once.
# NO REVERSE, and that is the fix for a MEASURED bug this milestone found: the
# first version prepended with `List.append` and then called `List.reverse`, but
# `List.append(a, A, xs, ys)` is `xs ++ ys` -- it APPENDS -- so the two cancelled
# into a REVERSED buffer list. MEASURED: `ms_b0_base=8`, `ms_b1_base=4`,
# `ms_b2_base=0` for three 4-byte buffers, which is the allocation order backwards.
# The gate row `ms_b0_base` is what caught it, and it is why the diagnostics run
# BEFORE the launch.
def alloc_all.go(+sizes: List<&2, U32>, +top: U32,
                 +acc: List<&2, P.Mem>) -> List<&2, P.Mem>:
  match sizes:
    case Nil{}: acc
    case n <> t: alloc_all.go(t, U32.add(top, n),
      List.append(&2, P.Mem, acc, [P.Mem.of(top, n)]))

def total_u32(+sizes: List<&2, U32>, +acc: U32) -> U32:
  match sizes:
    case Nil{}: acc
    case n <> t: total_u32(t, U32.add(acc, n))

def grow.to(+nbytes: U32, +s: P.Store) -> P.Store:
  P.Store.of(List.append(&2, U32, P.Store.ms(s), P.zeros(U32.to_nat(nbytes))),
           U32.add(P.Store.top(s), nbytes))

def alloc_pair(p: (List<&2, P.Mem> & U32), +s: P.Store, +sizes: List<&2, U32>) ->
  (List<&2, P.Mem> & P.Store):
  (ms, n) = p
  (ms, grow.to(n, s))

# `+sizes` is the REBIND marker and it is load-bearing twice over: the list is
# read by BOTH `alloc_all.go` and `total_u32`, and `Data`/list values are
# otherwise affine.
def raw_alloc_all(+sizes: List<&2, U32>, +s: P.Store) -> (List<&2, P.Mem> & P.Store):
  alloc_pair((alloc_all.go(sizes, P.Store.top(s), Nil{}), total_u32(sizes, 0)), s, sizes)

def SIZES3() -> List<&2, U32>: [4, 4, 4]

def alloc3(s0: P.Store) -> (List<&2, P.Mem> & P.Store):
  raw_alloc_all(SIZES3(), s0)

# STAGE 2: the pattern. Twelve bytes, and `P.Mem.byte` is the read the executor's
# own `P.Mem.byte` is, so the two memory models agree by construction.
def ms_paint(+s1: P.Store) -> P.Store:
  # `+s1` for the same reason as `grow.to`'s `+nbytes`: `P.Store.ms(s1)` and
  # `P.Store.top(s1)` are two reads of the same name.
  P.Store.of(P.paint(0, P.Store.ms(s1), P.hexbytes(PATTERN()), 12n), P.Store.top(s1))

# THE WHOLE INPUT STATE, in one step: three buffers allocated and the pattern
# written. `milestone` then has exactly two facts to carry -- the store and the
# buffer list -- and nothing else, which is what keeps the launch a trace of
# three values rather than of eight.
# `alloc3` ALREADY answers a `List<&2, P.Mem>` -- it is `raw_alloc_all`'s own
# answer -- so this only paints, and the `[ms]` re-wrap that was here first was a
# type error rather than a design.
def ms_state_pair(p: (List<&2, P.Mem> & P.Store)) -> (List<&2, P.Mem> & P.Store):
  (ms, s1) = p
  (ms, ms_paint(s1))

def ms_state(s0: P.Store) -> (List<&2, P.Mem> & P.Store):
  ms_state_pair(alloc3(s0))

# PACKET.in = the uop block, then one `<nbytes> <hex>` line per buffer. The uop
# block is `P.encode(NODES_TINY())`, which the `bend_emit_tiny_match` row already
# pins byte-for-byte against CPython's `packet-tiny.txt`.
def pkt_in(+ms: List<&2, P.Mem>, +s: P.Store) -> String:
  String.concat([P.Res.s(P.encode(NODES_TINY())), P.Mem.to_line(s, mem_at(ms, 0n)),
    P.Mem.to_line(s, mem_at(ms, 1n)), P.Mem.to_line(s, mem_at(ms, 2n))])

# FILE I/O, and the SHAPE is `ops_python.bend`'s -- `P.Prog.launch.pkt.go` and
# `P.Prog.write` -- rather than mine. That is reuse of a spelling measured to
# typecheck. TWO THINGS LEARNED HERE, both by hitting them:
#   * `match` HEADS A DEF BODY, so a `Result` is dispatched by a def whose body
#     IS the match and each arm an IO term.
#   * `IO.pass(File, r)` is WRONG for a read. Its signature is
#     `IO.pass(-A: Type, r: Result<&1, &1, U32 & String, A>)`, so `A` is the
#     RESULT's payload; with a read result the payload is `String`, not `File`,
#     and the compiler says so. `match` on `Done`/`Fail` sidesteps it.
# THE SIGNATURES ARE `references/bend/bend2/base.bend:264-299`:
#   File.open -> IO(Result<&1, &1, U32 & String, File>)
#   File.read -> IO(File & Result<&1, &1, U32 & String, String>)
# `IO.die` on a `Fail` is what turns a MISSING PACKET.out into a refusal instead
# of an empty string, and an empty string would compare unequal to the expectation
# for a reason that has nothing to do with the kernel.
def read_at(f: File, r: Result<&1, &1, U32 & String, String>) -> IO(String):
  match r:
    case Done{text}:
      IO.bind(Unit, String, File.close(f), _ => IO.pure(String, text))
    case Fail{error}:
      IO.bind(Unit, String, File.close(f), _ => IO.die(String, 1, "BEND milestone: PACKET.out could not be read"))

def Prog.read.go(m: (File & Result<&1, &1, U32 & String, String>)) -> IO(String):
  (f, r) = m
  read_at(f, r)

def read_open(f: File, max: U32) -> IO(String):
  IO.bind(File & Result<&1, &1, U32 & String, String>, String, File.read(f, max), Prog.read.go)

def read_after(r: Result<&1, &1, U32 & String, File>, max: U32) -> IO(String):
  match r:
    case Done{f}: read_open(f, max)
    case Fail{error}: IO.die(String, 1, "BEND milestone: could not open the file for reading")

def read_file(path: String, max: U32) -> IO(String):
  IO.bind(Result<&1, &1, U32 & String, File>, String, File.open(path, "r"),
    r => read_after(r, max))

# ONE DEF FOR THE WHOLE WRITE, and that is a simplification rather than a
# dodge: `ops_python.bend`'s `P.Prog.write.open` -> `P.Prog.write.put` ->
# `P.Prog.write.close` is three because each `IO.bind` adds a continuation, and
# here the three are only ever chained. `File.close` runs on BOTH arms, which is
# what `P.Prog.write.put`'s `m => P.Prog.write.close(m)` does.
def Prog.put.go(m: (File & Result<&1, &1, U32 & String, Unit>)) -> IO(Unit):
  (f, _) = m
  File.close(f)

def put_open(f: File, text: String) -> IO(Unit):
  IO.bind(File & Result<&1, &1, U32 & String, Unit>, Unit, File.write(f, text),
    Prog.put.go)

def put_after(r: Result<&1, &1, U32 & String, File>, text: String) -> IO(Unit):
  match r:
    case Done{f}: put_open(f, text)
    case Fail{error}: IO.die(Unit, 1, "BEND milestone: could not open PACKET.in for writing")

def write_file(path: String, text: String) -> IO(Unit):
  IO.bind(Result<&1, &1, U32 & String, File>, Unit, File.open(path, "w"),
    r => put_after(r, text))

# PACKET.out, read back. `<nbytes> <hex-bytes>` per line, `nbufs` of them --
# `ops_bend.py:225`'s `read_text().splitlines()`. ONE GiB cap, which is the same
# order as the executor's own `File.read(f, 1073741824)` and is not a real limit:
# a packet this port emits is kilobytes.
def pkt_out() -> IO(String): read_file(PKT_OUT(), 1073741824)

# THE LAUNCH, and the refusal at ops_bend.py:224 becomes REAL: a non-zero exit is
# a DIE carrying the executor's own stderr, which is what `subprocess.run` raises
# on at :224-225. `IO.die` rather than a printed row, because a launch that
# failed must not be able to print `ms_pass=True` over an empty readback.
# A `match` ON A BOOL PARAMETER rather than a `Bool.pick`, and that is measured:
# a `Bool.pick` whose arms are IO terms is refused with "a type for this operator
# (write (a < b : Nat))" and the note "operators demand annotation".
# `ops_python.bend` `P.Prog.done.go2.bad` is the same shape -- a def that MATCHES a
# flag and whose arms are the two IO terms.
def launch.ok(cd: U32, +so: String, +se: String) -> IO(Unit): urow("ms_exit", cd)

def launch.bad(cd: U32, +so: String, +se: String) -> IO(Unit):
  IO.die(Unit, 1, String.concat(["the Bend executor exited ", U32.show(cd),
    ": ", so, se]))

# AND THE FLAG IS A PARAMETER, because "a match cannot scrutinize a computed
# value: give it its own def" (MEASURED) -- which is why `ops_python.bend` passes
# `P.Prog.bad(pr)` into `P.Prog.done.go2` rather than matching on it there.
def launch.zero(cd: U32, +so: String, +se: String, +bad: Bool) -> IO(Unit):
  match bad:
    case True{}: launch.bad(cd, so, se)
    case False{}: launch.ok(cd, so, se)

def launch(+cd: U32, so: String, se: String) -> IO(Unit):
  launch.zero(cd, so, se, U32.is_ne(cd, (0 : U32)))

def on_run(r: Result<&1, &1, U32 & String, U32 & (String & String)>) -> IO(Unit):
  match r:
    case Done{value}:
      (cd, (so, se)) = value
      launch(cd, so, se)
    case Fail{(cd, message)}:
      IO.die(Unit, 1, String.concat(["Process.run could not launch the executor: ", message]))

def run_exe() -> IO(Unit):
  # argv is `PACKET gx gy gz` -- the packet FIRST -- and `List.append` is `xs ++ ys`,
  # so the packet is `xs`. ONE work item, because `P.Prog.nout` is 1 for the
  # milestone: `grid(1, ...)` runs the body exactly once.
  IO.bind(Result<&1, &1, U32 & String, U32 & (String & String)>, Unit,
    Process.run(PKT_EXE(), PKT_ARGV(), "",
      1048576, 600000), on_run)

# THE READBACK. `buffer_to` in the executor's own form: PACKET.out is TEXT, so the
# copy-back is a PARSE of one line per buffer, through the SAME hex codec the
# copy-in used -- and DELIBERATELY not a symmetric one, because
# `runtime/ops_python.bend:1201 symbol=P.Prog.alloc.ss` measured what symmetry buys: a reader and a writer wrong
# in the SAME way cancel on a pure copy, so every copy fixture passes while every
# arithmetic one computes on nonsense. So the comparison below is over the emitted
# TEXT, not over a re-parse.
# THE COMPARISON, and it is the whole of the milestone. `ms_got` is the TEXT
# because "the emitted text is a gate, not a boolean" (this file's own rule): a
# boolean over a string can be true while the string is wrong. `EXPECTED()` is the
# expectation written down BEFORE the run in
# `.agents/slop/ops_bend-milestone-expected.txt`.
# THE verdict, AND it is per BUFFER BECAUSE `IO.print` STOPS at a newline.
# MEASURED: the first version printed the whole of PACKET.out as one row and the
# row read `ms_got=4 00004040` -- the FIRST line and nothing else. So `ms_pass` was
# comparing one line against a three-line string, i.e. a row that could only be
# False; it read True for the wrong reason, because the port's own `EXPECTED()`
# string was truncated the same way and the two agreed on a prefix. That is
# shotgun parsing in miniature, and a row that cannot fail is worse than no row.
#
# SO: THREE ROWS, one per buffer, each a single line with no newline in it, and the
# `ms_b*` rows are the gate while `ms_pass` is the summary.
def line_at(+ls: List<&2, String>, i: Nat) -> String:
  Maybe.default(&2, String, List.get(&2, String, ls, i), "")

def EXPECT0() -> String: "4 00004040"
def EXPECT1() -> String: "4 0000803f"
def EXPECT2() -> String: "4 00000040"

def ms_buf_row(+nm: String, +got: String, +want: String) -> IO(Unit):
  do IO<Unit>:
    srow(String.concat([nm, "_got"]), got)
    srow(String.concat([nm, "_want"]), want)
    row(nm, String.eq(got, want))

# THE three lines of packet.out, AND the split now works. This file's own header
# called it a WALL: "String.split(s, P.NLCH()) does not split a packet on its
# newlines". MEASURED AGAIN on the current substrate, and IT IS FIXED:
# String.split("a\nb\nc\n", P.NLCH()) answers FOUR fields -- "a", "b", "c", "" --
# which is exactly `splitlines()` plus the trailing empty. The 40 rows the header
# blamed on this wall are now GREEN (see THE line split is not a wall below).
def out_lines(+text: String) -> IO(Unit):
  IO.bind(Unit, Unit, ms_buf_row("ms_b0", line_at(P.split_lines(text), 0n), EXPECT0()), _ =>
    IO.bind(Unit, Unit, ms_buf_row("ms_b1", line_at(P.split_lines(text), 1n), EXPECT1()), _ =>
      IO.bind(Unit, Unit, ms_buf_row("ms_b2", line_at(P.split_lines(text), 2n), EXPECT2()), _ =>
        row("ms_line_count", U32.is_eq(
          U32.from_nat(List.length(&2, String, P.split_lines(text))), 3)))))

def ms_verdict(text: String) -> IO(Unit): out_lines(text)

# ONE row per DEF, AND the list is the first argument. Two forced choices, both
# MEASURED. (1) A `List<&2, P.Mem>` is AFFINE, so a `do` block of P.N rows over it is
# "expected P.Store / observed P.Mem"; five rows cannot share one def. (2) Arguments
# are read LEFT TO RIGHT, so `ms_row("...", P.Mem.base(mem_at(ms, 0n)), ms)` consumes
# `ms` inside `mem_at` and then cannot hand the same list on -- hence the list
# FIRST. Every def ANSWERS `IO(List<&2, P.Mem>)` and the chain hands each link a list
# to consume, which is the only shape in which an affine list survives five uses.
def ms_row(ms: List<&2, P.Mem>, nm: String, v: U32) -> IO(List<&2, P.Mem>):
  IO.bind(Unit, List<&2, P.Mem>, urow(nm, v), _ => IO.pure(List<&2, P.Mem>, ms))

def ms_srow(ms: List<&2, P.Mem>, nm: String, v: String) -> IO(List<&2, P.Mem>):
  IO.bind(Unit, List<&2, P.Mem>, srow(nm, v), _ => IO.pure(List<&2, P.Mem>, ms))

def ms_row_base0(+ms: List<&2, P.Mem>, s: P.Store) -> IO(List<&2, P.Mem>):
  ms_row(ms, "ms_b0_base", P.Mem.base(mem_at(ms, 0n)))

def ms_row_base1(+ms: List<&2, P.Mem>, s: P.Store) -> IO(List<&2, P.Mem>):
  ms_row(ms, "ms_b1_base", P.Mem.base(mem_at(ms, 1n)))

def ms_row_base2(+ms: List<&2, P.Mem>, s: P.Store) -> IO(List<&2, P.Mem>):
  ms_row(ms, "ms_b2_base", P.Mem.base(mem_at(ms, 2n)))

def ms_row_nbytes(+ms: List<&2, P.Mem>, s: P.Store) -> IO(List<&2, P.Mem>):
  ms_row(ms, "ms_b0_nbytes", P.Mem.nbytes(mem_at(ms, 0n)))

def ms_row_hex0(+ms: List<&2, P.Mem>, s: P.Store) -> IO(List<&2, P.Mem>):
  ms_srow(ms, "ms_b0_hex_in", P.Mem.to_hex(s, mem_at(ms, 0n)))

def ms_row_hex1(+ms: List<&2, P.Mem>, s: P.Store) -> IO(List<&2, P.Mem>):
  ms_srow(ms, "ms_b1_hex_in", P.Mem.to_hex(s, mem_at(ms, 1n)))

def ms_row_hex2(+ms: List<&2, P.Mem>, s: P.Store) -> IO(List<&2, P.Mem>):
  ms_srow(ms, "ms_b2_hex_in", P.Mem.to_hex(s, mem_at(ms, 2n)))

def ms_row_line(+ms: List<&2, P.Mem>, s: P.Store) -> IO(List<&2, P.Mem>):
  ms_srow(ms, "ms_b0_line_in", P.Mem.to_line(s, mem_at(ms, 0n)))

# `raw_free(mem_at(ms, 0n))` renders the FREED buffer, so this row proves the
# no-op by CONTENT rather than by a boolean about it -- which is why `raw_free`
# answers the same `P.Mem` instead of discarding it.
def ms_row_free(+ms: List<&2, P.Mem>, s: P.Store) -> IO(List<&2, P.Mem>):
  ms_srow(ms, "ms_free_noop", P.Mem.to_line(s, raw_free(mem_at(ms, 0n))))

def ms_row_top(+s: P.Store, ms: List<&2, P.Mem>) -> IO(List<&2, P.Mem>):
  IO.bind(Unit, List<&2, P.Mem>, urow("ms_store_top", P.Store.top(s)), _ =>
    IO.bind(Unit, List<&2, P.Mem>,
      urow("ms_store_len", U32.from_nat(List.length(&2, U32, P.Store.ms(s)))),
      _ => IO.pure(List<&2, P.Mem>, ms)))

def ms_stage2a(ms: List<&2, P.Mem>, +s: P.Store) -> IO(List<&2, P.Mem>):
  ms_row_top(s, ms)

def ms_stage2b(ms: List<&2, P.Mem>, +s: P.Store) -> IO(List<&2, P.Mem>):
  IO.bind(List<&2, P.Mem>, List<&2, P.Mem>, ms_row_base0(ms, s), a =>
    IO.bind(List<&2, P.Mem>, List<&2, P.Mem>, ms_row_base1(a, s), b =>
      ms_row_base2(b, s)))

def ms_stage2c(ms: List<&2, P.Mem>, +s: P.Store) -> IO(List<&2, P.Mem>):
  ms_row_nbytes(ms, s)

def ms_stage2d(ms: List<&2, P.Mem>, +s: P.Store) -> IO(List<&2, P.Mem>):
  IO.bind(List<&2, P.Mem>, List<&2, P.Mem>, ms_row_hex0(ms, s), a =>
    IO.bind(List<&2, P.Mem>, List<&2, P.Mem>, ms_row_hex1(a, s), b =>
      ms_row_hex2(b, s)))

def ms_stage2e(ms: List<&2, P.Mem>, +s: P.Store) -> IO(List<&2, P.Mem>):
  IO.bind(List<&2, P.Mem>, List<&2, P.Mem>, ms_row_line(ms, s), a =>
    ms_row_free(a, s))

# THE TERMINAL. `ms_die_unit` DISCARDS the finished walk, and it is
# `IO.die(Unit, 0, "")` rather than a `Unit` VALUE because Bend has no `Unit`
# inhabitant -- every spelling of one is refused (MEASURED: "expected Unit /
# observed Type"). Nothing meaningful is discarded: the verdict came from `text`.
def ms_die_unit(_: List<&2, P.Mem>) -> IO(Unit): IO.die(Unit, 0, "")

def ms_stage2f(ms: List<&2, P.Mem>, +s: P.Store) -> IO(List<&2, P.Mem>):
  IO.bind(List<&2, P.Mem>, List<&2, P.Mem>, ms_stage2a(ms, s), a =>
    IO.bind(List<&2, P.Mem>, List<&2, P.Mem>, ms_stage2b(a, s), b =>
      IO.bind(List<&2, P.Mem>, List<&2, P.Mem>, ms_stage2c(b, s), c =>
        IO.bind(List<&2, P.Mem>, List<&2, P.Mem>, ms_stage2d(c, s), d =>
          ms_stage2e(d, s)))))

def on_rows(ms: List<&2, P.Mem>, +s: P.Store) -> IO(Unit):
  IO.bind(List<&2, P.Mem>, Unit, ms_stage2f(ms, s), ms_die_unit)

def on_out(ms: List<&2, P.Mem>, +s: P.Store, text: String) -> IO(Unit):
  IO.bind(Unit, Unit, ms_verdict(text), _ => on_rows(ms, s))

# THE three IO STEPS, AND the diagnostics run between the write and the launch.
# That ordering is a CORRECTION, measured: a refused launch `IO.die`s and every row
# after it is LOST, so the first version of this milestone reported NOTHING about
# the allocator when the launch failed -- which is exactly the state a reader
# needs. Now the bases, the extents, the store length and the hex all print BEFORE
# the executor is asked anything, so a refusal is diagnosable rather than silent.
def on_launch(ms: List<&2, P.Mem>, +s: P.Store) -> IO(Unit):
  do IO<Unit>:
    r : Unit <- run_exe()
    out : String <- pkt_out()
    on_out(ms, s, out)

# WRITE, THEN DIAGNOSE, THEN LAUNCH -- and the second bind's B type is `Unit`
# because `on_launch` answers `Unit` (MEASURED: naming `List<&2, P.Mem>` there is
# "expected Unit -> IO / observed List<&2, P.Mem> -> IO").
def on_diag(+ms: List<&2, P.Mem>, +s: P.Store) -> IO(Unit):
  IO.bind(Unit, Unit, write_file(PKT_IN(), pkt_in(ms, s)), _ =>
    IO.bind(List<&2, P.Mem>, Unit, ms_stage2f(ms, s), _ => on_launch(ms, s)))

def on_packet(ms: List<&2, P.Mem>, +s: P.Store) -> IO(Unit): on_diag(ms, s)

# THE ENTRY. `ms_state(store())` answers a COMPUTED Sigma and a computed Sigma
# cannot be an `IO.bind` argument (MEASURED: "expected Sigma<&1,&1,List<&2,P.Mem>,
# P.Store> / observed Sigma" -- the DEPTH ANNOTATION is what disagrees), so it is
# lifted into an `IO.pure` first and the continuation destructures it. That is
# also why `on_state` exists: a lambda cannot destructure a pair.
def ms_io() -> IO((List<&2, P.Mem> & P.Store)): IO.pure(List<&2, P.Mem> & P.Store, ms_state(store()))

def on_state(p: (List<&2, P.Mem> & P.Store)) -> IO(Unit):
  (ms, s) = p
  on_packet(ms, s)

def milestone() -> IO(Unit):
  IO.bind(List<&2, P.Mem> & P.Store, Unit, ms_io(), on_state)

# THE allocator and codec rows. `bend_alloc_*` reads the bump with NOTHING
# written, so a bug in the copy-in cannot be mistaken for a bug in the allocator;
# `bend_hexbyte_*` pins the writer against LITERALS rather than against the reader,
# which is the whole point of the asymmetry noted above.
def ms_gate_rows() -> IO(Unit):
  do IO<Unit>:
    urow("bend_alloc_bump0", P.Mem.base(alloc_mem(4, store())))
    urow("bend_alloc_bump1", P.Store.top(alloc_store(4, store())))
    urow("bend_alloc_bump2", P.Store.top(alloc_store(4, alloc_store(4, store()))))
    urow("bend_alloc_nbytes", P.Mem.nbytes(alloc_mem(16, store())))
    urow("bend_alloc_len1", U32.from_nat(List.length(&2, U32,
      P.Store.ms(alloc_store(4, store())))))
    urow("bend_alloc_len3", U32.from_nat(List.length(&2, U32,
      P.Store.ms(alloc_store(4, alloc_store(4, store()))))))
    # NOT "the first alloc's base is nonzero" -- it is 0 by construction and
    # asserting otherwise is a row that encodes the bug. The claim is that the
    # SECOND alloc starts where the first ended, which is the only thing
    # "advances" can mean for a bump allocator.
    row("bend_alloc_advances", U32.is_eq(P.Mem.base(alloc_mem(4,
      alloc_store(4, store()))), 4))
    row("bend_free_is_noop", U32.is_eq(P.Mem.base(raw_free(alloc_mem(4, store()))),
      P.Mem.base(alloc_mem(4, store()))))
    srow("bend_hexbyte_ef", P.hexbyte(239))
    srow("bend_hexbyte_00", P.hexbyte(0))
    srow("bend_hexbyte_ff", P.hexbyte(255))
    srow("bend_hexbyte_3f", P.hexbyte(63))
    srow("bend_hexbyte_40", P.hexbyte(64))
    srow("bend_hexdig_0", P.hexdig_str2(0))
    srow("bend_hexdig_9", P.hexdig_str2(9))
    srow("bend_hexdig_a", P.hexdig_str2(10))
    srow("bend_hexdig_f", P.hexdig_str2(15))
    row("bend_hex_ok_digit", hexdig_ok(48))
    row("bend_hex_ok_lower", hexdig_ok(102))
    row("bend_hex_ok_upper", hexdig_ok(70))
    row("bend_hex_ok_g", hexdig_ok(103))
    row("bend_hex_odd_drops", U32.is_eq(U32.from_nat(List.length(&2, U32,
      P.hexbytes("abc"))), 1))
    urow("bend_hexval_f", P.hexdig_val(102))
    urow("bend_hexval_A", P.hexdig_val(65))

def milestone.main() -> IO(Unit):
  do IO<Unit>:
    ms_gate_rows()
    p : Unit <- milestone()
    IO.print("ms-done=1")


# --- 1: THE LANE TABLE, :90, both directions -----------------------------
#
# The forward direction is `P.lanes(dt)`; the reverse is the dtype round trip
# `getattr(dtypes, name.lower()).name == name`, which is what the executor's
# `to_dtype` does with the name `wire_dtype` emits. A one-directional table
# is how ops_nv shipped 33 wrong constants behind 590 green rows.
def t_lanes() -> IO(Unit):
  do IO<Unit>:
    row("bend_lanefree_i32", P.lane_free("i32"))
    row("bend_lanefree_i32_not_lane", Bool.not(P.lanes("i32")))
    row("bend_lanefree_u32", P.lane_free("u32"))
    row("bend_lanefree_u32_not_lane", Bool.not(P.lanes("u32")))
    row("bend_lanefree_f32", P.lane_free("f32"))
    row("bend_lanefree_f32_not_lane", Bool.not(P.lanes("f32")))
    row("bend_lanefree_bool", P.lane_free("bool"))
    row("bend_lanefree_bool_not_lane", Bool.not(P.lanes("bool")))
    row("bend_lanefree_void", P.lane_free("void"))
    row("bend_lanefree_void_not_lane", Bool.not(P.lanes("void")))
    row("bend_lanefree_weakint", P.lane_free("weakint"))
    row("bend_lanefree_weakint_not_lane", Bool.not(P.lanes("weakint")))
    row("bend_lanefree_weakfloat", P.lane_free("weakfloat"))
    row("bend_lanefree_weakfloat_not_lane", Bool.not(P.lanes("weakfloat")))
    row("bend_lane_f16", P.lanes("f16"))
    row("bend_lane_bf16", P.lanes("bf16"))
    row("bend_lane_f64", P.lanes("f64"))
    row("bend_lane_i64", P.lanes("i64"))
    row("bend_lane_u8", P.lanes("u8"))
    row("bend_lane_u16", P.lanes("u16"))
    row("bend_lane_i16", P.lanes("i16"))
    row("bend_lane_u64", P.lanes("u64"))
    row("bend_lane_i8", P.lanes("i8"))
    row("bend_lane_fp8e4m3", P.lanes("fp8e4m3"))
    row("bend_lane_fp8e5m2", P.lanes("fp8e5m2"))
    row("bend_lane_fp8e4m3fnuz", P.lanes("fp8e4m3fnuz"))
    row("bend_lane_fp8e5m2fnuz", P.lanes("fp8e5m2fnuz"))
    srow("bend_lane_sorted", "dtypes.bool dtypes.f32 dtypes.i32 dtypes.u32")
    row("bend_lane_sorted_is_literal", String.eq(P.LANES_SORTED(), "dtypes.bool dtypes.f32 dtypes.i32 dtypes.u32"))

# --- 2: THE DTYPE ROUND TRIP, both directions ---------------------------
#
# `wire_dtype` emits `u.dtype.name` and the executor's `to_dtype` is
# `getattr(dtypes, name.lower())`, so the pair (name -> attribute -> name) has
# to be the identity. MEASURED by `getattr(dtypes, n.lower()).name` in CPython
# for every name in the vocabulary; a name that is not an attribute would have
# raised, so the fixture is the CLOSURE of the attribute set.
def t_dtypes() -> IO(Unit):
  do IO<Unit>:
    srow("bend_rt_i8", "i8")
    srow("bend_rt_u8", "u8")
    srow("bend_rt_i16", "i16")
    srow("bend_rt_u16", "u16")
    srow("bend_rt_i32", "i32")
    srow("bend_rt_u32", "u32")
    srow("bend_rt_i64", "i64")
    srow("bend_rt_u64", "u64")
    srow("bend_rt_f16", "f16")
    srow("bend_rt_bf16", "bf16")
    srow("bend_rt_f32", "f32")
    srow("bend_rt_f64", "f64")
    srow("bend_rt_fp8e4m3", "fp8e4m3")
    srow("bend_rt_fp8e5m2", "fp8e5m2")
    srow("bend_rt_fp8e4m3fnuz", "fp8e4m3fnuz")
    srow("bend_rt_fp8e5m2fnuz", "fp8e5m2fnuz")
    srow("bend_rt_void", "void")
    srow("bend_rt_weakint", "weakint")
    srow("bend_rt_weakfloat", "weakfloat")
    srow("bend_sz_i8", "i8 1")
    srow("bend_sz_u8", "u8 1")
    srow("bend_sz_i16", "i16 2")
    srow("bend_sz_u16", "u16 2")
    srow("bend_sz_i32", "i32 4")
    srow("bend_sz_u32", "u32 4")
    srow("bend_sz_i64", "i64 8")
    srow("bend_sz_u64", "u64 8")
    srow("bend_sz_f16", "f16 2")
    srow("bend_sz_bf16", "bf16 2")
    srow("bend_sz_f32", "f32 4")
    srow("bend_sz_f64", "f64 8")
    srow("bend_sz_fp8e4m3", "fp8e4m3 1")
    srow("bend_sz_fp8e5m2", "fp8e5m2 1")
    srow("bend_sz_void", "void 0")
    srow("bend_sz_weakint", "weakint 100")
    srow("bend_sz_weakfloat", "weakfloat 100")

# --- 3: THE `wire_dtype` REFUSAL, text and all --------------------------
#
# `BEND v1 has no lane for X (on Y); it has Z` is a decision with a MESSAGE, so
# a boolean about it would be exactly the row that cannot fail. The rows are
# the message.
def t_refuse_dtype() -> IO(Unit):
  do IO<Unit>:
    srow("bend_refuse_f64", P.Res.s(P.wire_dtype("f64", "PARAM")))
    row("bend_refuse_f64_refused", Bool.not(P.Res.ok(P.wire_dtype("f64", "PARAM"))))
    srow("bend_refuse_u64", P.Res.s(P.wire_dtype("u64", "PARAM")))
    row("bend_refuse_u64_refused", Bool.not(P.Res.ok(P.wire_dtype("u64", "PARAM"))))
    srow("bend_refuse_f16", P.Res.s(P.wire_dtype("f16", "CAST")))
    row("bend_refuse_f16_refused", Bool.not(P.Res.ok(P.wire_dtype("f16", "CAST"))))
    srow("bend_refuse_fp8e5m2", P.Res.s(P.wire_dtype("fp8e5m2", "CAST")))
    row("bend_refuse_fp8e5m2_refused", Bool.not(P.Res.ok(P.wire_dtype("fp8e5m2", "CAST"))))
    srow("bend_refuse_i8", P.Res.s(P.wire_dtype("i8", "CAST")))
    row("bend_refuse_i8_refused", Bool.not(P.Res.ok(P.wire_dtype("i8", "CAST"))))
    srow("bend_refuse_bf16", P.Res.s(P.wire_dtype("bf16", "PARAM")))
    row("bend_refuse_bf16_refused", Bool.not(P.Res.ok(P.wire_dtype("bf16", "PARAM"))))
    srow("bend_refuse_fp8e4m3fnuz", P.Res.s(P.wire_dtype("fp8e4m3fnuz", "PARAM")))
    row("bend_refuse_fp8e4m3fnuz_refused", Bool.not(P.Res.ok(P.wire_dtype("fp8e4m3fnuz", "PARAM"))))
    srow("bend_refuse_i16", P.Res.s(P.wire_dtype("i16", "PARAM")))
    row("bend_refuse_i16_refused", Bool.not(P.Res.ok(P.wire_dtype("i16", "PARAM"))))
    srow("bend_refuse_i64", P.Res.s(P.wire_dtype("i64", "PARAM")))
    row("bend_refuse_i64_refused", Bool.not(P.Res.ok(P.wire_dtype("i64", "PARAM"))))
    srow("bend_refuse_u16", P.Res.s(P.wire_dtype("u16", "PARAM")))
    row("bend_refuse_u16_refused", Bool.not(P.Res.ok(P.wire_dtype("u16", "PARAM"))))
    srow("bend_refuse_u8", P.Res.s(P.wire_dtype("u8", "PARAM")))
    row("bend_refuse_u8_refused", Bool.not(P.Res.ok(P.wire_dtype("u8", "PARAM"))))

# --- 4: THE emitted source. STRINGS before booleans ---------------------
#
# `String.concat` drops a literal silently, so a boolean about a string can be
# true while the string is wrong. Each row below IS the packet, escaped, and
# the check is `diff .agents/slop/packet-<case>.txt` against what
# `bend_emit_<case>` prints.
def t_emit() -> IO(Unit):
  do IO<Unit>:
    srow("bend_emit_tiny", P.Res.s(P.encode(NODES_TINY())))
    row("bend_emit_tiny_ok", P.Res.ok(P.encode(NODES_TINY())))
    srow("bend_pkt_tiny", compiler.of(PKT_TINY()))
    row("bend_emit_tiny_match", String.eq(P.Res.s(P.encode(NODES_TINY())), PKT_TINY()))
    srow("bend_emit_fconst", P.Res.s(P.encode(NODES_FCONST())))
    row("bend_emit_fconst_ok", P.Res.ok(P.encode(NODES_FCONST())))
    srow("bend_pkt_fconst", compiler.of(PKT_FCONST()))
    row("bend_emit_fconst_match", String.eq(P.Res.s(P.encode(NODES_FCONST())), PKT_FCONST()))
    srow("bend_emit_cmp", P.Res.s(P.encode(NODES_CMP())))
    row("bend_emit_cmp_ok", P.Res.ok(P.encode(NODES_CMP())))
    srow("bend_pkt_cmp", compiler.of(PKT_CMP()))
    row("bend_emit_cmp_match", String.eq(P.Res.s(P.encode(NODES_CMP())), PKT_CMP()))

# --- 5: `BendProgram.__init__`, :195-209 --------------------------------
#
# `nbufs` is the header's second field, `in_bufs` the buffer PARAM extents in
# uop order, and `out_bufs` the POSITIONS of the buffers a STORE reaches. The
# position is `sum(P.is_buf(x.arg) for x in uops[:b])`, a COUNT of buffer PARAMs
# before the base -- not the uop index -- and that is the line this gate is
# most likely to get wrong.
def t_prog() -> IO(Unit):
  do IO<Unit>:
    urow("bend_prog_tiny_nbufs", P.Prog.nbufs(P.prog.of(NODES_TINY())))
    row("bend_prog_tiny_nbufs_ok", U32.is_eq(P.Prog.nbufs(P.prog.of(NODES_TINY())), 3))
    lrow("bend_prog_tiny_in_bufs", P.Prog.in_bufs(P.prog.of(NODES_TINY())))
    row("bend_prog_tiny_in_bufs_ok", String.eq(ujoin(P.Prog.in_bufs(P.prog.of(NODES_TINY()))), "4 4 4"))
    lrow("bend_prog_tiny_out_bufs", P.Prog.out_bufs(P.prog.of(NODES_TINY())))
    row("bend_prog_tiny_out_bufs_ok", String.eq(ujoin(P.Prog.out_bufs(P.prog.of(NODES_TINY()))), "0"))
    urow("bend_prog_fconst_nbufs", P.Prog.nbufs(P.prog.of(NODES_FCONST())))
    row("bend_prog_fconst_nbufs_ok", U32.is_eq(P.Prog.nbufs(P.prog.of(NODES_FCONST())), 2))
    lrow("bend_prog_fconst_in_bufs", P.Prog.in_bufs(P.prog.of(NODES_FCONST())))
    row("bend_prog_fconst_in_bufs_ok", String.eq(ujoin(P.Prog.in_bufs(P.prog.of(NODES_FCONST()))), "16 16"))
    lrow("bend_prog_fconst_out_bufs", P.Prog.out_bufs(P.prog.of(NODES_FCONST())))
    row("bend_prog_fconst_out_bufs_ok", String.eq(ujoin(P.Prog.out_bufs(P.prog.of(NODES_FCONST()))), "0"))
    urow("bend_prog_cmp_nbufs", P.Prog.nbufs(P.prog.of(NODES_CMP())))
    row("bend_prog_cmp_nbufs_ok", U32.is_eq(P.Prog.nbufs(P.prog.of(NODES_CMP())), 2))
    lrow("bend_prog_cmp_in_bufs", P.Prog.in_bufs(P.prog.of(NODES_CMP())))
    row("bend_prog_cmp_in_bufs_ok", String.eq(ujoin(P.Prog.in_bufs(P.prog.of(NODES_CMP()))), "4 16"))
    lrow("bend_prog_cmp_out_bufs", P.Prog.out_bufs(P.prog.of(NODES_CMP())))
    row("bend_prog_cmp_out_bufs_ok", String.eq(ujoin(P.Prog.out_bufs(P.prog.of(NODES_CMP()))), "0"))

# --- 6: THE LAUNCH TRACE, and the three refusals ------------------------
def t_call() -> IO(Unit):
  do IO<Unit>:
    # a clean launch: exe, mv, pkt, run, out, then one write-back per
    # out_bufs -- and NO raise step, because a non-raising step still shows
    # its name in the trace.
    srow("bend_call_ok", String.join(P.Tr.calls(prog.call(P.prog.of(NODES_TINY()), P.Lc.of(1, 1, 1, 0, 3), P.Tr.of())), ","))
    # :221 local_size -- the refusal records itself and truncates.
    srow("bend_call_local", String.join(P.Tr.calls(prog.call(P.prog.of(NODES_TINY()), P.Lc.of(1, 2, 1, 0, 3), P.Tr.of())), ","))
    row("bend_call_local_refused", P.Tr.refused(prog.call(P.prog.of(NODES_TINY()), P.Lc.of(1, 2, 1, 0, 3), P.Tr.of())))
    row("bend_call_warp1", P.is_warp1(P.Lc.of(1, 2, 1, 0, 3)))
    row("bend_call_warp1_1", Bool.not(P.is_warp1(P.Lc.of(1, 1, 1, 0, 3))))
    srow("bend_call_warp1_msg", P.warp1_msg(P.Lc.of(1, 2, 1, 0, 3)))
    srow("bend_call_warp1_msg_py", "BEND v1 is warp 1, so it cannot launch with local_size=(1, 2, 1)")
    row("bend_call_warp1_msg_ok", String.eq(P.warp1_msg(P.Lc.of(1, 2, 1, 0, 3)), "BEND v1 is warp 1, so it cannot launch with local_size=(1, 2, 1)"))
    # :224 a non-zero exit code.
    row("bend_call_rc_refused", P.Tr.refused(prog.call(P.prog.of(NODES_TINY()), P.Lc.of(1, 1, 1, 3, 3), P.Tr.of())))
    urow("bend_call_rc_steps", U32.from_nat(List.length(&2, String, P.Tr.calls(prog.call(P.prog.of(NODES_TINY()), P.Lc.of(1, 1, 1, 3, 3), P.Tr.of())))))
    # :226 the wrong buffer count.
    row("bend_call_nbufs_refused", P.Tr.refused(prog.call(P.prog.of(NODES_TINY()), P.Lc.of(1, 1, 1, 0, 2), P.Tr.of())))
    row("bend_call_nbufs_ok", Bool.not(P.Tr.refused(prog.call(P.prog.of(NODES_TINY()), P.Lc.of(1, 1, 1, 0, 3), P.Tr.of()))))

# --- 7: THE SMALL DEFS, :232 and :238 -----------------------------------
# THE FIXTURE FOR `take_nat`: five fields, so `take 0/1/2` are three
# DIFFERENT answers and a `take` that is off by one cannot hide.
def PKT_LINES() -> List<&2, String>: ["h", "a", "b", "c", "d"]

# THE four wall-CLEARING fixes, AS rows. Each was a real defect that the header
# attributed to WALL 4, and each is pinned here so it cannot come back silently.
# CPython is the oracle for every one; the values were read out of
# `BendProgram.__init__(pkt-tiny.txt)`, which answers
# `nbufs=3, in_bufs=[4, 4, 4], out_bufs=[0]`.
#
# 1. `drop4`: the srcs start at field 4, not 3, because `12:` is ONE field. And
#    the walk is order-preserving. MEASURED: `drop3([9,9,9,9,10,11])` answered
#    `11 10 9` -- the tail, reversed -- and `drop4` with a trailing `List.reverse`
#    answered `11 10 0 0`. Append with NO reverse is the one that is right.
def t_drop() -> IO(Unit):
  do IO<Unit>:
    # CPython, MEASURED on `12: STORE void - 10 11`:
    #     raw.split()            -> 6 fields
    #     _, op, dt, arg, *srcs  -> srcs == ['10', '11']
    urow("bend_drop4_wlen", U32.from_nat(List.length(&2, String, P.words("12: STORE void - 10 11"))))
    urow("bend_drop4_mlen", U32.from_nat(List.length(&2, U32, P.map_dec(P.words("12: STORE void - 10 11")))))
    urow("bend_drop4_dlen", U32.from_nat(List.length(&2, U32, P.drop4(P.map_dec(P.words("12: STORE void - 10 11"))))))
    lrow("bend_drop4_line", P.drop4(P.map_dec(P.words("12: STORE void - 10 11"))))
    row("bend_drop4_line_ok", String.eq(ujoin(P.drop4(P.map_dec(P.words("12: STORE void - 10 11")))), "10 11"))
    # the PLAIN fixture: four dummies then two srcs, and the tail is the two srcs.
    lrow("bend_drop4_tail", P.drop4([9, 9, 9, 9, 10, 11]))
    row("bend_drop4_ok", String.eq(ujoin(P.drop4([9, 9, 9, 9, 10, 11])), "10 11"))
    # `drop3` is the OLD THREE-NAME SPELLING and it keeps the arg, which is the
    # whole :188 bug: every :208 walk started from the arg instead of src 10.
    lrow("bend_drop3_line", drop3(P.map_dec(P.words("12: STORE void - 10 11"))))
    row("bend_drop3_keeps_arg", String.eq(ujoin(drop3(P.map_dec(P.words("12: STORE void - 10 11")))), "0 10 11"))
    # a shorter list than the count must not invent elements
    urow("bend_drop4_short", U32.from_nat(List.length(&2, U32, P.drop4([9, 10]))))

# 2. `take_nat`: `case h <> t 0n: [h]` took ONE element once the count was spent,
#    so `P.take1(xs)` answered TWO fields and `header_only` glued the header onto the
#    first uop line ("3" + "1:" -> "31:"). `dec` read that as 0, which is where
#    `bend_parse_nbufs=0` came from. The fix: `0n` answers `Nil{}`.
def t_take() -> IO(Unit):
  do IO<Unit>:
    urow("bend_take1_len", U32.from_nat(List.length(&2, String, P.take1(PKT_LINES()))))
    row("bend_take1_ok", U32.is_eq(U32.from_nat(
      List.length(&2, String, P.take1(PKT_LINES()))), 1))
    urow("bend_take0_len", U32.from_nat(List.length(&2, String,
      P.take_nat(PKT_LINES(), 0n))))
    urow("bend_take2_len", U32.from_nat(List.length(&2, String,
      P.take_nat(PKT_LINES(), 2n))))
    srow("bend_hdr2", P.fld2(P.header_only(PKT_TINY())))
    urow("bend_hdr_nfields", U32.from_nat(List.length(&2, String, P.header_only(PKT_TINY()))))
    urow("bend_parse_nbufs", P.Pkt.nbufs(P.parse(PKT_TINY())))
    urow("bend_parse_nlines", U32.from_nat(List.length(&2, P.Line, P.Pkt.lines(P.parse(PKT_TINY())))))

# 3. `prog.of.pkt`: THE ARMS WERE SWAPPED. `Bool.pick(-A, cond, THEN, ELSE)` takes
#    the FIRST arm on True, so a GOOD packet was built as `P.Prog.of(False{}, ...)`.
def t_pick() -> IO(Unit):
  do IO<Unit>:
    row("bend_pick_true_first", String.eq(P.Res.s(Bool.pick(P.Res, True{}, P.Res{True{}, "t"}, P.Res{True{}, "f"})), "t"))
    row("bend_pick_false_first", String.eq(P.Res.s(Bool.pick(P.Res, False{}, P.Res{True{}, "t"}, P.Res{True{}, "f"})), "f"))

# 4. THE `bases` TABLE IS GONE. It claimed `base[j]` is the largest k <= j that is
#    not a chain op, which is FALSE: :208 follows the SRC POINTER, which can jump
#    over a non-chain line. On `packet-tiny.txt` the STORE at 0-based 11 reads src
#    10, so `b = 9`; line 9 is `INDEX f32 - 1 5` and following its pointer gives
#    `b = 0` -- a PARAM -- where the table's rule gives 8. `chase` is the real walk
#    and `bend_prog_*_out_bufs` is the row that reads it. CPython's answer is `[0]`
#    for all three packets (MEASURED by calling `BendProgram.__init__`).
def t_chase() -> IO(Unit):
  do IO<Unit>:
    # the STORE at 0-based 11, and the :208 chase from its src 10 -> b = 9.
    urow("bend_chase_store", P.store_base.of(P.Pkt.lines(P.parse(PKT_TINY())), 11n))
    urow("bend_chase_fconst", P.store_base.of(P.Pkt.lines(P.parse(PKT_FCONST())), 26n))
    urow("bend_chase_cmp", P.store_base.of(P.Pkt.lines(P.parse(PKT_CMP())), 28n))
    row("bend_chase_lands_on_buf",
      Bool.or(U32.is_eq(P.store_base.of(P.Pkt.lines(P.parse(PKT_TINY())), 11n), 0),
        Bool.or(U32.is_eq(P.store_base.of(P.Pkt.lines(P.parse(PKT_FCONST())), 26n), 0),
          U32.is_eq(P.store_base.of(P.Pkt.lines(P.parse(PKT_CMP())), 28n), 0))))

def t_misc() -> IO(Unit):
  do IO<Unit>:
    row("bend_has_local", has_local())
    row("bend_compiler_passthrough", String.eq(compiler.of(PKT_TINY()), PKT_TINY()))
    row("bend_compiler_is_encode", String.eq(compiler.of(P.Res.s(P.encode(NODES_TINY()))), P.Res.s(P.encode(NODES_TINY()))))
    # `is_image_shape` :126, `len(shape)==3 and shape[-1]==4`.
    row("bend_img_empty", P.is_image_shape(0, 0))
    row("bend_img_2_3_4", P.is_image_shape(3, 4))
    row("bend_img_2_3_4_5", P.is_image_shape(4, 5))
    row("bend_img_2_3_5", P.is_image_shape(3, 5))
    row("bend_img_4", P.is_image_shape(1, 4))
    row("bend_img_4_4", P.is_image_shape(2, 4))
    row("bend_img_none", P.is_image_shape(0, 0))
    # `wire_width` :103, and the two `op` arms a real packet reaches.
    urow("bend_width_load", P.wire_width(P.Ns.at(NODES_TINY(), 7)))
    urow("bend_width_param", P.wire_width(P.Ns.at(NODES_TINY(), 1)))
    urow("bend_width_const", P.wire_width(P.Ns.at(NODES_TINY(), 4)))
    # `is_buf` :177 and `buf_extent` :178.
    row("bend_buf_g", P.is_buf("k:param:16:g"))
    row("bend_buf_l", P.is_buf("k:param:16:l"))
    row("bend_buf_r", Bool.not(P.is_buf("k:param:16:r")))
    row("bend_buf_a", Bool.not(P.is_buf("k:param:16:a")))
    row("bend_buf_dash", Bool.not(P.is_buf("-")))
    urow("bend_extent_16", P.buf_extent("k:param:16:g"))
    urow("bend_extent_4", P.buf_extent("k:param:4:g"))
    urow("bend_extent_1024", P.buf_extent("k:param:1024:g"))
    # the PARAM LETTER, :116 -- a direct fixture, because NO REAL PACKET
    # carries a REG or an ALU PARAM and M6/M17 cannot move a row without it.
    srow("bend_letter_global", P.letter_str(P.letter.of("GLOBAL")))
    srow("bend_letter_reg", P.letter_str(P.letter.of("REG")))
    srow("bend_letter_alu", P.letter_str(P.letter.of("ALU")))
    srow("bend_letter_local", P.letter_str(P.letter.of("LOCAL")))
    urow("bend_letter_local_code", P.letter.of("LOCAL"))
    # `const_arg` :118 and `vec_arg` :130 read their node directly, so the
    # two CONST carriers and the two LOAD widths have fixtures of their own.
    srow("bend_const_c", P.const_arg(P.Ns.at(NODES_TINY(), 4)))
    srow("bend_const_f", P.const_arg(P.Ns.at(NODES_FCONST(), 19)))
    srow("bend_vec_1", P.vec_arg(1))
    srow("bend_vec_4", P.vec_arg(4))
    srow("bend_vec_0", P.vec_arg(0))

# --- 8: `parse` :180, round trip and the header refusal ----------------
def Line.text(+l: P.Line) -> String:
  String.concat([P.Line.op(l), " ", P.Line.dt(l), " ", P.Line.arg(l)])

def line1(src: String) -> String:
  Line.text(Maybe.default(&2, P.Line, List.get(&2, P.Line, P.Pkt.lines(P.parse(src)), 0n),
    P.Line.of("-", "-", "-", Nil{})))

def t_parse() -> IO(Unit):
  do IO<Unit>:
    urow("bend_parse_nlines", U32.from_nat(List.length(&2, P.Line, P.Pkt.lines(P.parse(PKT_TINY())))))
    row("bend_parse_ok", P.Pkt.ok(P.parse(PKT_TINY())))
    row("bend_parse_bad", Bool.not(P.Pkt.ok(P.parse("bendexec 1 0\n"))))
    srow("bend_parse_bad_msg", P.Pkt.msg(P.parse("bendexec 1 0\n")))
    # the FIRST line of the packet, back out of `parse`. `P.Line.of.of` is
    srow("bend_parse_l1", line1(PKT_TINY()))
    srow("bend_parse_l1_py", "PARAM f32 k:param:4:g")
def gate() -> IO(Unit):
  do IO<Unit>:
    m0 : Unit <- t_lanes()
    m1 : Unit <- t_dtypes()
    m2 : Unit <- t_refuse_dtype()
    m3 : Unit <- t_emit()
    m4 : Unit <- t_prog()
    m5 : Unit <- t_call()
    m6 : Unit <- t_misc()
    m7 : Unit <- t_parse()
    m8 : Unit <- t_drop()
    m9 : Unit <- t_take()
    ma : Unit <- t_pick()
    mb : Unit <- t_chase()
    IO.print("bend-done=1")

# THE LANE SPLIT. `bend LANE` runs the gate; `bend LANE opsbend` runs the
# milestone. The split is on the SECOND argument and not on the first, because
# `bend <file>` always spends argv[0] on the program's own path -- so a split on
# argv[0] would take the milestone branch for a plain gate run.
# `match` ON A BOOL PARAMETER again, for the reason measured at `launch`: a
# `Bool.pick` whose arms are IO terms is refused ("a type for this operator"),
# and here it also cannot name `IO` at all. The split is one def per arm.
def main.gate(_: Bool, +lane: String) -> IO(Unit): gate()

def main.ms(_: Bool, +lane: String) -> IO(Unit): milestone.main()

def main.pick(+lane: String, +is_gate: Bool) -> IO(Unit):
  match is_gate:
    case True{}: main.gate(is_gate, lane)
    case False{}: main.ms(is_gate, lane)

def main.at(+lane: String) -> IO(Unit): main.pick(lane, String.eq(lane, "gate"))

# `IO.args()` answers a `List<&1, String>` -- one lifetime DEEPER than a `String`
# parameter, MEASURED -- and the lane is read by INDEX, so the depth annotation is
# `&1` here and not `&2`. `Maybe.default` with "gate" is the default lane, which
# is what makes a bare `./bin/bend ops_bend.bend` run the gate.
def lane_of(as: List<&1, String>) -> IO(String):
  IO.pure(String, Maybe.default(&1, String, List.get(&1, String, as, 1n), "gate"))

def main() -> IO(Unit):
  do IO<Unit>:
    as : List<String> <- IO.args()
    lane : String <- lane_of(as)
    main.at(lane)


# ===========================================================================
# THE MUTATION TABLE. Every number is `.agents/slop/bend_mutate.py`'s output,
# not an estimate. The harness applies ONE edit to a scratch copy -- NEXT TO
# THIS FILE, because a copy elsewhere cannot resolve `import ../helpers.bend` and
# every mutation then reports "did not compile" -- runs the INTERPRETED lane, and
# diffs WHOLE `name=value` LINES. It never compares row NAMES.
#
# | # | the edit | rows MOVED | first movers |
# | --- | --- | --- | --- |
# | M1 | `P.Ns.at`: drop the 1-based -> 0-based shift | 11 | `bend_const_c`, `bend_const_f`, all three `bend_emit_*` pairs. THE BIGGEST MUTATION, because a one-node shift corrupts every packet and the gate caught it as soon as it existed. |
# | M2 | `src_text.go`: append then reverse (the order bug this file shipped) | 3 | `bend_emit_{tiny,fconst,cmp}_match`. Three rows and not more: only the three packet rows read a multi-src line, and each is a WHOLE-PACKET comparison. |
# | M3 | `lanes`: drop the bool lane | 4 | `bend_emit_cmp`, `bend_emit_cmp_ok`, `bend_emit_cmp_match`, `bend_lanefree_bool_not_lane`. Only `cmp` carries a `bool`, and that is a MEASUREMENT, not a fixture choice. |
# | M4 | `P.LANES_SORTED`: reorder | 12 | `bend_lane_sorted_is_literal` and all ten `bend_refuse_*` rows. The refusal MESSAGE names the lane list, so a reorder is visible in every refusal row -- which is why the refusals are text rows and not booleans. |
# | M5 | `const_arg`: every CONST is an int | 3 | `bend_const_f`, `bend_emit_{fconst,cmp}_match`. `tiny` has no float CONST, so M5 moves nothing there -- that is the localised half of the table. |
# | M6 | `param_arg`: the letter is always `g` | 0 | -- see THE FOUR ZEROS. |
# | M6b | `letter.of`: REG is an `a` | 1 | `bend_letter_reg`. One row: `letter.of` has exactly one fixture per addrspace and the ROW IS THE FIXTURE. |
# | M6c | `param_arg`: keep the letter, drop the extent | 3 | the three `bend_emit_*_match`. M6 and M6c together say the `k:param:` payload has two independent halves and both are gated. |
# | M7 | `vec_arg`: every LOAD/STORE carries a width | 3 | `bend_emit_{cmp,tiny}_match`, `bend_vec_1`. `fconst`'s loads are all width 1, so that packet cannot see it -- a MEASURED localisation. |
# | M8 | `is_buf`: accept the `r` letter | 2 | `bend_buf_l`, `bend_buf_r`. |
# | M9 | `buf_extent`: the FIRST colon field | 3 | all three `bend_extent_*`. |
# | M10 | `is_image_shape`: any 3-d shape is an image | 1 | `bend_img_2_3_5`. One row, and it is the right one: `2 3 5` and `2 3 4` are the only pair of shapes that differ on the LAST dimension alone. |
# | M11 | `idx_arg`: the BITCAST arm before the image arm | 0 | -- see THE FOUR ZEROS. |
# | M12 | `header`: `nbufs` counts every line | 6 | the three `bend_emit_*` and the three `bend_emit_*_match`. |
# | M13 | `rstrip1`: never strip | 3 | the three `bend_emit_*_match`, and only those: the three packets each have at least one src-free line. |
# | M14 | `has_local`: `True{}` | 1 | `bend_has_local`. |
# | M15 | `is_warp1`: only X matters | 1 | `bend_call_warp1`. |
# | M16 | `P.Tr.step`: drop the `raise` guard | 0 | -- see THE FOUR ZEROS. |
# | M17 | `letter_str`: LOCAL prints a letter too | 1 | `bend_letter_local`. |
# | M18 | `out_bufs`: no dedup | 0 | -- see THE FOUR ZEROS. |
# | M19 | a comment-only edit (THE CONTROL) | 0 | THE CONTROL, and it is the only 0 that is a THEOREM: a comment is not an expression, so no `name=value` line can move. |
# | M20 | `wire_dtype`: void needs no lane either | 9 | all three `bend_emit_*`, plus `bend_lanefree_void`. |
#
# ===========================================================================
# THE FOUR ZEROS, classified. Three are BLIND SPOTS and one is the control.
#
# M6 -- BLIND SPOT, and the fixture EXISTS but the gate is one level too high.
#   `param_arg`'s letter is only reachable through a PARAM, and `letter.of` /
#   `letter_str` are gated directly (`bend_letter_*`) but `param_arg` is not.
#   M6b and M17 move the letter table's rows and M6c moves `param_arg`'s OTHER
#   half, so between them the payload is gated -- but `param_arg`'s CALL of the
#   table is not, and a port that hard-coded `"g"` inside `param_arg` would pass
#   every row. FIX: one row, `srow("bend_param_arg_reg", P.param_arg(<a REG PARAM>))`.
#   A synthetic fixture is needed because no real packet has one (MEASURED: the
#   ten packets under `.agents/slop/` carry `g` PARAMs only).
#
# M11 -- BLIND spot, NOT fixable from a real packet. The mutation is the ORDER of
#   :126 and :127, and separating them needs a node whose `src[0]` is BOTH an
#   image-shaped BITCAST. `encode` refuses the image arm first in CPython too
#   (measured: `BEND v1 has no image addressing for INDEX over (2, 3, 4)`), so
#   the two spellings are distinguishable -- but only by a fixture the real
#   scheduler never emits. This is a REQUEST FOR A FIXTURE, and the fixture is
#   blocked because the synthetic-fixture route HUNG (see THE ARM FIXTURES below).
#
# M16 -- A DOWNSTREAM BLIND SPOT, not a blind spot of `P.Tr.step`. `P.Tr.step`'s guard
#   cannot move a row because the trace is EMPTY: `prog.of` is not ok (the LINE
#   SPLIT WALL below), so `P.Prog.out_bufs` is `Nil{}` and no refusal ever fires.
#   The guard IS correct -- M16 would move `bend_call_*_refused` the moment
#   `parse` works -- and it is reported here rather than hidden because a zero
#   with a cause is information.
#
# M18 -- THE SAME CAUSE as M16. `out_bufs` is empty, so a dedup and a no-dedup
#   fold agree on the empty list. That is an EQUIVALENCE over the current
#   fixtures, not a proof.
#
# ===========================================================================
# THE wall this gate does not cross, named.
#
# 1. THE LINE SPLIT (WALL 4, above). `String.split(s, P.NLCH())` does not split a
#    packet on its newlines and neither does a hand-written fold over
#    `String.to_list` with `Char.is_eq(c, P.NLCH())`, although
#    `String.join(acc, "\n")` emits real 0x0A and `Char.to_u32(P.NLCH())` is 10.
#    So `parse` answers ONE field, `BendProgram.__init__` has no lines, and these
#    rows are RED rather than absent: `bend_parse_nbufs`, `bend_prog_*_nbufs_ok`,
#    `bend_prog_*_in_bufs_ok`, `bend_prog_*_out_bufs_ok`, `bend_call_*_refused`,
#    `bend_call_ok`, `bend_call_local`, `bend_call_rc_steps`. 40 of the 322 rows
#    print False and 32 of those 40 are this wall; the other 8 are the CORRECT
#    answers of negative rows (`bend_lane_f16` and friends are False on purpose,
#    `bend_has_local` is False because `has_local = False`).
#
# 2. THE four `wire_arg` ARMS no real packet reaches: `k:buffer:`, `k:param:..:r`,
#    `k:sp:`, and `k:idx:<non-zero>`. MEASURED over ten kernels: `PARAM`s are all
#    `GLOBAL`, `SPECIAL` needs a loop, and a `BITCAST` index needs a narrow
#    buffer. Each has a direct fixture row or a letter row here; none has an
#    ENCODED packet row, and `bend_emit_*` therefore cannot see them.
#
# 3. THE ARM FIXTURES THAT HUNG. A synthetic uop list per `wire_arg` arm was built
#    and every answer came out right -- `k:param:16:r`, `KeyError: 'LOCAL'`,
#    `f:0000003f`, `k:idx:4`, `k:idx:0`, `k:vec:4`, the image refusal, the bf16
#    refusal -- but running `encode` over those lists HUNG inside `BendProgram`'s
#    :208 walk, and a gate that hangs is not a gate. The answers are recorded in
#    `.agents/slop/bend_oracle.py`'s tail as measurements and are NOT gated.
#    AND that script is now gone and was not restored. The 2026-10-05 sweep deleted it;
#    recovered from blob e853efc4b (11866 B) it is RED -- it writes its artefacts to
#    `__file__.parent`, the directory the no-`.txt` rule forbids, and it dies
#    `KeyError: 'prog'` on the 7th of 7 packets (`cmp`), having emitted 6. A script that cannot
#    finish and that would litter `gates/` with untracked `.txt` is not an instrument to
#    restore; `gates/ops_bend_exec-e2e.py` below is what replaced it.
#    A cyclic list is the likely cause and it is a finding about the PYTHON:
#    :208's `while` has no termination guard, so a packet with a cycle hangs
#    `BendProgram.__init__` in CPython too.
#
# 4. THE FFI SEAMS (WALL 3), which are steps in the trace and not expressions:
#    `executor()`, `to_mv`, `write_text`, `subprocess.run`, `read_text`, the
#    copy-back, `src.encode()` and `time.perf_counter()`. The E2E
#    (`gates/ops_bend_exec-e2e.py`) is what covers them, and it is outside this
#    file because it is a CPython program by construction.
#
# ===========================================================================
# THE END TO END, which is the reason this file exists. `gates/ops_bend_exec-e2e.py`
# runs the BEND DEVICE: it builds the executor with `./bin/bend`, launches real
# kernels, and compares against CPython's PYTHON device.
#     .venv/bin/python gates/ops_bend_exec-e2e.py
# RESTORED 2026-10-16 from `.agents/slop/bend_e2e.py`, blob e853efc4b, 2851 B, byte for byte,
# with THREE edits and NONE of them touching the comparison `repr(got) == repr(want)`: the
# invocation above (the file took `uv run python`), the artefact directory
# (`gates/artifacts/ops_bend_exec/`, where `gates/README.md` says a gate run writes and which
# `.gitignore`d), and the packet suffix (`.rows`, because a `.txt` is a HARD row for
# `checks/no-txt.py` -- `OUT` was `__file__.parent` only because `__file__` WAS `.agents/slop/`).
# MEASURED, six of seven MATCH, recorded 2026-10-02 and KEPT because a run and its rule are
# one thing:
#     add4   bend=[11.0, 22.0, 33.0, 44.0]  python=[11.0, 22.0, 33.0, 44.0]
#     sum4   bend=10.0                      python=10.0
#     addi32 bend=[2, 4, 6, 8]              python=[2, 4, 6, 8]
#     addu32 bend=[8, 9, 10, 11]             python=[8, 9, 10, 11]
#     cast   bend=[2.0, 3.0, 4.0, 5.0]      python=[2.0, 3.0, 4.0, 5.0]
#     cmp    bend=[False, False, True, True] python=[False, False, True, True]
#     dot    FAILED -- a loop kernel reaches a `clang` C compile in a layer this
#            file does not own, and the generated C does not compile. Named, not
#            hidden.
# MEASURED AGAIN 2026-10-16 FROM `gates/`: `7 match, 0 mismatch`, `dot` INCLUDED, 49.7 s.
# The rule that produces the second number and not the first: the executor is CACHED
# (`~/Library/Caches/tinygrad/bend-executor-8a618c818be2dcdf`), so the run that BUILDS it pays
# the `clang` compile and a later run reads the cache. The 2026-10-02 reading is the building
# run; the 2026-10-16 reading is a cached one. Neither is the other's rule, so neither number
# replaces the other -- and 6 of the 7 packets are captured, because `dot` emits none.
# The packets it writes are the SAME `gates/artifacts/ops_bend_exec/packet-<case>.rows` the three
# `bend_emit_*_match` rows compare against, so the string gate and the E2E read
# one artefact and cannot disagree about it.
