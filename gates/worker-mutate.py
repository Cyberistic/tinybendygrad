#!/usr/bin/env python3
"""THE MEASURED MUTATION TABLE for tinybendygrad/engine/{worker,jit}.bend.

    .venv/bin/python gates/worker-mutate.py            # the worker table (the default)
    .venv/bin/python gates/worker-mutate.py jit        # the jit table
    .venv/bin/python gates/worker-mutate.py --plant    # the plant, on copies

WHAT THIS IS. A SENSITIVITY INSTRUMENT, and nothing else. For each of a fixed list of one-line
source mutations, this file breaks the driver on purpose and asks WHICH OF ITS ROWS MOVE. A
mutation that moves nothing is a BLIND SPOT -- the row set cannot see that bug -- and is reported
as one, by name.

WHAT THIS IS NOT. **IT COMPARES NOTHING AGAINST CPYTHON.** The port/CPython parity lives in the
`gatekit.Gate` gates (`gates/*-gate.py`), which run a CPython ORACLE beside the bend driver and
diff the two lanes. This file has ONE lane: the bend driver, mutated. A row that moves here says
"the port's output DEPENDS on this line". It says NOTHING about whether the port AGREES with
CPython, and a reader who takes this file for a parity check has read a comparison that was never
made.

THE SUBSTRATE IS NEVER WRITTEN. MEASURED 2026-10-21: the previous version of this file rewrote
`tinybendygrad/engine/worker.bend` IN PLACE and restored it afterwards from `/tmp/worker.bend.orig`,
so a crash, a SIGKILL or a Ctrl-C between the write and the restore left the substrate MUTATED --
and that file is inside `checks/differ.py`'s `SUBSTRATE_WALKS`, so a mutated copy moves
`substrate_digest()` and silently invalidates the green corpus. THE MUTATION NOW HAPPENS ON A
COPY, inside a temporary MIRROR of `tinybendygrad/`, and this file asserts the substrate's bytes
before and after every run. `--plant` kills a run mid-flight and asserts the same thing, with a
PRE-FIX FIXTURE as the falsifier: the old shape, killed the same way, leaves the substrate
MUTATED.

WHY A MIRROR OF THE TREE AND NOT OF THE FILE. `tinybendygrad/engine/jit.bend` imports
`./../helpers.bend`, `./../LAWS/spec.bend`, `./../uop/ops.bend` and `./realize.bend` -- RELATIVE
TO ITS OWN PATH -- so a copy of the file alone cannot resolve them and answers "the substrate did
not warm", which is a REFUSED exit for the wrong reason: a harness that reports "the mutation was
found" because the file could not be compiled has learned nothing (the same failure
`gates/realize_graph_census-mutate.py`'s header records). The mirror carries the whole
`tinybendygrad/` tree, so the imports resolve AND the compiler's NAMESPACE -- which it computes
RELATIVE TO THE ROOT FILE's own directory -- is the string it computes in the real tree.
MEASURED 2026-10-21: the mirror's `worker.bend` and `jit.bend` emit BYTE-IDENTICAL rows to the real
ones (56 and 0), and `--check-only` answers `ALL PROOFS CHECK` in the mirror too.

THE VERDICT, AND WHAT EACH OF ITS STATES MEANS. The vocabulary is `gates/gatekit.py`'s, imported
by path, never re-spelled.
  PASS     the baseline CHECKED, every mutation was APPLIED (its pattern is in the source), and
           the substrate's bytes are UNCHANGED.
  FAIL     the substrate's bytes CHANGED -- the invariant this file exists to protect broke --
           or a mutation's pattern was NOT FOUND, which means THIS TABLE no longer describes the
           source it names.
  REFUSED  a precondition is absent: the driver, the substrate tree or the compiler is missing,
           the baseline does not check, or the baseline emits NO ROWS.
A BLIND SPOT AND A MUTATION THAT DOES NOT RUN ARE FINDINGS, NOT FAILURES, and they are counted
APART: the first is information about ANOTHER gate -- "a mutation that moves nothing is information
about the GATE, and the response is to build the fixture it is asking for"
(`tinybendygrad/device.bend`) -- and the second says the compiler caught the bug before a row could
move. Both are in the verdict LINE, with their counts, because a verdict with no denominator is a
claim nobody can check.

THE `jit` TABLE IS VACUOUS TODAY, AND SAYS SO INSTEAD OF ANSWERING. MEASURED 2026-10-21:
`tinybendygrad/engine/jit.bend` has no `def main()` -- `e51904b04` (2026-10-06) removed it and the
`row`/`row_b`/`row_u`/`row_m` writers with it -- so the driver emits ZERO rows, and 20 of its 23
mutation patterns are NOT IN THE SOURCE ANY MORE. A table over a driver with no rows measures
nothing, and from the outside that reads exactly like a table full of blind spots, so this file
REFUSES the question rather than answering it wrongly: `jit` is REFUSED, with the row count and
the stale count named. The mutations are KEPT, because a `main()` is a thing jit.bend may grow
back, and a table deleted when its subject went quiet is a table nobody can rebuild.
"""
import argparse
import hashlib
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
HERE = Path(__file__).resolve().parent

