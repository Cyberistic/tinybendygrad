# FLIPPORT — `FLIP`'s `arg` is the PORT's, and the fix is a NEW bool-carrying `Arg` variant

Rule prefix **`FLIPPORT`**. Scope read: `tinybendygrad/uop/ops.bend`'s `FLIP` arg type and
`tinybendygrad/uop/render.bend` (owned); `fold.bend` and `.agents/slop/graphcmp.*` are
**FORBIDDEN** (other units / harness).

**VERDICT: `REFUSED`, MEASURED — I did NOT half-land.** The variant itself is ONE field
(`ABoolList{bs: List<&2, Bool>}`), but a correct landing needs `fold.bend`'s `order_arg`
(a forbidden file) or the port's `FLIP` path silently starts comparing a flag-list of
length 0 against the shape. The full RIPPLE is §5. **STATIC-ONLY — no `bend` run.**

---

## 1. THE PIN — where upstream stores the bool

`git show 'ad117c928^:tinygrad/uop/ops.py'`, the guard (read from the PIN, not the worktree):

```
:428  case Ops.FLIP:
:429    if len(ps) != len(self.marg) or not all(isinstance(x, bool) for x in self.marg): raise ValueError(f"bad flip on {ps}, {self.marg}")
:430    return ps
```

The construction site, `git grep -n 'flip_arg' 'ad117c928^' -- tinygrad/`:

```
ad117c928^:tinygrad/mixin/movement.py:253:    flip_arg = tuple([i in axis_arg for i in range(len(self.shape))])
ad117c928^:tinygrad/mixin/movement.py:254:    return self._mop(Ops.FLIP, arg=flip_arg) if any(flip_arg) else self
```

**WHERE IT IS STORED: the `Arg` tuple itself, `self.arg`, not a separate type.** The PIN's
`marg` property (`ops.py:818`) is the proof:

```
case Ops.PERMUTE | Ops.FLIP: return self.arg
```

So `Ops.FLIP` and `Ops.PERMUTE` share ONE slot (`self.arg`) whose ELEMENT TYPE is decided
by the op: `tuple[int, ...]` for PERMUTE, `tuple[bool, ...]` for FLIP. There is no
`BoolTuple` class. `isinstance(x, bool)` is the only element-type guard in `_shape`'s
movement switch (PERMUTE's is a VALUE guard, `sorted(marg) == range`, on ints; UNSHARD
has none). **A Python `bool` is not representable in the port's `Arg` at all** — see §3.

---

## 2. THE PORT'S `Arg` FOR `FLIP` TODAY — and the file's own text is RIGHT

`tinybendygrad/uop/ops.bend:1208`, inside `type Arg is Data` (`:1190-1216`):

```
ATuple{ys: List<&2, U32>}
```

Its own table, **`ops.bend:1144-1153`**, already names both the defect and the shape of
the fix:

```
#   -- and this is the WRONG SPELLING FOR A FLIP, which is `tuple[bool, ...]`:
#      `ops.py:428` asserts `all(isinstance(x, bool) for x in self.marg)` and
#      MEASURED on a fresh src `UOp(Ops.FLIP, src, (1, 0))` RAISES
#      `bad flip on (7, 3), (1, 0)` -- so the port can hold a shape CPython REJECTS,
#      and `graphcmp.bend`'s `g_flip` holds one (`O.ATuple{[1, 0]}`). The correct
#      type is a SEPARATE bool-carrying `Arg` variant, not this one narrowed,
#      because PERMUTE and UNSHARD really are ints. Five files construct or read a
#      FLIP's arg -- `fold.bend`'s `order_arg`, `schedule/prepare.bend:277`,
#      `mixin/movement.bend:993` and `:1533`, and `graphcmp.bend`'s `g_flip` and its
#      one `argstr` arm -- so this cannot be a one-file change.
```

**It names the shape ("a SEPARATE bool-carrying `Arg` variant") and the five sites, and
it says "this cannot be a one-file change."** The wall's own text is the fix; it is
also the reason §4 is a REFUSAL and not a patch. (The comment also carries the
insertion-order measurement that `flipbool` re-derived.)

---

## 3. IS THERE A BOOL `Arg` SLOT ALREADY? — NO. This is a NEW variant, not a reuse.

