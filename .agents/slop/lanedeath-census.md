# LANE-DEATH CENSUS — how many red entries were substrate and not port

Report for the four-lane event (`schedule/prepare.bend`, `tensor.bend`, `uop/render.bend`,
`viz/serve.bend`, identical `expected : Arg / observed : Const`, def `t_const_bool_int_splits` in no
file on the tree). Machine count: `.agents/slop/lanedeath-census.py`. Mechanism and reproduction:
`.agents/slop/phantom-run.py`. Reporting change: `rebase-gate.py`'s
`import_closure` / `substrate_manifest` / `drift` / `error_site`. Control:
`.agents/slop/lanedeath-provenance.py`.

**Nothing under `tinybendygrad/` was edited. `uop/ops.bend` was not touched. Nothing was committed.**

---

## 1. THE MECHANISM, REPRODUCED

`bend` checks an **imported module**, so a lane's verdict is a statement about its whole **import
closure** and not about the file the sweep named. And `bend`'s error message names a **def** and
its **source line**, with **no file in it**. So the reader greps the file the sweep named, finds
nothing, and concludes the lane is broken.

Reproduced end to end by `phantom-run.py --event`, with the shapes **copied** from the live file
(`Arg` at `uop/ops.bend:1045`, `Const` at `:807`, `UOp.new` at `:2442`):

```
STEP 2/4  four lanes, four files, ONE message
  victim1.bend   rc=1  rows=0  - expected : Arg - observed : Const  |  Location: t_const_bool_int_splits
  victim2.bend   rc=1  rows=0  - expected : Arg - observed : Const  |  Location: t_const_bool_int_splits
  victim3.bend   rc=1  rows=0  - expected : Arg - observed : Const  |  Location: t_const_bool_int_splits
  victim4.bend   rc=1  rows=0  - expected : Arg - observed : Const  |  Location: t_const_bool_int_splits
  the four messages: 4 emitted, 1 distinct
STEP 3/4  the def is deleted
  the def `def t_const_bool_int_splits() -> Bool:` is in the substrate : False
STEP 4/4  the same four lanes, unchanged, on the same machine
  victim1..4.bend  rc=0  victim1..4=True
```

**Why four and not twenty-four.** All four lanes import `uop/ops.bend`; **24 of the 39 wired
ports** do. So 4 is not the blast radius.

* It is not **reachability**: `phantom-run.py` measured 2 error classes × 2 substrate shapes, 20
  lanes. A substrate defect kills **4 of 4** victims **and the bystander** — the bystander
  imports the substrate and calls a def that does **not** reach the phantom — in **2 of 2** cells
  for **both** classes. Propagation over the import is **eager**; a caller makes no difference.
* It is the **window**: `rebase-gate.py`'s `main()` walks its targets **sequentially**, so the
  blast radius of a substrate edit is *the number of lanes whose turn falls inside the edit's
  window*. `phantom-run.py --event-order`, over `_coord-sweep.json`: the four deaths are at
  **indices 45, 46, 47, 49 of 50**, with index 48 (`uop/weak.bend`) NOT-STARTED so no lane ran
  there at all. **The last 4 of 50.** The other 45 targets — 19 of them importers of `ops.bend` —
  were measured before the window opened.

### Candidates ruled out, and what ruled them out

| candidate | verdict | evidence |
|---|---|---|
| **stale compiled artefact** | **RULED OUT** | The message is a type error over **numbered source lines quoted from the file just read**. A `.bin` holds no source lines. And the four lanes' stems are `prepare`/`tensor`/`render`/`serve` — four **distinct** stems, so they never shared one path even under the old `/tmp/rebase-gate/{stem}.bin` spelling. (The stem collision was real — 131 files, 110 stems — and is `substrate-audit.py` S3, but it is not this event.) |
| **a cache holding a parse of a since-deleted def** | **RULED OUT** | `run_port()` is documented "All lanes, no cache"; `lane()` calls `sh(*argv)` with no cache read. Reproduced with a cache that has never existed. |
| **bend emitted an error referring to a def from a file that has since changed** | **THIS IS IT** | Reproduced above. |
| **the def name is synthesised from a call site in a file that did not exist** | **REFUTED** | The name `bend` prints is the name on the `def` line it quotes, and that line is on disk while the error is live. `--event` step 3 shows the same line, the same error text, and the def gone. |

### A second phantom, found mechanically

`lanedeath-census.py` found it with no prose at all: `_coord-sweep.json` (06:30) records the same
four ports BROKEN naming **`UOp.const_factor.seed`**, and `grep -rn "def UOp.const_factor"`
over `tinybendygrad/` returns **nothing**. `uop/ops.bend:7001` today is
`+f = UOp.copy_to_device(ar, 4, Some{1}, s5.dn(2))`. **A stored sweep is a measurement of a
revision, and its stderr names defs from that revision.** The two phantoms are the same failure
twice: `t_const_bool_int_splits` and `UOp.const_factor.seed`.

