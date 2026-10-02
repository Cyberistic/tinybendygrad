#!/usr/bin/env python3
"""amdev_mutate.py -- the MEASURED mutation table for amdev.bend.

One edit to a scratch copy, run the INTERPRETED lane, diff the row NAMES. The
useful column is "rows moved", because a mutation that moves nothing measures what
this gate does NOT see -- and those are reported, not closed.

    .venv/bin/python .agents/slop/amdev_mutate.py
"""
import subprocess, sys, os, shutil

SRC = 'tinybendygrad/runtime/support/am/amdev.bend'
BEND = './bin/bend'

def rows(text):
  return [l.split('=', 1)[0] for l in text.splitlines() if '=' in l]

def run(path):
  r = subprocess.run([BEND, path], capture_output=True, text=True)
  return r.stdout, r.stderr

base_out, base_err = run(SRC)
assert 'ALL PROOFS' in base_err or base_out, base_err[:400]
BASE = rows(base_out)
BASEV = base_out

# (label, the literal to replace, the replacement, what it is testing)
M = [
  ("M1",  'Bool.or(U32.is_gt(am, bm), Bool.and(U32.is_eq(am, bm), v.ge2(an, ax, bn, bx)))',
         'Bool.or(U32.is_gt(am, bm), Bool.and(U32.is_eq(am, bm), v.ge2(an, ax, bn, an)))',
         'the version compare: `>` against `>=` on the MAJOR component.'),
  ("M2",  'U32.or(U32.and(aid, PCIE_AID_MASK()),\n      U32.shln(1, U32.to_nat(U32.sub(PCIE_EXT_SHIFT(), PCIE_AID_SHIFT())))), 0)',
         'U32.or(U32.and(aid, PCIE_AID_MASK()),\n      U32.shln(1, U32.to_nat(PCIE_EXT_SHIFT()))), 0)',
         'the RELATIVE shift: `1 << (34 - 32)` is `1 << 2` in the high word, and `1 << 34` in a U32 SATURATES TO 0. This is the ops_amd SQTT-pointer shape.'),
  ("M3",  'U32.shln(1, U32.to_nat(U32.sub(palloc.shift(i), 32)))',
         'U32.shln(1, U32.to_nat(U32.add(palloc.shift(i), 32)))',
         'the palloc high word: subtract 32 for the split, not add.'),
  ("M4",  'Bool.pick(U32, palloc.big(i), 0, U32.shln(1, U32.to_nat(palloc.shift(i))))',
         'Bool.pick(U32, palloc.big(i), 1, U32.shln(1, U32.to_nat(palloc.shift(i))))',
         'the palloc low word: for a 64-bit entry it must be ZERO, and a 1 there would make the allocator hand out 2^32 + n.'),
  ("M5",  'Bool.pick(String, v.lt3(gcmaj, gcmin, gcrev, 12, 0, 0), MOD_NBIO(), MOD_NBIF())',
         'Bool.pick(String, v.lt3(gcmaj, gcmin, gcrev, 11, 0, 0), MOD_NBIO(), MOD_NBIF())',
         ':406 `nbio` for ip_ver < (12,0,0) -- moving the boundary to 11.'),
  ('M6',  'palloc.nbig.at(+i: U32, got: U32) -> U32: U32.add(got, Bool.to_u32(palloc.big(i)))',
         'palloc.nbig.at(+i: U32, got: U32) -> U32: U32.add(got, Bool.to_u32(palloc.big(U32.sub(i, 1))))',
         'the palloc 64-bit test reads the NEXT index, so `nbig` counts one too few.'),
  ("M7",  'Bool.pick(U32, aid.bigger(acc, x), acc, x)',
         'Bool.pick(U32, aid.bigger(x, acc), acc, x)',
         'the `max((k >> 2 ...), default=0)` fold: the argument order decides which wins.'),
  ('M8',  'def mods.names.at(+nb: String) -> List<&2, String>:\n  List.append(&2, String, mods.names(), [nb])',
         'def mods.names.at(+nb: String) -> List<&2, String>:\n  List.append(&2, String, [nb], mods.names())',
         ':405-407 builds the module list and appends nbio/nbif LAST; prepending it changes which table each IP is keyed by.'),
  ("M9",  'Bool.pick(U32, read, U32.or(addr, U32.shln(RLCG_READ_BIT(), U32.to_nat(RLCG_READ_SHIFT()))), addr)',
         'Bool.pick(U32, read, addr, U32.or(addr, U32.shln(RLCG_READ_BIT(), U32.to_nat(RLCG_READ_SHIFT()))))',
         'the RLC gateway\'s read/write bit: `(addr | 1<<28) << 32` is a read, `addr << 32` a write. Swapping them is a silently wrong gateway command.'),
  ("M10", 'Tr.pair(1, hi, Tr.pair(0, lo, t))', 'Tr.pair(0, hi, Tr.pair(1, lo, t))',
         'wreg_pair\'s ORDER: the LOW word is stored first. This mutation swaps the SLOTS, not the nesting, so it is the argument order.'),
  ("M11", 'mb.msgbuf(i: Nat, +req: U32, +addr: U32, +t: Tr) -> Tr:\n  match i:\n    case 0n: t\n    case 1n+m: mb.msgbuf(m, req, U32.add(addr, 1), Tr.mm_wr(addr, mb.word_of(req, addr), t))',
         'mb.msgbuf(i: Nat, +req: U32, +addr: U32, +t: Tr) -> Tr:\n  match i:\n    case 0n: t\n    case 1n+m: mb.msgbuf(m, req, U32.add(addr, 1), Tr.mm_wr(addr, mb.word_of(req, U32.add(addr, 1)), t))',
         ':272 `for i, val in enumerate((req, 0, 0, 0)): mmio[TRN_DW0 + i] = val` -- the REQUEST goes in the FIRST word, so writing the next address\'s value would put the request one word late.'),
  ("M12", 'Bool.pick(Tr, wait_ready,\n    Tr.mb_wr(1, 2,\n      Tr.wait(MB_WAIT_READY(), MAILBOX_MSG_TIMEDOUT(),\n        mb.poll(0, True{}, Tr.mb_wr(0, 0, t)))),\n    Tr.mb_wr(0, 0, t))',
         'Bool.pick(Tr, wait_ready,\n    Tr.mb_wr(1, 2,\n      Tr.wait(MB_WAIT_READY(), MAILBOX_MSG_TIMEDOUT(),\n        mb.poll(0, True{}, Tr.mb_wr(0, 0, t)))),\n    t)',
         ':276 `vf_mailbox[0] = 0` is UNCONDITIONAL -- only the ready wait and the ack are behind `if wait_ready:`. This mutation drops the FALSE arm\'s store.'),
  ('M13', 'def rv.hi(caddr) -> U32: U32.shrn(caddr, 31n)', 'def rv.hi(caddr) -> U32: U32.shrn(caddr, 32n)',
         ':351 `wreg(0x06, caddr >> 31)` -- the high address bit, off by one.'),
  ('M14', 'def rv.lo(caddr) -> U32: U32.or(U32.and(caddr, VRAM_WIN_MASK()), VRAM_WIN_FLAG())',
         'rv.lo(caddr) -> U32: U32.or(U32.and(caddr, VRAM_WIN_MASK()), 0)',
         ':352 `(caddr & 0x7FFFFFFF) | 0x80000000` -- dropping the mask keeps the address bit that selects the window half.'),
  ("M15", 'Bool.pick(Tr, pre, Bool.pick(Tr, more,\n    Tr.rd_cfg(U32.add(cap, 1), 1, Tr.rd_cfg(cap, 1, t)),\n    Tr.rd_cfg(cap, 1, t)), t)',
         'Bool.pick(Tr, pre, Bool.pick(Tr, more,\n    Tr.rd_cfg(cap, 1, Tr.rd_cfg(U32.add(cap, 1), 1, t)),\n    Tr.rd_cfg(cap, 1, t)), t)',
         'the ASPM probe ORDER: `cap` then `cap + 1`. The inner call is evaluated first, so the argument that reads LAST must be the OUTER one. Invisible on every fixture with one read per step.'),
  ('M16', 'Bool.pick(Tr, Bool.and(U32.is_ne(cap, 0), Bool.not(aspm.seen(cap, seen)))),',
         'Bool.pick(Tr, Bool.and(U32.is_ne(cap, 0), Bool.or(aspm.seen(cap, seen), False{}))),',
         ':154 `if cap and cap not in seen` -- `not` against `or`.'),
  ("M17", 'U32.and(raw, ASPM_LNKCTL_MASK())', 'ASPM_LNKCTL_MASK()',
         ':154 writes `read_config(...) & ~3`, NOT the mask itself; writing the mask would clear every other Link Control bit.'),
  ("M18", 'Bool.pick(Nat, U32.is_eq(v, want), i, best)', 'Bool.pick(Nat, U32.is_eq(v, want), best, i)',
         'the two-way table SEARCH: `:400`\'s dict comprehension OVERWRITES, so the LAST duplicate wins (UVD_HWID and VCN_HWID are both 12).'),
  ("M19", 'Bool.pick(Nat, String.eq(s, want), i, best)', 'Bool.pick(Nat, String.eq(s, want), best, i)',
         'the two-way table\'s REVERSE direction, which is a different walk.'),
  ("M20", 'Bool.or(aid.is_mask(mask, AID_ALIVE_F()),\n    Bool.or(aid.is_mask(mask, AID_ALIVE_3()), aid.is_mask(mask, AID_ALIVE_C())))',
         'Bool.or(aid.is_mask(mask, AID_ALIVE_F()),\n    Bool.or(aid.is_mask(mask, AID_ALIVE_3()), aid.is_mask(mask, 12)))',
         'the AID alive-mask SET {0xf, 0x3, 0xc}: 0xc IS AID_ALIVE_C(), so this mutation is a CONTROL. It should move nothing.'),
  ("M21", 'v.ge2(+an: U32, +ax: U32, +bn: U32, +bx: U32) -> Bool:\n  Bool.or(U32.is_gt(an, bn), Bool.and(U32.is_eq(an, bn), U32.is_ge(ax, bx)))',
         'v.ge2(+an: U32, +ax: U32, +bn: U32, +bx: U32) -> Bool:\n  Bool.or(U32.is_gt(an, bn), Bool.and(U32.is_eq(an, bn), U32.is_ge(ax, ax)))',
         'the version TAIL compare: reading `ax` on both sides is an EQUIVALENCE, not a bug -- reported as a blind spot, NOT closed with a row.'),
  ("M22", 'def MOD_NBIO() -> String: "nbio"', 'def MOD_NBIO() -> String: "nbio"',
         'a comment-only-equivalent edit. THE CONTROL: a table with no row that CANNOT move is a table of coincidences.'),
]

