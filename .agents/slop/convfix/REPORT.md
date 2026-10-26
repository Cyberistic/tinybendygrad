# CONVFIX — the Bend executor runs a convolution now

Unit: convfix. Started 2026-10-25T19:44Z, finished 2026-10-26.
Scope: `.agents/slop/convfix/`, `tinybendygrad/runtime/ops_python.bend`.

## THE ANSWER, IN ONE PARAGRAPH

**NO, IT DID NOT, AND IT DOES.** Measured on 2026-10-25, the port's executor
**REFUSED** the port's own convolution — `x(1,3,32,32) conv2d w(8,3,3,3)
padding=1` → `(1,8,32,32)`, the shape `tinybendygrad/nn/layers.bend`'s five
`conv_*` rows use — while **upstream's own `PythonProgram.__call__` ran the SAME
PACKET, the SAME BUFFERS and the SAME GRID without complaint**. The refusal was
the port's own, and it was wrong: **the port's poison check was not behind the
gate that upstream's is**. Behind that refusal sat a **second, independent
defect** — the scratch `BUFFER`'s region was placed at the wrong offset in the
flat byte list and counted in ELEMENTS where the base arithmetic counts BYTES —
which made every packet with a local scratch read and write the wrong place.
**BOTH ARE FIXED.** After the fix the port's conv agrees with CPython's PYTHON
device on **all 8192 values**, the same packet through upstream's own
interpreter gives **byte-identical buffers**, the 153-fixture census goes from
**53 divergences to 30** (23 fixed, **0 new**), and `gates/ops_bend_exec-e2e.py`
still reads **7 match, 0 mismatch-or-refused**.

## 0. THE LOG

- 2026-10-25T19:44Z — report created (per the brief: within the first five minutes).
- 2026-10-25T19:55Z — read the port's header, `ops_bend.py`'s header, upstream's
  `tinygrad/runtime/ops_python.py`, `gates/ops_bend_exec-e2e.py`, the prior art
  `.agents/slop/execfix/REPORT.md`, `gates/ops_python_exec-gen.py`,
  `gates/ops_python_exec-gate.py`.
- 2026-10-25T20:20Z — **THE MEASUREMENT**: three small convs MATCH; the port's
  own conv shape is REFUSED while upstream's interpreter runs it.
- 2026-10-25T21:10Z — **DEFECT 1**, narrowed by a diagnostic build of the port:
  the refusal is at `pc=333 off=3100 buf=1`.
- 2026-10-25T21:30Z — **DEFECT 1 CONFIRMED**: upstream's own `_load`/`_store`,
  monkeypatched at runtime, show upstream never touches offset 3100.
- 2026-10-26T00:00Z — **DEFECT 1 FIXED**; the port now RUNS the conv and gets
  the wrong answer.
- 2026-10-26T01:20Z — **DEFECT 2 FOUND**: the scratch `BUFFER`'s byte region is
  at the wrong offset and is counted in elements.
- 2026-10-26T01:45Z — **DEFECT 2 FIXED**; the census goes 53 → 30.
- 2026-10-26T02:10Z — the port's header updated; the final executors rebuilt.
- 2026-10-26T02:30Z — **the final verification**: census 53 → 30, e2e 7/7,
  the conv probe 4/4, the new fixture refuses on the pre-fix executor and
  matches upstream on the post-fix one.

## 1. THE MEASUREMENT, BEFORE ANY FIX

`gates/ops_bend_exec-e2e.py` has **no conv case**. `gates/ops_python_exec-fixtures.rows`
holds 153 records and their name prefixes are `f32` (40), `u32` (31), `i32` (31),
`bool` (26), `alu` (25): **the conv lane was unmeasured.**

`.agents/slop/convfix/probe.py` is the instrument. It runs a conv on the **BEND**
device (the port's executor, through `ops_bend.py`'s `BendDevice`) and on
CPython's **PYTHON** device, **and it builds the oracle's inputs ITSELF** — the
e2e gate's own header records that an oracle which re-uses the subject's buffers
compares the wrong answer with itself. It also captures the BEND launch (the
packet text, the buffers, the grid) and hands **the same packet, the same
buffers and the same grid** to upstream's own interpreter.

MEASURED (`.agents/slop/convfix/probe-run2.out`):

| case | shape | bend | python | verdict |
|---|---|---|---|---|
| `conv1x1x3x3_k1x1x3x3_p0` | (1,1,3,3)×(1,1,3,3) p0 | 27.75 | 27.75 | **MATCH** |
| `conv1x1x4x4_k1x1x3x3_p0` | (1,1,4,4)×(1,1,3,3) p0 | 4 values, equal | equal | **MATCH** |
| `conv1x1x4x4_k1x1x3x3_p1` | (1,1,4,4)×(1,1,3,3) p1 | 16 values, equal | equal | **MATCH** |
| `conv1x3x32x32_k8x3x3x3_p1` | **the port's own conv shape** | **REFUSED** | 8192 values | **REFUSED** |

### THE A/B ON THE REFUSED PACKET — THE DECISIVE PART

```
== conv1x3x32x32_k8x3x3x3_p1
#   launch 0: gsize=(1, 1, 1) lsize=(1, 1, 1) nbuf=3
#     port:   rc=1 stderr=executor: refused the packet -- a line it does not port,
#             or a load or store past the end of its buffer, where ops_python raises IndexError
#     oracle: ran, 3 buffers
```

**⇒ UPSTREAM RUNS IT. THE PORT REFUSES IT. THE PORT IS WRONG AND UPSTREAM IS
RIGHT** (rule 1 of the brief).

**AND THE `local_size` IS CARRIED, NOT GUESSED.** `BendRenderer.has_local = False`
(`ops_bend.py:252`), so the scheduler never splits an axis to LOCAL on the BEND
device, while the PYTHON renderer has no such rule: **the same expression
renders 581 uops at `local_size (16,8,1)` on PYTHON and 580 uops at
`local_size (1,1,1)` on BEND.** The first draft of this unit's oracle guessed
`local_size` and had to be thrown away; an oracle run with a guessed local size
is not the launch it claims to be.

## 2. DEFECT 1 — THE POISON CHECK IS NOT BEHIND THE GATE

### THE PORT SIDE — `tinybendygrad/runtime/ops_python.bend:1942-1951` (before the fix)

```bend
def Prog.oob(+p: Prog, +u: Uop, +j: U32, +n: Nat) -> Bool:
  match n:
    case 0n: False{}
    case 1n+q: Bool.or(U32.is_ge(Prog.store.i(p, u, j), Buf.e(Prog.buf(p, u))), Prog.oob(p, u, j, q))

