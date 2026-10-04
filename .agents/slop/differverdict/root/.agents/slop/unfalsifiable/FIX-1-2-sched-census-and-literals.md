# Fixes 1 and 2 — `sched-cmp.py` / `sched-oracle.py`

Two of the four headline numbers. Every figure below was produced by RUNNING the
harness; the harness is `sched-arm-plant.py` in this directory and its transcript is
`sched-arm-plant-RESULTS.txt` beside it. Raw output: `$TMPDIR/unfals/`.

## The instrument before, read from source

`.agents/slop/sched-cmp.py` as committed (`unfalsifiable/pre-fix-sched-cmp.py`,
sha256 `0426b9b311c0da4adbfd25a539f39b810f0e0e5222269aa5b1f0f389d7802c1a`):

```
:39   def dig(name): return DIG.get(name, 0)        # 0 for any name outside DIG
:123  print(f"# specs_attempted=6 specs_scheduled=6 fields_compared={len(agree)+len(disagree)} ...")
:125  print(f"# denominator: {len(agree)+len(disagree)} fields = 6 specs x {(len(agree)+len(disagree)) // 6} fields")
:135  uncoded = collections.Counter()               # never written, never printed
:139  print(f"# alphabet={len(DIG)} ops, digit 0 reserved for 'no code'")
```

`.agents/slop/sched-oracle.py:267` as committed:

```
print(f"# specs_attempted={len(SPECS)} controls={len(CONTROLS)} scheduled_calls={sum(1 for k in names if not k.endswith('RAISED'))}")
```

## Fix 1 — the uncoded-op census, and whether the hazard is ARMED

### IT IS ARMED. I did not take the audit's word for it; I built the slice.

The audit says the hazard is dormant in the committed six specs. Measured first, by
driving each of the six and asking which packed slice holds an uncoded name
(`sched-uncoded-arm.py`, all six: `ksrc=['SINK','PARAM',...]`, `ktop=['SINK']`,
`kmark` in `REDUCE/MAX/CAST/MUL`) — **none arms**, which reproduces the audit and
also confirms no *reported* value was wrong.

Then four candidate specs, each driven. Three produced **empty slices** (`lin.src ==
[]`, the documented silent-empty `create_schedule` shape) and armed nothing; that
was my construction being wrong, not the hazard, so I mirrored the working
`s_elementwise` construction — three fresh unrealized operands, one realized
destination — and re-ran. Result:

```
exp_chain   ksrc=[SINK,PARAM,PARAM,PARAM,PARAM] ktop=[SINK] kmark=['EXP2']   ARMED
where_pick  ksrc=[SINK,PARAM,PARAM,PARAM,PARAM] ktop=[SINK] kmark=['WHERE']  ARMED
```

`WHERE` is one of the four ops the audit named. `OpsWHERE` **exists** in
`tinybendygrad/uop/ops.bend`, so the port can express it and its `dig` falls through
to `case _ : 0` — the port genuinely answers 0, not "cannot answer".

### The arm is end-to-end, on both sides, from a real bend run

`s_where` was added to `SPECS` in a `$TMPDIR` copy of the oracle. One edit flows to
both generators (`sched-emit.py:210` and `sched-fixture.py:286` both iterate
`SO.SPECS`), so the port grew a real seventh spec built from CPython's own object
graph — no node transcribed — and `./bin/bend` on the regenerated fixture produced
**`where_kmark=0`** as a genuine port row.

### PLANT — before / after, same copy, only the comparator differs

| | PRE-FIX (`pre-fix-sched-cmp.py`) | POST-FIX (`sched-cmp.py`) |
|---|---|---|
| `specs_attempted` | **6** (wrong — seven ran) | **7** |
| `fields_compared` | 70 | 70 |
| `fields_agree` | **70** | 70 |
| `fields_disagree` | **0** | 0 |
| the `where_kmark` row | **`AGREE where_kmark=0`** | `AGREE where_kmark=0` |
| word `UNCODED` in output | **absent** | present |
| word `WHERE` in output | **absent** | present: `WHERE=1` |
| rc | **0** | **1** |

**What it read before the fix: `0`.** Not a wrong number — a number that stood for
nothing, reported as agreement at rc=0, with the only alphabet line in the output
(`digit 0 reserved for 'no code'`) *announcing* the reservation and never saying
whether anything landed in it.

The fix does **not** invent a disagreement: both sides really do answer 0, so the row
is still `AGREE`. It makes the same comparison say what the 0 was, and it turns the
run red because a field built only from uncoded names cannot distinguish "an op
neither side has code for" from "an empty sequence" from "no STORE".

### DISARM A — the live six-spec tree, run twice

`UNCODED 0`, `SNAPSHOT_FRESH`, `VERDICT AGREE`, rc=0, both runs byte-identical.

### DISARM B — SCOPE, the sharp one

