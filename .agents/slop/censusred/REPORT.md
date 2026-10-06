# THE CENSUS RED — `graphcmp-oracle.py`, 2026-10-07

**HEADLINE: `# ORACLE SELFCHECK: OK` AND `rc=1` DO NOT COEXIST. THE BRIEF'S QUOTE IS STALE.
MEASURED TWICE TONIGHT (a committed artifact and a fresh 35 s run): the token reads `FAIL` and
the exit reads `rc=1`, AND THEY AGREE. The red was REAL — the bend `getaddr` arm emitted the
arena bottom `BAD/NOOP` where CPython emits two nodes — and the exit was RIGHT to be red. The
only liar was the narrative, written twice: a commit message that claims `getaddrfix` landed a
change its own `--stat` does not contain, and a `WHOLE` derivation that declares "the set is
asked of it by path" and then asks nobody. Both are now closed; the census is `rc=0`,
`# ORACLE SELFCHECK: OK`, reached set `DENOSXabcfiklrsw` (16).**

Instrument: `env -u PYTHONPATH LC_ALL=C .venv/bin/python .agents/slop/graphcmp-oracle.py`,
the module's own docstring invocation. Every reading below carries the command that produced it.

---

## 1. THE EXIT CODE'S ACTUAL WRITER — every path, and which one fired

`grep -n 'sys.exit\|SystemExit\|return 1\|rc=' .agents/slop/graphcmp-oracle.py`:

| file:line | path | can it set non-zero? |
|---|---|---|
| `graphcmp-oracle.py:452` | `return 0 if not bad else 1` | **YES — the only `bad`-driven writer** |
| `graphcmp-oracle.py:456` | `sys.exit(main())` | passes 452's value out |
| `graphcmp-oracle.py:137` | `raise SystemExit("graphcmp.py declares no --dev default…")` | YES, refusal |
| `graphcmp-oracle.py:237` | `raise SystemExit("tinygrad is already imported…")` | YES, refusal |
| (any) | an uncaught exception after import | YES, traceback → exit 1 |

**A single writer decides the census exit: `bad`.** 14 `bad.append` sites feed it (§6). The two
`SystemExit`s and the exception path never reach the token print at all.

**WHICH ONE FIRED, MEASURED (fresh run, output in `red-before.out`):**

```
  getaddr     2/1   BAD    2     DSbis      2      1  0/0  ?,BAD  [PY-BEND OPs DIFFER: ['ALLOC','GETADDR','NOOP']]
# ORACLE SELFCHECK: FAIL
#   getaddr: the two sides opened DIFFERENT devices -- py ['sCPU'] against bend [] ...
#   unmapped arg atom letters: B
rc=1
```

So line 456 → 452, `bad` = 2 elements. TWO independent asserts fired:

1. **`:274` device mismatch** — `py['devs']=={'sCPU'}` against `bd['devs']==set()`. Real: the
   bend arm produced one `BAD` row with no `PARAM`, CPython produced `ALLOC`+`GETADDR`.
2. **`:311` unmapped arg atom `B`** — the scanner read the whole marker `BAD` as the letter `B`.

**Both trace to ONE root cause in the port probe, already diagnosed in prose and never landed.**

---

## 2. `census-rc` AND `oracle-selfcheck` AS THE TWO INSTRUMENTS READ THEM

`checks/differ.py:254` pins `"census-rc": "rc=0"`; `:272` pins
`"oracle-selfcheck": "# ORACLE SELFCHECK: OK"`. `differ.py:607-608` derives them from
`runs/graphcmp/D/D0-coverage-census.txt`: `oracle-selfcheck` = the grep of the token line,
`census-rc` = `last_line(...)` = the `rc=<code>` that `differ.py:544`'s `capture(..., stamp_rc=True)`
**stamps from the subprocess return code** (the oracle itself never prints `rc=`).

The live artifact `runs/graphcmp/D/` (taken 2026-10-06 15:47) reads exactly what the pins forbid:

```
$ tail -1 runs/graphcmp/D/D0-coverage-census.txt
rc=1
$ grep census-rc\|oracle-selfcheck runs/graphcmp/D/D0-run-summary.txt
oracle-selfcheck=# ORACLE SELFCHECK: FAIL
census-rc=rc=1
```

`checks/corpus-figure.py:186-201` imports all of `differ.PINS` and compares them to that summary,
so it would print `RUN HEALTH : FAILED` naming both. **Both facts are red, and they are red in the
SAME direction and from the SAME invocation.**

**CAN THEY DISAGREE? YES — and the divergence is not hypothetical.** They are one token and one
exit from one run, and they agree whenever `main()` RETURNS, because 452 derives both from `bad`.
They diverge exactly when `main()` never returns: the two refusals, or an exception, exit non-zero
with **no** `# ORACLE SELFCHECK` line at all — a token that is ABSENT, not `FAIL` and not `OK`.
Demonstrated live (`refusal_plant.py`, the `:237` lane):

