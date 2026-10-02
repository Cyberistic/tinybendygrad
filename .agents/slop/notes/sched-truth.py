import sys
sys.path.insert(0, "/Users/cyberistic/src/tries/2026-09-30-tinybendygrad")
from tinygrad.uop.ops import UOp, Ops, ParamArg, gate_kernel_sink
from tinygrad.dtype import dtypes, AddrSpace
from tinygrad import schedule as S

def opn(u): return u.op.name
CODE = {Ops.BUFFER: 1, Ops.AFTER: 2, Ops.PARAM: 3, Ops.CALL: 4, Ops.END: 5, Ops.STORE: 6,
        Ops.SINK: 7, Ops.SPECIAL: 8, Ops.CONST: 9, Ops.NOOP: 99}
def code(u): return CODE.get(u.op, 0)

def buf(slot, name):
  return UOp(Ops.BUFFER, src=(UOp(Ops.SPECIAL, arg=name, src=(UOp.const(1),)),),
             arg=ParamArg(slot=slot, dtype=dtypes.i32, size=4, name=name, device="CPU"))

def body(n):
  return UOp(Ops.SINK, src=(UOp(Ops.STORE, src=(UOp.const(0), UOp.const(n))),))

def mark(k):
  return k.src[0].src[0].src[1].val

def enc(xs):
  r = 0
  for x in xs: r = r * 10 + x
  return r

# ---------------------------------------------------------------- fx1
A1, B1 = buf(0, "a"), buf(1, "b")
Vb = UOp.variable("v", 0, 10, dtype=dtypes.i32).bind(3)
Vu = UOp.variable("v", 0, 10, dtype=dtypes.i32)
K1 = UOp(Ops.CALL, src=(body(1), A1))
K2 = UOp(Ops.CALL, src=(body(2), B1, Vb))
E2 = UOp(Ops.END, src=(K2,))
AF1 = UOp(Ops.AFTER, src=(A1, K1))
AF2 = UOp(Ops.AFTER, src=(AF1, E2))
TOP1 = UOp(Ops.SINK, src=(AF2, UOp(Ops.SINK, src=(A1,))))

# ---------------------------------------------------------------- fx2
A2, X2 = buf(0, "a2"), buf(1, "x2")
Ka = UOp(Ops.CALL, src=(body(1), A2))
Kb = UOp(Ops.CALL, src=(body(2), A2))
Kc = UOp(Ops.CALL, src=(body(3), X2))
AFa = UOp(Ops.AFTER, src=(A2, Ka))
AFb = UOp(Ops.AFTER, src=(AFa, Kb))
AFc = UOp(Ops.AFTER, src=(X2, Kc))
TOP2 = UOp(Ops.SINK, src=(AFb, AFc, UOp(Ops.SINK, src=(A2,))))

# ---------------------------------------------------------------- fx3: nested AFTER chain, for buf_uop
A3 = buf(0, "a3")
K3 = UOp(Ops.CALL, src=(body(3), A3))
AG1 = UOp(Ops.AFTER, src=(A3, K3))
AG2 = UOp(Ops.AFTER, src=(AG1, K3))
TOP3 = UOp(Ops.SINK, src=(AG2, UOp(Ops.SINK, src=(A3,))))

# ---------------------------------------------------------------- an AFTER with an illegal source
BAD = UOp(Ops.AFTER, src=(A1, K1, UOp(Ops.SINK, src=(A1,))))

def bad_ok(a):
  try:
    S._split_after(a); return 1
  except AssertionError:
    return 0

def report(nm, TOP):
  ts = list(TOP.toposort(gate_kernel_sink).keys())
  L = S.create_schedule(TOP)
  return len(ts), L

for nm, TOP in (("fx1", TOP1), ("fx2", TOP2)):
  print(f"== {nm} ==")
  ts = list(TOP.toposort(gate_kernel_sink).keys())
  L = S.create_schedule(TOP)
  print("topo_n", len(ts), "lin_n", len(L.src), "lin_op", opn(L))
  print("marks", enc([mark(k) for k in L.src]), "nsrcs", enc([len(k.src) for k in L.src]))
  print("lin_src_ops", [[opn(s) for s in k.src] for k in L.src])

