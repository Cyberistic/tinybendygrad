#!/usr/bin/env python3
"""Mutation harness for tinybendygrad/runtime/support/system.bend.

One edit per rule, applied to a scratch copy INSIDE THE TREE (a $TMPDIR copy cannot
resolve `import ../../helpers.bend`), and the harness diffs WHOLE `name=value` LINES
-- never row names. Rule 59: a name-diff harness reports 0 for every mutation whose
effect is a changed value, and every mutation in this file changes a value.

    uv run python .agents/slop/system_mutate.py            # the table
    uv run python .agents/slop/system_mutate.py M7         # one mutation, verbose

`HARNESS-FAIL` means the edit did not land, which is a broken instrument and not a
finding (rule 6 of the `1..10` series).
"""
import re, subprocess, sys, os, pathlib

ROOT = pathlib.Path(__file__).resolve().parents[2]
SRC = ROOT / "tinybendygrad" / "runtime" / "support" / "system.bend"
SCRATCH = ROOT / "tinybendygrad" / "runtime" / "support" / "_mutate.bend"
BEND = ROOT / "bin" / "bend"
ROWS = ROOT / ".agents" / "slop" / "system-rows.txt"

# (id, the substring to find, the substring to replace, what it is testing)
MUTATIONS = [
  ("M1", "def cap.locked_of(osx: U32) -> U32:\n  Bool.pick(U32, U32.is_eq(osx, CAP_YES()), CAP_LOCKED_OSX(), CAP_LOCKED_LINUX())",
         "def cap.locked_of(osx: U32) -> U32:\n  Bool.pick(U32, U32.is_eq(osx, CAP_NO()), CAP_LOCKED_OSX(), CAP_LOCKED_LINUX())",
         ":51's `0 if OSX else 0x2000`, with the ternary reversed"),
  ("M2", "def cap.populate_of(osx: U32) -> U32:\n  Bool.pick(U32, U32.is_eq(osx, CAP_YES()), CAP_POPULATE_OSX(), CAP_POPULATE_LINUX())",
         "def cap.populate_of(osx: U32) -> U32:\n  Bool.pick(U32, U32.is_eq(osx, CAP_NO()), CAP_POPULATE_OSX(), CAP_POPULATE_LINUX())",
         ":51's `getattr(mmap, 'MAP_POPULATE', 0 if OSX else 0x008000)`, reversed"),
  ("M3", "def MAP_ANONYMOUS_OSX() -> U32: 4096", "def MAP_ANONYMOUS_OSX() -> U32: 32",
         "MAP_ANONYMOUS's platform split -- a host value where a platform one belongs"),
  ("M4", "def PAGEFRAME_MASK_HI() -> U32: 8388607", "def PAGEFRAME_MASK_HI() -> U32: 134217727",
         "(1<<55)-1's HIGH word. 0x7fffff vs 0x7ffffff: one hex digit, and the bug I made"),
  ("M5", 'String.concat(["sudo sh -c \'echo ", value, " > ", path, "\'"])',
         'String.concat(["sudo sh -c \'echo", value, ">", path, "\'"])',
         "WALL 2's SPACES around the `>`. A dropped space is a `sudo` that writes a file named `echo1`"),
  ("M6", "def sysfs.echo", "def sysfs.echo_renamed", "the def is GONE (a rename is the one edit that proves the rows read the def)"),
  ("M7", "def sys.reserve_va.put(va_start: U32, va_size: U32, osx: U32, seen: Bool, +t: Tr) -> Tr:\n  Bool.pick(Tr, seen, t, sys.reserve_va.take(va_start, va_size, osx, t))",
         "def sys.reserve_va.put(va_start: U32, va_size: U32, osx: U32, seen: Bool, +t: Tr) -> Tr:\n  sys.reserve_va.take(va_start, va_size, osx, t)",
         "THE CACHE. :86's `functools.cache` -- the negative case is IN THE PYTHON SOURCE"),
  ("M8", "  Bool.pick(Tr, needed, Tr.fail(t), t)", "  t",
         ":59's RAISE. Everything after the second read truncates"),
  ("M9", "  sysfs.again(path, value, expected, Bool.not(ok1), sysfs.read(path, t))",
         "  sysfs.again(path, value, expected, Bool.not(ok1), t)",
         ":57's FIRST READ. It happens on both arms, before the comparison"),
  ("M10", "def alloc.size.pick(+rounded: U32, +contiguous: Bool, +size: U32) -> U32:\n  Bool.pick(U32, contiguous, rounded, size)",
          "def alloc.size.pick(+rounded: U32, +contiguous: Bool, +size: U32) -> U32:\n  rounded",
          "THE WALRUS. `size := round_up(...)` is inside the `if contiguous`, so a plain request is never rounded"),
  ("M11", "def alloc.fixed(+vaddr: U32) -> U32: Bool.pick(U32, U32.is_zero(vaddr), 0, MAP_FIXED())",
          "def alloc.fixed(+vaddr: U32) -> U32: MAP_FIXED()",
          ":100's `(MAP_FIXED if vaddr else 0)` -- a FALSY test, not a None test"),
  ("M12", "def bars.buses.pick(+bus1: U32, +gpu: U32) -> U32: U32.or(U32.shln(bus1, 8n), U32.shln(gpu, 16n))",
          "def bars.buses.pick(+bus1: U32, +gpu: U32) -> U32: U32.or(U32.shln(gpu, 8n), U32.shln(bus1, 16n))",
          ":141's `(bus+1) << 8 | (gpu_bus) << 16` -- the two shifts TRANSPOSED. A silently wrong bus number"),
  ("M13", "def bars.mem_base16(mem_base: U32) -> U32: U32.and(U32.shrn(mem_base, 16n), U16MAX())",
          "def bars.mem_base16(mem_base: U32) -> U32: U32.and(mem_base, U16MAX())",
          ":144's `(mem_base>>16) & 0xffff` -- the shift dropped"),
  ("M14", "def bars.pref_base16(+hi: U32, +lo: U32) -> U32: U32.and(U32.shrn(lo, 16n), U16MAX())",
          "def bars.pref_base16(+hi: U32, +lo: U32) -> U32: U32.and(hi, U16MAX())",
          "the HIGH word substituted for the low one. The bug I made: 8 instead of 0"),
  ("M15", "def bars.rebar_size(cap: U32) -> U32:\n  U32.shln(U32.sub(hx.bitlen(U32.shrn(cap, 4n)), 1), 8n)",
          "def bars.rebar_size(cap: U32) -> U32:\n  U32.shln(U32.sub(hx.bitlen(U32.shrn(cap, 4n)), 1), 4n)",
          ":158's `<< 8` -- the shift amount, which resizes a BAR to the wrong power of two"),
  ("M16", "def REBAR_CTRL_MASK() -> U32: 4294959359", "def REBAR_CTRL_MASK() -> U32: 4294963199",
          "`~0x1F00` -- the bits it CLEARS"),
  ("M17", "def bars.size32(lo: U32) -> U32: U32.sub(0, U32.and(lo, LO_MASK()))",
          "def bars.size32(lo: U32) -> U32: U32.sub(0, U32.and(lo, 255))",
          ":175's `& ~0xf`. A BAR size four orders of magnitude wrong"),
  ("M18", "def bars.step.pick(+bar_off: U32, step: U32) -> U32: U32.add(bar_off, step)",
          "def bars.step.pick(+bar_off: U32, step: U32) -> U32: U32.add(bar_off, BAR_OFF_STEP64())",
          ":183's `bar_off += 8 if bar_64 else 4` -- the two arms SWAPPED"),
  ("M19", "def bars.more(bar_off: U32) -> Bool: U32.is_lt(bar_off, BAR_LOOP_BOUND())",
          "def bars.more(bar_off: U32) -> Bool: U32.is_le(bar_off, BAR_LOOP_BOUND())",
          "`while bar_off < 24` -- `<` against `<=`, so the loop runs one BAR too many"),
  ("M20", "  Bool.or(U32.is_gt(ah, bh), Bool.and(U32.is_eq(ah, bh), U32.is_ge(al, bl)))",
          "  Bool.or(U32.is_gt(ah, bh), Bool.and(U32.is_eq(ah, bh), U32.is_gt(al, bl)))",
          "the two-word lexicographic `>=`. `va_base <= lo` with `==` refused"),
  ("M21", "def bar.size(lo: U32, +hi: U32) -> U32: U32.add(U32.sub(hi, lo), BAR_INFO_DELTA())",
          "def bar.size(lo: U32, +hi: U32) -> U32: U32.sub(hi, lo)",
          ":260's `int(e,16) - int(s,16) + 1`. The `+ 1` IS the whole of bar_info"),
  ("M22", "def face.is_bar_small(bar_size: U32) -> Bool: U32.is_eq(bar_size, SMALL_BAR_SIZE())",
          "def face.is_bar_small(bar_size: U32) -> Bool: U32.is_ge(bar_size, SMALL_BAR_SIZE())",
          ":300's `== (256 << 20)` turned into a comparison -- a 1 GiB bar is suddenly 'small'"),
  ("M23", "def face.devmem_align.pick(+big: Bool, +amt: U32) -> U32: Bool.pick(U32, big, TWO_MB(), amt)",
          "def face.devmem_align.pick(+big: Bool, +amt: U32) -> U32: Bool.pick(U32, big, amt, TWO_MB())",
          ":315's `(2 << 20) if size >= (8 << 20) else (4 << 10)` -- the two arms SWAPPED"),
  ("M24", "  Bool.pick(U32, sysmem, sysmem_align, dev_align)", "  Bool.pick(U32, sysmem, dev_align, sysmem_align)",
          ":315's `PAGESIZE if should_use_sysmem else <ladder>` -- the two arms SWAPPED"),
  ("M25", "def hx.width.p1(+a: Bool, +b: Bool, +c: Bool) -> U32:\n  Bool.pick(U32, a, 1, Bool.pick(U32, b, 2, Bool.pick(U32, c, 3, 4)))",
          "def hx.width.p1(+a: Bool, +b: Bool, +c: Bool) -> U32:\n  Bool.pick(U32, a, 1, Bool.pick(U32, b, 2, Bool.pick(U32, a, 3, 4)))",
          "the THIRD threshold of the `%x` ladder. The bug I made: one predicate for two rungs"),
  ("M26", "def hx.digit.pick(+v: U32, dec: Bool) -> String:\n  Bool.pick(String, dec, String.from_list([Char.from_u32(U32.add(48, v))]),\n    String.from_list([Char.from_u32(U32.add(87, v))]))",
          "def hx.digit.pick(+v: U32, dec: Bool) -> String:\n  Bool.pick(String, dec, String.from_list([Char.from_u32(U32.add(48, v))]),\n    String.from_list([Char.from_u32(U32.add(86, v))]))",
          "the `a`-..`f` base of `%x`. Off by one in one letter, and only the letters see it"),
  ("M27", "def post.nclamp(+n: U32) -> U32: Bool.pick(U32, U32.is_ge(n, POST_NSLOTS()), POST_NSLOTS(), n)",
          "def post.nclamp(+n: U32) -> U32: n",
          ":418's `[:3]` TRUNCATION -- a fourth argument would be sent"),
  ("M28", "def rpc.port.pick(+has_colon: Bool, +port: U32) -> U32:\n  Bool.pick(U32, has_colon, port, REMOTE_DEFAULT_PORT())",
          "def rpc.port.pick(+has_colon: Bool, +port: U32) -> U32:\n  Bool.pick(U32, has_colon, REMOTE_DEFAULT_PORT(), port)",
          ":402's `int(...) if \":\" in r else 6667` -- the default on the wrong side"),
  ("M29", "def Rcmd.names() -> List<&2, String>:\n  [\"PROBE\", \"MAP_BAR\", \"MAP_SYSMEM_FD\", \"CFG_READ\", \"CFG_WRITE\", \"RESET\",",
          "def Rcmd.names() -> List<&2, String>:\n  [\"MAP_BAR\", \"PROBE\", \"MAP_SYSMEM_FD\", \"CFG_READ\", \"CFG_WRITE\", \"RESET\",",
          ":360's enum ORDER -- two members NEIGHBOUR-SWAPPED, which is a silently wrong remote command"),
  ("M31", "def scan.term(device: U32, mask: U32, devlist: List<&2, U32>) -> Bool:\n  List.contains(U32, U32.is_eq, devlist, U32.and(device, mask))",
          "def scan.term(device: U32, mask: U32, devlist: List<&2, U32>) -> Bool:\n  List.contains(U32, U32.is_eq, devlist, device)",
          ":126's `(device & mask)` -- the AND dropped, which refuses every NVIDIA card with a nonzero revision"),
  ("M32", "def scan.base_ok(class_code: U32, base_class: U32) -> Bool:\n  U32.is_eq(U32.shrn(class_code, 16n), base_class)",
          "def scan.base_ok(class_code: U32, base_class: U32) -> Bool:\n  U32.is_eq(U32.shrn(class_code, 8n), base_class)",
          ":116/:122's `>> 16`"),
  ("M33", "def scan.cap_id(hdr: U32) -> U32: U32.and(hdr, 255)", "def scan.cap_id(hdr: U32) -> U32: U32.shrn(hdr, 8n)",
          ":156's `PCI_EXT_CAP_ID` -- the low BYTE, not bits 15:8"),
  ("M34", "def pci.bus_trim.pick(+pcibus: String, n: U32) -> String: String.take(pcibus, U32.to_nat(n))",
          "def pci.bus_trim.pick(+pcibus: String, n: U32) -> String: String.drop(pcibus, U32.to_nat(n))",
          ":220's `pcibus[:-1]` -- `take` against `drop`. `drop` removes from the FRONT"),
  ("M35", "def pci.class_prefix(device: String) -> String: String.take(device, 2n)",
          "def pci.class_prefix(device: String) -> String: String.take(device, 1n)",
          ":136's `device[:2]` -- the class is TWO characters, not one"),
  ("M36", "def pci.map_flags.pick(+addr: U32) -> U32: Bool.pick(U32, U32.is_zero(addr), MAP_BAR_FLAGS_OSX(), MAP_BAR_FLAGS_FIXED())",
          "def pci.map_flags.pick(+addr: U32) -> U32: Bool.pick(U32, U32.is_zero(addr), MAP_BAR_FLAGS_FIXED(), MAP_BAR_FLAGS_OSX())",
          ":263's `MAP_SHARED | (MAP_FIXED if addr else 0)`"),
  ("M37", "def pci.resize_log2(size: U32) -> U32: U32.sub(hx.bitlen(size), BAR_INFO_DELTA())",
          "def pci.resize_log2(size: U32) -> U32: U32.sub(hx.bitlen(size), 2)",
          ":267's `bit_length() - 1` -- the wrong constant"),
  ("M38", "def meta.sysmem(+hMemory: U32) -> Meta: Meta.of(True{}, hMemory)",
          "def meta.sysmem(+hMemory: U32) -> Meta: Meta.of(False{}, hMemory)",
          ":321's LITERAL `has_cpu_mapping=True` read as the `cpu_access` argument"),
  ("M39", "def face.has_explicit(kind: U32) -> Bool: U32.is_ne(kind, KIND_PCI())",
          "def face.has_explicit(kind: U32) -> Bool: True{}",
          ":297's getattr fallback -- which of the three classes SETS peer_group"),
  ("M40", "def pci.tails() -> List<&2, String>:\n  [\"enable\", \"driver\", \"driver/unbind\", \"driver_override\", \"config\", \"iommu_group\",",
          "def pci.tails() -> List<&2, String>:\n  [\"enable\", \"driver\", \"driver_override\", \"driver/unbind\", \"config\", \"iommu_group\",",
          "the sysfs TAIL table -- two neighbours swapped, a silently wrong unbind path"),
  ("M41", "def rpc.buf_opts() -> List<&2, U32>: [SO_SNDBUF(), SO_RCVBUF()]",
          "def rpc.buf_opts() -> List<&2, U32>: [SO_RCVBUF(), SO_SNDBUF()]",
          ":393's `(SO_SNDBUF, SO_RCVBUF)` -- the two options TRANSPOSED"),
  ("M42", "     Bool.pick(U32, refused, next, U32.add(next, 1)),\n     reserved, have_atomic, have_sys, refused}",
          "     U32.add(next, 1),\n     reserved, have_atomic, have_sys, refused}",
          "THE RAISE. Every refusal row at once, and nothing else"),
  ("M43", "def elemsize.go(fmts: List<&2, String>, sizes: List<&2, U32>, +c: String, +at: U32) -> U32:\n  match fmts:\n    case Nil{}: mapflag_missing()\n    case h <> t:\n      match sizes:\n        case Nil{}: mapflag_missing()\n        case z <> u:\n          +nxt = U32.add(at, 1)\n          Bool.pick(U32, String.eq(h, c), at, elemsize.go(t, u, c, nxt))",
          "def elemsize.go(fmts: List<&2, String>, sizes: List<&2, U32>, +c: String, +at: U32) -> U32:\n  match fmts:\n    case Nil{}: mapflag_missing()\n    case h <> t:\n      match sizes:\n        case Nil{}: mapflag_missing()\n        case z <> u:\n          +nxt = U32.add(at, 1)\n          Bool.pick(U32, String.eq(h, c), at, mapflag_missing())",
          "the struct calcsize table's WALK -- a stub that always misses, so only the negative row moves"),
  ("M44", "def mapflag_of.go(+v: U32, vs: List<&2, U32>, +at: U32) -> U32:\n  match vs:\n    case Nil{}: mapflag_missing()\n    case x <> t:\n      +nxt = U32.add(at, 1)\n      Bool.pick(U32, U32.is_eq(v, x), at, mapflag_of.go(v, t, nxt))",
          "def mapflag_of.go(+v: U32, vs: List<&2, U32>, +at: U32) -> U32:\n  match vs:\n    case Nil{}: at\n    case _x <> t: mapflag_of.go(v, t, U32.add(at, 1))",
          "the mmap table's WALK, reduced to its length. Only the name rows and the missing row can move"),
  ("M45", "def bars.writes.cmd(+bus: U32, +xs: List<&2, Cfg>) -> List<&2, Cfg>:\n  bars.put8(xs, Cfg.of(PCI_COMMAND(), bus, 0, 0, PCI_COMMAND_ALL(), 1))",
          "def bars.writes.cmd(+bus: U32, +xs: List<&2, Cfg>) -> List<&2, Cfg>:\n  bars.put8(bars.put8(xs, Cfg.of(PCI_COMMAND(), bus, 0, 0, PCI_COMMAND_ALL(), 1)), Cfg.of(PCI_COMMAND(), bus, 0, 0, PCI_COMMAND_ALL(), 1))",
          "the EIGHTH write -- :151's PCI_COMMAND duplicated. The bug I made: nine writes for eight"),
  ("M46", "def bars.writes.of(+bus: U32, +gpu_bus: U32, +acc: List<&2, Cfg>) -> List<&2, Cfg>:\n  bars.writes.cmd(bus,",
          "def bars.writes.of(+bus: U32, +gpu_bus: U32, +acc: List<&2, Cfg>) -> List<&2, Cfg>:\n  bars.writes.cmd(0,",
          ":141's `bus` threaded into the first write -- pinned at zero, which is the bus-0 fixture"),
  ("M48", "def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>, +at: Nat) -> Bool:\n  match n:\n    case 0n: Nat.is_eq(at, patlen)\n    case 1n+m:\n      match cs:\n        case Nil{}: Nat.is_eq(at, patlen)\n        case c <> t: Tr.has.go(m, patlen, t, pat, Tr.step(List.get(&2, Call, pat, at), c, at))",
          "def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>, +at: Nat) -> Bool:\n  match n:\n    case 0n: True{}\n    case 1n+m:\n      match cs:\n        case Nil{}: True{}\n        case c <> t: Tr.has.go(m, patlen, t, pat, Tr.step(List.get(&2, Call, pat, at), c, at))",
          "Tr.has with the answer hard-wired -- the order rows and the matcher, all of them"),
  ("M47", "# THE CLAMP IS A THEOREM, and M27 measured it", "# THE CLAMP IS A THEOREM (M27)", "CONTROL -- a comment-only edit. A table with no row that CANNOT move is a table of coincidences"),
  ("M49", "def pci.probe(+pcibus: String, +bound: Bool, use_vfio: Bool, t: Tr) -> Tr:\n  pci.probe.unbound(pcibus, use_vfio, bound,\n    pci.probe.sibs(pcibus, pci.probe.drv2(pcibus, bound,\n      pci.probe.drv1(pcibus, pci.probe.enable(pcibus, t)))))",
          "def pci.probe(+pcibus: String, +bound: Bool, use_vfio: Bool, t: Tr) -> Tr:\n  pci.probe.unbound(pcibus, use_vfio, bound,\n    pci.probe.sibs(pcibus, pci.probe.drv2(pcibus, bound,\n      pci.probe.drv1(pcibus, t))))",
          ":211's `enable` open -- the DEAD-CODE probe. A def nothing calls is invisible to every other check"),
  ("M50", "def gid.of(+tail: U32) -> String: gid.of.p2(U32.shrn(tail, 16n), U32.and(tail, 65535))",
          "def gid.of(+tail: U32) -> String: gid.of.p2(U32.and(tail, 65535), U32.shrn(tail, 16n))",
          ":53's tail ORDER -- four bytes the wrong way round, and every length and total still correct"),
]


