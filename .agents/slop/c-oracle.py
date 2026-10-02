#!/usr/bin/env python3
"""c-oracle.py -- the CPython oracle for `tinybendygrad/runtime/support/c.bend`.

EVERY value below is ASKED OF CPYTHON. None is transcribed. Six techniques are
needed because six of `c.py`'s facts are not reachable by reading it:

  1. `ctypes.sizeof` on `init_c_struct_t`'s class, and reads and writes through
     the `Field` descriptors, are the only way to see what the bitfield
     arithmetic ACTUALLY does. `Field._resolve` builds its getter and setter
     out of closures, so there is nothing to call but the descriptor.

  2. `_resolve` builds a throwaway `ctypes.Structure` through the module-global
     name `type`. Injecting `c.__dict__['type']` CAPTURES the `_fields_` tuple
     it builds, so the `dummy*` rows are CPython's own construction and not my
     re-typing of it. (A module global shadows the builtin, so this works;
     `c.types.type` does NOT, because `_resolve` calls bare `type(...)`.)

  3. `helpers.getenv` is `@functools.cache`d, so a fixture that changes
     `os.environ` must `getenv.cache_clear()` first or it reads the FIRST
     environment for the rest of the process. Found the hard way: eighteen
     `.so` fixtures all answered False because the cached value was a directory
     from an earlier run. `FL` clears it on every call for that reason.

  4. `findlib` reads `os.name` and `sys.platform` as MODULE GLOBALS of `c`, so
     the platform arms are reachable by replacing `c.os` / `c.sys` with
     namespaces. The real `os` and `sys` are untouched.

  5. TEMP PATHS ARE NORMALISED. `mkdtemp` returns a different directory every
     run, so every emitted path goes through `T()`, which rewrites the fixture
     root to the literal `<T>`. Without it the "pre-split snapshot" could never
     be diffed and the whole gate would be theatre.

  6. `DLL.__getattr__` only raises ITS message when `nm not in _loaded_`, so a
     plain object is useless as a fixture -- `type object '_X' has no
     attribute` is CPython's own error, not `c.py`'s. The fixture subclasses
     `c.DLL` so the descriptor is found.

    DEV=NULL .venv/bin/python .agents/slop/c-oracle.py > .agents/slop/runs/c-cpy.txt
"""
import ctypes, os, pathlib, re, sys, tempfile, types
from tinygrad.runtime.support import c

U32 = ctypes.c_uint32
R = []
def row(name, value): R.append(f"{name}={value}")
def u(x): return f"{x & 0xFFFFFFFF:08x}"
def mem(o): return bytes(memoryview(o).cast("B")).hex()
def setmem(o, bs):
  for i, b in enumerate(bs): o._mem_[i] = b

# `mkdtemp` is not reproducible; the fixture root is rewritten to `<T>` so the
# snapshot diffs. `mkdtemp(dir=ROOT)` keeps every fixture under one parent.
ROOT = tempfile.mkdtemp(prefix="cbend-oracle-")
TMPS = []
def T(s):
  """normalise a path under the fixture root"""
  s = str(s)
  for t in TMPS:
    if s.startswith(t): return "<T>" + s[len(t):]
  return s
def solo(*specs):
  """a directory holding exactly these files, created under ROOT"""
  d = tempfile.mkdtemp(dir=ROOT)
  TMPS.append(d)
  for n, b in specs: (pathlib.Path(d)/n).write_bytes(b)
  return d
def setplat(osname, plat, env):
  m = types.SimpleNamespace()
  for k in dir(os):
    if not k.startswith("_"): setattr(m, k, getattr(os, k))
  m.name = osname
  m.pathsep = ";" if osname == "nt" else ":"
  m.environ = env
  c.os = m
  c.sys = types.SimpleNamespace(platform=plat, byteorder=sys.byteorder)
def _raises(f):
  try: f(); return None
  except BaseException as e: return type(e).__name__