def Prog.live(+p: Prog, +u: Uop) -> Prog:
  Prog.live.at(p, Prog.oob(p, u, 0, U32.to_nat(Uop.run(u))))
```

`Prog.live` is called by `Prog.ld1` (:1990) and by `Prog.store` (:2027) and it
checks **every** access, **whether or not the access happens**.

### THE UPSTREAM SIDE — `tinygrad/runtime/ops_python.py:25-27` and `:88-94`

```python
def load(inp, j, dtype: DType):
  if len(inp) >= 3: return [_load(m, x+j*_step(m, dtype) if x is not None else None, dtype) if gate else alt for (m,x),alt,gate in zip(*inp[:3])]
  return [_load(m, x+j*_step(m, dtype) if x is not None else None, dtype) for m,x in inp[0]]
...
        if u.op is Ops.STORE:
          store_gate = exec_masks[-1]
          for j,val in enumerate(src_values[1] if u.max_numel() > 1 else [src_values[1]]):
            for (m,o),v,g in zip(src_values[0], val, store_gate):
              if g: _store(m, o+j*_step(m, src_dtypes[1]), v, src_dtypes[1])
```

**⇒ UPSTREAM ONLY TOUCHES THE MEMORY WHERE THE GATE IS OPEN.** A gated-off LOAD
takes `alt` (`:26`); a masked-off STORE writes nothing (`:93`). `_load`'s
IndexError (`:19`) and `_store`'s (`:30`) are therefore only reachable through an
access that HAPPENS. **The port's check stands in for that IndexError, so IT
has to be behind the same gate.**

### WHERE IT BITES — THE PACKET, LINE BY LINE

`.agents/slop/convfix/packets/conv1x3x32x32_k8x3x3x3_p1/PACKET-0.in` is the
BEND launch: 580 uops, 3 buffers, `gsize (1,1,1)`, `lsize (1,1,1)`.

```
2: PARAM f32 k:param:32768:g     # the OUTPUT, 8192 f32
4: PARAM f32 k:param:12288:g     # the INPUT,  3072 f32
6: PARAM f32 k:param:864:g       # the WEIGHT,  216 f32
8: BUFFER f32 k:buffer:64        # a LOCAL scratch, 16 f32
118: RANGE i32 - 42              # trip 2
121: RANGE i32 - 119             # trip 33
125: RANGE i32 - 122             # trip 8
168: RANGE i32 - 126             # trip 3
```

The offset of the input reads is `168*1024 + 121*32 + 125*4` (`169: MULACC i32 -
168 28 151`, `151: MULACC i32 - 121 59 144`, `144: SHL i32 - 125 42`) plus a
constant per tap:

```
172: LOAD f32 - 171 11 145   off = base - 1    gate = (0 < counter125)
175: LOAD f32 - 174 11 149   off = base - 28   gate = ((counter125 < 7) & (0 < counter121))
178: LOAD f32 - 177 11 147   off = base - 33   gate = ((0 < counter125) & (0 < counter121))
181: LOAD f32 - 180 11 149   off = base + 31   gate = ((0 < counter125) & (counter121 < 31))
184: LOAD f32 - 183 11 147   off = base + 36   gate = ((counter125 < 7) & (counter121 < 31))
187: LOAD f32 - 186 11 145   off = base + 4    gate = (counter125 < 7)
331: LOAD f32 - 330 11 147   off = base - 32   gate = (0 < counter121)
334: LOAD f32 - 333 11 149   off = base + 32   gate = (counter121 < 31)
336: LOAD f32 - 335 11 145   off = base        gate = -
```

`base` reaches `2*1024 + 32*32 + 7*4 = 3100`, so the taps at `base - 33`,
`base - 28` and `base - 1` are **NEGATIVE** at the borders — and the port's
arithmetic is UNSIGNED, so `base - 33` wraps to 4294967263.

**⇒ THE PORT CHECKS THE ACCESSES THAT THE GATE EXCLUDES.** The diagnostic build
(the tree's file, patched to report the offending pc/offset/buffer, built, run,
then **restored** — `shasum -a 256` matched before and after) names the one that
fired first:

```
executor: refused the packet at pc=333 off=3100 buf=1
```

`pc=333` is 0-based, so the wire's uop **334** — `334: LOAD f32 - 333 11 149`,
the tap at `base + 32`, whose gate is **`(counter121 < 31)`**. At the iteration
that produced `off = 3100 = 2*1024 + 31*32 + 7*4 + 32`, `counter121` is 31, so
**the gate is FALSE** and upstream reads `alt` instead of the buffer.

### THE PROOF THAT UPSTREAM NEVER MAKES THAT ACCESS

`.agents/slop/convfix/accesses.py` monkeypatches upstream's OWN `_load` and
`_store` **at runtime** (`tinygrad/` is the oracle and is not edited) and
re-runs the launch:

```
# upstream ran the packet: 154968 memory accesses
#   load: buffer len=16,   32768 accesses, index range [0, 15],   out-of-range=0
#   load: buffer len=216,  55296 accesses, index range [0, 215],  out-of-range=0
#   load: buffer len=3072, 25944 accesses, index range [0, 3071], out-of-range=0
#   store: buffer len=16,  32768 accesses, index range [0, 15],   out-of-range=0
#   store: buffer len=8192,  8192 accesses, index range [0, 8191], out-of-range=0
# THE PORT'S REFUSAL WAS at offset 3100 into the 3072-element buffer:
#   upstream accessed it 0 time(s)
```

**⇒ UPSTREAM MAKES 154,968 MEMORY ACCESSES, NONE OF THEM OUT OF RANGE, AND IT
NEVER TOUCHES THE OFFSET THE PORT REFUSED. THE PORT'S REFUSAL IS THE PORT'S
OWN, AND IT IS WRONG.**

### THE FIX

```bend
def Prog.ld.open(+p: Prog, +u: Uop) -> Bool: Elem.is_true(Prog.src(p, u, 2n))

