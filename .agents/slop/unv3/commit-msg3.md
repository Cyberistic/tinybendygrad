slop: the corpus digests, and the BASE copy is a convenience and not a requirement

The three digests are the receipts of three DIFFERENT trees, and the report says
which is which: the frozen `git archive` of HEAD, the live tree with this slice edits,
and the tree at this slice commit. A `.bend` edit MOVES the corpus freshness pin, so
the digests are receipts and not a standing fact.

`check.sh` no longer REQUIRES the base copy (479 MB, not committed): it copies the base
WHEN IT IS THERE and measures the LIVE port either way, because the base copy is a
convenience and the LIVE tree is the measurement.
