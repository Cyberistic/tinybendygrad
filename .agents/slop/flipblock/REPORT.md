# FLIPBLOCK — `FLIP`'s bool `Arg` is NOT landable from here: a MEASURED REFUSAL

Rule prefix **`FLIPBLOCK`**. Scope read: `tinybendygrad/uop/ops.bend` (the variant),
`fold.bend` (the blocker), `render.bend`/`upat.bend` (compile arms), `.agents/slop/graphcmp.bend`
(the differ fixture). **The tree is UNTOUCHED.** All instruments are `.py` under
`.agents/slop/flipblock/`, run with `.venv/bin/python`.

**VERDICT: `REFUSED`, MEASURED — I did NOT half-land.** The task's precondition for taking
both edges is *"fold.bend is idle AND you can make the arm additive"*. The arm IS additive in
control flow (§1), but a FAITHFUL landing is **9 files, not two** (§2), one of them
(`tensor.bend`) is under another unit's **active** working-copy edit right now, and `fold.bend`
is on my explicit DO-NOT-TOUCH list. Per the brief's own rule 3, I took **neither** edge.

---

## 1. `order_arg` — additive in CONTROL FLOW, but NOT "one `case`"

`fold.bend:1850-1853`, the whole of it:

```
def order_arg(arg: O.Arg) -> List<&2, U32>:
  match arg:
    case O.ATuple{ys}: ys
    case _           : Nil{}
```

- **Does a new arm change the ORDER any other op depends on? NO.** A match arm keyed on a
  *new* constructor cannot match any value that exists today, so `ATuple` still returns `ys`
  and `_` still returns `Nil{}`. `order_arg`'s two callers are `perm_ds` (`:1856`) and
  `flip_ds` (`:1889`); PERMUTE keeps its `ATuple`, so **PERMUTE's fold is byte-identical.**
  Additive: verified by reading both callers and the `M12` mutation row (`fold.bend:6683`:
  `order_arg→Nil{}` moves 5 rows, both FLIPs and both PERMUTEs — that row is *why* the arm
  must not be dropped, not why it is non-additive).
- **Is it one `case`? NO.** `order_arg`'s declared return is `List<&2, U32>`; the prescribed
  variant is `ABoolList{bs: List<&2, Bool>}`, and `flip_ds.put` (`:1880`) is typed
  `ys: List<&2, U32>`. So the arm must either carry a `List<Bool>→List<U32>` converter (a
  SECOND new def), or `flip_ds.put`/`flip_ds.of` must be re-typed to take a length. Either is
  **2–3 edits in `fold.bend`, not one line.**
- **The safer shape does NOT touch `order_arg` at all**: a new `flip_len(arg) -> U32`
  (`ATuple→List.length`, `ABoolList→List.length`) used only by `flip_ds`. That removes even the
  theoretical shared-function risk — and shows the brief's "add the `order_arg` arm" is one of
  two shapes, not the shape.

**So the brief's own precondition ("one `case`, additive") is half-true: additive YES, one
`case` NO.**

---

## 2. RE-VERIFIED BLAST RADIUS — **9 files**, not two

Measured by discovery (§7 `blast.py`, `os.walk` over `tinybendygrad/**/*.bend`, doctrine 1 — no
hand list), classing every `OpsFLIP{}` **construction** (`:NNN` = `UOp.new`/`.new` on the same
line), every `O.Arg`-taking def whose body arms on `O.ATuple` (**reader**), and every
`case O.OpsFLIP` (**dispatch**):

```
TOTAL construct=4  reader=9  dispatch=3  tokenlist=29
FILES constructing or reading a FLIP arg: 9
  mixin/movement.bend        construct 993,1533   reader 545
  schedule/prepare.bend      construct 277
  uop/fold.bend              construct 5325       reader 1852,2097   dispatch 2358,4067
  uop/movement.bend                                reader 192
  uop/render.bend                                  reader 722
  uop/spec.bend                                    reader 461         dispatch 1184
  uop/upat.bend                                    reader 412
  uop/validate.bend                                reader 2586
```

Plus the HARNESS `.agents/slop/graphcmp.bend` (`g_flip:1340`, `argstr:453`). **Two files is
false by a factor of five.** A faithful change is:

