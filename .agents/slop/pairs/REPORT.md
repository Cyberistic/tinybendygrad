# FIVE PAIRS, THREE CLASSES, AND THE 10TH TOKEN

`.agents/slop/pairs/`, 2026-10-07. `git rev-parse --short HEAD` = `3c4ceeea3`.
**No `bend` was run. No commit, no `git add`. Nothing under `checks/` that a unit is currently in
was touched without a fresh read; the two hot files `checks/differ.py` (05:42) and
`checks/no-txt.py` (05:58) were NOT edited.** Owned: the five pairs named in the brief, a new
shared declaration module, and `.agents/slop/pairs/`.

**HEADLINE.** The brief's strongest case is real: two gates held **character-identical 9-string
hand lists** (measured from `HEAD`: `checks/abi_gate.py:457` `JS_ARM_TOKENS` ==
`checks/abi4_gate.py:189` `OTHER_ABI_TOKENS`). **AND NOTHING IN THE TREE COMPARED THEM** -- a
one-sided edit was caught by no witness, so the pair was one belief held twice, exactly the
`names/ARMED` shape. The 10th token is a **DEFECT**, not a definition: a discovery over the tree's
other-ABI bytes finds four markers no token covers (`pack64`, `i64_of`, `Number(`, the I64 record
tag), **none of which occurs in any legitimate ABI-4 arm**, so they can be added safely. The pair
is closed by **sharing AND widening** (`checks/coindep.py`). Three of the five are the same fact
and are now one declaration; **one is deliberately redundant and was LEFT ALONE**; **one is not
the same fact at all and the sweep's grouping is wrong.**

---

## 1. THE 10TH TOKEN -- what it is, why both gates miss it, and DEFECT or DEFINITION

**The fence.** Each gate applies a CONTENT fence to an arm's edit bytes: *"any arm that introduces
or removes one of these is not an ABI-4 arm."* Both spell the same nine strings:

```
p.hi  p.lo  p.fst  p.snd  io_tup  BigInt  asIntN  << 32n  >>> 32n
```

**What the nine actually cover, DISCOVERED (not read from the list).** The fence test is a
substring test (`t in old or t in new`), so a token covers everything it is a substring of:

| other-ABI marker | covered by | how |
|---|---|---|
| `p.hi`, `p.lo`, `p.fst`, `p.snd` | themselves | exact |
| `io_tup` | itself | exact |
| `BigInt.asIntN`, `BigInt.asUintN` | `BigInt` | **superstring** (`BigInt` is in the list, `asIntN`/`asUintN` are not needed) |
| `>> 32n` (ABI-3 outbound, `dtype.js:180`) | `>>> 32n` | **superstring** -- `">>> 32n"[1:] == ">> 32n"` |

**The four markers NO token covers** (discovered over `tinybendygrad/runtime/dtype.js`,
`checks/abi_gate.py`'s own ABI-2 edit constants, and `checks/jsfix_gate.py`'s ABI-5 plant):

```
pack64                                     the ABI-2 OUTBOUND helper the repair rewrote
i64_of                                     the ABI-2 INBOUND helper the repair rewrote
Number(                                    the ABI-5 marker: a JS number entering BigInt arithmetic
$: "tinybendygrad/helpers.I64"             the ABI-2 outbound RECORD TAG
```

