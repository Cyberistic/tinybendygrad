# THE THREE WRONG-SHAPE DISAGREEMENTS — FIRST ROW, BOTH SIDES' BYTES

**THE FIRST THING ON DISK.** Every byte below was read out of `runs/graphcmp/D` with
`.venv/bin/python` and nothing was re-run; the run is left byte-identical (see `RUN.md`).

Two independent belts agree on each line number, and they share no regex and no input
file — belt 1 reads the differ's own `diff` record (`D2-cmp-<g>.txt`, hunk header),
belt 2 walks the two canonical files side by side with `zip`
(`.agents/slop/disagree/names.py:first_row_from_cmp` / `first_row_recomputed`).
`run: python3 .agents/slop/disagree/names.py` prints `two belts agree: True` for all three.

The canonical wire is `N:i<id>` then SEVEN length-prefixed chunks — the op name plus the
six compared `fields`. `fields=6` on every `DENOMINATOR` line is the count of the
compared ones; **the op name is chunk 0 and is matched, not compared.** Every row of both
sides of all 25 graphs parses into exactly seven chunks and consumes itself exactly
(`wire_shape_agrees` → `SAME 7-chunk length-prefixed wire on every row`). So a serialisation
defect is falsified and what remains is per-field.

---

## 1. `flip` — canon line 6, `py#6 FLIP`, field `arg`. **BOTH** harness and port.

```
py   2:i6 4:FLIP 3:f32 11:(l0:4,l0:3) 2:i0 1:N 8:n(b1,b0) 5:n(i5)     60 B  sha256 4e36336a611cbbb4
bend 2:i6 4:FLIP 3:f32 11:(l0:4,l0:3) 2:i0 1:N 8:n(i1,i0) 5:n(i5)     60 B  sha256 bfe837e7e06cce02
```

**FIELD arg: py=`n(b1,b0)`  bend=`n(i1,i0)` — WRONG SHAPE, PORT.**

Six of seven chunks are byte-equal (`i6 FLIP f32 (l0:4,l0:3) i0 N … n(i5)`), so the wire
agrees and the op agrees. Only the `arg` payload's ATOM SPELLING differs: `b` vs `i`.

### 1a. `ATuple` IS THE *PERMUTE* INT SPELLING. A bool has no representation.

    tinybendygrad/uop/ops.bend:1035   #   tuple[int, ...]         ATuple     PERMUTE arg (`movement.py:231`), UNSHARD arg
    tinybendygrad/uop/ops.bend:1081   ATuple{ys: List<&2, U32>}

Upstream's FLIP arg is `tuple[bool, ...]` — `tinygrad/uop/ops.py:428`:

    case Ops.FLIP:
      if len(ps) != len(self.marg) or not all(isinstance(x, bool) for x in self.marg): raise ValueError(f"bad flip on {ps}, {self.marg}")

**It ASSERTS every element is a `bool`.** `List<&2, U32>` cannot hold a bool, so the
port has *one* spelling for two upstream types and the FLIP one is unreachable.
**Wrong shape, not a wrong value: `b1` is not a mis-spelled `i1`, it is a type the port
cannot express at all.**

### 1b. THE HARNESS'S OWN BUG — a bend-only node CPython never builds.

    runs/graphcmp/D/D2-canon-py-flip.txt    6 rows    (root = FLIP#6)
    runs/graphcmp/D/D2-canon-bend-flip.txt  7 rows    (+ 2:i7 5:GROUP 4:void 1:R 2:i0 1:N 1:N 5:n(i6))

`tinygrad/uop/ops.py:559` — `UOp.group`:

    def group(*srcs:UOp|None, **kwargs):
      if len(srcs) == 1 and isinstance(srcs[0], UOp): return srcs[0]

`graphcmp.py:1385` is `return UOp.group(a.flip(0).uop)` — **a one-element group** — so
**CPython builds NO GROUP AT ALL.** The port implements the collapse correctly:

    tinybendygrad/uop/ops.bend:2507-2513   case Nil{}: Found{nar, 0} / case s <> t: case Nil{}: Found{ar, s}

`.agents/slop/graphcmp.bend:1304` **hand-builds the GROUP anyway, bypassing `UOp.group`.**
**This is a FIXTURE bug, one line, in a SETTLED file. It also moves the verdict: with the
GROUP gone, `py rows=6 bend rows=6` and the remaining disagreement is (a) alone.**

---

## 2. `lin` — canon line 46, `py#46 SINK`, field `arg`. **WRONG SHAPE, PORT.**

```
py   3:i46 4:SINK 4:void 1:R 2:i0 2:i1 66:kI(sr_4_5_3,n(Opt(op=EOptOps.SPLITaxis=i2arg=n(i0,XUPCAST))),N,i0) 6:n(i45)   112 B  sha256 52b3f241dcbb21d4
bend 3:i46 4:SINK 4:void 1:R 2:i0 2:i1 22:kI(sr_4_5_3,n(q),N,i0)                                              6:n(i45)    68 B  sha256 ed789317030ebfcb
```

**FIELD arg: py=`kI(sr_4_5_3,n(Opt(op=EOptOps.SPLITaxis=i2arg=n(i0,XUPCAST))),N,i0)`
bend=`kI(sr_4_5_3,n(q)),N,i0)` → `kI(sr_4_5_3,n(q)),N,i0)` — WRONG SHAPE, PORT.**

`dtype`, `shape`, `depth`, `tag`, `src` are byte-equal. **`fields-mismatches=1` and the ONE
field is `arg` — but `arg` cannot be spelled, and the count still agrees (1 option = 1 `q`).
THIS IS THE CLASS THAT SURVIVES EVERY VALUE-LEVEL CHECK.**

`tinybendygrad/uop/ops.bend:919`:

    type KernelInfo is Data:
      KernelInfo{name: String, applied_opts: List<&2, U32>, opts_to_apply: Maybe<&2, List<&2, U32>>, beam: U32}

Upstream's elements are `Opt` **dataclasses** (`codegen/opt/__init__.py:11`:
`Opt(op=OptOps.SPLITaxis, axis=2, arg=(0, XUPCAST))`). `List<&2, U32>` is a type that
**permits the wrong encoding**, so the marker `q` is not a typo in the renderer — it is
what the type allows.