def run(path):
  r = subprocess.run([str(BEND), str(path)], capture_output=True, text=True, cwd=ROOT)
  if r.returncode != 0:
    return None, r.stdout + r.stderr
  return dict(l.split("=", 1) for l in r.stdout.strip().split("\n") if "=" in l), ""


def main():
  only = sys.argv[1] if len(sys.argv) > 1 else None
  base_text = SRC.read_text()
  base, err = run(SRC)
  if base is None:
    print("BASELINE DOES NOT RUN:\n" + err[:2000]); return 1
  ref = ROWS.read_text()
  assert len(base) == len([l for l in ref.split("\n") if "=" in l]), "baseline disagrees with the captured rows"
  print(f"baseline: {len(base)} rows, run clean, exit 0\n")
  print("| # | rows moved | what it is testing |")
  print("| --- | --- | --- |")
  seen = set()
  for mid, find, repl, what in MUTATIONS:
    if mid in seen: continue
    seen.add(mid)
    if only and mid != only: continue
    if not find or not repl or find == repl:
      print(f"| {mid} | HARNESS-FAIL | the edit is malformed (empty or identical halves) |"); continue
    if find not in base_text:
      print(f"| {mid} | HARNESS-FAIL | the ANCHOR is not in the file (the edit did not land) |")
      if only: print(f"\n--- {mid} anchor ---\n{find[:400]}")
      continue
    SCRATCH.write_text(base_text.replace(find, repl, 1))
    got, err = run(SCRATCH)
    if got is None:
      moved = f"COMPILE-FAIL ({err.strip().splitlines()[2] if len(err.strip().splitlines())>2 else err[:60]})"
      print(f"| {mid} | {moved} | {what} |")
    else:
      names = sorted(k for k in set(base) | set(got) if base.get(k) != got.get(k))
      moved = f"**{len(names)}**" + ("" if not names else " <br>" + ", ".join(f"`{n}`" for n in names[:14]) + (" ..." if len(names) > 14 else ""))
      print(f"| {mid} | {moved} | {what} |")
    SCRATCH.unlink(missing_ok=True)
  return 0


if __name__ == "__main__":
  sys.exit(main())
