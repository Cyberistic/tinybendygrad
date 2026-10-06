# ABIFIX — `checks/abi_gate.py` HAD TWO STALE CONSTANTS AND NO DECLARATION

Rule prefix: **`ABIFIX-`**. Instrument: `checks/abi_gate.py` (12 rows × 11 arms × 2 lanes).
Artifacts, all in this directory: `before.rows`, `after.rows`, `plants.rows`, `probe.rows`,
`green-at-135bf0204.rows`, `abi.json.recovered`, `probe/`.

Reproduce: `.venv/bin/python checks/abi_gate.py` — ~40 s today, and it REFUSES in 0.05 s if
either input is gone. The live tree is never written; every arm is built from a copy.

---

## ABIFIX-1 — THE VERDICT BEFORE, UNDER BOTH INTERPRETERS, VERBATIM

`before.rows` is the first thing written to disk in this unit, and it was captured before any
edit. **Two interpreters, two exception sites, one answer: NO DENOMINATOR.**

    $ .venv/bin/python checks/abi_gate.py          # Python 3.12.10
    Traceback (most recent call last):
      File ".../checks/abi_gate.py", line 804, in <module>
        main()
      File ".../checks/abi_gate.py", line 532, in main
        decl = json.loads(DECL.read_text())
    FileNotFoundError: [Errno 2] No such file or directory:
      '.../checks/abi.json'
    exit=1

    $ python3 checks/abi_gate.py                    # Python 3.14.6
      File ".../checks/abi_gate.py", line 43, in <module>
        from tinygrad import dtype as td
    ModuleNotFoundError: No module named 'tinygrad'
    exit=1

`abi4_gate.py` measured the same two-site split on its own gate and was right to generalise
from it. **The second site is the `parents[2]` defect, not a variant of the first**: with
`REPO = /Users/cyberistic/src`, `sys.path.insert(0, REPO)` puts a directory with no
`tinygrad` in front of the venv's editable install, so the import that ABIFIX-3 now asserts
*after* is what raised. **One file, two defects, and each one masked the other** — under
`python3` you never even reached the missing declaration.

An exception is not a red gate. It has no denominator and no disagreement, so it was excluded
from every count by being uncategorisable, and `abi4_gate.py:540` adjudicates
`"abi_gate.py exits 0 against this tree"` — a gate that *raises* and a gate that *ran and
found nothing wrong* are the same observation to it.

## ABIFIX-2 — WAS IT EVER GREEN, AND AT WHICH COMMIT

**YES: `135bf0204`, 2026-10-04, `gate rc: 0`, 27 PASS / 0 FAIL.** The artifact is recovered
verbatim at `green-at-135bf0204.rows` (`git show 135bf0204:.agents/slop/abi/abi-gate.txt`),
and `135bf0204` **is** in `HEAD`'s ancestry.

The gate did not live at `checks/` then. `git cat-file -e 135bf0204:checks/abi_gate.py`
fails: it was at `.agents/slop/abi/abi_gate.py`, **three levels below the root**, which is
exactly where `parents[2]` is correct. `git log -S'parents[2]'` on the path returns one
commit for the *constant*'s introduction and the move separately, and the arithmetic is the
whole lesson:

| path | depth below root | `parents[2]` is |
|---|---|---|
| `.agents/slop/abi/abi_gate.py` | 3 | **the repo root** ✔ |
| `checks/abi_gate.py` | 1 | `/Users/cyberistic/src` ✘ |

`57d0fc387` ("slopcopies: 110 COPIES DELETED, 126 CITATIONS REPOINTED") moved the file up two
levels and repointed every **citation** while carrying both **constants** across unchanged.
**This is a regression caused by a MOVE, not by an edit** — and it is the same shape as
`abi4_gate.py`'s, one file over, which is why the sibling unit found it there first.

## ABIFIX-3 — WAS `abi.json` DELETED, OR NEVER COMMITTED

**DELETED. It was committed, it is recoverable byte-exact, and the deleting commit is in
`HEAD`'s ancestry.** This is a fact about git, not an inference:

    git log --all --diff-filter=D -- '*abi.json'
    371cc64c9  sweep: THE SWEEP DELETED 3,603 FILES AND TOOK 166 REPRODUCTION
                PATHS WITH THEM ... 116 OF 127 RECOVERED FROM GIT.
    96b3b8874   (empty message)                    <- NOT in HEAD ancestry
    130e9f136   (empty message)                    <- NOT in HEAD ancestry

    git show --stat 371cc64c9 -- '*abi.json'
     .agents/slop/abi/abi.json | 441 ----------------------------------------------
     1 file changed, 441 deletions(-)

