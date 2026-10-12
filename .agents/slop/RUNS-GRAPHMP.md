runs-graphcmp: **13 **LIVE **GATES **READ **A **DIRECTORY **THAT **IS **A **SWEEP **ROOT, **IS **`0` **TRACKED**, **AND
**WHOSE **NEWEST **ARTEFACT **IS **4 **DAYS **15 **HOURS **OLD** — **AND **`gates/retention-check.py` **IS **ALREADY
**FIRING **ON **IT**, **SO **THE **DEFECT **IS **NOT **UNDETECTED, **IT **IS **UNACTED**

```
live gates naming runs/graphcmp : 13 of 1030 scanned .py   (checks/, gates/, root)
throwaway units naming it       : 52 of  696 scanned .py   (.agents/slop/)
tracked files in the directory  : 0        on disk: 241
gitignored                      : YES -> git ls-files --others --exclude-standard returns 0
newest artefact                 : 10/07 23:50      now 10/12 14:37   => 4 days 15 hours
checks/sweep.py:72              : RESIDUE_ROOTS = (".agents/slop", "runs")   <- it is a SWEEP ROOT
gates/retention-check.py        : rc=1  IV FIRES  runs/graphcmp/D/: NOT healthy: 102 complaint(s)
```

**SO `runs/graphcmp/D/` **IS **A **DIARY **IN **THE **STRICTEST **SENSE **AND **IT **IS **NOT **EVEN **A **CACHE**:
**A **CACHE **IS **WHAT **THE **LAST **RUN **WROTE**, **SO **IT **HAS **AN **AUTHOR; **THIS **HAS **`13` **READERS**, **A
**DELETION **RULE **POINTING **AT **IT**, **AND **`0` **FILES **GIT **CAN **RESTORE** — **AND **THE **TREE's **OWN
**RETENTION **GATE **SAID **SO **OUT **LOUD**: **`IV **FIRES`**, **`102` **COMPLAINTS**, **`rc=1`**.\n\n**AND **THAT **LAST **FACT **IS
**THE **ONE **THAT **MATTERS**: **THE **DEFECT **IS **NOT **UNDETECTED — **IT **IS **UNACTED** — **AND **A **GATE **THAT
**FIRES **ON **A **SUBJECT **GIT **CANNOT **SEE **IS **THE **`checks/substrate-id.py` **CLASS **ONE **DIRECTORY **UP**:
**THAT **WAS **A **GATE **RETURNING **`PASS` **WITH **THE **EMPTY **STRING's **sha256`, **AND **THIS **IS **A **GATE
**RETURNING **`rc=1` **ABOUT **A **DIRECTORY **NO **`git ls-files --others --exclude-standard` **WILL **EVER **LIST**,
**SO **BOTH **ARE **INVISIBLE **TO **THE **SWEEPS **THAT **COULD **ACT **ON **THEIR **VERDICTS**.\n\n**AND **THE **STALENESS **IS
**A **COUNT, **AND **THE **COUNT **IS **THE **FINDING**: **`graphs-disagree=0`** — **THE **NUMBER **`lane_pin`
**CROSS-CHECKS — **IS **A **MEASUREMENT **OF **NOTHING**, **BECAUSE **THE **ARTEFACTS **IT **READS **PREDATE **THE **FIX
**BY **4 **DAYS**, **AND **THE **TOKEN **LOOKS **EXACTLY **LIKE **SUCCESS** *** **AND **`checks/rows/`, **REGENERATED
**TODAY, **IS **`34` **OF **`34` **GRAPH **BYTE-IDENTICAL** — **SO **THE **TREE **HOLDS **TWO **OPPOSITE **TRUE **STATEMENTS
**ABOUT **THE **SAME **CORPUS**, **AND **THE **STALE **ONE **IS **THE **ONE **THE **GATES **READ.**

**THE **FIX **IS **NOT **REGENERATE**, **AND **THE **COSTING **SAID **WHY**: **"REGENERATING **HIDES **THE **DATE,
**AND **THE **DATE **IS **THE **EVIDENCE."** *** **EITHER **`runs/` **STOPS **BEING **A **SWEEP **ROOT**, **OR **ITS
**ARTEFACTS **BECOME **TRACKED**, **OR **EVERY **ONE **OF **THOSE **`13` **GATES **GETS **TO **SAY **`DEAD` **WHEN **THE
**DIRECTORY **IS **ABSENT**. *** **THE **THIRD **IS **CHEAPEST **AND **IS **THE **ONLY **ONE **THAT **SURVIVES **BOTH
**THE **SWEEP **AND **THE **CLONE**: **A **GATE **THAT **READS **NOTHING **AND **REPORTS **SUCCESS **IS **THE
**FAILURE **MODE **THIS **PROJECT **HAS **SPENT **A **SESSION **NAMING** — **AND **A **GATE **THAT **REPORTS **`DEAD`**
**IS **THE **FIX.**
