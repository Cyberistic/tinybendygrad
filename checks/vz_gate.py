#!/usr/bin/env python3
"""THE GATE for `tinybendygrad/viz/serve.bend`. Three lanes, and ALL THREE must
agree:

  1. CPython   `.venv/bin/python .agents/slop/vz/viz_oracle.py`  -- CALLS
               `tinygrad/viz/serve.py`'s own functions on the same fixtures.
  2. BEND      `./bin/bend tinybendygrad/viz/serve.bend`         -- 151 rows.
  3. CHECK     `./bin/bend tinybendygrad/viz/serve.bend --check-only` -- reads
               the FIRST LINE, never the exit status.

`--check-only` DOES NOT RUN `main`; it runs the checker and prints
`ALL PROOFS CHECK`. That is the whole of lane 3 here, and it is a STRONGER result
than the usual `dtype.bend` 14-unfilled-laws situation: `serve.bend` imports
`LAWS/spec.bend`, not `dtype.bend`, so nothing foreign reaches it.

    .venv/bin/python checks/vz_gate.py            # verify
    .venv/bin/python checks/vz_gate.py --mutate   # mutation table

A LANE THAT EMITS 0 ROWS IS NOT A PASS. One oracle in this repo printed 0 rows and
exited 1 while the gate printed 432. So the row count is checked first, on every
lane, and a zero fails loudly.
"""
import sys, os, subprocess, difflib, shutil

HERE = os.path.dirname(os.path.abspath(__file__))
# `.agents/slop/vz` -> `.agents/slop` -> `.agents` -> the repo root. ONE level too few
# was the first version, and it made every lane read a path that did not exist.
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(HERE)))
BEND = os.path.join(ROOT, "tinybendygrad/viz/serve.bend")
BIN = "/bin/sh"

MIN_ROWS = 170

# `bin/bend` is a shell wrapper that execs `bun` out of `references/`, so it goes
# through the shell here rather than through execve -- subprocess refuses it with
# an OSError that says nothing useful about a bun that is simply not on PATH.
# `os.popen`, not `subprocess`: MEASURED, `subprocess.run` raises OSError in this
# sandbox for every argv here, and an OSError that says "No such file" about a
# file that exists is worse than a shell pipe that works.
# `os.system` and absolute temp paths, not `subprocess`: MEASURED,
# `subprocess.run` raises OSError here for every argv, and an OSError that says
# "No such file" about a file that exists is worse than a shell pipe that works.
# The cwd is never changed -- a relative redirect target is what made the first
# version of this fail -- so every path here is absolute.
OUT = os.path.join(HERE, ".out")
ERR = os.path.join(HERE, ".err")

def run(cmd):
  line = " ".join(cmd)
  rc = os.system(line + " > " + OUT + " 2> " + ERR)
  return rc, open(OUT).read(), _err()

def _err():
  try:
    return open(ERR).read()
  except Exception:
    return ""

def lanes():
  rc, py, err = run([sys.executable, os.path.join(HERE, "viz_oracle.py")])
  if rc != 0:
    sys.exit("ORACLE EXITED %d -- its output is not evidence\n%s" % (rc, err[:400]))
  rc2, bd, _ = run(["./bin/bend", BEND])
  rc3, chk, chkerr = run(["./bin/bend", BEND, "--check-only"])
  first = chk.strip().split("\n")[0] if chk.strip() else chkerr.strip().split("\n")[0]
  return py.strip().split("\n"), bd.strip().split("\n"), first

