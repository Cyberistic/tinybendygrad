# render: the repr layer, and the first place a dropped literal is invisible

`render.py` turns a UOp back into Python source text. It is the first
string-building unit in the port — everything before it was DATA — and it is the
first place where a dropped literal produces a plausible wrong answer instead of a
type error. The file is `tinybendygrad/uop/render.bend`.

## What we gain

- **Every gate row is a STRING diffed against CPython's own repr, never a boolean
  about one.** 46 printed lines, 40 rows, and all 40 carry the Python value
  printed next to the answer, so a dropped literal shows up as a STRING
  DIFFERENCE rather than hidden inside a boolean. `String.concat` will happily
  drop a `", "` and yield a plausible wrong string; that is the whole reason the
  gate is shaped this way and it matters more here than in any other unit.
- **`String.split` splits on ONE CHARACTER**, which is what makes the exponent's
  own length readable in `f32_repr` — `String.split(s, 'e')` then `length` on the
  tail is how Python's two-digit exponent is produced from `F32.show`'s one.
- **`F32.show` and CPython's `repr` disagree in four measured ways, and the file
  pins each one.** `F32.show(3.0)` is `"3"` where `repr(3.0)` is `"3.0"`;
  `F32.show(1e-7)` is `"1e-7"` where Python is `"1e-07"`; and a CONST carrying
  0.1 needs 8+ significant digits, which is the wall below.
- **`sint_show` is the one genuinely new string primitive here, and its limit is
  stated rather than chosen.** `U32.show(4294967293)` is `"4294967293"` and
  CPython's `str(-3)` is `"-3"`, so this closes for the int32 range with a sign
  flag plus a magnitude — exactly the shape `helpers.bend`'s `I64` already uses.
  Above 2^31 it reads negative, so a uint32 above 2^31 would print with a minus
  sign and a CONST holding 2**40 would print `-2199023255552` where CPython says
  `1099511627776`. No CONST in a compiled graph carries a value that large, and
  widening the range means a two-word divide.
- **`repr` is a per-arm FUNCTION, not a dynamic dispatch, and that is the better
  representation.** `render.py` calls `repr(...)` on six different things; in
  Python each dispatches on the runtime type of an `Any`. There is no `Any` and
  no runtime type to dispatch on here, because `Arg` and `Tag` are CLOSED
  DATATYPES — eighteen `Any` values became eighteen compiler-checked arms, which
  is `spec/ops.md`'s "parse, don't validate" applied to a string.
- **The 15 `pm_pyrender` rules are a `match` on the op, not a table, and the
  reason is in the Python's own note.** `render.py` says "you can remove
  pm_pyrender_extra and it'll still be correct" — which is TRUE, and is exactly
  why thirteen of the rules are special cases that FALL THROUGH to the
  `GroupOp.All` rule when their guard fails, so first-wins and the fallback
  compose into one dispatch rather than fifteen attempts.
- **Rule order is load-bearing twice, for `REDUCE` and for the sugar fallback**,
  and that is recorded on the def rather than discovered later.
- **Three `pa` fixtures cover all three ORDERINGS of `ParamArg`'s nine keyword
  fields** (device only; name and no size; addrspace + volatile + image). A
  field-order bug that moved one keyword cannot pass all three. `pa2` is the
  deliberate trap: `size` is the one POSITIONAL optional, so a `size` that
  printed when it is `None` moves every later field.
- **46 rows, both lanes byte-identical, and the file CHECKS.**

## The wall that is not about strings: `eval_pyrender`

`spec.py:294` does `exec(code, pyrender_globals(), lcls)` on the string
`pyrender` produced and reads back `lcls['ast']`. That is not a missing
primitive; it is a missing language. Bend has no `exec`, no globals dict, and no
value that knows its own type's name, so **the round trip has no representation
at all** — not a hard one, not a deferred one.

`upat.bend` already settled the precedent: the pattern COMPILER EMITS PYTHON TEXT
and the Bend side is a hand-written dispatch instead. So the correct port of
`pyrender` is to emit the text and NOT round-trip it, and `test_pyrender`
(`spec.py:299`) becomes the string-diff gate at the foot of this file instead of
an `exec`. Recorded, not engineered around.

## Four substrate gaps, and only the first is cosmetic

- **(a) No `sprintf`, no field-width specifier, no `format`.** Every
  `f"{i:4d}"`, `f"{str(u.op):20s}"`, `f"{str(u.dtype):40s}"`, `f"{str(srcs):32s}"`
  and `multirange_str(..., pad=10)` is `H.pad_left`/`H.pad_right`, which
  helpers.bend HAS. Closed by composition, not a wall.
- **(b) No `String.replace`/`replace_all`,** because `String.split` splits on a
  single CHAR, so a multi-character substring replace has no primitive at all.
  The one that IS needed — `str(x.dtype)[7:]`, which strips the literal prefix
  `"dtypes."` — is `String.drop(s, 7n)`, which base.bend has. A general
  `replace` would need a char-wise scan; nothing here needs it.
- **(c) No signed integers,** which is wall (2) above: `sint_show`.
- **(d) No Python `repr()` of an arbitrary object.** This is the real one, and
  the one genuinely lost thing in the file: Python's `repr` of an object with a
  user-defined `__repr__` READS THAT METHOD, and Bend cannot read a method off a
  value. `ParamArg` is that case.

