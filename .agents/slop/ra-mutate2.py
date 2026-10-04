import re, subprocess, sys, shutil
# POST-SPLIT, same prologue as ra-mutate.py: the written file is
# `codegen/late/regalloc.bend`, `run()` prints all three files in Python's order, and
# `q()` re-qualifies each ENTRY with the `LT.` the split forced on a call site.
MUTATED = 'tinybendygrad/codegen/late/regalloc.bend'
FILES = ['linearizer', 'regalloc', 'gater']
_qpat = re.compile(r'(?<![\w.])(%s)(?![\w])' % '|'.join(re.escape(n) for n in
    ['RaEn', 'RaEn.k', 'RaEn.v', 'RaTb', 'RaTb.es', 'at', 'b2u', 'cfg_entry',
     'lt_is_exit', 'lt_is_range', 'lt_key', 'lt_lines', 'lt_op_is', 'row', 'tb_get',
     'tb_has', 'tb_ins', 'tb_keys', 'tb_new', 'tb_pget', 'tb_pput', 'tb_pset',
     'tb_put', 'tb_vput', 'tb_vs', 'u32_none']))

def q(s):
  return _qpat.sub(lambda m: 'LT.' + m.group(1), s)

BAK = '/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/late-base.bend'
shutil.copy(MUTATED, BAK)
base = [l for l in open('/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/full.txt').read().split('\n') if l.strip()]

def run():
  out = []
  for f in FILES:
    for _ in range(5):     # bend 2.0.34 machine-stack-overflows ~1 run in 20
      r = subprocess.run(['./bin/bend', 'tinybendygrad/codegen/late/%s.bend' % f],
                         capture_output=True, text=True)
      t = [l for l in (r.stdout + r.stderr).strip().split('\n') if l.strip()]
      if t: out += t; break
  return out

