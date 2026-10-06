# The 553 `.txt`, attributed to owning generators

`.venv/bin/python checks/txt-owners.py` recomputes every number here. Nothing in this file is a
transcript of a run I did once.

## THE TOTAL MOVED THREE TIMES WHILE THIS WAS BEING MEASURED

    552   first measurement
    562   after the census was written      (+10: another unit writing .agents/slop/rerun/D-before)
    553   after the langs/ fix              (-8 mine, -1 somebody else's)

**So the total is not a result and is not reported as one.** What is a result is the next table,
which is a partition of whatever the total happens to be at the moment it is run. The excused
count did NOT move: **139**, every time, and it is `differ.declared()` imported, never re-derived.

## THE ATTRIBUTION, BY OWNING GENERATOR

A generator is credited a file only when the generator's own **redirect target** resolves to that
exact repo-relative path. A mention is not a write path, so a file only its reader names is
unowned, which is the honest answer and not a gap in the check.

| files | reached by | generator | status |
|---|---|---|---|
| 5 | 10 | `checks/e2e.sh` | LIVE, the seven-stage gate |
| 5 | 10 | `.agents/slop/e2epy/oracle-e2e.sh` | LIVE, the same driver |
| 5 | 45 | `.agents/slop/skipexit/prefix/checks/e2e.sh` | a plant's frozen prefix |
| 5 | 45 | `.agents/slop/skipexit/prefix/.agents/slop/e2epy/oracle-e2e.sh` | a plant's frozen prefix |
| 4 | 11 | `.agents/slop/opsbend-milestone.sh` | LIVE |
| 3 | 2 | `.agents/slop/strays/MANIFEST.tsv` | a ledger, not a program |

**12 distinct files, 27 credits.** `checks/e2e.sh` and `oracle-e2e.sh` are the same driver and both
write the same five names, which is why credits exceed files.

## THE 541 THAT NO GENERATOR OWNS

| n | where | what it is |
|---|---|---|
| **244** | `oracles/` | hand-curated, **named by nothing at all** |
| 139 | `.agents/slop/rerun/D-before/` | another unit's differ re-run, in flight |
| 12 | `.agents/slop/differverdict/shell-D/` | a differ lane copy |
| 11 | `.agents/slop/differverdict/pristine/runs/graphcmp/D/` | a differ lane copy |
| 10 each | `.agents/slop/differverdict/warm-{oracle,planted,python}/` | differ warm-cache copies |
| 9 | `.agents/slop/rerun/` | as above |
| 7 | `.agents/slop/` | loose |
| 6+5x8+1x2 | `.agents/slop/e2epy/fixtures/plant*/runs/e2e/` | e2e plant fixtures |
| 5 | `.agents/slop/e2estage8/artifacts/` | **stage 8 is RETIRED** (AGENTS.md) |
| 4 | `.agents/slop/differverdict/py-D/` | a differ lane copy |
| 4 | `oracles/schedule-bodies/` | orphans of a gate that cannot run |
| 4 | `runs/e2e/` | e2e stage output, written by a path this check refuses to follow |
| 3 | `.agents/slop/i64shl/`, `.agents/slop/shfinish/ref/` | closed runs |
| the rest | 12 dirs, 1-2 each | residue |

### `oracles/` IS THE LARGEST GROUP AND IT HAS NO GENERATOR

244 of the 553, 45%. Confirmed by a SECOND METHOD THAT SHARES NO REGEX WITH THE CHECK -- a plain
`grep -l -F` for each basename over every tracked file, code and prose, asking whether any file
other than the artifact names it:

    oracles/*.txt total:                            259
      named by SOME other tracked file:               0
      named by NOTHING at all:                      259

**Not one of the 259 is named anywhere in the repository.** There is no generator to close this at,
which is why the largest group resists the rule: a generator rule cannot fire on a file no code
produced. `oracles/` already holds 35 `.rows` and 5 `.err`, so the convention is present inside the
very directory that violates it.

## `gates/artifacts/`: WHY 0 OF 10 DIRS CAN REPORT HEALTH

**NOT the `.txt` source.** Measured: **0 `.txt` under `gates/artifacts/`, 77 files, all
`.cmp`/`.out`/`.rows`/`.bin`.** The hypothesis that the artifact directory is the proliferation
source is false, and the priority-1 group was empty from the start.

The real fault is a declared universe that omits its own contents:

    gates/retention-check.py:61  GATEKIT_OUTPUT = {py,bd,bn}.{txt,sub} | {gate.bin}     -- 7 names
    gates/gatekit.py             writes {py}.rows {bd,bn}.out {py,bd,bn}.cmp gate.bin   -- 7 names
    MEASURED INTERSECTION                                                                 -- 1 name

The one name they agree on is `gate.bin`. `artefacts_ok()` therefore judges each of the 10
directories on **one file out of seven**, and cannot see `py.rows` -- the oracle's expected values,
the file whose staleness matters most -- because that name is outside its own declared set.
"D glob(\"*.txt\") DEFINES THE POPULATION" is exactly right, and worse: the population holds no
`.txt` and no `.rows`.

**MINIMAL FIX, NAMED, NOT APPLIED** (`gates/retention-check.py`, another unit's):

    gates/retention-check.py:61   -> {f"py{LANE_ROWS}", f"bd{LANE_OUT}", f"bn{LANE_OUT}",
                                     f"{t}{LANE_CMP}" for t in (py,bd,bn), "gate.bin"}

The durable fix is what the file's own `Output` docstring already asks for: `gatekit.declared()`,
so `declared=None` stops meaning "transcribe it and be wrong". The comment at `:53-58` says the
transcription exists only because the generator publishes none.

## FILES WHOSE ONLY CLAIM ON EXISTENCE IS A DOCUMENT

**`.agents/slop/norm/fixtures.txt` -- CITED FOUR TIMES, DOES NOT EXIST.**
`lint_norm.py:238` ("`norm/fixtures.txt` is the list"), `NORM.md:194` ("Full table in
`norm/fixtures.txt`"), `NORM.md:212`, `.agents/TODO.md:12051`. `.agents/slop/norm/` holds
`canon.py`, `canon.selftest.py`, `census.txt`, `gate.txt`, `lint_norm.py`. Not a `.txt` finding --
the opposite one, and it is the same disease read backwards.

**`oracles/schedule-bodies/*.txt` (4) -- orphans of a gate that cannot run.** `checks/sb-gate.sh:48`
sets `D=.agents/slop/schedule-bodies`, which contains **only `00-START.md`**. The four `.txt` sit in
`oracles/schedule-bodies/`, a directory the script never names. `sb-oracle.py` and `sb-diff.py` are
absent from both. The script's own header is **right** about all of this and says so at `:38-44`;
this is a case where the document is correct in both halves and the files are still orphans.

**`langs/.gitignore`'s `out/` excludes nothing.** `git check-ignore -v langs/out/native.txt` exits
1 -- the 12 files are tracked, so the rule is inert for content. It is NOT inert for review:
`jj status` and `jj diff --stat` honour it, so the **8 renames below are invisible in the one tool a
reviewer reads** while `jj file list langs/out` shows all 12 `.out` names. A rename a reviewer cannot
see is a rename that has not been reviewed.

## THE FIX AT SOURCE: `langs/verify.sh`

`langs/` is now **0 `.txt`**, from 8.

| what | where | before | after |
|---|---|---|---|
| lane outputs | `langs/verify.sh:42,48,59,67,72,84,88,94` | `bend/native/clang/harness/js/sdk_js/bench/wasm.txt` | `.out` |
| loop reads | `langs/verify.sh:106,116,120` | `"$OUT/$lane.txt"` | `"$OUT/$lane.out"` |
| input vector | `langs/verify.sh:27,80`, `langs/sdk/bench.ts:31,99`, `langs/README.md:7,118` | `langs/vectors/payload.txt` | `payload.rows` |

`.out` because these are what a lane **PRINTED**; `.rows` because the vector is 42 u32 expected
values. `verify.sh:57` already made the distinction once -- stderr is `clang.log`, stdout was
`clang.txt` -- so the extension was the only thing wrong.

**The loop sites are the load-bearing ones.** `"$OUT/$lane.txt"` with `lane in bend native clang
harness js` names the same five files the write sites name; leaving it is the `$GT.py`/`$GT.rows`
failure this project already paid for once, where writes were renamed and reads were not.

**Closure verified, not asserted:** `langs/out` is named in exactly one file in the tree
(`OUT=langs/out`, `verify.sh:26`). Every surviving `bend.txt`/`py.txt` grep hit belongs to a
different generator's own `$OUT` (`checks/gate.sh` -> `mktemp -d`, `.agents/slop/e2e_negctl.sh` ->
`runs/e2e/`, `.agents/slop/graphcmp.py` -> `runs/graphcmp/`).

## THE PLANT

    DISAGREE  one write site reverted to .txt, reads left at .out -- the real failure mode
      langs/verify.sh:48   "$OUT/core_native" "$PAYLOAD" > "$OUT/native.txt"
      langs/verify.sh:114  REF="$OUT/native.out"
      $ .venv/bin/python checks/txt-owners.py --gate langs/verify.sh
        GATE  langs/verify.sh:48 still writes a `.txt`
      rc=1

    AGREE     committed state
      $ .venv/bin/python checks/txt-owners.py --gate langs/verify.sh
        GATE  none of langs/verify.sh names a `.txt` write target.
      rc=0

Artifacts: `langs-plant-disagree.out`, `langs-plant-agree.out`.

**THIS PLANT WAS WRITTEN TWICE.** The first version scoped `--gate` to the attribution set, so a
generator that correctly writes no `.txt` was indistinguishable from a typo and the plant answered
`no such generator`, **rc 2 on both sides, having moved nothing**. The scoped form now reads the
named file's source. A plant that cannot move is a plant that passes.

## THREE OF THE CHECK'S OWN FAULTS, each caught by disagreeing with the tree

1. **Basename matching** gave `checks/gate.sh` credit for two files it writes into `mktemp -d`,
   because `bench.txt`, `py.txt` and `native.txt` each exist under four unrelated directories.
2. **Re-scanning the line** for tokens turned `e2e_mm_gate.py "$RUN/e2e-mm-bend.txt" >
   "$RUN/e2e-mm-gate.txt"` into a WRITE of `runs/e2e/e2e-mm-bend.txt` -- crediting the e2e gate's
   own INPUT to the tool it feeds. The redirect is now captured, not re-found.
3. **`ROOT=$(cd ...)`** bound to the text before the first quote, producing
   `$(cd/runs/e2e/e2e-mm-bend.txt`, which cost **38 real write paths** their attribution.

## NOT SETTLED

- **`runs/graphcmp/D/**` and `.agents/slop/rerun/`, `.agents/slop/differverdict/**` (~180 files).**
  Being regenerated by another unit. Not touched, and `runs/graphcmp/D`'s `.txt` names are carved
  out anyway.
- **67 generators write a `.txt` this check REFUSED to follow** (13 unresolved variables, the rest
  paths under `/tmp` or directories that do not exist). Their write paths are NOT credited above,
  so the 12 attributed files is a FLOOR, not a ceiling. `.agents/slop/restorekit/plants.py`'s
  `wk-cd-gate/PLANTED.txt` is a deliberate residue plant and is counted as a refusal, not a finding.
- **`checks/sb-gate.sh`, `checks/e2e.sh`, `.agents/slop/opsbend-milestone.sh`,
  `.agents/slop/strays/MANIFEST.tsv`** are the 4 remaining live generators. Each needs its readers
  moved with it; `checks/e2e.sh` has 45 referencing files and is the seven-stage gate.
- **`langs/verify.sh` WAS NOT EXECUTED.** It needs `bend`, `node` and `clang`, and the house rules
  forbid running `bend` (`bin/bend` execs `references/bend/bend2/main.ts`). The plant above is over
  the driver's own name table, which catches the rename hazard but is a weaker guarantee than
  execution, and it is not execution.