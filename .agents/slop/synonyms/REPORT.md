# SYNONYMS: THE TWELVE RENAMED EXIT CODES, AND THE ONE COLLISION SETTLED

`.agents/slop/synonyms/` — every number below was measured by running the file named beside it.
**AST, NOT TEXT, throughout.** `prune4`'s lesson is why: a regex census reported 183 where the
truth was 61 because `\.add\(` matched `seen.add(` on a Python set. `twelfth.py` below is the
proof that the lesson generalises one level further — a `name <- code` unpack census reports
**31 "renamed codes"** over the tree, and **28 of them are `WARP_SIZE = 32`, `TH_LOAD_NT`,
`kgsl_deviceid__enumvalues`** — firmware tables and disassembler selectors that are not
vocabularies. A shape is not a population.

---

## 0. WHAT I CANNOT SEE, FIRST

1. **THE THIRD VOCABULARY SHAPE IS INVISIBLE TO EVERY EXISTING READER, AND I FOUND IT BY
   RESOLUTION.** `.agents/slop/hooks/run.py:56` spells `NAME = {PASS: "GREEN", …}`. Its keys are
   **`ast.Name`, not literals**, so `ast.literal_eval` **raises** on it — which is why
   `gate-surface.declaration()` (marker: the literal name `VERDICTS`) and
   `gate-surface.vocabulary()` (shape: a module-level `A, B = (0, 1)` unpack) are both blind.
   Reading it takes **two passes**: resolve `:54`'s tuple unpack into constants, then use them as
   the dict's keys. **This is a fourth kind of population** — neither a generator's declaration,
   nor a directory walk, nor a regex over write sites — and `AGENTS.md`'s doctrine names three.
   **I am not proposing a reader for it**, because adding one is adding a marker list, which is
   the fault.
2. **THE MARKER LIST IS A HAND LIST.** `final.py` reads `MARKERS = ("VERDICTS", "NAME")` — two
   names, hand-written, in a file arguing against hand lists. `shapes.py` measures why a
   structural marker cannot replace it: **56 disagreeing entries over 22 sites**, 45 of them
   `PSP_ERRORS` / `_SDWA_SEL` / `TAGS` / `R4_TH_LOAD` / `kgsl_*__enumvalues`. **Adding a third
   marker would move the defect one level down**, which is `AGENTS.md`'s own `xd1/pin` failure
   reproduced inside the census of that failure. **This is the strongest argument for NOT
   extending the reader, and it is why item 2's relationship is a refusal rather than a table.**
3. **`HOMES` IS A HAND LIST AND I MEASURED WHAT IT COSTS.** `gates/gates-pop.py:103` is
   `("checks", "gates")`. Outside it: **6 of 45 `gatekit` consumers**, plus the runner that HOLDS
   the vocabulary copy. `hooks/run.py:128` names a gate by `--report-gate=` on the command line
   and `:122-127` admits why.
