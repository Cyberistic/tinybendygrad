# 08 — "234 counts, 0 loads → UNCHANGED was UNDECIDABLE"

**VERDICT: the count 234 is CAN-FAIL. The "0" half is CANNOT-FAIL for the
filename-derived captures — and the reason is structural, which is the finding.**

## Subject and instrument

- **Subject:** every recorded baseline count in the corpus, and whether a machine
  load was recorded beside it.
- **Instrument:** `.agents/slop/load-census.py --guard`. Live, `rc` measured
  properly (not through a pipe, which would have given me `tail`'s status):

```
FAIL  load_guard: 0 of 234 recorded baseline count(s) carry a load or an elapsed
      time; 234 carry neither  [RE-MEASURED-ALONGSIDE=215  SUSPECT=19]
GUARD rc=1
```

This matches `baseline-ledger.md` exactly: **234 recorded baseline counts in 13
files**, `OK` 0, `RE-MEASURED-ALONGSIDE` 215, `SUSPECT` 19, and
`RECOVERABLE: 0 of 234. UNRECOVERABLE: 234 of 234.`

**The instrument is the only number in this set that is designed to be red.**
`--guard` exits 1 and the file says so: *"It fails by design, and it will keep
failing."* A permanent red with a permanent cause is the correct shape for a
guard, and this is worth saying before anything else about it.

## Plant — the count 234 is CAN-FAIL

`--root` makes the corpus a parameter, so the count can be moved without writing
into the tree. A `$TMPDIR` corpus of 16 copied baseline files:

```
copied corpus                      : 0 of 235 recorded baseline count(s) carry a load   rc=1
+ one extra baseline-shaped file    : the denominator tracks the corpus
```

The denominator is a glob over three shapes (`*baseline*.txt`,
`rebase/baseline*.json`, `rebase/stability-*.json`), so it is a measurement of the
corpus and it moves with the corpus. **CAN-FAIL.**

## CANNOT-FAIL — and this is the finding: the "0" is structural for filename counts

Three plants, all on a `$TMPDIR` copy, all placed to land:

| plant | where | result |
|---|---|---|
| 1 | `loadavg=4.11` appended at **end of file** | `0 of 235` — unmoved |
| 2 | `loadavg=4.11` inserted **immediately after the file's first count line** | `0 of 235` — unmoved |
| 3 | `# load average 4.11 -- recorded with this capture` as a **non-claim context line** beside the first count | `0 of 235` — unmoved |

**Why.** Read `load-census.py:104`:

```python
def qualified(lineno, lines):
  """True if a load token is on the claim's line or in the blank-line-delimited window around it.
  `lineno` is 1-based into `lines`."""
  lo, hi = max(0, lineno - 1 - CONTEXT_LINES), min(len(lines), lineno + CONTEXT_LINES)
```

The load test **needs a line number**. And the claim the guard reports for
`oracles/amdev-baseline-552.txt` is `(unidentified capture): ?=552` — the number is
derived from the **filename**, so the claim has no line to anchor a window to. A
load token anywhere in that 700-line file cannot be near a claim that has no
position.

So for the filename-derived sub-population, **`0 of N` is true by construction,
not by measurement of load.** That does not make the ledger wrong — it makes the
ledger's `0` a statement about *where these numbers were written*, and the
honest label for that class is *"structurally unqualifiable"*, not *"measured as
unqualified"*. The `UNDECIDABLE` verdict the ledger reaches is right; the route it
takes to get there is not the one a reader would assume.

**This is not a defect I can plant away, and I am not going to soften it: the
"0" half of `0 of 234` cannot go red for any file whose count is encoded in its
own name.** Plants 1–3 are the attempt; the reason is the `qualified()` signature.

## What the ledger gets right

- The `load_guard()` v1 defect is recorded on the record: it printed
  *"215 of 234 carry a load or an elapsed time"* computed as an OR over three
  facts, and the corrected version *"reads 0 of 234"* from the load and
  elapsed-time facts alone. **A measurement that was wrong, the wrongness, and the
  fix are all in the ledger.** That is the standard.
- *"No lane was re-run to produce a number in this file"* — a ledger, not a
  refresh, stated in the header.
- The denominator instability (`234` then `235` twenty-three seconds later with
  no edit) is recorded as **F9** with the fix.

## Reproduce

```
.venv/bin/python .agents/slop/load-census.py --guard ; echo "rc=$?"
```

Measure `rc` without a pipe — `cmd | tail; echo $?` reports `tail`'s status, and
I made that mistake once during this audit before catching it.

For the plants, copy `*baseline*.txt`, `rebase/baseline*.json` and
`rebase/stability-*.json` into a `$TMPDIR` tree and pass `--root`.