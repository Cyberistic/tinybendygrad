index-arm: name EMPTIED, the fifth shape, and measure that a bare commit truncates

The caller's census said 44 armed paths. By the time this unit re-measured it was 32, and by
the time the classification finished it was 0 -- none of that is a clean bill of health and
none of it is this commit's doing. What is here is the shape the census was under-reporting.

EMPTIED is a subset of STALE, and the split matters. 12 of the 29 stale paths held git's
EMPTY blob `e69de29b` in the index while HEAD held 1-40 KB of content. `git ls-files --debug`
reads `flags: 0` on them, so they are NOT intent-to-add, which means the gate's own docstring
-- "git 2.50.1 REFUSES intent-to-add entries" -- does not apply to them. There was no name for
that, so there was no count for it.

MEASURED, not argued. No git command produces this entry: `update-index --cacheinfo` also
zeroes the stat cache, git sees the mismatch, re-reads the worktree and the shape never
happens. So `.agents/slop/armclass/plant-stat.py` forges it at the byte level -- empty blob,
stat cache still naming the worktree's real size, flags clear -- and bare-commits it. Result:
rc=0, `HEAD:keep.py` becomes the empty blob, and the 8,100-byte worktree file is left intact
and unrecorded. A STALE entry reverts a file. An EMPTIED entry deletes its contents.

The gate change is strictly additive: EMPTIED is computed as a subset of STALE, printed on its
own line, and enters neither `destructive()` nor any count. `checks/index-arm-gate.py --plant`
still returns A=PASS(0) and B=REFUSED(3), rc=0, and the plant above additionally requires the
real gate to PASS the clean repo and name EMPTIED on the forged one -- so the new shape cannot
be a line that never fires, and A cannot be softened to accommodate it.

THE CENSUS MOVED UNDER ME, AND THAT IS THE FINDING, NOT A PASS. Frozen at HEAD eae9ccb53f1a,
index written 18:10: deletion 3, stale 29, foreign 0, intent 624 -- 32 armed. Every one of the
32 was provably wrong (index corroborated by neither HEAD nor the worktree). At 18:37 the index
had been rewritten and all 32 reconciled; at 18:45 `ARMED 0`. `jj op log` names the writer:
`snapshot working copy` at 7 minutes ago, issued by another unit's `jj log`. So the arming is
self-healing by jj's own hand, which is a real property of this tree and NOT a reason to
ignore it -- the 12 EMPTIED paths were armed for at least half an hour, and every one of them
was one bare `git commit` away from committing a 0-byte file under a lying commit message.
`jj op log --no-graph` -- the command that produced that evidence -- is itself recorded as a
`snapshot working copy` op at the top of the log, so the mechanism is jj generally and not one
command, re-confirmed today.

I reset NOTHING, because by the time classification finished there was nothing provably wrong
left to reset. Per-path `git reset HEAD -- <p>` was the intended tool and never fired.

Also verified: my own reads do not arm what they inspect. `.git/index` was sha `d755130f3f3b3f66`
before and after running the gate and the classifier, mtime unchanged -- the read-only claim in
the gate's header is true of the code I added.

Scratch and evidence under `.agents/slop/armclass/`; `table-1837-frozen.txt` is the 32-row
classification, `table-now.txt` the post-state, `idx.stage`/`head.tree` the frozen census.