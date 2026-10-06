# armfour REPORT — the four graphs behind `g_matmul()`, armed and measured

Unit: `.agents/slop/graphcmp.bend`'s `rows.pick3` dispatcher and the four builders it lacked:
`custom_function`, `mselect`, `mstack`, `stage`. Read `AGENTS.md`: populations by DISCOVERY, and
`SKIP`/`DEAD`/`REFUSED` are not passes.

**`bend` WAS RUN — by this unit, alone.** Every verdict below is a measured `bend` run under
`checks/bounded.py`, plus the CPython side of the same graph, and the differ's own row-for-row
verdict. The VERDICT TOKEN is the `[bounded]` line's; peak RSS is BIMODAL (median 207,
`hw.memsize` 16,384) and these four are all ≤ 698 MB, so no run was parallelised and none was needed.

**Files I edited (1): `.agents/slop/graphcmp.bend`** (four builders `:1499`/`:1512`/`:1526`/`:1542`,
four rungs in `rows.pick3` `:1556`). I did NOT touch `checks/`, `gates/`, `AGENTS.md`,
`tinybendygrad/`, `runs/`. I did not commit, `git add`, or `@` anyone.

---

## 1. Per graph — the py builder, the ops it reaches, and whether a bend arm was writable

Each py builder is in `.agents/slop/graphcmp.py` (`GRAPHS` at `:1591-1600`). The spec is not the
docstring — it is `emit --side py --graph NAME`, and the py rows are quoted from it.

| graph | py builder | what it builds | ops reached | nodes py | writable with existing port builders? |
|---|---|---|---|---|---|
| `custom_function` | `graphcmp.py:1553` | `UOp.custom_function("myfn", Tensor.empty(4,3).uop)` | CUSTOM_FUNCTION | 6 | **YES** — `O.UOp.custom_function` (`ops.bend:5295`) is the port's own ctor |
| `mselect` | `graphcmp.py:1562` | `Tensor.empty(4,3).uop.copy_to_device(("CPU","CPU")).mselect(0)` | MSELECT, COPY, RANGE | 9 | **YES** — `O.UOp.copy_to_device` (`:7636`) mints the range, `O.UOp.mselect` (`:4560`) |
| `mstack` | `graphcmp.py:1571` | `UOp.mstack(a.uop, b.uop)` over two `Tensor.empty(4,3)` | MSTACK | 8 | **YES** — `O.UOp.mstack` (`:2733`) |
| `stage` | `graphcmp.py:1582` | `(Tensor.empty(4,3) + 1).contiguous().uop` | STAGE, ADD | 8 | **YES** — hand-assembled `O.UOp.new` with `O.ANone{}`; the port's STAGE ctor `UOp.bufferize` (`:4530`) answers `ABad{}`, not upstream's `None` |

**No port def is missing for any of the four.** `newgraphs` was right that "needs hardware" is the
wrong test; the same held here — every node is a constructor the port already has, and the two
disagreements below are in the port's *Arg model* and its *fold*, not its constructor surface.

## 2. The arms, and how `row`/`col` are laid out

Inserted BEFORE `rows.pick3` (a forward reference does not compile here — the same rule the three
`threegraphs` arms record) and each name added to the dispatch chain:

```
def g_custom_function() -> O.Found:   graphcmp.bend:1499   O.UOp.custom_function(.., "myfn", [i(r43)], S.void())
def g_mselect()        -> O.Found:   graphcmp.bend:1512   O.UOp.copy_to_device(.., None{}, S.Dn{[0,0]}) ; O.UOp.mselect(.., 0)
def g_mstack()         -> O.Found:   graphcmp.bend:1526   O.UOp.mstack(.., i(r0), [i(r1)])
def g_stage()          -> O.Found:   graphcmp.bend:1542   UOp.new(ad, OpsSTAGE{}, [i(ad)], ANone{}, TNone{})
dispatcher: rows.pick3  graphcmp.bend:1556   (was :1490; four rungs added before `g_matmul()`)
```

Construction order IS toposort order on both sides, so the arena indices line up and `src` matches
byte for byte where the atoms match.

## 3. THE MEASUREMENT — verdict token, row count, and the row-for-row diff

`bend` command (each graph, serial):

```
.venv/bin/python checks/bounded.py --seconds 300 --mb 2048 -- ./bin/bend .agents/slop/graphcmp.bend <graph>
.venv/bin/python .agents/slop/graphcmp.py diff --graph <graph>          # CPython vs the arm
```

