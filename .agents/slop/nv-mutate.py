import json, re, os, sys

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "../../tinybendygrad/runtime/ops_nv.bend")

N = chr(34)   # "

ENTRIES = [
 ("M1",
  "def qmd.ver.of(compute: U32) -> U32:\n  Bool.pick(U32, U32.is_ge(compute, CLASS_BLACKWELL_COMPUTE_A()), QMD_VER5(), QMD_VER3())",
  "def qmd.ver.of(compute: U32) -> U32:\n  Bool.pick(U32, U32.is_gt(compute, CLASS_BLACKWELL_COMPUTE_A()), QMD_VER5(), QMD_VER3())",
  "ops_nv.py:54 -- >= becomes >, so Blackwell_A itself stops being ver 5"),
 ("M2",
  "def pd.reloc.off(+a: U32, kind: U32) -> U32:\n  Bool.pick(U32, U32.is_eq(kind, RELOC_64()), a, U32.add(a, 4))",
  "def pd.reloc.off(+a: U32, kind: U32) -> U32:\n  Bool.pick(U32, U32.is_eq(kind, RELOC_64()), a, a)",
  "ops_nv.py:263 -- the +4 for both 32-bit arms, the low word of a 64-bit address"),
 ("M3",
  "U32.or(U32.shln(typ, 28n), U32.shln(nvals, 16n))",
  "U32.or(U32.shln(typ, 29n), U32.shln(nvals, 16n))",
  "ops_nv.py:48 -- typ << 28 is 28 and not 29"),
 ("M4",
  "nvm.words_of(NVALS_SEM())",
  "U32.add(nvm.words_of(NVALS_SEM()), 1)",
  "ops_nv.py:48 -- a uint64 address counts TWO words, so the sem header says 5"),
 ("M5",
  "def qmd.slot.ok(busy0: Bool, busy1: Bool) -> Bool: Bool.not(Bool.and(busy0, busy1))",
  "def qmd.slot.ok(busy0: Bool, busy1: Bool) -> Bool: Bool.not(Bool.or(busy0, busy1))",
  "ops_nv.py:85-91 -- set_release refuses only when BOTH slots are busy"),
 ("M6",
  "Bool.pick(U32, U32.is_le(shmem, 32768), 32768,\n    Bool.pick(U32, U32.is_le(shmem, 65536), 65536, 102400))",
  "Bool.pick(U32, U32.is_ge(shmem, 32768), 102400,\n    Bool.pick(U32, U32.is_ge(shmem, 65536), 65536, 32768))",
  "ops_nv.py:293 -- the MIN over {32768,65536,102400} picks the smallest candidate"),
 ("M7",
  "case h <> Nil{}: to_name.join.parts(Nil{}, List.append(&2, String, acc, [h]))",
  "case h <> Nil{}: to_name.join.parts(Nil{}, List.append(&2, String, acc, [String.concat([h, \"_\"])]))",
  "hcq2.py:63 -- String.split drops the separator, so to_name has to put it back"),
 ("M8",
  "def flags.term(v: U32, lo: U32) -> U32: U32.shln(v, U32.to_nat(lo))",
  "def flags.term(v: U32, lo: U32) -> U32: U32.shln(v, U32.to_nat(U32.sub(lo, 1)))",
  "ops_nv.py:40 -- the shift is the bitfield tuple SECOND element"),
 ("M9",
  "Tr{Bool.pick(List<&2, Call>, refused, calls,\n               List.append(&2, Call, calls, nvm.words.of(ws, h))), next,",
  "Tr{Bool.pick(List<&2, Call>, refused, calls, nvm.words.of(ws, h)), next,",
  "the emit REPLACES the head instead of appending -- the Bool.pick selector trap"),
 ("M10",
  "def copy.nsteps(sz: U32) -> U32: H.ceildiv_u32(sz, COPY_STEP())",
  "def copy.nsteps(sz: U32) -> U32: Bool.pick(U32, U32.is_zero(sz), 0, 1)",
  "ops_nv.py:191 -- len(range(0, sz, 1<<31)) is 0 for an empty copy and 2 at the top"),
 ("M11",
  "Bool.pick(Tr, prev, t, cq.exec.open(pma, qmd_addr_hi, pcas2, t))",
  "cq.exec.open(pma, qmd_addr_hi, pcas2, t)",
  "ops_nv.py:180 -- a CHAINED launch emits no words at all"),
 ("M12",
  "Bool.not(Bool.or(U32.is_gt(pr, THREADS_MAX()), U32.is_lt(max_threads, pr)))",
  "Bool.not(Bool.or(Bool.and(U32.is_gt(pr, THREADS_MAX()), U32.is_lt(max_threads, pr)), False{}))",
  "ops_nv.py:164 -- the first launch refusal is a DISJUNCTION"),
 ("M13",
  "Bool.pick(PC, U32.is_lt(found, U32.from_nat(List.length(&2, PKey, PC.ks(p)))),",
  "Bool.pick(PC, Bool.not(U32.is_eq(found, U32.from_nat(List.length(&2, PKey, PC.ks(p))))),",
  "ops_nv.py:315 -- the miss sentinel is the key-list LENGTH and not 0. A REAL BLIND SPOT: it moves nothing, because `pc.find` now answers `len` on a miss and an index below it on a hit, which makes `found < len` and `found != len` THE SAME PREDICATE. The equivalent blind spot is a test that cannot fail."),
 ("M14",
  "def arch_low.at(v: U32, hexish: Bool) -> U32:\n  match hexish:\n    case True{}: U32.shrn(v, 4n)",
  "def arch_low.at(v: U32, hexish: Bool) -> U32:\n  match hexish:\n    case True{}: U32.shrn(v, 1n)",
  "ops_nv.py:601 -- val >> 4 where the test is val > 0xf"),
 ("M15",
  "U32.or(U32.shrn(U32.and(sm, 3840), 4n), U32.and(sm, 15))",
  "U32.or(U32.shrn(U32.and(sm, 3840), 1n), U32.and(sm, 15))",
  "ops_nv.py:602 -- ((sm & 0xf00) >> 4) | (sm & 0xf)"),
 ("M16",
  "def iowr.cmd(nbytes: U32, nr: U32) -> U32:\n  iowr.pack(U32.and(nbytes, IOWR_SIZE_MASK()), U32.and(nr, IOWR_NR_MASK()))",
  "def iowr.cmd(nbytes: U32, nr: U32) -> U32:\n  iowr.pack(nbytes, nr)",
  "ops_nv.py:44 -- sizeof(args) & 0x1FFF truncates an 8 KiB struct to nothing"),
 ("M17",
  "def pd.max2(+a: U32, +b: U32) -> U32:\n  Bool.pick(U32, U32.is_gt(a, b), a, b)",
  "def pd.max2(+a: U32, +b: U32) -> U32:\n  Bool.pick(U32, U32.is_lt(a, b), a, b)",
  "a max that is a min -- device.bend:584's own rule, one layer down"),
 ("M18",
  "def dev.reg_nchunks(n: U32) -> U32: H.ceildiv_u32(n, REG_CHUNK())",
  "def dev.reg_nchunks(n: U32) -> U32: U32.div(n, 128)",
  "ops_nv.py:819 -- the chunk is 124 rows and not 128"),
 ("M19",
  "def dev.slm(+required: U32, +have: U32) -> U32:\n  Bool.pick(U32, U32.is_ge(have, required), have, H.round_up_u32(required, SLM_GRAN()))",
  "def dev.slm(+required: U32, +have: U32) -> U32:\n  H.round_up_u32(required, SLM_GRAN())",
  "ops_nv.py:689 -- the early return is the NEGATIVE case for the whole pool. This one moved NOTHING until `nv_slmp_33_have48` was added: every other fixture had `have` already equal to `round_up(required, 32)`."),
 ("M20",
  "def iface.want(ix: U32) -> U32:\n  match ix:\n    case 1: CLASS_HOPPER_USERMODE()\n    case 2: CLASS_BLACKWELL_GPFIFO()\n    case 3: CLASS_BLACKWELL_COMPUTE_B()",
  "def iface.want(ix: U32) -> U32:\n  match ix:\n    case 1: CLASS_TURING_USERMODE()\n    case 2: CLASS_AMPERE_GPFIFO()\n    case 3: CLASS_AMPERE_COMPUTE_B()",
  "ops_nv.py:408-412 -- the ladders are NEWEST GENERATION FIRST"),
 ("M21",
  "U32.add(U32.mul(U32.add(U32.sub(ntpg, tpc_cnt), tpc), PROF_TPC_STRIDE_PRE()),\n                  U32.add(prof.sm_base(sm), reg))",
  "U32.add(U32.mul(U32.add(U32.add(U32.sub(ntpg, tpc_cnt), tpc), PROF_TPC_STRIDE_PRE()), 1),\n                  U32.add(prof.sm_base(sm), reg))",
  "ops_nv.py:805 -- (ntpg - cnt + tpc) * 0x200 MULTIPLIES, it does not add 0x200"),
 ("M22",
  "# ===========================================================================\n# STAGE 4 (part one) -- THE BUFFER POOL",
  "# (a comment-only edit)\n# ===========================================================================\n# STAGE 4 (part one) -- THE BUFFER POOL",
  "THE CONTROL -- a comment-only edit, and a table with no row that CANNOT move is a table of coincidences"),
 ("M23",
  "def to_name.join.go(parts: List<&2, String>, acc: List<&2, String>) -> String:\n  match parts:\n    case Nil{}: String.join(List.reverse(&2, String, acc), \"_\")\n    case h <> t: to_name.join.go(t, to_name.norm(h) <> acc)",
  "def to_name.join.go(parts: List<&2, String>, acc: List<&2, String>) -> String:\n  match parts:\n    case Nil{}: String.join(acc, \"_\")\n    case h <> t: to_name.join.go(t, acc <> [to_name.norm(h)])",
  "hcq2.py:63 -- join(parts) is in the PARTS order"),
 ("M24",
  "H.round_up_u32(U32.mul(pd.r1(regs), 32), 256)), 4), 4), 32)",
  "H.round_up_u32(U32.mul(pd.r1(regs), 32), 128)), 4), 4), 32)",
  "ops_nv.py:305 -- the register allocation granularity is 256 and not 128"),
 ("M25",
  "def nvm.words(ws: List<&2, U32>, h: U32, acc: List<&2, Call>) -> List<&2, Call>:\n  match ws:\n    case Nil{}: acc\n    case w <> t: nvm.words(t, h, List.append(&2, Call, acc, [Call{CALL_WORD(), w}]))",
  "def nvm.words(ws: List<&2, U32>, h: U32, acc: List<&2, Call>) -> List<&2, Call>:\n  match ws:\n    case Nil{}: acc\n    case w <> t: nvm.words(t, h, List.append(&2, Call, acc, [w]))",
  "the payload words keep the HEADER as their tag -- a TYPE change, so it is refused rather than measured"),
 ("M26",
  "def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>,\n              +at: Nat) -> Bool:\n  match n:\n    case 0n: Nat.is_eq(at, patlen)\n    case 1n+m:\n      match cs:\n        case Nil{}: Nat.is_eq(at, patlen)",
  "def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>,\n              +at: Nat) -> Bool:\n  match n:\n    case 0n: True{}\n    case 1n+m:\n      match cs:\n        case Nil{}: True{}",
  "THE MATCHER WITH ITS FUEL SET TO NOTHING -- ops_webgpu.bend's real blind spot"),
 ("M27",
  "def cq.stride(qmd_sz: U32, max_kernargs: U32) -> U32: U32.add(qmd_sz, max_kernargs)",
  "def cq.stride(qmd_sz: U32, max_kernargs: U32) -> U32: max_kernargs",
  "ops_nv.py:137 -- stride is qmd_sz PLUS the largest kernargs, and the default is 0"),
 ("M28",
  "def pd.image_len(img: U32) -> U32: U32.add(H.round_up_u32(img, 4096), 4096)",
  "def pd.image_len(img: U32) -> U32: H.round_up_u32(img, 4096)",
  "ops_nv.py:277 -- the NOTE is 4KB of slack AFTER the page-aligned image"),
  ("M29",
   "def query_litter.at(+ix: U32) -> Bool:\n  Bool.or(U32.is_eq(ix, 0), Bool.or(U32.is_eq(ix, 1), U32.is_eq(ix, 2)))",
   "def query_litter.at(+ix: U32) -> Bool:\n  Bool.or(U32.is_eq(ix, 1), Bool.or(U32.is_eq(ix, 2), U32.is_eq(ix, 3)))",
   "ops_nv.py:665 -- THE LITTER SET IS {0,1,2}. This mutation is the SECOND wrong reading of it and is here to keep both readings honest: the first said {1,3}, the second {1,2,3}, and only nv_570.__dict__ said {0,1,2}"),
  ("M30",
   "def dev.slm_bytes(bpt: U32, ntpg: U32, ngpc: U32) -> U32:\n  H.round_up_u32(U32.mul(U32.mul(bpt, ntpg), ngpc), TOT_ROUND())",
   "def dev.slm_bytes(bpt: U32, ntpg: U32, ngpc: U32) -> U32:\n  U32.mul(U32.mul(bpt, ntpg), ngpc)",
   "ops_nv.py:693 -- the ONLY 128 KiB rounding in the file. Its rows were named nv_slmtot_* in the oracle and nv_slm_* in the gate, so twelve of them matched NOTHING for a whole stage"),
  ("M31",
   "def qmd.fields_v3() -> U32: 181",
   "def qmd.fields_v3() -> U32: 180",
   "ops_nv.py:58-59 -- the 181-row table IS the reason a word list is exact, and the count had a COMMENT naming a row that did not exist"),
  ("M32",
   "def iowr.cmd.at(+explicit: U32, nbytes: U32, nr: U32) -> U32:\n  Bool.pick(U32, U32.is_zero(explicit), iowr.cmd(nbytes, nr), explicit)",
   "def iowr.cmd.at(+explicit: U32, nbytes: U32, nr: U32) -> U32:\n  Bool.pick(U32, U32.is_zero(explicit), explicit, iowr.cmd(nbytes, nr))",
   "ops_nv.py:44 -- `cmd or (...)`: a zero explicit word FALLS THROUGH to the derived one, and cmd=0 is what every uvm() call passes"),
]


