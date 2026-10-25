# `gates/pin-cite-gate.py`: THE ATTRIBUTION, THE THREE RULES, AND WHAT THE FIX COST

**The defect, in one paragraph.** `gates/pin-cite-gate.py`'s `window_tokens()` decides
WHICH CITATION a backticked name belongs to, and every class the census reports
(`at_pin`, `unverifiable`, `dangling`, ...) is read off a row's claim tokens. Its
docstring said **"A BACKTICKED NAME BELONGS TO THE NEAREST CITATION"** and its code kept
a name for citation `i` when the name was within 40 characters of some **OTHER**
citation -- so on a line with two citations the name went to the **FARTHER** one and was
**DROPPED** from the nearest. **A TOKEN ON THE WRONG ROW IS A ROW WHOSE VERDICT IS ABOUT
THE WRONG CLAIM**, so this was never a line-number bug: it decided which row was
`at_pin` and which was `unverifiable`.

**The measured instance.** `tinybendygrad/extra/models/clip.bend:105` reads

    "extra/models/clip.py:11 gelu = Tensor.gelu -- MISSING as a BODY; mixin/elementwise.bend:772
     has the CONSTANT ew_k.gelu and :1217 has `def ew_quick_gelu`, which is a DIFFERENT function"

Three citations on the line (`extra/models/clip.py:11`, `mixin/elementwise.bend:772`,
`:1217`), ONE backticked name. The name is **5 characters** from `:1217` and **42**
from `:772`. The shipped rule gave it to `:772` -- which holds NEITHER the name NOR the
claim -- and gave `:1217`, which HOLDS `def ew_quick_gelu`, nothing at all.

---

## THE THREE RULES, COMPARED

| | the rule | where |
|---|---|---|
| **1. the DOCSTRING** | a name belongs to the **NEAREST** citation | `gates/pin-cite-gate.py`'s `window_tokens` docstring, before this change |
| **2. the CODE (as shipped)** | a name belongs to citation `i` iff it is within **40 characters of some OTHER** citation `j != i` -- so the name goes to the **FARTHER** citations and is **dropped from the nearest** | the same function's body |
| **3. the REFERENCE** | a name belongs to the **NEAREST** citation; a name **EQUALLY** close to two belongs to **BOTH**; **no distance cutoff** | `gates/bendcite-gate.py`'s `_nearest_spans()` (committed `0832ac87a`) |

**RULE 3 IS RULE 1.** `gates/bendcite-gate.py`'s `_nearest_spans()` computes the
distance from the name's character range to every citation's range, takes the minimum,
and gives the name to every citation that reaches the minimum -- a tie goes to both,
and there is no cutoff. That is the docstring's rule, spelled out.

**RULE 2 IS THE INVERSE OF RULE 1**, and the inversion is not subtle: it asks whether the
name is near *somebody else*. MEASURED on the measured instance, the shipped rule gives
`ew_quick_gelu` to `:772` and takes it away from `:1217`; the fixed rule gives it to
`:1217` and takes it away from `:772`.

