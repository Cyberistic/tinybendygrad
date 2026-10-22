# CONST IDENTITY -- the two divergences, measured, and the wall

Unit: the port's CONSTANT IDENTITY vs upstream's, in BOTH directions.
HEAD at the start: `27e4e33cca5a7ed73ccc82611a34fda0baba0de8`.

Instruments landed by this unit:

| file | what it is |
|---|---|
| `gates/constid.bend` | the PORT's rows (the driver's lane) |
| `gates/constid-oracle.py` | CPython's rows (the oracle's lane) |
| `gates/constid-gate.py` | the three-lane gate |
| `gates/constid-plant.py` | the PLANT: the IEEE comparator, on a COPY |
| `gates/constid-ops-bend.patch` (under `patch/`) | the prepared `uop/ops.bend` patch |

---

## 1. THE MERGE -- two upstream constants the port makes ONE

### Upstream, MEASURED (`.agents/slop/constid/oracle.py`, `gates/constid-oracle.py`)

`dtype.py:8-25`'s `ConstFloat` packs its value with `struct.pack('<d', v)` -- a DOUBLE --
and `__hash__` is `hash(self.bits)`.  So upstream's float-const identity is 64 bits wide.

```
ConstFloat(0.1).bits              = 0x3fb999999999999a
ConstFloat(0.10000000149011612).bits = 0x3fb99999a0000000
hash(ConstFloat(0.1))              = 2286027170853263771
hash(ConstFloat(0.10000000149011612)) = 2286027170960637953    <- DIFFERENT
ConstFloat(0.1) == ConstFloat(0.10000000149011612) = False
```

**AND THE PORT's KEY, WHICH IS THE BIT PATTERN ITSELF** (the port has no separate hash
function: the arena's key comparison is `eq_const.CFloat`, i.e. the bits):

```
F32.bits(0.1)               = 0x3DCCCCCD
F32.bits(0.10000000149011612) = 0x3DCCCCCD                     <- THE SAME
```

**TWO KEYS IN ONE HASH TABLE** -- upstream's own `ucache` key is
`(op, src, arg, tag, type(arg))` (`ops.py:201`), and the two key tuples are TWO ENTRIES IN
ONE DICT:

```
keys_in_one_table(UOp.const(0.1, weakfloat), UOp.const(0.10000000149011612, weakfloat)) = 2
```

The second pair is the one whose VALUE the port's own formatter can see.  2**24+1 is the
smallest integer an f32 cannot hold:

```
ConstFloat(16777217.0).bits = 0x4170000010000000
ConstFloat(16777216.0).bits = 0x4170000000000000     <- a different double
hash(ConstFloat(16777217.0)) = 103582791697956866
hash(ConstFloat(16777216.0)) = 103582791429521410     <- DIFFERENT
struct.pack('<f', 16777217.0) == struct.pack('<f', 16777216.0)   <- the SAME f32, 0x4b800000
```

### The port, MEASURED (`gates/constid.bend`)

A Bend float LITERAL is an F32 literal (`references/bend/bend2/bend.ts:2204-2210`), so the
port's `0.1` and its `0.10000000149011612` are the SAME 32 bits:

```
merge_f32_bits=1036831949            # 0x3DCCCCCD, both
merge_keys=1                          # ONE key in ONE arena (upstream: 2)
merge_keys_int=1                      # ONE key in ONE arena (upstream: 2)
merge_keys_control=2                  # THE CONTROL: two keys when they differ
merge_value_text=16777216.000000     # upstream holds 16777217.000000
```

**THE MERGE IS A HASH COLLISION IN THE PORT's CONSTANT IDENTITY, AND THE CONSTANT ALSO HOLDS
A DIFFERENT NUMBER.**

---

## 2. THE SPLIT -- two nan payloads

### Upstream, MEASURED

`dtype.py:16-18` and `dtype.py:21` say two DIFFERENT things about the same object:

```
ConstFloat(nan_p1) == ConstFloat(nan_p2)   = True    # __eq__: nan == nan
hash(ConstFloat(nan_p1)) != hash(nan_p2)    = True    # __hash__: hash(self.bits)
```

**UPSTREAM'S OWN TWO RULES CONTRADICT EACH OTHER, AND UPSTREAM'S OWN HASH TABLE SETTLES IT
FOR `__hash__`:**

```
keys_in_one_table(nan_p1, nan_p2) = 2      # TWO ENTRIES IN ONE DICT
keys_in_one_table(nan_p1, nan_p1) = 1
```