print(f"{'id':<5}{'rows moved':>11}  what")
print('-' * 100)
zero = []
for label, old, new, what in M:
  s = open(SRC).read()
  if old not in s:
    print(f"{label:<5}{'EDIT NOT FOUND':>11}  {what}")
    continue
  # The scratch copy MUST live IN THE TREE: `import ../../../helpers.bend` is a
  # RELATIVE path, so a copy under $TMPDIR cannot resolve it and every mutation
  # would report "did not compile" for a reason that has nothing to do with the
  # edit. Removed afterwards whatever happens.
  SCRATCH = os.path.join(os.path.dirname(SRC), '_amdev_mut.bend')
  open(SCRATCH, 'w').write(s.replace(old, new, 1))
  out, err = run(SCRATCH)
  os.path.exists(SCRATCH) and os.remove(SCRATCH)
  if not out.strip():
    print(f"{label:<5}{'DID NOT COMPILE':>15}  {what}")
    continue
  got = rows(out)
  # `rows` answers KEYS, so the value dicts must be built from the RAW output, not
  # from `BASE`. The first version read `BASE` here and got two EMPTY dicts, so
  # every mutation reported "0 rows moved" -- a harness that cannot see its own
  # edits. `BASEV` is the baseline's own `k=v` map.
  gd = dict(x.split('=', 1) for x in out.splitlines() if '=' in x)
  bd = dict(x.split('=', 1) for x in BASEV.splitlines() if '=' in x)
  moved = sorted(set(gd) ^ set(bd)) + sorted(k for k in set(gd) & set(bd) if gd[k] != bd[k])
  n = len(moved)
  if n == 0: zero.append(label)
  print(f"{label:<5}{n:>11}  {what}")
  if n and n <= 6: print(f"{'':<17}{moved}")
print('-' * 100)
print(f"baseline rows: {len(BASE)}")
print(f"mutations moving nothing: {zero or 'none'}")