**THE TWO INSTRUMENTS NOW AGREE.** `gates/bendcite-gate.py` implements the rule itself
and says so in its own header ("THE NEAREST-CITATION RULE IS IMPLEMENTED HERE, AND THE
SHARED ONE IS NOT COPIED BECAUSE IT IS NOT THE RULE"). `gates/pin-cite-gate.py` now
implements the same rule. **TWO PARSERS THAT DISAGREE IS HOW A CENSUS'S NUMBERS STOP
MEANING ANYTHING**, and they no longer disagree.

### THE DIFFERENCES THAT REMAIN, PRECISELY

Two, and both are REPORTED rather than papered over:

1. **THE CUTOFF.** The shipped rule had a 40-character window (`_NEAREST`) and the
   reference has none. **The cutoff had to go, and it is GONE** -- see below. The
   reference also has a rule this file does not: it SKIPS a line whose number of
   backticks is ODD, because the backtick spans are then misaligned. This file does not
   skip those lines, and it did not before either.
2. **THE POPULATIONS DIFFER.** `gates/bendcite-gate.py` reads the port's INTERNAL
   `.bend` -> `.bend` pointers; this file reads the port's UPSTREAM `.py` citations.
   The same rule, two populations.

---

## WHICH RULE I CHOSE, AND WHY

**I CHOSE RULE 1 / RULE 3 (the nearest citation, ties to both, no cutoff), AND I CHANGED
THE CODE, NOT THE DOCSTRING.** The code's behaviour is **NOT** the correct one: the
measured instance is the proof -- a name that belongs to `:1217` was given to `:772`,
which is TRUE OF NEITHER. A rule that hands a claim to a citation that does not hold it
is wrong by construction, so the docstring stands and the code was wrong.

**THE CUTOFF WAS REMOVED, AND THAT IS A MEASURED DECISION, NOT A TIDY-UP.** The cutoff
was the one piece of the shipped rule that was not the inverse of the docstring's rule,
and MEASURED on one frozen tree it is destructive:

| the rule | `cite.at_no_revision_dangling` | `cite.upstream_removed` |
|---|---|---|
| shipped (inverted, with the cutoff) | 0 | 2 |
| nearest, cutoff applied UNIFORMLY | **21** | **0** |
| nearest, cutoff applied only where a line carries SEVERAL citations | 2 | 2 |
| **nearest, no cutoff (SHIPPED HERE)** | **2** | **2** |

A uniform cutoff takes the two `upstream_removed` rows out of their class -- the gate
can no longer SEE the claim token, so it cannot ask the evidence -- and it takes
**EIGHTEEN REAL CHECKS** with it: `tinybendygrad/runtime/ops_amd.bend`'s `WALL(p3)`
rows name their construct **47 characters** from the citation that holds it, and the
cutoff left them `uncheckable_no_claim_token`, i.e. **counted and not verdicted**. A
proximity rule with a cutoff is a proximity rule with a fudge. The reference
implementation has no cutoff, and neither does this one now. `_NEAREST` was DELETED --
a constant that no longer reads anything is a label.

---

## THE CLASS COUNTS, BEFORE AND AFTER

**BOTH READINGS WERE TAKEN ON THE SAME FROZEN COPY OF THE PORT TREE** (`--tree`), because
the port tree is owned by other units and moves under the gate's feet, and the rows were
paired **BY INDEX**. The freeze is `cp -R tinybendygrad .agents/slop/pinwindow/frozen/`;
the rows are `before.rows` and `after.rows` beside this report, and
`.agents/slop/pinwindow/diffrows.py` prints the pairing.

| class | BEFORE | AFTER | moved |
|---|---|---|---|
| `cite.total` | 2540 | 2540 | 0 |
| `cite.checkable` | 1596 | **1517** | -79 |
| `cite.uncheckable_no_claim_token` | 944 | **1023** | +79 |
| `cite.at_pin` | 1359 | **1261** | -98 |
| `cite.only_older_revision` | 4 | **28** | +24 |
| `cite.at_no_revision` | 231 | **226** | -5 |
| **`cite.at_no_revision_dangling` (THE FAIL CLASS)** | **0** | **2** | **+2** |
| `cite.ambient_relocated` | 0 | 0 | 0 |
| `cite.unverifiable_no_claim_about_the_file` | 224 | **207** | -17 |
| **`cite.upstream_removed`** | **2** | **2** | **0** |

**NO CLASS WAS WEAKENED AND NONE WAS SWEPT AWAY.** The `dangling` criterion is
untouched, the `upstream_removed` class and its two rows are untouched, and every other
class's CRITERION is untouched. **THE CLASS THAT SHRANK IS THE CLASS THAT WAS LYING:**
`at_pin` lost 98 rows because the shipped rule was INFLATING IT -- a row whose only
token belonged to ANOTHER citation was being read as holding the pin, and a row that
says nothing about its own file is not a row that holds the pin. `only_older_revision`
gained 24 rows for the same reason in reverse: the shipped rule DROPPED their names
and left them uncheckable, i.e. **counted and not verdicted**.

**THE FAIL CLASS GREW BY TWO, AND BOTH ARE PRINTED BY THE GATE.** They are not swept
into a holding class; they are the gate's findings.

---

## EVERY ROW THAT CHANGED CLASS

**160 of 2540 rows changed class** (337 rows changed their token set: 290 lost a token,
46 gained one, 2204 are untouched). The full per-row table, with each row's identity,
its class before and after, its tokens before and after, and the line it was read from,
is in `.agents/slop/pinwindow/movement.rows.out` (produced by
`.agents/slop/pinwindow/diffrows.py` from the two committed rows files).

| movement | rows | the classification, and why |
|---|---|---|
| `at_pin` -> `uncheckable_no_claim_token` | 93 | **MISATTRIBUTION.** The row's ONLY claim token belonged to another citation on the same line, so the row makes **no checkable claim** about its own file: counted, not verdicted. MEASURED examples: `tinybendygrad/codegen/decomp/dtype.bend:127` ("(dtype.py:47-50), `l2i_cdiv.abs` (dtype.py:47-50) and `l2i_cdiv.signed`" -- the names belong to the SECOND pointer), `tinybendygrad/codegen/decomp/transcendental.bend:133` ("`supports_float4` (renderer/__init__.py:67, set False by wgsl.py:59)" -- the name belongs to `:67`), `tinybendygrad/codegen/gpudims.bend:46` ("(:103) and `pm_range_to_special` (:103)"). **None of the 93 was in the fail class, and none of them is a failure now.** |
| `uncheckable_no_claim_token` -> `only_older_revision` | 19 | **MISATTRIBUTION (the shipped rule) -- THE FIX RESTORED THE CHECK.** The shipped rule DROPPED these names because the name was isolated by more than 40 characters from every OTHER citation on the line, so the row was counted and not verdicted. MEASURED: 17 of the 19 are `tinybendygrad/runtime/ops_amd.bend`'s `WALL(p3)` rows (`runtime/ops_amd.py:613` names `AMDKFD_IOC_ACQUIRE_VM` 47 characters away), plus `tinybendygrad/codegen/rewriter.bend:83` (`ops.py:497` and `_ranges`) and `tinybendygrad/runtime/ops_python.bend:51` (`ops_python.py:106` and `memoryview`,`arg`). **These are 19 rows that now hold at an OLDER revision, which is a HOLDING class: the port pinned an older upstream.** |
| `unverifiable` -> `uncheckable_no_claim_token` | 17 | **MISATTRIBUTION.** The row's tokens were the PORT's own vocabulary and they were the OTHER citation's; the row made no checkable claim before and makes none now. **Both classes are "counted, not verdicted", so no verdict was lost.** |
| `uncheckable_no_claim_token` -> `at_pin` | 9 | **MISATTRIBUTION (the shipped rule) -- THE FIX RESTORED THE CHECK, AND IT PASSES.** The shipped rule dropped these names and the rows were never checked; now they are, and they HOLD at the pin: `tinybendygrad/nn/optim.bend:64` (`mixin/op.py:1889`), `tinybendygrad/renderer/llvmir.bend:48` (`llvmir.py:165`), `tinybendygrad/renderer/ptx.bend:18`/`:20` (`ptx.py:180`, `ptx.py:210`), `tinybendygrad/runtime/ops_amd.bend:166` (`runtime/ops_amd.py:596`), `tinybendygrad/runtime/ops_cl.bend:165` (`tinygrad/runtime/ops_cl.py:108`), `tinybendygrad/runtime/ops_nv.bend:15` (`tinygrad/runtime/ops_nv.py:38`), `tinybendygrad/runtime/support/system.bend:94` (`tinygrad/runtime/support/system.py:88`), `tinybendygrad/schedule/prepare.bend:33` (`ops.py:1886`). **These are 9 NEW CONFIRMATIONS at the pin.** |
| `at_pin` -> `at_no_revision` | 8 | **FIVE MISATTRIBUTION, THREE REAL DEFECTS.** The two `tinybendygrad/mixin/op.bend:27` rows and `tinybendygrad/mixin/rand.bend:55` and `tinybendygrad/schedule/__init__.bend:121` and `tinybendygrad/tensor.bend:28` are the port's PARALLEL-LIST and POSSESSIVE prose, which proximity cannot pair with its pointer (see THE LIMITATION). The three REAL ones are named below. **`at_no_revision` is NOT the fail class** (the subject is a bare basename, so the census's directory ambient may have pointed it at the wrong file). |
| `at_pin` -> `only_older_revision` | 4 | **REAL, AND NOT A FAILURE.** The pointer is pinned to an OLDER upstream than the pin, which is the class's whole meaning: `tinybendygrad/mixin/creation.bend:33` (`ops.py:867` and `commit_dtype`), `tinybendygrad/runtime/support/hcq2.bend:109` (`tinygrad/runtime/support/hcq2.py:458` and `HCQInfo`), `tinybendygrad/schedule/__init__.bend:74` (`ops.py:1015` and `ops.py:1020`). |
| `at_pin` -> `unverifiable` | 2 | **MISATTRIBUTION.** The token is the PORT's own vocabulary (`Ops`,`SQRT` at `tinybendygrad/nn/optim.bend:59`; `commit_dtype` at `tinybendygrad/mixin/op.bend:29`), so the row makes no claim about the cited file: counted, not verdicted. **NOT a failure.** |
| `at_pin` -> `dangling` | 2 | **THE FAIL CLASS GREW. ONE REAL, ONE MISATTRIBUTION-DRIVEN.** Both are named below. |
| `uncheckable_no_claim_token` -> `at_no_revision` | 2 | **MISATTRIBUTION.** The name now belongs to this row and it does not hold: `tinybendygrad/extra/models/t5.bend:69` (`bert.py:235` and `erf`), `tinybendygrad/renderer/llvmir.bend:187` (`llvmir.py:20` and `lconst`). **Neither is in the fail class** (both subjects are bare basenames). |
| `unverifiable` -> `at_pin` | 2 | **MISATTRIBUTION (the shipped rule) -- THE FIX RESTORED THE CHECK, AND IT PASSES.** `tinybendygrad/extra/models/retinanet.bend:49` (`extra/models/bert.py:164` and `onehot`) and `tinybendygrad/mixin/op.bend:59` (`mixin/movement.py:614` and `_pool`). |
| `uncheckable_no_claim_token` -> `unverifiable` | 1 | **MISATTRIBUTION.** `tinybendygrad/codegen/decomp/dtype.bend:145` (`dtype.py:59` and `l2i_cdiv`,`abs`). **Both classes are "counted, not verdicted".** |
| `unverifiable` -> `only_older_revision` | 1 | **MISATTRIBUTION (the shipped rule).** `tinybendygrad/mixin/op.bend:29` (`tinygrad/dtype.py:220` and `sum_acc_dtype`,`commit_dtype`): the shipped rule read the row as holding `commit_dtype`, which is not in `dtype.py` at any revision, and the row passed at the pin **by coincidence**. It now holds at an OLDER revision on its own claim. |

