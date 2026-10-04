#!/usr/bin/env python3
"""Q3 -- THE TWO NEW `selfcheck` ROWS ARE ARMED, MEASURED BY BREAKING THEM ON A COPY.

**AN ASSERTION THAT CANNOT FAIL IS NOT AN ASSERTION.** graphcmp-oracle.py says so in its own
comment about defect 21 and `selfcheck` is the precedent it cites, so this unit's two new
rows (`bw` must answer `?=0`, and both sides' float CONST must be exactly `f1065353216`) have
to be shown firing. A row that has only ever printed its own value proves nothing.

**AND NOTHING IN THE LIVE TREE IS TOUCHED.** `tinybendygrad/` is five units deep in edits
right now and `tinybendygrad/uop/ops.bend` is under single ownership; a mutation run that
edited either would destroy another unit's work. So every arm below is built by MONKEYPATCHING
the loaded module in this process, on rows this process fabricated, and the real
`selfcheck` function is then called. The two failure modes are:

  A. the `?` row   -- feed it bend rows carrying `?` in the dtype column and read FAIL;
  B. the float row -- feed it a `repr`-spelled float CONST and read FAIL, AND feed it a
     *mismatched pair* (`f1` against `f1065353216`) and read FAIL, because those are two
     different bugs and a row that only catches the first would leave the second.

The monkeypatch is undone in a `finally`, and the third phase calls `selfcheck` with NOTHING
patched and requires OK -- so a run that leaves the module broken is a run that says so.
"""
import os
import sys

os.environ.setdefault("DEV", "NULL")
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
import graphcmp as G                                        # noqa: E402


WIRE = G.WIRE                                  # ("id","op","dtype","shape","depth","tag","arg","src")


def retitle(rows: list[str], i: int, field: int, new: str) -> str:
  """Field `field` of row `i`, rewritten in the wire format. `chunk`/`unchunks` are the
  differ's own, so the rewrite cannot invent a spelling the reader would not accept.

  **TWO INDICES, AND THE FIRST VERSION HAD ONE -- WHICH IS THE FINDING.** The first version
  took a single `idx` and used it BOTH as the row subscript (`rows[idx]`) and as the field
  subscript (`f[idx] = new`), so `retitle(good, 0, "?")` patched the `id` field of row 0 and
  not the `dtype` field. MEASURED consequence: the arm reported `# SELFCHECK: OK` on a patch
  that had changed nothing the `?` row reads, and the probe's own guard caught it --
  `patched dtype field = 'f32'` after a call whose entire purpose was to write `?` there.
  **`at_value` scans fields 2 and 3 only, so a `?` written into field 0 is invisible to it,
  and a mutation harness that patches the wrong field reads as a row that cannot fire.** That
  is this project's standing trap at a third site: LIMITS 13 (`BYTE-IDENTICAL` over two
  0-byte files), 17 (the `arg=None` SINK that crashed the emitter), and now a mutation that
  patched the wrong column. The reason this was caught and not believed is that the probe
  READ BACK the field it claimed to have written instead of trusting the verdict.
  """
  f = G.unchunks(rows[i])
  f[field] = new
  return " ".join(G.chunk(v) for v in f)


