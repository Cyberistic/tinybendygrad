four-caches: **THREE **CACHES **OF **THE **ONE **CORPUS **EXIST **AND **THE **GATE **BUILT **TO **SAY **WHICH **IS **AUTHORITATIVE
**READS **THE **ONE **THAT **NOTHING **IN **THE **TREE **OWNS** — **AND **THE **LINE **THAT **MAKES **IT **INVISIBLE **IS **ONE **LINE **OF
`.gitignore`**

```
location                                     files  gitignored  tracked  vs live  keyed
checks/rows-<g>-<s>.rows  <- census.py:133      69        YES        0     matches   2 of 68
checks/rows/rows-<g>-<s>.rows  (published)      68         no       68     matches   never read
oracles/rows-<g>-<s>.rows                        54         no    tracked   STALE    no generator
```

**`.gitignore:167` **IS **`checks/rows-*.rows`**, **AND **THAT **SINGLE **LINE **IS **THE **CAUSE**: **ON **THIS **TREE **28,411 **FILES
ARE **IGNORED **AND **4 **ARE **UNTRACKED **NON-IGNORED** — **A **RATIO **OF **~7,000:1**, **AND **THE **PRESCRIPTION **IN
`AGENTS.md` **THAT **IGNORED **IS **~200x **UNTRACKED` **IS **NOW **OFF **BY **MORE **THAN **AN **ORDER **OF **MAGNITUDE`** *** **AND
`git ls-files --others --exclude-standard` **— **THE **ONLY **CORRECT **"WHAT **DOES **NOTHING **OWN**" **QUESTION** — **RETURNS
**`0` **FOR **ALL **69**, **SO **EVERY **SWEEP **THAT **ASKED **IT **REPORTED **THEM **CLEAN**.**\n\n**AND `census.py`'S `rc=3` **IS **HONEST,
AND **ITS **REASON **IS **THE **DEFECT**: `checks/rows-key.rows` **HOLDS **`2` **ROWS** — `flip py`, `flip bend` — **AND **THEIR
sha256 **IS **THE **CURRENT **`.agents/slop/graphcmp.bend`** (`2e180103…`), **SO **THE **KEYING **WORKS**; **BUT **`66` **OF **68
**SLOTS **HAVE **NO **KEY**, **SO **THE **GATE **CANNOT **SAY **THEY **ARE **CURRENT**, **SO **IT **REFUSES**
(`:136 return ("STALE", 0, None, set())  # served NOTHING`)** *** **THAT **IS **`whosecache`'s** OWN **RULE **APPLIED
**CORRECTLY** — **AUTHORITY **NEEDS **BOTH **HALVES **OF **THE **GENERATOR: **THE **WRITE **PATH **AND **THE **ABILITY **TO **SAY
**THE **SLOT **IS **STALE`** — **AND **THE **KEY **FILE **IS **GITIGNORED **BY **THE **SAME **LINE**, **SO **A **CACHE **THAT
**CANNOT **SAY **IT **IS **CURRENT **CAN **NEVER **LEARN **TO**: **THE **REFUSAL **IS **SELF-SEALING.**\n\n**AND **I **MADE **`whosecache`'s**
**NAMED **MISTAKE **THIRTY **SECONDS **AFTER **BEING **TOLD **IT**: **I **RAN **A **HAND **CENSUS **COMPARING **CACHED **BYTES
**TO **A **LIVE **GENERATION **AND **REPORTED **"0 **OF **68 **SLOTS **DIFFER **— **THE **CORPUS **IS **CURRENT."** **THAT **IS
**CONTENT **RESEMBLANCE**, **AND **THE **REPORT **I **HAD **JUST **LANDED **(`whosecache`) **SAYS **IN **ITS **OWN **WORDS: "CONTENT
**RESEMBLANCE **IS **NOT **AUTHORITY."** *** **I **READ **A **QUESTION **THE **INSTRUMENT **EXISTS **TO **ANSWER, **ANSWERED **A
**DIFFERENT **ONE**, **AND **TREATED **THE **CLEANER **NUMBER **AS **THE **FINDING** — **WHICH **IS **`prune4`'s** "A **MEASUREMENT
**THAT **READS **NOTHING **PRODUCES **A **PERFECTLY **CLEAN **NUMBER", **AT **THE **TWELFTH **SCALE**.\n\n**AND **THE **CORPUS
**ITSELF **DOES **SURVIVE **A **PORT **EDIT**, **WHICH **IS **THE **MEASUREMENT **THAT **DISTINGUISHES **"STALE **BECAUSE **THE
**PORT **MOVED" **FROM **"STALE **BECAUSE **IT **WAS **WRITTEN **BEFORE **THE **FIX"**: **MEASURED **WITH
**`tinybendygrad/schedule/rangeify.bend` **MODIFIED **IN **THE **SAME **MINUTE**: **34 **OF **34 **GRAPHS **BYTE-IDENTICAL,
**FRESHLY **GENERATED, **386 **ROWS **x **2 **LANES, **DIFFER **NONE**.\n\n**AND **THE **FIX **IS **NOT **"REFRESH **THE **CACHE"** — **THE
**TRACKED, **PUBLISHED **SET **(`checks/rows/`, `68` **FILES**, **WHICH **I **REGENERATED **THIS **SESSION **TO **34 **OF **34
**BYTE-IDENTICAL**) **IS **NEVER **READ **BY **THE **INSTRUMENT **BUILT **TO **ANSWER **THIS **QUESTION**, **BECAUSE **IT **READS
**A **SIBLING **PATH **DISTINGUISHED **ONLY **BY **A **TRAILING `/`**, **AND **THAT **SIBLING **IS **INVISIBLE **TO **GIT** —
**A **POPULATION **DEFINED **BY **A **SUFFIX **INSTEAD **OF **A **DIRECTORY**, **WHICH **IS **THE **`suffixset`/`findtype` **CLASS
**THIS **PROJECT **HAS **NAMED **SIX **TIMES** **AND **HERE **IT **IS **A **TRAILING **SLASH**.\n\n**EITHER **THE **GATE **KEYS **THE
**TRACKED **SET, **OR **THE **KEY **FILE **STOPS **BEING **GITIGNORED. **THE **FIRST **IS **CORRECT**: **A **PUBLISHED **SET
**THAT **IS **IN **THE **TREE **MUST **BE **THE **SET **THAT **CAN **BE **CHECKED** — **AND **THE **DENOMINATOR **TO **REPORT
**WITH **THE **FIX **IS **68 **SLOTS **OVER **34 **GRAPHS, **OF **WHICH **`2` **ARE **KEYED **TODAY**.\n\n**UNIT **`stalecites` **LANDED**
**IN **`28ce6f9e8389`**, **AND **THE **THIRTEENTH **ARMED **INDEX **WAS **FOUND **THREE **SECONDS **AFTER **IT**: **30 **STAGED
**ENTRIES, **29 **OF **THEM **DELETIONS, **0 **EMPTY **BLOBS** — **A **BARE **`git commit` **WOULD **HAVE **DELETED **29 **OF **THE
**30 **ROW **FILES **JUST **COMMITTED** — **A **FOURTH **SHAPE**, **BECAUSE **`git ls-files --stage` **RETURNED **NOTHING **FOR
**THOSE **PATHS**: **ABSENT **FROM **THE **INDEX **ENTIRELY, **NOT **PRESENT-AND-EMPTY.**\n\n**AND **THE **THIRTEENTH **PROVES **THE
**CAUSE **IS **CONTINUOUS**, **NOT **PER-MISTAKE**: **IT **RE-ARMED **AFTER **`git read-tree HEAD`** **ON **THE **DEFAULT **INDEX.**
