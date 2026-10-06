#!/usr/bin/env python3
"""dup-gate.py -- THE GUARD FOR THE DUPLICATE-ROW-NAME CLASS.  GUARD 0 runs before any value is
compared, and it is the only thing on most of these lanes that can be red.

    .venv/bin/python checks/dup-gate.py --port PORT.txt --oracle ORACLE.txt
    .venv/bin/python checks/dup-gate.py --port P --oracle O --selftest
    .venv/bin/python checks/dup-gate.py --compare BEFORE.txt AFTER.txt

WHAT IT GUARDS, AND WHY IT IS NOT A VALUE CHECK.  `rebase-gate.py:rows()` is `{name: value}` with
LAST WINS, so a name printed twice costs `n-1` measurements and the surviving row is the last
one.  Every lane in this class prints `disagree=[]` while the rows are unaddressable -- the
`=`-class unit measured exactly that (`disagree=[]` under AGREE with 4 measurements
unreachable on `nir_llvmir`), and the same shape is why `uop/fold.bend`'s own gate found
`lf_sub_int32_-3_4` printed TWICE and keyed on the first token.  So the guard's FIRST job is to
make the loss visible; a value comparison is what it does afterwards, and on a lane whose two
sides print the same bytes it is a tautological zero.

THE THREE READERS ARE IMPORTED, NOT FORKED.  `rebase-gate.py:row()` is the shipped row rule,
`eq-census2.py:scan()` is the shipped STRUCTURAL reader that finds the writer's boundary, and
this file adds only the multiplicity.  156 forked row readers exist and one of them caused a
two-round contradiction between two gates; a fourth reader here would be a fourth opinion about
what a row is.

EVERY COUNT COMES FROM THE LINES, NEVER FROM A DICT.  `dupes()` builds the name list, applies
`Counter`, and only then reads multiplicities.  A `set()` has already overwritten the duplicate
when you ask it, which is how `eq-census2.py` read 0 on the one lane in this tree that HAS one
-- twice, and the reconciliation line is what caught both.

PLANTS, BECAUSE A RED WITH NO PAIRED DISARM PROVES NOTHING ABOUT WHERE IT LANDED.  Three
controls in this project were found disarmed, one leaving six lanes green.  `--selftest` runs
four cells over the REAL captured pair and prints the base count MEASURED, never typed:

    clean     no plant                    -- the DISARM
    value     one changed VALUE           -- must move `disagree` and break byte-identity
    name      one name given to two rows  -- must move `dup` with the lanes still byte-identical
    collide   two names made IDENTICAL    -- must move `dup` and `lost`, `disagree` unchanged

The NAME plant and the VALUE plant are distinguishable in exactly one way that matters: the
NAME plant leaves the two lanes BYTE-IDENTICAL.  A value plant cannot do that, and a name check
that a value plant can turn green is not testing the name.
"""
import argparse, hashlib, importlib.util, pathlib, sys
from collections import Counter

HERE = pathlib.Path(__file__).resolve().parent


def refuse(*why) -> None:
  """exit 3 = REFUSED, and NOT a verdict.  `checks/abi_gate.py` rule, in this file's idiom.

  Placed BEFORE `load()` below, because the stale depth made `load()` raise
  `FileNotFoundError` FIRST, and an assertion DOWNSTREAM of what it asserts cannot turn an
  exception into a refusal: rc 1 and a traceback, which carries no denominator and so counts
  nowhere.  The twin `dup-census.py` says the same thing about the same defect."""
  print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
  sys.exit(3)


# `parents[0]`, NOT `HERE.parent`.  `3f0e70ff1` MOVED this file from `.agents/slop/` to `checks/`,
# ONE level shallower, and carried the constant across without recomputing it -- so `SLOP` became
# the REPO ROOT and `load(SLOP / "rebase-gate.py")` asked for `<repo>/rebase-gate.py`, which has
# never existed, while the real one sat at `.agents/slop/rebase-gate.py`.  MEASURED: the twin
# `dup-census.py` was fixed for exactly this and this file was not, and it is NOT among the
# twelve the instrument found because it names NO `parents[N]` -- a rule that finds an instance by
# its SPELLING cannot find one that spells the same depth as `HERE.parent`.  The depth is PROVED by
# `refuse()` below, not assumed.
REPO = HERE.parents[0]
if not (REPO / "pyproject.toml").is_file() or not (REPO / "tinybendygrad").is_dir():
  refuse(f"REPO does not hold the tree: {REPO} is not the repo root "
         f"(is `parents[N]` stale after a move?)")
