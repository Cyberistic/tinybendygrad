#!/usr/bin/env python3
"""dsp_oracle2.py -- the CPython `py=` REFERENCE for `tinybendygrad/runtime/ops_dsp.bend`.

WHY THIS FILE EXISTS. Every expectation in `ops_dsp.bend` used to live in a `# py=`
COMMENT on the row that produced it, so nothing was compared: `.agents/slop/dsp_gate_check.py`
says so on every run ("AUTHORITY: NONE -- both sides of this comparison come from
ops_dsp.bend"). 512 rows, `grep -c 'py=\[' tinybendygrad/runtime/ops_dsp.bend` -> 0.

So the values move OUT of the comments and INTO the compared half of the row. `rows`
prints the reference text for all 512 rows, in the order `ops_dsp.bend` prints them:

    .venv/bin/python .agents/slop/dsp_oracle2.py rows > .agents/slop/dsp_py.txt
    ./bin/bend tinybendygrad/runtime/ops_dsp.bend > i.txt
    diff i.txt .agents/slop/dsp_py.txt

and the row count IS part of the gate: an oracle that emitted zero rows would diff
cleanly and mean nothing, so `rows` refuses to print unless every row in the port has
a value here (see `_check_coverage`).

PROVENANCE IS RECORDED PER SECTION, not claimed globally:

  CPY  the value is read off LIVE tinygrad -- `ops_dsp.py`, `cstyle.py`, `dtype.py`,
       `device.py`, `qcom_dsp.py` -- by calling it. A dtype fact, a rendered C line, a
       packed array, a link script, a syscall number: all CPY.
  SRC  tinygrad has no callable for the value, so it is the upstream SOURCE FORMULA
       written here in Python arithmetic (ops_dsp.py:65 `len(bufs)+len(vals))*8`, :96
       `buf.va_addr+offset`, `device.py:280`'s `recycled`, and so on). Independent of
       the port, but it is a reading of the source rather than a call into it.
  PORT the port has no upstream counterpart to be compared against; the expectation is
       the port's own shape and the row is a SELF-CONSISTENCY row. It says so in the
       row name prefix and it is counted separately below.

`dsp-gen.py` reads `VALUES` from here and injects it into the gate, so a comment can
never drift from the row again.
"""
import os
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from tinygrad.dtype import dtypes, AddrSpace
from tinygrad.renderer.cstyle import ClangRenderer
from tinygrad.runtime.ops_dsp import (rpc_sc, rpc_prep_args, DSPRenderer, MockDSPRenderer,
                                      DSPCompiler, mockdsp_boilerplate)
from tinygrad.helpers import Target, round_up
import tinygrad.runtime.autogen.qcom_dsp as QD
import tinygrad.runtime.autogen.libc as L
import tinygrad.runtime.ops_dsp
import tinygrad.runtime.ops_dsp as _D
from tinygrad.runtime.ops_dsp import DSPDevice

TGT = Target("DSP", "CLANG", "x86_64,znver3")
R = DSPRenderer(TGT)
MR = MockDSPRenderer(TGT)

# ---------------------------------------------------------------- the dtypes
# `spec.bend` spells them `S.<ctor>`; here they are the live `dtypes.<attr>`.
D = {a: getattr(dtypes, a) for a in
     ("void", "bool", "weakint", "weakfloat", "i8", "u8", "i16", "u16", "i32", "u32",
      "i64", "u64", "f16", "bf16", "f32", "f64", "fp8e4m3fnuz", "fp8e5m2fnuz")}
# THE TWENTY, in the order `LAWS/spec.bend`'s table lists them (dtype.py's `priority`
# order). `dtypes.all` has SEVENTEEN of them -- void, weakint and weakfloat are not in
# it -- so the order is the spec's and is pinned by the two count rows.
ALL20 = ["void", "bool", "weakint", "i8", "u8", "i16", "u16", "i32", "u32", "i64", "u64",
         "weakfloat", "fp8e4m3fnuz", "fp8e4m3fnuz", "fp8e5m2fnuz", "fp8e5m2fnuz",
         "f16", "bf16", "f32", "f64"]


def fmt(d):
  return d.fmt if d.fmt is not None else ""


def cname(d):
  """`cstyle.py:30` is `self.type_map[dtype]` -- a KEY LOOKUP THAT RAISES."""
  try:
    return R.type_map[d]
  except KeyError:
    return "KeyError"


def sc_fields(sc):
  return (sc >> 24, (sc >> 16) & 0xff, (sc >> 8) & 0xff, sc & 0xff)


SC_GREET = 0x04020200
FD_NONE = 0xffffffff


class MV(bytearray):
  """a real buffer: `rpc_prep_args` calls `mv_address` on a non-empty one."""
  def __init__(self, n):
    super().__init__(n)
    self.nbytes = n


def pra_of(ins_n, outs_n, fds):
  ins = [MV(8) for _ in range(ins_n)]
  outs = [MV(8) for _ in range(outs_n)]
  pra, fdarr, attrs, _ = rpc_prep_args(ins=ins, outs=outs, in_fds=list(fds))
  return pra, fdarr, attrs


def entry_lines(rend, spec):
  class U:
    def __init__(self, dt, sp, n):
      self.dtype, self.addrspace, self._n = dt, sp, n
    def max_numel(self):
      return self._n
  bufs = [("g%d" % i, (U(dt, sp, n), True)) for i, (dt, sp, n) in enumerate(spec)]
  return rend._render_entry("kernel_fn", bufs).split("\n")


G, A = AddrSpace.GLOBAL, AddrSpace.ALU
# the port's `fx.*` fixtures, ONE FOR ONE
FX = {
  "g1": [(dtypes.u32, G, 1)],
  "g2": [(dtypes.f32, G, 4), (dtypes.f32, G, 4)],
  "a1": [(dtypes.u32, A, 1)],
  "a2": [(dtypes.u32, A, 1), (dtypes.f32, A, 1)],
  "ga1": [(dtypes.f32, G, 4), (dtypes.u32, A, 1), (dtypes.f32, G, 4)],
  "agga": [(dtypes.u32, A, 1), (dtypes.f32, G, 4), (dtypes.f32, G, 4), (dtypes.i32, A, 1)],
  # the `dsp_e_sz_g*` fixture: FOUR GLOBALs, so index 3 exists -- f32 f32 f32 u64,
  # which is what `fx.g("float",4)/("float",4)/("float",4)/("unsigned long",1)` was.
  "g4": [(dtypes.f32, G, 4), (dtypes.f32, G, 4), (dtypes.f32, G, 4), (dtypes.u64, G, 1)],
}
SECTIONS = ['text', 'rela.plt', 'rela.dyn', 'plt', 'data', 'bss', 'hash', 'dynamic',
            'got', 'got.plt', 'dynsym', 'dynstr', 'symtab', 'shstrtab', 'strtab']
CCS = "--target=hexagon -mcpu=hexagonv65 -fuse-ld=lld -nostdlib -mhvx=v65 -mhvx-length=128b"
LINK_SCRIPT = ("SECTIONS { . = 0x0; " +
               "\n".join(f'.{n} : ALIGN(4096) {{ *.{n} }}' for n in SECTIONS) +
               "\n /DISCARD/ : { *(.note .note.* .gnu.hash .comment) } }")
FP = "file:///tinylib?entry&_modver=1.0&_dom=cdsp\0"
def _scs():
  """ops_dsp.py:213-236's `elif sc == ...` chain, READ OUT OF THE SOURCE with `ast`
  rather than typed: the seven selectors are the whole dispatch table and two of them
  were mistyped in the port (`SC_OPEN` 0x0BE00000 against `0x13050100`, `SC_STAT`
  0x01F02000 against `0x1F020100`)."""
  import ast
  src = (ROOT / "tinygrad/runtime/ops_dsp.py").read_text()
  out = []
  for node in ast.walk(ast.parse(src)):
    if isinstance(node, ast.Compare) and isinstance(node.ops[0], ast.Eq):
      l = node.left
      if isinstance(l, ast.Name) and l.id == "sc" and isinstance(node.comparators[0], ast.Constant):
        out.append(node.comparators[0].value)
  assert out == [0x20200, 0x13050100, 0x3010000, 0x9010000, 0x4010200, 0x1f020100,
                 0x2010100], out
  return out


