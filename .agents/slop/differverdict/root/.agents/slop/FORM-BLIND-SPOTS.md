# FORM-BLIND SPOTS — where each tool's number is a FLOOR, not a total

**THE RULE, STATED ONCE AND CHECKABLE.**

> **A tool that matches a form cannot see the instance that lacks it.**
>
> **THE TEST:** build two texts that *mean the same thing* and are *written differently*. A
> reader that answers differently is matching a form. Name the variant, construct it, and
> assert — with a **control reader that must also get it wrong**, or the assertion is dead.

The test is not a reading. Every finding below was reached by a **disagreement** between two
tools that meant the same thing, never by reading a tool: `hand_typed` missing f-strings, the
`s5_` tally missing an unbound row, `radix` missing hex, `O.Found.i(` missing a local, and the
`rows()` F3 discovery all arrived as a number two tools did not share. That is the only
reliable detector, so **a disagreement count is not a coverage statement** and the
denominators below are printed on every run.

## THE FOUR INSTRUMENTS

| file | what it does |
|---|---|
| `rowform.py` | the FORM-COMPLETE row reader (`any_row`, `blind_reason`) and the meaning-equal spelling battery |
| `formblind-census.py` | every selector under `.agents/slop/`, extracted from its AST, run against the battery. `--denoms --detail --floor` |
| `formblind-audit.py` | 17 constructed variants, each with a form-complete answer, the real reader's own answer, and a control. Exits 1 on the 12 that still stand |
| `substrate-audit.py` | the OTHER root cause: 4 instruments that are right about a form and wrong about the substrate |

> **SNAPSHOT, AND THE UNIVERSE IS LIVE.** Other agents are adding tools while this
> runs: the census read **851 → 841 → 846** tools over one session and the lane
> count **771 → 834 → 835**. Every count below was read TWICE and the two reads
> compared, but a number that grows while you watch it is an **unfinished** one, not
> an unstable one. **Run `formblind-census.py --denoms` and `--floor`; do not quote
> these blocks from memory.** The per-reason floor split is the stable part.

## DENOMINATORS — every run prints these, and none of them is a coverage claim

```
tools in universe                            841   (.py/.sh/.mjs/.js under .agents/slop)
  excluded xd1/                             4989 files   vendored tinygrad checkout -- SUBJECT, not tool
  excluded opstree/                          348 files   vendored tinygrad checkout -- SUBJECT, not tool
  census instruments (SELF)                     5        excluded: a census that counts its own detector
FORM-BLIND                                    67
FORM-COMPLETE-ON-BATTERY                     284       survived the battery -- a FLOOR, not a proof
NOT-A-SELECTOR (UNAUDITED)                   490       no predicate found; NOT CLEARED
DELEGATES-A-READER                           166       inherits another tool's blindness
FORKS-A-READER                               156       `def rows…` / `split_py` / `parse_rows` of its own
```

**490 of 841 tools were not audited.** They have no selection predicate the extractor can see.
That is reported as a denominator, not folded into the green. **The universe is moving** —
851 → 841 over the session, because other agents are adding tools — so run `--denoms`, do not
quote this block from memory.

## BLAST RADIUS — who inherits `rebase-gate.py:rows()`

**9 tools call it.** Every count they print is a floor:

`dd-band-diff.py` · `dd-split.py` · `multi-namelane.py` · `ops-501-mutate.py` · `ops501-agree.py` ·
`ops501-names.py` · `rebase-portrows.py` · `rebase_gate_shim.py` · `wire-lanes.py`

A further **156 tools FORK a reader** (`def rows…` / `split_py` / `parse_rows`), so a fix
applied to `rebase-gate.py` leaves the forks blind with nothing to notice. The census prints a
`FORK:` column for each.

## THE MEASURED FLOOR (`formblind-census.py --floor`, run twice, both stable)

Across the **835** `.txt` lanes that `rows()` *does* read as rows, it cannot read **3,298**
of their lines:

| reason | lines | what it is |
|---|---:|---|
| `SINGLE-SPACE` | 3,091 | the gap must be **two** spaces; a lane printing `name value` reads as zero rows |
| `TAB` | 186 | refused on purpose — a TSV table's first column is not a row name |
| `EQ-INSIDE-GAP` | 19 | a two-space row whose value carries `=`: the `=` branch claims it first and **renames** it |
| `OTHER` | 2 | |

**The lane count moves while you watch** — 771 → 834 → 835 across this session, because other
agents are writing lanes. That is why the floor is read twice and the two reads compared: a
count that grows while you watch it is an **unfinished** one, not an unstable one. The per-reason
split has been stable (`TAB` 186 and `EQ-INSIDE-GAP` 19 on every read); `SINGLE-SPACE` tracks
the lane count.

Plus, unmeasurable by counting because the row simply vanishes: **a row whose NAME carries a
space** (`F3` requires `len(head.split()) == 1`) — and `multi-rows.py` writes
`f"{n.ljust(w)}  {v}"`, so an `n` with a space drops the row.

## THE SIX FINDINGS, WHERE EACH ONE NOW LIVES