SLOP = REPO / ".agents" / "slop"
_EQ = SLOP / "eq" / "eq-census2.py"
for _p in (SLOP / "rebase-gate.py", _EQ):
  if not _p.is_file():
    refuse(f"input absent: {_p}"
           + ("  (swept by 371cc64c9; recoverable from git at 371cc64c9^:)"
              if _p == _EQ else "")
           + "  This gate cannot produce a denominator without it.")


def load(path, name):
  spec = importlib.util.spec_from_file_location(name, str(path))
  mod = importlib.util.module_from_spec(spec)
  spec.loader.exec_module(mod)
  return mod


RG = load(SLOP / "rebase-gate.py", "rebase_gate")
EQ = load(SLOP / "eq" / "eq-census2.py", "eq_census2")
ROW, SCAN = RG.row, EQ.scan


def digest(text):
  """sha256 of the NON-BLANK lines.  ⚠ NOT `md5 -q`: on macOS `md5 -q` takes exactly ONE file and
  prints NOTHING given several, so a two-lane byte comparison with it silently compares one lane
  and calls it two."""
  body = "\n".join(l for l in text.splitlines() if l.strip())
  return hashlib.sha256(body.encode()).hexdigest()[:12]


def dupes(text):
  """{name: n} for every name `row()` prints more than once, COUNTED FROM THE LINES.

  Returned as a LIST of (name, n) so the multiplicities survive to the caller; `rows()` cannot
  express this at all, which is the whole reason the class exists."""
  c = Counter(r[0] for r in (ROW(l) for l in text.splitlines()) if r is not None)
  return {k: v for k, v in c.items() if v > 1}


def refusals(text):
  """(lines with no writer boundary, lines the writer emitted and `row()` refused), with the
  reason.  These are DIFFERENT defects with different owners: `uop/fold.bend`'s 93 are a
  separator the reader cannot see, and `schedule/prepare`'s 14 are `== SECTION ==` banners that
  `row()` refuses DELIBERATELY."""
  sc, shape, _n2, _n = SCAN(text)
  nob = [(i, w) for i, k, _, w in sc if k == "no-boundary"]
  ref = [(i, ln) for i, ln in ((i, text.splitlines()[i - 1]) for i, k, _, _ in sc
                               if k in ("F1", "F2")) if ROW(ln) is None]
  return nob, ref, shape


def guard0(text, label):
  """Everything the class is about, with its denominator, BEFORE any value is read."""
  lines = text.splitlines()
  d = dupes(text)
  nob, ref, shape = refusals(text)
  acc = [ROW(l) for l in lines]
  accepted = [r for r in acc if r is not None]
  keys = {r[0] for r in accepted}
  return {"label": label, "lines": len(lines), "accepted": len(accepted), "keys": len(keys),
          "dup": d, "dup_rows": sum(d.values()), "lost": len(accepted) - len(keys),
          "nob": nob, "ref": ref, "shape": shape, "sha": digest(text),
          "rows": {r[0]: r[1] for r in accepted}}


def show(g):
  print(f"  {g['label']}: lines={g['lines']} accepted={g['accepted']} keys={g['keys']} "
        f"DUPLICATE NAMES={len(g['dup'])} over {g['dup_rows']} rows  lost={g['lost']}  "
        f"no-boundary={len(g['nob'])} refused={len(g['ref'])}  sha256(nb)={g['sha']}")
  for k, n in sorted(g["dup"].items()):
    print(f"      DUPLICATE {k!r} x{n}  value={g['rows'][k]!r}")


