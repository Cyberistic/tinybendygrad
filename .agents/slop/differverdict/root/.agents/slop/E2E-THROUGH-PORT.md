# E2E-THROUGH-PORT — the artifact's one executable artifact, running the matmul **through** the port

`.agents/slop/e2e.sh` stage 6. **ADDED. Stages 1–5 are byte-unchanged** (lines 1–121
`sha256 86c465e9…` before and after) and stage 4's verdict is still the script's exit
status. Measured, 2026-10-04, on bend 2.0.35.

```
./.agents/slop/e2e.sh        ->  PASS        (96 s wall, of which ~60 s is stage 6)
zsh .agents/slop/e2e_port/run-port-mm.sh  ->  0        (runnable on its own)
```

---

## 1. WHICH STAGES ARE EXECUTION THROUGH THE PORT, AND WHICH STILL ASK NODE

| stage | what it does | a device? | execution or text |
|---|---|---|---|
| 1 `oracle` | `e2e_mm.py`, CPython tinygrad `DEV=CPU` | no | **the EXPECTATION**, not an execution |
| 2 `port (pure)` | `bend e2e_mm.bend` prints a program | no | **TEXT** |
| 3 `gpu` | `node e2e_mm_run.mjs`, headless Chrome, `navigator.gpu`, `apple/metal-3` | **YES — ASKS NODE** | **EXECUTION**, not through the port |
| 4 `gate` | `e2e_mm_gate.py` diffs two recorded texts | no | **TEXT** |
| 5 `ops_bend` | `opsbend-milestone.sh`, the port's own runtime | no | **EXECUTION** — one f32 add over 3 scalars |
| **6 (new)** | **`cstyle.bend`'s `render_kernel` → `cc` → link → Bend launches the kernel by pointer** | **no** | **EXECUTION — 64/64 u32 words of `(A@B)@Cm`** |

**The single number: stage 3 is the only stage that asks Node for a device, and it is
still there, unchanged, because stage 6 was added and not substituted.** Stages 5 and 6
are execution through the port. Nothing else is. The header above is printed by the
script itself (`run-port-mm.sh`, the `WHERE EACH STAGE GETS ITS DEVICE` block) so the
artifact cannot be read as stronger than it is.

## 2. THE 64/64, FROM A CLEAN RE-RUN

Two measurements of the same fact, by different code:

```
lane (python list compare, inside portexec/run-kernel.sh STEP 6):
   equal  : True   diff bytes: 0   (64/64 words)

stage 6 (awk field extraction, then the external diff, byte-counted -- NOT read out
         of the lane):
   words port=64  CPython=64  differing lines=0  diff bytes=0
   first 8 port   : 1044381696 1079115776 1050148864 3231514624 1088487424 3221946368 1048576000 1091551232
   first 8 CPython: 1044381696 1079115776 1050148864 3231514624 1088487424 3221946368 1048576000 1091551232
```

**diff bytes: 0.** Both runs ran twice and the `WORD` lines were `cmp`-identical; the
buffer `Nat`s were distinct within the process and differed between the two runs (ASLR),
so no address is compared to a constant. The four steps are named separately by
`run-kernel.sh` and were all `ok`: `bend -o` 159,801 B (shim inlined at line 5650),
`cc` on the port's kernel alone with `-Wall -Werror` → 1,240 B object and **zero
warnings**, `cc` on bend's `run.c`, LINK, RUN.

The expectation is `runs/e2e/e2e-mm-oracle.json`'s `answer_u32` — `e2e_mm.py`'s own
record — **read, never recomputed**. If it is absent stage 6 **refuses** (exit 3) rather
than substituting a matmul of its own, because a self-computed expectation would make
"matches CPython" a comparison against a different program.

## 3. EXECUTION vs TEXT, WITH THE DENOMINATOR

Counted every run by `coverage.py`, which imports `portexec/census.py`'s own
`classify` and hands every row to `cc`:

| | rows | share |
|---|---:|---:|
| **rows in the port's own stdout — THE DENOMINATOR** | **227** | 100.00% |
| TEXT ONLY — a fragment, not a translation unit | 216 | 95.15% |
| C source — a `void N(...)` signature and a body | 11 | 4.85% |
| …of those, `cc` **accepts** on this machine | 6 | 2.64% |
| …of those, `cc` **rejects** | 5 | 2.20% |
| …**EXECUTED** here and compared against CPython | **1** | **0.44%** |
| kernels executed that are **NOT** among those 227 | 1 | — |
| **STILL TEXT: 226 of 227 (99.56%)** | | |

**The correction this stage makes to the artifact's own prose.** `portexec/README.md:50`
tabulates `1` executed row *plus* `1` kernel "NOT among the 227 rows", and then
`README.md:53` writes **"2 of 227 rows have been executed. 225 are still text-only"**.
That is a denominator error of one: the second kernel is not one of the 227. The
correct sentence is **1 of 227 rows (0.44%), 226 of 227 still text, plus one executed
kernel outside the set.** `coverage.py` prints the out-of-set row with no percentage for
exactly that reason. Reported, not fixed — `portexec/` is committed and not this unit's.

## 4. THE NEGATIVE CONTROLS ACTUALLY RUN, AND WHAT EACH TURNED RED

**7 plants. All 7 red. 4 are this stage's; 3 are inherited from `run-kernel.sh`, which
runs its own inside every lane and which I do not re-count.** A control that fell over
instead of answering wrongly would be reported as **NOT A CATCH** — a crash is not a red
row (`e2e_negctl.sh:168`; `nv_nvdev_gate.py` hid 15 disagreements behind a traceback).

| | plant | result | what it turned red |
|---|---|---|---|
| **C0** | none — **the copy, unmutated, must be green** | GREEN | *without this the four below prove nothing* |
| **C1** | **THE PORT**: `cstyle.bend:1363` `buftypes.go` accumulates at the head, so `render_kernel` emits the buffers reversed | **RED** | `MISMATCH at 64/64 words`. The evidence is in the output: `PORT PROTOTYPE : extern void mm(float* restrict data3_4, …, float* restrict data0_4)`, `SHIM CALL : data3_4, data2_4, data1_4, data0_4`, and every one of the 64 words is `0` — the kernel wrote into the wrong buffer |
| **C2** | **VACUITY**: the second dot reads `data1_4` instead of the local `tmp`, so the kernel computes a *real* matmul `A@C` | **RED** | `MISMATCH at 64/64 words`, 64 non-zero wrong words. 64 real multiply-adds still executed — so this is not "no kernel ran", it is **"the wrong computation ran and was not accepted"** |
| **C3** | **THE EXPECTATION**: one bit of word 37 of the 64 answer words in the copy's oracle record | **RED** | `MISMATCH at 1/64 words, first 5: [(37, 3243163648, 3243163649)]` — **index 37 and no other**, so the comparison is positional over all 64 and reads the record |
| **C4** | the same C1 port plant on lane A's **one-input** row `kern2 CLANG` | **RED** | `MISMATCH at 1/4 words`, word 0 → `0`. **I predicted this would be a THEOREM and was wrong** — see §6 |
| i1 | kernel: the first dot's 8 taps become 7 | RED | inherited |
| i2 | bend program: fill B into A's buffer | RED | inherited |
| i3 | shim: never call the kernel | RED | inherited |

`C1` is the one nobody had run for **any** execution lane: `e2e_negctl.sh`'s NC3 mutates
the port for the *WebGPU* lane, and no CPU-backend execution lane had a port plant. It
is the same `List.append(a, A, xs, ys) IS xs ++ ys` rule the notes have carried since
position 1824 — with a compiler attached, and with the port's own output as the witness.

