# WHAT THE LINEAR RULE TABLE MUST DO — from `tinygrad/uop/ops.py`

## 0. WHAT "THE LINEAR RULE TABLE" IS, AND WHY THIS FILE IS THE PLACE

`tinybendygrad/schedule/__init__.bend:7-13` defers `__init__.py:82-301` with three
clauses. Clause C3 is the one this unit builds:

> `graph_rewrite`'s engine pass needs the rule table to be LINEAR
> (`brief-port.md`, THE REWRITER) while these rules need the ctx to be a MUTABLE
> accumulator threaded through the pass.

"Linear" is not a wish about lists. `brief-port.md:88-92` fixes it:

```
    def engine_pass(rules: List<Rule>, a: Arena) -> Arena:
      match rules:
        case Nil{}: a
        case R{use} <> rest: engine_pass(rest, use(a))
```

A rule is a `Type` (it holds a function), so **the rule TABLE is linear and a second
pass rebuilds it.** The port's answer is a tag instead of a function
(`ops.bend:3455-3471`): a compiled rule is a **top-level def named by a tag**, the
table is a `PMEntrys` `Data` record, and the dispatch is a `match`.

So the linear rule table is **`ops.bend`'s `pm_dispatch` / `pm_dispatch_m` — the
global tag→body table** — and `pm_dispatch`'s reachability is the wall.

**THE WALL, quoted.** `tinybendygrad/engine/realize.bend:1072-1080`:

> THE SCAN IS THIS FILE'S, BECAUSE THE BODY IS THIS FILE'S. `O.pm_rewrite` cannot
> be used here: `pm_rewrite` calls `pm_dispatch`, which is `ops.bend`'s OWN
> tag-to-body table -- tag 0 is its SINK rule, tag 1 its NOOP rule, tag 2 its
> CAST rule -- so a `PMEntrys` built in THIS file can only ever reach those three
> bodies, and `fl_0`, `va_0`, `va_1` and `beam_0` are unreachable through it.
> Measured: `O.pm_dispatch(0, ar, <a LINEAR>)` answers `VSkip`, and so does
> `O.pm_rewrite(flatten_table(), ar, <a LINEAR>)`

**MEASURED IN THIS UNIT, BEFORE ANY EDIT.** Exactly one place in the tree reaches
`ops.bend`'s dispatch:

```
$ grep -rn --include='*.bend' 'pm_rewrite(\|pm_rewrite_m(' tinybendygrad/ | grep -v 'def pm_rewrite'
tinybendygrad/codegen/__init__.bend:108:  wr.step.try_rule(u, O.pm_rewrite_m(pm, ar, u, ctx), repl, rebuilt)
tinybendygrad/engine/realize.bend:1079:#  `O.pm_rewrite(flatten_table(), ar, <a LINEAR>)`   <- a COMMENT
```

and its two tables use tags 3 and 4 only (`codegen/__init__.bend:318` and `:528`).
**Every other `PMEntrys` in the tree is scanned by its OWN local scan** — the grep
returns `sym_scan`, `dm_scan`, `sh_scan`, `te_scan`, `gr_scan`, `rz_claim`,
`fn_scan`, `wk_scan`, `dc_l_scan`, `dc_s_scan`, `tx_tab`. That is why `pm_dispatch`
has held three placeholder bodies for 77 ops.

## 1. THE SOURCE, `file:line`

`tinygrad/uop/ops.py` holds **FOUR** `PatternMatcher`s. All four are in one place,
all four are one rule each, and all four are `ops.py`'s OWN — this is the whole of
ops.py's rule-table surface:

| ops.py | name | pattern | rule body |
|---|---|---|---|
| **1896** | `_substitute` | `UPat(tuple(Ops), name="x")` | `lambda ctx,x: ctx.get(x,None)` |
| **1897** | `_pm_resolve_params` | `UPat(Ops.PARAM, name="p")` | `lambda ctx,p: ctx[p.arg.slot] if p.arg.slot >= 0 else None` |
| **1904** | `remove_all_tags` | `UPat(GroupOp.All, name="x")` | `lambda x: x.replace(tag=None) if x.tag is not None else None` |
| **1907** | `pm_drop_after` | `UPat(Ops.AFTER, name="a")` | `lambda a: a.src[0]` |

Verified by calling CPython, not by reading:

```
$ python3 -c "from tinygrad.uop import Ops, GroupOp; print(len(tuple(Ops)), GroupOp.All == set(Ops))"
77 True
```

(`tinygrad/uop/__init__.py:135` is `All = set(Ops)`.)

**`ops.py:1613-1619` is the scan every entry must satisfy:**

