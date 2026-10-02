#!/usr/bin/env python3
"""
nv_ip_mutate.py -- the mutation table for ip.bend.

Every rule in the file is attacked by ONE textual edit, the interpreted lane is
re-run, and the rows are diffed against the CLEAN run.  What is recorded is HOW MANY
ROWS MOVED -- so a rule whose mutation moves nothing is a BLIND SPOT and gets asked
for a fixture instead of being reported as covered.

    python3 .agents/slop/nv_ip_mutate.py            # the whole table
    python3 .agents/slop/nv_ip_mutate.py ru hex8   # only those

A mutation that does not compile, or that changes a row's NAME, counts as moved:
a renamed row is a missing row, which is a failure the differ would catch. The
mutation is applied to the BUILT file (not the parts) and the file is restored from
a copy, so no build step can launder a mutation into a no-op.
"""
import os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, '..', '..'))
IP = os.path.join(ROOT, 'tinybendygrad/runtime/support/nv/ip.bend')
BEND = os.path.join(ROOT, 'bin', 'bend')
CLEAN = os.path.join(HERE, 'nv_ip_interp.txt')

# (label, [(old, new), ...]). Each `old` must appear EXACTLY ONCE in the file or the
# run aborts: a mutation that silently matched nothing is the one failure mode this
# table cannot detect from its own output, so it is made impossible instead. A
# mutation may span several sites because Bend has no forward references -- a rule
# whose threads run through two defs cannot be cut at one of them.
MUT = [
    # --- Stage B: the lookup rules over the GENERATED tables --------------
    # the table is data, so a mutation here is a mutation of a LIST, and that is
    # the point: `const_name.go` must resolve the ONE duplicated name to the same
    # entry `const_name_n.go` counts, or the sharing constant is unreadable.
    # LAST-WINS IS NOT A CONDITION, IT IS A SHAPE. Flipping the guard around the
    # existing self-call cannot do it: `Bool.pick` answers the arm it takes and
    # DROPS the other, so `Bool.pick(_, hit, a, Bool.pick(_, eq, Cv{..}, go(t)))`
    # returns `Cv{hit, c}` at the first match and never recurses. The walk only
    # continues if the recursion sits in the CALLER, so that is what this moves.
    ('const_name.last_wins',
     'def const_name.go(+xs: List<&2, Cn>, +a: Cv, +v: U32) -> Cv:\n  match xs:\n    case Nil{}: a\n    case c <> t:\n      Bool.pick(Cv, Cv.hit(a), a,\n        Bool.pick(Cv, U32.is_eq(Cn.v(c), v), Cv{True{}, c}, const_name.go(t, a, v)))',
     'def const_name.step(+c: Cn, +a: Cv, +v: U32) -> Cv:\n  Bool.pick(Cv, U32.is_eq(Cn.v(c), v), Cv{True{}, c}, a)\n\ndef const_name.go(+xs: List<&2, Cn>, +a: Cv, +v: U32) -> Cv:\n  match xs:\n    case Nil{}: a\n    case c <> t: const_name.go(t, const_name.step(c, a, v), v)'),
    ('const_name_n.no_count',
     '    case c <> t: const_name_n.go(t, bump(U32.is_eq(Cn.v(c), v), n), v)',
     '    case c <> t: const_name_n.go(t, bump(U32.is_lt(Cn.v(c), 0), n), v)'),
    ('const_name.no_walk',
     '    case c <> t:\n      Bool.pick(Cv, Cv.hit(a), a,\n        Bool.pick(Cv, U32.is_eq(Cn.v(c), v), Cv{True{}, c}, const_name.go(t, a, v)))',
     '    case c <> t: a'),
    ('hex8.strip.ascending',
     '    Bool.pick(String, U32.is_gt(n, 255), String.drop(s, 1n),\n      Bool.pick(String, U32.is_gt(n, 15), String.drop(s, 2n), String.drop(s, 3n)))',
     '    Bool.pick(String, U32.is_gt(n, 255), String.drop(s, 1n),\n      Bool.pick(String, U32.is_lt(n, 15), String.drop(s, 2n), String.drop(s, 3n)))'),
    ('hex8.strip.no_mask',
     '                          nib(U32.and(n, 15))], ""), n)',
     '                          nib(n)], ""), n)'),

    # --- Stage C: the arithmetic ------------------------------------------
    ('ru.bit_trick',
     'def ru(+x: U32, +m: U32) -> U32: U32.mul(U32.div(U32.add(x, U32.sub(m, 1)), m), m)',
     'def ru(+x: U32, +m: U32) -> U32: U32.and(U32.add(x, U32.sub(m, 1)), U32.not(U32.sub(m, 1)))'),
    ('rd.trunc',
     'def rd(+x: U32, +m: U32) -> U32: U32.mul(U32.div(x, m), m)',
     'def rd(+x: U32, +m: U32) -> U32: U32.sub(x, U32.mod(x, m))'),
    ('rp.elem.no_header',
     'def rp.elem(+plen: U32) -> U32: cdiv(U32.add(U32.add(plen, 32), 48), rp.msg_size())',
     'def rp.elem(+plen: U32) -> U32: cdiv(U32.add(plen, 48), rp.msg_size())'),
    ('rp.ring_len.is_size',
     'def rp.ring_len() -> U32: U32.mul(rp.msg_size(), rp.msg_count())',
     'def rp.ring_len() -> U32: rp.msg_size()'),
    ('rp.wraps.ge',
     'def rp.wraps(+total: U32, +wp: U32) -> Bool: U32.is_lt(rp.first(total, wp), total)',
     'def rp.wraps(+total: U32, +wp: U32) -> Bool: U32.is_ge(rp.first(total, wp), total)'),
    ('rp.cont_more.ge',
     '  Bool.pick(U32, U32.is_gt(plen, rp.max_payload),\n            cdiv(U32.sub(plen, rp.max_payload), rp.max_payload), 0)',
     '  Bool.pick(U32, U32.is_ge(plen, rp.max_payload),\n            cdiv(U32.sub(plen, rp.max_payload), rp.max_payload), 0)'),
    ('rp.pickw.swap',
     '  Bool.pick(U32, hi, U32.add(U32.mul(U32.from_nat(p), 2), 1), U32.mul(U32.from_nat(p), 2))',
     '  Bool.pick(U32, hi, U32.mul(U32.from_nat(p), 2), U32.add(U32.mul(U32.from_nat(p), 2), 1))'),
    ('reg_len0.21',
     'def reg_len0() -> U32: 22', 'def reg_len0() -> U32: 21'),
    ('seq_bad.ge8',
     'def seq_bad(op: U32) -> Bool: U32.is_gt(op, 8)',
     'def seq_bad(op: U32) -> Bool: U32.is_ge(op, 8)'),
    ('am.page_ok.ge',
     'def am.page_ok(+sz: U32) -> Bool: U32.is_eq(sz, 4096)',
     'def am.page_ok(+sz: U32) -> Bool: U32.is_ge(sz, 4096)'),
    ('door.gb2.always',
     'def door.gb2_bit(+chip: String) -> U32: Bool.pick(U32, String.starts_with(chip, "GB2"), 1073741824, 0)',
     'def door.gb2_bit(+chip: String) -> U32: 1073741824'),
    ('ref.pages_go.or',
     '    case s <> r: ref.pages_go(r, Bool.and(ok, am.page_ok(s)))',
     '    case s <> r: ref.pages_go(r, Bool.or(ok, am.page_ok(s)))'),
    ('wpr.leg4.65535',
     '  wpr.leg5(vram, vga_off, frts_off, boot_off, rd(U32.sub(boot_off, radix3_sz), 65536))',
     '  wpr.leg5(vram, vga_off, frts_off, boot_off, rd(U32.sub(boot_off, radix3_sz), 65535))'),
    ('tr.hit.off_by_one',
     '  Bool.or(refused, U32.is_eq(U32.add(n, 1), fail_at))',
     '  Bool.or(refused, U32.is_eq(n, fail_at))'),
    ('rp.put_wp.no_guard',
     '  rp.put_wp2(e, Bool.pick(U32, Tr.refused(e), Tr.wp(e), wp))',
     '  rp.put_wp2(e, wp)'),
    ('rp.put_wp.arms_swapped',
     '  rp.put_wp2(e, Bool.pick(U32, Tr.refused(e), Tr.wp(e), wp))',
     '  rp.put_wp2(e, Bool.pick(U32, Tr.refused(e), wp, Tr.wp(e)))'),
    ('rp.bumped.no_guard',
     '  rp.bumped2(seq, handle, e, Bool.pick(U32, Tr.refused(e), seq, U32.add(seq, 1)))',
     '  rp.bumped2(seq, handle, e, U32.add(seq, 1))'),
    ('rp.door.before_wp',
     'def rp.wp2(+elem: U32, +t: Tr) -> Tr:\n  rp.wp3(elem, Tr.wp(t), Tr.seq(t), Tr.emit(C_QUEUE_WP(), rp.wp_after(Tr.wp(t), elem), elem,\n                                           rp.msg_count(), t))',
     'def rp.wp2(+elem: U32, +t: Tr) -> Tr:\n  rp.door(rp.wp3(elem, Tr.wp(t), Tr.seq(t), Tr.emit(C_QUEUE_WP(), rp.wp_after(Tr.wp(t), elem), elem,\n                                           rp.msg_count(), t)))'),
    # `rp.door` CONSUMES its trace, so the sequence cannot be bumped after it in a
    # one-line edit. And Bend has NO forward references -- a use of an unseen name
    # is a hole, reported as "an unfilled law is a dead claim" -- so the helper has
    # to land BETWEEN `rp.bumped` and `rp.bump`, which is a second site.
    ('rp.seq.after_door',
     [('def rp.bumped(+seq: U32, +handle: U32, +e: Tr) -> Tr:\n  rp.bumped2(seq, handle, e, Bool.pick(U32, Tr.refused(e), seq, U32.add(seq, 1)))',
       'def rp.bumped(+seq: U32, +handle: U32, +e: Tr) -> Tr:\n  rp.bumped2(seq, handle, e, Bool.pick(U32, Tr.refused(e), seq, U32.add(seq, 1)))\n\ndef rp.late(+seq: U32, +handle: U32, +e: Tr) -> Tr: rp.bumped(seq, handle, rp.door(e))'),
      ('def rp.bump(+e: Tr) -> Tr: rp.door(rp.bumped(Tr.seq(e), Tr.handle(e), e))',
       'def rp.bump(+e: Tr) -> Tr: rp.late(Tr.seq(e), Tr.handle(e), e)')], None),
    ('rp.barrier.dropped',
     'def rp.barrier(+e: Tr) -> Tr: rp.bump(Tr.emit(C_BARRIER(), 0, 0, 0, e))',
     'def rp.barrier(+e: Tr) -> Tr: rp.bump(e)'),
    ('rpc.wait.no_emit',
     'def rpc.wait(+func: U32, +t: Tr) -> Tr: Tr.emit(C_WAIT_RESP(), func, 0, 0, t)',
     'def rpc.wait(+func: U32, +t: Tr) -> Tr: t'),
    ('ref.timeout.no_raise',
     'def ref.timeout(+func: U32, +t: Tr) -> Tr: rpc.raise(func, 4294967295, rpc.wait(func, t))',
     'def ref.timeout(+func: U32, +t: Tr) -> Tr: rpc.wait(func, t)'),
    ('rp.finish.sum_not_xor',
     'def rp.finish(+h: U32, +l: U32) -> U32: U32.xor(h, l)',
     'def rp.finish(+h: U32, +l: U32) -> U32: U32.add(h, l)'),
    ('rp.word2.function_zero',
     '            Bool.pick(U32, U32.is_eq(w, rp.w_function()), func,',
     '            Bool.pick(U32, U32.is_eq(w, rp.w_function()), 0,'),
    ('rp.word2.elem_zero',
     '    Bool.pick(U32, U32.is_eq(w, rp.w_elem()), rp.elem(plen),',
     '    Bool.pick(U32, U32.is_eq(w, rp.w_elem()), 0,'),
    ('rp.which.last_word',
     'def rp.which(+i: U32) -> U32: U32.min(i, U32.sub(rp.nwords(), 1))',
     'def rp.which(+i: U32) -> U32: U32.min(i, U32.sub(rp.nwords(), 2))'),
    ('rp.nwords.19',
     'def rp.nwords() -> U32: 20', 'def rp.nwords() -> U32: 19'),
    ('rpc.minted.no_advance',
     '      Tr{calls, wp, seq, hgen.next(handle), fail_at, refused}',
     '      Tr{calls, wp, seq, handle, fail_at, refused}'),
    ('rpc.func_alloc.is_tag',
     'def rpc.func_alloc() -> U32: Cn.v(const_of("NV_VGPU_MSG_FUNCTION_ALLOC_MEMORY"))',
     'def rpc.func_alloc() -> U32: C_RPC_SEND()'),
    ('am.plen.no_56',
     'def am.plen(+npages: U32) -> U32: U32.add(56, U32.mul(8, npages))',
     'def am.plen(+npages: U32) -> U32: U32.mul(8, npages)'),
    ('rp.entry_off.zero',
     'def rp.entry_off() -> U32: 4096', 'def rp.entry_off() -> U32: 0'),
    ('rpc.am3.no_wait',
     '        rpc.minted(rpc.wait(rpc.func_alloc(), Rq.tr(r))))',
     '        rpc.minted(Rq.tr(r)))'),
]


