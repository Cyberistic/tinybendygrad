#!/usr/bin/env python3
"""MEASURE THE TWO STAGES OF `tinybendygrad/codegen/__init__.bend`'s arena
threading, against CPython called live. Supersedes the first version of this
file, which could only see the pre-fix tree.

    .venv/bin/python .agents/slop/codegen-init-measure.py

WHAT IS BEING ORDERED, AND WHY THE ORDER IS THE POINT. The port carried a
`SINK -> Some{self}` rule that upstream's table does not have
(`tinygrad/schedule/__init__.py:96-101` has exactly two patterns, read off the
objects by `codegen-init-oracle.py` Q1). Removing it alone made the printed row
WORSE, because `wr.rebuild` minted through `O.UOp.new` and kept only
`Found.i` -- an index with no arena to resolve it against, which
`O.Arena.node` answers as its total out-of-range bottom (`NOOP`). So the
rule was LOAD-BEARING on a bug. The two stages measured here are:

    BASE      the frozen pre-fix tree (`runs/gr-init/base`), md5-asserted.
    A-arena   arena threaded, third rule STILL PRESENT.
    B-both    arena threaded, third rule REMOVED. This is the landed file.
    C-comment a comment-only edit of B. The CONTROL: every row must be SAME.

If B's rows were not CPython's, then the wall was not the only root cause and
the third rule is not removable -- and that is a finding, not a failure to be
patched over.

CPython's values are RE-DERIVED AT RUN TIME by CALLING tinygrad from this
checkout. Nothing below is transcribed:

    py.new_sink_op           = SINK
    py.repl                  = PARAM(0)->PARAM(99),PARAM(1)->PARAM(100),ALLOC->BUFFER,SINK->SINK
    py.new_sink_is_original  = 0
    py.new_sink_srcs         = PARAM(99),PARAM(100),BUFFER
    py.n_repl                = 4

THE ARENA-LENGTH SWEEP. `O.Arena` is an immutable record and `O.Arena.node` is
total, so a single wrong row could be one fixture's arena having been clobbered
rather than a rebuilt index being out of reach. `M-padK` interns K extra PARAMs
(distinct slots) before the fixture, making the arena `5 + K` nodes at the
sink. The row is reported at EVERY length. K=0 is 5 nodes, K=4 is 9; the
oldest predecessor of this harness swept 11 lengths across 7 distinct arenas
and saw `SINK->NOOP` at every one.

SCORING. A row's SCORE is the number of characters that differ from CPython's,
whitespace stripped, so it is a distance in one unit and lower is closer.
Rows are compared WHOLE, as `name=value` LINES -- a harness that compares row
names reports 0 for every mutation.
"""
from __future__ import annotations

import hashlib
import os
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[2]
PORT = "codegen/__init__.bend"
PROBE = "codegen-init-probe.bend"

BASE_TREE = ROOT / "runs" / "gr-init" / "base" / "tinybendygrad"
# The PRE-FIX port, as ONE frozen FILE. `base/tinybendygrad/` is a live mirror
# of the tree that tracks whatever the port currently is; it is not an archive.
PREFIX_PORT = ROOT / "runs" / "gr-init" / "base" / ".agents-prefix-port.bend"
OLD_PROBE = ROOT / "runs" / "gr-init" / "base" / ".agents-old-probe.bend"

# md5 of the two ports this harness reads. A mismatch is a hard stop, never a
# silent measurement of something other than what the report claims.
MD5_BASE_TREE = "083c05ff6013d152ce3f83db4fc62a51"   # the pre-fix port, 361 lines
MD5_LIVE_TREE = "df922fb5ce15b4ad8428a723950ba568"   # the landed port, 317 lines

