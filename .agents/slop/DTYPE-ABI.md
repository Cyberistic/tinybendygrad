# DTYPE-ABI — seven undeclared conventions, and a gate that reads the declaration

Rule prefix: **`ABI-`**. Files: `.agents/slop/abi/`.
**SEVEN, NOT FOUR.** The four named in the brief are ABI-1…ABI-4; the gate found three more.

> ## THIS FILE WAS A STUB AND SAID SO.
>
> It read, in full: `STATUS: stub. conventions not yet cited; measurement not yet built.`
> — **beside 216 KB of instrument**: a 623-line `abi_gate.py`, a declaration in `abi.json`,
> and two generated backends (`gen/probe.gen.c` 5,007 lines, `gen/probe.js` 894).
>
> **A stub that says "not yet built" next to a working gate is a report that lies by
> omission, and it is the same defect as a missing row beside a passing one.** A reader
> checking only the prose concludes the job was not attempted.
>
> **What follows was measured from the gate's own output, not from the stub.** Rule `ABI-`.
> `runtime/dtype.c` and `runtime/dtype.js` are **byte-unchanged** — as instructed.

## The declaration is data, not prose

`abi.json` is read by `abi_gate.py`, which drives both lanes and **attributes every
disagreement to one of the four ids**. Its own `_about` block states the limit of the
site check, which is the sentence that matters most in the whole artifact:

> **"That is a DANGLING-POINTER check, not a behaviour check: it can tell you this document
> has gone stale, and it can NOT tell you a lane conforms. Conformance is measured, in
> `rows`."**

**A declaration that cannot fail is a comment with JSON syntax.** This one can: the cited
`file:line` must still contain the token, and conformance is a separate measurement.

## The two backends are cited, not inherited by assumption

> Generated-file sites (`probe.gen.c`, `probe.js`) are **the BEND BACKENDS, not the
> lanes.** They are cited because **two of the four conventions are actually implemented
> there and only inherited by the lanes.**

```
c    gen/probe.gen.c:3133   io_eff_rows[c].run(e, fs, w)
     "the frame is Term* fs of n = cid_arity(c) slots; ctr_take at :3136 built it"
js   gen/probe.js:777       op.run(...op.args, op.kont)
     "op.args is a JS array of NATIVE values, passed through with NO conversion"
```

**ABI-1 and ABI-4 are properties of the backends, and the lanes merely inherit them.** A
lane written by reading the other lane's *code* inherits nothing — which is exactly how both
bugs happened, and why a comment did not prevent either.

## The four original conventions

| id | statement | bug it shipped |
|---|---|---|
| **ABI-1** | a seam receives a **positional frame** of length `cid_arity(the CID)`; an `H.I64` argument is **ONE slot**, not two | C read `f[0],f[1]` = arg 0 + arg 1 and returned **two allocation addresses** |
| **ABI-2** | a record crosses by **field name** | JS read `p.fst`/`p.snd` against fields `hi`/`lo`; **both `undefined`, and `undefined >>> 0 === 0`**, so `i64_of ≡ 0` and **`i64_trunc`, the identity, was not the identity** |
| **ABI-3** | pair order is `(hi << 32 \| lo)` on both sides | agreed **by coincidence**; `pack64` works by **layout, not contract** |
| **ABI-4** | a scalar crosses as **bits** in C and as a **value** in node | `fp16(1.5)` is **`0`** under node |

## What the gate measures — the numbers, from its own output

```
shipped          node disagrees with CPython on   9/12
js-repair-abi2   node disagrees with CPython on   4/12
disarm-abi2-js   node disagrees with CPython on   4/12    <- the control: SAME, so ABI-2's
                                                              repair is what moved the 5 rows
rows moved (ABI-4 plant): 3/12  ['abi4_fp16_1p5', 'abi4_fp16_1p1', 'abi4_fp16_m2p25']

PASS  the ABI-2 repair fixes every record row
PASS  the ABI-2 repair touched ONLY record rows
FAIL  the ABI-4 repair touched ONLY F32 rows
PASS  the ABI-2 disarm moved 0 against the repair
PASS  all four obligations applied, node agrees with CPython everywhere
PASS  the repaired JS lane is byte-equal to the C lane on all rows
gate rc: 1
```

**`gate rc: 1`, and the FAIL is the honest part.** Applying all four obligations makes node
agree with CPython on **12/12** and **byte-equal to the C lane on all rows** — but **the
ABI-4 repair on its own moves rows outside the F32 set**, so ABI-4 is **not yet correctly
localised**. Reported, not reconciled.

The rows make ABI-4 concrete:

```
abi4_fp16_1p5        CPython 1.5               node 0
abi4_fp16_1p1        CPython 1.099609375       node 1.0996094
abi4_fp16_m2p25      CPython -2.25             node nan
abi4_fp8to_0x3C      CPython 1.5               node 1
```

## The three it found by running it

- **ABI-5 — `Term` is a `u64` in C (`probe.gen.c:171`) and a JS `number` in node
  (`dtype.js:142` answers `Number(...)`).** Nothing states which parts of a value are exact
  in each. **This is the whole `Number`-mantissa question, and ABI-5 is where it belongs.**
- **ABI-6 — the zero-divisor branch: both lanes answer `0` where `tinygrad`'s `helpers`
  raise `ZeroDivisionError`.** **The lanes AGREE**, so it is a divergence from upstream, not
  between lanes — and it is counted `diverge`, **never `pass`**.
- **ABI-7 — `dtype.js`'s own return-style split** (ABI-4's `second_site`) was not localised
  when the document was written; it is now attributed.

## Rules this artifact earns

- **A report is not the work, and a stub is not a status.** The instrument was 216 KB and
  nearly finished; the prose said the measurement did not exist. **Write the report from the
  instrument's output, and if you run out, say which half you wrote.**
- **Attribute every disagreement to an id, or you have two lanes and no conversation.** The
  gate's contribution is not that it found ABI-5…7; it is that a red *can be named*.
- **A paired disarm that moves the same count as the plant proves the plant did nothing.**
  `disarm-abi2-js` reads **4/12**, exactly `js-repair-abi2` — so the 5 rows that changed are
  attributable to ABI-2's repair and to nothing else.
