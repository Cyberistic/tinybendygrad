# awmma — `AWmma.tc` is `Maybe` (upstream's `tc_upcast_axes` is `tuple|None`); the port's `List` was the bug

Unit `awmma`, 2026-10-06. **STATIC-ONLY: `bend` was NOT run** (another unit holds it). Python only;
no `.txt`; no commit, no `git add`, no `@`.

## 0. What I changed (2 files, both mine; `ops.bend` net +7 lines, `render.bend` net 0)

`tinybendygrad/uop/ops.bend` — the type, its one constructor, its equality, one fixture.
`tinybendygrad/uop/render.bend` — the port's `repr`-mirror arm.
**I did NOT touch** `checks/`, `gates/`, `AGENTS.md`, `.agents/slop/graphcmp.*` (my grant forbids
them). **Consequence, stated up front: `graphcmp.bend` will not compile until its 3-line ripple
lands (§4). That ripple is the deliverable I am forbidden to apply.**

## 1. The PIN (not the worktree) — `ad117c928^:tinygrad/uop/ops.py:652-654`

```
652  def wmma(a:UOp, b:UOp, acc:UOp, dims:tuple[int, int, int], threads:int, tc_upcast_axes=None):
653    # dtype_in is stored in the arg (not derived from src[0].dtype) because bitcast rewrites change src dtypes
654    return UOp(Ops.WMMA, src=(a, b, acc), arg=(dims, a.dtype, threads, tc_upcast_axes))
```

**Three arg NAMES after `self`'s three srcs: `dims:tuple[int,int,int]`, `threads:int`,
`tc_upcast_axes` with default `None`.** The arg tuple is `(dims, a.dtype, threads, tc_upcast_axes)`.
**So slot 4's domain is `None` OR a tuple** — a plain optional; `()`, `(0,1,2,3)` and `None` are
three distinct values. The one upstream caller is
`ad117c928^:tinygrad/codegen/opt/postrange.py:229,235` (`tc_upcast_axes=tc_upcast_axes`), which even
carries `# TODO: remove tc_upcast_axes from the arg`. `argstr` (`ops.py:272-274`) is `repr(self.arg)`
for WMMA, i.e. `((3, 4, 4), dtypes.f32, 256, None)` when absent — **`None`, not `[]`** (MEASURED,
`.venv/bin/python`).

## 2. Both sides' spelling (file:line), and where the `None` died

| site | before | prints |
|---|---|---|
| `tinybendygrad/uop/ops.bend:1197` `AWmma{…, tc: List<&2,U32>}` | **cannot hold `None`**; absence stored as `Nil{}` | — |
| `tinybendygrad/uop/ops.bend:7332` `UOp.wmma(…, tc: List<&2,U32>)`, `:7519` fixture `… Nil{}` | same | — |
| `.agents/slop/graphcmp.bend:445` `case O.AWmma{…, tc}: … us(tc)` | `us(Nil{})` | **`n()`** |
| `tinybendygrad/uop/render.bend:606` `awmma_repr(…, tc: List)` | `[…, []]` | **`[]` (second loss)** |
| `.agents/slop/graphcmp.py:490-494` `carg`, `if tc is not None else ATOMS["none"]` | already correct | **`N`** |
| `.agents/slop/graphcmp.py:1533` `g_wmma` `arg=(…, 256, None)` | already correct | — |

**MEASURED (py lane, CPython only, no bend):**
`.venv/bin/python .agents/slop/graphcmp.py emit --side py --graph wmma`, row 11 of 11:
```
3:i11 4:WMMA 3:f32 11:(l0:4,l0:3) 2:i0 1:N 27:wm(n(i3,i4,i4),Df32,i256,N) 12:n(i4,i8,i10)
```
py = `…,i256,N)`. The port's `us(Nil{})` = `…,i256,n())`. **One value (`None`), two spellings, and
the port's is the spelling `graphcmp.bend:216-218` reserves for a PRESENT empty tuple.** The
`None` is lost at the TYPE (`List` cannot hold it), and surfaces in TWO port renderers
(`graphcmp.bend`'s `argstr`, `render.bend`'s `awmma_repr`).