# ---------------------------------------------------------------- ioctl ----
# `_do_ioctl` builds the request number; the value it RETURNS is whatever
# ioctl(2) returned, so the request is captured from a spy on `fcntl.ioctl` --
# the same function object `_do_ioctl` resolves at call time.
import fcntl
_cap = []
def _spy(fd, req, *a, **k): _cap.append(req); return 0
fcntl.ioctl = _spy
def req(idir, base, nr, typ, *args):
  _cap.clear()
  c._do_ioctl(idir, base, nr, typ, 7, *args)
  return _cap[-1]

row("ioctl_none_ord_A_11", u(req(0, ord("A"), 0x11, None)))
# THE FIRST TRAP: the `__struct is None` arm never looks at `__idir`.
row("ioctl_none_idir3_same", int(req(3, ord("A"), 0x11, None) == req(0, ord("A"), 0x11, None)))
row("ioctl_none_B_11", u(req(0, ord("B"), 0x11, None)))
row("ioctl_w_ord_A_11_4", u(req(1, ord("A"), 0x11, U32)))
row("ioctl_r_ord_A_11_4", u(req(2, ord("A"), 0x11, U32)))
row("ioctl_wr_ord_A_11_4", u(req(3, ord("A"), 0x11, U32)))
row("ioctl_w_ord_A_11_8", u(req(1, ord("A"), 0x11, ctypes.c_uint64)))
row("ioctl_w_ord_A_11_1", u(req(1, ord("A"), 0x11, ctypes.c_int8)))
# `ctypes.sizeof(c_byte*0) == 0`, so a struct arm with a ZERO-SIZED payload
# still carries the `idir<<30` half and is NOT the no-struct request: the two
# branches differ by exactly the direction bits and nothing else.
row("ioctl_w_size0_is_none_req",
    int(req(1, ord("A"), 0x11, ctypes.c_byte*0) == req(0, ord("A"), 0x11, None)))
# `ord(base) if isinstance(base, str) else base` -- an int base passes through
row("ioctl_base_int_equals_str", int(req(1, 0x41, 0x11, U32) == req(1, ord("A"), 0x11, U32)))
# the four constructors differ ONLY in `__idir`, read off the functools.partial
for nm, f, typ in [("_IO", c._IO, None), ("_IOW", c._IOW, U32), ("_IOR", c._IOR, U32), ("_IOWR", c._IOWR, U32)]:
  p = f("A", 0x11) if typ is None else f("A", 0x11, typ)
  row(f"io_{nm}_partial", f"{p.args[0]},{p.args[1]},{p.args[2]},{'None' if p.args[3] is None else 'typ'}")
def rc_msg(rc):
  fcntl.ioctl = lambda fd, rq, *a, **k: rc
  try:
    c._do_ioctl(1, ord("A"), 0x11, U32, 7, 1); return "NO-RAISE"
  except RuntimeError as e: return str(e)
  finally: fcntl.ioctl = _spy
row("ioctl_rc5_msg", rc_msg(5))
row("ioctl_rc_neg1_msg", rc_msg(-1))
row("ioctl_rc0_msg", rc_msg(0))
row("host_byteorder", sys.byteorder)

# ------------------------------------------------ Field.__set_name__ / rf ----
# `idx` given to the constructor is OVERWRITTEN by `__set_name__` with
# `len(_real_fields_)-1`; what survives is the APPEND ORDER.
class Body(c.Struct):
  SIZE = 4
  a = c.Field(U32, 0)
  b = c.Field(U32, 2)
row("sname_real_fields", ",".join(e[0] for e in Body._real_fields_))
row("sname_entry_width", ",".join(str(len(e)) for e in Body._real_fields_))
row("sname_idx_after", f"{Body.__dict__['a'].idx},{Body.__dict__['b'].idx}")
row("sname_ctor_idx_given", "0,0")     # both constructed with idx=0
class BodyBF(c.Struct):
  SIZE = 4
  a = c.Field(U32, 0, 4, 0)
  b = c.Field(U32, 0, 12, 4)
row("sname_bf_entry_width", ",".join(str(len(e)) for e in BodyBF._real_fields_))
# bit_width == 0 is FALSY, so it takes the 3-tuple arm even though it was passed
class BodyZero(c.Struct):
  SIZE = 4
  z = c.Field(U32, 1, 0, 0)
