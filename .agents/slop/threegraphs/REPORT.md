# threegraphs REPORT — the three arms the bend dispatcher never had

Unit: `.agents/slop/graphcmp.bend` + `.agents/slop/graphcmp.py`. Read `AGENTS.md`: populations
by DISCOVERY, and `SKIP`/`DEAD`/`REFUSED` are not passes.

**I did not run `bend`** (another unit holds it). Everything below that is not a `bend`-run is
marked as such. The one claim only `bend` can settle is named in §3 and §6.

I edited **only** `.agents/slop/graphcmp.bend` (the three arms + three rungs + one doc line).
**I did not edit `.agents/slop/graphcmp.py`, `checks/`, `gates/`, `AGENTS.md`, `tinybendygrad/`,
`runs/`.** I did not commit.

---

## 1. The dispatcher, and the line each arm must be inserted before

`.agents/slop/graphcmp.bend`:

- `rows.pick3(+name: String) -> O.Found` — **`graphcmp.bend:1485`** (was `:1421`). Its body is a
  right-nested `Bool.pick` chain, one rung per `String.eq(name, "<g>")`; the bottom rung is
  **`g_matmul()`** — the FALLBACK. `rows.pick` (`:1517`) is a pass-through; `fz_name` (`:1549`)
  reads argv's tail, so no argument also lands on the matmul.
- **The exact line the three arms must be inserted before is `def rows.pick3`.** They now sit at
  `:1434` (`g_allred`), `:1449` (`g_cdiv`), `:1467` (`g_late`), immediately above it.

**IT DID NOT STAY AT `:1421`, AND IT CANNOT.** A forward reference does not compile in this file:
`bend` rejects it (`helpers.bend:1155`, "expected : a filled definition"). A prior unit placed its
five arms AFTER `rows.pick3` to keep the line fixed and **MEASURED the bend side die** —
`emit bend: 0 rows after 5 attempts — rc=1, Location: rows.pick3` (commit `1ca6afb63`, fixed by
`3ae870111`, which moved the arms before `pick3` and `pick3 :1336 -> :1421`). So placing these three
after `pick3` is not an option, and **`disagree-gate.py:85` must be repointed `1421 -> 1485`** (§5).

## 2. Per-graph: py fixture · bend arm · node/child match

The py fixture is the specification. I read each target off `emit --side py --graph NAME` (the py
side's OWN rows), then mirrored it. Verified statically by `.agents/slop/threegraphs/static-check.py`
(`.venv/bin/python .agents/slop/threegraphs/static-check.py`; `STATIC-CHECK OK`).

| graph | py fixture | bend arm | nodes py | nodes bend | `(op, child-count)` — both sides |
|---|---|---|---|---|---|
| `allred` | `graphcmp.py:1393` | `graphcmp.bend:1434` | **9** | **9** | ALLOC 0 · CONST 0 · CONST 0 · STACK 2 · RESHAPE 2 · CONST 0 · RANGE 1 · COPY 2 · ALLREDUCE 1 |
| `cdiv` | `graphcmp.py:1412` | `graphcmp.bend:1449` | **10** | **10** | ALLOC 0 · CONST 0 · CONST 0 · STACK 2 · RESHAPE 2 · ALLOC 0 · RESHAPE 2 · CMOD 2 · CDIV 2 · GROUP 2 |
| `late` | `graphcmp.py:1457` | `graphcmp.bend:1467` | **12** | **12** | ALLOC 0 · CONST 0 · CONST 0 · STACK 2 · RESHAPE 2 · ALLOC 0 · RESHAPE 2 · SUB 2 · NEG 1 · CMPEQ 2 · FDIV 2 · GROUP 4 |

Both sides' construction order IS the toposort order (the `id` column is a toposort position), so
the arena indices line up and `src` reads `n(i5,i7)` on both sides.

`g_allred` is built through the **port's own constructors** — `O.UOp.copy_to_device` (which mints the
DEVICE RANGE via `device_range_src`, `ops.bend`) and `O.UOp.allreduce` — so the PORT, not the fixture,
is on trial. `cdiv`/`late` hand-assemble, because the port has no `fmod`/rewrite constructor; their
`n()` args and ParamArgs match the py rows field for field (`allocd(0,S.int32(),12)` etc.).

