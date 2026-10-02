#!/usr/bin/env python
# THE MUTATION TABLE for tinybendygrad/mixin/movement.bend, MEASURED.
#
# Each mutation is one (old, new) pair applied to a COPY of the file, the gate is run,
# and the rows that differ from the baseline are recorded. A mutation that moves
# NOTHING is a measurement of a blind spot and is reported as such -- it is not
# hidden, and it is not counted as a pass.
import subprocess, sys, os, tempfile, shutil, re

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
assert os.path.isdir(os.path.join(REPO, 'bin')), REPO
SRC = os.path.join(REPO, 'tinybendygrad/mixin/movement.bend')
BEND = os.path.join(REPO, 'bin/bend')

MUTS = [
  ("M1  mx_pool_out: drop the (k-1)", "U32.sub(a, U32.mul(b, U32.sub(c, 1)))", "U32.sub(a, U32.mul(b, c))"),
  ("M2  mx_pool_shape.of2: swap o_ and k_",
   "mx_pool_shape.join(lead, mx_pool_out(i, d, k, s), k)",
   "mx_pool_shape.join(lead, k, mx_pool_out(i, d, k, s))"),
  ("M3  mx_pool_perm: swap the ODD and EVEN thirds",
   "mx_cat(mx_range(U32.to_nat(nn)), mx_cat(mx_pool_perm.go(U32.to_nat(ni), nn, U32.add(nn, 1)), mx_pool_perm1(U32.to_nat(ni), nn, 0)))",
   "mx_cat(mx_range(U32.to_nat(nn)), mx_cat(mx_pool_perm1(U32.to_nat(ni), nn, 0), mx_pool_perm.go(U32.to_nat(ni), nn, U32.add(nn, 1))))"),
  ("M4  mx_pool_perm.go: step +2 -> +1",
   "mx_pool_perm.go(p, nn, U32.add(ix, 2))", "mx_pool_perm.go(p, nn, U32.add(ix, 1))"),
  ("M5  mx_pool_f: drop the smax(1, .) clamp",
   "mx_smax1(mx_ceildiv_s(neg, mx_ofd(o, s, d), i))", "mx_ceildiv_s(neg, mx_ofd(o, s, d), i)"),
  ("M6  mxm_as_shape.at: invert the symbolic refusal",
   "  match bad:\n    case True{}: Nil{}\n    case _: [mxm_const_val(ar, mxm_nth_u(srcs, ix))]",
   "  match bad:\n    case True{}: [mxm_const_val(ar, mxm_nth_u(srcs, ix))]\n    case _: Nil{}"),
  ("M7  mxm_szs: read the OFFSET instead of the SIZE",
   "List.append(&2, U32, [MxP.sz(p)], acc)", "List.append(&2, U32, [MxP.lo(p)], acc)"),
  ("M8  mxm_marg.sel3: the catch-all answers MPair, not MDim",
   "    case _: MDim{Nil{}, False{}}", "    case _: MPair{Nil{}}"),
  ("M9  mx_perm_is: drop the mxm_dup conjunct",
   "def mx_perm_is(lt: Bool, dup: Bool) -> Bool: mxm_perm_ok(lt, dup)",
   "def mx_perm_is(lt: Bool, dup: Bool) -> Bool: mxm_perm_ok(lt, False{})"),
  ("M10 mxm_pick_all: drop the List.reverse",
   "List.reverse(&2, U32, mxm_pick.go(xs, ys, Nil{}))", "mxm_pick.go(xs, ys, Nil{})"),
  ("M11 mx_shows.go: prepend instead of append (the printer's own bug)",
   "mx_shows.go(t, List.append(&2, String, acc, [U32.show(x)]))",
   "mx_shows.go(t, List.append(&2, String, [U32.show(x)], acc))"),
  ("M12 mx_dropn: drop the ndim>=ni clamp",
   "Bool.pick(U32, U32.is_lt(nd, ni), 0, U32.sub(nd, ni))", "U32.sub(nd, ni)"),
  ("M13 mx_pool_out: truncate instead of ceildiv",
   "H.ceildiv_u32(U32.sub(a, U32.mul(b, U32.sub(c, 1))), e)",
   "U32.div(U32.sub(a, U32.mul(b, U32.sub(c, 1))), e)"),
  ("M14 mx_pool_kid: i*f + d -> i*f",
   "U32.mul(k, U32.add(U32.mul(i, f), d))", "U32.mul(k, U32.mul(i, f))"),
  ("M15 mxm_shape.sel: the ladder's arms the other way round",
   "    case True{}: mxm_shape.ord(m, ps)\n    case _: mxm_shape.sel2(dim, pair, m, ps)",
   "    case True{}: mxm_shape.sel2(dim, pair, m, ps)\n    case _: mxm_shape.ord(m, ps)"),
  ("M16 mxm_ys: read the arg of src[0] instead of the node's own arg",
   "def mxm_ys(ar: O.Arena, i: U32) -> List<&2, U32>:\n  mxm_ys.of(O.Arena.arg(ar, i))",
   "def mxm_ys(ar: O.Arena, i: U32) -> List<&2, U32>:\n  mxm_ys.of(O.Arena.arg(ar, O.Arena.src0(ar, i)))"),
  # --- THE WRITE HALF (Section I). One mutation per wrapper rule, and each one is the
  # mistake the gate has to catch rather than an arbitrary edit.
  ("W1  mxw_stk: PREPEND the CONST index instead of appending",
   "mxw_stk(t, O.Found.ar(G.c1(ar, v)), List.append(&2, U32, acc, [O.Found.i(G.c1(ar, v))]))",
   "mxw_stk(t, O.Found.ar(G.c1(ar, v)), List.append(&2, U32, [O.Found.i(G.c1(ar, v))], acc))"),
  ("W2  mxw_pairs_node2: SWAP the two shape args (self|a|b -> self|b|a)",
   "O.UOp.new(ar, op, [T.Tensor.u(t), O.Found.i(a), O.Found.i(b)], O.ANone{}, O.TNone{})",
   "O.UOp.new(ar, op, [T.Tensor.u(t), O.Found.i(b), O.Found.i(a)], O.ANone{}, O.TNone{})"),
  ("W3  mxw_reshape: invert the identity test",
   "  mxw_pick(mxw_same(T.Tensor.ar(made), T.Tensor.u(made), T.Tensor.u(t)), t, made)",
   "  mxw_pick(Bool.not(mxw_same(T.Tensor.ar(made), T.Tensor.u(made), T.Tensor.u(t))), t, made)"),
  ("W4  mxw_permute: invert the order test",
   "mxw_pick(O.eq_u32(ys, MO.mo_range(mxw_len_nat(mxw_dims_of(T.Tensor.ar(t), T.Tensor.u(t))))),",
   "mxw_pick(Bool.not(O.eq_u32(ys, MO.mo_range(mxw_len_nat(mxw_dims_of(T.Tensor.ar(t), T.Tensor.u(t))))))),"),
  ("W5  mxw_any: test ALL-ZERO instead of SOME-NON-ZERO",
   "Bool.or(sofar, Bool.not(U32.is_zero(f)))", "Bool.or(sofar, U32.is_zero(f))"),
  ("W6  mxw_flip_new: give FLIP a SECOND src (the flags as a STACK)",
   "O.UOp.new(T.Tensor.ar(t), O.OpsFLIP{}, [T.Tensor.u(t)], O.ATuple{flags}, O.TNone{})",
   "O.UOp.new(T.Tensor.ar(t), O.OpsFLIP{}, [T.Tensor.u(t), O.Found.i(G.mstack(T.Tensor.ar(t), flags))], O.ATuple{flags}, O.TNone{})"),
  ("W7  mxw_shape_of: the False arm answers Nil instead of the fold",
   "    case _ False{}: mxw_fold_shape(ar, u)", "    case _ False{}: Nil{}"),
  ("W8  mxw_dims_of: fuel 0 instead of Arena.budget",
   "mxw_shape_of(O.Arena.budget(ar), mxw_mv(O.Arena.op(ar, u)), ar, u)",
   "mxw_shape_of(0n, mxw_mv(O.Arena.op(ar, u)), ar, u)"),
  ("W9  mxw_stk: build the STACK in a FRESH arena, not the grown one",
   "    case Nil{}: G.mstack(ar, acc)", "    case Nil{}: G.mstack(O.Arena.empty(), acc)"),
  ("W10 mxw_count: count the ROOT only, not the toposort",
   "U32.from_nat(List.length(&2, U32, O.UOp.toposort(O.Arena.budget(ar), ar, u)))",
   "U32.from_nat(1n)"),
  ("W11 mxw_reshape: the identity test reads the BASE's arena (the aliasing slip)",
   "  mxw_pick(mxw_same(T.Tensor.ar(made), T.Tensor.u(made), T.Tensor.u(t)), t, made)",
   "  mxw_pick(mxw_same(T.Tensor.ar(t), T.Tensor.u(made), T.Tensor.u(t)), t, made)"),
]


