# STAGE 3 — the fix, and its MULTISET proof

Fixer: `.agents/slop/dup/dup-fix-usb.py` (count-asserted, `--check` writes nothing).
Gate/proof: `.agents/slop/dup/dup-gate.py` (`--compare`, and `--selftest` for Stage 5).

## 1. WHAT WAS FIXED, AND WHY IT IS **ORACLE-ONLY**

`.agents/slop/usb-oracle-trace.py`, **3 lines deleted**:

```
250d249
< b("usb_enum_refused_5_is_checked", bool(_ck_hit.get("libusb_get_device_descriptor", False)))
252d250
< b("usb_enum_refused_6_raw_no_fire", bool(_ck_hit.get("libusb_free_device_list", False)))
268d265
< sys.stdout.write("\n".join(OUT) + "\n")
```

**The port side needed nothing, and that is the point rather than a convenience.**
`runtime/support/usb.bend`'s PORT lane prints **940 rows over 940 distinct keys with 0
duplicates**, before and after.  So there is no row to rename, no name that any other lane's table
could cite, and **not one byte of any other lane moves**.  A duplicated EMISSION is not a
duplicated NAME, and that is what makes this class fixable at all on most lanes.

## 2. THE CITING-FILE CENSUS — every file that names a row this edit touches

Run by `dup-fix-usb.py --check`, over the whole tree, before the write.

| name | citing files (repo-relative, count) |
|---|---|
| `usb_enum_refused_5_is_checked` | `.agents/slop/usb-oracle-trace.py` ×2 · **`tinybendygrad/runtime/support/usb.bend` ×1** · `runs/gr-init/base/…/usb.bend` ×1 · `runs/margsym/snap/…/usb.bend` ×1 · `.agents/slop/render-wt/…` ×1 · `.agents/slop/xd1/wt/…` ×1 · `.agents/slop/proof-close/mut{1,2}/…` ×1 each · `.agents/slop/dd-cone-wt/{ctl-comment,revert-add,revert-both,revert-push}/…` ×1 each · `.agents/slop/ddcheck/tree/…` ×1 · plus 4 census caches and `.agents/slop/rebase/{baseline,stability-2026-10-03}.json` ×3 each |
| `usb_enum_refused_6_raw_no_fire` | the same set, with `usb.bend` ×4 and `usb-secure.bend.txt` ×3, and `.agents/slop/notes/bend2-constraints.md` ×1 |
| `usb_ctx_order_debug6` | the same set, `usb.bend` ×1, plus `.agents/slop/eq/eq-nameshape-report.md` ×1 |

**Why that list does not block the fix.** Every one of those citations is a row NAME, and no name
changed — `dup-gate.py --compare` prints `RENAME 0 pair(s)` and `939 -> 939 distinct names`.  The
census is printed anyway because a rename with an unmeasured citation list is how a fix silently
un-gates a lane, and the two cases are indistinguishable from the outside.

**The one citation that needed checking rather than listing** is
`.agents/slop/rebase/baseline.json`, because `rebase-gate.py`'s GUARD 1 is an ABSOLUTE row count.
It stores 3 occurrences of each name, and `rows()`'s key set is **939 before and 939 after**, so
GUARD 1 is satisfied by the fix rather than tripped by it.  Measured, not assumed: the gate line
below reads `shared names: 939 of 940 port / 939 oracle`.

## 3. THE MULTISET PROOF

```
$ .venv/bin/python .agents/slop/dup/dup-gate.py --compare \
      .agents/slop/dup/usb-oracle-BEFORE.txt \
      .agents/slop/dup/lanes/tinybendygrad_runtime_support_usb.bend.oracle0.txt
ROWS       1014 -> 939 lines; 1014 -> 939 read; 939 -> 939 distinct names -- EQUAL distinct counts is
           the collision check: a rename created no name
VALUES     same multiset: False   distinct 365 -> 365   only in BEFORE []   only in AFTER []
VALUE SET  identical: True   instances 1014 -> 939 (a duplicate fix removes INSTANCES, so the
           multiset may differ while the set may not)
DUPLICATES 71 -> 0 name(s) printed more than once, COUNTED FROM THE LINES and not from `rows()`'s
           dict (which has already overwritten them): none
LOST       75 -> 0 measurements unreachable by any name
RENAME     0 pair(s); 939 name(s) on the BEFORE side have no partner
BYTES      sha256(nb) 9a2134079411 -> b3b32df7c91a   CHANGED
AUDIT OK -- no name is printed more than once
```

