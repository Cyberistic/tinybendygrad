#!/usr/bin/env python3
"""validate-mutate.py -- MUTATE `uop/validate.bend` ONE RULE AT A TIME AND RECORD WHICH
`name=value` ROWS MOVE, AND WHETHER THE MOVE MOVED TOWARD OR AWAY FROM CPython.

THE QUESTION THIS EXISTS TO ANSWER, which is the one the prior session left open. Its own words:
"`dv_and15`, `dv_and21` and `neg4` move 3 rows, `- 1` -> `- 256`, and that direction is NOT
adjudicated... A hand-derivation of `validate.py:16` gives `w=8` -> bound `128`, matching
NEITHER. So: the aliasing is proven and the fix is right by that proof; WHETHER `- 256` IS WHAT
CPython ANSWERS IS **NOT ESTABLISHED**."

A mutation run answers exactly that, and it answers it in the only way that counts: each mutant
is run through BOTH lanes, so a mutant that moves rows toward CPython is distinguishable from a
mutant that moves them away. **A ROW THAT MOVED IS NOT A FIX.** `disagree` is the number that
separates them.

HARNESS RULES, all learned in this repo and all applied here:
  * DIFF WHOLE `name=value` LINES, never row names. A name-comparing harness reported 0 for all
    68 mutations in one unit.
  * THE MUTANT RUNS IN THE ORIGINAL'S DIRECTORY. A `$TMPDIR` copy cannot resolve `import Base`
    and reports every mutation as "did not compile" -- 22 phantom blind spots in one unit.
  * md5 BEFORE and AFTER, and the file is restored from an in-memory copy in `finally`. The
    digest is printed so a reader can check the restore without trusting it.
  * bend stack-overflows on ~1 run in 20 and prints ZERO rows with a zero exit status, so an
    empty lane is RETRIED and the attempt count is reported: "0 rows" and "0 rows after 3
    attempts" are different claims.
  * AN UNEXPLAINED ZERO IS REPORTED AS A ZERO, with a reason. No theorem is invented for it.

    DEV=NULL python3 .agents/slop/validate-mutate.py [--json]
"""
import argparse
import hashlib
import json
import os
import pathlib
import subprocess
import sys
import time

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parents[1]
PORT = REPO / "tinybendygrad" / "uop" / "validate.bend"
BEND = str(REPO / "bin" / "bend")
ORACLE = ".agents/slop/validate-oracle.py"
TRIES = 3


def load_rows_reader():
  import importlib.util
  spec = importlib.util.spec_from_file_location("rebase_gate", HERE / "rebase-gate.py")
  m = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(m)
  return m.rows


rows = load_rows_reader()


def md5(p):
  return hashlib.md5(p.read_bytes()).hexdigest()  # noqa: S324 -- an identity check, not a secret


def sh(*a, timeout=1800):
  return subprocess.run(a, cwd=REPO, capture_output=True, text=True, timeout=timeout,
                        env=dict(os.environ, DEV="NULL"))


def bend_lane():
  """(rows, attempts, raw). Retried while empty -- see the header."""
  raw = ""
  for n in range(1, TRIES + 1):
    r = sh(BEND, str(PORT.relative_to(REPO)))
    raw = r.stdout
    got = rows(raw)
    if got or n == TRIES:
      return got, n, raw
    time.sleep(20)  # the failure is depth-dependent; an immediate re-run collides
  return {}, TRIES, raw


def oracle_rows():
  r = sh(sys.executable, ORACLE)
  if r.returncode:
    raise SystemExit(f"ORACLE FAILED rc={r.returncode}\n{r.stderr[-2000:]}")
  return rows(r.stdout)


def score(prt, orc):
  """(agree, disagree, disagreeing_names) over the SHARED rows. The shared count is the
  denominator and it is returned too, because a disagreement count without one is the failure
  this repo keeps paying for."""
  shared = sorted(set(prt) & set(orc))
  bad = [k for k in shared if prt[k] != orc[k]]
  return len(shared) - len(bad), len(bad), bad, len(shared)


