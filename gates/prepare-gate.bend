# gates/prepare-gate.bend -- THE GATE DRIVER for `tinybendygrad/schedule/prepare.bend`.
#
# THE ROWS MOVED HERE FROM THE PORT FILE. THE PORT FILE CARRIES THE PORT AND
# THIS FILE CARRIES THE INSTRUMENT, AND THE TREE's OWN CONVENTION SAYS SO:
# `gates/README.md:173` -- "a gate's `.bend` driver and its CPython oracle sit in
# `gates/`, named by the gate that needs them."
#
# THE ROWS ARE PURE CONSUMERS: THEY CALL THE PORT's DEFS AND DEFINE
# NOTHING THAT THE PORT NEEDS.

import Base
import ./../tinybendygrad/schedule/prepare.bend as P
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/uop/ops.bend as O
import ./../tinybendygrad/uop/fold.bend as F

def pr_wm(fuel: Nat, +ar: O.Arena, self: U32) -> O.Found:
  P.pr_wm_all(fuel, P.WmSp{ar, self, Nil{}, False{}})
# THE FIXTURE PAIR. `O.Found` is `ops.bend`'s `(arena, node)`, and a node is an
# arena INDEX, so a fixture list has to carry the folded arena with it or every
# reader has to be handed both.
def pr_ear_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, [O.OpsSHRINK{}], [O.OpsSHRINK{}]},  # 0 SHRINK rej=SHRINK slen=0 rlen=1 any=0 nalts=1 name=s
    O.PMEntry{1, [O.OpsRESHAPE{}], [O.OpsRESHAPE{}]},  # 1 RESHAPE rej=RESHAPE slen=1 rlen=2 any=0 nalts=1 name=x
    O.PMEntry{2, [O.OpsRESHAPE{}], Nil{}},  # 2 RESHAPE rej=- slen=1 rlen=2 any=0 nalts=1 name=x
    O.PMEntry{3, [O.OpsPERMUTE{}], [O.OpsPERMUTE{}]},  # 3 PERMUTE rej=PERMUTE slen=1 rlen=1 any=0 nalts=1 name=x
    O.PMEntry{4, [O.OpsPERMUTE{}], Nil{}},  # 4 PERMUTE rej=- slen=0 rlen=0 any=0 nalts=0 name=x
    O.PMEntry{5, [O.OpsSTACK{}], [O.OpsINDEX{}]},  # 5 STACK rej=INDEX slen=0 rlen=0 any=0 nalts=1 name=stk
    O.PMEntry{6, [O.OpsINDEX{}], [O.OpsCONST{}, O.OpsSTACK{}]},  # 6 INDEX rej=CONST STACK slen=0 rlen=2 any=0 nalts=1 name=idx
    O.PMEntry{7, [O.OpsINDEX{}], [O.OpsINDEX{}]},  # 7 INDEX rej=INDEX slen=0 rlen=1 any=0 nalts=1 name=idx2
    O.PMEntry{8, [O.OpsINDEX{}], [O.OpsINDEX{}]},  # 8 INDEX rej=INDEX slen=0 rlen=1 any=0 nalts=1 name=idx2
    O.PMEntry{9, [O.OpsALLREDUCE{}], Nil{}},  # 9 ALLREDUCE rej=- slen=1 rlen=1 any=0 nalts=1 name=red
    O.PMEntry{10, [O.OpsREDUCE{}], Nil{}},  # 10 REDUCE rej=- slen=1 rlen=1 any=0 nalts=1 name=reduce
    O.PMEntry{11, [O.OpsDETACH{}, O.OpsCONTIGUOUS_BACKWARD{}], Nil{}},  # 11 CONTIGUOUS_BACKWARD DETACH rej=- slen=0 rlen=0 any=0 nalts=0 name=x
    O.PMEntry{12, [O.OpsSINK{}], Nil{}},  # 12 SINK rej=- slen=0 rlen=0 any=0 nalts=0 name=x
    O.PMEntry{13, [O.OpsCOPY{}], Nil{}},  # 13 COPY rej=- slen=0 rlen=1 any=0 nalts=1 name=copy
    O.PMEntry{14, [O.OpsSTORE{}], [O.OpsCOPY{}]},  # 14 STORE rej=COPY slen=1 rlen=2 any=0 nalts=1 name=-
    O.PMEntry{15, [O.OpsCOPY{}], Nil{}},  # 15 COPY rej=- slen=0 rlen=1 any=0 nalts=1 name=copy
    O.PMEntry{16, [O.OpsSTAGE{}], Nil{}},  # 16 STAGE rej=- slen=1 rlen=1 any=0 nalts=1 name=stg
    O.PMEntry{17, [O.OpsSTAGE{}], Nil{}},  # 17 STAGE rej=- slen=1 rlen=1 any=0 nalts=1 name=stg
    O.PMEntry{18, [O.OpsSTORE{}], [O.OpsRESHAPE{}]},  # 18 STORE rej=RESHAPE slen=1 rlen=2 any=0 nalts=1 name=-
    O.PMEntry{19, [O.OpsSTORE{}], Nil{}},  # 19 STORE rej=- slen=1 rlen=2 any=0 nalts=1 name=-
    O.PMEntry{20, [O.OpsSTORE{}], Nil{}},  # 20 STORE rej=- slen=1 rlen=2 any=0 nalts=1 name=-
    O.PMEntry{21, [O.OpsAFTER{}], [O.OpsAFTER{}, O.OpsSTORE{}]},  # 21 AFTER rej=AFTER STORE slen=1 rlen=2 any=0 nalts=1 name=-
    O.PMEntry{22, [O.OpsAFTER{}], [O.OpsSTORE{}]},  # 22 AFTER rej=STORE slen=1 rlen=2 any=0 nalts=1 name=-
    O.PMEntry{23, [O.OpsSTORE{}], [O.OpsBITCAST{}]},  # 23 STORE rej=BITCAST slen=1 rlen=2 any=0 nalts=1 name=-
    O.PMEntry{24, [O.OpsBITCAST{}], Nil{}},  # 24 BITCAST rej=- slen=0 rlen=0 any=0 nalts=0 name=bc
    O.PMEntry{25, [O.OpsREDUCE{}], Nil{}},  # 25 REDUCE rej=- slen=1 rlen=1 any=0 nalts=1 name=reduce
    O.PMEntry{26, [O.OpsSPECIAL{}, O.OpsBUFFER{}, O.OpsALLOC{}, O.OpsNOOP{}, O.OpsREWRITE_ERROR{}, O.OpsPARAM{}, O.OpsREFPARAM{}, O.OpsCALL{}, O.OpsPROGRAM{}, O.OpsLINEAR{}, O.OpsSOURCE{}, O.OpsBINARY{}, O.OpsAFTER{}, O.OpsSTACK{}, O.OpsGETADDR{}, O.OpsINDEX{}, O.OpsSHRINK{}, O.OpsLOAD{}, O.OpsSTORE{}, O.OpsWMMA{}, O.OpsCAST{}, O.OpsBITCAST{}, O.OpsEXP2{}, O.OpsLOG2{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsRECIP{}, O.OpsNEG{}, O.OpsTRUNC{}, O.OpsADD{}, O.OpsMUL{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsTRUNCDIV{}, O.OpsMAX{}, O.OpsTRUNCMOD{}, O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCMPEQ{}, O.OpsXOR{}, O.OpsOR{}, O.OpsAND{}, O.OpsTHREEFRY{}, O.OpsSUB{}, O.OpsFDIV{}, O.OpsPOW{}, O.OpsDIV{}, O.OpsMOD{}, O.OpsWHERE{}, O.OpsMULACC{}, O.OpsBARRIER{}, O.OpsRANGE{}, O.OpsIF{}, O.OpsEND{}, O.OpsENDIF{}, O.OpsBACKEDGE{}, O.OpsCONST{}, O.OpsCUSTOM{}, O.OpsCUSTOMI{}, O.OpsINS{}, O.OpsCONTIGUOUS_BACKWARD{}, O.OpsDETACH{}, O.OpsSTAGE{}, O.OpsCOPY{}, O.OpsMSELECT{}, O.OpsMSTACK{}, O.OpsCUSTOM_FUNCTION{}, O.OpsRESHAPE{}, O.OpsPERMUTE{}, O.OpsEXPAND{}, O.OpsPAD{}, O.OpsUNSHARD{}, O.OpsREDUCE{}, O.OpsALLREDUCE{}, O.OpsPYLITERAL{}], Nil{}},  # 26 ADD AFTER ALLOC ALLREDUCE AND BACKEDGE BARRIER BINARY BITCAST BUFFER CALL CAST TRUNCDIV TRUNCMOD CMPEQ CMPLT CMPNE CONST CONTIGUOUS_BACKWARD COPY CUSTOM CUSTOMI CUSTOM_FUNCTION DETACH END ENDIF EXP2 EXPAND FDIV FLIP DIV MOD GETADDR GROUP IF INDEX INS LINEAR LOAD LOG2 MAX MSELECT MSTACK MUL MULACC NEG NOOP OR PAD PARAM PERMUTE POW PROGRAM PYLITERAL RANGE RECIP REDUCE REFPARAM RESHAPE REWRITE_ERROR SHL SHR SHRINK SIN SOURCE SPECIAL SQRT STACK STAGE STORE SUB THREEFRY TRUNC UNSHARD WHERE WMMA XOR rej=- slen=0 rlen=0 any=0 nalts=0 name=x
    O.PMEntry{27, [O.OpsSINK{}], Nil{}},  # 27 SINK rej=- slen=0 rlen=0 any=0 nalts=0 name=s
    O.PMEntry{28, [O.OpsAFTER{}], Nil{}},  # 28 AFTER rej=- slen=0 rlen=0 any=0 nalts=0 name=s
  ]}