## 3. The decision: `Maybe<&2, List<&2, U32>>` — the port's EXISTING optional vocabulary

**It is `Maybe`, not a new sum type.** The port already spells `tuple|None`/`str|tuple|None` with
`Maybe` and already has the wrappers, counted:
* **`Maybe<&2, List<…>>` occurs 47× in `ops.bend`** (`KernelInfo.opts_to_apply:
  Maybe<&2,List<&2,OPT>>` at `:999` is a `Data` field — proof a `Maybe` of a `List` is a legal field).
* **17 `eq_opt_*` defs** already exist (`eq_opt_op`/`eq_opt_dt`/`eq_opt_tag` are `Maybe<List<…>>`
  wrappers). The u32-list member was simply missing; I added it (§0). **A new sum type here would be
  a second vocabulary for a shape `Maybe` already covers.**
* `ParamArg.device: Maybe<&2, S.Dev>` (`:878`) is the ADEV shape — `str|tuple|None` in `Maybe`.

**Of the 16 `Arg` variants (`ops.bend:1181-1201`), `AWmma` is now the ONLY one holding a `Maybe`.**
So the fix is one variant + its renderer, not a shared helper's retune — but the equality wrapper
and the renderer are exactly the shared vocabulary `adevfix` pointed at.

## 4. THE COMPLETE RIPPLE LIST (old → new)

### Applied (mine)

| file:line | old | new |
|---|---|---|
| `ops.bend:1197` | `AWmma{…, tc: List<&2,U32>}` | `…, tc: Maybe<&2, List<&2,U32>>}` |
| `ops.bend:1141` (comment) | `… AWmma   WMMA arg` | `… WMMA arg. `tc` is a `Maybe` (upstream's slot is `tuple\|None`)` |
| `ops.bend:1635` (**new**) | — | `def eq_opt_u32s(x: Maybe<&2,List<&2,U32>>, y: …) -> Bool:` (4-arm Maybe eq over `eq_u32`) |
| `ops.bend:2037` | `eq_arg.AWmma(…, +tc: List<&2,U32>)` | `…, +tc: Maybe<&2,List<&2,U32>>` |
| `ops.bend:2039` | `eq_u32(tc, y4)` | `eq_opt_u32s(tc, y4)` |
| `ops.bend:7332` | `UOp.wmma(…, tc: List<&2,U32>)` | `…, tc: Maybe<&2,List<&2,U32>>` |
| `ops.bend:7519` | `UOp.wmma(…, 32, Nil{})` | `UOp.wmma(…, 32, None{})` |
| `render.bend:606-607` | `…, tc: List<&2,U32>` / `… [", ")]` | `…, tc: Maybe<&2,List<&2,U32>>` / `Bool.pick(String, Maybe.is_some(&2,List<&2,U32>,tc), u32_list_repr(Maybe.default(&2,List<&2,U32>,tc,Nil{})), "None")` |

### UNAPPLIED — forbidden to me, REQUIRED for `graphcmp.bend` to compile (3 edits)

`graphcmp.bend` has the exact idiom already: `mum(mm/nm/dm)` render `Maybe` as `N` (`:219-240`).
Mirror it for a `Maybe` list (this is the `us`/`n(...)` twin of `mum`/`i(...)`):

| file:line | old | new |
|---|---|---|
| `graphcmp.bend` (new def, beside `us` at `:176`) | — | `def um(m: Maybe<&2, List<&2, U32>>) -> String:` / `  match m:` / `    case Some{x}: us(x)` / `    case _: "N"` |
| `graphcmp.bend:445` | `… ",", U32.show(threads), ",", us(tc), ")")` | `… ",", U32.show(threads), ",", um(tc), ")")` |
| `graphcmp.bend:1421` | `…, 256, Nil{})` | `…, 256, None{})` |

