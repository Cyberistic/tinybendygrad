# WHERE THE PORT IS TOTAL AND PYTHON IS NOT

Two of the four rules answer where Python raises. Both are measured, not assumed, and
both are the same total-function trade `helpers.bend`'s `unwrap_or` and
`schedule/__init__.bend`'s `Split` (`__init__.py:29`, the `AssertionError` in
`_split_after`) already make.

## 1. `_pm_resolve_params` (ops.py:1897) AND A SLOT THE CTX DOES NOT CARRY

```python
_pm_resolve_params = PatternMatcher([(UPat(Ops.PARAM, name="p"),
                                     lambda ctx,p: ctx[p.arg.slot] if p.arg.slot >= 0 else None)])
```

CPython, measured by `lintable-oracle.py`:

```
$ .venv/bin/python .agents/slop/lintable/lintable-oracle.py | grep rp_slot5
rp_slot5_raises_py=1
```

**`KeyError: 5`.** `ctx` is a `dict` and `ops.py:1897` indexes it directly. The port's
`List.get` answers "no rewrite":

```
rp_fires_slot5_oor=0     (present = 0)
```

Two consequences, both of which are properties of the port and not defects:

- **`List.get` out of range must be `None{}`.** If it answers a bottom `U32` instead,
  the rule would claim to rewrite a PARAM to whatever the bottom index happens to be.
  The row is on the `Maybe`, not on the value, precisely because a legitimate answer of
  0 must not look like a miss — the same reason `ops.bend:7562` reads `Map.has`.
- **`slot >= 0` is vacuous in Python** and cannot be. Every Python `int` satisfies it,
  so the only thing it can exclude is an arg that is not an `AParam` at all, where
  `p.arg.slot` would itself raise `AttributeError`. The port's guard is therefore the
  `AParam` match, and `4294967295` is the bottom — matched EXPLICITLY rather than left
  to `List.get`, because `U32.to_nat` on the top is a `Nat` no `List.get` answers and
  the out-of-range behaviour would then be an accident of that fold.

## 2. `pm_drop_after` (ops.py:1907) ON AN `AFTER` WITH NO SRCS

```python
pm_drop_after = PatternMatcher([(UPat(Ops.AFTER, name="a"), lambda a: a.src[0])])
```

`a.src[0]` on a zero-src `AFTER` is an `IndexError` in Python. The port's
`Arena.src` answers the arena's bottom:

```
dat_zero_src=0
```

The arena's bottom is `Node{OpsNOOP{}, Nil{}, ABad{}, TNone{}}` (`ops.bend:1171`), so a
rule that returned it would hand the engine a NOOP that no constructor in the tree
ever produces. **The claim is unchanged** — an `AFTER` still matches `AFTER` — so a
zero-src `AFTER` is reachable and the answer is a value no caller wants. A caller that
must refuse it has to check `Arena.nsrc` itself, and this row says so rather than
leaving it as a surprise.

## 3. `remove_all_tags` (ops.py:1904) AND `ops.py:256`

```python
    if (self.op, self.src, self.arg, self.tag) == new_args: return self
```

`replace(tag=None)` on a node whose tag is already `None` returns `self` without
minting. The port has no such test: it always calls `UOp.new`. **That is a no-op, and
the interning is what makes it one** — `UOp.make.intern.put` is `case Some{i}: ar`
(`ops.bend:2204-2207`), so a structurally identical node returns the index it already
has and the arena does not grow. Row `rat_keeps_untagged=0`: the rule answers `None{}`,
and the arena is untouched.

This is why `pm_r_tag_m.of`'s `UOp.new` is evaluated EAGERLY on both arms of the
`Bool.pick`. `Bool.pick` chooses an arm; it does not sequence one. Being eager is safe
here only because interning makes the untagged path a no-op — which is stated at the
call site rather than left as a lucky accident.

## 4. `Arena.node` IS TOTAL, SO A WRONG ARENA DOES NOT FAIL

Not a row but a constraint the probe had to be built around: `Arena.node` answers the
bottom for an index that was never interned (`Maybe.default(&1, Node, Arena.at(ar, i),
Arena.bottom())`). A rule handed the wrong arena returns a plausible NOOP rather than
erroring. `Arena.at` is the PARTIAL reader and is the only one that can say an index
does not exist.

`pm_scan_m` / `pm_scan_f` pass `ar` to every rule and no rule checks it, so **the
engine cannot detect a mis-threaded arena from the rule side.** `codegen/__init__.bend`'s
`wr.step` holds the arena across the whole pass, which is what makes that safe today.