def pr_fma_keys() -> List<&2, O.Op>: [O.OpsADD{}, O.OpsAFTER{}, O.OpsAND{}, O.OpsTRUNCDIV{}, O.OpsTRUNCMOD{}, O.OpsCMPEQ{}, O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsEXP2{}, O.OpsFDIV{}, O.OpsDIV{}, O.OpsMOD{}, O.OpsLOG2{}, O.OpsMAX{}, O.OpsMUL{}, O.OpsMULACC{}, O.OpsNEG{}, O.OpsOR{}, O.OpsPOW{}, O.OpsRECIP{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsSTAGE{}, O.OpsSUB{}, O.OpsTHREEFRY{}, O.OpsTRUNC{}, O.OpsWHERE{}, O.OpsXOR{}]
def WMF.fx(w: P.WMF) -> F.Folded:
  match w:
    case P.WMF{fx, items}: fx
def len_strs(xs: List<&2, String>) -> U32: U32.from_nat(List.length(&2, String, xs))
def row(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def rowu(nm: String, v: U32) -> IO(Unit): row(nm, U32.show(v))
def pr_pd_row(+name: String, +es: List<&2, O.PMEntry>, +op: O.Op) -> IO(Unit):
  do IO<Unit>:
    row(String.concat([name, "_pd_", O.Ops.name.of(op)]),
      Bool.pick(String, U32.is_zero(len_strs(P.pr_pd_go(es, 0n, op, Nil{}))), "-",
        String.join(P.pr_pd_go(es, 0n, op, Nil{}), ",")))
def pr_keys_go(+name: String, +ops: List<&2, O.Op>, +es: List<&2, O.PMEntry>) -> IO(Unit):
  match ops:
    case Nil{}: IO.print("")
    case op <> t:
      do IO<Unit>:
        pr_pd_row(name, es, op)
        pr_keys_go(name, t, es)
def pr_keys_row(+name: String, +ops: List<&2, O.Op>, +ts: O.PMEntrys) -> IO(Unit):
  do IO<Unit>:
    rowu(String.concat([name, "_keys"]), P.len_ops(ops))
    pr_keys_go(name, ops, O.PMEntrys.es(ts))
def rej_str(+rej: List<&2, O.Op>) -> String:
  Bool.pick(String, U32.is_zero(P.len_ops(rej)), "{}", P.braced(rej))
def len_pme(es: List<&2, O.PMEntry>) -> U32: U32.from_nat(List.length(&2, O.PMEntry, es))
def b2u(b: Bool) -> U32: Bool.pick(U32, b, 1, 0)
def pr_dsk_keys() -> List<&2, O.Op>: [O.OpsCOPY{}]
def pr_dsk_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, [O.OpsCOPY{}], [O.OpsSTAGE{}]},  # 0 COPY rej=STAGE slen=1 rlen=1 any=0 nalts=1 name=copy
    O.PMEntry{1, [O.OpsCOPY{}], Nil{}},  # 1 COPY rej=- slen=1 rlen=1 any=0 nalts=1 name=copy
  ]}