| graph | bounded TOKEN | peak RSS | rows py/bend | differ VERDICT | first differing row |
|---|---|---|---|---|---|
| `custom_function` | `WITHIN-LIMITS` rc=0 | 698 MB | 6 / 6 | **AGREE** | — |
| `mstack` | `WITHIN-LIMITS` rc=0 | 628 MB | 8 / 8 | **AGREE** | — |
| `mselect` | `WITHIN-LIMITS` rc=0 | 644 MB | 9 / 9 | **DISAGREE** | `MSELECT py#9 vs bend#9  arg py=i0 bend=y n(i0)` |
| `stage` | `WITHIN-LIMITS` rc=0 | 550 MB | 8 / 8 | **DISAGREE** | `STAGE py#8 vs bend#8  dtype py=f32 bend=?` · `shape py=(l0:4,l0:3) bend=?` |

`custom_function` and `mstack` are `AGREE` — the port builds those two graphs exactly. The two
disagreements are the finding, and they are TWO DIFFERENT classes, neither of them `allred`'s.

## 4. What the two DISAGREEing graphs mean

**`mselect` — `WRONG VALUE` on one `arg`: a PORT ARG-REPRESENTATION gap.** Upstream's `mselect(arg:int)`
(`tinygrad/uop/ops.py:769`) holds a Python **int**; the differ's generic int grammar renders it
`i0` (`graphcmp.py` `_carg`, `ATOMS["u32"]=="i"`). The port types `mselect`'s arg as a ONE-BYTE
`ABlob{[k]}` (`tinybendygrad/uop/ops.bend:4560`), whose renderer is `blobstr` → `y n(i0)`
(`graphcmp.bend:385`). So the port CAN tell shard indices apart (the comment at `ops.bend:4554`
says so), but it spells a *number* as *bytes*, and the normal form cannot match. **This is the
`?`-class WALL the port itself wrote down: `ops.bend:4554` `WALL(p3) ops.py:201 -- BLOCKED ON A
CASE THAT HAS NOT ARISEN, ... IF A LATER UNIT MUST TELL AN `int` FROM A `bytes` ON ONE NODE,
that is a NEW `Arg` arm`.** THIS GRAPH IS THAT CASE — the trigger has arisen. Class:
data-model spelling, same family as `flip` (`tuple[bool]` vs `ATuple[u32]`) and `wmma` (`None` tc),
NOT the same as `allred` (§5).

**`stage` — `WRONG SHAPE` on TWO fields: a PORT FOLD gap.** Upstream settles STAGE on both columns:
dtype passes through `src[0].dtype` (`tinygrad/uop/ops.py:148-152`) and shape is
`tuple(r.vmax+1 for src[1:]) + src[0].shape` (`ops.py:376-378`) → `f32`, `(4,3)`. The port's
`dt_shape` (`tinybendygrad/uop/fold.bend:2282`) has the passthrough arm for `MSTACK`/`MSELECT`
(`:2350-2351`) but STAGE falls to a bare `case O.OpsSTAGE{}: None{}` (`:2431`), so BOTH columns are
unsettled and the emitter prints `?` (`graphcmp.bend:518`/`:544`). `bend` reports
`settled=False`. This is the same class as the historical `sym`/`loop`/`bw` `?` rows, and it
reactivates the differ's `?`-ledger prose, which now reads:

> `graphcmp.py:2178` **"NO LIVE FIXTURE ANY MORE"** … `sym`, `loop` and `bw` ALL read `?=0`

`stage` reads `?=0/2`, so **that sentence is stale as of this run** — `stage` IS a live fixture for
the `?` ledger again. (Reported, not edited: `graphcmp.py` is the differ, outside this grant.)

## 5. Are the disagreements `allred`'s class? — NO

`allred`'s cause was the **device-tuple NORMAL FORM** (`adevfix` REPORT: a union rendered by TWO
renderers — `dev` flattened, `_carg` nested — one value, two spellings; `PIN` `allred` is
`WRONG VALUE` `arg` at row 8, and the fix lands in the RENDERER, not the port). `mselect` and
`stage` are neither:

- `mselect` is the PORT's `Arg` model (`ABlob` standing in for an int), on ONE node — not two
  renderers of one value, and no renderer change can fix it.
- `stage` is the PORT's FOLD (`dt_shape` has no STAGE arm), on TWO columns of ONE node — upstream
  settles it, the port does not.