### Reachability -- and the payloads each side uses

* upstream's REACHABLE const nan is `math.nan`, the DOUBLE `0x7FF8000000000000`, because
  `DType.const` CANONICALISES a nan before `ConstFloat` wraps it (`dtype.py:81-82`:
  `if isinstance(val, float) and math.isnan(val): val = math.nan`).
  MEASURED: `UOp.const(nan, float32).src[0].arg.bits` and
  `UOp.const(nan_with_other_payload, float32).src[0].arg.bits` are BOTH `0x7ff8000000000000`.
* the port's REACHABLE const nan is the F32 `0x7FC00000` -- and that IS the f32 of
  upstream's payload (MEASURED: `struct.pack('<f', math.nan)` = `0x7fc00000`).  **THE TWO
  SIDES' PAYLOADS ARE THE SAME VALUE AT THEIR RESPECTIVE WIDTHS.**
* a HAND-BUILT second payload is reachable only by bypassing `DType.const`: upstream
  `ConstFloat(0x7FF0000000000001)`, the port `F32.from_bits(0x7FC00001)`.

**IS THE PORT's `eq_const.CFloat` REACHABLE FROM ANYTHING THAT CAN HOLD A NAN? YES** --
`O.CFloat{F32.div(0.0, 0.0)}` is the reachable nan const (`split_keys_reachable=1`, and
`t_float_nan_interns` already asserts it), and it is ONE key, exactly as upstream's
canonicalised nan is ONE key.

### The port, MEASURED, AND IT IS A LANE SPLIT

```
                    bd (the JS lane)   bn (the C lane)   upstream
split_keys_distinct      1                 2              2
split_eq_distinct        1                 0              (upstream's == is 1, upstream's TABLE is 2)
split_bits_p2   2143289344 (0x7FC00000) 2143289345 (0x7FC00001)  -
```

* **THE C LANE IS RIGHT**: two nan payloads are TWO keys, matching upstream's hash table.
  `eq_const.CFloat` compares the BITS, and that is the correct answer for a CONST IDENTITY.
* **THE JS LANE COLLAPSES EVERY NaN ONTO ONE PAYLOAD** -- `tinybendygrad/base.bend:36-47`
  already says so, and this measurement CONFIRMS it independently: the JS lane's
  `F32.bits(F32.from_bits(0x7FC00001))` is `0x7FC00000`.  The C lane keeps it
  (`references/bend/bend2/comp.ts:391/396` carries an F32 as the raw `u64` of its pattern).
  `bin/bend <file>` IS the JS lane: `main.ts`'s `book_run` -> `Comp.io_run` compiles the
  book to JS and runs it in bun; `bin/bend <file> -o <bin>` is the C lane.

### THE ANSWER TO "FIX IT IF THE PORT's EQUALITY IS THE THING THAT DIVERGES"

**THE PORT's EQUALITY IS THE KEY IDENTITY, AND IT DOES NOT DIVERGE FROM UPSTREAM's HASH
TABLE.  MAKING IT IEEE WOULD CREATE A HASH COLLISION UPSTREAM DOES NOT HAVE.**  The plant
measures it -- see §5.

What diverges is the WIDTH, and the WIDTH is a WALL -- see §3.

---

## 3. THE WALL -- what the compiler actually offers, FROM THE SOURCE

**Is there an `F64`?  NO.**  `references/bend/bend2/base.bend:65-68` is the whole of the
numeric primitive types:

```bend
type U32 is Data:
  U32{data: Word(32n)}

type F32 is Data:
  F32{data: Word(32n)}
```

and the ONLY occurrence of "f64" in `references/bend/bend2/` is a COMMENT at `bend.ts:1156`
about `f32_round` using JavaScript's f64 `Number` internally.  There is no f64 ARITHMETIC to
call.

**Is a float literal an f32 literal?  YES.**  `references/bend/bend2/bend.ts:2204-2210`:

```ts
  const v = f32_round(m[0]);
  if (!isFinite(v)) {
    parse_fail(p, "a float literal with a finite f32 value (got " + m[0] + ")", beg);
  }
  return Lit("F32", f32_to_bits(v));
```

**Is a `Word` of 64 legal?  YES.**  `base.bend:54-62`:

```bend
type Word.Con<-p: Nat> is Data:
  WCon{head: Bool, tail: Word(p)}

def Word(n: Nat) -> Data:
  match n:
    case 0n:
      Word.Nil
    case 1n+p:
      Word.Con<p>
```

