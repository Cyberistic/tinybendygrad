# unshardtable — closing `dt_shape`'s UNSHARD/STAGE wall: the named unblock is NOT small

**Verdict: STATIC-ONLY. I did NOT land.** The prior unit's named unblock ("the partial
`Table` plus a recursive interval walk suffices — that is the smallest unblock") rests on a
measurement I reproduced and **refuted**: its "9 forward calls" are 9 **comment lines**. The
forward-reference wall is REAL, so the unblock is a ~680-line relocation, not a thread.
`bend` is **ABSENT from PATH** (measured: `command -v bend` empty; no `/opt/homebrew/bin/bend`,
`/usr/local/bin/bend`, `~/.local/bin/bend`), so nothing can be compile-checked.

No `fold.bend` edit was made. `fold.bend` was checked IDLE before reading (md5
`b8d252c52accb70f3a8ecc147779c56b`, twice 30 s apart, identical).

---

## 1. The refusal's shape — CONFIRMED, both claims

* **The cycle is real.** `dt_shape` (`fold.bend:2321`) runs INSIDE the fold: `Kahn.ans`
  (`:4364`) → `derived` (`:2559`) → `derived.of` (`:2549`) → `dt_shape`. The `BTable` is
  `mm.sweep(ar, main)` (`:4830`) called by `MMed.of(ar, tb)` (`:4861`) where `tb` is the
  **completed** `Table` from `UOp.fold` (`:4502`). So the BTable does not exist while
  `dt_shape` runs. **"Hand `dt_shape` a BTable" is impossible.** ✔
* **The one-frame-up claim is real.** `Kahn.ans:4364` carries `tb: Table` and calls
  `derived(ar, i, O.Arena.node(ar, i), ss)` (`:4365`) **without** it. So the caller holds the
  partial main `Table`, not a `BTable`. ✔
* **`mm.lift` is SHAPE-FREE.** `mm.lift(+op, +srcs: List<Bnd2>, arg, +d)` (`:4076`) — no
  shape anywhere. ✔

## 2. THE HEADLINE CORRECTION — the forward-reference wall is REAL

The prior unit wrote: *"`forward_ref_check.py` finds 9 cross-name forward calls … So `dt_shape`
CAN call `mm.lift`."* I rebuilt the instrument (discovery, not a list) and **stripped comment
text**:

* `fold.bend`: **0** forward references. The naive scanner's 9 hits are at lines
  **119, 165, 269, 290, 3529, 4437, 4498, 4712, 4833** — I printed each; **all nine are `#`
  comment lines** (e.g. `:290` is the prose ``reachable call is `promo_dtype(src[1:])` ``).
  `.agents/slop/unshardtable/forward_refs.py` (comment-stripped) prints `0`.
* Tree-wide: only **9** naive hits, in **2** files — `LAWS.bend` (all inside `law … {…}`
  **propositions**, not code) and `runtime/support/autogen.bend` (`rep_emit1:748` → `space():755`).
  `autogen.bend` is **COLD and TYPE-MISMATCHED** (`.agents/slop/coldness/COLDNESS.md:187`), so it
  proves nothing.

The language reference settles it — `references/bend/guide/GUIDE.md:113-121`:

> Termination is mandatory and mutual recursion is not allowed. … **A `def` marked `@unsafe`
> recurses freely and may call a def written below it** … **the order binds only defs**.

Only `@unsafe` (which "prints SOME PROOFS FAIL") may call below. There is **no `@unsafe` in
`fold.bend`** (measured). Therefore **a checked def may not call a def defined below it**, and
`dt_shape` (`:2321`) **cannot** call `mm.lift` (`:4076`) or `fold.dt` (`:4430`).

**The prior unit's `forward_ref_check.py` failed doctrine 1 inside the census of doctrine 1: a
basename/identifier regex matched prose and called it a call. Its own warning — "A BASENAME
SHAPE … IS NOT A POPULATION" — is the exact defect.** This changes the cost decisively.

## 3. The COST of the `Table` thread (file:line)

Callers that must grow a parameter for the **Table-thread shape**:

| def | line | change |
|---|---|---|
| `dt_shape` | `fold.bend:2321` | `+tb: Table` (needs it in the UNSHARD/STAGE arms) |
| `derived.of` | `fold.bend:2549` | `+tb`, passes to `dt_shape` |
| `derived` | `fold.bend:2559` | `+tb` |
| `Kahn.ans` | `fold.bend:4365` | pass `tb` (already has it) — the ONE call site |
| `derived.put` | `fold.bend:2542` | unchanged (only assembles `Derived`) |
| `wk_dtype_at` | `weak.bend:420` | `F.dt_shape(...)` grows `+tb`; has `F.Folded.t(fx)` (`fold.bend:4101`) |

