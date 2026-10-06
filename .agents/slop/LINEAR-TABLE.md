# THE LINEAR RULE TABLE — `tinybendygrad/uop/ops.bend`

Unit: build the linear rule table in `uop/ops.bend`. Nothing committed.
Detail in `.agents/slop/lintable/`:

| file | what |
|---|---|
| `01-WHAT.md` | what the table must do, `file:line` from `tinygrad/uop/ops.py` |
| `02-TABLE.md` | the table, with `ops.bend` line numbers |
| `03-PROBE.md` | the probe, its pairs, and the four defects it caught |
| `04-PLANT.md` | the plant and its paired disarm |
| `05-TOTALITY.md` | where the port is total and Python raises |
| `06-UNBLOCKED.md` | what actually unblocked, with the denominator |

Gate: `sh checks/lintable-gate.sh` — **36 rows, 3 lanes identical**
(CPython, bend interpreted, bend native).

---

## 1. THE PRE-EXISTING UNCOMMITTED DELTA IN `ops.bend`

`git diff origin/master -- tinybendygrad/uop/ops.bend` before my first edit:

```
@@ -4614,7 +4614,10 @@ def gate_kernel_sink(+ar: Arena, +x: U32) -> Bool:
-# PORTED -- `ops.py:1224 UOp.set` is `UOp.set` (this file). Four `set_*` rows
+# PORTED -- `ops.py:1224 UOp.set` is `UOp.set` (this file). The def, its fixture,
+# its four rows and its gate landed inside a CONCURRENT agent's commit rather than
+# one of mine, so the history does not attribute them; the write-up is here and at
+# the gate, which is where a reader lands anyway. Four `set_*` rows
```

**4 insertions, 1 deletion, and it is COMMENT-ONLY.** It is a provenance note about
`ops.py:1224 UOp.set` — the author recording that the def, its fixture, its four rows
and its gate landed inside a concurrent agent's commit, so the history does not
attribute them.

**It belongs to the `UOp.set` porting unit and it is NOT live work**: mtime 13:48:49,
which is over two hours before I started (15:50), and the file compiled clean both
before and after. It says nothing about the rule table. **Not committed, not reverted,
worked around** — my additions are at `ops.bend:3746-4008` and touch none of it.

## 2. PRE-EDIT BASELINES, CAPTURED BEFORE THE FIRST EDIT AND NEVER RE-RECORDED

```
lintable/BEFORE-ops.bend.sha256   907391462cfddf1554be4b0164289053b54469b3590e2c329c1676c29692e2a6
lintable/BEFORE-time.txt          1791118235
lintable/BEFORE-ops-gate.txt      "112 shared rows, 3 lanes identical" / "total bend rows = 315"
lintable/BEFORE-ops-set-gate.txt  "4 rows, 3 lanes identical"
./bin/bend tinybendygrad/LAWS/PROOF-ALL.bend   ->  ALL PROOFS CHECK
```

Marked suspect, not re-recorded. **After the edit both gate outputs are byte-identical
to their baselines** (`diff` clean) and `PROOF-ALL.bend` is still `ALL PROOFS CHECK`.

## 3. WHAT THE TABLE MUST DO — from `tinygrad/uop/ops.py`

`tinygrad/uop/ops.py` holds **four** `PatternMatcher`s, and all four are in one place:

| ops.py | name | pattern | body |
|---|---|---|---|
| **1896** | `_substitute` | `UPat(tuple(Ops), name="x")` | `lambda ctx,x: ctx.get(x,None)` |
| **1897** | `_pm_resolve_params` | `UPat(Ops.PARAM, name="p")` | `lambda ctx,p: ctx[p.arg.slot] if p.arg.slot >= 0 else None` |
| **1904** | `remove_all_tags` | `UPat(GroupOp.All, name="x")` | `lambda x: x.replace(tag=None) if x.tag is not None else None` |
| **1907** | `pm_drop_after` | `UPat(Ops.AFTER, name="a")` | `lambda a: a.src[0]` |

That is the whole of ops.py's rule-table surface, and until now **none of the four was
reachable**: `pm_dispatch` had three placeholder bodies (SINK, NOOP, CAST) and
`pm_dispatch_m` five.

Two more source lines carry the shape:

- **`ops.py:1602-1606`** is where a `PMEntry` comes from — `entry = [p, None, p.early_reject]`,
  then `entry[1] = <compiled fn>`, then `for uop in p.op: pdict.setdefault(uop, []).append(entry)`.
  The compiled function is the **tag**; the fan-out is why `PMEntry.ops` is a CLAIMED SET.
- **`ops.py:1480-1483`** computes the reject set from the pattern's FIRST SRC. All four
  patterns are built with `src=` omitted, so all four reject sets are **EMPTY** and
  `ops.py:1617`'s `if not early_reject.issubset(ler): continue` never skips any of them.
  Measured by CPython, not asserted.

