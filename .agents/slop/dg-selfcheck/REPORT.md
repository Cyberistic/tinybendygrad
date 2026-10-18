# `oracle-selfcheck` — static diagnosis

**HEAD** `e92adbb5cc1023eb6e2b7e2801a0a7c5e5cd27de` (`lanes: a member that PRINTED rows and had them
compared by nothing is DEAD, not PASS`) · **read at** `2026-10-18T18:49:27Z` · **mode: static only.**
Nothing was compiled, no `bend`, no `graphcmp`, nothing under `gates/`, no `checks/differ.py`. The only
Python executed was `ast.parse` over `.agents/slop/graphcmp-oracle.py` plus an `exec` of the one
`device_verdict` `FunctionDef` — a pure function over two `set`s, no `tinygrad` import.

## Verdict, first

The pin is **not red because of `tinygrad/`, and not red because of a stale expectation.** The rule
that produced the red was a real oracle bug — it compared an **absence atom** against a **device name** —
and that rule **has already been fixed and committed** (`9f0164b6e`, 2026-10-18T21:30:30+03:00, an
ancestor of HEAD). The red you are reading lives in an **artifact that predates its own fix by 8m17s**
and is `.gitignore`d, so it can only be cleared by re-running.

**Classification: (c) a harness limitation, at origin** — a precondition in the census's own instrument,
not a defect in the reference tree and not an expectation that has drifted. **Plus, and separately, the
live red is a stale artifact.** Those are two different conditions and the second does not make the
first (b).

## 1. The pin, and the two selfchecks it is easy to confuse

There are **two** `# SELFCHECK` strings in this tree and only one is red:

| string | written by | today |
|---|---|---|
| `# SELFCHECK: OK` | `.agents/slop/graphcmp.py:2991` | **OK** — `D0-run-summary.txt:15` |
| `# ORACLE SELFCHECK: FAIL` | `.agents/slop/graphcmp-oracle.py:531` | **FAIL** — `D0-run-summary.txt:18` |

`checks/differ.py:293` pins the **second**:

```python
"conflations": "4 of 4", "oracle-selfcheck": "# ORACLE SELFCHECK: OK",
```

and `checks/differ.py:907` is what produces it:

```python
capture("D0-coverage-census.txt", ".agents/slop/graphcmp-oracle.py", stamp_rc=True)
```

The brief's claim that this pin sits **upstream of the corpus verdicts** is structurally true — the
census is a `D0` artifact — but it is worth stating what the corpus is doing without it, because it
bounds how urgent this is: `graphs-agree=33`, `graphs-disagree=0`, `byte-identical=33`, `selfcheck=# SELFCHECK:
OK`, and `graphs-refused=1` (`D0-run-summary.txt:5-15`). **33 of 33 comparable graphs already agree
byte-identically.** The 34th, `loop`, is REFUSED for its own independent reason. So this pin is not
holding up a red corpus; it is a red light on a green road.

## 2. The deciding code — pre-fix, verbatim (`5da7e7add`, the artifact's own producer)

```python
    if py["devs"] != bd["devs"]:
      bad.append(f"{g}: the two sides opened DIFFERENT devices -- py {sorted(py['devs'])} "
                 f"against bend {sorted(bd['devs'])} -- so this row's node/op/shape/atom "
                 f"counts are about two different graphs")
```

`bad` is the only failure channel the census has (`:531`):

```python
  print("# ORACLE SELFCHECK: " + ("OK" if not bad else "FAIL"))
  for b in bad:
    print("#   " + b)
```

`py["devs"]` / `bd["devs"]` is `graphcmp.py:2363`:

```python
def devnames(lines: list[str]) -> set[str]:
  ...
  for ln in lines:
    arg = unchunks(ln)[6]
    if arg.startswith("P("):
      out.add(split_top(arg[2:-1])[7])          # ParamArg's EIGHTH field, TEXT, verbatim
  return out
```

