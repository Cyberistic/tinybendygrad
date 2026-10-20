# THE `--selftest` LANE'S TWO CAPTURES — WHAT IT EXACTLY NEEDS

Quoted from `checks/rn-gate.py` at HEAD `9574a3e2a`. Line numbers are that file's.

HEAD at the time of writing: `9574a3e2aa2508e400dc9931d01399ee9ba30226`
(HEAD MOVED during this investigation: it was `d9dcd0fe2ffb6559beb13e67f083021fa0a6748c` at
`2026-10-20T20:41:53Z`, the first reading. The tree is a moving target; every fact below was
re-verified at the second HEAD and is quoted with the HEAD it was measured at.)

---

## 0. THE TWO NAMES, AND WHERE THEY MUST LIVE

```
400:  for _cap in ("rn-port.txt", "rn-orc.txt"):
401:    if not (HERE / _cap).is_file():
402:      refuse(f"selftest input absent: {HERE / _cap} -- the captured pair this lane judges was never "
403:             f"committed (0 commits touch it), so there is nothing to restore and no `git show` "
404:             f"recovers it. Capture it with `--oracle-stdout` (an oracle-side capture IS committed "
405:             f"elsewhere) or leave this lane PERMANENTLY REFUSED.")
406:  live = (HERE / "rn-port.txt").read_text()
407:  orc = (HERE / "rn-orc.txt").read_text()
```

`HERE` is `checks/` (`HERE = pathlib.Path(__file__).resolve().parent`, `:65`). So the two inputs
are **`checks/rn-port.txt`** (the PORT lane) and **`checks/rn-orc.txt`** (the ORACLE lane), read
as raw TEXT.

**THE REFUSAL'S CLAIM IS HALF FALSE, AND THE FALSE HALF IS THE FINDING.** "0 commits touch it, so
there is nothing to restore" is TRUE OF THE TWO *NAMES* and FALSE OF THE TWO *CAPTURES*: both
captures exist in the tree, tracked, and byte-verified against the md5s this same file records
(§5). What does not exist is a file at those two names.

**AND THE TWO NAMES ARE ILLEGAL IN THIS TREE.** `checks/no-txt.py` (`:280-308`) reports every
`.txt` the project owns, and its five carve-outs are `checks/differ.py`, `.agents/slop/figure2/plant.py`,
`.agents/slop/txtexec/rename.py`, `.agents/slop/skipexit/repro.py` and `checks/dup-census.py`'s own
cache. **`checks/rn-port.txt` and `checks/rn-orc.txt` are in none of them**, so committing them
under the names the gate hard-codes turns `checks/no-txt.py` RED. The restoration must therefore
RENAME the gate's two inputs to a non-`.txt` extension in the same commit (§6).

---

## 1. WHAT THE GATE DOES WITH THE TWO TEXTS

`judge(port_txt, orc_txt)` (`:321-362`) is the only consumer. It:

1. calls `reshape()` on each side — GUARD 0, the coverage delta, BEFORE any value is compared;
2. calls `rows_strict()` on each side — the NAME → VALUE map;
3. compares `set(pr) & set(orr)` — the **GATED** rows. `stray` = oracle-only names, `ghost` =
   port-only names;
4. for each gated row, compares `split_py(value)[0]` — i.e. the VALUE with the `py=` column
   stripped off — and counts `agree` / `disagree`.

### 1a. THE READER: `logical_rows` (`:128-153`) then `row_strict` (`:156-197`)

- A capture is a sequence of PHYSICAL lines. Blank lines are skipped.
- A LOGICAL row is a group of physical lines folded by **BRACKET DEPTH** over `[` / `]`
  (`DEPTH = {"[": 1, "]": -1}`, `:100`), plus ONE hand-written case: a depth-0 line whose first
  non-space text is `py=` continues the row above it (the port's five wrapped rows,
  `render.bend:2809-2819`).
- For a logical row's text: `head, sep, tail = text.rpartition(SEP)`. If `SEP` is absent,
  `probe` is the WHOLE text; if present, `probe` is everything before the LAST `]   py=[`.
- Then the boundary is found, in this order:
  - `ROW_OPEN = " = ["` — the PORT's spelling, the `=` preceded by a space;
  - `"=["` — the ORACLE's spelling, the `=` glued.
  - A candidate is a DEPTH-0 `=` whose remainder, after spaces, opens a bracket.
  - **Exactly one candidate** → the row is `(name = probe[:i].strip(), value = probe[i+1:].strip())`.
  - **More than one** → REFUSED, not resolved. **Zero** → fall back to the first depth-0 `=`;
    if there is none → REFUSED.

### 1b. THE CONSTANTS

```
 98: SEP = "]   py=["      # `py_row`'s own three-space literal (render.bend:2148)
 99: ROW_OPEN = " = ["     # and its own name/value boundary, same line
```

