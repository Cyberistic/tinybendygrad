# UPSTREAM-PIN.md — where the port stands against tinygrad

**This is the drift record.** `tinygrad/` is vendored into this repo as plain files with
**no history of its own**, so until this file existed there was no pin and "how far behind
are we" was not merely unrecorded — it was *unanswerable*.

Recompute at any time:

```bash
python3 .agents/slop/upstream-delta.py --fetch
```

## The pin

**The pin is `6c3d401cf324` and it is NOT to be advanced while drift is open.** The table
below is what the tooling prints; recompute it rather than trusting it, because it has been
stale twice today.

| | commit | date | measured |
|---|---|---|---|
| **OUR PIN** — the commit the vendored `tinygrad/` is *based on* | `6c3d401cf324` | 2026-09-29 | 230 vendored blobs |
| **UPSTREAM HEAD** | `91b8cb5fa6c0` | 2026-10-02 | 59 commits ahead |
| **PIN MATCH** | **204/230** | | 26 blobs are past the pin |
| of which **HAND-EDITED** | **1** | | `runtime/ops_bend.py` — matches no upstream commit |
| of which **RE-VENDORED** | **25** | | a coupled batch landed; each equals a post-pin commit |
| **PORT-RELEVANT CHANGED** | **39** | | files we have a committed `.bend` for |

⚠ **THE PIN MATCH COUNT IS NOT A HEALTH SIGNAL, AND SAYING IT IS DROPS IS A BUG THAT HAS
ALREADY LANDED IN THIS FILE.** It counts *blob ≠ the pin's blob*, so it **falls every time a
batch is landed correctly** — 210/230 → 204/230 when B1's remainder landed. It also cannot
tell a hand edit from a correct re-vendor; that conflation is what made "LOCAL EDITS" read
20 when the true hand-edit count was 1. **The invariant is the HAND-EDIT count, and it must
be 1** (or 0, if `ops_bend.py` is resolved). See the bottom of this file.

The pin was found **by content, not by assumption**: every one of our 230 vendored blobs is
hashed and compared against upstream's `tinygrad/` tree, walking history back until the
match count peaks. It peaked at **229/230**, not 230 — the one file being `ops_bend.py`.

**`tinygrad/runtime/ops_bend.py`** is the long-standing non-match: a local edit, flagged by
the script every run, and now the *only* one. Unresolved: it needs a decision — re-vendor
from upstream, or keep ours and document why — not a shrug.

**Why the pin is a *best* match and not an exact one.** A vendored fork will drift from its
source in two directions — upstream moves, and we edit our copy — so an exact hash match is
the wrong invariant. The invariant that matters is: **the pin is the newest commit whose
tree explains the most of our files**, and the count is reported every run so that a
*hand edit* is visible. Re-vendoring is supposed to move a file away from the pin; that is
the batch working, not a regression, and the report now says so in those words.

## The number that matters: PORT-RELEVANT CHANGED

A changed upstream file with **no** port costs nothing — it is either out of scope or
unstarted. A changed upstream file **with** a committed port is **unexamined drift**: the
port was verified against the old source and nothing has looked at it since.

So every run of the script produces a work list, sorted by how much upstream moved:

```
python3 .agents/slop/upstream-delta.py          # the work list
python3 .agents/slop/upstream-delta.py --json   # for a gate
python3 .agents/slop/upstream-delta.py --files  # every changed file, not just ours
```

## The workflow for closing one drift

> **THE PER-FILE ADVICE BELOW WAS WRONG. It was replaced on 2026-10-02.**
> This file used to say "re-vendor just that one file". It does not work, and the
> failure was measured eight times before the sentence was removed. `--solo` reproduces
> every one of them on demand:
>
> ```bash
> .agents/slop/rebase-try.sh --solo tinygrad/uop/ops.py        # ImportError: axis_to_pos
> .agents/slop/rebase-try.sh --solo tinygrad/renderer/cstyle.py # AttributeError: dtypes.i8
> ```
>
> The error is not that upstream's commits are large. It is that upstream moves a **name**
> across a module boundary in the same commit that moves its user, so "one file" is never
> the unit that changes. `78d482262` deletes `AxisType.REDUCE` *and* rewrites every user of
> it; `793abbb16` renames `int8`→`i8` *and* the renderer that spells it. Per-file
> re-vendoring cannot express either. The unit is the **coupled batch**, and the batch is
> computed, not chosen — see below.

### Step 1 — compute the batches, do not guess them