**`graphcmp.py` needs NO change**: `carg`'s WMMA arm (`:490-494`) already branches
`… if tc is not None else ATOMS["none"]`, and `g_wmma` (`:1533`) already passes `None`. The task's
"two `g_wmma` builders" is therefore **one** — only the `.bend` builder writes the wrong value.

### Prose citations that shift because `ops.bend` gained 7 lines at `:1635` (REPORTED, not moved)

`checks/nl-gate.py:39,40,477` cite `ops.bend:7837`/`:7874` → now **`:7844`/`:7881`**;
`gates/ops-core-gate.py:12` cites `:5044-5045` → **`:5051-5052`**. Both are prose.
**No HARD pin moves**: `checks/disagree-gate.py`'s only `ops.bend` CITES are `:1117` and `:999`
(`:113-131`), both ABOVE `:1635`, so `cited()` still reads its needles. `render.bend`'s lines do
NOT move (net 0), so `rn-gate.py`'s `:2148`/`:2809`/`:2693` cites stand.

## 5. What ONLY `bend` settles (a static check cannot)

1. **That `ops.bend` + `render.bend` COMPILE** with `Maybe<&2, List<&2, U32>>` as a `Data` field and
   `Maybe.is_some`/`Maybe.default` in the one-line `awmma_repr`. A type change is proven by the BODY
   compiling; no static tool here compiles Bend.
2. **That `graphcmp.bend diff --graph wmma` returns `AGREE 11/11`** — a normal-form change is about
   OUTPUT TEXT, and only bend prints bend's bytes. Py is MEASURED to `…,i256,N)` (§2); the bend
   `um(None{})` is static arithmetic to `"N"`.
3. That the port's own `sg_wmma` row (`:7519`) still prints `wmma:32/f32` (`sg.ctor` ignores `tc`).

`SKIP`/`DEAD`/`REFUSED` are not passes; the bend lane today is **UNMEASURED**.

## 6. Two things I did NOT fix, named so they are not re-decided

1. **The present value is a NESTED tuple `tuple[tuple[(int,int),…],…]` upstream; the port (and
   `graphcmp.py`'s `carg`) model it FLAT (`List<U32>`).** Unmeasured in this corpus (no fixture
   mints a present `tc`) and **out of scope**: it is the same class as `flip`'s
   `ATuple{ys:List<U32>}` spanning `tuple[int,…]` vs `tuple[bool,…]` (`ops.bend:1150-1159`). Fixing
   it needs a nested-pair variant, which is `flip`'s fix, not this one's.
2. **`render.bend:606`'s `awmma_repr` is ALSO divergent in its `dims` slot**: it prints
   `[3, 4, 4]` (a `List`) where CPython's `repr` of the tuple is `(3, 4, 4)`. It should be
   `u32_tuple_repr(dims)`. Unmeasured — there is **no `arg_repr AWMma` fixture** in
   `render.bend`'s rows (`:2979-3000`) — so I left it; changing unmeasured bytes is risk, not a fix.

## 7. The denominator

* **`Arg` variants: 16** (`ops.bend:1181-1201`); **1** holds a `Maybe` (`AWmma.tc`); **2** hold a
  bare `List<U32>` (`AWmma.dims`, `ATuple.ys`). The device/`str|tuple|None` shape lives in
  `ParamArg.device` + `ADev`/`AAllred.dev` and was settled by `adevfix`.
* **`Maybe<&2, List<…>>` sites: 47** in `ops.bend`; **`eq_opt_*` wrappers: 17** (now 18 with
  `eq_opt_u32s`).
* **Port renderers that lost this `None`: 2** (`graphcmp.bend`'s `argstr` via `us`; `render.bend`'s
  `awmma_repr`). NPY-side: 0 (`carg` already correct).
* **`wmma` is one of ONE** — the only `Arg` carrying an optional list — so the fix is this variant's,
  not a shared helper's retune; the helper (`eq_opt_u32s` / `um`) is the reused vocabulary.