def gate(port_text, oracle_text, pname, oname):
  gp, go = guard0(port_text, pname), guard0(oracle_text, oname)
  print("GUARD 0 -- the duplicate census, per lane, before any value is compared")
  show(gp)
  show(go)
  shared = sorted(set(gp["rows"]) & set(go["rows"]))
  dis = [k for k in shared if gp["rows"][k] != go["rows"][k]]
  identical = gp["sha"] == go["sha"]
  print(f"  lanes print the SAME BYTES: {identical}"
        + ("   <<< `disagree` below is a TAUTOLOGICAL ZERO and THE BYTE DIFF IS THE GATE"
           if identical else
           "   <<< the two sides DIFFER, so the value comparison is a REAL measurement"))
  bad = []
  if gp["dup"] or go["dup"]:
    bad.append("DUPLICATE NAME")
  if gp["nob"] or go["nob"]:
    bad.append("NO-BOUNDARY LINE")
  if gp["ref"] or go["ref"]:
    bad.append("REFUSED BY row()")
  if not shared:
    bad.append("NO SHARED ROW NAMES")
  if dis:
    bad.append("VALUE DISAGREEMENT")
  print(f"  shared names: {len(shared)} of {len(gp['rows'])} port / {len(go['rows'])} oracle   "
        f"disagree={dis if len(dis) <= 8 else dis[:8] + ['...']}")
  print(f"  VERDICT: {'BROKEN (' + ', '.join(sorted(set(bad))) + ')' if bad else 'AGREE'}")
  return not bad


PLANTS = {
  # name -> (find, replace, kind).  Applied to the PORT text only, once each.
  "value": ("\n", "\n", "value"),
}


