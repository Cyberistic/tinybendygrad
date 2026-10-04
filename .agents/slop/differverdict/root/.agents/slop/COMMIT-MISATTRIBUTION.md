# COMMIT MISATTRIBUTION -- a ledger

Written because the defect was found TWICE IN TWO COMMITS and both times by a
unit that had to say "this is not my commit."

## THE MECHANISM

The coordinator's procedure was:

```
jj describe --stdin < msg      # describes @
jj split <paths>               # moves <paths> to a NEW commit; @ becomes the rest
```

`jj split` does NOT clear the remainder's description. **Both halves carry the
message.** The child carries the files; the parent carries nothing and is a false
claim -- a commit that says "I did X" and does nothing.

**32 EMPTY COMMITS ON master CARRY SUBSTANTICATIVE MESSAGES.** Measured over the
60 most recent commits, `git show --stat` file count == 0 and a non-empty subject.

## THE WORSE HALF: SPLIT-BY-PATH DOES NOT BOUND THE MESSAGE

When a commit sweeps in files it does not mention, the work becomes
**unattributable** -- no commit describes it, and `git log -S` points at an
unrelated one. Two instances, both VERIFIED:

| commit | its subject says | it actually carries |
|---|---|---|
| `b8897fd4` | "UNCHANGED has been UNDECIDABLE, because no baseline recorded a load" | `runtime/support/nv/nvdev.bend` -- **the `minor_extended_revision` transposition FIX** (2 hunks) |
| `0056b7845` | "slop(llvmir): 147 measurements were unreachable under a green verdict" | `reader-fork-census.py`, `reader-fork-convert.py`, `reader-guard.py`, `reader-contracts.tsv`, `reader-fork-census.txt`, `reader-registry.py`, **and the 19 converted readers** |

`0056b7845` is the whole forked-reader programme: the 156 -> 38 correction, the
44,345-line `py=`-tail load, and the guard that caught the 157th reader live.
**No commit describes it.** Its unit's report is the only record.

## WHAT WAS CAUGHT, AND BY WHOM

Both were caught by units that checked `git log -S` instead of assuming their
edit was uncommitted. The second unit reported the collision rather than
re-committing, which is the only reason it is visible at all.

## THE CORRECTED PROCEDURE

1. **Split FIRST, describe SECOND, and describe the CHILD explicitly.**
   `jj split <paths>` then `jj describe -r @- --stdin < msg`.
2. **Verify the child carries files and the parent does not**, before bookmarking:
   `jj diff -r @- --summary | wc -l` and `jj diff -r @ --summary | wc -l`.
3. **Never `jj describe` an unqualified `@`** while other units have live changes.
   That is what lets a sweep happen at all.
4. **A unit that suspects its work is misattributed should SAY SO and not
   re-commit.** Duplicating the content fixes nothing and hides the defect.

## WHY THIS IS NOT BEING REWRITTEN

The standing rule is never amend and never force-push. These 32 commits are
pushed. Correcting them would require a history rewrite, so the ledger stands in
their place: **an empty commit on master is known to be an artefact of this
procedure and carries no claim.**

## THE EMPTY TWINS, first 20 of 32
1d19d4eed9800d6adc9fb44b737754caff0c1a8a  slop(nvdev): the transposition was DETECTABLE. `wid` wraps, so 4 bits was wrong.
de6a46a22c97fecb69cf322fe44f126c8da1549e  slop(eq): the `=`-name class is CLOSED tree-wide. 302 names cost a measurement, 28 were merely misnamed, and 31 of them were never names at all.
e7317b7eb76ce55d10d7a673ee6563e29d86b972  slop(graphcmp): 23 -> 34 of 77 ops, and the py side stopped being hand-written
a30ab5005a05187f9e8f279217f625f5c4db31ca  slop: Bend calls shared libraries. The FFI wall was never a wall.
34ccb08da47f7fe559369026ba822719711f8157  slop(fold): the symbolic-dim wall was TWO defs, and one flag meant TWO OPPOSITE things
74bce5e2765915e53e747216185d1ba958ceaa73  slop: the staged guard I installed was VACUOUS, and two more ports are false
d14c09808c408e402644055da48ee1d04624c990  ops.bend: two blockers named, one of them a LANGUAGE change
9e118732a2f7df7694cb6837a762a0fe66b78ed1  slop(llvmir): 147 measurements were unreachable under a green verdict
3b63f5a1e75f7f2c33513bb511aaf5a491baadd8  prepare: label the two captures as STALE, because a capture is not a gate
5996c6e6e8215e1f784116531422e2f98f489fc3  slop(cstyle): 8 row names carried `=`, and two measurements were unreachable
9901d7d4189fdd144096443ec02e6fe1ab5e7dc4  slop: staged mutation harnesses, and one guard firing on a real concurrent write
99a8f8da3c20498a73c43b60e37494fc46188d7e  slop: UNCHANGED has been UNDECIDABLE, because no baseline recorded a load
6add7196d003f313542ac1a722977dff987a62fc  slop(cstyle-gate): rows_shipped was not rows(), and the green survives anyway
d6b9bb5d628518e279e7d387b43c117bcad3b2db  slop(rebase-gate): a starved lane is the slow lane, and that is the tell
4a9fe1d5ec9960a904838922064ef27c1e16c13d  slop(rebase-gate): a starved lane is the slow lane, and that is the tell
cef560a0eb1bef17b2d6b95f79f89068f23f1293  slop(rebase-gate): a lane's verdict is about its IMPORT CLOSURE, not the file
2cf3b7ca4fe567c84f9705faea9dfa0e50f69bc1  slop(validate): dv_where duplicated a node in the WALK, not the arena
66d4dc7e9ff7ae9c0a743382beb2c9b60eb8980c  slop(wire): an empty cache must not read as a fresh measurement
c89421bc89e5e28bc435c301d3ab7c2e75900c4b  A SILENT UNIT IS NOT A FAILED UNIT, AND NOT A SUCCESSFUL ONE
e9b274e11773fa6944490efa4b69e9104e580a44  slop(rebase-gate): name the cause of every BROKEN, and reconcile against the selftest

... and 12 more.