print("== helpers fx1 ==")
print("unwrap_A1", code(_unwrap := S._unwrap_src(A1)), "unwrap_B1", code(S._unwrap_src(B1)))
print("unwrap_Vb", code(S._unwrap_src(Vb)), "unwrap_AF1", code(S._unwrap_src(AF1)))
print("unwrap_AF2", code(S._unwrap_src(AF2)), "unwrap_AFa", code(S._unwrap_src(AFa)))
print("unwrap_bad", code(S._unwrap_src(BAD)))
for nm, x in (("A1", A1), ("AF1", AF1), ("AF2", AF2), ("AG1", AG1), ("AG2", AG2), ("bad", BAD)):
  if bad_ok(x) == 0:
    print(f"split_{nm} RAISED"); continue
  ks, ds = S._split_after(x)
  print(f"split_{nm} ks={len(ks)} ds={len(ds)} ksops={[opn(k) for k in ks]} dsops={[opn(d) for d in ds]}")
print("split_bad_ok", bad_ok(BAD), "split_AF1_ok", bad_ok(AF1))
for nm, x in (("A1", A1), ("AF2", AF2), ("AG2", AG2)):
  print(f"states_{nm}", len(S._states(x)), [opn(s) for s in S._states(x)])
print("bufuop_A1", code(A1.buf_uop), "bufuop_AF1", code(AF1.buf_uop), "bufuop_AF2", code(AF2.buf_uop))
print("bufuop_AG1", code(AG1.buf_uop), "bufuop_AG2", code(AG2.buf_uop), "bufuop_Vb", code(Vb.buf_uop))
print("bv_Vb", int(Vb.is_bound_var), "bv_Vu", int(Vu.is_bound_var), "bv_A1", int(A1.is_bound_var))
print("bv_K2src1", int(K2.src[1].is_bound_var), "bv_K2src2", int(K2.src[2].is_bound_var))
print("bs_K2_K1", int(K1 in K2.backward_slice), "bs_E2_K2", int(K2 in E2.backward_slice))
print("bs_K1_K2", int(K2 in K1.backward_slice))
print("bs_Kb_Ka", int(Ka in Kb.backward_slice))

# the four dicts, reproduced the way create_schedule builds them, for the COUNT rows
def dicts(TOP):
  children, in_degree, writes, reads = {}, {}, {}, []
  for u in TOP.toposort(gate_kernel_sink):
    if u.op is not Ops.AFTER: continue
    kernels, after_deps = S._split_after(u)
    prev_state = S._unwrap_src(u.src[0])
    prev_kernels = set(S._split_after(prev_state)[0]) if prev_state.op is Ops.AFTER else set()
    writes.setdefault(prev_state, []).append((u, tuple(k for k in kernels if k not in prev_kernels)))
    for k in kernels:
      in_degree.setdefault(k, 0)
      kernel_deps = k.src[0].src[1:] if k.op is Ops.END else k.src[1:]
      read_states = [st for s in kernel_deps for st in S._states(s)]
      reads += [(u, k, st) for st in read_states]
      for st in read_states + [st for s in after_deps for st in S._states(s)]:
        if st.op is Ops.AFTER:
          for t in S._split_after(st)[0]:
            children.setdefault(t, []).append(k)
            in_degree[k] += 1
  for u, k, s in reads:
    for a, wks in writes.get(s, []):
      if a is u: continue
      for t in wks:
        if t is not k and t not in k.backward_slice:
          children.setdefault(k, []).append(t)
          in_degree[t] += 1
  return children, in_degree, writes, reads

for nm, TOP, nodes in (("fx1", TOP1, dict(A1=A1, B1=B1, K1=K1, K2=K2, E2=E2, AF1=AF1, AF2=AF2)),
                       ("fx2", TOP2, dict(A2=A2, X2=X2, Ka=Ka, Kb=Kb, Kc=Kc, AFa=AFa, AFb=AFb, AFc=AFc))):
  children, in_degree, writes, reads = dicts(TOP)
  print(f"== dicts {nm} ==")
  print("n_children", len(children), "n_in_degree", len(in_degree), "n_writes", len(writes), "n_reads", len(reads))
  print("zero_deg_order", enc([1 for k, v in in_degree.items() if v == 0]), "n_zero", sum(1 for v in in_degree.values() if v == 0))
  print("deg_K", {k.op.name: v for k, v in in_degree.items()})
  print("kid_K", {k.op.name: [x.op.name for x in v] for k, v in children.items()})
  print("wrk_A", sum(1 for k in writes if k is nodes.get("A1", nodes.get("A2"))))
  print("wr_af", sum(1 for k in writes if k is nodes.get("AF1", nodes.get("AFa"))))
  print("newk_AFb", [opn(t) for a, ks in writes[nodes.get("AF1", nodes.get("AFa"))] for t in ks])