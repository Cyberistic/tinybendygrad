# Corpus wire: the five new graphs, the state, and the order to land them

Measured 2026-10-06 13:59:27 +0300, `HEAD` `d2cde2f2c`, no `bend` run.
**THE CORPUS IS MOVING UNDER THE MEASUREMENT** — see §0. Pinned by:

```
47a48d65f134…  .agents/slop/graphcmp.py         (mtime 13:58:00)
216a040f806c…  .agents/slop/graphcmp.bend       (mtime 13:57:40)
5808bb3c25d1…  checks/differ.py                 (mtime 12:52:05)
a86eb38da776…  checks/disagree-gate.py
```

---

## 0. THE FINDING THAT OUTRANKS THE BRIEF: it is not five, it is nine

The brief says five graphs (`threefry`, `mulacc`, `getaddr`, `unshard`, `wmma`) were authored
and are not in `WANT`. They are — but so are **four more that landed while I measured**:
`custom_function`, `mselect`, `mstack`, `stage` (`graphcmp.py` mtime 13:58:00, four new
`def g_*` at `:1552-1593`). At 13:55 the corpus was **30**; at 13:59 it was **34**.

`graphcmp.py` is not in my brief and not in my ownership; another unit is writing it. So every
number below is quoted **with the reading that produced it**, and a live run today is red on a
different `graphs=` than the one this report was written against. **A denominator read from a
file being written is a denominator of the host, not of the corpus.**

---

## 1. Current state, three numbers with denominators

| reading | `len(GRAPHS)` | `len(WANT)` | gap (GRAPHS∖WANT) | `D0-run-summary` |
|---|---|---|---|---|
| brief's premise, ~13:55 | **30** | **20** | 10 | graphs=25, unset=5, answered=20, agree=21, disagree=4, byte=21 |
| **pinned, 13:59:27** | **34** | **20** | **14** | same (a 25-graph run, stale) |

- **30/20**: the five new + the five already-unset (`alu bit bw move where`) = the gap of 10.
- **34/20**: those ten **+ `custom_function mselect mstack stage`** = the gap of 14. `WANT∖GRAPHS = ∅`.
- `D0-run-summary.txt` still reads `graphs=25`, from a run of a 25-graph corpus — it predates all
  five, let alone the four extras.

**How much `GRAPHS` and `WANT` disagree, named: by 14 at 13:59 (`alu bit bw custom_function getaddr
move mselect mstack mulacc stage threefry unshard where wmma`), of which the five in the brief are
`threefry mulacc getaddr unshard wmma`.** The instrument that prints this without a run is
`.agents/slop/want/census.py` (rc=1 now). It is named in `checks/differ.py:122` and **wired into
nothing executable.**

---

## 2. Wiring the five: `WANT` cannot express `UNSET` — **(a) is impossible, so the honest entry is (b)**

`WANT` is a verdict table (`"AGREE"` / `"DISAGREE"`). `cmd_run` (`checks/differ.py:410,413`) reads:

```python
unset = [g for g in graphs if g not in WANT]                       # membership, not a value
moved = [... for g in graphs if g in WANT and verdict(...) != WANT[g]]
```

A row spelled `"x": "UNSET"` would do **both halves wrong at once**: it removes `x` from `unset`
(the graph is now "answered") *and* `AGREE != UNSET` puts `x` in `moved` (`expect-moved` → `RUN
WRONG`). Simulated against the live logic:

```
WANT={"a":"AGREE","b":"UNSET"}, graphs=("a","b","c")
  unset = ['c']      # 'b' left unset -- what we wanted
  moved = ['b: VERDICT=AGREE EXPECTED=UNSET']
  cmd_run exit = 1
```

So **(a) — "add them as UNSET-expecting" — is not expressible in `WANT` as it stands.** The honest
choices are:

- **(b) RECOMMENDED: leave `WANT` unchanged until a run records the verdicts.** The five run anyway
  (`cmd_run` iterates `corpus()`, `:409-411`); `D1-verdicts.txt` records each as
  `EXPECTED=UNSET`, and the run exits 1 on `unset`. Read `D1-verdicts.txt`, *then* write the rows.
  This is the order the protocol's own "What a first run of a NEW graph prints" implies — step 1's
  "add a WANT row" is only writable *after* the discovery run, which the protocol elides.
- (a′) A one-line change to `differ.py` makes (a) expressible, at the cost of touching the gate:
  ```python
  unset = [g for g in graphs if WANT.get(g, "UNSET") == "UNSET"]
  moved = [f"{g}: VERDICT={verdict(f'D1-graph-{g}.txt')} EXPECTED={WANT[g]}" for g in graphs
           if g in WANT and WANT[g] != "UNSET" and verdict(f"D1-graph-{g}.txt") != WANT[g]]
  ```
  This is the only spelling that lets a row say "run it, do not compare it yet". Not my edit to make.

Per-graph, the verdict each *should* carry — **conditional on the run**:

| graph | paste-ready row | basis |
|---|---|---|
| `getaddr`, `mulacc`, `unshard`, `threefry` | `"<n>": "AGREE",` | only after `D1-verdicts.txt` prints `AGREE` (guessing 4 bare AGREEs is the `DECISION.md` §2 failure) |
| `wmma` | `"wmma": "DISAGREE",` | **predicted, not guessed** — see §5; its own bend arm documents the divergence |

---

## 3. Every count that must move — `file:line`, old → new

Measured against the pinned 34-corpus. **`graphs-disagree` is NOT a `differ.PINS` key**; the count
that must move is `len(PIN)` in `disagree-gate.py`, which is `len()`-derived and re-checked against
the summary line.

### `checks/differ.py`
| site | old | new (34-corpus) |
|---|---|---|
| `:221` `"graphs"` | `"25"` | `"34"` |
| `:221` `"graphs-unset"` | `"5"` | `"14"` unwired · `"9"` if the five wired · `"5"` if all nine |
| `:221` `"graphs-answered"` | `"20"` | `"20"` · `"25"` · `"29"` (same three cases) |
| `:233` `"graphs-agree"` | `"21"` | **UNKNOWN until the run** — `21 + (# new agreeing)`; do NOT guess |
| `:233` `"byte-identical"` | `"21"` | **UNKNOWN until the run** |
| `:233` `"expect-moved"` | `"0"` | stays `"0"` (zero-tolerance invariant) unless a guessed row is wrong |
| `:94` prose | `MEASURED: 25 declared` | stale; the corpus is 34 |
| `:195/:202/:206` `PLANTS`/`CONTROLS`/`STAB` | — | only if a new graph joins those lanes (protocol step 4); not required |

### `checks/disagree-gate.py`
| site | old | new |
|---|---|---|
| `:63` `PIN` | 4 keys | `+ "wmma": dict(row=?, fields=(?), shape=?, fault=?)` **iff** `wmma` DISAGREEs. Row/fields are read from disk, so they cannot be written until the run. `len(PIN)` — the gate's `graphs-disagree` denominator (`:146`) — goes 4 → 5. |
| `:80` `SUBSTITUTED` | `("allred","cdiv","late","matmul")` | unchanged — every new graph now HAS a bend arm (`graphcmp.bend:1349-1464`) |
| `:285` `SUBSTITUTION_ARTEFACTS` | 8 ops | unchanged unless a new graph reaches a py-only op; `wmma`'s `tc` slot is a spelling, not an op |
| `:193` negative claim | `("allred","cdiv","late")` | unchanged |

### `checks/corpus-figure.py` — nothing to move
`:224/:245` print `len(gc.GRAPHS)` (derived) and `:76-94` import `differ.PINS` (derived). **It has no
literal count.** It is the gate that goes red (§4), not a gate to edit.

### `checks/env-precond.py`
| site | old | new |
|---|---|---|
| `:327` fallback | `"graphs=25\n"` | `"graphs=34\n"` (only read when the summary is absent — a stale default, protocol step 2) |