And by calling CPython rather than reading:

```
$ python3 -c "from tinygrad.uop import Ops, GroupOp; print(len(tuple(Ops)), GroupOp.All == set(Ops))"
77 True
```

so `all_ops()`'s 77-entry literal is generated, and `lintable-oracle.py` re-measures it.

## 4. THE TABLE

```
tag 40   PMEntry{40, [OpsAFTER{}],  Nil{}}    ops.py:1907
tag 41   PMEntry{41, all_ops(),      Nil{}}    ops.py:1904
tag 42   PMEntry{42, [OpsPARAM{}],   Nil{}}    ops.py:1897
tag 43   PMEntry{43, all_ops(),      Nil{}}    ops.py:1896
```

**Three families, and every one is forced by a type, not a preference:**

| family | answer | ctx | rules |
|---|---|---|---|
| `_m` (existing) | `Maybe<&2, U32>` | `List<&2, U32>` | 40, 42 |
| `_sub` (new, 2 defs) | `Maybe<&2, U32>` | `Map<&2, U32>` | 43 |
| `_f` (new, 5 defs) | `Maybe<&2, Found>` | ignored | 41 |

`_sub` exists because **Bend's `Map` is String-keyed** and `_substitute`'s
`dict[UOp, UOp]` is keyed by the node. `_f` exists because tag 41 **mints**, and
`UOp.new` returns `Found{ar, i}` — the grown arena is part of the answer, and
`pm_rewrite_m` answers an index and no arena.

Tags 40-43 because tags **0..32 and 999** are already in use across the tree. Re-measured
after the edit: `grep -E 'PMEntry\{(40|41|42|43)[,}]'` outside `uop/ops.bend` returns
**nothing**, so no existing table is perturbed.

## 5. THE PROBE'S TWO NUMBERS, SIDE BY SIDE

A record binder shadows a same-named parameter and nothing says so — it compiled,
typechecked, reported its flag correctly and answered wrong for every input
(`r5_bad_passes=1` vs `r5_good_passes=5`). So every function this unit wrote got a
probe printing both spellings. Full set in `03-PROBE.md`; the load-bearing pairs:

```
MUST DIFFER
  pick_t_rule=0            pick_f_rule=1          <- through the RULE, and they disagree
  rat_tag_before=1         rat_tag_after=0        rat_strips=1   rat_keeps_untagged=0
  dat_src=1                dat_self=2             <- src[0] is 1, self is 2
  rp_is_param=1            rp_paramclaim_on_add=0
  sub_hit_node=4242        sub_miss_node=0
  sub_key_p2=13            sub_key_p5=14
  rp_fires_slot2=33        rp_fires_slot0=11      rp_fires_slot5_oor=0  rp_fires_wrong_op=0
  sub_has_on_zero=1        sub_has_on_unbound=0
  tag_none_on_none=1       tag_none_on_int=0      tag_none_on_str=0     tag_none_on_bool=0

MUST AGREE (two READERS of one fact; agreement IS the pass condition)
  rp_binder_slot=2         rp_param_slot=2
  rp_binder_slot5=5        rp_param_slot5=5
  all_ops_n=77             all_ops_claim_n=77     <- and CPython's len(tuple(Ops)) is 77
```

**The probe caught four defects, one of them in `ops.bend`:**

1. **`pm_r_tag_m.of`'s parameter was named `tagged` and passed `tag_is_none(...)`** —
   the name is the negation of the value. Compiled, typechecked, and answered
   *correctly* for every input. Renamed to `untagged`. A probe row written from
   `ops.py:1904`'s guard caught it, because the row and the code disagreed and the row
   was right about what the name claims.
2. `rp_is_not_param` named a negative and measured a positive — a tautology that would
   have passed with `op_is` returning `True{}` unconditionally.
3. `fx_p2()` and `fx_p5()` each built their own `Arena.empty()`, so both PARAMs were
   index 0 and `sub_miss_node` answered **4242 instead of 0**. A node-keyed map is only
   meaningful inside one arena.
4. Eleven identical fillers **interned to one node**, and `sub_key`/`sub_val` printed
   "2" and 2 — which is how I found that pair to be an **identity**, not a fixture
   problem: **a wider fixture cannot separate an identity.** It was deleted.

## 6. THE PLANT AND THE DISARM

One line, in a copy of the tree under `.agents/slop/lintable/plant/`:

```
-  Bool.pick(Maybe<&2, Found>, untagged, None{}, Some{made})
+  Bool.pick(Maybe<&2, Found>, untagged, Some{made}, None{})
```

`remove_all_tags` becomes its own negation. **The claim is untouched, so only the
bodies can see it** — which is what a rule-table gate is for.

