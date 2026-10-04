# DELIVERABLE — `renderer/llvmir.bend`, the `=`-bearing row names, and the guard

Files: `tinybendygrad/renderer/llvmir.bend`, `.agents/slop/llvmir-oracle.py`,
`.agents/slop/llvmir-gate.py`, `.agents/slop/llvmir-gate-noguard.py`, `.agents/slop/li/**`.
`renderer/nir_llvmir.bend` was **NOT** touched — see "NOT FIXED" for why, with the counts.

## 1. The census on THIS lane, and a correction to the brief

The brief's table says llvmir has **157** `=`-bearing names with **48 on ONE key**. The 157 is
right. The 48 is the SECOND-largest key, and it is not a correction the census got wrong — it is
a correction to *how its result was quoted*: `name-census.md`'s key list prints **five** keys of
the eleven, and `rfn abi` (77 rows) was not among the five.

From the census's own `name-census.json`, `tinybendygrad/renderer/llvmir.bend`, `port` lane:

| shipped key | rows | names |
|---|---|---|
| `rfn abi` | **77** | `rfn abi=None` (29), `abi=amdgpu_kernel` (24), `abi=win64cc` (24) |
| `br2 load vol` | 48 | `br2 load vol=False/True {f32,i32,u8} [0..7]` |
| `br5 stack n` | 10 | `br5 stack n=1/2/3/4 …` |
| `br3 load vol` | 6 | `br3 load vol=False/True {f32,i8,u64}` |
| `br4 store vol` | 6 | `br4 store vol=False/True {f32,i8,u64}` |
| `is_volatile PARAM vol` | 2 | `vol=False`, `vol=True` |
| `is_volatile CAST vol` | 2 | ″ |
| `is_volatile BUFFER vol` | 2 | ″ |
| `is_volatile CONST vol` | 2 | ″ |
| `is_volatile AFTER vol` | 2 | ″ |
| `lt 1 ptr f32` | 2 | **no `=` anywhere** — the same name twice |

157 `=`-bearing names → **10** keys → **147 rows unaddressable**. 471 physical rows → **323**
names; 471 − 323 = 148, and 147 of those are the `=` collapse while **1** is the `lt 1 ptr f32`
duplicate, which is a different defect and is why the two must be counted apart.

**The largest single-key collapse on this lane is 77 rows, not 48**, and there are **five**
f-strings, not one. The five row-emitting defs, post-rename, and their seven oracle sites:

| rows | port def | oracle `rows` site |
|---|---|---|
| 10 | `r_ivs()` `llvmir.bend:986` | `llvmir-oracle.py:105` |
| 48 | `r_br2s()` `llvmir.bend:1001` | `:211` |
| 6 + 6 | `r_br34s()` `llvmir.bend:1004` | `:226`, `:229` |
| 10 | `r_br5s()` `llvmir.bend:1007` | `:249` |
| 77 | `r_rfns()` `llvmir.bend:1022` | `:454`, `:461` |

## 2. Per key: was `=` the separator, or load-bearing?

Every `=` on this lane is a **Python keyword-argument separator the port wrote into a LABEL**.
None of them is load-bearing, and each has an upstream `file:line`.

| key | `=` | upstream's own name | verdict |
|---|---|---|---|
| `rfn abi` | `abi=None` / `abi=amdgpu_kernel` / `abi=win64cc` | `abi: str \| None`, **`llvmir.py:147`**; read `{' ' + self.abi if self.abi else ''}` at **`:160`**; values assigned at **`:207`** (`'win64cc' if sys.platform == 'win32' else None`) and **`:230`** (`abi = "amdgpu_kernel"`) | `abi` **is** upstream's identifier — and this file's own `rfn.slot(+abi)` / `r_rfn(+abi)` parameter name (`llvmir.bend:884`, `:899`). `abi=None` is the falsy case. Upstream contains **no `abi=` string at all**. Separator only. |
| `br2 load vol` (48) | `vol=False` / `vol=True` | upstream has **no identifier `vol`**. The function is `is_volatile` (**`llvmir.py:10`**) and the emitters interpolate `{'volatile ' if is_volatile(idx) else ''}` at **`:90`, `:95`, `:98`**. This port's abbreviation is already the `ivol`/`volsp` parameter's name (`llvmir.bend:291`, `:298`) | Separator only. `vol` is the port's standing abbreviation, `cstyle.bend`'s `lb` case exactly. |
| `br3 load vol` (6), `br4 store vol` (6) | same `vol=` | same two lines | Separator only. |
| `is_volatile <SHAPE> vol` (2×5) | same `vol=` | same | Separator only. `is_volatile` IS upstream's function; `vol` is not. |
| `br5 stack n` (10) | `n=1` / `n=2` / `n=3` / `n=4` | upstream has **no identifier `n`**. The STACK rule writes `len(x.src)` and `enumerate(x.src)`'s `i` at **`llvmir.py:103`–`:105`**. `n` is `br5.name(+xn, +i, +n)`'s **third parameter** (`llvmir.bend:612`), standing for that length | Separator only. |

