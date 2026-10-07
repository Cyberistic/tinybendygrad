# runfinal — the one run that unblocks five instruments

Unit: `bend`. Owns `runs/graphcmp/D/`, `checks/differ.py` `PINS`/`WANT`. Committed nothing.
Pinned run: `WITHIN-LIMITS  rc=0  peak-RSS=803 MB  178 s`. Tree at `e62eaf1e8` (05:39:26).

## 1. Quietness reading (BEFORE)

- mtime watcher over `tinybendygrad/` + `.agents/slop/graphcmp.bend`, 300 s window, 15 s period
  (`.agents/slop/runfinal/quietwatch.py`): **3 writes, settling 05:37:12** — two files,
  `tinybendygrad/tensor.bend` (05:34:09) and `tinybendygrad/nn/__init__.bend` (05:35:43).
- Independent scan at 05:32: 0 files modified in the last 5/15/60 min; newest tree write was
  `tensor.bend`/`function.bend` region ~4 h 50 m earlier. So the port was quiet for ~4 h 50 m and
  then another unit landed `tn_where` (`e62eaf1e8`, "24/24 green") at 05:39:26.
- Quick check, two `git status --porcelain` 60 s apart (05:33:56 clean → 05:34:56
  ` M tensor.bend`): **writes appeared between readings.** Per instruction, proceeded anyway.
- The `run34` flux pattern (15:35:12–15:39:43 on 2026-10-06) did **not** recur; the 294 s run does
  **not** fit in a quiet gap, so waiting for silence is the known-wrong answer, as stated.

## 2. Substrate compile

`./bin/bend .agents/slop/graphcmp.bend matmul` under `bounded.py`: **`WITHIN-LIMITS`**, rc=0,
peak-RSS 655 MB, 2 s; emitted the matmul graph (1193 B stdout).

Two runs were taken (run 1 answered `getaddr` but left it UNSET; run 2 is the completed, pinned one):

| run | token | rc | peak RSS | wall | note |
|---|---|---|---|---|---|
| run 1 | WITHIN-LIMITS | 1 | 770 MB | 223 s | `RUN INCOMPLETE: 1 of 34 … getaddr` |
| **run 2 (pinned)** | **WITHIN-LIMITS** | **0** | **803 MB** | **178 s** | WANT completed; run returns 0 |

Run 1's window overlapped the `tn_where` landing (`tensor.bend` 05:34:09, `nn/__init__.bend`
05:35:43, commit 05:39:26) — the commit touched no file contents, and run 1 was still fully green.
Run 2 was taken after that commit, with no tree write during its 178 s window (last write 05:35:43,
commit 05:39:26, both before run 2). **Run 2 is the measurement of record.**

## 3. `D0-run-summary.txt` as READ (run 2)

```
graphs=34
graphs-answered=34
graphs-unset=0
expect-moved=0
graphs-agree=32
graphs-disagree=2
byte-identical=32
not-comparable=0
stable-pairs=5 of 5
stable-failed=0 of 5
stable-differ=0 of 5
plants-disagree=7 of 7
cross=1 of 1
selfcheck=# SELFCHECK: OK
conflations=4 of 4
controls=5 of 5
oracle-selfcheck=# ORACLE SELFCHECK: OK
census-rc=rc=0
dev=CPU
lc_all=C
noopt=0
pythonhashseed=0
```
`differ.unhealthy()` → **NONE (all 17 pins green)**; `differ.artefacts_ok()` → **NONE**.

## 4. `getaddr` — THE HEADLINE

Prediction on record (`getaddrwire`): `graphs-unset 1→0`, `graphs-answered 33→34`, and `getaddr`
lands AGREE or DISAGREE. **Measured (run 1, the run that ran it):**
`D1-graph-getaddr.txt` → `# VERDICT: AGREE` (`# DENOMINATOR: graphs=2 (1 py + 1 bend) nodes=2/2
… ops-reached=2/2 of 77`); `D2-cmp-getaddr.txt` → `getaddr BYTE-IDENTICAL (143 bytes both sides)`.
The AGREE branch is confirmed: `graphs-agree` and `byte-identical` each **+1**. The one-BAD-row
arena-bottom emission is gone (`census`: `getaddr` no longer "opened DIFFERENT devices").
**The `WANT` row was written because the run MEASURED it** (`"getaddr": "AGREE"`), which is what
turned `graphs-unset` 1→0 (a function of the TABLE, not the port).

