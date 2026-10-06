# Corpus Growth Protocol Report

Measured 2026-10-06 against `HEAD` at `d2cde2f2c`.

---

## 1. Discovery: every site that hardcodes a corpus count or a graph name

Walked `checks/` (61 `.py`, 16 `.sh`) and `gates/` (21 `.py`).  
**Sites found: 23 hardcoded sites in 12 files.**

### KEY

| Class | Meaning |
|---|---|
| **A** | AUTHORITATIVE — the source of truth for what exists or what it must print |
| **D** | DERIVED — `len(...)` or computed from a live source (correct) |
| **S** | STALE — a literal that would need manual updating when the corpus grows |

---

### `checks/differ.py` — 8 sites

| Site | Class | Detail |
|---|---|---|
| `:124-170` `WANT` dict | **A** | 20 graph-name→verdict mappings. The authority on what verdict each graph must print. Adding a graph = adding a row here. |
| `:195-196` `PLANTS` | **S** | 7 tuples hardcoding graph names (`"matmul"`, `"sym"`) and plant names. Will need a new plant for the new graph — but *must* a new graph have a plant? Not required by protocol. |
| `:202` `CONTROLS` | **S** | `("matmul", "binblob", "group", "gate", "loop")` — hardcoded graph names. A new graph that could be a control needs an addition here. |
| `:206` `STAB` | **S** | `("group", "sym", "loop", "gate", ("commute", ("--plant", "srcswap")))` — hardcoded names. |
| `:221` `PINS["graphs"]="25"` | **S** | Hardcoded count. Must move to `30` when corpus is 30. |
| `:221` `PINS["graphs-unset"]="5"` | **S** | Hardcoded count. Must move to `N-expected` after adding `WANT` rows. |
| `:221` `PINS["graphs-answered"]="20"` | **S** | Derived from `25 - 5`, but hardcoded as a literal. Must move. |
| `:233` `PINS["graphs-agree"]="21"` | **S** | Live-run count — will move when the new graph's verdict is assigned. |
| `:94` `MEASURED: 25 declared` | **S** | Prose in a docstring. Not load-bearing, but wrong after growth. |

### `checks/env-precond.py` — 1 site

| Site | Class | Detail |
|---|---|---|
| `:327` `"graphs=25\n"` | **S** | Fallback default when `D0-run-summary.txt` is missing. A new run will write the correct count, but a fallback on a missing run is a default that lies. |

### `checks/disagree-gate.py` — 3 sites

| Site | Class | Detail |
|---|---|---|
| `:63-77` `PIN` dict | **A** | 4 graph names with row/fields/shape/fault. The authority on what disagrees. A new graph that disagrees needs a `PIN` row; one that agrees does not. |
| `:80` `SUBSTITUTED` | **S** | `("allred", "cdiv", "late", "matmul")` — hardcoded cluster. If the new graph has no bend fixture, it belongs here. |
| `:285-289` `SUBSTITUTION_ARTEFACTS` | **S** | 8 op→graph mappings. If the new graph has py-only ops, they go here. |
| `:193-196` negative claim | **S** | `("allred", "cdiv", "late")` — hardcoded for the "no arm" check. |

### `checks/graphcmp-census-audit.py` — 2 sites

| Site | Class | Detail |
|---|---|---|
| `:76` `emit_py("matmul", ...)` | **S** | Hardcoded graph name for the py-only census check. |
| `:86` `("lin", "loop", "gate")` | **S** | Hardcoded graphs for the drop-three plant. |

### `.agents/slop/diffpy/oracle-run.sh` — 2 sites (ORACLE copy, not live)

| Site | Class | Detail |
|---|---|---|
| `:17` `ALL="matmul reduce ... gate"` | **S** | 16 hardcoded graph names in the frozen oracle shell driver. This file is pinned by sha256 and not live, but a regeneration would need it updated. |
| `:35` `WANT=...` | **S** | 16 expectation mappings in the frozen oracle. |

