# NVROWS — are 313 of `nvdev.bend`'s 374 gate rows dead, and if so, was it damage or rot?

Unit brief: measure live `tinybendygrad/runtime/support/nv/nvdev.bend`. Answer:
rows alive vs dead out of 374; `file:line` for the mechanism; live defect /
pre-existing rot / intended shape; does live == origin in this respect;
plant + disarm (disarm first).

Rule prefix: **NVROWS-01..**. Nothing committed. Nothing planted in the live tree
(`md5 -q tinybendygrad/runtime/support/nv/nvdev.bend` = `09eec1e5bd8bf2355f289dc242ded12c`,
unchanged from the start of this unit).

---

## 1. THE COUNT, WITH ITS DENOMINATOR

| | |
|---|---|
| row call sites in the live source | **374** |
| **ALIVE** (the site executes, a consumer reads its value) | **368** |
| **DEAD** (never executes) | **6** |
| row *lines* the file prints at runtime | 811 (from 368 sites — 52 sites are in loops) |
| distinct `name=` rows | 799 |

**The 313 figure is TRUE OF THE STRAY AND FALSE OF THE LIVE FILE.** In the preserved
damage copy `IP.{,u,s}row(` survives on **61** lines, so 374 − 61 = 313 removed —
the triage's arithmetic is exact. But that copy **does not compile**
(`bend` rc 1), so it is not a silent wrong answer; it is a loud one. The live
file has 313 of its rows **alive**.

## 2. `file:line` FOR WHAT MAKES THEM DEAD

**`tinybendygrad/runtime/support/nv/nvdev.bend:1272` — `def t_const() -> IO(Unit)`.**

The 6 dead sites are its entire body:

| site | line | row |
|---|---|---|
| S070 | `nvdev.bend:1274` | `nv_pte_kind` |
| S071 | `nvdev.bend:1275` | `nv_pte_aperture_0` |
| S072 | `nvdev.bend:1276` | `nv_pte_aperture_1` |
| S073 | `nvdev.bend:1277` | `nv_sf_addrkey_2000` |
| S074 | `nvdev.bend:1278` | `nv_sf_addrkey_2000_v2` |
| S075 | `nvdev.bend:1279` | `nv_sf_addrkey_2000_v3` |

**`t_const` has ZERO call sites.** `grep -n 't_const' nvdev.bend` returns exactly
one line — the `def`. `main` (`nvdev.bend:2331-2345`) calls 12 row groups
(`t_regs t_mmu t_mask t_encode t_update t_chip t_mmu_tables t_pte t_setfield
t_boot t_trace t_flds_b42`) and `t_const` is not among them. Every other `t_*`
def has ≥ 1 call site; `t_const` has 0.

**`Bool.pick` is NOT the mechanism, and this is measured, not assumed.** The brief
names `Bool.pick` as the suspect because "`Bool.pick` cannot plant a dead arm". That
is correct and it is why the suspect is wrong here: the 6 rows are inside a
`do IO<Unit>:` block whose enclosing `def` is never *entered*. No arm is reached and
no arm is skipped — control never gets inside `t_const` at all. A construct that
cannot plant a dead arm did not plant this; an omission did. `Bool.pick` appears
**45 times** in the live file, all in value-returning positions.

## 3. LIVE DEFECT, PRE-EXISTING ROT, OR INTENDED SHAPE

**PRE-EXISTING ROT — and it is a real defect, so it is a bug report, not a shrug.**

Evidence, three independent legs:

1. **It is old.** All three commits that touch this file were checked for
   `t_const`:
   | commit | rowsites | `t_const` defs | `t_const` call sites | `main`'s groups |
   |---|---|---|---|---|
   | `c00db572e` (the port) | 342 | 1 | **1 (= the def line)** | 11 |
   | `b8897fd48` | 368 | 1 | **1** | 12 |
   | `fde0fc1a8` (live) | 374 | 1 | **1** | 12 |

   `t_const` sits at **line 1272 in all three**. It has never been called.
2. **It is not declared.** Contrast `nv.pow_shifts` at `nvdev.bend:2329`, which the
   file explicitly annotates: *"it exists ONLY so the mutation 'drop the reversal'
   has a real alternative to swap in; **it has no caller, which is stated here
   rather than left to be discovered**."* `t_const` has no such note. The file
   knows how to say "this is intentionally dead" and did not say it here.