sys.path.insert(0, str(HERE))
from gatekit import FAIL, PASS, REFUSED, VERDICT, WARM  # noqa: E402  (after sys.path, deliberately)

SUBSTRATE = "tinybendygrad"
ENGINE = "engine"
# THE PER-CALL WALL BOUND, UNCHANGED FROM THE PRE-FIX FILE. A mutation that makes the compiler
# LOOP is a FINDING, so it is reported (`TIMED OUT`) rather than raised: the pre-fix file let
# `subprocess.TimeoutExpired` escape, and a crash is not a verdict.
TIMEOUT = 1200
# THE FOUR STATES OF ONE RUN, and they are four because the pre-fix file had one. A run that
# checks, a run that does not, a run that checks and then fails, and a run that never finished
# are four different facts about a mutation, and the pre-fix file reported the second and the
# fourth as the same thing.
CHECKS = "CHECKS"
COLD = "COLD"
BROKE = "BROKE"
TIMED_OUT = "TIMED-OUT"
VACUOUS = "VACUOUS"

MUTATIONS = {
 "jit": [
  ("M1  jt_refusal: names check dropped",
   'def jt_refusal.at(+r: Maybe<&2, String>, ar: O.Arena, c: Cap, info: List<&2, InInfo>) -> Maybe<&2, String>:\n  Bool.pick(Maybe<&2, '
   'String>, Bool.not(has_str(r)), jt_info_refusal(ar, c, info), r)',
   'def jt_refusal.at(+r: Maybe<&2, String>, ar: O.Arena, c: Cap, info: List<&2, InInfo>) -> Maybe<&2, String>:\n  jt_info_refusal(ar, c, info)'),

  ("M2  jt_refusal: info check dropped",
   'def jt_refusal.at(+r: Maybe<&2, String>, ar: O.Arena, c: Cap, info: List<&2, InInfo>) -> Maybe<&2, String>:\n  Bool.pick(Maybe<&2, '
   'String>, Bool.not(has_str(r)), jt_info_refusal(ar, c, info), r)',
   'def jt_refusal.at(+r: Maybe<&2, String>, ar: O.Arena, c: Cap, info: List<&2, InInfo>) -> Maybe<&2, String>:\n  r'),

  ("M3  jit_mode: cnt==1 arms the EAGER branch",
   '  Bool.pick(U32, is_one, 2, jit_mode.at(U32.is_zero(cnt), cnt))',
   '  Bool.pick(U32, is_one, 1, jit_mode.at(U32.is_zero(cnt), cnt))'),

  ("M4  jit_mode: the `not JIT` guard loses to cnt",
   'def jit_mode.at2(off: Bool, jit_on: Bool, cnt: U32) -> U32:\n  Bool.pick(U32, off, 1, jit_mode.on(cnt))',
   'def jit_mode.at2(off: Bool, jit_on: Bool, cnt: U32) -> U32:\n  jit_mode.on(cnt)'),

  ("M5  Jit.bump: `captured` dropped (the CACHE bug)",
   'def Jit.bump.of(+j: Jit, cnt: U32) -> Jit:\n  Jit{Jit.has_fxn(j), cnt, Jit.cap(j), Jit.prune(j)}',
   'def Jit.bump.of(+j: Jit, cnt: U32) -> Jit:\n  Jit.of2(Jit.has_fxn(j), Jit.prune(j), cnt)'),

  ("M6  Jit.of: the `2 if fxn is None else 0` flipped",
   'def initial_cnt(has_fxn: Bool) -> U32:\n  Bool.pick(U32, has_fxn, 0, 2)',
   'def initial_cnt(has_fxn: Bool) -> U32:\n  Bool.pick(U32, has_fxn, 2, 0)'),

  ("M7  execs_thresh: `>= 10` becomes `>= 11`",
   'def execs_thresh(n: U32) -> Bool:\n  U32.is_ge(n, 10)',
   'def execs_thresh(n: U32) -> Bool:\n  U32.is_ge(n, 11)'),

  ("M8  on_disk: the `DISK` prefix dropped",
   'def on_disk(is_str: Bool, dev: String) -> Bool:\n  Bool.and(is_str, String.starts_with(dev, "DISK"))',
   'def on_disk(is_str: Bool, dev: String) -> Bool:\n  Bool.and(is_str, Bool.not(String.starts_with(dev, "DISK")))'),

  ("M9  prep_dup_refusal: the comparison inverted (the bug the gate caught)",
   'def prep_dup_refusal(+bases: List<&2, U32>) -> Maybe<&2, String>:\n  Bool.pick(Maybe<&2, String>, Bool.not(U32.is_eq(j_n(bases), '
   'j_n(j_adds(bases, Nil{})))),\n            Some{m_dup()}, None{})',
   'def prep_dup_refusal(+bases: List<&2, U32>) -> Maybe<&2, String>:\n  Bool.pick(Maybe<&2, String>, U32.is_eq(j_n(bases), '
   'j_n(j_adds(bases, Nil{}))),\n            Some{m_dup()}, None{})'),

  ("M10 nr_next: the CHILDREN go AFTER the siblings (the ORDER)",
   'def nr_next(x: JRet, t: List<&2, JRet>) -> List<&2, JRet>:\n  match x:\n    case RNone{}: t\n    case RTensors{n}: t\n    case '
   'ROther{nm}: t\n    case RSeq{kids}: List.concat(&2, JRet, [t, kids])',
   'def nr_next(x: JRet, t: List<&2, JRet>) -> List<&2, JRet>:\n  match x:\n    case RNone{}: t\n    case RTensors{n}: t\n    case '
   'ROther{nm}: t\n    case RSeq{kids}: List.concat(&2, JRet, [kids, t])'),

  ("M11 nr_first: the FIRST offender does not stick",
   'def nr_first(+got: Maybe<&2, String>, nm: String) -> Maybe<&2, String>:\n  Bool.pick(Maybe<&2, String>, Bool.not(has_str(got)), Some{nm}, got)',
   'def nr_first(+got: Maybe<&2, String>, nm: String) -> Maybe<&2, String>:\n  Some{nm}'),

  ("M12 srt_ins: `is_lt` becomes `is_le` (STABILITY)",
   'String.is_lt(x, h), List.append(&2, String, [x, h], t)',
   'String.is_le(x, h), List.append(&2, String, [x, h], t)'),

  ("M13 ii_dt_eq: the dtype NAME dropped from the comparison",
   'def ii_dt_eq(+a: S.Dt, +b: S.Dt) -> Bool:\n  Bool.and(U32.is_eq(S.Dt.bits(a), S.Dt.bits(b)), String.eq(j_dt_nm(a), j_dt_nm(b)))',
   'def ii_dt_eq(+a: S.Dt, +b: S.Dt) -> Bool:\n  U32.is_eq(S.Dt.bits(a), S.Dt.bits(b))'),

  ("M14 JName.eq: Pos==Kw accepted",
   '    case Pos{i} Kw{b}: False{}\n    case Kw{a} Pos{j}: False{}',
   '    case Pos{i} Kw{b}: False{}\n    case Kw{a} Pos{j}: True{}'),

  ("M15 InInfo.eq: the DEVICE dropped from the comparison",
   '                    Bool.and(ii_dt_eq(InInfo.dt(l), InInfo.dt(r)),\n                             String.eq(InInfo.dev(l), InInfo.dev(r))))',
   '                    ii_dt_eq(InInfo.dt(l), InInfo.dt(r)))'),

  ("M16 cw_step: the `Ops.CALL` filter dropped",
   '  Bool.pick(List<&2, U32>, O.op_is(ar, call, O.OpsCALL{}),\n            j_adds(RZ.get_call_written_bufs(ar, call), acc), acc)',
   '  Bool.pick(List<&2, U32>, Bool.not(O.op_is(ar, call, O.OpsCALL{})),\n            j_adds(RZ.get_call_written_bufs(ar, call), acc), acc)'),

  ("M17 pl_step: `needed` stops growing (the `needed |= si_bufs` mutation)",
   '            Prune{List.append(&2, U32, Prune.kept(p), [0]), Prune.once(p),\n                  List.concat(&2, U32, [Prune.need(p), sibufs])},',
   '            Prune{List.append(&2, U32, Prune.kept(p), [0]), Prune.once(p),\n                  Prune.need(p)},'),

  ("M18 pl_step: the two arms swapped (kept <-> once)",
   'def pl_step(+sibufs: List<&2, U32>, +p: Prune) -> Prune:\n  Bool.pick(Prune, pr_hit(Prune.need(p), sibufs),',
   'def pl_step(+sibufs: List<&2, U32>, +p: Prune) -> Prune:\n  Bool.pick(Prune, Bool.not(pr_hit(Prune.need(p), sibufs)),'),

  ("M19 prep_pick: the UNSHARD unwrap removed",
   'def prep_pick(unshard: Bool, ar: O.Arena, +u: U32) -> U32:\n  Bool.pick(U32, unshard, O.Arena.src0(ar, u), u)',
   'def prep_pick(unshard: Bool, ar: O.Arena, +u: U32) -> U32:\n  u'),

  ("M21 free_base: `allocated_views == 0` becomes `!= 0`",
   'def free_base(allocated_views: U32, base_allocated: Bool) -> Bool:\n  Bool.and(U32.is_zero(allocated_views), base_allocated)',
   'def free_base(allocated_views: U32, base_allocated: Bool) -> Bool:\n  Bool.and(Bool.not(U32.is_zero(allocated_views)), base_allocated)'),

  ("M22 free_skip: the `not Ops.BUFFER` arm inverted",
   'def free_skip(ar: O.Arena, u: U32, has_buf: Bool) -> Bool:\n  Bool.or(Bool.not(O.op_is(ar, u, O.OpsBUFFER{})), Bool.not(has_buf))',
   'def free_skip(ar: O.Arena, u: U32, has_buf: Bool) -> Bool:\n  Bool.or(O.op_is(ar, u, O.OpsBUFFER{}), Bool.not(has_buf))'),

  ("M23 m_names: the `=` debug specifier ADDED to `names` (the diff caught it)",
   '                 " != ", JName.reprs(want)])',
   '                 " != names=", JName.reprs(want)])'),

  ("M24 m_group: the plural space dropped",
   'String.concat(["JIT ", U32.show(n), " ", Bool.pick(String, U32.is_eq(n, 1), "call", "calls")])',
   'String.concat(["JIT ", U32.show(n), Bool.pick(String, U32.is_eq(n, 1), "call", "calls")])'),
 ],
 "worker": [
  ("W1  pool_refused: the `PARALLEL == 0` guard dropped",
   'def pool_refused(is_daemon: Bool, parallel: U32) -> Bool:\n  Bool.or(is_daemon, U32.is_zero(parallel))',
   'def pool_refused(is_daemon: Bool, parallel: U32) -> Bool:\n  is_daemon'),

  ("W2  pool_refused: the daemon guard dropped",
   'def pool_refused(is_daemon: Bool, parallel: U32) -> Bool:\n  Bool.or(is_daemon, U32.is_zero(parallel))',
   'def pool_refused(is_daemon: Bool, parallel: U32) -> Bool:\n  U32.is_zero(parallel)'),

  ("W3  pool_make: the MEMO removed (a pool is rebuilt every call)",
   'def pool_make(+pool: Maybe<&2, Pool>, id: U32, +parallel: U32, maxtasks: U32) -> Maybe<&2, Pool>:\n  Bool.pick(Maybe<&2, Pool>, '
   'has_pool(pool), pool, pool_new(id, parallel, maxtasks))',
   'def pool_make(+pool: Maybe<&2, Pool>, id: U32, +parallel: U32, maxtasks: U32) -> Maybe<&2, Pool>:\n  pool_new(id, parallel, maxtasks)'),

  ("W4  terminated: the pool-existed test inverted",
   'def terminated(pool: Maybe<&2, Pool>) -> Bool:\n  has_pool(pool)',
   'def terminated(pool: Maybe<&2, Pool>) -> Bool:\n  Bool.not(has_pool(pool))'),

  ("W5  mod_cleared: only `__file__` is cleared",
   'def mod_cleared(+x: Mod) -> Mod:\n  Mod{Mod.nm(x), None{}, None{}}',
   'def mod_cleared(+x: Mod) -> Mod:\n  Mod{Mod.nm(x), None{}, Mod.spec(x)}'),

  ("W6  mod_restore: the `now` arm replaced by `saved` (the SETATTR arm dies)",
   'def mod_restore(+saved: Maybe<&2, String>, now: Maybe<&2, String>) -> Maybe<&2, String>:\n  Bool.pick(Maybe<&2, String>, '
   'missing_is_none(saved), now, saved)',
   'def mod_restore(saved: Maybe<&2, String>, now: Maybe<&2, String>) -> Maybe<&2, String>:\n  Bool.pick(Maybe<&2, String>, '
   'Bool.not(missing_is_none(saved)), now, saved)'),

  ("W7  WFlags.viz: VIZ is no longer switched off",
   'def init_worker() -> WFlags:\n  WFlags.of(0, 0, 0, True{})',
   'def init_worker() -> WFlags:\n  WFlags.of(0, 1, 0, True{})'),

  ("W8  init_worker: SIGINT is no longer ignored",
   'def init_worker() -> WFlags:\n  WFlags.of(0, 0, 0, True{})',
   'def init_worker() -> WFlags:\n  WFlags.of(0, 0, 0, False{})'),

  ("W9  spawnv_returncode: the forced 0 dropped",
   'def spawnv_returncode() -> U32:\n  0',
   'def spawnv_returncode() -> U32:\n  1'),

  ("W10 maxtasks_default: 16 becomes 8",
   'def maxtasks_default() -> U32:\n  16',
   'def maxtasks_default() -> U32:\n  8'),

  ("W11 pool_new: `initializer=_init_worker` dropped",
   'def pool_new(id: U32, parallel: U32, maxtasks: U32) -> Maybe<&2, Pool>:\n  Some{Pool.of(id, parallel, 0, pool_init_name(), maxtasks)}',
   'def pool_new(id: U32, parallel: U32, maxtasks: U32) -> Maybe<&2, Pool>:\n  Some{Pool.of(id, parallel, 0, "", maxtasks)}'),

  ("W12 sch_puts: the schedule REVERSED",
   'def sch_puts(xs: List<&2, Task>, acc: List<&2, String>) -> List<&2, String>:\n  match xs:\n    case Nil{}: acc\n    case +h <> t: '
   'sch_puts(t, List.append(&2, String, acc, [sch_one(h)]))',
   'def sch_puts(xs: List<&2, Task>, acc: List<&2, String>) -> List<&2, String>:\n  match xs:\n    case Nil{}: List.reverse(&2, String, '
   'acc)\n    case +h <> t: sch_puts(t, List.append(&2, String, acc, [sch_one(h)]))'),

  ("W13 eq_mstr: `None` equals a `Some`",
   '    case None{} Some{b}: False{}\n    case Some{a} None{}: False{}',
   '    case None{} Some{b}: True{}\n    case Some{a} None{}: True{}'),
 ],
}