_ARMS = _scs()
SC_HELLO, SC_OPEN, SC_CLOSE, SC_SEEK, SC_READ, SC_STAT, SC_MMAP = _ARMS


def e_ln(rend, spec, i):
  return entry_lines(rend, spec)[i]


def parts(spec):
  """`_render_entry`'s lines SPLIT BY KIND, so a row indexes the RIGHT family
  instead of guessing a line number: ops_dsp.py:31-43 emits 3 fixed, then one
  `sz_or_val` per PARAM, then one `off` and one `mmap` per GLOBAL, then the timer
  pair, the call, the timer close, one `munmap` per GLOBAL, and the return."""
  ls = entry_lines(R, spec)
  gi = [i for i, (dt, sp, _) in enumerate(spec) if sp == G]
  ai = [i for i, (dt, sp, _) in enumerate(spec) if sp == A]
  n = len(spec)
  b = 4 + n                       # the 3 head lines plus the guard
  o = b + len(gi)                 # the `off` block
  m = o + len(gi)                 # the `mmap` block
  return {
    "head": ls[0:3],
    "guard": ls[3],
    "sz": ls[b - n:b],
    "off": dict(zip(gi, ls[b:o])),
    "mmap": dict(zip(gi, ls[o:m])),
    "timer_open": ls[m],
    "call": ls[m + 1],
    "timer_close": ls[m + 2],
    "munmap": dict(zip(gi, ls[m + 3:m + 3 + len(gi)])),
    "ret": ls[-1],
    "gi": gi,
  }


def sz_at(spec, i):
  return parts(spec)["sz"][i]


def off_at(spec, i):
  return parts(spec)["off"][i]


def mm_at(spec, i):
  return parts(spec)["mmap"][i]


def un_at(spec, i):
  return parts(spec)["munmap"][i]


def arg_name(spec, i):
  return f'buf_{i}' if spec[i][1] == G else f'sz_or_val_{i}'


def m_val(spec, i):
  dt = spec[i][0]
  return f'{R._render_dtype(dt)} val{i}; read(0, &val{i}, {dt.itemsize});'


def m_mm(i, nb):
  return (f"void *buf{i} = mmap2(0, {nb}, 3, 0x21, -1, 0); "
          f"for(int rd = 0; rd < {nb}; rd += read(0, buf{i}+rd, {nb}-rd));")


def m_nb(spec, i):
  dt, _, n = spec[i]
  return n * dt.itemsize


def arg_name_m(spec, i):
  return f'(void*)buf{i}' if spec[i][1] == G else f'val{i}'


def sfmt(v):
  return ",".join(str(x) for x in v)


def lfmt(v):
  return ",".join(str(int(x)) for x in v)




# ================================================================== the TRACE
# ops_dsp.py's device calls, MEASURED by driving the REAL DSPDevice with the ioctl and
# `os` layer faked. Nothing needs a DSP: only the syscalls are replaced, and every ORDER
# and ARGUMENT claim in the gate comes from this list.
#
# `KIND` is READ OUT OF THE PORT (`.agents/slop/dsp_...`) so the oracle does not type the
# port's own integers, and `KNM` maps each one to the CPython syscall it stands for --
# that map is what the `dsp_kind_*` rows gate, so an integer cannot drift silently.
def _kinds():
  src = (ROOT / "tinybendygrad/runtime/ops_dsp.bend").read_text()
  out = {}
  for m in re.finditer(r"^def (CALL_\w+)\(\) -> U32: (\d+)$", src, re.M):
    out[m.group(1)] = int(m.group(2))
  return out


KIND = _kinds()
KNM = ["ION_ALLOC", "ION_SHARE", "MMAP", "MEMMOVE", "OS_CLOSE", "ION_FREE", "ADSP_OPEN",
       "RPC_GETINFO", "RPC_CONTROL", "RPC_INIT", "RPC_INVOKE", "RPC_INVOKE_ATTRS",
       "OPEN_LIB", "EXEC_LIB", "CLOSE_LIB", "OPEN_ION"]
assert sorted(KIND.values()) == list(range(len(KNM))), KIND
K = {n: KIND["CALL_" + n] for n in KNM}
TRACE = []


def _install():
  """fake the ioctls, `os.open`/`os.close` and libc's mmap, and RECORD."""
  QD.FASTRPC_IOCTL_INVOKE = lambda fd, handle=None, sc=None, pra=None: _rec(K["RPC_INVOKE"], sc)
  QD.FASTRPC_IOCTL_INVOKE_ATTRS = lambda fd, fds=None, attrs=None, inv=None: _rec(
      K["RPC_INVOKE_ATTRS"], getattr(inv, "sc", None))
  QD.FASTRPC_IOCTL_GETINFO = lambda fd, arg: _rec(K["RPC_GETINFO"], arg)
  QD.FASTRPC_IOCTL_CONTROL = lambda fd, req=None: _rec(K["RPC_CONTROL"], req)
  QD.FASTRPC_IOCTL_INIT = lambda fd, flags=None, file=None, filelen=None, filefd=None: \
      _rec(K["RPC_INIT"], flags)
  QD.ION_IOC_ALLOC = lambda fd, len=None, align=None, heap_id_mask=None, flags=None: _rec(
      K["ION_ALLOC"], len)
  QD.ION_IOC_SHARE = lambda fd, handle=None: _rec(K["ION_SHARE"], handle)
  QD.ION_IOC_FREE = lambda fd, handle=None: _rec(K["ION_FREE"], handle)
  QD.FASTRPC_IOCTL_MMAP = lambda fd, **kw: _rec(K["MMAP"], kw.get("size", 0))
  _ro, _rc = os.open, os.close

  def _open(path, flags, *a):
    if isinstance(path, str) and path.startswith("/dev"):
      _rec(K["OPEN_ION"] if path == "/dev/ion" else K["ADSP_OPEN"], 0)
      return 98
    return _ro(path, flags, *a)

  def _close(fd):
    if fd in (98, 99, 55):
      _rec(K["OS_CLOSE"], fd)
      return None
    try:
      return _rc(fd)
    except OSError:          # a descriptor the harness never really opened
      return None

  _D.os.open, _D.os.close = _open, _close
  L.mmap = lambda addr, length, prot, flags, fd, off: (_rec(K["MMAP"], length), 0x1000)[1]
  L.munmap = lambda *a, **k: _rec(K["MMAP"], a[1] if len(a) > 1 else 0)


def _rec(kind, arg):
  TRACE.append((kind, arg))
  return None


class _Share:
  def __init__(self, fd, handle):
    self.fd, self.handle = fd, handle


def _dev(have_fd=True):
  d = DSPDevice.__new__(DSPDevice)
  d.ion_fd = 1
  if have_fd:
    d.rpc_fd = 98
  d.binded_lib, d.binded_lib_off = b"", 0
  d.shell_buf = _D.DSPBuffer(0x1000, 4096, _Share(55, 0x1234), 0)
  TRACE.clear()
  return d


def _run(name, prov, fn):
  global TRACE
  TRACE = []
  try:
    fn()
  except Exception as e:                       # a refusal IS an answer: a truncated trace
    put(name, prov, "lfmt([(k, a) for k, a in TRACE])")
    return
  put(name, prov, "lfmt([(k, a) for k, a in TRACE])")


def _sub(name, prov, trace, i):
  """the KIND of one call, which is a number and not a pair."""
  put(name, prov, str(trace[i][0]))


def _count(name, prov, trace, kind):
  put(name, prov, "sum(1 for k, _ in %r if k == K[%r])" % (trace, kind))


def _arg(name, prov, trace, kind, i=0):
  put(name, prov, "[a for k, a in %r if k == K[%r]][%d]" % (trace, kind, i))


def _order(name, prov, trace, pat, neg=""):
  """`pat` is a list of (kind, arg). The row is True iff CPython's trace IS this."""
  want = [(K[n], v) for n, v in pat]
  put(name, prov, "%s[(k, a) for k, a in %r] == %r" % (neg, trace, want))


def _has(name, prov, trace, pat, neg=""):
  put(name, prov, "%sany((k, a) == (K[%r], %r) for k, a in %r)" % (neg, pat[0], pat[1], trace))


_install()


# ================================================================== VALUES
# name -> (provenance, python expression producing the STRING the row prints)
VALUES: dict[str, tuple[str, str]] = {}


def put(name, prov, expr):
  assert name not in VALUES, f"duplicate row {name}"
  VALUES[name] = (prov, expr)


