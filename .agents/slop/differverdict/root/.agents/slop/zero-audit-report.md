# ZERO AUDIT — every `0 rows` in this project, classified

Written 2026-10-04. Nothing here is a plan; every number is a measurement and
every measurement names the file it came from.

---

## 1. THE CLASSIFIER — `.agents/slop/zero-classify.py`

Five verdicts, and **there is no sixth**. A zero that cannot be placed in one of
them is an error, never a pass.

| verdict | what it means | what it costs to earn it |
|---|---|---|
| `UNREACHABLE+proof` | the site genuinely cannot be called | a **measurement**: the rename compiled *and* the gate output stayed byte-identical (`dd-mut-proof.py`), or the arm was deleted and stayed byte-identical (`dd-mut-tether.py`) |
| `PORT-DEFECT` | the site **is** called and a row asserts a **wrong** value | a disagreeing row that **carries CPython's answer at that site** |
| `PATCH-NOT-APPLY` | the edit never landed | nothing — the harness says so (RULE D) |
| `INVISIBLE-to-reader` | the reader cannot see the node | CPython's answer at the site is in **no** baseline row |
| `NO-MUTATION-WRITTEN` | nothing was aimed at the site | nothing — this is the **denominator** |

Two things are also counted, because reporting them as coverage is the same error:
`MOVED` (not a zero) and `NOT-A-PROGRAM` (RULE B — a non-program says nothing,
**not even zero**).

### THE MECHANICAL TEST, and the two questions it asks

Q1 and Q2, **in this order**, both string questions over data already on disk:

```
Q1  WRONG + JOINED   does a DISAGREEING baseline row carry CPython's answer
                     AT THIS SITE?                          -> PORT-DEFECT
Q2  VISIBLE          does CPython's answer at this site appear in ANY row?
                     no, and Q1 silent                     -> INVISIBLE-to-reader
```

**WRONG before VISIBLE.** A row that *lies* is a defect even when it is also the
only witness; a row that is *silent* is only a coverage gap. Asking "is it zero?"
never decides this, and comparing against zero never decides it — a wrong value
is not a zero, and only CPython can say so.

Q1 is a **per-site join**, not a family vote, and that was a bug I wrote and then
found. The `l2i` family is deliberately coarse (every `lg*` row is one), so a
family vote let all 51 disagreeing `l2i` rows act as an alibi for every `l2i_*`
site — it called **M06 a defect when M06 is a proven THEOREM**. The join key is
the site's own declared CPython answer; a row can only witness a defect *at* a
site if CPython's answer for that site is inside it.

### THE DISCRIMINATION IS TESTED, NOT PROSE — `.agents/slop/zero-selftest.py`

It replays the two cases this project has already paid for, on the **real
snapshots**:

| case | input | verdict | why it is the right answer |
|---|---|---|---|
| **2** | `l2i_shl.hi` against snapshot `73b0e1e7` | **`PORT-DEFECT`** | `lg9p` reads `BITCAST(WHERE)` where CPython has `BITCAST(OR)` — a row that **lies** |
| **2b** | `l2i_define` | **`UNREACHABLE+proof`** | rename compiled, output byte-identical |
| **4** | an answer in no row | **`INVISIBLE-to-reader`** | nothing carries it — nothing **lies** |
| — | an unknown MEASURED verdict | **REFUSED, exit 1** | "unrecognised" must not become a sixth verdict that reads like a pass |

```
$ python3 .agents/slop/zero-selftest.py
  ok   CASE 2  l2i_shl.hi on the DEFECTIVE snapshot               PORT-DEFECT
  ok   CASE 2b l2i_define, proven by rename                       UNREACHABLE+proof
  ok   CASE 4  an answer that is in NO row                        INVISIBLE-to-reader
  declared: UNREACHABLE+proof | PORT-DEFECT | PATCH-NOT-APPLY | INVISIBLE-to-reader | NO-MUTATION-WRITTEN
  ok   an unknown MEASUREMENT is REFUSED (exit 1)
ALL CHECKS PASS
```

**The same site, the same rows, different snapshot, different verdict.** The only
thing that changed between rows 1 and 3 is the snapshot's own bytes. If the test
passed for both, the classifier would be reading a label.

### Two bugs the classifier had, which are worth recording

