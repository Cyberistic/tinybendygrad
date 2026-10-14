# opsfind — FINDINGS A, B, C, E, F of `gates/ops_python_census-gate.py`

**Measured 2026-10-13. Every reading below is a command that ran; the scripts that
produced them are `mutate.py` (the port's lane, planted) and `checks.py` (the gate's
own text checks, planted). Both restore the port in a `finally`, so a plant never
survives them. Raw output: `mutate.out`, `checks.out`, `gate.out`.**

**FINAL: `gates/ops_python_census-gate.py` rc=0, 85 rows x 3 lanes, 85 exact, 0
pinned, all 10 checks OK** (`gate.out`). The 85 row NAMES did not change; `names_hold()`
still derives both populations independently.

## FINDING A — EIGHT ROWS PRINTED A CONSTANT. CLOSED.

`literal_rows()` re-derives the population by parsing each row's value expression. It
answered EIGHT; it now answers `[]`, and `literal_rows_hold()` pins the empty set.

| row | read BEFORE | read AFTER | the input it reads |
|---|---|---|---|
| `pywma_metal_dims0` | bare `8` | `Core.d0(METAL_CORE(0))` | `tc.metal[0].dims[0]` |
| `pywma_metal_threads` | bare `32` | `Core.threads(METAL_CORE(0))` | `tc.metal[0].threads` |
| `pyc_is_b64decode` | `compile.is_b64decode()` -> `True{}` | `compile.is_b64decode(compile.transform())` | the transform `compile` applies |
| `pyc_refused` | `Bool.not(...True{})` | `Bool.not(...same call...)` | the same input, negated |
| `pyd_ctor_len` | bare `4` | `U32.from_nat(List.length(&1, U32, DEV_ARGS()))` | ops_python.py:186's argument count |
| `pyd_ctor_allocator` | `DEV_ALLOCATOR()` == the position | `DEV_POS(DEV_ALLOCATOR())` | the ctor's ORDER |
| `pyd_ctor_renderers` | `DEV_RENDERERS()` == the position | `DEV_POS(DEV_RENDERERS())` | the ctor's ORDER |
| `pyd_ctor_runtime` | `DEV_RUNTIME()` == the position | `DEV_POS(DEV_RUNTIME())` | the ctor's ORDER |
| `pyd_nrenderers` | bare `1` | `List.length(..., DEV_RENDERER_CLASSES())` | the renderer list ops_python passes |

**Where the port already HAD those inputs.** It had both axes, and the fix is to make
the rows read them instead of re-typing them:

* `METAL_CORE(din) -> Core` is ONE declaration of `tc.metal[0]`, and the four
  `core_find` fixtures now build their cores from it. Before, the SAME numbers
  (`8,8,8` and `32`) sat unreferenced in the `Core{...}` the lookup rows were given,
  while the two rows printed their own copies. This is the `al_shift_of` shape from
  this session's own history: two correct constants, dead beside a caller that had
  its own.
* `DEV_ARGS() -> List<&1, U32>` is ONE declaration of
  `super().__init__(device, HostAllocator(self), [PythonRenderer], PythonProgram)`
  in CPython's order, and the rows SEARCH it (`DEV_POS.go`) rather than carrying a
  position. The tags moved from `0/1/2` to `10/11/12/13`: they were DEFINED to equal
  the positions, which is precisely why they were constants wearing a row's clothes.
  A tag can no longer be a position by accident.
* `compile.transform()` and `b64.transform()` are declared SEPARATELY and the row
  compares them, so a rename on either side moves BOTH `pyc_*` rows from one edit.

**THE WEAKEST OF THE EIGHT, STATED PLAINLY.** The oracle decides `pyc_is_b64decode`
empirically: `B64_HOLDS` CALLS `compile` on eight fixtures and compares the BYTES.
The port CANNOT — the quartet fold is WALL 5, a real and unfinished wall whose first
draft produced plausible-looking hex and was wrong on every non-trivial input. So the
port's row is a DECLARED identity where the oracle's is a measured one. The port's
header now says so in those words, and the gate's header says which side is which,
so a green run cannot be read as "the transform was verified here". It was not.

### Mutation readings (`mutate.out`)

