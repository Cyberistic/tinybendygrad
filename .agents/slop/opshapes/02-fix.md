# THE FIX — the correct type per defect, whether it NARROWS, and what it costs

## THE BAR, RESTATED AS A TEST I APPLIED

> a "fix" that makes a row agree by changing the fixture, or by widening a type until
> everything fits, is not a fix.

**EVERY plant in `01-evidence.md` NARROWS: a field deleted, `List<U32>` -> `List<Bool>`,
`List<U32>` -> `List<OPT>`. NOT ONE OF THEM MAKES ANYTHING AGREE.** The `loop` plant
closes the `arg` chunk to CPython's bytes and leaves `dtype`/`shape` at `?`. The `flip`
and `lin` plants make a green tree go red and change no verdict. That is the point.

## 1. `flip` — WRONG SHAPE, and the port can hold a shape CPython REJECTS

**`ops.bend:919`-style current text, `:1081` in full:**

    ATuple{ys: List<&2, U32>}

**THE CORRECT TYPE** is a **separate** bool-carrying `Arg` variant,
`ATuple`-for-PERMUTE/UNSHARD staying `List<&2, U32>`:

    AFlags{fs: List<&2, Bool>}          # FLIP only. `ops.py:428` asserts bool.

**NARROWS?** YES, but **narrowing `ATuple` itself is the WRONG fix** and I did not
propose it as the fix: `PERMUTE` (`movement.py:231`) and `UNSHARD` (`ops.py:691`,
*"the tuple of sharded axes, sorted"*) really are `tuple[int, ...]`, so `ATuple` stays
int and a FLIP gets its own variant. The consequence is the point of the whole job:
**today the type permits the wrong encoding, so `graphcmp.bend:1304` holds
`O.ATuple{[1, 0]}` — a value `UOp(Ops.FLIP, src, (1, 0))` RAISES on.**

**WHAT IT COSTS — five files, and only one of them is mine:**