def selftest(port_text, oracle_text, pname, oname):
  """Four cells over the REAL pair.  The base is MEASURED, never typed: `renderer/cstyle.bend`
  ships five hand-transcribed `py=` literals that disagree, and a control hardcoding 0 would read
  a VALUE plant as a failure of the instrument."""
  base = guard0(port_text, pname)
  shared = sorted(set(base["rows"]) & set(guard0(oracle_text, oname)["rows"]))
  print(f"[selftest base] the REAL captured pair: {len(shared)} shared names, "
        f"{len(base['dup'])} duplicate name(s), byte-identical="
        f"{base['sha'] == guard0(oracle_text, oname)['sha']}")
  lines = port_text.splitlines()
  olines = oracle_text.splitlines()

  # ⚠ A ROW IS LOCATED BY ITS NAME **EXACTLY**, NEVER BY `startswith` AND NEVER BY LINE NUMBER.
  # Two ways this bites, both measured on the first run of this selftest:
  #   * `startswith` on an F2 lane whose names are prefixes of each other (`ldt f32` vs
  #     `ldt f32x`) renames the WRONG row and the NAME plant becomes a no-op -- `dup` stayed 0
  #     on both sides and the plant proved nothing;
  #   * the two sides of a lane pair have different lengths and different orders (`usb` is 940
  #     against 939), so "the same edit at the same index" renames a DIFFERENT row on the other
  #     side and the plant shows up on the oracle alone: `dup(port)=0 dup(oracle)=1`.
  # The assertion "a NAME plant must raise dup on BOTH sides" is what caught both.
  def idx_of(name, arr):
    for i, l in enumerate(arr):
      if "=" in l and l.split("=", 1)[0].strip() == name:
        return i
    raise SystemExit(f"selftest: no row named {name!r} on this side")

  def ofirst(name):
    return idx_of(name, olines)

  def first(name):
    return idx_of(name, lines)

  # ⚠ THE VALUE PLANT MUST MOVE THE **COMPARED** COLUMN AND NOT THE TRANSCRIPTION.
  # `rebase-gate.py:row()` returns `(name, left, right)` and its own docstring is explicit:
  # "`right` IS DELIBERATELY NOT THE COMPARED COLUMN" -- on an F2 lane `right` is the hand-copied
  # `py=` literal.  Appending a token to the END of a `name = [v]   py=[w]` line therefore
  # changes only `w`, and the first run of this selftest read `verdict AGREE, disagree=0,
  # byteIdent False` for the VALUE plant on `nir_llvmir`: a plant that changes bytes, breaks
  # byte-identity, and is NOT CAUGHT.  A value plant that a value comparison cannot see is the
  # shape of the failure `rebase-gate.py` documents when it refuses to compare transcriptions.
  # So the token goes immediately AFTER THE FIRST `=`, which is inside `left` on every shape.
  v = lines[:]
  i = first(shared[0])
  k = v[i].index("=")
  v[i] = v[i][:k + 1] + "PLANT" + v[i][k + 1:]
  # NAME plant: rename ONE row onto an EXISTING name, on BOTH sides, so the two lanes stay
  # BYTE-IDENTICAL while one name now carries two rows.  Both sides are planted because a
  # one-sided rename is a lane whose names stopped matching, which is a different defect and a
  # different verdict -- the point of the cell is that byte-identity alone CANNOT see this.
  n, m = first(shared[1] if len(shared) > 1 else shared[0]), first(shared[0])
  key = shared[0]
  np_, op_ = list(lines), list(olines)
  np_[n] = key + "=" + lines[n].split("=", 1)[1]
  op_[ofirst(shared[1] if len(shared) > 1 else shared[0])] = \
      key + "=" + olines[ofirst(shared[1] if len(shared) > 1 else shared[0])].split("=", 1)[1]
  # COLLIDE plant: rename a row whose VALUE DIFFERS onto another name.  Distinct from NAME in the
  # way that matters -- `rows()` keeps the LAST row on a key, so a collision between two rows
  # with the SAME value loses only a label, while a collision between two rows with DIFFERENT
  # values silently changes which measurement the reader sees.  A guard that reports only "some
  # name appears twice" cannot tell those apart, so the pair is chosen to differ.
  diff = [k for k in shared if guard0(oracle_text, "o")["rows"][k] != base["rows"][k]]
  donor = shared[2] if len(shared) > 2 else shared[0]
  c, o2 = list(lines), list(olines)
  c[first(donor)] = shared[0] + "=" + lines[first(donor)].split("=", 1)[1]
  o2[ofirst(donor)] = shared[0] + "=" + olines[ofirst(donor)].split("=", 1)[1]
  print(f"  [plant] donor={donor!r} -> key={shared[0]!r}; value differs from the key's: "
        f"{donor in diff} (a collision between EQUAL values and one between UNEQUAL values are "
        f"the same name collision and not the same measurement)")

  cells = [("clean", port_text, oracle_text),
           ("value", "\n".join(v), oracle_text),
           ("name", "\n".join(np_), "\n".join(op_)),
           ("collide", "\n".join(c), "\n".join(o2))]
  print(f"  {'cell':<8} {'verdict':<8} {'dup(port)':>9} {'dup(oracle)':>11} {'byteIdent':>10} "
        f"{'disagree':>8}")
  out = {}
  for nm, pt, ot in cells:
    gp, go = guard0(pt, "port"), guard0(ot, "oracle")
    sh = sorted(set(gp["rows"]) & set(go["rows"]))
    dd = sum(1 for k in sh if gp["rows"][k] != go["rows"][k])
    bad = bool(gp["dup"] or go["dup"] or dd or not sh)
    verdict = "BROKEN" if bad else "AGREE"
    print(f"  {nm:<8} {verdict:<8} {len(gp['dup']):9} {len(go['dup']):11} "
          f"{str(gp['sha'] == go['sha']):>10} {dd:8}")
    out[nm] = (verdict, len(gp["dup"]), len(go["dup"]), gp["sha"] == go["sha"], dd)
  print(f"[selftest assert] clean must be AGREE or carry the MEASURED base disagree: "
        f"{out['clean']}")
  print(f"[selftest assert] value must BREAK byte-identity: {not out['value'][3]} "
        f"(base byteIdent={out['clean'][3]})")
  print(f"[selftest assert] name must raise dup on BOTH sides with the lanes STILL "
        f"byte-identical: {out['name'][1] > out['clean'][1] and out['name'][2] > out['clean'][2] and out['name'][3]} "
        f"-- raised port {out['clean'][1]}->{out['name'][1]}, oracle {out['clean'][2]}->{out['name'][2]}, "
        f"byteIdent {out['name'][3]}, disagree {out['name'][4]}")
  print(f"[selftest assert] collide must raise dup: {out['collide'][1] > out['clean'][1]}")
  ok = (not out["value"][3]) and out["name"][3] and out["name"][1] > out["clean"][1] \
      and out["name"][2] > out["clean"][2] and out["collide"][1] > out["clean"][1]
  print(f"SELFTEST {'OK' if ok else 'FAILED'}"
        + ("" if out["clean"][3] else
           "   <<< the pair is NOT byte-identical, so the NAME plant cannot demonstrate the "
           "byte-identity claim; re-run on a byte-identical pair (nir_llvmir, llvmir, ptx, c, "
           "viz, nn) for that cell"))
  return ok