3. **Every instrument this project owns is blind to it, by construction.** A dead
   site emits nothing, so it costs **0 duplicate measurements** — the exact finding
   recorded in `.agents/slop/nvdup/nvdup-deadarm.txt` for `nv-oracle.py`, whose
   census reads `DEAD SITES=0`. Measured on this file:
   - `nv_nvdev_gate.py` → **`GATE PASS`** (558 rows compared, 0 disagreements), rc 0
   - `bend --check-only` / plain run → **rc 0**
   - row count 811 → **unchanged** by the 6 dead rows

   So the file is green, and green here means "6 of 374 rows were never run".

## 4. DO LIVE AND ORIGIN DIFFER IN THIS RESPECT

**No. Verified, not assumed.**

```
cmp .agents/slop/strays/origin/.../nvdev.bend tinybendygrad/.../nvdev.bend  -> IDENTICAL
md5 -q  both -> 09eec1e5bd8bf2355f289dc242ded12c
```
The census run against each gives the **same verdict, member for member**:
`374 sites / 368 executed / 6 dead / rc 0 / OUTPUT-NEUTRAL True`, dead at the same
six lines. (`ip.bend` in `strays/origin/` is also byte-identical to live,
`65ef5e0524b74f00c3b15925858cae71`, so the sandbox is a faithful tree.)

## 5. THE DISARM, BUILT FIRST

`.agents/slop/nvrows/nvrows-deadrow-gate.py`

Bend has no `sys.settrace` and no reflection, so the Bend analogue of a line tracer
is: **give every call site a unique row name, then look for that name in stdout. A
site that runs is seen; a site that does not run is absent.** That counts
*absence*, which is the only thing that can see this defect. It is the same
technique as `.agents/slop/nvdup/nvdup-deadarm.py` (a SITE census, not a LINE
census) for the same stated reason.

- Selector: `IP\.(?:u|s)?row\(`; tag `Snnn:` prefixed to the **name** argument only.
- **Sandbox is mandatory, not tidiness.** The **import closure** is mirrored with
  its package-relative layout. Two resolutions are needed and both are real:
  `import ./ip.bend` is file-relative; `import Base` (`ip.bend:371`) is
  **package-root**-relative. Getting this wrong produced
  `no such file: <tmp>/helpers.bend` and an INCONCLUSIVE verdict on a file that is
  fine — the 22-phantom-blind-spot trap, met again and named.
- **A file that does not run is INCONCLUSIVE, never CLEAN.** rc 2, distinct from
  both the pass and the fail code.
- **The disarm is proved output-neutral on every run**: the instrumented stdout
  with the tag *stripped* is compared line-for-line against the untagged baseline.
  `DISARM OUTPUT-NEUTRAL: True` in every cell below. Two of my own reds were reds
  about the instrument and are recorded in NVROWS-04/05, not papered over.

### THE MATRIX — full output in `nvrows/census-MATRIX.txt`

| cell | sites | printed | executed | dead | rc | neutral | what it proves |
|---|---|---|---|---|---|---|---|
| **LIVE** | 374 | 811 | **368** | **6** | 0 | T | the answer |
| `ORPHAN` | 377 | **811** | 368 | **9** | 0 | T | **catches the silent class**: +3 dead rows, `bend` rc 0, printed count *unchanged*, `nv_nvdev_gate.py` would still pass |
| `SELF` | **373** | 810 | 367 | 6 | 0 | T | **the disarm's own blind spot, measured**: one live row routed through `IP.emit` stops matching the textual selector. The census silently loses a site. Same shape as `nvdup-deadarm.py`'s `longhand` cell |
| `REVIVE` | 374 | **817** | **374** | **0** | 0 | T | **the rows come back**, on one added line |
| `STRIP` | 0 | 0 | — | — | **1** | — | a faithful `IP.{,u,s}row(`→`String.concat(` does **not** compile: the real damage was COLD, not silent |
| ORIGIN copy | 374 | 811 | 368 | 6 | 0 | T | live == origin in this respect |
| STRAY (damage) | **61** | 0 | — | — | **1** | — | 374 − 61 = **313**; the triage's arithmetic is exact, and the file does not build |

**The plant:** `ORPHAN` — one new `t_*` group of 3 rows, defined and never called.
That is the *smallest* live defect of this class, and it is what a later agent
would actually produce by omission. It is caught; the same omission in the live
file was not, because nothing ran a census.

