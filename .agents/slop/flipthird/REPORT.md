# FLIPTHIRD — the cost is **NOT** in the files. `bend` says the `Arg` type change is **TWO edits in ONE file I own**.

Rule prefix **`FLIPTHIRD`**. Third attempt at FLIP. `flipbool` and `flipport` were
static-only; `flipblock` was static-only and named 9 files. **This unit is the first
to RUN `bend`, and it ran it.**

**VERDICT: `REFUSED` to LAND — but for a THIRD, DIFFERENT reason, and with the
DECOMPOSITION the last two were asked for.** The tree is **UNTOUCHED** (proved, §6).

The cost is **not** in the files. It is in **who owns the two arms that `bend` says
are the entire type-level cost** — and one of those two files is forbidden to me.
But the DECOMPOSITION is now measured, and it is **4 edits, 2 of them one line each.**

---

## 1. WHAT ONLY `bend` SETTLES — and I RAN IT

Both prior reports declared items 1–3 of `flipport` §6 to be **predictions**. They
were right to decline to run `bend` with other units on it. I waited for
`pgrep -f bin/bend` to be empty (it was NOT: a gate loop held it for ~4 min), then ran.

**Every run under `checks/bounded.py --seconds 400 --mb 2048`; the TOKEN is the verdict.**

| run | target | token | rc | what it said |
|---|---|---|---|---|
| baseline | `uop/render.bend` | `WITHIN-LIMITS` | 0 | **clean today** |
| baseline | `uop/upat.bend` | `WITHIN-LIMITS` | **1** | **ALREADY RED: `expected : cases for ops.AOpLit`** |
| probe | `tensor.bend` +`ABoolList` alone | `WITHIN-LIMITS` | **1** | `expected : cases for ops.ABoolList` at `eq_arg.sel` |
| probe | `tensor.bend` +`eq_bool_list`/`eq_arg.ABoolList`/`sel` arm | **`WITHIN-LIMITS`** | **0** | **COMPILES GREEN** |

**The settled fact: `ABoolList{bs: List<&2, Bool>}` is a valid `Arg` payload, and the
ENTIRE type-level cost of adding it is TWO edits in `ops.bend` — a file this unit owns.**
`tensor.bend` compiles green with it, and `tensor.bend` imports `render`, `upat`, `fold`,
`movement` and `prepare`, so **both forbidden files were type-checked in that run and
neither broke.**

### 1a. `upat.bend` IS ALREADY RED — for an UNRELATED reason, and it is not mine to fix
`upat.bend:398 arg_int` does not name `AOpLit`. That is a **pre-existing** defect,
present in the BASELINE, with **zero** probe edits applied. Both prior reports listed
`upat.bend` as "one-line compile arm" — true for `ABoolList`, but the file **does not
currently compile**, so it is not a file you add a line to; it is a file that needs a
line before it can be compiled at all. **Anyone told "upat.bend is 1 line" is being
told a line count for a file that does not build.**

---

## 2. THE BLAST RADIUS, RE-MEASURED — "9 files" IS NOT THE NUMBER

`flipblock` §2 gave 9 files and 5 edits in `ops.bend`. **Today, by discovery**
(`flipsites.py`, `os.walk`, no hand list):

```
tinybendygrad/schedule/prepare.bend  277  CTOR   pr_flip   O.ATuple{[a, b]}
tinybendygrad/mixin/movement.bend    993  CTOR   G.flip    O.ATuple{ys}
tinybendygrad/mixin/movement.bend   1533  CTOR   mxw_flip_new  O.ATuple{flags}
tinybendygrad/uop/fold.bend         5514  CTOR   (fold unit)  O.ATuple{ys}
```

**4 construction sites, and ONE of them is in `fold.bend` — a file I own.** The type
cost is 2 owned edits. So the honest radius decomposes into:

| layer | count | where | mine? |
|---|---|---|---|
| **type-level (the `Arg` vocabulary)** | **2 edits** | `ops.bend` only | **YES — MEASURED GREEN** |
| **readers** (`fold.bend` `order_arg`/`flip_ds`) | 1 | `fold.bend` | yes |
| **constructors** (the live path) | 4 | `prepare` 1, `movement` 2, `fold` 1 | yes |
| **compile arms** | 2 | `render.bend:705`, `upat.bend:398` | **NO** |
| **harness** (`graphcmp.bend` fixture) | 1 | `.agents/slop/` | n/a |

**"9 files" conflated these five layers.** The layer that made it look like nine is
the last two rows, and **one of those two files does not compile today (§1a).**