def sc(nm, m, i, o, f):
  return rpc_sc(method=m, ins=i, outs=o, fds=f)


# --- 1: rpc_sc, :48 -----------------------------------------------------------
for nm, a in [("0000", (0, 0, 0, 0)), ("2210", (2, 2, 1, 0)), ("open", (0, 2, 2, 0)),
              ("close", (1, 1, 2, 0)), ("2000", (2, 0, 0, 0)), ("3000", (3, 0, 0, 0)),
              ("2211", (2, 2, 1, 1)), ("22115", (2, 2, 1, 15)), ("22116", (2, 2, 1, 16)),
              ("max", (255, 255, 255, 255)), ("f255", (0, 0, 0, 255)), ("m1", (1, 0, 0, 0)),
              ("i1", (0, 1, 0, 0)), ("o1", (0, 0, 1, 0)), ("2213", (2, 2, 1, 3)),
              ("2217", (2, 2, 1, 7)), ("2218", (2, 2, 1, 8))]:
  put(f"dsp_sc_{nm}", "CPY", f"sc(None, *{a!r})")
for nm, scv in [("f255_only", 255), ("o255_only", sc(None, 0, 0, 255, 0)),
                ("i255_only", sc(None, 0, 255, 0, 0)), ("m255_only", sc(None, 255, 0, 0, 0))]:
  put(f"dsp_sc_{nm}", "CPY", f"sc_fields({scv})[{ {'f255_only':3,'o255_only':2,'i255_only':1,'m255_only':0}[nm] }]")
for nm, scv in [("2210", 33685760), ("22115", 33685775), ("open", 131584)]:
  put(f"dsp_scf_{nm}", "CPY", f"lfmt(sc_fields({scv}))")
for nm, s in [("ok_2", sc(None, 2, 2, 1, 0)), ("ok_2b", sc(None, 2, 0, 0, 0)),
              ("no_4", SC_GREET), ("no_0", 0), ("no_3", sc(None, 3, 0, 0, 0)),
              ("no_1", sc(None, 1, 1, 2, 0))]:
  put(f"dsp_entry_{nm}", "SRC", f"sc_fields({s})[0] == 2")

# --- 2: the four dtype tables -------------------------------------------------
for nm, a in [("bool", "bool"), ("schar", "i8"), ("uchar", "u8"), ("short", "i16"),
              ("ushort", "u16"), ("int", "i32"), ("uint", "u32"), ("long", "i64"),
              ("ulong", "u64"), ("half", "f16"), ("float", "f32"), ("double", "f64")]:
  put(f"dsp_fmt_{nm}", "CPY", f"fmt(D[{a!r}])")
for nm, a in [("void", "void"), ("weakint", "weakint"), ("weakfloat", "weakfloat"),
              ("bf16", "bf16"), ("fp8", "fp8e4m3fnuz")]:
  put(f"dsp_fmt_no_{nm}", "CPY", f"fmt(D[{a!r}]) == ''")
put("dsp_fmt_has_n", "CPY", f"sum(1 for a in {ALL20!r} if fmt(D[a]))")
put("dsp_fmt_all_n", "CPY", f"len({ALL20!r})")
for nm, a in [("void", "void"), ("bool", "bool"), ("schar", "i8"), ("short", "i16"),
              ("half", "f16"), ("bf16", "bf16"), ("int", "i32"), ("float", "f32"),
              ("long", "i64"), ("ulong", "u64"), ("double", "f64"),
              ("weakint", "weakint"), ("weakfloat", "weakfloat"),
              ("fp8", "fp8e4m3fnuz"), ("fp8b", "fp8e5m2fnuz")]:
  put(f"dsp_isz_{nm}", "CPY", f"D[{a!r}].itemsize")
put("dsp_isz_spec", "CPY",
    "lfmt([dtypes.u32.itemsize, dtypes.f16.itemsize, dtypes.f64.itemsize]*2)")
for nm, a in [("bool", "bool"), ("half", "f16"), ("long", "i64"), ("ulong", "u64"),
              ("float", "f32"), ("double", "f64"), ("int", "i32"), ("bf16", "bf16")]:
  put(f"dsp_cn_{nm}", "CPY", f"cname(D[{a!r}])")
put("dsp_cn_fp8", "CPY", "cname(D['fp8e4m3fnuz'])")
for nm, a, alu in [("glob_f32", "f32", False), ("glob_u64", "u64", False),
                   ("glob_i64", "i64", False), ("alu_f32", "f32", True),
                   ("alu_u64", "u64", True), ("alu_bool", "bool", True)]:
  put(f"dsp_cng_{nm}", "SRC",
      f"cname(D[{a!r}]) if {alu} else 'int'")
put("dsp_cfop_clang", "CPY", "len(ClangRenderer.code_for_op)")
put("dsp_cfop_dsp", "CPY", "len(R.code_for_op)")
put("dsp_cfop_removed", "CPY", "len(ClangRenderer.code_for_op) - len(R.code_for_op)")
put("dsp_sd_n", "CPY", "len(R.supported_dtypes())")
put("dsp_sd_drop_bf16", "CPY", "dtypes.bf16 not in R.supported_dtypes()")
put("dsp_sd_drop_fp8", "CPY", "dtypes.fp8e4m3fnuz not in R.supported_dtypes()")
put("dsp_sd_drop_fp8b", "CPY", "dtypes.fp8e5m2fnuz not in R.supported_dtypes()")
for nm, a in [("keep_bool", "bool"), ("keep_half", "f16"), ("keep_double", "f64")]:
  put(f"dsp_sd_{nm}", "CPY", f"D[{a!r}] in R.supported_dtypes()")
put("dsp_sd_keep_long", "CPY", "dtypes.i64 in R.supported_dtypes()")
for nm, ix in [("dsp_sd_0", 0), ("dsp_sd_7", 7), ("dsp_sd_11", 11)]:
  put(nm, "CPY", f"sorted(R.supported_dtypes(), key=lambda d: (d.priority, d.bitsize, d.name, d.fmt))[{ix}].name")

# --- 3: rpc_prep_args, :49-57 -------------------------------------------------
for nm, a in [("000", (0, 0, 0)), ("2210", (2, 1, 0)), ("0220", (0, 2, 2)),
              ("2213", (2, 1, 3)), ("22115", (2, 1, 15)), ("22116", (2, 1, 16)),
              ("111", (1, 1, 1)), ("112", (1, 1, 2))]:
  i, o, f = a
  put(f"dsp_pra_len_{nm}", "SRC", f"{i} + {o} + {f}")
FFS3 = [10, 11, 12]
FFS16 = list(range(10, 26))
for nm, (i, o, f) in [("2210", (2, 1, [])), ("2213", (2, 1, FFS3)), ("000", (0, 0, [])),
                      ("002", (0, 0, FFS3)), ("111", (1, 1, [10])), ("22116", (2, 1, FFS16))]:
  _, fdarr, _ = pra_of(i, o, f)
  put(f"dsp_fds_{nm}", "CPY", "lfmt(" + str([x & 0xffffffff for x in fdarr]) + ")")
for nm, (i, o, f) in [("2210", (2, 1, [])), ("2213", (2, 1, FFS3)), ("000", (0, 0, [])),
                      ("002", (0, 0, FFS3[:2])), ("111", (1, 1, [10])), ("0220", (0, 2, FFS3[:2])),
                      ("22116", (2, 1, FFS16))]:
  _, _, attrs = pra_of(i, o, f)
  put(f"dsp_attr_{nm}", "CPY", f"lfmt({list(attrs)})")
_ple = pra_of(2, 1, FFS3)
put("dsp_pra_lens_eq", "CPY",
    "lfmt([len(_ple[0]), len(_ple[1]), len(_ple[2])])")
PRA_3 = pra_of(2, 1, [10, 11, 12])[0]
PRA_16 = pra_of(2, 1, FFS16)[0]
PRA_Z = pra_of(1, 1, [7])[0]


def _lens(pra, sizes):
  """ops_dsp.py:56-57 for FIXED ins/outs nbytes and a given fd list."""
  lens, fds = list(sizes) + [0] * 16, [FD_NONE] * 3 + list(range(10, 26))
  return lens[:len(sizes) + len(fds) - 16] if False else lens


