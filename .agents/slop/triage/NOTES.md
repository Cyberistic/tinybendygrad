# TRIAGE — 21 preserved stray `.bend` copies

Rule prefix for this unit: **TRIAGE-01..06** (numbers collide across units; cite by prefix).
Full report: `.agents/slop/TRIAGE.md`. Evidence: `triage/d/*.diff`, `gate-BEFORE.txt`,
`gate-AFTER.txt`, `allfiles.txt`.

## Method

1. `cmp` the live tree against `strays/origin/` — **0 mismatches**, so the live tree *is* the
   origin baseline and "before" needs no separate tree.
2. Re-measure `substrate-check.sh` half 1 over **all 137** `.bend` files, not the 21. Baseline:
   14 COLD / 0 names-BAD — matches `agent-core.md`'s table. This is what makes "not breaking a
   file that depends on it" a measurement instead of an assertion.
3. For every diff, ask the *strongest available* question, not "does it look finished":
   upstream source for a transcribed constant, the port's own named predicate for a table, a
   sibling line for a polarity, `grep -c` on the tree for a line-count claim.
4. Classify, then gate, one file at a time. Apply only through the layer that owns the change.

## Rules

**TRIAGE-01 — A generated product's md5 identifies the GENERATOR'S OUTPUT, not the file in the
tree.** The coordinator held md5 `04199adf…` / 71,324 B / `IN SYNC` as the state of
`libclang.bend`. Measured: that md5 is the **preserved stray copy**. The live file was
`07383541…` / 63,334 B and `apply-port-lane.py --check` said **`OUT OF SYNC`**. A restore can move
a *generated* file backwards, and a generator's own `--check` is the only thing that sees it.

**TRIAGE-02 — Check `fix(live) == stray` before believing either one.** `fix` is the committed
generator step, idempotent by construction. Byte equality between "what the generator makes from
the live file" and "the stray" is corroboration neither can fake. It settled libclang in one
command and would have settled any of the other 20 the same way — they all fail it.

**TRIAGE-03 — A `--check-only` COLD verdict can be the file's DESIGN, so the gate for such a file
is the build lane.** `libclang.bend` is S-1 (a `.bend` importing only `.c`): `SOME PROOFS FAIL`
with the **same 11 foreign laws on both sides**, so "COLD → WARM" was never available as a
criterion. `bend -o` was: **rc 1 / 0 lines → rc 0 / 5,503 lines**, plus `cl-port-gate.py` rc 0
with `FAILURES: 0`. Diff the *whole* 11-name list before and after, not the first line.

**TRIAGE-04 — `unseen` is a number you must read, not a number you can skip.** The whole-tree
gate output diffed in exactly two lines after the apply: libclang's own line count, and
`unseen` 46831 → 46846. The +15 is the unqualified `Foo.bar` refs the 15 new type declarations
introduce — inside the check's declared blind spot. An instrument that hides its own blind spot
must be reported with the blind spot's magnitude.

**TRIAGE-05 — "0 of 0" in a mutation table is a report that nothing ran, and it is worse than
absent.** `runtime/support/am/ip.bend`'s appended "MEASURED, NOT ASSERTED" block reads
"0 LOGIC mutations, 0 of 0 move rows", "0 constants, 0 moving", "0/0", "**0 BLIND SPOTS
SURVIVE**" — while claiming "the 46 unread constants the sweep found were DELETED" in a diff
that is `+456/−0`. Both instruments (`ip_mutate.sh`, `ip_sweep.py`) exist on disk. **An instrument
that produced nothing must not be reported as a pass**, and a table that asserts it found nothing
in a file it never edited is that failure wearing a green tick.

**TRIAGE-06 — A non-idempotent generator is indistinguishable from a lost unit's leftovers
until you count its marker.** `dsl_gen.py` truncates at `# ==== GATE BODY … ====` but
re-appends `FIXTURES`, so each run adds one copy of the fixture block. Measured: "THE FIXTURE"
headers are **1 at origin, 7 in the stray** (`generate.bend`: 4 → 10). The +1403 and the
`duplicate declaration: VOP2_ALL` are *the same fact*. **Count the generator's marker; do not
read the diff's line count** — the brief's "+1401" and "+86" are two views of one non-idempotent
loop.

## Measured facts worth keeping

- The brief's cold/warm table reproduced **exactly**: 6 COLD/1 SAME/14 WARM, from a clean
  overlay of `strays/working/` on a copy of the tree. Compiler verdicts for all six: `NoSuchDef`
  (`codegen/__init__`), `duplicate declaration: VOP2_ALL` (`dsl`, `sqtt`), `duplicate
  declaration: gl.go` (`generate`), `expected : 1 patterns (one per scrutinee)` (`support/
  autogen`, on `case c1 c2 rest`), `expected : 'def', 'type' or 'law' / observed : ','`
  (`nv/nvdev`).
- **A Bend list pattern destructures exactly ONE element.** The stride-2 rewrite of
  `colons_to_underscores` is therefore not a bug to fix but a form that **cannot be written**;
  the pending-state version it replaced was total.
- **`Bool.or(x, False{}) == x`** — which is how `gpudims.bend`'s `rs_claimed` becomes a function
  that can never claim LOCAL while still compiling and still printing rows.
- `mm.s0(+xs) = mm.src2(xs, 0)` (`uop/fold.bend:3499`), so the stray's
  `mm.lift.mv` edit is a **no-op rename** — 3 of that file's 4 edits are damage, the 4th is not.
- Three one-line variants of `memory.bend` under three PIDs, each falsified by the port's own
  predicate or by upstream: `aspace_val_is_ix_plus1` (`:627`) refutes `ASPACE_PHYS_VAL 0`;
  `memory.py:39`'s `# size, next, prev, is_free` refutes the transposed comment; and a record
  field-order permutation (`Mv{h, addr, …}`) is the shape `agent-core.md` names as "a silently
  wrong register write".

## Re-measure

    find tinybendygrad -name '*.bend' | sort > .agents/slop/triage/allfiles.txt
    .agents/slop/substrate-check.sh $(cat .agents/slop/triage/allfiles.txt)

**Nothing committed. Nothing in `strays/` deleted or modified.**