### THE THREE REAL DEFECTS THE FIX EXPOSES

MEASURED against upstream at the pin (`5c2bf39d6c4b`):

1. **`tinybendygrad/extra/models/rnnt.bend:25`** -- the port writes
   "`class LSTMCell` (rnnt.py:88)". Upstream's `extra/models/rnnt.py:88` is
   `self.joint.l1.weight.assign(...)`, and the file's `LSTMCell` (upstream's OWN name at
   an older revision) is NOT on that line at ANY revision -- the gate measured
   `newest_rev=NONE`. The name is the NEAREST name to `:88`, so the row is judged by its
   OWN claim and it FAILS. **A REAL DEFECT: the pointer and the name disagree.** (Under
   the shipped rule the row passed on `cells` -- the OTHER name on the line -- which
   upstream held at `:88` in an OLDER revision, `dcee90aa3f1e`. **That was a
   coincidence about a different claim.**)
2. **`tinybendygrad/renderer/llvmir.bend:8`** -- the port writes
   "`_render_fn` (:231-235 symbol=_render_fn)", and upstream declares `_render_fn` at
   **`tinygrad/renderer/llvmir.py:173`**, not in `:231-235` (`:231` is inside
   `_render_kernel`, and `_render_footer` is declared at `:232`). **A REAL DEFECT: the
   pointer names the wrong range.** Its SIBLING row (`llvmir.py:232` and
   `_render_footer`) HOLDS at the pin, so the line is not stale -- the two pointers in
   it are crossed.
