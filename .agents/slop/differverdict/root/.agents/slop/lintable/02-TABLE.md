# THE TABLE — `tinybendygrad/uop/ops.bend`, and where each line is

## WHAT WAS ADDED, IN FILE ORDER

| ops.bend line | what | upstream |
|---|---|---|
| 3746-3759 | the block header: `ops.py:1602-1606` is where a `PMEntry` comes from; `ops.py:1480-1483` is why all four reject sets are empty | `ops.py:1602`, `ops.py:1480` |
| 3761-3768 | `all_ops()` — the 77-entry claim, generated from CPython | `ops.py:1896`, `ops.py:1904`, `uop/__init__.py:135` |
| 3777-3783 | `tag_is_none` | `ops.py:1904` |
| 3790-3792 | `pm_r_drop_m` — **tag 40** | `ops.py:1907` |
| 3808-3820 | `pm_r_rp_m.slot` / `.at` / `pm_r_rp_m` — **tag 42** | `ops.py:1897` |
| 3831-3832 | two new cases in `pm_dispatch_m.go` (40, 42) | — |
| 3918-3923 | `pm_r_tag_m.of` / `pm_r_tag_m` — **tag 41** | `ops.py:1904` |
| 3942-3948 | `pm_sub_m.of` / `pm_sub_m` — **tag 43** | `ops.py:1896` |
| 3961-3972 | the four tables: `pm_substitute`, `pm_resolve_params`, `pm_remove_all_tags`, `pm_drop_after_table` | the four `PatternMatcher`s |
| 3988-4008 | the `_f` family: `pm_try_f.go` / `.of` / `pm_try_f` / `pm_scan_f` / `pm_rewrite_f` | `ops.py:1613-1619` |

## THE FOUR ENTRIES, AS LITERALS

```
tag 40   PMEntry{40, [OpsAFTER{}],  Nil{}}     ops.py:1907  pm_drop_after
tag 41   PMEntry{41, all_ops(),      Nil{}}     ops.py:1904  remove_all_tags
tag 42   PMEntry{42, [OpsPARAM{}],   Nil{}}     ops.py:1897  _pm_resolve_params
tag 43   PMEntry{43, all_ops(),      Nil{}}     ops.py:1896  _substitute
```

`Nil{}` in the third slot is `ops.py:1480-1483`'s arithmetic, not a shortcut: all four
patterns are built with `src=` omitted, so `upat_match == []` and `early_reject ==
set()`, and `ops.py:1617`'s subset test therefore never skips any of them. Measured by
CPython in `lintable-oracle.py`: every `p.early_reject` has length 0.

## THREE FAMILIES, AND EVERY ONE IS FORCED BY A TYPE

| family | answer | ctx | rules | why not in another family |
|---|---|---|---|---|
| `_m` (existing) | `Maybe<&2, U32>` | `List<&2, U32>` | 40, 42 | — |
| `_sub` (new, 2 defs) | `Maybe<&2, U32>` | `Map<&2, U32>` | 43 | `Map` is String-keyed (`Map.set(a, -V, m, key: String, x)`) |
| `_f` (new, 5 defs) | `Maybe<&2, Found>` | `List<&2, U32>`, ignored | 41 | tag 41 **mints**; `UOp.new` returns `Found{ar, i}` and the grown arena is part of the answer |

`_f` is **the first table in this file whose rule can hand back a grown arena.**
`ops.bend:3698-3706` records the same wall for `pm_r_alloc_m`: "the new arena was
discarded by the engine fold, so the rebuilt index was unreachable."

## WHAT THE TABLE DELIBERATELY DOES NOT CLAIM

- **`ops.py:1618`'s `ret is not uop` is NOT PORTED.** Python skips a rule whose answer
  IS the node and keeps scanning; `pm_scan_m`/`pm_scan_f` stop on the first `Some{}`.
  Every one of the four tables has exactly one entry, so the scan ends either way and
  the difference is unobservable **today** — but a five-entry table would see it.
- **`ops.py:253-257`'s `if (...) == new_args: return self` is not needed**, and the
  reason is the interning already measured: `UOp.make.intern.put` is `case Some{i}:
  ar`, so rebuilding an already-untagged node returns the index it has and the arena
  does not grow.
- **`ops.py:1897`'s `slot >= 0` guard is vacuous in Python** (every Python `int`
  satisfies it). Its only possible exclusion is an arg that is not an `AParam`, so the
  port's guard is the `AParam` match and `4294967295` is the bottom.
- **A ZERO-SRC `AFTER`** answers `Arena.src(ar, self, 0)` = 0, the arena's bottom.
  Python raises `IndexError` there. Row `dat_zero_src=0`; see `05-TOTALITY.md`.

## THE TAGS ARE GLOBAL; THE TABLES ARE NOT

Measured: every `PMEntry` in the tree numbers its own rules from 0. `codegen/__init__.bend:318`
tag 0 is `_pm_resolve_params`; `engine/realize.bend:1150` tag 0 is `pm_flatten_linear`.
**The same `PMEntry{0, ...}` means a different rule in every one of them** — the scan
that reads a table and the dispatch that reads a tag live in different files. Tags in
use across the tree, re-measured AFTER this edit:

```
0..32, 40, 41, 42, 43, 999
```

40-43 are this unit's. `grep -E 'PMEntry\{(40|41|42|43)[,}]'` over `tinybendygrad/`
excluding `uop/ops.bend` returns **nothing**, so no existing table can be perturbed by
the two new `pm_dispatch_m` cases. The one consumer that reaches `ops.bend`'s dispatch
at all is `codegen/__init__.bend:108`, and its tables use tags 3 and 4.