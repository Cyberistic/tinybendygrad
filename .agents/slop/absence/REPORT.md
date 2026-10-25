# The `upstream_removed` class — a TRUE ABSENCE, and a class that can go RED

`gates/pin-cite-gate.py`, 2026-10-25. One task: **the census had no class for a citation
whose claim IS the absence**, so a true claim about upstream read as
`at_no_revision_dangling` — a false reading of a true claim.

Everything below is measured by a named instrument:

- `.venv/bin/python gates/pin-cite-gate.py --tree DIR --rows OUT.rows` — the census.
- `.venv/bin/python gates/pin-cite-gate.py --plant` — the four absence arms.
- `.venv/bin/python .agents/slop/absence/measure.py` — the two measurements below, and
  `--compare BEFORE.rows AFTER.rows` for the elementwise class movement.

---

## 1. The class, and its evidence rule

**`upstream_removed`** — the row's claim IS that upstream does not have the thing, and
upstream's history confirms it.

`absence_of()` in `gates/pin-cite-gate.py` is the whole of it. **Six conditions, every
one necessary:**

| | condition | what it rules out |
|---|---|---|
| 1 | **the row names a revision R** — an upstream commit sha it writes, or the pin it names | a mood is not a claim |
| 2 | **R is consistent with the pin's history** — R is an upstream commit that is an ancestor of (or equal to) the pin | a sha of *this* repo's history; a revision the port does not contain |
| 3 | **the construct is absent at R** — a claim token does not occur in the cited file's content at R | a claim about a construct upstream still has |
| 4 | **the construct was present before R** — the same token occurred in that file at some revision older than R | a name upstream never had; the port's own vocabulary |
| 5 | **the removal is attributable** — the commit D at which the file's content changed from holding the token to not holding it exists, and D ≤ R | a removal with no commit behind it |
| 6 | **the row asserts the absence** — the port's absence marker is on the citation's own line | a claim that upstream HAS the thing |

**WHAT "CONSISTENT WITH THE PIN'S HISTORY" MEANS, PLAINLY.** The pin ships the tree this
port is based on, so a revision the pin does not contain is a revision the port cannot be
checked against. R therefore has to be an **upstream** commit at or before the pin.

**MEASURED, 2026-10-25** (`.agents/slop/absence/measure.py`):

```
upstream ref tip      5c2bf39d6c4b6b201abdf2865dd4a14228de4e60
DECLARATION's OUR PIN 5c2bf39d6c4b6b201abdf2865dd4a14228de4e60
the two are equal     True
upstream commits      15368

the port's headers name 91 distinct hex runs:
  not-a-commit at all                     70     (0xffffffff, 3.1415926218032836914, ...)
  upstream, at or before the pin          18
  a commit of THIS repo, not of upstream   3     (80d329a33, c2a66ea41, e853efc4b)
```

**⇒ THE CONDITION IS NOT VACUOUS.** Three of the shas the port's headers name are commits
of *this* project, and a row naming one of them can never be a claim about upstream.

**⇒ AND THE MARKER IS NECESSARY WHILE THE EVIDENCE IS SUFFICIENT.** A claim that upstream
DELETED a construct and a claim that upstream HAS one are the **same shape** to every
instrument that reads a citation — a name, a file, a line — and no amount of upstream
history tells them apart. Only the row says which one it is making.

**MEASURED, and this is the TIGHTNESS number:**

```
header lines carrying a marker:            317
of those, lines that also carry a citation:  44
THE EVIDENCE selects 2 of the 44.
```

The 42 the evidence refuses are the port talking about **itself** (`base.bend` has no
`File.list`), about a construct upstream **never had** (`cfield` was never in
`tinygrad/runtime/support/c.py`), or naming **no revision at all**.

**⇒ THE MARKER ALONE QUALIFIES NOTHING, AND THE EVIDENCE ALONE IS NOT ENOUGH.**

---

## 2. The two rows it now classifies

