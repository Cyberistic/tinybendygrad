# `census-rc=rc=1` — static diagnosis

**HEAD `cea5fc2ac5d3`** (`e92adbb5cc10` at 18:49:28Z, moved mid-analysis; the move touched only
`gates/lane-census.py`, and every citation below was re-verified after it) · **read 2026-10-18T18:51:36Z**.
Static only: no `bend`, no `graphcmp*`, no `gates/`, no `differ.py` execution, no corpus loop.
Artifacts: `state.rows` (34 rows, TAB), `collect.py` (its generator — the rows are read, not typed).

## 1. How `census-rc` is produced

Four hops, and **no fallback anywhere in them**:

```
graphcmp-oracle.py:534   return 0 if not bad else 1
graphcmp-oracle.py:538   sys.exit(main())
checks/differ.py:458     rc = subprocess.run([PY, script], cwd=ROOT, env=ENV, stdout=f, stderr=f).returncode
checks/differ.py:459-461 if stamp_rc: f.write(b"rc=%d\n" % rc)
checks/differ.py:907     capture("D0-coverage-census.txt", ".agents/slop/graphcmp-oracle.py", stamp_rc=True)
checks/differ.py:979     f"census-rc={last_line('D0-coverage-census.txt')}"
checks/differ.py:1267-8  def last_line(out): return text(out).rstrip("\n").split("\n")[-1]
```

The whole of `capture()`:

```python
def capture(out, script, stamp_rc=False):                    # :451
    """The oracle/probe steps: BOTH streams are the artifact, so they are merged into it.
    `stamp_rc` is the census's, because a step whose output is a TABLE must say whether the
    table is finished ..."""
    with (D / out).open("wb") as f:
        rc = subprocess.run([PY, script], cwd=ROOT, env=ENV, stdout=f, stderr=f).returncode
    if stamp_rc:                                             # :459
        with (D / out).open("ab") as f:
            f.write(b"rc=%d\n" % rc)                         # :461
```

**The recorded `rc=1` is the oracle's own exit code, carried by the stamp.** It is not a
fallback and not a harness verdict. The artifact's last line is literally `rc=1`, and the
oracle sets it from one line: `return 0 if not bad else 1`. There is no default arm — an
unstamped artifact would yield `census-rc=` (empty), not `rc=1`, and a *missing* artifact would
raise `FileNotFoundError` inside `text()`. `unhealthy()` (`:1347`) then names it:
`census-rc=rc=1 (expected rc=0)`.

## 2. Why it is 1

`runs/graphcmp/D/D0-coverage-census.txt`, last three lines:

```
# ORACLE SELFCHECK: FAIL
#   loop: the two sides opened DIFFERENT devices -- py ['N', 'sCPU'] against bend ['sCPU'] -- so this row's node/op/shape/atom counts are about two different graphs
rc=1
```

**No Traceback. No `IndexError`. No REFUSED line inside this artifact.** The lane ran to
completion and then *asserted* itself false. `bad` holds exactly **1** member — the `for b in
bad: print("#   " + b)` loop at `graphcmp-oracle.py:532-533` emitted exactly one line.

> A count I got wrong first and corrected: scanning the file for every `#   ` prefix returns
> **18**, because the oracle prints 17 lines of its own DEFECT-20 commentary in that shape
> (`:43-56`). `bad` is only what the loop emits, so the denominator is 1, not 18.

`N` is `ATOMS["none"]` — the atom for Python `None`, which `devnames()` returns because
ParamArg's eighth field prints the absence when `device is None`. An **absence** was compared
against a **device name**. `loop` is where the two come apart: CPython's `@uopfunc` bodies
(`get_time_ms`/`do_get_time_ms`, `hcq2.py:65-78`) put four addrspace-REG temps in the graph and
the bend fixture models `hcq_fence`'s loop body without them.

Independent corroboration from a **different lane of the same run** — `D1-graph-loop.txt`,
written by `run()` not `capture()`:

```
# rows py=52 bend=25 ... device tokens only on py=['N'] only on bend=[]
# PARTIAL FIXTURE: the bend side models 25 of the 52 nodes CPython's graph has (27 unmodelled) ...
# devices py=['N', 'sCPU'] bend=['sCPU'] -- NOT WELL-POSED, and this is NOT a verdict (exit 2) ...
rc=2
```