### One unresolved question, and what would settle it

`_coord-sweep.json` (06:30) records those four ports BROKEN with the **ELAB** class
(`message : a parameter or field scrutinee`, `Location:\n7001 | def UOp.const_factor.seed`), while
`.agents/TODO.md:4727` records the same four ports with the **TYPE** class
(`expected : Arg / observed : Const`, `t_const_bool_int_splits`), both at `BROKEN=6`. **Two
distinct substrate incidents, same four victims, same tally, different error text.** I cannot
order them from the artefacts: `_coord-sweep.json` is the only surviving machine record and its
mtime is 06:30, and `TODO.md` gives no clock for its per-entry run.

*What would distinguish them:* the sweep JSON for the `expected : Arg` run. Its absence is the
reason the `expected : Arg` claim is **quotation**, while the `UOp.const_factor.seed` one is
**measurement** — and only one of those two is evidence.

---

## 2. THE REPORTING CHANGE

Four functions in `rebase-gate.py`, all reading the lane's own import closure:

| function | what it answers |
|---|---|
| `import_closure(bend)` | which files this lane compiled **through** — raises `SubstrateUnreadable` rather than returning a short list |
| `substrate_manifest(bend)` | `[(path, sha256[:12], bytes)]` for that closure, read **now** |
| `drift(before, after)` | which closure files **changed while the lane ran** — `moved` / `added` / `gone` separately |
| `error_site(err, closure)` | for every def the error names: **which file, which line** — or `None`, unresolved |

`run_port()` takes a manifest **before** the first lane and **after** the last and compares them.
`stamp()` lifts the three fields out of `lanes` **before** `classify()` runs — the order is the
fix, and getting it wrong is recorded in `stamp()`'s comment, because `classify()` reads them.

