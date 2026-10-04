# JS-LANE — the JS lane is CORRECT, and the two lanes do not share an ABI

> ## REFUTED BY `JS-LANE-GATE.md`. READ THAT INSTEAD.
>
> **The claim below — "`i64_of` reads the two halves of one record. That is exactly right" —
> IS FALSE, AND IT WAS NEVER EXECUTED.** A record crosses to JS **by name**: the instrumented
> keys are `["$","hi","lo"]`. `H.I64` is `I64{hi: U32, lo: U32}` (`helpers.bend:1639-1640`),
> so `p.fst` and `p.snd` are **both `undefined`**, and **`undefined >>> 0 === 0`** — which
> makes **`i64_of` identically 0 for every input**, so **`Dt.i64_trunc`, the identity
> function, is not the identity.** 30 rows present, **0/30 agree**; the shipped column
> prints `:` on every row.
>
> **The finding that survives is the one about the ABI**, and it is now worse, not better:
> there are **four** undeclared conventions, not two. C's bug was the **argument count**;
> **JS's is the field names.**
>
> **What went wrong here was reasoning from a call site instead of running it.** The `p` in
> `(a) => pack64(i64_of(a))` *looks* like one structured value and I read it as one that
> matches `fst`/`snd`. **It is one value — with the wrong field names.**

The unit dispatched to this job wrote one 4 KB seed file and **completed without a text
response**. Everything below was measured by the coordinator afterwards.

## The finding, which inverts the brief that sent the unit here

The brief said `runtime/dtype.js:136-138` carries **"the same flat assumption"** as the
`dtype.c` bug. **That is wrong, and it is wrong in the direction that matters most: the JS
lane is the correct one.**

```js
// dtype.js:164
io_eff(CID(Dt.i64_trunc), (a) => pack64(i64_of(a)));
// dtype.js:136-137
function i64_of(p) {
  return BigInt.asIntN(64, (BigInt(p.fst >>> 0) << 32n) | BigInt(p.snd >>> 0));
}
```

`a` is **ONE argument**, and it carries `.fst`/`.snd`. So `i64_of` reads **the two halves
of one record.** That is exactly right.

```c
/* dtype.c:270 */ io_eff(CID(Dt.i64_trunc), i64_run, 0);
/* dtype.c:214-217 */
static Term i64_run(Env e, Term* f, IoWork* w) { return pack64(e, i64_of(e, f[0])); }
```

`f` is a **flat frame** (`Term* f`), so `f[0]` is *argument 0* — the whole record — and
must be **opened** with `ctr_take` before its halves can be read. The old reader took
`f[0]` and `f[1]`, i.e. **argument 0 and argument 1**, which is why it returned
`51413338:51413722`: two allocation addresses, not a number.

> **A "SAME ASSUMPTION" CLAIM IS A CLAIM ABOUT A FILE THAT WAS NEVER READ.** Both lanes
> contain the tokens `fst`/`snd` and `f[0]`/`f[1]`, both are called `i64_of`, and both are
> registered under the same `CID`. **The tokens match and the semantics do not**, because
> one lane passes a structured value and the other passes a frame.

## The real hazard this exposes

**The two lanes have different calling conventions for the same effect**, and after the fix
they happen to agree on value and order:

| | reads | order |
|---|---|---|
| `dtype.js` (unchanged) | `p.fst`, `p.snd` — the record's fields | `hi << 32 \| lo` |
| `dtype.c` (fixed) | `ctr_take(e, t, 2, o)` -> `o[0]`, `o[1]` | `o[0] << 32 \| o[1]` |

**Both are `(hi, lo)`, so they agree — by coincidence of ordering, not by construction.**
Nothing in either file states the order, and nothing checks that the two lanes agree. The
header's claim that *"a `.bend` that runs under both lanes cannot tell which one it got"* is
**an assertion, not a measurement** — and now that the two lanes are known to differ in ABI,
that assertion is **load-bearing and unverified.**

## What is still unmeasured

**No gate executes the JS lane.** That is unchanged and it is the open item. The seam gate
`.agents/slop/w64mile/gen_seam.py` drives the **C** lane only (30 rows, shipped ≠ CPython on
30, fixed ≠ CPython on 0). So:

- The JS lane's **arithmetic** — `floor_pair`, `cdiv_of`, the `ceildiv` sign convention at
  `dtype.js:171-172` — is **unexercised**. `ceildiv(x,0)` answers `0` here and in C, where
  CPython raises; counted `diverge`, never `pass`.
- `BigInt.asIntN(64, ...)` is the sign-carrying step in JS. In C it is the `(s64)` cast.
  **Those are different expressions with the same intent**, and only one of them is gated.

## The recommendation, stated as a constraint rather than a task

**Do not "fix" `dtype.js` to match `dtype.c`.** The correct move is the opposite: name the
convention once, in one place, and have both lanes read it. A pair-ordering convention that
lives in two files, in two languages, with no shared declaration **is a wall that will hide
the next `i64_of` bug** — which is precisely how the C defect survived.

## Rules learned

- **A brief that asserts a defect exists sends a unit looking for a defect.** This one said
  *"the same flat assumption"* and the truth was the opposite. Shorten dispatch briefs to
  **the location and the question**, never to a conclusion about the answer.
- **`i64_of` appearing twice, with the same name, under the same `CID`, is not a binding.**
  It is two independent implementations of one ABI, in two languages, with no shared
  declaration. **The ABI is the thing that is missing, and it is missing from the type
  system, not from the code.**
