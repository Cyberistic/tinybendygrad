# `WANT` cannot express `UNSET` — the gap, the decision, and what must move

**Reading taken 2026-10-06 14:45:55 +03 at `git rev-parse HEAD` = `86cef1a76e07cc2232b95a0dd79abd969c6c8637`
(`git log -1` = 2026-10-06 14:33:40 +0300).** `checks/differ.py`, `.agents/slop/graphcmp.py` and
`.agents/slop/graphcmp.bend` are all UNMODIFIED vs that commit (`git diff --stat HEAD -- <those three>`
is empty), so the numbers below are the committed tree's, not a working-tree accident.

Instrument: `.agents/slop/wantwire/discover.py`, run once at the moment above; it loads `differ.py`
BY PATH (`spec_from_file_location`), takes `corpus()` = `differ.py`'s own loader of `graphcmp.GRAPHS`,
takes `WANT` from the same module, and derives the bend arms by regex `^def g_` over
`.agents/slop/graphcmp.bend`. It runs no `bend` and writes nothing under `runs/`.

---

## 1. The gap, by discovery

| quantity | value | denominator / reading |
|---|---|---|
| `GRAPHS` (`graphcmp.py:1590`, via `differ.corpus()`) | **34** | 34 `def g_` in `graphcmp.py`; 34 keys in the dict |
| `WANT` (`differ.py:124`) | **20** | 16 `AGREE` + 4 `DISAGREE` |
| gap (`graphs not in WANT`) | **14** | 34 − 20 |
| answered | **20** | = `len(WANT)` |
| `WANT` names not in corpus | **0** | no orphan rows |

