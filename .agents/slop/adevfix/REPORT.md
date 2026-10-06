# adevfix — the device-tuple normal form: the decision, applied, and the collision behind it

Unit: `.agents/slop/graphcmp.py` (`carg`) + `.agents/slop/graphcmp.bend` (`devs`/`dev`).
Read `AGENTS.md`: populations by DISCOVERY; `SKIP`/`DEAD`/`REFUSED` are not passes.
**`bend` was NOT run** (another unit may hold it). Every claim below is marked as what it is,
and §5 names the one claim only `bend` settles.

**Files I edited (2):** `.agents/slop/graphcmp.py`, `.agents/slop/graphcmp.bend`.
**I did NOT touch** `checks/`, `gates/`, `AGENTS.md`, `tinybendygrad/`, `runs/graphcmp/D/`,
`graphcmp-oracle.py`, or anything else. **I did not commit or `git add`.**

---

## 1. The normal form, from the PIN (`ad117c928^:tinygrad/uop/ops.py`)

A device is a UNION, and the tuple arm is stored **verbatim**, never flattened. PIN lines
(measured off `git show 'ad117c928^:tinygrad/uop/ops.py'`, 1928 lines — **the worktree's numbers
are 3 lower**; `ADEV.md` quotes the worktree, so its `758/765/677` are the re-vendored
positions, not the pin's):

| PIN `ops.py` | says |
|---|---|
| `:32` | `device: str\|tuple[str, ...]\|None = None` — `ParamArg`'s device, the union |
| `:682` | `allreduce(self, op, device:str\|tuple[str, ...])` → `UOp(Ops.ALLREDUCE, src=(self,), arg=(op, device))` |
| `:768` | `copy_to_device` → `UOp(Ops.COPY, src=(inp, *UOp.device_range_src(device)), arg=device)` — **stored verbatim** |
| `:849` | `device_range_src(device:str\|tuple[str, ...]\|None)` = a range **iff** `isinstance(device, tuple)` |
| `:890-903` | `def device(...)`: `:899` `if self.op is Ops.COPY: return self.arg`; `:900` `if self.op is Ops.ALLREDUCE: return self.arg[1]` |

**The `__repr__`/`argstr` path** (PIN): `UOp.__repr__` `ops.py:269-271` → `tinygrad/uop/render.py:14`
`pretty_print` → `f"...{type(x).__name__}({x.op}, arg={x.argstr()}...)"` → `argstr` `ops.py:272-274`
returns `repr(self.arg)` (except `REDUCE`).

**Exact text.** Upstream's raw `argstr` is Python `repr`: COPY → `arg='CPU'` for a str and
`arg=('CPU', 'CPU')` for the pair; ALLREDUCE → `arg=(Ops.ADD, ('CPU', 'CPU'))`. **The differ's
canonical text is not `repr`** — it is its own atom grammar, where a name is `s`+name and the
generic tuple opener is `n(..)`. So the differ MUST spell the pair `n(sCPU,sCPU)` and the bare
str `sCPU` — the two arms are two DIFFERENT values and both must render (the flatten collides on
`('CPU',)` vs `'CPU'` and on `('CPU,CPU',)` vs `('CPU','CPU')`; upstream branches on exactly that
union at PIN `ops.py:849`, `:681`, `:699`, `spec.py:29/:140`). Measured with CPython (worktree;
`argstr`/`device` are byte-identical to the pin at those lines):

```
'CPU'              COPY argstr= 'CPU'              ALLREDUCE argstr= (Ops.ADD, 'CPU')
('CPU',)           COPY argstr= ('CPU',)           ALLREDUCE argstr= (Ops.ADD, ('CPU',))
('CPU','CPU')      COPY argstr= ('CPU', 'CPU')     ALLREDUCE argstr= (Ops.ADD, ('CPU','CPU'))
```

## 2. Both sides' spelling — BEFORE the fix (HEAD), and where it moved

**`graphcmp.py` `carg`** (HEAD `:476-553`; now `:477-…`) — the per-op arms, in order: `CONST RANGE
REDUCE WMMA INS ALLREDUCE CUSTOM_FUNCTION CALL SINK(None) SINK PROGRAM`, then the fallthrough
`_carg` (`:563`). **It had NO `COPY` arm and NO `CUSTOM`/`CUSTOMI` arm.** With no COPY arm, COPY
already fell to `_carg` → `tup(..)` → `n(sCPU,sCPU)` (**correct by accident**); `ALLREDUCE` had an
arm (HEAD `:498`) using `dev(x[1])`, and `dev` (HEAD `:404-411`, the block now occupied by
`f32bits` at `:404`) **flattened** a tuple to `ATOMS["str"] + ",".join(x)` = `sCPU,CPU`. **One
value, two spellings, two nodes apart.** `paramarg`'s device field (HEAD `:714`, now `:715`) also
called `dev`. **AFTER:** `dev` is gone; `carg` `:496` `if op is Ops.COPY: return _carg(x)`;
`:498` `al(…, _carg(x[1]))`; `paramarg` `:715` `_carg(pa.device)`.

**`graphcmp.bend` `devs`/`dev`** — `dev1` (`:147-148`) = `bstr(R.dev_name.tag(t))` = `sCPU`;
`devs` (`:158-159`, now `:163-164`) was `bstr(String.join(devs.go(ts, Nil{}), ","))` — **a second
`bstr` over members already `bstr`'d by `dev1`**, so `S.Dn{[0,0]}` printed **`ssCPU,sCPU`**: a
THIRD spelling. `dev` (`:161-164`, now `:166-169`) dispatches `S.D1`→`dev1`, `S.Dn`→`devs`.

## 3. THE UNCOMMITTED DECISION — it EXISTS, verbatim

```
grep -rl "ADEV" .agents/slop/        ->  .agents/slop/ADEV.md , .agents/slop/adev/CLAIM.md , ...
```

`.agents/slop/ADEV.md:1` (unit `ADEV`, 2026-10-04) and `.agents/slop/adev/CLAIM.md` are the
decision. It was never committed; the files were later **reverted by the index reset** (current
md5s differ from `CLAIM.md`'s final `4a0d2467…`/`184f7edd…`, and `dev` is back). Verbatim:

> **ADEV-1. `S.Dev`'s two arms are two values. Never render a device tuple by flattening it.**
> **ADEV-2. A union rendered by TWO functions is a defect waiting for its second spelling.**
> … the special renderer must **die**, not be retuned: `dev` is deleted, not rewritten.
>
> `graphcmp.py` — `dev()` DELETED (it existed only to flatten; both call sites now say `_carg`);
> one new `carg` arm `if op is Ops.COPY: return _carg(x)`; …
> `graphcmp.bend` — ONE body changed: `devs` now wraps `n(..)` instead of `bstr(...)`.
> `g_allred` reads AGREE … NOT COMMITTED.

**I did not re-decide it. I applied it.** Two witnesses in the decision disagree on one point:
`ADEV.md` §5 names only the two `dev` call sites, while `CLAIM.md` also says the COPY arm was
ADDED. I applied the COPY arm (it is behaviourally the fallthrough, but it makes the device
population explicit and mirrors bend's `ADev` arm). Measured: COPY's text is unchanged by it —
the change is ALLREDUCE's. (§4 proves only ALLREDUCE moved.)

## 4. The fix, applied (2 files)

* `graphcmp.py`: **`dev` deleted** (`:404-411`); `ALLREDUCE`'s arm → `_carg(x[1])`; `paramarg`'s
  device field → `_carg(pa.device)`; `if op is Ops.COPY: return _carg(x)` added. `dev`'s str/None
  branches were already identical to `_carg`'s, so **only a tuple device moves.**
* `graphcmp.bend`: `devs` → `String.concat(["n(", String.join(devs.go(ts, Nil{}), ","), ")"])`
  (the `n(` opener `us` at `:171-172` and `img2` at `:176` already use). Comment rewritten.

**PROVEN STATICALLY (py side, `.agents/slop/adevfix/emit_diff.py`, no `bend`):** over all **34**
graphs, py-side rows for **exactly 1 graph moved**:

```
## allred
  9  HEAD : ... ALLREDUCE ... arg=al(OADD,sCPU,CPU)
      FIX  : ... ALLREDUCE ... arg=al(OADD,n(sCPU,sCPU))
```

and allred's COPY was **already** `n(sCPU,sCPU)` (no arm needed). Every other graph is
byte-identical. **`.venv/bin/python .agents/slop/adevfix/emit_diff.py` → rc=0.**

**PROVEN STATICALLY (string arithmetic, no `bend`):** `devs.go` yields `dev1(t)="sCPU"`;
`devs` now = `"n(" + "sCPU,sCPU" + ")"` = `n(sCPU,sCPU)` — matching py and bend's own `us`.
**What only `bend` settles:** that this `.bend` body COMPILES and that `graphcmp.bend diff
--graph allred` returns `VERDICT: AGREE 9/9`. A normal-form change is about OUTPUT TEXT, and no
static check can produce bend's bytes.

## 5. THE COLLISION — ADEV's "oracle untouched" is STALE, and this is a SECOND decision

`ADEV.md` §9 says `graphcmp-oracle.py` was left untouched and `selfcheck: OK`. That was true on
2026-10-04. On today's tree it is **FALSE**, because a LATER decision (`DEFECT 28`, 2026-10-06)
patched the census for the FLATTENED form that ADEV-1 forbids:

* `graphcmp-oracle.py:54` `PAYLOAD_LAST_FIELD = ("al(",)"` + `atoms()` (`:57-96`) takes the
  payload's first letter unconditionally. **MEASURED**: `atoms("al(OADD,sCPU,CPU)") ==
  {"a","O","s"}` (the flatten the hack exists for) but `atoms("al(OADD,n(sCPU,sCPU))") ==
  {"a","O","n"}` — and **`n` is neither an atom (`graphcmp.py:324` `ATOMS`) nor a composite
  prefix (`:336` `COMPOSITE`)**. So the census's `unknown` set becomes `{n}` and its own
  selfcheck (`graphcmp-oracle.py:336-337, 460`) prints `# ORACLE SELFCHECK: FAIL`, rc=1.
* `selfcheck/plants.py:292-339` `plant2` is the guard for that hack and asserts
  `atoms("al(OADD,sCPU,CPU)") == {"a","O","s"}` and `hasattr(o, "PAYLOAD_LAST_FIELD")`.

**Consequence on a fresh `differ.py run`:** `checks/differ.py:242` `"oracle-selfcheck":
"# ORACLE SELFCHECK: OK"` → FAIL, and `:234` `"census-rc": "rc=0"` → `rc=1`, unless
`PAYLOAD_LAST_FIELD` dies with the flatten. The renderers' grammar is now unambiguous — the
nested form needs no form-specific rule; `_atoms` already reads it — so the coordinated change is:
delete `PAYLOAD_LAST_FIELD`, simplify `atoms` → `_atoms`, drop the `:338-351` selfcheck block and
`plants.py` plant2. **I did not make it**: it is outside this unit's grant (`carg` + `devs`/`dev`)
and touches a second instrument set. **This paragraph is the write-down so it is not decided
twice.**

## 6. What MOVES if `allred` goes DISAGREE → AGREE (file:line, old/new — none edited)

`checks/disagree-gate.py`:
* `:63` `PIN = {` — `:64` `"allred": dict(row=6, fields=("arg",), shape="NOT A ROW", fault="HARNESS")`
  **LEAVES** the dict. (With the three `threegraphs` arms landed but ADEV NOT applied, `allred`
  STAYS and re-measures: **row 6 → 8** — the COPY row — `fields=("arg",)`.)
* `len(PIN)` is **derived, never written** (`:7`). Old `4` `{allred,cdiv,late,flip}`; with the
  arms `allred`+`cdiv`+`late` leave → new `1` `{flip}`. (`cdiv`/`late` were predicted AGREE,
  not defects — see §7.)
* `:80` `SUBSTITUTED = ("allred", "cdiv", "late", "matmul")` → the substituted set is NOT empty;
  see §7.

`runs/graphcmp/D/D0-run-summary.txt` (STALE: `graphs=25`, the corpus is 34):
* `:6` `graphs-disagree=4` is `len(PIN)`; `checks/disagree-gate.py:165` asserts the two agree.
  Old `4`; after a fresh run with arms+ADEV fix it must be regenerated to `len(PIN)`.

`checks/differ.py` `PINS` (`:213-243`) — all become stale on the same fresh run:
* `:221` `"graphs": "25"` → 34; `"graphs-unset": "5"`, `"graphs-answered": "20"` likewise.
* `:233` `"graphs-agree": "21"` / `"byte-identical": "21"` (a function of the PORT — allred adds 1
  among the other movements).
* `:234` `"selfcheck"`, `"census-rc"` and `:242` `"oracle-selfcheck"` — see §5.

`checks/corpus-figure.py` `run_health()` (imports `differ.py`'s `PINS` and compares all 17, plus
derives `graphs` from `len(gc.GRAPHS)`, `:1590`): a `D0-run-summary.txt` that still reads
`graphs=25` against a 34-graph corpus prints `RUN HEALTH : **FAILED**` until the run is re-taken.
**`corpus-figure.py` was NOT edited.**

## 7. Was `allred` the LAST real port defect behind the substitution? — NO, and not the last substitution either

* **`allred`'s defect was real** and is not a shape difference: `nodes=9/9`, and only the device
  `arg` was wrong — a spelling. It is now a spelling both sides make the same way.
* **But the substitution is NOT closed.** `graphcmp.bend:1490` `rows.pick3` has **29** rungs over
  a **34**-graph corpus (`graphcmp.GRAPHS`, read with `.venv/bin/python`). The corpus names with
  **no bend arm** are `custom_function`, `mselect`, `mstack`, `stage` (plus `matmul`, which IS the
  default `g_matmul()` at `:1520`). `rows.pick` (`:1522-1526`) is a pass-through, so **those four
  fall to `g_matmul()` and are substituted exactly as `allred`/`cdiv`/`late` were** — anything
  real in them is still hidden. Confirmed against the run: none of the four has a
  `D2-canon-bend-*.rows` at all (the run predates them).
* **`disagree-gate.py:80`'s `SUBSTITUTED` is a hand list and is now stale**: it names the OLD four
  and misses these four. The by-discovery instrument is `names.py:silent_default_cluster`
  (`:228-236`, groups bend canon by sha256) — the gate should ask it, not carry a literal.

So: `flip` remains a genuine `DISAGREE` (PIN `:67`, shape `BOTH`, fault `HARNESS+PORT`), `allred`
leaves, and **four more graphs are waiting behind the same substitution** — un-compared, not
(measured) defective.

## 8. Verdicts I am and am not entitled to

* `cdiv` / `late`: **AGREE** — inherited from `threegraphs` §4; I did not re-measure them (`bend`).
* `allred`: **predicted AGREE 9/9** once `bend` runs — py side **MEASURED** to now emit
  `n(sCPU,sCPU)` and `al(OADD,n(sCPU,sCPU))`; bend side is **static only** (§4). `SKIP`/`DEAD`/
  `REFUSED` are not passes, and the only honest verdict for the bend lane today is **UNMEASURED**.

## 9. md5s (post-fix; before were `b798adbe…` / `73a9ce7e…`)

```
graphcmp.py    858c78c19d925788659195e6eded5c29
graphcmp.bend  863f8da4d32fe9d0a107afe00701bbc9
```