row("sname_bw0_entry_width", ",".join(str(len(e)) for e in BodyZero._real_fields_))
E0 = BodyZero._real_fields_[0]
row("sname_bw0_entry", f"{E0[0]},{ctypes.sizeof(E0[1])},{E0[2]}")
# `register_fields` REPLACES `_real_fields_` and installs with enumerate's idx,
# so a class that already got entries from `__set_name__` restarts at 0.
class RegAfterBody(c.Struct):
  SIZE = 4
  a = c.Field(U32, 0)
RegAfterBody.register_fields((("p", U32, 3), ("q", U32, 1)))
# M2 IS A THEOREM AND THIS IS THE MEASUREMENT OF IT, NOT AN ARGUMENT.
# `__set_name__` picks `idx = len(_real_fields_) - 1`, and it appends only when
# `hasattr(owner, "_real_fields_")`. So the question is whether `has_real` can be
# False while the prior length is not zero -- and it cannot, because the length
# is only nonzero if something appended, and appending is what creates the
# attribute. `Field.set_name.idx(has_real, n)` is therefore `n` on BOTH arms and
# no fixture can separate them from the plain `n`.
#
# The pairs are COLLECTED from real `__set_name__` calls rather than reasoned
# about: the original is wrapped, and every (hasattr, len-before) it sees is
# recorded. If the set is exactly {(False,0), (True,1), (True,2)} then the two
# arms are never distinguishable and M2 is a theorem.
PAIRS = []
_orig_set_name = c.Field.__set_name__
def _spy_set_name(self, owner, name):
  has = hasattr(owner, "_real_fields_")
  n = len(getattr(owner, "_real_fields_", ()))
  PAIRS.append((has, n, name))
  return _orig_set_name(self, owner, name)
c.Field.__set_name__ = _spy_set_name
class Three(c.Struct):
  SIZE = 4
  one = c.Field(U32, 0)
  two = c.Field(U32, 1)
  three = c.Field(U32, 2)
class Sub(Three):
  four = c.Field(U32, 3)
c.Field.__set_name__ = _orig_set_name
row("sname_setname_pairs", ";".join(f"{h},{n},{nm}" for h, n, nm in PAIRS))
row("sname_hasreal_iff_npositive", int(all((n > 0) == h for h, n, _ in PAIRS)))
# AND THE CONSEQUENCE, read off the classes the spy watched: every `idx` equals the
# prior length, so `idx = n` and `idx = pick(n, has_real, n, 0)` agree on all of
# them. `getattr` reaches the FIELD, not the CField, so it is `__dict__`.
row("rf_after_body_idx", f"{RegAfterBody.__dict__['p'].idx},{RegAfterBody.__dict__['q'].idx}")
row("rf_after_body_names", ",".join(e[0] for e in RegAfterBody._real_fields_))

# --------------------------------------------- Field._resolve's dummy class --
CAP, _real_type = [], type
def _type(name, bases, ns):
  if bases and any(b is ctypes.Structure for b in bases): CAP.append((name, ns))
  return _real_type(name, bases, ns)
c.__dict__["type"] = _type
def lens1(f): return ",".join(str(getattr(t, "_length_", "typ")) for _, t in f)
class Probe(c.Struct):
  SIZE = 0
Probe.register_fields((("f0", U32, 3), ("f1", U32, 1), ("f2", U32, 7)))
for i, off in [(0, 3), (1, 1), (2, 7)]:
  CAP.clear()
  getattr(Probe, f"f{i}")
  nm_, ns = CAP[-1]; f = ns["_fields_"]
  row(f"dummy{i}_names", ",".join(x[0] for x in f))
  row(f"dummy{i}_lens", lens1(f))
  row(f"dummy{i}_layout_pack", f"{ns['_layout_']},{ns['_pack_']}")
  row(f"dummy{i}_ofs_size", f"{getattr(Probe, f'f{i}').offset},{getattr(Probe, f'f{i}').size}")
c.__dict__["type"] = _real_type