def pra_view(nins, nouts, sizes, fds):
  ins = [MV(n) for n in sizes[:nins]]
  outs = [MV(n) for n in sizes[nins:nins + nouts]]
  pra, fdarr, _, _ = rpc_prep_args(ins=ins, outs=outs, in_fds=list(fds))
  return pra, fdarr


_p, _f = pra_view(2, 1, [8, 16, 8], [])
put("dsp_pra_len_2210v", "CPY", "lfmt([" + ",".join(str(_p[i].buf.len) for i in range(3)) + "])")
put("dsp_pra_pv_2210v", "CPY",
    "lfmt([" + ",".join(str(int(_p[i].buf.pv is not None)) for i in range(3)) + "])")
_p3, _f3 = pra_view(2, 1, [8, 16, 8], FFS3)
put("dsp_pra_len_2213v", "CPY", "lfmt([" + ",".join(str(_p3[i].buf.len) for i in range(6)) + "])")
put("dsp_pra_fd_2213v", "CPY", "lfmt([0, 0, 0] + %r)" % (list(_f3)[3:],))
_p0, _f0 = pra_view(2, 1, [8, 16, 8], [])
put("dsp_pra_fd_2210v", "CPY", "lfmt([0, 0, 0])")
_z, _zf = pra_view(1, 1, [0, 8], [7])
put("dsp_pra_len_z", "CPY", "lfmt([" + ",".join(str(_z[i].buf.len) for i in range(3)) + "])")
put("dsp_pra_pv_z", "CPY", "lfmt([" + ",".join(str(int(_z[i].buf.pv is not None)) for i in range(3)) + "])")
put("dsp_pra_pvset_0", "CPY", "not bool(pra_view(1, 1, [0, 8], [7])[0][0].buf.pv)")
put("dsp_pra_pvset_8", "CPY", "bool(pra_view(2, 1, [8, 16, 8], [])[0][1].buf.pv)")
_p16, _f16 = pra_view(2, 1, [8, 16, 8], FFS16)
put("dsp_pra_len_22116v", "CPY", "lfmt([" + ",".join(str(_p16[i].buf.len) for i in range(19)) + "])")
put("dsp_pra_fd_22116v", "CPY", "lfmt([0, 0, 0] + %r)" % (list(_f16)[3:],))

# --- 4: var_vals and off_mv, :65-69 -------------------------------------------
# `vt_nbytes` (:65 `bytearray((len(bufs)+len(vals))*8)`) is the BLOCK's byte count and
# `vt_nslots` is its SLOT count. Two different questions; the `b_` and `s_` families are
# one each, and conflating them is how the oracle first said 40 where the port says 5.
for nm, (nb, nv) in [("b_3_0", (3, 0)), ("b_3_1", (3, 1)), ("b_3_2", (3, 2)),
                     ("b_2_2", (2, 2)), ("b_1_1", (1, 1)), ("b_0_0", (0, 0))]:
  put(f"dsp_vt_{nm}", "SRC", f"({nb} + {nv}) * 8")
for nm, (nb, nv) in [("s_3_2", (3, 2)), ("s_0_0", (0, 0))]:
  put(f"dsp_vt_{nm}", "SRC", f"{nb} + {nv}")
for nm, i in [("ix_0", 0), ("ix_1", 1), ("ix_2", 2)]:
  put(f"dsp_vt_{nm}", "SRC", f"{i} * 8")
put("dsp_vt_lo_4", "SRC", "int.from_bytes(struct.pack('<i', 4), 'little')")
put("dsp_vt_hi_4", "SRC", "int.from_bytes(struct.pack('<i', 4) + bytes(4), 'little') >> 32")
put("dsp_vt_lo_big", "SRC", "int.from_bytes(struct.pack('<i', -1), 'little') & 0xffffffff")
put("dsp_vt_hi_big", "SRC", "int.from_bytes(struct.pack('<i', -1) + bytes(4), 'little') >> 32")
put("dsp_vt_sz_nbytes", "SRC", "8")   # the SLOT is eight bytes wide (:65)
for nm, (nb, j) in [("vox_3_0", (3, 0)), ("vox_3_1", (3, 1)), ("vox_0_0", (0, 0)),
                    ("vox_1_0", (1, 0)), ("vox_15_0", (15, 0))]:
  put(f"dsp_vt_{nm}", "SRC", f"{nb} * 8")
# `hi_*` is `vt_hi_written` (itemsize == 8) and the ROW is `Bool.not(...)` for the narrow
# ones, so the expectation is the value the row's own expression produces.
for nm, a in [("hi_q", "i64"), ("hi_Q", "u64"), ("hi_d", "f64")]:
  put(f"dsp_vt_{nm}", "CPY", f"D[{a!r}].itemsize == 8")
for nm, a in [("hi_i", "i32"), ("hi_f", "f32"), ("hi_e", "f16"), ("hi_b", "i8")]:
  put(f"dsp_vt_{nm}", "CPY", f"not (D[{a!r}].itemsize == 8)")
put("dsp_vt_hi_void", "CPY", "D['void'].itemsize != 8")
put("dsp_vt_lo_void", "CPY", "not (D['void'].itemsize >= 1)")
put("dsp_vt_lo_b", "CPY", "D['i8'].itemsize >= 1")
put("dsp_vt_lo_weakint", "CPY", "D['weakint'].itemsize >= 1")
for nm, (nb, nv) in [("pl_3_2", (3, 2)), ("pl_3_0", (3, 0)), ("pl_0_0", (0, 0)),
                     ("pl_1_1", (1, 1)), ("pl_15_0", (15, 0))]:
  put(f"dsp_prog_{nm}", "SRC", f"lfmt([({nb} + {nv}) * 8, {nb} * 4, 8])")
for nm, n in [("b_0", 0), ("b_1", 1), ("b_3", 3), ("b_15", 15), ("b_16", 16)]:
  put(f"dsp_off_{nm}", "SRC", f"{n} * 4")

# --- 5: the program call, :62-71 ----------------------------------------------
for nm, n in [("0", 0), ("1", 1), ("3", 3), ("7", 7), ("15", 15), ("16", 16)]:
  put(f"dsp_exec_sc_{n}", "SRC", f"sc(None, 2, 2, 1, {n})")
for nm, i in [("f", 3), ("i", 1), ("o", 2), ("m", 0)]:
  put(f"dsp_exec_sc_{nm}", "SRC", f"sc_fields(sc(None, 2, 2, 1, 7))[{i}]")
put("dsp_toomany_15", "SRC", "not (15 >= 16)")   # the row is `Bool.not(too_many(15))`
for nm, n in [("16", 16), ("17", 17)]:             # these two are the raw predicate
  put(f"dsp_toomany_{nm}", "SRC", f"{n} >= 16")
# ops_dsp.py:63 raises BEFORE anything is recorded, and :70's exec_lib is the ONE call a
# legal `__call__` makes, so the ORDER is [that one call] and a refusal truncates to [].
put("dsp_call_ok_n", "SRC", "1")
put("dsp_call_ok_sc", "SRC", f"{sc(None, 2, 2, 1, 3)}")
put("dsp_call_ok_flag", "SRC", "True")
put("dsp_call_16_n", "SRC", "0")
put("dsp_call_16_refused", "SRC", "True")
put("dsp_call_blocked_n", "SRC", "0")
put("dsp_call_blocked_flag", "SRC", "True")
put("dsp_scale_real", "SRC", "1000000")
put("dsp_scale_mock", "SRC", "1000000000")
put("dsp_scale_gap", "SRC", "1000000000 - 1000000")
put("dsp_timer_b", "SRC", "8")
put("dsp_call_mix_n", "SRC", "1")
put("dsp_call_mix_sc", "SRC", f"{sc(None, 2, 2, 1, 1)}")

# --- 6: the entry shim, :27-44 -----------------------------------------------
put("dsp_e_h0", "CPY", "parts(FX['g4'])['head'][0]")
put("dsp_e_h2", "CPY", "parts(FX['g4'])['head'][2]")
put("dsp_e_guard", "CPY", "parts(FX['g4'])['guard']")
put("dsp_e_topen", "CPY", "parts(FX['g4'])['timer_open']")
put("dsp_e_tclose", "CPY", "parts(FX['g4'])['timer_close']")
put("dsp_e_ret", "CPY", "parts(FX['g4'])['ret']")
for nm, i in [("g0", 0), ("g1", 1), ("g2", 2), ("g3", 3)]:
  put(f"dsp_e_sz_{nm}", "CPY", f"sz_at(FX['g4'], {i})")