So the declaration was NOT lost by the slop→checks move: it lived at
`.agents/slop/abi/abi.json` and **`371cc64c9` deleted it outright**, two commits before
`57d0fc387` moved the gate that reads it (`git merge-base --is-ancestor 371cc64c9 57d0fc387`
→ yes). **That is the sibling report's one correction.** It attributes the loss to "the same
slop→checks move took `abi.json`'s expectation with it and left the file behind"; the git
record says the file was never moved at all — it was swept, and the move came later and found
nothing to carry. The consequence is the same (`:532` raises) and the reason is not.

**One blob, unchanged for its whole life.** Across all 55 commits that ever contained it, the
sha256 is `46db02f2f0c255b3c016b1cfd24ae493aa2096d93ce46266ca35d9c2949771e4` — 441 lines,
19,824 bytes. It was edited three times (`888ed3a1e` add, `f252b1b7`, `135bf0204`) and the
final form is the one restored. The two other deletion commits are sibling worktrees of the
same sweep, so **there is no ambiguity about which bytes are the declaration's**: one blob,
one content.

## ABIFIX-4 — THE RESTORED BYTES, AND HOW THEY WERE VERIFIED AGAINST THE CALLER

`checks/abi.json` is `git show 371cc64c9^:.agents/slop/abi/abi.json`, byte-identical
(`cmp` clean, sha256 as above) to `abi.json.recovered`. **It is a restoration, not a
reconstruction** — no byte was authored here.

"Restored" is not "correct", and the brief's warning is the reason this section exists: **a
restored file that no longer matches its caller is a new class of broken.** So it was checked
against the gate, in three independent ways, and **two of them say the file is now stale**:

1. **Shape.** The gate reads `decl["abi"][i]["id"|"name"|"statement"|"site"]` and
   `decl["undeclared"]`, where an entry is `[id, prose]` or `[id, prose, meta]`. The
   restored blob has exactly those: 4 ABI ids, 4 `undeclared` entries, one of them
   (`ABI-8`) carrying `{"historical": true, "why": ...}` — the opt-out `undeclared_refs()`
   documents, which the gate reported as `1 declared-historical entry skipped`. **0 shape
   errors.**
2. **Caller semantics.** 32 citations: 23 `[file, line, token]` and 9
   `{file, body, token}`. All 9 generated-body citations resolve against the backends the
   gate emits (8 `ok`, 1 `STALE`). All 4 `undeclared` prose blocks parse under the gate's own
   `UNDECLARED_REF` regex.
3. **The tree.** **23 of 32 are STALE, and this is the finding, not a defect in the fix.**
   Measured against the tree at `135bf0204` — the commit where the gate was green — the same
   23 lane citations are **0 stale**. So the pins were correct when written and the tree has
   moved under them:

   | cited | token | token's actual line now | moved by |
   |---|---|---|---|
   | `dtype.c:205,207,216` etc. (10 C citations) | `i64_of(Env e, Term t)`, `io_tup(e,`, … | 236, 238, 247, … | **+21 to +33** |
   | `dtype.js:143,160,168,191,192` (10 JS citations) | `return of32(`, `p.hi >>> 0`, … | 151, 172, 180, 203, 204 | **−25 to +12** |
   | `dtype.bend:580,584,588` (3 declaration citations) | `def Dt.fp16(x: F32) -> IO(F32):` | **GONE ENTIRELY** | see ABIFIX-6 |

   **20 of the 23 stale tokens are still present in their file, on a different line.** Three
   are gone, and they are gone for a *reason the gate itself names* (`probe.rows` §B): the
   seams stopped being effects. `dtype.bend:748` is now `def Dt.fp16(+x: F32) -> F32:` where
   `135bf0204:580` was `def Dt.fp16(x: F32) -> IO(F32):`.

**So the restored file is the gate's own reference, restored exactly, and it is red because
the tree moved — which is what a pointer check is for.** Its red is the declaration reporting
on itself, and it is the FIRST of the seven FAILs below. The pins were deliberately **not**
re-pointed: re-pointing them would be this unit authoring the declaration's claims, and three
of them have no line to point at.

## ABIFIX-5 — THE FIX, AND THE OFF-BY-ONE