**AND THE MARKER IS THE ORACLE'S, NOT THE PORT'S.** `.agents/slop/graphcmp.bend:316-330`
says so in its own words — *"THE OPTION LISTS ARE COUNTS, NOT CONTENTS, and that is a
refusal rather than a comparison … So one `q` per option: the count compares, the content
is a named refusal, and nothing here copies the port's answer into the oracle."*

---

## 3. `loop` — canon line 25, `py#25 CALL`, fields `dtype`, `shape`, `arg`. **WRONG SHAPE, PORT.**

```
py   3:i25 4:CALL 4:void 1:R 2:i0 1:N 20:cI(shcq_fence,b0,b0)              18:n(i23,i24,i24,i24)   78 B  sha256 2be0a7de4d4e5f55
bend 3:i25 4:CALL 1:?    1:?  2:i0 1:N 26:cI(shcq_fence,b0,b0,Dvoid)      18:n(i23,i24,i24,i24)   81 B  sha256 aa07efb1333e34fd
```

**FIELD dtype: py=`void` bend=`?`. FIELD shape: py=`R` bend=`?`.
FIELD arg: py=`cI(shcq_fence,b0,b0)` bend=`cI(shcq_fence,b0,b0,Dvoid)`.**

`?` is the fold producing **no `Derived` at all** — not a wrong value. It is this corpus's
**only live `?`.** The `Dvoid` tail is the port's **fourth** `CallInfo` field.

The port's `CallInfo` (`ops.bend:1010`) has **four** fields
`{name, precompile, precompile_backward, dtype: S.Dt}`. Upstream's (`ops.py:1400-1405`)
has **FIVE and NONE of them is `dtype`**:

    @dataclass(frozen=True)
    class CallInfo:
      grad_fxn: Callable|None = None
      name: str|None = None
      precompile: bool = False
      precompile_backward: bool = False
      aux: Any = None

The port dropped `grad_fxn` (a Python function object) and `aux` (the hcq per-call side
channel) — documented and deliberate, `ops.bend:999-1006` — **and invented `dtype`.**

**THE CITATION IS STALE, AND THAT IS THE FINDING** — see `02-fix.md`.

---

## THE THREE-ROW SUMMARY

| graph | line | op | mismatched fields | class | fault | narrower fix? |
|---|---|---|---|---|---|---|
| `flip` | 6 | FLIP | `arg` (`b1,b0` vs `i1,i0`) | wrong shape | port (bool tuple unspellable) | yes — add a bool spelling |
| `flip` | 7 | GROUP | row exists only on bend | not a row | **fixture**, `graphcmp.bend:1304` | n/a (delete) |
| `lin` | 46 | SINK | `arg` (`Opt(…)` vs `q`) | wrong shape | port (`List<U32>` for `Opt`) | yes — model `Opt` |
| `loop` | 25 | CALL | `dtype`, `shape`, `arg` | wrong shape | port (4th `CallInfo` field) | yes — delete a field |

**ALL THREE ARE WRONG SHAPE. NONE IS WRONG VALUE.** `spine` reported
`field-mismatches=0` on `lin`/`loop` and called the values wrong; those are the *shape*,
which is a different bug with a different fix.