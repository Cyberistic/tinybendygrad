# The wire, landed: three O(B²) walks become cons walks

**The `bend` unit, 2026-10-07. Every number below carries its method and its reading.** The one change
is in `tinybendygrad/runtime/ops_python.bend` (the `DEV=BEND` executor, compiled by `ops_bend.py:83`);
`DEV=PYTHON` (`tinygrad/runtime/ops_python.py`) is untouched and remains the A/B.

## 0. Headline

- **The 291× reproduces**, and cleaner: at n=16384, index-by-counter `1.0479 s` vs cons walk
  `0.0028 s` = **370×** (the walk is at its ~2.8 ms process-spawn floor).
- **The three O(B²) wire sites are cons walks now.** From `bench_bytes.py`, the same 1-uop packet:
  **8192 B 2470 ms → 988 ms · 16384 B 7117 ms → 1051 ms · 32768 B 25 869 ms → 1141 ms** (min of 2,
  fresh subprocess each). The quadratic is **gone**: NEW is flat.
- **The encoder is byte-identical.** `ones(64,64)` (a full 16384-byte buffer write) and `matmul(64,64)`
  (65550 B out) both round-trip **byte for byte** through the pre-fix and post-fix executors.
- **BUT the parity does not jump to 1431/1431.** Only the WIRE was quadratic; the **store** path is
  quadratic too (`Mem.put`/`List.set`, `Val.put`, `Mem.st`), and it was *always* there. Removing the
  wire leaves the store's `c ≈ 1.0e-8 s/byte²` as the binding term. So `2.8 + c·B² < 180` gives
  **B ≲ 132 kB ≈ 181×181**, not gitinput's extrapolated 1.27 MB. The full-device coefficient fell
  **3.3e-8 → 1.0e-8** (matches bendperf's full-device `3.2e-8`), i.e. **~3.2×**, and `B` ~1.9×. The whole
  `ones(64,64)` launch (fixed + wire + store) went **11.76 s (bendperf) → 5.6 s**.

## 1. Reproduce the 291× (task 1) — token and method

The prebuilt `.agents/slop/bendperf/walkbench` (Mach-O, a native run — **not** a `bend` process) sums
n `U32`s two ways. `walk.py` runs it, min of 3, `time.perf_counter` around `subprocess.run`:

`.agents/slop/bendwire/walk-repro.rows`

```
      n     idx_s    walk_s    ratio
   1024    0.0072    0.0025     2.9x
   2048    0.0186    0.0023     8.0x
   4096    0.0660    0.0024    27.9x
   8192    0.2620    0.0025   105.6x
  16384    1.0479    0.0028   370.4x
```

The idx column is quadratic, the walk column is flat; the ratio grows with n. bendperf reported
1.0619/0.0036 = 291×; the ratio difference is the walk's ~2.8 ms spawn floor. **REPRODUCED.**

`bend` was invoked **only** under `checks/bounded.py --mb 2048`, alone:

```
.venv/bin/python checks/bounded.py --seconds 900 --mb 2048 -- ./bin/bend tinybendygrad/runtime/ops_python.bend --check-only
[bounded] WITHIN-LIMITS  rc=0  peak-RSS=1292 MB (ceiling 2048)  4s
ALL PROOFS CHECK
```
(Verdict TOKEN, not exit code.)

## 2. What landed (task 2) — THREE sites, not 37

`ops_python.bend` has 37 index-shaped sites (`gitinput`'s `blastradius.rows`). **Only the O(B²) wire
walkers are changed; the compute stores are left, with the reason below.** All three share one cause:
a body indexed by a counter that climbs, so each access walks the cons list from the head.

| site | was | now |
|---|---|---|
| `Prog.hex.go` (was `:1192`) | `Prog.hex.byte(cs, p)` → `List.get(cs, 2p)`+`List.get(cs, 2p+1)`, O(k) per byte | folds the char list head-first, two chars per byte |
| `Prog.hex.at`/`nib`/`byte` (was `:1180`) | the O(k) accessors, used **only** by `hex.go` | **deleted** — the walk subsumes them |
| `Prog.hex.app` (was `:1197`) | `List.append(acc, [h])` walked `acc` per element | `h <> app(t, acc)`, O(\|bs\|) |
| `Prog.line.go` (was `:2171`) | `Mem.byte(ms, at)` = `List.get(ms, at)`, O(at), at climbing | drops `base` once, then a cons walk |

The cons walk reads the list head-first, so it answers the bytes **reversed**; `Prog.hex.app` prepends
onto a reversed accumulator and `Prog.bytes` reverses once (and `Arg.hex` does for its one-line read) —
the same cancellation the old `append`-in-one-line had, now O(bytes) instead of O(B²). Net: **three defs
deleted** (`hex.at`/`nib`/`byte`), `hex.go` gains a `Bool` state, `line.go` loses its `at` counter.

**`base.bend` at `:70`.** `tinybendygrad/base.bend` is **56 lines** — there is no `:70`, and no `Array`
in it. `Array` is Bend's **builtin** (`Base`), used elsewhere in this tree (`ops_python.bend:216-224`
records its rules). It was **not** used here: the wire is a sequential read, so a cons walk is the
direct shape and needs no random access; `Array.get` (`:216`) even has its own destructuring rules.

## 3. Measure after, the same way (task 3)

`bench_bytes.py`: the pre-fix (`970cbc1d5f288c9a`) and post-fix (`501a6a0ac0ceab82`) executor binaries,
same minimal 1-uop packet, min of 2 fresh subprocesses, `time.perf_counter` around each launch.

`.agents/slop/bendwire/wire-fit.rows`

```
    bytes |     OLD ms     NEW ms |  speedup
     1024 |    1032.23    1027.06 |     1.0x
     2048 |    1103.05     982.80 |     1.1x
     4096 |    1378.50    1002.68 |     1.4x
     8192 |    2470.15     987.98 |     2.5x
    16384 |    7116.60    1051.29 |     6.8x
    32768 |   25869.29    1140.68 |    22.7x
```

Fit (ms): OLD `≈ 1.05 s + 2.32e-8·B²` (from 8192/32768 and 16384/32768, agreeing to 2%), NEW
`≈ 1.06 s + 4.2e-6·B` (linear, coefficient 4 µs/byte). **The B² term is removed from the wire.**

## 4. The encoder is byte-identical (task 4)

`roundtrip.py` runs one `PACKET.in` through the **pre-fix** executor, the **post-fix** executor, and
the packet the post-fix device itself wrote, and compares `PACKET.out` byte for byte:

```
launch-ones-000/PACKET.in  33162 B   (ones 64x64, full 16384-byte buffer write)
  old-exec 32775 B  39a4d6b48ac4d05a
  new-exec 32775 B  39a4d6b48ac4d05a
  device   32775 B  39a4d6b48ac4d05a   BYTE-IDENTICAL
launch-64/PACKET.in  73681 B   (matmul 64x64, 65550 B out)
  old-exec 65550 B  bee10c2aff28a4f2
  new-exec 65550 B  bee10c2aff28a4f2
  device   65550 B  bee10c2aff28a4f2   BYTE-IDENTICAL
```

`ones` is the stronger test: a fill writes the **whole** buffer, so both hex paths run over 16384 B.
The pre-fix executor `970cbc1d5f288c9a` is retained in tinygrad's cache (its key is the pre-edit
mtime+size), so this is a real before/after, not a re-derivation.