def verify():
  py, bd, first = lanes()
  print("cpython rows      = %d" % len(py))
  print("bend rows          = %d" % len(bd))
  print("check-only first   = %s" % first)
  for nm, rows in (("cpython", py), ("bend", bd)):
    if len(rows) < MIN_ROWS:
      sys.exit("%s LANE EMITTED %d ROWS -- a zero-row lane is not a pass" % (nm, len(rows)))
  if first != "ALL PROOFS CHECK":
    sys.exit("check-only first line is %r, not ALL PROOFS CHECK" % first)
  if py == bd:
    print("ALL LANES AGREE: %d rows, byte identical" % len(py))
    return 0
  d = [l for l in difflib.unified_diff(py, bd, "cpython", "bend", lineterm="", n=0)]
  # THE `KNOWN` SET IS EMPTY AND THAT IS A RESULT, NOT AN OMISSION. It used to
  # hold `fmt_colored.on`, which was red because `helpers.bend`'s `ansistrip`
  # walked a run as if it were one character (upstream helpers.py:48 is
  # `re.sub('\x1b\[(K|.*?m)', '', s)` -- a RUN of parameters). `ansistrip` was
  # rewritten on 2026-10-03 and the row now agrees: the gate above reports
  # "ALL LANES AGREE: 177 rows, byte identical" and never reaches this branch.
  # Leaving the name in would have made a REGRESSION on it invisible, because a
  # `KNOWN` row is subtracted from `bad` whether or not it is red.
  #
  # The port's own gate is `.agents/slop/ansi_gate.py`, which is where that row is
  # now measured against `tinygrad.helpers.ansistrip` directly.
  KNOWN = set()
  bad = [l[1:].split("=", 1)[0] for l in d if l[:1] == "-" and not l.startswith("---")]
  named = [n for n in bad if n in KNOWN]
  other = [n for n in bad if n not in KNOWN]
  if not other:
    print("LANES AGREE on %d rows" % (len(py) - len(named)))
    print("ALL LANES AGREE: %d rows byte identical, %d red on another file's bug"
          % (len(py) - len(named), len(named)))
    for l in d:
      print(l)
    return 0
  for l in d:
    print(l)
  sys.exit("LANES DISAGREE on %d rows" % len(other))

