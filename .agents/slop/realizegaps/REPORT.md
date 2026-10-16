# REALIZEGAPS — the two open boxes of the entry of that name, measured and closed

## 1. WHAT THE ENTRY ACTUALLY SAID, AND WHICH TWO OF ITS THREE BOXES THESE ARE

`.agents/TODO.md:14341` is `## REALIZEGAPS — three gaps in realize_graph_census's OWN instrument
(2026-10-13)` and its three open boxes are, **quoted**:

    - [ ] **`kern` COMPARES A COUNT WHERE THE THINGS ARE NAMES.** The port returns device *table indices*
          and CPython returns device *names*. **A WRONG INDEX WITH THE RIGHT COUNT IS INVISIBLE**, so a
          row that claims to test `kern` cannot fail on the thing most likely to be wrong. MEASURED and
          NOT FIXED. Needs the driver to print the resolved NAME, not `len`.

    - [ ] **`Arg` PAYLOADS DO NOT PRINT**, so a `ParamArg` slot and an `Estimates` are indistinguishable
          in every row. The op-sequence lanes already fixed this with an ` arg=` suffix (the `md_*` census
          did it first); this census did not inherit it.

    - [ ] **369 OF ITS 974 ROWS ARE `notacall`** -- 38% of the census carries no comparison. They are
          almost certainly load-bearing (they are why every lane's row count agrees), so CUTTING them is
          wrong and the real question is whether the census is honest about what fraction of itself it
          compares. `gates/tn_graph_census`'s footer answers a related question well ("the PIN is the
          MUTATION") and this census should answer its own in the same place.

**THE ENTRY'S OWN BOX 1 IS `kern`, NOT THE DRIVER AXIS, AND IT IS STILL OPEN.** Box 1 asks for
the resolved NAME and it is not what either the brief or the previous unit chased;
`REALIZEGAPS-SETTLED` (`:16227`) says so in the file's own words — *"**`TODO.md`'s
`REALIZEGAPS` BULLETS ARE ABOUT `Arg` PAYLOADS AND THE **369-OF-974** HONESTY FIGURE, NOT THE
DRIVER AXIS**"* — and `kern_blind_holds` already measures box 1's ceiling on both sides
(`Device.tag` does not exist in this tree's CPython; `device.bend:344`'s `tag_of` is a
three-valued sentinel; `schedule/memory.bend:999` disagrees with it and `uop/validate.bend:2532`
declines to arbitrate). **SO: BOXES 2 AND 3 ARE THE BRIEF'S TWO THINGS, AND BOX 1 IS NOT DONE
AND WAS NOT THIS UNIT'S TO DO.** What is new below is that box 1's blindness turned out to reach
**into the `arg` payload itself** — see §2.

**THE FIXTURE DID NOT MOVE.** MEASURED: the 65 `rs_x*` / `O.UOp.new` lines are byte-identical
to HEAD's, the census is still 1004 rows, and `arena_n` still reads 66. Everything below is a
PRINTER and its two guards. **AND THE ROW COUNT IS NOT A COINCIDENCE:** `ROWS[0]` is derived from
`DRV` x `NODES` and asserted by `drivers_hold`, `calls_hold` and the mutate harness's
`declared_rows()`, so a printer change that moved the population would have been caught rather
than adopted.

## 2. `Arg` PAYLOADS: THE SPELLING, AND WHY IT IS COPIED RATHER THAN INVENTED

**BOTH PRECEDENTS WERE READ, AND BOTH SPELLINGS ARE NAMED IN THE CODE:**

| precedent | what it prints | where |
|---|---|---|
| `gates/crp_graph_census.bend:189` / `-oracle.py:191` | `OP/NSRC[TARGET]` — the payload **inside** the token, gated on `isinstance(u.arg, DType)` | `tok.arg` |
| `gates/decomp_graph_census.bend:54` | `OP/NSRC[TARGET]`, same shape | same |
| `gates/md_graph_census.bend:104` | `arg=<dtype name>` appended, `-` for absent | `md_arg` |

**COPIED, NOT INVENTED: `OP/NSRC[PAYLOAD]`** — crp's and decomp's bracket, **because it travels
PER NODE**. md's ` arg=` suffix is on the census's ROOT, which is the right choice when a census
has one node per row (`md_graph_census`'s rows are single dtypes); this census's answer is a
**cone or a list**, so every node in it needs its own payload and a root-position suffix has
nowhere to go. The `-`-for-absent spelling is md's and is kept.

**THE TEST IS ON THE ARG, NOT THE OP** — crp's own stated reason (`crp_graph_census.bend:179`):
a fourth op that ever grows a `ParamArg` is printed by this and not by a list of ops that would
rot beside it. Twelve arms, one per `Arg` constructor the fixture uses (`ops.bend:1190`'s
twenty-four), plus the wildcard.

**THE TOKEN IS NOW ONE SHAPE.** `CONST(value)` is gone: a CONST's `arg` IS `APy{CInt}` and its
payload is its value, so `CONST/0[3]` is one arm of the same match and `rs_s1.go`'s `is_const`
Bool — which existed only because a `match` may not scrutinise a computed value — is deleted.

**THE ROW FORMAT IS UNAFFECTED, AND THAT IS CHECKED RATHER THAN ASSUMED.** `gatekit` parses a
lane by splitting on the FIRST `=`, and MEASURED: 0 of 1004 row KEYS contain a second `=`. The
31 values that do contain one are the pre-existing `beam_sig` `:b=` suffix, not the payload —
**no arm's payload contains `=`, `,` is already the cone's own separator, and `+` is already
the list's**, so the bracket adds no new delimiter into either.**

### The projection, per arm, and what it CANNOT distinguish

| arm | payload | what it catches |
|---|---|---|
| `ANone` | *(nothing)* | — |
| `ADt` | `i32` | a BITCAST's target dtype |
| `APy` | the const value | a bound value that is the wrong one |
| `AParam` | `name:val` | a PARAM/BUFFER that is the wrong one; a bound vs unbound var of the same name |
| `ACall` | the call name | one CALL confused with another (15 of them printed `CALL/3`) |
| `AKernel` | `name:beam` | `k1`(beam 0) vs `k2`(beam 2) vs a bodyless SINK |
| `AProgram` | `vars;globals;outs;ins` | a PROGRAM with the wrong index lists or the wrong variable |
| `ACustom` | the function name | `validate` vs `encdec` |
| `ARange` | `d`+ids | the axis and its ids |
| `AStr` | the string | two different string args |
| `ABlob` | the byte values | two different byte payloads |
| `AInt` | the index | two different shard indices |
| `ADev` | *(nothing — see below)* | **nothing, and that is measured** |
| `_` | `[?]`, refused by `argkinds_hold` | a kind neither lane spells is a RED RUN |

**`ADev` PRINTS NOTHING AND THE REASON IS BOX 1'S REASON.** `Ops.GETADDR`'s arg is a DEVICE:
CPython's is `str|tuple[str,...]` and the port's is `ADev{S.D1{tag}}`. **MEASURED: printing it
anyway takes FIVE ROWS RED** (`arg_51`, `arg_63`, `beam_51`, `beam_63`, `res_51`) — `Device.tag`
does not exist in this tree's CPython, so there is no spelling both lanes have. `ParamArg.device`
is omitted for the SAME reason, which makes this **one fact at two sites**, and `kern`'s
`len()` is the third. **BOX 1'S BLINDNESS IS NOT ONE ROW: IT IS THE DEVICE, IN THREE PLACES, AND
THE `arg` PAYLOAD IS THE THIRD.**

**MEASURED, THE HOLE IT CLOSED.** `.agents/slop/realizegaps/collide.py` counts the fixture's own
node pairs that print identically:

    BEFORE   65 nodes -> 32 distinct tokens, 147 of the 2080 pairs INDISTINGUISHABLE
             15 CALLs as `CALL/3`, 7 PROGRAMs as `PROGRAM/1`, 3 SINKs as `SINK/0`,
             2 PARAMs as `PARAM/0@2`, 2 CUSTOM_FUNCTIONs, 4 LINEARs
    AFTER    65 nodes -> 60 distinct tokens, 8 pairs
             [11,30,34,56] PROGRAM/1[-;0,1;0,1]   [26,36] LINEAR/1   [27,58] LINEAR/2

**EVERY ONE OF THE EIGHT IS A PAIR WHOSE TWO ARGS ARE EQUAL** — the four PROGRAMs differ only in
`src[0]` (their SINKs carry different `KernelInfo`s) and the four LINEARs have `arg=None`. **So 8
is the FLOOR for an arg payload, and the name of the residual is `src[0]`, not the arg.** Printing
`src[0]` on every node would close them and is a different printer decision (an arity decision),
so it is named and not done.

### The mechanical check: the payload text is the ONLY thing inserted

`.agents/slop/realizegaps/beforeafter.py` compares the two HEAD lanes with the two new ones, and
the claim is not a diff count — it is per row:

    `skeleton(AFTER) == skeleton(BEFORE)`, where skeleton(AFTER) DELETES every `[...]` and
    skeleton(BEFORE) rewrites `CONST(v)` to `CONST/0[v]` and then deletes every `[...]`.

What is compared is the OP/ARITY SEQUENCE, ITS ORDER, every `@<slot>` VALUE, every separator and
every literal the payload does not own. **MEASURED:**

    rows per lane 1004 / 1004 / 1004 / 1004      rows ADDED 0, rows DROPPED 0
    py: 79 of 1004 rows changed; 0 changed by anything OTHER than payload text
    bd: 73 of 1004 rows changed; 0 changed by anything OTHER than payload text

**THE PINS FILE, THE SAME WAY:** 63 pins before, 63 after, **12 values changed, 0 by anything
other than inserted payload text**, and the row NAME set is byte-identical. `--refresh` reported
`63 divergences, 941 exact matches` — unchanged from HEAD.

## 3. THE 369-OF-974 FIGURE, RE-MEASURED AT 1004 ROWS

**RE-MEASURED, NOT CARRIED: 378, NOT 369.** The verdict line, `_compared()` and `compares_holds()`
all now read **378 = 9 CALL-only drivers x 42 non-CALL nodes**, so `compared = 1004 - 378 - 15 =
611`.

**THE +9 IS ARITHMETIC, NOT A CORRECTION, AND THE ARITHMETIC IS THE PROOF THE CROSS-CHECK IS
STILL RIGHT AFTER 30 NEW ROWS.** The 974 -> 1004 step is exactly two fixture nodes (64: the
multi-device BUFFER, 65: the CALL over it) x 15 drivers = **+30 rows**. Node 64 is a BUFFER and
node 65 is a CALL, so `NONCALL` went 41 -> 42 and `CALLS` went 22 -> 23, and 9 drivers x 1 new
non-CALL = **+9 refusals**. 369 + 9 = 378. `compared` 590 -> 611 = +21, which is +30 rows - 9 new
refusals. **All four numbers check.**

**THE CROSS-CHECK IS NOW MUTATED, WHICH NOTHING HAD DONE.** `compares_holds()` compares the
MEASURED refusal count off the lanes with the DERIVED one (`len(oracle.CALL_ONLY) * len(NONCALL)`,
`CALL_ONLY` loaded BY PATH). A cross-check that has never been seen to disagree is not a
cross-check, so `G37` drops one member of the oracle's `CALL_ONLY` — which changes the derived
number and not the measured one, because the lanes decide refusal from the node's OWN OP TAG.
**MEASURED: `compares_holds` goes RED on its own message.**

**THE TWO STALE NUMBERS ARE GONE FROM THE PROSE TOO.** The gate's docstring said "369 of the rows
are that" in one place and "the 41 NON-CALL nodes" in another, while its own header said 378 and
42. A verdict line and a docstring that disagree about the same count is the
`.agents/TODO.md:16227` shape in miniature.

## 4. ROWS ADDED, AND WHAT THEY CANNOT DISTINGUISH

**NO ROW WAS ADDED AND NO ROW WAS DROPPED.** The population is unchanged at 1004 = 15 drivers x
65 nodes + 15 bottom + 12 arm-coverage + 2 header, and the class membership is unchanged at 63
declared divergences over the same nine classes. **The payload changed 79 CPython row values and
73 port row values; it added nothing.**

**WHAT THE PAYLOAD STILL CANNOT DISTINGUISH, ALL OF IT MEASURED OR NAMED:**

1. **8 node pairs whose two args are equal** (§2): four PROGRAMs differing in `src[0]`, four
   LINEARs with `arg=None`. The floor, and the cause is `src[0]`.
2. **`ADev`, and so `ParamArg.device`** — a GETADDR or a buffer over the WRONG DEVICE prints
   identically (§2). Box 1's ceiling, at two more sites.
3. **`KernelInfo.beam`'s VALUE — `k2`'s non-zero beam, on the PORT lane.** The field is now
   printed (`SINK/0[k2:<beam>]` is the token) and **no port answer contains `k2`** — MEASURED
   `grep -c k2 bd.out` = 0 — so the beam a fixture SINK carries is still unreadable wherever it
   could matter. §5's `X5` is the measurement, and the cause is fixture reachability, not the
   printer.
4. **The RANGE arm (`rs_pay.ax`)** — a DEAD ARM on the port lane: `grep -c 'RANGE/' bd.out` is
   **0**. `Z4` measures it. The fixture's one RANGE is node 28 and no driver's ANSWER contains it.
5. **The `ACustom` arm** — a DEAD ARM **on the port lane only**: `CUSTOM_FUNCTION/` is 0 in
   `bd.out` and 7 in `py.rows`. `Z5` measures it. The two dead arms are the SAME FACT: an arg kind
   reaches a token only if some answer contains a node of that kind, and this fixture's answers
   contain neither.
6. **Nine of `ParamArg`'s thirteen fields**, and they are named at the arm: `dtype`, `size`,
   `vmin_vmax`, `multiple_of`, `addrspace`, `volatile`, `image`, `buffer`, `device`. The first
   eight are CONSTANT across all nineteen of this fixture's `ParamArg`s (every `dtype` is
   `dtypes.i32`; `addrspace` is GLOBAL on the eleven buffer args and ALU on the four var args), so
   printing them would have added width and no discrimination. **`device` is the ninth and is
   omitted for the reason in §2.**
7. **`KernelInfo.estimates`** — `ops.bend` DROPS the field (P5, `renderer/__init__.py:16`) and
   every SINK here carries `None` on CPython's side, so there is nothing on the port side to
   print. **This is the `Estimates` the entry's box 2 names**, and the honest answer is that the
   PORT CANNOT HOLD IT.
8. **`KernelInfo.applied_opts` / `opts_to_apply`, and `ProgramInfo`'s sizes** — `Nil{}`/`None{}`
   and `(4,1,1)/(1,1,1)` on every node of their kinds. Constant, so no discrimination.
9. **The SEVEN other CPython axes and the port's two bend-only ones** (`AXIS_REDUCE`,
   `AXIS_UNROLL`) — `rs_pay.ax` prints `d` or `-` for the whole set, which is `crp`'s `addrstr`
   shape for `AddrSpace`. With one RANGE in the fixture nothing here can be wrong, and that is
   why it is one Bool and not eight `case` arms.