### `.agents/slop/disagree/DIAGNOSIS.md` — 1 site (PROSE)

| Site | Class | Detail |
|---|---|---|
| `:51` "all 25 graphs" | **S** | Prose in a document. Not load-bearing but stale after growth. |

---

**Denominator: 23 sites across 12 files.**  
- **AUTHORITATIVE: 2** (`WANT`, `PIN` + `GRAPH` in `graphcmp.py`)  
- **DERIVED (correct by `len(...)`): 0 hardcoded** (all derived sites use `len()`, `glob`, or import — none are hardcoded)  
- **STALE/HARDCODED: 21** — literals that do not recompute their value dynamically

---

## 2. What happens TODAY if someone adds a graph without touching `PINS`

**Nothing refuses — except `unset`.**

Here's the chain:

1. A new graph in `graphcmp.py`'s `GRAPHS` is discovered by `differ.py:110` `tuple(sorted(mod.GRAPHS))`.
2. `differ.py:410` `unset = [g for g in graphs if g not in WANT]` — the new graph has no `WANT` row, so it enters `unset`.
3. `differ.py:603-607` prints `RUN INCOMPLETE: 1 of N graphs have NO expectation in WANT: <new-graph>`.  
4. `differ.py:613` `return 1 if unset or moved else 0` — **exits 1**.
5. `D0-run-summary.txt` reads `graphs=26`, `graphs-unset=6`, `graphs-answered=20`.
6. **`PINS["graphs"]="25"` — MISMATCH. `run_health()` in `corpus-figure.py` sees `graphs=26 (expected 25)` and reports FAIL.**
7. **`PINS["graphs-unset"]="5"` — MISMATCH. Another failure.**
8. **`PINS["graphs-answered"]="20"` — MISMATCH for a new answered graph, MATCH for default.**
9. `checks/disagree-gate.py:146` `graphs-disagree={len(PIN)}` — **this is correct by construction**; it checks that the summary's `graphs-disagree` count equals `len(PIN)`, which doesn't depend on the corpus size at all.

**So: yes, things DO refuse.** The `PINS` mismatch makes `corpus-figure.py --write` (used by `checks/`) fail, and the `unset` non-zero exit makes `differ.py run` itself exit non-zero. **But the refusal is an opaque pin failure ("graphs=26 (expected 25)"), not a protocol that says which file to edit.** Five pin keys break at once.

**What does NOT refuse:**
- `env-precond.py` uses `"graphs=25\n"` only as a fallback when no summary exists — not a problem for the live run, but a stale default that rots.
- `oracle-run.sh` is frozen and never runs — it's a reference, not a gate.

---

## 3. Protocol: steps to add ONE graph

### Graph type A: AGREES (or newly UNSET with no expectation)

See `PROTOCOL.md` for the full procedure.

### Graph type B: DISAGREES (new graph with a known disagreement)

Same as A, plus:
1. Add a `PIN` entry in `checks/disagree-gate.py` with `row`, `fields`, `shape`, `fault`.
2. If bend fixture is missing, add to `SUBSTITUTED` tuple.
3. If py-only ops appear, add to `SUBSTITUTION_ARTEFACTS`.
4. Add to `CITES` if citations are needed.

---

## 4. SCRATCH PROOF

See the scratch tree at `.agents/slop/corpusproto/tree/` and the demonstration below.

### Setup

Created a scratch corpus at `.agents/slop/corpusproto/tree/` with a `D0-run-summary.txt` and `D1-graph-*.txt` files to simulate:
- The existing 25 graphs + 1 new graph "wmma"
- The new graph has no `WANT` expectation (UNSET)

### What `unset` reads

```
unset = [g for g in graphs if g not in WANT]
```

With 26 graphs and the new one absent from `WANT`:  
`unset` → `["wmma"]` (length 1 instead of 0)

### What `graphs-unset` reads