That eighth field is the `device`, and `graphcmp.py:731`'s `paramarg` writes it through `_carg(pa.device)`.
`_carg`'s first arm is `graphcmp.py:618-619`:

```python
  if x is None:
    return ATOMS["none"]
```

and `graphcmp.py:336` is `ATOMS = {"none": "N", ...}`. **So `device=None` prints as the letter `N`, into
a set the caller then reads as a set of device NAMES.** `pdev = {'N','sCPU'} != bdev = {'sCPU'}` — the
absence arrived where a device belonged, the `if` fired, and the census failed.

## 3. The failing line, verbatim (`runs/graphcmp/D/D0-coverage-census.txt:72`)

```
# ORACLE SELFCHECK: FAIL
#   loop: the two sides opened DIFFERENT devices -- py ['N', 'sCPU'] against bend ['sCPU'] -- so this row's node/op/shape/atom counts are about two different graphs
```

**One graph of 34, and one `bad` entry of the 1 recorded.** The census table itself already carries the
real diagnosis 51 lines earlier (`D0-coverage-census.txt:21`):

```
  loop       52/25  BAD   19 DNSXbcilrs      4      1  0/0  -  [PY-BEND OPs DIFFER: ['AND', 'BUFFER', 'CUSTOM_FUNCTION', 'FLOORDIV', 'MUL']]
```

## 4. Both sides of the first disagreement

| side | device set | where the extra token comes from |
|---|---|---|
| CPython | `['N', 'sCPU']` | `UOp.placeholder((1,), dtypes.u64, addrspace=AddrSpace.REG)` in `tinygrad/runtime/support/hcq2.py:66-70` — **no `device=` argument, so `None`, so `N`** |
| bend | `['sCPU']` | the fixture models `hcq_fence`'s loop body only; it does not model the `do_get_time_ms` body, so it never reaches a device-less PARAM |

The chain is readable end to end, with no `bend` involved:

```python
# tinygrad/runtime/support/hcq2.py:65-70
@uopfunc
def do_get_time_ms(ms:UOp) -> UOp:
  ts = UOp.placeholder((2,), dtypes.u64, addrspace=AddrSpace.REG)
  ts = ts.after(UOp.custom_function("clock_gettime", dtype=dtypes.i32).call(UOp.const(time.CLOCK_MONOTONIC, dtypes.i32), ts.index(0)))
  return ms.index(0).store(ts[0] * 1000 + ts[1] // 1000000).sink()
def get_time_ms(dep:UOp) -> UOp: return (ms:=UOp.placeholder((1,), dtypes.u64, addrspace=AddrSpace.REG)).after(do_get_time_ms(ms.after(dep)))[0]
```

**The corpus corroborates this without my having to trust my own reading.** `graphcmp.py:1241-1242`
records CPython's own census for `loop`:

```
CALL=4 BACKEDGE=1 LOAD=2 STORE=2 INDEX=7 RANGE=1 PARAM=6 BUFFER=3 AFTER=7
CONST=8 CUSTOM_FUNCTION=1 FLOORDIV=1 AND=1 ADD=2 MUL=2 CMPLT=2 NOOP=1 SINK=2
```

The five ops the artifact reports as `PY-BEND OPs DIFFER` are `AND, BUFFER, CUSTOM_FUNCTION, FLOORDIV,
MUL` — and those are **exactly the ops `do_get_time_ms` builds**: `clock_gettime` → `CUSTOM_FUNCTION`,
`ts[1] // 1000000` → `FLOORDIV`, `ts[0] * 1000` → `MUL`, the `.store(...)` → `BUFFER`, and the
`(done < target)` / `&` of the `hcq_fence` backedge → `AND`. The missing 27 rows and the missing `N` are
the same 27 rows. `graphcmp.py:1246` states the same fact: *"`graphcmp.bend`'s `g_loop` models
`hcq_fence`'s own loop body (25 rows, one `CALL`), while CPython's tree carries three more `@uopfunc`
bodies under three more `CALL`s."*

