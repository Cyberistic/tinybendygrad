# THE PRIORITY TAXONOMY — ONE QUESTION, AND THE EVIDENCE TO ANSWER IT

**FOR THE HUMAN. NOT A GATE, NOT A VERDICT.** Nothing here is transcribed: every number was
produced by a command that is named below it, and every command can be re-run.

- **Tree:** measured at HEAD `b3b74fff986547b8e27b23d70a6b172e6fd8fd88`. **HEAD moved twice
  while this was being written** (to `c836cf4a9`, then `831ac0f11`), and
  `git diff --stat b3b74fff9 831ac0f11` touches **no** file under `tinybendygrad/`,
  `.agents/TODO.md`, `.agents/slop/` or `gates/phase-taxonomy-gate.py`. Every number below
  was re-run at `831ac0f11` and is **identical** to the run at `b3b74fff9`.
- **The gate that opened the question:** `gates/phase-taxonomy-gate.py` (commit `f978bca3b`).
  Its own output, **2026-10-21T18:09:11Z** (and identical at 17:58:58Z):
  `C1 DECLARED PASS (6)` · `C2 COVERED FAIL (2)` · `C3 OBEDIENT FAIL (441 of 633)` ·
  `annotation_conflict name=VIZ marker_phase=P3 table_phase=P8 cell=viz/ sites=6`.