- **`inside()` used `site.startswith(fam + ".")`.** Bend namespaces sub-defs with
  an **underscore** (`l2i_shl.hi` is under `l2i_shl` is under `l2i`) — there is no
  `l2i.` in any name. Every `l2i_*` site classified as belonging to **no family**,
  which is how M09 first came back `UNDECLARED` instead of `PORT-DEFECT`. A
  classifier that cannot see a family is worse than one with no opinion.
- **`moved_all` was `set(m for _, _, _, m in entries if _ == "MOVED" ...)`** — `_`
  rebound by the generator, so it read the *loop variable*, not the verdict.
  "172 rows covered" became "0 rows covered". Denominator arithmetic that is wrong
  in the direction of *under*-counting is the dangerous direction.

---

## 2. THE AUDIT — `.agents/slop/zero-audit.py`

Every mutation table in `.agents/slop`, re-parsed. **Not re-run**: several of these
harnesses mutate the LIVE tree, which is forbidden. The `MEASURED` column is each
table's own.

| table | mutations | moved | **zero** | not-a-program | has a reachability proof beside its zeros? |
|---|---|---|---|---|---|
| `dd-mutations.txt.tsv` | **41** | 36 | **5** | 0 | **yes** — all 5 re-proved on this snapshot |
| `c-mutations.txt` | 26 | 25 | 1 | 0 | no |
| `ga-mutate.txt` | 41 | 40 | 1 | 0 | no |
| `ag-mutations.txt` | 44 | 42 | 2 | 0 | no |
| `dsp2_mutations.txt` | 22 | 22 | 0 | 0 | n/a |
| `dsp_mutations.txt` | 67 | 65 | 2 | 0 | no |
| `codegen3-mutations.txt` | 6 | 0 | 6 | 0 | 2 self-described THEOREMs (alpha-renames) |
| `cs_mutation_table.txt` | 27 | 26 | 1 | 0 | no |
| `ext_mutation_table.txt` | 40 | 39 | 1 | 0 | no |
| `nv_ip_mutations.txt` | 33 | 33 | 0 | 0 | n/a |
| `rf-arg-mutations.txt` | 10 | 5 | 5 | 0 | no |
| `rf2-mutations.txt` | 38 | 34 | 4 | 0 | no |
| `tc-mutations.txt` | 32 | 32 | 0 | 0 | n/a |
| `usb-mutations.md` | 45 | 44 | 1 | 0 | yes — M6 carries an inline THEOREM argument |
| `ops-python-mutations.txt` | 20 | 19 | 1 | 0 | no — **and the 1 is a RULE D violation** |
| `mm-mutations.txt` | — | — | — | — | **NO FILE** |
| `ops-mutations.txt` | — | — | — | — | **NO FILE** |
| `dk-mutations.txt` | — | — | — | — | **NO FILE** |
| **TOTAL** | **492** | **462** | **30** | 0 | |

(492 − 30 = 462 moved; `zero-audit.py` prints the two columns separately because a
zero and a non-a-program are different facts and `codegen3`'s six "zeros" are
alpha-renames that legitimately move nothing.)

### THE FINDING THAT MATTERS MOST

**492 mutations across 15 tables carry 30 zeros, of which 25 are unclassified** —
their labels are the raw harness output copied through: `SAME` (5), `ZERO` (1), and
`(unstated)` (24). Of the 5 `SAME`, all 5 are dd's and all 5 are re-proved THEOREMs
— so **not one zero in the fourteen non-dd tables has any classification at all.**

And those 14 tables **do not distinguish PORT-DEFECT from INVISIBLE-to-reader**;
only `dd` records a proof beside its zeros. So every one of those 25 is a
`0 rows` that could be a defect, a fixture request, a theorem, or nothing. That is
the same shape as the six findings the brief lists as having cost real money — an
oracle covering 109 of 172, 82 cache files holding `{}`, 18 disagreements
suppressed inside a 65-name `SKIP`. **A disagreement count is not a coverage
statement.**

### THE AUDITOR MADE THE VERY ERROR IT WAS WRITTEN TO END

The first run of `zero-audit.py` reported dd's **8** zeros. Five are real; the
other three were `C00`/`C01`/`C02` — the **RULE C controls**, whose `0 rows` is
their *required* outcome and the guard on every other verdict in the table. The
file now strips `C*` ids before counting, with a comment saying why.

It is worth recording rather than quietly fixing: an auditor that counts its own
smoke detector as a blind spot is not a subtle error, and it was one line. **A
denominator is only as good as the thing it excludes.**

