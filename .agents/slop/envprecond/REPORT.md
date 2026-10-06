# env-precond METHOD A: a line number is a hand list of one

**Task:** `checks/env-precond.py --check` refused on two lines. Both pins named a line
number, and a line number rots the moment an edit lands above it. The fix is to pin the
**thing**, not its address. Only `checks/env-precond.py` was edited; nothing outside it.

## 1. What METHOD A actually asserted (before the fix), `file:line`

`checks/env-precond.py:196-205`, the old loop:

```python
for path, line, text in DIFFER_LINES + ORACLE_LINES + GRAPH_LINES:
    src = sources.get(path, [])
    have = src[int(line) - 1] if int(line) <= len(src) else ""     # <-- LINE NUMBER
    want = [v for v in ("PYTHONHASHSEED", "NOOPT") if v in text]   # <-- SHAPE, from the text
    miss = [v for v in want if v not in have]
```

It asserted **both**:

- a **LINE NUMBER** — it indexed the file at `int(line) - 1`, so an insertion above the
  pin moved it off its target; and
- a **SHAPE** — that line had to contain the tokens `PYTHONHASHSEED`/`NOOPT`, where the
  tokens were derived from the declared `text` by substring.

It never asserted **line contents** in full; `text` was only a token source. So a pin that
named `:509` was red even though the thing it meant was present at `:513`, and a pin whose
`text` named neither token (`ORACLE_LINES`) was **vacuously green** — `want = []`,
`miss = []`, `ok … pins (nothing required)`, at any line, existing or not. A line-number
pin is a hand list of one; a vacuous one cannot even be wrong, because it asserts nothing.

## 2. `checks/differ.py:509` vs `:513` — what the pin MEANT

`:509` is the D10 0-row-guard `run(...)`. The census capture the pin meant is at **`:513`**:

```python
    capture("D0-coverage-census.txt", ".agents/slop/graphcmp-oracle.py", stamp_rc=True)  # DEV/PYTHONHASHSEED/NOOPT/LC_ALL are set by ENV above, not by this call
```

The declaration's own `text` was the **:513 line including its comment** — the pin meant the
call, and only its number was stale. **The miss predated the recent `differ.py` edits** and
was wrong when written (the string it declared never sat at `:509`).

**Fix:** `PINS` now names `(file, ANCHOR, must-carry)` — an anchor is a literal substring
naming the line's **job**, so an insertion above it cannot move the pin. The two `differ.py`
pins are:

```python
    ("checks/differ.py", 'ENV = {k: v', ("PYTHONHASHSEED", "NOOPT")),
    ("checks/differ.py", 'capture("D0-coverage-census.txt"', ("PYTHONHASHSEED", "NOOPT")),
```

METHOD A greps for the anchor and asserts the tokens on the line it lands on
(`checks/env-precond.py:205-216`). The anchor for the census call is
`capture("D0-coverage-census.txt"` and it lands on **`checks/differ.py:513`**.

**A third instance of the same class, found while fixing the two:** the old `ORACLE_LINES`
pinned `.agents/slop/graphcmp-oracle.py:91` and claimed the text
`os.environ["DEV"] = "CPU"`. Line 91 is `head, _, payload = arg.partition(",")`. The real
assignment is at **`:192`**, `os.environ["DEV"] = DEV` (read from `graphcmp.py`'s own `--dev`
default via `graphcmp_dev()`), and the `"CPU"` spelling is the *predecessor* the oracle's
docstring (`:141`) records as a bug. It was never seen because `want=[]` made the check
vacuous. Now anchored at `os.environ["DEV"] = DEV`.

## 3. Re-testing the #2 refusal (`graphcmp.py:1800`)

The prior unit declined to add `PYTHONHASHSEED`/`NOOPT` to `clean_env`, calling it *"an edit
made to satisfy a regex."* Re-measured, **the prior unit was right**:

