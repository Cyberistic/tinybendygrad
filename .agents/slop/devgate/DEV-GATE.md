# DEV-GATE — `DEV` assigned after the import it configures is a COMMENT, not a setting

2026-10-04. Nothing committed. NEW files only (`devgate/`) plus ONE other unit's oracle,
`oracles/mm-range.py`, which the brief assigned. Rule prefix **`DEVG`**.

    devgate.py            the classifier + four modes: --plants --heldout --check --why --crosscheck
    CLAIM-devgate.md      the claim, written before the code
    ../oracles/mm-range.py  FIXED: asked NULL, got NULL, proved by its printed device

```
python3 .agents/slop/devgate/devgate.py . --check        # rc 1 iff some file assigns DEV after importing
python3 .agents/slop/devgate/devgate.py . --why          # per-file write line -> boundary line
python3 .agents/slop/devgate/devgate.py . --crosscheck   # AST vs an independent regex scan
python3 .agents/slop/devgate/devgate.py --heldout        # the error rate
```

## 1. `mm-range.py` — FIXED, and proved by the device it prints

`od -c` on line 1 of its output, verbatim: `d e v i c e :   N U L L \n`.

The minimal fix: `os.environ['DEV'] = 'NULL'` moved from `:59` to **`:14`, above the
`from tinygrad import …` on `:15`**. Four insertions, three deletions, nothing else touched —
no graph, no tally, no `walk()`.

**It still exits 1, and that is the point.** It dies at `:70` on `Tensor.floordiv`
(`AttributeError: 'Tensor' object has no attribute 'floordiv'`) — separate rot, not mine. A
gate on that exit status would have called the fix a failure. The device is the only evidence
that matters and it is line 1.

This also **changed the numbers the oracle exists to report**: `OVER_I64` was being measured
on METAL, and `matmul` alone reports 21 over-range bounds under NULL.

## 2. THE DENOMINATOR, AND THE NUMBER IS NOW KNOWN

`HERMETIC.md` §3 said 37 scripts and its own control `C3b` was reported at "16 false positives
out of 17". Neither number survives.

- **69 `.py` files in the tree WRITE `DEV`** (assignment or `setdefault`/`update`/`putenv`).
- **14 are VENDORED** — `tinygrad/` and `.agents/slop/{xd1,opstree}/`. Reported, never gated.
- **55 are the denominator**: writes `DEV` and reaches tinygrad.
- Of the 55: **55 `EARLY`, 0 `LATE`, 0 `DEFERRED`, 0 `BOTH`, 0 `UNRESOLVED`, 0 `IMPORTLESS`.**

**The one `LATE` in the tree was `mm-range.py`, and it is fixed.** So the corpus is now clean,
and the class had exactly **1** member, not 8 and not 37.

`--why` prints all 55 with **each file's own write line and its own boundary line**, because
"cannot say why the other 29 are fine" is the failure this table exists to prevent. Examples:

```
EARLY  oracles/mm-range.py:14   -> boundary 15
EARLY  .agents/slop/hermetic/isolate.py [DANGLING: this instrument was DELETED by the 2026-10-05 prune and is not in git]:46   -> boundary  -    (G.load_tinygrad() at :47, same scope)
EARLY  runs/margsym/snap/graphcmp.py:2366     -> boundary 2488
EARLY  .agents/slop/wip/optprobe/diff.py:2   -> boundary 3
```

### The classes, and why `VENDORED` is not a defect

`tinygrad/device.py:59` is `os.environ["DEV"] = device   # we set this in environment for
spawned children` — a **real write**, and it really is behind the module-scope import at `:6`.
That is upstream's contract: it publishes the *chosen* device to children. 14 copies
(`tinygrad/`, `opstree/`, and three `xd1/` worktrees) are the same line.

**`HERMETIC.md` §5's citation here is stale.** It describes those sites as `DEV = ContextVar(…)`
or `os.getenv("DEV")` at `:59` and calls them "upstream's own contract, not defects". The
**conclusion is right and the spelling is wrong**: `:59` is an assignment, not a read. A
citation is not a binding.

## 3. WHY 0 LATE IS NOT A GREEN I HAVE EARNED — the error rate

Two legs, because they test different things, and neither covers the other's blind spot.

**Leg 1 — the PARSE, on 15 HELD-OUT plants written after the classifier was frozen.**
`--heldout` → **14/15 correct, 1 misclassified**. The miss, named and NOT chased (chasing it
would destroy the only property that makes the number an estimate):
`ho-nested-def-import-ignored` — a def whose body imports tinygrad, called only from another
def that is never called. devgate says `EARLY`; the sharper answer is `IMPORTLESS`.