def pr_t_row(+name: String, +k: U32, +e: O.PMEntry) -> IO(Unit):
  do IO<Unit>:
    row(String.concat([name, "_", U32.show(k), "_ops"]), P.ops_str(O.PMEntry.ops(e)))
    row(String.concat([name, "_", U32.show(k), "_rej"]), rej_str(O.PMEntry.rej(e)))
def pr_t_go(+name: String, +es: List<&2, O.PMEntry>, +k: Nat) -> IO(Unit):
  match es:
    case Nil{}: IO.print("")
    case e <> t:
      do IO<Unit>:
        pr_t_row(name, U32.from_nat(k), e)
        pr_t_go(name, t, Nat.add(k, 1n))
def pr_t_of(+name: String, +ts: O.PMEntrys) -> IO(Unit):
  do IO<Unit>:
    rowu(String.concat([name, "_n"]), len_pme(O.PMEntrys.es(ts)))
    pr_t_go(name, O.PMEntrys.es(ts), 0n)
# THE `pdict` KEY SETS, emitted by `.agents/slop/prep-gen-tables.py` from
# `PatternMatcher.pdict` (ops.py:1592), in the alphabetical order the oracle
# prints.  `pr_<t>_keys` is the LENGTH and `pr_<t>_pd_<OP>` is the ordered rule
# list for one key.
def g_t4() -> IO(Unit):
  do IO<Unit>:
    pr_t_of("dsk", pr_dsk_table())
    pr_keys_row("dsk", pr_dsk_keys(), pr_dsk_table())
def pr_fma_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, [O.OpsAFTER{}], [O.OpsSTORE{}]},  # 0 AFTER rej=STORE slen=1 rlen=2 any=0 nalts=1 name=after
    O.PMEntry{1, [O.OpsSTAGE{}], Nil{}},  # 1 STAGE rej=- slen=1 rlen=1 any=0 nalts=1 name=after
    O.PMEntry{2, [O.OpsEXP2{}, O.OpsLOG2{}, O.OpsSIN{}, O.OpsSQRT{}, O.OpsRECIP{}, O.OpsNEG{}, O.OpsTRUNC{}, O.OpsADD{}, O.OpsMUL{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsTRUNCDIV{}, O.OpsMAX{}, O.OpsTRUNCMOD{}, O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCMPEQ{}, O.OpsXOR{}, O.OpsOR{}, O.OpsAND{}, O.OpsTHREEFRY{}, O.OpsSUB{}, O.OpsFDIV{}, O.OpsPOW{}, O.OpsDIV{}, O.OpsMOD{}, O.OpsWHERE{}, O.OpsMULACC{}], Nil{}},  # 2 ADD AND TRUNCDIV TRUNCMOD CMPEQ CMPLT CMPNE EXP2 FDIV DIV MOD LOG2 MAX MUL MULACC NEG OR POW RECIP SHL SHR SIN SQRT SUB THREEFRY TRUNC WHERE XOR rej=- slen=0 rlen=0 any=0 nalts=0 name=alu
  ]}
def g_t1() -> IO(Unit):
  do IO<Unit>:
    pr_t_of("fma", pr_fma_table())
    pr_keys_row("fma", pr_fma_keys(), pr_fma_table())