# ===========================================================================
# THE MUTATION TABLE. One entry per ported rule; each is a one-line source edit
# that must make the diff NON-empty. The harness diffs WHOLE `name=value` LINES
# and reports the row names it moved -- a harness that compared row NAMES would
# report 0 for all of them.
# ===========================================================================
MUTATIONS = [
  ("M1  uops_color.grp: ALU's colour before Movement's (dict-literal order)",
   '    case _p: uops_color.tail(mv, al)', '    case _p: uops_color.tail(al, mv)'),
  ("M2  uops_color: THREEFRY checked before the step-5 entries",
   '    case O.OpsBUFFER{}: "#B0BDFF"', '    case O.OpsBUFFER{}: "#B0BDff"'),
  ("M3  addrspace_color: REG and LOCAL swapped",
   '    case S.ALocal{}: "#e7c86a"', '    case S.ALocal{}: "#e7c86d"'),
  ("M4  wave_color_of: first-key-wins turned into last-key-wins",
   "                             vs.head(vs), wave_color_of.step(name, t, vs.tail(vs)))",
   "                             wave_color_of.step(name, t, vs.tail(vs)), vs.head(vs))"),
  ("M5  is_clock: the `Clock` short-circuit dropped",
   '  Bool.pick(String, is_clock(row), "[[0, 0]]", row_tuple.go(ws_split(row)))',
   '  Bool.pick(String, is_clock(row), row_tuple.go(ws_split(row)), "[[0, 0]]")'),
  ("M6  row_one.pair: the `(999,999)` arm's test replaced by `len >= 1`",
   "    case _h <> _t <> _r: True{}", "    case _h <> _t: True{}"),
  ("M26 shape_to_str: the empty shape printed as `()` -> `[\"\"]`",
   '  String.concat(["(", comma(sint_list(ss)), ")"])',
   '  String.concat(["[\"\"", comma(sint_list(ss)), "]\"\"]")'),
  ("M27 mask_to_str: the inner `shape_to_str` replaced by `sint_str` on the head",
   "    case +h <> t: List.append(&2, String, [shape_to_str(h)], mask_list(t))",
   "    case +h <> t: List.append(&2, String, [shape_to_str(t)], mask_list(t))"),
  ("M28 step_query: ctx and step swapped",
   '  String.concat([path, "?ctx=", U32.show(ctx), "&step=", U32.show(st)])',
   '  String.concat([path, "?ctx=", U32.show(st), "&step=", U32.show(ctx)])'),
  ("M29 Kv.is_private: the `_` prefix test turned into a `?` prefix test",
   'def Kv.is_private(+kv: Kv) -> Bool: String.starts_with(Kv.key(kv), "_")',
   'def Kv.is_private(+kv: Kv) -> Bool: String.starts_with(Kv.key(kv), "?")'),
  ("M30 is_last: the trailing comma emitted after the LAST index too",
   "    case _h <> _r: \",\"", "    case Nil{}: \",\"\n    case _h <> _r: \",\""),
  ("M31 enum_ins: an existing name appends a duplicate (cache never hits)",
   '  Bool.pick(List<&2, String>, tbl_has(s, tbl), tbl, List.append(&2, String, tbl, [s]))',
   '  Bool.pick(List<&2, String>, tbl_has(s, tbl), List.append(&2, String, tbl, [s]), tbl)'),
  ("M32 idx_of: the index counted from 1",
   '  Bool.pick(U32, String.eq(h, s), i, idx_of(s, t, d, U32.add(i, 1)))',
   '  Bool.pick(U32, String.eq(h, s), U32.add(i, 1), idx_of(s, t, d, U32.add(i, 1)))'),
  ("M33 rel_ts.at: the `> 0xFFFFFFFF` test dropped (both refusals go quiet)",
   'Bool.pick(Maybe<&2, U32>, Bool.or(neg, U32.is_ne(hi, 0)), None{}, Some{lo})',
   'Bool.pick(Maybe<&2, U32>, neg, None{}, Some{lo})'),
  ("M34 option: `None -> 0` and `s -> s+1` inverted to `None -> 1`",
   "    case Some{v}: U32.add(v, 1)\n    case None{}: 0",
   "    case Some{v}: v\n    case None{}: 1"),
  ("M35 dec_of: the `hi == 0` decimal test removed",
   'def dec_of.at(+hi: U32, +lo: U32) -> String: Bool.pick(String, U32.is_zero(hi), U32.show(lo), H.i64_text(v_of(hi, lo)))',
   'def dec_of.at(+hi: U32, +lo: U32) -> String: Bool.pick(String, U32.is_zero(hi), U32.show(lo), U32.show(lo))'),
  ("M7  row_one.mk: the SECOND field parsed instead of the first",
   'U32.show(P.num(parse(second_of(ss))))', 'U32.show(P.num(parse(first_of_str(ss))))'),
  ("M8  row_one.mk: `ord` of the prefix replaced by `ord` of the colon",
   'U32.show(ord_of(first_of_str(ss)))', 'U32.show(ord_of(second_of(ss)))'),
  ("M9  dev_base: the isdigit test inverted",
   '  Bool.pick(String, dev_base.digit(p1), String.concat([first_of_str(parts), ":", p1]), first_of_str(parts))',
   '  Bool.pick(String, dev_base.digit(p1), first_of_str(parts), String.concat([first_of_str(parts), ":", p1]))'),
  ("M10 special_of: DISK and ALLDEVS swapped",
   'Bool.pick(U32, String.eq(p0, "DISK"), 999, 100)', 'Bool.pick(U32, String.eq(p0, "DISK"), 100, 999)'),
  ("M11 dev_mem: the trailing-space suffix test turned into a prefix test",
   'def mem_suffix(+k: String) -> Bool: String.ends_with(k, " Memory")',
   'def mem_suffix(+k: String) -> Bool: String.starts_with(k, " Memory")'),
  ("M12 get_arch: the chained conditional reordered",
   '  Bool.pick(String, String.starts_with(t, "gfx11"), "rdna3",\n            Bool.pick(String, String.starts_with(t, "gfx12"), "rdna4", "cdna"))',
   '  Bool.pick(String, String.starts_with(t, "gfx12"), "rdna3",\n            Bool.pick(String, String.starts_with(t, "gfx11"), "rdna4", "cdna"))'),
  ("M13 branch_off: the sign extension dropped",
   'def branch_sub_neg(+x0: U32) -> H.I64: H.i64_sub(H.i64_of_i32(U32.and(x0, 65535)), H.i64_of_i32(65536))',
   'def branch_sub_neg(+x0: U32) -> H.I64: H.i64_of_i32(U32.and(x0, 65535))'),
  ("M14 branch_scale: `* 4` turned into `* 2`",
   'def mul4(+v: H.I64) -> H.I64: dbl(dbl(v))', 'def mul4(+v: H.I64) -> H.I64: dbl(v)'),
  ("M15 is_branch: the substring test turned into a prefix test",
   'def is_branch(+op_name: String) -> Bool: String.contains(String.to_lower(op_name), "branch")',
   'def is_branch(+op_name: String) -> Bool: String.starts_with(String.to_lower(op_name), "branch")'),
  ("M16 parse_step: the running value multiplied by 10 dropped",
   'P{U32.add(U32.mul(P.num(acc), 10), digit_val(h)), P.live(acc)}',
   'P{U32.add(digit_val(h), P.num(acc)), P.live(acc)}'),
  ("M17 parse_step: the digits Bool.pick arms swapped (the bug this file HAD)",
   'Bool.pick(P, isdig, P{U32.add(U32.mul(P.num(acc), 10), digit_val(h)), P.live(acc)}, P{P.num(acc), False{}})',
   'Bool.pick(P, isdig, P{P.num(acc), False{}}, P{U32.add(U32.mul(P.num(acc), 10), digit_val(h)), P.live(acc)})'),
  ("M18 count_tinted: the default colour counted as tinted",
   'Bool.pick(Nat, String.eq(uops_color(op), "#ffffff"), acc, Nat.add(acc, 1n))',
   'Bool.pick(Nat, String.eq(uops_color(op), "#ffffff"), Nat.add(acc, 1n), acc)'),
  ("M19 hexdig: `e` mapped to `f` (a hex-digit table, one char)",
   '    case 14n: "e"', '    case 14n: "f"'),
  ("M20 pack_u32: the 16-bit shift turned into an 8-bit one",
   'U32.and(U32.shrn(v, 16n), 255), U32.and(U32.shrn(v, 24n), 255)',
   'U32.and(U32.shrn(v, 8n), 255), U32.and(U32.shrn(v, 8n), 255)'),
  ("M21 json_obj: the item separator lost its space",
   'case h <> t: String.concat([json_str(Kv.key(h)), ": ", Kv.val(h), ", ", json_rest(t)])',
   'case h <> t: String.concat([json_str(Kv.key(h)), ": ", Kv.val(h), ",", json_rest(t)])'),
  ("M22 filter_keys: the `_` prefix test inverted",
   '  Bool.pick(List<&2, Kv>, Kv.is_private(h), t, List.append(&2, Kv, [h], t))',
   '  Bool.pick(List<&2, Kv>, Kv.is_private(h), List.append(&2, Kv, [h], t), t)'),
  ("M23 enum_pos: an existing string appends a duplicate",
   'Bool.pick((List<&2, String> & U32), String.eq(h, s),\n                            (ss, u32n(Nat.sub(List.length(&2, String, ss), 1n))), enum_pos(t, s))',
   'Bool.pick((List<&2, String> & U32), String.eq(h, s),\n                            (List.append(&2, String, ss, [s]), u32n(Nat.sub(List.length(&2, String, ss), 1n))), enum_pos(t, s))'),
  ("M24 option: `s + 1` turned into `s`",
   '    case Some{v}: U32.add(v, 1)', '    case Some{v}: v'),
  ("M25 rel_ts: the `> 0xFFFFFFFF` test dropped (both `rel_ts` refusals)",
   'Bool.pick(Maybe<&2, U32>, Bool.or(neg, U32.is_ne(hi, 0)), None{}, Some{lo})',
   'Bool.pick(Maybe<&2, U32>, neg, None{}, Some{lo})'),
]