| # | the form it matched | the variant it could not see | consequence | where the blind spot is written down | status |
|---|---|---|---|---|---|
| 1 | `rows()`: `name=value` | `name␣␣value` — **213 real rows compared against nothing** | the F3 discovery; a wrong number reached a claim | `rebase-gate.py:165-189` (own header) | fixed 2026-10-04 |
| 2 | `rows()`: name is **one token** | a name carrying a space; a TAB; a single space; a value carrying `=` | **3,298 lane lines** measured | `dd-band-diff.py` (this round), `rowform.py`, audit **A1–A4, A16** | **KNOWN-BLIND** — owner is another unit |
| 3 | `--handtyped`: one regex with `$` | f-string names, hex, two `row()`/line, wrapped calls, `row()` in a string | **224 reported, 578 actual** | `unobservable-census.py:hand_typed()` | **FIXED** — delegates to `handtyped-audit.py` |
| 4 | the `s5_` tally: the **bound** form | the one row written bare | **18 named where there were 19** | audit **A14**; `ops-501-gate.sh` itself is sound (it greps lane OUTPUT) | KNOWN-BLIND in the tally, not in the gate |
| 5 | a quoted-import grep: `"ops.bend"` | Bend imports are **unquoted** | **0 importers** — a vacuous blast radius; **330 of 333** import mentions invisible | audit **A15**, `--corpus` | KNOWN-BLIND |
| 6 | `unchunks`: a space separator | whitespace is structural | **"0 trace rows"** — a count that reads as a finding | `graphcmp-LIMITS.md` item 5 | fixed 2026-10-04 |
| 7 | `dd-band-census` §C: `O.Found.i(` in the body, inside a **six-name callee whitelist** | the index routed through a local **and** any callee off the list | **0 printed where §A printed 7** | `dd-band-census.py` §C, audit **A13** | **FIXED** — arguments, stated set, own denominator |

### Two more found by the census, not by reading

8. **`--handtyped` over-counted too.** After it was corrected, exactly one row it had reported
   vanished: `device-oracle-MUTANT.py`'s `allow_lower`. That file contains **no `row()` call at
   all** — `row("allow_lower", 0)` occurs in a `PLANT_TO` template and in prose. A text scanner
   cannot tell a row from a sentence about a row. Audit **A17**. The old 209 was too *low* by
   329 and too *high* by 1.
9. **A claimed blind variant that was not one.** `hand_typed`'s `bare` arm `f"[^"{]*"` **does**
   see `row("a", f"1")`. The census classified it blind and it is not. Audit **A10** pins it, so
   a census that is not corrected is a census that teaches the wrong lesson.

## THE OTHER ROOT CAUSE — wrong substrate, not blind form

> **A tool that measures the right form of the wrong thing answers a question you did not ask.**

Different fix: widening the selector does not help. `substrate-audit.py`, all measured:

| # | instrument | what it measures | the substrate it should measure | status |
|---|---|---|---|---|
| S1 | a sha256 **digest** | the file being **mutated** | the file the rows are `SAME`-compared against — *a digest protects the mutant, not the reference* | fixed (`revision-ledger.py`, both digests named) |
| S2 | a **cache** | an mtime over a cache file | whether the payload is a measurement at all — `read_fresh_cache` returns `({}, 'fresh')` for a **crashed** lane | **LIVE DEFECT** — see below |
| S3 | a **binary path** keyed on `<stem>` | 131 `.bend` files, **110 distinct stems** | `port_key()` — 14 `__init__` ports shared one artefact, `run_port()` unlinked it then executed whatever was there | fixed (`rebase-gate.native_bin`, injectivity asserted) |
| S4 | a **selftest** whose `PASS` came from six synthetic states with `run_port()` stubbed | the **classifier** | the **instrument** — a re-implementation measuring itself | fixed; the file names the mistake |

### S2 is live, and the shape of the fix is the interesting part

`rebase-scan-oracles.cached()` has an `empty` clause and its `store()` will not write one.
`wire_parse.read_fresh_cache()` — **the shared reader, imported by `wire-rows.py` and
`wire-pair.py`** — does not. Measured on one constructed state (an empty cache newer than its
source, which is what a bend stack-overflow leaves behind):

```
rebase-scan-oracles.cached()   ->  (None, 'empty')      refuses: an empty cache is a FAILED run
wire_parse.read_fresh_cache()  ->  ({}, 'fresh')        reports a FAILED run as a fresh ZERO
```

**A CORRECTION THAT DOES NOT PROPAGATE IS INDISTINGUISHABLE FROM A CORRECTION THAT NEVER
HAPPENED.** The `empty` clause landed in one *consumer*, not in the shared function — the same
shape as the `rows()` fork `cstyle-gate.py` still carries. Not fixed here: `wire_parse.py` is
shared by three tools this unit does not own, and changing its return contract silently changes
two of them.

## WHAT IS STILL WRONG, IN ONE PLACE

`cstyle-gate.py:rows_shipped` says "rebase-gate.py's `rows()`, verbatim". **MEASURED false on
six shapes: it agrees on two and differs on four** — it is the pre-F2/pre-F3 reader, it misses
the two-space gap, it does not fold `]   py=[`, and it manufactures the `""` phantom row that
`rows()` excludes *on purpose*. So its shred count measures a reader that no longer exists.
Comment written in place; the fix is one line (`rows_shipped = rg.rows`) and is not made here
because the file belongs to another unit.

## WHAT I DID NOT FIX, AND WHY

- **`rebase-gate.py:rows()`** (A1–A4) — owned by another unit this round. Reported, measured,
  asserted, and the floor is written into every consumer that reaches it.
- **`wire_parse.read_fresh_cache`** (S2) — three consumers, two of them not mine.
- **490 NOT-A-SELECTOR tools** — no predicate to audit. Unaudited is not cleared.
- **156 forked readers** — a fix to the original leaves each fork blind. The census names
  them; deduplicating 160 forks is a different piece of work and is not done here.