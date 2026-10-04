# NORM — one normaliser, and the four gates that each had their own

Rule prefix for this unit: **`NORM-`**. Files: `.agents/slop/norm/`.
**Nothing committed. Nothing under `tinybendygrad/` touched.**

```
python3 .agents/slop/norm/canon.selftest.py   # the four rows + the property + the plants
python3 .agents/slop/norm/gate_norm.py        # both lanes, four verdicts, never summed
python3 .agents/slop/norm/lint_norm.py        # the census; exit 1 on a NEW bad normaliser
zsh    .agents/slop/norm/lint_demo.sh         # both of the lint's branches, measured
```

## THE CLASS, IN ONE LINE

> **A normaliser that rounds differently on the two sides manufactures a
> disagreement that is not one.**

The rule is one line and it is not about printing:

> **A float is compared at the width OF THE SEAM THAT CARRIED IT, on BOTH sides,
> through `norm/canon.py`, and nowhere else.**

This is the fifth instrument in this tree's family of instruments that produced a
plausible line of output and a wrong verdict, and the subtlest, because the output
is not wrong — it is *about a different thing* than the reader thinks. The other
four: `--check-only` says `ALL PROOFS CHECK` for an empty file; a dict-keyed
presence check cannot see 55 duplicate rows; `None{}` counted a type-correct
`Option.None` as an empty body; `bend=137` counted one probe. **A formatting
difference reported as a semantic one is worse than a crash, because it is
believed.**

## 1. THE CENSUS — every normaliser, classified

The one question: **does it round-trip through the value's own width?** Full output
in `norm/census.txt`; 998 gate files scanned.

| file:line | spelling | width | round-trips? |
|---|---|---|---|
| `jslane2/gen_f32_seam.py` (was `:100`) | `repr(float(s))` | none | **NO** — instance 1, now on `canon` |
| `mm-dt-gate.py:60` | `"F" + f"{v:g}" if is_integer else repr(v)` | none | **NO** — and see §1a |
| `mm-walk-gate.py:44` | the same line | none | **NO** — copy 2 of 3 |
| `mm-lift-gate.py:158` | the same line | none | **NO** — copy 3 of 3 |
| `dc-oracle.py:135` | `f"C({a:g})"` | none | **NO** — and the author said so |
| `abi/abi_gate.py:132` (`norm`) | `repr(unpack("<f",pack("<f",v)))` | f32 | **yes** — do-not-touch, already correct |
| `abi4/abi4_gate.py:240` (`norm`) | the same | f32 | **yes** — do-not-touch, already correct |
| `jstage/jsstage.py:308` (`f32`) | `unpack("<f",pack("<f",x))` + `isnan` | f32 | **yes** — another unit, already correct |
| `graphcmp.py:459` | `ATOMS["float"] + str(f32bits(x))` | f32 bits | **yes** — instance 3, the fix |
| `tx-oracle.py:17-21` (`fbits`) | `str(unpack("<I",pack("<f",x)))` | f32 bits | **yes** |
| `tx-arena.py:135` | `f"cf{bits}"` | f32 bits | **yes** |
| `beautiful-mnist-gate.py:57,68` | `f32()` then `pack(">f",x).hex()` | f32 bits | **yes** |
| `mathlib/expect.py:26`, `expect3.py:29`, `expect4.py:21` | f32 bits / exact rational | f32 | **yes** |
| `tc-audit.py:39-49` | `f32bits` + `float.hex()` | f32 | **yes** |
| `tc-gen.py:40`, `tc-value.py:37` | f32 bits | f32 | **yes** |
| `dtypeb/gen_fp8.py:35,40` | `unpack("<f",pack("<I",p))` | f32 | **yes** (and `:35` is the FX-14 fixture trap) |
| `f64/oracle_f64.py:114` | `struct` f64 pack/unpack + a round-trip `assert` | f64 | **yes** |
| `dt32/dt32-oracle.py:39,43`, `frombits/*:41,45`, `abi4:183,187`, `notes/fp8_oracle.py:40,44`, `notes/fp16_oracle.py:21,30` | `struct` round trips | f32 | **yes** |
| `jslane2/gen_js_seam.py:116`, `w64mile/gen_seam.py:80`, `w64mile/gen_i64.py:101`, `jsfix/*:154,37` (`pattern`) | `hi:lo` | n/a (integer) | **yes** — not a float normaliser |
| `bend_e2e.py:71` | `repr(got) == repr(want)` | unstated | **sound by accident** — see §4 |
| `tinybendygrad/base.bend:54` | `F32.from_bits` | n/a | the primitive, not a normaliser |

