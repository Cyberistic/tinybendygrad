# THE PLANT AND ITS PAIRED DISARM

    sh .agents/slop/lintable/lintable-gate.sh --plant    # plants, proves red, disarms
    sh .agents/slop/lintable/lintable-gate.sh --disarm   # the standalone check

Both live in `lintable-gate.sh`, so a red cannot be reported without the green that
puts it back, and both are the **same edit at the same place**. A plant that lands
somewhere else proves nothing: three controls in this project were found disarmed, one
leaving six lanes green.

## WHAT IS PLANTED

One line, in a COPY of the repo tree under `.agents/slop/lintable/plant/`:

```
  pm_r_tag_m.of:
-   Bool.pick(Maybe<&2, Found>, untagged, None{}, Some{made})
+   Bool.pick(Maybe<&2, Found>, untagged, Some{made}, None{})
```

`remove_all_tags` becomes its own negation: it strips the tag off an UNTAGGED node and
keeps it on a TAGGED one. `ops.bend:3918-3919`.

**Why this mutation and not another.** The claim (`all_ops()`) is untouched and every
necessary-condition row stays green — only the rule's BODY changes. So it is the one
mutation here that a rule-table gate exists for: a mutation that only the bodies can
see.

## THE THREE THINGS THAT ARE CHECKED BEFORE THE RED IS BELIEVED

1. **THE PLANT APPLIED.** `bend --check-only` on the planted file must print
   `ALL PROOFS CHECK`. A mutation table that aborts is not the table: two units this
   session published a green mutation for a mutant that never applied — one calling
   `U32.nand`, which does not exist in Bend 2.0.35 and silently aborted a 28-entry
   table at entry 19.
2. **THE PLANT IS NOT VACUOUS.** Seven rows move, and the script exits 1 if the
   planted lane is byte-identical to the baseline. This is the vacuous-plant case to
   avoid — "flipping a value whose other operand was already `True` left a port's
   sha256 identical", and reading that as "the gate is blind" would have been a false
   finding.
3. **THE GATE ITSELF GOES RED.** The planted lane is diffed against the SAME oracle and
   a clean diff is treated as a failure of the script. "The rows moved" is not the same
   claim as "the gate fails"; only the second says the harness can see a wrong answer.

## WHAT MOVED

Bend lane, against the baseline:

```
  pick_t_rule          0 -> 1
  pick_f_rule          1 -> 0
  rat_strips           1 -> 0
  rat_keeps_untagged   0 -> 1
  rat_tag_after        0 -> 1
  rat_strips_n         1 -> 0
  rat_keeps_untagged_n 0 -> 1
```

Gate lane (the three shared rows that carry the rule's behaviour):

```
  rat_strips_n         1 -> 0
  rat_keeps_untagged_n 0 -> 1
  rat_tag_after        0 -> 1
```

Rows that did **not** move, and why that matters: `rat_tag_before` (the fixture, not
the rule), `all_ops_n` / `all_ops_claim_n` (the claim), every `*_tab_*` row (the table
shape), and every `pm_drop_after` / `_pm_resolve_params` / `_substitute` row. A mutation
that moves only the rows it should is the property; one that moves everything is a
change detector.

## THE DISARM

`sh .agents/slop/lintable/lintable-gate.sh --plant` disarms itself and then checks
that the disarmed lane is byte-identical to the baseline, exiting 1 if it is not. The
separate `--disarm` mode is the standalone check and it exits 0 **only** because
neither arm of the mutation is present in the live `ops.bend`:

```
lintable-gate: live ops.bend carries neither arm of the mutation
```

The plain gate makes the same check, so a planted live tree cannot be reported green.

## WHY A TREE COPY AND NOT `$TMPDIR`

A `$TMPDIR` scratch copy cannot resolve a relative import — it produced 22 phantom
blind spots in one unit. `plant/` keeps the relative depth (`../../../tinybendygrad/…`
from the probe), and the live tree is never patched from a harness.