**`SEP` IS NOT A REQUIREMENT OF THE CAPTURE.** It is the gate's *fast path* for splitting a row
into "value" and "`py=` column". A row without it is read with `probe = text` and the boundary
search still succeeds. **MEASURED**: the committed oracle capture has 37 of its 80 rows carrying
`"]   py=["` and 43 not, and the gate's own reader returns **80 names and 0 refusals** on it.

### 1c. THE FIELDS, AND HOW MANY

A row carries **three** things: a NAME, a VALUE, and a `py=` literal column.

- The compared field is the **VALUE**: the text after the boundary `=`. It therefore **includes the
  leading `[`** and, on a row that HAS the SEP, **excludes the trailing `]`** (the SEP consumed it)
  and excludes the whole `py=[...]` column.
- The `py=` literal column is **not compared** on a row that has the SEP (it was partitioned off
  before the value was cut), and **is** part of the compared value on a row that does not have it
  (it sits inside the value). Consequence: `judge`'s `stale` counter is **empty on this pair**,
  because `split_py` never finds a SEP inside a value.
- **THE NUMBER OF ROWS IS NOT FIXED BY THE GATE.** It compares whatever the two sides share. The
  fixed numbers are the *pair's* (measured, §5): 140 port lines / 80 port logical rows of which
  11 are `rnd_*`, 124 oracle lines / 80 oracle logical rows, 80 gated, 75 agree, 5 disagree.

---

## 2. THE FOUR LANES, AND WHAT EACH DEMANDS OF THE PAIR

```
417:  lanes = {
418:    "base": (live, orc),
419:    "value": (plant_value(live, "pyrender const")[0], orc),
420:    "shape": (plant_shape(live, [("pyrender const", "pyrender co=nst")])[0],) * 2,
421:    "collide": (plant_shape(live, [("pyrender const", "pyrender ast"),
422:                                   ("pyrender cast", "pyrender ast")])[0],) * 2,
423:  }
424:  want = {"base": (True, n0), "value": (True, n0 + 1), "shape": (True, 0), "collide": (True, 0)}
```

`n0 = len(base["disagree"])` is **MEASURED at runtime** (`:409`), not typed. `good` is
`bool(r["bad"]) == want_broken and len(r["disagree"]) == want_dis` (`:429`).

| lane | demand on the PORT capture | demand on the ORACLE capture |
|---|---|---|
| `base` | `bad` non-empty and `disagree == n0` (its own number) | must SHARE names with the port, else "0 gated rows" |
| `value` | a row named **`pyrender const`**, matched by `^pyrender\ const\s*=` (`plant_value`, `:288`), whose value the plant can change | `pyrender const` must be in the ORACLE too, else the plant creates a GHOST and `disagree` does not move |
| `shape` | a row named `pyrender const` followed by **SPACES** then `=` — `plant_shape`'s regex is `^` + re.escape(old) + `" +(?==)"` (`:307`) | NONE — the `shape` and `collide` lanes feed the PORT text to BOTH sides (`) * 2`) |
| `collide` | a row named **`pyrender cast`**, same regex | NONE — same reason |

So the two hard requirements the PORT capture must meet **beyond** being a well-formed capture are:

- **`pyrender const`** — present, name spelled exactly, and the line is `pyrender const` + one-or-more
  SPACES + `=`. (The port pads its names to a column: `pyrender const    = [`. The oracle glues
  the boundary: `pyrender const=[`, which is why the `shape`/`collide` plants are applied to the
  PORT text only.)
- **`pyrender cast`** — present, same spelling rule.

And the ORACLE capture must contain **the same row NAMES** as the port, or the gate compares
nothing.

---

## 3. THE PORT CAPTURE'S SHAPE (what `tinybendygrad/uop/render.bend` prints)

`py_row` at `tinybendygrad/uop/render.bend:2048-2049`:

```
2049:  IO.print(String.concat([nm, " = [", pyrender(...), "]   py=[", py, "]"]))
```

so a `py_row` row is

```
<padded name><spaces> = [<value, may contain newlines>]   py=[<py value>]
```

and the VALUE may contain newlines, so **one logical row is 2-7 physical lines** and the SEP sits
on the row's FIRST physical line, never the last.

The port also prints, outside `py_row`:
- `rnd_row` (`:2586-2587`): `nm + "="` GLUED, F1, **no** `py=` column at all — 11 such rows
  (`rnd_rows` at `:2589-2602`: `rnd_param_named` … `rnd_unclaimed`);
- `sint_show 2**31-1` / `-3` / `-2**31`: `] py=` — ONE space;
- `f32_repr 3.0` / `1e30` / `0.1`: `]     py=` — FIVE spaces;
- five `arg_repr` rows: the `py=` column on its OWN LINE (the hand-written wraps) — the only case
  `logical_rows` special-cases.

