# BATCH 2 STATUS, and the MEASUREMENT that says what is left

MEASURED 2026-11-18, by running the tree's own instruments.

## THE CENSUS, and where it moved

| reading | blocks | lines |
|---|---|---|
| the BASELINE (the cut's target) | 10,549 | 85,815 |
| at my start | 10,383 | 79,054 |
| now | 9,195 | 58,344 |

NARRATION is down to 5,229 blocks / 17,354 lines. THE KEEP SET (DIFFERENCE +
WEIRD + MEASURED) is 3,966 blocks / 40,290 lines, and IT HAS NOT BEEN TOUCHED:
it is the set the RULE keeps, and the cut took 24,000 lines out of NARRATION
and nothing out of the KEEP SET.

## THE COMPILE GATE, on the whole tree

`.venv/bin/python checks/port-compile-gate.py --rows .agents/slop/comments/batch2/compile.rows`

    CENSUS      COMPILES=189
    CENSUS      COMPILES-AS-C=3
    CENSUS      COLD-BY-DESIGN=5
    CENSUS      FINDING=1
    DENOMINATOR population=198  compiled=192  cold-by-design=5  findings=1  unmeasured=0
    COST        336.5s for 198 file(s) = 1.70s per file, ONE bend at a time.

`unmeasured=0` is the row that says the census saw EVERY file. THE FIVE
COLD-BY-DESIGN ARE THE STANDING CLASSES (`LAWS.bend` declares it is not a
proof yet; `sz.bend`, `imagenet.bend`, `live.bend`, `device.bend` rely on
unsafe or foreign code) and the THREE COMPILES-AS-C are the ones the compiler
emits `C` for anyway.

## THE ONE FINDING IS NOT MINE

`FINDING tinybendygrad/renderer/kuconv.bend` -- `expected : cstyle.KU with 8
fields / observed : C.KU{...7 fields}`.

**MEASURED, AND IT IS PRE-EXISTING:** I put HEAD's bytes back into the file
(`git show HEAD:tinybendygrad/renderer/kuconv.bend`) and ran
`bin/bend --check-only`: THE IDENTICAL ERROR. So the defect is in HEAD and my
comment cut did not make it.

**AND THE CAUSE IS NAMED:** `cstyle.KU` has EIGHT fields (`op, dtype, addr,
numel, shape, arg, srcs, cc` -- `cstyle.bend:53`) and `kuconv.bend:275`
constructs SEVEN. The `cc` field was added by `2cd82bd15 PARITY 96: the
piece-list transformation lands` and `kuconv.bend` was never updated.

**THIS IS NOT MY BUG TO FIX INSIDE A COMMENT-CUT BATCH.** It is a real
port defect that a comment cut must not mask and must not be blamed for.

## THE WORKING COPY

28 files, **+622 / -1311**, and EVERY ONE OF THEM IS COMMENT-ONLY: the
per-file check (`git diff -U0` minus `#` lines minus blanks) is EMPTY for all
28. `tinybendygrad/uop/ops.bend.new` is NOT a port file -- it is another
unit's 11,402-line tracked scratch file, and it is the only file in the tree
with a non-comment diff.

## THE CORPUS, AND WHY IT IS NOT A VERDICT ON THIS TREE

`runs/graphcmp/D/D0-run-summary.txt`, 2026-11-18 13:06:

    graphs=38 graphs-answered=38 graphs-agree=38 graphs-disagree=0 byte-identical=38
    substrate-start=f179c412bb0bbd3bf3c18d751117a2ed4e2761178cb670ba387d30dd3b1591de
    substrate-end=436a84da5b4ebb5ed73f9856156f36edbb38ce0415ae18e858ed3430cc6a2527

**THE TWO SUBSTRATE DIGESTS DIFFER, SO THE RUN STRADDLED A `.bend` EDIT.** The
tree was being written while the corpus ran -- `find tinybendygrad -name
'*.bend' -newermt '-3 minutes'` names five files touched in the last three
minutes. AND `D0-repro.txt` IS ABSENT, so `gates/corpuswitness-gate.py`
answers `witness.fresh=REFUSED`, `witness.substrate=REFUSED`,
`verdict.reported=REFUSED`, and `claim=FAIL`.

THE LIVE SUBSTRATE IS `80748102c3ecd8266ab6c9b0560f1d62404db746f9fd7df6b48bfba988a2cc6b`,
which is NOT the recorded end digest either. **THE CORPUS IS GREEN AND IT IS
NOT A CERTIFICATE, AND THE REASON IS THE TREE IS STILL MOVING.** The verdict
`38/38 agree` is a real measurement of 38 graphs; it is not a measurement of
THIS tree, because the tree moved under it.

## WHAT THE NEXT BATCH IS

THE REMAINING NARRATION MASS, by the census's own ranking:

    uop/fold.bend          308 narration / 439 total
    uop/ops.bend          228 narration / 394 total
    uop/symbolic.bend     221 narration / 447 total
    runtime/support/nv/nvdev.bend   143 / 160
    runtime/ops_metal.bend           140 / 177
    runtime/support/am/ip.bend       131 / 162
    runtime/support/usb.bend         129 / 141
    sz.bend                          123 / 123
    helpers.bend                    112 / 150

`sz.bend` IS THE TREE'S OWN "COLD BY DESIGN" FILE (7 defs rely on unsafe or
foreign code) and it is 123 of 123 blocks NARRATION -- but it is a 1,108 MB
compile, so it is a SEPARATE batch, not a batch-3 file.