```
refusal rc=1
token lines: 0
stdout bytes: 0
stderr: tinygrad is already imported, so `DEV` can no longer choose this census's device...
```

`census-rc=rc=1` over `oracle-selfcheck` **ABSENT** is a state `differ.py`'s pins cannot express,
because `oracle-selfcheck` would then read `""` (grep miss) — not pinned, and not a value. The two
are pinned as if they were one fact; they are two facts that share a value only on the happy path.

---

## 3. WHICH SIDE LIES

**Neither the token nor the exit. `FAIL` is TRUE and `rc=1` is TRUE; the census was correctly red
over a real bend defect.** The brief's `# ORACLE SELFCHECK: OK` does not reproduce — it is from a
tree state that no longer exists (the `DENOSXabcfiklrsw`/16 reached set in the brief is exactly
the post-getaddr-fix state; the live tree had reverted the getaddr arm to the pre-new arena).

The two things that were actually lying, both by DECLARING a fix that the code does not contain:

- **`graphcmp.bend:1352`** — current source passed the **pre-`UOp.new`** arena:
  `O.UOp.getaddr(O.Arena.budget(ar), ar, O.Found.i(a0), S.D1{0})`. `Arena` is immutable;
  `UOp.new.of` returns `Found{made, ..}` (ops.bend:2657), so `Found.i(a0)` indexes `Found.ar(a0)`
  and is out of range in `ar`. `Arena.node` is TOTAL and answers the bottom (ops.bend:1344-1348),
  so `peel` saw `NOOP`, `getaddr.go` took the `False` arm and returned `self` unchanged, and the
  graph was the single `2:i1 4:NOOP ... 3:BAD` row. Commit `00b1015749d3b4e4470e2659e3cff95a8c8ce34c`
  describes this fix in full and its `--stat` shows **only** `tinygrad/tensor.bend`,
  `gates/tn_sin_log2_exp2_rsqrt.bend`, and the two `.agents/slop/censusred/` artifacts. The
  landing was reported and not performed.
- **`graphcmp-oracle.py:40`** — `WHOLE = tuple(m for m,_,_,_ in G.LEDGER if m not in set(G.ATOMS.values()))`
  was added (4ff8ca126) with a comment saying "the set is asked of it by path", and **`WHOLE` was
  referenced nowhere else** (`grep -n WHOLE` → definition only). `atoms("BAD")` still answered `{B}`.

---

## 4. THE FIX, ON THE LYING SIDE, TO `rc=0`

Two edits, each on the side that was lying:

1. **Oracle scanner (`graphcmp-oracle.py:85`)** — the token walk now consults the generator's own
   declaration: `... and arg[i:j+1] not in WHOLE`. A declared whole marker (`BAD`) is no longer
   read as its first letter. This is not silencing: the SAME broken bend arm still exits `rc=1`
   via the `:274` device-mismatch assert (proved in §5).
2. **Port probe (`graphcmp.bend:1352`)** — thread the arena `UOp.new` returned:
   `+a1 = O.Found.ar(a0)` then `O.UOp.getaddr(O.Arena.budget(a1), a1, O.Found.i(a0), S.D1{0})`.
   After this, the bend and py rows are byte-identical.

Locked with a NEW selfcheck (`graphcmp-oracle.py:340`), because once `getaddr` is green no live
graph emits `BAD`, so the exclusion would otherwise be a check with no fixture:

```python
if atoms("BAD") != set():
    bad.append(f"the whole marker `BAD` is read as an atom letter: {sorted(atoms('BAD'))}")
```

**GREEN, MEASURED (`run.out`):** `rc=0`; `# DISTINCT ARG ATOM LETTERS REACHED: DENOSXabcfiklrsw
(16 distinct = 10 atom letters + 6 composite-form prefixes; …: none)`;
`getaddr 2/2 ok`; `# ORACLE SELFCHECK: OK`.

---

## 5. THE PLANT — BOTH STATES, SHOWN

**RED (corpus):** revert only the bend arm to the pre-`UOp.new` arena (`plant-red.out`):

```
  getaddr     2/1   BAD    2     DSbis      2      1  0/0  ?,BAD  [PY-BEND OPs DIFFER: ['ALLOC','GETADDR','NOOP']]
# ORACLE SELFCHECK: FAIL
#   getaddr: the two sides opened DIFFERENT devices -- py ['sCPU'] against bend [] ...
rc=1
```

**Note the plant's new shape:** the red is now the SINGLE truthful cause. The pre-fix tree emitted
TWO rows here (device mismatch **and** `unmapped arg atom letters: B`, see `red-before.out`); with
`WHOLE` wired, the spurious `B` is gone and the exit still fires on the real defect. Same input,
same `rc=1`, one cause instead of one cause plus one artifact.