def Prog.ld.happens(+p: Prog, +u: Uop) -> Bool:
  Bool.not(Bool.and(Prog.ld.three(u), Bool.not(Prog.ld.open(p, u))))

def Prog.live(+p: Prog, +u: Uop, +happens: Bool) -> Prog:
  Prog.live.at(p, Bool.and(happens, Prog.oob(p, u, 0, U32.to_nat(Uop.run(u)))))
```

with `Prog.ld1` passing `Prog.ld.happens(p, u)` and `Prog.store` passing
`Prog.open(p)` (the exec mask, which is upstream's `store_gate`).

## 3. DEFECT 2 — THE SCRATCH BUFFER'S BYTE REGION IS IN THE WRONG PLACE

**⇒ THIS ONE WAS ALREADY IN THE TREE'S OWN CENSUS, AND THE PIN FILE MISDIAGNOSED
IT.** Ten of the 153 fixtures carry a scratch `BUFFER` op, and **23 of the 53
divergences from upstream belong to exactly those ten fixtures.**

### THE PORT SIDE — `tinybendygrad/runtime/ops_python.bend:1035-1046` (before the fix)

```bend
def Prog.zeros(+fs: List<&2, Buf>, acc: List<&2, U32>) -> List<&2, U32>:
  match fs:
    case Nil{}: acc
    case f <> t: Prog.zeros(t, Prog.pad(U32.to_nat(Buf.e(f)), acc))     # <-- ELEMENTS