### RULE D, SCANNED IN THE SOURCES — one live violation

`zero-audit.py` greps the *branch that produces the number*, because a report file
cannot tell you which branch produced its own figure.

```
RULE D VIOLATIONS -- a dead patch printed as a zero:
  ops-python-mutate.py    f'| {mid} | (pattern not found) | 0 | {what} |'
compliant refusals found in: c-mutate.py cl_split_mutate.py nv-mutate.py
                             usb-mutate.py wgsl-mutate.py
```

`ops-python-mutate.py:107` is `print(f'| {mid} | (pattern not found) | 0 | {what} |')`
and the committed record carries it:

```
ops-python-mutations.txt:7:  | M4 | (pattern not found) | 0 | get_amd's DEFAULT is
                             amd_rdna3, so a typo'd gfx arch is a FULL rdna3 set |
```

**That is a dead patch published as `0 rows`, in a committed artifact.** It should
read `PATCH-NOT-APPLY`. It is the exact failure RULE D exists to prevent and it is
still in the tree. I have reported it rather than fixed it, because
`ops-python-mutate.py` is not in my file list — but the fix is one line.

---

## 3. THE MISSING ENTRIES — `l2i_dt` and `f2f_dt` had **no mutation at all**

**11 of the dd table's 23 unmoved rows** were unmoved because nothing was aimed at
them. Both sites are **live** — `dd-mut-proof.py` **refuses** to rename either, so
a zero here would have been a real zero about a live site.

The previous report **claimed** "a one-line swap of `l2i_dt`'s two values would
move `l2idt0 l2idt1`". **Verified, not inherited — and the claim was wrong by an
order of magnitude.**

| id | edit | inherited claim | **measured** |
|---|---|---|---|
| **M37** | `l2i_dt.wide`: swap the SIGNED and UNSIGNED answers | "2 rows" | **MOVED 23 rows** |
| **M38** | `l2i_dt`: the 64-bit test answers the 32-bit half | — | **MOVED 47 rows** |
| **M39** | `f2f_dt.w`: swap the 8-bit and 16-bit answers | — | **MOVED 6 rows** |
| **M40** | `f2f_dt.w`: swap the 32-bit and 64-bit answers | — | **MOVED 2 rows** |
| **M41** | `f2f_dt.of`: the float test never refuses | — | **MOVED 1 row** |