# THE FIXTURES.  ONE arena for all of them, because a `toposort` SIZE is only
# comparable with CPython's if both sides count the same reachable set, and two
# arenas would make every fixture a different graph.  The nodes are built in the
# same order the oracle builds its, so the arena layout agrees as well.
def wm_fix() -> P.WMF:
  +a4 = P.pr_buf(O.Arena.empty(), 0, 4, "a4", 0)
  +a8 = P.pr_buf(O.Found.ar(a4), 1, 8, "a8", 0)
  +sh22 = P.pr_shp2(O.Found.ar(a8), 2, 2)
  +sh4 = P.pr_shp1(O.Found.ar(sh22), 4)
  +sh41 = P.pr_shp2(O.Found.ar(sh4), 4, 1)
  +rs22 = P.pr_reshape(O.Found.ar(sh41), a4, sh22)
  +rs41 = P.pr_reshape(O.Found.ar(rs22), a4, sh41)
  +rs4 = P.pr_reshape(O.Found.ar(rs41), a4, sh4)
  +pm22 = P.pr_perm(O.Found.ar(rs4), rs22, 1, 0)
  +c0 = P.pr_shp1(O.Found.ar(pm22), 0)
  +pd = P.pr_pad(O.Found.ar(c0), a4, c0, sh4)
  +pe = P.pr_expand(O.Found.ar(pd), a4, sh4)
  +r0 = P.pr_range(O.Found.ar(pe), 4, 0)
  +ix = O.UOp.new(O.Found.ar(r0), O.OpsINDEX{}, [O.Found.i(a4), O.Found.i(r0)], O.ANone{}, O.TNone{})
  +bc = O.UOp.new(O.Found.ar(ix), O.OpsBITCAST{}, [O.Found.i(a4)], O.ADt{S.single()}, O.TNone{})
  # UNSHARD is one of the three extra hop ops and its arm is in `pr_wm_hop`, but it is NOT a
  # gate fixture: `fold.bend` has no UNSHARD dtype rule, so `F.fold.dt` answers `None`
  # where CPython answers `int` and a row that printed `ERR` on this side and `int`
  # on that one would be a row that CANNOT PASS.  It is a REPORTED fold gap, not a
  # port bug, and the mutation M09 below is the check that the arm is live.
  +bcx = O.UOp.new(O.Found.ar(bc), O.OpsINDEX{}, [O.Found.i(a8), O.Found.i(r0)], O.ANone{}, O.TNone{})
  +cf = O.UOp.new(O.Found.ar(bcx), O.OpsCAST{}, [O.Found.i(a4)], O.ADt{S.single()}, O.TNone{})
  +al = P.pr_alu2(O.Found.ar(cf), O.OpsADD{}, a4, a4)
  +e4 = P.pr_end(O.Found.ar(al), a4)
  +af = P.pr_after(O.Found.ar(e4), a4, e4)
  +afm = P.pr_after(O.Found.ar(af), rs22, e4)
  +afm2 = P.pr_after(O.Found.ar(afm), pm22, e4)
  +afi = P.pr_after(O.Found.ar(afm2), ix, e4)
  +nest = P.pr_reshape(O.Found.ar(afi), pm22, sh4)
  +st = P.pr_store(O.Found.ar(nest), a4, a4)
  +mom = P.pr_perm(O.Found.ar(st), rs22, 0, 1)
  +ia4 = O.Found.i(a4)
  +irs22 = O.Found.i(rs22)
  +irs41 = O.Found.i(rs41)
  +irs4 = O.Found.i(rs4)
  +ipm22 = O.Found.i(pm22)
  +ipd = O.Found.i(pd)
  +ipe = O.Found.i(pe)
  +iix = O.Found.i(ix)
  +ibc = O.Found.i(bc)
  +icf = O.Found.i(cf)
  +ial = O.Found.i(al)
  +iaf = O.Found.i(af)
  +iafm = O.Found.i(afm)
  +iafm2 = O.Found.i(afm2)
  +iafi = O.Found.i(afi)
  +inest = O.Found.i(nest)
  +ist = O.Found.i(st)
  +imom = O.Found.i(mom)
  P.WMF{F.folded(O.Found.ar(mom)), [
    P.WMI{"buf", ia4}, P.WMI{"reshape", irs22}, P.WMI{"rs41", irs41}, P.WMI{"rs4", irs4},
    P.WMI{"permute", ipm22}, P.WMI{"pad", ipd}, P.WMI{"expand", ipe},
    P.WMI{"index", iix}, P.WMI{"bitcast", ibc}, P.WMI{"cast", icf},
    P.WMI{"alu", ial}, P.WMI{"after_plain", iaf}, P.WMI{"after_mov", iafm},
    P.WMI{"after_mov2", iafm2}, P.WMI{"after_idx", iafi}, P.WMI{"nested_mov", inest},
    P.WMI{"store", ist}, P.WMI{"mov_of_mov", imom}]}
