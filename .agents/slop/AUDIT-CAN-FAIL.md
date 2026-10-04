# AUDIT-CAN-FAIL — can this project's headline numbers go red?

Eight headline numbers, audited by **plant** (a change to the subject that must
move the number) and **disarm** (a change that must not, proving the number is
not tracking noise). Every premise was established by **calling CPython or running
`bend`**, never by grepping a name and never by reading a filter's own prose.
Nothing under `.agents/slop/` or `tinybendygrad/` was edited; every plant is a
copy in `$TMPDIR`.

## THE TABLE

| # | number | subject | what the instrument actually read | verdict |
|---|---|---|---|---|
| 01 | **Proofs 34/34, ALL PROOFS CHECK** | the 34 `law` decls in `LAWS.bend` about `LAWS/spec.bend` + `LAWS/alu.bend` | `bend PROOF-ALL.bend --check-only`, which prints **no count at all**; the "34" is `grep -c '^law '` | **CAN-FAIL** — 7 plants, 7 reds; 3 disarms, 3 greens |
| 02 | **34 of 77 ops** | which of tinygrad's 77 `Ops` the 16-graph corpus reaches | `graphcmp-oracle.py`: `34` is a **union over both sides**; `43 of 77` is **py-side only** | **CAN-FAIL** — 34 → 23 |
| 03 | **60/60 fields agree** | the port's schedule output, 10 fields × 6 specs | `sched-cmp.py` reads a **static `sched-port.txt`**; it never runs the port | **CAN-FAIL** for the comparison; **CANNOT-FAIL** for two header literals and for a port edit |
| 04 | **307/324 mechanically derivable** | which of 324 libclang `@dll.bind` sigs have no absent-type blocker | `len(uniq) - len(blocked)` — a **not-count of blockers**, not a derivation | **CAN-FAIL** — 307 → 306 |
| 04b | **coverage 324/324 = 100.0%** | libclang's *exported* symbols | `denom = len(uniq)` — **the same set**, no binary read | **CANNOT-FAIL** — `X/X` |
| 05 | **222 rows** on cstyle | — | `cstyle-gate.py` no longer prints 222 anywhere | **NOT-A-COUNT** — retired; current is 227/224/221 |
| 06 | **32 of 38 readers drifted** | row readers in `.agents/slop/` vs `rebase-gate.rows()` | the census, with the control **loaded by path** | **CAN-FAIL** — 32/38 → 1/3 → 0/0 |
| 07 | **E2E PASS, 64/64 u32 words** | the GPU's 64 output words vs CPython's 64 | real WebGPU walk, **bit-exact** | **CAN-FAIL** — 1 bit in 1 word of 64 → red |
| 08 | **234 counts, 0 loads** | every recorded baseline count, and whether a load was recorded | `load-census.py --guard`, `rc=1` **by design** | **234 CAN-FAIL; the "0" is CANNOT-FAIL for filename-derived counts** |

## THE DENOMINATOR

- **Numbers audited: 8** (plus the 04b coverage ratio, which is a ninth number
  hiding inside 04).
- **Numbers with a landed plant on the subject: 6 of 8** — 01, 02, 04, 06, 07,
  and 08's count.