### 1a. THE THREE INSTANCES ARE NOT THREE DEFECTS

They are one defect wearing three coats, and the census finds the same **shape** in
four more sites: **a normaliser that handles HALF the trap and leaves the other
half.**

- `repr(float(s))` re-formats `448` as `448.0` — JSL2-7's half — and cannot touch
  the shortest-form half. **MEASURED: it gets the f16 `1.1` row WRONG
  (`1.0996094` vs `1.099609375`) and gets `1.0`, `448` and `nan` RIGHT.**
- `mm-dt-gate.py:60`, `mm-walk-gate.py:44` and `mm-lift-gate.py:158` carry
  **three byte-identical copies** of a line that special-cases the integral float
  and leaves the non-integral one.
- `dc-oracle.py:130` says, in its own comment, *"`%g` agrees with `H.f32_show` on
  1.0 — the only float CONST in this file — and would NOT agree on a non-integral
  one."* Shipped the gap anyway.
- `cstyle-live/cstyle-numbers.py:5` states the whole argument for hex. It is right.

## 2. THE SHARED HELPER, AND WHAT IT COSTS

`.agents/slop/norm/canon.py`. **One file, two functions, no language split.**

```
canon(value, width)      a VALUE (float, or a decimal spelling) -> canonical string
canon_bits(pattern, width)  an IEEE-754 PATTERN at width    -> canonical string
```

Why the **width is an argument** and not a constant: `1.0 + 2**-40` is
`0x3ff0000000001000` in f64 and **exactly `1.0`** in f32 (`e2e.sh:215` calls it
"THE ROW f32 CANNOT HAVE"). A normaliser with the width hard-coded answers one of
two questions depending on which width it picked, and the reader cannot tell which
from the output. `canon(x, width)` cannot be called without naming the width.

Why **two** entry points, and it is not a convention: **neither side of a gate can
hold a NaN payload in a float.** CPython's `float` has no payload, so the oracle
cannot even express `0x7fc00001`; JavaScript's `NaN` is one value. So `canon`
**REFUSES** — given a spelling that parses to NaN it answers `<width>:?nan`, a
string equal to no pattern's spelling, which forces a gate to notice it is
comparing a value it cannot resolve. `canon_bits` is the only entry point that
separates two NaNs, and a gate using it must say what its lane did with the
payload. `gen_f32_seam.py` calls that outcome **`AGREE-UNRESOLVED`** and counts it
in neither pass nor fail; `gate_norm.py` calls it **`LANE-LOSS`**.

**WHAT IT COSTS, because it is NOT FREE. This is a NINTH convention in a tree that
already has eight live ABI ones.**

- **One file, no per-language split** — and the reason is a property of the gates,
  not luck: **both lanes are normalised in Python, from text, after they have
  run.** The helper never has to exist in `.bend`, in C, or in JS. That is the
  whole reason one helper is possible.
- One line per gate in its emitter: `U32.show(F32.bits(v))` instead of
  `F32.show(v)`. Both spellings are carried side by side in `gate_norm.bend` and
  `jslane2/gen_f32_seam.py` so the difference is measured rather than remembered.
- **The enforcement is `lint_norm.py`, not the helper.** A helper nobody is forced
  through is a helper that is bypassed the first time it is inconvenient.

### The gates I could NOT move onto it, with the reason

| gate | why not | is it correct? |
|---|---|---|
| `abi/abi_gate.py` | **explicitly do-not-touch** | **yes**, `:132` round-trips |
| `abi4/abi4_gate.py` | **explicitly do-not-touch** | **yes**, `:240` round-trips |
| `jstage/jsstage.py` | another unit's tree | **yes**, `:308` round-trips + `isnan` |
| `graphcmp.py` | **do-not-touch** | **yes**, already bits-based |
| `mm-dt-gate.py` · `mm-walk-gate.py` · `mm-lift-gate.py` | another unit's tree | **NO** — baseline, §1 |
| `dc-oracle.py` | another unit's tree | **NO** — baseline, §1 |
| `bend_e2e.py` | e2e family | sound *by accident*, §4 |