- `clean_env` (`graphcmp.py:1796`) has exactly **two** call sites — `:1826` (`emit_bend`)
  and `:2635` (`emit_debug`) — and both pass `env=` to `subprocess.run([str(BEND), …])`,
  where `BEND = REPO/"bin"/"bend"` (`:275`).
- `bin/bend` is `exec bun references/bend/bend2/main.ts`. `grep` finds **no**
  `NOOPT`/`PYTHONHASHSEED` in `references/bend/`; bun reads neither.
- The **port** reads five flags: `DEBUG`, `DEFAULT_FLOAT`, `DEFAULT_INT`, `NO_COLOR`,
  `SUM_DTYPE` (`tinybendygrad/helpers.bend:308,342-345`). `NOOPT` appears in the port only
  as **prose** (`helpers.bend:2776`: *"…is phase P6"*), not as a `getenv`. `PYTHONHASHSEED`
  is a CPython variable; the bend side runs no CPython.

**Verdict: no reader exists → the precondition is OVER-SPECIFIED at `graphcmp.py:1800`, and
SAID SO is the answer.** `PINS` now declares the bend pin with no extra tokens
(`(".agents/slop/graphcmp.py", 'e.update(LC_ALL="C", DEV=dev)', ())`); the anchor itself
asserts `LC_ALL`/`DEV`, which is all that line pins. `checks/differ.py`'s ENV still pins
`NOOPT`/`PYTHONHASHSEED`, because **it** feeds the CPython oracle, which reads them.

**No edit is required in `checks/differ.py` or `.agents/slop/graphcmp.py`.** The replacement
text, *if an owner insisted on satisfying the old over-broad pin*, would be
`e.update(LC_ALL="C", DEV=dev, PYTHONHASHSEED="0", NOOPT="0")` — but that is the edit made to
satisfy a regex, and it is not recommended.

## 4. `--check` BEFORE and AFTER

**BEFORE — rc=1 (REFUSED):**

```
METHOD A -- the source lines that build the child environments:
    ok       checks/differ.py:47 pins PYTHONHASHSEED,NOOPT
    MISSING  checks/differ.py:509 lacks PYTHONHASHSEED,NOOPT
    ok       .agents/slop/graphcmp-oracle.py:91 pins (nothing required)
    MISSING  .agents/slop/graphcmp.py:1800 lacks PYTHONHASHSEED,NOOPT

METHOD B -- what the run recorded, read with partition('='), no regex:
    ok        dev=CPU (declared CPU)
    ok        pythonhashseed=0 (declared 0)
    ok        noopt=0 (declared 0)
    ok        lc_all=C (declared C)
RC=1
```

**AFTER — rc=0 (two methods, four anchors, four recorded rows):**

```
METHOD A -- the source lines that build the child environments, found by anchor:
    ok       'ENV = {k: v' pins PYTHONHASHSEED,NOOPT
    ok       'capture("D0-coverage-census.txt"' pins PYTHONHASHSEED,NOOPT
    ok       'os.environ["DEV"] = DEV' pins (its own tokens)
    ok       'e.update(LC_ALL="C", DEV=dev)' pins (its own tokens)

METHOD B -- what the run recorded, read with partition('='), no regex:
    ok        dev=CPU (declared CPU)
    ok        pythonhashseed=0 (declared 0)
    ok        noopt=0 (declared 0)
    ok        lc_all=C (declared C)
RC=0
```

The check can still refuse, and is shown to in §5. `--plant satisfied` and `--plant moved`
both exit 0 with all three internal plants `CORRECT` (moved-pin fires on METHOD A, moved-summary
on METHOD B).

## 5. PLANT — two states on a COPY

`.agents/slop/envprecond/plant.py` (copies the four sources to a tempdir; the live tree is
never written). Four beats, two directions:

```
STATE 1  as-is        -> exit 0  (expected 0): CORRECT
STATE 2  edit-above   -> exit 0  (expected 0): CORRECT   # a line inserted ABOVE the census capture
STATE 3  broken       -> exit 1  (expected != 0): CORRECT # PYTHONHASHSEED/NOOPT stripped from ENV
STATE 4  restored     -> exit 0  (expected 0): CORRECT
PLANT: OK -- REFUSES when broken, PASSES when restored
```