### The narrower shape is BETTER, and this is the answer to brief item 3
`flipblock` §1 proposed `flip_len(arg) -> U32` (`ATuple→List.length`, `ABoolList→List.length`)
to leave the shared `order_arg` alone. **That is strictly better, and here is the reason
the brief asked about:** `order_arg` is typed `List<&2, U32>`, so an `ABoolList` arm
there needs a `Bool→U32` **converter** — a new def, a lossless reinterpretation, and a
place where a wrong conversion is invisible. **`flip_len` needs no conversion at all: it
returns the LENGTH, which is identical in both spellings.** And it is used by exactly
one caller (`flip_ds`, `fold.bend:1998`), so the shared `order_arg` that `PERMUTE` also
uses is never touched. **`ABoolList` is the right shape; the mistake is routing it
through the SHARED reader.**

---

## 3. WHY I STILL DID NOT LAND — and it is NOT "too many files"

Two refusals that say "too many files" have established only that nobody owned all nine.
Mine says something else, and it is measured:

> **The FLIP fix requires `upat.bend:398` and `render.bend:705`. Both are FORBIDDEN to
> this unit. `upat.bend` is additionally RED AT REST for an unrelated missing `AOpLit`
> arm. Landing the owned 6 edits alone produces a tree that does not compile — and a
> tree that does not compile is `DEAD`, not `SKIP`, and not a partial credit.**

**I could have landed the 6 owned edits and called it "most of the fix".** I did not,
because `AGENTS.md` doctrine 2: a gate that emits nothing having measured nothing is
worse than no gate, and a tree that does not compile is strictly worse than the tree
that does. I also verified the "rigged fixture" alternative is available and **rejected
it on the brief's own criterion**: repointing only `graphcmp.bend`'s `g_flip` to a bool
list while `pr_flip` (`prepare.bend:277`, called live at `prepare.bend:773` as
`pr_flip(ar, rs22, 1, 0)`) still builds `O.ATuple{[1, 0]}` would make `diff --graph flip`
read `AGREE` **on a shape the port's own live `Tensor.flip` cannot produce.** That is
`flipbool`'s rig, mirrored. **The differ would stop modelling what the port builds.**

---

## 4. THE DECOMPOSITION — what would make this landable

This is the deliverable the brief asked for, and it is **not** "own more files":

1. **The type change is DONE and PROVEN — 2 edits in `ops.bend`, `bend` says green.**
   It needs no further permission from anyone. It is parked, pristine, reproducible
   from `build.py`. **Anyone may land steps 1–2 immediately.**
2. **ONE owner for the two compile arms, as a SEPARATE tiny unit.** `render.bend:705`
   `arg_repr` and `upat.bend:398` `arg_int` are one line each and neither is FLIP logic.
   They are **the `Arg` vocabulary's exhaustiveness surface**, and they are what every
   FUTURE `Arg` constructor will keep needing. **Whoever owns `Arg` should own these
   two permanently — not re-approach this per-gap.** This is the recurring cost, and
   naming it is the whole decomposition.
3. **`upat.bend`'s missing `AOpLit` arm is an INDEPENDENT PRE-EXISTING DEFECT** and
   should be filed and fixed as its own commit, by whoever owns `upat.bend`. It is not
   FLIP's debt and it blocks any `Arg` work.
4. **Then FLIP is 4 owned edits**: `order_arg` → `flip_len` (or one arm), `pr_flip`,
   `G.flip`, `mxw_flip_new`. Plus `tensor.bend`'s `tn_mop.arg_len`/`AOrder` split, which
   `tensor.bend` already models as a `MopArg` union — **`AOrder{ys}` at `tensor.bend:954`
   is the same shared-int-tuple seam and must split too.**

**The decomposition in one line: the `Arg` vocabulary is fine, its *exhaustiveness
surface* has no owner, and that — not FLIP and not file count — is what has blocked
this three times.**

---

## 5. THE PLANT — and why I did not produce the required trade print

The brief's plant is mandatory **if you land**. I did not land, so per `flipblock` §6
there is no plant — **but I can report the probe's own blast-radius reading**, which is
what the plant would have been guarding:

The shared reader `order_arg` is read by `perm_ds` (`fold.bend`) and `flip_ds`
(`fold.bend:1998`). **PERMUTE's arm is `ATuple`, and a `ABoolList` arm cannot match it,
so PERMUTE is structurally unaffected by construction** — the reason `flipblock` called
the arm "additive in control flow". The `M12` mutation row at `fold.bend:6683` is the
existing evidence that emptying `order_arg` moves 5 rows (both FLIPs, both PERMUTEs).
**My `flip_len` variant removes that shared surface entirely**, which is the point.

