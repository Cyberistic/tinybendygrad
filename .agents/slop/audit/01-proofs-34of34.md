# 01 — "Proofs 34/34, ALL PROOFS CHECK"

**VERDICT: CAN-FAIL** — 7 plants, 7 reds; 3 disarms, 3 greens.

## What the subject is

The 34 `law` declarations in `tinybendygrad/LAWS.bend`, read against the spec
algebra in `tinybendygrad/LAWS/spec.bend` (869 lines), `LAWS/alu.bend` (121) and
`LAWS.bend` itself. Established by reading, not by grepping a name:

```
grep -c '^law ' tinybendygrad/LAWS.bend      -> 34
```

**The proofs are NOT `law`/`check` statements.** They are `def` statements whose
*name matches a law name* (`def L.permute_preserves_numel(t, order): {==}`).
`grep -c '^law '` and `grep -c '^check'` on the three proof files both return 0,
because none of them contains the string `law ` at all. So the brief's "618
lines with zero laws" is right about the grep and wrong about the implication:
the form is name-matched defs.

`PROOF.bend` = 494 lines, 16 `def L.`; `PROOF2.bend` = 109 lines, 18 `def L.`;
`LAWS/PROOF-ALL.bend` = 15 lines, 0 defs — it is only `import Base` + two
imports, because "bend discharges a law by a def of the same name anywhere in
the book".

**Are these closed examples? No.** `law` in Bend is universally quantified over
its `for` binders, so `permute_preserves_numel` quantifies over *all* `t: S.Sp`
including symbolic `SS` dims. This was verified by reading the law body:

```bend
law permute_preserves_numel:
  for +t: S.Sp
  for +order: List<&2, Nat>
  {numel_of(S.SpPermute{t, order}) == numel_of(t) : Nat}
```

## What the instrument actually read

`./bin/bend tinybendygrad/LAWS/PROOF-ALL.bend --check-only`. Its ENTIRE output
is one line. Baseline, run twice:

```
ALL PROOFS CHECK
ALL PROOFS CHECK
```

**Subject vs instrument: they differ, and this is the finding.** The number
"34/34" appears NOWHERE in the instrument's output. Bend does not print a count.
The 34 is `grep -c '^law ' LAWS.bend`; the second 34 is `grep -hc '^def L\.'`
over the two proof files. Measured:

```
PROOF.bend:16  PROOF2.bend:18   = 34
```

and all 34 law names do have a matching `def L.<name>(`. So the stated number is
*true as a count* but the count is not instrumented — nothing in the gate reads
"34". Delete one proof and bend prints `SOME PROOFS FAIL` while both greps still
report 33 and 34 respectively, i.e. the number would read "33/34" only if you
recompute it by hand. Verified:

```
baseline              laws=34  def L. = 16+18 = 34
plant2_delete_proof   laws=34  def L. = 15+18 = 33
```

## Plants — all seven red, each verified twice

Every plant is a change to the **subject** (spec/alu/LAWS), never to the proof,
except plant 2 which is explicitly the proof side. Every case is a fresh copy of
`tinybendygrad/` in `$TMPDIR`; the live tree was never patched.

| # | Plant | Verdict | Named failure |
|---|---|---|---|
| 1 | `LAWS/spec.bend` `case SpPermute{t, order}: Sp.shape(t)` → `Some{Shape.empty()}` | **RED** | `L.permute_preserves_numel` — `- expected : 1n / - observed : S.dims_prod(S.Sp.shape(t))` |
| 2 | delete `def L.permute_preserves_numel` from `PROOF.bend` | **RED** | `Error: 1 TODO found. The code is incomplete, and not a valid proof yet.` |
| 3 | `LAWS/spec.bend` `pick_dim(a,b) -> a` (unconditional) | **RED** | (see note) |
| 4 | `LAWS/spec.bend` `prod`'s `Nil{}` arm `1n` → `0n` | **RED** | `split` at `nat_mul_one_r`: `- expected {Nat.mul(..., 0n) == ...} / - observed {Nat.mul(..., 1n) == ...}` |
| 5 | `LAWS/spec.bend` `case SpReshape{t, src, dst}: Some{Shape.of(dst)}` → `Sp.shape(t)` | **RED** | `L.reshape_preserves_numel` — `- expected {S.dims_prod(S.Sp.shape(t)) == S.dims_prod(S.Sp.shape(t))}` |
| 6 | `LAWS/alu.bend` `neg` → identity | **RED** | `L.neg_is_mul_by_minus_one` |
| 7 | `LAWS/spec.bend` `case SpWhere{q, a, b}: Sp.dtype(b)` → `Sp.dtype(a)` | **RED** | `L.where_takes_the_second_operand_dtype` |

