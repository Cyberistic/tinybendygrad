# EXECFIX — the bend executor's broadcast and max lanes

Started 2026-10-25T18:28:24Z. Owner: this unit.
Scope: `tinybendygrad/runtime/ops_python.bend`, `.agents/slop/execfix/`, optionally `gates/ops_bend_exec-e2e.py`.

## Status log

- 2026-10-25T18:28:24Z — report created (per instruction: within first five minutes).
- 2026-10-25T18:30Z — executor built: `./bin/bend tinybendygrad/runtime/ops_python.bend -o .agents/slop/execfix/executor` (10.1 s, rc=0).
- 2026-10-25T18:35Z — the three defects REPRODUCED, and the repro is narrower than the brief:
  **THE `max` DEFECT IS THE INTEGER LANE ONLY.** The float lane's `max` is right.
- 2026-10-25T18:50Z — both causes MEASURED (see §2, §3).

## 1. WHAT WAS REPRODUCED, AND WITH WHAT

`.agents/slop/execfix/probe.py` renders the packets (the repo's own `ops_bend.encode`,
through the real `BEND` device) and prints the answer. It is the instrument here.

| case | expression | bend | python |
|---|---|---|---|
| `max0` | `T(range(16)).realize().reshape(4,4).max(axis=0)` | `[0, 1, 2, 3]` | `[12, 13, 14, 15]` |
| `max0f` | the same with **float32** | `[12.0, 13.0, 14.0, 15.0]` | `[12.0, 13.0, 14.0, 15.0]` **MATCH** |
| `max1` | `T(range(16)).realize().reshape(4,4).max(axis=1)` | `[0, 4, 8, 12]` | `[3, 7, 11, 15]` |
| `bcast_mul` | `T(range(1,17)).reshape(4,1,4) * T(2..32 step 2).reshape(1,4,4)` | first 4×4 slab only, rest zeros | full 4×4×4 |
| `sum0` | `T(range(16)).reshape(4,4).sum(axis=0)` | `[24, 28, 32, 36]` | MATCH |

**⇒ THE `max` DEFECT IS THE INTEGER LANE.** `max0` and `max0f` differ ONLY in the dtype
(`T(range(16))` is int32; the float case is float32) and **THE TWO PACKETS ARE BYTE-IDENTICAL
APART FROM THE DTYPE**:

```
== max0   (int32)                == max0f  (float32)
23: MAX i32 - 21 16              23: MAX f32 - 21 16
24: MAX i32 - 23 19              24: MAX f32 - 23 19
25: MAX i32 - 24 13              25: MAX f32 - 24 13
```

**⇒ SO THE DIFFERENCE IS THE ALU LANE, NOT THE PACKET, NOT THE LOOP AND NOT THE STORE.**

## 2. CAUSE #1 — THE INTEGER LANE'S `max` IS A `min` (`tinybendygrad/uop/symbolic.bend:634`)

`tinybendygrad/uop/symbolic.bend:634`:

```bend
def i32_max(uns: Bool, +x: U32, +y: U32) -> U32:
  Bool.pick(U32, i32_lt(uns, y, x), y, x)     # <-- `y < x`, so this is MIN(x, y)
```

The float lane, `symbolic.bend:807`, has the operands the other way round and is right:

```bend
def f32_max(+x: F32, +y: F32) -> F32: Bool.pick(F32, F32.is_lt(x, y), y, x)   # max
```

**MEASURED** (`.agents/slop/execfix/alu.bend`, `./bin/bend .agents/slop/execfix/alu.bend`):

```
i32 MAX(3,7) = CInt(0:3)        <- upstream's python_alu[Ops.MAX] is `max` -> 7
i32 MAX(7,3) = CInt(0:3)        <- 7
u32 MAX(3,7) = CInt(0:3)        <- 7
i32 ADD(3,7) = CInt(0:10)       <- right
i32 CMPLT(3,7) = CBool(1)       <- right
i32_lt(3,7) = 1                 <- right
i32_lt(7,3) = 0                 <- right
i32_max(3,7) = 3                <- WRONG, min
i32_max(7,3) = 3                <- WRONG, min
cmp_lt(3,7) = 1                 <- right
```

**⇒ THE COMPARISON IS RIGHT AND THE `max` IS WRONG, SO THE FAULT IS THE ARGUMENT ORDER
OF `i32_lt` INSIDE `i32_max`, AND NOTHING ELSE.** `i32_max` answers `min(x, y)`.

**⇒ AND THAT EXPLAINS THE OBSERVED `max` ANSWER EXACTLY.** The packet's chain is

```
23: MAX i32 - 21 16     21 = buf1[range]      16 = buf1[range+4]
24: MAX i32 - 23 19     19 = buf1[range+8]
25: MAX i32 - 24 13     13 = buf1[range+12]
```