## Four of the five imports do not exist

`render.py:3-4` imports five names. `strip_parens` EXISTS (helpers.bend:1055).
The other four are rebuilt here, and two of those rebuilds are a real gap in a
shared file rather than an inconvenience:

- `range_str` is ABSENT from ops.bend, and ops.bend:537 says "`range_str` does
  not read it" — so its absence is a gap in the gate file, not something to work
  around. Rebuilt from `AxisType`, `axis_colors`, `Ops.value` and `sint_show`.
- `multirange_str` is ABSENT. Rebuilt from `range_str` plus a sort, and the sort
  is BY `x.arg`, which is why a RANGE's `ids` and `at` have to be split first.
- `consumer_map_from_toposort` is ABSENT because `fold.bend`'s `Kahn.consumers`
  COUNTS a node's in-edges but does not RETURN them, and `pyrender` needs both
  the count and the single consumer's identity (render.py:163). Rebuilt as
  `consumers.of`/`consumers.who`.
- `sint` is ABSENT, and so is `sint_to_uop` (ops.bend:3487 marks that one
  `TODO(p3)`). `sint` is a TYPE ALIAS for `UOp | int`, so `marg_str`'s
  `isinstance(a, UOp)` becomes a match on `Arg`'s `APy` arm — which is strictly
  MORE precise, since `sint` is exactly "a UOp or a Const".

## Walls recorded in-file

- **`F32.show` vs `repr(float)` is a WALL, not a bug in the fixer.** There is no
  `F64` in base.bend, so there is no def that can print the 17-significant-digit
  decimal an f64 round-trips through. `F32.show` is right about the F32 and
  CPython is right about the f64, and for every CONST a compiled graph actually
  holds the two strings are equal. The disagreement is confined to a CONST
  carrying a float needing 8+ significant decimal digits, which tinygrad never
  emits — `dtypes.from_py` wraps a Python float in a `ConstFloat` unchanged, so
  it CAN, and then the emitted code differs in its trailing digits while still
  parsing to the same UOp.
- `ParamArg.addrspace=None` vs `S.Addr`.
- `KernelInfo.estimates` and `ProgramInfo.target` were dropped in ops.bend (P5).
- `Tag.TTuple` is a REAL cycle and prints `<UOp>`.
- The Device name table is declared as this file's convention.

## Reported, not fixed

`ops.bend`'s `Ops.name` returns `ADD` where CPython's `str(Ops.ADD)` is
`Ops.ADD`, which is wrong for every Python repr of an `Ops`. No other unit reads
it, so render.bend corrects it locally rather than touching the shared file.

## Not done

`rg "TODO\(p3\)" tinybendygrad/uop/render.bend` is the work queue: 11 markers.

- **`pyrender` itself is UNGATED.** It and `_render_with_splits` are ported and
  the file CHECKS, but no arena fixture drives them, and no gate row prints their
  output. That is the single most important thing left in this unit and it is a
  GATE problem, not a port problem: all 40 oracle-bearing rows above exercise the
  `repr` helpers directly, so the rules that compose them are the one part of this
  file with no witness.
- `render.py:6` `pretty_print` — PORTED IN PART. Its `dfs` is a
  `cache.setdefault(...)` over a CYCLIC graph, so the cache is a second store
  beside the arena and the walk needs a fuel the Python does not. `argstr`/
  `tagstr` ARE ported, which was the cheap half.
- `render.py:18` `print_uops` — BLOCKED on `UOp.ranges` (ops.py:497).
  `multirange_str` and `range_str` ARE ported here and take the range list as a
  parameter, so only the `u.ranges` COLUMN is missing, not the formatting.
- `render.py:35` `marg_str` / `:37` `render_marg` — `marg_str`'s third arm is
  `a.render()`, and `render` is `TODO(p3)` ops.py:1181; it needs `simplify()` and
  the whole `renderer` matcher, whose Movement arm calls `render_marg`. **The two
  are a cycle the port cannot break by ordering.** `render_marg` itself is `x.marg`,
  `TODO(p3)` ops.py:814.
- `render.py:45` `renderer` / `:74` `renderer_infer` — 21 UPat rules whose payloads
  are mostly `ctx[src]`; only the sugar/renderer INFER arms need anything not
  already here. They are needed by `UOp.render()`, not by `pyrender`.
- No mutation table — no room.

## One red row, found writing this file

`arg_repr ARng = [((0), AxisType.GLOBAL)]   py=((0,), AxisType.GLOBAL)`. This is
the only one of the 40 oracle-bearing rows that does not match CPython, and the
file does not claim it. `srcs` implements Python's `len(src) == 1` special case
correctly (`srcs_one` emits `"(x,)"`, and the header says why: `(x,)` and `(x)`
are different Python literals and only the first round-trips through
`eval_pyrender`). But `u32_tuple_repr`, which `arange_repr` uses for a RANGE's
axis-id tuple, has no such case — so a one-element axis id prints `(0)` where
CPython prints `(0,)`. Same wall, one arm short. It is a real bug and it is a
gate row, which is the argument for the gate being the string.