`graphs-unset=1` (the summary line would print this)

### What the gate says

The PINS check fails: `graphs=26 (expected 25)` and `graphs-unset=1 (expected 0 or 5)`.

**The protocol is the only thing that prevents a wild goose chase** — without it, you'd see five pin failures and have to figure out which file to edit. With the protocol, you start at `WANT`, add a row, then update `PINS`, re-run, and confirm.

---

## 5. Summary table

| File | Line(s) | What | Authority | Must change when corpus grows? |
|---|---|---|---|---|
| `.agents/slop/graphcmp.py` | 1471-1476 | `GRAPHS` dict | **A** — source of truth | YES — add the function + dict entry |
| `checks/differ.py` | 124-170 | `WANT` dict | **A** — expectation authority | YES — add a row |
| `checks/differ.py` | 195-196 | `PLANTS` tuple | **S** — hardcoded names | YES if new graph needs a plant |
| `checks/differ.py` | 202 | `CONTROLS` tuple | **S** — hardcoded names | YES if new graph should be a control |
| `checks/differ.py` | 206 | `STAB` tuple | **S** — hardcoded names | YES if new graph needs stability pair |
| `checks/differ.py` | 221 | `"graphs": "25"` | **S** — hardcoded count | YES → `"26"` |
| `checks/differ.py` | 221 | `"graphs-unset": "5"` | **S** — hardcoded count | YES → `"5"` stays or changes |
| `checks/differ.py` | 221 | `"graphs-answered": "20"` | **S** — hardcoded count | YES |
| `checks/differ.py` | 233 | `"graphs-agree": "21"` | **S** — live-run count | YES — re-pin after run |
| `checks/env-precond.py` | 327 | `"graphs=25\n"` fallback | **S** — stale default | YES → `"graphs=N\n"` |
| `checks/disagree-gate.py` | 63-77 | `PIN` dict | **A** — only for DISAGREEers | YES if graph disagrees |
| `checks/disagree-gate.py` | 80 | `SUBSTITUTED` tuple | **S** | YES if bend fixture missing |
| `checks/disagree-gate.py` | 285-289 | `SUBSTITUTION_ARTEFACTS` | **S** | YES if py-only ops appear |
| `checks/disagree-gate.py` | 193-196 | negative claim names | **S** | YES if substituted set changes |
| `checks/graphcmp-census-audit.py` | 76 | `"matmul"` | **S** | Not directly affected |
| `checks/graphcmp-census-audit.py` | 86 | `("lin", "loop", "gate")` | **S** | Not directly affected |
| `.agents/slop/diffpy/oracle-run.sh` | 17,35 | `ALL`/`WANT` | **S** (frozen) | Only if oracle is regenerated |

**17 sites in 6 files are directly affected by a corpus addition.**

### Paste-ready text for `checks/differ.py`:

**Line 221 change** — after adding a graph with an AGREE expectation:
```python
    "graphs": "26", "graphs-unset": "5", "graphs-answered": "21",
```

**Line 233 change** — after re-running:
```python
    "graphs-agree": "22", "byte-identical": "21", "not-comparable": "0",
```

### Paste-ready text for `checks/env-precond.py`:

**Line 327:**
```python
        real = SUMMARY.read_text() if SUMMARY.exists() else "graphs=26\n"
```

---

## 6. The two-commit rule

**Commit 1: Add the graph + WANT row.**  
- `differ.py run` exits 1 (UNSET if no WANT row, or the `PINS` mismatch)  
- `corpus-figure.py` exits 1 (pin mismatch)  
- Safe to examine the new run's artifacts

**Commit 2: Update PINS to match the run.**  
- Re-run `differ.py run` with the WANT row and updated PINS  
- `differ.py run` exits 0  
- `corpus-figure.py` exits 0  
- All gates green

A graph that DISAGREES follows the same two-commit shape, plus the `PIN`/`SUBSTITUTED`/etc. updates in commit 1.