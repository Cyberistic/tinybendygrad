# `loop`: the THIRD STATE — a REFUSAL, and what it is not

**Diagnosis: STATIC ONLY.** Nothing was compiled. No `bend`, no `graphcmp run`, nothing under
`gates/`, no `checks/e2e*`, `sweep.py`, `bounded.py`, `differ.py`, `cites-census.py`, no
pytest/mypy/ruff. The only processes run were `git rev-parse`, `ls`, `grep`, `awk`, `wc`, `date`.

- **HEAD** `4b42c0ccf7e53bb140680a19bbcdaddad2f02bf4` (`4b42c0ccf arenaparam: the 62 self-parenting
  nodes are threaded, and the corpus is 31/34 BEFORE AND AFTER`)
- **Read at** `2026-10-18T17:22Z` – `2026-10-18T17:30Z`
- **Nothing was modified outside `.agents/slop/dg-loop/`.** No fix is proposed and none is made.

> **THE TREE MOVED UNDER ME AND THE READS ARE NOT FROM ONE INSTANT.** A fresh `differ run` was
> writing `runs/graphcmp/D/` throughout: `D1-graph-loop.txt.err` had mtime `Oct 18 20:27` local at
> my first read and `D1-graph-loop.txt` was rewritten again at `20:27`. The cited 05:51:48Z
> summary is a *different, earlier* run. Everything below is quoted from artifacts I read, with
> the read time attached; the DEVICE SETS and the counts are stable across both because both runs
> reproduced them.

---

## 1. THE REFUSAL, IN FULL

`runs/graphcmp/D/D1-graph-loop.txt.err` is **one line, 487 bytes**, and the whole of it is:

```
# devices py=['N', 'sCPU'] bend=['sCPU'] -- NOT WELL-POSED, and this is NOT a verdict (exit 2). The port's graph fixture is pinned at the arena tag 0 and the py graph is on ['N', 'sCPU'], so every consumer of the ALLOC would carry a different `core` and the report would be a cascade of `src` differences with the cause in none of them. Re-run with --dev <the name the port resolved> -- or, if the name is not in the port's table at all, that is a port gap to report, not a flag to set.
```

There is no second line and no truncation. Note the message names **two different repairs** —
"re-run with `--dev`" and "that is a port gap to report" — and §3 below shows that for `loop`
the first one **cannot work**, which is why the message's own advice is insufficient.

The paired stdout artifact is 5 bytes: `rc=2`. **No `VERDICT:` line is emitted at all.**

---

## 2. THE CODE THAT PRODUCES IT

`.agents/slop/graphcmp.py:3313-3333`, inside `main()`'s `diff` branch:

```python
  bd, notes = emit_bend(a.dev, a.graph, probe=probe)
  py = emit_py(a.graph, a.plant)
  # THE PRECONDITION. The port's fixture names one device and the py graph carries
  # whatever `--dev` opened, so the two device sets must be EQUAL before the cores mean
  # anything: an ALLOC whose device differs has a different `core`, which propagates to
  # every consumer and reports as a cascade of `src` differences with the cause in none of
  # them. Exit 2 -- a FAILURE, never a verdict, on the same principle as the 0-row guard.
  pdev, bdev = sorted(devnames(py)), sorted(devnames(bd))
  if pdev != bdev:
    print(f"# devices py={pdev} bend={bdev} -- NOT WELL-POSED, and this is NOT a verdict "
          f"(exit 2). The port's graph fixture is pinned at the arena tag 0 and the py graph "
          f"is on {pdev}, so every consumer of the ALLOC would carry a different `core` and "
          f"the report would be a cascade of `src` differences with the cause in none of "
          f"them. Re-run with --dev <the name the port resolved> -- or, if the name is not "
          f"in the port's table at all, that is a port gap to report, not a flag to set.",
          file=sys.stderr)
    return 2
```

The exit status is documented as a designed state, `.agents/slop/graphcmp.py:249-251`:

```
Exit status: 0 when the two sides agree on every core and every field, 1 when they do not,
2 when the comparison was NOT WELL-POSED or a side produced nothing -- which is a FAILURE
and never a verdict (trap 4 above).
```

**The device-set reader is ONE function applied to both sides**, `.agents/slop/graphcmp.py:2325-2335`:

```python
def devnames(lines: list[str]) -> set[str]:
  """The device names the stream actually carries, read off `ParamArg`'s EIGHTH field
  (ops.py:33, the declaration order this file emits). Only `P(..)` args have one, so a
  `s`-atom elsewhere is never mistaken for a device. Used as a PRECONDITION, not as the
  comparison -- the differ compares the device as part of `arg` either way."""
  out = set()
  for ln in lines:
    arg = unchunks(ln)[6]
    if arg.startswith("P("):
      out.add(split_top(arg[2:-1])[7])
  return out
```