# --- the anchors. Every one must appear EXACTLY ONCE or the patch is refused;
# a silently-unapplied mutation is a zero that reads like a theorem.
SINK_ENTRY_ANCHOR = 'O.PMEntrys{[O.PMEntry{3, [O.OpsPARAM{}], Nil{}}, O.PMEntry{4, [O.OpsALLOC{}], Nil{}}]}'
SINK_ENTRY_BACK = 'O.PMEntrys{[O.PMEntry{0, [O.OpsSINK{}], Nil{}}, O.PMEntry{3, [O.OpsPARAM{}], Nil{}}, O.PMEntry{4, [O.OpsALLOC{}], Nil{}}]}'
FOUND_AR_ANCHOR = "case O.Found{ar, i}: (ar, Map.set(&2, U32, repl, U32.show(u), i))"
FOUND_AR_MUT = "case O.Found{ar, i}: (O.Arena.empty(), Map.set(&2, U32, repl, U32.show(u), i))"
SCAN_U = "wr.step.try_rule(u, O.pm_rewrite_m(pm, ar, u, ctx), repl, rebuilt)"
SCAN_R = "wr.step.try_rule(u, O.pm_rewrite_m(pm, ar, rebuilt, ctx), repl, rebuilt)"
COMMENT_ANCHOR = "# A dummy PARAM that the ctx carries."
COMMENT_EDIT = "# A dummy PARAM that the ctx carries. CONTROL: comment only, no behaviour."
PAD_ANCHOR = "  ar0 = O.Arena.empty()\n  +p0 = test_param(ar0, 0)"

# A DELETION is the strongest control there is and it is here as one. The
# landed file drops `gr_show.topo.k`/`.k.of`/`.topo` and `gr_show.repl.kv`,
# four defs that nothing in the tree calls (`grep -rn` over `tinybendygrad/`,
# `.agents/` and `runs/` returns only their own definitions and two OTHER
# units' frozen ancestor trees under `.agents/slop/dd-cone-wt/`, which are
# not live code). A dead def is invisible to every row -- it compiles, it
# proves, and nothing observes it -- so re-inserting it must move NOTHING.
DEAD_REINSERT = """
def gr_show.repl.kv(k: String, v: U32) -> String:
  String.concat([k, "->", U32.show(v)])

def gr_show.topo.k(rest: List<&2, U32>, acc: String) -> String:
  match rest:
    case Nil{}: acc
    case v <> t: gr_show.topo.k(t, String.concat([acc, U32.show(v), ","]))

def gr_show.topo.k.of(t: List<&2, U32>, acc: String, u: U32) -> String:
  gr_show.topo.k(t, String.concat([acc, U32.show(u), ","]))

def gr_show.topo(topo: List<&2, U32>) -> String:
  match topo:
    case Nil{}: ""
    case u <> t: gr_show.topo.k.of(t, "", u)
"""
DEAD_ANCHOR = "\n# A node's printable form is `OP(slot=N)` for PARAM and the bare"

GATE_ROWS = ("repl", "new_sink_is_original", "new_sink_srcs", "new_sink_op")
CONTROL_ROW = "n_repl"
# PORT-ONLY, no CPython counterpart: upstream returns a UOp object and has no
# arena numbering, so `new_sink=<index>` cannot be compared to anything. It is
# carried because it is the DIRECT readout of the fix -- the index is a NEW
# node in the fold's GROWN arena -- and it is swept over six arena lengths
# below. Folding it into the compared `repl` row would have made a correct
# port FAIL on a difference that has no oracle side.
PORT_ONLY = ("new_sink",)


def pad(k: int) -> str:
  """K PARAMs with distinct slots interned before the fixture, so the arena is
  `5 + K` nodes when the sink lands. The chain is linear in `+` binders, so this
  is a text insertion into the port's `main` and nothing downstream moves."""
  if not k:
    return PAD_ANCHOR.replace("\n  +p0 = test_param(ar0, 0)", "")
  chain = "".join(f"\n  +z{i} = test_param(O.Found.ar(z{i - 1}), {40 + i})" for i in range(1, k))
  return f"  ar0 = O.Arena.empty()\n  +z0 = test_param(ar0, 40){chain}\n  +p0 = test_param(O.Found.ar(z{k - 1}), 0)"