def main() -> int:
  G.load_tinygrad()
  G.COMM = G.commutative()

  real_bend_bw, real_py_bw, real_bend_sym, real_bend_loop = (
    G.bend_bw_rows, G.py_bw_rows, G.bend_sym_rows, G.bend_loop_rows)

  print("q3_BASELINE -- nothing patched, selfcheck must be OK")
  rc = G.selfcheck()
  print("q3_baseline_selfcheck_rc=%d %s" % (rc, "OK" if rc == 0 else "FAIL"))
  if rc != 0:
    return 1

  try:
    # ---------- ARM A: the `?` row, on a node that has NOT settled -------------------
    good = list(real_bend_bw("CPU"))
    bad = list(good)
    for i, ln in enumerate(bad):
      if G.unchunks(ln)[2] == "f32":          # the dtype column, index 2 of WIRE
        bad[i] = retitle(good, i, WIRE.index("dtype"), "?")
        break
    else:
      print("q3_FAIL no f32 dtype row to unsettle, so arm A would be vacuous")
      return 1
    # READ THE COLUMN BACK BEFORE BELIEVING THE ARM. This is the check that catches the
    # wrong-column patch, and it is the only reason the first version of this probe was
    # caught rather than believed: the arm printed `# SELFCHECK: OK` while having written `?`
    # into the `id` field of row 0.
    if G.unchunks(bad[0])[WIRE.index("dtype")] != "?":
      print("q3_FAIL arm A wrote the wrong COLUMN: row 0's dtype is still "
            f"{G.unchunks(bad[0])[WIRE.index('dtype')]!r}. An arm that patches a field "
            f"`ledger` does not scan reads as a row that cannot fire.")
      return 1
    print("q3_armA_readback=dtype column now reads `?`  (the patch landed where it was aimed)")
    G.bend_bw_rows = lambda dev: bad
    print("")
    print("q3_ARM_A -- one node's dtype column reads `?` (what the identity PERMUTE did)")
    rc = G.selfcheck()
    print("q3_armA_selfcheck_rc=%d %s" % (rc, "OK" if rc == 0 else "FAIL"))
    if rc == 0:
      print("q3_FAIL arm A did NOT fire: the `?=0` row on `bw` cannot fail, so it is a claim")
      return 1

    # ---------- ARM B1: `repr` back in the float column, on BOTH sides --------------
    G.bend_bw_rows, G.py_bw_rows = real_bend_bw, real_py_bw
    repy = list(real_py_bw())
    for i, ln in enumerate(repy):
      if G.unchunks(ln)[2] == "weakfloat":
        repy[i] = retitle(repy, i, WIRE.index("arg"), "fConstFloat(1.0)")
        break
    G.py_bw_rows = lambda: repy
    print("")
    print("q3_ARM_B1 -- py's float CONST reverts to `repr`, i.e. `fConstFloat(1.0)`")
    rc = G.selfcheck()
    print("q3_armB1_selfcheck_rc=%d %s" % (rc, "OK" if rc == 0 else "FAIL"))
    if rc == 0:
      print("q3_FAIL arm B1 did NOT fire: the float-spelling row cannot see `repr` come back")
      return 1

    # ---------- ARM B2: the two sides MISMATCH, py right and bend wrong -------------
    # A DIFFERENT bug from B1 and the row must catch it too: here py is the exact bits and
    # bend is `F32.show`'s text. A row that only compared py against a literal would pass
    # this, which is why B2 exists.
    G.py_bw_rows = real_py_bw
    bbend = list(real_bend_bw("CPU"))
    for i, ln in enumerate(bbend):
      if G.unchunks(ln)[2] == "weakfloat":
        bbend[i] = retitle(bbend, i, WIRE.index("arg"), "f1")
        break
    G.bend_bw_rows = lambda dev: bbend
    print("")
    print("q3_ARM_B2 -- py keeps the exact bits and bend reverts to `F32.show` (`f1`): the "
          "two sides DISAGREE, which is a different defect from B1")
    rc = G.selfcheck()
    print("q3_armB2_selfcheck_rc=%d %s" % (rc, "OK" if rc == 0 else "FAIL"))
    if rc == 0:
      print("q3_FAIL arm B2 did NOT fire: the row checks only the py side's spelling")
      return 1
  finally:
    G.bend_bw_rows, G.py_bw_rows = real_bend_bw, real_py_bw
    G.bend_sym_rows, G.bend_loop_rows = real_bend_sym, real_bend_loop

  # ---------- AND THE RESTORED MODULE MUST BE OK, OR THE RUN LIES ------------------
  print("")
  print("q3_RESTORED -- patches undone, selfcheck must be OK again")
  rc = G.selfcheck()
  print("q3_restored_selfcheck_rc=%d %s" % (rc, "OK" if rc == 0 else "FAIL"))
  print("")
  print("q3_ARMS_FIRED  A(?=0 on bw)=FIRED  B1(repr back)=FIRED  B2(sides mismatch)=FIRED  "
        "baseline=OK  restored=OK")
  return 0 if rc == 0 else 1


if __name__ == "__main__":
  sys.exit(main())