M37's 23 rows: `l2idt0 l2idt1 lg2 lg2n lg2sig lg3 lg3n lg3sig lg6 lg6n lg6sig
lg7n lgo lgosig lgv lgvn lgvsig lgw lgwn lgwsig lgx lgxn lgxsig`

**Why the inherited claim was wrong, and it is worth more than the fix:**
`l2i_dt` is not only a printed table. It is on **every `l2i` fixture's path** —
`l2i_cast0`/`l2i_cast1` call it to build the cast target. The previous report said
so in prose ("both are live, `dd_dtb.to` is on every `l2i` fixture's path") and
still predicted 2 rows. A claim about a mutation's reach should never be
inherited; it costs 25 s to measure and this one was wrong by 11x.

M38's 47 rows is the larger finding: the `bits == 64` test is what decides
`l2i_dt` has an answer at all, and getting it wrong **breaks the cast target for
half the fixtures**. One character (`64` → `32`).

### Where that leaves the dd table's denominators

| | before (36 mutations) | **after (41)** |
|---|---|---|
| baseline rows | 182 | 182 |
| baseline rows a mutation moved | 159 | **172** |
| unmoved rows at a site that **was** aimed | 15 | **2** (`lgnn lgon`) |
| unmoved rows whose family has **no** aimed mutation | 8 | 8 (`c0..c7`, `f2f_clamp_max`) |
| `l2idt*` / `f2fdt*` unmoved | **11** | **0** |

The 15 included `lg7n` and `lgv`, which M37/M38 now move. The remaining 8 are
`f2f_clamp_max`'s value, reached by nothing in this gate — subject of
`dd-divE-probe.py`, not of this table. `lgnn`/`lgon` are one-node counts that no
mutation of this table changes.

A note on counting, because it is easy to get wrong in the flattering direction:
the 41 mutations move **174 distinct row names**, but only **172 of the 182**
baseline rows. The other two, `lguk` and `lgusig`, are rows a mutation **created**
— they are in no baseline. "Rows moved" and "baseline rows covered" are different
numbers and only the second is a coverage statement.

---

## 4. PIN DISCIPLINE — which revision each verdict is valid for

**A table that silently describes a file that is no longer live is worse than one
that admits its age.**

| artifact | valid for | live now? |
|---|---|---|
| `dd-mutations.frozen.bend` / `dd-mutations.txt` / `dd-mutations.txt.tsv` | target **`e4618a7127ce`**, tree **`e17d3f7dd48c`** | **NO.** live `dtype.bend` is **`cdd85227d359`** |
| `dd-gate-base-182.txt` | target `e4618a71` + tree `e17d3f7dd48c` | reproduces **byte-identically** (`sha1 78c79061a587…`, 182 rows, 184 lines) — re-verified today |
| `dd-oracle.txt` | CPython's tree as of 2026-10-03 22:41 | re-run today → `sha1 8f80df08413a…`, **byte-identical** |
| `dd-mutations-classified.txt` | the **old** 172-row table, snapshot `73b0e1e7` | **superseded.** Its `M09 SAME / REQUEST` is the misdiagnosis this unit exists to correct |
| `dd-mutations-proofs.tsv` | snapshot `73b0e1e7` | **all five re-proved on `e4618a71` today** → `.agents/slop/dd-zero-verdicts.tsv` |
| `zero-selftest.py` CASE 2 | snapshot **`73b0e1e7`** deliberately | live by design — it is the DEFECTIVE snapshot |
| every other table in §2 | **UNSTATED** | **this is the finding.** No other table names a revision |

`dd-mutate.py` prints the divergence on every run:

```
#         live dtype.bend is now cdd85227d359 -- DIFFERENT.  This table is
#         against the snapshot, not against what is on disk.
```

The live file has moved **five** times under this work
(`d9189ae5 → c4380cfc → 62a650a5 → c4380cfc → e4618a71 → cdd85227`) and its owner
fixed the `promote`/`remint` defect (`dd_wk` → `dd_wf`) meanwhile, which is worth
noting: **`lg5k`/`lg5n`/`lg5sig` are three of the ten rows that disagree with
CPython on the pinned snapshot, and the live file's `dd_wf` is the fix.** A 0 on
the pinned snapshot is a statement about the snapshot — this is now measured, not
asserted.

---

## 5. JUDGEMENT ON THE WARN-vs-REFUSE DEVIATION in `dd-mut-base.sh`

**I ACCEPT the deviation, with one amendment.**

The claim is that validity rests on two asserted things — the frozen digest
(`RULE I`, asserted in `dd-mutate.py:build_mirror`) and `mirror == frozen`
(asserted at `dd-mut-base.sh:56`) — and not on `live == frozen`. **I read the
code and the claim is true.** Both assertions are real, both are on the path, and
neither can be satisfied by a stale file: `build_mirror` `sys.exit`s on a digest
mismatch, and line 56 `exit 1`s if the mirror is not the frozen bytes. A
hard `live == frozen` would assert something the table does not depend on.

The empirical case is also real and I re-measured it: **the live file moved five
times** while this table was built. A hard assertion makes the script unrunnable
exactly when it is needed — and an unrunnable baseline is how you get a table
built against *nothing*.

### The amendment, and it is measured, not stylistic

I took the claim's own defence — "what validity rests on is *asserted*" — and
checked what each assertion actually covers. Both are about the **mutation side**.
**Nothing asserts anything about the baseline file**, and the one guard on it is
`shape()`, which is three fields: first line, line count, last line.

So I corrupted a baseline the way this session's mutant baseline was corrupted —
swapped `hi42`'s operand order, which is the exact M09 defect:

```
original shape: ('l2idt0=i64->i32', 184, '')
corrupt  shape: ('l2idt0=i64->i32', 184, '')
SHAPE GUARD PASSES A CORRUPT BASELINE: True
```

`dd-mutate.py` would accept it. **The claim is true and incomplete**: the frozen
digest and `mirror == frozen` protect the file being mutated, and the file being
mutated is not the file `SAME` is measured against.

Two things make this survivable, and both should be said rather than assumed:

- **RULE C is the real guard, and it has now earned its keep twice.** It caught
  this exact defect when it happened and it is what would catch it again.
- `probe_substrate` re-runs the unmutated mirror and compares its shape to the
  baseline's, which rejects a *differently-shaped* build (the 172- and 178-row
  baselines differ in line count) but not a same-shaped corrupt one.

**What I would change**, in priority order:

1. **`shape()` must carry a digest of the row SET, not three fields.** A baseline
   is a claim about a file; three fields is not a claim, it is a sample.
2. **`dd-mut-base.sh` should write its provenance into the baseline file** as a `#`
   header — mirror digest, target digest, tree rev. The warning goes to **stderr
   only**, so a baseline produced by a warned-about run is **silently unlabelled**.