```bash
python3 .agents/slop/rebase-plan.py          # name, attribute, rebind, tuple, signature
python3 .agents/slop/rebase-plan.py --json   # machine-readable, for a gate
```

The plan for the current window is written up, with evidence, in
`.agents/slop/rebase/REBASE-PLAN.md`. It is **3 coupled batches (17 + 2 + 1 required
files) + 20 independent singletons**, not 46 files: the batches are independent of each
other and each singleton is independent of everything else, so the work is steps you may
take in any order. **10 of the 46 files cannot be vendored alone at all.**

Coupling is computed at five levels, and a tool that only does the first one will look
right and be wrong — each level has already fooled us:

| level | what moved | measured failure |
|---|---|---|
| **name** | `from x import n`, `n` added / removed / rebound | `ops.py` alone → `ImportError: axis_to_pos` |
| **attribute** | `Cls.member` added / removed | `cstyle.py` alone → `AttributeError: dtypes.i8` |
| **attribute rebind** | `Cls.member` bound to a different container | `ops_cpu.py` alone → `'set' has no 'values'` |
| **tuple payload** | `arg=(a,b)` → `arg=(b,a)` | `rangeify.py` → `x.arg[0] + 1` is `AxisType + int` |
| **signature** | a def's parameter list | `heuristic.py` → `axes_of() got an unexpected keyword 'reduce'` |

The tuple level is why **an import probe is not a test**. Every `AxisType.REDUCE` use sits
inside a function body, so the tree imports cleanly and dies on the first kernel.

### Step 2 — confirm each batch empirically, out of tree

```bash
.agents/slop/rebase-try.sh --all          # build each batch in a throwaway tree and run it
.agents/slop/rebase-try.sh --shrink 1     # try to MINIMISE a batch, one file at a time
.agents/slop/rebase-try.sh --solo <file>  # vendor ONE file alone -- the negative control
```

This vendors nothing: it unpacks the pin into a temp dir, overlays one batch at HEAD, and
runs real CPython. It is safe to run with thirteen agents live, and it is the only thing
that settles a batch. `--shrink` matters because a derived batch is an upper bound —
batch 1 came out of the static pass as 21 files and shrinks to **17 required, 4 free**.

`--solo` is the **negative control**, and it is the mode that refuted the old advice: it
does exactly what this file used to tell people to do, one file at a time, and it fails
for **10 of the 46**. Run it whenever someone proposes a per-file re-vendor.

Three things the probe must do, all three of which it initially got wrong:

- **Import every `ops_*` module explicitly.** Under `DEV=NULL` five of the seven backends
  never load, so `--shrink` declared them droppable when each one in fact imports
  `encode_submit` and dies on load. A probe that cannot see a file is not evidence that
  the file is independent.
- **Assert only batch-independent invariants.** Asserting a name that only HEAD has makes
  an unrelated batch fail; asserting one that only the pin has makes the pin fail its own
  probe. Every name the probe mentions must resolve at both ends.
- **Run a program, not just an import.** Every deleted `AxisType` member is used inside a
  function body, so the broken tree imports cleanly and fails on the first kernel.
- **Import every module the CANDIDATE SET names**, not a hard-coded list. `DEV=NULL` never
  imports `codegen/opt/search`, so the probe of the file that BROKE THE IMPORT reported the
  same verdict for the broken file as for a good one — it never looked at it. That is how
  `search.py` sat at the pin, unimportable, with `rebase-plan.py` recording it CHANGED and
  no gate in the tree noticing: **every oracle touching `codegen/opt/` was dead or unwired.**
  `exercise` now derives the module list from the file list, because the hard-coded `ops_*`
  list was itself the bug being fixed.

#### ⚠ THE PROBE'S BASELINE WAS THE PIN, AND AFTER A BATCH LANDS THAT IS THE WRONG QUESTION

Every mode above builds *the pin* plus a candidate overlay. That was the right question
while all 230 blobs matched the pin. **After B1 and B2, 19 of them do not**, so "pin + file
set" no longer describes the operation anyone performs — the operation is
`git checkout upstream/master -- <files>` **applied to the working tree**.

`.agents/slop/rebase-try.sh` therefore grew `--from-work` and `--solo-work` (overlay on the
working tree) and `--shrink-work` (minimise an explicit file list against it). `--shrink`
against a plan batch is now the *wrong question* too: BATCH 1 is 23 files of which 8 were
already at HEAD, so shrinking all 23 minimises a set that includes 8 no-ops.

#### THE SIX FILES `--shrink` FOUND REQUIRED, AND WHY NINE MORE ARE NOT OPTIONAL