`lint_norm.py`'s `BASELINE` carries those four defect sites with a reason each and
keys them on `file:line`, so a site that **moves** is reported as new and the
exemption goes stale in the open.

## 3. THE FOUR MOTIVATING CASES, EACH SHOWN PASSING

`norm/selftest.txt`, `norm/gate.txt`:

```
1  `1.1` in f16   f32_show says `1.0996094` -> f32:3f8cc000
                 CPython says `1.099609375` -> f32:3f8cc000      AGREE
2  `1.0`         `F32.show` says `1`        -> f32:3f800000
                 its bits say 0x3f800000   -> f32:3f800000      AGREE
3  `1.0 + 2**-40`  f64 -> f64:3ff0000000001000
                   f32 -> f32:3f800000 == 1.0's own        WIDTH DECIDES
4  two NaNs      f32:7fc00001  vs  f32:7fc00000  vs  the refusal f32:?nan
                                                                ALL THREE DISTINCT
J  JSL2-7         `448` vs `448.0` -> f32:43e00000 both      AGREE
```

On both lanes (`node` v26.8.1 and `cc`, `norm/gate.txt`): **8 rows asked for,
8 AGREE, 0 DISAGREE, 0 LANE-LOSS, 0 absent, exit 0.**

**And the plants, so each row is shown able to fail:**

- `repr(float(s))` — the normaliser the brief names — is wrong on **2 of 5** of the
  lane/oracle rows: the f16 `1.1` and the f64 reading of `1.0 + 2**-40`.
- `f"{v:g}"` — `dc-oracle.py:131` — is wrong on **0 of 5**, and wrong in a way no
  lane/oracle row can see: `1.0000001`, `1.0000002`, `1.0000003` are **three
  distinct f32 values** and it spells them all `1`.

## 4. WHAT IS MEASURED THAT CORRECTS THE BRIEF

- **`F32.show(1.0)` is `1`, not `1.0`.** The `.0` at `bend.ts:1202` belongs to the
  diagnostic printer at `comp.ts:788`, not to `F32.show`. JSL2-7's `448` vs
  `448.0` is real and the gate had to notice it.
- **`tinybendygrad/base.bend:42` is half wrong.** It says
  `F32.bits(F32.from_bits(p))` collapses **every** NaN onto `0x7FC00000` in the JS
  lane. **MEASURED on both lanes: `nan_p1` reads back `2143289345` under `node` and
  under `cc`, and `0x7FC00001` **is** `2143289345`.** The payload **survives the
  typed-array path on both lanes** (`comp.ts:537-542`). What does *not* survive it
  is a NaN **manufactured by JavaScript**: `0/0` packs as `0x7fc00000`. The claim
  that survives is narrower, and it is the one a gate may rely on: **a NaN that
  crossed as a pattern keeps its payload; a NaN made by arithmetic does not, and
  nothing downstream can tell them apart.** `base.bend` is not this unit's file —
  reported with `file:line`, not edited.
- **`bend_e2e.py:71`'s `repr(got) == repr(want)` is sound only by accident.** Both
  sides are already f32-exact doubles, and `repr` is injective on those — so it
  reduces to `==` — but that invariant is stated nowhere, and an f64 or f16 row
  would break it. Do-not-touch; reported.
- **`jslane2/gen_f32_seam.py` had never run.** `dtype.bend` made `Dt.bf16`,
  `Dt.fp16` and `Dt.fp8_to` **pure** defs (`dtype.bend:583`), so the file's
  `v : F32 <- D.Dt.bf16(...)` stopped compiling and the gate printed `bend failed`
  and exited 1. **The `fp16_1p1` fixture the JFP- unit had added had therefore
  never executed.** A fixture in a gate that cannot compile is not a fixture.
  Fixed: it now runs **7/7 on both lanes, 0 lane disagreements, exit 0** — and
  that 0 is *not* the JS lane being fixed, it is the JS lane no longer being
  reached by these rows, which is what the closing text of that gate now says.
- **`IO.pure(F32, ...)` does not compile.** `IO.pure`'s first parameter is
  `-A: Type` and `F32` in expression position is the **constructor**
  (`expected : F32 / observed : @-R:Type -> ...`). A pure call needs no lift in an
  **argument** position. `jstage/jsstage.py:218` emits exactly that shape, so that
  lane has it too; another unit's file, reported.

