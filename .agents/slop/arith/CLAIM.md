# arith-unit — CLAIM 2026-10-04

Unit: `arith` (reaching CDIV CMOD CMPEQ FDIV NEG SUB).

I CLAIM (read-only first, edits only after re-measuring and only if needed):
  graphcmp.py        .agents/slop/graphcmp.py
  graphcmp.bend      .agents/slop/graphcmp.bend
  graphcmp-oracle.py .agents/slop/graphcmp-oracle.py

Other units are live on the substrate (runtime/**, uop/**, renderer/**,
tinygrad/**, LAWS/**, PROOF*.bend, helpers.bend, e2e*, reader-*). I will not touch those.
Rule prefix for this unit: ARITH-n.

STATE: created before any reads of the differ. No edits to the claimed three yet.