Shrinking the 15 that still differed gave **6 REQUIRED of 15**: `helpers.py`,
`support/hcq2.py`, `codegen/opt/search.py`, `ops_null.py`, `support/usb.py`, `ops_amd.py`.
The other nine probe **green without each other**, and landing only the six is a **silent**
semantic change:

```
                                        class table   instance table
6-file minimum                        3 rules        2 rules   <-- FORK
all 15                                 3 rules        ABSENT     <-- one table
```

Upstream moved `pm_bufferize` off the `Compiled` **instance** and onto the **class**:
`device.py@HEAD` only *declares* `pm_bufferize: Any = None`, `hcq2.py@HEAD` **defines**
`Compiled.pm_bufferize = PatternMatcher([...])`, and every backend **extends** it with
`Compiled.pm_bufferize += PatternMatcher([...])`. Our `device.py` still builds
`self.pm_bufferize` in `__init__` and our `ops_cuda/nv/qcom` still extend the *instance*
table. So with `hcq2.py` at HEAD and `device.py` behind, hcq2 reads the CLASS table while
the backends keep extending the INSTANCE one: **two rule tables for one job**, the per-device
placeholder rules never reach the bufferizer, and **a missing rewrite is not an error.**
Reproduce with `.agents/slop/rebase-pm-fork.py <repo> <files…>`.

**This is the sixth coupling level, and `rebase-plan.py` does not compute it:** not a name, an
attribute, a signature or a tuple payload, but *which module a shared attribute is DEFINED
in*. `rebase-plan.py` reports `ops_null.py -> device.py  use of NEW Compiled.pm_bufferize`,
which is true and not actionable; the load-bearing edge is
`device.py <-> hcq2.py <-> every ops_*`. Measured by `rebase-pm-fork.py`, not by an import
probe — **no probe can see this one**, because nothing raises.

`rebase-plan.py` also computes batches **pin → HEAD**, so once a batch is partly landed its
answer describes a move that is half already done. `.agents/slop/rebase-remaining.py`
classifies each vendored blob by *which commit it equals* and reports what is left; use it,
not `rebase-plan.py`, to decide the next step.

### Step 3 — declare one of four outcomes, per file

All four are legitimate, which is the point of stating them:

1. **RE-PORT** — upstream changed behaviour the port encodes. Re-run the port's gate
   against the new CPython, see which rows move, fix the defs those rows point at. A row
   that does not move is evidence the change did not reach ported logic — record that,
   do not assume it.
2. **RE-VERIFY, NO CHANGE** — upstream moved a comment, a name, or code the port treats as
   a seam. Record the check and move on. **This is a real result and must be written
   down**, because "we looked" and "nobody looked" are otherwise indistinguishable.
3. **RE-BASE** — the change is in `viz/`, `test/`, `extra/`, or a renderer we do not port.
   Nothing to do; the pin advances.
4. **SCOPE DECISION** — upstream added a file or a subsystem. That is an owner decision
   (`llm/`, `viz/`, the `isa` tables, `autogen/`), recorded in `.agents/TODO.md`, not
   something to absorb silently.

**Never "fix" the port by matching a diff without understanding it.** A gate row that
encodes upstream's bug is worse than a red file: it converts a loud failure into a silent
wrong kernel. If an upstream change looks wrong, that is an `UPSTREAM.md` entry, not a
port edit.

### Step 4 — declare one of three gate states, per port

Re-vendoring changes what every CPython oracle in the tree measures against, so "the gate
exited 0" does not answer "may I advance the pin?". Twelve committed files once printed
**0 rows** and nobody noticed for an hour, because a harness reporting zero *disagreements*
cannot tell "the port matches" from "nothing was compared".

```bash
python3 .agents/slop/rebase-gate.py --batch 1        # the gate, three states
python3 .agents/slop/rebase-gate.py --port tinybendygrad/dtype.bend
python3 .agents/slop/rebase-gate-selftest.py         # prove the states are reachable
```

| state | meaning | required evidence |
|---|---|---|
| **UNCHANGED** | zero rows moved | the gate prints **which hunks** were examined, so "we looked" and "nobody looked" are different bytes |
| **RE-PORTED** | rows moved, defs fixed | the moved rows now agree with CPython, listed by name |
| **BROKEN** | rows went to **zero**, or the oracle died, or rows disagree | named lane, and the baseline count it fell from |

A fourth, `NOT-STARTED`, exists for a port with no wired oracle. It is reported loudly on
purpose: silence is indistinguishable from success in every other tool, and a port that was
never checked must not be able to pass by being unmeasurable.

