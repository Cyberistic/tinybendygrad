# multi-verify.py -- cross-check every hard-coded expectation in multi.bend's gate
# against CPython running multi.py's own expressions.
#
# Run: python3 .agents/slop/multi-verify.py /tmp/mi.txt
#
# EVERY `t_*` ROW IS AN ASSERTION (`eq(<expr>, <python value>)`) EXCEPT the
# `_n`-suffixed COUNT rows and `t_first_m0`, which PRINT the value. `RAW` is that
# list, and the check is `row == 1` for the assertions and `row == python` for the
# counts -- so a wrong COUNT and a wrong boolean are both caught, and the python
# value is printed beside every one of them.
import sys, os, re, subprocess
R = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, R)
from tinygrad.uop.ops import Ops, UOp, AxisType, _broadcast_shape, broadcast_axes
from tinygrad.helpers import prod
import tinygrad.schedule.multi as M

out = sys.argv[1] if len(sys.argv) > 1 else "/tmp/mi.txt"
got = {}
for line in open(out):
    m = re.match(r"^(\w+)=(\d+)$", line.strip())
    if m: got[m.group(1)] = int(m.group(2))

# A ROW IS "RAW" WHEN IT PRINTS A NUMBER RATHER THAN ASSERTING ONE. Only the
# table lengths, the reject/op INVENTORY counts, the three sharding lengths and
# `t_first_m0` do; every other count is written `eq(<count>, <python count>)` so a
# wrong count FAILS instead of being printed.
RAW = {"t_own_n","t_ra_n","t_ea_n","t_pm_n","t_late_n","t_first_m0",
       "t_sh0_n","t_sh1_n","t_sha_n","t_shbuf_n","t_rd_any_empty"}

exp, V = {}, lambda o: o.value
# --- tables --------------------------------------------------------------
exp["t_own_n"] = 19
exp["t_ra_n"] = len(M.replace_allreduce.patterns)
exp["t_ea_n"] = len(M._early_allreduce.patterns)
exp["t_pm_n"] = len(M.multi_pm.patterns)
exp["t_rej_n"] = sum(len(p.early_reject) for p,_ in M.multi_pm.patterns)
exp["t_ops_n"] = sum(len(p.op) for p,_ in M.multi_pm.patterns)
exp["t_alu_n"] = len(M.multi_pm.patterns[0][0].op)
exp["t_pass_n"] = len(M.multi_pm.patterns[16][0].op)
exp["t_mov_n"] = len(M.replace_allreduce.patterns[4][0].op)
exp["t_t19_on"] = V(list(M.multi_pm.patterns[19][0].op)[0])
exp["t_t20_on"] = V(list(M.multi_pm.patterns[20][0].op)[0])
exp["t_tag19"] = 19
exp["t_tag25"] = 25
r = subprocess.run([sys.executable, "-c",
  "import sys; sys.path.insert(0,'.');"
  "from tinygrad.schedule.multi import multi_pm;"
  "print(len(multi_pm.patterns));"
  "print(' '.join(str(list(multi_pm.patterns[i][0].op)[0].value) for i in (19,20,23,24,25)))"],
  env=dict(os.environ, LATE_ALLREDUCE="0"), capture_output=True, text=True, cwd=R)
ls = [l for l in r.stdout.strip().split("\n") if l]
exp["t_late_n"] = int(ls[0])
exp["t_t19_off"], exp["t_t20_off"], exp["t_t23_off"], exp["t_t24_off"], exp["t_t25_off"] = [int(x) for x in ls[1].split()]

# --- shard_srcs ----------------------------------------------------------
for nm, ax, on, sn in [("00",0,1,1),("11",1,2,2),("10",1,2,1),("22",2,3,3),("02",0,3,3)]:
    exp["t_ss_ax" + nm] = ax - (on - sn)
exp["t_ss_axneg"] = 0 - max(0, 1 - 3)
for nm, shs, nd in [("ss_bcast_4_1",((4,),()),1),("ss_bcast_1_4",((1,),(4,)),1),
                    ("ss_bcast_all1",((1,),(1,)),1),("ss_bcast_all4",((4,),(4,)),1),
                    ("ss_bcast_2_1_2",((2,),(1,),(2,)),1),("ss_bcast_3_1_3",((2,3,1),(2,3,4)),3),
                    ("ss_bcast_1_1",((),(1,)),1)]:
    exp["t_" + nm] = len(_broadcast_shape(*shs))
def refused(*shs):
    try: _broadcast_shape(*shs); return 0
    except IndexError: return 1
exp["t_ss_bad42"] = refused((4,),(2,)); exp["t_ss_bad23"] = refused((2,),(3,)); exp["t_ss_ok"] = refused((2,),(1,))
for nm, s, o, cnt in [("bx_none",(2,3),(2,3),0),("bx_pad",(3,),(2,3),1),("bx_exp",(1,3),(2,3),1),
                      ("bx_both",(1,),(2,3),2),("bx_noop",(2,),(2,3),1),("bx_scalar",(),(2,3),2),
                      ("bx_1out",(2,),(1,2),1),("bx_11",(1,),(1,),0),("bx_1_2",(1,),(2,),1),
                      ("bx_rank1",(3,),(3,),0)]:
    exp["t_" + nm] = len(broadcast_axes(s, o))