| file | edits | why |
|---|---|---|
| `uop/ops.bend` | +`ABoolList{bs: List<&2, Bool>}` in `type Arg` (`:1208`); +`eq_arg.ABoolList`; +`eq_arg.sel` arm; fix the `:1144` table | the variant + the key |
| `uop/render.bend` | +`arg_repr` arm (`:722`) | `repr((True,False))` = `(True, False)` |
| `uop/upat.bend` | +`arg_int` arm (`:412`) | exhaustive match, no `_` |
| `uop/fold.bend` | +`order_arg`/`flip_len` arm; retype or convert | **THE BLOCKER** |
| `mixin/movement.bend` | `arg_tuple` reader (`:192`), `G.flip` (`:993`), `mxw_flip_new` (`:1533`) | the live `Tensor.flip` path |
| `schedule/prepare.bend` | `pr_flip` (`:277`) — **live**, called at `:773` | the real PM FLIP constructor |
| `tensor.bend` | `tn_mop.order` must branch on `op` (`:950`); `t_mop_flip` (`:1691`) | shared PERMUTE+FLIP constructor |
| `uop/spec.bend` | `arg_tuple` reader (`:461`), `te_7` (`:1647`) | SPEC layer |
| `graphcmp.bend` | `g_flip` fixture (`:1340`), `argstr` arm (`:453`) | the differ row |

**Why NOT the minimal 5-file version.** One could add the variant + arms + change only
`graphcmp.bend`'s `g_flip`, leaving the real constructors (`pr_flip:277`, `G.flip:993`,
`mxw_flip_new:1533`, `tn_mop.order:950`) spelling FLIP as `ATuple`. That COMPILES and would make
`diff --graph flip` read `AGREE` — **and it is a rigged fixture**: the differ would no longer
model what the port's own `Tensor.flip` builds. That is the mirror of `flipbool`'s warning
("making both sides `i` would be rigging a real port gap"): a gate that agrees on a fixture the
port cannot produce is worse than no gate. **The fixture must not be repointed without
`prepare.bend:277` and `tensor.bend:950` following it.**

**And the concurrent-edit hazard is real:** `git status` shows `tensor.bend` is MODIFIED in the
working copy (`git diff` = a new `tn_where`, unrelated to FLIP) and its mtime is `Oct 7 05:34`,
minutes old. `tensor.bend:950` is squarely in my blast radius. Editing it now collides with a
live unit.

---

## 3. THE REFUSAL — two files, three edits each, and the smallest unblock

**The two files the brief is asking about:**

**`uop/ops.bend` (owned, but only useful WITH `fold.bend`):**
1. `:1208` after `ATuple{ys: List<&2, U32>}` add `ABoolList{bs: List<&2, Bool>}`;
2. `:2053` add `def eq_arg.ABoolList(y, +bs: List<&2, Bool>)` (`eq_bool_list`, `eq_bool` exists at `:1616`);
3. `:2154` add `case ABoolList{bs}: eq_arg.ABoolList(y, bs)` in `eq_arg.sel`.
   (+ `render.bend:722` and `upat.bend:412` are one-line compile arms with no `_`.)

**`fold.bend` (DO-NOT-TOUCH — another unit's):**
1. `:1850` the `order_arg`/`flip_len` arm for `ABoolList` (with a `Bool→U32` converter, or a
   length-only reader that leaves `order_arg` alone);
2. `:1880` `flip_ds.put` (and `:1883` `flip_ds.of`) re-typed if the length-only route is taken;
3. `:5325`/`:6154` the fold unit's own FLIP fixture/row, if the port's spelling changes.

**SMALLEST THING THAT UNBLOCKS: one arm in `fold.bend` teaching `flip_ds` an `ABoolList`
flag-list (or its length) — nothing else is a hard dependency of the FOLD.** Given that, the
remaining work is mechanical but is **8 more files**, and the honest version cannot skip
`prepare.bend:277` + `tensor.bend:950`. That is not a subagent edit under a no-concurrent-edit
rule with `tensor.bend` already dirty.

---

## 4. WHAT ONLY `bend` SETTLES — and what I established

The brief names three claims. **I established NONE of them, because I landed no edit:**

1. that `ABoolList{bs: List<&2, Bool>}` **compiles** — NOT established (it is a prediction;
   `device.bend:93` claims a `Bool` list is unusable, though `flipport` §3 measured four live
   `List<&2, Bool>` readers, so it is likely fine);
2. that `argstr` renders `n(b1,b0)` — NOT established (the `b` atom is `graphcmp.py`'s `ATOMS`
   `bool→"b"`, `graphcmp.bend:89-90` `bo`; correct, but unrendered);
3. that `diff --graph flip` returns `AGREE 6/6` — NOT established. The **BEFORE** IS established
   from the last run: `runs/graphcmp/D/D1-graph-flip.txt` reads `VERDICT: DISAGREE`.

`bend` is **FREE** (no compiler process; `ps` shows none), but I did not consume it: there is no
edit to test, the `BREAK`/`AGREE` verdict is already recorded on disk, and the brief reserves
`bend` for two other units.

---

## 5. THE DENOMINATOR — PIN = 2, and FLIP is NOT "one edit" away

`.venv/bin/python .agents/slop/flipbool/pin-census.py` loads the generator's own `PIN`
(`checks/disagree-gate.py`, doctrine 1 — no second copy):

```
# PIN rows (the generator's own declaration, loaded by path): 2
#   flip       row=6   shape=BOTH         fault=HARNESS+PORT
#   unshard    row=8   shape=WRONG SHAPE  fault=PORT
# UN-DIAGNOSED (shape BOTH or fault names HARNESS): 1 ['flip']
```

`flipbool`'s fresh static census (`corpus-argscan.py`, 34+34 canonical files, field 6 = `arg`):

```
py   FLIP kinds=(b,b) n=1     bend FLIP kinds=(i,i) n=1     TOTAL tuple-args=13 (both sides)
```

**13 tuple-args/side; exactly ONE carries `b` (py FLIP) vs the port's `i`.** `flipbool`'s "the
missing guard is width 1, not 13" is about the GUARD (`ops.py:428`'s `isinstance(x, bool)` —
the other 12 ops have no element-TYPE guard upstream), **not about the FIX SIZE.** The one
guarded op needs a NEW `Arg` kind, and a kind cascades to **9 files**; the other 12 need
nothing.