| plant | BEFORE | AFTER |
|---|---|---|
| A1 tc.py widens the metal FRAGMENT 8->16 on the core the LOOKUP uses | **moved 0/1 NOTHING** | moved 1/1 `pywma_metal_dims0: 8 -> 16` |
| A2 the metal fragment gets 64 THREADS | **moved 0/1 NOTHING** | moved 1/1 `pywma_metal_threads: 32 -> 64` |
| A3 ops_python.py reorders the ctor | no input to move — the BEFORE file declares no ORDER; the positions ARE the tags | moved 2/2 `allocator 0->1`, `renderers 1->0` |
| A4 ops_python.py drops a ctor argument | no input to move — `4` was a bare literal, so `3` is as writable as `4` | moved 4/4 `len 4->3`, `allocator 0->2`, `renderers 1->0`, `runtime 2->1` |
| A5 ops_python.py names a SECOND renderer | no input to move — `1` was a bare literal | moved 1/1 `nrenderers 1->2` |
| A6 `base64.b64decode` is renamed | no input to move — one literal and nothing to COMPARE it against | moved 2/2 `is_b64decode True->False`, `refused False->True` |

A1 and A2 are the readings that matter: BEFORE, moving the fragment the lookup
actually consumes moved NOTHING on the two rows that claim to describe it, and the
gate stayed green. A3/A4/A5 have no BEFORE reading because there was nothing to
move — a row that IS its own literal has no input, which is the finding.

## FINDING B — THE HEADER DENIED TWO ROWS THAT EXISTED. CLOSED.

`ops_python.bend:2374` read "A row that disagrees with CPython is a row that encodes
a bug, so there are NO `pyc_*` rows here at all", 285 lines above the two rows that
disclaimed. The header now says there ARE two, says which is which, and says that
the port's is the weaker identity. `pyc_rows_hold()` now requires the disclaimer to be
GONE (its return is a stale finding, not a new one) and the two rows to still be the
two that are printed. **Reading:** unplanted OK; with the sentence re-inserted,
`pyc_rows_hold: RED -- the header disclaims the pyc_* rows AGAIN -- finding B is back`.

## FINDING C — TWO DEAD DEFS. CLOSED, BY DELETION, NOT BY WIRING.

`grep -c` answered 1 for each before the work: each was its own definition and no
call site. **Neither was wired, and the reasons differ:**

* **`B64_EQ() -> U32: 61`** — residue of a base64 alphabet whose decoder was
  abandoned mid-file. The decoder is WALL 5 and is not coming back inside this unit,
  so there is no reader to wire it to. DELETED.
* **`prog.init(us) -> List<&2, U32>`** — it returned `Nil{}`. It built NEITHER of the
  two maps its own comment described (`uop_to_index` and `loop_ends`), so it was not
  an unused implementation of a rule; it was a stub with a comment. Its comment was
  load-bearing for Finding F, which is why deleting it needed the check below rather
  than a shrug. DELETED.

**Readings** (`checks.out`): unplanted `dead_defs_hold: OK`; with `def B64_EQ() -> U32: 61`
back in, `RED -- B64_EQ has 1 mentions, expected 0`; with `def prog.init(...)` back in,
`RED -- prog.init has 1 mentions, expected 0`.

**REGRESSION GUARD for A** (`checks.out`): with `pyd_ctor_len` reverted to a bare `4`,
`literal_rows_hold: RED -- 1 row(s) print a constant again: ['pyd_ctor_len']`.

## FINDING F — CHECKED, NOT ASSUMED. **THE ARM IS SOUND, AND DELETING THE DEAD DEF DID NOT INVALIDATE IT.**

The claim was that `case O.OpsEND{}: Prog.at(p, Uop.src1(u))` agrees with
`i = self.uop_to_index[u.src[1]]` only because a def nothing called said so. It went
the other way, and the evidence is live code on BOTH sides:

* `ops_bend.encode` builds `idx = {u: i for i, u in enumerate(uops)}` (ops_bend.py:135)
  — the SAME comprehension as ops_python.py:49 — and writes `str(idx[s]+1)`
  (ops_bend.py:142). So the wire's `<src>` field IS `uop_to_index[src] + 1`, which
  `Uop.of.sr` subtracts ONE FROM, ONCE, FOR EVERY SRC.
