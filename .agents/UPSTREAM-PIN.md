# UPSTREAM-PIN.md — where the port stands against tinygrad

**This is the drift record.** `tinygrad/` is vendored into this repo as plain files with
**no history of its own**, so until this file existed there was no pin and "how far behind
are we" was not merely unrecorded — it was *unanswerable*.

Recompute at any time:

```bash
python3 .agents/slop/upstream-delta.py --fetch
```

## The pin

| | commit | date |
|---|---|---|
| **OUR PIN** — what the vendored `tinygrad/` actually is | `6c3d401cf324` | 2026-09-29 |
| **UPSTREAM HEAD** | `cff94ae8828d` | 2026-10-02 |
| **BEHIND** | **51 commits** | 122 files changed, 49 under `tinygrad/` |
| **PORT-RELEVANT CHANGED** | **31** | files we have a committed `.bend` for |

The pin was found **by content, not by assumption**: every one of our 230 vendored blobs is
hashed and compared against upstream's `tinygrad/` tree, walking history back until the
match count peaks. It peaked at **229/230**, not 230, and **is now 227/230** — see
`⚠ THE PIN HAS ALREADY MOVED PART WAY` at the bottom of this file. A drop here is the
signal that the vendored tree was edited without the pin moving, and it is the entire
reason this file exists.

**`tinygrad/runtime/ops_bend.py`** is the long-standing non-match: a local edit, flagged by
the script every run. Unresolved: it needs a decision (re-vendor from upstream, or keep
ours and document why), not a shrug.

**`tinygrad/dtype.py` and `tinygrad/runtime/ops_null.py`** are *new* non-matches as of
`d2cde2f2c`. They are half-applied re-vendors, not local edits, and the tree is broken
because of them.

## Why the pin is a *best* match and not an exact one

A vendored fork will drift from its source in two directions — upstream moves, and we edit
our copy — so an exact hash match is the wrong invariant. The invariant that matters is:
**the pin is the newest commit whose tree explains the most of our files**, and the match
count is reported every run so a regression in it is visible. If the count ever *drops*,
someone has edited the vendored tree without the pin moving, which is exactly the failure
this file exists to catch.

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

## ⚠ THE PIN HAS ALREADY MOVED PART WAY, AND THE TREE IS CURRENTLY BROKEN

Commit `d2cde2f2c` ("gate harnesses: four of them LIED") re-vendored `tinygrad/dtype.py`
and `tinygrad/runtime/ops_null.py` to HEAD **without the rest of their batches**. This is
the per-file anti-pattern, committed, and it is visible in the drift table above:

```
LOCAL EDITS not from upstream (3): tinygrad/dtype.py, tinygrad/runtime/ops_bend.py,
                                   tinygrad/runtime/ops_null.py
```

`ops_bend.py` is the known local edit. **`dtype.py` and `ops_null.py` are not** — they are
half-done re-vendors. The tree does not import as a result:

```
AttributeError: type object 'UPat' has no attribute 'custom_function'
  tinygrad/runtime/ops_null.py:57, in NullDevice
```

`ops_null.py` at HEAD calls `UPat.custom_function`, which HEAD `uop/ops.py` defines and the
pin does not. **That is B1's coupling, arriving file-at-a-time.**

`dtype.py` is B2's dependency and is genuinely at HEAD, but `renderer/cstyle.py` — its other
half — is still at the pin, and HEAD `cstyle.py` is what needs `dtypes.i8`. So B2 is half
applied in the safe direction and the tree survives that much only because `cstyle.py` has
not moved yet.

**To restore a working tree, finish B2 or revert B2.** Do not "fix" `ops_null.py` by
editing it; it is correct for HEAD and wrong only because its batch is missing.

The pin match count dropping from **229/230 to 227/230** is this, caught by the invariant
this file was written to protect. That is the check working.