| row | the row says | the evidence |
|---|---|---|
| `tinybendygrad/runtime/ops_amd.bend:231` | "`hashlib.md5` … **NOT IN upstream at this pin**: upstream's `runtime/ops_amd.py` has NO `hashlib.md5`" | `hashlib` and `md5` were REMOVED from `tinygrad/runtime/ops_amd.py` at `fa0f9af3b` ("amd: remove rgp markers", #18643) and are absent at the pin |
| `tinybendygrad/runtime/ops_cl.bend:159` | "upstream's old `OSX_TIMING_RATIO` form is **GONE at this pin**" | `OSX_TIMING_RATIO` was REMOVED from `tinygrad/runtime/ops_cl.py` at `38cbec532` ("move cl to hcq2", #18872) and is absent at the pin |

Both removals are upstream's own, and both removal commits are ancestors of the pin.

---

## 3. The class counts, before and after

**ONE FROZEN TREE** (`--tree`, a copy of `tinybendygrad/`), because the live tree is owned
by other units and moves under the gate's feet. `cite.total` is 2547 in both readings.

| class | before | after |
|---|---|---|
| `cite.total` | 2547 | 2547 |
| `cite.checkable` | 1600 | 1600 |
| `cite.uncheckable_no_claim_token` | 947 | 947 |
| `cite.at_pin` | 1289 | 1289 |
| `cite.only_older_revision` | 16 | 16 |
| `cite.at_no_revision` | 295 | 293 |
| `cite.at_no_revision_dangling` — **the fail class** | **2** | **0** |
| `cite.ambient_relocated` | 1 | 1 |
| `cite.unverifiable_no_claim_about_the_file` | 221 | 221 |
| `cite.upstream_removed` — **the new class** | — | **2** |
| `cite.local_sided_excluded` | 546 | 546 |

The two rows that left the fail class are the two true absences above. **The count of
false citations fell from 2 to 0 because two TRUE claims stopped being read as false —
not because a genuinely false row was re-labelled.** The elementwise proof:

```
$ .venv/bin/python .agents/slop/absence/measure.py --compare BEFORE.rows AFTER.rows
  MOVED tinybendygrad/runtime/ops_amd.bend:231  dangling -> upstream_removed
  MOVED tinybendygrad/runtime/ops_cl.bend:159  dangling -> upstream_removed
rows before 2547, after 2547
  dangling -> upstream_removed: 2
  non-class field moves: 0
```

**⇒ NOT ONE ROW OF ANOTHER CLASS MOVED, AND NOT ONE VERDICT FIELD MOVED** (`at_pin`,
`newest_rev`, `claim`, `present_in_file`, `explicit`). The new class sits **below**
`at_pin`, `only_older_revision`, `ambient_relocated` and `unverifiable` in the precedence,
so it can only ever take a row **out of** `dangling` or `at_no_revision`: it can never
re-label a row another class already holds, and it can never accuse.

---

## 4. The plant — the class goes RED, in both directions

`.venv/bin/python gates/pin-cite-gate.py --plant` grew **four arms that differ ONLY in the
tail of one line**, and the plant asserts that they differ in nothing else. The subject is
DISCOVERED from the corpus's own history (a construct upstream deleted), not named.

```
PLANT absence arm: tinygrad/__init__.py:1 token `shape` -- DELETED at 5ae2de9845e4, and STILL PRESENT at 5132bab48d1a
PLANT absence-arm  tinygrad/__init__.py:1 at_pin=NO newest=NONE class=upstream_removed   present_in_file='shape'
PLANT absence-wrong-rev tinygrad/__init__.py:1 at_pin=NO newest=NONE class=dangling      present_in_file='shape'
PLANT absence-no-rev    tinygrad/__init__.py:1 at_pin=NO newest=NONE class=dangling      present_in_file='shape'
PLANT absence-not-a-claim tinygrad/__init__.py:1 at_pin=NO newest=NONE class=dangling    present_in_file='shape'
PLANT OK: … the ABSENCE arm is a TRUE ABSENCE, and the wrong-revision, no-revision and
          not-a-claim arms are all STILL DANGLING
```

| arm | the tail | verdict |
|---|---|---|
| `absence-arm` | `upstream DELETED \`shape\` at <the removal commit>` | **`upstream_removed`** — the claim is true |
| `absence-wrong-rev` | `upstream DELETED \`shape\` at <a revision where upstream still HAD it>` | **`dangling` — RED.** The evidence fails: the construct is present at the revision the row names |
| `absence-no-rev` | `upstream DELETED \`shape\`.` (no revision) | **`dangling` — RED.** A comment that merely mentions a deleted name, with no revision, does not qualify |
| `absence-not-a-claim` | `upstream's \`shape\` is there at this pin.` (the revision, no marker) | **`dangling` — RED.** The construct really is gone at the pin, but the row does not SAY so, so the direction is not the row's |

The `absence-not-a-claim` arm is the one that isolates condition 6: it names the pin, the
construct really was removed before it, and it still stays red.

---

## 5. What I could NOT make tight, and why

**THE MARKER IS A HAND LIST, AND IT IS THE ONE LEXICAL PRECONDITION IN THE CLASS.**
`ABSENCE_MARKER` is six words (`GONE`, `DELETED`, `REMOVED`, `NOT IN`, `DOES NOT
EXIST`, `has NO`). It is measured — 317 header lines carry one, 44 of them carry a
citation — and it is necessary-but-not-sufficient, so it cannot qualify a row on its own.
**What it costs:** a row that asserts an absence in wording the list does not cover stays
`dangling`, i.e. **the class is too tight for that row, and the row stays RED.** That is
the safe direction: the gate cries and a human looks. The opposite error — the class being
too LOOSE — is what the evidence conditions exist to prevent, and the elementwise
measurement above is the proof that no other class was touched.

**⇒ AND THE DIRECTION CANNOT BE READ FROM THE CONTENT.** This is not a limitation of the
implementation, it is a fact about the instrument: a citation to `ops_cl.py:139` whose
token is nowhere in that file is a dangling claim if the port says "upstream's
`OSX_TIMING_RATIO` is at :139" and a true absence if it says "`OSX_TIMING_RATIO` is GONE at
this pin". **The two rows have the same shape to every content test**, so the direction
has to come from the row and the truth has to come from upstream's history. The class
splits them with one word and then PROVES the truth with five conditions.

**THE ABSENCE IS SCOPED TO THE FILE, NOT TO THE CITED LINE.** The two rows say "upstream's
`runtime/ops_amd.py` has NO `hashlib.md5`" and "upstream's old `OSX_TIMING_RATIO` form is
GONE" — file-scoped claims. The cited line is where the port says the SURVIVOR is
(`symbol=_amd_program_image`, `symbol=_wait_signal`), not where the removed construct was
(`hashlib.md5` was at `:558`, `OSX_TIMING_RATIO` at `:75`). **A LINE-SCOPED absence
("upstream's `foo` is not at `:12`") is NOT in this class**: it would fail condition 3
only if the construct were absent from the whole file, which a line-scoped claim does not
say. Such a row stays `dangling`, which is the right verdict for a claim the instrument
cannot read.

**THE CLASS IS NOT VACUOUS, BUT IT IS NARROW TODAY.** Two rows of 2547. The class is not
a filter that quietly swallows rows; it is a named, reported, evidence-backed class, and
its size is a measurement rather than a design target.

**WHAT THE CLASS DELIBERATELY DOES NOT DO.** It does not verify that the port's prose
about the survivors is true. It verifies that upstream does not have the thing the row
says upstream does not have. The survivors ("`Field._resolve` is the shape that replaced
it") are still the port's claim, and `gates/todo-cite-gate.py` is the instrument that
settles those.
