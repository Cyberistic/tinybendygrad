# WHAT I COULD NOT SETTLE

1. **THE `?` ON `loop`'s `dtype` AND `shape`.** I proved it is NOT the `CallInfo.dtype`
   field — deleting the field leaves `? ?` exactly where they were, and the driver
   prints `settled=False`. **I did not find the `fold.bend` wall that stops CALL#25
   settling**, so I cannot say what closes it. `fold.bend` is not this unit's file and
   I did not go looking inside `Kahn` for it. This is the half of `loop` still open,
   and it is the half nobody has characterised.

2. **`lin` off the device pin.** I measured `DEV=CPU` -> 1 option and default device ->
   2, so the recorded row's `1 = 1` is the pin. **I did not re-run the differ**, because
   `runs/graphcmp/D` is shared and not mine, so I cannot say how many OTHER recorded
   numbers move under a different `DEV`. `flip` and `loop` are probably unaffected (no
   `Opt` anywhere in either) but "probably" is not measured.

3. **THE THREE HARNESS FAILURES.** `allred`, `cdiv`, `late` share one 18-row emission
   with `matmul` (`sha256 9f39a6e3…`) because `rows.pick3` has no arm for them. **I did
   not re-diagnose this** and I did not touch `rows.pick3`. One thing I add: the same
   `Bool.pick` chain is the *third* place in this corpus where a missing arm silently
   substitutes, so the census in `DIAGNOSIS.md` §3 is the load-bearing artefact here,
   not the diagnosis.

4. **WHETHER `flip`'s HAND-BUILT GROUP WAS DELIBERATE.** `git log -S` puts `g_flip` and
   its GROUP line in the same commit. I confirmed the mechanism (CPython's `UOp.group`
   collapses one src, `ops.bend:2507` implements the collapse correctly, and
   `graphcmp.bend:1304` bypasses it) but I cannot tell intent from a message.

5. **`graphcmp.py`'s DATACLASS ARM JOINS FIELDS WITH `""`, NOT `","`.**
   `graphcmp.py:672-673` — `"".join(f"{n}={_carg(getattr(x, n))}" ...)`. So `lin`'s
   payload is the **unambiguously-unparseable** text
   `Opt(op=EOptOps.SPLITaxis=i2arg=n(i0,XUPCAST))`, where `EOptOps.SPLIT` + `axis=i2`
   and `EOptOps.SPLITaxis` + `=i2` are the same string. **`Opt` and `CallInfo` have
   hand-written arms elsewhere** (`cI(` at `:508` uses `","` correctly), so this is one
   arm's delimiter and not a global policy. **I did not fix it and did not measure how
   many other payloads it ambiguates** — `ParamArg`'s `P(...)` and `pI(...)` go through
   the same arm, so it is at least three arg forms.

6. **`flips`'s blast radius is a CENSUS, NOT A PLANT.** The `ATuple: List<U32> ->
   List<Bool>` plant went red at `eq_arg.ATuple` and Bend reports ONE error at a time,
   so I did not iterate to exhaustion the way I did for `loop` (whose full 11 sites came
   from a census and were then applied together and checked green). The five files in
   `02-fix.md` §1 are from `grep`, and **none of them has been compiled.**

7. **`lin`'s fix is a MOVE, and I have not measured the move.** `OPT` must come down out
   of `codegen/opt/postrange.bend` (which imports `ops.bend`) into a module `ops.bend`
   can import. **I do not know whether Bend's import graph permits it in that direction**
   without trying, and `substrate-check.sh`'s cold-file sweep is another unit's.

8. **FOUR UNITS ARE LIVE AND `HEAD` MOVED TWICE UNDER ME** (once to `6caac2102`, once to
   `2eb87476e`). The `ops.bend` I edited is HEAD's, and `git diff HEAD` on it was empty
   before my edit — but **another unit may be mid-edit on it now**, and my three
   citations are the first thing to re-verify if so.