## 4. THE ORACLE CAPTURE'S SHAPE (what `checks/render-gate-oracle.py --gate` prints)

`emit_gate` at `checks/render-gate-oracle.py:257-281` prints, per name class:

| name class | spelling | rows |
|---|---|---|
| `_PY_ROW = ("pyrender ", "pyr_")` | `name=[value]   py=[py]` — THREE spaces, bracketed | 37 |
| default | `name=[value]   py=py` — THREE spaces, bare | 32 |
| `_IO1` (3 `sint_show`) | `name=[value] py=py` — ONE space | 3 |
| `_IO5` (3 `f32_repr`) | `name=[value]     py=py` — FIVE spaces | 3 |
| `_SPLIT` (5 `arg_repr`) | `name=[value]` — **NO `py=` column at all** | 5 |

and the boundary is **GLUED**: `name=[value]`, never `name = [value]`.

**The `py=` column's spelling varies BY DESIGN, per name class, and the gate's reader reads all
five shapes.** The 43 oracle rows without the gate's three-space bracketed SEP are not malformed
and not a different artifact — they are rows the oracle's own printer spells a different way.

## 5. THE PAIR, MEASURED (the numbers the gate's own docstring records)

`checks/rn-gate.py:44-45`:

```
44: nir_llvmir.  MEASURED: port stdout md5 `302944bb48a32379`, oracle stdout md5
45: `642f9770c558df0f1be03a8f67ac997e`; 140 lines against 124.
```

and `.agents/slop/eq/REPORT.md:26-27`:

```
| `uop/render.bend` port                   | 80 | **0** | 97 | 140 | **43** |
| `xd1/render-gate-oracle.py --gate`       | 80 | **0** | 85 | 124 | **39** |
```

MEASURED at HEAD `9574a3e2a`, with the gate's OWN readers (`rows_strict`, `judge`) and the tree's
own `rebase-gate.py:rows()`:

| quantity | port | oracle | source of the expectation |
|---|---|---|---|
| md5 of the capture | `302944bb48a32379f3a13d857893ec69` | `642f9770c558df0f1be03a8f67ac997e` | `rn-gate.py:44-45` |
| physical lines | 140 | 124 | `rn-gate.py:45` |
| logical rows (`rows_strict`) | 91 (80 shared + 11 `rnd_*`) | 80 | `eq/REPORT.md:26-27` |
| names containing `=` | 0 | 0 | `eq/REPORT.md:26-27` |
| distinct keys of `rows()` (the shipped reader) | **97** | **85** | `eq/REPORT.md:26-27` |
| lines `row()` accepts | **140** | **124** | `eq/REPORT.md:26-27` |
| rows no name can address | **43** | **39** | `eq/REPORT.md:26-27` |
| continuation lines | **49** | **44** | `eq/REPORT.md` §1 |
| refusals from the gate's own reader | **0** | **0** | — |

and over the pair: **gated 80, agree 75, disagree 5**, the five being
`arg_repr AKern`, `arg_repr AParam1`, `arg_repr AParam2`, `arg_repr AParam3`, `arg_repr AProgr` —
the port's hand-written `py=` wraps, which the oracle's `_SPLIT` class does not print. Stray: 0.
Ghost: the 11 `rnd_*` names. This is the pair `rn-gate.py:374-385` describes:

> "this lane's real pair already disagrees on 5 rows (the hand-written `py=` wraps)"

## 6. WHAT RESTORING THE LANE WOULD TAKE (not done here — this unit may only write under
##    `.agents/slop/rnpair/`)

1. **Two new tracked files under `checks/`, renamed off `.txt`** (else `checks/no-txt.py` goes
   red): the port capture and the oracle capture, at the byte content measured in §5.
2. **A rename of the gate's two declared input names** — `checks/rn-gate.py:400` (the `for _cap in`
   tuple) and `:406-407` (the two `read_text()` calls) — from `.txt` to whatever the new files are
   called, plus the refusal message at `:402-405`.
3. **Nothing else.** The lane's readers, the four plants and the `want` table are unchanged; the
   pair was measured against the gate's own code.
4. **SEPARATELY, for the LIVE lane** (`:468-473`): the refusal is caused by a **stale path**, not
   by a missing artifact. `ORACLE = [".agents/slop/xd1/render-gate-oracle.py", "--gate"]` (`:74`)
   names a path that **0 commits in the whole history ever touched**; the script is committed at
   **`checks/render-gate-oracle.py`** and has been since `3f0e70ff1` (2026-10-04). One path change
   in `ORACLE` fixes the *reference* — but the script then **cannot run**, see `REPORT.md` §4.