def Prog.bytes(+b: Build, fs: List<&2, Buf>) -> List<&2, U32>:
  Prog.zeros(List.drop(&2, Buf, fs, U32.to_nat(Build.nb(b))), List.reverse(&2, U32, Build.bp(b)))
```

### THE UPSTREAM SIDE — `tinygrad/runtime/ops_python.py:98-108`

```python
        elif u.op in {Ops.PARAM, Ops.BUFFER}:
          ...
          if u.addrspace == AddrSpace.REG:
            values[u] = [memoryview(bytearray(u.max_numel()*u.dtype.itemsize)).cast(storage_fmt) for _ in range(warp_size)]
          else:
            size = u.max_numel() * u.dtype.itemsize
            buf = memoryview(bytearray(size)) if u.op is not Ops.PARAM else to_mv(pargs.pop(0), size)
```

**⇒ UPSTREAM'S SCRATCH IS A `bytearray` OF `max_numel()*itemsize` BYTES — so it
is `w*e` BYTES long, and it is a SEPARATE object from the packet's buffers, not
a region inside them.**

### THE TWO HALVES OF THE MISCOUNT

1. **THE COUNT.** `Buf.e` is the ELEMENT count; the byte count is `w*e`. The
   bases are computed in bytes (`Prog.bases.next` = `at + Buf.w(f)*Buf.e(f)`,
   `ops_python.bend:962`) and the padding was computed in elements.
2. **THE ORDER.** `Prog.bases` gives the scratch the base that FOLLOWS the
   packet's buffers, so the flat byte list has to be **the packet's bytes
   FOLLOWED BY** the scratch's region. The old code **prepended** the zeros, so
   the packet's own bytes sat at offset `len(zeros)` while their base is 0.

**⇒ THE SHIFT IS `e` BYTES**, and it is visible in the tree's own census:

| fixture | scratch | `w` | `e` | upstream | port (before) |
|---|---|---|---|---|---|
| `bool.maxpair.0.b1` | `k:buffer:1` | 1 | 1 | `0100010001000100` | `0001000100010001` |
| `i32.maxpair.0.b1` | `k:buffer:4` | 4 | 1 | `0100000002000000…` | `0001000000020000…` |
| the port's conv packet | `k:buffer:64` | 4 | 16 | — | shifted **16 bytes = 4 floats** |

**⇒ AND THE PORT'S OWN CONV PACKET IS THE 16-BYTE ONE.** Measured on the
post-defect-1 port's `PACKET.out` against upstream's buffers on the SAME packet:
the port's b1 (the input) read `[0,0,0,0, -4.5, -0.5, …]` where upstream reads
`[-4.5, -0.5, 3.5, …]` — **exactly four floats of shift** — and the port's b2
(the weight) read `[2.5, -4.5, -0.5, 3.5, …]` where upstream reads
`[-0.75, 0.25, 1.25, …]`; `2.5` is `xv[3068]`, the input's element 3068, which
is what b2's shifted window shows.

**⇒ AND THE PIN FILE'S DIAGNOSIS OF THE LOCAL-REDUCTION FAMILY IS WRONG.**
`gates/ops_python_exec-pins.rows` says:

> the loop-carried LOCAL reduction family: `Prog.loop` walks `loop_ends` and a
> nested END jumps to the inner head (ops_python.bend's own header, WHAT DOES
> NOT). The port's `f32.localsum.0.b0` is 717.0 where CPython's is 10.0.

**⇒ `f32.localsum.0.b0` was 33980.0 (0x000084fc) where CPython's is 10.0
(0x00002041) — and after this fix the port answers 10.0.** The nested-END
diagnosis was a story: the nested RANGE's counter reset was fixed by an earlier
unit (commit 38c6465b5), and what was left was **a byte offset**.

### THE FIX

```bend
def Prog.zeros(+fs: List<&2, Buf>, acc: List<&2, U32]) -> List<&2, U32>:
  match fs:
    case Nil{}: acc
    case f <> t: Prog.zeros(t, Prog.pad(U32.to_nat(U32.mul(Buf.w(f), Buf.e(f))), acc))