`parents[2]` → **`parents[0]`**, not `parents[1]`. `Path.parents` is 0-indexed, so
`parents[0]` *is* `checks/`'s immediate parent = the repo root; `parents[1]` is
`/Users/cyberistic/src/tries` and is also wrong. **The depth is now PROVED, not assumed** —
`refuse()` asserts `C_LANE.is_file()` under `REPO`, which is `sb-gate.sh` rule 1 ("a `cd`
that lands outside is exit 3") in Python.

**`refuse()` is placed BEFORE the `tinygrad` import**, and that placement is the substantive
part of ABIFIX-1. Under bare `python3` the original defect raised *in the import*; an
assertion sitting downstream of the thing it asserts cannot convert that exception into a
refusal. Moving the import below the assertions is what makes the plant below exit 3 rather
than re-raise `ModuleNotFoundError` under one of the two interpreters.

It also asserts every input EXISTS: `BEND`, `JS_LANE`, `DECL`. A missing input is not a
passing input — that is the `[ -f $BASE ]`-with-no-else shape `sb-gate.sh` retired, and
`checks/abi.json`'s absence is exactly that shape's residue.

**One more constant, found while measuring: `undeclared_refs()` resolved `gen/` refs as
`HERE / "abi" / rel`** — i.e. `checks/abi/gen/probe.js`, a directory that has never existed,
while `main()` writes those backends to `gendir = HERE / "gen"` and `cite_ok()` resolves them
there. Fixed to `HERE / rel`. It is the same class: a `pathlib` join that invents a directory
is a stale `parents[N]` with a different spelling. It was **latent, not firing** — no live
`gen/` citation exists in the block — so this changes today's verdict by nothing and is
reported because a fix that is not exercised is a claim, not a measurement.

## ABIFIX-6 — PLANTS AND DISARM, RUN AGAINST THE FIX

`plants.rows`, verbatim. **The regression does not reproduce its own exception; it produces a
stated refusal.**

| run | `REPO` / mutation | rc | what it said |
|---|---|---|---|
| **FIX** | `HERE.parents[0]` | **1** | a full verdict, 20 PASS / 7 FAIL |
| **PLANT** | `HERE.parents[2]` *(the regression, restored)* | **3** | `REFUSED … /Users/cyberistic/src is not the repo root` |
| **PLANT** | `HERE.parents[1]` *(the near miss)* | **3** | `REFUSED … /Users/cyberistic/src/tries is not the repo root` |
| **PLANT** | `checks/abi.json` removed *(the sweep, replayed)* | **3** | `REFUSED … input absent: …/checks/abi.json` |
| **DISARM** | `HERE.parent` *(equivalent spelling, not a mutation)* | 1 | **byte-identical to FIX**, stdout *and* stderr |

Three plants, three refusals, zero exceptions. One disarm, 0 rows moved — the only correct
count. The plant that restores `parents[2]` is the one that matters: it is the exact
regression, and the gate now answers it with a number about itself instead of a traceback.

## ABIFIX-7 — THE VERDICT AFTER, WITH ITS DENOMINATOR

`after.rows`. **rc 1. 27 checks, 20 PASS / 7 FAIL — and this is the same 27-check table the
green artifact has, so the gate's own denominator is unchanged and now reachable.**

**Designed: 12 rows × 11 arms × 2 lanes = 264 lane-row comparisons, all executed.** Both
lanes printed 12/12 in the shipped arm, and `drive()` exits on a short row set, so no arm
contributed an absence to a count.

The measurement itself is **green**: `cc agrees with CPython on 12/12`, `node agrees with
CPython on 12/12`, `the two lanes DISAGREE on 0/12`. Both interpreters agree — bare `python3`
now reaches the same 20/7 because `parents[0]` is the real root.

**The 7 FAILs are two clusters, and they are the same finding:**

- **1 — "the declaration's pointers are current"**: the 23 stale citations of ABIFIX-4.
- **6 — every plant that was supposed to FIRE did not** (ABI-2 in, ABI-2 out, ABI-1 on cc,
  ABI-3, ABI-4, and "the two lanes agree *because both are right*"). **All 5 plants and all 5
  disarms moved 0/12 rows.** `green-at-135bf0204.rows` shows the same 5 plants moving 4–5
  rows each (5, 5, 5, 5, 4) and the same 5 disarms moving 0 — so the disarms are unchanged
  and **only the plants stopped working**.

**And the cause is measured, not guessed: NEITHER LANE IS REACHED ANY MORE.** From
`probe.rows` §C — a plant of *uncompilable* C appended to `runtime/dtype.c`:

    bend rc 0, cc rc 0, 12/12 rows, IDENTICAL to the unplanted run
    grep -c THIS_IS_NOT_C   <probe.gen.c>  = 0
    grep -c i64_of          <probe.gen.c>  = 0    (dtype.c has 7)
    grep -c pack64          <probe.gen.c>  = 0    (dtype.c has 8)
    grep -c dtype.js        <probe.js>     = 0

    git grep -c 'import "./runtime/dtype' -- 'tinybendygrad/*.bend'
      135bf0204:  dtype.bend = 20
      HEAD:       dtype.bend = 0

`dtype.bend`'s seams were `import "./runtime/dtype.c"` / `.js` — the seam's body WAS the FFI
into the lane, which is why `135bf0204`'s `probe.gen.c` had `i64_of` ×7 and `pack64` ×8
(dtype.c inlined). They are **pure Bend now**, so the emitted probe no longer *contains*
either lane, and every plant is patching a file nothing reads. `abi_gate.py` is measuring
`dtype.bend` compiled two ways, and calling it two lanes.

**This is the eleventh instance of the class this repo keeps rediscovering** — the same one
`abi4`'s unit celebrated as ABI4-4 (*"a lane that printed nothing counted as a lane that was
never wrong"*), except here the lane prints all 12 rows, so every presence guard passes. **A
plant that moves 0 rows is either a fixture that cannot separate, or a lane that is not
consulted, and only one of those is a theorem.** `.agents/slop/LANE-LIVENESS.md` already
records `dtype.bend` as one of 2 lanes that compare ZERO rows; this gate is a third instance
of the same wiring, reached from the other direction.

## ABIFIX-8 — THE TOOLCHAIN IS NOT BROKEN. MEASURED ON THIS GATE.

The brief warned me not to inherit "the toolchain is broken" from `abi4`'s unit, and that
warning was **correct**. `probe.rows` §A/§B, on this gate's own probe:

    ## A. the same seams, bound with `=`      -> bend rc 0, node rc 0, 12/12 rows
    ## B. the same seams, bound with `<-`     -> SOME PROOFS FAIL, dies on the FIRST bind
       - expected : @-R:Type -> @k:(@_:H.I64 -> IO.OP<R>) -> IO.OP<R>
       - observed : H.I64

**The two runs differ by one character per bind.** `bin/bend` compiles and runs this probe
today; what it rejects is an *effect* bind against a seam that is no longer an effect. The
parent's refutation stands and extends: `tinybendygrad/uop/ops.bend` at 401,110 bytes
checking out is not the only witness — the 12-row ABI probe checks out too, once written in
the tree's current dialect.

So `PROBE`'s eleven `<-` binds are **a third stale fixture in this gate, same class as
`abi.json`**: written against a tree where the seams returned `IO(...)`. Fixed to `=`.
**This was not in the brief and is the one change here that goes past the two named
findings** — it is reported because without it the gate cannot reach a verdict at all, and a
gate that exits 0 having run nothing is worse than no gate.

## WHAT IS NOT SETTLED

1. **Whether the six `abi.json` citations that name `runtime/dtype.{c,js}` should still
   exist.** The lanes are unreachable from `dtype.bend` today (ABIFIX-7), so three ABI ids in
   the declaration are now conventions about **files nothing imports**. Re-pointing the pins
   would hide that; rewriting the ABI entries would be authoring the declaration. **Left for
   whoever owns the declaration's content.**
2. **Whether `checks/gen/` (created by this run, `probe.js` 1,415 lines, `probe.gen.c`, and
   **not** gitignored) belongs in the tree.** `135bf0204` had it committed at
   `.agents/slop/abi/gen/`, because *"`bend -o` embeds `import \"./x.js\"` verbatim, so a
   citation into a temp dir is a citation into nothing"* — a real reason, but it is now
   **two generated files of a dead lane**, and one of the nine generated citations is already
   STALE against them. **Not committed and not deleted; flagged.**
3. **Whether `abi4_gate.py`'s 98 rows are subject to the same disconnection.** It writes the
   lane to `work/tinybendygrad/runtime/dtype.js` and runs `bend` on a probe importing
   `dtype.bend` — structurally identical to what I measured here. **Not run and not edited:
   `abi4_gate.py` is not this unit's, and a unit may be measuring it.** If its plants have
   also gone to 0, the `ABI4-7` table (NEEDS 10/40/30, FIXES 10/10/0) is measuring
   `dtype.bend`, not `dtype.js`, and that is the largest single claim in the ABI-4 report.