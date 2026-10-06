# THE EVIDENCE — every number, and the two belts that had to move

Every number here was measured in this session. `runs/graphcmp/D` was only ever READ;
its manifest is `31abca502343be9dea7d0b9eba90fa403e5f525621ef11dc1294f4cbd372cee9`
before and after, `git status --porcelain runs/graphcmp` is empty, and its newest
mtime is still `Oct 6 00:31`.

## THE INSTRUMENT, AND WHY IT IS NOT A GATE

`.agents/slop/rows.sh` runs `graphcmp.bend`'s OWN `main` on ONE graph in a **scratch
copy of the tree** and prints the canonical rows. `main` takes the graph name as
argv[1] (`fz_name`, `graphcmp.bend:1344`) and `IO.print`s every row — **it does not
write `runs/graphcmp/D`**, so it cannot perturb the shared run.

It is a copy of `tinybendygrad/` + `.agents/slop/graphcmp.bend` + a private `bin/bend`
shim, under the temp root, with `references/bend/bend2` copied in. **Two `bend`
processes at once is how `sz.bend`'s 1,468 MB becomes an OOM, and three other units
are live**, so `rows.sh` polls `ps -A -o args | grep -c '[b]end2/main.ts'` and WAITS
rather than joining them.

**CONTROL — the instrument reproduces the recorded run BYTE FOR BYTE:**

    ctl-loop  rc=0 WITHIN-LIMITS rows=26 empty-bend=0 helpers.bend=130719
    # root=25 nodes=26 settled=False
    tail -n +2 ctl-loop.out | diff runs/graphcmp/D/D2-canon-bend-loop.txt   ->  IDENTICAL

A driver that did not reproduce the artifact would make every plant below worthless.

## THE VERDICT TOKEN, NOT THE EXIT CODE, AND EMPTINESS AFTER THE GREEN

`checks/bounded.py` prints its verdict on stderr and **bend prints its errors on
stderr too** — `one.sh`'s stdout was EMPTY on every failing run, which is exactly the
"a command that can return nothing without failing" trap. So every result line here
carries `rc=` **and** the parsed token **and** `empty-bend=` **and** `helpers.bend=`:

| run | rc | token | empty `.bend` | `helpers.bend` |
|---|---|---|---|---|
| control, 8 closure files | 0 | `WITHIN-LIMITS` | 0 | 130,719 |
| `loop` plant, 5 closure files | 0 | `WITHIN-LIMITS` | 0 | 130,719 |
| live `ops.bend` after the citation fix | 0 | `WITHIN-LIMITS` | 0 | 130,719 |

Compiler `Bend 2.0.34`. `err=42B` on every invocation, green included — it is
`bend 2.0.35 is available: run bend update`, i.e. an UPDATE NOTICE, not an error.

## PLANT AND DISARM, FOUR LANES, TWO OF THEM NEGATIVE

`opshapes.py <loop|flip|lin> apply|revert <tree>` REFUSES any tree without
`.agents/slop/graphcmp.bend` + `tinybendygrad/uop/ops.bend`, so it cannot be pointed
at the live tree. Every plant is a **NARROWING**, and `revert` is a RESTORE + `diff -r`
(a plant that deletes text has no anchor to be reverted by, so the disarm has to be a
byte comparison rather than a substitution).

### `loop` — `CallInfo.dtype` deleted. **THE ROW MOVES.**

    BASE 402,370 B  ->  PLANTED 402,143 B  (ops.bend, -227)
    ALL PROOFS CHECK  on uop/spec.bend uop/render.bend engine/jit.bend
                      engine/realize.bend schedule/__init__.bend

    BEFORE  3:i25 4:CALL 1:?  1:?  2:i0 1:N 26:cI(shcq_fence,b0,b0,Dvoid) 18:n(i23,i24,i24,i24)
    AFTER   3:i25 4:CALL 1:?  1:?  2:i0 1:N 20:cI(shcq_fence,b0,b0)       18:n(i23,i24,i24,i24)
    CPYTHON 3:i25 4:CALL 4:void 1:R 2:i0 1:N 20:cI(shcq_fence,b0,b0)       18:n(i23,i24,i24,i24)

**The `arg` chunk becomes CPYTHON'S BYTES, and `dtype`/`shape` STAY `?`.** So the
field and the `?` are **TWO** defects, and the brief's premise — that `loop` is one
expensive fix — is half right: the field is the half the narrowing closes.

The narrowing's first bite, on the ops.bend half alone, named its own blind spot:

    expected : ops.CallInfo with 3 fields
    observed : CallInfo{None{}, True{}, False{}, S.Dt{0, 0, S.CVoid{}, "void"}}
    Location: sg.arena          <- ops.bend:6957, a literal the census had

### `loop` — the POSITIVE CONTROL, and it DOES NOT MOVE

Forcing the deleted field to a NON-VOID dtype cannot be run on the planted tree (the
field is gone), so it is forced on the clean one. It does not move the `dtype` column
— because `dt_str`'s `?` is `F.UOp.dtype` returning `None`, i.e. **the fold produced no
`Derived`**, and the driver says so in its own header: `# root=25 nodes=26
settled=False`. `lin` by contrast prints `settled=True`.

### `flip` — `ATuple: List<&2, U32>` -> `List<&2, Bool>`. **GOES RED.**

    SOME PROOFS FAIL
    expected : List<&2, U32>
    observed : List<&2, Bool>
    Location: eq_arg.ATuple     <- ops.bend:1878, `eq_u32(ys, y1)`