| file:line | the change |
|---|---|
| `uop/ops.bend:1081` | add the variant + `eq_arg`'s arm + the `Arg` dispatch arm **(mine)** |
| `uop/fold.bend:1787` `order_arg`, `:2295` `flip_ds` | the `marg` reader must take it |
| `schedule/prepare.bend:277` | constructs `O.ATuple{[a, b]}` on a FLIP |
| `mixin/movement.bend:993`, `:1533` | construct it (`:1533`'s binder is even named `flags`) |
| `.agents/slop/graphcmp.bend:1304`, `:416` | the fixture, and `argstr`'s SINGLE `ATuple` arm |

**`graphcmp.bend:416` is the structural reason and it is not a line count:**
`def argstr` dispatches on the **`Arg` variant alone, not on the op**, so `us(ys)`
renders `n(i1,i0)` for a FLIP and for a PERMUTE with the same arm. **With one element
type there is exactly one spelling and no renderer change can recover a `b`.**

## 2. `lin` — WRONG SHAPE, and the payload is not merely wrong, it is UNOBSERVABLE

**`ops.bend:919` in full, at HEAD before my edit:**

    KernelInfo{name: String, applied_opts: List<&2, U32>, opts_to_apply: Maybe<&2, List<&2, U32>>, beam: U32}

**THE CORRECT TYPE** is `applied_opts: List<&2, OPT>` — **and `OPT` ALREADY EXISTS IN
THE PORT**, at `codegen/opt/postrange.bend:159`:

    type OPT is Data:
      OPT{op: OPTOPS, axis: U32, arg: OPTARG}          # OPTOPS :122, OPTARG :153

Upstream's is `codegen/opt/__init__.py:11`, `Opt(op: OptOps, axis: int|None,
arg: int|tuple|None)`, and the port's `OPT` CAN spell `lin`'s payload:
`OPT{OPS_SPLIT{}, 2, OA_SPLIT{SPL{0, AXIS_UPCAST{}, False{}}}}`.

**NARROWS?** YES — a `U32` becomes an `OPT`, which is the type that says what the slot
is. **What it does NOT fix is honest and is `postrange.bend`'s own note at :163:**
`OPT.axis` is `U32`, upstream's is `int|None`, so `axis=None` is still unspellable.
That is a NARROWING DONE RIGHT that leaves a known hole named, not one widened away.

**WHAT IT COSTS — and the blocker is an IMPORT DIRECTION, not a type:**

    tinybendygrad/codegen/opt/postrange.bend:116   import ./../../uop/ops.bend as O

`postrange.bend` imports `ops.bend`, so **`ops.bend` cannot import `OPT` back.** The
type has to MOVE DOWN into `ops.bend` (or a module under it) first, which is
`postrange.bend` + `search.bend` + `heuristic.bend`. **None of them is mine.**
After the move: `uop/render.bend:664` (`akernel_applied`), `engine/realize.bend:1200`,
and the SETTLED `graphcmp.bend:324` `opts.go` / `:337` `kernelinfo` / `:962`'s
hard-coded `O.KernelInfo{"r_4_5_3", [0], None{}, 0}`.

**THE COUPLING NOBODY NAMED: the option COUNT is environment-dependent.** MEASURED by
calling the py side: `DEV=CPU` gives ONE option, the default device gives TWO. So the
`1 = 1` agreement is the pin, not the port — and re-running the corpus off the pin
would disagree on the COUNT as well as the payload. **A `lin` "fix" that made the count
agree by widening the field would be wrong even though the row then agreed.**

## 3. `loop` — TWO defects on one row, and only one of them is a shape

**`ops.bend:1010` in full:**

    CallInfo{name: Maybe<&2, String>, precompile: Bool, precompile_backward: Bool, dtype: S.Dt}

**THE CORRECT TYPE is upstream's, which is FIVE fields and none of them `dtype`:**

    CallInfo{name: Maybe<&2, String>, precompile: Bool, precompile_backward: Bool}

(`grad_fxn` and `aux` stay dropped — a Python function object and `Any`, P7/P6,
`ops.bend:999-1006`.)

**NARROWS? YES — a field is DELETED. Strictly narrower, never broader.** And it is
PROVEN GREEN: 11 sites in 7 files, `ALL PROOFS CHECK`, and the `arg` chunk becomes
CPython's bytes.

**BUT IT CLOSES HALF THE ROW.** `dtype` and `shape` stay `?` because the fold never
settles CALL#25 (`settled=False` in the driver's own header). **The `?` is a
`fold.bend` wall and it is NOT the field** — which is the sharpest correction to the
brief's premise. `fold.bend`'s `call_ds` would have to read `src[0].dtype` AND the
Kahn settle has to close; neither is a type change.

## THE `graphcmp.bend:301` COUPLING — NAMED AND COSTED

> `graphcmp.bend:301` renders `cI(name, pre, prebackward, dt(cdtype))` from the exact
> field the fix deletes. So the correct port fix breaks a frozen render site and cannot
> land alone.

**CONFIRMED, AND IT IS TWO SITES IN THAT FILE, NOT ONE:**

    :300-301   def callinfo -> case O.CallInfo{cname, precompile, precompile_backward, cdtype}:
                   "cI(" nm "," bo "," bo "," dt(cdtype) ")"        <- the RENDER SITE
    :1004-1005 def g_loop  -> O.ACall{O.CallInfo{Some{"hcq_fence"}, False{}, False{}, S.void()}}
                                                                         <- the FIXTURE, and it
                                                                            HARD-CODES the 4th field

**`:1005` is worse than `:301`.** `:301` renders whatever the port holds; `:1005`
*supplies* the illegal value, so even after the render site is re-cut the fixture would
have to change too. And `:999-1003` already says it knows:
*"Its `CallInfo` has THREE slots on the py side … against the port's FOUR, so this arg
is a REPORTED disagreement by construction."*

**WHAT IT COSTS: one line each, in a file whose last edit is committed and settled.
I DID NOT EDIT IT. `graphcmp.bend` is byte-identical to how I found it — `diff -r`
against the live copy is empty after every plant, including the two that needed it.**

## THE FULL FILE LIST FOR THE `loop` NARROWING — FOUR OF SEVEN ARE NOT MINE

| file | sites | mine? |
|---|---|---|
| `tinybendygrad/uop/ops.bend` | `:1010` type, `:1450/1454/1458/1460` accessors, `:1808` `eq_callinfo`, `:1091` `of`, `:6939` `sg.ci`, `:6957` `sg.arena` | **yes** |
| `tinybendygrad/uop/fold.bend` | `:1142` `call_dt` (delete), `:1150` `call_ds`, `:2263`, `:4909` fixture | no |
| `tinybendygrad/uop/spec.bend` | `:407` `arg_call.go`, `:414` `arg_call`, `:1080-1089` `sh_23.body` | no |
| `tinybendygrad/uop/render.bend` | `:634`, `:637` `arg_repr` fixtures | no |
| `tinybendygrad/engine/jit.bend` | `:1243` | no |
| `tinybendygrad/engine/realize.bend` | `:1416` | no |
| `.agents/slop/graphcmp.bend` | `:300-301`, `:1005` | no — **SETTLED** |

**`graphcmp.bend:301` IS NOT THE SHARPEST COUPLING. `spec.bend:407` IS** — because
`sh_23`'s rule is not a field delete at all: at HEAD `spec.py:112` is
`lambda x: isinstance(x.arg, CallInfo)`, so the whole `Maybe<S.Dt>` half of `arg_call`
and the `sh_23.body.pick/go` pair go away and `sh_23.body` becomes a pure type test.
That is a **rule change in the SPEC layer**, not a shape change in the arena.