Two things it deliberately does not do: it does not guess (an unresolved def is printed with the
closure's size beside it), and it does not rest on a single digest — **a digest says what the bytes
are, never when they were read**.

### Live, unplanted, on this tree

`rebase-gate.py --port tinybendygrad/uop/spec.bend`, while another unit was editing
`uop/fold.bend`:

```
BROKEN       tinybendygrad/uop/spec.bend
             cause=LANE-DEATH [INSTRUMENT]
             CAUSE: 2 of 4 runnable lane(s) did not run: interpreted rc=1: ... Resolved 2 of 2 named
               def(s) against 5 file(s) in the import closure; THE DEF IS IN
               tinybendygrad/uop/fold.bend, NOT IN THE PORT -- this is a SUBSTRATE death and the port
               is a victim of it. 1 of 5 closure file(s) CHANGED WHILE THIS LANE RAN
               (tinybendygrad/uop/fold.bend) -- the lane and the tree are not the same revision
    compiled 5 .bend file(s) in the import closure; working copy 592e4c97c0e8 slop(validate): ...
      1c05c98e7409     33280B  tinybendygrad/LAWS/spec.bend
      e91a9cbb4863    111371B  tinybendygrad/helpers.bend
      ef5bc244506b    362852B  tinybendygrad/uop/fold.bend
      bf4960e440f1    362124B  tinybendygrad/uop/ops.bend
      179e0df45cb0    157835B  tinybendygrad/uop/spec.bend
    ⚠ 1 of 5 closure file(s) CHANGED WHILE THIS LANE RAN: tinybendygrad/uop/fold.bend.
               SITE `interpreted`: bend named def `sym_dim.pa` -> tinybendygrad/uop/fold.bend:1250
TALLY BROKEN=1
      EXIT 1. working copy 592e4c97c0e8 ...
      1 distinct FILE(S) the failing lanes' errors resolve to, over 1 lane(s):
        tinybendygrad/uop/fold.bend   <- 1 lane(s): tinybendygrad/uop/spec.bend
```

This is the deliverable working on the real tree with **no plant by this unit**: the error's def is
in `fold.bend`, not in the port the sweep named, and the closure moved under the lane.

### The control — 7/7, and one cell proves the rest can fail

`lanedeath-provenance.py` plants into `.agents/slop/phantom-repro/planted/`, never into
`tinybendygrad/`. **7 of 7 cells, 0 skipped.**

| cell | asserts |
|---|---|
| C1 | plant in the **port** → the site names the port and its line (`port.bend:4`) |
| C2 | plant in an **imported** file → the site names **that** file (`:31`) and `cause_reason` says `NOT IN THE PORT` — **the event** |
| C3 | the def is **deleted** → the *same recorded text* re-resolves to `None`, over a closure of 2; a fresh run reports nothing. **The ghost is in the message, not a cache.** |
| C4 | no plant → no site, over a **non-empty** closure with **non-empty** digests |
| C5 | a closure file moves while the lane runs → the drift is **named** (thread churns; detected on attempt ≤6 of 6) |
| C6 | `drift()` driven with identical, one-changed, and one-added manifests — **the boring answer must be empty** |
| C7 | **with `error_site()` neutered, C2's own assertion must FAIL** |

C7 is the anti-disarming cell. It failed first for a real reason and that reason is the record:
`def sub.answer()` in the substrate made bend emit `expected : a defined name / observed :
Sub.answer`, so C4's lane still died — the control caught its own fixture being wrong rather than
reporting a pass. It also caught the gate's own wrong lift order (see `stamp()`).

Three defects this control found in the change, before it was ever green:

1. `stamp()` lifted the provenance fields **after** `classify()`, which reads them — so the
   verdict text never mentioned the substrate. Fixed, and the wrong order is recorded in place.
2. `substrate_line()` printed `⚠ 0 of 5 closure file(s) CHANGED…` on **every green run**, because a
   `drift` dict with three empty lists is truthy. A warning that fires on every clean run is a
   warning nobody reads.
3. `error_site()` read only the `def`-line rendering, so the ABlob incident (`Location:
   binary_n.of`, no `def` line) classified as **NO-DEF** — the census's first silent pass. There are
   **three** `Location:` renderings in this tree's record; all three are now read.

---

## 3. THE CENSUS — WITH ITS DENOMINATOR

`lanedeath-census.py`, over every JSON on disk that carries a `verdicts[]` list. **3 artefacts,
150 verdicts, 18 BROKEN entries.** Every line is `n of N`.

| bucket | entries | what it is |
|---|---|---|
| **SUBSTRATE** | **5 of 18** | the error's def is in an **imported** file. One edit, N victims, **0 defects** |
| **UNRESOLVED** | **4 of 18** | the error names a def that is **in no file of the closure** — a message about a revision of the tree that no longer exists |
| **PORT** | **1 of 18** | the error's def is in the port. A defect in a `.bend` file |
| **NO-DEF** | **8 of 18** | the error names no def (a disagreement, or the declared-dead `dtype.bend`) |

Per artefact:

* `dev-wholetree-2.json` (BROKEN=8): **5 SUBSTRATE, all resolving to `uop/fold.bend`**
  (`binary_n.of` at `fold.bend:1043`), **1 PORT** (`uop/fold.bend` itself), 2 NO-DEF. The note at
  position ~18065 called `engine/jit.bend` "truncated … so a text-only classifier files it as
  port-local. It is not" — this reader resolves it mechanically, to
  `tinybendygrad/engine/realize.bend`.
* `_coord-sweep.json` (BROKEN=6): **4 UNRESOLVED**, all naming `UOp.const_factor.seed`.
* `rebase/postrecord-2026-10-03.json` (BROKEN=4): **4 NO-DEF**. The prose says this tally
  included `device.bend` (which is clean, 21/21) and `cstyle.bend` (unwired, therefore
  NOT-STARTED) — **neither is a lane death at all**, and the classifier correctly refuses to call
  them one.

### The incidents behind the entries — 12 found, 8 explained, 4 not

Each with the evidence and its own denominator. **An unexplained one is not counted as substrate.**

| # | incident | lanes | explained? | evidence |
|---|---|---|---|---|
| 1 | `uop/ops.bend` `ABlob{n}` → `ABlob{bs}`, 04:18 mid-sweep | **6** | **YES** | `dev-wholetree-2.json`, 5 resolve to `fold.bend:1043`; notes ~18064 |
| 2 | `t_const_bool_int_splits`, `expected : Arg / observed : Const` | **4** | **YES**, but the artefact is gone | `TODO.md:4727`; reproduced by `phantom-run.py --event` |
| 3 | `UOp.const_factor.seed`, match-scrutinee at `ops.bend:7001` | **4** | **YES** | `_coord-sweep.json`; def gone from the tree |
| 4 | eight `nc_*` defs read an un-`+`-pinned binder twice | **3 named** ("fails EVERY file") | **PARTLY** — "3 of ≥3"; the "EVERY file" is unverified | `TODO.md:2734` |
| 5 | `fold.bend` mid-edit: `Kahn.get`, `perm.go`, `perm_step`, `g_mv_r23` | **1 each, 4 times** | **YES** — **the phantom class again**, by an agent's own report | `TODO.md:2014` |
| 6 | `UOp.const_factor.mul` cold-compile + duplicate `GroupOp.defines`, `ops.bend` mid-edit ~6 min | **4 probes** | **YES** | `TODO.md:6561` |
| 7 | `duplicate declaration: UOp.unbound.go`, then `a Some pattern with 1 field` | ≥1 | **YES** | `TODO.md:6309` |
| 8 | `cstyle.bend` compiled → unparseable at `:590`; `.bend` count 137→135 | **1** | **YES**, and **caught by the harness** (`SUBSTRATE MOVED`, run discarded) | `TODO.md:5073` |
| 9 | `fold.bend`, `movement.bend` transiently uncompilable **three times** | **2** | **NO** — the *effect* is named ("silently corrupted one baseline") and **no error text was recorded**, so it cannot be told from a port defect | `agent-core.md`, CONCURRENCY §1 |
| 10 | `codegen/decomp/dtype.bend` mid-edit (`jj status: M`) | ≥1 | **NO** — no error text recorded | `TODO.md:3368` |
| 11 | `codegen/__init__.bend` mid-write; the file did not compile for a revert | ≥1 | **NO** — no error text recorded | `TODO.md:4400` |
| 12 | `PROOF.bend` reported mid-edit | ≥1 | **NO** — no error text recorded | notes ~14325 |

**The denominator, stated three ways because they are not the same number:**

* **18 BROKEN entries** in **3 machine artefacts** — 5 substrate, 4 unresolved, 1 port, 8 with no
  def named.
* **12 incidents** named anywhere in `.agents/` — **8 explained** with error text or an artefact,
  **4 not** (9, 10, 11, 12). Those four are recorded as unexplained. They are **not** counted as
  substrate, because "another agent was editing" is a hypothesis and the project has already been
  charged for believing one.
* **9 incidents** of which this file can say anything at all with a **def name or a file name** in
  hand. Incidents 9–12 have neither.

**What would move the number.** A stored stderr for any of 9–12 turns an unexplained incident into
a classified one, and `lanedeath-census.py` will classify it the moment an artefact exists. That is
the whole argument for the change in §2: **the reporting is what makes the census possible**, and
four of twelve incidents are unclassifiable today only because nothing recorded where the error
lived.

### Port-side red entries, for completeness — 4, and all accounted for

* `codegen/decomp/dtype.bend` row `c7` — a **declared refusal**, and the **only** genuine
  DISAGREE in any artefact. Open as "OPEN, NOT MINE — `c7`".
* top-level `dtype.bend` — **declared dead on purpose**, wired so BROKEN is reachable.
* `baseline-DEMO.json`'s BROKEN=3 (`uop/spec.bend` 2 rows, `codegen/opt/search.bend` 5,
  `codegen/rewriter.bend` 3 row-name collisions) — **demonstration-baseline artefacts**, not
  findings. `baseline-DEMO.json` is excluded from the census for that reason.
