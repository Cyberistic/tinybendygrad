import re, subprocess, sys, os, shutil
F = 'tinybendygrad/codegen/late.bend'
BAK = '/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/late-base.bend'
OUT = '/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode'
shutil.copy(F, BAK)
base = open('/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/full.txt').read().split('\n')
base = [l for l in base if l.strip()]

def run():
  r = subprocess.run(['./bin/bend', F], capture_output=True, text=True)
  t = (r.stdout + r.stderr).strip().split('\n')
  return [l for l in t if l.strip()]

def moved(before, after):
  b, a = set(before), set(after)
  lost = [l for l in before if l not in a]
  new = [l for l in after if l not in b]
  return lost, new

# (name, old, new) -- ONE entry per ported rule.
MUT = [
 ('PSEUDO_OPS: drop BARRIER', 'O.OpsAFTER{}, O.OpsBARRIER{}, O.OpsGROUP{}', 'O.OpsAFTER{}, O.OpsGROUP{}'),
 ('live range: backward walk becomes forward', 'ra_lr.go(List.reverse(&2, RaUop, ops), U32.sub(ra_nm(s), 1), s)',
  'ra_lr.go(ops, U32.sub(ra_nm(s), 1), s)'),
 ('live range: dedup(u.src) becomes identity', 'Bool.pick(List<&2, U32>, u32_in(r, s), acc,', 'Bool.pick(List<&2, U32>, False{}, acc,'),
 ('live range: loop-interval append dropped', 'ra_lr.d2.put(t, v, ra_hi(lp, tb_last(t, v)))', 't'),
 ('loops: max user becomes first user', 'ra_lastuse.go(ops, 0, k, 0)', 'ra_lastuse.go(ops, 0, k, 4294967295)'),
 ('loops: the RANGE bound flipped', 'U32.is_lt(lo, RaEn.v(e))', 'U32.is_lt(RaEn.v(e), lo)'),
 ('live[v] = alloc(...) dropped', 'def ra_lv(+s: RaSt, +v: U32, +r: U32) -> RaSt:\n  ra_st.lv(s, tb_put(RaSt.lv(s), v, r, Nil{}))',
  'def ra_lv(+s: RaSt, +v: U32, +r: U32) -> RaSt:\n  s'),
 ('alloc: first-wins becomes last-wins', 'ra_alloc.keep(Bool.or(RaBd.f(a), U32.is_lt(RaBd.d(a), RaBd.d(ra_key(lv, lr, r, i, nmx)))),',
  'ra_alloc.keep(Bool.or(RaBd.f(a), U32.is_lt(RaBd.d(ra_key(lv, lr, r, i, nmx)), RaBd.d(a))),'),
 ('alloc: the seed no longer yields', 'Bool.or(RaBd.f(a), U32.is_lt', 'Bool.or(False{}, U32.is_lt'),
 ('alloc: free does not have priority', 'ra_key(+lv: RaTb, +lr: RaTb, r: U32, i: U32, +nmx: U32) -> RaBd:\n  RaBd{ra_dist(tb_vs(lr, ra_linv(RaTb.es(lv), r)), i, nmx), r, ra_linv(RaTb.es(lv), r), False{}}',
  'ra_key(+lv: RaTb, +lr: RaTb, r: U32, i: U32, +nmx: U32) -> RaBd:\n  RaBd{0, r, ra_linv(RaTb.es(lv), r), False{}}'),
 ("alloc: the END/BACKEDGE use-skip dropped", 'def ra_uses.ex(ex: Bool, +s: RaSt, +i: U32, ss: List<&2, U32>, +ops: List<&2, RaUop>) -> RaSt:\n  match ex:\n    case True{} : s',
  'def ra_uses.ex(ex: Bool, +s: RaSt, +i: U32, ss: List<&2, U32>, +ops: List<&2, RaUop>) -> RaSt:\n  match ex:\n    case True{} : ra_uses.go(ss, i, s, ops)'),
 ('a non-Register src is no longer skipped', 'ra_use.got(U32.is_ne(v, u32_none()),', 'ra_use.got(True{},'),
 ("live.get is a zero test again (W5b)", 'ra_use.got(U32.is_ne(v, u32_none()), Bool.not(tb_has(RaSt.lv(s), v)), s, i, v)',
  'ra_use.got(U32.is_ne(v, u32_none()), U32.is_ne(tb_get(RaSt.lv(s), v), u32_none()), s, i, v)'),
 ('the i+1 for a non-RANGE def becomes i', 'Bool.pick(U32, lt_is_range(op), i, U32.add(i, 1))', 'Bool.pick(U32, lt_is_range(op), i, i)'),
 ('two-address: the cons reorder dropped', 'Bool.pick(List<&2, U32>, RaSt.ta(s),\n            ra_tw(ra_uses_tw(RaSt.lv(s), RaSt.ops(s), ss), ra_cons(RaSt.un(s), v)),\n            ra_cons(RaSt.un(s), v))',
  'Bool.pick(List<&2, U32>, RaSt.ta(s),\n            ra_cons(RaSt.un(s), v),\n            ra_cons(RaSt.un(s), v))'),
 ('two-address: uses[0] goes last instead of first', 'ra_tw.go(us, t, Bool.pick(List<&2, U32>, u32_in(us, r), pre,\n                                              List.append(&2, U32, pre, [r])))',
  'ra_tw.go(us, t, Bool.pick(List<&2, U32>, u32_in(us, r), List.append(&2, U32, pre, [r]), pre))'),
 ('two-address: only the head def is reordered', 'ra_defs.go(r, ra_def(ra_cons2(s, ss, v), s, i, op, v), i, op, ss, un)',
  'ra_defs.go(r, ra_def(ra_cons(un, v), s, i, op, v), i, op, ss, un)'),
 ('sorted_uses: the name tiebreak dropped', 'su_le.n0(String.is_le(n, m), String.eq(n, m),\n            U32.is_le(x, y))))', 'su_le.n0(True{}, False{}, True{})))'),
 ('sorted_uses: lr[k][0] tiebreak dropped', 'su_le.n0(U32.is_le(f, g), U32.is_eq(f, g),\n          su_le.n0(String.is_le(n, m), String.eq(n, m),\n            U32.is_le(x, y))))',
  'su_le.n0(U32.is_le(f, g), U32.is_eq(f, g),\n          su_le.n0(True{}, False{}, True{})))'),
 ('sorted_uses: the next-use distance is constant', 'Su{ra_dist(tb_vs(lr, v), i, 0), at(tb_vs(lr, v), 0n),', 'Su{0, at(tb_vs(lr, v), 0n),'),
 ('prologue: used_in_loop is never filtered', 'Bool.pick(List<&2, U32>, ra_inloop(tb_vs(lr, RaEn.k(en)), i, e),', 'Bool.pick(List<&2, U32>, True{},'),
 ('prologue: the constraint subset test is an OR', 'ra_blk.go(t, es, Bool.and(acc, ra_invals(es, r)))', 'ra_blk.go(t, es, Bool.or(acc, ra_invals(es, r)))'),
 ('prologue: live_in[v] is not written', 'ra_st.in(ra_lv(s, v, r), v, r)', 'ra_lv(s, v, r)'),
 ('prologue: the push is dropped', 'ra_st.ns(s, List.append(&2, RaTb, RaSt.ns(s),\n    [RaSt.in(ra_w.go(', 'ra_st.ns(s, List.append(&2, RaTb, RaSt.ns(s),\n    [tb_new()]))\n#(\n    [RaSt.in(ra_w.go('),
 ('prologue: the set union becomes a concatenation of live only', 'ra_used(RaSt.lv(s), RaSt.sp(s), i, RaSt.lr(s), tb_get(RaSt.lp(s), i))',
  'ra_used(RaSt.lv(s), RaSt.sp(s), i, RaSt.lr(s), 4294967295)'),
 ('epilogue: the reload condition dropped', 'Bool.and(tb_has(RaSt.lv(s), v), U32.is_eq(tb_get(RaSt.lv(s), v), r))', 'False{}'),
 ('epilogue: it reloads everything', 'def ra_epi.ok(+s: RaSt, +v: U32, r: U32) -> Bool:\n  False{}', 'def ra_epi.ok(+s: RaSt, +v: U32, r: U32) -> Bool:\n  Bool.and(tb_has(RaSt.lv(s), v), U32.is_eq(tb_get(RaSt.lv(s), v), r))'),
 ('epilogue: the pop is dropped', 'ra_st.ns(s, ra_pop(RaSt.ns(s)))', 'RaSt.ns(s)'),
 ('fill: the spill slot is never recorded', 'ra_fill.slot(U32.is_ne(tb_get(RaSt.sp(s), v), 0), s, v)', 's'),
 ('fill: the fill is never recorded', 'ra_fill.put(ra_alloc(cs, s, i), i, v)', 'Al{Al.r(ra_alloc(cs, s, i)), s}'),
 ('fill: the state is the pre-alloc state again', 'ra_st.ib(Al.st(a), tb_put(RaSt.ib(Al.st(a)), i, 0,\n                                        tb_pput(tb_vs(RaSt.ib(Al.st(a)), i), v, Al.r(a))))',
  'ra_st.ib(s, tb_put(RaSt.ib(s), i, 0,\n                      tb_pput(tb_vs(RaSt.ib(s), i), v, Al.r(a))))'),
 ('live.pop becomes a no-op', 'Al{RaBd.r(b), ra_st.lv(s, ra_del(RaSt.lv(s), RaBd.v(b)))}', 'Al{RaBd.r(b), s}'),
 ('reals[i][v] appends instead of replacing', 'ra_st.re(s, tb_pset(RaSt.re(s), i, v, r))', 'ra_st.re(s, tb_put(RaSt.re(s), i, 0, [v, r]))'),
 ('the pseudo-op continue is dropped', 'ra_lr.lp(lt_is_range(RaUop.op(u)), ra_lr.ps(ra_is_pseudo(RaUop.op(u)), s, i, u), i,',
  'ra_lr.lp(lt_is_range(RaUop.op(u)), ra_lr.d2(ra_lr.d1(s, i, u), i, u), i,'),
 ('the main loop starts at 1', 'ra_run.go(ops, ra_lr.go(ops, U32.sub(ra_nm(s), 1), s), 0)', 'ra_run.go(ops, ra_lr.go(ops, U32.sub(ra_nm(s), 1), s), 1)'),
 ('rewrite: the pseudo-op answer is not None', 'Bool.pick(String, ps, "-",', 'Bool.pick(String, ps, O.Ops.name.of(RaUop.op(u)),'),
 ('rewrite: the tag rewrite is not threaded', 'ra_after(s, u), List.append(&2, Em, rw_before(s, i), [Em{RaUop.op(u), ""}]))', 'Nil{}, List.append(&2, Em, rw_before(s, i), [Em{RaUop.op(u), ""}]))'),
 ('the row order moves the per-uop rows first', 'List.append(&2, String, ra_lead(pre, s),\n              List.append(&2, String, ra_a_lines.g(pre, s, ra_keys(RaSt.re(s)), Nil{}),\n                         ra_tail(pre, s)))',
  'List.append(&2, String, ra_a_lines.g(pre, s, ra_keys(RaSt.re(s)), Nil{}),\n              List.append(&2, String, ra_lead(pre, s), ra_tail(pre, s)))'),
 ('the row sorts by intern index instead of by text', 'String.join(List.sort(String, sle, ra_pairs.go(tb_vs(t, i), un, tb_vs(t, i), Nil{})), " ")',
  'String.join(ra_pairs.go(tb_vs(t, i), un, tb_vs(t, i), Nil{}), " ")'),
 ('the intern table loses v4', 'Ru{"v4", 10, [1, 2]}]', 'Ru{"v4", 9, [1, 2]}]'),
]
print('%-52s %s' % ('MUTATION', 'ROWS MOVED'))
print('-' * 100)
for name, old, new in MUT:
  src = open(BAK).read()
  if old not in src:
    print('%-52s %s' % (name[:52], 'DID NOT APPLY'))
    continue
  try:
    open(F, 'w').write(src.replace(old, new, 1))
    got = run()
  finally:
    open(F, 'w').write(src)
  lost, added = moved(base, got)
  if not lost and not added:
    print('%-52s %s' % (name[:52], 'NOTHING (blind spot)'))
  else:
    print('%-52s %s' % (name[:52], ', '.join(l.split('=')[0] for l in lost + added)))
shutil.copy(BAK, F)
print()
print('restored:', run() == base)