3. `dd-mutate.py` should refuse a baseline whose header digest disagrees with the
   mirror it is about to mutate.

**What would make the deviation genuinely unsafe**, now stated concretely rather
than as a worry: a baseline carried over from a run against a *different snapshot
of the same shape*, with no control able to see it. That is precisely the
M09-mutant-baseline failure, one shape-collision away.

**Verdict: ACCEPT the deviation** — `live == frozen` should stay a warning — **and
add the row-set digest**, which is what the claim was reaching for and does not
actually have.

---

## 6. WHAT I FOUND AND DID **NOT** FIX

1. **`ops-python-mutate.py:107` — RULE D violation, live, in a committed record.**
   `| M4 | (pattern not found) | 0 | ...`. Not my file. One line.
2. **10 rows disagree with CPython on the pinned snapshot `e4618a71`**: `c7 lg1n
   lg5k lg5n lg5sig lg6n lg9n lgqn lgu lgun`. Three (`lg5k/lg5n/lg5sig`) are the
   `promote`-remint defect the live file has since fixed with `dd_wf`; `lgu`/`c7`
   are the known `f2f`-not-built and `F64`-absent gaps. **`lg1n lg6n lg9n lgqn`
   are node-count rows** — off by one, four of them, and I did not chase them.
   Reported, not fixed: the dtype unit owns that file.
3. **25 unclassified zeros** in the fourteen non-dd tables. They need `--aim`,
   `--family` and `--site-answer` declarations exactly as `dd` now has, which is
   per-table work I could not do without re-running harnesses that mutate the live
   tree.
4. **`mm-mutate.py`, `ops-mutate.py`, `dk-mutate.py` have harnesses but no table
   file at all.** Their results are in run logs or were never written down. An
   absent number is not a zero, so they are reported as absent.
5. **The three harnesses that mutate the LIVE tree in place** — `ops-mutate.py`
   (`"The file is RESTORED from a byte snapshot on every exit path"`),
   `dk-mutate.py` (`"The edit is applied IN PLACE"`), and `c-mutate.py`
   (`BEND = REPO / "tinybendygrad/runtime/support/c.bend"`, no mirror at all).
   These are the harnesses I declined to re-run, and the reason is the standing
   rule: **never patch the live tree from a harness.** Six units have died to that.
6. **Row-name reading is not unified.** `zero-classify.py` reuses
   `unobservable-census.py`'s regex (`name` up to the first `=` or `:`) rather than
   building a third reader, per the instruction to coordinate. A shared
   `rowslib` is still the right answer and does not exist yet.
7. **The `l2i` family is coarse** (`^lg` → `l2i`). This can only *under*-report
   INVISIBLE-to-reader, never invent one — the conservative direction — but it means
   per-arm attribution still comes from the per-mutation MOVED row lists rather
   than from the classifier.

---

## 7. FILES

| file | what it is |
|---|---|
| `zero-classify.py` | **the classifier** — five verdicts, per-site join, denominator |
| `zero-selftest.py` | proves 2-vs-4 on the **real snapshots**; refuses a sixth verdict |
| `zero-audit.py` | audits every table in `.agents/slop`; scans RULE D in the sources |
| `dd-zero-aim.tsv` | which site each of the 41 mutations is aimed at |
| `dd-zero-family.tsv` | which site produces each baseline row |
| `dd-zero-site-answer.tsv` | CPython's answer at each site — the join key |
| `dd-zero-verdicts.tsv` | the classified dd table |
| `dd-mutate.py` | **+ M37..M41**, the two sites that had no mutation |

**Reproduce:**

```sh
python3 .agents/slop/zero-selftest.py                       # the discrimination
.agents/slop/dd-mut-base.sh /tmp/b.txt                     # the baseline
python3 .agents/slop/dd-mutate.py /tmp/b.txt /tmp/t.txt     # the table
python3 .agents/slop/zero-audit.py                          # every table
```

`dd-mut-base.sh` is `sh`-safe; use an absolute `OUT` path.