**How "rows went to zero" is detected** — three independent guards, because any one alone
has already been fooled here:

1. **Absolute count.** A per-port baseline row count is recorded. If now < baseline, rows
   were lost; a loss to exactly 0 is the incident. A *relative* check ("did any row move?")
   passes on an empty row set — that is the whole bug.
2. **Lane non-emptiness.** Every lane must yield at least one row. An oracle that exits 0
   having printed nothing is a *failed oracle*, not a passing one.
3. **No cache.** Every lane is re-run; a cached `0 rows` from an hour ago is
   indistinguishable from a fresh `0`.

`rebase-gate-selftest.py` produces each state on purpose — including the exact
210-rows → 0 shape — and fails if the gate cannot name it. A detector never shown failing
is indistinguishable from a detector that cannot fail.

#### ⚠ BATCH 1's GATE STATE IS `NOT-STARTED=23` AND THAT IS THE HONEST ANSWER

`rebase-gate.py --batch 1` returns **no** `UNCHANGED`, `RE-PORTED` or `BROKEN`: all 23 of
B1's ports are `NOT-STARTED`, 8 for want of a recorded baseline and 15 for want of a wired
oracle. **Do not fix this with `--record` while the reds are still red** — see below. Guard
1 was done by hand instead, and it passes:

| | before landing | after landing |
|---|---|---|
| 8 ports with oracles, row counts | 1,978 rows | **1,978 rows — identical, per port, per lane** |
| lanes that went to zero | — | **none** |

By-name comparison against CPython, using the gate's own row extractor and its own oracle
registry (`.agents/slop/rebase-rows-cmp.py <port> <oracle>`), which is the comparison a
recorded baseline would have made:

| port | shared rows | disagree |
|---|---|---|
| `runtime/support/hcq2.bend` | 157 | 0 |
| `uop/ops.bend` | 62 | 0 |
| `uop/spec.bend` | 11 | **2** — `te_len` 56/55, `fu_len` 71/70 |
| `runtime/ops_metal.bend` | 14 | 0 |
| `runtime/ops_nv.bend` | 543 | 0 |
| `runtime/ops_rdma.bend` | 389 | 0 |
| `codegen/rewriter.bend` | 41 | **3** — `rs_len`, `rs_claim_warp`, `rs_claim_loop` |
| `codegen/opt/search.bend` | 12 | **5** — `acts_n`, `acts_n_padto`, `acts_zero`, `zero_un9`, `zero_red0` |

**And every one of those 10 reds PREDATES the landing**, measured with
`.agents/slop/rebase-ab-oracle.py`, which rebuilds the pre-landing tree by blob and runs the
oracle on both: `rw-oracle.py` **0 of 55 rows moved**, `rebase-oracle-search.py` **0 of 12
moved**. The single row that *did* change is the one the whole batch was for —
`rebase-oracle-search.py`'s `#repro_vendored_import` went from
`AttributeError: type object 'AxisType' has no attribute 'UNROLL'` to `OK:209`.

So the reds are the **RE-PORT backlog**, not fallout from this landing. `--record` now would
write `acts_n=269` into a baseline as if it were the truth, which is precisely the
"a row that encodes upstream's bug" failure Step 3 warns about. **Record a baseline only
after the reds are fixed.**

## Cadence

tinygrad moves fast — **50 commits in 3 days** at the time of writing, and **31 of our
ports moved in that window**. So this is not a weekly chore. Re-run `--fetch` at the start
of a working session, and treat a non-zero PORT-RELEVANT CHANGED as a work list rather
than as background noise.

## Adding a pin advance

**Do not advance the pin while drift is open** — that is precisely how a port silently
falls behind, because the measurement stops being made. This file is edited but the pin
is **not** moved: 31 ports are still in unexamined drift and the drift is open.

When the delta is closed, advance the pin **one batch at a time**, never the whole tree at
once, and never before the batch's ports report a state from Step 4:

```bash
# 1. every port in the batch reports a state, and none is BROKEN or NOT-STARTED
python3 .agents/slop/rebase-gate.py --batch 1

# 2. re-vendor EXACTLY the batch -- not `tinygrad/`, not a file, all of one batch
git checkout upstream/master -- $(python3 .agents/slop/rebase-plan.py --json \
  | python3 -c "import json,sys; print(*next(b['files'] for b in json.load(sys.stdin)['batches'] if b['id']==1))")

# 3. re-run the batch's gates; rows must move to RE-PORTED, never to zero
python3 .agents/slop/rebase-gate.py --batch 1
```