## 5. MUTATIONS THAT MOVED ZERO ROWS, WITH THE CAUSE NAMED

**FULL SWEEP, FINAL: `.venv/bin/python gates/realize_graph_census-mutate.py` — 532 s wall,
largest child 1,658 MiB (1.62 GiB), harness steady state 33.2 MiB, 30 lane mutations + 41 guard
mutations. Baseline first: `gate rc=0, py rows=1004, bd rows=1004, pins data rows=63` and
`all 11 checks GREEN on the unmutated lanes`. Verdict: "21 of 30 lane mutations moved a row,
25 of 30 were CAUGHT, 1 declared VACUOUS, 5 found nothing, 5 GUARDS ANSWERED BY RAISING".**

| id | moved | cause |
|---|---|---|
| `Z4` `rs_pay.ax` (the RANGE axis) | 0 | **DEAD ARM / fixture coverage gap.** No row's answer contains a RANGE: `grep -c 'RANGE/' bd.out` = 0. The spelling is right and nothing asks. |
| `Z5` the `ACustom` arm | 0 | **DEAD ARM on ONE lane.** `grep -c 'CUSTOM_FUNCTION/' bd.out` = 0 and `py.rows` = 7. `get_call_arg_uops` drops `src[0]`, and VAL_BODY means the port answers a claim bit and builds no cone. Same fact as `Z4`: an arg kind reaches a token only if some answer contains a node of that kind. |
| `X5` `k2`'s beam 2 → 5 | 0 | **VACUOUS BY FIXTURE REACHABILITY, and I ALMOST RE-CLASSIFIED IT WRONG.** See below. |
| `V11`'s FIRST FORM | 0 rows, all 1004 VANISHED, `rc=3` | **A SEVENTH CAUSE: THE MUTATION DID NOT COMPILE.** It passed `rs_opt_str`'s own `String` back into `rs_opt_str`, which takes a `Maybe<&2,String>`. From outside, "did not compile" and "nobody reads it" are one line. |
| `V12`'s FIRST TWO FORMS | 0 rows, 1004 VANISHED, `rc=3` | **the same seventh cause**, and it nearly cost a LIVE arm the dead list: form (i) assigns a bare `String` literal (`cannot infer`), form (ii) feeds `rs_ids` an empty list, COMPILES, and **moves 2 rows** (`flat_27`, `val_27`). The arm is live and narrowly so. |
| `Z1`, `Z3` (pre-existing) | 0 | `va_1` is a DEAD DEF; `rs_cval`'s non-`CInt` arm is never taken. |