## 3. What is PROVEN statically (and what is NOT)

`static-check.py` proves, from the SOURCE text:

1. each builder defined exactly once;
2. every `O.`/`S.`/`H.` symbol an arm names RESOLVES (`ops.bend` 1008 symbols, `spec.bend`,
   `helpers.bend`) — including `O.UOp.copy_to_device` (`ops.bend:7617`) and `O.UOp.allreduce`
   (`:4524`);
3. every `O.UOp.<ctor>` call's arity equals the port's `def UOp.<ctor>` parameter count
   (`copy_to_device` -> 4, `allreduce` -> 4, `new` -> 5, `const` -> 2, all non-vacuous);
4. `rows.pick3` wires each name to ITS arm and has exactly one `g_matmul()` default;
5. the ordered `(op, child-count)` sequence and the node count equal the py rows'.

**THIS IS NOT A COMPILE.** It does not typecheck bend's linearity/ownership (`+` binder reuse), and
it cannot prove the emitted BYTES equal the py rows — dtype/shape are the FOLD's output, a `bend`
fact. `bend` running the arms and `graphcmp.py diff --graph NAME` are still owed (§6).
*Supporting (read-only): the fold already carries dtype/shape arms for all six new ops
(`fold.bend`: GROUP `late()` :2331, CMOD :2388, CDIV :2386, SUB :2392, NEG :2354, CMPEQ :2370,
FDIV :2372, COPY/ALLREDUCE thru0 :2349/:2353), so the fold is not the missing piece.*

## 4. Predicted first-run verdicts

**`cdiv` — AGREE.** **`late` — AGREE.** Every atom matches: `N` args (GROUP, CMOD, CDIV, SUB,
NEG, CMPEQ, FDIV), the i32/f32 ParamArgs, `CMPEQ` -> `bool`, `GROUP` -> `(void, R)`. Nothing in
either graph touches the one thing that could diverge on `DEV=CPU` (a device tuple).

**`allred` — DISAGREE, and the substitution was hiding a REAL difference: the device-tuple NORMAL
FORM.** This is the `flip` pattern again — `?=0` on both sides while `DISAGREE`ing. Two rows
differ, and neither is the port's graph *shape* (`nodes=9/9`, 7 shared cores):

```
COPY      py=n(sCPU,sCPU)          bend=ssCPU,sCPU
ALLREDUCE py=al(OADD,sCPU,CPU)     bend=al(OADD,ssCPU,sCPU)
```

Two independent renderer defects, both in the DIFFER's text, not in the port (`.agents/slop/ADEV.md`
measured all of this, and it is why the cause is a spelling and not a shape):

- `graphcmp.py` has **no `carg` arm for `COPY`** (`:479-566`; `ALLREDUCE` has one at `:498`), so the
  device tuple falls to the generic `_carg` tuple grammar and **nests** `n(sCPU,sCPU)`, while
  `ALLREDUCE`'s arm flattens `sCPU,CPU` — two spellings of one value, two nodes apart.
- `graphcmp.bend`'s `devs` (`:158-159`) **double-prefixes**: `bstr(String.join(devs.go(..), ","))`
  where `go` already yields `dev1(t)` = `bstr(..)`, so `S.Dn{[0,0]}` prints **`ssCPU,sCPU`** — a
  THIRD spelling, matching neither.

**What would make `allred` AGREE:** the ADEV fix, and it is a DELETION per file (ADEV-1/2: a union
rendered by two functions is a defect). Measured (`ADEV.md` §3, real revert): before `DISAGREE`,
after `AGREE 9/9 cores`, denominator and row count UNMOVED.
- `graphcmp.py`: **delete `dev` (`:404`)**, and both call sites — `carg`'s `ALLREDUCE` (`:498`) and
  `paramarg`'s device field (`:714`) — say `_carg`.
- `graphcmp.bend`: `devs` renders `n(` + the comma-joined members + `)`, not a double-`bstr`.
I did **not** land it: it is a NORMAL-FORM decision on the py ORACLE, and ADEV left it uncommitted
(“Nothing committed”). Landing it moves the three `graphcmp.py` CITES rows (§5). **Reported, not
hacked.**

