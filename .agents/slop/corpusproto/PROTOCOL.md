# Protocol: Adding one graph to the corpus

**Apply in order. Each step names the file and the exact change.**

---

## Step 0 — Write the graph definition

**File:** `.agents/slop/graphcmp.py`

1. Add a `def g_newname(dev=None) -> list[UOp]:` function before the `GRAPHS` dict (use a nearby graph as template).
2. Add `"newname": g_newname` to the `GRAPHS` dict (line 1471).
3. Run `bend diff --graph newname` once to verify it emits something.

**Denominator check after this step:** `WANT` has no row for it, `PINS` still say 25/5/20.

---

## Step 1 — Add the expectation (WANT row)

**File:** `checks/differ.py`

1. Add `"newname": "AGREE",` (or `"DISAGREE"`) to the `WANT` dict at line 124.  
   **If AGREEs:** put it with the AGREE group.  
   **If DISAGREEs:** put it with the DISAGREE group and add a comment explaining why.

**Denominator check:** `len(WANT)` is now 21 (or more). The `unset` computation at `:410` will exclude the new graph from `unset`.

---

## Step 2 — Update PINS (corpus-level counts)

**File:** `checks/differ.py`, line 221

Change the first three pins to reflect the new corpus size:

```python
    "graphs": "26",                  # was 25
    "graphs-unset": "5",             # was 5 (or 6 if you didn't add a WANT row)
    "graphs-answered": "21",         # was 20
```

**If the new graph takes an existing unset graph's slot:** `graphs-unset` drops by 1.

**File:** `checks/env-precond.py`, line 327 (fallback default — only needed if the summary is ever missing)

```python
        real = SUMMARY.read_text() if SUMMARY.exists() else "graphs=26\n"
```

---

## Step 3 — Run and re-pin live-run counts

Run `differ.py run`:
```sh
.venv/bin/python checks/differ.py run
```

Then update the live-run pins in `checks/differ.py`, line 233:

```python
    "graphs-agree": "22",           # was 21 — new graph contributes
    "byte-identical": "22",         # was 21 — new graph contributes
    "not-comparable": "0",          # stays 0
```

(The specific `graphs-agree`/`byte-identical` values depend on what the new graph produced.)

---

## Step 4 — Optional: PLANTS, CONTROLS, STAB

**Only if the new graph needs these lanes.**

**File:** `checks/differ.py`

- `PLANTS` (line 195): add `("newname", "newname")` if the graph has a plant.  
- `CONTROLS` (line 202): add `"newname"` if the graph should be a control.  
- `STAB` (line 206): add `("newname", ())` if the graph needs a stability pair.

Each addition changes `declared()` and the artifact count.

---

## Step 5 — If the graph DISAGREES

**File:** `checks/disagree-gate.py`

- `PIN` dict (line 63): add `"newname": dict(row=N, fields=(...), shape="...", fault="...")`.  
- `SUBSTITUTED` (line 80): add `"newname"` if the bend side has no fixture.  
- `SUBSTITUTION_ARTEFACTS` (line 285): add py-only ops if they appear.  
- `CITES` (line 83): add source citations for the diagnosis.  
- `lane_citations` (line 193): add the name to the negative claim if applicable.

---

## Step 6 — Run all gates

```sh
.venv/bin/python checks/differ.py run
.venv/bin/python checks/disagree-gate.py
.venv/bin/python checks/corpus-figure.py
```

All three must exit 0.

---

## Two-commit rule

| Commit | Contains | Exits |
|---|---|---|
| 1 | steps 0-1 (graph + WANT but NOT re-pinned PINS) | `differ.py run` exits **1** (pin mismatch); artifacts are inspectable |
| 2 | steps 2-6 (PINS updated, gates all green) | `differ.py run` exits **0**; all gates pass |

A graph that DISAGREES needs its `disagree-gate.py` changes in commit 1 (so the gate's author knows about it) and its pins re-measured in commit 2.

---

## What a first run of a NEW graph prints

```
graphs=26
graphs-answered=21
graphs-unset=5
```

The `D1-verdicts.txt` will list the new graph as:

```
newname: VERDICT=AGREE EXPECTED=UNSET -- RUN AND RECORDED, NOT COMPARED: an AGREE and nobody has said so -- a bookkeeping gap, not a known fault
```

The run exits 1 because `unset` is non-empty (if no WANT row) or because PINS mismatch.