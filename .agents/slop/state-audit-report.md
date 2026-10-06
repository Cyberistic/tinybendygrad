# STATE AUDIT — 2026-10-03, one honest snapshot of every gate

**Instrument:** `.agents/slop/state-audit.py` (new, this unit). Every number below came from
a run in this session, and each is labelled with the run it came from. **Nothing is reused
from the briefing.** Where a figure moved between runs, both readings and both clock times
are given.

**Commands, all with `env -u PYTHONPATH` and `LC_ALL=C`:**

| gate | invocation | interpreter |
|---|---|---|
| rebase | `.venv/bin/python .agents/slop/rebase-gate.py --json` (whole tree, no `--record`) | `.venv/bin/python` (3.12) |
| selftest | `.venv/bin/python .agents/slop/rebase-gate-selftest.py` | same, and cross-checked on `python3` (3.14) |
| naming | `.venv/bin/python .agents/slop/naming-gate.py` | same |
| tree | `tree-verdict.py -P 6 --json`, on a **private symlink root** (see §4) | same |
| proof | `./bin/bend tinybendygrad/LAWS/PROOF-ALL.bend --check-only` × 3 | — |
| upstream | `.venv/bin/python .agents/slop/upstream-delta.py` | same |

---

## ⚠ THE FINDING THAT GOVERNS EVERYTHING ELSE: THE INTERPRETER IS THE GATE

Measured, and it settles a contradiction two units have been carrying:

```
$ ls .venv/lib/python3.12/site-packages/__editable__.tinygrad-0.14.0.pth   # EXISTS
$ ls /opt/homebrew/opt/python@3.14/.../site-packages/*.pth                  # NONE
```

```
$ env -u PYTHONPATH .venv/bin/python .agents/slop/tensor-gate.py | wc -l   ->  30
$ env -u PYTHONPATH python3          .agents/slop/tensor-gate.py | wc -l   ->   0
    ModuleNotFoundError: No module named 'tinygrad'
```

The editable install is **python3.12 inside `.venv` and nowhere else**. `rebase-gate.py`
runs oracles with `sys.executable`, so it inherits the caller's interpreter. **Launched
with the bare `python3` on PATH, all 38 wired ports go BROKEN on their `cpython:*` lanes**
and the reader concludes the tree is red. I hit this myself: my first sweep was launched
on `python3`, produced a wipeout, and I killed and relaunched it on `.venv/bin/python`.

**So both circulating claims are half-true, and which half you measure depends only on
which `python3` you typed:**
- "PYTHONPATH blocks every oracle" — **true under `python3`**, false under `.venv/bin/python`.
- "it's an editable install, so `PYTHONPATH` is never a blocker" — **true under
  `.venv/bin/python`**, false under `python3`, and also false under
  `python3 -c` run from the repo root (where `sys.path[0]` is `''` and a `tinygrad/`
  directory sits in the cwd, which is a false positive that survives exactly until an oracle
  is invoked as a *script* from `.agents/slop/`, where `sys.path[0]` is `.agents/slop`).

`state-audit.py` therefore **probes** the interpreter (script, neutral cwd) rather than
assuming one, and refuses to measure at all if no candidate can import `tinygrad`.

---

## 1. `rebase-gate.py` — whole tree

**Run A**: launched 19:25 on `.venv/bin/python`, finished **20:07**, `rc=1`.
50 verdicts. **UNCHANGED=0, RE-PORTED=0, BROKEN=4, NOT-STARTED=46.**

The sweep did finish — one pass, all 50 targets. NOT-STARTED splits as **34 "no baseline
recorded" + 12 "no oracle wired"**. There are **zero UNCHANGED and zero RE-PORTED** because
`oracles/rebase/baseline.json` (mtime Oct 2 18:42) predates the oracle widening to 38; every wired
port has lanes that ran and agreed but no baseline to move against.

### Every BROKEN port, with its reason

**Run A, 20:07:**