MUT = [
 ('loops: max user becomes first user',
  'Bool.pick(U32, u32_in(RaUop.ss(u), k), i, best))',
  'Bool.pick(U32, u32_in(RaUop.ss(u), k), Bool.pick(U32, U32.is_eq(best, 0), i, best), best))'),
 ('alloc: free does not have priority',
  'RaBd{ra_dist(tb_vs(lr, ra_linv(RaTb.es(lv), r)), i, nmx), r, ra_linv(RaTb.es(lv), r), False{}}',
  'RaBd{0, r, ra_linv(RaTb.es(lv), r), False{}}'),
 ('prologue: live_in[v] is not written',
  'def ra_w.put(+s: RaSt, +v: U32, +r: U32) -> RaSt:\n  ra_st.in(ra_lv(s, v, r), v, r)',
  'def ra_w.put(+s: RaSt, +v: U32, +r: U32) -> RaSt:\n  ra_lv(s, v, r)'),
 ('prologue: the push is dropped',
  '  ra_st.ns(s, List.append(&2, RaTb, RaSt.ns(s),\n    [RaSt.in(ra_w.go(ra_srt(ra_pro.us(s, i), i, RaSt.lr(s), RaSt.un(s)),\n                     ra_st.in(s, tb_new()), i, u32_none()))]))',
  '  ra_st.ns(s, List.append(&2, RaTb, RaSt.ns(s), [tb_new()]))'),
 ('epilogue: it reloads everything',
  'def ra_epi.ok(+s: RaSt, +v: U32, r: U32) -> Bool:\n  Bool.and(tb_has(RaSt.lv(s), v), U32.is_eq(tb_get(RaSt.lv(s), v), r))',
  'def ra_epi.ok(+s: RaSt, +v: U32, r: U32) -> Bool:\n  True{}'),
 ('epilogue: the pop is dropped',
  'ra_epi.go(RaTb.es(ra_head(RaSt.ns(s))), ra_st.ns(s, ra_pop(RaSt.ns(s))), i)',
  'ra_epi.go(RaTb.es(ra_head(RaSt.ns(s))), s, i)'),
 ('the main loop starts at 1',
  'ra_run.go(ops, ra_lr.go(List.reverse(&2, RaUop, ops), U32.sub(ra_nm(s), 1), s), 0)',
  'ra_run.go(ops, ra_lr.go(List.reverse(&2, RaUop, ops), U32.sub(ra_nm(s), 1), s), 1)'),
 ('rewrite: the tag rewrite is not threaded',
  'List.append(&2, Em, List.append(&2, Em, rw_before(s, i), [Em{RaUop.op(u), ""}]),\n              rw_after(s, u))',
  'List.append(&2, Em, List.append(&2, Em, rw_before(s, i), [Em{RaUop.op(u), ""}]),\n              Nil{})'),
 ('rewrite: the spilled-src fills are dropped',
  'Bool.pick(Em, rw_ispill(s, i, rw_vreg(s, i, u, j)),', 'Bool.pick(Em, False{},'),
 ('reals[i][v]: replace becomes whole-list append',
  'def tb_pset.put(t: RaTb, +b: U32, vs: List<&2, U32>, k: U32, r: U32) -> RaTb:\n  tb_vput(t, b, tb_pput(vs, k, r))',
  'def tb_pset.put(t: RaTb, +b: U32, vs: List<&2, U32>, k: U32, r: U32) -> RaTb:\n  tb_put(t, b, 0, tb_pput(vs, k, r))'),
 ('reals[i][v]: append a second copy of the pair',
  'def ra_set(+s: RaSt, i: U32, v: U32, r: U32) -> RaSt:\n  ra_st.re(s, tb_pset(RaSt.re(s), i, v, r))',
  'def ra_set(+s: RaSt, i: U32, v: U32, r: U32) -> RaSt:\n  ra_st.re(s, tb_pset(tb_pset(RaSt.re(s), i, v, r), i, v, r))'),
 ('the row order moves the per-uop rows first',
  'List.append(&2, String, ra_lead(pre, s),\n              List.append(&2, String, ra_a_lines.g(pre, s, ra_keys(RaSt.re(s)), Nil{}),\n                         ra_tail(pre, s)))',
  'List.append(&2, String, ra_a_lines.g(pre, s, ra_keys(RaSt.re(s)), Nil{}),\n              List.append(&2, String, ra_lead(pre, s), ra_tail(pre, s)))'),
 ('the row reads an INDEX where the oracle reads a NAME',
  'def ra_pair(+vs: List<&2, U32>, +un: List<&2, Ru>, +k: U32) -> String:\n  String.concat([ra_reg(un, k), ">", U32.show(k), "->",\n                 ra_reg(un, tb_pget(vs, k)), ">", U32.show(tb_pget(vs, k))])',
  'def ra_pair(+vs: List<&2, U32>, +un: List<&2, Ru>, +k: U32) -> String:\n  String.concat([U32.show(k), "->", U32.show(tb_pget(vs, k))])'),
 ('the register name is replaced by its index',
  'def ra_reg(+un: List<&2, Ru>, r: U32) -> String:\n  Ru.nm(ra_uni(un, r))',
  'def ra_reg(+un: List<&2, Ru>, r: U32) -> String:\n  U32.show(r)'),
]
print('%-46s %s' % ('MUTATION', 'ROWS MOVED'))
print('-' * 100)
for name, old, new in MUT:
  src = open(BAK).read()
  old, new = q(old), q(new)
  if old not in src:
    print('%-46s %s' % (name[:46], PNA.not_applied()))
    continue
  try:
    open(MUTATED, 'w').write(src.replace(old, new, 1))
    got = run()
  finally:
    open(MUTATED, 'w').write(src)
  lost = [l.split('=')[0] for l in base if l not in got]
  added = [l.split('=')[0] for l in got if l not in base]
  if not lost and not added:
    if got == base:
      print('%-46s %s' % (name[:46], 'NOTHING (blind spot)'))
    else:
      print('%-46s %s' % (name[:46], 'ORDER ONLY'))
  else:
    print('%-46s %s' % (name[:46], ', '.join(lost + added)))
shutil.copy(BAK, MUTATED)
print()
print('restored:', run() == base)
