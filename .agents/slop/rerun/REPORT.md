# rerun report — `checks/differ.py run`

Run: `./.venv/bin/python checks/bounded.py --seconds 3000 --mb 2048 -- ./.venv/bin/python checks/differ.py run`
→ `[bounded] WITHIN-LIMITS rc=1 peak-RSS=789 MB (ceiling 2048) 173s`. Exit 1 comes from
`differ.py`'s own verdict (`RUN INCOMPLETE` 5 unset + `RUN WRONG expect-moved=1`), NOT from the
watchdog. No other `bend` was running.

## 1. disagree-gate

`./.venv/bin/python checks/disagree-gate.py` → rc=0, **"5 disagreements pinned, 0 failure(s)"**,
all four lanes `ok` (PIN, CITATIONS, COVERAGE ARTEFACTS, PLANT + DISARM).
The fresh summary reads **`graphs-disagree=5`**, matching `len(PIN)=5` — the stale
`graphs-disagree=6` and the `loop` row are gone from `runs/graphcmp/D/D0-run-summary.txt`.

## 2. env rows + preconds + retention

Four new rows, as written by `cmd_run` into `D0-run-summary.txt`:

```
dev=CPU
lc_all=C
noopt=0
pythonhashseed=0
```

`checks/env-precond.py --check` → **rc=1, still failing**, but differently: METHOD B is now
all `ok` (`dev=CPU`, `pythonhashseed=0`, `noopt=0`, `lc_all=C` against the declaration) — the
`dev=` REFUSAL is gone. METHOD A fails: `MISSING .agents/slop/graphcmp.py:1800 lacks
PYTHONHASHSEED,NOOPT`. Owner: `.agents/slop/graphcmp.py:1800`, not this unit.

`gates/retention-check.py` CLAUSE IV fires with **4 complaints** (was 6):
`expect-moved=1` (expected 0), `graphs-agree=20` (expected 19), `byte-identical=20`
(expected 19), `selfcheck=# SELFCHECK: FAIL` (expected `# SELFCHECK: OK`).
The `oracle-selfcheck` and `census-rc` complaints are gone. It does **not** drop to 2.
Both remaining red families trace to the same stale pin: `checks/differ.py:136` still has
`"loop": "DISAGREE"` while the port now emits `loop: VERDICT=AGREE` — so `expect-moved=1`,
agree/byte-identical each +1, and the `selfcheck` lane that counted `?`=2 on `loop`'s CALL
now reads `?=0` and prints `# SELFCHECK: FAIL`.

## 3. `late` — census vs canon on the FRESH artifacts

- Census TOTAL is **312** (`# TOTAL: 25 graphs, 312 nodes per side`), and the 25
  `D2-canon-py-*.txt` files sum to **312** (`cat … | grep -c ""` = 312). Gap closed.
- Census `late` row: `late 12/18 BAD … [PY-BEND OPs DIFFER: ['CMPEQ', 'FDIV', 'GROUP', 'MUL',
  'NEG', 'PERMUTE', 'REDUCE', 'SUB']]`. `RECIPROCAL` is **gone**; `FDIV` is present, as
  `g_late` builds (`graphcmp.py:1465` `(a / b).uop`).
- `D2-canon-py-late.txt` = 12 lines, ops `{ALLOC, CMPEQ, CONST, FDIV, GROUP, NEG, PERMUTE…, RESHAPE, STACK, SUB}`; `OPS REACHED: py=9 bend=7` in `D1-graph-late.txt` — the same graph, same op set the census's sorted list implies.
- The differ lane's two rung-crossrefs name the same unmatched nodes (`RESHAPE py#7 vs bend#12`, `ALLOC py#6 vs bend#9`) — a SUBSTITUTED-fixture harness artefact, consistent with `SUBSTITUTED=("allred","cdiv","late","matmul")`.
- `checks/disagree-gate.py` rc=0 ⇒ belts agree: **`late` row=6, fields=(dtype, shape, arg)** — unchanged by the fresh run. The RECIPROCAL/FDIV split the brief measured was an artefact of the stale directory; on fresh artifacts census and canon name the same graph, so **the `PIN` row did not move and no repin is needed**.

## Other asked-for facts (fresh run)

- Disagreement set (5): **allred, cdiv, flip, late, lin**. Disagree-gate lists the same five.
- `expect-moved=1`: **loop** — `VERDICT=AGREE EXPECTED=DISAGREE` (stale `WANT` row, `checks/differ.py:136`; fix is the orchestrator's).
- `oracle-selfcheck=# ORACLE SELFCHECK: OK` and `census-rc=rc=0` — both fixed, both green.
- `selfcheck=# SELFCHECK: FAIL` — its `?`-ledger claim over `loop`'s CALL is stale (`?=0` on loop, sym's wall closed).
- `lin`: still **`VERDICT: DISAGREE`**, with SHARED cores=45 of 46 — its SINK `py#46 vs bend#46`, `arg py=kI(sr_4_5_3,n(Opt(op=EOptOps.SPLITaxis=i2arg=n(i0,XUPCAST))),N,i0) bend=kI(sr_4_5_3,n(q),N,i0)`. The `OPT`-in-`postrange.bend` + opts-renderer fix is NOT in.
- `graphs=25, graphs-answered=20, graphs-unset=5, byte-identical=20,
  stable-pairs=5 of 5, plants-disagree=7 of 7, cross=1 of 1, conflations=4 of 4,
  controls=5 of 5`.