**The disarm moved nothing** on the LIVE cell: 811 printed rows before and after,
and the stripped instrumented stdout is byte-identical to the baseline.

## 6. CAN THE 6 ROWS COME BACK — AND SHOULD THEY

**They can, on one line** (`REVIVE` proves it: 374/374, 817 printed, CLEAN):

```bend
# nvdev.bend, in main()'s do-block, next to the other 12:
    +m : Unit <- t_const()
```

Values they print, checked against CPython **by calling it** (`nvdev.py:40`,
`kind=6`, `aperture=2 if aspace is AddrSpace.SYS else 0`):

| row | port | upstream says |
|---|---|---|
| `nv_pte_kind` | 6 | `kind=6` ✓ |
| `nv_pte_aperture_1` | 2 | `aspace is AddrSpace.SYS` → 2 ✓ |
| `nv_pte_aperture_0` | 0 | `AddrSpace.PHYS` → 0 ✓ |

**Two caveats that must travel with the fix, or the fix buys 4 measurements, not 6:**

1. **The oracle has no counterpart for any of the 6.** `nv_nvdev_oracle.py` emits
   2176 rows and **0** of these names. Revived, they land in the gate's
   *"PORT ROWS WITH NO ORACLE COUNTERPART"* bucket — they print and nothing checks
   them. So **wiring `t_const` is necessary and not sufficient**: the expectations
   must be added to the oracle, or 3 of the 6 are unverified transcriptions.
2. **Two of the six are the same measurement.** `nv_sf_addrkey_2000` and
   `nv_sf_addrkey_2000_v3` are both the literal call `nv.pte_addrkey(3, 0)` —
   identical rows with different names. That is `agent-core.md`'s "a row that
   encodes a bug / a test that cannot fail", in the making. Upstream `nvdev.py:45`
   admits four keys (`address`, `address_small`, `address_sys`,
   `address_small_sys`); the file probes 2, and one of the 2 twice.

**Verdict on the class: pre-existing rot, worth a one-line fix plus three oracle
rows plus one row deleted. It is not the triage's damage and it was not caused by
the triage.** Filed, not fixed — the brief forbids planting in the live tree.

## 7. A SECOND DEAD DEF IN THE SAME FILE, REPORTED NOT FIXED

`nvdev.bend:1770` — `def emit(xs: List<&2, String>) -> IO(Unit)`. Never called
(`grep -n '\bemit('` finds 10 hits: 9 are `IP.Tr.emit`, this is the 10th), **and
not callable**: planting a call to bare `emit(...)` gives

```
expected : a filled definition (an unfilled law is a dead claim: live code cannot use it)
observed : emit
```

so the name resolves to an unfilled Bend law, not to the local def. `nvdev.bend`'s
own comment at `:1318` describes `emit` as the printer every `t_*` group is
"built by `go` folds" for — and no group uses it. **A def that exists, is never
called, and cannot be called.** Same class, one file over.

## 8. WHAT A LATER UNIT INHERITS IF I DO NOTHING

- **A green file whose gate is 6 rows short of its source**, with `GATE PASS`,
  `bend` rc 0, and 811 printed rows — and **no instrument in this tree that can
  see it**. That is the dangerous inheritance: not a red to fix but a baseline to
  build on.
- **A precedent.** `nv.pow_shifts` at `:2329` teaches that uncalled defs are fine
  here when annotated. `t_const` is an *unannotated* one, and the annotation is
  the only thing that distinguishes intent from omission. Every future `t_*` group
  can be added without being called and inherit the same immunity.
- **A false citation, if this report's own numbers are quoted later without the
  denominator.** "313 dead rows" is true of a file that does not compile and false
  of the file in the tree. Both numbers, always.
- **The instrument to stop it:** `.agents/slop/nvrows/nvrows-deadrow-gate.py`, rc 0
  on a clean file, rc 1 on this one, **output-neutral by construction**, and with
  its own blind spot (`SELF`) printed rather than promised.

## FILES I WROTE (all under `.agents/slop/nvrows/`, nothing committed)

| file | what |
|---|---|
| `nvrows-deadrow-gate.py` | the disarm: sentinel census, sandbox, plants, neutrality proof |
| `census-MATRIX.txt` | full output, all 7 cells |
| `census-LIVE.txt` | the live verdict alone |
| `NOTES.md` | this file |

Live tree untouched. `strays/` read-only and unread for anything but evidence.