#!/usr/bin/env python3
"""Mutation harness for tinybendygrad/runtime/ops_dsp.bend.

Applies ONE textual edit to a scratch copy of the port, runs the INTERPRETED
lane, and diffs the row NAMES against the baseline.  The useful column is
"rows MOVED": a mutation that moves nothing measures what the gate does NOT
see, and is reported as a blind spot rather than papered over.

Usage: python3 .agents/slop/dsp_mutate.py [--baseline]
"""
import os, re, shutil, subprocess, sys, tempfile
import patch_not_apply as PNA

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "tinybendygrad/runtime/ops_dsp.bend")
BEND = os.path.join(ROOT, "bin/bend")
WORK = os.path.join(ROOT, "tinybendygrad/runtime")  # relative imports need the source dir

# (id, a unique substring of the OLD text, the NEW text, what it is testing)
MUTATIONS = [
  ("M1",  "def sc_method(sc: U32) -> U32: U32.shrn(sc, SC_METHOD())",
          "def sc_method(sc: U32) -> U32: U32.shrn(sc, SC_OUTS())",
          ":33's `sc>>24` -- the entry shim reads the METHOD byte. Off by one field."),
  ("M2",  "U32.or(U32.or(U32.or(U32.shln(method, SC_METHOD()), U32.shln(ins, SC_INS())),\n                U32.shln(outs, SC_OUTS())), fds)",
          "U32.or(U32.or(U32.or(U32.shln(method, SC_METHOD()), U32.shln(ins, SC_INS())),\n                U32.shln(outs, SC_METHOD())), fds)",
          ":48's four one-byte fields -- outs placed at method's shift."),
  ("M3",  "def attrs_of(nins: U32, nouts: U32, nfds: U32) -> List<&2, U32>:\n  List.append(&2, U32, fill(U32.to_nat(U32.add(nins, nouts)), ATTR_BUF(), Nil{}),\n    fill(U32.to_nat(nfds), ATTR_DMA(), Nil{}))",
          "def attrs_of(nins: U32, nouts: U32, nfds: U32) -> List<&2, U32>:\n  List.append(&2, U32, fill(U32.to_nat(nfds), ATTR_DMA(), Nil{}),\n    fill(U32.to_nat(U32.add(nins, nouts)), ATTR_BUF(), Nil{}))",
          "THE BUG the first run found: :54's head and tail swapped."),
  ("M4",  "def pra.pv_set(nbytes: U32) -> Bool: Bool.not(U32.is_zero(nbytes))",
          "def pra.pv_set(nbytes: U32) -> Bool: True{}",
          ":56's `mv.nbytes > 0 else 0` -- the ZERO-LENGTH rule."),
  ("M5",  "def pra.pv_set(nbytes: U32) -> Bool: Bool.not(U32.is_zero(nbytes))",
          "def pra.pv_set(nbytes: U32) -> Bool: False{}",
          "the same rule, the other way -- a NEGATIVE case for M4."),
  ("M6",  "def prog.exec_sc(nbufs: U32) -> U32:\n  rpc_sc(M_INVOKE(), prog.nins(), prog.nouts(), nbufs)",
          "def prog.exec_sc(nbufs: U32) -> U32:\n  rpc_sc(M_INVOKE(), prog.nins(), prog.nouts(), U32.add(nbufs, 1))",
          ":70's `fds=len(bufs)` -- the selector is a function of ONE number."),
  ("M7",  "def prog.too_many(nbufs: U32) -> Bool: U32.is_ge(nbufs, MAX_BUFS())",
          "def prog.too_many(nbufs: U32) -> Bool: U32.is_gt(nbufs, MAX_BUFS())",
          ":63's `len(bufs) >= 16` -- the refusal boundary itself."),
  ("M8",  "def vt_val_offset(nbufs: U32, j: U32) -> U32: U32.mul(U32.add(nbufs, j), 8)",
          "def vt_val_offset(nbufs: U32, j: U32) -> U32: U32.mul(j, 8)",
          ":68's `i*8` with `i` starting at `len(bufs)` -- the vals' BASE offset."),
  ("M9",  "def vt_size_at(i: U32, size: U32) -> Slot: Slot{size, 0, 8}",
          "def vt_size_at(i: U32, +size: U32) -> Slot: Slot{size, size, 8}",
          ":67's 4-byte `pack_into('i', ...)` leaves the HIGH word UNTOUCHED, not sign-extended."),
  ("M10", '    case "float": "f"\n    case "double": "d"',
          '    case "float": "f"\n    case "double": "f"',
          "dt.fmt for double -- `d` against `f`. One character, a wrong kernel."),
  ("M11", '    case "int": "i"\n    case "unsigned int": "I"',
          '    case "int": "I"\n    case "unsigned int": "I"',
          "dt.fmt for int -- SIGNED against unsigned. The classic silent one."),
  ("M12", '    case "long": 8\n    case "unsigned long": 8\n    case "double": 8',
          '    case "long": 4\n    case "unsigned long": 8\n    case "double": 8',
          "dt.itemsize for int64 -- 8 against 4."),
  ("M13", '    case "float8_e4m3": 1\n    case "float8_e4m3fnuz": 1\n    case "float8_e5m2": 1\n    case "float8_e5m2fnuz": 1\n    case "long": 8',
          '    case "long": 8',
          "the four fp8 itemsize arms -- 1 byte each, and the bug this gate found."),
  ("M14", '    case "bool": "_Bool"\n    case "half": "__fp16"\n    case "long": "long long"\n    case "unsigned long": "unsigned long long"',
          '    case "bool": "_Bool"\n    case "half": "__fp16"\n    case "long": "long"\n    case "unsigned long": "unsigned long long"',
          ":15's ADDED int64 key -- `long long` against `long`."),
  ("M15", "def dt_cname_global(+is_alu: Bool, +nm: String) -> String:\n  match is_alu:\n    case True{}: dt_cname(nm)\n    case False{}: \"int\"",
          "def dt_cname_global(+is_alu: Bool, +nm: String) -> String:\n  match is_alu:\n    case True{}: dt_cname(nm)\n    case False{}: dt_cname(nm)",
          "THE GLOBAL ARM of :32 -- a float buffer's SIZE must be spelled `int`."),
  ("M16", "def dt_supported(base: Bool, +nm: String) -> Bool:\n  Bool.and(base, Bool.and(Bool.not(dt_is_fp8(nm)), Bool.not(String.eq(nm, \"__bf16\"))))",
          "def dt_supported(base: Bool, +nm: String) -> Bool:\n  Bool.and(base, Bool.not(dt_is_fp8(nm)))",
          ":46's `not bfloat16` -- the reason supported_dtypes exists at all."),
  ("M17", "def dt_is_fp8.i(nm: String) -> Bool:\n  match nm:\n    case \"float8_e4m3\": True{}\n    case \"float8_e4m3fnuz\": True{}\n    case \"float8_e5m2\": True{}\n    case \"float8_e5m2fnuz\": True{}\n    case _: False{}",
          "def dt_is_fp8.i(nm: String) -> Bool:\n  match nm:\n    case \"float8_e4m3\": True{}\n    case _: False{}",
          ":46's `d not in dtypes.fp8s` -- three of the four fp8 arms."),
  ("M18", "def entry.dma_slot(i: U32) -> U32: U32.add(i, U32.add(prog.nins(), prog.nouts()))",
          "def entry.dma_slot(i: U32) -> U32: U32.add(i, 2)",
          ":37's `pra[i+3]` -- the two ins and one out ahead of the dma slots."),
  ("M19", "def vt_size_byte(i: U32) -> U32: U32.mul(i, 8)",
          "def vt_size_byte(i: U32) -> U32: U32.mul(i, 4)",
          ":33's `(char*)pra[0].buf.pv + i*8` -- the 8-BYTE slot stride."),
  ("M20", "    \"*)((char*)pra[0].buf.pv+\", U32.show(vt_size_byte(i)), \");\"])",
          "    \"*)((char*)pra[0].buf.pv+\", U32.show(vt_size_byte(0)), \");\"])",
          "the slot INDEX inside the sz_or_val line -- every param reading slot 0."),
  ("M21", "def alloc.offset.va(va: U32, off: U32) -> U32: U32.add(va, off)",
          "def alloc.offset.va(va: U32, off: U32) -> U32: va",
          ":96's `buf.va_addr + offset` -- the ADDRESS does not advance."),
  ("M22", "def alloc.offset.acc(offset: U32, off: U32) -> U32: U32.add(offset, off)",
          "def alloc.offset.acc(offset: U32, off: U32) -> U32: off",
          ":96's `buf.offset + offset` -- offsets ACCUMULATE. The silent one."),
  ("M23", "      DspBuf{id, alloc.offset.va(va, off), nsz, alloc.offset.acc(offset, off),\n             share_fd, share_handle, has_share}",
          "      DspBuf{id, alloc.offset.va(va, off), nsz, offset,\n             share_fd, share_handle, has_share}",
          "the same claim, at the record -- a view of a view loses its parent's offset."),
  ("M24", "      DspBuf{id, alloc.offset.va(va, off), nsz, alloc.offset.acc(offset, off),\n             share_fd, share_handle, has_share}",
          "      DspBuf{id, alloc.offset.va(va, off), size, alloc.offset.acc(offset, off),\n             share_fd, share_handle, has_share}",
          "the SECOND BUG the gate found: the pattern binder shadowing `size`."),
  ("M25", "def alloc.free_calls(has_share: Bool, +nbytes: U32, handle: U32) -> List<&2, Call>:\n  Bool.pick(List<&2, Call>, has_share,\n    [Call{CALL_MMAP, nbytes}, Call{CALL_OS_CLOSE, FD_NONE()},\n     Call{CALL_ION_FREE, handle}],\n    [Call{CALL_MMAP, nbytes}])",
          "def alloc.free_calls(has_share: Bool, +nbytes: U32, handle: U32) -> List<&2, Call>:\n  Bool.pick(List<&2, Call>, has_share,\n    [Call{CALL_ION_FREE, handle}, Call{CALL_OS_CLOSE, FD_NONE()},\n     Call{CALL_MMAP, nbytes}],\n    [Call{CALL_MMAP, nbytes}])",
          ":88-91's free ORDER -- munmap before munmap-of-the-handle."),
  ("M26", "def alloc.alloc.real.go(+nbytes: U32, +t: Tr) -> Tr:\n  Tr.emit(CALL_MMAP(), nbytes,\n    Tr.emit(CALL_ION_SHARE(), ION_FLAG_CACHED(),\n      Tr.emit(CALL_ION_ALLOC(), nbytes, t)))",
          "def alloc.alloc.real.go(+nbytes: U32, +t: Tr) -> Tr:\n  Tr.emit(CALL_ION_ALLOC(), nbytes,\n    Tr.emit(CALL_ION_SHARE(), ION_FLAG_CACHED(),\n      Tr.emit(CALL_MMAP(), nbytes, t)))",
          ":81-83's alloc ORDER -- ION_ALLOC, ION_SHARE, then the mmap."),
  ("M27", "def compiler_args_first(mock: Bool) -> String:\n  Bool.pick(String, mock, ARG_STATIC(), ARG_SHARED())",
          "def compiler_args_first(mock: Bool) -> String:\n  Bool.pick(String, mock, ARG_SHARED(), ARG_STATIC())",
          "THE THIRD BUG the gate found: :100's `-static` / `-shared` arms swapped."),
  ("M28", "def compiler.cachekey_of(+mock: Bool, +ccache: Bool) -> String:\n  Bool.pick(String, Bool.and(Bool.not(mock), ccache), CACHEKEY(), \"\")",
          "def compiler.cachekey_of(+mock: Bool, +ccache: Bool) -> String:\n  Bool.pick(String, ccache, CACHEKEY(), \"\")",
          ":113's `None if mock else \"compile_dsp\"` -- the MOCK arm."),
  ("M29", "def link_section(0n) -> String:\n  case 0n" if False else "    case 0n: \"text\"", '    case 0n: ".text"',
          ":104's first section name. A dropped dot in a section list is a link failure."),
  ("M30", "def link_line(+n: String) -> String:\n  String.concat([\".\", n, \" : ALIGN(4096) { *(.\", n, \") }\"])",
          "def link_line(+n: String) -> String:\n  String.concat([\".\", n, \" : ALIGN(8192) { *(.\", n, \") }\"])",
          ":106's ALIGN(4096) -- the NOTE at :103 says 4k is the fix."),
  ("M31", "    case n <> t: link_lines(t, String.concat([acc, \"\\n\", link_line(n)]))",
          "    case n <> t: link_lines(t, String.concat([\"\\n\", link_line(n), acc]))",
          "the prepend that REVERSES the section order. Caught twice by the same row."),
  ("M32", "def link_body() -> String: String.drop(link_lines(link_sections(), \"\"), 1n)",
          "def link_body() -> String: link_lines(link_sections(), \"\")",
          "the leading separator `str.join` would not have."),
  ("M33", "def dev.init_dsp.again(+t: Tr) -> Tr:\n  dev.init_dsp.after_stale(dev.init_dsp.stale(Tr.emit(CALL_RPC_INVOKE(), SC_STALE(), t)))",
          "def dev.init_dsp.again(+t: Tr) -> Tr:\n  dev.init_dsp.after_stale(Tr.emit(CALL_RPC_INVOKE(), SC_STALE(), dev.init_dsp.stale(t)))",
          ":169 BEFORE :170 -- the stale INVOKE precedes the close."),
  ("M34", "def dev.init_dsp(have_fd: Bool, t: Tr) -> Tr:\n  match have_fd:\n    case True{}: dev.init_dsp.again(t)\n    case False{}: dev.init_dsp.fresh(t)",
          "def dev.init_dsp(have_fd: Bool, t: Tr) -> Tr:\n  dev.init_dsp.fresh(t)",
          ":167's `if hasattr(self, 'rpc_fd')` -- the stale-fd path skipped entirely."),
  ("M35", "Tr.emit(CALL_RPC_INIT(), INIT_FLAGS(),\n      Tr.emit(CALL_RPC_CONTROL(), CONTROL_REQ(),\n        Tr.emit(CALL_RPC_GETINFO(), ARGPTR_SIZE(),\n          Tr.emit(CALL_ADSP_OPEN(), 0, t)))))",
          "Tr.emit(CALL_RPC_INIT(), INIT_FLAGS(),\n      Tr.emit(CALL_RPC_GETINFO(), ARGPTR_SIZE(),\n        Tr.emit(CALL_RPC_CONTROL(), CONTROL_REQ(),\n          Tr.emit(CALL_ADSP_OPEN(), 0, t)))))",
          ":173 before :174 -- GETINFO and CONTROL swapped."),
  ("M36", "def dev.exec_lib.retry(+sc: U32, fail_second: Bool, +t: Tr) -> Tr:\n  exec_once(sc, fail_second, dev.init_dsp(True{}, exec_once(sc, True{}, t)))",
          "def dev.exec_lib.retry(+sc: U32, fail_second: Bool, +t: Tr) -> Tr:\n  exec_once(sc, fail_second, dev.init_dsp(True{}, t))",
          ":159-164's retry -- a port that SKIPS the first attempt records ten, not eleven."),
  ("M37", "def exec_once(+sc: U32, fail: Bool, +t: Tr) -> Tr:\n  match fail:\n    case True{}: dev.open_lib(t)\n    case False{}: exec_full(sc, t)",
          "def exec_once(+sc: U32, fail: Bool, +t: Tr) -> Tr:\n  exec_full(sc, t)",
          "THE RAISE, at the device-error site: a failed ioctl records its open AND its close."),
  ("M38", "def Tr.refuse_now(+t: Tr) -> Tr:\n  match t:\n    case Tr{+calls, next, +refused}: Tr{calls, next, True{}}",
          "def Tr.refuse_now(+t: Tr) -> Tr:\n  match t:\n    case Tr{+calls, next, +refused}: Tr{calls, next, False{}}",
          "THE RAISE, at :63 -- the refusal flag itself. Dropping it lets everything after run."),
  ("M38b", "def Tr.emit.go(+refused: Bool, +calls: List<&2, Call>, +next: U32, k: U32,\n               arg: U32) -> Tr:\n  Tr{Bool.pick(List<&2, Call>, refused, calls,\n               List.append(&2, Call, calls, [Call{k, arg}])),\n     Bool.pick(U32, refused, next, U32.add(next, 1)), refused}",
          "def Tr.emit.go(+refused: Bool, +calls: List<&2, Call>, +next: U32, k: U32,\n               arg: U32) -> Tr:\n  Tr{List.append(&2, Call, calls, [Call{k, arg}]),\n     Bool.pick(U32, refused, next, U32.add(next, 1)), refused}",
          "THE RAISE inside `Tr.emit` -- the guard for a DEVICE error. See BLIND SPOT 1: it is not reachable yet."),
  ("M39", "def open_lib_bad(status: U32) -> Bool: U32.is_eq(U32.shrn(status, 31n), 1)",
          "def open_lib_bad(status: U32) -> Bool: U32.is_lt(status, 100)",
          ":147's SIGNED 32-bit test -- the port that reached for an unsigned compare."),
  ("M40", "def RPC_GREET() -> U32: 67240448",
          "def RPC_GREET() -> U32: rpc_sc(M_INVOKE(), 2, 2, 0)",
          "THE greeting LITERAL. Rewriting it as an rpc_sc call sends method 2 and the DSP never greets."),
  ("M41", "    case 199229440: ARM_OPEN()", "    case 199229448: ARM_OPEN()",
          "the elif chain's sc table -- one digit off in the OPEN arm."),
  ("M42", "def rpc.arm_ids.at(n: Nat) -> U32:\n  match n:\n    case 0n: ARM_HELLO()\n    case 1n: ARM_OPEN()",
          "def rpc.arm_ids.at(n: Nat) -> U32:\n  match n:\n    case 0n: ARM_OPEN()\n    case 1n: ARM_HELLO()",
          "the chain's ORDER -- greeting first, open second."),
  ("M43", "def rpc.nin.arm(a: U32) -> U32:\n  match a:\n    case 2: 4",
          "def rpc.nin.arm(a: U32) -> U32:\n  match a:\n    case 2: 1",
          ":215's `in_args[3]` -- the name is the FOURTH in-arg of the open arm."),
  ("M44", "def rpc.obj_pad(off: U32) -> U32: U32.sub(RPC_OBJ_ALIGN(), U32.mod(off, RPC_OBJ_ALIGN()))",
          "def rpc.obj_pad(off: U32) -> U32: U32.sub(RPC_OBJ_ALIGN(), U32.mod(off, 4))",
          ":201's `round_up(ptr+4, 8)` -- the alignment is 8, not 4."),
  ("M45", "def rpc.seek_ok(whence: U32) -> Bool: U32.is_eq(whence, APPS_STD_SEEK_SET())",
          "def rpc.seek_ok(whence: U32) -> Bool: True{}",
          ":221's SEEK_SET assert -- the only assert in the file."),
  ("M46", "def mrender.nbytes(+p: Param) -> U32: U32.mul(Param.numel(p), dt_itemsize(Param.cn(p)))",
          "def mrender.nbytes(+p: Param) -> U32: U32.add(Param.numel(p), dt_itemsize(Param.cn(p)))",
          ":262's `max_numel()*itemsize` -- multiply, not add."),
  ("M47", "def mrender.val(+i: U32, +p: Param) -> String:\n  String.concat([dt_cname(Param.cn(p)), \" val\", U32.show(i), \"; read(0, &val\",\n    U32.show(i), \", \", U32.show(dt_itemsize(Param.cn(p))), \");\"])",
          "def mrender.val(+i: U32, +p: Param) -> String:\n  String.concat([dt_cname_global(Param.is_alu(p), Param.cn(p)), \" val\", U32.show(i), \"; read(0, &val\",\n    U32.show(i), \", \", U32.show(dt_itemsize(Param.cn(p))), \");\"])",
          ":266's `_render_dtype` -- the ALU arm of the GLOBAL helper would be right by luck here and wrong for a GLOBAL."),
  ("M48", "def mrender.arg_name(+i: U32, +p: Param) -> String:\n  Bool.pick(String, Param.is_alu(p), String.concat([\"val\", U32.show(i)]),\n    String.concat([\"(void*)buf\", U32.show(i)]))",
          "def mrender.arg_name(+i: U32, +p: Param) -> String:\n  Bool.pick(String, Param.is_alu(p), String.concat([\"buf\", U32.show(i)]),\n    String.concat([\"(void*)buf\", U32.show(i)]))",
          ":268's `val{i}` for an ALU -- the mock's bare-value spelling."),
  ("M49", "def prog.scale_micros() -> U32: 1000000", "def prog.scale_micros() -> U32: 1000000000",
          ":71's /1e6 against :292's /1e9 -- two programs, two scales."),
  ("M50", "def mprog.scale_ins() -> U32: 1000000000", "def mprog.scale_ins() -> U32: 1000000",
          "the same pair, the other way."),
  ("M51", "def SYSCALL_READ() -> U32: 63", "def SYSCALL_READ() -> U32: 62",
          "the gpages syscall table at :257 -- read is 63."),
  ("M52", "def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>,\n              +at: Nat) -> Bool:\n  match n:\n    case 0n: Nat.is_eq(at, patlen)",
          "def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>,\n              +at: Nat) -> Bool:\n  match n:\n    case 0n: True{}",
          "THE MATCHER, with the ops_webgpu M23 bug: the fuel is the TRACE length but the answer ignores `at`."),
  ("M53", "def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>,\n              +at: Nat) -> Bool:\n  match n:\n    case 0n: Nat.is_eq(at, patlen)",
          "def Tr.has.go(n: Nat, +patlen: Nat, cs: List<&2, Call>, +pat: List<&2, Call>,\n              +at: Nat) -> Bool:\n  match n:\n    case 0n: Nat.is_eq(at, patlen)\n    case 1n+p: True{}",
          "the matcher with the PATTERN length as fuel -- the other half of M23."),
  ("M54", "def entry.count_sz.of(+ps: List<&2, Param>, got: U32) -> U32:\n  match ps:\n    case Nil{}: got\n    case _ <> t: entry.count_sz.of(t, U32.add(got, 1))",
          "def entry.count_sz.of(+ps: List<&2, Param>, got: U32) -> U32:\n  match ps:\n    case Nil{}: got\n    case p <> t: entry.count_sz.of(t, U32.add(got, Bool.to_u32(Param.is_alu(p))))",
          ":32 emits one sz_or_val PER PARAM, ALU or not -- not per ALU."),
  ("M55", "def entry.count_off(ps: List<&2, Param>) -> U32: entry.count_go(False{}, ps, 0)",
          "def entry.count_off(ps: List<&2, Param>) -> U32: entry.count_go(True{}, ps, 0)",
          ":35 and :37 filter on `!= AddrSpace.GLOBAL`, so the count is the GLOBAL one."),
  ("M56", "def ENTRY_TAIL() -> U32: 4", "def ENTRY_TAIL() -> U32: 3",
          "the tail's four lines -- the LINE COUNT is the only row that sees a dropped one."),
  ("M57", "def pra_len(nins: U32, nouts: U32, nfds: U32) -> U32:\n  U32.add(U32.add(nins, nouts), nfds)",
          "def pra_len(nins: U32, nouts: U32, nfds: U32) -> U32:\n  U32.add(nins, nouts)",
          ":52's one array of len(ins)+len(outs)+len(in_fds) -- the fd slots count too."),
  ("M58", "def FD_NONE() -> U32: 4294967295", "def FD_NONE() -> U32: 0",
          ":53's `-1` marker."),
  ("M59", "def dev.shell_spec() -> D.Bspec: D.Bspec{False{}, False{}, False{}, True{}, False{}}",
          "def dev.shell_spec() -> D.Bspec: D.Bspec{False{}, False{}, False{}, False{}, False{}}",
          ":135's `BufferSpec(nolru=True)` -- THE EVICTION NEGATIVE CASE. Dropping it makes the shell recyclable."),
  ("M60", "def dev.shell_size(nbytes: U32) -> U32: H.round_up_u32(nbytes, SHELL_ALIGN())",
          "def dev.shell_size(nbytes: U32) -> U32: nbytes",
          ":135's `round_up(nbytes, 0x1000)` -- the shell buffer's alignment."),
  ("M61", "def alloc.copyin_bytes(src_bytes: U32) -> U32: src_bytes", "def alloc.copyin_bytes(src_bytes: U32) -> U32: 0",
          ":94's `src.nbytes` going in -- a view's window, not its buffer."),
  ("M62", "def dev.is_mock() -> Bool: True{}", "def dev.is_mock() -> Bool: False{}",
          ":129's ONE branch, which selects four things at once."),
  ("M63", "def INSN_CNT_WORD() -> U32: 1784217600", "def INSN_CNT_WORD() -> U32: 1784217601",
          ":257's `.word 0x6a15c000` -- the inscount instruction word."),
  ("M64", "def CFOP_DSP() -> U32: 17", "def CFOP_DSP() -> U32: 18",
          ":16's `code_for_op = {k:v for ... if k != Ops.SQRT}` -- ONE entry removed."),
  ("M65", "def rpc.reply_sc_index() -> U32: 2", "def rpc.reply_sc_index() -> U32: 1",
          ":197's `sc = msg_recv[2]` -- the selector is the reply's THIRD word."),
  ("M66", "def rpc.msg_status_index() -> U32: 1", "def rpc.msg_status_index() -> U32: 0",
          ":192's `[context, status, ...]` -- status is the SECOND word."),
  # --- THE CONTROL: a comment-only edit must move nothing.
  ("M99", "# :63 `if len(bufs) >= 16: raise RuntimeError(f\"Too many buffers to execute:\n# {len(bufs)}\")`. `prog.too_many` is the whole of it; `prog.call`'s `Tr.refuse_now`\n# is what turns it into a trace that records NOTHING.",
          "# :63 refuses at sixteen buffers. prog.too_many is the whole of it, and\n# prog.call's Tr.refuse_now is what turns it into a trace that records NOTHING.",
          "THE CONTROL: a comment-only edit. A table with no row that CANNOT move is a table of coincidences."),
]


