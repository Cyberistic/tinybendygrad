# CORRECTION TO `WALLMAP.md` -- ITS RANK 1 IS NOT A MEASUREMENT

Landed beside the original rather than edited into it, so the original stays
measurable and this stays adjacent to it.

## RANK 1 (`no math.*`, 35 targets) IS WRONG, AND THE FIXTURE IS A TUTORIAL FILENAME

```
91 mentions of `math.`   0 outside a comment   0 imports
```

**There is no call site. Writing `math.*` would unblock zero targets.** The name comes
from `bend guide`, which teaches module imports with a demo file called `math.bend`
whose only def is `square`.

## WHY THE RANK EXISTED AT ALL, AND WHY IT WAS NOT REPRODUCIBLE

The `MATH-LIB` classifier **was not preserved.** A sweeping window/pattern gives the
nearest reconstruction as **28 lines / 13 files / 20 targets**, `lines/target` **1.4**
rather than the 0.9 the table reported.

**`WALLMAP.md` §6 already conceded the ranking "rests on keyword patterns in prose."**
That concession was in the file the next brief sent a unit to read. **A caveat in a
table is not enforcement, and a rank is not a measurement until the instrument that
produced it is preserved.**

## THE RULES THIS ADDS

- **A rank is not a measurement until the classifier is preserved.** A census whose
  derived artifact is missing cannot be re-run, and a number that cannot be re-run
  cannot be refuted.
- **A keyword pattern in prose counts COMMENTS.** Every `-` marker in this tree is a
  comment, so a grep that does not exclude comment lines measures the project's
  documentation, not its work. This is the fifth recorded instance of an instrument
  reading prose as data, and the first where the prose was a tutorial.
- **Markers that name their own blocker are worth more than a ranking computed over
  markers that do not.** The 20 real targets each name theirs; the aggregate did not.

## THE REAL TARGETS, FOR THE NEXT READER

| cluster | n | the comment's own blocker |
|---|--:|---|
| f32 constants in `mixin/elementwise.bend` | 10 | an F32 literal; gated on `UOp.const` -> `dtypes.from_py` + `truncate` |
| `gcd` on I64 | 4 | variadic reduce + `_min_max` + `simplify` (`divandmod.bend:883`) |
| rounding/classification | 4 | `F32.trunc` exists, `isnan` solved; needs `.bitcast` sugar |
| `_min_max` | 3 | symbolic's own item #1 |

**0 of these 20 need `math.*`.** Highest leverage is `dtype.bend`, which gates the
first cluster **and 8 of its own 14 constructors** -- and the 14 split **8/6**, where
**the 8 are 32-bit** and only the **6 `H.I64` ones** are the 64-bit question.