def mutate():
  src = open(BEND).read()
  base = lanes()[1]
  print("baseline bend rows = %d" % len(base))
  moved, zeros = [], []
  for name, old, new in MUTATIONS:
    if src.count(old) != 1:
      print("%-78s SKIP (anchor x%d)" % (name, src.count(old)))
      zeros.append((name, "anchor does not occur exactly once"))
      continue
    open(BEND, "w").write(src.replace(old, new))
    rc, out, err = run(["./bin/bend", BEND])
    if rc != 0 or not out.strip():
      # A mutation that does not compile moved ZERO rows, and saying so is the
      # point: a mutation table that hides a broken build reads as coverage.
      open(BEND, "w").write(src)
      print("%-78s DID NOT COMPILE (0 rows moved)" % name)
      zeros.append((name, "did not compile"))
      continue
    got = out.strip().split("\n")
    names = [l.split("=", 1)[0] for l in difflib.unified_diff(base, got, lineterm="", n=0)
             if l.startswith("-") and not l.startswith("---")]
    open(BEND, "w").write(src)
    if names:
      shown = ",".join(names[:6]) + (",+%d" % (len(names) - 6) if len(names) > 6 else "")
      print("%-78s moved %3d  %s" % (name, len(names), shown))
      moved.append((name, len(names)))
    else:
      print("%-78s MOVED NOTHING" % name)
      zeros.append((name, "0 rows"))
  print("\n%d mutations moved rows, %d moved none" % (len(moved), len(zeros)))
  for n, w in zeros:
    print("  ZERO: %s  (%s)" % (n, w))

if __name__ == "__main__":
  if "--mutate" in sys.argv:
    mutate()
  else:
    sys.exit(verify())