**Why both gates miss them, and why that is structural.** The nine are a HAND LIST. Nothing
derives "the other ABIs' vocabulary" from the other ABIs' bytes, so a tenth token is invisible by
construction -- which is precisely the `names.py`/`ARMED` fault (a 3-name hand list could not name
the fourth substituted graph). **The evidence that the list was not derived: its ninth token,
`>>> 32n`, occurs NOWHERE in the tree** outside the three hand-list spellings (measured by
`os.walk` over every `.py`/`.js`/`.c`/`.bend`; the only other hits are a stale `.agents/slop/`
copy and this unit's own files). A derived list would not contain a token the tree never spells.

**Verdict: DEFECT, not DEFINITION.** The discriminator the brief asks for is *would adding the
10th token false-fire on a legitimate ABI-4 arm?* Measured statically:
`abi_gate.arm_leaks('plant-abi4-js') == []` and `arm_leaks('disarm-abi4-js') == []` with the
widened fence, i.e. **none of the four markers occurs in `fp8_decode` / `dtype_fp16` /
`dtype_fp8_to` or any of their plants, disarms or the ALT spelling.** So the four are a genuine
blind spot and closing the pair is SHARING **and** WIDENING -- not sharing alone. The one
marker that is a *policy* rather than a defect is `Number(`: it is generic JS, and a later arm
could legitimately write `Number.isNaN`. I kept the parenthesised form `Number(` to narrow it, and
record here that it is the weakest of the four.

**The pair's agreement was never checked.** `grep` finds nothing asserting
`abi_gate.JS_ARM_TOKENS == abi4_gate.OTHER_ABI_TOKENS`. So a one-sided edit was caught by NO
witness -- which is stronger than the brief's claim ("one-sided edit -> caught"). **A pair whose
agreement is asserted by nothing is not two witnesses; it is one belief, stored twice.**

---

## 2. THE CLASSES -- five pairs, three classes, and the grouping error

| # | pair | shared value | CLASS | why |
|---|---|---|---|---|
| 1 | `checks/abi_gate.py:457` `JS_ARM_TOKENS` <-> `checks/abi4_gate.py:189` `OTHER_ABI_TOKENS` | the same 9 strings | **SAME FACT** | both are the CONTENT fence for an ABI-4 arm; one vocabulary, two consumers. WIDENED too (the 10th token is a defect) |
| 2 | `gates/mixin-op-gate.py:89` `port_only` <-> the oracle's `BEND_ONLY` | `rop_gap, exp_cast, commit_weak, bin_promote` | **DELIBERATELY REDUNDANT** | the gate's row-count check compares its declaration to the ORACLE'S OWN OUTPUT; an oracle told the gate's list would be checked against itself. KEPT INDEPENDENT |
| 3 | `gates/i64-shl-gate.py` inline value tuple <-> `gates/i64-shl-oracle.py` `VALUES` names | `neg1, one, lowhi` | **SAME FACT** | the fixture's value NAMES; the words stay the oracle's own measurement |
| 4 | `checks/disagree-gate.py:58` `ARMED` <-> `checks/differ.py` `WANT` | `allred, cdiv, late` | **NOT THE SAME FACT** | `ARMED` = "the dispatcher routes these three to their own builder"; `WANT` maps the whole corpus to run verdicts (`"allred": "AGREE"`, `differ.py:161`). Same three NAMES, two predicates -- the sweep grouped a name overlap as a claim overlap |
| 5 | `checks/no-strays.py:127` `SKIP_DIRS` <-> `checks/unowned.py:42` `SKIP_DIRS` | `{.git,.venv,__pycache__,node_modules,references}` | **SAME FACT** | the shared exclusion set. The two apply it differently (basename prune vs path substring); only the SET is shared |

**Pair 2, the trap, in full.** The `remove duplication` reflex says: one list, two files, dedup it.
That is wrong here. `gatekit.run()` derives the expected oracle row count as
`rows - len(port_only)` (`gates/gatekit.py:384`). The check has teeth **only because the oracle
independently decides what it cannot answer** -- the four rows are CPython refusals, so the oracle
omits them structurally and prints 32 while the port prints 36. If the oracle read the gate's
`port_only`, the count would compare the list to itself. **The independent copy is what makes the
number a measurement.** Further: `BEND_ONLY` is currently read by NOTHING (grep confirms it is
defined at `gates/mixin-op-oracle.py:149` and never referenced), so the independence is nominal
today -- **a separate, smaller defect: a restatement nothing reads is rot, not a witness.** That
defect is named here and not fixed, because fixing it (making the oracle assert its own
`BEND_ONLY`) is a second change belonging to the oracle, not to this census.

**Pair 4, the census error.** `pairs.py` (coindependent's sweep) grouped string-sets that are
spelled in 2+ files. `ARMED` and `WANT` share three KEYS, not a fact. `ARMED`'s claim is about
`rows.pick3`'s dispatch arms (`disagree-gate.py:arms_wired`); `WANT`'s claim is about each graph's
run verdict. A graph can be armed and still disagree, or unarmed and agree (falling through to
`g_matmul()` and coincidentally matching). **A census that groups two different things is the same
defect as one that counts a shape** -- the sweep's criterion `(a) same string set in 2 files`
cannot tell a shared CLAIM from a shared VOCABULARY.

---

## 3. WHAT WAS LANDED -- one module, N consumers

**Module: `checks/coindep.py`** (tracked, beside the instruments; loaded BY PATH via
`importlib.util.spec_from_file_location`, the `gates/gendirs.py` shape). It holds one declaration
per SAME-FACT pair -- `ABI_OTHER_TOKENS`, `I64SHL_VALUES`, `SKIP_DIRS` -- and its docstring records
in full why pair 2 and pair 4 are NOT here.

| pair | module | files changed |
|---|---|---|
| 1 | `checks/coindep.py` | `checks/abi_gate.py`, `checks/abi4_gate.py` (both now `_coindep().ABI_OTHER_TOKENS`) -- **2 consumers** |
| 3 | `checks/coindep.py` | `gates/i64-shl-gate.py`, `gates/i64-shl-oracle.py` -- **2 consumers** |
| 5 | `checks/coindep.py` | `checks/no-strays.py`, `checks/unowned.py` -- **2 consumers** |
| 2 | -- | **0 -- deliberately left as two copies** |
| 4 | -- | **0 -- not the same fact** |

Verification that does not need `bend`: `py_compile` on all six edited files (OK); `checks/no-strays.py`
rc=0 and `checks/unowned.py --tsv` rc=0 after the change; the literal 9-string tuple no longer
exists in either abi gate (`grep -c '"p.hi"'` = 0 in both); `grep -c` of the token literals in
`abi_gate.py` is only the ABI-2 ARM ANCHORS (`JS_I64_OF_FST` etc.), which is expected and not the
fence.

---

## 4. THE PLANTS -- break the ONE declaration, both move; the loss stated honestly

`.agents/slop/pairs/plant.py` (output `.agents/slop/pairs/plant.out`), **17 checks, all PASS**.
No live file is written: the broken declaration is written to a scratch file and each gate's OWN
source is `exec`'d with its `coindep.py` path redirected there -- the same loader, a different path.

- **PAIR 1.** Both gates' fences `==` the declaration. `PLANT`: delete `pack64` from the
  declaration on the scratch copy -> `abi_gate` and `abi4_gate` both fall to **12 tokens**, neither
  can restore it, because the literal is gone from both (`assigns_from_coindep` reads the AST: RHS
  is `_coindep().ABI_OTHER_TOKENS`). `DISARM`: pristine has `pack64` in both. Fence FIRES on a
  crafted entangled arm carrying `pack64`; does NOT fire on a legitimate ABI-4 edit; FIRES on the
  widened `Number(` and the record tag.
- **PAIR 3.** The gate's `EXPECTED` is the declaration; the oracle derives its value NAMES from
  `_coindep().I64SHL_VALUES`. `PLANT`: drop `lowhi` -> the name set shrinks for both.
- **PAIR 5.** Both instruments' `SKIP_DIRS` equal the declaration; both source lines read
  `_coindep().SKIP_DIRS`.

**THE LOSS, STATED HONESTLY.** Before: two gates *could* hold different fences (they never did, and
nothing would have caught it -- the pair had no witness). After: they cannot disagree, and that is
the point. **What is lost is the ability to DETECT that they disagree -- but that ability did not
exist: nothing compared them.** So for pair 1 the sharing costs nothing real; for pair 5 the same
(no test compared the two `SKIP_DIRS` either). For pair 3 the loss is slightly more: the gate
could previously catch an oracle that dropped a value (the gate's `EXPECTED` was independent); now
the gate's name set is the oracle's. The DIFF still catches value mismatches, and the `rows=151`
count still catches a dropped row, so the loss is bounded -- but it is a real loss and is why pair 3
is the weakest of the three.

---

## 5. THE DENOMINATOR -- the whole tree, by `os.walk` (never the brief's five)

`.agents/slop/pairs/census.py` -> `.agents/slop/pairs/census.out`. AST string-lists of >=3 string
constants, canonicalised, appearing in >=2 files:

```
WHOLE TREE  (os.walk, SKIP=.git .venv __pycache__ node_modules references test tinygrad): 111
TRACKED     (.py in `git ls-files`):                                                        109
  of those, ALL sites under .agents/slop/ (scratch copies/plants):                           44
  TRACKED, >=1 site OUTSIDE .agents/slop/ (live instruments):                                 65
```

**Which count is right: BOTH, for their scopes.** `coindependent/pairs.py` walked `checks/` and
`gates/` only and found the five (plus a `DERIVED` list). This sweep walks the whole tree and finds
**111**, because `.agents/slop/` holds 44 all-slop duplicate lists (copies and plants). The brief's
five are the **live-instrument** subset; the whole-tree number is larger and the difference is
`scope`, not disagreement. **A census of a census is the same mistake as a census from a list: the
number is meaningless without the scope printed beside it.**

**The 65 "live" candidates classify into four shapes, not one** (naming the notable ones):

1. **COPIES / PLANTS of one instrument** (not pairs at all -- one file, duplicated into
   `.agents/slop/`): `checks/differ.py`'s artifact-name conventions vs
   `.agents/slop/corpuswire/tree/` and `.agents/slop/figure2/plant/`; `gates/gendirs.py` vs
   `.agents/slop/gendirs/writetargets.py`; `gates/i64-shr-oracle.py` vs `.agents/slop/ishr/`;
   `checks/citation-gate.py` vs `.agents/slop/stale269/`; `checks/substrate.py` vs
   `.agents/slop/substratepop/`; `checks/sweep.py` vs `.agents/slop/unknowns/`;
   `checks/abi4_gate.py` vs `.agents/slop/abi4check/` (a stale `HEAD` copy).
2. **PORT vs UPSTREAM ORACLE** -- the large class: `checks/llama.py` vs `examples/llama.py`;
   `checks/cli.py` / `checks/serve.py` vs `tinygrad/viz/cli.py` / `serve.py`;
   `examples/mlperf/losses.py` vs `tinygrad/mixin/op.py`; `checks/compile.py` vs
   `extra/dsp/compile.py`; `checks/fw_live.py` vs `extra/amdflash/fw_live.py`; `checks/cli.py`'s
   `CPU/NPY/PYTHON` vs `tinygrad/runtime/ops_*.py`. **This is the class a `remove duplication`
   reflex gets catastrophically wrong -- see §6.**
3. **SHARED EXCLUSIONS / EXTENSION SETS across genuinely independent tools**: the brief's pair 5,
   and the `.venv/node_modules/tinygrad` skip set in `checks/no-txt.py` vs four
   `.agents/slop/sloptxt/` readers; `gates/bc-u32-gate.py` + `gates/gatekit.py` + four more gates
   sharing `("bd","bn","py")`.
4. **THE BRIEF'S FIVE.**

**Honest limit.** The sweep's criterion is `(a) same string set in 2 files`; classifying all 65 by
CLASS needs the `(c) used-as-expectation` test *and* the human judgement of whether the two
predicates are the same fact -- which pair 4 shows the criterion cannot do mechanically. So this
report gives the **population by scope** (111 / 109 / 65) and **classifies the five the brief
named**; the remaining 60 are named by shape above, not one by one.

---

## 6. WHAT A SHARED DECLARATION COSTS -- where independence is worth MORE than agreement

`gates/gendirs.py` records the argument AGAINST doing this everywhere: *"two instruments holding
two lists have no authority over each other and their disagreement would be a third finding with no
way to settle it."* That is a virtue when a second instrument is a WITNESS. It is a rubber stamp
when the two copies are the same belief edited twice.

**Where independence is worth more, and why:**

- **PAIR 2 (`port_only` vs `BEND_ONLY`) -- the gate and its own oracle.** An oracle MUST NOT be
  told the gate's expectation. The gate's row-count check is only a measurement while the oracle
  independently declares what CPython cannot answer. Sharing here would convert a check into a
  tautology. **This is the pair the reflex gets wrong, and the brief's own warning, measured.**
- **THE PORT CLASS (`checks/*.py` vs `tinygrad/viz/*.py`, `examples/*`) -- by construction.** A
  PORT's whole claim is that it reproduces upstream's constants *by spelling them*, not by
  importing them. If `checks/serve.py` imported `tinygrad/viz/serve.py`'s lists, the port would
  agree with its oracle by construction and the port would measure nothing. **The duplication IS
  the test.** `AGENTS.md`: a shared population makes drift impossible, which is a virtue ONLY when
  drift is a failure; here drift is the DETECTION.
- **PAIR 4** is not independence worth keeping -- it is a grouping error.

**The line, therefore, is:** share when the two consumers are TWO INSTRUMENTS OVER THE SAME
FACTUAL POPULATION (pairs 1, 3, 5 -- neither is the other's oracle). Do NOT share when the second
consumer is the first's ORACLE (pair 2) or its UPSTREAM (the port class), because then the second
is supposed to be independent, and agreement-by-construction destroys the very comparison.

---

## Artifacts

```
checks/coindep.py                     the shared declaration (landed)
.agents/slop/pairs/probe.py  /  .out  /  .err    the 10th-token discovery + tree sweep
.agents/slop/pairs/plant.py  /  .out  /  .err    17 plants, all GREEN
.agents/slop/pairs/census.py /  .out             the denominator, by scope
```