* **MEASURED** on a real `encode` output: the wire field equals `uop_to_index[src]+1`
  for every src of every uop, and on the END line the port's pc (2 - 1) equals
  `uop_to_index[END.src[1]]` (1).
* It is not an END special case: `Prog.src` and `Prog.slot` read every other src the
  same way, which is why `Prog.val`'s END arm could not be the only thing at risk.

So deleting `prog.init` REMOVED a false witness rather than removing a real one, and
the comment that carried the true claim now lives at `Uop.of.sr`, beside the code
that does the resolution, and names the encoder's line. **Still not reached by any row
in this census** — the END arm is exercised by the executor lane, not the fixture lane.

## FINDING E — REPORTED, NOT FIXED. THE STRONGER CLAIM IS KEPT.

CPython's :155 is `assert u in values, u`, a PER-DISPATCH check. The port's catch-all
`case _: Prog.alu(p, u)` has no guard, which would be a silent wrong answer — except
that `op_of` has no `BINARY`/`CALL`/`WMMA`/`CUSTOM_FUNCTION` arm, `Uop.of.op2` leaves
the op unparsed, `Uop.refused` is `kind >= 14`, and `Prog.one.no` sets `ok = False`,
all BEFORE the arena is walked. A parse-time refusal of the whole program beats a
per-dispatch assertion. It is deliberately not weakened. `interpreter_hold()` now
re-measures all FOUR links (it previously measured two). **Readings** (`checks.out`):
with `case "BINARY": Some{O.OpsBINARY{}}` added to `op_of`, `RED -- op_of now has a
"BINARY" arm, and Prog.dispatch has no case for it`; with `Uop.refused`'s threshold
moved to `13`, `RED -- Uop.refused is no longer 'kind >= 14' -- the parse-time refusal
the catch-all's safety rests on has moved or is gone`.

## THE COVERAGE GAP — NOT CLOSED, AND THE BLOCKER IS AN INSTRUMENT, NOT A FIXTURE LIST

`PythonProgram.__call__` (ops_python.py:52-157, 106 of 186 lines, 57%) has no rows.
Closing it would need a lane that turns a v1 packet into real `UOp` objects, and the
only reader of that wire in the tree stops where the uops begin: `ops_bend.parse`
"only recovers the shape BendProgram needs to marshal buffers, which is why it stops
at op names and index lists". Writing a wire -> `UOp` decoder inside this oracle is
the reimplementation the oracle exists to avoid, and a hand-listed fixture set is
what `AGENTS.md`'s doctrine 1 forbids. **What it would take:** a second census whose
fixture population is a GENERATOR THAT RUNS — `ops_bend.encode` over a rendered uop
list, with the CPython lane handed the same `UOp` objects through
`pickle.dumps`/`PythonProgram.__init__`, and the bend lane handed the packet it
produces — so the two lanes share ONE artifact that a generator minted and neither
side typed. That is a census of its own and it was not started here.

## FOUND AND NOT DONE

1. **SIX MORE SINGLE-MENTION DEFS, all older than this gate**, measured by parsing
   every `def` in the port and counting identifier mentions: `is_hspace` (:346),
   `word_at` (:360), `str_of` (:363), `hex_str2` (:405), `elemname` (:1357),
   `Uop.src0` (:745). `dead_defs_hold()` deliberately stays pinned on the two this
   finding named rather than generalised, because generalising it would be red for
   these six and fixing them is a different unit. `hex_str2`/`is_hspace`/`word_at`
   look like the same abandoned-decoder residue as `B64_EQ`; that is a reading of
   their names, not a measurement, and they were left alone.
2. **`pyc_is_b64decode` remains the weakest row** and no mutation can make it strong;
   only porting the quartet fold can, and that is WALL 5.
3. **Finding D is open** — see above.
4. The gate's docstring previously asserted "THE PORT STAYS BYTE-IDENTICAL. Not one
   line of `tinybendygrad/runtime/ops_python.bend` is edited by this unit." That
   stopped being true with the first edit and now reads as what is true: the port is
   the driver and is edited by this unit, while the 85 row NAMES are unchanged and
   `names_hold()` still derives both populations independently.