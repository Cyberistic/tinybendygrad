# SPECCITE — DOES A `file:line` CITATION IN THE PORT STILL NAME WHAT IT CLAIMS?

Instrument: **`checks/citation-gate.py`** (also named not-`differ.py`, and not owned by any other
unit). Plants: `plants.py` here. Pin: `checks/citation-gate.ledger.tsv`. Subject:
**`tinybendygrad/uop/spec.bend`**, whose citation at `:412`/`:1092` named a rule upstream added at
`6f4bfde23` and removed at `ad117c928`. **NOTHING HERE IS COMMITTED.**

    .venv/bin/python checks/citation-gate.py                     # the census + the verdict
    .venv/bin/python checks/citation-gate.py tinybendygrad/uop/spec.bend
    .venv/bin/python .agents/slop/speccite/plants.py            # 4 arms, the tree never modified

---

## 1. THE CENSUS, AND IT IS A POPULATION NOT TEN INSTANCES

`tinybendygrad/**` makes **5,651** `file:line` citations into a Python tree, across **138** `.bend`
files. **331 of them are broken, by class.** Nobody had counted them: `abi4check`'s unit found **nine**
in `checks/abi4_gate.py` alone and called it a census, and `abi4check`'s own §6 table has **nine**
rows while the brief's list of that table says seven.

| class | n | what it is | remedy |
|---|---:|---|---|
| `HOLDS` | 423 | the quoted text is on the line it names | -- |
| `STALE-LINE` | **269** | the text is in that file, nearest occurrence is elsewhere | RESTORE |
| `PROSE` | 556 | the text is in no `.py`, and git says it never existed | not a citation |
| `WRONG-FILE` | 27 | the text is in another `.py`, not the one named | RESTORE |
| `NO-FILE` | 26 | the named file does not resolve | RESTORE |
| `STALE-RULE` | **5** | git: the quoted text was added and then removed | **AUTHOR** |
| `PAST-EOF` | 4 | the line number is past the end of the file | RESTORE |
| **adjudicated** | **1,310** | one `.py` citation in the block **and** a backtick span on that citation's own line | |
| **unbound** | **4,341** | counted, never judged | |

**REACH IS 23%, AND THAT IS THE FIRST FINDING.** 4,341 of 5,651 citations carry no quotable source
next to them — `TODO(p3) ops.py:3370`, `render/__init__.py:85`, `dtype.py:230` — so there is nothing
for any checker to compare against. **The class this project keeps hitting lives disproportionately in
the 77% this instrument cannot see.** Two earlier attempts at a wider rule were measured and dropped,
and the measurements are the reason:

| rule | adjudicable | verdict quality |
|---|---:|---|
| ≥3 identifier tokens of the claim co-occur within ±40 lines | 5,538 | **4,506 findings, 81% false** — `dtype`, `self`, `isinstance` occur everywhere |
| nearest backtick span in the block, any line | 913 | 122/297 quotes were **prose** (`` " is the ONLY override and it is " ``) |
| **one citation + longest span ON ITS OWN LINE** | **1,310** | every class mechanically checkable |