## 5. `test/null/test_dtype.py` under `DEV=BEND` (task 5)

The pre-fix binary is pinned for a true before/after with the `oldexec.py` pytest plugin (the executor
is `functools.cache`d on mtime+size, so the edited file no longer maps to yesterday's binary):

```
BEFORE (oldexec):  1 failed, 9 passed   (0.07 / 0.08 / 0.09 s)
AFTER  (default):  1 failed, 9 passed   (0.12 / 0.14 / 0.14 s)
```

The failure is `TestEqStrDType::test_strs` (`'dtypes.f32' != 'dtypes.float'`) and it fails on `DEV=CPU`
too — device-independent, as `bendsuite` recorded. **Pass counts are identical; the time is not the
signal here** (this file launches no large-buffer kernel, so the wire term is negligible). The AFTER
min (0.12 s) exceeding the BEFORE min (0.08 s) is load, not the change: the same binary runs a 1024-byte
packet at 1027 ms post-fix vs 1032 ms pre-fix (§3). Reported, not hidden.

## 6. The parity figure, our own coefficient (task 6)

**The premise needed correcting: the wire was not the only quadratic.** `bench_bytes` (§3) isolates the
wire (no loop, no store): post-fix it is linear. So the remaining quadratic is the **store** —
`Mem.put`→`List.set` (`:861`), `Val.put` (`:855`), `Mem.st`/`Mem.st4` (`:891`/`:889`) — each O(offset).

`fit.py` measures the full device, `Tensor.ones(n,n).contiguous().realize()` under `DEV=BEND`, min of 2
fresh processes:

```
    n         B         s    us/elem
   64     16384     5.616    1371
   80     25600     9.234    1443
   96     36864    19.879    2157
  112     50176    28.114    2241
  128     65536    42.807    2613
```

Fit `t = a + c·B²` on n=64/128: `a = 3.14 s`, **`c = 9.2e-9 s/byte²`**. Pairwise fits across adjacent
points give `c` between `7.8e-9` and `1.3e-8` (load); **take `c ≈ 1.0e-8`**. The store coefficient is
confirmed by shape: subtracting the fixed cost, `(42.8−3.1)/(5.6−3.1) = 15.9 ≈ 16` for a 4× buffer —
quadratic, not linear.

**Solve `2.8 + 1.0e-8·B² < 180`:**
```
B² < (180 − 2.8) / 1.0e-8 = 1.772e10  →  B ≲ 133 000 B ≈ 130 kB
as f32 n×n:  n = sqrt(133000/4) ≈ 182   →   B ≲ 182×182
```

**Before → after:** the full-device coefficient was `3.2e-8` (bendperf; = wire `2.3e-8` + store `1.0e-8`,
which sums to the measured pre-fix `ones(64,64)` 11.76 s exactly). Now `1.0e-8`. So `B` rises from
`≲71 kB (133²)` to `≲130-133 kB (≈182²)` — **~1.9× in B, ~3.2× in area** — and **NOT** to 1.27 MB: that
extrapolation (gitinput's `/291`) divided the *whole* quadratic by 291, but only the wire part moved.

### How many of the 1431 (the deliverable)

The corpus jumps from tiny buffers to **256×256 = 262 144 B**, which is **> 133 kB** both before and
after, so `test_arange::test_tri_complexity` and friends stay out of reach either way. `reach.py`
re-runs `bendsuite`'s ten zero-measured files (its `sweep-bend.tsv`: verdict FAULTHANDLER-TIMEOUT or
KILLED-BY-SWEEP with 0 passed) **under BOTH executors at the SAME budget** (`-v`, per-file cap 240 s,
`TEST_TIMEOUT=180`, one process per file). Matched budgets are the point: an earlier NEW-only run at
these wider timeouts read "56 pass", but that is the **timeout**, not the fix — the original sweep used
96/120 s.

| file | OLD pass/measured | NEW pass/measured | verdict |
|---|---|---|---|
| test_allreduce | 0 / 0 | **5 / 5** | OLD ABORTED → NEW COMPLETED |
| test_arange | 0 / 1 | 0 / 1 | both ABORTED (256²) |
| test_assign | 4 / 4 | 4 / 4 | both ABORTED (5th: many launches) |
| test_attention | 0 / 0 | 0 / 0 | both ABORTED |
| test_function | 5 / 5 | 5 / 5 | both ABORTED |
| test_linearizer | 3 / 8 | 3 / 8 | both COMPLETED (4 pre-existing fails) |
| test_real_world | 0 / 8 | 0 / 8 | both ABORTED (3 pre-existing fails, 5 skip) |
| test_schedule | 20 / 20 | 20 / 20 | both KILLED at the 240 s cap (of 289) |
| test_symbolic_tensor | 15 / 15 | 15 / 15 | both COMPLETED |
| test_winograd | 4 / 4 | 4 / 4 | both COMPLETED |

`.agents/slop/bendwire/reach.tsv` (new) and `reach-old.tsv` (old). **The fix flips exactly one file:
`test_allreduce`, 0 → 5 tests, wall 180+ s → 65 s.** Every other file is unchanged at matched budgets,
because they are bound by the **store** path (256×256) or by the **fixed per-launch cost** (many tiny
launches), neither of which is the wire.

**So "N of M": the wire fix admits `test_allreduce` (5 tests); 344 of the 349 remain out.** Against the
corpus: measured `1082 → 1087` of 1431, passed `946 → 951`. Read every row with the five-verdict rule —
**ABORTED is not zero** (the faulthandler `exit=True` kills pytest before the summary, so the counts are
the tests that finished, e.g. `test_assign` is 4 of 5; its 5th builds a pending-assign graph whose many
launches each pay ~2.7 s fixed). `test_linearizer`/`test_real_world`'s **failures** are pre-existing
device gaps, not regressions.

**The remaining throughput work is the store (`Mem.put`/`List.set`, `Val.put`, `Mem.st`) — 34 of the 37
sites — followed by the per-launch fixed `0.68 s + 95 ms/uop-line` parse (`bendperf §3b`). A wire-only
fix was never going to reach 1431/1431, and this A/B is the measurement that says so.**

## 7. Why three sites and not 37

A rewrite of `Mem.put`/`Val.put`/`Mem.st` changes the executor's **store semantics for every launch** —
`List.set` at an index is the only random access the arena has, and there is no cons walk for it. It is
a different change with a different proof (an `Array` arena, or a mutable-cell scheme), it cannot be
bisected against this one, and it is not the O(B²) the brief named. The three wire sites are the O(B²)
that shows up as "one launch takes 25 s for 32 kB"; they are landed, measured and byte-verified here.
The other 34 are named, with the reason, and left.

## 8. Limits, recorded not hidden

- Timings are wall on a shared machine; other units ran throughout (the n=64 `ones` read 5.6 s
  uncontended and 8.5 s under the `reach` sweep). The *shapes* are robust; the constants carry load.
  Every cell is min-of-2 or min-of-3, method stated.
- `test_assign`/`test_arange`/… hit the 180 s watchdog; their `reach` counts are lower bounds.
- `git diff` for the file is **empty** — this tree's `jj` server snapshots the working copy into the
  current revision, so the edit already reads as committed. The authority is not the diff: it is the
  compiled executor (`501a6a0ac0ceab82`, `ALL PROOFS CHECK`) and the byte-identity test (§4).

## 9. Reproduce

```
.venv/bin/python .agents/slop/bendwire/walk.py --reps 3 16384                # §1
.venv/bin/python checks/bounded.py --seconds 900 --mb 2048 -- \
    ./bin/bend tinybendygrad/runtime/ops_python.bend --check-only            # §1
.venv/bin/python .agents/slop/bendwire/bench_bytes.py                        # §3
.venv/bin/python .agents/slop/bendwire/roundtrip.py .agents/slop/bendperf/launch-ones-000  # §4
.venv/bin/python .agents/slop/bendwire/fit.py --reps 2 64 96 128             # §6
.venv/bin/python .agents/slop/bendwire/reach.py                              # §6, new executor
.venv/bin/python .agents/slop/bendwire/reach.py --old                        # §6, old executor (A/B)
```