which is `min(buf1[r], buf1[r+4], buf1[r+8], buf1[r+12]) = buf1[r]` for `r = 0..3`,
i.e. **`[0, 1, 2, 3]`** — the measured answer. And `max(axis=1)`'s packet loads
`buf1[r], buf1[r+1], buf1[r+8], buf1[r+12]`, whose minimum is `buf1[r]` = `[0, 4, 8, 12]` —
also the measured answer. **THE `max` DEFECT IS ONE FUNCTION, NOT TWO.**

**THE ORACLE:** upstream's `tinygrad/uop/ops.py` spells `python_alu[Ops.MAX] = max`
(the table `PythonRenderer.code_for_op` points at), so upstream's answer is `max`
and the port's `min` is wrong.

## 3. CAUSE #2 — A RANGE'S COUNTER IS NEVER RESET WHEN THE LOOP EXITS (`tinybendygrad/runtime/ops_python.bend:1712`)

**THE PORT'S OWN HEADER ALREADY NAMES THE SHAPE** (`ops_python.bend:20-24`):

> `reduce_sum_1d, reduce_sum_2step, reduce_max, reduce_exp2, matmul, permute` --
> NESTED RANGE loops. The first eight outputs of `permute` are right and the remaining
> 120 are untouched, so the inner loop is right and the OUTER one's back edge is not.

**THE UPSTREAM SIDE** (`tinygrad/runtime/ops_python.py:126-134`):

```python
elif u.op is Ops.RANGE:
  if u not in values: values[u] = [0] * warp_size
  else:
    for j in range(len(values[u])): values[u][j] += 1
  if values[u][0] == src_values[0][0]:
    del values[u]                       # <-- THE COUNTER IS DELETED
    i = self.loop_ends[u] + 1
    continue
```

**THE PORT SIDE** (`tinybendygrad/runtime/ops_python.bend:1701-1715`):

```bend
def Prog.rng.nxt(+p: Prog, +u: Uop, +seen: Bool) -> U32:
  Bool.pick(U32, seen, U32.add(Prog.cur(p, u), 1), Prog.cur(p, u))

def Prog.rng.put(+p: Prog, +u: Uop, +seen: Bool, +nxt: U32) -> Prog:
  Bool.pick(Prog, seen, Prog.put(p, u, elem_of(nxt, Uop.dt(u))), Prog.next(Prog.flag.put(p, u)))

def Prog.rng.over(+p: Prog, +u: Uop, +over: Bool, +seen: Bool, +nxt: U32) -> Prog:
  match over:
    case True{}: Prog.at(p, U32.add(Prog.loop(p, Prog.pc(p)), 1))    # <-- NOTHING IS CLEARED
    case False{}: Prog.rng.put(p, u, seen, nxt)
```

**THE PORT MODELS "never visited" WITH A SECOND SLOT** (the counter's slot + 1, the
"visited flag", `ops_python.bend:796-807`), because the arena is zeroed and so
"never visited" and "visited with value 0" are the same cell. **BUT THE PORT NEVER
CLEARS THAT FLAG WHEN THE LOOP EXITS**, AND UPSTREAM'S `del values[u]` DOES EXACTLY
THAT: it removes the counter, so the NEXT visit is a FIRST visit (`values[u] = [0]`)
and the body reads `0` again.

**⇒ THE CONSEQUENCE IS PRECISE AND IT IS THE OBSERVED SYMPTOM:** after the inner RANGE
of a nested pair has run to its trip count, its flag is still set and its counter still
holds the last value. So on the outer loop's SECOND iteration the inner RANGE is
"already visited", its counter is incremented once more (`nxt = trip + 1`),
`nxt == trip` is FALSE, **and the inner body never runs** — so the STORE never runs
for the outer iterations 2..N and the output keeps only the first outer slab.

**MEASURED AGAINST THE PACKET.** `bcast_mul`'s packet (`.agents/slop/execfix/packet-bcast_mul.rows`):

```
18: RANGE i32 - 17        # OUTER, trip 4
19: SHL i32 - 18 13       #   outer*4   -> A[4*outer .. +3]
20: SHRINK i32 - 4 19 17
21: LOAD i32 k:vec:4 20
22: AFTER i32 - 17 18
27: RANGE i32 - 22        # INNER, trip 4  (22 = AFTER -> 4)
28: SHL i32 - 27 13       #   inner*4   -> B[4*inner .. +3]
29: SHRINK i32 - 5 28 17
30: LOAD i32 k:vec:4 29
35-38: MUL                # 4 lanes
39: STACK i32 - 35 36 37 38
40: MULACC i32 - 18 11 28 #   outer*16 + inner*4   -> the OUTPUT offset
41: SHRINK i32 - 2 40 17
42: STORE void k:vec:4 41 39
44: END void - 43 27      # the INNER loop's back edge
45: END void - 44 18      # the OUTER loop's back edge
```