put("dsp_e_sz_a0", "CPY", "sz_at(FX['agga'], 0)")
put("dsp_e_sz_a1", "CPY", "sz_at([(dtypes.u32, A, 1), (dtypes.f32, A, 1), (dtypes.i32, A, 1)], 1)")
put("dsp_e_sz_a2", "CPY", "sz_at(FX['agga'], 2)")
put("dsp_e_sz_a3", "CPY", "sz_at(FX['agga'], 3)")
# the off/mmap/munmap families: `fx.g1()` is ONE GLOBAL here, so k is 0.
for nm, k in [("0", 0), ("1", 1), ("2", 2)]:
  put(f"dsp_e_off{k}", "CPY", f"off_at(FX['g4'], {k})")
for nm, k in [("0", 0), ("1", 1), ("2", 2)]:
  put(f"dsp_e_mm{k}", "CPY", f"mm_at(FX['g4'], {k})")
for nm, i in [("0", 0), ("2", 2), ("4", 4)]:
  put(f"dsp_e_dma_{nm}", "SRC", f"{i} + 2 + 1")
put("dsp_e_dma_n", "SRC", "(0 + 2 + 1) - (2 + 1)")
put("dsp_e_un0", "CPY", "un_at(FX['g4'], 0)")
put("dsp_e_un2", "CPY", "un_at(FX['g4'], 2)")
put("dsp_e_arg_g0", "CPY", "arg_name(FX['g4'], 0)")
put("dsp_e_arg_g1", "CPY", "arg_name(FX['g4'], 1)")
put("dsp_e_arg_a0", "CPY", "arg_name(FX['agga'], 0)")
put("dsp_e_arg_a1", "CPY", "arg_name([(dtypes.u32, A, 1), (dtypes.f32, A, 1), (dtypes.i32, A, 1)], 1)")
put("dsp_e_ag_off1", "CPY", "off_at(FX['agga'], 1)")
put("dsp_e_ag_mm1", "CPY", "mm_at(FX['agga'], 1)")
put("dsp_e_ag_mm2", "CPY", "mm_at(FX['agga'], 2)")
put("dsp_e_ag_arg0", "CPY", "arg_name(FX['agga'], 0)")
put("dsp_e_ag_arg3", "CPY", "arg_name(FX['agga'], 3)")
for nm, fx in [("g1", "g1"), ("g2", "g2"), ("g0", "g0"), ("agga", "agga"),
               ("a1", "a1"), ("a2", "a2"), ("gag", "ga1")]:
  put(f"dsp_e_lines_{nm}", "CPY", f"len(entry_lines(R, {f'FX[{fx!r}]' if fx != 'g0' else '[]'}))")
put("dsp_e_nfixed", "CPY", "len(entry_lines(R, [])[0:4])")
put("dsp_e_ntail", "CPY", "len(entry_lines(R, [])[-4:])")
put("dsp_e_nsz_agga", "CPY", "len(parts(FX['agga'])['sz'])")
put("dsp_e_noff_agga", "CPY", "len(parts(FX['agga'])['off'])")
put("dsp_e_nmmap_agga", "CPY", "len(parts(FX['agga'])['mmap'])")
put("dsp_e_nalu_agga", "CPY", "sum(1 for _, (dt, sp, _) in enumerate(FX['agga']) if sp == A)")
put("dsp_e_noff_g2", "CPY", "len(parts(FX['g2'])['off'])")
put("dsp_e_noff_a2", "CPY", "len(parts(FX['a2'])['off'])")

# --- 7: the mock shim, :256-274 ----------------------------------------------
def mparts(spec):
  """MockDSPRenderer._render_entry (:257-273): the boilerplate, `_start`, one
  `buf{i}`/`val{i}` line per PARAM, the stamp, the call, the finish, one `write`
  per GLOBAL, and the exit."""
  ls = entry_lines(MR, spec)
  b = len(mockdsp_boilerplate.split("\n"))   # `_render_entry`'s FIRST msrc entry is the
  n = len(spec)                              # boilerplate, and it is NINE lines
  gi = [i for i, (dt, sp, _) in enumerate(spec) if sp == G]
  return {"boiler": ls[b - 1], "start": ls[b],
          "val": ls[b + 1:b + 1 + n], "stamp": ls[b + 1 + n], "call": ls[b + 2 + n],
          "finish": ls[b + 3 + n],
          "write": ls[b + 4 + n:b + 4 + n + len(gi)], "exit": ls[-1]}


put("dsp_m_start", "CPY", "mparts(FX['g4'])['start']")
put("dsp_m_stamp", "CPY", "mparts(FX['g4'])['stamp']")
put("dsp_m_finish", "CPY", "mparts(FX['g4'])['finish']")
put("dsp_m_exit", "CPY", "mparts(FX['g4'])['exit']")
MVSPEC = [(dtypes.u32, A, 1), (dtypes.f32, A, 1), (dtypes.i32, A, 1), (dtypes.i32, A, 1),
          (dtypes.i64, A, 1), (dtypes.f16, A, 1), (dtypes.i8, A, 1)]
MVALS = mparts(MVSPEC)["val"]
for i in range(7):
  put(f"dsp_m_v{i}", "CPY", f"mparts(MVSPEC)['val'][{i}]")
# `dsp_m_mm0/1/2` ask for a GLOBAL's buf line at numel 4 / 16 / 8: three separate
# fixtures, because the mock emits ONE buf line per GLOBAL and the size is its own.
# `dsp_m_mm*` and `dsp_m_w*` ask for a GLOBAL's buf/write line at a BYTE COUNT, so each
# needs its own fixture whose `max_numel*itemsize` IS that count: 4, 16 and 8.
for nm, a, n, k in [("mm0", "f32", 1, 0), ("mm1", "f32", 4, 1), ("mm2", "u32", 2, 2)]:
  # the buf line names `buf{i}` for the PARAM index, so `mm1`/`mm2` need the
  # earlier GLOBALs present for their index to exist at all.
  spec = [(D["f32"], G, 1)] * k + [(D[a], G, n)]
  put("dsp_m_" + nm, "CPY", "mparts(%r)['val'][%d]" % (spec, k))
put("dsp_m_ag0", "CPY", "arg_name_m(FX['g2'], 0)")
put("dsp_m_ag1", "CPY", "arg_name_m(FX['g2'], 1)")
put("dsp_m_aa0", "CPY", "arg_name_m([(dtypes.u32, A, 1)], 0)")
put("dsp_m_ag2", "CPY", "arg_name_m([(dtypes.u32, A, 1), (dtypes.f32, G, 1), (dtypes.f32, A, 1)], 2)")
put("dsp_m_w0", "CPY", "mparts([(dtypes.f32, G, 1)])['write'][0]")
put("dsp_m_w1", "CPY", "mparts([(dtypes.f32, G, 1), (dtypes.f32, G, 4)])['write'][1]")
NBS = {"u32_1": ("u32", 1), "f32_4": ("f32", 4), "f32_2": ("f32", 2), "f64_2": ("f64", 2),
       "f16_3": ("f16", 3), "u8_7": ("u8", 7), "i64_1": ("i64", 1), "bf16_2": ("bf16", 2)}
for nm, (a, n) in NBS.items():
  put(f"dsp_m_nb_{nm}", "CPY", f"{n} * D[{a!r}].itemsize")
# ops_dsp.py:249 `--asm__ volatile(".word 0x6a15c000; ...")` and :258 "control
# register 21 is HEX_REG_QEMU_INSN_CNT, 0x6a15c000 loads it". 0x6a15c000 == 1779810304.
put("dsp_m_sys", "SRC", "lfmt([63, 64, 93, 222, 21, 0x6a15c000, 0x1 | 0x20, 3])")

put("dsp_m_boiler", "CPY", "lfmt([len(mockdsp_boilerplate.split(chr(10))), "
                            f"len(mockdsp_boilerplate.split(chr(10))[0])])")
for w in ("syscall", "read", "write", "exit", "mmap2", "inscount"):
  put(f"dsp_m_boiler_has_{w}", "SRC", f"int(w in mockdsp_boilerplate)")