3. **`tinybendygrad/runtime/webgpu_call.bend:60`** -- the port writes
   "`tinygrad/runtime/ops_webgpu.py:95 `bg_entry` calls `dev.create_uniform(x)`". The
   cited line IS the call, but `bg_entry` is DECLARED at `:94` and the cited line does
   not name it. Under the corrected attribution the name `bg_entry` is the nearest name
   to `:95`, so the row is judged by its own claim and it FAILS. **THE VERDICT IS TRUE
   UNDER THE GATE'S OWN MODEL, and the model's limit is the finding**: `holds()` asks
   "does the cited LINE hold the name", and it does not ask "is the cited line INSIDE
   the construct the name declares" for a SINGLE-line citation (it asks it only for a
   RANGE). **The port can discharge this row by writing `:94-95`.**

### THE TWO ROWS THAT WENT RED, AND WHY ONE OF THEM IS NOT A PORT DEFECT

* **`tinybendygrad/mixin/op.bend:242`** -- the port writes
  "`mo_squeeze`'s negated test (mixin/movement.py:301); `mo_eqmul`'s `bool` against
  `int` (mixin/elementwise.py:611)". The names `mo_eqmul`, `bool` and `int` belong to
  the `:611` claim; the `:301` claim is in PROSE (`mo_squeeze` is not backticked), so
  the row makes NO CHECKABLE CLAIM and belongs in `uncheckable_no_claim_token`. Under
  the corrected rule `mo_eqmul` is 3 characters from `:301` and `bool` is an EXACT TIE
  (16 and 16), so the row is judged by two names that are not its own and it FAILS.
  **THIS IS A MISATTRIBUTION-DRIVEN FAILURE AND NOT A PORT DEFECT**, and it is the
  price of a proximity rule on possessive prose. It is REPORTED here rather than
  hidden, and it is the first thing the next agent should look at.