`cdiv`/`late` would DISAGREE only if the fold left a dtype/shape unsettled (`?` column) — it does
not (§3) — or if a ParamArg field drifted (slot/dtype/size); the arms mirror those by hand.

## 5. What `checks/disagree-gate.py` needs, once these land (+ a fresh run)

The gate reads `runs/graphcmp/D/`, which is STALE (25 graphs, no `allred`/`cdiv`/`late` arms), so
every line below needs `checks/differ.py run` re-run with `bend` first. **I did not edit the gate.**

| location | now | needed |
|---|---|---|
| `CITES` `graphcmp.bend:1421` `"def rows.pick3"` | `:1421` | **`:1485`** (moved +64; §1). The other bend cite (`:764`, `OpsGROUP`) and all `graphcmp.py` cites are **unmoved**. |
| negative-claim lane `:188-196` | asserts `rows.pick3` has NO arm for `allred`/`cdiv`/`late` | **delete** — it now fires for all three (measured: `.venv/bin/python checks/disagree-gate.py --lane citations` returns 4 fails, 3 of them this claim). |
| `PIN` `:63-77` | `{allred, cdiv, late, flip}`, `len(PIN)=4` | **`cdiv` and `late` LEAVE** (AGREE, §4) -> **`len(PIN)` 4 -> 2** `{allred, flip}`. `allred` STAYS (DISAGREE) but re-measures: first row **6 -> 8** (the COPY row), `fields=("arg",)`, `shape`/`fault` re-derived. |
| `SUBSTITUTED` `:80` | `("allred","cdiv","late","matmul")` | **`()`** — no bend cluster contains them once they have arms (`names.py:silent_default_cluster`). |
| `SUBSTITUTION_ARTEFACTS` `:285-289` | the 8 py-only ops | **`{}`** — `ALLREDUCE COPY CDIV CMOD FDIV CMPEQ NEG SUB` are now reached on BOTH sides, so `lane_coverage`'s `one_sided` set empties and `:318`/`:324` must be rewired. |
| `D0-run-summary.txt` | `graphs-disagree=4` | must read `graphs-disagree={len(PIN)}` = the new value. |

Predicted gate delta if `allred` is left DISAGREEing: `PIN` 4 -> 2, `SUBSTITUTED` 4 -> 0,
`SUBSTITUTION_ARTEFACTS` 8 -> 0. If the ADEV fix also lands: `PIN` 4 -> 1 (`{flip}`), and the
`graphcmp.py` cites `:1385/:1393/:1412/:1457` move up by the `dev` deletion.

## 6. Handoff to the `bend` unit, IN ORDER

1. **Run the three arms** (this is the step that makes them proof):
   `bin/bend .agents/slop/graphcmp.bend allred` (then `cdiv`, `late`), then
   `.venv/bin/python .agents/slop/graphcmp.py diff --graph <name>` for each.
   If a side emits 0 rows, apply graphcmp.py's trap 4 (re-run; a 0-row side is a FAILURE, never a
   verdict).
2. **Expect `cdiv` AGREE, `late` AGREE, `allred` DISAGREE** at the COPY/ALLREDUCE `arg` (§4).
3. **If `allred` agreement is wanted, land the ADEV device fix** (`ADEV.md` §5, exact edits): delete
   `dev` in `graphcmp.py` and route `ALLREDUCE` + `paramarg` to `_carg`; render `devs` in
   `graphcmp.bend` as `n(sCPU,sCPU)`. Then re-run `allred` — expect AGREE 9/9.
4. **Re-run `checks/differ.py run`** to refresh `runs/graphcmp/D/` (the gate's input).
5. **Then, and only then, move the gate** (§5) as ONE commit: `CITES` 1421 -> 1485, delete the
   negative-claim loop, re-derive `PIN`/`SUBSTITUTED`/`SUBSTITUTION_ARTEFACTS`, and
   `graphs-disagree`.
6. Re-run `.agents/slop/threegraphs/static-check.py` if any arm is edited.

**Files this unit wrote:** `.agents/slop/graphcmp.bend` (three arms `:1434`/`:1449`/`:1467`, three
rungs in `rows.pick3` `:1485`, one doc line `:1539`), `.agents/slop/threegraphs/static-check.py`,
this file.