## 5. DOES THIS STAGE TOUCH THE UNFALSIFIABLE `kern2 alu` PAIR? — **NO**

**It does not, and I am counting neither row.** Said loudly here and in the script's own
output:

* the pair is `cstyle.bend:2367-2368`, which pair an ALU signature
  (`void E_4(const float alu0_1, const float alu1_1)`) with the `g_kernel()` body at
  `cstyle.bend:1878-1879`, which names `data1_4`/`data0_4` →
  `cc: error: use of undeclared identifier 'data1_4'`;
* **`renderer_oracle.py:563-565`** hands upstream the *same* mismatched pair
  (`B(alu=True)`, `renderer_oracle.py:516-522`), so both lanes of the text gate agree on
  a string no compiler has ever accepted. *(The hand-off I was given cites
  `renderer_oracle.py:551-552`; the rows are at **563-565** and the ALU-buffer builder at
  **516-522**. 551-552 is the `vol` pair. Same finding, wrong position.)*
* **stage 6's executed kernel is `emit-mm.bend`'s four-buffer `mm`, which is NOT one of
  the 227 rows**, so it has no `py=` twin to agree with it. The `alu` pair cannot be
  involved in its arithmetic.
* stage 6's *only* use of the 227 rows is `kern2 CLANG`, which `cc` accepts and which is
  in the 6 — and the coverage table reports the pair's `cc` message verbatim rather than
  counting them.

## 6. FINDINGS, REPORTED NOT FIXED (every one of these files is held by a live unit)

1. **`portexec/README.md:53` — "2 of 227 rows have been executed. 225 are still
   text-only."** The denominator error of §3. `1 of 227`, `226 of 227`.
2. **`portexec/STAGE3.md:98-101`** — *"Unlike Stage 2, **no aliasing plant is a theorem
   here**: … the same slot-swapping plant does turn it red … and that is the plant used
   for `mm`."* **No aliasing plant is in `run-kernel.sh`'s `mm` list** (`:204-224` has
   tap-count, fill-target and skip-call). The claim that it was used is not true of the
   script.
3. **`census.py:54`** truncates the first `cc` stderr line to 90 characters, and on this
   machine that line is all temporary path — so `census.py`'s "first rejection message"
   column prints `.../kern2_BASE_alu.c:3:31: er` and no message. `coverage.py` strips the
   `path:line:col:` prefix instead, which is why §5 has the real text.
4. **THE `ALu` ROWS' POSITION** — `renderer_oracle.py:563-565`, not `:551-552`.
5. **`bend2-constraints.md`'s INDEX says line positions are "unique and stable — cite
   those until this is renumbered".** They have drifted: the index points `List.append`
   at 1590, and 1590 is `def f.b(...) MUST BE DECLARED BEFORE def f.a(...)`; the rule is
   at **1824**. Positions are no more stable than the numbers, and the index's own claim
   is the thing that decayed.
6. **`cstyle-gate.py:552-554` prints `!! CAPTURED LANE INPUT. Not a live run.`** and then
   builds both lanes from `CompletedProcess([], 0, …read_text(), "")` when
   `--port-stdout` is given. So the 227-row gate has a mode where its own verdict is about
   a *capture*. Nothing in stage 6 depends on it; it is why §3's denominator is stated as
   "text" without further qualification.

## 7. WHAT THIS STAGE PROVES, AND WHAT IT DOES NOT

**Proves, on this machine, in this run:**

* the port's `render_kernel` signature assembly — the kernel typedef, the `restrict`
  suffix, the buffer types, the `void` return, the braces and the framing — is C a
  compiler accepts with `-Werror` and **zero warnings**, and a machine executes;
* the shim's ABI is the port's, derived by **parsing** the port's own emitted text, so
  the port and the harness cannot agree by accident;
* **64 u32 words of `(A@B)@Cm` come back bit-identical to `e2e_mm.py`'s CPython answer
  through `bend -o` → `cc` → link → run, with no Node, no browser, no `navigator.gpu`
  and no tinygrad Python scheduler in the execution path**;