Same device sets, same run, `rc=2` and counted as `graphs-refused=1`.

### This is the SAME failure as `oracle-selfcheck`, not an independent one

Both pins read **the same artifact**:

```python
checks/differ.py:978   f"oracle-selfcheck={grep_line('D0-coverage-census.txt', 'ORACLE SELFCHECK')}",
checks/differ.py:979   f"census-rc={last_line('D0-coverage-census.txt')}",
```

One oracle process, one self-check, one `bad` list, two spellings. The other unit diagnosing
`oracle-selfcheck` and this pin is diagnosing **one** defect, and commit `9f0164b6e` says so in
its own subject line: *"the device precondition compared an ABSENCE against a device, and
failed on **both pins**"* / *"`oracle-selfcheck=FAIL` and `census-rc=rc=1` are ONE cause."*

## 3. The `stamp_rc` claim: **REFUTED as cited, TRUE as substance**

| claim | measured at `cea5fc2ac5d3` |
|---|---|
| `:684` passes `stamp_rc=True` | **REFUTED.** `:684` is `one_line`'s body: `return (D / out).read_bytes().count(b"\n") <= 1` |
| `:691` omits it | **REFUTED.** `:691` is a **blank line** inside `cmd_run`; the census call is `:907` |
| a crashed lane can emit no `rc=` at all | **TRUE for 2 of 3 `capture()` call sites, FALSE for the census** |

The census passes `stamp_rc=True` at `:907`. The two that omit it are **`:910`**
(`D8b-cpython-dbg1-reachability`) and **`:914`** (`D0-ops-probe`). So:

- **the census** — a crash still writes `rc=1` (or `134`, or `-9`); `subprocess.run` returns a
  code for every exit. It cannot go silent.
- **`D8b` / `D0-ops-probe`** — a crash writes **no** `rc=` line at all; `last_line()` would then
  return a traceback's last line, or `""`. That is the DEAD-lane shape: a row that measured
  nothing wearing the name of a row that measured something.

Neither recorded `rc=1` here, and no lane crashed. **The stamping path is not what reddened this
pin.** One structural hazard is real but unexercised: `capture()` merges `stdout=f, stderr=f`, so
it writes **no `.err`** (confirmed: `D0-coverage-census.txt.err` does not exist) — a crash's
traceback would interleave into the census table.

## 4. Classification: **(c) cascading from `oracle-selfcheck`** — in fact *identical* to it

Evidence:

1. **One artifact, two rows.** `:978` and `:979` both read `D0-coverage-census.txt`.
2. **One cause, one `bad` entry.** Exactly one line after `SELFCHECK: FAIL`.
3. **Mechanically identical.** `bad` non-empty ⇒ `:534` returns 1 ⇒ `:461` stamps `rc=1` ⇒
   `:979` reads it. `oracle-selfcheck` reads the *same* `bad` list at `:531`.
4. **Corroborated independently** by `D1-graph-loop.txt` (`rc=2`, same device sets).
5. **Named by the fix's own commit subject**: *"failed on both pins"*.

**The pin is STALE, and the cause is already fixed in HEAD.** Timeline:

| when | what |
|---|---|
| `21:22:13Z` | `D0-coverage-census.txt` written — by the **pre-fix** oracle; `rc=1` |
| `21:22:18Z` | `D0-run-summary.txt` written; `oracle-selfcheck=FAIL`, `census-rc=rc=1` |
| `21:28:06Z` | `graphcmp-oracle.py` mtime — `NODEV` / `device_verdict` land |
| `21:30:30Z` | `9f0164b6e` commits it; `git diff HEAD` on that file is now **empty** |

The pre-fix code, from `git diff` (`-` side), is the exact string in the artifact:

```python
    if py["devs"] != bd["devs"]:
      bad.append(f"{g}: the two sides opened DIFFERENT devices -- py {sorted(py['devs'])} "
                 f"against bend {sorted(bd['devs'])} -- so this row's node/op/shape/atom "
                 f"counts are about two different graphs")
```

The current code cannot produce that line for `loop`. `device_verdict` (`:181-205`) subtracts
`NODEV = frozenset({G.ATOMS["none"]})` = `{'N'}`:

