# STAGE 1 — ONE binding, from the committed file to a linked, called binary

Reproduce: `zsh $TMPDIR/clangshim/s1.sh`  (nothing here touches the repo tree)

## The exact working commands

```
B=/Users/cyberistic/src/tries/2026-09-30-tinybendygrad/bin/bend
CLIB=/Library/Developer/CommandLineTools/usr/lib
cd $TMPDIR/clangshim

$B s1.bend -o s1.gen.c                                   # step 1  82579 bytes, rc 0
cc -c s1.gen.c -o s1.o                                   # step 2  compile only, rc 0
cc s1.gen.c -L$CLIB -lclang -Wl,-rpath,$CLIB -o s1.out    # step 3  link,        rc 0
./s1.out                                                   # step 4  rc 0
```

Observed:

```
step1 bend -o   ok (82579 bytes)
step2 cc compile ok
step3 link -lclang ok
step4 run        rc=0 | S1_NAT 4388877072
PASS [s1] one libclang call returned a value
```

## Which binding, and where it came from

`clang_createIndex`, and the input is two committed lines:

* `tinybendygrad/runtime/autogen/libclang.bend:1080` — `def clang_createIndex(excludeDeclarationsFromPCH: U32, displayDiagnostics: U32) -> Maybe<&2, Nat>`
* `.agents/slop/ag-libclang.tramp:2` — `clang_createIndex|CXIndex|CXIndex|excludeDeclarationsFromPCH|ctypes.c_int32|int|displayDiagnostics|ctypes.c_int32|int`

The C declaration is written from those, because **there is no clang-c header on
this machine**:

```c
typedef void* CXIndex;
extern CXIndex clang_createIndex(int, int);
```

That is the refusal being killed. `libclang.bend:15-16` says a per-function FFI
"would mean 324 C files and 324 hand-written shims". A function costs
**3 C lines** here (`PTR` macro, `_run` body, one `io_eff` registration), one
`import` in the `.bend`, and one `cc`.

`CXIndex = ctypes.c_void_p`, so the return crosses as one `Term` word and the
law is `IO(Nat)`. Not a string: `const char*` **return** is 2 lines but a
`const char*` **parameter** is the ~12-line cons walk, and `clang_getClangVersion`
is the case `ffi-experiment/e4.bend` already reached. Both are re-run in Stage 2.

## THE HARNESS TRAP THIS STAGE HIT, and it is worth naming

The first attempt at the four-function version **silently passed on stale
build output**. `bend -o` failed (a real error, printed to stdout), the stale
`s1.gen.c` from an earlier build was still on disk, `cc` linked it, and the
binary printed `X` — a value from the *previous* two-line program. `s1.sh` now
`rm -f`s both outputs and checks `[[ -s s1.gen.c ]]` before compiling, because
`ls`/exit-status chaining is what let a broken build read as a working one.
This is `rebase-oracle-ops.py:54` again: an artefact that dies on its own data
and prints nothing looks exactly like agreement.

## A NEW MEASURED CONSTRAINT: EVERY `Nat` IN BEND 2.0.35 IS LINEAR

`ffi-experiment/EXPECTED.md` records "Foreign values are **linear**
(`consumed more than once`)". Re-measured, and the rule is **wider than that**:

```
$ cat q1.bend                     # p is a PURE Nat, never near a foreign call
def addn(a: Nat, b: Nat) -> Nat: (a + b : Nat)
def main() -> IO(Unit):
  do IO<Unit>:
    p : Nat = addn(1n, 2n)
    q : Nat = addn(p, p)          # <-- error: expected p / observed p (consumed more than once)
```

A `Nat` may be **used exactly once**, whatever produced it. Three consequences,
each of which shaped Stage 2 and Stage 4:

1. A handle cannot be printed *and* passed. There is no `def dup(x: Nat) -> Nat: x`
   escape — the binder inside `dup` is fine, but passing `ix` to `dup` is itself
   the one use, so `ix` is spent.
2. **No libclang round trip is expressible in Bend.** `setGlobalOptions(ix, n)`
   followed by `getGlobalOptions(ix)` needs `ix` twice. That is a wall on the
   *callers*, not on the bindings — every shim still links and every shim still
   runs; what Bend cannot do is chain two calls on one handle.
3. A bare integer literal is **`U32`, not `Nat`**. `addn(1, 2)` is a type error;
   `addn(1n, 2n)` compiles. Worth knowing because a generated law that takes
   `Nat` parameters accepts `0n`/`1n` only.

Also re-measured, and it matters for anyone trusting the file: `bend --check-only`
on any file with a foreign effect prints `SOME PROOFS FAIL` and
`2 defs rely on unsafe or foreign code`. **Exit status is not a gate** (rule in
`agent-core.md`, re-confirmed on bend **2.0.35** — the version named in
`EXPECTED.md`, and `WALL 4`'s "MEASURED, twice" on 2.0.34 is stale).

## What this stage does NOT claim

`s1.out` calling `clang_createIndex` and getting a non-zero word is evidence
that a *signature* is a complete input for a *call*. It is not a device
runtime, and it does not make `clang_parseTranslationUnit` reachable — that
needs a handle to survive across two calls, which is the linear-`Nat` wall.