## 5. THE ROWS THAT WERE MISSING RATHER THAN WRONG

Full table in `norm/fixtures.txt`. Every gate on the baseline has a fixture set
that **cannot fail on its own normaliser**, measured by running each gate and
reading the spellings it emits:

| gate | its float-arm fixtures | can they fail it? |
|---|---|---|
| `mm-dt-gate.py` | `F±240 F±448 F±57344` — all integral | **NO** |
| `mm-lift-gate.py` | `F±1.5` | **NO** — 1.5's exact f64 decimal *is* its f32 shortest form |
| `mm-walk-gate.py` | none at all | **NO** — the arm is **unreachable** |
| `dc-oracle.py` | `C(1.0)` | **NO** — and `%g` cannot get 1.0 wrong |

**What I added:** all four cases on both lanes in `norm/gate_norm.bend` +
`gate_norm.py`; the plants in `norm/canon.selftest.py`; both of the lint's exit
branches in `norm/lint_demo.sh`.

**What I did not add, and why:** the three-line fixtures that would expose
`dc-oracle.py:131` and the `mm-*` gates belong to other units, and adding a row to
someone else's gate is how two units end up editing one file. The rows are written
out in `fixtures.txt` so the owning unit can paste them.

## 6. RULES

- **`NORM-1` — A FLOAT IS COMPARED AT THE WIDTH OF THE SEAM THAT CARRIED IT, ON
  BOTH SIDES, THROUGH `norm/canon.py`, AND NOWHERE ELSE.** The width is an argument
  because `1.0 + 2**-40` is `0x3ff0000000001000` at f64 and exactly `1.0` at f32,
  and a hard-coded width answers a question the reader cannot see.
- **`NORM-2` — A NORMALISER THAT REFUSES IS BETTER THAN ONE THAT GUESSES.** A
  decimal spelling carries no NaN payload, so `canon` answers `f32:?nan` and lets
  the gate report `AGREE-UNRESOLVED` / `LANE-LOSS` rather than call two NaNs one
  row. **A normaliser that claims to separate NaNs is separating them on one side.**
- **`NORM-3` — THE TRAP HAS TWO HALVES AND EVERY INSTANCE HERE FIXED ONE OF THEM.**
  `repr(float(s))` handles the integral half (`448`) and not the shortest-form
  half (`1.0996094`); `mm-*-gate`'s line handles the integral half and not the
  non-integral one. **A fix that names only the half it fixed has left the class
  in place.**
- **`NORM-4` — A GATE WHOSE FIXTURES CANNOT FAIL ON ITS OWN NORMALISER HAS NOT
  TESTED IT.** All four baseline gates are in that state, measured by running each
  one. And for `%g` the exposing fixture is **two different values inside one
  side**, which is a row shape no gate in this tree has.
- **`NORM-5` — A FIX IN A GATE THAT CANNOT COMPILE IS NOT A FIX.**
  `jslane2/gen_f32_seam.py` had a correct `norm` and a correct `fp16_1p1` fixture
  and had never run, because `dtype.bend` moved the three seams to pure defs under
  it. **Re-run every gate you fix, and read its rows, not its exit status.**
- **`NORM-6` — A LINT PINNED TO A CONSTANT IS THE SAME FAMILY OF DEFECT IT
  EXISTS TO STOP.** `lint_norm.py` reports **BASELINE** (the four known defects,
  each with a reason and a `file:line` key) and **NEW** (anything else), and exits
  on `NEW` alone. `lint_demo.sh` measures both branches: green on the tree, red on
  one planted site.
- **`NORM-7` — WHAT A CENSUS GETS WRONG IS USUALLY NOISE, AND NOISE IS HOW A
  CENSUS DIES.** MEASURED, all four: scanning `xd1/`/`opstree/` (two whole second
  tinygrad checkouts) buried four real sites under ~400 browser formatters;
  `\bcanon\(` matched `clangshim-gen.py`'s own unrelated `def canon`; `canon(x,
  "f32")` fixed it; `#`-stripping alone left `gen_f32_seam.py:174` flagged
  because it **quotes** the defect in a docstring; and `repr(float(` **building an
  oracle** is a different job from normalising one. A lint whose output gets
  ignored is a lint that has failed quietly.