def Prog.bytes(+b: Build, fs: List<&2, Buf>) -> List<&2, U32>:
  List.reverse(&2, U32, Prog.zeros(List.drop(&2, Buf, fs, U32.to_nat(Build.nb(b))), Build.bp(b)))
```

**`Build.bp` HOLDS THE PACKET'S BYTES REVERSED**, so `zeros ++ bp` reversed once
is `wire_order ++ zeros`: the packet's bytes in wire order, then the scratch's
region, which is where `Prog.bases` says it is.

**⇒ AND THE FIRST DRAFT OF THIS FIX WAS WRONG, AND THE CENSUS CAUGHT IT.** The
first draft reversed `Build.bp` and then reversed the whole list, which
**reversed the packet's bytes a second time**: `census-diff.rows` shows **every
row in the fixture file changing** (43 lines of diff, e.g.
`f32.add.0.b1=0000803f0000004000004040…` → `f32.add.0.b1=4100000040e00000…`).
**⇒ A FIX THAT MOVES 364 ROWS IS NOT A FIX, AND THE CENSUS IS THE INSTRUMENT
THAT SAYS SO.** The corrected draft moves 23 rows and all 23 AGREE with
upstream.

## 4. THE FIX, IN ONE PLACE

`tinybendygrad/runtime/ops_python.bend`, 90 insertions and 31 deletions
(`git diff --stat`). The three code changes are the two above plus
`Prog.ld.lane` now reading the gate through `Prog.ld.open` (one name for one
value). The rest is the header and the comments, and the header is the file's
authoritative spec, so it was rewritten to the state measured today: the conv
lane PASSES, the nested-RANGE and LOCAL-reduction and maxpair families PASS, and
**ONE family still fails — the VECTOR-STORE LANE.**

The whole diff is `git diff -- tinybendygrad/runtime/ops_python.bend` against
blob `53c0cd51bb6dea87c3275eb61a1e4c95f198033a`.

## 5. THE REGRESSION CHECK

### 5.1 THE 153-FIXTURE CENSUS — `.agents/slop/execfix/census.py`

The tree's own fixture file, read in place, one executor process at a time.

| | rows | divergences from upstream |
|---|---|---|
| before | 364 | **53** |
| after | 365 | **30** |

**23 FIXED, 0 NEW.** Every one of the 23 moved rows **agrees with upstream
after the change** (`every moved row now AGREES with upstream: True`):

```
bool.maxpair.0.b1  bool.maxpair.0.b2  f32.argmax.0.b0  f32.argmax.0.b1
f32.cumsum.0       f32.cumsum.0.b0   f32.cumsum.0.b1  f32.localmax.0.b0
f32.localmax.0.b1  f32.localprod.0.b1 f32.localsum.0.b0 f32.localsum.0.b1
f32.localsumsq.0.b0 f32.localsumsq.0.b1 f32.maxpair.0.b0 f32.maxpair.0.b1
f32.maxpair.0.b2   i32.maxpair.0.b0  i32.maxpair.0.b1 i32.maxpair.0.b2
u32.maxpair.0.b0   u32.maxpair.0.b1  u32.maxpair.0.b2
```

**⇒ ALL 23 MOVED ROWS ARE PINNED, AND 0 UNPINNED ROW MOVED.** So the gate's
verdict is unchanged — and that is exactly the trap the brief names: **a pinned
row's VALUE is never compared, so a fix can move one without anything going
red.** The rows are compared here, against upstream's own answers.

**⇒ AND 23 PINS ARE NOW STALE.** `gates/ops_python_exec-pins.rows` is **not
mine and I did not edit it**, but those 23 names now describe rows that AGREE
with upstream, so the file over-declares divergences. **THE ORCHESTRATOR SHOULD
RE-DERIVE IT**: the generator's own py lane is the oracle
(`.venv/bin/python gates/ops_python_exec-gen.py`, 2.4 s, 366 rows) and the
census's `bd` lane is the port.

The 30 that remain are **all pinned** (`py-done` is the oracle's completion
marker, not a row): the VECTOR-STORE LANE family
(`f32.sqrt.0.b0`, `f32.exp2.0.b0`, `f32.log2.0.b0`, `f32.recip.0.b0`,
`f32.shl.0.b0`, `f32.shr.0.b0`, `f32.cmod.0.b0`, `f32.bitcast.0.b0`, `f32.ne.0.b0`
and the `i32.`/`u32.`/`bool.`/`alu.CMPNE.f` twins).

### 5.2 `gates/ops_bend_exec-e2e.py` — the seven cases

```
== add4: MATCH   == sum4: MATCH   == addi32: MATCH   == addu32: MATCH
== cast: MATCH   == cmp: MATCH    == dot: MATCH
# 7 match, 0 mismatch-or-refused
```

**⇒ THE EXECUTOR STILL MATCHES ON EVERYTHING IT MATCHED BEFORE.**

### 5.3 THE CONV PROBE — the headline measurement

`.agents/slop/convfix/probe-final.out`:

```
== conv1x3x32x32_k8x3x3x3_p1
#   python: n=8192 head=[-19.5, 6.625, 9.375, -18.125, 14.875, 17.625, -9.875, 23.125]
#           tail=[-14.125, 18.375, 20.625, 0.875, 5.875, -11.125, 4.875, 3.5]
#   bend:   n=8192 head=[-19.5, 6.625, 9.375, -18.125, 14.875, 17.625, -9.875, 23.125]
#           tail=[-14.125, 18.375, 20.625, 0.875, 5.875, -11.125, 4.875, 3.5]
#     port:   rc=0
#     oracle: ran, 3 buffers
#     bytes:  b0: SAME b1: SAME b2: SAME
#   VERDICT: MATCH
# 4 match, 0 mismatch-or-refused
```

**⇒ THE CONV MATCHES ON ALL 8192 VALUES, AND THE SAME PACKET GIVES BYTE-IDENTICAL
BUFFERS THROUGH UPSTREAM'S OWN INTERPRETER.**

## 6. THE NEW FIXTURE — AND THE POPULATION FILE IS NOT MINE

**`.agents/slop/convfix/fixture-conv.rows`** — one record, in the tree's own
`PACKET.in` spelling, 7,585 bytes:

```
@ f32.conv2d.0 1 1 1
bendexec1 140 3
1: CONST weakint c:256
2: PARAM f32 k:param:1024:g 1
...
8: BUFFER f32 k:buffer:4 7
...
140: SINK void - 139
1024 0000…
768 0000…
432 0000…
```

**THE SHAPE IS CHOSEN, NOT TYPED.** `.agents/slop/convfix/scan.py` renders eight
conv shapes and reports which kernel carries a LOCAL scratch `BUFFER` — and the
scratch is where the byte-shift defect lived:

```
(1,1,3,3)x(1,1,3,3) p0:  56 uops, 0 scratch BUFFER []
(1,1,4,4)x(1,1,3,3) p1: 170 uops, 0 scratch BUFFER []
(1,2,5,5)x(2,2,3,3) p1: 619 uops, 1 scratch BUFFER
(1,3,6,6)x(4,3,3,3) p1: 765 uops, 1 scratch BUFFER
(1,3,8,8)x(4,3,3,3) p1: 140 uops, 1 scratch BUFFER   <-- the smallest
(1,3,16,16)x(8,3,3,3) p1: 215 uops, 1 scratch BUFFER
(1,3,32,32)x(8,3,3,3) p1: 580 uops, 1 scratch BUFFER  <-- the port's own
```

**⇒ THE TWO CONVS WITHOUT A SCRATCH MATCHED BEFORE THE FIX AND PIN NOTHING.**
`(1,3,8,8)×(4,3,3,3)` padding=1 is the smallest conv whose kernel has one:
**140 uops and 2,224 bytes of buffers**, against the port's own 580 uops and
45,920 bytes.

**⇒ THE FIXTURE MEASURES SOMETHING** (`.agents/slop/convfix/verify_fixture.py`):

```
BEFORE: rc=1 executor: refused the packet -- a line it does not port, or a load
        or store past the end of its buffer, where …