`derived` has exactly **one** caller (`Kahn.ans:4365`; `weak.bend`'s `wk_derived` is a different
name). So the parameter itself threads **3 frames + 1 cross-file caller** — that part is short.

**The short thread is not the cost. The cost is the CALLEE.** To *use* `tb`, `dt_shape` must
turn a src index into an interval, which needs `_min_max` = `mm.lift` (`:4076`) + `fold.dt`
(`:4430`), **both below `:2321`**. Options, each measured by line span:

* **Relocate** the whole `mm` block (`Bnd`/`Bnd2`, `mm.bin.enter` ~`:3918`, `mm.MM2`/`mm.lift.*`,
  `mm.lift` `:4076`, ~`3396-4076`) **above** `:2321` → a ~680-line reorder of the file's
  documented four-part structure.
* **`@unsafe`** the call path → forfeits proofs, `SOME PROOFS FAIL`.
* **Two-pass fold** (below) → avoids relocation but doubles the fold.

## 4. Both named shapes — smaller vs more honest

**Shape A — thread `Table`** (prior unit's unblock): 3 frames + 1 cross-file caller + **a new
recursive interval walk** (no memo; descends from a src to its ancestors calling `mm.lift`) +
the UNSHARD per-axis logic. **Requires the relocation.** Does NOT preserve the refusal unless the
walk returns `None` on any missing ancestor — it can, so it is honest in principle.

**Shape B — a `bnd: Maybe<&2, Bnd2>` field on `Derived`** (the `ss`-based alternative):
- touches the central type: `fold.bend:684`, `Derived.unknown()` `:773`, the **six** readers
  `:782/805/1004/1026/1038/1055`, the constructor `:2545`, **and `weak.bend:396`** (constructs
  `F.Derived` positionally).
- computes `bnd` in `derived.put` via `mm.lift` → **the same relocation problem**, plus it
  re-derives what `mm.sweep` already computes in a second place (drift risk).

| | A (thread Table) | B (`bnd` field) |
|---|---|---|
| whacks | 4 sigs + `weak.bend:420` | central `Derived` + 8 sites + `weak.bend:396` |
| `mm` relocation | required | required |
| refusal honesty | `None` from the walk | `None` exactly when node unanswered (structural) |

**Smaller: A** (no central-type change; one `+tb` per frame). **More honest: B** — a field that is
`None` iff the node was unanswered is the same shape as the existing `ended` field
(`fold.bend:1055`), so the refusal is structural rather than a second walk's discipline. **Neither
is small**, because of §2. A `bnd` field that were a *default range* would be the LIE the brief
warns about; it must be `Maybe`.

**Shape C — two-pass fold (the actually-smallest honest shape, missed by the prior unit).** Keep
`mm.lift`/`mm.sweep` where they are. Pass 1 `UOp.fold` answers the RANGE srcs (they ARE in the
table). `mm.sweep` then gives their intervals. Pass 2 folds again with a `BTable` handed to
`dt_shape`. This **reuses the gated `mm.sweep` (127 rows)** and needs **no relocation**, at the
price of folding twice and a new `fold` entry point threaded to the `Folded`/`Ranged`/`MMed`
readers.

**Shape D — a narrow `range_width` (smallest, narrowest).** For the UNSHARD/STAGE *shapes* the
needed quantity is `int(r.vmax)+1`. For a RANGE/SPECIAL whose `src[0]` is an I64 CONST `c`,
`_min_max` = `0,(c-1)` (ops.py:1147), so width = **`c`** exactly. A reader using only
`const_i64` (`fold.bend:1381`, **above** `dt_shape`) + `O.Arena.src/arg` closes
`g_unshard` with **no relocation, no signature growth, `fold.bend`-only**. It must return `None`
for a symbolic end (upstream would compute it) — a labelled divergence, not a lie. This is the
shape I would hand a unit that has `bend`.

## 5. The DENOMINATOR — confirmed `53 of 77`

Re-ran `.agents/slop/unshardfold/refusal_population.py` (discovery: reads the `Op` enum
declaration in `ops.bend` and `dt_shape`'s arms): **77 members → answer 13, cascade-refuse 49,
own-wall-refuse 4, late 11, absent 0.** Reachable `dt_of(dt, None)` = **4 + 49 = 53**. ✔
Own-wall = `{OpsUNSHARD, OpsSTAGE, OpsRESHAPE, OpsEXPAND}`.

**What a fix actually closes: 2 of the 4** — `UNSHARD` and `STAGE`-with-ranges (both are the
`(r.vmax)+1` read, shapes A/B/C/D all close exactly these two). **`RESHAPE` and `EXPAND` are NOT
closed** by any interval thread: their wall is `marg` answering `None` for a symbolic dim
(`reshape_ds.of` / `expand_ds`, `fold.bend:1567/2026`), a `sym_dim`-refusal with no interval in
it. So a landed interval fix moves the own-wall reachable set **4 → 2** (53 → **51**), and STILL
prints `?` on a graph whose src is symbolic-marg.

The 49 cascade are structural, not arm bodies: `Kahn.go.of` (`:4368`) refuses to call `derived`
when any src is unresolved, so cascade refusal is conditional on a **deferred src**, and the 49
arms do not change. Closing UNSHARD/STAGE only changes *graphs* whose wall was UNSHARD/STAGE.

## 6. `graphs-disagree 2 → 1` is a PARITY figure

Read from `runs/graphcmp/D/D1-graph-unshard.txt`: `settled=False`, `field-mismatches=2` —
`MISMATCH UNSHARD py#8 vs bend#8 dtype py=f32 bend=?` and
`shape py=(l0:8,l0:3) bend=?`. That is ONE node (`g_unshard`'s `UNSHARD`, src `(a, RANGE(2))`,
`arg=(0,)`, `.agents/slop/graphcmp.py:1515`), two fields. Closing the arm makes the port emit
`f32` and `(8, 3)` — `field-mismatches=0`, `settled=True`, verdict AGREE. So the drop is a real
**answer parity**, not a reclassification. (The other disagreement, `D1-graph-flip.txt`, is an
**arg-encoding** divergence — `FLIP arg py=n(b1,b0) bend=n(i1,i0)` — a PORT kind, another unit;
it is untouched here.)

**Caveat on the run's health:** `runs/graphcmp/D/D0-run-summary.txt` currently reads
`oracle-selfcheck=FAIL`, `census-rc=rc=1` — NOT the "green 17/17" `AGENTS.md` recorded. The D1
verdict files are still the last per-graph evidence, but the run dir is RED at this read.

## 7. The plant I would expect (NOT landed, so no before/after was produced)

From the real `D1-graph-unshard.txt` row, a landed UNSHARD/STAGE closer must turn:

```
UNSHARD  dtype py=f32   bend=?          ->  bend=f32
UNSHARD  shape py=(l0:8,l0:3) bend=?    ->  bend=(l0:8,l0:3)
```

and a graph whose UNSHARD/STAGE src is itself DEFERRED (a symbolic-marg RESHAPE under it, or a
missing dtype) must STILL read `?`. That is the line between a fix and a lie: the width reader
must answer `None` when it cannot read an exact width, exactly as `stage_ds` refuses today
(`fold.bend:1330-1332`). **I am on the refusing side: no field is defaulted, no range is
guessed.**

## 8. What ONLY `bend` settles

* That a landed patch **compiles** (the relocation/`+tb`/new arms type-check; Bend's order rule
  is satisfied).
* That `diff --graph unshard` returns **AGREE** (`settled=True`, `field-mismatches=0`) and that
  `flip` is unchanged.
* That the 49 cascade cases still refuse (no over-reach).
* That the other `UOp.fold`/`Folded`/`Ranged`/`MMed` rows are byte-identical after any relocation.

I could not run it: `bend` is absent (§1).

---

### Instruments (this unit; all `.py`, `.venv/bin/python`)
* `.agents/slop/unshardtable/forward_refs.py` — comment-stripped forward refs, `fold.bend` → **0**.
* `.agents/slop/unshardtable/forward_refs_tree.py` — tree-wide → **9**, all in law-props or a COLD file.
* `.agents/slop/unshardfold/refusal_population.py` (prior unit's, re-run) — **77 / 13 / 49 / 4 / 11 / 0**.
* `references/bend/guide/GUIDE.md:113-121` — the order rule.
* `.agents/slop/coldness/COLDNESS.md:187` — `autogen.bend` is COLD.