---

## THE LIMITATION, MEASURED: A PROXIMITY RULE CANNOT READ THREE OF THE PORT'S SHAPES

**THIS IS THE MOST IMPORTANT THING IN THIS REPORT.** The nearest rule is a PROXIMITY
rule, and this corpus's prose has three shapes that proximity cannot pair with a
pointer. Each is MEASURED, on a row in this very census.

1. **ONE NAME, SEVERAL POINTERS.** `tinybendygrad/renderer/llvmir.bend:8` writes
   "`_render_footer` (:232 symbol=_render_footer, :281 symbol=_render_footer)". The name
   is nearest `:232`, so the `:281` row loses its claim and becomes
   `uncheckable_no_claim_token`. **The name is about BOTH.**
2. **A PARALLEL LIST.** `tinybendygrad/mixin/op.bend:27` writes "`max`/`sum`/`prod`
   (reduce.py:73/:20/:47)". The names are paired with the pointers by ORDER. Proximity
   pairs them wrongly (`max` is 9 characters from the bare `:713` and 15 from
   `reduce.py:73`), and the census's own `BARE_RE` cannot even SEE `:20` and `:47`,
   because they follow a `/`. **THE PARSER LOSES TWO OF THE THREE POINTERS BEFORE THE
   ATTRIBUTION IS ASKED.**
3. **A POSSESSIVE.** `tinybendygrad/mixin/op.bend:242` writes "`mo_eqmul`'s `bool`
   against `int` (mixin/elementwise.py:611)": the name is CLOSER to the PRECEDING
   pointer than to its own.

**AND THE ROW THAT WENT RED BECAUSE OF SHAPE 3 IS THE ONE ABOVE.**