```python
  def rewrite(self, uop:UOp, ctx=None):
    if len(pats:=self.pdict.get(uop.op, [])):                      # 1614  CLAIM by op
      if (ler:=uop.__dict__.get('_src_ops')) is None: uop.__dict__['_src_ops'] = ler = {u.op for u in uop.src}
      for _,match,early_reject in pats:
        if not early_reject.issubset(ler): continue                # 1617  NECESSARY CONDITION
        if (ret:=match(uop, ctx)) is not None and ret is not uop: return ret   # 1618  FIRST NON-NONE WINS
    return None
```

and **`ops.py:1602-1606` is where `PMEntry` comes from:**

```python
    for p,fxn in self.patterns:
      assert p.op is not None
      entry: list = [p, None, p.early_reject]
      entry[1] = upat_deferred_compile(p, fxn, entry) if compiled else upat_interpret(p, fxn)
      for uop in p.op: self.pdict.setdefault(uop, []).append(entry)
```

`for uop in p.op` is the fan-out that makes `PMEntry.ops` a **CLAIMED set**, and
`entry[1] = <compiled fn>` is the **tag**. `p.early_reject` is the third field.

**`ops.py:1480-1483` computes the reject set, and ALL FOUR COME OUT EMPTY:**

```python
      upat_match = [src] if isinstance(src, UPat) else ([] if src is None else self.src[0])
      self.early_reject = {pp.op[0] for pp in upat_match if pp.op is not None and len(pp.op) == 1}
```

All four patterns are built with `src=` **omitted**, so `src is None`, so
`upat_match == []`, so `early_reject == set()`. `set().issubset(anything)` is
`True`, so `ops.py:1617` **never skips any of the four**. `PMEntry.rej` is `Nil{}`
for all four entries — and that is a fact about the source, not a shortcut.

## 2. THE FOUR ENTRIES

```
tag 40  ops.py:1907  pm_drop_after        claims {AFTER}             rej {}   body Arena.src(ar,self,0)
tag 41  ops.py:1904  remove_all_tags      claims tuple(Ops) [77]      rej {}   body UOp.new(..., TNone{})
tag 42  ops.py:1897  _pm_resolve_params   claims {PARAM}              rej {}   body ctx[slot] if slot>=0
tag 43  ops.py:1896  _substitute          claims tuple(Ops) [77]      rej {}   body ctx.get(self)
```

Tags 40-43, not 8-11: **measured**, tags 0..32 and 999 are in use across the tree
(`PMEntry{8, ...}` in `rangeify.bend`, `prepare.bend`, `multi.bend`,
`gradient.bend`, `decomp/op.bend`), so 40 is the first free tag. Section 6 of
`03-PROBE.md` re-measures this after the edit.

## 3. THE ONE THING THAT IS NOT PORTABLE, AND IT IS NOT LINEARITY

`tinygrad/uop/ops.py`'s four lambdas share a `ctx` parameter that Python leaves
UNTYPED. `ops.py:1888` types it `ctx=None`. A Bend parameter has a type, so:

| rule | ctx type in Python | ctx type in Bend |
|---|---|---|
| `_pm_resolve_params` | `dict[int, UOp]` indexed by `p.arg.slot` | `List<&2, U32>` |
| `_substitute` | `dict[UOp, UOp]` keyed by the node | `Map<&2, U32>` |
| `remove_all_tags`, `pm_drop_after` | unused | `List<&2, U32>`, ignored |

**A single linear table cannot hold all four, and the blocker is the ctx TYPE, not
the linearity.** And a second blocker is sharper still: **`pm_rewrite_m` returns
`Maybe<&2, U32>`, an arena INDEX, and `remove_all_tags` MINTS.**
`ops.bend:3698-3706` records the same wall for `pm_r_alloc_m`:

> The arena-growth wall: the original implementation minted a BUFFER here, but the
> new arena was discarded by the engine fold, so the rebuilt index was unreachable.

`UOp.new` returns `Found{ar, i}` (`ops.bend:2431-2432`, `:2451`). A rebuilding rule
needs `Maybe<&2, Found>`. So the port is **three families**, and each family's
existence is forced by a measured fact, not chosen:

| family | answer | ctx | carries | rules |
|---|---|---|---|---|
| `_m` (existing `pm_dispatch_m`) | `Maybe<&2, U32>` | `List<&2, U32>` | index only | 1907, 1897 |
| `_sub` (new, 3 defs) | `Maybe<&2, U32>` | `Map<&2, U32>` | index only | 1896 |
| `_f` (new, 3 defs) | `Maybe<&2, Found>` | `List<&2, U32>`, ignored | **the grown arena** | 1904 |

## 4. WHAT THE TABLE DOES NOT HAVE TO RE-DERIVE

`pm_claimed` (`op_in ops`, `ops.py:1614`), `pm_early` (`rej ⊆ ler`,
`ops.py:1617`) and `pm_ler` (fold over `List.range(nsrc)`) are already ported and
already read `PMEntry.ops` / `PMEntry.rej`. The new work is: **four entries, four
bodies, and the reachability.**