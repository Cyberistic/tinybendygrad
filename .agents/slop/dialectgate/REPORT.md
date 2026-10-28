# `gates/dialect-fixture-gate.py` -- THE 472 WERE NOT ROW TAGS

**THE DEFECT WAS IN THE GATE, NOT IN THE PORT.** MEASURED 2026-10-29.

## WHAT THE GATE DID, AND WHAT IT SAID

The gate's rule was `TAG = re.compile(r'"([^"\n]*)"')` -- **every quoted string** -- and it
reported, per fragment, `claims` / `carried` / `carried_renamed` / `lost`.

```
FRAGMENT  claims=2009  carried=1773  carried_renamed=0    lost=236  oracles/post-oracle-bend.bend
FRAGMENT  claims=2009  carried=1616  carried_renamed=157  lost=236  oracles/pre-oracle-bend.bend
FRAGMENTS  files=7 claims=5280 carried=4651 carried_renamed=157 lost=472
```

**472 "lost" row tags, and NOT ONE OF THEM WAS A ROW TAG.**

## WHY NONE OF THE 472 WAS ONE

`oracles/pre-oracle-bend.bend` and `oracles/post-oracle-bend.bend` are **PTX/LLVM ORACLES**: they
carry the oracle's ASSEMBLY alongside their row tags. A rule that reads every quoted string reads
assembly as claims.

MEASURED, per file (the two files agree EXACTLY, because they differ only on the rename):

| where the old-lost string sits | count per file |
|---|---|
| a **LATER ARGUMENT** of a row-maker call -- a VALUE | 231 |
| an argument of a call that is **NOT a row-maker** -- a PTX DIRECTIVE, a LABEL, a DTYPE LIST | 5 |
| **total old-lost per file** | **236** |

The 231 values are the later arguments of calls like

```
r_lcs("lconst special +inf", True{}, False{}, "0x7FF0000000000000")
```

where the row tag is the **FIRST** argument and the later ones are the values: a dtype name
(`"void"`, `"i8"`, `"half"`), a number (`"10"`, `"0x7FF0000000000000"`), a register name
(`"%v0"`), a LABEL (`"v0_entry:"`), or PTX/LLVM TEXT (`"  %v0 = load float, float* %v1"`).

The 5 are `"alwaysinline"`, `"nounwind"`, `"attributes"`, `"#0"` and the DTYPE LIST
`"fp8e4m3,fp8e5m2,fp8e4m3fnuz,fp8e5m2fnuz"`.

**THE WHOLE POPULATION OF EACH FILE, for the same measurement:** 2,009 quoted strings, of which
**445 are row tags**, 1,529 are later arguments of a row-maker call, 35 are arguments of a call
that is not a row-maker, and **0 are outside every call**.

## THE RULE, AND WHERE ITS POPULATION COMES FROM

> **A quoted string is a ROW TAG iff it lies inside the FIRST ARGUMENT of a call to a ROW-MAKER,
> and a ROW-MAKER is a function THE PORT DEFINES whose FIRST PARAMETER IS THE ROW NAME (`nm`).**

The row-maker set is **DISCOVERED FROM THE PORT**, never typed: the gate walks every `.bend` under
`tinybendygrad/` for `def NAME(... nm: String ...)`, and **PRINTS the set with the file and line
of every definition**, so a reader can re-run the grep and see it is not a list somebody typed.

**285 distinct names, 285 last-components.** MEASURED examples:

```
r_lt        tinybendygrad/renderer/llvmir.bend:481
lf_row      tinybendygrad/uop/fold.bend:4661
srow        tinybendygrad/examples/train_resnet.bend:106
urow        tinybendygrad/examples/train_resnet.bend:108
u1          tinybendygrad/runtime/support/usb.bend:98
```

**THE PORT's DEF NAMES ARE DOTTED** (`Enc.emit.head`, `Op.in_.go`), so a call is matched on its
**LAST COMPONENT** too.

**THE FIRST ARGUMENT MAY BE A COMPOSITION.** `oracles/usb-arith-rows.bend` spells a row name as
`u1(String.concat(["usb_split_empty", "_full"]), ...)`, so both pieces of the name are inside the
first argument and both are checked.