| port | rows (interpreted / native / oracle) | why |
|---|---|---|
| `renderer/cstyle.bend` | 225 / 225 / 15 | GUARD 4: the lane pairs **share no row names** (`cpython:renderer_oracle` vs both port lanes) |
| `dtype.bend` | 0 / — / 0 | GUARD 3: `interpreted` and `native` lanes exit 1 — `SOME PROOFS FAIL … 14 defs rely on unsafe or foreign code`; native says `Error: no main to run` |
| `codegen/decomp/dtype.bend` | **164** / 164 / 351 | GUARD 4: **36 rows disagree with CPython** |
| `renderer/amd/generate.bend` | 726 / — / 779 | GUARD 3: native lane `Error: the machine stack overflowed` |

**Run B (re-check, ~20:20, `--port` on each of the four):** only **three** reproduced.

| port | Run A | Run B | moved? |
|---|---|---|---|
| `codegen/decomp/dtype.bend` | BROKEN, 36 disagreeing | BROKEN, **2** disagreeing (port rows 164→**172**) | file rewritten 20:05:52 |
| `renderer/amd/generate.bend` | BROKEN, native overflow | **NOT-STARTED**, native=**726**, all lanes ran | file rewritten 20:16:27 |
| `dtype.bend` | BROKEN (dead lane) | BROKEN, identical reason | no |
| `renderer/cstyle.bend` | BROKEN (0 shared names) | BROKEN, identical reason | no |

**BROKEN on every run: 3. BROKEN in the sweep only: 1. BROKEN in the re-check only: 0.**

### What each red would take to become green — and whether it should

1. **`renderer/cstyle.bend` — PERMANENTLY RED BY DESIGN. It should stay red.**
   `renderer_oracle.py cstyle` exits 1 on upstream's own `dtypes.weakint` and shares 0 of
   225 row names. Wired deliberately so GUARD 4 is reachable on the real tree. Making it
   green would mean writing an oracle that actually renders cstyle rows through CPython —
   real work, and until then the red is the *correct* report.

2. **`dtype.bend` — PERMANENTLY RED BY DESIGN. It should stay red.**
   14 laws cannot be filled because Bend 2.0.34 has no `F16`/`I64`/`F64`/`U64`; the
   interpreted lane therefore exits 1 and the native lane has no `main` to run. Wired
   deliberately. Green would require Bend gaining those dtypes — not this repo's decision.

3. **`codegen/decomp/dtype.bend` — ONE DISAGREEMENT, AND IT IS A DECLARED REFUSAL.**
   Re-running with `--json` names it: the disagreement tuple is
   `['cpython:dtype-oracle', 'interpreted', 'c7']` and `['…', 'native', 'c7']` — that is
   **one row name counted twice** because interpreted and native agree with each other.
   Measured values: port prints `c7=refused:unported`; oracle prints `c7=F(2139095040)`.
   The port's own source (`codegen/decomp/dtype.bend:2417-2422`) declares this: the oracle's
   `c{i}` row is a function of `dt` alone while CPython's depends on `fr` too, so `c7`
   (`float64`) is ill-posed; the port prints `unported` on purpose and carries a TODO naming
   the two ways it closes (an `F64`, or `f2f_clamp_max` returning the `fr`-narrowed value).
   **The gate is right and the port is honest.** To go green, close that TODO — or record
   an exemption, since `refused:unported` is a *statement*, not an omission.

4. **`renderer/amd/generate.bend` — NOT RED. It did not reproduce.**
   Run B ran all lanes clean (interpreted 726, native 726, oracle 779). Run A's native
   overflow hit a file version that no longer exists (rewritten 20:16:27) — and this file is
   the one `.agents/slop/one.sh`'s own header says **overflows ~1 run in 6**. Independently,
   4 consecutive direct runs of the current file gave **726 rows, 0 overflows**.

---

## 2. `rebase-gate-selftest.py`

Run twice, once per interpreter (`python3` 3.14 at 19:25 and `.venv/bin/python` 3.12 at
19:25): **byte-identical output**, so the selftest is interpreter-independent.

- **66 PASS, 0 FAIL**, `rc=0`, final line `all states reachable -- a gate that cannot fail is not a gate`.
- Breakdown: 26 state/plan-shape checks + 2 roster checks + 38 per-oracle conformance checks = 66.
- **`BASE_ORACLES` and `ORACLE_CONFORMANCE` AGREE.** The check prints
  `PASS  BASE_ORACLES and ORACLE_CONFORMANCE are the same roster (38 oracles)`.
  **Oracle count: 38.** The equality is tested in both directions (only-in-A, only-in-B).
