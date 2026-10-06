# wmma's fourth `arg` slot: `N` (py) vs `n()` (bend)

Author: wmmafix unit, 2026-10-06. Read-only on `checks/`, `gates/`, `AGENTS.md`,
`runs/graphcmp/D/`. **No source edited** (a candidate `TODO` comment was reverted because it
shifted every pinned `ops.bend` line by +6 — see §4). No `bend` run — see §7.

## 1. Upstream's declaration (the PIN, not the worktree)

`ad117c928^:tinygrad/uop/ops.py:652-654`:

```
652  def wmma(a:UOp, b:UOp, acc:UOp, dims:tuple[int, int, int], threads:int, tc_upcast_axes=None):
653    # dtype_in is stored in the arg (not derived from src[0].dtype) because bitcast rewrites change src dtypes
654    return UOp(Ops.WMMA, src=(a, b, acc), arg=(dims, a.dtype, threads, tc_upcast_axes))
```

**The `arg` tuple has FOUR slots: `(dims, a.dtype, threads, tc_upcast_axes)`.**

**The fourth slot is OPTIONAL: its default is `None`.** Upstream's `UOp.arg` itself is declared
`Any = None` (`ops.py:243`), so the type is only visible at the constructor and at the one
caller. The caller is `ad117c928^:tinygrad/codegen/opt/postrange.py:229 & :235`:

```
229  tc_upcast_axes = tuple([tuple([(a, 2 if j < cnt else 1) for j,a in enumerate(...)]) for cnt in upcast_cnt])
235  tc_uop = UOp.wmma(..., tc.dims, tc.threads, tc_upcast_axes=tc_upcast_axes)
```

So the field's value domain is `None` **or** a *nested* tuple `tuple[tuple[(axis:int, size:int), ...], ...]`.
`postrange.py:233` even carries upstream's own `# TODO: remove tc_upcast_axes from the arg`.

**Its `__repr__`**: `UOp.__repr__` delegates to `pretty_print` (`ops.py:269-271`), which emits
`UOp({op}, arg={argstr()}, src=(...))` (`render.py:6-11`); `argstr()` falls through to
`repr(self.arg)` (`ops.py:272-274`). None of the `renderer`/`pm_pyrender` arms special-case WMMA,
so a WMMA arg is the plain 4-tuple repr — `None` in slot 4 when absent.

The corpus's py side (`.agents/slop/graphcmp.py:491-494`) mirrors exactly that:

```
491  if op is Ops.WMMA:
492    dims, dtp, thr, tc = x
493    return (f"wm({tup([u(i) for i in dims])},{dt(dtp)},{u(thr)},"
494            + (tup([u(i) for i in tc]) if tc is not None else ATOMS["none"]) + ")")
```

`ATOMS["none"] == "N"` (`graphcmp.py:324`); `tup` is `"n(" + ... + ")"` (`graphcmp.py:383`).
So py spells **absent** `N` and a **present list** `n(...)` — two distinct spellings.

## 2. The port's spelling

Type — `tinybendygrad/uop/ops.bend:1197`:

```
AWmma{dims: List<&2, U32>, dt: S.Dt, threads: U32, tc: List<&2, U32>}
```

Constructor — `ops.bend:7306` (declares `tc: List<&2, U32>`) and `:7307` builds the `AWmma`.
(`ops.bend` is being edited live by other units — the `replace` addition at `:2733` is not ours —
so out-of-region line numbers here are a snapshot; `AWmma` at `:1197` is the load-bearing one.)

Renderer — `.agents/slop/graphcmp.bend:440`:

```
case O.AWmma{wdims, wdt, threads, tc}: String.concat(["wm(", us(wdims), ",", dt(wdt), ",", U32.show(threads), ",", us(tc), ")"])
```

`us` (`.agents/slop/graphcmp.bend:171-172`) is `"n(" + join(...) + ")"`, so an **empty** list is `n()`.

Measured py row for `--graph wmma` (`.venv/bin/python .agents/slop/graphcmp.py emit --side py --graph wmma`;
saved as `wmma-py-emit.rows`), row 11 of 11:

```
3:i11 4:WMMA 3:f32 11:(l0:4,l0:3) 2:i0 1:N 27:wm(n(i3,i4,i4),Df32,i256,N) 12:n(i4,i8,i10)
```

The port renders the same WMMA as `wm(n(i3,i4,i4),Df32,i256,n())`.