**THE CARRIED CHECK IS UNCHANGED**: `f'"{t}"' in port`, and the ONE DECLARED NORMALISATION
`RENAME = re.compile(r"([A-Za-z0-9_]+)=")` with `RENAME.sub(r"\1 ", tag)`. MEASURED: all 157 of
`pre`'s renamed row tags are load-bearing -- **none** of the originals is verbatim in the port,
and **all** 157 renamed forms are.

## BEFORE / AFTER, PER FRAGMENT

`quoted=` is the OLD denominator (every quoted string). `rowtags=` is the NEW denominator (the
verdict is over these). `old_lost=` is the OLD rule's lost count, kept so the delta is on the face
of the output.

| fragment | quoted | rowtags | carried | carried_renamed | **lost** | not_a_rowtag | old_lost |
|---|---|---|---|---|---|---|---|
| `oracles/lift-rows.bend` | 126 | 126 | 126 | 0 | **0** | 0 | 0 |
| `oracles/nv_ip_rows_c.bend` | 324 | 297 | 297 | 0 | **0** | 27 | 0 |
| `oracles/nv_ip_rows_d.bend` | 178 | 166 | 166 | 0 | **0** | 12 | 0 |
| `oracles/nv_ip_rows_e.bend` | 44 | 42 | 42 | 0 | **0** | 2 | 0 |
| `oracles/post-oracle-bend.bend` | 2,009 | 445 | 445 | 0 | **0** | 1,564 | 236 |
| `oracles/pre-oracle-bend.bend` | 2,009 | 445 | 288 | 157 | **0** | 1,564 | 236 |
| `oracles/usb-arith-rows.bend` | 590 | 564 | 564 | 0 | **0** | 26 | 0 |
| **FRAGMENTS** | **5,280** | **2,085** | **1,928** | **157** | **0** | **3,195** | **472** |

**THE DENOMINATOR BOTH WAYS IS ON THE FACE OF THE OUTPUT.** The gate's own `OLD-RULE` line reads:

```
OLD-RULE  ... old_carried=4651 old_carried_renamed=157 old_lost=472 over the same fragments, and
          472 of those are strings that are NOT row tags (0 are row tags)
```

**472 of the OLD rule's 472 lost strings are NOT row tags, and the gate MEASURES that, it does not
assert it.**

### THE FIVE CONTROL FRAGMENTS

`lift-rows`, `nv_ip_rows_c/d/e` and `usb-arith-rows` are the CONTROL: their `lost` was 0 under the
old rule and is **0 under the new rule**, and every row tag is carried. Their `quoted` counts are
unchanged and printed, so the reader sees that the rule did not BREAK them -- and that their
`carried` count is now over ROW TAGS rather than over every quoted string, because the strings it
no longer counts were never claims.

### WHAT EACH KIND OF NOT-COUNTED STRING IS, AND WHY IT IS NOT A ROW TAG

| kind | example | why it is not a row tag |
|---|---|---|
| **VALUE** -- a later argument of a row-maker call | `"void"`, `"i8"`, `"0x7FF0000000000000"`, `"%v0"`, `"10"` | the row tag is the FIRST argument; a later argument is the value the row is ABOUT |
| **ASSEMBLY** -- PTX/LLVM text in a later argument | `"  %v0 = load float, float* %v1"`, `"define void @mykernel(...) #0"` | the oracle's payload, not its claim |
| **LABEL** | `"v0_entry:"`, `"loop_body_0:"`, `"#0"` | a branch target, not a row name |
| **PTX DIRECTIVE** | `"alwaysinline"`, `"nounwind"`, `"attributes"` | an attribute of the oracle's assembly |
| **DTYPE LIST** | `"fp8e4m3,fp8e5m2,fp8e4m3fnuz,fp8e5m2fnuz"` | the argument of `r_f8o()`, which has NO row-name parameter -- MEASURED, `r_f8o` is **not** a row-maker |

## THE PLANT, AND ITS CONTROL

