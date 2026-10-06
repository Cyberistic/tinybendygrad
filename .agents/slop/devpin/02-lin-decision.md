# 02 — `lin`: WHICH OF THE THREE ANSWERS, AND THE MEASUREMENT

**I TOOK NONE OF THE THREE AS FRAMED, BECAUSE THE PREMISE IS FALSIFIABLE AND I FALSIFIED
IT. `lin`'s recorded `DISAGREE` IS CORRECT AND DEVICE-INDEPENDENT. DELETING IT (answer 3)
WOULD DELETE A GOOD ROW. THE DEVICE DEPENDENCY IS REAL — IT IS IN 14 *OTHER* ROWS.**

```
.venv/bin/python .agents/slop/devpin/lin-decision.py
```

## THE MEASUREMENT: `lin`'s VERDICT DOES NOT MOVE, ON ANY DEVICE

`WANT["lin"] == "DISAGREE"` (`checks/differ.py:132`). A verdict moves only if some device
turns DISAGREE into AGREE, and a row AGREES only if the py side is **byte-identical** to the
port's recorded emission. MEASURED, reading `runs/graphcmp/D/D2-canon-bend-lin.txt` and
re-emitting the py side under four devices (nothing written to `runs/`):

| `--dev` | py rows | `Opt` objects | py side | byte-identical to the port? | verdict |
|---------|---------|---------------|---------|------------------------------|---------|
| `CPU` | 46 | 1 | `kI(sr_4_5_3,n(Opt(op=EOptOps.SPLITaxis=i2arg=n(i0,XUPCAST))),N,i0)` | **no** | DISAGREE |
| `NULL` | 46 | 1 | identical to CPU | **no** | DISAGREE |
| `METAL` | 44 | 2 | `kI(sr_5_4_3,n(Opt(…),Opt(…)),N,i0)` | **no** | DISAGREE |
| `PYTHON` | 41 | 2 | identical to METAL's shape, shorter | **no** | DISAGREE |

**`DISAGREE` ON ALL FOUR. `expect-moved=0` CANNOT FIRE ON `lin` FROM THE DEVICE.**

**AND A THIRD INDEPENDENT CONFIRMATION OF THE DEVICE, THIS TIME BY REPRODUCTION RATHER THAN
INFERENCE:** `--dev CPU` re-emits `D2-canon-py-lin.txt` **BYTE-IDENTICALLY**, and `NULL`,
`METAL`, `PYTHON` all do not:

```
--dev CPU     rows=46 Opt-objects=1  vs recorded D2-canon-py-lin.txt: IDENTICAL
--dev NULL    rows=46 Opt-objects=1  vs recorded: DIFFERS
--dev METAL   rows=44 Opt-objects=2  vs recorded: DIFFERS
--dev PYTHON  rows=41 Opt-objects=2  vs recorded: DIFFERS
```

## SO WHAT IS TRUE, AND WHAT IS NOT

| claim | verdict |
|-------|---------|
| "`runs/graphcmp/D` was taken under `DEV=CPU`" | **TRUE**, three ways: the argparse default at `graphcmp.py:2839`, the `sCPU` in 52 artifacts and all 50 `D2-canon-*`, and a byte-identical re-emission. |
| "`lin` was recorded as a WRONG-SHAPE PORT DEFECT and is not one" | **TRUE** — but not *because of the device*. The py side resolves the option to `Opt(op=…, axis=…, arg=…)`; the port emits `q`, the NAMED REFUSAL for "an applied option the port cannot resolve" (`graphcmp.py:326`). **That is a content refusal, and it is a real port gap.** |
| "the port and CPython AGREE; they were run on two different machines" | **FALSE.** They do not agree — `D2-cmp-lin.txt` records `lin DIFFERS` with both spellings side by side, and they still differ on every device. |
| "answer 3: delete the verdict and let it be a SKIP" | **WRONG HERE.** `expect-moved=0` is zero-tolerance but `lin` contributes 0 to it under every device. Deleting the row loses a true statement and protects nothing. |
| "the fix (`applied_opts: List<&2,OPT>`) would have fixed a row that was not broken" | **TRUE, AND THIS IS THE PART THAT MATTERS** — see below. |

