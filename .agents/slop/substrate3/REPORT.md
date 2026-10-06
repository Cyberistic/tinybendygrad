# `checks/substrate.py` — what `unseen` is, and giving the sweep a population

Unit: substrate3. Repo HEAD at start: `9c947d0ac36da7f85d67c217fce8e170e20e3f96`. All python run as
`.venv/bin/python`.
**`bend` was NOT run** — the `.bend` and `.c` lanes of HALF 1 are `READ-ONLY — compiles bend`.
Everything below that needs `bend` is left unrun and labelled. Raw captures beside this file:
`pop.files` (the 138-file `.bend` population), `pop.before.out` (ORIGINAL code),
`pop138.after.out` (same 138, EDITED code), `pop.after.out` (`--root -n`, 144 files),
`node.out`, `plant.out`. Plant harness: `plant.py`.

---

## 1. WHAT `unseen` COUNTS, EXACTLY (original `:591-594`, current `:645-647`)

The ref counter is `REF = re.compile(r"\b([A-Za-z_]\w*)\.([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)")`
(`:490`). For each match `al = group(1)`, `dotted = group(2)`:

```python
if al not in alias:                 # :645   `alias` is built ONLY from aliased imports
    if al[:1].isupper():            # :646   the ONLY test applied
        t["unseen"] += 1            # :647
    continue                        # :648   no resolution is attempted, ever
```

`alias` is populated at `:621-627` from `IMPORT` (`:485`), which requires the literal `\s+as\s+`.
**So `unseen` is not "a name I could not resolve". It is a COUNT, BY SHAPE, of every `Foo.bar`
in the file whose `Foo` (a) is not one of the file's `import ... as Foo` names and (b) starts
with an uppercase letter.** No pool is consulted (`continue` at `:648`); nothing is looked up;
the ref is neither exact, suffix-only, nor unresolved. It is a ref the counter *did not ask a
question about*.

**Why it is not a finding: it is outside the pool BY CONSTRUCTION.** The pool is
`pool[a] |= decls(t_)` (`:580`) for `a, t_ in alias.items()` — i.e. only aliased imports.
`import Base` (123 of the 138 files, `rg` census) has no `as`, so it never enters `alias`, so
the whole stdlib surface it carries has no pool to resolve against. The frozen shell oracle
records this reason verbatim: `.agents/slop/substrate/oracle-check.sh:427`
`if al[:1].isupper(): T["unseen"] += 1   # UNALIASED: Base / stdlib`.

---

## 2. SHOULD `unseen` BE A FINDING? NO — AND THE DOCUMENTED REASON IS HALF THE TRUTH

The exclusion reason is real and structural (§1). But the comment at `:603-607` names it as
*"i.e. the unaliased `import Base` stdlib surface"*. **That is one of two components, and not
the larger one.** Measured over the 138-file population, splitting each unseen ref by whether
its prefix is declared in the *same file*:

```
unseen = 47,275   LOCAL (prefix declared in this same file) = 22,599  (47.8%)
                  OTHER (Base stdlib / genuinely undeclared) = 24,676  (52.2%)
```

`renderer/isa/x86.bend` alone: 1,891 of its 2,584 unseen are LOCAL (`Reg.`, `Asm`, `Enc`,
`AsmMem` are `type`/`def` in that very file). So `unseen` is two classes — **local types the
file itself declares** and **the unaliased `import Base` surface** — and a third sliver of
genuinely undeclared names hides inside the second.

**As a hard finding it would cry wolf: 47,275 red sites, ~half of them provably fine.** The
task's own hypothesis is the correct diagnosis: *"the parse cannot tell a local from a module
ref"* — a PARSE limitation. A longer parse fixes it; a louder alarm does not. The longer parse
needs the file's own `decls()` **plus** bend's builtin `Base`, and `Base` is **not in this
tree**: `tinybendygrad/base.bend` is 56 lines declaring only `def F32.from_bits`; the 3,009-line
module that declares `List`/`U32`/`String`/`Bool` is `references/bend/bend2/base.bend`, which is
gitignored and untracked. Resolving local refs but not `Base` would flip ~24,676 legitimate
refs to a false `unresolved` — the exact false positive we must not introduce.

---

## 3. CHOICE: (a) A NAMED CLASS WITH ITS OWN DENOMINATOR (cite `:674-683`, `:792-807`)

Option **(a)** is implemented. `half2` now returns the tally, and prints — after `TOTALS` — a
`COVERAGE` line (`:680-683`) carrying the DENOMINATOR the name check travels with:

```
COVERAGE qualified=84058 checked=36783 UNSEEN=47275 (56.2%)  <- unseen refs are OUTSIDE the
import graph (local types + the unaliased `import Base` stdlib). NOT findings; an unaccounted surface.
```

`qualified = refs + unseen` (`:674`). The `NAMES CLEAN` / `SUBSTRATE CLEAN` sentence
(`:792-807`) now states `checked` of `qualified` instead of claiming "all names resolved" flat,
and the closing prose names the second component (local types). `unseen` remains **NOT a
finding**.