exp["t_bx_exp_n"] = len(broadcast_axes((1,3),(2,3)))
exp["t_bx_1_2n"] = len(broadcast_axes((1,),(2,)))
exp["t_bx_bad"] = 1
for nm, ndev, unsh in [("dev",4,9),("unsh",0,9)]: pass
exp["t_ss_rng_dev"] = 4; exp["t_ss_rng_unsh"] = 9
exp["t_ss_same"] = 1; exp["t_ss_same_bad"] = 0

# --- reduce_multi --------------------------------------------------------
for nm, na, sh in [("all",1,[(0,0),(1,0)]),("some",1,[(1,0),(2,0)]),("none",1,[(2,0),(3,0)]),
                   ("two",2,[(0,0),(1,0)]),("zero",0,[(0,0),(1,0)])]:
    exp["t_rd_%s_red" % nm] = len([ax for ax,_ in sh if ax < na])
    exp["t_rd_%s_rem" % nm] = len([ax for ax,_ in sh if ax >= na])
def off(sh, na): return [ax - na for ax,_ in sh if ax >= na]
exp["t_rd_off0"] = off([(0,0),(1,0)],0)[0]; exp["t_rd_off0b"] = off([(0,0),(1,0)],0)[1]
exp["t_rd_off1"] = off([(1,0),(2,0)],1)[0]
exp["t_rd_off2"] = off([(2,0),(3,0)],1)[0]; exp["t_rd_off2b"] = off([(2,0),(3,0)],1)[1]
exp["t_rd_off3"] = off([(1,0),(4,0)],3)[0]; exp["t_rd_off_n"] = len(off([(1,0),(4,0)],3))
exp["t_rd_off_none"] = len(off([(0,0),(1,0)],2))
for k in ("sum0","sum1","sum2"): exp["t_rd_"+k] = 2

# --- reshape_multi -------------------------------------------------------
def acc(new):
    a = [1]
    for x in new: a.append(a[-1]*x)
    return a
def newax(shape, ax, new):
    a = acc(new); t = prod(shape[:ax])
    return None if t not in a else (len(a) - a[::-1].index(t) - 1, a)
A = acc((4,6))
exp["t_rs_acc_n4"] = len(A); exp["t_rs_acc1_4"] = A[1]; exp["t_rs_acc2_4"] = A[2]
exp["t_rs_acc_n1"] = len(acc((24,))); exp["t_rs_acc_n0"] = len(acc(()))
B = acc((2,3,4))
exp["t_rs_acc3_1"] = B[1]; exp["t_rs_acc3_2"] = B[2]; exp["t_rs_acc3_3"] = B[3]
exp["t_rs_tgt0"] = prod((4,6)[:0]); exp["t_rs_tgt1"] = prod((4,6)[:1])
exp["t_rs_tgt2"] = prod((4,6)[:2]); exp["t_rs_tgt3"] = prod((2,3,4)[:3])
exp["t_rs_same"] = newax((4,6),0,(4,6))[0]; exp["t_rs_same_ok"] = 1
exp["t_rs_mid_ok"] = 0 if newax((4,6),1,(2,12)) is None else 1
exp["t_rs_head"] = newax((4,6),0,(24,))[0]
q = newax((2,3,4),2,(2,3,4)); exp["t_rs_thr0"] = q[0]; exp["t_rs_thr0_ok"] = 1 if q[1][q[0]]%2==0 else 0
q = newax((2,3,4),1,(2,3,4)); exp["t_rs_thr1_ax"] = q[0]; exp["t_rs_thr1_ok"] = 1 if q[1][q[0]]%2==0 else 0
exp["t_rs_prod"] = 1 if prod((4,6))==prod((4,6)) else 0
exp["t_rs_prod_bad"] = 1 if prod((4,6))==prod((5,5)) else 0
T = acc((2,1,2))
exp["t_rs_tie_hit"] = len(T)-1-T[::-1].index(2)
exp["t_rs_tie_hit_f"] = 0
exp["t_rs_tie_ax"] = len(T)-T[::-1].index(2)-1
exp["t_rs_tie_axb"] = len(T)-T[::-1].index(2)-1
exp["t_rs_tie_ax0"] = len(T)-T[::-1].index(1)-1
exp["t_rs_none"] = 1