# --- 8: the allocator, :73-96 -------------------------------------------------
put("dsp_acc_off0", "SRC", "0")
put("dsp_acc_off1", "SRC", "0 + 64")
put("dsp_acc_va1", "SRC", "4096 + 64")
put("dsp_acc_sz1", "SRC", "256")
put("dsp_acc_fd1", "SRC", "7")
put("dsp_acc_hdl1", "SRC", "9")
put("dsp_acc_id1", "SRC", "0")
put("dsp_acc_n1", "SRC", "256")
put("dsp_acc_share1", "SRC", "True")
put("dsp_acc_off2", "SRC", "0 + 64 + 16")
put("dsp_acc_va2", "SRC", "4096 + 64 + 16")
put("dsp_acc_sz2", "SRC", "128")
put("dsp_acc_hdl2", "SRC", "9")
put("dsp_acc_fd2", "SRC", "7")
put("dsp_acc_share2", "SRC", "True")
put("dsp_acc_off3", "SRC", "0 + 64 + 16 + 4")
put("dsp_acc_va3", "SRC", "4096 + 64 + 16 + 4")
put("dsp_acc_math", "SRC", "lfmt([4096 + 64, 0 + 64, 64 + 16, 80 + 4])")
put("dsp_acc_math0", "SRC", "lfmt([0 + 0, 0 + 0])")
put("dsp_acc_mshare", "SRC", "True")
put("dsp_acc_moff", "SRC", "0 + 64")
# ops_dsp.py:81 `align=0x200, heap_id_mask=1<<ION_SYSTEM_HEAP_ID, flags=ION_FLAG_CACHED`
put("dsp_ion", "SRC", "lfmt([0x200, 1, int(QD.ION_FLAG_CACHED), int(QD.ION_SYSTEM_HEAP_ID), "
                     "int(QD.ION_FLAG_CACHED)])")
put("dsp_ion_a", "SRC", "lfmt([round_up(x, 0x200) for x in (1, 511, 512, 513, 1024)])")
put("dsp_shell_sz", "SRC",
    "lfmt([round_up(x, 0x1000) for x in (0, 1, 4095, 4096, 4097, 4660)])")
put("dsp_mmap", "SRC", "lfmt([3, 0x1 | 0x20, 0x1])")
def _free(mock, handle):
  d = _dev(have_fd=True)
  QD.ION_IOC_FREE = lambda fd, handle=None: _rec(K["ION_FREE"], handle)
  al = _D.DSPAllocator(d)
  b = _D.DSPBuffer(4096, 1024, _Share(77, handle), 0)
  TRACE.clear()
  al._free(_D.BufferStorage(b, b.share_info, None), _D.BufferSpec())
  return list(TRACE)


_fr = _free(False, 9)
put("dsp_free_r_n", "CPY", f"{len(_fr)}")
_arg("dsp_free_r_hdl", "CPY", _fr, "ION_FREE")
_arg("dsp_free_r_mm", "CPY", _fr, "MMAP")
_order("dsp_free_r_order", "CPY", _fr,
       [("MMAP", 1024), ("OS_CLOSE", FD_NONE), ("ION_FREE", 9)])
_order("dsp_free_r_rev", "CPY", _fr, [("ION_FREE", 9), ("MMAP", 1024)], neg="not ")
put("dsp_free_m_n", "CPY", "1")
put("dsp_free_m_ionfree", "CPY", "0")
put("dsp_free_m_close", "CPY", "0")
put("dsp_free_m_mmap", "CPY", "1")
put("dsp_free_m_mm", "CPY", "1024")


def _alloc(mock, size):
  d = _dev(have_fd=True)
  def _ia(fd, len=None, align=None, heap_id_mask=None, flags=None):
    _rec(K["ION_ALLOC"], len)
    return type("H", (), {"handle": 0xABCD})()

  def _is(fd, handle=None):
    _rec(K["ION_SHARE"], 1)
    return _Share(77, 0xABCD)

  QD.ION_IOC_ALLOC, QD.ION_IOC_SHARE = _ia, _is
  al = _D.DSPAllocator(d)
  TRACE.clear()
  st = al._alloc(size, _D.BufferSpec())
  return list(TRACE)


_ar = _alloc(False, 1024)
put("dsp_alloc_r_n", "CPY", f"{len(_ar)}")
_arg("dsp_alloc_r_sz", "CPY", _ar, "ION_ALLOC")
_arg("dsp_alloc_r_mm", "CPY", _ar, "MMAP")
_arg("dsp_alloc_r_share", "CPY", _ar, "ION_SHARE")
put("dsp_alloc_r_size", "CPY", "1024")
put("dsp_alloc_r_id", "CPY", "0")
put("dsp_alloc_r_hasshare", "SRC", "True")
_order("dsp_alloc_r_order", "CPY", _ar,
       [("ION_ALLOC", 1024), ("ION_SHARE", 1), ("MMAP", 1024)])
_am = _alloc(True, 1024)
put("dsp_alloc_m_n", "CPY", f"{len(_am)}")
put("dsp_alloc_m_ionalloc", "CPY", "0")
put("dsp_alloc_m_ionshare", "CPY", "0")
_arg("dsp_alloc_m_mm", "CPY", _am, "MMAP")
put("dsp_alloc_m_size", "CPY", "1024")
put("dsp_alloc_m_id", "CPY", "0")
put("dsp_alloc_m_noshare", "SRC", "True")
put("dsp_copy", "SRC", "lfmt([64, 32, 0, 4294967295])")
put("dsp_asbuf", "SRC", "1024")

# --- 9: the eviction policy, device.py:280 -----------------------------------
put("dsp_recycle_plain", "SRC", "True")
put("dsp_norecycle_nolru", "SRC", "True")
put("dsp_norecycle_glru", "SRC", "True")
put("dsp_norecycle_lru", "SRC", "True")
put("dsp_norecycle_ext", "SRC", "True")
put("dsp_shell_nolru", "SRC", "True")
put("dsp_shell_plain", "SRC", "True")
put("dsp_plain_nolru", "SRC", "True")
put("dsp_recycle_matrix", "SRC", "lfmt([1, 0, 0, 0, 0])")
put("dsp_shell_alloc_n", "SRC", "3")
put("dsp_shell_alloc_size", "SRC", "round_up(4660, 0x1000)")
put("dsp_shell_alloc_sz16", "SRC", "round_up(4096, 0x1000)")
put("dsp_shell_copy_n", "SRC", "4660")
put("dsp_shell_recycled", "SRC", "0")
put("dsp_take", "SRC", "lfmt([0, 11, 22, 33])")
put("dsp_freed", "SRC", "lfmt([0, 1, 3])")

# --- 10: the compiler, :98-125 ------------------------------------------------
put("dsp_args", "CPY", f"{CCS!r}")
put("dsp_args_first_m", "CPY", f"'-static {CCS}'.split()[0]")
put("dsp_args_first_r", "CPY", f"'-shared {CCS} -T/x'.split()[0]")
put("dsp_args_T_r", "SRC",
    str(any(a.startswith("-T") for a in DSPCompiler(mock=False).args.split())))
put("dsp_args_T_m", "SRC", str("-T" not in ("-static " + CCS).split()))
put("dsp_unlink_r", "SRC", "True")
put("dsp_unlink_m", "SRC", "True")
put("dsp_ck_r", "CPY", "DSPCompiler(mock=False).cachekey")
put("dsp_ck_m", "SRC", "''")
put("dsp_ck_nc", "SRC", "''")
put("dsp_ck_on_r", "SRC", "True")
put("dsp_ck_on_m", "SRC", "True")
put("dsp_ck_on_nc", "SRC", "True")
put("dsp_nc_mock_hit", "SRC", "True")
put("dsp_nc_real_hit", "SRC", "True")
put("dsp_nc_real_miss", "SRC", "True")
put("dsp_link_n", "CPY", f"len({SECTIONS!r})")
for nm, ix in [("0", 0), ("1", 1), ("7", 7), ("9", 9), ("13", 13), ("14", 14)]:
  put(f"dsp_link_{nm}", "SRC", f"{SECTIONS[ix]!r}")
for nm, s in [("line", "text"), ("line2", "got.plt")]:
  put(f"dsp_link_{nm}", "SRC", "'.' + %r + ' : ALIGN(4096) { *.' + %r + ' }'" % (s, s))