**No transcription of an upstream `format()` spec is involved**, and no `=` appears inside a
`py=` expectation: `ftr`'s values do contain `=` (`"no-trapping-math"="true"`,
`llvmir.bend:915`, `:945`) and those are **values**, correctly so.

## 3. The fix, and the collision check

Three literal substitutions, in the port and in the oracle, each asserted to its exact count
before it ran (so a file that moved under me aborts rather than half-rewrites):

```
llvmir.bend           " vol=" -> " vol "            94 occurrences (70 row names + 24 comments)
                      " abi=" -> " abi "            86            (77 row names +  9 comments)
                      "br5 stack n=" -> "br5 stack n "  21         (10 row names + 11 comments)
llvmir-oracle.py      "vol={vol}" -> "vol {vol}"    8   (4 sites x 2 modes)
                      "abi={abi}" -> "abi {abi}"    2
                      "abi=None"  -> "abi None"     2
                      "stack n={n}" -> "stack n {n}" 2
```

The oracle needed **different patterns**, and that is a finding rather than a detail:
`llvmir-oracle.py:80` is `def par(slot=0, dtype=None, vol=False, aspace=None)`, whose **keyword
argument** contains the substring ` vol=`. `li-rename.py`'s patterns would have rewritten it to
`vol False` and the oracle would have stopped parsing. The oracle's script asserts `par()`'s
signature is byte-identical before and after and `compile()`s the result.

Comments were renamed too (`vol=False` → `vol False` in prose at `llvmir.bend:295-296`,
`:608`, `:1008`, `:1005` and 21 more sites), so no comment names a row that no longer exists.

### The rename was verified against the GENERATOR, not against my own diff

`llvmir-oracle.py`'s `bend` mode prints this file's row-builder source from the same run that
prints the gate text. Its output differs pre- vs post-rename in **5 lines**, and the only
tokens that moved are:

```
77  abi=   ->  77  abi
70  vol=   ->  70  vol
10  stack n=  ->  10  stack n
```

**Not one other byte of the generated port source changed.** So the port's row names are exactly
what the oracle emits — which is the claim the header makes and the only one that can be
corroborated without trusting the diff.

### The collision check, BY MULTISET

`llvmir-gate.py --compare BEFORE AFTER` (`li/rename-audit.txt`):

```
ROWS       472 -> 472 lines; 471 -> 471 read; 470 -> 470 distinct names
           -- EQUAL distinct counts is the collision check: the rename created no name
VALUES     same multiset: True   distinct 253 -> 253   only in BEFORE []   only in AFTER []
RENAME     157 PAIR(S), each one name whose `X=` form is the other side's name with a single
           space in place of the `=`; 0 name(s) have no such partner
COLLISIONS 1 name(s) printed more than once: {'lt 1 ptr f32': 2}
           -- PRESENT ON BOTH SIDES, so it PREDATES the rename and is a separate defect
`=` NAMES  157 -> 0
SHIPPED    323 -> 470 keys of rebase-gate.py:rows(), i.e. 147 more rows a name can address
```

**No collision was created**: 470 distinct names before and after, and every one of the 157
renamed names is exactly its old name with one space where the `=` was.

Three numbers in that audit were wrong in my first version and are recorded because the census
shipped two of the same shapes:

* `=` counted in **`rows_shipped`'s keys** is a **tautological 0** — `row()` cuts at the first
  `=`, so a key cannot contain one, over lane text that *has* the defect. It must come from
  `rows_strict`'s names.
* **collisions counted from `rows_strict`'s dict** are invisible: the dict has already
  overwritten the duplicate, so it printed `none` on the one lane that has one. Counted from the
  LINES, it is 1.
* "how many names were renamed" as `x in A|B and reverse(x) in A|B` is true for every name when
  both sets agree, and it printed **627 on a 470-name lane**. It must be *pairs across the two
  sides*: 157.

## 4. The guard, and its control

`.agents/slop/llvmir-gate.py`. `reshape()` is **GUARD 0**: it runs per lane, **before any value
is compared**, and every non-zero fact goes into `bad`. `rebase-gate.py`'s `rows()`/`row` are
**imported, never copied** — a second reader is how this project got a two-round contradiction.
Six facts, each over `physical` (471) or over `lines` (472):

`eq` names containing `=` · `reshaped` keys fed >1 **different** row · `repeated` keys fed >1
**identical** row · `gate_only` rows the shipped reader cannot read at all · `only_*` the two
readers' name sets, both directions · `unread` lines matching neither shape. `lost` counts
**rows**, never keys (the census shipped a keys count where the quantity is rows and it read 0
on the lane where the loss was largest).