**STATE 2 is the load-bearing one:** inserting a line above the census capture — the exact
edit that made the old `:509` pin red — now leaves the check GREEN, because the anchor
travelled with the call. **STATE 3** strips the two tokens METHOD A asserts and the check
REFUSES with `MISSING 'ENV = {k: v' lacks PYTHONHASHSEED,NOOPT`.

## 6. Also corrected in `checks/env-precond.py` (stale citations in my own file)

Fixing stale pins while the prose kept stale pins would be the disease inside its own cure:

- `PRECONDS`/docstring cited `graphcmp-oracle.py:119` as an unsorted set print and
  `:150-160` as a false "already sorted" claim. The oracle now **sorts** those prints
  (`graphcmp-oracle.py:233,279`) under its own rule *"a PIN IS A SEED AND a SORT IS A LAW"*
  (`:307`), so PYTHONHASHSEED's consequence is stated as historical and **re-measurable**,
  not settled.
- `observed()` returned `PYTHONHASHSEED = "UNRECORDED (randomized per process)"` while
  METHOD B read `pythonhashseed=0` from the summary. `observed()` now reads the summary's
  keys, so `--record` and `--check` cannot disagree.
- The `DEV` row cited `graphcmp-oracle.py:91` + `setdefault`; corrected to the `:192`
  assignment and the recorded predecessor.

## 7. Replacement text for files I do not own (nothing edited)

**`.agents/slop/devrecord/xcheck.py:88-92`** — the prose is now false (`env-precond` exits 0;
XCHECK itself still prints `GREEN`):

```
        print("  env-precond's exit is 0: METHOD A's four anchors hold and METHOD B reads four\n"
              "  `ok`. `.agents/slop/graphcmp.py:1800` is NOT MINE and needs no NOOPT/PYTHONHASHSEED\n"
              "  -- MEASURED, `clean_env` only ever reaches `bin/bend`, and the port reads exactly\n"
              "  five flags (DEBUG DEFAULT_FLOAT DEFAULT_INT NO_COLOR SUM_DTYPE), so neither has a\n"
              "  reader downstream. env-precond's PINS says so and asks only for what it can enforce.")
```

**`checks/differ.py:878-879`** — *"`checks/env-precond.py --check` refused today for exactly
this"* is stale; only the ROWS-absent refusal remains true:

```
            # PLANT 4 -- THE ROWS ABSENT. `checks/env-precond.py`'s METHOD B refuses when a row
            # is missing, and a check that reports nothing when its input is missing is a printer.
```

**`.agents/TODO.md:13413-13415`** — "`checks/env-precond.py --check` still refuses" is stale:

```
- [x] **`checks/env-precond.py --check` is GREEN.** METHOD A anchors its four pins (not line
      numbers) and METHOD B finds dev=/pythonhashseed=/noopt=/lc_all= in the summary. The
      bend-side pin carries no extra tokens: MEASURED, NOOPT/PYTHONHASHSEED have no reader
      downstream of clean_env. Evidence: `.agents/slop/envprecond/REPORT.md`.
```

**`.agents/slop/preconds/FINDINGS.md` §7 (206-209) and its `--check` transcript (211-223)** —
pre-date the applied pins and now show a refusal that no longer happens. That file is a
historical measurement and can stay as history; if read as current, retitle it as such.

## 8. Files

- **edited:** `checks/env-precond.py` (343 → 362 lines) — anchor-based `PINS`, anchor lookup
  in METHOD A, anchor fabrication in `_one_plant`, corrected `observed()`/`record()`.
- **new:** `.agents/slop/envprecond/plant.py` (91 lines).
- **not touched:** `checks/differ.py`, `.agents/slop/graphcmp.py`, `runs/graphcmp/D/`,
  `AGENTS.md`, `tinybendygrad/`. No `bend` run; `.venv/bin/python` throughout; no `.txt`.