# (id, what it changes, the exact old text, the exact new text, why this mutant exists)
MUTS = [
  ("M1", "dv_and.put: the FIXED arena back to the PRE-MINT one (the aliasing)",
   "def dv_and.put(+ar: O.Arena, nm: String, k: U32) -> String:\n"
   "  +t = dv_bin(ar, O.OpsAND{}, 100, k)\n"
   "  +g = fx_const_bool(O.Found.ar(t), True{})\n"
   "  dv2(nm, t, g, dv_and.mm(O.Found.ar(t), t))",
   "def dv_and.put(+ar: O.Arena, nm: String, k: U32) -> String:\n"
   "  +t = dv_bin(ar, O.OpsAND{}, 100, k)\n"
   "  +g = fx_const_bool(O.Found.ar(t), True{})\n"
   "  dv2(nm, t, g, dv_and.mm(ar, t))",
   "THE MUTANT THE WHOLE SESSION TURNED ON. Reverting the aliasing fix must move the three "
   "`dv_and*` rows OFF CPython's answer. If it moves them ONTO it, the fix was wrong. The "
   "anchor is the WHOLE DEF rather than the one call, because `dv2(nm, t, g, "
   "dv_and.mm(O.Found.ar(t), t))` occurs TWICE -- here and in `dv_max.of` -- and a "
   "two-occurrence anchor is a silently SKIPPED mutant rather than a result."),
  ("M2", "bv_w.tail: `1 +` dropped, so w = 7 and the BV2Int offset is 128",
   "case Some{q}: Some{U32.add(1, bv_max4(p, q))}", "case Some{q}: Some{bv_max4(p, q)}",
   "THE `128` READING. The prior unit's hand-derivation reached 128; this mutant produces it "
   "mechanically, so the claim is testable instead of arguable."),
  ("M3", "dv2: the sink arena back to `Found.ar(t)` (the mask's arena)",
   "dv.of(nm, uops_to_z3(O.Found.ar(g), ms, O.Found.i(t), O.Found.i(g)), O.Found.i(t))",
   "dv.of(nm, uops_to_z3(O.Found.ar(t), ms, O.Found.i(t), O.Found.i(g)), O.Found.i(t))",
   "A SECOND aliasing defect, found while wiring the oracle: the gate is interned AFTER `t`, so "
   "`Found.ar(t)` is the store without it."),
  ("M4", "pow2: `m != 0` back to a sign-bit test",
   "Bool.and(Bool.not(U32.is_zero(m)), U32.is_eq(U32.and(m, U32.sub(m, 1)), 0))",
   "Bool.and(Bool.not(U32.is_eq(U32.and(m, 2147483648), 0)),\n"
   "           U32.is_eq(U32.and(m, U32.sub(m, 1)), 0))",
   "D6. `r & 15` and `r & -4` must fall back to the bit-blast, and this is what makes them not."),
  ("M5", "vz_cint: `CBool` dropped, so a bool CONST has no value",
   "    case O.CBool{b}: Some{vz_cbool(b)}\n", "",
   "D5's real cause. Every fixture's gate is `UOp.const(True)`, so this removes `True` from "
   "EVERY constraint list at once."),
  ("M6", "create_bounded: `ZGe{sym, vmin}` back to `ZLe{vmin, sym}`",
   "Ren{Sol.add(s, ZAnd{ZGe{sym, vmin}, ZLe{sym, vmax}}), zat.hit(sym)}",
   "Ren{Sol.add(s, ZAnd{ZLe{vmin, sym}, ZLe{sym, vmax}}), zat.hit(sym)}",
   "D1/D2's root cause: the AST CPython builds, not a printer heuristic."),
  ("M7", "ren_9.mx.mk: MAX back to the FLOORMOD ladder tag",
   "  ZIf{z3_lt(a, b), b, a}", "  ren_9.b2.mk(0, a, b)",
   "The mistranslation `dv_max` was added for. Reachable, and invisible to `n_z3_alu`."),
  ("M8", "Sol.put: the term appended to `cs` again",
   "  Sol{Sol.cs(s), List.append(&2, Bind, Sol.es(s), [Bind{u, t}]), Sol.ms(s)}",
   "  Sol{List.append(&2, Z, Sol.cs(s), [t]), List.append(&2, Bind, Sol.es(s), [Bind{u, t}]),"
   " Sol.ms(s)}",
   "D4. Every rewritten node's VALUE leaking into the assertion list."),
  ("M9", "z3_lt: `a < b` un-canonicalised",
   "  Bool.pick(Z, Z.is_num2(a, b), ZGt{b, a}, ZLt{a, b})", "  ZLt{a, b}",
   "z3 canonicalises `a < n` to `n > a` for a z3 numeral and NOT for a Python int; this is the "
   "only place in the ported surface where that fires."),
  ("M10", "range_str: the axis-id separator dropped",
   "    case h <> t: rs_ids.go(t, String.concat([acc, sep, rs_one(h)]), \"_\")",
   "    case h <> t: rs_ids.go(t, String.concat([acc, sep, rs_one(h)]), \"\")",
   "D3's separator. A single-axis id is unaffected, so this is EXPECTED to be a blind spot for "
   "`dv_range_global`/`dv_range_loop` and to move only a multi-axis row -- and no multi-axis row "
   "exists, which is the finding."),
  ("M11", "z3_pow: the shift factor doubled",
   "  U32.shln(1, U32.to_nat(k))", "  U32.shln(2, U32.to_nat(k))",
   "THE OTHER ROUTE TO A WRONG LITERAL IN A TERM. M2 reaches it through the WIDTH (256 -> 128) "
   "and M11 through the SHIFT FACTOR, so both moving away from CPython is evidence about the "
   "printed literal and not about one line of code. NOTE WHAT THIS MEASURED: `z3_pow` moves "
   "`dv_shr2` and NOTHING else, so the BV2Int offset literal in `dv_and21` is NOT produced by "
   "`z3_pow` -- `ZBv.str` shifts inline -- and no single def owns both literals."),
]


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--json", action="store_true")
  ap.add_argument("--only", default="", help="comma-separated mutant ids to run")
  a = ap.parse_args()

  orig = PORT.read_text()
  d0 = md5(PORT)
  orc = oracle_rows()

  base, tries, _ = bend_lane()
  if not base:
    raise SystemExit(f"BASELINE LANE PRODUCED ZERO ROWS after {tries} attempt(s)")
  b_ag, b_bad, b_names, b_sh = score(base, orc)
  out = {"baseline": {"port_rows": len(base), "shared": b_sh, "agree": b_ag,
                      "disagree": b_bad, "disagreeing": b_names, "md5": d0, "tries": tries},
         "mutants": []}

  if not a.json:
    print(f"BASELINE  md5={d0}  port={len(base)} rows  shared={b_sh}  agree={b_ag}  "
          f"disagree={b_bad}")
    print(f"           disagreeing: {', '.join(b_names)}\n")

  try:
    for mid, what, old, new, why in MUTS:
      if a.only and mid not in a.only.split(","):
        continue
      if orig.count(old) != 1:
        rec = {"id": mid, "what": what, "status": f"SKIPPED: anchor text occurs "
                                                     f"{orig.count(old)}x, expected 1"}
        out["mutants"].append(rec)
        if not a.json:
          print(f"{mid}  {rec['status']}\n     {what}")
        continue
      PORT.write_text(orig.replace(old, new))
      got, nt, _ = bend_lane()
      if not got:
        rec = {"id": mid, "what": what, "why": why, "status": "BLIND: zero rows after "
                                                            f"{nt} attempt(s) -- did not compile"}
      else:
        moved = [k for k in sorted(set(base) | set(got)) if base.get(k) != got.get(k)]
        ag, bad, names, sh_n = score(got, orc)
        rec = {"id": mid, "what": what, "why": why, "status": "ran", "attempts": nt,
               "moved": moved, "moved_count": len(moved), "shared": sh_n, "agree": ag,
               "disagree": bad, "delta_disagree": bad - b_bad, "disagreeing": names,
               "delta_agree": ag - b_ag}
      out["mutants"].append(rec)
      if not a.json:
        if rec["status"] != "ran":
          print(f"{mid}  {rec['status']}\n     {what}")
        else:
          direction = ("TOWARD CPython" if rec["delta_disagree"] < 0
                       else "AWAY from CPython" if rec["delta_disagree"] > 0 else "NEITHER")
          print(f"{mid}  moved {rec['moved_count']} row(s) {direction} "
                f"(disagree {b_bad} -> {rec['disagree']}, agree {b_ag} -> {ag})\n"
                f"     {what}\n     rows: {', '.join(rec['moved']) or '(none)'}")
  finally:
    PORT.write_text(orig)

  d1 = md5(PORT)
  out["restored_md5"] = d1
  out["restore_ok"] = (d1 == d0)
  if not a.json:
    print(f"\nRESTORE  {d0} -> {d1}   {'OK' if d1 == d0 else '*** DIGEST MISMATCH ***'}")
    print(json.dumps(out, indent=1) if a.json else "")
  else:
    print(json.dumps(out, indent=1))
  return 0 if d1 == d0 else 1


if __name__ == "__main__":
  sys.exit(main())