def run(path):
  r = subprocess.run([BEND, path], capture_output=True, text=True, timeout=900)
  if r.returncode != 0:
    return None
  return r.stdout


def rows(text):
  if text is None:
    return None
  d = {}
  for line in text.strip().split('\n'):
    if '=' in line:
      k, v = line.split('=', 1)
      d[k.strip()] = v.strip()
  return d


base = rows(run(SRC))
if base is None:
  print("BASELINE FAILED TO RUN"); sys.exit(1)
print(f"baseline: {len(base)} rows\n")

print(f"{'mutation':52s} | {'rows moved':>10s} | rows")
print("-" * 120)
for name, old, new in MUTS:
  src = open(SRC).read()
  if old not in src:
    print(f"{name:52s} | {'ANCHOR?':>10s} | old text not found -- MUTATION NOT APPLIED")
    continue
  # THE COPY MUST LIVE BESIDE THE ORIGINAL: the file's imports are RELATIVE
  # (`./../helpers.bend`, `./op.bend`), so a copy in /tmp cannot resolve them and every
  # mutation would read as REFUSED.
  tmp = tempfile.NamedTemporaryFile('w', suffix='.bend', delete=False,
                                    dir=os.path.dirname(SRC), prefix='_mxmmut')
  tmp.write(src.replace(old, new, 1))
  tmp.close()
  got = rows(run(tmp.name))
  os.unlink(tmp.name)
  if got is None:
    print(f"{name:52s} | {'REFUSED':>10s} | does not compile / does not run")
    continue
  moved = sorted(k for k in set(base) | set(got) if base.get(k) != got.get(k))
  mark = "  <== BLIND SPOT" if not moved else ""
  print(f"{name:52s} | {len(moved):>10d} | {', '.join(moved) if moved else '-'}{mark}")