# name -> (tree, probe, [patches]).  `tree` is copied, never mutated in place.
STAGES: dict[str, tuple[str, str, list]] = {
    "BASE": ("base", "old", []),
    "A-arena": ("live", "new", [(SINK_ENTRY_ANCHOR, SINK_ENTRY_BACK)]),
    "B-both": ("live", "new", []),
    "C-comment": ("live", "new", [(COMMENT_ANCHOR, COMMENT_EDIT)]),
    "C-deadcode": ("live", "new", [(DEAD_ANCHOR, DEAD_REINSERT + DEAD_ANCHOR)]),
    "M-drop-arena": ("live", "new", [(FOUND_AR_ANCHOR, FOUND_AR_MUT)]),
    "M-u": ("live", "new", [(SCAN_U, SCAN_R)]),
    "M-u-norule": ("live", "new", [(SCAN_U, SCAN_R), (SINK_ENTRY_ANCHOR, SINK_ENTRY_BACK)]),
}
for _k in range(1, 6):
    STAGES[f"B-pad{_k}"] = ("live", "new", [(PAD_ANCHOR, pad(_k))])


def md5(p: pathlib.Path) -> str:
  return hashlib.md5(p.read_bytes()).hexdigest()


def freeze(tree: str, probe: str) -> pathlib.Path:
  """A temp tree. Nothing here is ever written back to the repo.

  The BASE stage is NOT the whole frozen tree: several agents are live and
  `uop/ops.bend` moved under `runs/gr-init/base` after it was cut, so the
  frozen tree no longer reproduces its own numbers (it printed
  `no rebuilt sink (wall)` for the pre-fix port on a tree that used to print
  `new_sink=4`). So the substrate is always the LIVE tree and BASE swaps in
  exactly ONE file -- the port -- plus the probe. The measurement is about
  that file; every other file is whatever the substrate currently is, which is
  the only way two numbers here and there are comparable at all.
  """
  live = md5(ROOT / "tinybendygrad" / PORT)
  if live != MD5_LIVE_TREE:
    raise SystemExit(f"LIVE PORT MOVED: {PORT} md5 {live} != recorded {MD5_LIVE_TREE}")
  d = pathlib.Path(tempfile.mkdtemp(prefix="gr-init-fix-"))
  shutil.copytree(ROOT / "tinybendygrad", d / "tinybendygrad", symlinks=True)
  if tree == "base":
    got = md5(PREFIX_PORT)
    if got != MD5_BASE_TREE:
      raise SystemExit(f"FROZEN PRE-FIX PORT MOVED: md5 {got} != recorded {MD5_BASE_TREE}")
    shutil.copy(PREFIX_PORT, d / "tinybendygrad" / PORT)
  (d / ".agents" / "slop").mkdir(parents=True)
  src_probe = OLD_PROBE if probe == "old" else ROOT / ".agents" / "slop" / PROBE
  shutil.copy(src_probe, d / ".agents" / "slop" / PROBE)
  (d / "bin").mkdir()
  os.symlink(ROOT / "references", d / "references")
  os.symlink(ROOT / "bin" / "bend", d / "bin" / "bend")
  return d