* 1 of the port's own 227 gate rows (`kern2 CLANG`) is now execution rather than text,
  measured in this run rather than quoted from a prior commit;
* the lane listens to **the port** (C1, C4), to **the fixture's arithmetic** (C2), and to
  **the expectation and its positional comparison** (C3).

**Does NOT prove, and is not claimed:**

* that the port **scheduled** this matmul. **The kernel body is a fixture** —
  `emit-mm.bend`'s literals, exactly as `g_kernel()` at `cstyle.bend:1878` is a literal.
  `cstyle.bend` has **no `_render`**: nothing in the port turns a UOp list into lines,
  and `cstyle.bend:49` names the wall — `Ops.SHRINK` has no dtype in `fold.bend`, so
  `F.fold.dt` answers `None` and `render_type`, which every emitted line needs, cannot be
  driven from a graph. **That wall is `fold.bend`'s to move.**
* that stage 5's wall moved. There is **still no Bend-emitting renderer**; the renderers
  emit C, PTX, WGSL, LLVM IR and NIR. Stage 6 does not need one: the render side emits C
  as it always did, `cc` compiles it, and **Bend is the driver**. The mechanism is
  upstream's own CPU backend (`ops_cpu.py:29-72`), not an invention.
* anything about a **GPU**. Stage 6 is the CPU backend. Stage 3's WebGPU result is
  untouched and still the only GPU evidence.
* anything about the other **226** rows. They remain text.

## 8. THE FAILURE DISCIPLINE, AND HOW IT WAS TESTED

* **SUBSTRATE ≠ a verdict.** A row count under 220 prints the port's **own stderr** and
  names the state `SUBSTRATE`, on every lane *and every control* — a substrate break
  inside a control would otherwise wear the costume of a successful catch. The precedent
  is `run-kernel.sh:51-66`, where "port produced 0 rows in 8 attempts" was a concurrent
  agent's edit to `helpers.bend:2551`.
* **A failure names its step.** `bend -o`, `cc` on the kernel, `cc` on `run.c`, LINK, RUN
  and COMPARE are each a numbered STEP, and a plant that does not apply says
  `VACUOUS PLANT` with the count rather than passing quietly (`plant.py`).
* **Nothing in the live tree is edited.** `tinybendygrad` is copied to `$TMPDIR` with the
  relative layout the `.bend` imports need, and `bin/ references/ tinygrad/ .venv/` are
  symlinked — `e2e_negctl.sh:44-56`'s shape. The copy is rebuilt for **every** control, so
  no control can inherit the previous one's break (`e2e_negctl.sh:125` measured that
  failure mode). One line of the copy's `run-kernel.sh` is rewritten, the `ROOT=`
  constant, because without it every plant would be planted in a file nothing reads.
* **Stage 6 cannot retract a green matmul.** Measured, not asserted: with
  `run-port-mm.sh` renamed away so that stage 6 could not run at all, `e2e.sh` printed
  `mm_e2e_failed=0 / PASS`, `STAGE 6 FAILED`, `--- the script's exit status is STAGE 4's:
  PASS ---` and **exited 0**. The only `*rc` the appended block assigns is `psrc=$?`
  (`e2e.sh:152`); the exit is still `exit "$rc"` (`e2e.sh:161`).

## 9. FILES

| file | what |
|---|---|
| `.agents/slop/e2e_port/run-port-mm.sh` | the stage: two lanes, the recomputed diff, the controls, the two tables |
| `.agents/slop/e2e_port/coverage.py` | the execution-vs-text table with the denominator, and the `alu` warning |
| `.agents/slop/e2e_port/plant.py` | one textual mutation, refusing a vacuous one |
| `runs/e2e/e2e-port-mm.txt` | the artifact this stage writes; `runs/e2e/e2e-negctl.txt` is the model |
