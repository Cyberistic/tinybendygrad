# bendarms REPORT — five graph arms for the bend dispatcher

Unit: `.agents/slop/graphcmp.bend` builder arms. Read `AGENTS.md` first: populations by
DISCOVERY, and `SKIP`/`DEAD`/`REFUSED` are not passes.

**I did not run `bend`** (another unit holds it). Everything below that is not a
`bend`-run is marked as such; the one claim only `bend` can settle is named at the end.

---

## 1. The dispatcher's SHAPE, and its fallback

`.agents/slop/graphcmp.bend`:

- `rows.pick3(+name: String) -> O.Found` — **`graphcmp.bend:1336`**. Its body is a
  right-nested `Bool.pick` chain, one rung per `String.eq(name, "<g>")`, so a graph
  name selects a builder.
- **The fallback is `g_matmul()` — `graphcmp.bend:1363`** (the bottom rung, reached
  when no `String.eq` matches). `g_matmul` is a REAL graph (`graphcmp.bend:609`).
- `rows.pick` (`:1365`) is a pass-through, and `main` (`:1477`) reads argv's tail via
  `fz_name` (`:1472`), so **no argument at all also lands on the `matmul`**.

So an unknown name **substitutes the matmul** and the differ then compares the MATMUL
against the py side's real graph. This is the `late`/`matmul` substitution fault
`AGENTS.md` names, and `checks/disagree-gate.py:78-80` pins it.

The py side is asymmetric and does NOT substitute: `graphcmp.py:2969` declares
`--graph` with `choices=sorted(GRAPHS)`, so an unknown name is refused at argparse
(exit 2). **Only the bend side substitutes.**

### Correction to the task's premise: it is EIGHT names, not five

`graphcmp.GRAPHS` (`graphcmp.py:1536-1543`) declares **30** names. Before this change
`rows.pick3` had **21** rungs + the `matmul` default = 22 reachable, so **eight** names
fell through to the matmul:

```
allred  cdiv  late  threefry  mulacc  getaddr  unshard  wmma
```

The task names the five new ones (`threefry mulacc getaddr unshard wmma`); `allred`,
`cdiv`, `late` were ALREADY unarmed (`disagree-gate.py:78-80` says so in prose). After
this change the five have arms and **three** still fall through: `allred cdiv late`.
I did not touch those three (they are a separate, pinned decision — see §4).

---

## 2 & 5. Per-graph: py fixture · bend arm · node/op/child match