`Word(p)` is generic over `Nat`, so `Word(64n)` is a type, and `base.bend:1187-1260` gives
it `zero`, `not`, `and`, `or`, `xor`, `shl`.

**A way to hold the bits in a `U32` pair?  YES -- AND THE PORT ALREADY HAS IT.**
`tinybendygrad/helpers.bend:1647-1648`:

```bend
type I64 is Data:
  I64{hi: U32, lo: U32}
```

with `i64_add`, `i64_sub`, `i64_and`, `i64_or`, `i64_shl`, `i64_cmp` beside it.

**⇒ SO A BEND VALUE CAN CARRY THE 64 BITS OF A DOUBLE.  THE WALL IS NOT THE STORAGE.**

**⇒ THE WALL IS: BEND CANNOT *PRODUCE* THOSE 64 BITS.**
* it cannot WRITE a double (a float literal is `Lit("F32", ...)`), so the port's SOURCE
  cannot spell upstream's `0.1` as upstream's `0.1`;
* it cannot COMPUTE a double (no f64 arithmetic), so it cannot compute the f32 truncation
  of a double from that double's bits -- and upstream's `truncate[float32]` IS exactly
  `ctypes.c_float(x).value`.

**⇒ THE THIRD WAY, AND IT IS AVAILABLE IN THE PORT's OWN ARITHMETIC: an f64->f32 rounding
is pure INTEGER work on the 64 bits** (extract sign/exponent/mantissa, round to nearest
even, handle subnormals and overflow), and `H.I64` has add/sub/and/or/not/shl/cmp.  So
`CFloat{f: F32, d: H.I64}` is BUILDABLE: the f32 is computed from the double's bits by a
rounding function written in integer arithmetic, and the double's bits are SPELLED at the
site.  **WHAT IS MISSING IS THE ROUNDING FUNCTION AND EVERY `CFloat{...}` SPELLING SITE** --
which is a change to `uop/ops.bend`'s `Const` and to the whole tree's call sites, and
`uop/ops.bend` is another unit's file.

---

## 4. WHAT LANDED, AND THE PREPARED PATCH

LANDED (comment-only, in the two FREE files):

* `tinybendygrad/dtype.bend` -- the `truncate_float` wall comment now carries the WHOLE
  wall: the 64-vs-32 identity divergence with its measured counts, the compiler's answer
  quoted from its source, the three things the port CAN do with 64 bits, and the two it
  cannot, and the SETTLED nan answer with the plant's measurement.
* `tinybendygrad/mixin/creation.bend` -- `cr_const_of.trunc` carries the REACHABILITY of
  the merge (the weakfloat arm is the identity on the PORT's F32, which is not upstream's
  identity on a double) and says the fix is `uop/ops.bend`'s `Const`.

PREPARED, NOT APPLIED (`patch/constid-ops-bend.patch`, 59 lines):

* at `type Const`'s `CFloat{f: F32}` -- the same wall, where a reader who opens
  `uop/ops.bend` will see it, with the measured counts and the compiler's answer;
* at `eq_const.CFloat` -- the NAN ANSWER, and the instruction NOT to change the
  comparator.

**IT WAS NOT APPLIED BECAUSE `tinybendygrad/uop/ops.bend` IS `MM` -- ANOTHER UNIT'S
IN-FLIGHT WORK -- AT BOTH THE START AND THE END OF THIS UNIT.**  The patch applies cleanly
to the current working copy (`git apply --check` rc=0).

---

## 5. THE PLANT

`gates/constid-plant.py` copies the whole `tinybendygrad/` tree (a `.bend` file imports its
neighbours relative to its own path, so a copy of ONE file cannot resolve them), applies the
mutation to the COPY, and measures the C lane.

**THE ARM: A CONST THAT UPSTREAM KEEPS APART MUST NOT BE ONE IN THE PORT -- PLANT IT AND
SHOW THE PORT's COUNT OF DISTINCT CONSTANTS MOVE.**

The mutation is the comparator itself:

```
  case CFloat{g}: U32.is_eq(F32.bits(f), F32.bits(g))      # the port's
-> case CFloat{g}: F32.is_eq(f, g)                          # IEEE
```

and the count of distinct constants in ONE arena MOVES **2 -> 1** -- a collision upstream
does not have.  **AND `merge_keys` DOES NOT MOVE**: it stays 1, because the merge is not the
comparator's doing, it is the WIDTH.  A plant that moved every count would have proved
nothing about which defect it is.

---

## 6. THE DIGEST

