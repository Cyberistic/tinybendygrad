# Literal-oracle conversion — unit report

**Unit**: convert literal `py=` expectations to CPython-derived calls, plus wire `kernel.bend`'s
`ops` row to the already-derived measurement.

**Status**: IN PROGRESS — this file is written as I go.

## Baseline (measured, not assumed)

- `.agents/slop/handtyped-audit.py` — AST classifier, 578 hand-typed rows across 33 oracles.
- `.agents/slop/handtyped-rank.py` — `score = 3·LIES + 2·REIMPL + MAGIC`.
- `.agents/slop/reimpl-scan.py` — 94 reimpl expressions across 16 oracles.
- Consequence ranking given by the coordinator: `nv` 148, `ip` 43, `ops-python-render` 33,
  `objc` 27, `cs` 26, `amdev` 23.

## Denominators used throughout

| quantity | value | source |
|---|---|---|
| hand-typed rows, whole repo | 578 | `handtyped-audit.py` |
| oracles with hand-typed rows | 33 | `handtyped-audit.py` |
| reimpl expressions, whole repo | 94 across 16 oracles | `reimpl-scan.py` |
| prior unit's converted rows | 27 of 578 = 4.7% | coordinator brief |

---

# 1. `kernel.bend`'s `ops` row — WIRED, AND THE LITERAL AND THE CALL AGREED

## State found on arrival

The oracle the gate reads is **`.agents/slop/notes/kn-truth.py`** (cited at
`tinybendygrad/codegen/kernel.bend:954`). `jj diff` shows it **modified, uncommitted**.
The committed parent (`jj file show -r @-`) printed the row as a hardcoded literal at
**line 167**:

```python
print("pos=20"); print("dup=0"); print("pos_same=1")
print("ix=" + " ".join(str(i) for i in range(20)) + " ")
print("ops=NOOP CONST CONST CONST SPECIAL BUFFER BUFFER PARAM RANGE RANGE SQRT STORE ALLOC REDUCE SINK PROGRAM PROGRAM INS PROGRAM PROGRAM ")
print("ab=BUFFER")
```

The working copy (mtime Oct 4 06:59, i.e. **after** `kn-noop-truth.py` at 06:09) replaces
those six prints with measurements off real `UOp(...)` objects:
`pos`/`dup`/`pos_same`/`ix` off `fixture()` + `intern_order()`,
`ops` off `n.op.name for n in nodes`, at **line 262**.
**That edit is the dead previous unit's work.** It is uncommitted. I verified it; I did not
write it.

## The measurement, run twice

| run | rows | `ops` |
|---|---|---|
| oracle run 1 | 38 | `NOOP CONST CONST CONST SPECIAL BUFFER BUFFER PARAM RANGE RANGE SQRT STORE ALLOC REDUCE SINK PROGRAM PROGRAM INS PROGRAM PROGRAM ` |
| oracle run 2 | 38 | identical — `diff` rc=0 |
| port `./bin/bend tinybendygrad/codegen/kernel.bend` | 38 | identical |

```
diff oracle port   -> rc=0 (no output)
sha256 oracle = 464e17ad01b46c322032038971677b6e8047e07dd2b505f6147c17ea005bd622
sha256 port   = 464e17ad01b46c322032038971677b6e8047e07dd2b505f6147c17ea005bd622
```

Byte-identical, 38 rows each. (Count-based diffs mislead, so: the sha256 of the whole
lane text, not a row count, is the claim.)

## Did the literal and the call AGREE? — YES, on all six rows

| row | committed literal | derived | agree |
|---|---|---|---|
| `ops` | `NOOP CONST … PROGRAM ` | same | **YES** |
| `pos` | `20` | 20 | YES |
| `dup` | `0` | 0 | YES |
| `pos_same` | `1` | 1 | YES |
| `ix` | `0 1 … 19 ` (from `range(20)`) | `0 1 … 19 ` (from `UOpMetaClass.ucache` insertion order) | YES |
| `ab` | `BUFFER` | BUFFER | YES |

**So the literal had not been wrong.** That is the finding, and it is a *negative*
finding: 6 of 6 rows of `kernel.bend`'s oracle were correct when hand-typed. It is worth
exactly as much as that — it does not license typing the next oracle.

**Caveat that makes the agreement weaker than it looks.** The committed `ix` was
`range(20)`, which asserts "the fixture interns 0..19 in construction order" without
reading anything; the derived `ix` reads `UOpMetaClass.ucache`'s insertion order. Those
two are different claims that happen to hold on the same fixture. Agreement between them
is corroboration of *ordering*, not of *node identity*.

## The lead literal: `kn-noop-truth.py` builds the WRONG RANGE and STILL agreed

`kn-noop-truth.py` (the instrument the brief points at) builds its RANGEs by hand as
`UOp(Ops.RANGE, src=(c4, CONST(0)), arg=AxisType.UPCAST)` — axis type in `arg`, axis id in
`src`. I measured both spellings against the pin:

```
kn-noop-truth RANGE    op=RANGE  len(src)=2 arg=AxisType.UPCAST         src_ops=['CONST', 'CONST']
kn-truth UOp.range     op=RANGE  len(src)=1 arg=(AxisType.UPCAST, (0,))  src_ops=['CONST']
op NAME identical (so the `ops` row cannot see the difference): True
```

`kn-noop-truth.py` agrees with the port **on a node CPython never builds**. This is the
`nv_query_litter` failure mode one level down: a wrong instrument that agrees with a
right port is indistinguishable from a right instrument. The working-copy `kn-truth.py`
uses `UOp.range(4, (0,), UL)` and its comment names this; I re-measured it rather than
believing it. **`kn-noop-truth.py` should not be used as a witness again.**

## What the converted row actually discriminates — 5 mutations, `kn-ops-mutate.py`

Baseline 38 rows, scratch copy asserted byte-identical to the live tree before and after
(`md5 a5094b436d53be050916206dee9bd495` both ends).

| mutation | rows moved | `ops` moved? | what it was |
|---|---|---|---|
| M1 fixture mints SIN where CPython mints SQRT | 1 | **YES** | op-name swap |
| M2 stale arena: pr3 interned in pr2's | 3 | **YES** | dedup drops INS, `ix` shortens 20→19, `pos_same` 1→0 |
| M3 pr2's two srcs swapped | 0 | no | same op multiset |
| M4 `ru` axis UNROLL→LOOP | 2 (`rm`, `rm_unroll`) | **no** | op name still `RANGE` |
| M5 b7's slot 7→9 | 0 | no | no op name changes |

**`ops` moved under M1 and M2 and not under M3, M4, M5.** That is the whole of its
discriminative power over this fixture: it is an **op-NAME sequence**, so it is blind to
src order (M3), to anything inside an `arg` (M4, M5), and — as measured above — to a
node whose `src` count and `arg` shape are wrong as long as the name is `RANGE`.

M3 moved **zero rows in the entire 38-row oracle**, not just `ops`. Two srcs swapped on
`pr2` is invisible to every row `kernel.bend` has.