Only once **no** port-relevant file is left may the pin be moved with a single
`git checkout upstream/master -- tinygrad/`, and only then is the table at the top of this
file updated.

**`git checkout upstream/master -- tinygrad/` on its own is the same mistake as per-file
re-vendoring, in the other direction.** It vendors files whose ports were never examined
and files with no port at all, so the pin moves while 31 unexamined ports stay unexamined
— the drift record then under-reports, which is worse than reporting it.

## ⚠ HISTORY: THE PIN MOVED PART WAY, AND THE TREE WAS BROKEN — BOTH NOW RESOLVED

**This section described a state that no longer exists. Read it as history; the current
numbers are at the top of this file and the tooling that produces them is
`upstream-delta.py`.** What follows is kept because the failure mode is the reusable part.

Commit `d2cde2f2c` ("gate harnesses: four of them LIED") re-vendored `tinygrad/dtype.py`
and `tinygrad/runtime/ops_null.py` to HEAD **without the rest of their batches**. This is
the per-file anti-pattern, committed:

```
LOCAL EDITS not from upstream (3): tinygrad/dtype.py, tinygrad/runtime/ops_bend.py,
                                   tinygrad/runtime/ops_null.py
```

`ops_bend.py` is the known local edit. **`dtype.py` and `ops_null.py` are not** — they are
half-done re-vendors. `ops_null.py` at HEAD calls `UPat.custom_function`, which HEAD
`uop/ops.py` defines and the pin does not, so `import tinygrad` raised
`AttributeError: type object 'UPat' has no attribute 'custom_function'`.

**"Do not 'fix' a file by editing it when it is correct for HEAD and wrong only because its
batch is missing"** is the rule that came out of this, and it held: `ops_null.py` was
finished by landing B1, never by hand-patching it.

### ⚠ "LOCAL EDITS" WAS A LIE BY CONFLATION, AND IT IS NOW SPLIT

The number in that block went **3 → 20 → 26** across two batches, and at no point did it
mean what its label said. "LOCAL EDITS not from upstream" is computed as *blob ≠ the
pin's blob*, which counts **two opposite things**:

* a file somebody **edited by hand** — the thing this invariant exists to catch;
* a file **correctly re-vendored** to a post-pin upstream state — the thing a batch is FOR,
  and which necessarily moves *away* from the pin.

Before any batch landed the two coincided, so a non-match really was a hand edit. Once
`ad117c92` and `e68c8eaa` landed they diverged: 20 "local edits" with **one** hand edit
among them. This file was then updated to describe 20 files that were 19 correct
re-vendors, which is how a stale warning becomes worse than no warning.

Landing B1's remainder took the count from **20 to 26** and the pin match from **210/230 to
204/230** — which reads exactly like the regression this file warns about, and is its
opposite. **A pin-match count that falls when a batch lands correctly is not a signal.**

`upstream-delta.py` now reports the two kinds separately, and only the first is an alarm:

```
⚠ HAND EDITS -- match NO upstream commit (1): tinygrad/runtime/ops_bend.py
RE-VENDORED past the pin (25): a coupled batch landed; these EQUAL a post-pin
                              upstream commit, which is the goal, not a regression.
```

`ops_bend.py` remains the one unresolved local edit. It needs a decision — re-vendor from
upstream, or keep ours and document why — not a shrug.


---

## APPEND 2026-10-03: THE MISSING-FILE ENUMERATION, AND TWO THINGS THE PIN DOES NOT SEE

Added, not substituted: **nothing above this line was edited.** The pin is not moved.

### THE ANSWER IS 0. WE WERE NOT MISSING FILES.

```bash
python3 .agents/slop/unvendored.py
```

| | count |
|---|---|
| upstream `.py` under `tinygrad/` at the pin `6c3d401cf324` | **213** |
| upstream `.py` under `tinygrad/` at HEAD `91b8cb5fa` | **213** |
| **MISSING at the pin** | **0** |
| **MISSING at HEAD** | **0** |
| missing non-`.py` blobs (the 9 js, 2 css, 2 html, `py.typed`, `.sh`, `.md`) | **0** |
| extra (ours, no upstream counterpart at that path) | 2 |

The pin and HEAD have the **same 213 paths** — `git diff --name-status 6c3d401cf324
upstream/master -- tinygrad/` reports only `M`, no `A` and no `D` — so "at the pin" and "at
HEAD" are one answer, not two. Cross-checked three ways so that a 0 is not one tool's opinion:
`comm` on the path lists, a basename comparison at **any** extension (empty, so nothing was
relocated and nothing was dropped), and a blob-hash walk.