def refuse(*why):
    """REFUSED, from `gatekit`'s own table, never re-spelled: a PRECONDITION was absent."""
    print("== REFUSED, NOT A VERDICT: " + "; ".join(why), file=sys.stderr)
    raise SystemExit(REFUSED)


def digest(path: Path) -> str:
    """The sha256 of a file's BYTES, which is the only thing the substrate invariant is about."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


def driver_of(root: Path, which: str) -> Path:
    """The driver under test, in the tree."""
    return root / SUBSTRATE / ENGINE / f"{which}.bend"


def mirror(root: Path, work: Path) -> Path:
    """A COPY of the substrate tree, in `work`, and the driver inside it.

    THE COPY IS A COPY AND NOT A LINK, and that is the whole safety argument: a hard link or a
    symlink would make the mirror's files and the tree's files ONE inode, so a write anywhere
    would be a write everywhere. `shutil.copytree` with `symlinks=False` reads the bytes and
    writes new ones, so the mirror cannot reach the tree.
    """
    src = root / SUBSTRATE
    if not src.is_dir():
        refuse(f"the substrate tree is absent: {src}")
    dst = work / SUBSTRATE
    shutil.copytree(src, dst, symlinks=False, dirs_exist_ok=True)
    return dst


def run(bend: Path, path: Path) -> tuple[dict[str, str], str]:
    """`(rows, status)` for one driver run.

    TWO RUNS, AND THE ORDER IS `gatekit.py`'s: `--check-only` answers WHETHER IT CHECKS and the
    plain run answers THE ROWS. Asking one invocation for both does not work: the interpreted
    lane prints the rows and does not print the verdict, so a script that greps for
    `ALL PROOFS CHECK` in the ROW output reports a green file as BROKEN. Measured, in this
    script.
    """
    try:
        c = subprocess.run([str(bend), str(path), "--check-only"], capture_output=True, text=True,
                           timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return {}, TIMED_OUT
    if WARM not in (c.stdout + c.stderr):
        return {}, COLD
    try:
        r = subprocess.run([str(bend), str(path)], capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return {}, TIMED_OUT
    if r.returncode != 0:
        return {}, BROKE
    out = {}
    for line in r.stdout.split("\n"):
        line = line.rstrip()
        if "=" in line and not line.startswith("opened"):
            k, v = line.split("=", 1)
            out[k] = v
    return out, CHECKS


def measure(root: Path, which: str, work: Path) -> tuple[list[str], dict[str, int], str]:
    """The mutation table for one driver: `(lines, counts, status)`.

    `status` is one of `CHECKS` (the table was measured), `COLD` (the baseline does not check),
    `TIMED-OUT` (the baseline never finished) or `VACUOUS` (the baseline emits NO ROWS, so there
    is nothing for a mutation to move). **A VACUOUS BASELINE IS NOT A TABLE OF BLIND SPOTS**, and
    the pre-fix file could not tell the two apart: it counted every mutation of a driver with no
    rows as a mutation that "moved nothing", which is a table of nothing wearing a table of
    findings.
    """
    counts = {"moved": 0, "cold": 0, "broke": 0, "timeout": 0, "blind": 0, "stale": 0}
    src_driver = driver_of(root, which)
    if not src_driver.is_file():
        refuse(f"the driver is absent: {src_driver}")
    original = src_driver.read_bytes()
    try:
        text = original.decode("utf-8")
    except UnicodeDecodeError as e:
        refuse(f"the driver is not UTF-8 and cannot be mutated as text: {src_driver}: {e}")
    tree = mirror(root, work)
    mutant = tree / ENGINE / f"{which}.bend"
    if not mutant.is_file():
        refuse(f"the mirror does not carry the driver: {mutant}")
    if mutant.read_bytes() != original:
        refuse(f"the mirror's driver is not the tree's driver: {mutant}")
    bend = root / "bin" / "bend"
    if not bend.is_file():
        refuse(f"the compiler is absent: {bend}")
    base, status = run(bend, mutant)
    if status == TIMED_OUT:
        return [], counts, TIMED_OUT
    if status != CHECKS:
        return [], counts, COLD
    if not base:
        # THE ROW COUNT IS NAMED, because "it moved nothing" and "there was nothing to move" are
        # the same sentence and only one of them is a measurement.
        stale = sum(1 for _n, old, _new in MUTATIONS[which] if old not in text)
        return [f"VACUOUS: the driver emits 0 rows; {stale} of {len(MUTATIONS[which])} mutation "
                f"patterns are not in the source"], counts, VACUOUS
    lines = [f"BASELINE {which}: {len(base)} rows, {WARM}"]
    for name, old, new in MUTATIONS[which]:
        tag = "%-56s" % name
        if old not in text:
            lines.append(f"{tag} NO-OP (pattern not found)")
            counts["stale"] += 1
            continue
        # THE WRITE IS TO THE MIRROR. The tree's driver is not opened for writing anywhere in
        # this file, and the plant proves it by killing a run in the middle of one.
        mutant.write_bytes(original.replace(old.encode("utf-8"), new.encode("utf-8")))
        rows, st = run(bend, mutant)
        mutant.write_bytes(original)
        if st == TIMED_OUT:
            lines.append(f"{tag} TIMED OUT  <-- the compiler did not finish in {TIMEOUT}s")
            counts["timeout"] += 1
            continue
        if st == COLD:
            lines.append(f"{tag} DOES NOT CHECK  <-- the compiler caught it")
            counts["cold"] += 1
            continue
        if st == BROKE:
            lines.append(f"{tag} CHECKS BUT DOES NOT RUN")
            counts["broke"] += 1
            continue
        moved = sorted(k for k in set(base) | set(rows) if base.get(k) != rows.get(k))
        if not moved:
            lines.append(f"{tag} MOVED NOTHING  <-- BLIND SPOT")
            counts["blind"] += 1
        else:
            lines.append(f"{tag} {len(moved):2d} rows: " + " ".join(moved[:9])
                         + (" ..." if len(moved) > 9 else ""))
            counts["moved"] += 1
    return lines, counts, CHECKS


# ---- the plant -------------------------------------------------------------------------
# THE STUB COMPILER. It is not a compiler: it answers `--check-only` with `ALL PROOFS CHECK`, the
# plain run with two rows, and it BLOCKS on a chosen plain call so the plant can kill a harness
# while the compiler is running. `WM_COUNT` names a counter file, `WM_BLOCK_AT` the plain call it
# blocks on, and `WM_MARKER` is touched when it blocks. ONLY `sleep` is an external command.
STUB_BEND = """#!/bin/sh
case "$*" in
  *--check-only*) echo "ALL PROOFS CHECK"; exit 0 ;;