**AND THE PAYLOAD ARMS THAT DO MOVE, BECAUSE A PRINTER WHOSE ARMS ARE ALL DEAD IS NOT A
PAYLOAD:** `V11` (drop `ParamArg.val`) **61 rows**, `V12` (empty `globals;outs;ins`) **2 rows**,
`X4`/`X2` (fixture axes) unaffected in kind. **The payload is a 12-arm printer and MEASURED 10 of
its arms carry a row; the two that do not (`ARange`, `ACustom` on the port lane) are named
above with their cause.**

**`X5` IS THE FINDING IN THIS SECTION, AND MY FIRST PASS HAD IT WRONG.** I wrote the entry up as
"the payload un-vacuoused `X5` — 4 rows, all CPython" **before running the sweep**, from the
`val_24` cone on the py lane. **MEASURED: `X5` moves ZERO rows on BOTH lanes.** The printer
objection *is* answered — `SINK/0[k2:<beam>]` is now printed — and the mutation still finds
nothing, because **no port answer names `k2` at all** (`grep -c k2 bd.out` = 0 against 1 on
`py.rows`). The cause is FIXTURE REACHABILITY: `k2` is `cK2`'s body, `pm_beam`'s claim is
`beam == 0`, so every driver that would carry it either refuses it (a non-CALL) or answers `00`,
and `get_call_arg_uops` drops `src[0]`. **A printer that prints a field nothing READS is a
printer limit; a printer that prints a field nothing can REACH is a coverage gap, and the two
read identically.** It stays declared `VACUOUS` with the reachability reason, and closing it
needs a driver whose answer contains node 8 — a new row, and `ROWS = 1004` is asserted in four
places.