So the causal direction is the reverse of what the red sentence claimed. The red sentence said
**"two sides, two devices, therefore two graphs."** The code says **"one side, one device, fewer rows."**

## 5. What has already changed

`9f0164b6e` — *"census: the device precondition compared an ABSENCE against a device, and failed on both
pins"*, 2026-10-18T21:30:30+03:00, confirmed an ancestor of HEAD — replaced the `if` with a named rule
(`.agents/slop/graphcmp-oracle.py:181-205`):

```python
def device_verdict(py: set[str], bd: set[str]) -> tuple[str, str]:
  pdev, bdev = py - NODEV, bd - NODEV
  if pdev != bdev:
    return ("DIFFERENT-DEVICES", f"py {sorted(pdev)} against bend {sorted(bdev)}")
  if py != bd:
    return ("ONE-SIDE-DEVICE-LESS", f"py {sorted(py)} bend {sorted(bd)}")
  return ("AGREE", "")
```

and the call site (`:338-343`) now routes the middle answer to a **report**, not to `bad`:

```python
    why, detail = device_verdict(py["devs"], bd["devs"])
    if why == "DIFFERENT-DEVICES":
      bad.append(f"{g}: the two sides opened DIFFERENT devices -- {detail} -- so this row's "
                 f"node/op/shape/atom counts are about two different graphs")
    elif why == "ONE-SIDE-DEVICE-LESS":
      nodevised.append(f"{g} {detail}")
```

I traced the committed rule over the recorded inputs (`ast.parse` → `exec` of the one `FunctionDef`,
`NODEV = {"N"}`). **3 cases, 3 answers, and the fatal branch still bites:**

| input | pre-fix | now |
|---|---|---|
| `loop` py=`['N','sCPU']` bend=`['sCPU']` | `DIFFERENT-DEVICES` | **`ONE-SIDE-DEVICE-LESS`** |
| `sym` py=`['N','sCPU']` bend=`['N','sCPU']` | `AGREE` | `AGREE` |
| `sCPU` vs `sMETAL` | `DIFFERENT-DEVICES` | `DIFFERENT-DEVICES` |

`bad.append` sites: **14 before, 14 after**, and the only difference between the two versions is the
**text** of the one device message. No failure channel was added and none removed, so nothing new can
reach `bad` that did not already reach it.

## 6. Why the red is nonetheless still on disk

| event | time (UTC) |
|---|---|
| `D0-coverage-census.txt` written | `2026-10-18T21:22:13Z` (mtime) |
| `D0-run-summary.txt` written | `2026-10-18T21:22:18Z` |
| `.agents/slop/graphcmp-oracle.py` last modified | `2026-10-18T21:28:06Z` |
| fix committed `9f0164b6e` | `2026-10-18T18:30:30Z` (= `21:30:30+03:00`) |

**The artifact was produced by the pre-fix rule, 8m17s before that rule was committed.** And
`runs/` is `.gitignore`d — `.gitignore:262`, verified with `git check-ignore -v` — so
`git ls-files --error-unmatch` answers *did not match any file(s)* and
`git ls-files --others --exclude-standard -- runs/` answers **0**. **The artifact is untracked,
uncommittable, and regenerated only by re-running.** A green rule cannot reach this red; only a run can.

## 7. Fix and verification — stated, not performed

**Nothing needs fixing in the code.** The rule is fixed and committed. What is required is a **re-run of
`checks/differ.py run`**, which I did not and must not do. On that re-run, four things are checkable by
eye, in this order:

1. `runs/graphcmp/D/D0-coverage-census.txt` line 71 reads `# ORACLE SELFCHECK: OK`, and **the `#   loop:`
   line that follows it is gone** — replaced by a `# ONE SIDE'S DEVICE-LESS ROWS ONLY (NOT A DEVICE
   DISAGREEMENT, NOT A CENSUS FAILURE): 1 of 34 graphs -- loop py ['N', 'sCPU'] bend ['sCPU']`
   (`.agents/slop/graphcmp-oracle.py:364-366`). **`ONE-SIDE-DEVICE-LESS` is the success shape here; its
   absence would be the surprise.**
2. `D0-run-summary.txt:19` reads `census-rc=rc=0`, which flips `unhealthy()`'s `oracle-selfcheck` and
   `census-rc` together.
3. **The census table's 34 rows must be byte-unchanged.** `tot_nodes`, `tal`, `graphs_of`, `tot_comm` and
   `tot_sym` read the **py** side only (`:298-302`), and the two unions the census does take are
   `tot_ops`/`tot_atoms` — which is why a new line appearing is not a new denominator. If `# TOTAL: 34
   graphs, 482 nodes per side, 68 distinct ops` moves, the reclassification changed a count and the
   fix is not the fix.
4. `graphs-agree=33 / graphs-refused=1 / byte-identical=33` must not move. `loop` stays REFUSED by
   `_dispatch` for the reason it was always refused — **25 of 52 nodes modelled** — and that verdict is
   unaffected by anything here.

**The instrument that already exists for step 1** is `gates/census-dev-gate.py`, which imports
`device_verdict` **by path** (`:73`) rather than copying the rule, and whose lane 3 exists precisely so
that "a gate that only ever sees the case that now passes is a gate that measured the fix, not the
rule":

```python
v = O.device_verdict({"sCPU"}, {"sMETAL"})
report("3 device_verdict STILL returns DIFFERENT-DEVICES on a device mismatch (the fatal "
       "branch bites)", v[0] == "DIFFERENT-DEVICES", ...)
```

**I did not run it** (forbidden). Its lanes 6 and 7 `sys.exit(3)` REFUSED when
`runs/graphcmp/D/D0-coverage-census.txt` is absent, and both currently read the **stale** artifact — so
until the re-run lands, this gate is measuring the wrong vintage of its own input, and its result
should not be quoted as evidence either way.

## 8. What I could **not** establish, stated as REFUSED rather than guessed

- **Whether a fresh run is green.** My claim is an inference with a visible denominator: the artifact
  records **1 `bad` entry**, that entry is the device one, and the set of `bad.append` sites is
  **unchanged at 14**. That is strong, and it is still an inference about an unperformed run.
- **Whether `bad` gains an entry from a source that did not fire today** — e.g. a future graph whose
  bend side adds a device name, which is precisely what `census-dev-gate.py` lanes 6 and 7 measure.
- **`D0-selfcheck.txt` after the re-run.** It is a different code path (`graphcmp.py:2991`) and is green
  today; nothing in the fix touches it, but I did not re-run it.
- **Byte-identity across the re-run.** The new `# ONE SIDE'S DEVICE-LESS ROWS ONLY` line changes the
  census artifact's bytes. `repro` compares two runs of the same tree, so this should be inert — **I
  did not verify that**, and `differ.py` is the only thing that can.
- I made **no claim about `tinygrad/`'s correctness.** Nothing read here suggests a defect in it; the
  `N` is upstream's own `UOp.placeholder` with no `device=`, and that is correct code.

## 9. Bottom line

One graph of 34 (`loop`) put an **absence atom** (`N`) where the census's precondition expected a
**device name**, so a row-count asymmetry — the bend fixture models 25 of CPython's 52 rows, because it
models `hcq_fence`'s loop body and not `do_get_time_ms`'s — was reported as a **device disagreement**.
That was a bug in the census, not in `tinygrad/`, and it is **already fixed and committed**. The pin is
red only because `runs/` is `.gitignore`d and the artifact on disk is older than the rule that
superseded it. **One re-run is the entire fix.** The claim "33 of 33 comparable graphs already agree
byte-identically" is what makes that the right amount of urgency.