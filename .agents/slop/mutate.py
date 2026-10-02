#!/usr/bin/env python3
"""The mutation harness for ops_rdma.bend, ops_npy.bend and nn/torch.bend.

Applies ONE textual edit to a scratch copy of a port file, runs the INTERPRETED
lane, and diffs the resulting row NAMES against the unmutated baseline. Prints
`| M<n> | rows moved | what it is testing |`. A mutation that moves NOTHING is
information about the GATE and not about the code, and says so.

    python3 .agents/slop/mutate.py tinybendygrad/nn/torch.bend
"""
import subprocess, sys, os, tempfile, shutil

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
BEND = os.path.join(ROOT, 'bin', 'bend')


def rows(path):
  out = subprocess.run([BEND, path], capture_output=True, text=True, cwd=ROOT)
  if out.returncode != 0:
    return None, out.stdout + out.stderr
  d = {}
  for line in out.stdout.splitlines():
    if '=' in line:
      k, v = line.split('=', 1)
      d[k] = v
  return d, None


def run(rel, muts, verbose=True):
  base, err = rows(os.path.join(ROOT, rel))
  if base is None:
    print(f"{rel}: BASELINE FAILED\n{err}")
    return
  src = open(os.path.join(ROOT, rel)).read()
  print(f"\n=== {rel} -- {len(base)} baseline rows ===")
  for i, (name, old, new) in enumerate(muts, 1):
    if old is None:
      print(f"| M{i} | NOT RUN | {name}")
      continue
    if old not in src:
      print(f"| M{i} | !! PATTERN NOT FOUND | {name}")
      continue
    d = tempfile.mkdtemp()
    # beside the original, so the RELATIVE imports still resolve
    tgt = os.path.join(ROOT, os.path.dirname(rel), '.mut_' + os.path.basename(rel))
    open(tgt, 'w').write(src.replace(old, new, 1))
    try:
      got, err = rows(tgt)
      if got is None:
        print(f"| M{i} | DID NOT COMPILE | {name}")
      else:
        moved = sorted(k for k in set(base) | set(got) if base.get(k) != got.get(k))
        print(f"| M{i} | {len(moved)} | {name}")
        if verbose and moved:
          print(f"|      | moved: {', '.join(moved)} |")
    finally:
      os.remove(tgt)
      shutil.rmtree(d, ignore_errors=True)


TORCH = [
 ("`drop2` drops ONE component (parent, not parent.parent)",
  "U32.add(prev, U32.add(1, U32.from_nat(String.length(x))))",
  "U32.add(1, U32.from_nat(String.length(x)))"),
 ("`tail2` drops ONE separator from the total",
  "Ac{U32.add(prev, U32.add(1, U32.from_nat(String.length(x)))), U32.add(1, U32.from_nat(String.length(x)))}",
  "Ac{U32.add(prev, U32.from_nat(String.length(x))), U32.add(1, U32.from_nat(String.length(x)))}"),
 ("`as_posix` maps EVERY char to a slash",
  "Bool.pick(Char, Char.is_eq(h, BSLASH_C()), SLASH_C(), h)", "SLASH_C()"),
 ("`drop2` returns DOT for a rooted path too",
  "Bool.pick(String, rooted, ROOT_SLASH(), DOT()),", "DOT(),"),
 ("`drop2` takes a PREFIX (drop) instead of a SUFFIX (take)",
  "String.take(s, Nat.sub(String.length(s), U32.to_nat(tail)))",
  "String.drop(s, U32.to_nat(tail))"),
 ("`MSG()` joins the two halves the wrong way round",
  'def MSG() -> String: String.concat([MSG_HEAD(), NL(), MSG_TAIL()])',
  'def MSG() -> String: String.concat([MSG_TAIL(), NL(), MSG_HEAD()])'),
 ("the path append happens AFTER the import",
  "def shim.run(f: String, ok: Bool) -> Imp: shim.import(ok, shim.append(f, Imp.of()))",
  "def shim.run(f: String, ok: Bool) -> Imp: shim.append(f, shim.import(ok, Imp.of()))"),
 ("the raise is NOT recorded in the trace",
  "List.append(&2, Call, calls, [Call{CALL_RAISE(), FROM_E()}]))),\n         Bool.pick(Bool, ok, refused, True{})}",
  "calls)),\n         Bool.pick(Bool, ok, refused, True{})}"),
 ("the raise does NOT set `refused`",
  "Bool.pick(Bool, ok, refused, True{})", "refused"),
 ("`ok` is ignored -- the raise always fires",
  "      Tr{Bool.pick(List<&2, Call>, ok, calls,\n                   Bool.pick(List<&2, Call>, refused, calls,\n                             List.append(&2, Call, calls, [Call{CALL_RAISE(), FROM_E()}]))),\n         Bool.pick(Bool, ok, refused, True{})}",
  "      Tr{Bool.pick(List<&2, Call>, refused, calls,\n                   Bool.pick(List<&2, Call>, refused, calls,\n                             List.append(&2, Call, calls, [Call{CALL_RAISE(), FROM_E()}]))),\n         True{}}"),
 ("a comment-only edit -- THE CONTROL",
  "# THE SPLIT, stated once and then obeyed. A def here EITHER derives the argument",
  "# THE SPLIT, stated once and then obeyed (control). A def here EITHER derives"),
]