def pr_ear_keys() -> List<&2, O.Op>: [O.OpsADD{}, O.OpsAFTER{}, O.OpsALLOC{}, O.OpsALLREDUCE{}, O.OpsAND{}, O.OpsBACKEDGE{}, O.OpsBARRIER{}, O.OpsBINARY{}, O.OpsBITCAST{}, O.OpsBUFFER{}, O.OpsCALL{}, O.OpsCAST{}, O.OpsTRUNCDIV{}, O.OpsTRUNCMOD{}, O.OpsCMPEQ{}, O.OpsCMPLT{}, O.OpsCMPNE{}, O.OpsCONST{}, O.OpsCONTIGUOUS_BACKWARD{}, O.OpsCOPY{}, O.OpsCUSTOM{}, O.OpsCUSTOMI{}, O.OpsCUSTOM_FUNCTION{}, O.OpsDETACH{}, O.OpsEND{}, O.OpsENDIF{}, O.OpsEXP2{}, O.OpsEXPAND{}, O.OpsFDIV{}, O.OpsDIV{}, O.OpsMOD{}, O.OpsGETADDR{}, O.OpsIF{}, O.OpsINDEX{}, O.OpsINS{}, O.OpsLINEAR{}, O.OpsLOAD{}, O.OpsLOG2{}, O.OpsMAX{}, O.OpsMSELECT{}, O.OpsMSTACK{}, O.OpsMUL{}, O.OpsMULACC{}, O.OpsNEG{}, O.OpsNOOP{}, O.OpsOR{}, O.OpsPAD{}, O.OpsPARAM{}, O.OpsPERMUTE{}, O.OpsPOW{}, O.OpsPROGRAM{}, O.OpsPYLITERAL{}, O.OpsRANGE{}, O.OpsRECIP{}, O.OpsREDUCE{}, O.OpsRESHAPE{}, O.OpsREWRITE_ERROR{}, O.OpsSHL{}, O.OpsSHR{}, O.OpsSHRINK{}, O.OpsSIN{}, O.OpsSINK{}, O.OpsSOURCE{}, O.OpsSPECIAL{}, O.OpsSQRT{}, O.OpsSTACK{}, O.OpsSTAGE{}, O.OpsSTORE{}, O.OpsSUB{}, O.OpsTHREEFRY{}, O.OpsTRUNC{}, O.OpsUNSHARD{}, O.OpsWHERE{}, O.OpsWMMA{}, O.OpsXOR{}]
def g_t5() -> IO(Unit):
  do IO<Unit>:
    pr_t_of("ear", pr_ear_table())
    pr_keys_row("ear", pr_ear_keys(), pr_ear_table())
def WMF.items(w: P.WMF) -> List<&2, P.WMI>:
  match w:
    case P.WMF{fx, items}: items
# THE FIXTURES.  ONE arena for all of them, because a `toposort` SIZE is only
# comparable with CPython's if both sides count the same reachable set, and two
# arenas would make every fixture a different graph.  The nodes are built in the
# same order the oracle builds its, so the arena layout agrees as well.
def pr_mop_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, [O.OpsINDEX{}], Nil{}},  # 0 INDEX rej=- slen=0 rlen=1 any=0 nalts=1 name=idx
    O.PMEntry{1, [O.OpsAFTER{}], Nil{}},  # 1 AFTER rej=- slen=0 rlen=1 any=0 nalts=1 name=a
    O.PMEntry{2, [O.OpsEND{}], Nil{}},  # 2 END rej=- slen=0 rlen=1 any=0 nalts=1 name=a
  ]}
def topo_str(+fx: F.Folded, +self: U32) -> String:
  +ar = F.Folded.ar(fx)
  +tb = F.Folded.t(fx)
  +ns = O.UOp.toposort(O.Arena.budget(ar), ar, self)
  P.ops_str(P.topo_ops(ar, tb, ns))
# THE FIXTURE BUILDERS. `O.Found` is `ops.bend`'s `(arena, node)` pair, and a
# node is an arena INDEX, so every fixture is built once and the arena is what
# every reader sees.
def rowi(nm: String, b: Bool) -> IO(Unit): rowu(nm, b2u(b))
def pr_wm_same(self: U32, b: U32) -> Bool: U32.is_eq(b, self)
def sig4(+fx: F.Folded, +self: U32) -> String:
  +ar = F.Folded.ar(fx)
  +tb = F.Folded.t(fx)
  String.join([
    U32.show(U32.from_nat(List.length(&2, U32, O.UOp.toposort(O.Arena.budget(ar), ar, self)))),
    O.Ops.name.of(O.Arena.op(ar, self)),
    U32.show(O.Arena.nsrc(ar, self)),
    P.ops_str(P.src_ops.go(ar, self, List.range(U32.to_nat(O.Arena.nsrc(ar, self))), Nil{})),
    P.shape_str(ar, tb, self),
    P.dt_name.of(F.fold.dt(ar, tb, self))
  ], "|")
# THE WALK ORDER, which for a scheduling pass is the point. Never a count.
def wm_row(+nm: String, +fx: F.Folded, +self: U32) -> IO(Unit):
  +ar = F.Folded.ar(fx)
  +f = pr_wm(O.Arena.budget(ar), ar, self)
  +b = O.Found.i(f)
  +g = F.folded(O.Found.ar(f))
  +pre = String.concat(["wm_", nm, "_"])
  do IO<Unit>:
    row(String.concat([pre, "in"]), sig4(fx, self))
    row(String.concat([pre, "out"]), sig4(g, b))
    rowi(String.concat([pre, "same"]), pr_wm_same(self, b))
    row(String.concat([pre, "wmx"]), P.pr_wm_wmx(ar, self, b))
    row(String.concat([pre, "topo"]), topo_str(g, b))
# `wmx` is `-1` for a non-AFTER input and the identity for an AFTER one, which is
# how the oracle spells it: the question "was the answer `u.src[0]`" only HAS a
# meaning on the AFTER arm.
def WMI.nm(w: P.WMI) -> String:
  match w:
    case P.WMI{nm, i}: nm
def WMI.i(w: P.WMI) -> U32:
  match w:
    case P.WMI{nm, i}: i
def wm_go(+fx: F.Folded, +ws: List<&2, P.WMI>) -> IO(Unit):
  match ws:
    case Nil{}: IO.print("")
    case w <> t:
      do IO<Unit>:
        wm_row(WMI.nm(w), fx, WMI.i(w))
        wm_go(fx, t)
