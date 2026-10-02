#!/usr/bin/env python3
"""Mutation harness for ops_bend.bend. Diffs WHOLE name=value lines, never names."""
import subprocess, pathlib, sys, difflib
F = pathlib.Path('tinybendygrad/runtime/ops_bend.bend')
# THE MUTANT GOES NEXT TO THE ORIGINAL. A scratch copy elsewhere cannot
# resolve `import ../helpers.bend`, and every mutation then reports "did not
# compile" -- the $TMPDIR trap, hit again.
T = F.with_name('ops_bend.mut.bend')
base = F.read_text()
def run(path):
  r = subprocess.run(['./bin/bend', str(path)], capture_output=True, text=True)
  return dict(l.split('=', 1) for l in r.stdout.splitlines() if '=' in l)
B = run(F)
MUT = [
 ('M1', 'Ns.at: drop the 1-based->0-based shift', 'List.get(&2, N, us, U32.to_nat(U32.sub(i, 1)))', 'List.get(&2, N, us, U32.to_nat(i))'),
 ('M2', 'src_text.go: append then reverse (the order bug this file shipped once)', 'src_text.go(t, List.append(&2, String, [U32.show(x)], acc))', 'src_text.go(t, List.append(&2, String, acc, [U32.show(x)]))'),
 ('M3', 'lanes: drop the bool lane', 'Bool.or(is_lane(dt), Bool.or(String.eq(dt, "f32"), String.eq(dt, "bool")))', 'Bool.or(is_lane(dt), String.eq(dt, "f32"))'),
 ('M4', 'LANES_SORTED: reorder', '"dtypes.bool dtypes.f32 dtypes.i32 dtypes.u32"', '"dtypes.f32 dtypes.bool dtypes.i32 dtypes.u32"'),
 ('M5', 'const_arg: every CONST is an int', 'Bool.pick(String, N.isint(n), "c:" ++ N.arg(n), "f:" ++ N.arg(n))', '"c:" ++ N.arg(n)'),
 ('M6', 'param_arg: letter always g', 'letter_str(letter.of(N.addr(n)))', '"g"'),
 ('M6c', 'param_arg: keep the letter, drop the extent', '"k:param:" ++ U32.show(U32.mul(wire_width(n), N.sz(n))) ++ ":"', '"k:param:0:"'),
 ('M6b', 'letter.of: REG is a too', 'Bool.pick(U32, String.eq(addr, "REG"), 2, 3)', 'Bool.pick(U32, String.eq(addr, "REG"), 1, 3)'),
 ('M7', 'vec_arg: every LOAD/STORE carries its width', 'Bool.pick(String, U32.is_eq(n, 1), "-", "k:vec:" ++ U32.show(n))', '"k:vec:" ++ U32.show(n)'),
 ('M8', 'is_buf: accept the r letter too', 'Bool.or(String.ends_with(arg, ":g"), String.ends_with(arg, ":l"))', 'Bool.or(String.ends_with(arg, ":g"), String.ends_with(arg, ":r"))'),
 ('M9', 'buf_extent: the FIRST colon field', 'List.get(&2, String, String.split(arg, \':\'), 2n)', 'List.get(&2, String, String.split(arg, \':\'), 1n)'),
 ('M10', 'is_image_shape: any 3d shape is an image', 'Bool.and(U32.is_eq(ndim, 3), U32.is_eq(last, 4))', 'U32.is_eq(ndim, 3)'),
 ('M11', 'idx_arg: BITCAST arm before the image arm', 'Bool.pick(Res, is_image_shape(N.ndim(Ns.at(us, Ns.src0(us, i))),\n                                  N.last(Ns.at(us, Ns.src0(us, i)))),\n      Res{False{}, idx_image_msg(Ns.at(us, Ns.src0(us, i)))},\n      Bool.pick(Res, idx_is_bitcast(Ns.at(us, Ns.src0(us, i))),\n        Res{True{}, "k:idx:" ++ U32.show(idx_scale(us, i))}, Res{True{}, "-"})))',
   'Bool.pick(Res, idx_is_bitcast(Ns.at(us, Ns.src0(us, i))),\n    Res{True{}, "k:idx:" ++ U32.show(idx_scale(us, i))},\n    Bool.pick(Res, is_image_shape(N.ndim(Ns.at(us, Ns.src0(us, i))),\n                                  N.last(Ns.at(us, Ns.src0(us, i)))),\n      Res{False{}, idx_image_msg(Ns.at(us, Ns.src0(us, i)))}, Res{True{}, "-"})))'),
 ('M12', 'header: nbufs counts every line', 'U32.show(count_bufs(us, us, 1, 0))', 'U32.show(Ns.n(us))'),
 ('M13', 'rstrip1: never strip', 'Bool.pick(String, String.ends_with(s, " "),\n    String.take(s, Nat.sub(String.length(s), 1n)), s)', 's'),
 ('M14', 'has_local: True', 'def has_local() -> Bool: False{}', 'def has_local() -> Bool: True{}'),
 ('M15', 'is_warp1: only X matters', 'Bool.or(U32.is_ne(Lc.lx(l), 1), Bool.or(U32.is_ne(Lc.ly(l), 1), U32.is_ne(Lc.lz(l), 1)))', 'U32.is_ne(Lc.lx(l), 1)'),
 ('M16', 'Tr.step: drop the raise guard', 'Bool.pick(Tr, Tr.refused(t), t,', 'Bool.pick(Tr, False{}, t,'),
 ('M17', 'letter_str: LOCAL prints a letter too', 'Bool.pick(String, U32.is_eq(k, 2), "r", "?")', '"r"'),
 ('M18', 'out_bufs: no dedup', 'H.dedup_u32(out_go(ls, ls, bases(ls), 1, Nil{}))', 'out_go(ls, ls, bases(ls), 1, Nil{})'),
 ('M19', 'a comment-only edit (THE CONTROL)', 'THE SPLIT, stated once and then obeyed', 'THE SPLIT, stated once, and then obeyed'),
 ('M20', 'wire_dtype: void needs no lane either', 'Bool.or(lanes(dt), lane_free(dt))', 'lanes(dt)'),
]
print(f'| # | edit | rows MOVED | first movers |')
print('| --- | --- | --- | --- |')
for name, desc, a, b in MUT:
  if a not in base:
    print(f'| {name} | {desc} | NOT APPLIED | the text did not match |'); continue
  T.write_text(base.replace(a, b, 1))
  r = subprocess.run(['./bin/bend', str(T)], capture_output=True, text=True)
  if not r.stdout:
    print(f'| {name} | {desc} | DID NOT COMPILE | see below |'); continue
  M = dict(l.split('=', 1) for l in r.stdout.splitlines() if '=' in l)
  moved = sorted(k for k in set(B) | set(M) if B.get(k) != M.get(k))
  print(f'| {name} | {desc} | {len(moved)} | {", ".join(moved[:6])}{"..." if len(moved) > 6 else ""} |')