**Leg 2 — the RULE, EXECUTED.** `--heldout` also replays each classified ordering as real
Python in a fresh process with no `DEV` in the environment: **10/10 orderings behave as
predicted**. The late ones print `METAL` and the early ones print `NULL`, on this host.

**The 27 tuning plants are 27/27 and mean nothing as an estimate** — I fixed seven of the
rules against them. They are labelled a FIXPOINT in the tool's own output for that reason.

**Leg 3 — an independent second instrument.** `--crosscheck` runs a regex scan with **no shared
code**: **68 agree, 1 disagree**, over 69 files. The one disagreement is the crosscheck earning
its keep — **`audit-hermetic.py:159`**:

```
DISAGREE audit-hermetic.py: ast=EARLY (write 72)  regex=inert (write 159, import 156)
```

`tokenize` settles which is wrong. `:159` is
`EARLY, LATE = 'os.environ["DEV"]="NULL"', 'pass  # DEV not set yet …'` — real code assigning
**string literals whose text contains the assignment**. The tokenizer emits that as
`type=STRING`. The regex instrument matched the *contents of a string*; devgate is right.

So: **parse error rate 1/15 on held-out data; rule agrees with a real interpreter 10/10;
instruments disagree 1 of 69, and that one is the regex's false positive.**

## 4. FOUR BUGS IN MY OWN INSTRUMENT, ALL OF THEM "A COMPARISON THAT CANNOT FAIL"

Every one produced a *plausible* number, and every one was wrong. Named because the failure is
the general one, not the particulars.

1. **`run_plants` returned `len(PLANTS)` unconditionally.** `--heldout` ran **15** plants and
   printed "**26/27**". A number that is not the count of the thing it describes.
2. **`order_inert` had no `@property`.** `v.order_inert == False` compared a *bound method* to
   a bool, is always false, so the crosscheck reported **0 agree / 69 disagree** — which reads
   as "the instruments are unrelated" when they agree 68 times. An instrument that flags
   everything is not an instrument; neither is one that disagrees with everything.
3. **`_module_aliases(tree)` was called inside a per-`Call` loop** and `loader_functions` read
   every `Name` node instead of each call's callee. The closure snowballed until **28 of
   graphcmp.py's functions** were "import boundaries", `_variable()` among them — which
   reported `graphcmp.py` **LATE**, contradicting a measurement (`--dev NULL` → `NULL`).
4. **The transitive-closure bug had a cause worth keeping:** a tinygrad import inside a def is
   an import only when the def is **called**. devgate now requires a **module-scope** import,
   or a loader **called at module scope**, before it will call a write inert.

**And the trap the class is about, reproduced in my own tool:** `DEV` inherited from the
environment plus a late source assignment is **inert and silent** — asking `CPU` under an
inherited `DEV=NULL` yields `NULL`, reading as if it took effect. `HERMETIC.md` §3 measured
this; devgate's `VENDORED`/`UNRESOLVED` classes exist so that a file which never imports
tinygrad can never be scored as if it had.

## 5. WHAT IS STILL OPEN

- **`DEFERRED` is a real class with 0 members today.** When a boundary is only reachable from
  inside another def, devgate **declines to call it `LATE`** — a boundary under a condition
  would make that unsound — and the count is resolved by a run, not by a guess. It is not a
  euphemism for "clean".
- **`UNRESOLVED`** is for a `*tinygrad*`-named call devgate cannot follow. Nine corpus
  provisioners (`isolate.py`, `reach/census.py`, `arith/both-census.py`, …) were `UNRESOLVED`
  until devgate learned to **open the other module** through `import graphcmp as G`. They are
  `EARLY`: the write is the statement immediately before `G.load_tinygrad()`. devgate reporting
  its own reach as a verdict about the code would have been the same error as C3b.
- **`mm-range.py:70`'s `Tensor.floordiv`** is rot I did not touch. Someone should check
  upstream's spelling — the oracle cannot produce its headline `OVER_I64`/`MAX_BITS` until it
  is fixed.
- **`runs/margsym/snap/graphcmp.py:2366`** and the other 54 are `EARLY` by source order **and
  have not each been executed**. The 10 executed replays validate the rule, not these 55 files.
  `--why` makes each one checkable by reading; that is a weaker claim than running all 55, and
  it is the claim being made.