- `ORACLE_NOT_WIRED` is disjoint from the wired roster: 1 named, `device.bend`, with a
  reason (a proven port bug on `allow_lower`, deliberately not wired because a permanently
  BROKEN lane would train the reader).

**What it does not cover, stated rather than implied:** of the 38 conformance checks, 36
are *synthetic* — they drive the six states through `gate_port()` over the oracle's own row
**names** without running the oracle. Only the 2 `dead` entries run the real gate on the
real tree. So the selftest proves the decision function is reachable, not that 38 oracles
work; that is `rebase-gate.py`'s job, and §1 is its answer.

---

## 3. `naming-gate.py`

**Stable reading, 9+ runs across 18:53–21:00:**

```
upstream .py files with a sibling .bend walked       109
upstream top-level BINDINGS                         1583
  VERBATIM     port reproduces the name exactly       283    17.9%
  QUALIFIED    name kept, under a module qualifier     38
  RENAMED/1                                          29   <- adjudicated
  RENAMED/n                                          89   <- adjudicated
  ABSENT       UNPORTED, no counterpart              1144    72.3%
RENAMED: 668 candidates -> 1 unadjudicated
RESULT: FAIL
```

### Versus the last-known figures (283 VERBATIM + 38 QUALIFIED, RESULT PASS)

- **VERBATIM 283 — unchanged** (when the tree is quiescent). **QUALIFIED 38 — unchanged.**
- **RESULT MOVED: PASS → FAIL.** `rc=1`. It has been FAIL in every run I made, from 18:53
  through 21:00. One unadjudicated rename:

  ```
  helpers.py   getenv   + _int   ->   getenv_int
  ```

  **To make it green:** either rename the port def to the bare upstream name `getenv`, or
  add one ledger line adjudicating *this exact affix* on *this exact name* in *this exact
  file*. An exemption covers one exact affix; changing the prefix re-arms the gate. So the
  fix is a one-line decision, and it should be made — a gate that is red for one ruling is a
  gate that stops being read.

### ⚠ The 283 is NOT stable, and this is worth more than the number

Runs at **19:34:12, 19:35:44, 19:35:57, 19:36:19** read **278 VERBATIM / 1149 ABSENT**.
Runs at 18:53, 19:36:41, 19:37:16–19:38:24 (six, byte-identical MD5), and ~20:5x read
**283 / 1144**. `ls -la` inside that window showed `codegen/__init__.bend` at 19:34,
`nn/state.bend` at 19:35, `renderer/amd/generate.bend` at 19:36 — three ports mid-write by
other agents, five upstream bindings moving VERBATIM→ABSENT and back.

**Both readings are real.** 283 is the settled value; 278 is a snapshot of someone else's
edit. **A re-derived gate number is only a fact if you also record when, and a number that
moved between two runs of the same command on the same tree is not evidence until you find
out who was writing.** RESULT=FAIL held in both readings.

---

## 4. `tree-verdict.py`

**Run on a PRIVATE scratch root.** `tree-verdict.py` hardcodes
`SCRATCH = os.path.join(HERE, "tv-scratch")` and exposes no flag to move it, while
`one.sh` writes `check.out`/`check.err`/`run.out`/`run.err` per file into it.

**This was measured, not assumed:** at 19:13 two `tree-verdict.py` processes were live, with
`one.sh tinybendygrad/runtime/support/elf.bend` running under **both** parents, writing to
the **same** directory, and the other doing `rm -rf .agents/slop/tv-scratch` between its own
two runs — deleting the first run's scratch mid-flight. My first run was contaminated; I
killed it and rebuilt on a symlink root (`state-audit.py:isolated_tv_root()`), where the
copies resolve `parents[2]` to a scratch tree and get a private `tv-scratch`, with
`tinybendygrad/ tinygrad/ examples/ references/ bin/bend` symlinked so bend reads real
sources and nothing is copied.

**Isolated run: launched 19:14, finished ~20:12, 138 files.**