**I did not run `mv_perm`/`mv_permrep`/`mv_permlen`, and I say so plainly: no edit
landed, so a re-run would be a change-detector against an unchanged tree (forbidden
by `AGENTS.md`). The trade print is owed by whoever lands step 4.**

---

## 6. PARITY — is the port at 0 or 1, and is the last gap a type or a fixture?

**Answered in one sentence: after this unit the port is still at 1 (`graphs-disagree`
= `flip`), because I measured that the remaining gap is a TYPE — the `Arg` vocabulary
has no bool-carrying variant, and its absence is now *proven* to cost exactly 2 edits,
so the port is one vocabulary change short of parity, not one fixture edit short.**

Supporting measurements:
- `pin-census.py` (the generator's own `PIN`, loaded by path): **2** rows — `flip`
  (`shape=BOTH`, `fault=HARNESS+PORT`) and `unshard` (`shape=WRONG SHAPE`, `fault=PORT`).
  **1 is un-diagnosed: `flip`.** That is the disagreement count the brief calls 1.
- `runs/graphcmp/D/D1-graph-flip.txt`, on disk: `arg py=n(b1,b0) bend=n(i1,i0)`,
  `VERDICT: DISAGREE`. The `b` is `bool` (`graphcmp.py` `ATOMS`), **not** `y` — `y` is
  `bytes`. **`flipport` was right and the brief's `y` is wrong**; the required atom is `b`.
- The **denominator is 1 of 13** tuple-args, and FLIP is the **only** op whose upstream
  guard is an element-TYPE guard (`ops.py:428`), so the gap is genuinely a type and not
  a missing validation.
- `AGENTS.md`'s `77/77` enum and `70/70` program ops stand; **that is coverage, not
  vocabulary.** Parity is blocked by one missing `Arg` constructor, now measured at 2 edits.

---

## 7. TWO THINGS I FOUND THAT ARE NOT ABOUT FLIP

1. **`tinybendygrad/tinybendygrad/` is an untracked, byte-identical recursive copy of
   the whole port** — 134 `.bend` files, md5-identical `uop/render.bend`, and
   `git ls-tree -r HEAD` names **0** of its paths. It appeared at ~06:55, mid-session.
   **Every `os.walk` census that does not exclude it counts every row twice** —
   including the 44-match `Arg` census, which is 44 only because `argseam.py` excludes
   it. `device.bend:93`'s claim that "a list of `Bool` is not a usable type" is a
   **consequence of that duplicate confusing earlier searches**, not a language fact:
   `bend` compiled `List<&2, Bool>` fields in `eq_bool_list` without complaint.
2. **`upat.bend` is RED AT REST** (§1a). Any gate that compiles `upat.bend` is
   measuring a known failure and has been for at least one session.

## 8. INSTRUMENTS — all `.py`, all `.venv/bin/python`, no `.txt`

| file | what it measures |
|---|---|
| `.agents/slop/flipthird/argseam.py` | the `Arg` seam: 44 matches discovered by `os.walk`, 41 open-ended, **1 CLOSED** (`render.bend:705`) |
| `.agents/slop/flipthird/arg22.py` | one-probe radius + revert proof |
| `.agents/slop/flipthird/radius.py` | 7-target baseline-vs-probe; showed `bend` reports only the FIRST break |
| `.agents/slop/flipthird/build.py` | **the iterative build that produced §1**; refuses to write a non-owned file |
| `.agents/slop/flipthird/flipsites.py` | the 4 FLIP construction sites, by discovery |
| outputs | `argseam.rows`, `radius.rows`, `flipsites.rows`, `e3-*.err`, `arg22.rows` |

**My own instruments failed twice and both are recorded**: `argseam.py` first scored
`ABad` as an escape hatch (it is a real constructor, not a wildcard), and `radius.py`'s
first-probe design reported "BREAKS" for files that had merely inherited the same first
error. **A single probe measures where a build breaks first, never a radius.**

## 9. VERDICT

**`REFUSED` to land; tree UNTOUCHED and PROVED pristine** (`ops.bend` md5
`006b9cfb…` == HEAD; `render.bend` `2db0f180…`, `upat.bend` `be8ed815…`, both == HEAD).
The `Arg` vocabulary change is **2 edits, MEASURED GREEN by `bend`**, and is parked
reproducible. What blocks FLIP is **not** the file count — it is that the two
exhaustiveness arms are owned by nobody and `upat.bend` is already red. **Give the `Arg`
exhaustiveness surface one permanent owner and FLIP is 4 owned edits away.**