**Nothing to classify, rank, or close.** There is no real gap and no ambiguous entry, because
the list is empty. The two extras are `tinygrad/runtime/ops_bend.py` (the declared local edit)
and `tinygrad/examples/beautiful_mnist.py`.

### ⚠ SO THIS ENUMERATION IS NOT THE INSTRUMENT FOR THE `DEV=MOCK` FAILURE, AND NEVER WAS
`DEV=MOCK` failed with `ModuleNotFoundError: No module named 'tinygrad.runtime.ops_mock'`
because `device.py:37` builds the module name dynamically as `ops_{x}`. **There is no
`ops_mock.py` upstream, so the set difference is EMPTY for it** — the measurement reports "no
gap" while the tree is one `DEV=` from a hard crash. A path-set difference can only find a
missing FILE; that failure was a missing NAME. `device.py:37` is the **only** site in all 213
files that constructs an importable module name at runtime.

The name space was therefore measured too, by **really importing** all 215 modules and really
checking every `from tinygrad.X import a`, with resolution delegated to CPython rather than
re-implemented:

```
215 modules imported · 0 missing modules · 0 missing names
  1 conditionally bound (NOT a gap): tinygrad.uop.ops.launch_viz
  4 dynamic import templates, 3 of them runtime/autogen/ (out of scope)
```

and the `DEV=` space closed by `dev-space-oracle.py`, **23 rows, exit 0**: every backend
upstream declares resolves to a `Compiled`, every `ops_<x>` we ship imports, and the only
`NO FILE` rows are names no upstream commit ever claimed. `WEBGPU` is `LOAD FAILS`, not a gap —
no WebGPU on this machine, which is a different thing from a missing file.

**`MOCK` is an INTERFACE, not a device.** `DEV` parses at `helpers.py:206` as
`[iface+]dev[:renderer][:arch]`, so `+` means **iface + dev**: `MOCK+CL` → device `CL`
(resolves), `CL+MOCK` → device `MOCK` (does not). Both were measured, because the asymmetry is
the whole explanation and it is not guessable from reading one of them.

### ⚠ A HAND EDIT NO TOOL IN THE TREE NAMES: `tinygrad/renderer/cstyle.py`
`unvendored.py` section 4 classifies provenance, and this file is the finding:

```
equals upstream HEAD                   189
equals the PIN (behind, correct)        23
equals NEITHER                          1   tinygrad/renderer/cstyle.py
```

`11217606b` matches **no commit in any ref** — not `upstream/master`, not any of the ~500
fetched upstream branches, not our own history. It is +31/-28 from the pin and +4/-4 from HEAD:
the pin→HEAD moves landed, and on top of them `CStyleLanguage.param_type` was **inlined into
its one caller and deleted**, and `type_map` hoisted into the class with subclasses composing
from it. Commit `e68c8eaa2` ("rebase B2") introduced it.

**It is a no-op, and only calling CPython established that.** Upstream's `param_type` passes
`_render_dtype(p.dtype, 1, p.addrspace, True, ...)` **positionally**; the inline passes the same
values by **keyword**. Evaluated side by side in one process over **240 (dtype × volatile ×
addrspace) triples: 0 differences** — `sz=1` and `mutable=True` are the defaults. So this is a
provenance defect, not a correctness one.

**Why it still matters, in two ways that are both load-bearing:**

1. `param_type` exists upstream at three sites and does not exist in our reference tree, so the
   1:1 naming rule ("def names match upstream exactly") is **unsatisfiable** for
   `renderer/cstyle.bend`, which indeed declares no `param_type`. The rule was violated in the
   reference tree, and the port inherited it.
2. **`upstream-delta.py` cannot see it.** That script reports `HAND EDITS (2)` naming
   `tinygrad/examples/beautiful_mnist.py` and `tinygrad/runtime/ops_bend.py` — and
   **`ops_bend.py` is not an upstream file**, so it can never appear in a walk over upstream's
   paths. The **HAND-EDIT invariant this file declares ("it must be 1") is therefore not
   measuring what it says it measures**: the count reads `2`, one of those two is outside the
   set being walked, and the one upstream file that genuinely matches no upstream commit is
   named by nothing. **A detector that walks the wrong side of the comparison reads healthy
   while the set it cares about has an unnamed member.**