```
pdev = {'N','sCPU'} - {'N'} = {'sCPU'}
bdev = {'sCPU'} - {'N'}     = {'sCPU'}      → equal, so NOT DIFFERENT-DEVICES
py != bd                    → ONE-SIDE-DEVICE-LESS  → `nodevised` (:342-343), NOT `bad`
```

So `loop` routes to the reported-not-fatal branch, `bad` empties, `:531` prints `OK`, `:534`
returns 0, and the stamp becomes `rc=0`.

**Not (a) a genuine oracle failure** — the port was never asked a census question it got wrong.
**Not (b) a stamping defect** — the census stamps, and no fallback exists to blame.
**(d) UNKNOWN, deliberately:** whether a re-run *reproduces* `rc=0` is not established here. The
inference rests on the artifact's own record that `loop` was the only `bad` member and on
`D1-graph-loop.txt`'s device sets, both from the 21:22 run. It is not a measurement of a new run.

### Two more pins are red, from a different mechanism

`4 FAIL of 17` — `graphs-agree=33` (expected 34) and `byte-identical=33` (expected 34). Both
are `34 − graphs-refused(1)`: `loop` is **REFUSED** (`rc=2`, PARTIAL FIXTURE), not
disagreeing. That is one of the five verdicts doing its job, and it is a *different* mechanism
from the census self-check — the census failure was a false alarm about a refusal that was
correct. Fixing the oracle does not move these two; they move when the `loop` bend fixture
models the other 27 nodes, or when the pin is re-taken deliberately.

Also recorded: `9f0164b6e`'s own note cites `.agents/slop/graphcmp-oracle.py` as
`SUBSTRATE_INPUTS[4]`; at `checks/differ.py:1174-1177` it is index **5**. Harmless to the
conclusion — it *is* a substrate input, so that commit moved `substrate_digest()`.

## 5. What fixing it requires, and what would verify it — without running it here

**Nothing in `checks/differ.py` needs fixing for `census-rc`.** The oracle fix is already
committed (`9f0164b6e`), and `differ.py`'s worktree equals HEAD. Both pins were left unchanged
and now *agree* — no pin deleted, re-pinned, or row removed to go green.

What is required is a **re-take**, not an edit:

1. **`checks/differ.py run`** (nothing else compiling, under the sum-precondition for `bend`).
   This rewrites `D0-coverage-census.txt` and `D0-run-summary.txt`. Expect
   `oracle-selfcheck=# ORACLE SELFCHECK: OK`, `census-rc=rc=0`, plus a new
   `# ONE SIDE'S DEVICE-LESS ROWS ONLY …` row and `loop` off `bad`.
2. **Expect `substrate-start != substrate-end`** on that first run. `graphcmp-oracle.py` is a
   `SUBSTRATE_INPUTS` member and `9f0164b6e` moved it; `9f0164b6e` says this run
   "is required and is NOT yet taken". A first run that reports a moved digest is the *expected*
   reading, not a new failure.
3. **`graphs-agree` / `byte-identical` stay red** after that re-take. They are pinned to 34 and
   `loop` is REFUSED. Do not re-pin them to 33 to go green — that would trade a true REFUSED for
   a silent hole. The honest remedy is the `loop` bend fixture, or a deliberate re-pin with the
   refusal recorded.

Verification paths, cheapest first:

- **`gates/census-dev-gate.py`** — asserts `device_verdict` with **no `bend`** (lane 3 feeds a
  `CPU`/`METAL` mismatch and still requires `DIFFERENT-DEVICES`, so the refinement is not merely
  permissive; `9f0164b6e` reports 8 of 8). This is the only instrument that can confirm the
  rule without compiling anything. *(I did not run it: `gates/` is out of grant.)*
- **`checks/graphcmp-census-audit.py --all`** — PLANT 2 (`emit_bend` 0 rows) and PLANT 3 (a bend
  op not in `Ops`) must still drive `SELFCHECK FAIL (rc=1)`, both through the *fatal* branch.
  A refinement that cannot reject is not a refinement.
- **`checks/differ.py run`** then read `unhealthy()` by content — the check is that
  `census-rc` and `oracle-selfcheck` leave the FAIL list and the other two do not.
- **`checks/corpus-figure.py`** prints `RUN HEALTH : OK` only when all 17 pins are green, so it
  will stay red until the `loop` fixture question is answered separately.