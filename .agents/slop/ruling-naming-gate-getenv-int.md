# RULING: `helpers.py :: getenv` `_int` is QUALIFIED — recorded in the LEDGER, not in the QUALIFIED tally

2026-10-03, `.agents/slop/`. **The naming gate reads PASS again.** No `.bend` file was
touched.

## WHAT UPSTREAM ACTUALLY SAYS (read, not paraphrased)

`tinygrad/helpers.py:156-163`:

```
156: @functools.cache
157: def to_function_name(s:str): ...
158: @overload
159: def getenv(key:str) -> int: ...
160: @overload
161: def getenv(key:str, default:T) -> T: ...
162: @functools.cache
163: def getenv(key:str, default:Any=0): return type(default)(os.getenv(key, default))
```

ONE binding, `getenv`, which is simultaneously **overloaded** (two `@overload` stubs) and
**generic** (`default:T -> T`, coerced by `type(default)(...)`). `helpers.bend` splits it
by return type because Bend has no overloading:

```
132: def getenv_str.go(v: ..., d: String) -> String:
137: def getenv_str(k: String, d: String) -> IO(String):
288: def getenv_int.go(v: ..., d: U32) -> U32:
293: def getenv_int(k: String, d: U32) -> IO(U32):
```

The port's own comment at `helpers.bend:143` opens "`getenv_int` -- THE OTHER ARM OF THE
SAME `getenv`", and `helpers.bend:150` states the split axis: "a default of `""` gives
`str` (`getenv_str` above) while a default of `0` gives `int` (here)."

## THE MECHANISM I FOUND, AND WHY IT IS THE ONE

`naming-gate.py` has **two different things** called QUALIFIED, and conflating them is
what the briefing did:

| | code position | meaning | is it an adjudication? |
|---|---|---|---|
| **QUALIFIED tally bucket** | `naming-gate.py:189-191`, `if name in quals` | the UPSTREAM NAME survives as a module qualifier, i.e. the port wrote `def SomeMod.getenv` | **NO** -- it is a *port-form* verdict that the name was reproduced |
| **ledger entry** | `naming-gate.py:210-228` + `naming-gate-ledger.py:51-153` | a reviewed (file, name, affix) rename, with a mandatory reason | **YES** -- this is the only thing that adjudicates a proposal |

`getenv_str` was **never in the QUALIFIED tally**. It is an adjudicated rename living in
the `RENAMED/n` bucket, exempted by a ledger line that already existed:

```
naming-gate-baseline.txt:47   helpers.py  getenv  _str  LANG-CONSTRAINED:no-generics-one-def-per-element-type
```

So the precedent the briefing points at is a **ledger line**, and the mechanism to extend
it is `naming-gate-ledger.py`'s `RULES` table -- the *authoritative writer* of the ledger.
`naming-gate-ledger.py:184-196` refuses to write unless every live proposal is covered by
a rule and no rule matches nothing, so a rule is the ruling, not a comment about one.

I rejected the other two candidates explicitly:

- **A call-site qualifier** would need a literal `def <something>.getenv` line in
  `helpers.bend`. Beyond being a lie about the port (there is no such def, and Bend cannot
  dispatch on the default's type to create one), `helpers.bend` is on the do-not-edit list
  -- see the existing ledger line `helpers.py unwrap _or OWNER-RULING-NEEDED:
  unwrap_or-vs-unwrap-helpers.bend-is-do-not-edit`. Not available, and not honest.
- **Widening the gate's QUALIFIED bucket** to cover "overload materialisations" would put a
  suppression in the DETECTOR. The gate's own docstring forbids that in the strongest terms
  (`naming-gate.py:47-66`): suppressing upstream names with more than one affix hit "hid 6 of
  the 9 renames this gate was built to catch". A detector that stops proposing is not a
  stricter gate; it is a gate that stopped checking.

**So: one token added to one existing, already-tight, per-file regex.**

```python
('helpers.py', r'_(?:i32|u32|str|nat|sign|seq|int)(?:_go|_str)?',
 'LANG-CONSTRAINED:no-generics-one-def-per-element-type'),      # naming-gate-ledger.py:92
```

### WHY `_int` TAKES THE *MONOMORPHISATION* REASON AND NOT THE OVERLOADING ONE

Both reasons are literally true of `getenv` (it is overloaded AND generic), so this is a
choice, and the choice is forced by the sibling arm. `_str` landed on the monomorphisation
string, so putting `_int` on `no-overloading-split-by-branch` would make the gate's own
by-reason report print one `getenv` arm under "monomorphisation" (29 entries) and the other
under "overloading" (4 entries) -- and read as two unrelated rulings when the port says
out loud they are the same def. Split the pair's reason string and the audit record starts
lying. Both reasons are also `LANG-CONSTRAINED:`, so the vocabulary's contract ("the affix
is forced by the LANGUAGE") holds either way.

MEASURED, before touching the regex -- the widened regex newly matches exactly ONE key of
668, so nothing else is exempted as collateral:

```
keys the WIDENED monomorphisation regex newly matches:  getenv +_int -> getenv_int
```

and this is now a standing check (selftest case 10), because the generator applies a regex
to every live proposal and writes the exemptions with no reviewer in the loop.

## THE CHANGE

Three files, all under `.agents/slop/`:

1. `naming-gate-ledger.py:76-93` -- `int` added to the monomorphisation regex, with the
   reasoning inline so the next reader does not re-litigate it.
2. `naming-gate-baseline.txt:47` -- one line added, hand-placed at the position the
   generator's `sorted()` puts it (`_int` < `_str` for the same `(file, name)`).
3. `naming-gate-ledger-check.py` (new) -- asserts the ledger FILE is byte-identical to what
   the generator WOULD write, plus full coverage and no dead rule.

**I hand-placed the line rather than running the generator on purpose.** The generator
rewrites all 668 lines from the live census, and other units were mid-write: a regeneration
taken at the wrong moment drops lines for transient candidates and leaves the ledger
permanently wrong. The new checker is what makes a hand edit safe -- before this file
existed nothing connected the ledger on disk to the `RULES` table, so a hand edit kept the
gate green while the next generator run silently deleted the line.

## RESULTS (all from runs in this session)

| | before | after |
|---|---|---|
| `RESULT` | **FAIL** (exit 1), 22:20:25 | **PASS** (exit 0), 22:25:32 |
| `RENAMED: N candidates -> M unadjudicated` | 668 -> 1 | 668 -> **0** |
| **QUALIFIED tally** | **38** | **38** |
| VERBATIM / RENAMED-1 / RENAMED-n / ABSENT | 283 / 29 / 89 / 1144 | 283 / 29 / 89 / 1144 |
| `naming-gate-selftest.py` | 12 ok / **3 FAIL**, exit 1, 22:23:31 | **20 ok / 0 FAIL**, exit 0, 22:29:51 |
| `rebase-gate-selftest.py` | 66 PASS / 0 FAIL, 22:23:45 | 66 PASS / 0 FAIL, 22:26:24 |

### QUALIFIED is 38 both before and after, and that is the honest answer

**The briefing asked for `getenv_int` to be "counted QUALIFIED". The code has no such
bucket for this case, and `getenv_str` was never counted QUALIFIED either.** QUALIFIED is
`name in quals` (`naming-gate.py:189`) -- "the port reproduced this name under a module
qualifier". `getenv` is neither a bare stem nor a qualifier anywhere in `helpers.bend`, so
it stays in `RENAMED/n`, now adjudicated. Its two arms are counted together in the 89.

Every number above was measured four consecutive times (22:25:32-22:25:43) and the output
was **byte-identical** across all four, including VERBATIM 283 -- consistent with the
bracketing you cited (283 at 18:53, 278 at 19:34-19:36), so the substrate was settled
throughout this session. I did not reproduce the 278, and I am not claiming 283 is a
stable baseline.

### The selftest was RED before, and its green cases were VACUOUS

`naming-gate-selftest.py` case 1 requires a clean tree to PASS. With the tree red, cases 3
(planted rename), 4 (blank reason) and 5 (stale line) "passed" **for the wrong reason** --
the gate was already failing, so they could not distinguish "caught the plant" from
"already red". Only after the fix do those three mean anything. I added cases 8-11 so the
gap cannot reopen silently:

- **8 EXACT AFFIX** -- re-spell either `getenv` arm in the mirror (`getenv_int ->
  getenv_integer`, `getenv_str -> getenv_text`, both halves); each MUST go red naming
  `helpers.py :: getenv`. An exemption that had become a wildcard fails here.
- **9 EMPTY-NAMED ROW** -- a ledger line with an empty affix MUST fail, as STALE. See below.
- **10 RULE WIDTH** -- the widened regex must admit exactly `('helpers.py','getenv','_int')`
  beyond the old one.
- **11 REPORTED BLIND SPOT** -- printed, never asserted (asserting a known hole would fail
  the wrong way, on the day it closes).

I also fixed a defect in that file: the summary read `'ALL %d CHECKS PASS' % (7 * 2 + 1)`
and **printed 15 for 12 checks**. The total is now counted from the checks that ran. A green
line whose number is not derived from the checks is the same defect as an
over-reporting conformance roster, and it is how a dropped case becomes invisible.

## THE PLANTED-RENAME CONTROL (on a throwaway mirror; the live tree was never patched)

All four in one copy at `/private/var/.../opencode/ngctl.*/tree`, since removed:

| control | mutation | result |
|---|---|---|
| 0 | none | `RESULT: PASS`, exit 0, 668 -> 0, 22:32:21 |
| 1 | `getenv_int` -> `getenv_integer` (both halves) | **FAIL**, exit 1, 22:32:41 -- `helpers.py getenv + _integer -> getenv_integer` unadjudicated, AND `_int` correctly reported **STALE** |
| 2 | plant removed | `RESULT: PASS`, exit 0, 22:33:18 |
| 3 | `getenv_int` -> `getenv_u32` | **FAIL**, exit 1, 22:33:21 -- as STALE (`_u32` is already covered, so the new `_int` line is stale once the arm moves) |
| 4 | empty-affix ledger row appended | **FAIL**, exit 1, 22:33:24 -- `*** 1 STALE LEDGER LINE(S) ***  helpers.py getenv +  (ledger says: ANY REASON AT ALL)` |

Control 1 is the important one: the gate bites on the very file and the very name this
ruling is about, and it also noticed that my new ledger line stops applying when the port
stops carrying the name.

## YOUR SECOND CAUTION: THE EMPTY-NAMED ROW -- MEASURED, IT HOLDS

An empty-affix ledger row **stays a FAILURE, and is reported as STALE, never as a rename
candidate** (`naming-gate.py:249`, `stale = {k for k in ledger if k not in detected}`). It
cannot be a candidate because `MIN_AFFIX = 3` (`naming-gate.py:111`) means the detector
can only propose an affix of length >= 3, so an empty affix is unreachable as a key. Pinned
as selftest case 9.

I also checked the `rows()`/`== SECTION ==` phantom-row hazard for a counterpart:
**there is none in the naming gate.** `port_names` (`naming-gate.py:135-147`) keys on
`DEF_LINE` anchored to `^\s*(def|struct|type)\s+<name>`, so a `#`/`//` comment cannot
manufacture a stem. Measured over the whole `.bend` tree: 27,490 `DEF_LINE` matches,
**0 `== ... ==` banner lines at all**, 3 files containing a triple-quoted block and **0
`DEF_LINE` matches inside one**. The gate has no row-splitting layer to go wrong.

## BLIND SPOTS FOUND WHILE LOOKING -- REPORTED, NOT SILENTLY FIXED

1. **A rename applied to a `.go` monomorphised half ALONE is invisible.**
   `port_names` splits on the final dot, so `def getenv_int.go(...)` contributes the stem
   **`go`** and pushes `getenv_int` into the QUALIFIER set. Rename only that line and the
   bare `def getenv_int(...)` still matches, so the gate answers PASS. MEASURED on the
   mirror (selftest case 11): `RESULT: PASS`. I hit this accidentally first -- my initial
   control used `count=1` and hit the `.go` half, so the control "passed" while renaming
   nothing the gate could see. The control now renames every occurrence.
   **Consequence:** every `.go` arm needs its bare twin renamed too, or the port can drift
   half-way with the gate green. `.go` stems also mean `quals` accumulates monomorphised
   base names, so an upstream name equal to one of them would count QUALIFIED for the
   wrong reason.
2. **`MIN_AFFIX = 3` hides 22 real (name, stem) pairs.** Measured: the pairs an affix of
   length >= 3 would report and the gate cannot, including `runtime/ops_cl.py check +t_ ->
   t_check`, `runtime/ops_cuda.py check +ed -> checked`, `renderer/nir.py aop +f_ -> f_aop`,
   `helpers.py argfix +1 -> argfix1`, `uop/symbolic.py casted_const +p_ -> p_casted_const`.
   The docstring cites the reason (upstream `dsl.py` binds one-letter `s`/`v`, which would
   manufacture 582 pairs), so this is a priced trade-off, not an oversight -- but the price
   is 22, not "some".
3. **`upstream_names` returns `{}` on a parse failure** (`naming-gate.py:120-122`, catching
   `SyntaxError`/`UnicodeDecodeError`/`ValueError`), which silently drops that file's
   ENTIRE denominator -- every port def in the sibling becomes undetectable. Measured: **0
   files currently fail to parse**, so it is latent. A `sys.stderr` line would cost one
   `print`.
4. **Eight sibling `.bend` files have ZERO upstream bindings**, so the gate is structurally
   silent on them. Seven are 0-byte `__init__.py` (correct -- they bind nothing). The two
   that are not: `tinygrad/nn/torch.py` (336 bytes, a side-effect re-export shim) and
   `tinygrad/runtime/support/compileserver.py` (596 bytes, all code under
   `if __name__ == "__main__"`). Both genuinely bind no module-level names, so nothing is
   miscounted -- but a rename in either is undetectable, by construction rather than by
   policy.

## OUTSIDE MY FILES

- **`tinybendygrad/helpers.bend`** is on the do-not-edit list. No call-site change is needed
  and none is possible: both arms already exist and are documented in place.
  **REPORT, not changed.**
- **`codegen/__init__.bend`, `nn/state.bend`, `generate.bend`** were mid-write by other
  units when I started; my four consecutive runs were byte-identical, so nothing I
  recorded was taken across that window. Not mine, not touched.
- **Not committed**, per instruction.