| bucket | n |
|---|---|
| green | **109** |
| no-main | **10** |
| no-rows | **8** |
| foreign-code-surface | **10** |
| proof-in-progress | **0** |
| broken-here | **1** |
| broken-in-import | **0** |
| no-verdict | **0** |
| **total** | **138** |

**Unstable row counts: 0 files.** No file's evidence carries an `UNSTABLE` marker. Every
file reached agreement within one.sh's 6-attempt cap.

### Every `broken-*` file, with its cause — and it does not reproduce

**`tinybendygrad/codegen/__init__.bend`** — `broken-here`, rows=0, attempts=[6,1,0]:

```
tinybendygrad/codegen/__init__.bend:214
  def main.run.show(r: Maybe<&2, U32>, repl: Map<&2, U32>, topo: List<&2, U32>) -> IO(Unit):
  -- expected a filled definition (an unfilled law is a dead claim: live code cannot use it)
  gr_show.topo
```

A `def` header with no body — a **partially-written file**. The sweep read it while another
agent was writing; the file's mtime is now 19:57 and line 214 is a comment.

**Re-check on the same isolated root, 8 attempts:**

```
rows=1  attempts=2  distinct=1  voids=0  verdict=ALL PROOFS CHECK
```

**So the sweep's single `broken-here` was an artifact of concurrency. The honest answer is
`broken-here` = 1 in the run and 0 on re-check.** This is the one number in this report that
changed because of a writer rather than because of bend.

### The other buckets, spelled out

**`no-main` (10)** — libraries with no `main` anywhere in their import closure, 6 attempts
each: `LAWS/PROOF-ALL.bend`, `__init__.bend`, `codegen/decomp/__init__.bend`,
`codegen/late/__init__.bend`, `engine/__init__.bend`, `helpers.bend`,
`renderer/_mut_m35.bend`, `renderer/_ptxmut.bend`, `runtime/__init__.bend`,
`runtime/support/__init__.bend`. By design, not a failure. (`renderer/_mut_m35.bend` and
`_ptxmut.bend` are mutation scratch and `scratch?`-tagged by the tool.)

**`no-rows` (8)** — a `main` **is** in scope and printed 0 rows in **6 of 6 attempts**, which
is a *question*, not a verdict: `LAWS.bend`, `LAWS/alu.bend`, `PROOF.bend`, `PROOF2.bend`,
`codegen/opt/__init__.bend`, `codegen/rewriter.bend`, `mixin/__init__.bend`,
`viz/__init__.bend`. The first four are judged by the **set**, which the tool resolves to
`ALL PROOFS CHECK` via `LAWS/PROOF-ALL.bend` — so they are green-by-set, not failures.

**`foreign-code-surface` (10)** — declared seams, not breakage: `dtype.bend` **declares its
own 14** (`Dt.bf16`, `Dt.fp16`, `Dt.fp8_from`, …) and `sz.bend` declares its own 7
(`Sz.read_dir`, `Sz.is_dir`, `walk.item`); the other 8 (`examples/beautiful_mnist.bend`,
`nn/__init__.bend`, `nn/onnx.bend`, `nn/optim.bend`, `nn/state.bend`,
`runtime/ops_python.bend`, `test/_probe/v5.bend`, `test/dtype_oracle.bend`) **propagate**
those same 14 from `../dtype`. The single `dtype.bend` declaration is the whole seam.

**Retries spent on zeros:** every one of the 10 `no-main` and 8 `no-rows` files spent the
**full 6-attempt cap** (`attempts=[6,1,0]`), because one.sh never lets 0 *be* the agreement.
`void_attempts` was 0 on all 18. A settled zero is therefore expensive to establish and is
reported as `rows=0, attempts=6, voids=0`, never as a bare 0.

---

## 5. `LAWS/PROOF-ALL.bend --check-only`

```
ALL PROOFS CHECK
Use --verdict for mathematical validity.
```

**`rc=0`.** Three runs inside `state-audit.py` plus two earlier ones: **5 runs, the same
first line every time.**

- **Read the first diagnostic line, never the exit code.** Recorded side by side because on
  a *failing* file bend prints the same shape to **stderr** and exits 1; here it went to
  stdout and exited 0. An `rc`-based gate is right here by luck.
