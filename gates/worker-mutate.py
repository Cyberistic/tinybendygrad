#!/usr/bin/env python3
"""The MEASURED mutation table for tinybendygrad/engine/{jit,worker}.bend.

Each mutation is a one-line text substitution applied to the working copy, the
interpreter lane is re-run, and the rows that DIFFER from the baseline are
recorded. A mutation that moves nothing is a BLIND SPOT and is reported as one --
`device.bend`'s "a mutation that moves nothing is information about the GATE, and the
response is to build the fixture it is asking for".

    python3 .agents/slop/probe/mutate.py jit
    python3 .agents/slop/probe/mutate.py worker
"""
import subprocess, sys, os, shutil

BEND = ["./bin/bend"]

MUTATIONS = {
 "jit": [
  ("M1  jt_refusal: names check dropped",
   'def jt_refusal.at(+r: Maybe<&2, String>, ar: O.Arena, c: Cap, info: List<&2, InInfo>) -> Maybe<&2, String>:\n  Bool.pick(Maybe<&2, String>, Bool.not(has_str(r)), jt_info_refusal(ar, c, info), r)',
   'def jt_refusal.at(+r: Maybe<&2, String>, ar: O.Arena, c: Cap, info: List<&2, InInfo>) -> Maybe<&2, String>:\n  jt_info_refusal(ar, c, info)'),

  ("M2  jt_refusal: info check dropped",
   'def jt_refusal.at(+r: Maybe<&2, String>, ar: O.Arena, c: Cap, info: List<&2, InInfo>) -> Maybe<&2, String>:\n  Bool.pick(Maybe<&2, String>, Bool.not(has_str(r)), jt_info_refusal(ar, c, info), r)',
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
   'def prep_dup_refusal(+bases: List<&2, U32>) -> Maybe<&2, String>:\n  Bool.pick(Maybe<&2, String>, Bool.not(U32.is_eq(j_n(bases), j_n(j_adds(bases, Nil{})))),\n            Some{m_dup()}, None{})',
   'def prep_dup_refusal(+bases: List<&2, U32>) -> Maybe<&2, String>:\n  Bool.pick(Maybe<&2, String>, U32.is_eq(j_n(bases), j_n(j_adds(bases, Nil{}))),\n            Some{m_dup()}, None{})'),

  ("M10 nr_next: the CHILDREN go AFTER the siblings (the ORDER)",
   'def nr_next(x: JRet, t: List<&2, JRet>) -> List<&2, JRet>:\n  match x:\n    case RNone{}: t\n    case RTensors{n}: t\n    case ROther{nm}: t\n    case RSeq{kids}: List.concat(&2, JRet, [t, kids])',
   'def nr_next(x: JRet, t: List<&2, JRet>) -> List<&2, JRet>:\n  match x:\n    case RNone{}: t\n    case RTensors{n}: t\n    case ROther{nm}: t\n    case RSeq{kids}: List.concat(&2, JRet, [kids, t])'),

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
   'def pool_make(+pool: Maybe<&2, Pool>, id: U32, +parallel: U32, maxtasks: U32) -> Maybe<&2, Pool>:\n  Bool.pick(Maybe<&2, Pool>, has_pool(pool), pool, pool_new(id, parallel, maxtasks))',
   'def pool_make(+pool: Maybe<&2, Pool>, id: U32, +parallel: U32, maxtasks: U32) -> Maybe<&2, Pool>:\n  pool_new(id, parallel, maxtasks)'),

  ("W4  terminated: the pool-existed test inverted",
   'def terminated(pool: Maybe<&2, Pool>) -> Bool:\n  has_pool(pool)',
   'def terminated(pool: Maybe<&2, Pool>) -> Bool:\n  Bool.not(has_pool(pool))'),

  ("W5  mod_cleared: only `__file__` is cleared",
   'def mod_cleared(+x: Mod) -> Mod:\n  Mod{Mod.nm(x), None{}, None{}}',
   'def mod_cleared(+x: Mod) -> Mod:\n  Mod{Mod.nm(x), None{}, Mod.spec(x)}'),

  ("W6  mod_restore: the `now` arm replaced by `saved` (the SETATTR arm dies)",
   'def mod_restore(+saved: Maybe<&2, String>, now: Maybe<&2, String>) -> Maybe<&2, String>:\n  Bool.pick(Maybe<&2, String>, missing_is_none(saved), now, saved)',
   'def mod_restore(saved: Maybe<&2, String>, now: Maybe<&2, String>) -> Maybe<&2, String>:\n  Bool.pick(Maybe<&2, String>, Bool.not(missing_is_none(saved)), now, saved)'),

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
   'def sch_puts(xs: List<&2, Task>, acc: List<&2, String>) -> List<&2, String>:\n  match xs:\n    case Nil{}: acc\n    case +h <> t: sch_puts(t, List.append(&2, String, acc, [sch_one(h)]))',
   'def sch_puts(xs: List<&2, Task>, acc: List<&2, String>) -> List<&2, String>:\n  match xs:\n    case Nil{}: List.reverse(&2, String, acc)\n    case +h <> t: sch_puts(t, List.append(&2, String, acc, [sch_one(h)]))'),

  ("W13 eq_mstr: `None` equals a `Some`",
   '    case None{} Some{b}: False{}\n    case Some{a} None{}: False{}',
   '    case None{} Some{b}: True{}\n    case Some{a} None{}: True{}'),
 ],
}