**`row_strict` refuses an ambiguous boundary rather than guessing**: the lane's ` = [` must
occur exactly once in the head, and a row that fails is counted `unreadable`. `rfind`, never
`find`, so a name containing ` = ` cannot be mis-split.

**The predecessor's failure, and why this gate cannot do it.** `cstyle-gate.py`'s old parity
print reported **6 names that no producer printed** as *"only it finds"* — the residue of two
producers' names after `row()` cut them at `=` — and then printed `AGREE`, rc=0. This gate words
the same two sets the other way round and puts them in `bad`:

> `10/471` names the shipped reader **MANUFACTURES out of a reshape, which NO producer printed**

and `--names` labels the second dump `SHIP-RESIDUE` with an explicit count of how many of them
are manufactured. **Honest caveat: that phrasing bug cannot fire on THIS lane**, because the
two lanes are byte-identical, so both readers manufacture the same names and the two sets agree
(cell 1 below prints `0 only it finds, 0 only this reader finds`). What this lane *does* have is
the quieter half of the same failure: `gated 323` over 471 printed rows and `AGREE`, rc=0.

### ⚠ THE VALUE COMPARISON ON THIS LANE IS A TAUTOLOGICAL ZERO

Measured, both before and after the rename: the port's stdout and `llvmir-oracle.py rows`'s
stdout are **byte-identical** (`md5 f099803f6606c675` before, `74e3e8322e0db301` after). Two
sides that print the same bytes agree on every value by construction, so `disagree` is 0 no
matter what the port computes, and the header's own "measured byte-identical to each other and
to the oracle" is the same fact. **The byte diff is this lane's gate; GUARD 0 is the only thing
here that can be red.** The gate prints that as a line rather than leaving it to be inferred.

## 5. THE CONTROL MATRIX — `sh .agents/slop/li/li-control.sh`

`li/control-matrix.txt`. Every cell is a real process and **every `rc` is that process's `rc`**,
captured immediately after it and before any `grep`. Cell 1 runs
`.agents/slop/llvmir-gate-noguard.py`, a **running** detector with **no `reshape()` in it** — a
control run against itself is not a control, so the "before" side had to be a gate that lacks
the guard.

| # | gate | bytes | rc | verdict | `eq` | unaddressable | `disagree` | gated |
|---|---|---|---|---|---|---|---|---|
| 0 | — | `unrename(post) == pre-port.txt` | — | `True`, md5 `f099803f` both | **157** | — | — | — |
| 1 | **pre-guard, no reshape** | PRE-RENAME | **0** | **AGREE** | — | — | `[]` | **323** |
| 2 | **guarded** | PRE-RENAME | **1** | **BROKEN** | **157** | **148** | `[]` | 470 |
| 3 | guarded | POST-RENAME | 1 | BROKEN — **only the duplicate** | **0** | 1 | `[]` | 470 |
| 3b | guarded | POST-RENAME − duplicate | **0** | **AGREE** | 0 | 0 | `[]` | 470 |
| 4 | guarded + **NAME plant, both lanes** | POST-RENAME | **1** | **BROKEN** | 4 | 3 | **`[]`** | 470 |
| 5 | guarded + **VALUE plant** | POST-RENAME | 1 | BROKEN | **0** | 1 | `['lt f32']` | 470 |
| 6 | `--selftest` | real 472-line lane | 0 | OK | | | | |

**Cells 1 → 2 are the argument.** Same bytes, same byte diff, `disagree=[]` in both. The verdict
moves `AGREE` rc=0 → `BROKEN` rc=1, and the coverage moves **323 → 470** of 471 printed rows.
Cell 0 is why cell 2 is not a reconstruction: `--unrename` reverses the rename in the row-name
field of the live bytes with four anchored patterns and reproduces the captured pre-rename
stdout **byte for byte**, so the pre-rename side of the control needs no checked-in oracle.

**Cell 4 is the control a value plant cannot fake**: three `rfn abi None global` rows renamed to
`glob=al` (so **3 rows land on 1 key**) plus one `br3` name given an `=`. Result
`eq=4 unaddressable=3 disagree=[]` — **every value agrees**, the byte diff is empty, and the
verdict moves on the name lane alone. A value plant is *incapable* of that shape, and that is
why it is the falsification rather than the evidence.

**Cell 5 is the falsification**: a planted value gives `eq=0` while the lane goes BROKEN, so a
name check a value plant can turn green is not testing the name.

**Cell 6**, `--selftest` over the real 472 lines (not a synthetic fixture, whose imports could
break and whose failures would be ambiguous):

