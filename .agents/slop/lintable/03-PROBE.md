# THE PROBE — every row prints both spellings, and the pairs are labelled

    ./bin/bend .agents/slop/lintable/lintable-probe.bend [DANGLING 2026-10-05: this path DOES NOT EXIST. It was pruned, or moved, or never committed -- do not assume which. `checks/repro-paths.py` lists all of them.]
    sh checks/lintable-gate.sh        # 36 rows, 3 lanes identical

Baseline: `.agents/slop/lintable/AFTER-probe.txt` (captured AFTER the last edit and
never re-recorded; the pre-edit baselines are `BEFORE-ops-gate.txt` and
`BEFORE-ops-set-gate.txt`).

## FIRST: A PAIR MUST **DIFFER**, OR A PAIR MUST **AGREE** — AND THE FILE SAYS WHICH

The brief asks for pairs that show two DIFFERENT numbers. Three of mine cannot, and
saying so is more useful than forcing them:

| kind | what it is | example |
|---|---|---|
| **MUST DIFFER** | a shadowed binder, an inverted `Bool.pick`, or a wrong node changes one side only | `pick_t_rule` / `pick_f_rule` |
| **MUST AGREE** | two READERS of one fact — agreement IS the pass condition | `rp_binder_slot` / `rp_param_slot` |
| **IDENTITY** | the two sides are the same value by construction and NO fixture can separate them | the deleted `sub_key` / `sub_val` pair |

## THE PAIRS THAT MUST DIFFER — and do

```
pick_t_none=0            pick_f_rule=1        <- through the RULE, and they DISAGREE
pick_f_some=1            rat_tag_after=0
pick_t_rule=0            rat_strips=1        rat_keeps_untagged=0
rat_tag_before=1         rp_is_param=1       rp_paramclaim_on_add=0
dat_src=1                dat_self=2          <- src[0] is 1, self is 2
dat_misses=0             sub_key_p2=13       sub_key_p5=14
rp_binder_slot=2         rp_binder_slot5=5   tag_none_on_none=1
rp_param_slot=2          rp_param_slot5=5    tag_none_on_bool=0  _on_int=0  _on_str=0
rp_fires_slot2=33        rp_fires_slot0=11   rp_fires_slot5_oor=0  rp_fires_wrong_op=0
sub_hit_node=4242        sub_miss_node=0     sub_has_on_zero=1  sub_has_on_unbound=0
sub_answer_on_add=77     sub_answer_unbound_add=0
```

## THE PAIRS THAT MUST AGREE — and do

```
rp_binder_slot=2           rp_param_slot=2
rp_binder_slot5=5          rp_param_slot5=5
rp_binder_slot_nonparam=4294967295   rp_param_slot_nonparam=4294967295
all_ops_n=77               all_ops_claim_n=77
```

`all_ops_n` is `List.length` over the literal and `all_ops_claim_n` counts the same
list; they are equal only if `all_ops()` is right, and 77 is CPython's
`len(tuple(Ops))` — measured, not typed.

## WHAT THE PROBE CAUGHT — FOUR DEFECTS, THREE OF THEM IN THE PROBE ITSELF

**1. A PARAMETER NAME THAT IS THE NEGATION OF ITS VALUE.** `pm_r_tag_m.of`'s
parameter was named `tagged` and was being passed `tag_is_none(...)`. It compiled, it
typechecked, and it answered CORRECTLY for every input. `pick_t_rule` / `pick_f_rule`
are written from `ops.py:1904`'s guard — "True means the node HAS a tag, so it gets a
replacement" — and the implementation answered the other way round, so the row and the
code disagreed and **the row was right about what the name claims.** Renamed to
`untagged` (`ops.bend:3918`). This is the shadowed-binder defect with better manners,
and `codegen/__init__.bend:176` had already documented the shadowing half.

**2. A ROW THAT NAMED A NEGATIVE AND MEASURED A POSITIVE.** `rp_is_not_param` called
`op_is(ar, i, OpsADD{})` on an ADD, so it printed 1 beside the PARAM row's 1. A
tautology: it would have passed with `op_is` returning `True{}` unconditionally. Now
both rows ask "is this a PARAM?" and differ (1 / 0).

**3. TWO FIXTURES IN TWO ARENAS COLLIDE AT INDEX 0.** `fx_p2()` and `fx_p5()` each
built their own `Arena.empty()`, so both PARAMs were index 0, and
`sub_miss_node` looked index 0 up in a map holding index 0 and answered **4242 instead
of 0**. `sub_hit_node` and `sub_miss_node` were the SAME query and both were green.
**A node-keyed map is only meaningful inside one arena** — that is about the port's
identity, not about the rule, and it is the reason `_substitute`'s `dvars` is per-arena.

**4. ELEVEN IDENTICAL FILLERS ARE ONE NODE.** The arena interns, so a chain of eleven
`OpsNOOP` mints held a single node and the slot-2 PARAM landed on index 2 — and then
`sub_key` printed "2" and `sub_val` printed 2 and the pair agreed. Two fixture sizes
were tried before the pair was deleted; see the next section.

## THE PAIR THAT WAS DELETED FOR BEING VACUOUS

`sub_key` (a String) against `sub_val` (a U32), expected to differ. **They cannot.**
`sub_key` IS `U32.show(idx)`, and printing a String prints its characters, so the row
is an identity — 13 beside 13 at every index, and "12" beside 12 before that. Making
the fixture wider (eleven distinct fillers, to push the index off a single digit) is
the measurement that **proved the pair vacuous rather than badly chosen: a wider
fixture cannot separate an identity.** It is the same shape as a plant that leaves a
sha256 identical because the other operand was already true.

What replaced it is a pair that can differ and does: the same key function applied to
two nodes in one arena, `sub_key_p2=13` and `sub_key_p5=14`. If the rule ever read the
wrong node — a shadowed `self`, a stale index, a binder that took a different field —
one of these moves and the other does not.

## THREE MORE VACUOUS ROWS FOUND AND FIXED IN THE PROBE

- `sub_zero_is_a_hit` printed 0 for BOTH a hit and a miss: the map's value was 0 and
  `hit(None{})` is also 0. Replaced by `sub_has_on_zero=1` / `sub_has_on_unbound=0`,
  which read `Map.has` — the reason `ops.bend:7562` says the `has` is not
  belt-and-braces.
- The `_n` companions were first written `hit(...) > 0`, which cannot tell "answered 0"
  from "did not answer" — the same defect. They read the `Maybe` now.
- `pm_drop_after` on a zero-src `AFTER` answers `0` (the arena's bottom). Python raises
  `IndexError`. Row `dat_zero_src=0`; see `05-TOTALITY.md`.

## THE THREE LANES

`lintable-gate.sh` runs CPython, bend interpreted, and bend native, and the diff is the
test. 36 shared rows agree. 33 further rows are printed by the bend lane and are
**excluded from the diff with a `#bend_only_<name>: <reason>` line in the oracle** —
`ops-gate.sh`'s convention. A row only one lane can decide is not a check.

The oracle prints the exclusion list over `set(out) | set(BEND_ONLY)`, not over `out`
alone. Iterating `out` silently drops every exclusion the oracle no longer emits, and
a silently-dropped exclusion is a lane that gets diffed against a row it should not
carry — which is what happened here for five rows before it was fixed.