Both are the same *shape* of finding as the rest of the corpus (a port spelling/shape gap the
substitution had hidden), but they are three distinct defects. Two graphs disagreeing the same way
would be one defect; these do not.

## 6. Gate deltas — `file:line`, old/new, **NOT EDITED**

The brief's line numbers (`:80 SUBSTITUTED`) are stale: the gate has since been reworked. Measured
today:

| file:line | now | what my change does | needed |
|---|---|---|---|
| `checks/disagree-gate.py:104` `CITES` | `(".agents/slop/graphcmp.bend", 1490, "def rows.pick3", ...)` | **BREAKS**: moving `def rows.pick3` from `:1490` to `:1556` (4 arms + comment, +66 lines) makes this line read a comment. Verified: `--lane citations` FAILs with `.agents/slop/graphcmp.bend:1490 -- reads '# the three arms above just closed...'`, expected `def rows.pick3` | repoint **1490 → 1556** |
| `checks/disagree-gate.py:58` `ARMED = ("allred","cdiv","late")` | a 3-name HAND LIST | **moves NO row**: `arms_wired` (`:219`) only asserts the three; my four arms are invisible to it. `custom_function`/`mstack`/`mselect`/`stage` are in the dispatcher and asserted by nothing | derive `ARMED` from `names.py:dispatcher_substitutions` (`:249`) — the ARMED set is `GRAPHS` keys MINUS the derived substituted set |
| `checks/disagree-gate.py:99` `SUBSTITUTED = ()` | `()` | **moves NO row**: my four arms add no one-sided op | already correct — and now DERIVED: `names.py --json` reports `substituted: []` |
| `checks/disagree-gate.py:321` `SUBSTITUTION_ARTEFACTS = {}` | `{}` | **moves NO row**: the `coverage` lane (`:325`) derives `one_sided`; both sides reach MSELECT and STAGE (`1/1`), so the set stays empty | already correct |
| `runs/graphcmp/D/D0-run-summary.txt` | STALE (25 graphs) | after a fresh `differ.py run`: `mselect`+`stage` DISAGREE, so `names.py`'s `disagree` grows by two and `lane_pin` (`:142`) `named != sorted(PIN)` FAILS unless `PIN` (`:70`) gains two entries | add `mselect`/`stage` to `PIN` and set `graphs-disagree = len(PIN)` |

**THE FINDING, stated as the brief asked: the gate cannot see this fix through its own hand list.**
`ARMED` (`:58`) names three graphs by hand; the by-DISCOVERY instrument already exists and agrees
with me — `names.py:dispatcher_substitutions` (`:249`) derives the substituted set from `GRAPHS`
and the dispatcher text, and with these four arms it returns **`[]`** (measured:
`.venv/bin/python .agents/slop/disagree/names.py --json` → `substituted: []`). `ARMED` should be
that derivation's complement, not a literal tuple. I did not widen either list.

**The one thing only a fresh `checks/differ.py run` settles:** whether `PIN`'s re-measured
`allred` row (8) and the two new `mselect`/`stage` rows are the exact first rows the differ names
(belt 1 and belt 2 must agree). I did not run `differ.py run` (it rewrites `runs/`, outside this
grant).

## 7. Handoff

1. Repoint `checks/disagree-gate.py:104` `1490 → 1556` — the ONLY gate row my edit breaks.
2. Replace `ARMED` (`:58`) with the derived complement of `dispatcher_substitutions`.
3. Run `checks/differ.py run` (needs `bend`, serially), then re-derive `PIN` + `graphs-disagree`.
4. If `stage`'s `?` is to be closed: add a STAGE arm to `dt_shape` (`fold.bend:2431`) — dtype
   passthrough `src[0]`, shape `()` + `src[0].shape` via a second walk (upstream's rule needs
   `vmax` only when `src[1:]` is non-empty; this node has none). If `mselect`'s `arg` is to be
   closed: that is a new `Arg` arm in `ops.bend` (a U32/int arm), per its own WALL note.

**Files this unit wrote:** `.agents/slop/graphcmp.bend` (four builders `:1499`/`:1512`/`:1526`/`:1542`,
four dispatcher rungs `:1556`), `.agents/slop/armfour/REPORT.md`.
`md5(.agents/slop/graphcmp.bend) = ceb1d2f4a910bdcb06f838b37d7b31ae`.