**So: FLIP is the only ARG-KIND-closeable disagreement, and it is NOT one edit away.**
`unshard` (`shape=WRONG SHAPE`) is a separate **~680-line relocation** (`unshardtable`, refused
on the same `fold.bend` order rule). There is **no third mystery and no one-edit op.** The
project carries **one known ~9-file vocabulary change (FLIP) and one known ~680-line relocation
(unshard)** — not two mysteries, and not two one-liners.

---

## 6. PLANT — not produced (nothing landed)

Item 6's plant is conditional on landing. What a landing MUST show, and why the brief's
PERMUTE check is the right blast-radius probe:

- **`flip` DISAGREE before → AGREE after** (`runs/graphcmp/D/D1-graph-flip.txt`: `n(i1,i0)` vs
  `n(b1,b0)`). BEFORE is on disk; the AFTER would require a `bend` run.
- **A PERMUTE whose guard is a VALUE guard still agrees.** PERMUTE's guard is
  `sorted(marg)==range` (a VALUE test on ints, `fold.bend`'s `perm`), NOT a type guard, so it is
  the op a shared-`order_arg` change could move UNTESTED. The `M12` row (`fold.bend:6683`)
  already MEASURES that emptying `order_arg` moves both PERMUTEs and both FLIPs — i.e. the
  shared reader is exactly where the risk lives, and PERMUTE is the control. **A landing that
  does not re-run `mv_perm`/`mv_permrep`/`mv_permlen` has not shown its blast radius.**

Because the honest landing is 9 files and 2 of the constructor repoints are outside my scope,
**the plant is not producible from this unit without rigging the fixture — which is the one
thing rule 3 forbids.**

---

## 7. INSTRUMENTS

- `.agents/slop/flipblock/blast.py` — the 9-file radius, by `os.walk` + write-site regex
  (doctrine 1). Output `.agents/slop/flipblock/blast.rows`.
- `.agents/slop/flipbool/corpus-argscan.py` (prior unit's, re-run) — 13 tuple-args, 1 bool.
- `.agents/slop/flipbool/pin-census.py` (prior unit's, re-run) — `PIN` loaded by path, = 2.
- `runs/graphcmp/D/D1-graph-flip.txt` — the standing DISAGREE.
- `git status` / mtimes — `fold.bend`, `render.bend`, `upat.bend` clean; `tensor.bend` DIRTY
  (`tn_where`, unrelated) and 05:34.

## 8. VERDICT

**`REFUSED` (measured), tree untouched.** `FLIP`'s `Arg` is the last corpus defect with a single
named blocker line (`fold.bend:1850` `order_arg`), but the arm is **additive in control flow and
NOT one case**, its file is **explicitly forbidden to me**, a faithful landing is **9 files**
not two, and one of those (`tensor.bend:950`) is **dirty under another unit right now**. Taking
only the owned edge would make `diff --graph flip` agree on a fixture the port's own
`Tensor.flip` cannot build — a rig, not a fix. **The smallest unblock is one `fold.bend` arm
(`order_arg`/`flip_len` for `ABoolList`); the smallest HONEST unblock additionally owns
`schedule/prepare.bend:277` and `tensor.bend:950`, and waits for `tensor.bend` to be clean.**