**This is an owner decision, not an agent's** (SCOPE DECISION, Step 3): re-vendor `cstyle.py`
from HEAD and port `param_type`, or keep ours and record it beside `ops_bend.py` as the second
declared local edit. Either way the HAND-EDIT count needs to be computed over OUR files and
hashed against upstream history, not over upstream's files. **`renderer/**` belongs to another
agent; this was measured and reported, not edited.**

### `tinygrad/examples/beautiful_mnist.py` IS AT A PATH UPSTREAM DOES NOT HAVE
Byte-identical to upstream's `examples/beautiful_mnist.py` (`3826e625`), but upstream has **no
`tinygrad/examples/` directory at all** — `git ls-tree upstream/master -- tinygrad/examples/` is
empty. Staged, not committed, and added at 07:14 during this session, so it is most likely a
concurrent agent mid-task; `examples/` is out of scope regardless. **Reported, not touched.**

---

## APPEND 2026-10-03 (drift accounting): FOUR STATES, ONE PIN, AND ONE RETRACTION

Added, not substituted: **nothing above this line was edited. The pin is NOT moved.**

Everything below was measured by running a tool or by executing a source line in CPython.
Two of the numbers above this line are wrong and are corrected at the bottom rather than
in place, because this file is append-only and a corrected-in-place number is
indistinguishable from a number that was never wrong.

### THE PIN, AS ONE NUMBER, WITH ITS METHOD

```
PIN      6c3d401cf324   2026-09-29   204 of our 230 vendored blobs match its tinygrad/ tree
method:  content match. Hash all 230 of our blobs, compare against upstream/master's tree,
         for the last 400 commits; take the commit whose tree explains the most files, and
         on a tie take the NEWEST such commit.
ties:    3 commits score 204. The runner-up is 203, so the tie is broken by one blob and
         the pin is not sensitive to which of the three is chosen on evidence -- only to
         the stated tie-break rule.
```

`upstream-delta.py` **re-derives** this every run and prints it. There is no stored copy
to fall out of date, which is the whole point: the pin was a second number in two files
and both were stale within a day.

### FOUR STATES, NOT TWO. THE OLD "HAND EDITS" NUMBER WAS NOT COUNTING HAND EDITS.

| state | meaning | count |
|---|---|---|
| **A at pin** | untouched baseline | **204** |
| **B re-vendored** | equals SOME upstream commit in that path's FULL upstream history | **25** |
| **C HAND EDIT** | upstream HAS this path; our blob is at NO upstream commit | **0** |
| **D local-only path** | upstream has NEVER had this path -- a vendored-in fork, not an edit | **1** (`runtime/ops_bend.py`) |

`upstream-delta.py` used to fold **D into C**, and printed `HAND EDITS (1)` naming
`tinygrad/runtime/ops_bend.py`. That is not a coincidence and cannot be fixed by content:
for a path upstream has never had, `tree.get(path)` is `None` at every commit, so no
content can ever match and the file is reported however it was written. **The declared
invariant ("HAND-EDIT must be 1") was measuring the wrong bucket.** It now measures **C**,
which is **0**.

It also bounded the search to the last **120** commits of `upstream/master`. That made the
alarm's sensitivity a constant nobody chose: a blob equal to an upstream commit older than
the window is indistinguishable from a hand edit. The search is now each path's **full**
upstream history across **every fetched upstream ref**, which is exact — a file's content
only changes at a commit that changed it — and costs two git calls per path.

**What the alarm still cannot see, stated rather than implied:** it classifies content, so
a hand edit that reproduces a byte-identical upstream file is invisible, and so is a local
addition at an upstream path. The 1:1 NAME check is a separate question and lives in the
ports.

### RETRACTION: `renderer/cstyle.py` IS NOT A HAND EDIT, AND WAS NEVER ONE

The section above beginning "⚠ A HAND EDIT NO TOOL IN THE TREE NAMES" is **retracted.**
Its central fact — "`11217606b` matches no commit in any ref" — is **false.**

```
our blob    11217606b624cb8783c48e6eb34d086ec6d49201
equals      upstream 87a4311b3c3a  "dead codes cleanup [PR] (#18579)"  2026-10-02 08:51 -0400
checked by  git log --remotes=upstream -- tinygrad/renderer/cstyle.py   -> 642 commits
            git cat-file --batch-check over <commit>:<path> for each    -> 605 distinct blobs
            11217606b is among them
```

`renderer/cstyle.py` is a **correct re-vendor to an intermediate commit**, 9 commits behind
`upstream/master` (+4/-4). It is bucket **B**, and `unvendored.py` now says so.