def main():
    src = open(SRC).read()
    base_out = run_src(SRC)
    base = dict(l.rsplit("=", 1) for l in base_out.split("\n") if l.startswith("nv"))
    want = set(sys.argv[1:])
    print("| # | rows moved | what it is testing |")
    print("| --- | --- | --- |")
    for mid, old, new, what in ENTRIES:
        if want and mid not in want:
            continue
        if old not in src:
            print(PNA.pipe([mid, PNA.not_applied(), what], 3))
            continue
        dst = os.path.join(os.path.dirname(SRC), "_mut_scratch.bend")
        open(dst, "w").write(src.replace(old, new, 1))
        out = run_src("tinybendygrad/runtime/_mut_scratch.bend")
        os.remove(dst)
        if out is None:
            print("| %s | REFUSED | %s |" % (mid, what))
            continue
        got = dict(l.rsplit("=", 1) for l in out.split("\n") if l.startswith("nv"))
        moved = sorted(k for k in base if base[k] != got.get(k))
        print("| %s | %d %s | %s |" % (mid, len(moved),
              ("(" + ", ".join(moved[:6]) + (", ..." if len(moved) > 6 else "") + ")")
              if moved else "", what))
    return 0


def run_src(rel):
    import subprocess
    r = subprocess.run(["./bin/bend", rel], capture_output=True, text=True,
                       cwd=os.path.abspath(os.path.join(HERE, "../..")))
    if r.returncode != 0:
        return None
    return r.stdout


if __name__ == "__main__":
    sys.exit(main())