**THE MEASURED ALTERNATIVE, FOR THE NEXT AGENT, AND ITS PRICE.** A rule that gives a
name to the NEAREST citation **ON EACH SIDE** (so a name with a pointer to its left and
one to its right belongs to both, and a name with only one side belongs to that one)
keeps BOTH red rows green and keeps the shared claims. MEASURED on the same frozen
tree: `at_no_revision_dangling` **0**, `upstream_removed` **2**, `at_pin` **1298**,
`checkable` **1555**, 121 rows change class instead of 160. **IT IS NOT WHAT THIS
FILE SHIPS**, because it is NOT the docstring's rule and NOT
`gates/bendcite-gate.py`'s rule, and the tree's own doctrine is that the two instruments
must agree. **THE PRICE OF IT IS THAT THE TWO INSTRUMENTS WOULD DISAGREE.** It is
MEASURED and it is in `.agents/slop/pinwindow/probe.py` (`EACH-SIDE`), so the next agent
does not have to re-derive it.

---

## THE PLANT, AND IT GOES RED

`gates/pin-cite-gate.py --plant` grew an **ATTRIBUTION ARM**: ONE line, TWO citations,
ONE backticked name, and the name is MOVED from beside the first citation to beside the
second **by a text edit on a COPY of the file on disk** (never `git show HEAD:`), with a
**byte-identical copy** beside it.

    PLANT attribution: `prod` sits beside tinygrad/helpers.py:14 in the control and beside tinygrad/helpers.py:1 after the edit
    PLANT attrib       tinygrad/helpers.py:14 at_pin=HOLDS newest=95b7c56b426d class=at_pin                 tokens='prod' -- the cited line names `prod`
    PLANT attrib       tinygrad/helpers.py:1 at_pin=NO newest=NONE class=uncheckable_no_claim_token tokens='' -- the cited line is 'from __future__ import annotations'
    PLANT attrib-moved tinygrad/helpers.py:14 at_pin=NO newest=NONE class=uncheckable_no_claim_token tokens='' -- the cited line is 'def prod(x:Iterable[T]) -> T|int: return functoo'
    PLANT attrib-moved tinygrad/helpers.py:1 at_pin=NO newest=NONE class=dangling               tokens='prod' -- the cited line is 'from __future__ import annotations'
    PLANT attrib-twin  tinygrad/helpers.py:14 at_pin=HOLDS newest=95b7c56b426d class=at_pin                 tokens='prod' -- the cited line names `prod`
    PLANT attrib-twin  tinygrad/helpers.py:1 at_pin=NO newest=NONE class=uncheckable_no_claim_token tokens='' -- the cited line is 'from __future__ import annotations'

**THE ATTRIBUTION FOLLOWS THE NAME, AND THE BYTE COPY DOES NOT MOVE.**

**AND THE ARM IS RED UNDER THE OLD RULE.** A COPY of the gate with the shipped rule
written back into it (`/tmp/gates-broken/pin-cite-gate.py`, the copy pointed at the real
tree) answers:

    PLANT FAILED: the attribution control did not give `prod` to the first citation: [] / ['prod'];
    the attribution edit did not move `prod` to the second citation: ['prod'] / [];
    the attribution control's row does not hold at the pin: the cited line is 'def prod(x:Iterable[T]) -> T|int: return functoo'
    rc=1

**THE INVERSION IS VISIBLE IN THE OUTPUT: under the shipped rule the control's name sits
with the SECOND row and the moved name with the FIRST.** The fixed gate answers `rc=0`.

**THE PLANT'S GEOMETRY IS ASSERTED, NOT ASSUMED.** The arm refuses to pass if the name
is not UNIQUELY nearest one of the two citations, so it cannot pass on a tie.

---

## WHAT ELSE WAS CHECKED, AND WHAT MOVED

* **`gates/todo-cite-gate.py` READS `gates/pin-cite-gate.py` BY PATH** and uses ONLY its
  `load_census()`. Neither `load_census()` nor `claim_tokens()` was touched, so its row
  set is UNCHANGED: **1140 citations, 1107 RESOLVES, 0 WRONG-LINE, PASS (rc=0)**, the
  same as before the change.
* **`gates/bendcite-gate.py` READS IT BY PATH TOO** and uses only `claim_tokens()`,
  which this change does not touch (`git diff` mentions it ZERO times). MEASURED BOTH
  WAYS: with the HEAD `pin-cite-gate.py` beside it and with the patched one, bendcite
   answers the same thing -- **`FAIL -- 299 of 1251 internal pointers do not hold`** --
   so its verdict is PRE-EXISTING and this change did not move it. (bendcite implements
   its own rule and does not call `window_tokens()`.)