- **"34/34" is two measurements, and bend supplies only one of them.** `ALL PROOFS CHECK`
  says every law is discharged and says nothing about how many laws exist. The 34 is
  counted from `tinybendygrad/LAWS.bend`: **34 `^law NAME:` declarations, 34 distinct
  names.** `PROOF.bend` and `PROOF2.bend` declare 0 laws each; `LAWS.bend` is the only file
  in the tree with any.
- **Rows = 0, settled in 3 attempts, 0 voids.** `PROOF-ALL.bend` is three `import` lines
  with no `main`, so 0 rows is the *correct* answer, and it cost the full retry cap to
  establish. That is a measurement, not a gap.

---

## 6. `upstream-delta.py`

Run twice (19:0x, 19:2x): **byte-identical.**

```
  PIN      6c3d401cf324  2026-09-29   204/230 vendored blobs match it
           method: content match over 400 commits of upstream/master; newest wins a tie.
           3 commit(s) tie at 204; the newest is taken. Runner-up 203/230, so the tie is
           broken by 1 blob(s).
  UPSTREAM 91b8cb5fa6c0  2026-10-02   BEHIND 59 commits, 124 files, 51 under tinygrad/
  AT PIN                 204
  RE-VENDORED            25
  ⚠ HAND EDITS            0
  LOCAL-ONLY PATHS        1   tinygrad/runtime/ops_bend.py
  PORT-RELEVANT CHANGED  46
```

- **PIN = `6c3d401cf324`, 2026-09-29. Vendored-blob match count = 204/230.**
- 204 + 25 + 1 = 230, so the four states are exhaustive.
- The pin is **derived, not stored** — a 400-commit content walk every run — so it cannot
  drift from a recorded value.
- **"25 files past the pin", not 16, and this is the *re-vendored* count.** `HAND EDITS` is
  **0**. Anyone reading "16 oracles use the pin vendor" was reading a different number.

---

## ROW PARSERS: TWO DEFECTS FOUND BY CHECKING ONE AGAINST THE OTHER

Not a deliverable, but it changed what §1's numbers mean, so it is reported.

I cross-checked my `parse_rows()` against `rebase-gate.py`'s own `rows()` on **8 lanes**.
They agree exactly on 7. Two defects, found by the disagreement:

**1. An empty value silently dropped rows.** With `(?P<val>\S.*?)` my parser returned **537**
for `nv-oracle.py` and **1028** for `elf_rows.py` against the gate's **547** and **1042** —
a shortfall of exactly the 10 `nv_*=` and 14 `elf_built_*=` rows whose value is the empty
string. Both numbers look like counts. The dangerous part: two lanes that *both* print an
empty value for the same row are compared by the gate and skipped by mine, so a disagreement
on precisely those rows would be invisible. **Fixed** (value may be empty); the two parsers
now agree to the key and to the value on all 8 lanes.

**2. A `== SECTION ==` banner is manufactured into a row — in the production gate too.**
`prepare-oracle.py` prints **14** banner lines (`== A: TABLES ==`, `== C: walk_mop ==`, …).
Split on the first `=`, the "name" is empty, so a dict collects all 14 as **one** key and
reports **2522** rows where there are **2521**. `rebase-gate.py`'s `rows()` does this and
names the phantom `""`; my parser now rejects it and reports 2521.

**This changes no verdict today** — GUARD 4 compares *shared names* and no port prints a row
called `""`. But it is a latent trap: an oracle whose banner text collided with a port row
name would be compared against a banner. **I did not patch `rebase-gate.py`** (read-only
task, not my file). The fix is one condition in `rows()`: reject a name that is empty or all
`=`. **Reported, not fixed.**

**Shape census, both lanes confirmed on the live tree:** `generate.bend` is 100% bracket
(`name = [val]   py=[val]`, 726), `nv-oracle.py` is 100% plain (`name=value`, 547), and a
`\s=\s` parser matches **0 of 547** lines of `nv-oracle.py` — which is the false zero, and
which my census prints so a lane that changes shape cannot hide.

---

## EVERYTHING RED, AND WHAT IT COSTS TO FIX