4. **A SPELLING CAN BE WRONG AND RESOLVE CLEANLY.** `resolve()` compares tokens; it cannot know
   that `checks/nl-gate-noguard.py`'s `0: "AGREE"` means PASS. **Does my change make this worse?
   No** — it is the pre-existing condition, and `resolve()` *adds* a channel that can catch it
   (a gate spelling the owner's word) without claiming to close it.
5. **A GATE WITH NO `VERDICTS` RESOLVES NOT AT ALL: 111 of 125 entry points.** They are reported
   by name (`census.out`), not summarised away.
6. **I CANNOT SETTLE WHICH OF THE ELEVEN ARE MEANING-SYNONYMS.** Ten of them are `OK`/`AGREE`/
   `CLEAN` for PASS and `RED`/`BROKEN` for FAIL, and their own `PLANTS` are what would settle it
   — which needs execution I was told not to do. **A reviewer is the only instrument for the
   rest**, as `declareverdict` says of its own `RED_IS`.

---

## 1. THE TWELVE, BY DISCOVERY

`census.py` → `resolve.py` → `twelfth2.py`. Population = `gates/gates-pop.py:discover()` loaded
**by path**; owner = `gates/gate-surface.py:vocabulary()` reading `gates/gatekit.py:60`.

| # | gate | line | its token | `gatekit`'s | class |
|---|------|-----:|-----------|-------------|-------|
| 1 | `checks/dup-census.py` | 306 | `0: OK` | `PASS` | SYNONYM |
| 2 | `checks/env-precond.py` | 437 | `0: OK` | `PASS` | SYNONYM |
| 3 | `checks/hermetic-census.py` | 187 | `0: OK` | `PASS` | SYNONYM |
| 4 | `checks/nl-gate-noguard.py` | 105 | `0: AGREE` | `PASS` | SYNONYM |
| 5 | `checks/nl-gate-noguard.py` | 105 | `1: BROKEN` | `FAIL` | SYNONYM |
| 6 | `checks/no-txt.py` | 222 | `0: CLEAN` | `PASS` | SYNONYM |
| 7 | `checks/no-txt.py` | 222 | `1: RED` | `FAIL` | SYNONYM |
| 8 | `checks/oracle_f64.py` | 314 | `0: OK` | `PASS` | SYNONYM |
| 9 | `gates/gate-surface.py` | 135 | `0: OK` | `PASS` | SYNONYM |
| 10 | `gates/gate-surface.py` | 135 | `1: RED` | `FAIL` | SYNONYM |
| **11** | **`checks/wallcheck.py`** | **681** | **`4: NO-ROW`** | **`SKIP`** | **COLLISION** |
| 12 | `.agents/slop/hooks/run.py` | 56 | `0: GREEN` | `PASS` | SYNONYM |

**The brief's "12 across 8 gates" is 11 + 1, not 12 gates.** 11 renamed codes are inside
`HOMES`, over **8 gates**; the twelfth is in a **runner outside `HOMES`**. MEASURED both ways and
they agree (`census.out`, `twelfth2.out`).

**Plus 4 UNMAPPED codes** the owner does not name at all — `checks/dup-gate.py:355` and
`checks/wallcheck.py:681` spell `2: USAGE`; `checks/env-precond.py:437` and
`gates/gate-surface.py:135` spell the **same number** `2: REFUSED`. **TWO MEANINGS ON ONE
NUMBER**, and `gate-surface.py:97-102` already names it. These are not synonyms; they are worse.

---

## 2. WHERE A SYNONYM TABLE LIVES — AND WHY NOT IN `gatekit`

**THE ANSWER: NOT IN THE OWNER. IN THE GATE — and it is ALREADY THERE. `VERDICTS` IS THE TABLE.**
A gate spelling its own exit with its own token, in its own source, read by `ast.literal_eval`
off its module body, **is a declaration**. `{4: "NO-ROW", 5: "DEAD", 3: "REFUSED"}` in
`wallcheck.py:681` is the same shape `RED_IS` already established.

**THE DIRECTION, AND WHAT IT IMPLIES.** `gatekit` is **imported BY** the gates — **45 consumers by
walk** (`cost.py`). The vocabulary therefore only travels **owner → gate**. A table *inside*
`gatekit` inverts the arrow: it makes the owner the author of 8 gates' vocabularies, which is
`gendirs.py`'s "two instruments holding two lists have no authority over each other" with the
owner as the second holder. **`gendirs.py` is right and that settles it.**

**COULD `gatekit` IMPORT THE GATES' SPELLINGS RATHER THAN BE IMPORTED BY THEM? NO — and the
direction is measurable, not stylistic:**

- `gatekit` would have to `spec_from_file_location` **125 entry points** to read them.
- `gate-surface.py:26` records why importing a gate is **forbidden**: importing RUNS it —
  `gates/mixin-op-gate.py` and `gates/beautiful-mnist-gate.py` `sys.exit(2)` at module scope, and
  every `Gate.__init__` **deletes its own artifact directory**.
- **A circular import**: `gates/gates-pop.py` imports `gatekit`. An owner that imports its
  consumers cannot be imported by them.
- **And it buys nothing**: the gate's own `VERDICTS` already says the same thing, in the place
  where a change to it lands in the same commit. `gatekit`'s five names stay; that is all it
  needs to own.

**WHAT LANDED: THE RELATIONSHIP AND THE REFUSAL, NOT A TABLE** (`resolve.py`, **5/5 GREEN**).
A gate spelling the owner's tokens resolves; a token the owner does not use **REFUSES (exit 3)**.

---

## 3. THE COLLISION — BOTH ANSWERS, AND WHICH THE EVIDENCE SUPPORTS

### ANSWER A — *it IS `SKIP`* (a synonym; the brief's implicit reading). **THE EVIDENCE REFUTES IT.**

Three measurements:

1. **`gatekit`'s `SKIP` IS UNREACHABLE.** `reach.py`, by AST over `Return` nodes:
   `return PASS` **1** site, `return REFUSED` **4**, `return DEAD` **2**, `return FAIL` **0**,
   **`return SKIP` — ZERO.** The file's only integer literals returned are **`[1]`**. **Exit 4 is
   not reachable from any integer literal in the owner.** So the question is not "do these mean
   the same?" — it is **"does `SKIP` mean anything at all?"** It does not, today.
2. **`wallcheck`'s OWN MESSAGE SAYS `REFUSED` TWICE, INCLUDING FOR EXIT 5.** `:396`
   `NO ROW MATCHES … — REFUSED, not CLEAN`; `:400` `LEDGER HAS NO ROWS — REFUSED, not CLEAN`.
   MEASURED by running it:
   ```
   $ .venv/bin/python checks/wallcheck.py NO-SUCH-ID   → rc=4  "NO ROW MATCHES … REFUSED, not CLEAN"
   $ .venv/bin/python checks/wallcheck.py --plant dead → rc=5  "LEDGER HAS NO ROWS — REFUSED, not CLEAN"
   ```
   **If 4 and 5 print the SAME word, then `NO-ROW` and `DEAD` are the same verdict under two
   numbers inside one gate** — and the gate's own prose calls that verdict `REFUSED`, which is
   **3**. **The collision is not between 4 and `SKIP`. It is between `wallcheck`'s 4/5 and its
   own 3.**
3. **THE TWO STATES REALLY DO DIFFER IN KIND** (`:395` vs `:399`): 4 is `want and not sel` — the
   ledger **has rows**, the caller's `--ids` **selected none**; 5 is `not sel` — the ledger is
   **empty**. **A mistyped id and a wiped ledger are different faults with the same exit.** That
   is a real distinction, and `:603-508` gives it a third: `:503 not graded → 5` for *every row
   refused*.

### ANSWER B — *it IS A SIXTH VERDICT* (`NO-ROW`: ran-and-found-nothing). **THE DANGEROUS ONE. THE
EVIDENCE PARTLY SUPPORTS IT, AND I WILL NOT SETTLE IT.**

**What supports it:** the distinction above is real, the tree has used it (a reachable, planted
exit — `PLANTS[4]`), and `AGENTS.md` says `DEAD` "HAS NO EXIT ANYWHERE — THAT IS THE GAP", so a
named sixth would be the first. **What refutes the framing:** a sixth verdict in **one gate's
private numbering** is not a sixth verdict **in the tree** — the tree's vocabulary is `gatekit`'s,
and `SKIP` (4) has **zero sites**. Naming `NO-ROW` as a sixth would be naming a sixth *number*,
which is the confusion the whole question is about.

### BOTH ANSWERS' COMMON DEFECT, WHICH IS THE REAL FINDING

**THE COLLISION IS NOT BETWEEN TWO VERDICTS. IT IS BETWEEN A VERDICT AND A HOLE.**
`gatekit`'s 4 is **unreachable**; `wallcheck`'s 4 is **live**. **A live verdict is colliding with
a vacant slot, and every runner scores it under the vacant slot's name.** `charge.py`, 3/3 GREEN:

| rc | owner token | `hooks/run.py:116` charges | agree? |
|---:|---|---|---|
| 0 | `PASS` | `GREEN` | **NO** (the twelfth, §1) |
| 1 | `FAIL` | `FAIL` | yes |
| 2 | *unmapped* | **`DEAD`** | **NO** — a mistyped `--ledger` path is scored as a CRASH |
| 3 | `REFUSED` | `REFUSED` | yes |
| 4 | `SKIP` (unreachable) | `SKIP` | yes — **`wallcheck`'s `NO-ROW` lands here** |
| 5 | `DEAD` | `DEAD` | yes |

**Plant A: `wallcheck`'s 4 (`NO-ROW`, the gate RAN, the SELECTION was empty) is charged `SKIP`
("it could not run"). NOT THE SAME CLAIM, and the charge cannot see that.**
**Plant B: `wallcheck`'s 2 (`USAGE`, the ledger path is absent) is charged `DEAD`.**
**Plant C: code 6 — a runner's own hypothetical sixth verdict — charges `DEAD` IDENTICALLY to
code 2.** **`VOCABULARY-CHARGES-NOTHING` IS THE DIFFERENCE AND IT IS MEASURED: A RUNNER THAT
MEANS A SIXTH VERDICT IS INDISTINGUISHABLE FROM ONE THAT CRASHED.**

**WHY THE TOKEN NEVER REACHES A RUNNER:** a subprocess returns an `int`. The only channel is
stdout, which `hooks/run.py:111` already reads as `head`. **That is where a relationship can
actually live.**

---

## 4. WHAT EACH ANSWER COSTS IN FILES

`cost.py`. **`gatekit` consumer count: 45 by walk over import sites (39 under `HOMES`, 6
outside). The brief's "~8" IS WRONG BY 37.**

- **ADDITIVE** (a new token; no number moves): **touches 0 of 45.** Consumers read the owner's
  unpack; an extra name costs a reader nothing. **This is the cheap direction.**
- **BREAKING** (a renumber): **6 consumers hold the literal 4 or 5** (`checks/bounded.py`,
  `checks/substrate.py`, `gates/gates-pop.py`, `gates/i64-shl-gate.py`, two `.slop` fixtures), and
  **all 11 renamed codes** would change, plus `checks/e2e.py:519 return 4` — a **literal**.

---

## 5. LANDED / DEFERRED

**LANDED — the relationship and the refusal** (`resolve.py`, `.agents/slop/synonyms/`), 5/5:

```
PASS  1  a gate spelling the owner's tokens RESOLVES (same meaning, same word)
PASS  2  a SYNONYM in the SAME MEANING that is a DIFFERENT WORD (AGREE/PASS) still REFUSES,
          because the spelling alone cannot say the meanings agree
PASS  3  THE COLLISION REFUSES (exit 3) rather than defaulting NO-ROW to the nearest token SKIP
PASS  4  an UNMAPPED code (2 USAGE) REFUSES
PASS  5  the SAME table with the collision spelled the OWNER's word (SKIP) resolves clean
```

**PLANTED BOTH WAYS, AND THE NEGATIVE IS PLANT 2 AND PLANT 3** — a gate spelling `REFUSED` and
one spelling `NO-ROW` **do not both resolve**, and the collision **REFUSES (3) rather than
defaulting**. `declareverdict`'s plant 5c, applied to a spelling.

**NOT LANDED, AND WHY — DOCTRINE, NOT DIFFICULTY:**
1. **No synonym table** — §2. A table in the owner is the fourth hand list.
2. **No new exit code and no renumber** — breaking, §4, and `SKIP` is unreachable anyway, so a
   new number would be a **sixth slot that nothing returns**, which is the defect again.
3. **No third `MARKERS` entry** — §0.2.
4. **The ten `OK`/`AGREE`/`CLEAN` synonyms are NOT re-spelled** — I own `gatekit.py` only, and
   these are gate bodies. **A reviewer decides; a reviewer can also be wrong, and only a reviewer's
   verdict is earned.**

**THREE OF MY OWN INSTRUMENTS WERE WRONG FIRST, AND ALL THREE ARE DEAD I READ PAST:**

| defect | how it read | the class |
|---|---|---|
| `resolve()` returned on the **first** row | a table with **4 agreeing rows and 1 collision** came back `SAME` | plants 3 and 4 RED; **`DEAD`**: "1 disagreement never looked at" |
| `census.py` unpacked `declaration()`'s result | `gate-surface.py:251` returns a **3-tuple** on SyntaxError; six branches return 4 — **a gate that is a syntax error crashes every reader**, and no gate is one today | latent in `gatekit`'s own vocabulary file |
| `reach.py` used `isinstance(v, int)` | `bool` **is** a subclass of `int`: reported `DISTINCT integer exits: [False, True]` for a file returning none | `prune4`'s lesson, one level down |
| `twelfth2.py` resolved one pass | `:54` is a **tuple** unpack, so the constant map was **`{}`** — an empty map is indistinguishable from an absent one, and the instrument reported "no vocabulary here" **about the file whose whole job is holding one** | `DEAD`, again |

**`gate-surface.py:vocabulary()` has the same `isinstance`-free but **`ast.literal_eval`-raises**
hole: a tuple of LISTS passes `isinstance(codes, tuple)` and then `dict(zip(...))` raises
`TypeError: unhashable type: 'list'`** — an instrument whose whole job is to name an *ambiguous*
owner would **crash** instead of **refusing**. **I did not fix it: `gate-surface.py` is not mine.**

---

## FILES

```
.agents/slop/synonyms/
  REPORT.md      this file
  census.py      AST census, VERDICTS only, population = gates-pop.discover() BY PATH
  control.py     LABELLED CONTROL: os.walk; the same readers, a different file set
  tables.py      every declaring gate's full table, side by side
  shapes.py      ALL THREE vocabulary SHAPES, and why a shape is not a population
  twelfth.py     every name<-code unpack (reads 31; 28 are firmware tables)
  twelfth2.py    THE TWELFTH: resolution as a fourth kind of population
  reach.py       IS gatekit's SKIP REACHABLE? (no: 0 return sites)
  cost.py        consumer count BY WALK; additive vs breaking
  resolve.py     THE RELATIONSHIP + THE REFUSAL, 5 plants            [GREEN 5/5]
  charge.py      WHAT A RUNNER CHARGES, 3 plants                     [GREEN 3/3]
  *.out          every reading above, captured
```

No `.txt`. No gate body, `AGENTS.md`, `tinybendygrad/` or `gatekit.py` touched. Nothing committed.