**`G36` WAS SILENT TWICE, FOR TWO DIFFERENT REASONS, AND BOTH ARE THE CLASS.**
1. Aimed at `rs_pay`'s `ACustom` arm — a DEAD ARM on the port lane, so the placeholder reached
   no row.
2. Aimed at the ORACLE's `ACustom` arm — a lane that does print `CUSTOM_FUNCTION/1[validate]`
   seven times — and still silent, because **phase 2 drives the checks on INJECTED LANE ROWS
   and never runs the oracle.** A source edit only reaches a check that RE-DERIVES its
   population from that source. Then, aimed at `arg_9`, it went red on `classes_hold` (which
   `and`-chains first) rather than on `argkinds_hold`. The shipped tamper puts `[?]` into
   `arm_MSELECT` — a row `no_bottom_value` reads only for `== 0`, so nothing else can speak
   first. **MEASURED: RED on `argkinds_hold`, with its own message.**
3. `G37` is the cross-check the brief asked about: MEASURED RED on `compares_holds` **and** on
   `axis_hold`, both with their own messages.

## 6. PEAK RSS AND RUNTIME, WITH THE TIMESTAMP

    gate, `2026-10-16`, AFTER `gatekit.py`'s in-flight edit landed:  rc=0, 17.57 s real,
      1,219,821,568 B maximum RSS (1.14 GiB)
    the same gate at HEAD (my baseline, before any edit):          15.85 s real,
      1,229,045,760 B (1.14 GiB)
    `bend --check-only gates/realize_graph_census.bend`:            0.99 s, 582,926,336 B
    `bin/bend gates/realize_graph_census.bend` (interpreted):       1.62 s, 721,207,296 B
    oracle only:                                                   1.9 s
    `--refresh`:                                                   1.89 s, 733,872,128 B
    the mutation sweep:                                             see §7

