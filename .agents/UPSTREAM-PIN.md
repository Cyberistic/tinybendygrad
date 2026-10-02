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
| **UPSTREAM HEAD** | `87a4311b3c3a` | 2026-10-02 |
| **BEHIND** | **50 commits** | 122 files changed, 49 under `tinygrad/` |
| **PORT-RELEVANT CHANGED** | **31** | files we have a committed `.bend` for |

The pin was found **by content, not by assumption**: every one of our 230 vendored blobs is
hashed and compared against upstream's `tinygrad/` tree, walking history back until the
match count peaks. It peaks at **229/230**, not 230.

**The one file that does not match is `tinygrad/runtime/ops_bend.py`** — a local edit or a
stale vendored copy, and it is flagged by the script every run. Unresolved: it needs a
decision (re-vendor from upstream, or keep ours and document why), not a shrug.

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

For each port-relevant changed file, in this order — and **all four outcomes are
legitimate**, which is the point of stating them:

1. **RE-PORT** — upstream changed behaviour the port encodes. The port's own gate is the
   acceptance test, so the fastest path is: re-run the file's gate against the *new*
   CPython, see which rows move, and fix the defs those rows point at. A row that does not
   move is evidence the change did not reach ported logic — record that, do not assume it.
2. **RE-VERIFY, NO CHANGE** — upstream moved a comment, a name, or code the port treats as
   a seam. Record the check and move on. **This is a real result and must be written
   down**, because "we looked" and "nobody looked" are otherwise indistinguishable.
3. **RE-BASE THE PIN** — the change is in `viz/`, `test/`, `extra/`, or a renderer we do not
   port. Nothing to do; the pin advances.
4. **SCOPE DECISION** — upstream added a file or a subsystem. That is an owner decision
   (`llm/`, `viz/`, the `isa` tables, `autogen/`), recorded in `.agents/TODO.md`, not
   something to absorb silently.

**Never "fix" the port by matching a diff without understanding it.** A gate row that
encodes upstream's bug is worse than a red file: it converts a loud failure into a silent
wrong kernel. If an upstream change looks wrong, that is an `UPSTREAM.md` entry, not a
port edit.

## Cadence

tinygrad moves fast — **50 commits in 3 days** at the time of writing, and **31 of our
ports moved in that window**. So this is not a weekly chore. Re-run `--fetch` at the start
of a working session, and treat a non-zero PORT-RELEVANT CHANGED as a work list rather
than as background noise.

## Adding a pin advance

When the delta is closed, move the pin forward by re-vendoring and re-running the script:

```bash
git checkout upstream/master -- tinygrad/     # re-vendor
python3 .agents/slop/upstream-delta.py --fetch
```

then update the table above. **Do not advance the pin while drift is open** — that is
precisely how a port silently falls behind, because the measurement stops being made.