NPY = [
 ("`renderers or [Renderer]` -- the EMPTY list survives",
  "def Npy.of(+dev: String) -> Npy:\n  Npy{dev, ALLOC_HOST(), RUNTIME_NONE(), RENDERERS_EFFECTIVE(), False{}, False{},",
  "def Npy.of(+dev: String) -> Npy:\n  Npy{dev, ALLOC_HOST(), RUNTIME_NONE(), RENDERERS_PASSED(), False{}, False{},"),
 ("`npy.mmap` rounds the size up to a page",
  "def npy.mmap(size: U32, t: Tr) -> Tr: Tr.emit(CALL_MMAP(), size, t)",
  "def npy.mmap(size: U32, t: Tr) -> Tr: Tr.emit(CALL_MMAP(), H.round_up_u32(size, 4096), t)"),
 ("`synchronize` moves AFTER the view and the write",
  "  Tr.emit(CALL_MVWRITE(), len, npy.mview(len, npy.sync(t)))",
  "  npy.sync(Tr.emit(CALL_MVWRITE(), len, npy.mview(len, t)))"),
 ("`_copyin` copies the BUFFER's length, not the source's",
  "def npy.copyin(+len: U32, t: Tr) -> Tr:\n  Tr.emit(CALL_MVWRITE(), len, npy.mview(len, npy.sync(t)))",
  "def npy.copyin(+len: U32, t: Tr) -> Tr:\n  Tr.emit(CALL_MVWRITE(), 12, npy.mview(12, npy.sync(t)))"),
 ("`_map`'s host guard is dropped",
  "  npy.map.at(D.map_ok(src_host, dev_host), t)", "  npy.map.at(True{}, t)"),
 ("`_free` always munmaps",
  "  Bool.pick(Tr, remote, Tr.emit(CALL_MUNMAP(), 0, t), t)", "  Tr.emit(CALL_MUNMAP(), 0, t)"),
 ("`alloc`'s `assert size > 0` is dropped",
  "  Bool.pick(Tr, U32.is_gt(size, 0), npy.alloc.go(Sz{size, npy.alloc_msg(size)}, t),\n            Tr.refuse(REFUSE_ALLOC(), t))",
  "  npy.alloc.go(Sz{size, npy.alloc_msg(size)}, t)"),
 ("`_offset` returns `buf` UNCHANGED -- the RDMA rule, not the host one",
  "def npy.offset(buf: U32, off: U32) -> U32: D.host_offset(buf, off)",
  "def npy.offset(buf: U32, off: U32) -> U32: buf"),
 ("the refusal ENTRY is guarded on `refused` too (nothing is ever recorded)",
  "      Tr{Bool.pick(List<&2, Call>, refused, calls,\n                   List.append(&2, Call, calls, [Call{CALL_REFUSE(), which}])), True{}}",
  "      Tr{Bool.pick(List<&2, Call>, refused, calls,\n                   List.append(&2, Call, calls, [Call{CALL_REFUSE(), which}])), refused}"),
 ("a comment-only edit -- THE CONTROL",
  "# FOUR LINES:", "# FOUR LINES (control):"),
]