**RED (scanner, in-process — the pre-fix scanner, isolated):**

```
WHOLE = ('X!', 'BAD', '?')
atoms("BAD") WITH the WHOLE exclusion  -> set()   (expect set())
atoms("BAD") WITHOUT the exclusion    -> {'B'}   (the spurious B)
```

**GREEN:** both edits present → `rc=0`, `# ORACLE SELFCHECK: OK` (`run.out`).

**The exit is not a constant:** three distinct inputs produce `rc=0` (fixed), `rc=1` (broken arm),
and `rc=1` with an ABSENT token (`refusal_plant.py`). The pin set observes a value that input moves.

---

## 6. THE DENOMINATOR — how many checks can set this file's exit

**14 `bad.append` sites** (`grep -n 'bad.append'`), all feeding the ONE writer at `:452`;
**plus 2 `SystemExit` refusals** (`:137`, `:237`); **plus the exception path** → **17 exit-setting
paths**, 16 of which are named checks:

| # | line | check | ever observed to fire? |
|---|---|---|---|
| 1 | 274 | py/bend opened different devices (corpus) | **YES — live, this session** |
| 2 | 307 | `atoms()` counts a dataclass FIELD NAME | YES — comment records DEFECT 21, 2026-10-04 |
| 3 | 309 | `atoms()` lost the ENUM atom `E` | YES — same DEFECT 21 plant |
| 4 | 311 | unmapped arg atom letters (corpus) | **YES — live, this session (`B`)** |
| 5 | 321 | field-wise device tuple ≠ 3 letters | asserted both ways when added; not re-observed |
| 6 | 324 | tuple opener `n` counted as atom | same as #5 |
| 7 | 327 | 4-element device tuple misread | same as #5 |
| 8 | 330 | BARE device name no longer an atom | same as #5 |
| 9 | 340 | whole marker `BAD` read as an atom (**new**) | **YES — planted, `WHOLE=()` → `{B}`** |
| 10 | 420 | enum parse ≠ live `Ops` | not observed |
| 11 | 424 | a graph reached a "by-construction" non-node | not observed |
| 12 | 427 | program-op partition not total/disjoint | not observed |
| 13 | 430 | NOT-REACHED split does not sum | not observed |
| 14 | 443 | op census counted a non-`Ops` name | comment records a design measurement; not re-observed |
| 15 | 137 | no `--dev` default in `graphcmp.py` | not observed |
| 16 | 237 | `tinygrad` already imported (refusal) | **YES — planted, `refusal_plant.py`** |
| 17 | — | uncaught exception | not observed |

**How many are pinned by `differ.py`: ZERO individually.** `differ.PINS` holds exactly TWO facts
about this file — `census-rc` and `oracle-selfcheck` — and both are AGGREGATE: the exit code and
the token of one invocation. A run can be green on both while every one of the 16 checks is dead
(the `70 of 70` line and `SELFCHECK: OK` would still print), and red on both while only one of the
16 fires. **Of 16 named checks, 6 have been observed to fire (1,2,3,4,9,16); 10 have never been
seen to.** A check nobody has watched fire is a check of unknown value — this is the number
AGENTS.md keeps asking for and this session is the first to tabulate it.

---

## 7. LOSSLESS EVIDENCE (`.agents/slop/censusred/`)

- `run.out` / `run.err` — the GREEN run, `rc=0`.
- `red-before.out` — the RED run at HEAD: `FAIL`, `rc=1`, BOTH fires.
- `plant-red.out` / `.err` — the corpus plant: broken bend arm → `rc=1`, one truthful cause.
- `refusal.out` / `.err` + `refusal_plant.py` — `rc=1` with an ABSENT token (the disagreement).
- `run.err`, `plant-red.err` — empty: neither lane writes to stderr.

## 8. WHAT A RE-TAKE STILL OWES

The pins **as `differ.py`/`corpus-figure.py` read them** live in `runs/graphcmp/D/`, and that
artifact is from 15:47 and still red. Turning the PINS green requires a full
`checks/differ.py run` — out of this unit's scope (`checks/` is off limits) and a 34-invocation
pipeline. This unit changed the GENERATOR only; the artifact is now stale by one corrected
assert, and `corpus-figure.py`'s own doctrine (see its `:170-180`) is that a stale artifact is
RED until re-taken, not hand-re-pinned. **Do not hand-edit `D0-coverage-census.txt`.**

## 9. CAVEAT: THE TREE IS WRITING WHILE THIS READS

`git rev-parse HEAD` moved from `00b101574` to `9d44f2c63` to `c3f589df5` during this session, and
another unit's commit swept this unit's `graphcmp-oracle.py` edits into `c3f589df5` mid-run. The
bend fix remains uncommitted (`M .agents/slop/graphcmp.bend`). Nothing here was staged or
committed by this unit.
