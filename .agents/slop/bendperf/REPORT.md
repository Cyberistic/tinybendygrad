# Throughput of `Device['BEND']`: what sets it, measured

**Measured 2026-10-06 ~15:00–15:20 by the `bend` unit, from the repo root. `bend` was invoked only
for `walkbench.bend` (a few `--check-only` attempts plus one `-o` build), each alone through
`checks/bounded.py --mb 2048`; every timing of the DEVICE in here runs the already-cached executor
Mach-O directly, which is NOT a `bend` process.** The machine is shared (other units ran throughout);
pass/fail facts are unaffected, seconds carry load. All artefacts under `.agents/slop/bendperf/`.

## 0. Headline

The port is **not** slow because it is compiled, nor because each element is a call. **It is slow
because its buffers and its arena are cons `List`s, and every indexed access is `List.get`/`List.set`,
which walk from the head: O(index).** The wire round-trips *every* buffer through ASCII hex once per
launch, byte-by-byte, by index — so a launch is **O(bytes²)**, and a store is **O(element·offset)**.

- `Tensor.ones(64,64)` under `DEV=BEND`: **11.76 s**. Under `DEV=PYTHON`: **0.093 s**. **126×**.
- The same kernel launch is **one** subprocess (`Prog.__call__` once per launch, not per element). The
  grid (all elements) loops *inside* the compiled executor.
- A counter-indexed list walk vs a cons walk, on the real bend compiler at n=16384: **1.062 s vs
  0.0036 s = 291×**, and the gap grows with n (quadratic vs linear).

## 1. Method

| instrument | what it does | why it is the right one |
|---|---|---|
| `.agents/slop/bendperf/bench_tensor.py` | fresh `.venv/bin/python` per size, `DEV` from env, times `Tensor.ones(n,n).contiguous().realize()` | DEV is a process constant; min of 2 |
| `.agents/slop/bendperf/bench_bytes.py`, `bench.py` | runs the **cached executor Mach-O** directly on packets | separates the executor's cost from tinygrad's; no `bend` in the loop |
| `.agents/slop/bendperf/probe.py` | intercepts `ops_bend.subprocess.run`, keeps full argv + packet + wall | rc of the launch, and the grid, which `bendsuite/time_launch.py` dropped |
| `.agents/slop/bendperf/walkbench.bend` | a 45-line bend program, `--check-only` `ALL PROOFS CHECK` (rc 0, 31 MB) | measures the List choice on the **real** compiler |

Executor binary: `~/Library/Caches/tinygrad/bend-executor-970cbc1d5f288c9a`, the cache key for the
current `tinybendygrad/runtime/ops_python.bend` (mtime+size; `ops_bend.py:150-164`). It is a native
`Mach-O 64-bit arm64`; running it is not a compile. `bend` ran once, for `walkbench`.

## 2. The fit (task 1)

`Tensor.ones(n,n)`, min of 2 fresh processes, `DEV` from env:

| n | elements | buffer bytes | BEND s | PYTHON s | BEND µs/elem | PYTHON µs/elem |
|---|---|---|---|---|---|---|
| 8 | 64 | 256 | 2.9116 | 0.0404 | 45494 | 631 |
| 16 | 256 | 1024 | 3.5213 | 0.0515 | 13755 | 201 |
| 24 | 576 | 2304 | 2.8233 | 0.0511 | 4901 | 88.7 |
| 32 | 1024 | 4096 | 3.1756 | 0.0524 | 3101 | 51.1 |
| 48 | 2304 | 9216 | 5.8726 | 0.0577 | 2549 | 25.1 |
| 64 | 4096 | 16384 | 11.7598 | 0.0930 | 2871 | 22.7 |

**The line bends at the buffer, not the element count.** Small sizes are flat at **≈2.8–3.5 s**
(a fixed per-launch cost, §3), the `µs/elem` *falls* until ~9216 bytes, then the last row costs
`(11.76−5.87)/(16384²−9216²) = 3.2e−8 s/byte²` — **quadratic in bytes**, not linear in elements.
There is no single "ms/element"; the per-element number is a fixed cost divided by an n that is too
small until the O(n²) term takes over. `bendsuite`'s "≈2.4 ms/element" is the small-n slope of a
curve whose large-n slope is quadratic.

## 3. Where the time goes (task 2), with file:line

Four costs, each measured by turning one knob:

**(a) ONE subprocess per LAUNCH, not per element.** `probe.py` on `ones(64,64)` recorded **1 launch**,
argv grid `1 1 1`: the whole 4096-element fill is one `subprocess.run` (`ops_bend.py:222`) and the
grid loops *inside* the executor (`grid`, `ops_python.bend:2104`; `run`, `:2073`). So a per-element
call is **not** the shape. The two shapes, measured on the executor binary: **10 sequential
1-shape launches = 9.290 s → 929 ms/launch → 1000 single calls ≈ 929 s**, versus **one** launch
carrying all 1000 elements = **8.92 s** on the same 16 kB buffer (measured, trip=250; the buffer is
sized to the PARAM's `max_numel`, so even a 1000-element trip on a 4096-element buffer pays the whole
wire). **≈104×**, and `bend` already has the better shape; the fixed cost is what a per-element
caller would pay 1000×.

**(b) Fixed per launch ≈ 0.68 s + 95 ms per uop LINE.** Minimal packets on the executor, declared
uop count held at 16 while the real line count varied: 1 line → 0.815 s, 2 lines → 0.929 s, 16 lines
→ 2.245 s. `= 0.68 s + 0.095 s/line`, linear in parsed lines. The no-argument *gate* run exits in
**0.003 s**, so this is **not** process spawn and **not** the wire; it is in the parser
(`Prog.parse`/`Prog.parse.go`, `ops_python.bend:1444`). A 17-uop fill therefore pays ≈2.3 s of pure
parse before it does arithmetic. **Cause not separated** (splitting it needs a source edit); it is
per line, not per declared uop, and not per interpreter step (see (d)).