**The first three slots agree.** Slot 4: py `N`, bend `n()`.

## 3. Which side is WRONG

**The port's type is wrong.** Upstream's slot is optional (default `None`); the port's `List<&2, U32>`
is not optional. A `List` holds 0 **or** n; a `Maybe` holds 0 **or** 1, and — the point — a `List`
cannot hold `None` at all. The port models absence as an *empty list*, and `us(Nil{})` then prints
`n()`, the spelling `.agents/slop/graphcmp.bend:216-218` **explicitly reserves for a present empty
tuple** and distinguishes from `N`:

> `Maybe` is CPython's `| None`, and `None` and the empty tuple are DIFFERENT values
> (`vmin_vmax=None` is not `vmin_vmax=()`), so absence gets its own tag `N` and a present empty tuple gets `n()`.

So the port emits a spelling for a **different value**. It is not "the port is right and the spelling
differs": the port's type cannot represent the value upstream holds.

There is a **second, independent** error in the same field: upstream's present value is a *nested*
tuple of `(axis, size)` pairs; the port's `List<&2, U32>` is a **flat** `u32` list, which cannot hold
a pair at all. The `Nil{}` fixture exercises only the absent case, so only the optionality half is
measured — but the type is wrong on both axes.

Precedent in the port: it already spells an optional field with `Maybe` —
`CallInfo{name: Maybe<&2, String>, ...}` (`ops.bend:1117`) — and `graphcmp.bend`'s `mum`/`mm`/`nm`/`dm`
(`:219-234`) render `Maybe` as `N` when absent. The port has the machinery; `AWmma.tc` just does not use it.

## 4. Fix? — **NO source change made**, on purpose

(The house rule *"add TODO comments in the code"* was tried: a 6-line note beside the `AWmma`
taxonomy row at `ops.bend:1141` shifted **every** `ops.bend` line after it by +6, including the
`disagree-gate.py` pin at `:1197`. A comment that moves pinned lines is worse than a comment that
waits, so it was reverted; the TODO lives here instead.)

Step 4's licence is *"fix the SPELLING **if that is all that differs**"*. It is **not** all that
differs: the type is wrong (§3). So there is no spelling-only edit to make, and I did not:

- I did **not** add `Nil{} -> "N"` to the `AWmma` arm. That would be changing the renderer so two
  distinct values (`None`, empty tuple) collapse to one spelling — the exact conflation
  `:216-218` forbids, and a type change smuggled in as a renderer tweak.
- I did **not** retype `tc`. A faithful retype is `tc: Maybe<&2, List<&2, U32>>` (minimum) or a
  dedicated nested-pair variant (full), and it is **not** a one-file change: it ripples to
  `ops.bend:7306` (`UOp.wmma`'s signature), `:2032` and `:2125` (`eq_arg.AWmma` compares `tc` as a
  list), `graphcmp.bend:440` (the `us(tc)` arm), and `graphcmp.bend:1416`'s `g_wmma` fixture
  (`Nil{}` -> `None{}`). That is a deliberate type change, not a spelling, and step 4 puts it out
  of scope. **A rename that changes a type is two changes wearing one hat**; I report instead.

## 5. What `checks/disagree-gate.py` needs when `wmma` lands DISAGREE

`file:line` and old -> new. **Not edited.**

- `checks/disagree-gate.py:63-77` — `PIN`: add a fifth entry.
  `"wmma": dict(row=<MEASURED>, fields=("arg",), shape=<NEW-LITERAL>, fault="PORT")`.
  - `row`: **11** from the measured py emit (`wmma-py-emit.rows`, WMMA is row 11 of 11). **This is
    the py side only**; the run's `first_row` must be re-read from a re-taken
    `runs/graphcmp/D/D1-graph-wmma.txt` before the literal is committed. Same index convention as
    `flip` (`row=6`, its last of 6) — `names.py` enumerates from 1 (`names.py:156,177`).
  - `fields=("arg",)` — the only chunk that moves; dtype/shape/depth/tag/src all agree.
  - `shape`: a **new** literal, not `flip`'s `"BOTH"`. `flip` is `"BOTH"` because its harness is also
    implicated; `wmma`'s harness (`graphcmp.py:491-494`) is **correct**, so the fault is the port's
    model alone. The header's `WRONG SHAPE` (`disagree-gate.py:58-60`) fits but has **no member** —
    naming it is part of this edit.
  - `fault="PORT"`.