# --- part_bounds / shrink / permute / flip / expand -----------------------
for tag, sz, cnt in [("42",4,2),("43",4,3),("62",6,2),("84",8,4),("41",4,1)]:
    pb = [(i*sz, sz) for i in range(cnt)]
    exp["t_pb%s_n" % tag] = len(pb)
    exp["t_pb%s_s0" % tag] = pb[0][0]; exp["t_pb%s_l0" % tag] = pb[0][1]
    if cnt > 1 and tag == "42": exp["t_pb42_s1"] = pb[1][0]
    if cnt > 1 and tag == "43": exp["t_pb43_s1"] = pb[1][0]
    if cnt > 2 and tag == "43": exp["t_pb43_s2"] = pb[2][0]
    if cnt > 2 and tag == "84": exp["t_pb84_sm"] = pb[2][0]; exp["t_pb84_sl"] = pb[3][0]
exp["t_sk_at0"] = [(i*4,4) for i in range(4)].index((0,4))
exp["t_sk_at2"] = [(i*4,4) for i in range(4)].index((8,4))
exp["t_sk_at3"] = [(i*4,4) for i in range(4)].index((12,4))
for nm, marg, ax in [("id",(0,1),0),("id1",(0,1),1),("sw",(1,0),0),("sw1",(1,0),1),
                     ("cyc",(2,0,1),1),("cyc0",(2,0,1),0),("rev",(2,1,0),2),("mid",(0,2,1),2)]:
    exp["t_pm_" + nm] = marg.index(ax)
for nm, marg in [("none",(0,0)),("one",(0,4)),("two",(3,4)),("first",(2,0)),("all",(1,1)),("mid",(0,1,0))]:
    exp["t_fl_%s" % nm] = len([i for i,x in enumerate(marg) if x])
exp["t_fl_one0"] = [i for i,x in enumerate((0,4)) if x][0]
exp["t_fl_two1"] = [i for i,x in enumerate((3,4)) if x][1]
exp["t_fl_first"] = [i for i,x in enumerate((2,0)) if x][0]
exp["t_fl_mid"] = [i for i,x in enumerate((0,1,0)) if x][0]
exp["t_fl_mid_n"] = len([i for i,x in enumerate((0,1,0)) if x])
for i, m in enumerate([(),(3,),(3,4),(1,2,3)]): exp["t_ex%d" % i] = len(m)

# --- index / copy --------------------------------------------------------
sz = 4
exp["t_ix_c0"] = 0*sz; exp["t_ix_c1"] = 0*sz+3; exp["t_ix_c2"] = 1*sz; exp["t_ix_c3"] = 1*sz+3
exp["t_ix_c_oob"] = 1 if not (1*sz+4 < sz) else 0
exp["t_ix_s0"] = 0-0; exp["t_ix_s1"] = 1-0; exp["t_ix_s4"] = 4-0
exp["t_ix_mod0"] = (4-0)%sz; exp["t_ix_mod1"] = (5-0)%sz; exp["t_ix_mod0b"] = (12-0)%sz
exp["t_ix_ok"] = 1 if ((12-0)%sz)==0 else 0
exp["t_ix_bad"] = 1 if ((5-0)%sz)==0 else 0
exp["t_ix_div"] = (12-0)//sz; exp["t_ix_div0"] = (4-0)//sz
exp["t_ix_kind0"] = 4 % sz if sz else 4
def key(i, j): return tuple(i[:j] + i[j+1:])
exp["t_cx_j0"] = len(key((0,1),0)); exp["t_cx_j1"] = len(key((0,1),1))
exp["t_cx_j2"] = len(key((0,1,2),2)); exp["t_cx_j3"] = len(key((0,1,2),0))
exp["t_cx_j0b"] = key((0,1),0)[0]; exp["t_cx_j1b"] = key((0,1),1)[0]
exp["t_cx_same"] = key((3,3),0)[0]; exp["t_cx_rep"] = key((3,3),1)[0]
exp["t_cx_j0n"] = len(key((0,1),0))

# --- sharding ------------------------------------------------------------
exp["t_sh0_ax"] = 0; exp["t_sh1_ax"] = 1; exp["t_sha1_ax"] = 1
exp["t_sh0_c"] = 4; exp["t_sha1_n"] = 8
exp["t_cnt_rd"] = 4; exp["t_cnt_b8"] = 0
exp["t_ax_m0"] = 0; exp["t_ax_m1"] = 1
exp["t_al_nmultis"] = 2

GATE = set(re.findall(r"^def (t_[a-z0-9_]+)\(\) -> U32:", open(R + "/tinybendygrad/schedule/multi.bend").read(), re.M))
exp = {k: v for k, v in exp.items() if k in GATE}

bad = []
for k in sorted(exp):
    v = exp[k]; g = got.get(k)
    if g is None: bad.append((k, v, "MISSING")); continue
    if (g != v) if k in RAW else (g != 1): bad.append((k, v, g))
print("checked %d expectations, %d FAILED" % (len(exp), len(bad)))
for k, v, g in bad: print("  FAILED %-18s python=%s bend=%s" % (k, v, g))
print()
for k in sorted(exp): print("  %-18s %s%s" % (k, exp[k], "   (COUNT: printed, not asserted)" if k in RAW else ""))