**QUOTED WITH THE TIMESTAMP BECAUSE THE TREE IS CONCURRENT.** The gate peaked at 1.14 GiB on both
runs here; `AGENTS.md` records an earlier run of this same tree at 1.648 GiB, and other units
were writing during both of mine.

## 7. `gates/gatekit.py` WAS BROKEN FOR PART OF THIS SESSION — AND IT IS NOT MINE

`Gate.run()` crashed on **every gate in the tree** with `NameError: name 'code' is not defined`
(gates/gatekit.py:503, `if (code, why := device_precondition(...)) != PASS:` — a walrus binds the
name, it does not unpack it into the comparison). That is another unit's uncommitted edit and
`gates/gatekit.py` is outside my grant, so **I did not touch it**; it was fixed under me within
the session and the gate then ran. I verified the FUNCTION is sound while the CALL SITE was not:
`gatekit.device_plant()` prints all five states and exits 0, and `device_precondition("CPU",
"CPU")` answers `(0, '')`. **REPORTED BECAUSE A GATE THAT CANNOT RUN IS NOT A GREEN GATE**, and
my own verification path (`.agents/slop/realizegaps/verify.py`, which does the lanes, the pins and
all ten checks by hand) is how I could tell my change was correct while `gate()` was unrunnable.

## 8. FOUND AND NOT DONE

