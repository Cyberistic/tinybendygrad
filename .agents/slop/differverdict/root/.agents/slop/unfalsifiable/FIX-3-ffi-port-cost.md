# Fix 3 — `ffi-port-cost.py`: the `X/X` coverage and the "derivable" label

Harness: `ffi-port-cost-plant.py` in this directory. Transcript:
`ffi-port-cost-plant-RESULTS.txt`. Pre-fix control: `pre-fix-ffi-port-cost.py`,
sha256 `d0a5be05d3e20227…`.

## What the committed tool printed

```
denominator   : 324 symbols exported by the binary
coverage      : 324/324 = 100.0%
mechanically derivable : 307/324 (95%) have no absent-type blocker
need a layout decision : 203 by-value struct or unresolvable type
BLOCKED                : 17
```

Reproduced byte-for-byte from the live tree before touching anything.

## FINDING A — `coverage: 324/324` was `N/N`, and no binary was read

`ffi-port-cost.py:496` (pre-fix) set, on the `--pybind` path,

```python
denom = len({f.name for f in fns})     # and report() printed len(uniq)/denom
```

`uniq` is `sorted(set(f.name for f in fns))` — the same set. So the line labelled
*"symbols exported by the binary"* exported nothing, and the guard at `:423`
(`if len(uniq) > denom` → *"the header and the binary disagree"*) was **unreachable**,
because the two sides were the same set by construction.

### Where the new denominator comes from, and why it is not the numerator

`nm -gU` on **the shared library the bindings bind to**:
`/Library/Developer/CommandLineTools/usr/lib/libclang.dylib`. Measured: **552**
exported symbols, all `clang_*`.

That is a different artifact, read by a different tool, answering a different question:

| | numerator | old denominator | new denominator |
|---|---|---|---|
| source | `tinygrad/runtime/autogen/libclang.py`, `@dll.bind` decorator tuples | *the same file* | the compiled `.dylib`, via `nm` |
| what it lists | declarations a binding *chooses* to expose | — | symbols the toolchain *exports* |
| read by | `parse_pybind` | `len(...)` over the same parse | `symbols_from_dylib` |

A declaration can exist without being exported, and an export can exist without a
declaration, and both directions now move the number. Measured, and they do:

- **4 declared names are not exported**: `clang_getOffsetOfBase`,
  `clang_getTypePrettyPrinted`, `clang_isBeforeInTranslationUnit`,
  `clang_visitCXXBaseClasses`;
- **232 exported symbols have no declaration** (`clang_BlockCommandComment_*`,
  `clang_CXRewriter_*`, …).

So the honest coverage is **320/552 = 58.0%** of the binary's exported symbols, and the
honest reverse is **320/324 = 98.8%** of declarations resolving to an export. Both are
now printed; neither can be 100% by construction. The old 100.0% was not a measurement
at all.

### PLANT A — delete one declaration (`clang_createIndex`)

| | PRE-FIX | POST-FIX |
|---|---|---|
| entry points | 323 | 323 |
| denominator | **323** (moved with the numerator) | **552** (held) |
| coverage | **323/323 = 100.0%** | **319/552 = 57.8%** |
| resolve rate | (not reported) | 319/323 = 98.8% |
| exported but not declared | (not reported) | **233** (was 232) |
| mechanical outright | — | **103** (was 104) |

**Coverage stayed at 100.0% while one of libclang's 324 declarations was gone.** Post-fix
the same deletion moves coverage *and* the complement, because the denominator is not a
function of the numerator.

### DISARM A — append a comment

Every number identical to the live baseline (`identical to the live baseline: True`).

### Fail-safe — `--dylib /nonexistent/...`

```
denominator   : UNAVAILABLE -- no library to read. Pass --dylib PATH,
coverage      : NOT MEASURABLE. The declaration count is 324, and 324/324 would be a
                SELF-COMPARISON, so no percentage is printed rather
                than one that cannot go red.
```

`any coverage PERCENTAGE printed: False` — asserted by the harness. **There is no
fallback onto the numerator.** A tool that cannot find an independent population says
so and prints no percentage; that is the only fail-safe here, because the alternative is
the tautology returning the first time `nm` is unavailable.

## FINDING B — "mechanically derivable" contradicted itself two thirds of the way

`mechanical = len(uniq) - len({f.name for f in blocked})` — a not-count of blockers
wearing the word *derivable*. Nothing was derived. `max_class` returns one value and
tests `blocked` first, so no function is both, and all **203** layout-decision functions
sit inside the 307 — while the same run labels them *"needs one layout convention"* and
*"per-struct decision, not mechanical"*.

Measured before editing anything, so the partition is a finding and not a construction:

```
total 324 | blocked 17 | structish 203 | OVERLAP 0 | union 220 | mechanical outright 104
17 + 203 + 104 = 324
no-blocker 307 = 104 + 203      <- so 203/307 = 66% are called "not mechanical"
```

The three buckets are now printed as a partition and **asserted** disjoint and
exhaustive, so the labels cannot drift from the counts again:

```
mechanical outright     : 104    no blocker and no layout decision
need a layout decision  : 203    by-value struct or unresolvable named type
blocked                 : 17     no Bend type, or past the 2^51-1 Nat window
                       : -------
total                   : 324    the three rows above are disjoint and sum to it
no absent-type blocker  : 307    = mechanical outright + need a layout decision. NOT
                                'derivable': the 203 in the middle row are each one
                                layout convention away.
```

The 307 is **kept**, because it is a true count of declarations avoiding three specific
C types — but it now sits under a name that says so, and the word `derivable` is gone
from the output entirely.

### PLANT B — one `c_int64` in a not-blocked declaration's decorator

`blocked 17 → 18`, `mechanical outright 104 → 103`, `no absent-type blocker 307 → 306`.
The BLOCKED channel is still can-fail after the edit, which is the regression guard that
matters: the partition is a re-derivation of the same data, and a plant that stopped
moving would mean it had become a second constant.

### DISARM B — an int64 *argument* on an already-blocked declaration

Nothing moved, `identical to the live baseline: True`. This is the audit's **failed
plant #1** (`clang_Type_getSizeOf` is already blocked for its `c_int64` return, so an
`int64` argument cannot add a blocker — the blocker set is a *set*). Kept as a control
so the next agent does not re-attempt it and read the zero as a fix.

### Two more of the audit's failed plants, kept as controls by construction

Both are inert for reasons now recorded in the harness's header, so neither is
re-attempted: `"(ctypes.c_int64, "` inserted after `(` adds a **bare parameter with no
annotation**, and `parse_pybind` reads the decorator's tuple, consulting the annotation
only as a fallback.

## Also changed

- `.agents/slop/ffi-experiment/libclang-cost.txt` — the committed artifact still carried
  `coverage : 324/324 = 100.0%` and `mechanically derivable : 307/324`. **Regenerated**,
  because a superseded number that stays committed stays quotable (audit 05's lesson).
  The diff is exactly the two fixed blocks and nothing else.
- `--dylib PATH` added; with no argument the tool searches six known locations and, if
  none exists, prints `NOT MEASURABLE` rather than a percentage.