`checks/differ.py`'s `substrate_digest()` hashes the WORKING COPY, and `substrate_entries()`
walks `tinybendygrad/` and `tinygrad/` plus a handful of NAMED inputs.  **`gates/` is NOT in
the walks, so the four gate files DO NOT move the digest; only the two `.bend` files do.**

* BASELINE, measured live at 10:04 before any of my edits:
  `c92e6ccc8398d4c9c95e7bf5a705876daf1f579129881140c441291c7e21c733`
* THE ATTRIBUTED DELTA, measured by swapping MY two files' entries in the entry list and
  recomputing (bit-identical to having swapped the files on disk), with EVERYTHING ELSE
  held at the same instant:

```
digest_live             = 2e9b27badeee6a705c0894298d031971d95fb2346a29e45ad488dfdd6ec9bebb
digest_without_my_edits = 9f667b09446bbbdbbf324ae5d094b5d2647dd17a2d7352d28ded10a309bb9eb8
```

**⇒ THE ATTRIBUTED DELTA IS `2e9b27ba…` → `9f667b09…` WITH MY EDITS OFF AND BACK WITH
THEM ON.**  The instrument is `.agents/slop/constid/digest.py --attr F1 F2 --base 853bed545^`.

**THE DIGEST ALSO MOVED FOR A SECOND REASON, AND IT IS NOT MINE:** other units committed
(`44e89e67b`, `298ad16f0`, `93e9efdf5`, `51359907a`) and are editing `tinybendygrad/`
while this unit worked, so the live digest is not the baseline plus my delta.  **THE
ATTRIBUTION IS DONE AT ONE INSTANT, WITH EVERYTHING ELSE HELD STILL, WHICH IS THE ONLY
HONEST WAY TO DO IT.**

**THE CORPUS WAS NOT RE-RUN.  `differ.py` WAS NOT RUN.  `runs/graphcmp/` WAS NOT READ.**

---

## 7. THE COMMIT

`853bed545` -- "constid: the port's CONSTANT IDENTITY diverges from upstream's in BOTH
directions, and the MERGE is a hash collision" -- 11 files, +1155/-1, and it carries EXACTLY
those 11 paths.

**THE RECIPE, AND IT IS MEASURED IN A THROWAWAY REPO FIRST** (`.agents/slop/constid/` has no
copy of it; the recipe was run against a temp repo with a second unit's uncommitted edit
present, and the assertion was that the commit carries NEITHER the second unit's edit NOR
loses it):

1. `git add -- <the NEW paths>` **ON THE SHARED INDEX** -- so another unit's bare `git
   commit` cannot delete them (AGENTS.md: a private index lands a new file in HEAD but NOT
   in the shared index, and a bare commit would then delete it).
2. `GIT_INDEX_FILE=.git/agent-index-constid git read-tree HEAD` then
   `GIT_INDEX_FILE=.git/agent-index-constid git add -- <the NEW paths>` -- the PRIVATE
   index, seeded from the CURRENT HEAD.
3. `GIT_INDEX_FILE=.git/agent-index-constid git commit --only -F <file> -- <all my paths>`
   -- the PATHSPEC is the boundary, so the shared index's other content is not carried.
4. `git show --stat` AND `git fsck --no-progress`, in the SAME command.  `fsck` names the
   THREE KNOWN malformed trees (`d57bc484`, `3a60f33f`, `d83cf685`) and NO FOURTH.
5. `git log -1 --format=%s` -- the subject landed.
6. **AND THEN `git add -- <the two tracked .bend files>` ON THE SHARED INDEX**, because
   step 3's private index left the SHARED index's entries for them at their PRE-COMMIT
   blobs -- so a bare `git commit` by another unit would have REVERTED them.  MEASURED: the
   status was `MM` on both before the re-sync and clean after it.

**WHAT WAS NOT COMMITTED, AND WHY: `.agents/TODO.md` and `.agents/TOOLS.md`.**  Both carry
ANOTHER UNIT's UNCOMMITTED WORK in the working tree (MEASURED: `git diff` on each shows
lines that are not this unit's), and `git commit --only -- <path>` commits the WORKING-TREE
content of a path, so committing either would have carried that unit's work inside this
commit -- the measured hazard AGENTS.md names.  **This unit's tick-off and ledger rows are
IN THE WORKING TREE** (`.agents/TODO.md`'s `const-identity [#######...] 3/7` row and
`.agents/TOOLS.md`'s `constid` section) and go in with whoever commits the shared file,
which is the tree's normal shape for the highest-traffic shared file in the tree.