Read as five separate claims, because they are five:

1. **939 → 939 distinct names.** A fix that invented a name, or dropped one, moves this.
2. **`VALUE SET identical: True`, `only in BEFORE []`, `only in AFTER []`.** No answer changed.
   `same multiset: False` is the EXPECTED answer here — the fix removes surplus *instances* — which
   is why the set question is asked separately; `dup-gate.py` prints that line precisely so the
   `False` cannot be read as a broken value set.
3. **71 → 0 duplicates, 75 → 0 lost.** The headline, as counts from the LINES.
4. **`RENAME 0 pair(s)`.** Nothing was renamed, so the citing-file list above is a report and not a
   prerequisite.
5. **`BYTES CHANGED`.** Required: a fix that did not change the bytes changed nothing.

## 4. THE BYTE DIFF OF THE ORACLE'S OWN OUTPUT — 75 lines removed, 0 added

```
$ diff .agents/slop/dup/usb-oracle-BEFORE.txt \
       .agents/slop/dup/lanes/tinybendygrad_runtime_support_usb.bend.oracle0.txt
744d743
< usb_enum_refused_5_is_checked=True
746,819d744
< usb_enum_refused_6_raw_no_fire=False
< usb_enum_refused_beyond_7=False
...
75 lines deleted, 0 added
```

**Only `deletions`.** Not one line was rewritten, so not one answer moved — which is the property
this fix had to have and the reason a byte-level `>` count of 0 is the load-bearing half of the
diff, not a detail.

## 5. THE GATE ON THE LIVE PAIR — and the standing hazard, said

```
GUARD 0 -- the duplicate census, per lane, before any value is compared
  …usb.bend.port.txt:   lines=940 accepted=940 keys=940 DUPLICATE NAMES=0 over 0 rows  lost=0  no-boundary=0 refused=0  sha256(nb)=66377307c15d
  …usb.bend.oracle0.txt:lines=939 accepted=939 keys=939 DUPLICATE NAMES=0 over 0 rows  lost=0  no-boundary=0 refused=0  sha256(nb)=b3b32df7c91d
  lanes print the SAME BYTES: False   <<< the two sides DIFFER, so the value comparison is a REAL measurement
  shared names: 939 of 940 port / 939 oracle   disagree=[]
  VERDICT: AGREE
```

**`disagree=[]` is UNAFFECTED BY THIS FIX BY CONSTRUCTION, and that is stated before the result.**
The dict the comparison runs through already collapsed the duplicates, so a before/after run prints
`disagree=[]` on both sides.  The evidence is §3 and §4.  **This lane is NOT one where `disagree`
is a tautological zero** — the two sides' bytes differ (66377307 against b3b32df7) — so here the
value comparison is a real measurement as well, and it still says `[]`.

**THE PORT LANE'S BYTES DID NOT MOVE:** `sha256(nb) = 66377307c15d` before and after.  That is the
claim that no other lane was disturbed, and it is a digest rather than an opinion.

## 5a. CONFIRMED BY THE TREE'S OWN GATE, which also shows the class is invisible to it

```
$ .venv/bin/python .agents/slop/rebase-gate.py --port tinybendygrad/runtime/support/usb.bend
UNCHANGED    tinybendygrad/runtime/support/usb.bend
    compiled 2 .bend file(s) in the import closure; working copy 0536a1c71f9c
    0 of 2 closure file(s) changed while this lane ran -- the substrate held still for the whole of it
TALLY UNCHANGED=1        rc 0
```

**The tree's own gate says `UNCHANGED` on the lane that had 75 unaddressable measurements, and it
is right**: the dict it compares through had already collapsed them, so nothing it measures moved.
That is GUARD 1 satisfied rather than tripped, from an instrument that had no part in this fix.