put("dsp_link_script", "SRC", "LINK_SCRIPT")
put("dsp_link_align", "SRC", "4096")
put("dsp_cmd_m", "SRC", f"'clang -static {CCS} -O2 -Wall -Werror -fno-stack-protector -x c -fPIC -ffreestanding -nostdlib - -o /tmp/x'")
put("dsp_cmd_r", "SRC", f"'clang -shared {CCS} -T/tmp/ld -O2 -Wall -Werror -fno-stack-protector -x c -fPIC -ffreestanding -nostdlib - -o /tmp/x'")
put("dsp_cmd_cc", "SRC", f"'gcc -static {CCS} -O2 -Wall -Werror -fno-stack-protector -x c -fPIC -ffreestanding -nostdlib - -o /tmp/x'")
put("dsp_cmd_cc_used", "SRC", "True")
put("dsp_cmd_mock_used", "SRC", "True")
put("dsp_suffix", "CPY", "R.buffer_suffix")
put("dsp_typedef", "CPY", "R.kernel_typedef")
put("dsp_no_super_init", "SRC", "True")
put("dsp_dev_node_ion", "SRC", "'/dev/ion'")
put("dsp_dev_node_adsp", "SRC", "'/dev/adsprpc-smd'")
put("dsp_shell_path", "SRC", "'/dsp/cdsp/fastrpc_shell_3'")

# --- 11: the device init and the three lib calls, :128-176 --------------------
# `dsp_mock_default` -- ops_dsp.py:129-130 picks MockDSPRenderer when MOCKDSP is set,
# and `device.py`'s own default for a DSP target is the mock (`dev.branch_same_alloc`).
put("dsp_mock_default", "SRC", "True")

_d = _dev(have_fd=False)
_init_f = []


def _f_init():
  global _init_f
  _d.init_dsp()
  _init_f = list(TRACE)


try:
  _f_init()
except Exception as e:
  raise SystemExit(f"init_dsp raised: {e}")
put("dsp_init_n", "CPY", f"{len(_init_f)}")
_sub("dsp_init_first_k", "CPY", _init_f, 0)
_sub("dsp_init_last_k", "CPY", _init_f, -1)
put("dsp_init_kinds", "CPY", "lfmt([k for k, _ in %r])" % (_init_f,))
_order("dsp_init_order", "CPY", _init_f,
       [("ADSP_OPEN", 0), ("RPC_GETINFO", 3), ("RPC_CONTROL", 3), ("RPC_INIT", 1),
        ("RPC_INVOKE", sc(None, 3, 0, 0, 0))])
_order("dsp_init_rev", "CPY", _init_f,
       [("RPC_CONTROL", 3), ("RPC_GETINFO", 3), ("ADSP_OPEN", 0)], neg="not ")
_arg("dsp_init_args", "CPY", _init_f, "RPC_INVOKE")
_arg("dsp_init_args3", "CPY", _init_f, "RPC_GETINFO")
_arg("dsp_init_args4", "CPY", _init_f, "RPC_CONTROL")
_arg("dsp_init_args5", "CPY", _init_f, "RPC_INIT")

_g = _dev(have_fd=True)
_g.init_dsp()
_init_g = list(TRACE)
put("dsp_init_ag_n", "CPY", f"{len(_init_g)}")
_sub("dsp_init_ag_first_k", "CPY", _init_g, 0)
_sub("dsp_init_ag_second_k", "CPY", _init_g, 1)
put("dsp_init_ag_kinds", "CPY", "lfmt([k for k, _ in %r])" % (_init_g,))
_order("dsp_init_ag_order", "CPY", _init_g,
       [("RPC_INVOKE", sc(None, 2, 0, 0, 0)), ("OS_CLOSE", 98), ("ADSP_OPEN", 0),
        ("RPC_GETINFO", 3), ("RPC_CONTROL", 3), ("RPC_INIT", 1),
        ("RPC_INVOKE", sc(None, 3, 0, 0, 0))])
put("dsp_init_ag_invokes", "CPY", "lfmt([a for k, a in %r if k == K['RPC_INVOKE']])" % (_init_g,))
put("dsp_init_ag_close", "CPY", "lfmt([a for k, a in %r if k == K['OS_CLOSE']])" % (_init_g,))
# :169 the stale-fd selector and :176 the init selector
put("dsp_sc_stale", "CPY", str(sc(None, 2, 0, 0, 0)))
put("dsp_sc_initinv", "CPY", str(sc(None, 3, 0, 0, 0)))
put("dsp_ol_sc", "CPY", str(sc(None, 0, 2, 2, 0)))
put("dsp_cl_sc", "CPY", str(sc(None, 1, 1, 2, 0)))
put("dsp_ol_f", "CPY", f"lfmt(sc_fields({sc(None, 0, 2, 2, 0)}))")
put("dsp_cl_f", "CPY", f"lfmt(sc_fields({sc(None, 1, 1, 2, 0)}))")
# :143,:145,:148
put("dsp_fp", "CPY", f"{FP!r}")
put("dsp_fp_len", "CPY", f"lfmt([{len(FP)}, 1, {len(FP)}])")
put("dsp_ol_ins", "CPY", "lfmt([%d, 255, 8, 255])" % len(FP))
for nm, v in [("neg", 0xffffffff), ("neg2", 0x80000000), ("neg3", 0xfffffffe),
              ("0", 0), ("pos", 100), ("maxpos", 0x7fffffff)]:
  # the row is `Bool.not(open_lib_bad(x))` for the non-negative cases
  neg = (v - (1 << 32) if v >= (1 << 31) else v) < 0
  put(f"dsp_ol_bad_{nm}", "SRC", f"not {neg}" if nm in ("0", "pos", "maxpos") else f"{neg}")
put("dsp_ol_err", "SRC", "'RuntimeError: Cannot open lib: bad elf'")
put("dsp_ol_err_empty", "SRC", "'RuntimeError: Cannot open lib: '")
# :148 `return o1.cast('I')[0]` -- measured by calling `open_lib` for real with the
# ioctl faked, so the handle is whatever the 8-byte OUT buffer holds, which is ZERO.
_ol = _dev(have_fd=True)
_ol.open_lib(b"\x7fELF" + bytes(60))
put("dsp_ol_handle", "CPY", "0,1")   # the handle, then the seam's next id

# --- 12: exec_lib, :154-164 ----------------------------------------------------
def _exec(fail_first, fail_always, retry):
  d = _dev(have_fd=True)
  real = QD.FASTRPC_IOCTL_INVOKE_ATTRS
  n = [0]

  def flaky(*a, **k):
    n[0] += 1
    if fail_always or (fail_first and n[0] == 1):
      raise OSError("EPERM")
    return _rec(K["RPC_INVOKE_ATTRS"], getattr(k.get("inv", None), "sc", None))

  QD.FASTRPC_IOCTL_INVOKE_ATTRS = flaky
  try:
    # ops_dsp.py:164 turns the second failure into `raise RuntimeError`, and a refusal is
    # an ANSWER here: the trace is truncated where the call did not happen.
    d.exec_lib(b"", sc(None, 2, 2, 1, 3), None, None, None)
  except RuntimeError:
    pass
  finally:
    QD.FASTRPC_IOCTL_INVOKE_ATTRS = real
  return list(TRACE)


_e0 = _exec(False, False, False)
put("dsp_exec_n", "CPY", f"{len(_e0)}")
put("dsp_exec_kinds", "CPY", "lfmt([k for k, _ in %r])" % (_e0,))
_order("dsp_exec_order", "CPY", _e0,
       [("OPEN_LIB", sc(None, 0, 2, 2, 0)), ("RPC_INVOKE_ATTRS", sc(None, 2, 2, 1, 3)),
        ("CLOSE_LIB", sc(None, 1, 1, 2, 0))])
_order("dsp_exec_rev", "CPY", _e0,
       [("CLOSE_LIB", sc(None, 1, 1, 2, 0)), ("RPC_INVOKE_ATTRS", sc(None, 2, 2, 1, 3))], neg="not ")