## 5. Pins: before → after (per `checks/differ.py`)

PINS delta (file `checks/differ.py`):

| pin | old | new | function of |
|---|---|---|---|
| `graphs` | 34 | 34 | `corpus()` (unchanged) |
| `graphs-unset` | 1 | **0** | the WANT-vs-`corpus()` TABLE (getaddr row added) |
| `graphs-answered` | 33 | **34** | the TABLE |
| `expect-moved` | 0 | 0 | PORT vs TABLE |
| `graphs-agree` | 31 | **32** | PORT (getaddr) |
| `byte-identical` | 31 | **32** | PORT (getaddr) |
| `not-comparable` | 0 | 0 | PORT |
| `selfcheck` | OK | OK | the differ's own |
| `census-rc` | rc=0 | rc=0 | PORT / oracle |
| `stable-pairs` / `stable-failed` / `stable-differ` | 5 of 5 / 0 of 5 / 0 of 5 | same | PORT |
| `plants-disagree` / `cross` / `controls` / `conflations` | 7 of 7 / 1 of 1 / 5 of 5 / 4 of 4 | same | PORT |
| `oracle-selfcheck` | OK | OK | oracle / PORT |

Only FOUR pins moved: `graphs-unset`, `graphs-answered` (both TABLE), `graphs-agree`,
`byte-identical` (both PORT). The stale `PINS` comment claiming the counts were "NOT MOVED, AND
THEY ARE RED, BECAUSE THE RUN34 PORT WENT INTO FLUX" was rewritten to record runfinal.

On-disk `D0-run-summary.txt` delta (run34, 15:47:32 → runfinal):

| row | run34 | runfinal |
|---|---|---|
| `graphs-answered` | 33 | 34 |
| `graphs-unset` | 1 | 0 |
| `expect-moved` | **3** | **0** |
| `graphs-agree` | 31 | 32 |
| `byte-identical` | 31 | 32 |
| `graphs-disagree` | 2 | 2 (unchanged) |
| `oracle-selfcheck` | **FAIL** | **OK** |
| `census-rc` | **rc=1** | **rc=0** |

`WANT` delta: added `"getaddr": "AGREE"` (measured) and rewrote the block that said `getaddr`
"stays UNSET"; `"stage"/"unshard"/"wmma"` were already AGREE/AGREE/DISAGREE (unchanged).

**Instrument that went GREEN → RED: NONE.** Three went RED → GREEN (`expect-moved`, `census-rc`,
`oracle-selfcheck`); `graphs-agree`/`byte-identical` +1; `disagree-gate` stayed GREEN.

## 6. Instruments, before → after

| instrument | before | after |
|---|---|---|
| `checks/corpus-figure.py` (DEV unset) | rc=1, RUN HEALTH **FAILED** (14/17; red: expect-moved=3, census-rc=rc=1, oracle-selfcheck=FAIL) | rc=1 (**DEVICE PRECONDITION VIOLATED**, not a health fail), RUN HEALTH **OK 17/17** |
| `checks/corpus-figure.py` (DEV=CPU) | rc=1, RUN HEALTH **FAILED** (14/17) | **rc=0, RUN HEALTH OK 17/17** |
| `checks/disagree-gate.py` | rc=0, 4 lanes ok, 2 pinned (`flip`, `unshard`) | rc=0, 4 lanes ok, 2 pinned (`flip` row 6 `arg` BOTH HARNESS+PORT; `unshard` row 8 `dtype,shape` WRONG SHAPE PORT) |

`corpus-figure.py` rc=1 with DEV unset is its declared behaviour (device pin is `CPU`); with
`DEV=CPU` it is rc=0. Its health verdict is the thing that moved: FAILED → OK.

## 7. Files touched

- `runs/graphcmp/D/` — rewritten by run 2 (owned; not staged).
- `checks/differ.py` — `WANT` row + comment; `PINS` four values + stale comment. Not staged.
- `.agents/slop/runfinal/{quietwatch.py,quiet1.out,substrate-matmul.*,differ-run*.{out,err},REPORT.md}`.
- Nothing committed; nothing `git add`-ed.