### Plant 3 needs a second try, and the first try is the interesting part

My first pick_dim plant was `def pick_dim(a: Nat, b: Nat) -> Nat: a` — the
identity. **It went GREEN.** That is not a hole: `pick_idem` proves
`S.pick_dim(v, v) == v`, and `pick_dim = \a -> a` satisfies that at `(v, v)`
just as well as the real 4-case body does. My plant did not change the law's
truth value. The second plant, `pick_dim -> 0n`, **went RED**. Reporting the
green first try because it is exactly the brief's trap: a plant that fails to
move a number is only meaningful once you have shown the plant actually
perturbs the subject.

### Plant 6 settles the reflexive-proof question

18 of the 34 proofs are literally `{==}` — `PROOF2.bend`'s own header says "every
one `{==}`". An open question was whether a reflexive body is a real check or a
tautology that encodes the bug (the `device.bend` `sig=0 4 5` failure in
`agent-core.md`). Plant 6 answers it: making `A.neg` the identity makes
`{A.neg(a) == S.SpMul{a, A.one()}}` false and the gate goes red. A `{==}` body
is reflexive against the *definition* it mirrors, so it catches a mis-implemented
spec def but cannot catch a wrong specification. That is the honest reading: it
is a mirror, and it is not tautological.

## Disarms — all three green, so the number is not tracking noise

| # | Disarm | Verdict |
|---|---|---|
| 1 | append a comment to `PROOF.bend` | GREEN |
| 2 | rename dtype `fp8e4m3fnuz` → `fp8e4m3FNUZ` across `LAWS/spec.bend`, `dtype.bend`, `uop/fold.bend` (24 occurrences) | GREEN |
| 3 | add a wrong, unused `def DISARM_relu(a: S.Sp) -> S.Sp: S.SpInvalid{}` to `alu.bend` | GREEN |

Disarm 2 is the brief's own trap, reproduced deliberately. `agent-core.md`
records that a dtype rename silently broke two name-based `match` patterns in
`uop/fold.bend` and stayed green. **A consistent rename of all 24 occurrences is
correctly invisible to the proof set**, because no law in `LAWS.bend` mentions a
dtype name — the dtype laws (`binary_is_uint8`, `comparison_is_bool`,
`store_is_void`, `call_is_void`, `range_is_index`) are about *arm shapes*, not
about `S.Dt.nm`. So the proof set's silence on dtype names is a **coverage
boundary**, not a green gate defect. It is a claim about the spec's shape and
elementwise algebra; it is not a claim about dtype naming.

## Two instrument properties that matter for reading any other green here

1. **`SOME PROOFS FAIL` is over-broad.** It is printed for a *parse* error too,
   not only for a false law. My first two malformed edits produced
   `SOME PROOFS FAIL` with `expected : 'def', 'type' or 'law'` — a syntax error,
   not a law failure. Consequence for this audit and every other: a red from
   this instrument must be read past its first line. (Green is unaffected.)
2. **A def with no return type is a law-proof attempt.** Adding
   `def DISARM_neg(a: S.Sp):` (no `-> T`) to `alu.bend` produced
   `expected : '->' (a def with no return type fills a law; no law named
   DISARM_neg is in scope)`. This confirms the `PROOF.bend` header's claim that a
   helper needs an explicit return type.

## What "34/34" is and is not a claim about

`LAWS.bend`'s own header draws the boundary and the audit confirms it: the laws
are about **the pure spec IR** (`LAWS/spec.bend`), not about the port's UOp
arena. The port does consume that IR — `renderer/__init__.bend:84`,
`renderer/tc.bend:73`, `renderer/tc_ptx.bend:28` and `renderer/isa/x86.bend:188`
all `import ./../LAWS/spec.bend as S` — so the spec is not dead code. But the
34 laws do not measure `tinybendygrad/uop/**`, `schedule/**` or `renderer/**`
semantics. Subject of this number, stated precisely: **the 34 claims in
`LAWS.bend` about `LAWS/spec.bend` + `LAWS/alu.bend`.**

## Reproduce

```
python3 .agents/slop/audit/proof-plants.py
```

Baseline is re-captured and re-verdicted inside the run; the script asserts its
`old` strings are present exactly once, so it fails loudly rather than silently
planting nothing if spec.bend moves under it.