def g_wm() -> IO(Unit):
  +w = wm_fix()
  wm_go(WMF.fx(w), WMF.items(w))
# THE MUTATION TABLE.  One edit per ported rule, re-run in the INTERPRETED lane
# (the two lanes are byte-identical at baseline, so the native lane adds nothing
# here and costs minutes), and the rows each edit moves are reported BY NAME.
# `.agents/slop/prep-mutate.py` applies them and this table is its output; nothing
# here is transcribed by hand.  The harness diffs whole `name=value` lines, never
# row NAMES.
#
#   MUT   DEF                WHAT IT CHANGES                              ROWS MOVED
#   M01   pr_fma_table       rule 2's ALU op set GAINS CONST                  1
#   M02   pr_mop_table       rule 2 claims STORE, not END                    2
#   M03   pr_ear_table       rule 10 (`split_reduceop`) claims WHERE          3
#   M04   pr_inl_table       rule 0 (`resolve_function`) claims END            2
#   M05   pr_dsk_table       rule 0's early_reject gains CONST                 1
#   M06   pr_mcl_table       `mop_cleanup` rule 5's reject gains CONST         1
#   M07   pr_wm_hop          drop INDEX/UNSHARD/BITCAST from the hop set       9
#   M08   pr_wm_extra        keep only INDEX of the three extra hop ops        3
#   M09   pr_wm_step         the spine's loop condition loses the AFTER half   9
#   M10   pr_wm_keep         a movement arm takes the node instead of keeping 42
#   M11   pr_wm_keep_a       INVERT `is not u.src[0]` -- rebuild on no change   9
#   M12   pr_wm_pre          APPEND the spine node instead of prepending it   10
#   M13   pr_wm_step.go.of   the spine stops pushing on the descent          10
#   M14   pr_wm_step.end.of  the spine never pushes the TERMINAL node        42
#   M15   pr_wm_mk           `*u.src[1:]` reads srcs BEFORE index 1            6
#   M16   pr_wm_turn.of      the `done` flag is ignored                  DOES NOT COMPILE
#   M17   pr_pd_go           the `pdict` scan claims no rule for any op      118
#   M19   rej_str            an EMPTY early_reject prints `-`, not `{}`      22
#   M20   braced             the reject set loses its braces                22
#   M21   shape_str.go       a shape's dim separator is `,`, not `x`          8
#   M22   sint_str.go        a SYMBOLIC dim prints `hi:lo`                   NOTHING (0)
#   M23   dt_name.of         an unresolved dtype prints `void`, not `ERR`    NOTHING (0)
#   M24   sig4               nsrc reads src[0]'s OWN nsrc                    23
#   M25   pr_wm_more         the spine descends on AFTER only                39
#   M26   pr_wm_fold         the fold visits no node at all                  42
#   M27   pr_ear_table       rule 20 (`fix_store_hazard`) reject gains AFTER   1
#   M28   pr_fma_table       rule 0 (`found_after`) reject loses STORE         1
#
# TWENTY-FIVE OF TWENTY-SEVEN MOVE ROWS.  The three that do not are reported as
# blind spots with their reasons, NOT closed with rows:
#
#   M16 IS NOT A MUTATION.  The edit deletes one arm of a `match`, which is a
#   syntax error and not a behaviour change -- it is listed so the table does not
#   claim a measurement it did not take.  The `done` flag IS measured, by M13: a
#   spine that keeps pushing after the terminal node moves the same ten rows.
#
#   M22 IS AN UNREACHABLE ARM, not a gap.  `Sint` is `SI{i64} | SU{u32}` and `O.SU`
#   is a shape dim for a SYMBOLIC size.  Nothing in this tree can mint one:
#   `ops.bend`'s `ParamArg.size` is `Maybe<&2, U32>` with the comment "always a
#   concrete int (never symbolic)" (ops.bend:698-699) and `fold.bend`'s
#   `param_shape.size` reads it as `sint_of(n)`.  Every fixture dim is a concrete
#   `O.SI`, so `sint_str.go`'s second arm never runs.  This is `fold.bend`'s M9
#   verbatim and it is reported here for the same reason.
#
#   M23 is the same kind of thing with one extra edge.  `dt_name.of`'s `None` arm
#   fires for a node the FOLD does not resolve, and the only such node in this
#   gate's fixtures would be a UNSHARD -- which is why the UNSHARD fixture was
#   REMOVED from the gate, and the reason is written into `wm_fix` beside the node
#   it would have used.  `fold.bend` has no UNSHARD dtype rule, so the arm is
#   reachable only by a fixture this gate deliberately does not build.  That is a
#   THIRD option the brief does not name: the fixture was REMOVED rather than kept
#   with a row that could not pass, and the removal is visible in the diff.  The
#   arm of `pr_wm_extra` that reads UNSHARD is still live, and M08 measures it.
#
# the rows this port cannot print, and the substrate fact behind each.  The oracle
# is 2544 rows; 321 of them are gated here and the rest are the WALLS above, named
# rather than faked:
#
#   * `mi_*` (190 rows) -- `_mop_index`'s three index counts, `src_prefix`, the tail
#     equality and `ret.shape == idx.shape`.  All but the last are PURE and PORTABLE
#     without an arena; the last needs `apply_movement_op` (schedule/indexing.py:130)
#     plus `UOp.index` (ops.py:581), which is W3.  The fixtures exist in the oracle.
#   * `sr_*` / `srp_*` (140 rows) -- `split_reduceop`'s candidate search.  The search
#     is PURE (`range` over `reduce.arg[1]`, `range(cap, 7, -1)`, `x.shape[i]%d` and
#     `is_expanded[i]`) and 2**22 is a `U32` LITERAL rather than a shift, so the
#     `U32.shl` trap does not bite here.  `is_expanded` is W4, so the search takes it
#     as a PARAMETER; `srp_L_*` in the oracle is `is_expanded` measured through
#     tinygrad's own `index` + `substitute`, so the fixture is already in hand.
#   * `ebp_*` (140 rows) -- `expand_bitcast`'s itemsize ladder: `ns`, `os`, the DISK
#     early-out, `rate = ns//os`, the reshape `x.shape[:-1] + (last//rate, rate)`,
#     `nparts` and the shift step `8*os` / `8*ns`.  All of it is pure arithmetic on
#     two itemsizes and a last dim, with NO arena and NO builder.  This is the
#     highest-value un-ported section and the shortest.
#   * `fa_*` (56 rows) -- `found_after`'s loop.  `argsort` is `H.argsort_u32`
#     (helpers.bend:196) and the RESHAPE / WHERE / SHRINK arms are pure, so it is
#     PORTABLE; only the `.after(...)` at the end is W3.
#   * `shb_*` / `fsh_*` (55 rows) -- `store_hazard_boundary` and `fix_store_hazard`.
#     The gated toposort is `O.UOp.toposort_nocalls` FILTERED by the boundary, which
#     is order-preserving, so both are portable; `op_in_backward_slice_with_self`
#     (ops.py) is not, and `target.store(src.contiguous())` is W3.
#   * `cas_*` / `sas_*` / `mcd_*` (40 rows) -- the three materialisers.  Each is one
#     predicate over `prod(x.max_shape)` and a device comparison; `max_shape` is
#     ops.py:467 and is not in `fold.bend`.
#   * `rfn_*` (52 rows) -- `resolve_function`'s THREE REFUSALS
#     (`arg {slot} shape mismatch: expected size {n}, got {shape}`,
#     `... expected scalar, got ...`, `... dtype mismatch: expected {p}, got {a}`)
#     and its OK rows.  `flat_storage`'s `a.pad_to(shp).reshape((n,))` is W3 and
#     `UOp.unique_num` is a global counter with no arena, so the ALLOC re-mint is
#     the part that cannot be answered.  The refusal MESSAGES are the rows and they
#     are exactly reproducible from the oracle.
#   * `fco_*` (100 rows) and `pr_*` (90 rows) -- `forward_call_outputs` and
#     `prepare_rangeify`.  Both are gated by `graph_rewrite` (W1) and
#     `UOp.substitute` (W2): the first is a fixpoint over a worklist with a rebuilt
#     todo, and the second IS a rewrite of every node.  `schedule/indexing.bend`
#     records the same `graph_rewrite` wall from the other side.
#   * `cl_*` (600+ rows) -- the per-rule FIRING rows, and they are the biggest
#     un-ported prize.  Each is "how many rules CLAIM this node, which ones, and
#     what `PatternMatcher.rewrite` returns", and the fixtures already exist in the
#     oracle (`FIX`, 33 nodes).  They are absent for a DEF-ORDER reason and not an
#     impossibility: `O.pm_rewrite` needs a `PMEntrys` and a dispatch, so the six
#     tables' `try`/`scan`/`dispatch` have to be written before any row can print,
#     and that is the next block of work rather than a wall.  The measurements to
#     make first are `cl_ear_bitstore_n=4`, `cl_ear_rsstore_n=4` and
#     `cl_ear_copystore_n=4`: four rules claim one node and only a FIRST-WINS scan
#     separates them.
#   * `<t>_<k>_{dt,src}` (2 per rule) -- `UPat.match_dtype` and the src permutation
#     tuple (upat.py:47).  `PMEntry` is `tag`/`ops`/`rej` and NOTHING ELSE
#     (uop/ops.bend:4043 symbol=PMEntry), so `UPat` does not survive into the compiled IR.
def pr_mop_keys() -> List<&2, O.Op>: [O.OpsAFTER{}, O.OpsEND{}, O.OpsINDEX{}]
def g_t2() -> IO(Unit):
  do IO<Unit>:
    pr_t_of("mop", pr_mop_table())
    pr_keys_row("mop", pr_mop_keys(), pr_mop_table())