### `checks/graphcmp-census-audit.py`
`:76 "matmul"`, `:86 ("lin","loop","gate")` — its own census probes, **not** the corpus size; not
directly affected (agrees with `corpusproto/REPORT.md`).

---

## 4. Scratch proof (`.agents/slop/corpuswire/tree/`) — corpusproto's "2" **reproduced**, then bounded

The tree holds copies of `checks/differ.py`, `checks/corpus-figure.py`, and a
`differ_wantdummy.py` (the task's "add ONE dummy to `WANT`"); `tree/proof.py` drives the **real**
`corpus-figure.run_health()` on a synthetic summary inside a `TemporaryDirectory` — **no `bend`,
no persisted `.txt`**. `tree/checks/differ.py --help` exits 0 (a differ path that needs no bend).

```
S0  today:     30/20/10  RED: graphs=30 (expected 25); graphs-unset=10 (expected 5)          -> 2
S1  +1 graph, no WANT    31/20/11  RED: graphs=31 (…25); graphs-unset=11 (…5)                  -> 2   <-- corpusproto
S2  +1 graph + WANT row  31/21/10  RED: graphs=31 (…25); graphs-unset=10 (…5); answered=21(…20) -> 3
WANT-only dummy 'dummygraph' -> in-WANT-not-corpus, RED
LIVE census:  GRAPHS=34  WANT=20  UNCOMPARED=14  -> RED before any bend run
```

- **REPRODUCED: `corpusproto`'s "2 pin mismatches" is exact for S1** — the same two keys,
  `graphs` and `graphs-unset`; `graphs-answered` matches because `(n+1)-(u+1) = n-u`.
- **REFUTED in scope:** the "2" is a property of leaving the new graph *out* of `WANT`. Add its
  `WANT` row (the protocol's step 1) and it is **3** — `graphs-answered` joins. corpusproto's
  `proof.py:90-95` hard-codes the no-WANT-row case and never measures the step-1 case.

### Which gate goes red FIRST
1. **Before any run, no bend needed:** `.agents/slop/want/census.py` → rc=1, 14 `UNCOMPARED`.
   **And it is wired into nothing** (only cited in a comment). This is the earliest refusal.
2. **At run time:** `cmd_run` exits 1 on non-empty `unset` (`differ.py:613`).
3. **After the run:** `corpus-figure.py` `run_health()` → `RUN HEALTH : **FAILED**` on the stale
   pins.

### The dangerous state, measured live
`DEV=CPU .venv/bin/python checks/corpus-figure.py` **exits 0 and prints**
```
graphs declared   : 34
RUN HEALTH        : OK -- 17 of 17 pins green (… `graphs=25` …)
```
**The health gate corroborates the artifact, not the corpus, so it is green over a corpus it
declares is 34.** `corpus-figure.py:12`'s own docstring still says "25 graphs" and `:234`'s
message still says "the 22 GRAPH DEFINITIONS". A run that is 9 graphs behind its corpus still
reads `OK`.

---

## 5. Order of the five, and which lands `DISAGREE`

The bend-side arms exist for all five (`graphcmp.bend:1349-1464`, `rows.pick3:1459-1463`, hash
`216a040f…`). Their own header (`:1339-1344`) says each was **mirrored node-for-node off
`emit --side py`**, with measured node counts `threefry 12, mulacc 10, getaddr 2, unshard 8,
wmma 11`.

**Most likely first-run `DISAGREE`: `wmma` — and its own arm says so.** `graphcmp.bend:1411-1416`:
> the py arg's FOURTH slot is `None` and renders `N`; the port's `AWmma.tc` … has no `Maybe`
> (`ops.bend:1197`), so an absent `tc` renders `n()` … only that slot disagrees, and it is a PORT
> SPELLING GAP (the same class as `flip`'s `tuple[bool]`).

So `wmma` is a *predicted* `DISAGREE` (like `flip` was the only predicted row today), the other
four are `AGREE`-predicted transcriptions. Recommended land order, each as its own commit so a red
pin names one graph:

1. **`getaddr`** — 2 nodes, hand-written `UOp`, no `Tensor`, no renderer.
2. **`mulacc`** — 10 nodes, hand-written `UOp(Ops.MULACC)`, no renderer.
3. **`unshard`** — 8 nodes, `AxisType.DEVICE` range, renderer-independent.
4. **`threefry`** — 12 nodes, `uint64` output.
5. **`wmma` LAST** — the known `DISAGREE`; it needs a `disagree-gate.PIN["wmma"]` row (read off the
   run), and the two-commit rule needs that row *with* the row's commit, so it cannot lead.

**A graph that lands expecting `AGREE` and prints `DISAGREE` is a corpus that learned nothing; a
graph that lands expecting nothing is a corpus that cannot fail** — which is the state of all
five (and the four extras) right now, and the reason `cmd_run` exits 1.

*(If the four extras also get arms, they land the same way; today `graphcmp.bend` has **no** arm for
`custom_function mselect mstack stage`, so bend defaults them to `g_matmul()` and they will print a
disagreement that is the dispatcher's, not the port's — the exact fault `graphcmp.bend:1335-1337`
warns about.)*

---

## 6. Paste-ready text (I did not edit any of these)

### `checks/differ.py` — `WANT` (`:124`)
**Commit 1: no change.** The five run and record `UNSET`; read `D1-verdicts.txt` first. Commit 2,
once the verdicts are recorded:
```python
    "allred": "DISAGREE", "cdiv": "DISAGREE", "late": "DISAGREE",
    # the five new graphs, verdicts READ OFF `D1-verdicts.txt`, never guessed:
    "getaddr": "AGREE", "mulacc": "AGREE", "unshard": "AGREE", "threefry": "AGREE",
    # `wmma` DISAGREES on the WMMA arg's FOURTH slot: py's `None` renders `N`, the port's
    # `AWmma.tc` has no `Maybe` (`ops.bend:1197`) and renders `n()`. Stated in the bend
    # arm itself, `graphcmp.bend:1411-1416` -- the `flip` class, a SPELLING gap.
    "wmma": "DISAGREE",
}
```

### `checks/differ.py` — `PINS` (`:221`), wired corpus = 34, five wired
```python
    "graphs": "34", "graphs-unset": "9", "graphs-answered": "25",
```
(Leave unwired: `"14"`/`"20"`. If the four extras are wired too: `"5"`/`"29"`.)

### `checks/differ.py` — `PINS` (`:233`), AFTER the run
```python
    "graphs-agree": "<21 + #new agreeing>", "byte-identical": "<21 + #new byte-identical>", "not-comparable": "0",
```
Do not fill these from this report; fill them from `D0-run-summary.txt` the run writes.

### `checks/disagree-gate.py` — `PIN` (`:63`), iff `wmma` DISAGREEs
```python
  "wmma":  dict(row=<first disagreeing row>, fields=("arg",), shape="WRONG VALUE", fault="PORT"),
```
`shape` is the PIN author's call: the 4th `arg` slot is a present field whose *spelling* differs
(`"WRONG VALUE"`) or an absent value the port cannot spell (`"WRONG SHAPE"`) — the arm itself
(`graphcmp.bend:1414-1416`) calls it a spelling gap.
`row`/`fields` cannot be written before the run: the gate recomputes them from
`D2-canon-{py,bend}-wmma.txt` on every invocation (`:132-136`). `len(PIN)` → 5 is then what makes
the summary's `graphs-disagree=5` check (`:146`) pass.

### `checks/env-precond.py` (`:327`)
```python
        real = SUMMARY.read_text() if SUMMARY.exists() else "graphs=34\n"
```

### `checks/differ.py` (`:94` prose)
`MEASURED: 25 declared` → `MEASURED: 34 declared` (or drop the number — a prose count is the
stale literal class this whole exercise is about).