def run(path):
  r = subprocess.run([BEND, path], capture_output=True, text=True, timeout=900)
  if r.returncode != 0:
    return None
  # the FULL `name=value` text, not the name: a mutation that changes a VALUE moves
  # a row without changing its name, and a name-only diff would call every one of
  # these zero.
  return [ln for ln in r.stdout.split("\n") if "=" in ln]


def main():
  base = run(SRC)
  if base is None:
    print("BASELINE FAILED TO RUN"); sys.exit(1)
  base_set = set(base)
  print(f"baseline: {len(base)} rows\n")
  print("| # | rows moved | what it is testing |")
  print("| --- | --- | --- |")
  for mid, old, new, why in MUTATIONS:
    s = open(SRC).read()
    if old not in s:
      print(PNA.pipe([mid, PNA.not_applied(), why], 3))
      continue
    p = os.path.join(WORK, f"_dspmut_{mid}.bend")
    open(p, "w").write(s.replace(old, new, 1))
    got = run(p)
    if got is None:
      print(PNA.pipe([mid, "DID-NOT-COMPILE", why], 3))
      continue
    gs = set(got)
    moved = sorted({k.split("=", 1)[0] for k in got if k not in base_set}
                   | {k.split("=", 1)[0] for k in base_set if k not in gs})
    print(f"| {mid} | {len(moved)} | {why} |")
    if moved and len(moved) <= 16:
      print(f"| | | moved: {', '.join(moved)} |")
  for f in os.listdir(WORK):
    if f.startswith("_dspmut_"): os.remove(os.path.join(WORK, f))


if __name__ == "__main__":
  main()