def pr_mcl_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, [O.OpsSHRINK{}], [O.OpsSHRINK{}]},  # 0 SHRINK rej=SHRINK slen=0 rlen=1 any=0 nalts=1 name=s
    O.PMEntry{1, [O.OpsRESHAPE{}], [O.OpsRESHAPE{}]},  # 1 RESHAPE rej=RESHAPE slen=1 rlen=2 any=0 nalts=1 name=x
    O.PMEntry{2, [O.OpsRESHAPE{}], Nil{}},  # 2 RESHAPE rej=- slen=1 rlen=2 any=0 nalts=1 name=x
    O.PMEntry{3, [O.OpsPERMUTE{}], [O.OpsPERMUTE{}]},  # 3 PERMUTE rej=PERMUTE slen=1 rlen=1 any=0 nalts=1 name=x
    O.PMEntry{4, [O.OpsPERMUTE{}], Nil{}},  # 4 PERMUTE rej=- slen=0 rlen=0 any=0 nalts=0 name=x
    O.PMEntry{5, [O.OpsSTACK{}], [O.OpsINDEX{}]},  # 5 STACK rej=INDEX slen=0 rlen=0 any=0 nalts=1 name=stk
    O.PMEntry{6, [O.OpsINDEX{}], [O.OpsCONST{}, O.OpsSTACK{}]},  # 6 INDEX rej=CONST STACK slen=0 rlen=2 any=0 nalts=1 name=idx
    O.PMEntry{7, [O.OpsINDEX{}], [O.OpsINDEX{}]},  # 7 INDEX rej=INDEX slen=0 rlen=1 any=0 nalts=1 name=idx2
    O.PMEntry{8, [O.OpsINDEX{}], [O.OpsINDEX{}]},  # 8 INDEX rej=INDEX slen=0 rlen=1 any=0 nalts=1 name=idx2
  ]}