RDMA = [
 ("the candidate list is DESCENDING, so the fold's LAST match is the SMALLEST",
  "  [LP_12(), LP_13(), LP_16(), LP_18(), LP_20(), LP_21(), LP_22(), LP_30()]",
  "  [LP_30(), LP_22(), LP_21(), LP_20(), LP_18(), LP_16(), LP_13(), LP_12()]"),
 ("`log_page` answers 12 when NOTHING matches -- no ValueError",
  "log_page.go(List.length(&2, U32, lp_cands()), lp_cands(), align, NO_LOG_PAGE)",
  "log_page.go(List.length(&2, U32, lp_cands()), lp_cands(), align, LP_12())"),
 ("`wait_expected` drops the `^ 1` epoch inversion",
  "def cq_epoch_of(+n: U32) -> U32: U32.xor(U32.and(U32.div(n, CQ_ENTRIES()), 1), 1)",
  "def cq_epoch_of(+n: U32) -> U32: U32.and(U32.div(n, CQ_ENTRIES()), 1)"),
 ("the doorbell rings slot `n` instead of `n + 1`",
  "def db_slot(+n: U32) -> U32: U32.mod(U32.add(n, 1), RING_ENTRIES())",
  "def db_slot(+n: U32) -> U32: U32.mod(n, RING_ENTRIES())"),
 ("the epoch drops its `& 1`",
  "def db_epoch(+n: U32) -> U32: U32.and(U32.div(U32.add(n, 1), RING_ENTRIES()), 1)",
  "def db_epoch(+n: U32) -> U32: U32.div(U32.add(n, 1), RING_ENTRIES())"),
 ("the receive bit is dropped from `wait_expected`",
  "U32.or(cq_epoch_of(n), Bool.pick(U32, recv, 2, 0))", "cq_epoch_of(n)"),
 ("the msn slot sits at bit 0 instead of bit 48",
  "U32.or(U32.shln(U32.and(slot, PSN_MASK()), MSN_SLOT_HI_AT_NAT()), U32.shrn(U32.and(next_psn, PSN_MASK()), 8n))",
  "U32.or(U32.and(slot, PSN_MASK()), U32.shrn(U32.and(next_psn, PSN_MASK()), 8n))"),
 ("the msn psn fields are unmasked (no `& 0xffffff`)",
  "U32.or(U32.shln(U32.and(next_psn, PSN_MASK()), MSN_PSN_AT_NAT()), U32.and(p, PSN_MASK()))",
  "U32.or(U32.shln(next_psn, MSN_PSN_AT_NAT()), p)"),
 ("the send ring drops the `+ 8` msn table",
  "U32.add(WQE_SIZE(), 8)", "WQE_SIZE()"),
 ("`bump.psn` adds `packets` on a RECEIVE too",
  "def bump.psn(+recv: Bool, packets: U32) -> U32:\n  Bool.pick(U32, recv, 0, packets)",
  "def bump.psn(+recv: Bool, packets: U32) -> U32:\n  packets"),
 ("the receive header gets the size in word 2 as well",
  "def hdr2(+recv: Bool, size: U32) -> U32:\n  Bool.pick(U32, recv, 0, size)",
  "def hdr2(+recv: Bool, size: U32) -> U32:\n  size"),
 ("`psns` drops the `initial=0` -- one entry short",
  "    case 0n: List.append(&2, U32, out, [acc])\n    case 1n+m:\n      match chunks:",
  "    case 0n: out\n    case 1n+m:\n      match chunks:"),
 ("`chunks_of` reverses the chunk order",
  "def chunks.go(n: Nat, +nbytes: U32, +off: U32, +acc: List<&2, U32>) -> List<&2, U32>:\n  match n:\n    case 0n: acc",
  "def chunks.go(n: Nat, +nbytes: U32, +off: U32, +acc: List<&2, U32>) -> List<&2, U32>:\n  match n:\n    case 0n: List.reverse(&2, U32, acc)"),
 ("`alloc.buf_size` rounds the BUFFER's size to a page too",
  "def alloc.buf_size(+nbytes: U32) -> U32: nbytes", "def alloc.buf_size(+nbytes: U32) -> U32: alloc.va_size(nbytes)"),
 ("`db.off_down` keeps the low twelve bits -- the doorbell pages UP",
  "def db.off_down(+db_off: U32) -> U32: U32.and(db_off, U32.not(PAGE_MASK()))",
  "def db.off_down(+db_off: U32) -> U32: db_off"),
 ("the page guard is OUTSIDE the register call -- a warning, not a refusal",
  "  map.call(npages(sizes, log_page(align_or(va, map.paddrs(sys, raw, translated), sizes))),\n           map.page_guard(has_page(align_or(va, map.paddrs(sys, raw, translated), sizes)),\n                          map.guard2(map.peer_ok(has_iface, src_peer, dev_peer), t)))",
  "  map.page_guard(has_page(align_or(va, map.paddrs(sys, raw, translated), sizes)),\n                 map.call(npages(sizes, log_page(align_or(va, map.paddrs(sys, raw, translated), sizes))),\n                          map.guard2(map.peer_ok(has_iface, src_peer, dev_peer), t)))"),
 ("`va_of` is the forward lookup too -- no reverse direction",
  "def va_of.put(+e: PEnt, +key: U32, +got: U32) -> U32:\n  Bool.pick(U32, Bool.and(U32.is_zero(got), U32.is_eq(PEnt.key(e), key)), PEnt.va(e), got)",
  "def va_of.put(+e: PEnt, +key: U32, +got: U32) -> U32:\n  Bool.pick(U32, Bool.and(U32.is_zero(got), U32.is_eq(PEnt.va(e), key)), PEnt.key(e), got)"),
 ("`_offset` adds the offset -- the HOST allocator's rule",
  "def alloc.offset(+buf: U32) -> U32: buf", "def alloc.offset(+buf: U32) -> U32: U32.add(buf, 4)"),
 ("`submit.src_replaced` replaces EVERY src, RDMA or not",
  "def submit.src_replaced(+n_srcs: U32, n_queues: U32) -> U32: n_queues",
  "def submit.src_replaced(+n_srcs: U32, n_queues: U32) -> U32: n_srcs"),
 ("the qp buffer-name table is reversed against ops_rdma.py's order",
  '    case 1: "sq"\n    case 2: "rq"', '    case 8: "sq"\n    case 2: "rq"'),
 ("a comment-only edit -- THE CONTROL",
  "#   3. THE COMPLETION QUEUE HAS ITS OWN ORDER, AND IT IS NOT THE RING'S. The",
  "#   3. THE COMPLETION QUEUE ORDER (control). The"),
]

if __name__ == '__main__':
  for f in sys.argv[1:]:
    if f.endswith('ops_rdma.bend'):
      run('tinybendygrad/runtime/ops_rdma.bend', RDMA)
    elif f.endswith('ops_npy.bend'):
      run('tinybendygrad/runtime/ops_npy.bend', NPY)
    elif f.endswith('torch.bend'):
      run('tinybendygrad/nn/torch.bend', TORCH)