**Two tools were wrong about it, in the same way.** `unvendored.py`'s `provenance()`
compared each blob against exactly **two** revisions — HEAD and the pin — and reported
everything else as "equals NEITHER". Landing a batch produces exactly an intermediate
commit, so the bucket that *is* a batch was the bucket that *looked* like a hand edit.
`provenance()` now resolves the middle case against the full upstream history, by calling
`upstream-delta.py` rather than reimplementing it: two tools answering one question
differently is how the same file got two opposite verdicts.

### `param_type` WAS ADDED UPSTREAM. WE DID NOT DELETE IT.

`renderer/cstyle.py:266` at `upstream/master` has `def param_type`. Our copy has zero
occurrences. **Upstream added it after the commit we vendored:**

```
git log --remotes=upstream -S"def param_type" -- tinygrad/renderer/cstyle.py
  e9a709ba4bf0  2026-10-02  remove warning (#18586)
```

Measured by constructing the class, not by grepping a comment:

```
CStyleLanguage(Target("NULL")) hasattr(lang, "param_type")
  pin 6c3d401cf324        False
  our-baseline 87a4311b3c3 False
  upstream/master          True
```

So the 1:1 naming rule **is satisfiable** for `renderer/cstyle.bend` against the tree it was
ported from, and **no exception is recorded**. What is real is one upstream def the port
does not yet have: a RE-PORT item, one name, owned by whoever owns `renderer/**`.
Reproduce both tables with `.agents/slop/drift-cstyle-head.py`.

### `--record` RUNS. THE BLOCK WAS A POLICY, AND THE REAL BLOCKER IS A ZERO-ROW LANE.

```
.venv/bin/python .agents/slop/rebase-gate.py --record --baseline .agents/slop/drift-record-probe.json
  -> recorded baseline for 3 ports; SKIPPED 47 targets with no oracle or no .bend file
  -> EXIT 0
```

It was written to a probe path, not to `rebase/baseline.json`, so the recorded baseline was
not touched. **Nothing mechanical blocks it.** What blocks adopting the result is that
`--record` faithfully records what the oracles currently emit, and right now:

| port | `interpreted` | `native` | `cpython:` lane |
|---|---|---|---|
| `runtime/support/hcq2.bend` | 360 | 360 | 163 (identical to `baseline-DEMO.json`) |
| `renderer/cstyle.bend` | 225 | 225 | **11, was 33** |
| `dtype.bend` | **0** | 0 | **0** |

`rebase-gate.py` already refuses a baseline with a zero-row lane ("baseline recorded ZERO
lanes for this port, so nothing can be compared against it"), so `dtype.bend` would record
a baseline that the gate then declares hollow. **Fix the oracle, not the recorder.**

The `cstyle` collapse is named by row, not by count — **25 rows lost, 3 new, 8 kept of
which 4 changed value**:

* `f32 val0 = ...` → `float val0 = ...`, `i32 val1 = ...` → `int val1 = ...` — `DType.name`
  spellings moved in the rendered source.
* `weakint g0 = get_group_id(0); /* 3 */`, `weakint l0 = ...`, `for (weakint gidx0 = ...)`
  — three rows, all lost.
* `k1_load_store.clang/.cuda/.metal`, `k4_smem.*`, `k5_special.ocl`, `k6_range`, `k7_cast`,
  `k8_stack.clang`, `k8_stack4.clang` — the multi-line per-renderer keys, all lost.
* changed in place: `k1_load_store` / `k2_alu` / `k3_consts` gained the `f32*`→`float*`
  spelling; `*(data0_1+0) = ...` and `*(data0_2+0) = ...` changed their whole RHS.

### STALE NUMBERS IN THE TABLE AT THE TOP OF THIS FILE

Recomputed today, all from `upstream-delta.py`:

| the table says | it is | why |
|---|---|---|
| HAND-EDITED **1** (`ops_bend.py`) | **0** hand edits; `ops_bend.py` is a local-only path (bucket D) | see above |
| RE-VENDORED **25** | **25** | correct |
| PIN MATCH **204/230** | **204/230** | correct |
| PORT-RELEVANT CHANGED **39** | **45** | upstream moved on; `--fetch` before believing either |
| "HAND EDITS (2) naming `beautiful_mnist.py` and `ops_bend.py`" | was true for one run; `beautiful_mnist.py` is gone from the index now | a concurrent agent, as that section says |

**One number, one place: `upstream-delta.py` is the only place any of these are written
down.** The table at the top of this file is a snapshot and should be read as one.