# Mutations that move NOTHING because the mutant is MATHEMATICALLY THE SAME
# FUNCTION, not because a fixture is missing. Each carries the identity that makes
# it so, because "0 moved" with no reason is indistinguishable from a hole in the
# gate and the two must never be confused in a report.
EQUIV = {
    'rd.trunc': 'x == (x/m)*m + x%m for every U32 x and m > 0, so x - x%m == (x/m)*m',
    'rp.cont_more.ge': 'at plen == max_payload both guards give cdiv(0, m) == 0',
    'rp.pickw.swap': 'rp.finish XORs the two accumulators, so permuting the words '
                     'between them is the identity',
    'rp.which.last_word': 'words 18 and 19 are both zero slots with no rp.word2 arm, '
                          'so 19 and 18 answer the same 0',
}


def run(src):
  r = subprocess.run([BEND, src], capture_output=True, text=True, cwd=ROOT, timeout=900)
  return r.returncode, r.stdout, r.stderr


def main():
  want = sys.argv[1:]
  src = open(IP).read()
  base = rows_of(open(CLEAN).read())
  print('%-24s %5s  %s' % ('mutation', 'moved', 'first rows to move'))
  print('-' * 92)
  results = []
  try:
    for label, old, new in MUT:
      if want and label not in want:
        continue
      if isinstance(old, list):
        if any(src.count(a) != 1 for a, _ in old):
          bad = [src.count(a) for a, _ in old]
          print('%-24s %5s  SITE COUNTS %s -- fix the mutation, do not run it' % (label, '-', bad))
          results.append((label, -1, 'BROKEN'))
          continue
        mut = src
        for a, b in old:
          mut = mut.replace(a, b, 1)
      elif src.count(old) != 1:
        print('%-24s %5s  MATCHES %d TIMES -- fix the mutation, do not run it'
              % (label, '-', src.count(old)))
        results.append((label, -1, 'BROKEN'))
        continue
      else:
        mut = src.replace(old, new, 1)
      # The mutation goes to the REAL path, because ip.bend carries
      # `import ../../../helpers.bend` and a copy anywhere else fails to resolve
      # it -- which is a NOBUILD on every mutation and a table of nothing. The
      # original is restored in the `finally`, and the restore is checked.
      open(IP, 'w').write(mut)
      try:
        rc, out, err = run(IP)
        if rc != 0:
          first = (err.strip().split('\n') or ['?'])[0]
          print('%-24s %5s  NOBUILD: %s' % (label, '-', first[:60]))
          results.append((label, -1, 'NOBUILD'))
          continue
        got = rows_of(out)
        moved = [k for k in base if k in got and got[k] != base[k]]
        lost = [k for k in base if k not in got]
        extra = [k for k in got if k not in base]
        n = len(moved) + len(lost) + len(extra)
        verdict = 'MOVED' if n else ('EQUIV' if label in EQUIV else 'BLIND')
        print('%-24s %5d  %-6s %s' % (label, n, verdict, ','.join((moved + lost + extra)[:3])[:56]))
        results.append((label, n, verdict))
      finally:
        open(IP, 'w').write(src)
  finally:
    if open(IP).read() != src:
      sys.exit('ip.bend was NOT restored -- refusing to report a table from a dirty file')
  print('-' * 92)
  blind = [l for l, n, s in results if s == 'BLIND']
  equiv = [l for l, n, s in results if s == 'EQUIV']
  broke = [l for l, n, s in results if s in ('BROKEN', 'NOBUILD')]
  print('%d mutations: %d moved rows, %d equivalent, %d blind, %d did not run'
        % (len(results), sum(1 for _, n, _ in results if n > 0), len(equiv), len(blind), len(broke)))
  for l in equiv:
    print('  EQUIVALENT %-22s %s' % (l, EQUIV[l]))
  if blind:
    print('BLIND -- a FIXTURE IS WANTED, not a coverage claim: ' + ', '.join(blind))
  if broke:
    print('DID NOT RUN: ' + ', '.join(broke))
  return 1 if blind else 0


def rows_of(text):
  out = {}
  for ln in text.split('\n'):
    if ln:
      k, _, v = ln.partition('=')
      out[k] = v
  return out


if __name__ == '__main__':
  sys.exit(main())