- **Numbers that are NOT a count at all: 1** — 05, "222 rows".
- **Numbers with a CANNOT-FAIL component: 4** — 03 (two header literals + the
  snapshot-staleness channel + a dead census whose hazard is armed), 04b (`X/X`),
  06 (the denominator is an unverified classifier's opinion), 08 (the "0" half).

**So: 6 of 8 headline numbers can be made red by a change to their subject. Two
of the eight cannot, and neither of those two is a healthy instrument.**

---

# EVERY CANNOT-FAIL, with the plant I tried and why it did not move

## A. `coverage: 324/324 = 100.0%` is `X/X` — libclang

`ffi-port-cost.py:496` sets `denom = len({f.name for f in fns})` on the `--pybind`
path, and `:418` sets `uniq = sorted(set([f.name for f in fns]))`. `:421` prints
`len(uniq)/denom`. The label says *"symbols exported by the binary"*. **No binary
is read on this path**, and the guard at `:423` that says *"the header and the
binary disagree"* is unreachable.

**Plant:** delete one declaration from a copy of `libclang.py`.
**Result: `entry points 323 (was 324)`, `coverage 323/323`, still 100.0%.**
Coverage is 100% with one of libclang's 324 declarations gone. A self-comparison
reported a coverage result.

## B. `specs_attempted=6 specs_scheduled=6` are string literals — sched

`sched-cmp.py:115` embeds both in the f-string. `sched-oracle.py:267` computes
the same pair for real, so the project already knows the right spelling.

**Plant:** add a seventh spec to a copy of `sched-oracle.py`'s `SPECS`, with its
ten fields in the snapshot.
**Result: `fields_compared=70 fields_agree=70`, header still `specs_attempted=6
specs_scheduled=6`, and `denominator: 70 fields = 6 specs x 11 fields` — which is
66, not 70.** Both literals falsified at once, rc=0.

## C. A port edit cannot move `60/60` — sched

`sched-cmp.py:101` is `open(os.path.join(HERE, "sched-port.txt"))`.
`port_rows()` **spawns nothing and never touches `tinybendygrad/`.**

**Plant, in order, all on copies:**
1. *Fidelity first* — a full `$TMPDIR` tree reproduces the published snapshot sha
   `207ee494…` **exactly**, so the snapshot is genuinely fresh. A real positive.
2. `Lin.out` → `List.drop(&2, U32, out, 1n)` in a copy of
   `tinybendygrad/schedule/__init__.bend`; 60 rows still produced, content
   differs.
3. **`sched-cmp.py` run as committed: `fields_agree=60 fields_disagree=0`, rc=0.**
4. Feed the planted snapshot in by hand: **`fields_agree=24 fields_disagree=36`,
   rc=1.**

The comparator is fine. The **staleness window** is the defect: a port regression
cannot be seen unless a human remembers to regenerate `sched-port.txt`, and there
is no freshness check. This is `schedule_cache` in its purest form.

## D. The "census of uncoded ops" the sched docstring promises is dead code

`sched-cmp.py`'s docstring: *"An op with no code becomes 0, on BOTH sides, so an
op the port has not ported shows as an agreement about the digit 0 — which is why
the census of uncoded ops is printed rather than left implicit."*

`:132-136` is:
```python
uncoded = collections.Counter()
for k, v in DIG.items():
    if v == 0:
        continue
```
`uncoded` is never written and never printed; `DIG` has no zero-valued entries
(measured: `none`). Nothing in the output mentions "uncoded".

**And the hazard is ARMED.** Walking `sink.toposort()` for all six specs: 18
distinct op names, of which **four are not in `DIG`** — `CMPLT ×4, AND ×4,
CMPNE ×2, WHERE ×2`, 12 nodes. And the packer is not injective over uncoded ops:

```
pack(['SHR','SHL']) = 0     pack(['NOPE','WHAT']) = 0     pack([]) = 0
```

So a kernel whose srcs were all unported ops and a kernel with an empty src list
pack identically and would report AGREE. **Honest qualification:** I checked the
exact three slices the packed fields read (`k.src`, `k.src[0].op.name`, the first
STORE's value op) for all six specs and **no uncoded op appears in any of them**,
so no currently reported value is wrong. It is armed and dormant, and the
instrument written to report it is a loop that discards its result.

## E. `32 of 38`'s denominator is an unverified classifier's opinion

353 functions in the corpus; **38** are in the denominator; **315** are excluded
because a static classifier said they are not row readers. The exclusion is
printed — which is the good half — but there is **no assertion that a function
classified `not-single-arg` is not a reader**. A misclassified reader shrinks the
denominator, so the headline gets worse for the wrong reason and the exclusion is
invisible.

**I could not plant this** without editing a live `.agents/slop/*.py`, which the
brief forbids and five units are holding. **So: numerator CAN-FAIL and measured
(32/38 → 1/3 → 0/0); denominator unverified, and I am not claiming otherwise.**

## F. `0 of 234 carry a load` is structural for filename-derived counts

Three plants on a `$TMPDIR` corpus, all placed to land: `loadavg=4.11` at end of
file; immediately after the file's first count line; as a non-claim context line
beside the first count. **All three left `0 of 235`.**

`load-census.py:104` — `def qualified(lineno, lines)` — **needs a line number.**
The claim the guard reports for `amdev-baseline-552.txt` is
`(unidentified capture): ?=552`: the number is in the **filename**, so the claim
has no line and no context window can reach it.

**For any file whose count is encoded in its own name, `0 of N` is true by
construction, not by measuring load.** The ledger's `UNDECIDABLE` verdict is
right; the honest label for that class is *"structurally unqualifiable"*, not
*"measured as unqualified"*.

---

# NUMBERS THAT ARE NOT ABOUT THEIR STATED SUBJECT

1. **"222 rows" is not about cstyle at all — it is about a reader that no longer
   exists.** `cstyle-gate.py` prints `port rows 227 / oracle rows 224 / gated
   221 / 6 excluded`. `222` appears only at docstring lines 180, 209 and 448,
   every one of them describing the retired parity-reader `rows()` and the
   `kern CUDA  lb=1` / `lb=4` name collision that was fixed by renaming. **A
   superseded count stays quotable until something scrubs it.**

2. **"189 nodes per side" (graphcmp) is a py-side count.** `graphcmp-oracle.py:112`
   is `tot_nodes += py["nodes"]`. With the bend side emitting **zero nodes for
   all sixteen graphs**, the oracle still prints `189 nodes per side`,
   `34 distinct ops`, `NOT REACHED (43 of 77)` and
   **`ORACLE SELFCHECK: OK`, rc=0**. True today by luck (`189/189` on every
   graph); true by construction, never.

3. **"of 77" (graphcmp) admits names that are not `Ops`.** `tot_ops` is a
   `set[str]` of whatever `unchunks(ln)[1]` yields. Planting a well-formed wire
   line with op `INVENTED` gives `35`, SELFCHECK still OK. **No assertion that
   `tot_ops ⊆ Ops`.**

4. **"mechanically derivable" (libclang) is "has no blocker", and two thirds of
   it is called not-mechanical by the same run.** `max_class` returns one value
   and tests `blocked` first, so all 203 `CBYVAL`/`OPAQUE` functions are inside
   the 307. `CLASS_NOTE` labels `CBYVAL` *"needs one layout convention"* and
   `STRUCT` *"per-struct decision, not mechanical"*. **203 of 307 = 66%.** A
   defensible restatement is *104/324 mechanical outright, 203 need a per-struct
   layout decision, 17 blocked.*

5. **The 34 laws are about the SPEC IR, not the port.** `LAWS/spec.bend` is
   genuinely used — `renderer/__init__.bend:84`, `renderer/tc.bend:73`,
   `renderer/tc_ptx.bend:28`, `renderer/isa/x86.bend:188` all import it — but the
   laws do not measure `uop/**`, `schedule/**` or `renderer/**` semantics.
   `LAWS.bend`'s own header draws the line and the audit confirms it.

6. **`graphcmp-LIMITS.md:431-432` miscounts its own denominator by one.** It says
   ten ops crossed through from `lin`/`loop`/`gate` and lists them; **eleven** do,
   and the missing one is `CMPLT`. Asking CPython which graphs reach each op:
   `CMPLT ['gate','loop']`, `IF ['gate']`, `END ['gate','lin']`, `ENDIF ['gate']`,
   `BACKEDGE ['loop']`, `LOAD ['lin','loop']`, `STORE ['gate','lin','loop']`,
   `CALL ['loop']`, `LINEAR ['gate']`, `NOOP ['loop']`, `AFTER ['loop']`. **The
   plant measures exactly those eleven.**

---

# THINGS THAT ARE BETTER THAN THEY LOOK — measured, and said plainly

- **The `34/77` census is a real fact about the corpus.** 34 → 23 when three
  graphs are removed, with the eleven ops named.
- **`len(list(Ops)) = 77` is measured at run time**, twice: 77, 77. The
  `census_lines` docstring's claim that the denominator "cannot rot the way the 77
  in the limits file can" is true — and it should be, because the limits file's 77
  is right but its **list of ops is one short**.
- **`sched-port.txt` is fresh.** sha256 `207ee494…`, exactly the value published in
  `sched-stage2.md`.
- **`cstyle-gate` calls CPython live** — `STALE-LITERAL 0` — and it separates the
  value lane from the name lane with a selftest that fires both ways. Contrast
  `sched-cmp`.
- **`e2e` is bit-exact and says so.** One bit in one word out of 64 → red, exactly
  one failure counted. And `mm_e2e_walk_completed` exists because an earlier
  version read a crash as a pass — the project's own instance of this defect,
  found and fixed.
- **`load-census.py --guard` is red by design** and says so in the file. A
  permanent red with a permanent cause is the right shape.
- **`reader-fork-census.py` loads its control by path** (`CANON_ROW = GATE_MOD.row`)
  rather than re-typing it, and prints an md5 of it. That is the correct answer to
  *"a row whose expected value is a def of the thing under test is not a test."*
- **`PROOF2.bend`'s `{==}` bodies are not tautologies.** Making `A.neg` the
  identity turns `neg_is_mul_by_minus_one` red. An 18-of-34 reflexive set catches a
  mis-implemented spec def; it cannot catch a wrong specification. That is the
  honest boundary.

---

# WHAT THE AUDIT ITSELF GOT WRONG, four times

Every plant below was green, and in every case the plant was at fault — not the
instrument. This is the brief's central trap and it fired on me.

1. **`pick_dim(a,b) = \a->a`** to break `max_dim_idempotent`. GREEN — because
   `pick_idem` proves `pick_dim(v, v) == v`, and the identity satisfies that at
   `(v,v)` exactly as well as the real four-case body. The plant did not change
   the law's truth value. `pick_dim -> 0n` went red.
2. **`clang_Type_getSizeOf`** as the libclang target — chosen without reading the
   tool's own BLOCKED list. It is **already blocked** for its `c_int64` return.
3. **`"(ctypes.c_int64, "` inserted after `(`** — that adds a bare parameter with
   no annotation, which `parse_pybind` reads as an untyped name.
4. **The annotation** `:int → :ctypes.c_int64` — inert, because `parse_pybind`
   reads the **`@dll.bind` decorator's ctypes tuple** and consults the annotation
   only as a fallback. Verified by calling the parser: with the annotation set to
   `c_int64` it still reports `ctypes.c_int32` for that argument.

Plus one more: **the e2e oracle plant**, green because `ORACLE` is a module global
rather than a path derived from the argument, so the `$TMPDIR` copy was ignored.

**A plant that does not move a number is evidence about the plant until proven
otherwise, and the proof is always the same: verify the instrument read what you
think it read.**

---

# THE SMALLEST FIXES, IN ORDER OF VALUE PER LINE

1. `sched-cmp.py:132` — delete the dead `uncoded` loop and **implement** the
   census, or delete the sentence from the docstring that claims it exists. Four
   uncoded ops are live in the corpus right now.
2. `graphcmp-oracle.py` — assert `tot_ops ⊆ {o.name for o in Ops}`, append
   `py["nodes"] != bd["nodes"]` to `bad`, and stop printing "per side" for a
   py-only count. **Two lines each; three blind spots.**
3. `ffi-port-cost.py:496` — take `denom` from the dylib or drop the
   `symbols exported by the binary` label. It is `X/X`.
4. `sched-cmp.py:115` — `f"specs_attempted={len(SPECS)} specs_scheduled={n}"`, the
   spelling `sched-oracle.py:267` already uses.
5. `graphcmp-LIMITS.md:431` — add `CMPLT` to the list of eleven.
6. `cstyle-gate.py` — delete the three `222` mentions, or state that they are
   historical. A retired number is still quotable.

---

# REPRODUCE

```
python3  .agents/slop/audit/proof-plants.py            # 01, 7 plants
env -u PYTHONPATH LC_ALL=C DEV=NULL .venv/bin/python .agents/slop/audit/graphcmp-census-audit.py
env -u PYTHONPATH LC_ALL=C DEV=NONE .venv/bin/python .agents/slop/audit/sched-cmp-audit.py
env -u PYTHONPATH LC_ALL=C DEV=NONE .venv/bin/python .agents/slop/audit/sched-cmp-audit2.py
env -u PYTHONPATH LC_ALL=C          .venv/bin/python .agents/slop/audit/ffi-port-cost-audit.py
.venv/bin/python .agents/slop/audit/e2e-plants.py
sh .agents/slop/e2e.sh
.venv/bin/python .agents/slop/load-census.py --guard ; echo "rc=$?"   # no pipe
```

Per-number detail: `.agents/slop/audit/01` … `08`.