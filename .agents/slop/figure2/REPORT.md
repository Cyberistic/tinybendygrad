# `checks/corpus-figure.py` — is it red? No. It is GREEN, and the rc=1 is the DEV precondition.

**MEASURED 2026-10-06 13:00 local, this tree, HEAD `863d89622`.**

## 1. The instrument names its own verdict — and it names no red pin

```
$ DEV=CPU .venv/bin/python checks/corpus-figure.py
DEVICE PRECONDITION : OK -- DEV=CPU, which is the declared pin
graphs declared   : 25
graphs built      : 25
graphs FAILED     : 0
denominator len(Ops) : 77
CPYTHON-SIDE UNION   : 61 of 77
RUN HEALTH        : OK -- 17 of 17 pins green (checks/differ.py's PINS, imported; `graphs=25` and `not-comparable=0` among them)
per-graph SUM        : 181   <- NOT the figure
NOT reached (16): REWRITE_ERROR PROGRAM SOURCE GETADDR SOURCE WMMA THREEFRY MULACC ...
rc=0
```

**NO PIN IS RED.** The full `RUN HEALTH` line is
`RUN HEALTH        : OK -- 17 of 17 pins green (checks/differ.py's PINS, imported; graphs=25 and not-comparable=0 among them)`.
There is no `RED:` clause because `run_health()` produced none (`.agents/slop/figure2/run-dev-cpu.out`, rc=0).

**The `rc=1` in the brief is the DEV precondition, not a pin.** With `DEV` unset the figure refuses
*before* it reaches `run_health()`:

```
$ env -u DEV .venv/bin/python checks/corpus-figure.py
DEVICE PRECONDITION : **VIOLATED** -- DEV=None and the declared pin is 'CPU'. ...
rc=1
```

That refusal is declared, correct, and REQUIRED (item 6) — a coverage figure whose denominator moves
with the backend (`g_late` reads the backend's own op table; 61 of 77 on CPU vs 60 on NULL/METAL) must
refuse on the wrong device. **It is NOT a pin going stale, and it was not removed.**

## 2. Which of (a) / (b) / (c)

- **(a) a genuinely regressed pin — NO.** All 17 declared pins are present in
  `runs/graphcmp/D/D0-run-summary.txt` and equal to the declared values.
- **(c) a parse bug that only some values trigger — NO, and the plant proves it.** The two
  space-bearing pins that carry the verdict (`selfcheck=# SELFCHECK: OK`,
  `oracle-selfcheck=# ORACLE SELFCHECK: OK`) parse correctly under the current
  `ln.split("=", 1)`. The plant (below) breaks exactly one of them and the figure goes red, so the
  parser sees them.
- **(b) a pin MOVED after the artifact was written — the HISTORY happened, but it moved TO the
  artifact, so nothing is stale and nothing is red.** Timeline, measured:

  | event | time | hash |
  |---|---|---|
  | `runs/graphcmp/D/D0-run-summary.txt` written (the fresh run) | `12:50:21` | (untracked, `.gitignore`d) |
  | commit editing `checks/differ.py` `PINS` **and** `.agents/slop/graphcmp.py` `selfcheck` prose | `12:57:57` | `e88229fd6` |
  | HEAD | `12:58:04` | `863d89622` |

  `e88229fd6` changed `checks/differ.py`'s `PINS` from
  `"graphs-agree": "19", "byte-identical": "19"` to `"graphs-agree": "21", "byte-identical": "21"`,
  and the artifact on disk ALREADY carries `graphs-agree=21`, `byte-identical=21`,
  `selfcheck=# SELFCHECK: OK`, `oracle-selfcheck=# ORACLE SELFCHECK: OK`. **The pins were moved TO
  the fresh artifact's values.** So the artifact is NOT the stale side; it IS the fresh run's output —
  the next `differ.py run` would produce the same bytes and the same green. **The "answer is the next
  run" clause is moot here: the artifact was regenerated, and the pins were re-pinned to it in the
  same session.** No fix is warranted.

## 3. PLANT — two states, distinguishable (on copies; `runs/graphcmp/D/` untouched)

`.agents/slop/figure2/plant.py` builds two throwaway roots, each with a COPY of the figure and a
SYMLINK to the real `.agents` (so `graphcmp.py`/`load_tinygrad` are identical), and its OWN
`runs/graphcmp/D/D0-run-summary.txt`. The only variable is ONE pin: `selfcheck`, flipped `OK`→`FAIL`.
The real summary is byte-compared before and after (`assert`s guard it). Output
(`.agents/slop/figure2/plant.out`):

```
GREEN STATE (real pin)     : rc=0
  RUN HEALTH        : OK -- 17 of 17 pins green (...)
RED STATE (selfcheck->FAIL): rc=1
  RUN HEALTH        : **FAILED** -- 16 of 17 pins green. RED: selfcheck=# SELFCHECK: FAIL (expected # SELFCHECK: OK). THE UNION ABOVE IS NOT A VERDICT.
PLANT: TWO STATES DISTINGUISHABLE
```

The real summary's mtime/bytes are unchanged.

## 4. Pin census (item 7)

| | count |
|---|---|
| declared by `checks/differ.py:PINS` | **17** |
| consulted by `run_health()` | **17** |
| green | **17** |
| red | **0** |

Out of **17** declared pins. (`.agents/slop/figure2/census.out`.) The summary carries five further
rows that are deliberately NOT pinned — `dev`, `lc_all`, `noopt`, `pythonhashseed`,
`graphs-disagree` — so "17 in the summary" is not a contradiction: `differ.py` declares 17, and
`run_health()` consults exactly those 17.

## Conclusion

**The brief's premise — "IT IS rc=1 NOW" — is FALSE for `DEV=CPU`.** The figure is green on all 17
pins. The only red is the DEV precondition firing when `DEV` is unset, which is intended and stays.
There is no pin to fix and no artifact to regenerate: the pins were already re-pinned to the fresh
artifact (`e88229fd6`, `12:57:57`, after the `12:50:21` artifact). **A governing claim about a red
instrument, like the instrument's own claims, has to carry the measurement that made it true — this
one did not.**