**The fourteen, and whether each has a bend arm** (arm = a `def g_<name>` in
`.agents/slop/graphcmp.bend`; the dispatcher's fallback rung is `g_matmul()`, `:1515`):

| # | name | bend arm? | predicted verdict if it lands today |
|---|---|---|---|
| 1 | `alu` | **yes** | AGREE (arm mirrors the py rows) |
| 2 | `bit` | **yes** | AGREE |
| 3 | `bw` | **yes** | AGREE |
| 4 | `move` | **yes** | AGREE |
| 5 | `where` | **yes** | AGREE |
| 6 | `threefry` | **yes** | AGREE |
| 7 | `mulacc` | **yes** | AGREE |
| 8 | `getaddr` | **yes** | AGREE |
| 9 | `unshard` | **yes** | AGREE |
| 10 | `wmma` | **yes** | AGREE |
| 11 | `custom_function` | **no** | DISAGREE — `rows.pick3` falls to `g_matmul()`; bend emits matmul |
| 12 | `mselect` | **no** | DISAGREE (same fallback) |
| 13 | `mstack` | **no** | DISAGREE (same fallback) |
| 14 | `stage` | **no** | DISAGREE (same fallback) |

So: **10 of 14 have an arm, 4 of 14 do not.** The 4 without an arm are the SAME defect the
`disagree-gate.py` `SUBSTITUTED` tuple exists for (`allred`/`cdiv`/`late`), and they are **not
listed there** — the corpus is carrying four *new* substituted graphs and nobody declared them.

---

## 2. THE CENTRAL QUESTION — decision: **(a) leave it. `UNSET` must stay a refusal.**

`WANT` should **not** be given a third value for `UNSET`, and `WANT` should **not** be derived from
the last run. The two rejected options, and why, follow; then what the fourteen need instead.

**Why (a).** `UNSET` is not a verdict about a graph; it is the run's statement that *nobody has an
opinion*, and `differ.py:604-614` makes it a **non-zero exit**. That is what makes corpus growth
visible: `graphs = len(corpus())` and `unset = [g for g in graphs if g not in WANT]` (`:410-411`) are
**discovery**, not a hand list, so a graph added to `GRAPHS` cannot grow silently — it appears in
`unset`, is named in `D1-verdicts.txt`, and refuses the run. Letting `WANT` *declare* `UNSET` would
convert a refusal into a **row that cannot fail**, which doctrine §2 forbids:
*"a graph that lands expecting nothing is a corpus that cannot fail."* The gap is not a defect in
`WANT`'s expressiveness; it is `WANT`'s expressiveness being the *only* honest state for a graph no
one has measured. The fix is to **answer the fourteen**, not to teach `WANT` to shrug.

**The prior unit is right and I re-derived it:** a literal `"x": "UNSET"` row is broken TODAY.
- `unset` is membership: `[g for g in graphs if g not in WANT]` (`:411`) → adding `"x"` **removes it
  from `unset`**, i.e. silences the refusal;
- `moved` compares `verdict(...) != WANT[g]` (`:414-415`) → the recorded verdict is `AGREE`/`DISAGREE`,
  never `"UNSET"`, so adding `"x"` **adds it to `moved`** → **RUN WRONG**.
The two clauses are why a `WANT`-shaped `UNSET` cannot exist under today's code.

---

## 3. (b) and (c) as paste-ready text, and what each breaks

### (b) `WANT`-shaped "expected UNSET", treated as a THIRD value

Paste-ready, `checks/differ.py` (the only file that changes):

```python
# :124  WANT -- add as many rows as you want, spelling the third value "UNSET"
WANT = { ... "custom_function": "UNSET", "mselect": "UNSET",
         "mstack": "UNSET", "stage": "UNSET", ... }

# :411  the gap: a declared-UNSET row is NOT an answer ...
#   unset = [g for g in graphs if g not in WANT]                       # was
unset = [g for g in graphs if g not in WANT or WANT.get(g) == "UNSET"]

# :414  ... and it is NOT compared against its own spelling
#   moved = [... if g in WANT and verdict(...) != WANT[g]]
moved = [f"{g}: VERDICT={verdict(f'D1-graph-{g}.txt')} EXPECTED={WANT[g]}" for g in graphs
         if g in WANT and WANT[g] != "UNSET" and verdict(f"D1-graph-{g}.txt") != WANT[g]]
```

**What it breaks, and it is a fork with no good branch:**
- With `unset` **keeping** `WANT.get(g) == "UNSET"`, the declared `UNSET` is a **no-op** — the run
  still exits 1 (`:614`) and the row is pure documentation. Then teaching `WANT` the word bought
  nothing, and the fourteen are still unanswered.
- With `unset` **dropping** the declared-`UNSET` graphs, the run exits **0** with fourteen graphs that
  nobody compared. That is the exact "gate that exits 0 having measured nothing" this project's
  doctrine names as worse than no gate. It also makes `graphs-unset=0` a **lie in the summary**: the
  field's meaning (`:553`) is "not compared", and a declared-`UNSET` graph is still not compared.
- `PINS["graphs-unset"]` then has two meanings depending on the branch, and `corpus-figure.py` imports
  `differ.PINS` (`:77`) and would pin whichever you chose, silently.

### (c) derive `WANT` from the last run's verdicts, one-commit lag

Paste-ready, `checks/differ.py`, replacing the literal table:

```python
# :124  WANT -- built from the previous run's recorded verdicts, not typed
def _want_from_last_run():
    """Re-read runs/graphcmp/D/D1-graph-*.txt -- the last run's own verdicts."""
    import re, pathlib
    d = ROOT / "runs/graphcmp/D"
    out = {}
    for p in sorted(d.glob("D1-graph-*.txt")):
        g = p.name.removeprefix("D1-graph-").removesuffix(".txt")
        found = re.findall(r"VERDICT: [A-Z]+", p.read_text(errors="replace"))
        if found:
            out[g] = found[-1].split()[1]
    return out

WANT = _want_from_last_run()
```

**What it breaks:**
- `runs/` is **gitignored** (`.gitignore:172`; `differ.py:182`'s citation of `:144` is stale) → the
  authority is not durable, and `WANT` becomes empty-or-stale on a fresh clone. A gate whose table
  is absent is a gate that cannot run.
- A table that reads the last artifact is a **re-statement**, not an expectation — `differ.py:142`
  says so itself ("each row is a disagreement rather than a re-statement of the last artifact").
  It can then **never disagree**, so `expect-moved` is structurally 0 and the whole `RUN WRONG`
  refusal (`:595-614`) is dead, because the expectation is whatever the port emitted.
- `repro` becomes tautological: two runs are byte-compared (`:936-954`) against a table that is
  itself a byte-copy of a run.
- A regression is caught **one commit late**, and only if the lagged table is committed — which
  means the verdict of run N is a source file at commit N+1, i.e. the port's output edits the gate.

**Therefore: (a).** The fourteen land as **real `AGREE`/`DISAGREE` rows**, each earned by a run or by
the arm that makes a run meaningful.

---

## 4. The PINS that must move once the fourteen are wired (`differ.py:213-243`)

Current (at the reading above): `graphs=25`, `graphs-unset=5`, `graphs-answered=20`, `expect-moved=0`,
`graphs-agree=21`, `byte-identical=21`, `not-comparable=0`.

| pin | current | required | denominator | knowable when? |
|---|---|---|---|---|
| `graphs` | `"25"` | **`"34"`** | `len(corpus())` = 34 | **KNOWN** — function of the corpus |
| `graphs-unset` | `"5"` | **`"0"`** | 34 − 34 answered | **KNOWN** — iff all 14 get a row |
| `graphs-answered` | `"20"` | **`"34"`** | = `graphs − graphs-unset` | **KNOWN** |
| `expect-moved` | `"0"` | **`"0"`** | rows that were WRONG, of 34 | **UNKNOWABLE until a run** — it is a function of the PORT against the TABLE, and it is a zero-tolerance invariant, so it MUST read 0 or the table is wrong |
| `graphs-agree` | `"21"` | **measure, do not guess** | files among 34 whose `D1-graph-*.txt` carries `VERDICT: AGREE` | **UNKNOWABLE until a run** |
| `byte-identical` | `"21"` | **measure, do not guess** | lines in `D2-bytediff.txt` saying `BYTE-IDENTICAL`, of 34 | **UNKNOWABLE until a run** |
| `not-comparable` | `"0"` | **`"0"`** | lines in `D2-bytediff.txt` saying `NOT COMPARED` | UNKNOWABLE until a run; must be 0 |
| `stable-pairs`/`stable-failed`/`stable-differ` | `5 of 5`/`0 of 5`/`0 of 5` | unchanged | `STAB` is 5 | **KNOWN** — corpus growth does not touch `STAB` |
| `plants-disagree` | `7 of 7` | unchanged | `PLANTS` = 7 | **KNOWN** |
| `cross`/`controls`/`conflations` | `1 of 1`/`5 of 5`/`4 of 4` | unchanged | fixed tuples | **KNOWN** |
| `selfcheck`/`census-rc`/`oracle-selfcheck` | unchanged | unchanged | — | KNOWN |

**`graphs-agree` and `byte-identical` are NOT predictions.** They are functions of the port's next
run, and the doctrine (`differ.py:210-212`) exists because a pin that was a *guess* (`graphs-agree=13`
then `14` against a `22`-graph reading) once declared a correct run unhealthy. For orientation only
(do NOT pin these): WANT holds 4 `DISAGREE` (`flip`, `allred`, `cdiv`, `late`) plus the 4 no-arm
graphs predict `DISAGREE`, so `graphs-agree` lands somewhere around **34 − 8 = 26** — **and if the
task's `cdiv`/`late`-AGREE prediction is right, `flip`/`allred` + the 4 no-arm give 34 − 6 = 28.**
Two candidate numbers, and that is the proof it is a measurement and not an answer.

**Also moves, and is not a pin:** `declared()` (`:261-285`) reads `corpus()`, so wiring 14 graphs adds
**4 artifact names each** (`D1-graph-<g>`, `D2-canon-py-<g>`, `D2-canon-bend-<g>`, `D2-cmp-<g>`) —
**175 → 231** declared `.txt` artifacts. `checks/no-txt.py`'s carve-out imports this, so it grows by
the same 56. `checks/env-precond.py:327`'s fabricated-summary fallback `"graphs=25\n"` is stale prose
(it is stripped of `RECORD_KEYS` before use, so harmless, but it lies).

---

## 5. The ORDER the fourteen should land

**A graph that lands expecting `AGREE` and prints `DISAGREE` is a corpus that learned something; a
graph that lands expecting nothing is a corpus that cannot fail.** So the order is by *how much a
wrong row can teach*, and the four that cannot be made to fail go last.

**Phase 0 — the already-answered-but-suspect rows, first.** `flip`, `allred`, `cdiv`, `late` are IN
`WANT` today with `DISAGREE`. `allred`/`cdiv`/`late` were **just armed** (`disagree-gate-pin:
86cef1a76`), and the arm replaced the *reason* for their `DISAGREE` (the old reason in `differ.py:155-169`
was "the bend side emits matmul's GRAPH" — no longer true for the two that got an arm). **The task's
prediction is `cdiv`/`late` AGREE, `allred` DISAGREE; `WANT` says all three DISAGREE.** Re-run
`differ.py run` and let **`expect-moved`** adjudicate. If `cdiv`/`late` print `AGREE`, their `WANT`
rows move `DISAGREE → AGREE` in the SAME commit and `expect-moved` stays `0`. This is the cheapest
possible test of the new arms and it is the one that can actually be wrong.

**Phase 1 — the ten with a bend arm (predicted `AGREE`).** `alu`, `bit`, `bw`, `move`, `where`,
`threefry`, `mulacc`, `getaddr`, `unshard`, `wmma`. Land each with an `AGREE` row earned by a run.
A run either confirms byte-identity or fires `expect-moved` and names the field — either outcome is
information. These are the graphs whose rows **can fail**, so they belong before Phase 2.

**Phase 2 — the four with NO bend arm (predicted `DISAGREE`, HARNESS).** `custom_function`, `mselect`,
`mstack`, `stage`. **Do NOT land these with an `AGREE` row**: `rows.pick3` (`graphcmp.bend:1485`) has
no arm and falls to `g_matmul()` (`:1515`), so bend emits the matmul while py emits the real graph —
an `AGREE` row would print `DISAGREE` and be `RUN WRONG`. Land them by exactly one of:
- **(2a)** write the four bend arms (the `.agents/slop/corpusproto/PROTOCOL.md` Step-0 shape, mirrored
  node-for-node from `emit --side py --graph NAME`), then an `AGREE` row — preferred, because it makes
  the row falsifiable; or
- **(2b)** land them `DISAGREE` **with a cause**, AND add all four to `checks/disagree-gate.py`'s
  `SUBSTITUTED` tuple (`:80`) and the `NOT A ROW` `PIN` table (`:63`) — otherwise a real renderer
  difference hides behind a harness substitution, which is the defect `disagree-gate.py`'s whole
  negative-claim lane exists to catch.

Until Phase 2's four are either armed or declared, the run stays **`RUN INCOMPLETE`
(`graphs-unset ≥ 4`)** — which is the correct, honest state, and is exactly (a).

---

## Appendix — what I did NOT do, and one stale citation found

- I did **not** edit `checks/differ.py`, `runs/graphcmp/D/`, `gates/`, `AGENTS.md`, or
  `.agents/slop/graphcmp.py`/`.bend`. `checks/differ.py` is the reference; my artifact is this file
  plus `.agents/slop/wantwire/discover.py`.
- Stale citation: `differ.py:182` says `runs/` is gitignored at `.gitignore:144`; it is at
  `.gitignore:172` (`git check-ignore -v`).
- `.agents/TODO.md` has no line for this gap; I did not add one (out of my lane) — the four
  undeclared substituted graphs (`custom_function`, `mselect`, `mstack`, `stage`) are a defect worth
  a TODO.