* The six lanes that came back **green while disarmed** (`ptx`, `tc_ptx`, `generate`, `llvmir`,
  `nir_llvmir`, `cstyle`) — **not lane deaths**; an INSTRUMENT defect (a plant in the `py=` column
  while `row()` compares `left`). Recorded because it is the reason C7 exists.

---

## 4. THINGS I FOUND AND DID NOT FIX

1. **`rebase-gate.py` is contended and I touched it anyway, deliberately.** The brief allows it for
   the substrate-reporting change and this is that change. Four new module-level functions plus
   three call sites (`run_port`, `stamp`, `classify`), one printed block, one `--json` field
   (`revision`). `BASE_ORACLES`, `verdict()`, `targets_of()`, `plan_of()`, `record_stable()` and
   `never_wired()` are untouched. **A merge conflict here is expected and is not a defect in either
   side.**
2. **`substrate-audit.py` has no S5.** It audits four substrate-wrong instruments (S1–S4) and its
   own denominator line says "4 of the 4 … named in this round". This event is a **fifth** shape —
   *a lane whose verdict is about its import closure and says so* — and it is not in that file. Not
   added: `substrate-audit.py` is not mine this round.
3. **`BAND-19` prescribes an mtime manifest on both sides of a long run. That is necessary and not
   sufficient.** An mtime answers "did the tree change", which is not the question the four
   victims asked; the question is "was the tree the same tree", and `drift()` answers it with two
   content digests bracketing the lane. Both belong. I did not rewrite `BAND-19`.
4. **`_coord-sweep.json` still carries no `revision` field** and cannot be re-dated. Every sweep
   taken before this change is a measurement of an unnamed revision, and three of the four
   incidents above are only orderable by prose. New sweeps carry `revision`.
5. **`uop/ops.bend` is the single most contended file in the tree** and is under single ownership
   this round. 24 of 39 wired ports import it, 59 of 131 `.bend` files do. Any lane that dies with
   an error in it is now attributable **without opening the file**; that is the most this unit can
   do about it, and it is not mine to fix.
6. **The `uop/spec.bend` BROKEN above is real and not mine.** `uop/fold.bend` was being written
   during that run. The new reporting named the file, the line and the mid-run change; the lane
   itself is not a defect.