# Clause II: the `UNMEASURED` hole, what it asserts, and what I did to it

Agent: clauseII unit. Date: 2026-10-06. Instrument: `gates/retention-check.py`.
Evidence raw: `.agents/slop/clauseII/{before.out,before.err,after.out,after.err,plant.py,plant.out,proof.out}`.

## 1. What the `UNMEASURED` branch asserts, exactly

**It asserts "no CLASS-SCOPED `run`", NOT "no `run` at all".** The predicate is two AST lines:

- `gates/retention-check.py:227` — `for cls in (n for n in tree.body if isinstance(n, ast.ClassDef)):`
  (only top-level `class` bodies are ever walked)
- `gates/retention-check.py:229` — `if not isinstance(fn, ast.FunctionDef) or fn.name != "run": continue`
  (inside that class, only a method literally named `run`)

Empty result ⇒ the `UNMEASURED` branch. In the new file that branch is `:370-374`; the pre-edit block
was `:377-389`.

Evidence that it is the CLASS test and not "no run":

```
$ rg -n '^class ' checks/differ.py          # rc=1, NO MATCH
$ rg -n '^\s*def run' checks/differ.py gates/gatekit.py
checks/differ.py:292:def run(out, *args):          # MODULE-LEVEL
gates/gatekit.py:291:    def run(self):            # class-scoped -> measurable
```

`checks/differ.py` has **zero** `class` definitions. Its writer is the module-level `cmd_run`
(`checks/differ.py:385`) over the module-level `run` (`:292`). So the correct reading of the message
is: *"this file has no `class X: def run` for clause II to read"* — the `run` exists, it is just not
class-scoped. The old message's second half (`stages .tmp. and os.replace-promotes … unlinks 2
hardcoded stale names`) was factually right: `run` stages `D/.tmp.{out}` then `os.replace` (`:303-308`),
`cmd_run` clears only `.tmp.*` (`:387-388`) and unlinks `D9-stability-{a,b}.txt` (`:528-529`). It does
**not** clear the directory, so there is genuinely no class-`run` clear to read.

## 2. Decision: **(b) MEASURED REFUSAL** — and the branch was already leaking green

Cited: `checks/differ.py:292` (`def run`, module-level) and `:385` (`def cmd_run`); `gates/gatekit.py:291`
(`def run(self)`, class-scoped). The property clause II measures — *every exit reaches a cleanup
`finally`* — is **gatekit's shape**. differ deliberately uses per-file atomic `os.replace`
(`checks/differ.py:303-308`) instead of a `finally`-settle. Extending the clause to read the
module-level writer would therefore report `FALSE` for a generator that is actually clean (clause I:
`runs/graphcmp/D` is the 1/12 clean dir; no `LEFTOVER` line) — i.e. it would re-commit the clause's
own historical sin of measuring the wrong shape. So **(a) is not the honest choice**, and the clause is
not *wrong* about gatekit — it is **refusing** about differ.

**The defect the brief did not name, and the one that mattered:** the old `UNMEASURED` branch never set
`red`. Measured on the recovered HEAD file with a single differ-shaped generator (`.agents/slop/clauseII/proof.out`):

```
OLD report() red=0  => UNMEASURED alone is GREEN: a pass!
NEW report() red=1  => UNMEASURED alone is red: the refusal is counted
```

`UNMEASURED` was on the same list as `OK` **and green**. That is the real hole: a reader could not tell
whether `differ.py` was fine or unknown *because the check agreed with them*. Fixed by returning red for
`unmeasured` and `missing` (`gates/retention-check.py:394`).

## 3. At-a-glance state separation

Four named tokens, each a fixed 10-wide column, so a token cannot be confused with a count:

| token | meaning | red? |
|---|---|---|
| `II OK` | class-scoped `run`, non-empty exit denominator, every exit covered | no |
| `II FALSE` | measured, an exit escapes cleanup | yes |
| `II UNMEASURED` | **no class-scoped `run`; empty denominator ⇒ REFUSAL, not a pass** | **yes** |
| `II MISSING` | the generator file itself is gone | yes |

Summary line now carries all three non-measured counts apart:
`II  clears its own output: 1/1 MEASURED, 1 UNMEASURED, 0 MISSING`.

## 4. PLANT — the clause goes red

`.agents/slop/clauseII/plant.py` imports the real `clause_ii` by path and drives four synthetic
generators differing **only** in the measured shape (`.agents/slop/clauseII/plant.out`):

```
[PASS] ok          red=0 want=0  II OK         …plant-ok.py: 0/1 exits NOT covered by a cleanup `finally`, clears=['unlink']
[PASS] false       red=1 want=1  II FALSE      …plant-false.py: 1/1 exits NOT covered by a cleanup `finally`, clears=['unlink']
[PASS] unmeasured  red=1 want=1  II UNMEASURED …plant-unmeasured.py: no class-scoped `run` in its AST, so the exit
[PASS] missing     red=1 want=1  II MISSING    …plant-missing.py is gone -- it is what declares the set
PLANT: GREEN  (4/4 cases as expected)
```

What was broken: the `false` plant deletes the `finally` that covers the `return`; the `unmeasured`
plant replaces the class with a bare module-level `def run` (exactly differ's shape); the `missing` plant
removes the generator file. Each makes the clause refuse.

## 5. Verdict before / after, with denominators

Clause II population: **2 generator source files** (`checks/differ.py`, `gates/gatekit.py`); the
`LEFTOVER` scan additionally reads **12 output directories** (1 graphcmp + 11 gates).

| | MEASURED | UNMEASURED | MISSING | II red? | general |
|---|---|---|---|---|---|
| before | 1/2 (gatekit `0/13`, clears OK) | 1 (differ) | 0 | **no** (UNMEASURED not counted) | `RETENTION: RED` |
| after | 1/2 (gatekit `0/13`, clears OK) | 1 (differ, now REFUSAL) | 0 | **yes** | `RETENTION: RED` |

The general verdict is `RED` in **both** runs, and in both it is clause **I**'s 11 residue dirs that
carry it — **not this change**. Clause II's own contribution moved 0 → 1 (`before.out:19` vs
`after.out:17`); the overall line did not move. The pre-existing 59-byte `SyntaxWarning: invalid escape
sequence '\d'` on stderr is byte-identical before and after (`.agents/slop/clauseII/before.err`).