```
lintable-gate: plant is ALL PROOFS CHECK, so it applied and did not abort
lintable-gate: plant moved these rows:
  pick_t_rule=0  pick_f_rule=1  rat_tag_after=0  rat_strips=1
  rat_keeps_untagged=0  rat_strips_n=1  rat_keeps_untagged_n=0
lintable-gate: and the GATE goes red on the plant, on these rows:
    rat_keeps_untagged_n=0  rat_strips_n=1  rat_tag_after=0
disarmed at .agents/slop/lintable/plant//tinybendygrad/uop/ops.bend
lintable-gate: disarm restored the baseline EXACTLY
```

Three things are checked before the red is believed: **it applied** (the planted file
is `ALL PROOFS CHECK`, so no silent abort); **it is not vacuous** (7 rows move, and the
script exits 1 otherwise); and **the gate itself goes red** against the same oracle
(exits 1 on a clean diff). `rat_tag_before`, `all_ops_*`, every `*_tab_*` row and every
other rule's rows did **not** move.

## 7. WHAT ACTUALLY UNBLOCKED — the denominator

```
$ awk 'NR>=82 && NR<=301 && /^def |^  def /' tinygrad/schedule/__init__.py | wc -l
15
```

**15 defs, and the audit's figure is right.** My own first pass said 14 because it
matched only `^def ` and missed `apply_binds` (`:110`), which is **indented** — a nested
def inside `resolve_linear_call`. A count that ignores indentation is short by exactly
the nested ones.

`grep -nE 'remove_all_tags|arg\.slot|ctx\[0\]\.get'` over the region returns four hits,
in **three defs** plus one table literal. That is the whole set:

**3 of 15** had the table as a blocker and no longer do:

| name | rule of the four | what the table now supplies | what still blocks it |
|---|---|---|---|
| `transform_to_call` (`:261`, rule at **`:267`**) | `remove_all_tags` by name | the body, as tag 41, via `pm_rewrite_f` — a family that did not exist | its `CallifyCtx` — **C2 untouched** |
| `resolve_linear_call` (`:103`) | `_pm_resolve_params`, inlined at `:98` | the full-slot body, as tag 42; the old tag 3 answered slots 0 and 1 only | its `(dict, tuple)` ctx — **C2 untouched** |
| `create_new_buffer` (`:90`) | `_substitute`, as `ctx[0].get(b, None)` | BOTH halves: a node-keyed map ctx (`_sub`) and a minting answer (`_f`) | `b.device`, `UOp.new_buffer` are other files' |

Plus, outside the 15, `pm_post_sched_cache` (`:96`) — whose two rules ARE the two above.

**12 of 15 were never behind the table:** `apply_binds`, `lower_sink_to_linear`,
`assert_all_same_devices`, `copy_kernel_to_store`, `simplify_copy_kernel`,
`contiguous_mops_to_view`, `is_store_after`, `collect_stores`, `canonicalize_alloc`,
`canonicalize_call_body`, `replace_input_buffer`, `create_linear_with_vars`. They are
behind their own rule bodies, behind `CallifyCtx` (clause C2), or behind plain
signatures with no table at all.

Tree-wide, **3 of the 4 rules have a live caller outside `uop/ops.py`**, and two are
exact type matches for the families added: `tinygrad/tensor.py:204` calls
`pm_drop_after` with **no ctx** (tag 40's exact shape, and three lines is all it
needs), and `tinygrad/codegen/simplify.py:32` calls `_substitute` with a
`dict[UOp,UOp]` ctx (tag 43's exact shape). `_pm_resolve_params` has **zero** call
sites and is reached only through the hand-inlined copy at `schedule/__init__.py:98`.

**So the measurement partly inverts the priority argument.** `pm_dispatch_m` went from
three reachable bodies to five, plus two new families — and the table was never the
binding constraint on **12 of the 15**. The remaining order is **rule bodies → ctx**,
and `CallifyCtx` (a dataclass carrying a list, a dict, a set and another list) is the
next thing to measure.

## 8. HONEST LIMITS

- **`ops.py:1618`'s `ret is not uop` is NOT ported.** Python skips a rule whose answer
  IS the node and keeps scanning; `pm_scan_m`/`pm_scan_f` stop on the first `Some{}`.
  Every table here has one entry so the scan ends either way, and the difference is
  unobservable **today** — but a five-entry table would see it.
- **A node-keyed `_substitute` map is per-arena** (finding 3 above). Two fixtures from
  two `Arena.empty()`s collide at index 0.
- **The port is total where CPython raises**, twice: `_pm_resolve_params` on an
  out-of-range slot (`KeyError: 5`, measured) and `pm_drop_after` on a zero-src `AFTER`
  (`IndexError`). Detail in `05-TOTALITY.md`.
- **`all_ops()` is a 77-entry literal.** It is generated from CPython and re-measured
  by the oracle, but it is a literal, and adding an `Op` constructor to `ops.bend`
  without adding it here would leave the claim short. The `all_ops_n` /
  `all_ops_claim_n` pair cannot catch that on its own — it only proves the list is
  self-consistent.