```
clean    AGREE    eq=0 unaddressable=0 disagree=[]
value    BROKEN   eq=0 unaddressable=0 disagree=['lt f32']
shape    BROKEN   eq=1 unaddressable=0 disagree=[]
collide  BROKEN   eq=2 unaddressable=1 disagree=[]
```

`selftest`'s `clean` base is the real lane **minus the one duplicated name**, and it prints that
removal, because a "clean" lane that is quietly not the real lane is the failure this work is
about.

## 6. How many of the 157 COST A MEASUREMENT

**147 of 157 lost a measurement; 10 were merely misnamed.** Per key, `rows()` keeps the **last**
row on a key, so a key holding *n* rows costs *n−1*:

| key | rows | lost | misnamed-but-reachable |
|---|---|---|---|
| `rfn abi` | 77 | **76** | 1 (`rfn abi=None empty [4]`) |
| `br2 load vol` | 48 | **47** | 1 (`br2 load vol=True u8 [7]`) |
| `br5 stack n` | 10 | 9 | 1 (`br5 stack n=3 bf16 [2]`) |
| `br3 load vol` | 6 | 5 | 1 |
| `br4 store vol` | 6 | 5 | 1 |
| the five `is_volatile … vol` keys | 2 each | 1 each | 1 each |
| | **157** | **147** | **10** |

The census's project-wide split was 59 merely misnamed / 302 costing a measurement.
**llvmir alone carries 294 of those 302 reshape rows — 97% — on its own two lane texts**
(147 on the port lane and 147 on the oracle lane; `name-census.json` puts `nir_llvmir`'s four
each at the remaining eight, and its `LOST=148` per lane is 147 reshape + 1 duplicate). And
note the second column is the *load*, not a disagreement count: the pre-rename lane reported
**`disagree=[]` and `AGREE` throughout**. Nothing was red, and 147 measurements were unreachable
by any name, on both sides, under a green verdict. That is the whole failure.

## 7. NOT FIXED — reported

1. **`lt 1 ptr f32` is printed twice, on BOTH sides. No `=` is involved.** `llvmir.bend:981` and
   `llvmir-oracle.py:647-648` each list the tuple `(1, dtypes.f32, True)` **twice** in the same
   `lt` count/ptr table (`(1,f32,True), (4,f32,False), (4,f32,True), (1,f32,True), (8,f64,False),
   (2,bf16,True)`), so entry four is entry one again. This is exactly the `nv_query_litter`
   shape agent-core.md records: **wrong in the PORT and in the ORACLE**, so the differ reports
   0 disagreements over a mistake made twice. Deleting the repeat costs no coverage — the claim
   is identical — but **guessing what entry four was meant to be would invent a row**, so it is
   REPORTED and cell 3b shows what the lane reads like without it (470/470, `AGREE`, rc=0). The
   owner may also prefer to make entry four `(1, f32, False)` (bare, count 1), which is a
   distinct claim `ldt` can answer; I did not assume it.
2. **The header named an oracle that does not exist.** It said `.agents/slop/li/li-oracle.py`;
   `rebase-gate.py`'s roster points at `.agents/slop/llvmir-oracle.py` and `li/` holds captures.
   Fixed, with the paths and the "a byte diff is not a coverage statement" caveat added.
3. **`renderer/nir_llvmir.bend` — 8 `=`-names, 4 keys, 4 rows lost — NOT TOUCHED, because the key
   is not the same one.** Its keys are `sd cpullvm {LLVM,x86_64,arm,riscv64} osx`, 2 rows each,
   from `r_sdcpu("LLVM osx=True", …)` (`nir_llvmir.bend:1058`); the token is **`osx`**, not `abi`,
   `vol` or `n`, so the brief's "only if the same key appears there" condition is not met. For the
   owner's analysis: upstream's identifier is `OSX`, imported from `tinygrad.helpers`
   (`llvmir.py:8`) and read at `llvmir.py:219`; upstream contains no `osx=`. Same defect, same
   one-character fix, different file and a different token.
4. **`uop/render.bend`** — 31 `=`-names, 30 rows collapsed onto the single F1 key `ast`, and the
   census's lane-shape-blind reader false-positived 31 of them. Under single ownership: REPORTED.
5. **`rebase-gate.py:1892` carries `# 323` on the llvmir lane entry** — the pre-rename
   addressable-name count, now **470**. Live file, another unit's.

## 8. Reproduce

```
.venv/bin/python .agents/slop/llvmir-gate.py                    # live gate, rc=1 on the duplicate alone
.venv/bin/python .agents/slop/llvmir-gate.py --selftest         # rc=0
sh .agents/slop/li/li-control.sh                                # the matrix above
.venv/bin/python .agents/slop/llvmir-gate.py --compare .agents/slop/li/pre-port.txt .agents/slop/li/post-port.txt
```

`./bin/bend tinybendygrad/renderer/llvmir.bend --check-only` prints `ALL PROOFS CHECK`.