**What (b) would cost.** It needs the file's own decls added to the pool *and* bend's `Base`
vendored into the tree (or a `--stdlib` path). Local-only resolution leaves 24,676 Base refs
(52%) still unseen, so it does not close the blind spot; and it would newly surface real
`unresolved` sites, changing the verdict of a gate unilaterally. That is a bigger, riskier
change than a disclosure, and it cannot be made *correct* without the stdlib present. (a)
discloses the same 56% at zero risk of a false red.

---

## 4. THE POPULATION DECLARATION (Doctrine 1)

Before: no `os.walk`, no `glob`, no generator — `run()` iterated `argv[i:]`, and no tracked caller
passed the tree (every call site passed 1 or 2 files). Added:

- `POP_ROOT = "tinybendygrad"`, `POP_SUFFIXES = (".bend", ".c", ".js", ".mjs")` (`:110-111`) —
  the four classes `instrument_for()` can judge, stated in one place.
- `discover(root)` (`:114-126`): `os.walk`, `dirs.sort()` + `sorted(fs)` for stable order, membership
  by `endswith(POP_SUFFIXES)`. The `*.staged-*` scratch copies and `*.mut` mutants do not match,
  so the same rule that includes the real files excludes the junk.
- `--root [DIR]` (`:230-234`), `const=POP_ROOT`; `split_leading` (`:166-203`) consumes the next
  token **only if it is a directory**, so `--root` followed by a file does not eat it, and keeps
  `--root=DIR`. `main()` (`:833-835`) discovers only when there are no file arguments; a printed
  `POPULATION root=... files=... by os.walk (...)` line (`:770-771`) makes the denominator
  auditable.
- Zero arguments still `REFUSED` (rc 3); the usage line now points at `--root` instead of a
  caller's `find`.

**`argv` is untouched:** a 1-file or 2-file caller is judged exactly as before (verified below).

---

## 5. THE PLANTS — TWO STATES EACH (`plant.py`, `-n`, no `bend`)

```
PLANT A  unseen-shaped ref (add `Zzz.missing_whole_world(B.Thing)`, `Zzz` not an alias)
  before: rc=0 BAD=0 UNSEEN=1
  after : rc=0 BAD=0 UNSEEN=2   (delta UNSEEN=1, delta BAD=0)
  STATE 1 GREEN rc=0? True   STATE 2 GREEN rc=0? True

PLANT B  broken import (`import ./ghost.bend as G`)
  broken  : rc=1 BAD=2 missing_module=1
  restored: rc=0 BAD=0 missing_module=0
  STATE 1 RED rc=1? True   STATE 2 GREEN rc=0? True
```

Plant A is the finding: an unseen-shaped ref **moves the number and does not move the verdict**.
Plant B proves the sweep still goes red on a real defect and green on restore.

---

## 6. COUNTS, WITH DENOMINATORS, BEFORE AND AFTER

Same 138 `.bend` files, `-n`, original code vs edited code (`pop.before.out` / `pop138.after.out`):

| | refs | exact | suffix | unresolved | unseen | missing_module | dead_import | finding |
|---|---|---|---|---|---|---|---|---|
| BEFORE | 36783 | 36783 | 0 | 0 | 47275 | 0 | 37 | 1 (PORT ALARM) |
| AFTER | 36783 | 36783 | 0 | 0 | 47275 | 0 | 37 | 1 (PORT ALARM) |

Identical. The new denominator over those 138: **`qualified = 84058`, checked `36783` (43.8%),
UNSEEN `47275` (56.2%)**. The one live finding is the pre-existing untracked-probe PORT ALARM
(`tinybendygrad/test/_probe/v5.bend`), not a port defect.

`--root -n` (the new population declaration) discovers **144** files = 138 `.bend` + 2 `.c` +
3 `.js` + 1 `.mjs`: `refs=36783 exact=36783 unresolved=0 unseen=47402`, `qualified=84185`
(UNSEEN 56.3%), rc=1 (same probe). The node lane, run for real (no bend), is unchanged:
4 `WARM`, `BAD 0`, rc=0 (`node.out`).

### Does `SUBSTRATE CLEAN` still mean what it meant?

**It does not mean something STRONGER, and that is deliberate.** No new finding was added;
`unseen` is still not a failure, so a clean run is exactly as clean as before. What changed is
that the verdict is now **honest about its own denominator**: the CLEAN sentence prints
`checked of qualified` and the `COVERAGE` line names the 56% the name check cannot decide.
`unseen` went from a number a reader had to hunt to a named class tied to its whole.

**The one real cost: the frozen oracle.** `.agents/slop/substrate/diff.py` compares the port's
stdout BYTE-FOR-BYTE against `.agents/slop/substrate/oracle-check.sh`. The added `COVERAGE` line
and the reworded CLEAN/verdict sentence mean that diff would now report drift on the HALF-2
lines. The oracle file itself and `ORACLE_PIN` (sha of that file) are untouched; only the port's
text moved. That is the deliberate verdict-text change this task requested, and the diff (under
`.agents/slop/`) must move with it — stated here, not fixed here.