AFTER:  rc=0  vs upstream: b0:SAME b1:SAME b2:SAME
```

**⇒ WIRING IT INTAKES TWO EDITS, BOTH IN ANOTHER INSTRUMENT'S FILES, AND I MADE
NEITHER:**
1. a seed in `gates/ops_python_exec-gen.py`'s `SEEDS` — the generator is the
   only writer of the fixture file, and the gate's `population_hold` compares
   the file's NAMES against the generator's re-harvest, so a record in the file
   that the generator does not produce is a **RED** run;
2. the record itself in `gates/ops_python_exec-fixtures.rows`.

**`gates/ops_python_exec-fixtures.rows`, `gates/ops_python_exec-pins.rows`,
`gates/ops_python_exec-gate.py` and `gates/ops_python_exec-gen.py` WERE NOT
EDITED BY THIS UNIT.** The record is here, ready to append.

## 7. WHAT I DID NOT CLOSE, NAMED

1. **THE VECTOR-STORE LANE.** 29 rows still disagree with upstream, and every
   one is pinned. MEASURED on `f32.sqrt.0`: CPython's output b0 is
   `[1.0, 1.4142135, 1.7320508, 2.0, <b0's own input unchanged>]` and the port
   answers `[0,0,0,0, <unchanged>]` — **the port writes the lanes it should
   have computed**. The same shape on sqrt, log2, exp2, recip, shl, shr, cmod,
   ne, CMPNE and bitcast. **I DID NOT FIX IT AND I DID NOT DIAGNOSE IT**: it is
   a different family from the two above, it was already pinned before this
   unit, and the brief's scope is the conv.
2. **23 PINS ARE NOW STALE.** `gates/ops_python_exec-pins.rows` names 23 rows
   that now AGREE with upstream. **THE FILE IS NOT MINE AND I DID NOT EDIT
   IT.** The orchestrator should re-derive it.
3. **THE EXECUTOR IS SLOW.** MEASURED, one process, `time`:
   the conv fixture (140 uops, 2,224 bytes) takes **16.6 s**; **the port's own
   conv shape (580 uops, 45,920 bytes) takes 9 min 18 s** (373 s user, 39 s
   system). **⇒ ON THE BEND DEVICE THE PORT'S OWN CONV IS NINE MINUTES OF
   INTERPRETER.** For the "run ImageNet using Bend" chain this is the next
   wall, and it is a performance wall, not a correctness one. `Prog.src` reads
   a list by index and `Prog.loop` scans the whole uop list, so the walk is
   O(uops) per step.
4. **THE HEADER'S OTHER BLOCKS WERE NOT RE-MEASURED.** The header's "MEASURED
   FACTS" block (`:78-96`) and "THE FOUR WALLS" (`:99-141`) are about the
   RENDER's shape — that `Ops.REDUCE` is never emitted, that `FDIV`/`THREEFRY`
   are not in `python_alu`, that there are no `DEFINE_*` ops, that
   `local_size` is never (1,1,1) for the PYTHON renderer — and **none of those
   four is touched by this change**. **⇒ THEY ARE LEFT AS THEY WERE, NOT
   RE-MEASURED.** The block this unit DID rewrite is the "STATE OF THIS FILE"
   header (`:5-35`), which is where the e2e and census readings live.
5. **`Prog.src` DOES NOT FILTER VOID SRCS, AND A VOID AFTER IS NOT SKIPPED.**
   Upstream's `src_values` is
   `[values[v] for v in u.src_without_body if v.dtype is not dtypes.void]`
   (`ops_python.py:66`) — **the void srcs are FILTERED OUT** — and upstream
   SKIPS a void AFTER outright (`ops_python.py:83-84`). The port's `Prog.src`
   (`ops_python.bend:1627`) reads the k-th src of the packet's own list with no
   filter, and `Prog.dispatch`'s AFTER arm computes a void AFTER from its
   src0. The conv packet has two such uops (`525: AFTER void - [9, …]` and
   `576: AFTER void - [9, …]`, where uop 9 is a void STACK), so the port reads
   uop 9 where upstream reads nothing at all. **⇒ THIS IS A REAL DIVERGENCE,
   IT IS PRE-EXISTING, IT IS NOT THE CAUSE OF ANYTHING MEASURED HERE (the
   AFTER's value is read by nobody on either side), AND I DID NOT FIX IT.**
6. **`Prog.oob` CHECKS ONLY LANE 0.** `Prog.oob` recurses with `j` FIXED at 0
   (`ops_python.bend:1945`), so a vec-4 store whose lane 3 is out of range but
   whose lane 0 is not is not caught. **PRE-EXISTING, NOT FIXED, AND NOT THE
   CAUSE OF ANYTHING MEASURED HERE.**
7. **THE CONV LANE IS MEASURED ON f32 ONLY.** A conv in f16/bf16 is the
   executor's WALL 1 and was not attempted.

## 8. THE WITNESSES AND HOW TO REBUILD THEM

Everything in `.agents/slop/convfix/`:

| file | what it is |
|---|---|
| `probe.py` | the conv A/B: BEND vs PYTHON vs upstream's own interpreter, on the SAME packet |
| `accesses.py` | upstream's own `_load`/`_store`, monkeypatched at runtime: what upstream TOUCHES |
| `scan.py` | which conv shapes render a kernel with a scratch `BUFFER` |
| `fixture.py` | writes the new fixture in the tree's `PACKET.in` spelling |
| `verify_fixture.py` | the fixture on BOTH executors and against upstream |
| `census-before.rows` | the 153-fixture census, pre-fix (364 rows) |
| `census-after.rows` | the 153-fixture census, post-fix (365 rows) |
| `census-diff.rows` | the 23 moved rows |
| `oracle-rows.rows` | upstream's own answers for all 153 fixtures (the gate's py lane) |
| `probe-final.out` | the headline measurement |
| `fixture-conv.rows` | THE NEW FIXTURE, ready to append |
| `packets/<case>/PACKET-0.in` | the captured BEND launches, with their buffers |
| `packet-big.annotated.rows` | the conv packet, annotated with the constants |
| `ops_python.pristine.bend` | the PRE-FIX source, byte-identical (sha256 `7ed97255e1a590a9fc2fa08baa474d2131a511361d8d9e2adb1ba55b2f8b4163`) |

### 8.1 THE GATE'S OWN VERDICT, COMPUTED (the gate itself is NOT run — the brief forbids it)

`gates/ops_python_exec-gate.py:317-332` compares the generator's oracle lane
(`py`) with the port lane (`bd`) over the rows that are NOT in the pins file.
Both lanes were produced here (the oracle lane by
`.venv/bin/python gates/ops_python_exec-gen.py`, 2.4 s, 366 rows; the port lane
by `.agents/slop/execfix/census.py` against the compiled executor), and the
gate's own two lines were then applied to them:

```
py rows=365 bd rows=365 unpinned=314 pinned=52
UNPINNED DIVERGENCES: 0
=> the gate's verdict on this change: PASS
```

**⇒ THE GATE STAYS GREEN, AND IT IS GREEN FOR A REAL REASON: 314 unpinned rows
and not one of them moved.** (All 23 moved rows are pinned, which is exactly the
trap the brief names: **a pinned row's value is never compared, so a fix can
move one with nothing going red** — which is why the rows were compared here,
against upstream's own answers, and not left to the gate.)

**⇒ AND THE GATE'S OTHER TWO CHECKS ARE UNAFFECTED, MEASURED:**
`gates/ops_python_exec-gen.py --coverage` reads `op_of: 46 declared, 2
unreached` and `dispatch: 20 declared, 2 unreached` — exactly the two counts
`coverage_hold` pins — because this change adds two defs (`Prog.ld.open`,
`Prog.ld.happens`) **outside** the `def Prog.dispatch(...)` slice the gate
reads (`ops_python_exec-gate.py:255`). And `population_hold` compares the
fixture FILE's names against the generator's re-harvest, and **this unit did
not touch the fixture file**.

**⇒ NOTHING WAS COMMITTED.** No mutating git command was run; every git read
used `env -u GIT_INDEX_FILE`. The two files this unit changed are
`tinybendygrad/runtime/ops_python.bend` and this directory
(`env -u GIT_INDEX_FILE git status --porcelain -- tinybendygrad/` reads
` M tinybendygrad/runtime/ops_python.bend` and nothing else).

### 8.2 THE BINARIES ARE BUILD OUTPUTS AND THE FIXTURE IS THE WITNESS

`executor-before` (the pre-fix executor) and `executor-after` (the post-fix
one) are here so the numbers above can be re-taken; they are rebuilt with

    ./bin/bend tinybendygrad/runtime/ops_python.bend -o <dir>/executor-after
    # the pre-fix source is git blob 53c0cd51bb6dea87c3275eb61a1e4c95f198033a:
    git cat-file blob 53c0cd51bb6dea87c3275eb61a1e4c95f198033a > <dir>/ops_python.old.bend
    # (it must be written to tinybendygrad/runtime/ to BUILD, because its
    #  imports are relative: `import ../base.bend as F`)

    .venv/bin/python .agents/slop/execfix/census.py <exe> <out.rows>
    .venv/bin/python .agents/slop/convfix/verify_fixture.py <before> <after>
    .venv/bin/python .agents/slop/convfix/probe.py


