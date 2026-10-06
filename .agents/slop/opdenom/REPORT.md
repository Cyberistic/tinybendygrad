# THE `61 of 77` DENOMINATOR OVERSTATES THE GAP BY A THIRD

Artifacts beside this file: `run.out` (the oracle under planted corpora), `audit.out` (the
owned audit, six states). Both are reproducible; the commands are at the bottom.

**VERDICT.** `77` is `len(list(Ops))`, every member of `tinygrad/uop/__init__.py`'s enum.
**Seven of the 77 cannot be a node of a program graph at all** — the enum says so in its own
comments — so the honest denominator for a coverage claim is **70**, not 77:

| figure | denominator counts | on the 25-graph corpus |
|---|---|---|
| `61 of 77` | every ENUM MEMBER | true, and not a coverage number |
| `61 of 70` | PROGRAM OPS (enum members a graph can contain) | the corrected figure |

Neither number is burned; they answer different questions.

---

## 1. The population is DISCOVERED, not typed

`graphcmp-oracle.py` parses the enum body out of `tinygrad/uop/__init__.py` — the same file
it already imports its names from — splitting it on the enum's **own** `# ** N -- title **`
headers and pairing each `NAME = auto()` with the comment block above it (or its trailing
comment). The parse is then checked against the live `Ops` (`sorted(parsed) == sorted(Ops)`),
so a transcription error is impossible: there is nothing transcribed.

**Parsing rule:** section = last `# ** N -- title **` seen; member = every `NAME = auto()`
on a line (a line may hold several: `BUFFER = auto(); ALLOC = auto()`); comment = the
trailing `# …` if present, else the accumulated preceding `# …` lines. **Every comment and
every assignment line is READ; none is listed here or in the code.**

Per-section census (MEASURED, `run.out` / `audit.out`):

| # | section title (the enum's own words) | members |
|---|---|---|
| 1 | defines/special | 3 |
| 2 | non op uops | 13 |
| 3 | load/store | 4 |
| 4 | math | 31 |
| 5 | control flow / consts / custom | 10 |
| 6 | ops that don't exist in programs | 15 |
| 7 | pattern compiler IR (used in upat.py) | 1 |
| | **total** | **77** |

## 2. The program-op denominator, each exclusion justified

A member is excluded when its section title or its own comment carries one of five markers
declared once in `NON_NODE_MARKERS`:

`"aren't rendered"` · `"renderer"` · `"pattern compiler IR"` ·
`"output strings into codegen"` · `"machine instruction"`

That marks **10** members. The corpus is the **second witness and only ever RESCUES**: an op
a graph reaches is proof the comment is about rendering, not graph membership. Three of the
ten are reached and stay (`NOOP`, `LINEAR`, `BINARY`), leaving **7 excluded**:

| op | enum's own comment (marker) | measurement: where it is CREATED |
|---|---|---|
| `REWRITE_ERROR` | "uops that aren't rendered" | `tinygrad/uop/ops.py:1722` (rewrite trace) + `tinygrad/viz/serve.py`; no Tensor op builds it |
| `PROGRAM` | "renderer" | the compiled-program container, `tinygrad/uop/spec.py:197`; produced by codegen, not a graph |
| `SOURCE` | "renderer … SOURCE has a str arg" | renderer output text; `spec.py:194` |
| `PYLITERAL` | section 7 "pattern compiler IR (used in upat.py)" | created only in `tinygrad/uop/upat.py` |
| `CUSTOM` | "used to output strings into codegen" | created only in `tinygrad/uop/upat.py` (CUSTOM predicates) |
| `CUSTOMI` | same comment | created only in `tinygrad/uop/upat.py` |
| `INS` | "INS is a machine instruction" | created only in `tinygrad/runtime/support/hcq2.py` |

**77 total → 70 program ops.** Of the 70, **61 are reached**; the other **9 are merely
unexercised** on this corpus: `GETADDR WMMA THREEFRY MULACC STAGE MSELECT MSTACK
CUSTOM_FUNCTION UNSHARD`.

**Caveat, measured and not hidden:** the rescue is load-bearing for `LINEAR`/`BINARY`/`NOOP`.
`audit.out`'s `PLANT 1` drops `lin`/`loop`/`gate` — the graphs that prove `LINEAR`/`BINARY`
are nodes — and the by-construction count rises to 9. So the STABLE claim is the
enum-declared set (10); the corpus-relative claim is 7. The corrected denominator 70 is
stable across both states; only the split moves.

## 3. The corrected figure, BOTH ways

Both are the same run (`run.out`, baseline state):

```
COVERAGE: 61 of 70 program ops === 61 of 77 enum members
```

- `61 of 77` — enum members. Rule: denominator = `len(list(Ops))`. Kept, because it is the
  honest count of the enum.
- `61 of 70` — program ops. Rule: denominator = enum members minus the 7 excluded in §2.

**Paste-ready replacement for `AGENTS.md` (do NOT edit that file from here):**

`AGENTS.md:8-9` currently reads (fragment):
> …`SPEC=2` takes the corpus census from 61 of 77 ops to 26 of 77 with 14 of 25 graphs failing.