## THE PART THAT MATTERS: A FIX VALIDATED ON ONE DEVICE IS VALIDATED ON ONE DEVICE

The fix `applied_opts: List<&2,OPT>` would make the port able to render the option. **On
`CPU`/`NULL` the py side has exactly ONE option, so a correct port would AGREE. On
`METAL`/`PYTHON` it has TWO, so a correct port would still DISAGREE — and the port would be
*right* to.** MEASURED: `Opt objects = 1` on CPU/NULL, `= 2` on METAL/PYTHON.

So a green `lin` row means *"the port models `Opt`"* **only if the device it was taken on has
one option** — and **the run records that nowhere.** `D0-run-summary.txt` has no device line
(`grep -i 'dev|cpu|metal|device' D0-run-summary.txt; echo rc=$?` → `rc=1`). **The pin is not
missing from the record; the record has no place to put it.** That is the actual defect, and
it is a *harness* defect, exactly as the job says — just not on the row it named.

## THE 14 ROWS THAT REALLY ARE AT RISK

`lin-decision.py` re-emits all 25 graphs under four devices and diffs against the recorded
`D2-canon-py-*.txt`:

| | count |
|---|---|
| py half **reproduces the recorded artifact on every device** | **7** — `gate indexed loop range rangeflat sink special` |
| py half **moves with the device** | **18** — `allred alu binblob bit buffer bw cast cdiv commute flip group late lin matmul move reduce sym where` |
| …of the 18, **recorded `IDENTICAL` (i.e. an AGREE row built on an unpinned variable)** | **14** — `alu binblob bit buffer bw cast commute group matmul move reduce sym where` |

**THOSE 14 ARE WHAT THE JOB'S FEAR DESCRIBES — AN `AGREE` ROW THAT WILL FIRE THE MOMENT
ANYONE RUNS ON ANOTHER DEVICE, AND THE FAILURE WILL LOOK LIKE A PORT REGRESSION.** `lin` is
not among them, because `lin`'s row is already a `DISAGREE`.

**BUT THE 14 ARE CURRENTLY PROTECTED BY AN ACCIDENT, NOT BY A DECLARATION:** `checks/differ.py`
never passes `--dev`, so `graphcmp.py:2853` overwrites `differ.py`'s own `DEV=NULL` with
`"CPU"` in every child. **The protection lives in an argparse DEFAULT in a third file, and
`checks/differ.py` does not know it exists.** One `--dev` added to `differ.py:452` and all 14
move at once.

## WHAT I AM ACTUALLY DELIVERING FOR `lin`

**NOTHING TO `WANT` — and that is the finding, not a dodge.** `lin`'s row is correct on all
four devices. What I deliver instead is the *pin* that makes "which device?" answerable, plus
a check that refuses when it is undeclared, plus `corpus-figure.py` refusing rather than
floating. `differ.py:126-131`'s comment — *"which the port can only answer with one `q` per
option"* — is true on `CPU`/`NULL` and **false on `METAL`/`PYTHON`**, and I have named the
exact line for the unit that owns `differ.py` to correct:

> `checks/differ.py:126-129` currently reads:
> `# `lin` DISAGREES on ONE node of 46 -- its SINK's `applied_opts`, which the port can only`
> `# answer with one `q` per option (`ops.bend:978` types them `List<U32>`; upstream's are`
> `# `Opt` dataclasses).`
>
> **SUGGESTED REPLACEMENT TEXT FOR THAT COMMENT (not applied — `differ.py` is not mine):**
> `# `lin` DISAGREES on ONE node of 46 -- its SINK's `applied_opts`, which the port can only`
> `# answer with one `q` per option (`ops.bend:978` types them `List<U32>`; upstream's are`
> `# `Opt` dataclasses).  **THE "ONE" IS A FUNCTION OF THE DEVICE AND NOT OF THE PORT:**`
> `# MEASURED over four devices, the py side carries 1 `Opt` under `CPU`/`NULL` and 2 under`
> `# `METAL`/`PYTHON`, so a port that modelled `applied_opts: List<&2,OPT>` would AGREE on the`
> `# first pair and DISAGREE on the second -- and be RIGHT to.  This row is DISAGREE on all`
> `# four, so it does not move with the device; see `.agents/slop/devpin/02-lin-decision.md`.`
