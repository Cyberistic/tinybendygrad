# THE 50.0% PRECISION WAS THE WRONG CONDITIONAL

**MEASURED 2026-10-15. Precision of a verdict is `P(agree | THE INSTRUMENT SAID FAIL)`. The `15/30` figure
was sampled across ALL lanes including `PASS` and `REFUSED`, which answers a different question.**

```
LANE A   8 FAILs, ALL from ONE file (.agents/slop/citemass/resolve.py:34-69)   ->  8/8 TRUE
         ops.bend is 8,912 lines and EVERY cited line points elsewhere:
           :1066 claimed 'ATuple{ys: List<&2, U32>}'   actually at 1208
           :4554 claimed 'WALL(p3)'                     actually at 4676
           :4560 claimed 'ABlob'                        actually at 1163
           :1057 claimed 'dtype: S.Dt'                  actually at 871
LANE B  10 FAILs over THREE subjects, ALL cited past end of file             -> 10/10 TRUE
           .agents/slop/e2e.sh                24 lines, cited at :122 and :138   x4
           tinybendygrad/runtime/ops_nv.bend   95 lines, cited far past it       x4
           tinybendygrad/engine/jit.bend     435 lines, cited at :1091           x2
```

## THE `7 -> 10` I KEPT CALLING A REGRESSION IS THE FINDING

`dangle` measured `e2e.sh` at **23** lines and `ops_nv.bend` at **94**. **Both are now 24 and 95.** So the
same true citations moved from *off by N* to *off by N+1*, and the number of places quoting those two files
grew from 7 to 10. **One defect, quoted three times — not three defects.**

## THE `PASS` HALF IS ALREADY THE INSTRUMENT'S OWN LOWER-BOUND LINE

A census that `FAIL`s **160** times and `PASS`es **2,049** can be **100% precise on the 160** and useless on
the 2,049 — and both halves are the same lesson. **The `1,799` claims the instrument already names as
`CANNOT FAIL` are the PASS half; the 160 that can, are 160 out of 160 right.**

## WHAT IS STILL OPEN, AND IT IS THE HONEST PART

**The 2,992 `REFUSED`s lane C created are still unmeasured.** A `REFUSED` is the state that should be
harmless and a `FAIL` should not be — so the open question is about the harmless half.

## AND `dangle`'s "4 OF LANE A ARE MY OWN AST FALSE POSITIVES" IS WRONG THE WAY ITS OWN SUBJECT IS WRONG

It counted false positives **of the writer**, not of the judge. **The judge is right on all 8, for the same
reason it is right on the 10: the text IS in the file, just not at the line the citation names.**

**A citation is a lower bound on value, not a sufficient condition — and a precision figure is a lower bound
on a figure, not a verdict on an instrument.**