# ------------------------------------------- Field's bitfield arithmetic -----
# The strongest rows in the file: read AND WRITE through the real descriptors.
FIELDS = (("a", U32, 0, 4, 0), ("b", U32, 0, 12, 4), ("x", U32, 4))
CS = c.init_c_struct_t(8, FIELDS)
row("ics_sizes", f"{CS.SIZE},{ctypes.sizeof(CS)}")
row("ics_real_fields", ",".join(e[0] for e in CS._real_fields_))
o = CS(); setmem(o, [0]*8)
for tag, raw in [("abcd", [0xAB,0xCD,0xEF,0x12,0x78,0x56,0x34,0x12]),
                 ("zero", [0x00]*8), ("ffff", [0xFF]*8),
                 ("0ff0", [0x0F,0xF0,0x00,0x00,0x00,0x00,0x00,0x00]),
                 ("a001", [0x01,0x00,0xF0,0x00,0x00,0x00,0x00,0x00])]:
  setmem(o, raw)
  row(f"bf_read_{tag}", f"a={o.a},b={o.b},x={o.x}")
setmem(o, [0xAB,0xCD,0xEF,0x12,0x78,0x56,0x34,0x12])
o.a = 0xF;    row("bf_set_a_15", mem(o))
o.b = 0xABC;  row("bf_set_b_abc", mem(o))
o.a = 0x0;    row("bf_set_a_0", mem(o))
o.b = 0xFFF;  row("bf_set_b_fff", mem(o))
row("bf_get_after_set", f"a={o.a},b={o.b},x={o.x}")
# THERE IS NO MASKING ON STORE: `b` is 12 bits at bit_off 4 inside a 2-byte
# slice, so the 16-bit 0x1000 overflows `to_bytes(sz)`.
try: o.b = 0x1000; row("bf_set_b_overflow", f"NO-RAISE,{mem(o)}")
except OverflowError: row("bf_set_b_overflow", "OverflowError")
# the arithmetic itself, evaluated by the same expressions _resolve uses
for bw, bo in [(4,0),(12,4),(1,7),(31,0),(32,0),(3,5)]:
  sz = -((-(bw+bo))//8); mask = (1 << bw) - 1
  row(f"bf_arith_{bw}_{bo}", f"sz={sz},mask={mask},setmask={~(mask << bo) & 0xFFFFFFFF}")
# `sys.byteorder` is read INSIDE the closures `_resolve` builds, from c's module
# global `sys`, so it is a PARAMETER and not a constant. Shimming `c.sys` makes
# the big-endian answer reachable on this little-endian host, which is what
# proves the port has to carry it rather than hardcode it.
def order(bo):
  setplat("posix", "linux", {"LD_LIBRARY_PATH": "", "PATH": "/pdir"}); c.sys.byteorder = bo
  setmem(o, [0xAB,0xCD,0xEF,0x12,0x78,0x56,0x34,0x12])
  r = f"a={o.a},b={o.b},x={o.x}"
  o.b = 0xABC
  return r + f",mem={mem(o)}"
row("bf_order_little", order("little"))
row("bf_order_big", order("big"))
c.sys.byteorder = sys.byteorder

# ------------------------------------------------ record / Struct.__init__ ---
@c.record
class R8(c.Struct):
  SIZE = 8
R8.register_fields((("a", U32, 0), ("b", U32, 4), ("c", U32, 2)))
row("record_size_fields", f"{R8.SIZE},{ctypes.sizeof(R8)},{R8._fields_[0][0]},{R8._fields_[0][1]._length_}")
row("field_offsets", ",".join(str(getattr(R8, n).offset) for n in "abc"))
row("field_sizes", ",".join(str(getattr(R8, n).size) for n in "abc"))
# `c` at byte 2 ALIASES `a` (bytes 0..3) and `b` (bytes 4..7). Reading the same
# struct three ways gives three different answers and only the ORDER of
# `[*zip(names, args), *kwargs.items()]` explains all three.
o1 = R8(1, 2);      row("init_pos_1_2", f"a={o1.a},b={o1.b},c={o1.c},mem={mem(o1)}")
o2 = R8(1, 2, c=9); row("init_pos_kw_c9", f"a={o2.a},b={o2.b},c={o2.c},mem={mem(o2)}")
o3 = R8(c=9);       row("init_kw_c9", f"a={o3.a},b={o3.b},c={o3.c},mem={mem(o3)}")
o4 = R8(1, 2, 3, 4);row("init_pos_4_dropped", f"a={o4.a},b={o4.b},c={o4.c},mem={mem(o4)}")
o5 = R8(1, 2, d=7); row("init_unknown_kw", f"d={o5.d},mem={mem(o5)}")
row("init_zip_bound", f"{len(R8._real_fields_)},{min(len(R8._real_fields_), 4)}")
row("ics_size_attr_stays_0", str(CS.SIZE))

# ------------------------------------------------------------ init_c_var ----
# `(creat_cb(v := ty()), v)[1]` returns the VAR, not the callback's result.
_seen = []
def _cb(x): _seen.append(x); return 99
V = c.init_c_var(U32, _cb)
row("var_value", str(V.value))
row("var_cb_returned", "99")     # what a reader that returns creat_cb(v) would print

# ------------------------------------------------------------------ DLL -----
row("dll_emsg_libfoo", c.DLL("libfoo", []).emsg)
row("dll_emsg_dash", c.DLL("my-lib-x", []).emsg)
row("dll_emsg_given", c.DLL("libfoo", [], emsg="boom").emsg)
row("dll_emsg_empty_is_falsy", c.DLL("", []).emsg)
row("dll_envkey_plain", "libfoo".replace("-", "_").upper() + "_PATH")
row("dll_envkey_dash", "my-lib-x".replace("-", "_").upper() + "_PATH")
# THE UPSTREAM INCONSISTENCY, measured: `findlib` reads MY_LIB_X_PATH but the
# `emsg` it falls back to names MY-LIB-X_PATH.
row("dll_emsg_key_ne_envkey", int(c.DLL("my-lib-x", []).emsg != "try setting " + "my-lib-x".replace("-","_").upper() + "_PATH?"))
class NotLoaded(c.DLL):
  def __init__(self, nm, paths, extra_paths=[], emsg="", **kw):
    self.nm, self.emsg = nm, emsg or f"try setting {nm.upper()+'_PATH'}?"
try: getattr(NotLoaded("nope", []), "anything")
except AttributeError as e: row("dll_getattr_msg", str(e))
# `fn.__module__ = f"tinygrad.runtime.autogen.{self.nm}"` -- `_loaded_` is a
# process-wide MUTABLE SET with no Bend equivalent, so it is a WALL and the
# row pins only the string the name is assigned.
row("dll_getattr_module", f"tinygrad.runtime.autogen.{'nope'}")

# -------------------------------------------------------------- findlib -----
def FL(nm, paths, extra=[], env=None, osname="posix", plat="linux", osx=False, win=False):
  c.OSX, c.WIN = osx, win
  if env is not None: setplat(osname, plat, env)
  c.getenv.cache_clear()          # rule 3: getenv is cached for the process
  return c.DLL.findlib(nm, paths, extra)
E = {"LD_LIBRARY_PATH": "", "PATH": "/pdir"}
setplat("posix", "linux", E); c.OSX, c.WIN = False, False
D = solo(("libz.so.6", b"\x7FELF" + b"x"*8))
os.environ["Z_PATH"] = D
# THE STRUCTURAL FACT: the whole filesystem search lives INSIDE `for p in paths`,
# so `paths=[]` never searches and an ABSOLUTE non-file entry `continue`s PAST
# it -- the env directory is on disk the whole time and is never read.
#
# THESE SIX ARE THE ONLY findlib ROWS THAT SURVIVE, and they are asked as a
# QUESTION A BEND PORT CAN ANSWER: does the search REACH the prefix loop? The
# rows that reported findlib's RETURN VALUE were dropped, because the return is
# a filesystem path: a Bend row would have to invent one, and a row whose
# expected value is not a value is a row that cannot fail. `paths` entries here
# differ only in ABSOLUTE-vs-RELATIVE, and the two-order rows are what pin the
# `continue` to ONE entry rather than to the whole loop.
row("fl_found_paths_empty", int(FL("z", []) is not None))
row("fl_found_paths_abs_nonfile", int(FL("z", ["/nonexistent"]) is not None))
row("fl_found_paths_rel", int(FL("z", ["."]) is not None))
row("fl_found_paths_abs_then_rel", int(FL("z", ["/nonexistent", "."]) is not None))
row("fl_found_paths_rel_then_abs", int(FL("z", [".", "/nonexistent"]) is not None))
row("fl_found_paths_two_abs", int(FL("z", ["/nonexistent", "/also/missing"]) is not None))
# `nm` NEVER APPEARS IN A FILE NAME. The ladder is built from `p`, the loop
# variable over `paths`; `nm` only picks the env key and the libc/m arm. The two
# captured rows below are the WHOLE PROOF: the same directory, the same `nm`,
# two different `paths`, and the ladder follows `paths` every time.
del os.environ["Z_PATH"]
# AND THE LADDER ITSELF, captured out of c.py rather than re-typed: shim
# `c.__dict__["pathlib"]` so every `Path.is_file()` argument `findlib` tests is
# recorded in order. This is c.py:106-107's `base` list, verbatim, and it is
# what proves the ladder is built from `p`.
#
# THE FIRST RECORDED ARGUMENT IS THE ENV PATH, from the early
# `if pathlib.Path(path:=getenv(...)).is_file(): return path`, so it is dropped
# and only the three LADDER RUNGS are reported. `p='zzz'` is the negative half:
# the ladder follows `paths`, so it asks for a file that is not there.
TESTED = []
class _PL:
  """a pathlib.Path that REPORTS every is_file() argument, so the base-name
  ladder c.py builds is captured rather than re-typed"""
  def __init__(self, p): self._p = pathlib.Path(p)
  def is_file(self):
    TESTED.append(str(self._p)); return self._p.is_file()
  def is_dir(self): return self._p.is_dir()
  def is_absolute(self): return self._p.is_absolute()
  def is_symlink(self): return self._p.is_symlink()
  def __str__(self): return str(self._p)
  def __truediv__(self, o): return _PL(str(self._p) + "/" + str(o))
  def __iter__(self): return iter(self._p.iterdir())
c.__dict__["pathlib"] = types.SimpleNamespace(Path=lambda p: _PL(p))
def ladder(p, nm):
  e = solo(("P", b"x")); os.environ[f"{nm.upper()}_PATH"] = e
  TESTED.clear(); FL(nm, [p], env=E, plat="darwin", osx=True)
  del os.environ[f"{nm.upper()}_PATH"]
  # ONLY THE FIRST PREFIX'S THREE RUNGS. When a rung matches, findlib RETURNS
  # and the rest are never tested; when none matches it walks every prefix and
  # reports twelve more, which says nothing the three rungs do not.
  return ",".join(T(x).replace(T(e) + "/", "") for x in TESTED[1:4])
row("fl_osx_bases_p_P", ladder("P", "zzz"))
row("fl_osx_bases_p_zzz", ladder("zzz", "zzz"))
c.__dict__["pathlib"] = pathlib

# the `.so` NAME test and the ELF MAGIC are TWO INDEPENDENT filters: `libz.so.7`
# passes the regex and fails the magic, and `libz.soa` fails the regex outright.
# So the rows answer "was it FOUND", which is `NAME-TEST and MAGIC`, and the
# three `_9_` rows are the MAGIC half alone with the name test passing.
SO_FIXTURES = ["libz.so.6", "libz.so", "libz.soa", "libz.so.", "libz.so.1.2.3", "libz.soX",
               "libz.a", "libz.so.6.txt", "libz.so.7", "libz.so.0", "libzso.6", "libz.SO.6",
               "libz.so.6.gz", "libz.so.06", "libz.sox", "libz.so.6.0.0", "libz.so.9", "libz.dylib"]
for nm_ in SO_FIXTURES:
  e = solo((nm_, b"\x7FELF")); os.environ["Z_PATH"] = e
  row(f"so_{nm_.replace('.', '_')}", int(FL("z", ["."], env=E) is not None))
for tag, magic in [("badmagic", b"\x7ELF"), ("badmagiclast", b"\x7FELG"), ("empty", b"")]:
  e = solo(("libz.so.9", magic)); os.environ["Z_PATH"] = e
  row(f"so_libz_so_9_{tag}", int(FL("z", ["."], env=E) is None))
del os.environ["Z_PATH"]
row("fl_libc_osx", T(FL("libc", ["."], env=E, plat="darwin", osx=True) or "None"))
row("fl_m_osx", T(FL("m", ["."], env=E, plat="darwin", osx=True) or "None"))
row("fl_libc_prefix", FL("libc", ["."], env=E, plat="darwin", osx=True).replace("libc.dylib", "lib@.dylib"))
row("fl_libc_linux", "" if FL("libc", ["."], env=E, plat="linux") is None else "FOUND")
row("fl_m_linux", "" if FL("m", ["."], env=E, plat="linux") is None else "FOUND")
# `libpaths` is keyed by BOTH os.name AND sys.platform and BOTH lists are
# appended, so on linux the posix five come first and then the linux four.
def libpaths(p, env, osname, plat):
  return {"posix": [d for d in env.get("LD_LIBRARY_PATH", "").split(":" if osname != "nt" else ";") if d]
                    + ["/usr/lib64", "/usr/lib", "/usr/local/lib"],
          "nt": env["PATH"].split(";" if osname == "nt" else ":"),
          "darwin": ["/opt/homebrew/lib", f"/System/Library/Frameworks/{p}.framework",
                     f"/System/Library/PrivateFrameworks/{p}.framework"],
          "linux": ["/usr/lib/wsl/lib/", "/lib", "/lib64", "/lib/<multiarch>"]}
env2 = {"LD_LIBRARY_PATH": "/lddir1::/lddir2", "PATH": "/pdir"}
lp = libpaths("P", env2, "posix", "linux")
for k in ["posix", "linux", "darwin", "nt"]:
  row(f"libpaths_{k}", ",".join(libpaths("P", {"LD_LIBRARY_PATH": "/lddir1::/lddir2", "PATH": "C:\\a;C:\\b"}, "nt" if k == "nt" else "posix", "win32" if k == "nt" else "linux")[k]))
row("prefixes_both_keys", ",".join(lp["posix"] + lp["linux"]))
row("prefixes_env_first", ",".join(["/env"] + lp["posix"] + lp["linux"] + ["/extra"]))
row("libpaths_unknown_key", ",".join({}.get("sunos", [])))
# `os.environ['PATH']` is a SUBSCRIPT inside an eagerly-built dict, so findlib
# raises KeyError on POSIX when PATH is absent -- it is read whether or not the
# POSIX arm is taken.
try:
  FL("z", ["."], env={"LD_LIBRARY_PATH": ""}); row("fl_no_path_key", "NO-RAISE")
except KeyError as e: row("fl_no_path_key", f"KeyError:{e}")

# ---------------------------------------------- CFUNCTYPE / Array / POINTER --
# The key is a TYPING object, not a tuple: `get_args(Literal[3]) == (3,)`, while
# `get_args((3,)) == ()` and `c.Array[U32, (3,)]` raises IndexError. Every
# generated field spells it `c.Array[ty, Literal[n]]` (io_uring.py:66), and the
# `Literal[0]` form is the zero-length padding `Field._resolve` builds by hand.
from typing import Literal
row("arr_default_type_length", f"{c.Array._type_.__name__},{c.Array._length_}")
row("arr_getitem_zero_len", str(c.Array[U32, Literal[0]]._length_))
row("arr_getitem_is_product", str(ctypes.sizeof(c.Array[U32, Literal[3]])))
row("arr_tuple_key_raises", "IndexError" if _raises(lambda: c.Array[U32, (3,)]) else "NO-RAISE")
print("\n".join(R))