**(c) The wire: O(bytes²) per launch.** A 1-uop packet with an `n`-byte buffer, no loop:

| bytes | 1024 | 2048 | 4096 | 8192 | 16384 | 32768 |
|---|---|---|---|---|---|---|
| s (min of 3) | 1.04 | — | 1.44 | 2.50 | 7.13 | 25.68 |

Doubling 8192→16384→32768 gives ×2.85, ×3.6 → quadratic. Cause: input hex decode `Prog.hex.go`
(`:1192`) reads char `2k` via `Prog.hex.at`(`:1180`) → `List.get(&2,Char,cs,k)` **O(k)**; output hex
encode `Prog.line.go` (`:2171`) reads `Mem.byte(ms,at)` (`:858`) → `List.get` **O(at)**. Both walk a
`List` from the head once per byte. This is why `ones(64,64)` = 2.3 s(parse) + 7.1 s(wire) + ~2.4 s(compute).

**(d) Compute: O(element·offset) stores.** `Mem.put` (`:861`) → `List.set` **O(at)**; `Mem.st`
(`:891`), `Val.put` (`:855`) likewise. The trip=0→1024 slope of the real packet was ~2.4 ms per
RANGE iteration (4 elements) — the store reaching further down the list each time, not arithmetic.

## 4. BEND vs PYTHON (task 3)

`DEV=PYTHON` is the *same interpreter shape* (`ops_python.py:52-157` walks the same uop list) but its
buffers are `memoryview(bytearray)` with **O(1)** indexing. Same op, same sizes, §2: **22.7 µs/elem
vs 2871 µs/elem at 64×64 — 126×**. The delta is therefore **the port's executor (List vs memoryview),
not the approach (one process walking uops).** The Python device is also *fast despite being CPython*.

## 5. The ONE change, and its measurement (task 4)

**Replace counter-indexed `List` walks in the buffer/arena hot paths with either a cons walk or
`Array` (`base.bend:70-72`, O(log n)).** The sites: `Prog.hex.go:1192`, `Prog.line.go:2171`,
`Mem.byte:858`, `Mem.put:861`, `Val.at:852`, `Val.put:855`.

Measured, on the real compiler: `walkbench.bend` sums a list of n ones by `List.get(xs,i)` vs by cons
match —

| n | idx s | walk s | ratio |
|---|---|---|---|
| 1024 | 0.0066 | 0.0027 | 2.5 |
| 2048 | 0.0187 | 0.0026 | 7.2 |
| 4096 | 0.0658 | 0.0032 | 20.8 |
| 8192 | 0.2615 | 0.0034 | 77.2 |
| 16384 | 1.0619 | 0.0036 | **291** |

The walk is flat; the index is quadratic; the ratio grows with n. Applied to the wire, this is the
3.2e-8·B² term → O(B), which is what makes `test/null/`'s compute third reachable.

**I did not edit `ops_python.bend`.** It is a shared, git-tracked file and other units run
`DEV=BEND` against the same working tree; a local edit would change their device mid-run. The
requirement here is "the report is the improvement if the change is out of your lane" — this is the
measurement that justifies the change, and the change is a real port to `Array`/traversal, not a
one-liner.

## 6. `test/null/`'s watchdog: the denominator (task 6)

Watchdog: `conftest.py:11` — `faulthandler.dump_traceback_later(int(os.getenv("TEST_TIMEOUT", 180)),
exit=True)`, so **one** slow test kills the whole pytest process.

From the executor fit, a single launch stays under 180 s while `2.8 + 3.2e-8·B² < 180` →
**B ≲ 71 kB ≈ 17.8k f32 elements ≈ 133×133**. Anything larger — `test_tri_complexity`'s 256×256
(262 kB) → ≈2340 s — cannot finish. `bendsuite`'s per-file sweep (its instrument, quoted not
re-run) measured the consequences on the real corpus: **83 files, 1431 collected, 1082 measured
(946 pass), 349 in 10 files measured nothing**, all 10 executor-bound (`test_schedule.py` alone is
289 of the 349). **So at this rate ~76 % of `test/null/` completes and the compute-heavy 24 % does
not** — a parity figure, not "the suite is slow".

## 7. Limits, recorded not hidden

- Timings are wall, on a machine whose load was 35–54 from other units; the *shapes* (linear, flat,
  quadratic) are robust, the constants are not. Every table used min-of-N.
- The §3b "95 ms/uop" is measured (line count vs wall) but its internal cause is not separated; it
  would take an edit to `ops_python.bend` to split parse from build.
- The `n=512 idx` microbench row was a first-run outlier (0.67 s) and is excluded; the table starts
  at 1024.
- `bench_bytes` at 65536 B exceeded a 300 s timeout (quadratic) and was not taken.

## 8. Reproduce

```
.venv/bin/python .agents/slop/bendperf/bench_tensor.py ones           # §2, §4
.venv/bin/python .agents/slop/bendperf/bench.py .agents/slop/bendperf/launch-ones-000/PACKET.in 0 1 1024   # §3c/d
.venv/bin/python .agents/slop/bendperf/bench_bytes.py 1024 4096 8192 16384 32768                          # §3c
.venv/bin/python checks/bounded.py --mb 2048 -- ./bin/bend .agents/slop/bendperf/walkbench.bend -o .agents/slop/bendperf/walkbench  # §5 (the one bend call)
.agents/slop/bendperf/walkbench 16384 idx ; .agents/slop/bendperf/walkbench 16384 walk                    # §5
```