esac
if [ -n "$WM_COUNT" ]; then
  n=0
  if [ -f "$WM_COUNT" ]; then
    read n < "$WM_COUNT" 2>/dev/null || n=0
    case "$n" in ''|*[!0-9]*) n=0 ;; esac
  fi
  n=$((n + 1))
  echo "$n" > "$WM_COUNT"
  if [ -n "$WM_BLOCK_AT" ] && [ "$n" -ge "$WM_BLOCK_AT" ]; then
    : > "$WM_MARKER"
    sleep 300
  fi
fi
echo "row_a=1"
echo "row_b=2"
exit 0
"""

# THE PRE-FIX SHAPE, AS A FIXTURE. The version of this file that predates the mirror rewrote the
# SUBSTRATE in place and restored it afterwards, so a kill between the write and the restore left
# the substrate MUTATED. This is a faithful MINIMUM of that shape -- not the pre-fix file -- and
# the plant runs it to prove the plant's detector can FAIL, because a detector that cannot fail is
# not a detector.
OLD_IN_PLACE = '''"""THE PRE-FIX SHAPE, AS A FIXTURE: the substrate is rewritten IN PLACE and restored
afterwards, so a kill between the write and the restore leaves it MUTATED."""
import shutil
import subprocess
import sys

substrate, bend = sys.argv[1], sys.argv[2]
shutil.copy(substrate, substrate + ".orig")
src = open(substrate + ".orig").read()
open(substrate, "w").write(src.replace("def pool_refused", "def pool_refused_MUTATED"))
subprocess.run([bend, substrate], capture_output=True, text=True)
shutil.copy(substrate + ".orig", substrate)
'''


def _harness_argv(tree: Path, work: Path) -> list[str]:
    """This file, as a PROGRAM, pointed at a synthetic tree. The plant kills a PROCESS, so the
    harness it kills has to be one."""
    return [sys.executable, str(HERE / "worker-mutate.py"), "--root", str(tree),
            "--work", str(work), "worker"]


def _spawn(argv: list[str], marker: Path, count: Path, block_at: int) -> subprocess.Popen:
    """The harness, in its own PROCESS GROUP, so a kill takes the stub compiler with it."""
    env = dict(os.environ)
    env["WM_MARKER"] = str(marker)
    env["WM_COUNT"] = str(count)
    env["WM_BLOCK_AT"] = str(block_at)
    return subprocess.Popen(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                            env=env, start_new_session=True)


def _kill_group(proc: subprocess.Popen) -> None:
    """SIGKILL the whole group: the harness AND the compiler it is waiting on."""
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
    except (ProcessLookupError, PermissionError):
        proc.kill()
    try:
        proc.wait(timeout=10)
    except subprocess.TimeoutExpired:
        pass


def _wait_for(marker: Path, seconds: float) -> bool:
    """Whether the marker appeared, i.e. whether the compiler was reached."""
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if marker.exists():
            return True
        time.sleep(0.02)
    return False


def plant(root: Path) -> int:
    """THE PLANT: THE SUBSTRATE IS NEVER WRITTEN, AND A KILLED RUN LEAVES IT BYTE-IDENTICAL.

    FOUR CHECKS, and the third is the one that makes the other two mean anything.

      1  THE CONTROL. A full run leaves the substrate byte-identical AND says it measured
         something, so "unchanged" is not "did nothing".
      2  THE KILL. A harness killed while the compiler is running leaves the substrate
         byte-identical. The kill lands on the FIRST MUTATION's run -- the baseline's plain run
         is plain call 1, the first mutation's is 2 -- so the mutated source has ALREADY been
         written, to the MIRROR.
      3  THE FALSIFICATION. The PRE-FIX shape, killed the same way, DOES leave the substrate
         MUTATED. Without this, 1 and 2 are satisfied by a detector that cannot fail.
      4  THE MIRROR IS FAITHFUL. An UNMUTATED COPY behaves the same as before: the mirror's
         rows are the real driver's rows, byte for byte. This is the control for the whole
         mechanism, and it is READ-ONLY on the tree.
    """
    checks = []
    source = driver_of(root, "worker")
    if not source.is_file():
        refuse(f"the plant copies the real driver into a synthetic tree, and it is absent: {source}")
    if not (root / SUBSTRATE).is_dir():
        refuse(f"the substrate tree is absent: {root / SUBSTRATE}")
    with tempfile.TemporaryDirectory(prefix="worker-mutate-plant-") as td:
        tree = Path(td) / "tree"
        (tree / "bin").mkdir(parents=True)
        (tree / "pyproject.toml").write_text("[project]\nname='worker-mutate-plant'\n")
        stub = tree / "bin" / "bend"
        stub.write_text(STUB_BEND)
        stub.chmod(0o755)
        driver = tree / SUBSTRATE / ENGINE / "worker.bend"
        driver.parent.mkdir(parents=True)
        shutil.copy(source, driver)
        work = Path(td) / "work"
        work.mkdir()
        marker = Path(td) / "MARKER"
        count = Path(td) / "COUNT"
        n = len(MUTATIONS["worker"])

        before = digest(driver)
        r = subprocess.run(_harness_argv(tree, work), capture_output=True, text=True)
        after = digest(driver)
        want = f"{n} mutations, {n} applied"
        ok1 = before == after and r.returncode == 0 and want in r.stdout
        checks.append(("1: a full run leaves the substrate BYTE-IDENTICAL, and it MEASURED",
                       ok1, f"unchanged={before == after} rc={r.returncode} "
                            f"said={want in r.stdout!r} out={r.stdout.strip()[-120:]!r}"))

        count.unlink(missing_ok=True)
        marker.unlink(missing_ok=True)
        before = digest(driver)
        proc = _spawn(_harness_argv(tree, work), marker, count, 2)
        landed = _wait_for(marker, 60)
        _kill_group(proc)
        after = digest(driver)
        ok2 = landed and before == after
        checks.append(("2: a harness KILLED mid-run leaves the substrate BYTE-IDENTICAL",
                       ok2, f"the compiler was reached={landed} unchanged={before == after}"))

        count.unlink(missing_ok=True)
        marker.unlink(missing_ok=True)
        before = digest(driver)
        old = Path(td) / "old_in_place.py"
        old.write_text(OLD_IN_PLACE)
        proc = _spawn([sys.executable, str(old), str(driver), str(stub)], marker, count, 1)
        landed = _wait_for(marker, 60)
        _kill_group(proc)
        after = digest(driver)
        ok3 = landed and after != before
        checks.append(("3: the PRE-FIX shape, killed the same way, DOES leave the substrate "
                       "MUTATED -- so 1 and 2 are not vacuous", ok3,
                       f"the compiler was reached={landed} changed={after != before}"))
        shutil.copy(source, driver)

    bend = root / "bin" / "bend"
    if not bend.is_file():
        checks.append(("4: an UNMUTATED COPY behaves the same as before", False,
                       f"the compiler is absent: {bend}"))
    else:
        real_before = digest(source)
        with tempfile.TemporaryDirectory(prefix="worker-mutate-mirror-") as md:
            tree = mirror(root, Path(md))
            a, sa = run(bend, driver_of(root, "worker"))
            b, sb = run(bend, tree / ENGINE / "worker.bend")
        ok4 = sa == CHECKS and sb == CHECKS and a == b and digest(source) == real_before
        checks.append(("4: an UNMUTATED COPY behaves the same as before -- the mirror's rows are "
                       "the real driver's rows", ok4,
                       f"real={len(a)} rows/{sa} mirror={len(b)} rows/{sb} "
                       f"identical={a == b} substrate_unchanged={digest(source) == real_before}"))

    rc = 0
    print("PLANTS -- one direction per check, and the third is the falsifier for the first two.")
    for name, ok, got in checks:
        print(f"  {'PASS' if ok else 'FAIL'}  {name}\n          observed: {got}")
        rc |= 0 if ok else 1
    print(f"PLANTS: {'GREEN' if rc == 0 else 'RED'} ({sum(1 for c in checks if c[1])}/{len(checks)})")
    return rc


def main() -> int:
    ap = argparse.ArgumentParser(
        prog="gates/worker-mutate.py", description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="VERDICT: PASS/FAIL/REFUSED from `gates/gatekit.py`'s own table. A verdict with no "
               "denominator is a claim nobody can check. WRITING: none -- the substrate is never "
               "written; the mutation happens on a copy in a temporary mirror.")
    ap.add_argument("which", nargs="?", default="worker", choices=sorted(MUTATIONS),
                    help="which driver's mutation table to run (default: worker, whose baseline "
                         "emits rows; `jit` has no main() and is REFUSED)")
    ap.add_argument("--root", default=None, help="point at another tree (plant/disarm only)")
    ap.add_argument("--work", default=None, metavar="DIR",
                    help="the directory the MIRROR is built in; it must be OUTSIDE the "
                         "repository. Default: a temporary directory")
    ap.add_argument("--plant", action="store_true",
                    help="assert the plant: the substrate is never written, a killed run leaves "
                         "it byte-identical, and the pre-fix shape does not")
    a = ap.parse_args()
    root = Path(a.root).resolve() if a.root else ROOT
    if a.plant:
        return plant(root)
    if not (root / "pyproject.toml").is_file():
        refuse(f"the repo root is not here: pyproject.toml is absent at {root}")
    if a.work:
        work = Path(a.work).resolve()
        work.mkdir(parents=True, exist_ok=True)
        tmp = None
    else:
        tmp = tempfile.TemporaryDirectory(prefix="worker-mutate-")
        work = Path(tmp.name)
    try:
        # THE MIRROR IS OUTSIDE THE REPOSITORY, and this is a precondition rather than a
        # preference: a mirror inside the tree would be a directory the substrate walk could
        # reach, and the whole point of the mirror is that NOTHING it holds is part of the tree.
        if work.is_relative_to(root):
            refuse(f"the mirror must be built OUTSIDE the repository: {work} is inside {root}")
        which = a.which
        driver = driver_of(root, which)
        before = digest(driver)
        lines, counts, status = measure(root, which, work)
        after = digest(driver)
        if status == TIMED_OUT:
            refuse(f"the baseline of {which}.bend never finished within {TIMEOUT}s")
        if status == COLD:
            refuse(f"the baseline of {which}.bend does not check: {WARM} was not said")
        if status == VACUOUS:
            refuse(f"the mutation table for {which}.bend is {lines[0]}")
        for line in lines:
            print(line)
        total = len(MUTATIONS[which])
        print()
        print(f"BLIND SPOTS ({counts['blind']} of {total} mutations moved nothing):")
        for line in lines:
            if "BLIND SPOT" in line:
                print("  " + line.split("  <--")[0].strip())
        code = PASS
        if after != before:
            code = FAIL
            print(f"THE SUBSTRATE CHANGED: {driver} was {before} and is {after}")
        elif counts["stale"]:
            code = FAIL
            print(f"THE TABLE IS STALE: {counts['stale']} of {total} mutation patterns are not "
                  f"in the source")
        print(f"WORKER-MUTATE: {VERDICT[code]} -- {total} mutations, {total - counts['stale']} "
              f"applied, {counts['cold']} did not check, {counts['broke']} checked but did not "
              f"run, {counts['timeout']} timed out, {counts['blind']} blind spots; the substrate "
              f"is {'byte-identical' if after == before else 'CHANGED'} "
              f"(sha256 {before[:16]}... -> {after[:16]}...)")
        return code
    finally:
        if tmp is not None:
            tmp.cleanup()


if __name__ == "__main__":
    sys.exit(main())