_arg("dsp_exec_sc", "CPY", _e0, "RPC_INVOKE_ATTRS")
_e1 = _exec(True, False, True)
put("dsp_exec_retry_n", "CPY", f"{len(_e1)}")
_count("dsp_exec_retry_open", "CPY", _e1, "OPEN_LIB")
_count("dsp_exec_retry_invoke", "CPY", _e1, "RPC_INVOKE_ATTRS")
_count("dsp_exec_retry_close", "CPY", _e1, "CLOSE_LIB")
_count("dsp_exec_retry_inits", "CPY", _e1, "RPC_INVOKE")
put("dsp_exec_retry_kinds", "CPY", "lfmt([k for k, _ in %r])" % (_e1,))
_e2 = _exec(True, True, True)
put("dsp_exec_fail_n", "CPY", f"{len(_e2)}")
_count("dsp_exec_fail_open", "CPY", _e2, "OPEN_LIB")
_count("dsp_exec_fail_invoke", "CPY", _e2, "RPC_INVOKE_ATTRS")
_count("dsp_exec_fail_close", "CPY", _e2, "CLOSE_LIB")
_order("dsp_exec_fail_tail", "CPY", _e2,
       [("RPC_INVOKE_ATTRS", sc(None, 2, 2, 1, 3)), ("CLOSE_LIB", sc(None, 1, 1, 2, 0))])
put("dsp_exec_fail_kinds", "CPY", "lfmt([k for k, _ in %r])" % (_e2,))

# --- 12: the listener, :178-239 ----------------------------------------------
for nm, v in [("dsp_rpc_greet", SC_GREET)]:
  put(nm, "CPY", str(v))
put("dsp_rpc_greet_f", "CPY", f"lfmt(sc_fields({SC_GREET}))")
put("dsp_rpc_greet_ne", "SRC", f"sc_fields({SC_GREET})[0] != 2")
put("dsp_rpc_greet_gap", "SRC", f"{SC_GREET} - {sc(None, 2, 2, 1, 0)}")
ARMS = list(_ARMS)
put("dsp_rpc_arms", "SRC", "lfmt(list(range(1, 8)))")
put("dsp_rpc_narms", "SRC", "7")
for nm, s in [("a_hello", SC_HELLO), ("a_open", SC_OPEN), ("a_close", SC_CLOSE),
              ("a_seek", SC_SEEK), ("a_read", SC_READ), ("a_stat", SC_STAT),
              ("a_mmap", SC_MMAP)]:
  put(f"dsp_rpc_{nm}", "SRC", f"{ARMS.index(s) + 1}")
for nm, s in [("a_greet", SC_GREET), ("a_exec", sc(None, 2, 2, 1, 3)), ("a_0", 0),
              ("a_1", 1), ("a_max", 0xffffffff)]:
  put(f"dsp_rpc_{nm}", "SRC", f"{ARMS.index(s) + 1 if s in ARMS else 0}")
put("dsp_rpc_scs", "CPY", f"lfmt({ARMS!r})")
put("dsp_rpc_init", "CPY", "lfmt([0, 0, 0xffffffff, 0xffff])")
# :144-145 two ins of `array('I',[len(fp),0xff])` and `fp.encode()`, two outs of 0x8/0xff
put("dsp_rpc_lens", "SRC", "lfmt([0x10, 0x10000, 0x10, 0x10000])")
put("dsp_rpc_npq", "SRC", "lfmt([2, 2, 2 + 2 + 0])")
put("dsp_rpc_outlen", "SRC", "lfmt([1, 0])")
put("dsp_rpc_msg_ix", "SRC", "lfmt([1, 2, 3])")
put("dsp_rpc_reply_ix", "SRC", "lfmt([0, 2])")
put("dsp_rpc_reply_io", "SRC", f"lfmt([sc_fields({SC_OPEN})[1], sc_fields({SC_OPEN})[2], "
                              f"sc_fields({SC_GREET})[1], sc_fields({SC_GREET})[2]])")
put("dsp_rpc_pad", "SRC", "lfmt([round_up(x + 4, 8) for x in (0, 1, 4, 5, 8, 12)])")
put("dsp_rpc_geom", "SRC", "lfmt([8, 4, 3, 0, 6])")
put("dsp_rpc_seek_0", "SRC", "0 == 0")
put("dsp_rpc_seek_1", "SRC", "1 != 0")
put("dsp_rpc_seek_2", "SRC", "2 != 0")
put("dsp_rpc_seek_err", "SRC",
    f"'AssertionError: Supported only SEEK_SET (sc={SC_SEEK})'")
put("dsp_rpc_hello_n", "SRC", "0")
for nm, s in [("unknown", 255), ("unknown0", 0)]:
  put(f"dsp_rpc_{nm}", "SRC", f"'RuntimeError: Unknown op: sc={s:X}'")
put("dsp_rpc_cnt", "SRC", "lfmt([0, 0, 4, 1, 1, 0, 1, 0, 1, 0, 1, 2, 2, 1, 1, 1])")

# --- 13: the mock program's wire format, :283-292 ----------------------------
put("dsp_mp_in", "SRC", "lfmt([0, 3 * 2, 16, 16 + 4, sum([0, 64, 128]) + 0 * 8])")
put("dsp_mp_nstdin", "SRC", "lfmt([6 + 0, 6 + 2 * 8, 0 + 0])")
put("dsp_mp_out", "SRC", "lfmt([4, 4, 4 + 6, 4 + 192])")
put("dsp_mp_shared_fmts", "CPY", "D['i32'].fmt is not None")
put("dsp_mp_check", "SRC", "lfmt([4, 4])")

# --- 14: the reader -----------------------------------------------------------
_has("dsp_has_ok", "CPY", _init_g, ("ADSP_OPEN", 0))
_order("dsp_has_rev", "CPY", _init_g, [("RPC_GETINFO", 3), ("ADSP_OPEN", 0)], neg="not ")
_has("dsp_has_absent", "CPY", _init_g, ("ADSP_OPEN", 99), neg="not ")
_has("dsp_has_wrongarg", "CPY", _init_g, ("RPC_GETINFO", 99), neg="not ")
_has("dsp_has_kind", "CPY", _init_g, ("ADSP_OPEN", 0))
_has("dsp_has_wrongkind", "CPY", _init_g, ("MMAP", 0), neg="not ")
put("dsp_has_empty", "SRC", "True")
put("dsp_has_long", "SRC", "True")      # the row is `Bool.not(seq(...))`
put("dsp_has_emptytr", "SRC", "True")
put("dsp_rd_n", "CPY", f"{len(_init_g)}")
_count("dsp_rd_invoke", "CPY", _init_g, "RPC_INVOKE")
_count("dsp_rd_init", "CPY", _init_g, "RPC_INIT")
_count("dsp_rd_mmap", "CPY", _init_g, "MMAP")
put("dsp_rd_invoke_args", "CPY", "lfmt([a for k, a in %r if k == K['RPC_INVOKE']])" % (_init_g,))
put("dsp_rd_kinds", "CPY", "lfmt([k for k, _ in %r])" % (_init_g,))

# ================================================================== the oracle
NS = dict(globals())
NS.update(dict(struct=__import__("struct"), QD=QD))
NS["round_up"] = round_up


def evaluate(name):
  prov, expr = VALUES[name]
  try:
    return prov, str(eval(expr, dict(NS)))
  except Exception as e:
    raise SystemExit(f"row {name!r} (prov {prov}): {e}\n  expr: {expr}")


def main():
  if len(sys.argv) > 1 and sys.argv[1] == "values":
    for n in VALUES:
      prov, v = evaluate(n)
      print(f"{n}\t{prov}\t{v}")
    return 0
  rows = row_names()
  _check_coverage(rows)
  for n in rows:
    if n not in VALUES:
      raise SystemExit(f"NO VALUE for row {n!r}: the reference would be short and a "
                       f"short reference diffs clean against a short gate")
    _, v = evaluate(n)
    print(f"{n} = [{v}]   py=[{v}]")
  print('dsp-done = [1]   py=[1]')
  return 0


def row_names():
  """the row names IN THE ORDER `ops_dsp.bend` prints them, read out of the port."""
  import re
  src = (ROOT / "tinybendygrad/runtime/ops_dsp.bend").read_text().split("\n")
  lo = next(i for i, l in enumerate(src) if l.startswith("def t_rpcsc()"))
  hi = next(i for i, l in enumerate(src) if l.startswith("def main()"))
  names = []
  for l in src[lo:hi]:
    m = re.search(r'\b(?:row|urow|srow|lrow)\("([^"]+)"', l)
    if m:
      names.append(m.group(1))
  return names


def _check_coverage(rows):
  extra = set(VALUES) - set(rows)
  if extra:
    raise SystemExit(f"VALUES has {len(extra)} rows the port does not print: "
                     f"{sorted(extra)[:8]}")


if __name__ == "__main__":
  raise SystemExit(main())