`outer*16 + inner*4` + a 4-lane store IS the flat index of `out[i][j][k]` with
`i = outer`, `j = inner`, `k = lane` — so the packet is RIGHT and the port's failure
is in the loop, not in the addressing. **AND THE OBSERVED ANSWER IS EXACTLY WHAT THE
TRACE PREDICTS:** outer=0 writes `out[0][0][0..3]`, `out[0][1][0..3]`, `out[0][2][0..3]`,
`out[0][3][0..3]` (the first 4×4 slab, all four `j`), and outer=1,2,3 write NOTHING
because the inner RANGE exits before its body — which is the measured
`[[[2, 8, 18, 32], [10, 24, 42, 64], [18, 40, 66, 96], [26, 56, 90, 128]], [[0,0,0,0],...],
[[0,0,0,0],...], [[0,0,0,0],...]]`.

**THE SAME TRACE EXPLAINS `dot`:** `dot`'s packet has the same nested shape
(`19: RANGE` outer, `28: RANGE` inner, `47: END` -> 28, `48: END` -> 19) and its store
offset is `MULACC i32 - 19 16 28` = `outer*4 + inner`, so outer=0 writes the first ROW
`[180, 200, 220, 240]` and outer=1,2,3 write nothing — **the measured
`[[180.0, 200.0, 220.0, 240.0], [0,0,0,0], [0,0,0,0], [0,0,0,0]]`.**

**⇒ SO THE BROADCAST DEFECT AND THE `dot` DEFECT ARE ONE DEFECT, AND IT IS NOT THE
BROADCAST: IT IS THE NESTED RANGE.** A SINGLE (non-nested) RANGE is unaffected,
WHICH IS WHY `sum0`, `sum4`, `max0` AND EVERY OTHER SINGLE-LOOP CASE MATCH.

---

## 7. WHAT IS COMMITTED, AND HOW TO REBUILD WHAT IS NOT

**THE COMPILED EXECUTORS ARE NOT COMMITTED.** `executor` AND `executor-old` ARE 550 KB BUILD
OUTPUTS, AND A BUILD OUTPUT IN GIT IS A SECOND COPY OF SOMETHING THAT A GENERATOR MAKES. **⇒ THE
OLD EXECUTOR IS REBUILT FROM `ops_python.old.bend`, WHICH IS THE PRE-FIX SOURCE AND IS COMMITTED** --
IT IS `git show HEAD:tinybendygrad/runtime/ops_python.bend` AT THE COMMIT BEFORE THE FIX, **SO THE
WITNESS IS ONE FILE INSTEAD OF A 191-FILE COPY OF THE PORT.**

    ./bin/bend tinybendygrad/runtime/ops_python.bend  -o /tmp/exec-new
    ./bin/bend .agents/slop/execfix/ops_python.old.bend -o /tmp/exec-old
    .venv/bin/python .agents/slop/execfix/census.py /tmp/exec-old /tmp/census-old.rows
    .venv/bin/python .agents/slop/execfix/census.py /tmp/exec-new /tmp/census-new.rows
    diff /tmp/census-old.rows /tmp/census-new.rows

**⇒ AND THE THREE ROWS THAT MOVE ARE `f32.argmax.0.b0`, `i32.maxpair.0.b0` AND
`u32.maxpair.0.b0` -- `moved-names.rows` AND `census-diff.rows` ARE THE RECORD, AND THEY ARE
SMALL.**

**⇒ AND THE PIN IS A NAME SET, SO A PINNED ROW's VALUE IS NEVER CHECKED.**
`gates/ops_python_exec-pins.rows` READS AS `{l.split()[0] ...}` -- **A SET OF NAMES, WITH NO
VALUES** -- AND `gates/ops_python_exec-gate.py:326` COMPUTES
`unpinned = (set(dpy) | set(dbd)) - pinned` **⇒ SO A PINNED ROW IS EXEMPT FROM THE COMPARISON
ENTIRELY.** MEASURED 2026-10-25: ALL THREE MOVED ROWS ARE **STILL** DIVERGENCES AFTER THE FIX --
CPython's OWN ANSWERS ARE `f32.argmax.0.b0=03000000`, `i32.maxpair.0.b0=10000000`,
`u32.maxpair.0.b0=10000000`, AGAINST THE FIXED PORT's `40000000`, `00080000`, `00080000` -- **⇒ SO
THE PINS STAY AND THE GATE IS HONEST, AND THE FINDING IS THE GAP: A FIX CAN MOVE A PINNED ROW's
VALUE WITHOUT ANYTHING GOING RED, BECAUSE THE PIN EXEMPTS THE ROW RATHER THAN PINNING IT.**