Eight specs: `where` arms, `where_relu` (same graph, `.relu()` on the end, so the
STORE's value is `MAX` and no compared field is built from an uncoded name) does not.
Both graphs contain a `WHERE`. The census reports **`WHERE=1`, not `WHERE=2`** — so
it measures the *compared fields*, not the graph. A census that counted graph-level
ops would go red on a spec that compares correctly, which would be its own
unfalsifiable number. Both rows still read `AGREE where_kmark=0` /
`AGREE where_relu_kmark=16`.

### Also measured: three distinct questions, one answer

```
pack(['SHR','SHL']) = 0     two uncoded ops (neither is in DIG)
pack([])           = 0     an empty src sequence
pack([''])         = 0     a kernel with no STORE -- store_val_op spells absence ''
pack(['CAST'])     = 17    the control
```

`store_val_op`'s docstring claimed absence is "visible as a name rather than as a 0
that could also mean 'uncoded'". True of its return value, **not** of the packed
field, where `''` and `MAX`-less and uncoded all land on 0. The census now prints
absence as `<empty>` rather than letting it hide. That is a third collision the audit
did not list, and it is dormant on all six specs (every kernel has a STORE).

## Fix 2 — the string literals

### PLANT — a seventh spec moves the header, on BOTH sides

Comparator, same armed copy:

```
PRE : # specs_attempted=6 specs_scheduled=6 fields_compared=70 fields_agree=70 ...
POST: # specs_attempted=7 specs_scheduled=7 fields_compared=70 fields_agree=70 ...
```

and the denominator line, which was `n // 6` against a literal:

```
PRE : # denominator: 70 fields = 6 specs x 11 fields     <- 6 x 11 = 66, not 70
POST: # denominator: 70 fields = 7 specs x 10 fields     <- 7 x 10 = 70. TRUE.
```

Oracle's own header, same seventh spec:

```
LIVE  (6 specs)  # specs_attempted=6 controls=1 specs_scheduled=6 scheduled_calls=12 block_keys=25
ARMED (7 specs)  # specs_attempted=7 controls=1 specs_scheduled=7 scheduled_calls=14 block_keys=29
```

**One more literal, found while making the two sides agree.** `sched-oracle.py:267`
computed `scheduled_calls` as `sum(1 for k in names if not k.endswith('RAISED'))`,
and `names` is not the set of calls — measured, it holds **25 keys** for six specs:
the 7 spec names, 6 `X#i` duplicate block keys, and 6 `X__calls` bookkeeping keys.
So `scheduled_calls=25` was 25 *keys*. The true count is the sum of the per-spec
`len(_CAPTURED)` = **12**, and the 25 is now printed under its own name
(`block_keys=25`) so the number is not lost, just no longer mislabelled.

### DISARM — six specs, live, twice

`specs_attempted=6 specs_scheduled=6`, `denominator: 60 fields = 6 specs x 10 fields`,
rc=0 both runs.

## Also fixed while in there: the staleness window

The brief is explicit that this is not a comparator bug. It was not one: `fields_agree`
still goes red on a wrong value. The **window** was the defect, so the port side is
now produced by this run — `live_port_rows()` executes `./bin/bend <fixture>` and its
stdout is the port side; `sched-port.txt` is read only to report `SNAPSHOT_FRESH` /
`SNAPSHOT_STALE`, and stale is red.

**PLANT C — the audit's own plant, `Lin.out` -> `List.drop(out, 1n)` in a `$TMPDIR`
copy of `tinybendygrad/schedule/__init__.bend`, snapshot regenerated from it:**

```
# SNAPSHOT_FRESH
# fields_compared=60 fields_agree=24 fields_disagree=36
# VERDICT RED DISAGREE      rc=1
```

Pre-fix, the committed comparator over this same tree read **60/60, rc=0**. The
audit measured 24/60 when it fed the mutated snapshot in by hand; this reproduces
**24/60** from the comparator running the mutated port itself.

**PLANT B — one snapshot row changed, port untouched.** Pre-fix: `DISAGREE`,
60->59. Post-fix: `SNAPSHOT_STALE ... 1 key(s) differ, first 5: [('matmul_ktop', 9,
5)]`, rc=1, and **zero** `DISAGREE` lines — because the port side is now what the port
produced, and it is right. Still red, for the truer reason. Reporting the behaviour
change rather than hiding it: the audit's PLANT 1 now lands on the staleness channel,
not the value channel.

**DISARM D — agent-core's `$TMPDIR` trap, deliberately.** A copy with no resolvable
`../../tinybendygrad` imports gives `SOME PROOFS FAIL` and 0 rows. The comparator
prints `NO_PORT_ROWS` and `SNAPSHOT_STALE`, `fields_compared=0`, rc=1. It does not
read a dead port as agreement — the `nv_nvdev_gate.py` failure mode.

## Other changes, and why

- `specs_scheduled` is measured by catching a raising or schedule-less spec, which
  contributes no fields and is counted as unscheduled. Pre-fix, one raising spec
  propagated and killed the run on its own data.
- `SPEC_FIELDS` is the single place the per-spec width is written, and `spec_of()`
  splits `<spec>_<field>` by longest-suffix over it. Splitting on `_` would break on
  `matmul_sym`, and a `RAGGED_DENOMINATOR` verdict fires if any spec does not carry
  every declared field — so the denominator line cannot quietly stop being a product.
- One bug of **mine**, found by the harness and fixed: `# VERDICT AGREE` printed
  beside `fields_disagree=36`, because `bad` never received `DISAGREE`. The rc was
  right; the verdict line was not. A verdict line that disagrees with the count beside
  it is the defect class this whole exercise is about.
- Fidelity control, run first and twice: a live `./bin/bend` on the live fixture is
  content-identical to the committed `sched-port.txt`, sha256 of non-blank lines
  `207ee494251e3dcde...`, which is the sha `sched-stage2.md` publishes. bend is
  **2.0.35**.

## NOT FIXED HERE, reported

`.agents/slop/sched-fixture.bend:50` — generated — carries the same false claim the
comparator did: *"Digit 0 means 'no code', so an uncoded op is visible rather than a
silent leading zero."* It is not visible; it packs to 0. The file is generated by
`sched-fixture.py` / `sched-emit.py`, neither of which is in my ownership, so this is
reported, not edited. Its `dig` does agree with the comparator's `DIG` on all 17
codes and the same `case _ : 0` fallthrough — verified by reading both.