`grep -n 'ABool\|Bool\|ABit\|bool' tinybendygrad/uop/ops.bend` returns `Bool` as a FIELD
of records (`TBool{b: Bool}` `:899`, `CBool{b: Bool}` `:808`, `SPL.lvl`-style flags) but
**no bare `Bool` `Arg` constructor**. The `Arg` constructors are `:1191-1216`:
`ANone ADt APy AParam ACustom ACall AKernel AProgram ARange AReduce AOpLit AWmma ATuple
AStr AInk AAllred ADev ABlob AInt AFloat ABad` — none carries a bare `Bool`.

* Would `APy{CBool{b}}` do? **No.** That is a `PyConst` (`CONST`'s value, `ops.py:261`),
  one scalar, and `ops.py:201`'s key compares `type(arg)` — `bool` vs `tuple` are two
  kinds. `FLIP`'s arg is a `tuple`, not a `PyConst`.
* So the fix follows `mselectarg`'s `AInt` precedent exactly: **one new one-field `Arg`
  variant**, named for the Python kind. `AInt{i: U32}` (`:1214`) is its shape; the FLIP
  twin is a BOOL LIST because FLIP is multi-axis:
  **`ABoolList{bs: List<&2, Bool>}`** (name is free; `ATupleB` is the alternative).

**Is `List<&2, Bool>` usable?** `device.bend:93` claims "A LIST OF `Bool` IS NOT A USABLE
TYPE." **MEASURED FALSE for the readers this variant needs** — the tree already walks
`List<&2, Bool>` with a cons pattern and `List.length`:

* `codegen/opt/postrange.bend:785-788` `count_bools(bs: List<&2, Bool>)` — `case h <> t`.
* `mixin/movement.bend:186-190` `mx_vec4s.go(..., n: List<&2, Bool>, ...)` — `case … g <> h`.
* `runtime/ops_qcom.bend:1706-1715` `flush.go(..., flags: List<&2, Bool>, ...)` — cons
  match, and `:1725` `List.length(&2, Bool, flags)`.
* `LAWS/spec.bend:435` `SpFlip{t: Sp, flags: List<&2, Bool>}` — a `Bool`-list field.

So `ABoolList` is one field and its three readers (`eq_*`, `arg_repr`, `argstr`) are
writable. **Only `bend` settles that they compile** (§6).

---

## 4. THE MEASURED REFUSAL — why I did not land it

`ops.bend:1144` says "this cannot be a one-file change", and the reason is a **forbidden
file**. Adding `ABoolList` and repointing the port's FLIP constructors leaves `fold.bend`'s
marg reader unhandled:

* `fold.bend:1850-1853` `order_arg(arg)` matches ONLY `case O.ATuple{ys}: ys`, else `Nil{}`.
* `fold.bend:1888-1889` `flip_ds` → `flip_ds.of(order_arg(arg), …)`.
* `fold.bend:1880-1881` `flip_ds.put` compares `List.length(&2, U32, ys)` against
  `List.length(&2, O.Sint, ps)`.

With `ABoolList`, `order_arg` falls to `Nil{}` → the port compares **0** flags against a
2-D shape → **every valid FLIP fails its own length check.** `fold.bend` is explicitly
another unit's file, so I cannot add the arm.

**SMALLEST THING THAT UNBLOCKS: one arm in `fold.bend`'s `order_arg` (or `flip_ds`)
teaching it `ABoolList`.** Given that, the owned edits (ops.bend + render.bend) plus the
compile arm in `upat.bend` and the constructor edits in `movement.bend`/`prepare.bend`/
`tensor.bend` land; the differ row additionally needs the FORBIDDEN
`graphcmp.bend` fixture/`argstr` (§5, H). **I left the tree untouched rather than
half-land it** (a variant with no `fold.bend` reader is a regression, not a partial fix).

### Proposed owned edits (for the orchestrator, not applied)

`ops.bend:1208` — add after `ATuple`:

```
  ABoolList{bs: List<&2, Bool>}
```

`ops.bend` — `eq_arg` (near `:2053`) + `eq_arg.sel` (after `:2154`):

```
def eq_arg.ABoolList(y: Arg, +bs: List<&2, Bool>) -> Bool:
  match y:
    case ABoolList{y1}: eq_bool_list(bs, y1)
    case _: False{}
...
    case ABoolList{bs}: eq_arg.ABoolList(y, bs)
```

(`eq_bool` already exists at `ops.bend:1616`; `eq_bool_list` is its list walk.)

`render.bend:722` — add after the `ATuple` arm:

```
    case O.ABoolList{bs}: bool_tuple_repr(bs)
```

where `bool_tuple_repr` is `u32_tuple_repr` (`render.bend:548`) with `Bool.show`
elements — Python's `repr((True, False))` is `(True, False)`.

---

## 5. THE RIPPLE — every site, old → new

**A. `ops.bend` (OWNED).**
| line | old | new |
|---|---|---|
| `:1144-1153` | the "WRONG SPELLING FOR A FLIP" note, naming five sites | note says CLOSED, names `ABoolList` |
| `:1208` | `ATuple{ys: List<&2, U32>}` | **+ `ABoolList{bs: List<&2, Bool>}`** |
| `:2053-2055` | `eq_arg.ATuple` | **+ `eq_arg.ABoolList` (+ `eq_bool_list`)** |
| `:2154` / `:2140-2162` | `eq_arg.sel` `ATuple` arm | **+ `case ABoolList{bs}: eq_arg.ABoolList(y, bs)`** |

**B. `render.bend` (OWNED).**
| line | old | new |
|---|---|---|
| `:722` (`:704-730`) | `case O.ATuple{ys}: u32_tuple_repr(ys)` | **+ `case O.ABoolList{bs}: bool_tuple_repr(bs)`** |
| `:2995-3003` | `arg_repr ATup/ATup1/ATup0` rows | **+ `ATupB` row = `(True, False)`** |

**C. `upat.bend` (COMPILE — exhaustive match, no `case _`).**
| line | old | new |
|---|---|---|
| `:397-420` `arg_int` | lists all 20 arms incl. `case O.ABad{}` `:420` | **+ `case O.ABoolList{_}: None{}`** |

**D. `fold.bend` — FORBIDDEN (another unit). THE BLOCKER.**
| line | old | new |
|---|---|---|
| `:1850-1853` `order_arg` | `case O.ATuple{ys}: ys` / `case _: Nil{}` | **+ `case O.ABoolList{bs}: <Bool→U32 or flip to a bool-length reader>`** |
| `:1880-1889` `flip_ds.put`/`flip_ds` | length compare on `List<&2, U32>` | compare against the bool list's length |

**E. `mixin/movement.bend`.**
| line | old | new |
|---|---|---|
| `:190-196` `arg_tuple.go`/`arg_tuple` | `case O.ATuple{ys}: Some{ys}` / `case _: None{}` | **+ `ABoolList` arm** (this is the `marg` reader for PERMUTE\|FLIP, `:515`, `:524-528`) |
| `:991-993` `G.flip` | `O.ATuple{ys}` | **`O.ABoolList{...}`** (the local test ctor) |
| `:1095` fixture | `G.flip(…,[1,0,0,0])` | pass `Bool`s |
| `:1526-1556` `mxw_flip_new`/`mxw_flip.put`/`mxw_any` | `flags: List<&2, U32>`, `U32.is_zero(f)` | **`List<&2, Bool>`, `Bool.not(f)`** |

**F. `schedule/prepare.bend`.**
| line | old | new |
|---|---|---|
| `:276-277` `pr_flip` | `O.ATuple{[a, b]}` (`a,b: U32`) | **`O.ABoolList{...}`**; `:269-272` comment already flags the wall |

**G. `tensor.bend`.**
| line | old | new |
|---|---|---|
| `:929-930` `tn_mop.order` | `O.ATuple{ys}` (shared PERMUTE+FLIP) | **branch on `op`: FLIP → `ABoolList`** |
| `:1668-1671` `t_mop_flip` | `AOrder{[0]}` | bool flags |

**H. `graphcmp.bend` — FORBIDDEN (harness). Needed for the differ row only.**
| line | old | new |
|---|---|---|
| `:453` `argstr` | `case O.ATuple{ys}: us(ys)` → `n(i1,i0)` | **+ `case O.ABoolList{bs}: <usb>` → `n(b1,b0)`** (reuse `bo`, `:89-90` = `b1`/`b0`) |
| `:1324-1340` `g_flip` | `O.ATuple{[1, 0]}` `:1340` | **`O.ABoolList{[True{}, False{}]}`** |

**I. `graphcmp.py` — FORBIDDEN, NO CHANGE.** The py side is faithful: `ATOMS`
(`graphcmp.py:324`) maps `bool → "b"`, so it already emits `n(b1,b0)`. (`wmmafix`'s
reversal means the py side must NOT be "fixed" to `i`.)

**J. `uop/spec.bend` (NOT forbidden; needed for `SPEC=1`).**
| line | old | new |
|---|---|---|
| `:459-462` `arg_tuple.go` | `case O.ATuple{ys}: Some{ys}` | **+ `ABoolList` arm** |
| `:1649-1652` `te_7` | `isinstance(mv.arg, tuple)` via `arg_tuple` | accept `ABoolList` |

**K. Comments only (no code):** `mixin/gradient.bend:667-673` `gr_22` is a `GSkip{}`
stub (fine); `schedule/multi.bend:1454-1458` records the FLIP bool marg.

**I am leaving: NOTHING edited.** The one line the orchestrator must add (as `mselectarg`
left its `graphcmp.bend` arm) is **H `:453`**, and the one arm that makes the port
correct is **D `:1850`**. Everything else is mechanical.

### `b` vs `y`
The brief says the renderer prints `b`/`y`. Measured: `graphcmp.py`'s bool atom is **`b`**
(`ATOMS:324`), and `graphcmp.bend`'s bool printer `bo` (`:89-90`) emits **`b1`/`b0`**. The
`y` atom is **BYTES** (`graphcmp.py:325` `bytes → "y"`; `graphcmp.bend` `blobstr`), which
is `ABlob`, not FLIP. The required port atom here is **`b`**, not `y`; the brief's `y`
does not survive measurement.

---

## 6. WHAT ONLY `bend` SETTLES (I did not run it — STATIC-ONLY)

The instrument is **`diff --graph flip`**, which `flipbool` measured at **`AGREE 6/6`**
once the fixture's `GROUP` was removed. Only `bend` can settle, after this fix:
1. that `ABoolList{bs: List<&2, Bool>}` **compiles** — surprising given `device.bend:93`;
2. that the new exhaustive arms (`upat.bend:420`, `render.bend:730`, `eq_arg.sel:2162`)
   are accepted;
3. that `graphcmp.bend`'s new `argstr` arm renders `n(b1,b0)` — the byte that makes the
   row `AGREE`.

I could not run it, so **items 1-3 are predictions, not verdicts.**

---

## 7. THE DENOMINATOR — 1 of 13, not 13 of 13

`.venv/bin/python .agents/slop/flipbool/corpus-argscan.py` (STATIC), population
`runs/graphcmp/D/D2-canon-{py,bend}-*` (34 + 34 files, directory walk), field 6 = `arg`:

```
# --- py ---
COPY     kinds=(s,s)    n=2      PERMUTE  kinds=(i,i)    n=1
FLIP     kinds=(b,b)    n=1      PERMUTE  kinds=(i,i,i)  n=8
UNSHARD  kinds=(i)      n=1      TOTAL    tuple-args=13
# --- bend --- (identical except FLIP kinds=(i,i))
```

**13 tuple-args per side; exactly 1 carries `b` (py FLIP) vs the port's `i` — the whole
class.** Upstream guards by ELEMENT TYPE for **1 of 13** (FLIP's `isinstance(x, bool)`,
`ops.py:428`):

| op | upstream guard (`_shape`) | element-TYPE guard? | port wrongly accepts? |
|---|---|---|---|
| FLIP | `isinstance(x, bool)` | **yes** | **yes — the port's `ATuple{List U32}`** |
| PERMUTE | `sorted(marg) == list(range(len(ps)))` | no (a VALUE guard on ints) | no — port implements it (`fold.bend` perm) |
| UNSHARD | none | no | no (upstream accepts any |
| COPY | none (`_shape` never sees it) | no | no |

**So the port's absent guard is width 1, not 13.** The other 12 are NOT "guards the port
forgot": upstream has no element-type guard to forget, and upstream ACCEPTS a bool
PERMUTE too (`sorted([True, False]) == [0, 1]`). **FLIP is the only op where upstream's
guard is about the ELEMENT TYPE, and the port's `Arg` cannot even spell the accepted
value.** That is why this is a vocabulary gap, not a guard the port failed to port.

---

## 8. VERDICT

`REFUSED` (measured). The PIN stores the bool in `self.arg` (the `Arg` tuple), the port
cannot spell it (`ops.bend:1208` `ATuple{ys: List<&2, U32>}`), the fix is ONE new variant
`ABoolList{bs: List<&2, Bool>}` (the port's own `ops.bend:1144` says exactly that, and
says it is not a one-file change), and landing it requires the FORBIDDEN `fold.bend`
(`order_arg:1850`). **The RIPPLE (§5) is the deliverable; the tree is untouched.**