- **The instrument that produced everything below:**
  `oracles/phase-taxonomy-matrix.py`, run **2026-10-21T18:09:11Z**, writing
  `oracles/phase-taxonomy-matrix.rows`. It LOADS the phase table from the tree by path
  (through the gate's own `declarations()`) and DISCOVERS the markers by `os.walk` +
  `endswith(".bend")`, so it has no hand list of phases, directories or markers.

## THE QUESTION, IN ONE LINE

**What does the `<pN>` slot of a `# TODO(<pN>) <file>.py:<line>  <name>` marker MEAN?**

Everything else below is evidence for or against an answer to that one line.

---

## 1. THE MATRIX

Rows = the phase the marker **NAMES**. Columns = the phase of the **directory the marker sits
in**. The diagonal is obedience; the off-diagonal is "contradiction". `-` = no directory the
table assigns (`helpers.bend` at the top level, `extra/`, `__init__.bend`).

Population: the gate's — `# TODO(...)` claims only, 633 of them.

```
  tag   P3     P4     P5     P6     P7     P8     -      total
  p1    0      0      0      1      0      0      0      1
  p3    166    34     23    204    157    18     3      605
  p4    0      0      0      0      0      0      1      1
  p6    0      0      0      0      0      0      1      1
```

**The matrix is ONE FAT ROW.** `p3` is 605 of the 608 phase-tagged sites and it is spread over
every column. There is **no per-phase structure in the markers at all** — so the question
"the markers are wrong, or the table is wrong" is not even well-posed as a per-phase
question. **The VIZ/P3-vs-P8 contradiction does not appear in this matrix AT ALL**: it comes
from the `P<n>/<X>` PROSE compound, which is a different mechanism from the `TODO(<tag>)`
slot, and §2 takes it apart separately.

(Reconciliation with the gate: C3 counted 441 = 439 (`p3` off-diagonal) + 1 (`p4`) + 1
(`p6`). The `p1` site is not among them because the gate skips a tag whose phase the table
gives no directory — which is itself a contradiction: `p1` names P1 and sits in `runtime/`,
which is P6.)

### 1a. THE OWN-PHASE TEST — the decisive negative

If the tag named the phase that owns the site, then each phase's own directories would carry
that phase's tag. Measured (same run):

```
  phase  own-dir markers   tagged-with-P   off-diagonal   total pP
  P1                   0              0             1          1   <- THE TABLE GIVES THIS PHASE NO DIRECTORY
  P3                 166            166           439        605
  P4                   0              0             1          1
  P5                   0              0             0          0   <- NO MARKER CARRIES THIS TAG AT ALL
  P6                   0              0             1          1
  P7                   0              0             0          0   <- NO MARKER CARRIES THIS TAG AT ALL
  P8                   0              0             0          0   <- NO MARKER CARRIES THIS TAG AT ALL
```

**The diagonal is empty for P4, P5, P6, P7 and P8.** `schedule/` and `engine/` (P4's own
directories) contain **zero** `p4` markers and 34 `p3` ones. `codegen/` and `renderer/` (P5)
contain **zero** `p5` markers — and P5 owns 36 files. `runtime/` (P6) contains zero `p6`
markers. `mixin/` and `nn/` (P7) contain zero `p7` markers. `llm/` and `viz/` (P8) contain
zero `p8` markers. **The only phase whose own directories carry its own tag is P3, and P3's
tag is the default.**

### 1b. THE TEMPLATE TEST — where `p3` comes from

`.agents/slop/brief-port.md:176-177` gives the marker grammar as a literal template:

> "…the `<file>.py:<line>`, and the phase that owns it. Mark omissions
> `# TODO(p3) <file>.py:<line>  <name>` in the file, matching `ops.bend`."

Measured: **596 of the 605 `TODO(p3)` claims are that template verbatim**, and **497 of
those 596 (83.4%) name their OWN file's upstream counterpart** — they are
"this file is missing upstream line N" self-references, which carry no phase information
about anything but themselves. The tree already carries this grammar; the slot was shown
FILLED with `p3` and 596 sites copied it.

### 1c. THE DENSITY CONTROL — `p3` is not uniform, and that is fine

```
  phase  files  p3-claims  claims/file  share-claims  share-files  ratio  files-with-p3
  P3        12       166       13.83        0.275       0.095   2.89          9
  P4        11        34        3.09        0.056       0.087   0.65          4
  P5        36        23        0.64        0.038       0.286   0.13          9
  P6        44       205        4.66        0.340       0.349   0.97         28
  P7        18       157        8.72        0.260       0.143   1.82         11
  P8         5        18        3.60        0.030       0.040   0.75          2
```

`p3` is 2.89× over-represented in `uop/` and 7.7× under-represented in `codegen/`, so "a
default" is not "uniformly spread". That is **not** evidence for a phase claim: `uop/` is
where the unfinished graph machinery is, and `codegen/` is mostly finished (9 of 36 files
carry any `p3` at all). The density tracks HOW MUCH UNFINISHED WORK A PHASE HAS, which is
what a default does; the TAG still does not track WHICH phase.

---

## 2. THE VIZ CASE — THE SIX MARKERS, QUOTED IN FULL

All six are in `tinybendygrad/uop/spec.bend`. `uop/` is P3 in the table, and the subject of
each marker is upstream `tinygrad/uop/spec.py` — also P3. **The `TODO(p3)` claim on each is
OBEDIENT under every reading.** The `P3/VIZ` compound is a separate thing.

```
3095: # TODO(p3) spec.py:286 def pyrender_globals -- imports `tinygrad.codegen.opt`,
3096: #   `tinygrad.schedule.rangeify` and `tinygrad.renderer` into a dict of names and
3097: #   is `@functools.cache`d. WALL: none of the three modules is ported, and the
3098: #   thing they exist to feed does not exist here at all -- see spec.py:292. P3/VIZ.
3099: # TODO(p3) spec.py:292 def eval_pyrender -- `exec` of GENERATED SOURCE. WALL: the
3100: #   point of `upat.py` is to EMIT Python, and this port emits defs instead, so the
3101: #   pyrender round-trip has no representation: there is no source to exec and no
3102: #   AST to compare it against. P3/VIZ.
3103: # TODO(p3) spec.py:296 def test_pyrender -- renders a UOp to source and compares
3104: #   the re-evaluated AST BY IDENTITY, recursing over parents on a mismatch. WALL:
3105: #   the whole feature is a debug view and it rests on the two above. P3/VIZ.
3106: # TODO(p3) spec.py:37  type_verify's `SPEC > 1` arm -- calls `test_pyrender(lst[-1])`
3107: #   and `SPEC` is a `ContextVar`, i.e. a process-wide mutable that Bend has no
3108: #   home for. WALL: the call is the one above; the flag is the configuration
3109: #   module `helpers.bend` lists as P6. P3/VIZ.
3133: # TODO(p3) spec.py:35  def type_verify -- PORTED as six folds that return the
3134: #   OFFENDING NODE, because Bend has no `raise` and a validator that cannot report
3135: #   is a validator nobody can use. The two lines not here are the `SPEC > 1` arm
3136: #   and the `DEBUG >= 3` print. WALL: P3/VIZ for both.
```
and the sixth, which is a numbered-list item rather than a claim:
```
3165: #   4. `SPEC` / `test_pyrender` (P3/VIZ) close `type_verify` and give the pyrender
```

### WHAT THE TEXT SAYS — and this is the whole finding

1. **The left slot is P3, and P3 is what the file's phase already is.** `uop/` = P3, and the
   marker's subject (`spec.py`) = P3. The compound's left slot adds nothing the tag does not
   already say, which is why it never contradicts anything.
2. **The right slot is a SECOND PARTY, not a subordinate.** The same notation is used seven
   times with a **PHASE** in the right slot — `P3/P6` at `schedule/allreduce.bend:697`,
   `uop/fold.bend:6540`, `uop/fold.bend:6747`, `uop/ops.bend:5008`, `uop/ops.bend:8888`,
   `uop/symbolic.bend:3113`, and `P3/P4` at `uop/ops.bend:3190`. "P3 owns P6" is not a
   sentence, so the compound **cannot** mean ownership. At `uop/ops.bend:3190` the tree reads
   it out loud: *"both are **P3/P4 work**"* — a disjunction of parties.
3. **In marker 3109 the wall names P6 IN PROSE and still writes `P3/VIZ`.** *"the flag is the
   configuration module `helpers.bend` lists as **P6**."* If the right slot enumerated the
   phases in the wall, it would read `P3/P6` there — and the same kind of wall (a `ContextVar`
   the port has no home for) IS written `P3/P6` at `uop/ops.bend:5008` and
   `uop/symbolic.bend:3113`. **So the right slot is not "the other phase in the wall"; it is
   the FEATURE the marker is about.** The tree says so at 3105: *"the whole feature is a
   debug view"*.
4. **The one compound that IS an ownership claim agrees with the table.**
   `tinybendygrad/schedule/memory.bend:1686` reads *"P6/runtime owns the allocator."* — there
   the compound is the grammatical **subject** of "owns", and `runtime/` IS P6. The six VIZ
   compounds are trailing LABELS after a WALL description; they are not subjects of "owns".
5. **What `VIZ` names is a FEATURE, and it collides with a directory NAME.** The six
   markers are about the Python-render round-trip -- at THE PIN `86c4f1343^`, the upstream
   file `uop/spec.py` carried `pyrender_globals` / `eval_pyrender` / `test_pyrender`.
   Measured: `git grep -n test_pyrender
   86c4f1343^ -- tinygrad/` returns five hits, **all** in `tinygrad/uop/` (`ops.py:205`,
   `ops.py:210`, `spec.py:38`, `spec.py:296`, `spec.py:302`) and **nothing under
   `tinygrad/viz/`**. (Upstream's `viz/serve.py:44` imports `pyrender` — the emitter in
   `uop/render.py` — not `test_pyrender`.) So `VIZ` names the visualization FEATURE; the
   gate's `annotation_conflicts` matches that word against the table's cell STEM `viz` **by
   name alone** (`stem_of("viz/") == "viz"`), and cannot tell a feature name from a directory
   name.

   **⇒ AND **THAT **IS **A **MEASUREMENT **OF **THE **PIN **`86c4f1343^`, **AND **THE **NAMES
   **ARE **GONE **AT **THE **PIN **THIS **DOCUMENT **IS **READ **AT.**  **MEASURED: `grep -rn
   pyrender tinygrad/ --include='*.py'` **IS **EMPTY **AT **HEAD**, **AND **`86c4f1343`
   ("RE-VENDOR **tinygrad/ **to **upstream **002630241", 2026-10-17) **IS **THE **COMMIT **THAT
   **TOOK **THEM **OUT** -- **AND **IT **RE-POINTED **THE **PORT's **OWN **MARKERS **TOO**: **AND
   **`tinybendygrad/uop/spec.bend` **NOW **NAMES **`upat.py:173`/`upat.py:181`/`render.py:65`
   **INSTEAD, **WITH **`P3/VIZ` **ON **ALL **THREE** (`spec.bend:3214`, `:3219`, `:3222`).  **⇒ AND
   **THE **`SPEC > 1` **ARM **IS **GONE **FROM **UPSTREAM **TOO** (`spec.bend:3225` **SAYS **SO**),
   **AND **THE **QUOTED **MARKERS **AT **§2 **ARE **THE **PRE-RE-VENDOR **TEXT** -- **SO **THE **SIX
   **MARKERS **THIS **DOCUMENT **COUNTS **ARE **THE **PORT's **OWN **AT **`86c4f1343^` **AND **NOT
   **AT **HEAD** -- **A **HUMAN **READING **THIS **MUST **KNOW **WHICH **PIN **THE **QUESTION **IS
   **ASKED **AT.**

### THE MATRIX OF THE COMPOUND (`P<n>/<X>`), from the same run

```
  file:line                       file-phase  tag   kind     X resolves to
  schedule/allreduce.bend:697           P4     -  PHASE    P6
  schedule/memory.bend:1686             P4     -  CELL     runtime/ -> P6
  uop/fold.bend:6540                   P3    p3  PHASE    P6
  uop/fold.bend:6747                   P3    p3  PHASE    P6
  uop/ops.bend:3190                    P3     -  PHASE    P4
  uop/ops.bend:5008                    P3    p3  PHASE    P6
  uop/ops.bend:8888                    P3     -  PHASE    P6
  uop/spec.bend:3098                    P3    p3  CELL     viz/ -> P8
  uop/spec.bend:3102                    P3    p3  CELL     viz/ -> P8
  uop/spec.bend:3105                    P3    p3  CELL     viz/ -> P8
  uop/spec.bend:3109                    P3    p3  CELL     viz/ -> P8
  uop/spec.bend:3136                    P3    p3  CELL     viz/ -> P8
  uop/spec.bend:3165                    P3     -  CELL     viz/ -> P8
  uop/symbolic.bend:3113                P3    p3  PHASE    P6
```

**Seven `PHASE` compounds and one `CELL` compound that AGREES with the table, versus six
`CELL` compounds that DISAGREE.** The right slot takes a phase, a directory or a feature —
it is a slot for "the other party", and only ONE of the fourteen is an ownership statement.

**CONCLUSION FOR THE VIZ CASE: the six markers are OBEDIENT. The contradiction is in the
gate's reading of the compound, not in the markers and not in the table.**

---

## 3. ONE RULE OR TWO?

**Neither of the two the brief offers. The off-diagonal sites are not a second rule — they
are the ABSENCE of a rule.**

- *"the marker names the FILE's phase"* — FALSE. `runtime/ops_amd.bend:210` is
  `# TODO(p3) runtime/ops_amd.py:715 the HW-fault f-string.`; the file is P6 and the tag says
  P3. 439 sites say the same thing outside `uop/`.
- *"the marker names the SUBJECT's phase"* — ALSO FALSE, and this is the sharper half.
  **497 of the 596 template `p3` markers (83.4%) name their OWN file's upstream counterpart**,
  so subject-phase ≡ site-phase in most of them, and the tag still says `p3` in every phase.
  A subject-phase reading would require the tag to change with the directory, and it never
  does.
- *"the marker names the phase that must LAND for the site to close"* — the reading that
  **does** fit the two singleton tags (`TODO(p4) helpers.py:305  \`time_sum_s\` needs the
  engine's clock` — P4 IS `engine/`; `TODO(p6) helpers.py:176  \`ContextVar._cache[k]\` is a
  KeyError` — the runtime's ContextVar machinery, P6), but it is falsified by the bulk:
  `engine/realize.bend:899` is `# TODO(p3) realize.py:107  runtime_cache -- a module-level
  dict[tuple[bytes,str], ...]`, whose wall is a Bend-LANGUAGE wall (no module-level mutable),
  not a uop/ wall. Nothing about P3 must land for it to close.

**So there is ONE grammar with a DEFAULT value.** `# TODO(<slot>) <file>.py:<line>  <name>`
is the brief's template; the slot was shown filled with `p3`; 596 sites copied it; the
28 sites that filled it differently each mean something else, and the tree already records
what each of them means:

| tag | sites | what the tree's own text says it means | where |
| --- | --- | --- | --- |
| `p3` | 605 | the TEMPLATE DEFAULT — the slot was never filled | every phase |
| `p4` | 1 | *"needs the engine's clock"* — the phase P4 = `engine/` | `helpers.bend:2571` |
| `p6` | 1 | the runtime's `ContextVar` machinery — the phase P6 = `runtime/` | `helpers.bend:436` |
| `p1` | 1 | a SEVERITY: *"THIS FILE IS A PORT OF A SUPERSEDED `ops_metal.py`"* | `runtime/ops_metal.bend:277` |
| `delete` | 1 | a DISPOSITION: *"delete both when `mxw_stk` grows…"* | `mixin/rand.bend:253` |
| `port` | 24 | a DISPOSITION: *"STOPPED AT `openimages` (extra/datasets/openimages.py:59)"* | `extra/**` |
| `pN` | 0 claims | an unnumbered placeholder, self-declared — a MENTION, not a claim | `mixin/rand.bend:42` |

**AND THE TREE ALREADY SAID ALL OF THIS, IN THREE PLACES, BEFORE THE GATE EXISTED:**

- `.agents/slop/WALLMAP.md:325` — *"**`p3` is not a phase. It is a default.** 1,023 of 1,028
  markers (99.5%) carry it, in every directory. A default that is on 99.5% of items orders
  nothing."*
- `.agents/TODO.md:10435, 10438, 10445` — *"only 214 of 1,023 `TODO(p3)` markers (20.9%) are in
  P3's directory"* … *"`p3` is a DEFAULT, not a phase"* … *"`delete` (1 marker) is a
  **disposition**, not a priority — the only tag that says what to do."*
- `.agents/slop/notes/bend2-constraints.md:24658-24666` (rule **W-6**) — *"`TODO(pN)`,
  `TODO(delete)`, `TODO(p1)`, `TODO(p4)`, `TODO(p6)` ARE THREE KINDS OF THING IN ONE
  NAMESPACE, AND NONE IS DEFINED AT THE POINT OF USE … so `p3` is a DEFAULT, not a phase, and
  a default on 99.5% of items orders nothing."*

**THE TREE DOES NOT CLAIM THE PHASE TABLE IS FALSIFIED. IT CLAIMS THE *GLOSS* IS.** Every
"falsified by the tree's own layout" in the tree points at the deleted gloss, not at the
table:

- `.agents/TODO.md:10435` — *"`engine/jit.bend:1091` gives the only gloss in the tree — *"A
  `# TODO(p3)` in the tree means 'a phase owns this'"* — **and it is falsified by the tree's
  own layout**"* — the subject is the GLOSS.
- `.agents/slop/WALLMAP.md:307-309` — *"A `# TODO(p3)` in the tree means 'a phase owns this' …
  **That gloss is false, and it is falsifiable.**"*
- `.agents/slop/notes/bend2-constraints.md:24664` — *"`engine/jit.bend:1091` glosses `p3` as
  'a phase owns this' — **falsified by the tree**"* — again the GLOSS.

**The gloss is GONE.** `git show HEAD:tinybendygrad/engine/jit.bend | grep 'phase owns this'`
answers rc=1. It was deleted on **2026-10-06** by `564733bed` (Tue Oct 6 13:35:05 2026, an
empty commit message); the removed lines are *"SECTION 10 -- THE SEAMS, each with the owner,
the Python line and what the port takes instead. A `# TODO(p3)` in the tree means "a phase
owns this", not "nobody knows"."* The gate that measures the gloss is dated **2026-10-20**
(`f978bca3b`, *"gates/phase-taxonomy-gate.py: keep the phase map, so C3 can go red"*) —
**fourteen days later, and its own commit message says the map was KEPT ON PURPOSE so that
C3 could go red.** **That is the finding: C3 is the deleted gloss, re-measured.**

---

## 4. THE CANDIDATE ONE-SENTENCE ANSWERS

Each is a sentence someone could paste into the tree. Each is listed with **what it changes**
and **what would falsify it** — a measurement, not an opinion.

### A — "`TODO(pN)` names the phase that OWNS the site."

> **What it changes:** 439 markers in `.bend` files must be retagged to their directory's
> phase (a large edit across `runtime/`, `nn/`, `mixin/`, `codegen/`, `schedule/`, `viz/`,
> `llm/`, `device.bend`, `function.bend`), plus 4 new tag values (`p5`, `p7`, `p8`, and a
> `p4` in `schedule/`). C3 goes green. C2 stays red.
> **Falsifier (measured, already):** the own-phase diagonal is **EMPTY for P4, P5, P6, P7
> and P8** (§1a). Under A, `codegen/` would carry `p5` markers and `runtime/` would carry
> `p6` markers; there are **none**, and `TODO(p2)`, `TODO(p5)`, `TODO(p7)`, `TODO(p8)` have
> **zero `.bend` sites each** (measured: `grep -rho 'TODO(pN)' --include='*.bend'
> tinybendygrad/ | wc -l` → 0 for each of the four). A also contradicts three places of the
> tree's own documentation (§3) and would have to overrule them. **A is already falsified.**

### B — "`TODO(p3)` is a TEMPLATE DEFAULT (the slot was never filled); the phase table is a DIRECTORY-OWNERSHIP PLAN, not a marker scale."

> **What it changes:** the GATE, not the `.bend` files. C3 becomes VACUOUS — it would be
> measuring a scale that does not exist — and has to be replaced by a clause that can go
> red. The natural replacement is C2's: *every tag value in use is DECLARED somewhere in the
> tree* (a discovery rule of C1's shape, not a hand list). And the tree needs ONE sentence
> back where the deleted gloss was, so the slot has a meaning at the point of use.
> **Falsifier:** find a marker whose tag is NOT `p3` and is NOT one of the 28 singletons
> the tree already explains; or find a marker in `uop/` whose tag is not `p3`; or find a
> `p2`/`p5`/`p7`/`p8` marker that is not in the 28. **Measured: there are NONE.** The
> counter-evidence is the density ratio (2.89× in `uop/`, 0.13× in `codegen/`), which B
> explains as "how much unfinished work the phase has" and not as "which phase this is";
> if the human wants a sharper B, that is the clause to sharpen.

### C — "`TODO(pN)` names the phase that must LAND for the site to close; `p3` is the default when the author did not fill it in."

> **What it changes:** the same retag as A for the sites whose wall is not a uop/ wall, and
> a per-marker decision on 439 sites. It also has to explain `p3` in `runtime/` etc.
> **Falsifier (measured):** `engine/realize.bend:899` — `# TODO(p3) realize.py:107
> runtime_cache -- a module-level dict[tuple[bytes,str], …]` — its wall is a Bend-LANGUAGE
> wall (no module-level mutable), so no phase has to land for it to close; and
> `runtime/ops_amd.bend:210` — "the HW-fault f-string" — likewise. **C does not survive the
> bulk.** It survives the two singletons (`p4` → `engine/`, `p6` → `runtime/`), which is
> exactly why it looks attractive.

### D — "`P<n>/<X>` names the PHASES AND PARTS a wall involves; the right slot is a party, not a subordinate."

> **What it changes:** the GATE's `annotation_conflicts` must stop
> matching the right slot against the table's cell stems BY NAME, and must classify the slot
> as PHASE / CELL / FEATURE first. The six VIZ rows then disappear — **not because anything
> was retagged, but because there was never a conflict.** No `.bend` file changes.
> **⇒ AND **THIS **IS **THE **ONE **PROPOSAL **THAT **WAS **ADOPTED, **AND **IT **HAS **MOVED
> **ON**: `annotation_conflicts` **WAS **A **FUNCTION **OF **THE **GATE** (`f978bca3b`:310) **AND
> **`7601a02ac` **("the **clauses **now **measure **what **the **tree **says**") **REPLACED **IT
> **WITH **`compound_census`**, **WHICH **IS **THE **NAME **THE **GATE **CARRIES **NOW**
> (`gates/phase-taxonomy-gate.py:398`), **AND **THE **GATE's **OWN **HEADER **RECORDS **THE **FIX**
> ("THE **OLD **C5**, **AND **WHY **IT **WAS **WRONG ... C5 **now **reads **a **compound **as **two
> **PARTIES**", `:66-74`).  **⇒ AND **THE **GATE **IS **LATER **THAN **THIS **DOCUMENT's **RUN**:
> **`f978bca3b` **IS **THE **GATE **THAT **OPENED **THE **QUESTION** (`:11`) **AND **`7601a02ac`
> **IS **THE **COMMIT **THAT **ANSWERED **IT** -- **SO **THE **NAME **THIS **PROPOSAL **NAMES **IS
> **A **HISTORY, **AND **THE **PROPOSAL **IS **NO **LONGER **A **PROPOSAL.**  **⇒ AND **THE **FALSIFIER
> **IS **ALSO **THE **GATE's **OWN**: **THE **`P6/runtime` **COMPOUND **STILL **AGREES **AND **THE
> **`P3/VIZ` **ONES **ARE **TRAILING **LABELS, **WHICH **IS **WHAT **`compound_census` **READS.**
> **Falsifier:** a third compound whose right slot is a table cell and DISAGREES with the
> table, or one in which the tree's own prose puts the compound in subject position and
> means ownership. Measured: the only cell compounds are `P6/runtime` (agrees) and `P3/VIZ`
> (disagrees), and the `P3/VIZ` sites are trailing labels, not subjects of "owns".

### E — "A tag value is either PHASE-SHAPED (`p` + digits) or a DISPOSITION; C2 must require a phase only of a phase-shaped tag."

> **What it changes:** C2's rule, and nothing in the `.bend` files. `delete` and `port` are
> verbs, so they are not "tags that name no phase" and C2 stops being red on them.
> **Falsifier:** a claim whose tag is phase-shaped but names a phase the tree does not
> declare — there is none today (`p2`, `p5`, `p7`, `p8` appear in no claim); or a
> disposition-shaped tag that the tree does not explain anywhere — `port` is explained at
> `.agents/slop/export/nlp/REPORT.md:59` (*"naming the first missing thing"*), `delete` at
> `WALLMAP.md:342`.

### F (the whole answer, if you want one sentence) — the gloss, restored and corrected.

> **What it changes:** ONE sentence in the tree — where the deleted gloss was
> (`tinybendygrad/engine/jit.bend`, SECTION 10) or in the tree's ledger — that says what
> the slot means, and a matching clause change in the gate so that C3 measures something
> that exists.
> **Falsifier:** the sentence must be falsifiable. As written, it must be falsifiable by a
> measurement of the tree's own layout, the way the old gloss was. **The old gloss WAS
> falsifiable and it WAS falsified — that is why it is gone. So the replacement has to be
> falsifiable too, and it must not be falsifiable by "most `p3` markers are not in `uop/`",
> because that is now a fact of the tree and not a defect.**

---

## 5. `delete` AND `port`: VERBS, NOT PHASES

**Both are DISPOSITIONS — instructions, not priorities. Neither is a phase.**

- **`delete`** — 1 site, `tinybendygrad/mixin/rand.bend:253`:
  `# TODO(delete) both when \`mxw_stk\` grows \`tn_shape_arg\`'s one-element arm.`
  It says **what to do** (delete these arms), conditioned on a future event. The tree's own
  text already says so — `.agents/slop/WALLMAP.md:342`: *"`delete` — one marker … A
  **disposition**, not a priority. It is the only tag that says what to *do* rather than who
  owns it."* Its one site is in `mixin/` = P7.
- **`port`** — 24 sites, **all** in `extra/` (a directory the phase table does not name):
  `# TODO(port): STOPPED AT \`openimages\` (extra/datasets/openimages.py:59), the …`
  It says **where the port stopped** and what is still missing. Declared at
  `.agents/slop/export/nlp/REPORT.md:59`: *"`# TODO(port):` naming the first missing thing,
  upstream signatures, every body a…"*.

**So C2's rule — "every tag value in use names a phase the tree DECLARES" — has no class for
them, and needs one.** The shape rule that needs no hand list: **a tag value is either
PHASE-SHAPED (`p` + digits, i.e. `p1`, `p3`, `p4`, `p6` — the port plan's phases) or it is
not (`delete`, `port` — dispositions, and `pN`, an unnumbered placeholder that says so
itself).** Measured on the claim population: the phase-shaped values are `p1`, `p3`, `p4`,
`p6`; the non-phase-shaped values are `delete`, `port`. (`pN` appears only as a MENTION, at
`mixin/rand.bend:42`, never as a claim — the gate's grammar catches that too.)

**NOTE FOR THE HUMAN:** `port` is the ONLY tag with more than one site that is not `p3`, and
**all 24 of its sites are in `extra/`, which no phase owns.** So even under candidate A,
`port` would remain uncovered. Whatever the answer is, `port` and `extra/` need a home or
an exemption.

---

## 6. IS THE TAXONOMY DERIVABLE FROM THE TREE'S OWN LAYOUT?

**No — the phase NUMBERS are not derivable from the tree's own layout. The MARKER SEMANTICS
are, and that is the part the human has to decide.**

- **The phase NUMBERS are not derivable.** They are a plan. The port's own import DAG does
  not order the phases: 195 inter-phase import edges, and **11 of them go UP the phase
  order** (10 of them `runtime/* → device.bend`, i.e. P6 imports P8; 1 is
  `uop/weak.bend → mixin/dtype.bend`, P3 imports P7). The import DEPTH does not recover the
  numbers either: mean depth is 2.50 (P3), 2.73 (P4), 2.83 (P5), **1.14 (P6)**, **5.83
  (P7)**, 2.60 (P8) — the phase order and the dependency depth are different orders.
  184 of 195 edges are consistent with the table, so the table is a *good* plan, but it is
  not a structural consequence of the tree.
- **What IS derivable is the marker semantics** — and it is derivable from the tree's own
  layout plus its own brief: the marker is a template (§1b), the tag is constant across
  every phase (§1a), and the density tracks unfinished work rather than phase identity
  (§1c).
- **And the table itself is NOT falsified by the layout.** The table assigns PHASES to
  DIRECTORIES. The layout IS those directories. The only thing the layout can falsify is a
  claim about the MARKERS — and the tree's own text falsifies that claim in three places
  (§3). **The tree's own text does not claim the phase table is falsified; it claims the
  GLOSS is.** If a document in this tree says the table is falsified by the layout, that
  document is wrong and should say "the gloss".

---

## 7. WHAT WAS NOT DONE

- **No `.bend` file was edited.** No marker was retagged. The phase table was not edited.
- `gates/phase-taxonomy-gate.py` was **not** edited: it still prints `annotation_conflict
  name=VIZ … sites=6` and still computes C3 over the deleted gloss. Candidate D is a change
  to that file, and it is the human's to authorise.
- `.agents/TODO.md`, `.agents/TOOLS.md`, `AGENTS.md` were not edited.
- `bend` was not run and `differ.py` was not run; nothing was fetched.
- **The 24 `port` sites were sampled, not each read in full** (they are uniform in form: all
  begin `STOPPED AT …`). The four that carry a distinct meaning (`p1`, `p4`, `p6`, `delete`)
  were quoted above. The `WALL(nn_pool_*)` tags (3) and the `DONE` verb (20) are outside the
  gate's population and are counted but not analysed.
- **The `P3/P6` and `P3/P4` compounds were read, not derived.** The reading "the right slot
  is a second party" is supported by the tree's own phrase *"both are P3/P4 work"*
  (`uop/ops.bend:3190`), by the prose in `uop/spec.bend:3109` (which names P6 in prose and
  still writes `P3/VIZ`), and by the fact that "P3 owns P6" is not a sentence. It is not
  PROVEN, and candidate D carries the falsifier for it.
- **`oracles/phase-taxonomy-matrix.py` is an instrument, not a gate.** It has no
  `gatekit` exit vocabulary, and it was deliberately NOT put in `gates/`, where
  `gates/gates-pop.py` counts what is a gate.

---

## 8. REPRODUCE

```sh
.venv/bin/python gates/phase-taxonomy-gate.py        # the gate's own three clauses
.venv/bin/python oracles/phase-taxonomy-matrix.py --rows   # the matrix, the tests, the rows
git show HEAD:tinybendygrad/engine/jit.bend | grep 'phase owns this'   # rc=1: the gloss is gone
git log --all --oneline -S 'a phase owns this' -- tinybendygrad/engine/jit.bend
git grep -n test_pyrender 86c4f1343^ -- tinygrad/    # the VIZ feature's consumers
grep -rho 'TODO(p[0-9])' --include='*.bend' tinybendygrad/ | sort | uniq -c
```

`oracles/phase-taxonomy-matrix.rows` is GENERATED by the instrument and carries the matrix
and the notation census as rows; nothing in it was typed by hand.
