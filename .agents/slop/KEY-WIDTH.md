# THE KEY HAS BEEN WRONG THREE TIMES, AND THE THIRD TIME IS THE MIRROR OF THE FIRST

**MEASURED 2026-10-15.** `checks/census.py` reports `34 of 68 slots STALE`, **every one of them `py`, none `bend`.**
The only edit since the keys were written was `a13db09bd98a` (`retrydet`), and **it touched `0` lines of `emit_py`** —
it changed `emit_bend` only. **MEASURED, all three sampled graphs are BYTE-IDENTICAL to the cache.**

**So every one of those 34 refusals is WRONG, and the gate is refusing for the right reason on the wrong subject.**

```
   the key says            the generator file changed
   the truth says          the rows for THIS lane are unchanged, and were verified so
   the gate does           REFUSED (3), 34 times, with a slot list
```

## THE THREE SHAPES, AND NONE OF THEM IS THE FIRST ONE

| # | the key is | measured by | consequence |
|---|---|---|---|
| 1 | **too NARROW** — one file where the subject depends on **7** | `closure` | an edit to an imported file was invisible |
| 2 | **no PRODUCT digest** — the producer's sha, never the cache's | me | an edited cache row was invisible |
| 3 | **too WIDE** — the whole file keys **both** lanes | found today | a bend-only edit refuses **34** healthy py slots |

**THE COMMON ERROR IS NOT THE WIDTH. IT IS THAT A KEY IS SCOPED TO A FILE WHEN ITS SUBJECT IS SCOPED TO A
FUNCTION.** *`graphcmp.py` holds `emit_py` and `emit_bend`; they share a file and nothing else. Keying on the file
claims a dependency that does not exist in either direction.*

## THE FIX, AND ITS COST, WHICH IS THE PART THAT MATTERS

**Hash the byte range of the lane's own function, not the file that holds it.** `ast` gives both end points; the
source segment between them is the unit. **That collapses shape 3 without disturbing 1 or 2** — the closure and the
cache digest stay.

**COST: ALL `68` **KEYS **ARE **INVALIDATED**, **AND **THE **REGENERATION **MUST **BE **OUT **OF **PROCESS** — **ONE
GRAPH **PER **PROCESS** — **BECAUSE **THE **py **LANE's `P(i..)` **COMES **FROM **A **MODULE-LEVEL `itertools.count`**
AND **AN **IN-PROCESS **RUN **OVER **34 **GRAPHS **WROTE **`37` **DISTINCT **VALUES **WHERE **A **PER-PROCESS **RUN
**GIVES **`4`.** *That corruption is mine and shipped once; the regeneration rule is not optional.*

## AND THE CHEAP PART THAT MAKES IT HARD TO REGRESS

**A **KEY **THAT **CAN **BE **WRONG **IN **THE **CHEAP **DIRECTION **SHOULD **BE **MADE **TO **SAY **SO**:
**IF **THE **WHOLE-FILE **DIGEST **AND **THE **FUNCTION **DIGEST **DISAGREE, **PRINT **BOTH **AND **CALL **IT
**OVER-BROAD, **NOT **STALE.** *** **THAT **TURNS **THE **`34` **WRONG **REFUSALS **INTO **A **NAMED **DIAGNOSTIC
**INSTEAD **OF **A **SILENT **TRUTH** — **AND **A **GATE **THAT **CAN **SAY **"I **AM **BROAD" **IS **NOT **THE **SAME
**GATE **AS **ONE **THAT **CAN **ONLY **SAY **"STALE"**.