And the same instrument, on two lanes that STILL carry duplicates:

```
$ rebase-gate.py --port tinybendygrad/viz/serve.bend            -> UNCHANGED   rc 0
$ rebase-gate.py --port tinybendygrad/runtime/support/hcq2.bend -> UNCHANGED   rc 0
```

**`UNCHANGED`, with a duplicate name on the oracle side of each.**  So the class is not merely
under-reported — the tree's gate is green on it, which is the whole reason a duplicate name needs
its own guard and a census.  (`tc_ptx` answered `RE-PORTED [STARVED]` on the same sweep, which is
concurrent-load and says nothing about rows; it is recorded rather than quoted as a result.)

## 6. WHAT THE FIX SCRIPT CAUGHT ON ITS OWN FIRST RUN, because an assertion that never fires is not
a control

`dup-fix-usb.py --apply` asserted the post-fix row count and **failed on the first attempt**:
`expected 126 trace rows, got 124`.  The prediction was wrong and the reason is arithmetic I had
not carried: removing the two duplicated emissions inside the body takes `126` emissions to `124`.
The assertion fired **before** the cached lane text was overwritten, so the failed run left the
BEFORE text in place and the census still read 75.  The file was restored from the script's own
`.dupbak`, the constant corrected to the measured 124, and the apply re-run from clean.  Recorded
because the same shape — a checked-in expectation that is right about the *intent* and wrong about
the *count* — is exactly what `agent-core.md`'s table of hand-typed `py=` values is made of.

## 7. FOUND AND **NOT** FIXED, with `file:line`

`.bend` files are not this unit's to edit, and two of the four remaining families need a `.bend` edit
on BOTH sides to be worth anything.

| what | where | lost |
|---|---|---|
| `ops_nv` PORT: 11 names, two loops with overlapping fixture lists and a re-print at the foot of `main` | `tinybendygrad/runtime/ops_nv.bend` — lane lines 37/609, 38/610, 109/111, 344/345, 432/460, 433/461, 434/462, 435/463, 436/464, 437/454, 444/455, 447/465 | 11 |
| `ops_nv` ORACLE: 27 names over 7 families, two emission sites each; the file says at `nv-oracle.py:338-339` that there is "ONE definition of each" and there are two. **Includes a NEGATIVE CASE that no name can address** — `nv_reloc_bad_refused="False"` at `:1159` is overwritten by `"True"` at `:1161` | `.agents/slop/nv-oracle.py:380/981, 428/439, 701/1154, 385-387/986-990, 692/1222, 719-721/1153-1162, 878/886, 756-760` | 27 |
| `llvmir`: `lt 1 ptr f32` printed twice, **symmetric** | `tinybendygrad/renderer/llvmir.bend` lane lines 26 and 29, and the row-builder that emits them | 1 + 1 |
| `tc_ptx`: `fmt 'ret;'` printed twice, **symmetric** | `tinybendygrad/renderer/tc_ptx.bend` lane lines 331 and 334 | 1 + 1 |
| `fold`: `lf_sub_int32_-3_4 lo` printed twice, **symmetric** | `tinybendygrad/uop/fold.bend` lane lines 84 and 87 — do-not-touch file | 1 + 1 |
| `viz`: `dev_sort.GPU Memory` twice with **different values** and a space before the second `=`, **symmetric** | `tinybendygrad/viz/serve.bend` lane lines 117 and 129, and `.agents/slop/vz/viz_oracle.py` | 1 + 1 |
| `hcq2`: 2 adjacent duplicate emissions, names the port does NOT print, so oracle-only and safe | `.agents/slop/hcq2-oracle.py`, lane lines 152-155 | 2 |

`hcq2` is the one remaining fix that is oracle-only, low-risk and loses no shared name.  It is left
for a unit that owns `runtime/support/hcq2.bend`, because a 2-measurement fix that ships alone
buys nothing and the same script shape as `dup-fix-usb.py` is one `file:line` away from being the
wrong edit.