1. **BOX 1 IS STILL OPEN** and its blindness is now at THREE sites, not one (§2). Closing it
   needs `Device.tag` or a port that holds a device NAME, and neither exists in this tree.
2. **THE 8 REMAINING INDISTINGUISHABLE PAIRS** need `src[0]` printed on every node — a decision
   about arity, not about args, and it would change every token again.
3. **`Z4`'s and `Z5`'s coverage gap** needs a fixture node whose kind reaches an ANSWER (a RANGE
   and a CUSTOM_FUNCTION in some driver's output). That is a new-node decision and `ROWS = 1004`
   is asserted in four places.
4. **`ProgramInfo.target`** is not ported at all (`ops.bend`'s comment), so the oracle's `target=`
   field is in no payload. Named, not printed.
5. **`res_63` STILL VANISHES UNDER THE PIN** and `pin_drift_holds` still runs the pin's code on
   every pass to keep saying so. `AGENTS.md` says `ad117c928^` IS the pin; I did not touch it.

## 9. FILES

    gates/realize_graph_census.bend          +`rs_pay` (12 arms + `rs_pay.pi`/`pa`/`ki`/`ax`),
                                              -`rs_s1.go`, -`rs_cval(+a)`; `rs_join2.add`,
                                              `rs_ids`, `rs_ids.dash` MOVED above the payload
                                              (Bend needs a def before its caller)
    gates/realize_graph_census-oracle.py     +`apay`, `s1` rewritten, `_ids`
    gates/realize_graph_census-gate.py       +`argkinds_hold`, the 378/42 figures, the two
                                              hard-coded token pairs, the Box-2 header
    gates/realize_graph_census-pins.rows     12 values re-spelled, 63 -> 63 rows
    gates/realize_graph_census-mutate.py     X5 re-classified, V11/V12/Z4/Z5/G36/G37 added,
                                              `RUN_TAIL` gained the `axis_hold` it was missing

    `tinybendygrad/` IS BYTE-IDENTICAL. MEASURED, and it is the first thing to check.