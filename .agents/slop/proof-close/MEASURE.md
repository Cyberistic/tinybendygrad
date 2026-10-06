# Close the last two laws — measurements

Before: `./bin/bend tinybendygrad/LAWS/PROOF-ALL.bend --check-only` first lines

    SOME PROOFS FAIL
    Error: 2 TODOs found.

After: `ALL PROOFS CHECK`.

`--verdict` could not run: `lean: Executable not found in $PATH`.

## Arrival

`drop_n` was already `List.drop` (the concurrent unit). The reduce law was already
`prod(List.take(dims, n))`. A checkout race briefly restored the old `case 0n: r`
arm; the `List.drop` form was back before the proof was written. That work was
not reverted.

## reduce_numel_divides_by_the_reduced_axes

Re-measured against the live tree after `drop_n = List.drop`:

| term | case | result |
|---|---|---|
| `take(n)` | (4,) n=0 | 4==4 |
| `take(n)` | (4,5,6) n=1 | 120==120 |
| `take(n)` | (4,5,6) n=0, n=3, n=5 | 120==120 |
| `take(n)` | symbolic (SS,5) n=1 | 0==0 |
| `take(n)` | (5,0) n=1 | 0==0 |
| `take(n+1)` | (4,) n=0 | 16==4 False |
| `take(n+1)` | (4,5,6) n=1 | 600==120 False |
| `prod(drop)` | (4,) n=0 | 16==4 False |
| `prod(drop)` | (4,5,6) n=1 | 900==120 False |

tinygrad: Reduce n=0 of (4,5,6) is (4,5,6); n=1 is (5,6); n=3 is ().
Ruling: prove the already-corrected `take(n)` statement. Not `take(n+1)`.

## broadcast_is_elementwise_max

Count form `max(numel(add), numel(b)) == numel(add)`, live spec:

| case | result |
|---|---|
| (2,3)+(3,3) | 9==9 True, but tinygrad IndexError |
| (SS,5)+(3,7) | 21==0 False |
| (5,0)+(3,) | 3==0 False |
| (5,1,0)+(3,4) | 12==0 False |
| shapeless+(3,3) | 9==0 False |
| (2,0)+(1,1) | 2==2 True under Nat.max |

tinygrad on the same idea:

| case | result |
|---|---|
| (2,0)+(1,1) | shape (2,0), numel 0 < 1, False |
| (0,)+(1,) | shape (0,), 0 < 1, False |
| (1,3)+(2,3) | shape (2,3), 6>=6 True |
| (3,)+(2,3) | shape (2,3). Spec left-align gives (3,3). |

Ruling: the count form is not tinygrad's rule. Restate to the axis rule on
equal-length concrete shapes, and make `max_dim`'s numeric arm `pick_dim`
(a 1 broadcasts to the other size, including 0). Equal length is where
head-zip and tinygrad's right-align coincide. Symbolic dims are excluded
because `dim_of(SS)` is 0.

Gate rows that fail under `Nat.max`: `bc_20_11=2,0`, `bc_0_1=0`. Both True.

## Self-check and mutations

Delete `L.flip_preserves_numel` on a copy: `Error: 1 TODO found.` Counter is
one per unfilled law.

| id | mutation | gate |
|---|---|---|
| C1 | comment only | SAME, ALL PROOFS CHECK |
| M-rb | split Nil base returns `nat_add_zero(0n)` | RED, expected `{1n==1n}`, observed `{0n==0n}` |
| M-rs | split step drops the IH rewrite | RED |
| M-bb | bcast_axes Nil base returns `nat_add_zero(0n)` | RED |
| M-bs | step cong swaps the two tails | RED, expected elem_pick==zip_max, observed the IH the other way |
| M-del | delete flip proof | RED, 1 TODO |

No non-typechecking mutation. No unexplained zero.
Harness wrote only `.agents/slop/proof-close/mut/`. Live tree mtime unchanged
across the run.

`git diff --stat HEAD` for the proof set: `LAWS.bend`, `LAWS/spec.bend`,
`PROOF.bend` only. `alu.bend` and `PROOF2.bend` absent.