## 2. `spec.bend:412`/`:1092`, WITH THE `git log -S` EVIDENCE

    $ git log -S'x.dtype is x.arg.dtype' --format=%h -- tinygrad/uop/spec.py
    6f4bfde23   restrict allowed call bodies (#17925)      <- ADDED
    ad117c928   rebase B1: 17 files ...                     <- REMOVED

`6f4bfde23` wrote `lambda x: isinstance(x.arg, CallInfo) and x.dtype is x.arg.dtype`. `ad117c928`
replaced the line with `lambda x: isinstance(x.arg, CallInfo)` and **also** changed the
`CUSTOM_FUNCTION` rule above it from `isinstance(x.arg, str)` to `isinstance(x.arg, CustomFunction)`.
**It is a RULE CHANGE, not a field delete**, exactly as `opshapes/02-fix.md:143` said the brief did not
name. And the line numbers were wrong independently: `:412` said `spec.py:113` when the rule is on
**113** — one line, and `:1091` said `spec.py:112`, which is the `#` comment above it.

**WHAT IS NOW ON DISK** (`tinybendygrad/uop/spec.bend:412`): the citation names `spec.py:113`, quotes
HEAD's whole rule, and states that `arg_call`/`sh_23.body` are **STRICTER THAN THE SPEC** because they
keep the deleted conjunct. **The port's behaviour is unchanged and now says so.** The comment is not
deleted because the divergence is the most useful thing it can carry, and because retyping a number
does not restore a rule.

**AND THE INSTRUMENT FOUND A SECOND ONE ON ITS FIRST RUN, IN THE SAME FILE.** `:756` cited
`spec.py:211` for `` `UPat(Ops.CONST).or_casted()` ``:

    $ git log -S'UPat(Ops.CONST).or_casted()' --format=%h -- tinygrad/uop/spec.py
    955037870   finish casted_consts migration (#17595)      <- ADDED
    ded106b18   more bitcasted buf (#17981)                  <- REMOVED

`spec.py:211` at HEAD is `(UPat(GroupOp.Movement), lambda: False)`. The SHRINK rule is at **`spec.py:208`**
and its third src now reads `UPat.cvar().or_casted()`. `UPat.cvar()` **is** `UPat(Ops.CONST)`
(`ops.py:1505`), so this is a pure constructor rename — the port was right, `:752`/`:756` were wrong,
and both line numbers were off by three. Fixed, with the rename recorded so the next reader does not
re-open it. **That is the eleventh instance and it was NOT in the brief's list of ten.**

## 3. THE PLANT THE CHECK CANNOT SEE — AND WHY IT CANNOT SEE IT

| arm | planted | rc | what it shows |
|---|---|---:|---|
| `CONTROL` | nothing, the live bytes | 0 | RED below is the plant, not the harness |
| `PLANT-1` | the real defect, byte-for-byte from `git show HEAD:` | **1** | the gate fires: `STALE-RULE`, `added+removed by ad117c928,6f4bfde23` |
| `PLANT-2` | `` # spec.py:113 `lambda x: isinstance(x.arg, CallInfo)` -- and sh_23 below is that rule, VERBATIM `` | **0** | **the blind spot** |
| `PLANT-3` | one cited line number moved by one | 0 | `STALE-LINE`, and **git is silent** on it |

**PLANT-2 IS WRONG IN A WAY NO LANE OF THIS GATE CAN SEE.** Its quote is on the line it names, in the
file it names, verbatim — the file resolves, the line is 113, the substring is present at 113, git
reports nothing. Every question the gate can ask has an answer it likes. **And the comment is false:**
`sh_23.body` also compares a dtype, and `spec.py:113` does not.

> **THE EVIDENCE IS INVARIANT UNDER THE VERY EDIT THAT BROKE IT.** `ad117c928` deleted a CONJUNCT and
> left its SIBLING in place. `isinstance(x.arg, CallInfo)` is on `spec.py:113` at `6f4bfde23^` and at
> `HEAD`, character for character, while the rule around it changed. So the strongest possible static
> evidence — "the text you quoted is on the line you named" — cannot distinguish a true citation from
> a false one.

**A LINE-NUMBER CHECK PASSES ON PLANT-2. A CONTENT-CHECK LOOKING FOR THE QUOTED TEXT PASSES ON
PLANT-2. ONLY A CHECK THAT READS THE RULE AS A WHOLE COULD CATCH IT, AND THE RULE IS UPSTREAM, WHICH
IS NOT IN THIS REPO.** So `checks/citation-gate.py` does not claim to decide. It enumerates.

## 4. THREE METHODS, AND NONE OF THEM SHARES A REGEX WITH ANOTHER

`STALE-LINE`/`HOLDS` asks a **byte-substring** question of the file. `STALE-RULE` hands a string to
**`git log -S`** and reads commits back. The triage hint uses a **third** tokenizer. Self-consistency
is not independence, and `PLANT-1` and `PLANT-3` are the two halves: `PLANT-1` is seen only by the git
lane, `PLANT-3` only by the substring lane, and they give opposite verdicts on the same tree.

**TWO FALSE-POSITIVE MODES WERE MEASURED AND BOTH WERE FIXED IN THE INSTRUMENT, NOT EXPLAINED AWAY.**

1. **First occurrence ≠ the occurrence meant.** `Allocator` first occurs at `device.py:11` inside
   `BumpAllocator`, and `free_cache` first occurs at a *call* site. Taking the first match reported
   "the text is at line 11" for a comment citing 259. **Now the verdict names the NEAREST occurrence
   and its distance, and never says "the".** `HOLDS` 386 → 423, `STALE-LINE` 306 → 269.
2. **`git log -S` is TEXT-EXACT, so `STALE-RULE` is NECESSARY AND NOT SUFFICIENT.** Of the 5 hits,
   **4 are respellings**: `mem_type(x)` → `mem_type(x: UOp)` (the function is still there),
   `return AddrSpace.REG` restructured across 6 commits, `f_ = [smax(1, ceildiv(o*s - d, i)) ...]`
   reformatted with spaces, and `UPat(GroupOp.Movement, src=(UPat.var("s"),), name="v")` → **the same
   rule with `allow_any_len=True` inserted**, which is a real behavioural widening and not a deletion.
   **Only `axis_to_pos` is a true deletion** — removed from `tinygrad/uop/ops.py` by `ad117c928`
   itself, and cited at `tinybendygrad/uop/ops.bend:742`.

**AND THE TRIAGE HINT THAT SEPARATES THEM IS WRONG ON THE TARGET DEFECT.** "Are the quote's
identifiers still in the file?" answers *survive* for `isinstance(x.arg, CallInfo) and x.dtype is
x.arg.dtype`, because **the deleted conjunct shares every identifier with the sibling that stayed**.
So the hint is printed and is not a verdict, and the gate blocks on the **population** and names the
ambiguity rather than resolving it. `.agents/TODO.md` carries the 5 with their owners.

## 5. CAN A STATIC CHECK ANSWER "DOES THIS CITATION STILL HOLD?"

**No, and the measurement is `PLANT-2` plus the 4-of-5 respelling rate plus the 23% reach ceiling.**
Three independent reasons, each measured rather than argued:

1. **The evidence is invariant under the breaking edit** (§3). This is not a limitation of *this*
   tokenizer; it is a property of conjunctive deletion.
2. **A fragment is not a rule.** `STALE-RULE` fired 5 times and was wrong 4 times, because reformatting,
   an inserted flag and a renamed constructor all move a fragment without moving the rule. **Only
   reading the rule separates them, and the rule is upstream.** This is the `declared()` precedent
   pointed the other way: `txtgen`'s unit proved that a declaration **derived from the tables it
   describes cannot audit those tables**, and here a verdict **derived from the quoted fragment cannot
   audit the rule the fragment is a sample of.**
3. **77% of the corpus has no fragment to audit** (§1). Reach is a property of how the port is written,
   not of the checker.

**WHAT I WOULD PIN, AND IT IS NOT A SHA OF THE COMMENT.** A `file:line` citation's line number is only
defined **relative to a blob**, and nothing in this repo pins that blob — which is why
`6f4bfde23`/`ad117c928` could move it unnoticed. So:

- **the blob id of every cited Python file**, in a ledger beside the gate. Then "line 113" means
  "line 113 of *that* blob", and a rebase is a **pin diff to review**, not a silent edit.
- **the `git log -S` verdicts**, which is `checks/citation-gate.ledger.tsv`: 555 rows, ~1.5 s each to
  derive, keyed by the quote so a changed comment re-derives and an unchanged one does not.
- **the reach floor, as a number that must not fall.** 1,310 adjudicable today. A corpus that stops
  quoting its sources is a corpus where this class returns silently, and that is invisible to every
  other gate here — `spec.bend`'s own `CUSTOM_FUNCTION` rule changed under a table-size row that read
  33 both before and after (`spec.bend:1057`).

## 6. WHAT I COULD NOT SETTLE

1. **THE FOUR `RESPELLED` ARE NOT CLASSIFIED, ONLY LABELLED.** Deciding that `allow_any_len=True` is a
   *widening* rather than a *deletion* needs the rule's meaning, which is upstream. One of the four is
   very likely a real port/behaviour divergence; I have not established which.
2. **THE 269 `STALE-LINE` ARE NOT AUDITED.** The verdict is mechanically true ("the nearest occurrence
   is N lines away") but I sampled **6**, and I fixed the one false-positive mode that sampling found.
   The other 263 are unverified as *findings*; the nearest-occurrence rule makes them sound but not
   necessarily *meant*.
3. **THE 4,341 UNBOUND.** Whether they carry claims at all is a question about how the port is written.
   I did not attempt to raise reach, and I would not without a per-file decision about whether those
   comments are meant to be checkable.
4. **`spec.py:211` WAS WRONG IN TWO PLACES AND `git log -S` FOUND ONLY ONE.** `:752`'s quote is
   `` `UPat(...).or_bitcasted()` `` — an ellipsis, so it is not a substring of anything, so it is
   `PROSE`, so `git` was never asked. **An abbreviated quote is invisible to a text-exact method.**
   Both line numbers are fixed; the reach gap that hid one of them is §1.
5. **THE PLANTS RUN AGAINST A MIRROR-SHAPED PATH.** `plants/spec.bend` sits outside `tinybendygrad/`,
   so its bare basenames resolve by `tinygrad/`-uniqueness rather than by the mirror. `spec.py` is
   genuinely ambiguous (`tinygrad/uop/` vs `extra/hcqfuzz/`) and this is **why the port's directory
   mirror is load-bearing**: a citation's resolvability is a function of a file having moved.