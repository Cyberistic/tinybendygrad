# STAGE 3 — the falsifiable row, 8/8

Reproduce: `zsh $TMPDIR/clangshim/s3.sh` — four laws, one `.c`, one `import`,
one `cc`, run **twice**.

## The working commands

```
REPO=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad
CLIB=/Library/Developer/CommandLineTools/usr/lib
cd $TMPDIR/clangshim

$REPO/bin/bend s3.bend -o s3.gen.c          # step 1
cc -c s3.gen.c -o s3.o                      # step 2
cc s3.gen.c -L$CLIB -lclang -Wl,-rpath,$CLIB -o s3.out   # step 3
./s3.out > s3.r1.out 2> s3.r1.err           # step 4, run 1
./s3.out > s3.r2.out 2> s3.r2.err           # step 4, run 2
```

## THE TWO RUNS, SIDE BY SIDE

```
                    run 1                          run 2
C_SAW HANDLE        4315083488                     4350899280
BEND_HANDLE         4315083488                     4350899280
C_SAW TWO           4315083808  4315084128         4350899600  4350899920
TWO_LIVE_DIFFER     1                              1
PLANT_0             0                              0
PLANT_5             5                              5
DISARM_5_AGAIN      5                              5
PLANT_7             7                              7
C_SAW TRIP          set=0 got=0 / 5,5 / 5,5 / 7,7  set=0 got=0 / 5,5 / 5,5 / 7,7
BEND_CVER           Apple clang version 17.0.0 (clang-1700.6.3.2)   (both runs)
```

```
PASS SAME_OBJ   run1 C reading == Bend reading  (4315083488)
PASS SAME_OBJ   run2 C reading == Bend reading  (4350899280)
PASS TWO_RUNS   the two runs' addresses DIFFER  (differ)
PASS TWO_LIVE   two live handles differ in-process  (1)
PASS PLANT      set 0 -> get 0  (0)
PASS PLANT      set 5 -> get 5  (5)
PASS PLANT      set 7 -> get 7  (7)
PASS DISARM     set 5 twice agrees  (5)

8/8 rows pass
ADDRESSES  run1 C=4315083488  run2 C=4350899280
```

## NEVER EITHER SIDE TO A CONSTANT

`ffi-experiment/run-all.sh`'s first version asserted `BEND_NAT 4307773504`. That
number is an **ASLR-varying heap address**; it changed every run. So this row has
no address literal in it at all:

* **SAME_OBJ** — `clang_createIndex` is called **once**. The shim prints the
  handle C got to **stderr**, then returns it as a `Term`; Bend prints what it
  received. Equal ⇒ one object, read twice, in one process. run1: both
  `4315083488`. run2: both `4350899280`.
* **TWO_RUNS** — the two runs' addresses **differ** (`4315083488` vs
  `4350899280`). If they ever matched, ASLR would be off for this process and
  the row above would be satisfied by a constant.
* **TWO_LIVE** — two indices **alive at the same time in one process**:
  `4315083808` and `4315084128`. This is the control that makes SAME_OBJ mean
  something: if two live handles could be equal, "C and Bend agree on an
  address" would be true of any answer at all. It is checked **in-process**, as
  `TWO_LIVE_DIFFER`, not by reading two numbers.

## THE PLANT, AND THE DISARM THAT MAKES IT MEAN SOMETHING

**PLANT.** `clang_CXIndex_setGlobalOptions(ix, v)` then
`clang_CXIndex_getGlobalOptions(ix)`, with `v` = 0, 5, 7. The answer must be
`v`: it is 0, 5, 7. libclang's own default is `CXGlobalOpt_None` = 0, so the
`PLANT_0` row is also a check against a value libclang itself defines rather than
one I typed.

**DISARM.** The same `v` twice must give the same answer: `trip(5n)` → 5 and
`trip(5n)` again → 5. A harness in which the plant lands *and* the disarm also
moves is measuring the harness. This is the pair `dup-gate.py --selftest` is
built on, and it is the reason a red with no paired disarm is not a finding.

**WHY THE ROUND TRIP IS ONE FOREIGN CALL.** A Bend `Nat` is **linear** —
`expected : ix / observed : ix (consumed more than once)` — and this is true of
*every* `Nat`, not only foreign ones (`def addn(a: Nat, b: Nat) -> Nat: (a+b : Nat)`
then `addn(p, p)` fails on a `p` that never touched C). So
`setGlobalOptions(ix, v)` followed by `getGlobalOptions(ix)` is **not expressible
from Bend at all**: `ix` would be consumed twice, and `def dup(x: Nat) -> Nat: x`
is no escape because passing `ix` to `dup` is itself the one use. Doing both
calls inside one `_run` is what makes the round trip writable. **That is a wall on
callers, not on bindings.**

## THE STRING LANE, because it is the one the census could not fold

`clang_getClangVersion()` returns `const char*`, and Bend receives
`Apple clang version 17.0.0 (clang-1700.6.3.2)` as a real `String`. A Bend
`String` is a cons list of code points (`term_ctr(CID_SCON, loc)`, scalar at
`mem[loc]`, sealed tail at `mem[loc+1]`, `CID_SNIL` terminated), so `io_str` is
what rebuilds it. Note what is **not** claimed: a `const char*` **parameter** is
the ~12-line `bend_cstr` walk, and the census exercised that path only with the
zero argument `""`.

## WHAT A DISARMED LANE WOULD HAVE LOOKED LIKE HERE

Recorded because three controls in this project were found disarmed and one left
six lanes green:

| control | disarmed would look like |
|---|---|
| SAME_OBJ | `C_SAW HANDLE` missing, or the two lines differing by a factor |
| TWO_RUNS | the same address on two runs ⇒ ASLR off ⇒ SAME_OBJ is vacuous |
| TWO_LIVE | `TWO_LIVE_DIFFER 0` ⇒ a constant satisfies "they agree" |
| PLANT | every `v` answering the same thing ⇒ `getGlobalOptions` ignored `set` |
| DISARM | two `trip(5n)` calls disagreeing ⇒ the harness, not libclang |

All five are green, and the DISARM is the one that says the PLANT is about
libclang.