replace the fragment `from 61 of 77 ops to 26 of 77` with:
> from 61 of 70 program ops (`61 of 77` enum members; 7 are not program-graph nodes) to 26 of 70 (`26 of 77`)

`AGENTS.md:295` currently reads:
> `SPEC=1` 61 of 77 ops · `SPEC=2` 26 of 77, 14 of 25 graphs FAIL, exit 1 · `SPEC=3` 0 of 77, all 25 FAIL

replace that clause with:
> `SPEC=1` 61 of 70 program ops (= 61 of 77 enum members) · `SPEC=2` 26 of 70, 14 of 25 graphs FAIL, exit 1 · `SPEC=3` 0 of 70, all 25 FAIL

`checks/corpus-figure.py:230` also prints the raw `len(names)` denominator; it is out of this
unit's scope and is flagged, not edited.

## 4. What the ORACLE now prints

The one-line `NOT REACHED (16 of 77)` is kept, and two actable numbers are printed beside it
(`graphcmp-oracle.py`, `NON_NODE_MARKERS` / `enum_sections` / `program_op_split`):

```
# NOT REACHED (16 of 77 ENUM MEMBERS): REWRITE_ERROR PROGRAM SOURCE GETADDR WMMA THREEFRY MULACC CUSTOM CUSTOMI INS STAGE MSELECT MSTACK CUSTOM_FUNCTION UNSHARD PYLITERAL
#   OF WHICH 7 CANNOT APPEAR IN A PROGRAM GRAPH AT ALL (by construction): CUSTOM CUSTOMI INS PROGRAM PYLITERAL REWRITE_ERROR SOURCE
#   AND 9 ARE PROGRAM OPS NO GRAPH DRIVES YET (unexercised): CUSTOM_FUNCTION GETADDR MSELECT MSTACK MULACC STAGE THREEFRY UNSHARD WMMA
# DENOMINATOR: 77 enum members -> 70 PROGRAM OPS (7 excluded by the enum's own markers: …)
# COVERAGE: 61 of 70 program ops === 61 of 77 enum members (the denominators answer different questions)
```

The reached set is unchanged; only what the denominator SAYS changes. `differ.py`'s pins
survive: `# ORACLE SELFCHECK: OK` and the `rc=` last line are untouched.

## 5. The plant — two states, and the number MOVES

`.agents/slop/opdenom/run.py` runs the real `main()` in one subprocess per state (the oracle
REFUSES a second `main()` in one process: `DEV` freezes at import), with `emit_bend` mirrored
onto the py stream because **this unit does not run `bend`**. `ALLOC` was tried first and
MOVED NOTHING (16 graphs reach it); the plant must remove an op's LAST occurrence, so it
DISCOVERS the op the corpus reaches in exactly one graph — `AFTER`, reached only by `loop`:

| state | NOT REACHED | by-construction | unexercised | program ops |
|---|---|---|---|---|
| baseline | 16 of 77 | 7 | 9 | 61 of 70 |
| remove `AFTER` from `loop` | 17 of 77 | **7** | **10** | **60 of 70** |

The denominator and the by-construction half hold; the unexercised half moves. `audit.out`
shows the same plant (`PLANT 4`) plus the older RED plants (`port-dead` / `port-invents`) as
`SELFCHECK FAIL (rc=1)` — the census can still go red.

## 6. `--selfcheck`, and the meaning of `61/61`

- **ORACLE SELFCHECK: OK before** (`runs/graphcmp/D/D0-coverage-census.txt`, last line
  `rc=0`) **and OK after** (`run.out`, `audit.out`, `rc=0`). The new split is ASSERTED, not
  printed and hoped for: parse == live `Ops`; by-construction and program are disjoint and
  total; the reached set never intersects by-construction; the NOT-REACHED split sums.
  `graphcmp.py selfcheck` is a different instrument (the differ's `D0-selfcheck`) and was not
  run here.
- **`OP NAMES ALL IN Ops: 61/61`** is `len(tot_ops) - len(unknown_ops)` over `len(tot_ops)`,
  where `tot_ops` is the **UNION of both sides**. It means "all 61 distinct op names observed
  are members of `Ops`" — a vocabulary check, not a coverage claim. The `61` there is the
  SAME 61 as the reached set only **because the port reaches a subset of the py ops**:
  MEASURED, `union - reached = {}` and `reached - union = {}` on the 25-graph corpus. Different
  computation, equal by measurement; the audit's docstring already warns the ratio's halves
  come from different sides.

---

### Reproduce

```
env -u PYTHONPATH OPDENOM_PIN=runs/graphcmp/D/D0-coverage-census.txt \
    .venv/bin/python .agents/slop/opdenom/run.py --all
env -u PYTHONPATH OPDENOM_PIN=runs/graphcmp/D/D0-coverage-census.txt \
    .venv/bin/python checks/graphcmp-census-audit.py --all
```

`OPDENOM_PIN` pins `G.GRAPHS` to the graph list RECORDED in the artifact, because another
unit was adding graphs (`getaddr mulacc threefry unshard wmma`, WMMA mid-edit) to
`graphcmp.py` at 13:42 while this ran. On the live corpus (WMMA dropped, it raises mid-edit)
the reached set was **65**, unexercised **5**, by-construction still **7** — the denominator
holds while the gap closes. The oracle needs no pin: it discovers.