So the two lists are built the *same* way. **The harness does not enumerate devices per side.**
It reads whatever each side's own rows carry. That kills option (c) in the brief — the
asymmetry is in the **rows**, not in the enumeration.

---

## 3. WHY THE PORT CARRIES ONLY `sCPU` — MEASURED OFF THE ROWS

Both canon files are in the run. Reading the 8th `P(...)` field of every row that has one:

| file | rows | `P(` rows | device values |
|---|---|---|---|
| `runs/graphcmp/D/D2-canon-py-loop.txt` | **52** | 7 | `sCPU`×3 (`i2 tl`, `i3 slots`, `i51` the CALL's param) + **`N`×4** (`i8`, `i9 ms`, `i12`, `i38`) |
| `runs/graphcmp/D/D2-canon-bend-loop.txt` | **25** | 4 | `sCPU`×4 (`i2 slots`, `i3 tl`, `i16 tv`, `i24`) |

Sorted: `['N', 'sCPU']` vs `['sCPU']` — exactly the refusal's two lists.

**Every one of the four `N` rows is `addrspace=SREG`; every `sCPU` row is `addrspace=SGLOBAL`.**
The `N` is not a device *name*, it is a **device-less** `ParamArg` — upstream's `device=None`.

Those four rows are upstream's own **`UOp.placeholder`** calls, inlined into the graph because
`hcq_fence` now calls `get_time_ms`, `tinygrad/runtime/support/hcq2.py:67` and `:70`:

```python
@uopfunc
def do_get_time_ms(ms:UOp) -> UOp:
  ts = UOp.placeholder((2,), dtypes.u64, addrspace=AddrSpace.REG)
  ...
def get_time_ms(dep:UOp) -> UOp: return (ms:=UOp.placeholder((1,), dtypes.u64, addrspace=AddrSpace.REG)).after(do_get_time_ms(ms.after(dep)))[0]
```

`hcq_fence` (`hcq2.py:73-78`) calls `get_time_ms` twice, which is why there are four SREG rows.

### The builder that omits them

`.agents/slop/graphcmp.bend:937-944` — the helper every `loop` PARAM is made with:

```
# A PARAM of an arbitrary dtype, volatility and NAME, for the three PROGRAM graphs below.
# `paramf` above is the f32/no-volatility/always-named case and is left alone: it is what
# `g_indexed` and `g_sym` are measured against, and a widened spelling of it would move
# those two fixtures' bytes. `loop` needs `u64` and a volatile PARAM; `lin` needs three
# UNNAMED f32 PARAMs; `gate` needs one named and one unnamed.
def paramd(slot: U32, dtx: S.Dt, nm: Maybe<&2, String>, vol: Bool) -> O.ParamArg:
  O.ParamArg{slot, dtx, None{}, None{}, nm, S.AGlobal{}, Some{S.D1{0}},
    vol, None{}, None{}, False{}, None{}}
```

**Field 7 (the device) is the literal `Some{S.D1{0}}` — arena device tag 0 — for every PARAM the
helper ever builds, and field 6 (the addrspace) is the literal `S.AGlobal{}`.** Neither is a
parameter of `paramd`. The docstring enumerates what the helper parameterises — dtype,
volatility, name — and is **silent on both addrspace and device**. That silence is the whole
answer to "deliberate?": there is no comment claiming `loop` cannot carry a `None` device.

`g_loop` (`graphcmp.bend:1044-1081`) builds **24 nodes + 1 CALL = 25 rows** and calls `paramd`
exactly four times. It models `BACKEDGE/LOAD/STORE/INDEX/RANGE/AFTER/CALL` and **does not model
`get_time_ms` at all** — no SREG placeholder, no `do_get_time_ms` CALL, no `CUSTOM_FUNCTION`,
no `MUL`/`FLOORDIV`, no `AND`. Its own header comment is stale against the live py side:

```
# `hcq_fence`'s three named PARAMs plus the one it takes as an argument. MEASURED off the
# py side's rows: `slots` is slot 0 and UNVOLATILE, `tl` is slot 1 and VOLATILE --
# `hcq_fence` replaces its arg with `volatile=True` itself (hcq2.py:407) -- `tv` is slot 2
# and the caller's PARAM is slot 3 and UNNAMED.
```

**The py side no longer has a `tv` slot.** `g_loop` (`graphcmp.py:1253-1254`) calls
`hcq_fence(tv, tv, 0)`, so `tv` **is** `slots` and interns to `i3`; the live py side's SGLOBAL
params are `i2 tl`, `i3 slots`, `i51` — three, not four.

### THE GROWTH, WITH ITS DENOMINATOR

`.agents/slop/graphcmp-LIMITS.md:83` records the corpus fixture census:

```
| `loop` | 25 | `hcq_fence(...)` -- tinygrad's OWN kernel, `runtime/support/hcq2.py:405-413` | BACKEDGE 1, LOAD 2, STORE 2 |
```

and `:822` — *"`(lin`, `loop)` do so on 1 of 46 and 1 of 25 nodes respectively"* — i.e. **at that
time BOTH sides were 25.** Measured now: **py 52, bend 25.** The py side grew by 27 rows and the
port fixture did not follow. `LIMITS.md:33` records the same run as

```
graphs 24   AGREE 22 (lin/loop DISAGREE, forward-only on purpose)   <-- was 16 / 14
```

**`loop` used to produce a verdict.** It is a REGRESSION from `DISAGREE` to no verdict at all,
not an accepted limitation.

---

## 4. IS IT A PORT GAP? NO. MEASURED, THREE WAYS.

The brief's option (a) is "the port does not implement device `'N'`". It does.

1. **The type exists.** `ParamArg`'s device field is a `Maybe` — `.agents/slop/graphcmp.bend:312-313`:

   ```
   def paramarg.of(+slot: U32, +dtx: S.Dt, +size: Maybe<&2, U32>, +vmin_vmax: Maybe<&2, O.PyRange>, +multiple_of: Maybe<&2, U32>,
     +name: Maybe<&2, String>, +addrspace: S.Addr, +device: Maybe<&2, S.Dev>, +volatile: Bool, +image: Maybe<&2, O.Img>,
   ```

   `Maybe<S.Dev>` **is** upstream's `device: str|tuple[str,...]|None` (`ops.py:33`). `None{}` is
   the representation of `device=None`, and the port builds it: `tinybendygrad/uop/movement.bend:856`,
   `tinybendygrad/uop/fold.bend:4499`, `tinybendygrad/uop/render.bend:1975` and `:2182`.

2. **The REG addrspace exists and is constructed.**
   `tinybendygrad/uop/render.bend:336-341`:

   ```python
   def addr_name(a: S.Addr) -> String:
     match a:
       case S.AGlobal{}: "GLOBAL"
       case S.ALocal{}: "LOCAL"
       case S.AReg{}: "REG"
       case S.Aalu{}: "ALU"
   ```

   and it is built, not only matched — `tinybendygrad/function.bend:1382`,
   `tinybendygrad/renderer/wgsl.bend:246-247`, `tinybendygrad/renderer/nir.bend:1273`.

3. **The port's renderer already prints `N`.** `.agents/slop/graphcmp.bend:261-264`:

   ```
   def dm(m: Maybe<&2, S.Dev>) -> String:
     match m:
       case Some{x}: dev(x)
       case _: "N"
   ```

   **`dm` is the code that writes the very string the py side writes.** The port does not lack the
   capability to emit `N`; the *fixture* simply never hands it a `None{}` device.

`LIMITS.md:447-449` — *"**The device is pinned.** `--dev CPU` by default, because the port's
fixture pins the ALLOC device at arena tag 0"* — justifies pinning for the **ALLOC** graphs
(eager `Tensor`). **`loop` is not an ALLOC graph.** Its `N` is a REG placeholder that the fixture
omits entirely. **LIMITS.md's stated justification does not reach `loop`.**

### AND THE MESSAGE'S OWN FIRST ADVICE CANNOT WORK HERE

The refusal says *"Re-run with `--dev <the name the port resolved>`"*. For `loop` that cannot
succeed: `--dev X` moves the bend side's tag 0 to `X`, but the py side's `sCPU` comes from
`graphcmp.py:1253` — `tv = _storage(Ops.PARAM, 3, dtypes.uint64, 1, device="CPU")` — which is
**hardcoded, not `--dev`-derived**. So the py set stays `['N', 'sCPU']` under any `--dev`, while
the bend set becomes `['X']`. The sets differ for every flag. `--dev` is not the repair.

---

## 5. THE ARITHMETIC, CONFIRMED FROM THE SUMMARY

`runs/graphcmp/D/D0-run-summary.txt` (the 05:51:48Z run cited in the brief):

```
graphs=34
graphs-answered=34
graphs-unset=0
expect-moved=3
graphs-agree=31
graphs-disagree=2
byte-identical=20
```

**34 − 31 − 2 = 1.** Counted independently over the artifacts at `17:30:08Z` — **34**
`D1-graph-*.txt`, **31** containing `VERDICT: AGREE`, **2** containing `VERDICT: DISAGREE`, and
exactly one with no `VERDICT:` line:

```
D1-graph-loop.txt -> rc=2
```

**So `loop` is the only one, and `graphs-unset=0` does not catch it.**

### WHY IT IS INVISIBLE BY CONSTRUCTION — there is no third bucket

`checks/differ.py:731-732` are the only two verdict counters:

```python
        f"graphs-agree={files_with('D1-graph-*.txt', 'VERDICT: AGREE')}",
        f"graphs-disagree={files_with('D1-graph-*.txt', 'VERDICT: DISAGREE')}",
```

**There is no `graphs-refused`.** A refused graph is counted in neither, and the summary has no
row for it. Worse, `checks/differ.py:256` pins `graphs-answered` at `34` and that is computed at
`:722` as `len(graphs) - len(unset)` — a function of the **`WANT` table's row count**, not of
verdicts. So the file reports **`graphs=34, graphs-answered=34, graphs-unset=0`** while one of
the 34 emitted nothing. `differ.py:726-729` names this exact hazard for a different counter
(*"All four can be self-consistent and wrong at once, which is the state this file ran in until
now"*) — and `loop` is that state again, through `graphs-answered`.

### THE CORPUS EXPECTS A VERDICT AND GETS NONE

`checks/differ.py:141` pins `"loop": "AGREE"`. `checks/differ.py:237` lists `loop` in `CONTROLS`
and `:241` in `STAB`. **`loop` is declared, expected to answer `AGREE`, and does not answer.**

---

## 6. CLASSIFICATION

| field | value |
|---|---|
| `verdict_state` | **REFUSED** — exit 2, `D1-graph-loop.txt` == `rc=2`, **no `VERDICT:` line**. Not `PASS`, not `FAIL`, not `SKIP` (a SKIP is exit 4 and `e2e.py:510` returns 4; this is exit 2 and `graphcmp.py:249-251` calls 2 "a FAILURE … never a verdict"). |
| `classification` | **`HARNESS_FIXTURE_STALE`** |

**Why not `PORT_GAP`:** measured false in §4 — the port has `S.AReg`, has `Maybe<S.Dev>` =
`None{}`, builds both, and `dm` already prints the exact string `"N"`. Nothing in
`tinybendygrad/` blocks this graph.

**Why not `DELIBERATE_REFUSAL`:** the refusal *mechanism* is deliberate and correct (a designed
precondition, a designed message, a designed exit). But the *situation* is not a declared
limitation — `paramd`'s docstring enumerates its parameters and says nothing about addrspace or
device; `LIMITS.md`'s "device is pinned" note is about ALLOCs and does not reach `loop`;
`LIMITS.md:33` and `:83` record `loop` as **DISAGREE at 25 nodes**, and `differ.py:141` pins it
`AGREE`. **A state the corpus records as a verdict and the pin table expects to be a verdict is
a regression, not an acceptance.** Calling it a deliberate refusal would retire a graph that is
supposed to be running.

**Why it is the brief's unlisted option (c), not (a) or (b):** `devnames` reads both sides with
one function over one field, so nothing enumerates devices differently. The asymmetry is that
`g_loop` builds 24 nodes and upstream's `loop` now has 52 — and the 27 missing nodes are exactly
the REG placeholders that carry every `N`. **The cause is a harness fixture in
`.agents/slop/graphcmp.bend`, not the port and not the comparator.**

### Does `loop` need work? YES — but not in `tinybendygrad/`

It needs neither "a fix in the port" nor "nothing but a place in the output". It needs the bend
fixture to grow to the live py side: `g_loop` must model `get_time_ms`'s two `do_get_time_ms`
CALLs, their SREG placeholders (`S.AReg{}` + a `None{}` device), the `CUSTOM_FUNCTION`, and the
`MUL`/`FLOORDIV`/`AND` that build the 30000 ms timeout arm — which means `paramd` must stop
hardcoding both `S.AGlobal{}` and `Some{S.D1{0}}`.

**AND THE REAL DEFECT IS UPSTREAM OF ALL OF THAT:** no artifact in the run has a row for a
refused graph. `D1-graph-loop.txt.err` — a 487-byte, fully-formed, correct refusal — is the ONLY
place this state exists, and `D0-run-summary.txt` never mentions it. `loop` is discoverable only
by subtracting two counters from a third.

---

## 7. WHAT I DID NOT DO

No fix. No edit outside `.agents/slop/dg-loop/`. Nothing compiled or executed from `bend`,
`graphcmp`, `gates/`, `e2e`, `sweep`, `bounded`, `differ`, `cites-census`, `pytest`, `mypy`,
`ruff`. Every number above is a read of an existing artifact or a `grep`/`awk` over committed
source, and each carries the read time because **a run was writing `runs/graphcmp/D/` while I
read it.**

## 8. FILES

- `state.rows` — one data row, TAB-separated:
  `graph`, `verdict_state`, `py_devices`, `bend_devices`, `classification`.