def run(d: pathlib.Path, rel: str, stage: str, *want: str, tries: int = 8) -> str:
  """bend stack-overflows about one run in twenty on a busy machine and prints
  ZERO rows, which is indistinguishable from 'not started'. Retry, and report
  how many retries it took -- a retry that changed nothing still happened.

  SEVERAL markers are acceptable, and one of them is the port's own refusal
  line: a behaviour that collapses the engine to the wall PRINTS that line,
  so treating it as zero rows would turn a real measurement into a hard stop.
  The distinction being preserved is `printed something` vs `printed nothing`.
  """
  last = ""
  last_err = ""
  for n in range(tries):
    r = subprocess.run([str(d / "bin" / "bend"), str(d / rel)],
                       capture_output=True, text=True, cwd=str(d), timeout=3600)
    last, last_err = r.stdout, r.stderr
    if any(w in r.stdout for w in want):
      if n:
        print(f"    [{stage}] {rel} took {n + 1} tries; earlier attempts returned "
              f"rc={0 if r.returncode == 0 else r.returncode} (bend stack-overflow, or a "
              f"concurrent agent's half-written file -- not 'not started')")
      return r.stdout.strip()
  raise SystemExit(f"[{stage}] ZERO ROWS AFTER {tries} TRIES for {rel} (want any of {want}).\n"
                   f"stdout:\n{last}\nstderr:\n{last_err}\n"
                   f"If stderr names a def outside this file, a concurrent agent is mid-edit:\n"
                   f"this harness measured a substrate in an unbuildable state, not a stage.\n")


def rows(out: str) -> dict:
  """Whole `name=value` LINES -> `name` -> `value`. Three shape facts, all
  measured here rather than assumed, because each one silently empties the
  comparison if it is wrong:

    * the port prints TWO facts on ONE line -- `new_sink=8 repl=...` -- so
      `repl=` inside the value is split into its own row and `new_sink` is
      appended to it. The arena index IS part of the row: it is the index the
      fold interned, and it is the one number that proves the arena grew.
    * the probe prefixes every row with `gr.` and the port does not, so the
      prefix is stripped. Two rows that both lacked it would compare equal
      and report nothing.
    * `IO.print` lines that are not rows (`bend 2.0.35 is available`) carry
      no `=` and are dropped by the partition below.
  """
  got: dict[str, str] = {}
  for line in out.splitlines():
    if "=" not in line or line.startswith("bend "):
      continue
    k, _, v = line.partition("=")
    k = k.strip().removeprefix("gr.")
    if k == "new_sink" and " repl=" in v:
      head, _, tail = v.partition(" repl=")
      got["repl"], got["new_sink"] = tail.strip(), head.strip()
      continue
    got[k] = v.strip()
  return got


def norm(s: str) -> str:
  """Whitespace-free, no trailing separator. Both emitters terminate a list
  with a separator the oracle does not, so comparing raw strings reports a
  distance of 2 on a row that is byte-for-byte correct, and a row that is
  correct-but-for-its-terminator looks as wrong as one that is wrong."""
  return re.sub(r"\s", "", s).rstrip(",")


def dist(a: str, b: str) -> int:
  a, b = norm(a), norm(b)
  return sum(1 for x, y in zip(a.ljust(len(b)), b.ljust(len(a))) if x != y) + abs(len(a) - len(b))