The plant names the load-bearing read. **Narrowing `ATuple` itself is the WRONG fix**,
because PERMUTE and UNSHARD really are `tuple[int, ...]`; the correct fix is a
SEPARATE bool-carrying `Arg` variant, and that touches five files (see `02-fix.md`).

**Why the port's `List<&2, U32>` is an ILLEGAL shape, measured against CPython:**

    base (7,3) RESHAPE   UOp(Ops.FLIP, (a,), (1, 0))       -> REJECTED: bad flip on (7, 3), (1, 0)
    base (8,5) RESHAPE   UOp(Ops.FLIP, (a,), (1, 0))       -> REJECTED: bad flip on (8, 5), (1, 0)
    base (6,4) RESHAPE   UOp(Ops.FLIP, (a,), (True,False)) -> ACCEPTED, elems ['bool','bool']
    isinstance(0, bool) = False | isinstance(True, bool) = True

`tinygrad/uop/ops.py:428` is `not all(isinstance(x, bool) for x in self.marg)` and
`marg` returns `self.arg` RAW (`ops.py:815`). **So `graphcmp.bend:1304`'s
`O.ATuple{[1, 0]}` is a value CPython raises on, and the port can hold it.**
`fold.bend:1786-1804` already said the Bool-ness "is not recoverable here"; what is
new is that CPython REJECTS the alternative, which makes the erase a legality bug.

### `lin` — the payload plant DOES NOT MOVE. **THE INSTRUMENT IS BLIND HERE.**

Two plants on the same slot, one bend run apart, and they go in OPPOSITE directions —
which is what makes the pair worth having:

    PLANT L2  applied_opts payload 0 -> 7  (still ONE option)
      tail -n +2 plantL2-lin.out | diff D2-canon-bend-lin.txt  ->  IDENTICAL
      *** NOT ONE BYTE MOVED ***

    PLANT L3  applied_opts COUNT 1 -> 2  (payload still the same wrong 7s)
      3:i46 4:SINK 4:void 1:R 2:i0 2:i1 24:kI(sr_4_5_3,n(q,q),N,i0) 6:n(i45)

`q` is a COUNT (`graphcmp.py:326` `"opt": "q"`, and `graphcmp.bend:316-330` says so in
its own words: *"THE OPTION LISTS ARE COUNTS, NOT CONTENTS … one `q` per option: the
count compares, the content is a named refusal"*). **So `lin`'s `1 = 1` count
agreement carries ZERO information about whether the port models `Opt` — and it is a
property of the DEVICE PIN plus a hard-coded `[0]`:**

    MEASURED by calling the py side, DEV=CPU:      applied_opts = 1  (Opt(SPLIT, 2, (0, UPCAST)))
    MEASURED by calling the py side, default dev:  applied_opts = 2  (+ Opt(SPLIT, 0, (4, LOCAL)))
    env MV=0 / MV_THREADS_PER_ROW=1 / WINO=0 / TC=0: still 2

`runs/graphcmp/D` was taken under `DEV=CPU`, which is why the recorded row has one
option and the default device would make the COUNT disagree too.

### DISARM — one restore, `diff -r`, byte-identical

    restored uop/ops.bend (402,370 B)  uop/fold.bend  uop/spec.bend  uop/render.bend
            engine/jit.bend  engine/realize.bend  .agents/slop/graphcmp.bend
    diff -r tinybendygrad <scratch>/tinybendygrad   ->  empty
    diff .agents/slop/graphcmp.bend <scratch>/...   ->  empty

## A CITATION THAT NAMES A FUNCTION *AND* A SHAPE — RESOLVED, AND THE SHAPE IS ELSEWHERE

    ops.bend:1007 (was)  "`dtype: DType = dtypes.void` … IS read: by `dtype_from_uop`'s
                          CALL arm and by `_shape`'s."
    ops.py:130-132       case Ops.CALL: / "a call has the dtype of its body, void for
                          opaque bodies" / **return src[0].dtype**      <- the BODY

    $ git log -S'dtype: DType = dtypes.void' -- tinygrad/uop/ops.py
    6f4bfde23 restrict allowed call bodies (#17925)
    $ git show 6f4bfde23 -- tinygrad/uop/ops.py | grep 'CallInfo'
    +      return UOp(Ops.CALL, ..., arg=CallInfo(grad_fxn, name, precompile, precompile_backward, aux,
    +                                                ret_dtype if ret_dtype is not None else dtypes.void))
    +  dtype: DType = dtypes.void          <<< the hunk ADDS the field
    $ git show HEAD:tinygrad/uop/ops.py | grep -A6 'class CallInfo'
    grad_fxn / name / precompile / precompile_backward / aux      <<< FIVE, none is dtype

**THE COMMIT THAT ADDED IT IS THE ONLY `git log -S` HIT, AND THE FIELD IS ABSENT AT
HEAD. THE PORT IS PINNED TO A COMMIT UPSTREAM HAS SINCE MOVED PAST.**

**AND THE SAME STALE PIN IS IN `spec.bend`, WHICH THE BRIEF DID NOT NAME:**

    $ git log -S'x.dtype is x.arg.dtype' -- tinygrad/uop/spec.py
    6f4bfde23   (added it)      ad117c928   (the rebase that removed it)
    HEAD spec.py:112  lambda x: isinstance(x.arg, CallInfo)      <- a pure TYPE test
    spec.bend:412     "isinstance(x.arg, CallInfo) and x.dtype is x.arg.dtype -- spec.py:113"

`spec.bend`'s `arg_call` still answers a half that does not exist at HEAD, and
`sh_23.body` compares a DECLARED dtype against the node's own when under HEAD there is
no declared dtype to compare. That is a **second stale citation**, in a file the brief
did not list.