- `len(PIN)` moves **4 -> 5**. No code line edits for this: `disagree-gate.py:146` derives the
  expected string from `len(PIN)` and asserts `graphs-disagree={len(PIN)}` appears in
  `runs/graphcmp/D/D0-run-summary.txt`. The **run** must therefore read `graphs-disagree=5`
  (`D0-run-summary.txt:6` currently `4`) and `graphs-answered=21` (`:2`, currently `20`),
  `graphs-unset=4` (`:3`, currently `5`). Those are produced by `bend` + `differ.py`, not by hand.
- `CHECKS` set — `disagree-gate.py:122-123` asserts the run's disagreeing names equal `sorted(PIN)`.
  So `names.py` must name `wmma` among the disagreeers in the re-taken run.
- `CITES` — `disagree-gate.py:83-111`: add a row citing the cause, e.g.
  `("ad117c928^:tinygrad/uop/ops.py", 654, "tc_upcast_axes", "the arg's 4th slot is optional; None is legal")`
  and
  `("tinybendygrad/uop/ops.bend", 1197, "tc: List<&2, U32>", "the port's 4th slot cannot hold None")`.
  `cited()` (`disagree-gate.py:151-157`) requires the needle not be followed by an identifier char,
  so `tc_upcast_axes` / `tc: List<&2, U32>` are safe.
- `SUBSTITUTED` (`disagree-gate.py:80`) is **unchanged** — `wmma` now has an arm
  (`graphcmp.bend:1447`), so it is no longer substituted; the negative check at
  `disagree-gate.py:193` only names `allred`/`cdiv`/`late`.

## 6. `wmma` vs `flip`: a second instance of one class, not the same defect

`flip` (`disagree-gate.py:67`): `shape="BOTH"`, `fault="HARNESS+PORT"`. Its cause
(`ops.bend:1150-1159`, `graphcmp.bend:1310-1313`): the port's **one** variant
`ATuple{ys: List<&2, U32>}` spans **two** upstream arg types — PERMUTE's `tuple[int, ...]` **and**
FLIP's `tuple[bool, ...]` — so a `bool` has no representation and the renderer prints `n(i1,i0)`
where py prints `n(b1,b0)`. The gap is in the tuple's **element type**.

`wmma`: the port's field `AWmma.tc` is a **flat non-optional** `List<&2, U32>` where upstream holds
`Optional[tuple[tuple[(int, int), ...], ...]]`. The gap is in the field's **optionality and nesting**.

**Same class, two mechanisms.** The class is: *the port's `Arg` variant is strictly weaker than
upstream's `arg`, so the renderer emits a spelling for a different value.* `flip` instances it by
collapsing two element types into one; `wmma` instances it by collapsing `None`/empty and flattening
a nested tuple. Neither is the other.

**So: `wmma` is a SECOND INSTANCE OF THE CLASS, not the same defect.** And the class currently has
**one name — `flip`** — which is the "one name for two classes" hazard read backwards: two members
(mechanisms) sharing an instance-named class. The durable naming is structural (e.g. `WEAK-ARG`),
with `flip` and `wmma` as its measured instances; calling the class `flip` would make a third
mechanism look like "another flip".

Both would be fixed the same way in principle — widen the port's `Arg` variant to hold what upstream
holds — which is why they belong to one class; the widening is different in each (a bool-carrying
tuple variant for `flip`, a `Maybe`/nested-pair for `wmma`).

## 7. What only `bend` can settle

I did not run `bend` (another unit holds it). Unsettled by these measurements:

1. **The port's actual emitted arg for `wmma`.** I derived `wm(n(i3,i4,i4),Df32,i256,n())` from
   `graphcmp.bend:440` + `:171-172`; only `bend --graph wmma` prints it. I did not read a
   `D1-graph-wmma.txt` — none exists (the on-disk `runs/graphcmp/D/` is the stale 25-graph run;
   `graphcmp.py`'s `GRAPHS` is already 34, `:1597` names `wmma`).
2. **`wmma`'s `first_row` in the run** (`names.py`'s two independent belts). My `row=11` is the py
   emit's line count; the run's index is what the gate compares (`disagree-gate.py:132-134`).
3. **That `wmma` lands `DISAGREE` at all** and that `graphs-disagree` becomes `5` with no other
   graph moving (the `stable`/`cross`/`plants` lines in `D0-run-summary.txt`).

All three are `bend`-gated and are written as assertions to re-take, not as facts.