```
CONTROL     the copy, byte-identical to the live tree  rc=0  ::  GREEN
PLANT       one row tag's TEXT changed, in a COPY  rc=1  ::  RED  -- AND IT NAMED THE PLANTED TAG:
            add_int32_3_4-PLANTED-NOT-IN-THE-PORT
DENOM      the row-tag denominator, control=2085 planted=2085  ::  UNCHANGED
RESTORE     the same copy, the row tag put back  rc=0  ::  GREEN
PORT-PLANT  the PORT's own row tag's TEXT changed, the FRAGMENT untouched  rc=1  ::  RED  -- AND IT
            NAMED THE ROW THE PORT LOST: add_int32_3_4
PORT-RESTORE the same copy, the port's row tag put back  rc=0  ::  GREEN

=== plant: PASS: 0 problem(s) ===
```

**THE PLANT IS A TEXT EDIT, AND IT CANNOT BE A PLANT THAT CANNOT FAIL:** the row tag's TEXT
changes, so the gate still COUNTS it (the denominator is unchanged) and then finds that the port
does not carry it.

**THE DENOMINATOR IS PRINTED BESIDE THE PLANT** because a green run that is green only because
the gate counts FEWER rows proves nothing. The row-tag count is **2085 before and 2085 after**;
only `carried` moves.

**THE PLANT RUNS IN BOTH DIRECTIONS.** The `PORT-PLANT` arm changes the PORT's own row tag and
leaves the fragment untouched -- that is the direction the defect this gate exists to find runs
in, and a gate that only notices a fragment gaining a tag is measuring the wrong direction.

**EVERY EDIT IS A TEXT EDIT ON A COPY.** The copy holds the port, the oracles and this gate; the
port is COPIED and not symlinked, because a symlinked port would make the plant measure the live
tree's port.

## THE GATE'S VERDICT

**`rc=0`** -- all **2,085** row tags of the **7** fragments under `oracles/` are carried by a
`.bend` under `tinybendygrad/`.

**NO ROW IS LOST, SO THERE IS NO PORT DEFECT TO REPORT.** The 472 were a GATE defect and the gate
is what changed.

## WHAT ELSE THE GATE PRINTS, AND WHY

* **`ROW-MAKERS 285 distinct, 285 last-components :: DISCOVERED from tinybendygrad by
  `def NAME(... nm: String ...)`, not typed:`** followed by every name with its file and line.
  The rule's population is VISIBLE, not asserted.
* **`LOCAL-MAKERS 1 row-maker SHAPE(S) DEFINED BY A FRAGMENT, which the port does not define`:
  `report` at `oracles/fold-mvt-e2e.bend:94`.** The rule's boundary is printed rather than
  assumed: that file's row tags are therefore NOT counted by this gate.
* **`DIALECT String=FOUND IO=FOUND Nil=FOUND`**, read out of `references/bend/bend2/base.bend`.
* **`POPULATION oracles/*.bend handed=17 :: os.walk + endswith('.bend')`** -- the population is
  DISCOVERED, never the seven names.

## A PERFORMANCE NOTE, BECAUSE A GATE NOBODY WAITS FOR IS A GATE NOBODY RUNS

The carried check is a substring test over a 12 MB string, and MEASURED at 3.5 ms per miss, so
7,365 of them cost **21 s**. The gate now builds **THE TEXT BETWEEN EVERY PAIR OF CONSECUTIVE
QUOTES IN THE PORT** once, and a tag that holds no `"` is carried exactly when it is one of those
chunks -- there is no third quote to skip over, because the tag has none. MEASURED against the
substring test on every string in every fragment: **0 disagreements**. A tag that DOES contain a
quote is not covered by that argument, so it is not covered by the set either: `carried()` falls
back to the substring test for those.

**21 s -> 0.81 s**, with the numbers unchanged (`old_carried=4651 old_carried_renamed=157
old_lost=472`, `rowtags=2085 carried=1928 lost=0`).

## THE FILES

* `gates/dialect-fixture-gate.py` -- the gate.
* `.agents/slop/dialectgate/census.out` -- the census, with the row-maker set and every count.
* `.agents/slop/dialectgate/census.err` -- the verdict line.
* `.agents/slop/dialectgate/plant.out` -- the plant and its control.