def compare(a_path, b_path):
  """THE MULTISET PROOF.  Renaming a row name changes what other lanes' tables cite, so the
  evidence is counts over MULTISETES, not a diff of two texts: how many lines, how many
  distinct names, whether the VALUES moved as a multiset, how many names paired with a partner
  that is the old name with one separator changed, and how many names are printed more than
  once on either side.  `nl-gate.py`'s `--compare` is the model and its wording is kept."""
  A, B = pathlib.Path(a_path).read_text(), pathlib.Path(b_path).read_text()
  ra, rb = ROW and [ROW(l) for l in A.splitlines()], [ROW(l) for l in B.splitlines()]
  ra = [r for r in ra if r is not None]
  rb = [r for r in rb if r is not None]
  na = Counter(r[0] for r in ra)
  nb = Counter(r[0] for r in rb)
  da = {k: v for k, v in na.items() if v > 1}
  db = {k: v for k, v in nb.items() if v > 1}
  va, vb = Counter(r[1] for r in ra), Counter(r[1] for r in rb)
  pairs = [(x, y) for x in set(na) for y in set(nb)
           if x != y and x.replace("-", " ") == y.replace("_", " ")]
  print(f"ROWS       {len(ra)} -> {len(rb)} lines; {sum(na.values())} -> {sum(nb.values())} read; "
        f"{len(na)} -> {len(nb)} distinct names -- EQUAL distinct counts is the collision check: "
        f"a rename created no name")
  print(f"VALUES     same multiset: {va == vb}   distinct {len(va)} -> {len(vb)}   "
        f"only in BEFORE {[x for x in va if x not in vb][:4]}   only in AFTER "
        f"{[x for x in vb if x not in va][:4]}")
  # `same multiset: False` ON ITS OWN READS LIKE A BROKEN VALUE SET, and for a DUPLICATE fix it is
  # the EXPECTED answer -- the fix removes surplus INSTANCES.  So the set question is asked
  # separately and answered separately: a duplicate fix must leave the set of values untouched.
  print(f"VALUE SET  identical: {set(va) == set(vb)}   instances "
        f"{sum(va.values())} -> {sum(vb.values())} (a duplicate fix removes INSTANCES, so the "
        f"multiset may differ while the set may not)")
  print(f"DUPLICATES {len(da)} -> {len(db)} name(s) printed more than once, COUNTED FROM THE "
        f"LINES and not from `rows()`'s dict (which has already overwritten them): "
        f"{'none' if not db else db}")
  print(f"LOST       {len(ra) - len(na)} -> {len(rb) - len(nb)} measurements unreachable by any "
        f"name")
  print(f"RENAME     {len(pairs)} pair(s); "
        f"{len(set(na) - {y for _, y in pairs})} name(s) on the BEFORE side have no partner")
  print(f"BYTES      sha256(nb) {digest(A)} -> {digest(B)}   "
        f"{'IDENTICAL' if digest(A) == digest(B) else 'CHANGED'}")
  ok = not db
  print(f"AUDIT {'OK -- no name is printed more than once' if ok else 'FAILED -- duplicates remain'}")
  return ok


def main():
  ap = argparse.ArgumentParser()
  ap.add_argument("--port")
  ap.add_argument("--oracle")
  ap.add_argument("--compare", nargs=2)
  ap.add_argument("--selftest", action="store_true")
  a = ap.parse_args()
  if a.compare:
    return 0 if compare(*a.compare) else 1
  if not (a.port and a.oracle):
    print("give --port and --oracle, or --compare BEFORE AFTER, or --selftest with both")
    return 2
  P, O = pathlib.Path(a.port).read_text(), pathlib.Path(a.oracle).read_text()
  if a.selftest:
    return 0 if selftest(P, O, pathlib.Path(a.port).name, pathlib.Path(a.oracle).name) else 1
  return 0 if gate(P, O, pathlib.Path(a.port).name, pathlib.Path(a.oracle).name) else 1


if __name__ == "__main__":
  sys.exit(main())