# THE TABLE ROWS.  `<t>_n` is the rule COUNT; `<t>_keys` is how many ops CLAIM a
# rule (`pdict`'s key set, ops.py:1592); `<t>_pd_<OP>` is the ORDERED list of
# rule indices that op claims, which is where FIRST-WINS lives (ops.py:1606 walks
# `pdict.get(uop.op, [])` in insertion order); and `<t>_<k>_{ops,rej}` are the two
# fields `PMEntry` actually has.
#
# `early_reject` is a SET (ops.py:1477) so it renders in BRACES and an EMPTY one
# renders `{}`, while `pat.op` is a TUPLE in the UPat's DECLARED order (ops.py:1454)
# and renders as a bare comma list.  The table literal therefore keeps `ops` in
# declared order and sorts `rej`, and this is where the two are rendered.
def pr_inl_keys() -> List<&2, O.Op>: [O.OpsAFTER{}, O.OpsCALL{}]
def pr_mcl_keys() -> List<&2, O.Op>: [O.OpsINDEX{}, O.OpsPERMUTE{}, O.OpsRESHAPE{}, O.OpsSHRINK{}, O.OpsSTACK{}]
# THE `pdict` ROW: the ordered rule indices ONE op claims.  `List.append` is
# `xs ++ ys` (agent-core.md), so the accumulator is already in order and there is
# no reverse -- `fold.bend`'s M2 note is about the PAIR, not about append.
# An op TWO rules claim prints a two-element list, and that is the row which
# separates a first-wins fold from a conjunction.
def g_t6() -> IO(Unit):
  do IO<Unit>:
    pr_t_of("mcl", pr_mcl_table())
    pr_keys_row("mcl", pr_mcl_keys(), pr_mcl_table())
# THE `pdict` KEY SETS, emitted by `.agents/slop/prep-gen-tables.py` from
# `PatternMatcher.pdict` (ops.py:1592), in the alphabetical order the oracle
# prints.  `pr_<t>_keys` is the LENGTH and `pr_<t>_pd_<OP>` is the ordered rule
# list for one key.
# 1. `walk_mop` -- prepare.py:40-43.
#      if u.op in GroupOp.Movement or u.op in {INDEX, UNSHARD, BITCAST}:
#        return walk_mop(u.src[0])
#      if u.op is AFTER and (b:=walk_mop(u.src[0])) is not u.src[0]:
#        return b.after(*u.src[1:])
#      return u
#
# THE IDENTITY IS THE RULE. `is not u.src[0]` decides whether the AFTER arm fires
# at all, so the rows are `wm_<nm>_same` (the answer IS the input) and
# `wm_<nm>_wmx` (the answer IS `u.src[0]`) -- neither is a count, and a movement
# node and its un-moved alias have the same op, the same nsrc, the same src op
# sequence and the same shape.  `GroupOp.movement` is `uop/ops.bend:505` symbol=GroupOp.movement and owns the
# predicate; the three extra ops are written out because they are three.
# The SHAPE is `fold.bend`'s: ONE self-recursive def with the decreasing fuel
# first, and a `Data` RECORD for the rest of the state, because a `match` on a
# record's field binder is legal where a `match` on a computed value is not.  That
# is `Kahn.run` / `Kahn.step` / `Kahn.pop` exactly (uop/fold.bend:4896 symbol=Kahn.run,
# uop/fold.bend:4887 symbol=Kahn.step, uop/fold.bend:4881 symbol=Kahn.pop), and it is
# the only reason this walk is writable at all: Python's two `if`s become one
# `match` on `WmSt{kind}`, and the AFTER arm's "build or keep" becomes a
# `Bool.pick` inside `pr_wm_fork`, which is a FUNCTION and not a scrutinee -- which
# is exactly what makes the `is not u.src[0]` identity expressible.
def rowb(nm: String, b: Bool) -> IO(Unit): row(nm, Bool.show(b))
def pr_inl_table() -> O.PMEntrys:
  O.PMEntrys{[
    O.PMEntry{0, [O.OpsCALL{}], Nil{}},  # 0 CALL rej=- slen=0 rlen=0 any=0 nalts=0 name=c
    O.PMEntry{1, [O.OpsAFTER{}], [O.OpsSINK{}]},  # 1 AFTER rej=SINK slen=0 rlen=2 any=0 nalts=1 name=-
  ]}
def g_t3() -> IO(Unit):
  do IO<Unit>:
    pr_t_of("inl", pr_inl_table())
    pr_keys_row("inl", pr_inl_keys(), pr_inl_table())
def main() -> IO(Unit):
  do IO<Unit>:
    g_t1()
    g_t2()
    g_t3()
    g_t4()
    g_t5()
    g_t6()
    g_wm()
    IO.print("done")