| gate | state | to make it green | should it? |
|---|---|---|---|
| naming-gate | FAIL (1 unadjudicated rename) | one ledger line, or rename to `getenv` | **yes** — a one-ruling red devalues the gate |
| rebase-gate / `cstyle.bend` | BROKEN by design | write a real cstyle oracle; upstream's own exits 1 | keep red until then |
| rebase-gate / `dtype.bend` | BROKEN by design | needs Bend `F16`/`I64`/`F64`/`U64` | no — not this repo's call |
| rebase-gate / `decomp/dtype.bend` | BROKEN, 1 declared refusal (`c7`) | close the TODO at `:2420`, or exempt `refused:unported` | yes |
| rebase-gate / `generate.bend` | **not red** — overflow did not reproduce | n/a | n/a |
| tree-verdict / `codegen/__init__.bend` | **not red** — mid-write artifact | n/a | n/a |
| tree-verdict / 8 `no-rows` | question, not a verdict | run a `main` that prints rows | judgment call per file |
| rebase-gate / 34 ports | NOT-STARTED, no baseline | `--record` on a tree known green | yes — but see below |
| rebase-gate / 12 ports | NOT-STARTED, no oracle | author a CPython oracle | yes — the structural gap |

**The one that matters most:** 34 wired ports run their lanes, agree, and report
NOT-STARTED purely because `oracles/rebase/baseline.json` predates the widening to 38 oracles. Until
`--record` runs on a tree known green, **`rebase-gate.py` cannot say UNCHANGED or RE-PORTED
about anything**, so its headline capability is untested on the real tree. `--record` is
explicitly the wrong tool on a tree this red: it would freeze today's state as the baseline.

---

## WHAT I COULD NOT MEASURE

- **No second full tree-verdict run.** The isolated run took 58 minutes and a concurrent
  agent's runs were mid-flight the whole time; a second full pass would have overlapped
  their writes again. Row-count stability is covered by one.sh's own 6-attempt agreement
  *within* the run (**0 unstable files**), not by two whole sweeps.
- **No whole-tree rebase-gate re-run.** The re-check was per-port on the four BROKEN ones,
  which is where a re-run would have differed. The 46 NOT-STARTED were not re-checked.
- **`rebase-gate.py` runs `rebase-plan.py` under a hardcoded bare `python3`**, not
  `sys.executable`. Harmless today (verified: `rebase-plan.py` imports nothing from
  `tinygrad` — 0 hits), but it is the same latent coupling as §0.
- **Two other agents were editing `tinygrad/**` throughout.** Files rewritten inside my
  measurement windows: `codegen/__init__.bend` (19:34, 19:57), `nn/state.bend` (19:35,
  19:38), `renderer/amd/generate.bend` (20:16), `codegen/decomp/dtype.bend` (20:05),
  `schedule/memory.bend` (20:23). Any number below whose file sits in that set is a
  timestamped snapshot, and I say which.
- **Not measured at all:** `wire-rows.py`'s 22 and `wire-pair.py`'s `ops_cpu` figures, and
  the 34-briefing claim of "8 of 31 wired gates BROKEN on every run". Those gates are not
  in scope for this task and I did not re-derive them. What I *did* find is that the
  mechanism behind that claim — an unimportable `tinygrad` — is real under the wrong
  interpreter and produces exactly that shape of result.

**Nothing committed.** Scratch lives in
`/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/state-audit/`.
Written: this file, `.agents/slop/state-audit.py`, and an append-only block at the end of
`.agents/slop/notes/bend2-constraints.md` (now at positions **15230–15313**; three later
blocks are appended after mine by other agents, positions cited above are still correct).

**I did not tick this unit off in `.agents/TODO.md`,** because the task brief scoped my
writes to `state-audit.py`, its report, and the notes append. `jj status` confirms **no
`tinybendygrad/**` or `tinygrad/**` file is mine** — the three shown modified
(`codegen/decomp/dtype.bend`, `renderer/amd/generate.bend`, `schedule/memory.bend`) carry
mtimes inside other agents' edit windows (20:05:52, 20:16:27, 20:23:43) and I only ever
read them.

**Self-audit:** all 16 headline numbers in this report were re-checked against the raw
artifacts programmatically after it was written; 16/16 match.