def run(path):
    """`--check-only` answers WHETHER IT CHECKS and the plain run answers THE ROWS.
    Asking one invocation for both does not work: the interpreted lane prints the rows
    and does not print the verdict, so a script that greps for `ALL PROOFS CHECK` in
    the row output reports a green file as BROKEN. Measured, in this script."""
    c = subprocess.run(BEND + [path, "--check-only"], capture_output=True, text=True, timeout=1200)
    ok = "ALL PROOFS CHECK" in (c.stdout + c.stderr)
    r = subprocess.run(BEND + [path], capture_output=True, text=True, timeout=1200)
    out = {}
    for line in r.stdout.split("\n"):
        line = line.rstrip()
        if "=" in line and not line.startswith("opened"):
            k, v = line.split("=", 1)
            out[k] = v
    return out, ok


def main():
    which = sys.argv[1] if len(sys.argv) > 1 else "jit"
    path = "tinybendygrad/engine/%s.bend" % which
    shutil.copy(path, "/tmp/%s.bend.orig" % which)
    base, ok = run(path)
    assert ok, "baseline does not check"
    print("BASELINE %s: %d rows, ALL PROOFS CHECK" % (which, len(base)))
    moved_nothing = []
    for name, old, new in MUTATIONS[which]:
        src = open("/tmp/%s.bend.orig" % which).read()
        if old not in src:
            print("%-56s NO-OP (pattern not found)" % name)
            moved_nothing.append(name + " [pattern not found]")
            continue
        open(path, "w").write(src.replace(old, new))
        rows, ok2 = run(path)
        shutil.copy("/tmp/%s.bend.orig" % which, path)
        moved = sorted(k for k in set(base) | set(rows) if base.get(k) != rows.get(k))
        tag = "%-56s" % name
        if not ok2:
            print("%s DOES NOT CHECK" % tag)
            moved_nothing.append(name + " [does not check]")
        elif not moved:
            print("%s MOVED NOTHING  <-- BLIND SPOT" % tag)
            moved_nothing.append(name)
        else:
            print("%s %2d rows: %s" % (tag, len(moved), " ".join(moved[:9]) +
                                       (" ..." if len(moved) > 9 else "")))
    open(path, "w").write(open("/tmp/%s.bend.orig" % which).read())
    print()
    print("MUTATIONS THAT MOVED NOTHING (%d):" % len(moved_nothing))
    for m in moved_nothing:
        print("  " + m)


main()