* **THE CORPUS DIGEST DID NOT MOVE**, because `gates/` is not in the substrate:
  `4090cdcf7210ddd906e77459a93a81d97ba6e8cf12cf6da984301a9330e9e362` before and
  after. (`checks/differ.py`'s `SUBSTRATE_WALKS` are `tinybendygrad` and `tinygrad`, and
  `SUBSTRATE_INPUTS` names `checks/differ.py`, `checks/devpin.py`, `bin/bend` and eight
  `.agents/slop/graphcmp*` files -- `gates/pin-cite-gate.py` is in none of them.)

---

## WHAT I COULD NOT MAKE TRUE, AND WHY

1. **THE GATE IS NOW RED, ON TWO ROWS, AND ONE OF THEM IS NOT A PORT DEFECT.** The fail
   class grew from 0 to 2. ONE of the two (`tinybendygrad/mixin/op.bend:242`) is a
   MISATTRIBUTION-DRIVEN failure: the row's own claim is in prose, so the correct
   class for it is `uncheckable_no_claim_token`, and a proximity rule cannot tell a
   possessive from a pointer. **THE FIX WAS NOT SUPPRESSED TO KEEP THE GATE GREEN** --
   a row that cannot go red is a label -- and the row is reported here and by the gate.
2. **93 ROWS LEFT THE `at_pin` CLASS, AND THAT IS NOT A WEAKENING.** They were holding
   the pin on ANOTHER CITATION'S TOKEN. Their own claim is not checkable, so the honest
   class is `uncheckable_no_claim_token` (counted, not verdicted) -- which is the gate's
   own doctrine: an unfalsifiable claim is not a passing claim. **THE CLASS THAT SHRANK
   WAS THE CLASS THAT WAS LYING.**
3. **THE PORT WAS NOT TOUCHED.** The three real defects above (`rnnt.py:88`,
   `llvmir.py:231-235`, `ops_webgpu.py:95`) and the two prose shapes the rule cannot
   read are in `tinybendygrad/`, which another unit is editing; they are REPORTED, not
   fixed here.
4. **THE SHARED CLAIM SHAPE IS NOT FIXED.** One name for several pointers loses the
   extra pointers' rows. A rule that keeps them is MEASURED (`EACH-SIDE`, above) and is
   NOT shipped, because shipping it would make the two instruments disagree.
5. **`.agents/TODO.md` WAS NOT TICKED IN THIS COMMIT.** `AGENTS.md` asks for it, and the
   protocol for this task says to commit only `gates/pin-cite-gate.py` and a report
   under `.agents/slop/`. `AGENTS.md` also records that `.agents/TODO.md` is the tree's
   HIGHEST-TRAFFIC SHARED FILE (61 of 131 commits since 2026-10-16), so the protocol's
   narrower clause wins and the tick is left to the session that owns the commit.

---

## THE ARTIFACTS

| path | what |
|---|---|
| `.agents/slop/pinwindow/probe.py` | the census under FOUR candidate rules, on one frozen tree: `OLD`, `NEAREST`, `NEAREST+CUTOFF`, `NEAREST+CUTOFF-1`, `SELF-NEAR`, `EACH-SIDE` |
| `.agents/slop/pinwindow/dump.py` | every row that changes class, with its tokens and its line |
| `.agents/slop/pinwindow/diff_rules.py` | the rows that tell `NEAREST` and `NEAREST+CUTOFF-1` apart |
| `.agents/slop/pinwindow/diffrows.py` | the row-level movement, before -> after, paired BY INDEX |
| `.agents/slop/pinwindow/before.rows`, `after.rows`, `live.rows` | the census's own rows, before, after, and on the live tree |
| `.agents/slop/pinwindow/movement.rows.out` | the 160 rows, one by one |
| `.agents/slop/pinwindow/plant.out`, `plant.err` | the plant's output, fixed and broken |
| `.agents/slop/pinwindow/frozen/` | the frozen copy of the port tree (LOCAL ONLY: it is in `.git/info/exclude`, so it can never be swept into a commit) |