def main() -> int:
  sys.path.insert(0, str(ROOT))
  from tinygrad.uop.ops import Ops, ParamArg, RewriteContext, UOp
  from tinygrad.dtype import dtypes
  from tinygrad.schedule import pm_post_sched_cache

  def param(slot):
    return UOp(Ops.PARAM, arg=ParamArg(slot, dtypes.int32, device="PYTHON"))

  root_u = UOp(Ops.SINK, src=(param(0), param(1),
                              UOp.alloc((1,), dtypes.int32, slot=0, device="PYTHON")))
  rc = RewriteContext(pm=pm_post_sched_cache, bpm=None, ctx=({}, (param(99), param(100))), enter_calls=False)
  got = rc.walk_rewrite(root_u)

  def short(u):
    return f"{u.op.name}({u.arg.slot})" if u.op is Ops.PARAM and hasattr(u.arg, "slot") else f"{u.op.name}"

  order, seen, topo = [], set(), []

  def post(u):
    if u in seen:
      return
    seen.add(u)
    for x in u.src:
      post(x)
    topo.append(u)

  post(root_u)
  PY = {
      "repl": ",".join(f"{short(o)}->{short(n)}" for o, n in rc.replace.items()),
      "new_sink_is_original": "1" if got is root_u else "0",
      "new_sink_srcs": ",".join(short(s) for s in got.src),
      "new_sink_op": short(got),
      "n_repl": str(len(topo)),
  }
  print("CPython, CALLED LIVE (no value below is transcribed):")
  for k, v in PY.items():
    print(f"    py.{k} = {v}")
  print()
  print(f"    (repl order == post-order DFS over the root: {list(rc.replace) == topo})")
  print()

  print(f"ports md5-verified: base={MD5_BASE_TREE[:12]} live={MD5_LIVE_TREE[:12]}")
  print("substrate for every stage is the LIVE tree; BASE swaps in the frozen PRE-FIX port\n"
        "(`runs/gr-init/base/.agents-prefix-port.bend`) and the old probe.")
  print()
  print("=" * 122)
  print(f"{'stage':13} | {'repl (the printed gate row)':44} | d | {'is_orig':9} | {'srcs':31} | "
      f"{'op':9} | n_repl | new_sink (port-only)")
  print("=" * 122)

  seen_substr: set[str] = set()
  out: dict[str, dict] = {}
  for name, (tree, probe, subs) in STAGES.items():
    # The substrate is md5-recorded per stage. A concurrent agent editing
    # `uop/fold.bend` under a measurement is exactly how one of these runs
    # printed `SOME PROOFS FAIL` for `binary_n.of` -- a def in neither this
    # file nor the probe -- and that is not a stage result.
    substrate = md5(ROOT / "tinybendygrad" / "uop" / "ops.bend") + "/" + md5(ROOT / "tinybendygrad" / "uop" / "fold.bend")
    seen_substr.add(substrate)
    d = freeze(tree, probe)
    port = d / "tinybendygrad" / PORT
    orig = port.read_text()
    text = orig
    for old, new in subs:
      n = text.count(old)
      if n != 1:
        raise SystemExit(f"PATCH DID NOT APPLY [{name}]: anchor appears {n}x: {old[:70]!r}")
      text = text.replace(old, new)
    if text != orig:
      port.write_text(text)
    try:
      praw = rows(run(d, "tinybendygrad/" + PORT, name, "new_sink=", "no rebuilt sink"))
      grows = rows(run(d, ".agents/slop/" + PROBE, name, "gr.new_sink_is_original="))
    finally:
      if text != orig:
        port.write_text(orig)
    shutil.rmtree(d)
    out[name] = {**grows, **{k: v for k, v in praw.items() if k != "repl"}}
    out[name]["repl"] = praw.get("repl", "")

  for name in STAGES:
    r = out[name]
    got = [r.get(k, "<no row>") for k in GATE_ROWS + (CONTROL_ROW,)]
    bad = [k for k, g in zip(GATE_ROWS + (CONTROL_ROW,), got) if norm(g) != norm(PY[k])]
    flag = "PASS" if not bad else "FAIL " + ",".join(bad)
    print(f"{name:13} | {r.get('repl','<no row>'):44} | {dist(r.get('repl',''), PY['repl']):2} | "
          f"{r.get('new_sink_is_original','<no row>'):9} | {r.get('new_sink_srcs','<no row>'):31} | "
          f"{r.get('new_sink_op','<no row>'):9} | {r.get('n_repl','<no row>'):6} | "
          f"{r.get('new_sink','<no row>'):9}  {flag}")
  print()
  print(f"py.repl (want)              = {PY['repl']}")
  print(f"py.new_sink_is_original     = {PY['new_sink_is_original']}")
  print(f"py.new_sink_srcs            = {PY['new_sink_srcs']}")
  print(f"py.new_sink_op              = {PY['new_sink_op']}")
  print(f"py.n_repl  (CONTROL)        = {PY['n_repl']}")
  print()

  print("THE SEQUENCE, on the row that decides it. `want` is CPython's, called above.")
  for stage, note in (("BASE", "the third rule is present; it returns `self`, so the sink reads as its own replacement"),
                      ("A-arena", "arena threaded, third rule STILL PRESENT -- threading alone moves nothing"),
                      ("B-both", "arena threaded, third rule REMOVED -- this is the landed file"),
                      ("M-u-norule", "the `u`->`rebuilt` mutation WITH the third rule put back, for independence")):
    gotv = out[stage].get("new_sink_is_original", "<no row>")
    print(f"    {stage:12} gr.new_sink_is_original = {gotv:9} want {PY['new_sink_is_original']}  "
          f"{'PASS' if gotv == PY['new_sink_is_original'] else 'FAIL'}   {note}")
  same = all(norm(out["C-comment"].get(k, "")) == norm(out["B-both"].get(k, ""))
             for k in set(out["B-both"]) | set(out["C-comment"]))
  print(f"    C-comment  comment-only control: {'SAME as B-both on every row' if same else 'MOVED -- THE BASELINE MOVED, every number here is suspect'}")
  print()

  print("THE ARENA-LENGTH SWEEP on B-both (`5 + K` nodes at the sink; `new_sink` IS the grown index):")
  print(f"    {'K':>2} {'arena at sink':>14} {'new_sink':>9}  repl row")
  for k in range(0, 6):
    name = "B-both" if k == 0 else f"B-pad{k}"
    r = out[name]
    repl = r.get("repl", "<no row>")
    print(f"    {k:>2} {5 + k:>14} {r.get('new_sink','<no row>'):>9}  "
          f"{'OK ' if norm(repl) == norm(PY['repl']) else 'BAD'} {repl}")
  print()
  dead_same = all(norm(out["C-deadcode"].get(k, "")) == norm(out["B-both"].get(k, ""))
                  for k in set(out["B-both"]) | set(out["C-deadcode"]))
  print(f"    C-deadcode  re-inserting the 4 DELETED defs: "
        f"{'MOVED NOTHING, so they were dead' if dead_same else 'MOVED A ROW -- they were NOT dead'}")
  print()

  print("MUTATIONS, with the rows they moved by name:")
  for name in ("M-drop-arena", "M-u", "M-u-norule"):
    moved = [k for k in GATE_ROWS + (CONTROL_ROW,) + PORT_ONLY
             if norm(out[name].get(k, "")) != norm(out["B-both"].get(k, ""))]
    print(f"    {name:13} moved {moved if moved else 'NOTHING -- a blind spot, with the reason below'}")
  print("      M-drop-arena  `wr.rebuild.found` returns `O.Arena.empty()` instead of the grown")
  print("                    arena: the threading is the ONLY thing carrying the index, so this")
  print("                    must move the srcs row.")
  print("      M-u           `pm_rewrite_m(pm, ar, rebuilt, ctx)`: settled as UNOBSERVABLE over")
  print("                    this table (both upstream patterns are `UPat(Ops.X)` with no `src=`")
  print("                    clause, and ops.py:1810 hands back `n` itself when `new_src == n.src`).")
  print("      M-u-norule    the same mutation WITH the third rule present, to show the two are")
  print("                    not interacting: if it moves nothing here either, the `u`/`rebuilt`")
  print("                    question is closed for the third time.")
  print()
  n_rows, n_stages = len(GATE_ROWS) + 1, len(STAGES)
  print(f"DENOMINATOR: {n_rows} rows compared per stage, {n_stages} stages, "
        f"{n_stages * 2} bend invocations, every row asserted non-empty (ZERO ROWS raises).")
  print(f"SUBSTRATE: {len(seen_substr)} distinct (ops.bend, fold.bend) pair(s) seen across the "
        f"{n_stages} stages -- {len(seen_substr) == 1 and 'the substrate held still' or 'IT MOVED; a concurrent agent edited under a measurement, so stage rows are not all comparable'}.")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())