The py fixture in `graphcmp.py` is the specification. I read each arm's target off
`emit --side py --graph NAME` (the py side's OWN rows), not off the docstrings — and
the docstrings are wrong: `g_mulacc`, `g_unshard` and `g_wmma` say "4 nodes"; their
rows are 10 / 8 / 11.

| graph | py fixture (`graphcmp.py`) | bend arm (`graphcmp.bend`) | nodes (py, MEASURED) | op order + child arity |
|---|---|---|---|---|
| `threefry` | `g_threefry` :1482 | `g_threefry` :1417 | **12** | MATCH (`static-check.py`) |
| `mulacc` | `g_mulacc` :1493 | `g_mulacc` :1435 | **10** | MATCH |
| `getaddr` | `g_getaddr` :1504 | `g_getaddr` :1390 | **2** | MATCH |
| `unshard` | `g_unshard` :1514 | `g_unshard` :1401 | **8** | MATCH |
| `wmma` | `g_wmma` :1524 | `g_wmma` :1458 | **11** | MATCH |

`.agents/slop/bendarms/static-check.py` proves, from the arm text, that for every arm
the ordered `(op, child-count)` sequence equals the py rows' sequence — e.g.
`threefry: ALLOC CONST CONST STACK RESHAPE ALLOC RESHAPE THREEFRY ALLOC RESHAPE
THREEFRY GROUP`. That is stronger than a count: a right count with a wrong order or
child arity is still a disagreement (the `lin` split-RANGE mistake in this file was
exactly that — 8 nodes, wrong src and arg).

**Every construction order is the toposort order the py rows carry** (the `id` column
is a toposort position), so the arena indices line up too.

### The one known column divergence — `wmma`'s `arg` (`tc` slot)

Not papered over, and it is a PORT SPELLING GAP, the same class as `flip`:

- py `carg` WMMA (`graphcmp.py`): the fourth slot `tc` is `None` and renders **`N`**.
- bend `argstr` AWmma: `case O.AWmma{...}: ... us(tc)` and `AWmma.tc` is
  `List<&2, U32>` (`ops.bend:1197`) — no `Maybe` — so an absent `tc` renders **`n()`**.

So `wmma` will read `wm(n(i3,i4,i4),Df32,i256,n())` on the bend side against
`wm(n(i3,i4,i4),Df32,i256,N)` on the py side: **the `arg` column disagrees on that one
slot; every other column and the node count match.** Closing it needs a `Maybe` in
`AWmma` (or a matching `argstr`/`carg` spelling) — a port change this unit does not
own. Reported, not hacked.

`getaddr`'s `ADev` arg resolves through the port's own table: `S.D1{0}` →
`render.bend:361` `dev_names()[0] = "CPU"` → `sCPU`, matching py's `sCPU`.

---

## 3. Proof that each arm BUILDS, without `bend`

Strongest available static check, in `.agents/slop/bendarms/static-check.py` (run:
`.venv/bin/python .agents/slop/bendarms/static-check.py`). It asserts:

1. all five builders are defined once;
2. every `O.<Name>` token in the arms resolves in `ops.bend` (as `def <Name>`,
   `def <Owner>.<Name>`, a namespace, or a record constructor `<Name>{`);
3. every `S.<Name>` resolves in `LAWS/spec.bend`, every `H.<Name>` in `helpers.bend`;
4. each `O.UOp.<ctor>(...)` call's arity equals the port's `def UOp.<ctor>` parameter
   count (proved non-vacuous: `UOp.new`→5, `UOp.wmma`→8, `UOp.range_end`→4,
   `UOp.getaddr`→4, measured off the defs);
5. `rows.pick3` has a rung for each of the five names;
6. the node counts and the `(op, child-count)` sequences above.

**What this is NOT.** It is a static resolution + arity + shape check over the SOURCE.
It does **not** typecheck the arms (bend's linearity/ownership rules, e.g. `+` binder
reuse) and it does **not** prove the emitted rows equal the py rows. **The final proof
needs `bend`: `bin/bend .agents/slop/graphcmp.bend <name>` for each name, then
`graphcmp.py diff --graph <name>`.** Until that runs, the arms are "authored and
statically resolved", not "verified".

Supporting (read-only, not a proof): `fold.bend` already carries dtype/shape arms for
all five ops (`OpsTHREEFRY` :2374, `OpsMULACC` :2396, `OpsGETADDR` :2298,
`OpsUNSHARD` :2200/:2438, `OpsWMMA` :2296), so the fold is not the missing piece — the
dispatcher arm is.

---

## 4. Making the fallback REFUSE (reported, NOT landed)

`g_matmul()` as the bottom rung means an unknown name is a substitution. A refusal
would be strictly better (a wrong comparison reports a disagreement that is the
dispatcher, not the port). I did **not** land it — it is a signature change and a
larger decision. What it would take and what it would break:

**What it takes.** `rows.pick3` returns `O.Found` and cannot fail; a refusal needs
`rows.pick`/`main` to return `IO(O.Found)` and `IO.fail` (or a `""`/`Unknown` sentinel
checked before the chain). That threads an effect through `main` — small, but not a
one-line edit.

**What it would break / must move with it:**

- **The 3 remaining unset graphs** `allred cdiv late`: today they get the matmul
  (NOT-A-ROW). A refusal makes the bend side emit NOTHING, which `graphcmp.py`'s trap 4
  (`emit_bend` re-runs then RAISES) turns into a FAILURE, not a verdict.
- **`checks/disagree-gate.py`**: its `SUBSTITUTED` pin is
  `("allred","cdiv","late","matmul")` (`:80`) and lane `:189-196` asserts the bend side
  has NO arm for `allred/cdiv/late`; the whole substitution diagnosis is that the bend
  file is byte-identical to another graph's (`NOT A ROW`). A refusal changes that shape
  (NOT-A-ROW → REFUSED/DEAD), so the pin, the diagnosis and the `CITES` entry that
  points at `graphcmp.bend:1336` ("its DEFAULT arm is what substituted the matmul")
  all have to be re-measured in the SAME commit.
- **`checks/corpus-figure.py`**: it builds every graph and pins `differ.py`'s
  `graphs`, `graphs-agree`, `not-comparable`, `graphs-unset`. A refusing bend side
  moves `not-comparable` / `graphs-unset`, so the figure and its pins move.
- **`gates/artifacts/` and `runs/graphcmp/D/`**: the run summary's per-graph verdicts
  change shape (`graphs-disagree`, `not-comparable`), and `disagree-gate.py:146` reads
  `graphs-disagree={len(PIN)}` from `D0-run-summary.txt`.

**Why it is safe to LEAVE for later:** the py side already refuses (argparse
`choices`), so making bend refuse aligns the two; but until `allred/cdiv/late` have
arms, a refusal would turn three pinned NOT-A-ROWs into three DEADs. That is a
corpus-shape change, not a dispatcher bug fix.

---

## The moved-pin hazard I hit and avoided

`checks/disagree-gate.py:85` CITES **`(".agents/slop/graphcmp.bend", 1336,
"def rows.pick3")`**. My first placement put the five builders BEFORE the dispatcher,
which pushed `def rows.pick3` off line 1336 and would have **broken that gate without
touching it** (the same "a pin that tracks a moving file must be re-measured when the
file moves" defect). I moved the builders to sit AFTER `rows.pick` (`:1365`), so
`def rows.pick3` is **still exactly `graphcmp.bend:1336`** — verified: `rg -n 'def
rows.pick3'` → `1336`.

Forward references are legal in bend, so this costs nothing:
**`tinybendygrad/runtime/support/autogen.bend:747`** `rep_emit1` calls `space()`,
defined at `:755`. MEASURED. (The dispatch comment `disagree-gate.py:78-80` in
`disagree-gate.py` now undercounts unarmed names — it does not mention the five — but
that prose is in `checks/`, which I do not own.)

---

## 6. Handoff to the bend unit, IN ORDER

1. **Run the arms** (the step that makes them proof):
   `bin/bend .agents/slop/graphcmp.bend threefry` … for all five, then
   `.venv/bin/python .agents/slop/graphcmp.py diff --graph <name>` for each. Expect
   AGREE for four; `wmma` should show a single `arg`-field mismatch on the `tc` slot
   (§2) and nothing else.
   - If the emit is empty or the process stack-overflows, apply graphcmp.py's trap 4
     (re-run; a 0-row side is FAILURE, never a verdict).
2. **Re-run `.agents/slop/bendarms/static-check.py`** if any arm is edited.
3. **Decide the `wmma` `tc` gap**: give `AWmma.tc` a `Maybe` (and match `argstr` to py's
   `N`), or leave it and add `wmma` to the same reported-divergence set as `flip`.
   Do NOT edit `AWmma`/`argstr` without the `flip` class in view — one spelling
   change moves both.
4. **Then, and only then, the fallback decision (§4)** as a separate change:
   re-measure `disagree-gate.py`'s `SUBSTITUTED` pin + `CITES` line,
   `corpus-figure.py`'s pins, and `runs/graphcmp/D/D0-run-summary.txt` together.
5. **Arm `allred`, `cdiv`, `late`** (the three the task did not name but the dispatcher
   still substitutes) — same procedure as §1, py fixture is the spec.
6. **Update `graphcmp.py`'s header graph table** (the "THIRTEEN GRAPHS" list) and
   `graphcmp.bend`'s dispatch comment only if it still names a stale count — those are
   prose ledgers, not this unit's proof.

**I did not commit; I did not touch `checks/`, `gates/`, `AGENTS.md`,
`tinybendygrad/`, or `runs/graphcmp/D/`.**

---

## Files this unit wrote

- `.agents/slop/graphcmp.bend` — five builder arms (`g_getaddr` :1390, `g_unshard`
  :1401, `g_threefry` :1417, `g_mulacc` :1435, `g_wmma` :1458) and five rungs in
  `rows.pick3` (:1336-1363). `def rows.pick3` deliberately left at `:1336`.
- `.agents/slop/bendarms/static-check.py` — the static proof in §3.
- `.agents/slop/bendarms/REPORT.md` — this file.
