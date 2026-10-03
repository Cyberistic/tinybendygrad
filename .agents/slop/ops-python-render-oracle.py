#!/usr/bin/env python3
"""THE CPYTHON ORACLE for the renderer/compiler/device half of
`tinygrad/runtime/ops_python.py`, and for the two defs of the program half that
have no packet: `wmma` and `PythonProgram.__init__`.

EVERY row below is what CPython ANSWERED. Nothing here is transcribed: each
`py_*` row is the result of calling the real class on the real `Target`, and each
`pywma_*` row is the result of calling the real `wmma` on a real `tc.TensorCore`
fragment list.

WHAT IS AND IS NOT GATEABLE, and why, stated here rather than discovered later:

  * `PythonRenderer.__init__` (:166-178) is a PURE function of
    (target.arch, target.renderer, IMAGE, EMULATE) and it replaces two fields on a
    frozen dataclass. Total, decidable, and every branch is reachable -- so it is
    gated here in full, including the refusal message.
  * `PythonCompiler.compile` (:160) is `base64.b64decode(src)`. base64 is a total
    character-level transform with no dynamic value in it, so the port can hold
    it exactly and it is gated in full.
  * `PythonRenderer.supported_dtypes` (:182) is a set comprehension over a set
    this file does not own. Its OWN half -- `d != dtypes.half or
    sys.version_info >= (3, 12)` -- is gated; the inherited set is a seam.
  * `PythonRenderer.render` (:180) is `base64.b64encode(pickle.dumps(uops))`. There
    is no pickle in Bend: a pickle is a Python OBJECT GRAPH written in a byte
    language, and `UOp.arg` is a Python object of any type at all. The port's
    counterpart is not a pickle and does not pretend to be one -- it is the v1
    TEXT WIRE, already implemented and gated by `.agents/slop/bend_packets.py`.
    What is gated here is the one thing about `render` that IS decidable without
    a pickle: it is a PURE function of the uop list, it is the LAST thing
    `Renderer.render` hands the compiler, and CPython's own answer for the same
    program is a base64 string that DECODES BACK to the uop list. So the oracle
    row is the round trip, and the port's row is its own packet's uop count.
  * `wmma` (:33-44) needs `tcore.frag_coords()` -- a three-way fragment layout
    from `renderer/tc.py`, which this project has not ported. It stays a WALL and
    is recorded as one; the CPython answer is printed so the wall is at least
    pinned to a real fragment list rather than to a description.

    .venv/bin/python .agents/slop/ops-python-render-oracle.py > .agents/slop/ops-python-render-oracle.txt
"""
import base64, itertools, os, sys, traceback

OUT = os.path.dirname(os.path.abspath(__file__))


def row(k, v): print(f'{k}={v!r}')


def archs():
  from tinygrad.helpers import Target
  import tinygrad.runtime.ops_python as OP
  return Target, OP


def main():
  from tinygrad.helpers import Target
  import tinygrad.runtime.ops_python as OP
  from tinygrad import Context
  from tinygrad.renderer import tc

  row('py_version_ge_312', sys.version_info >= (3, 12))
  row('py_version_tuple', tuple(sys.version_info[:2]))

  # ---- PythonRenderer.__init__, ops_python.py:166-178 ----------------------
  # every branch, with the IN and the OUT, both read off the live object.
  cases = [('empty', Target()),
           ('metal', Target(arch='METAL')),
           ('metal_lowp', Target(arch='METAL', renderer='lowp', device='2')),
           ('gfx1100', Target(arch='gfx1100')),
           ('gfx1201', Target(arch='gfx1201')),
           ('gfx950', Target(arch='gfx950')),
           ('sm_80', Target(arch='sm_80')),
           ('sm_75', Target(arch='sm_75')),
           ('sm_89', Target(arch='sm_89')),
           ('sm_90', Target(arch='sm_90')),
           ('cl_khr', Target(arch='gfx1100', renderer='opencl')),
           ('cuda_ptx', Target(arch='sm_80', renderer='cuda')),
           ('nonsense', Target(arch='NOT_AN_ARCH')),
           ('empty_renderer', Target(arch='', renderer='')),
           ('interface_set', Target(arch='gfx1100', interface='opencl')),
           ]
  for name, t in cases:
    try:
      r = OP.PythonRenderer(t)
      row(f'pyr_{name}_device', r.target.device)
      row(f'pyr_{name}_renderer', r.target.renderer)
      row(f'pyr_{name}_arch', r.target.arch)
      row(f'pyr_{name}_interface', r.target.interface)
      row(f'pyr_{name}_ncores', len(r.tensor_cores))
      row(f'pyr_{name}_coredims', [tuple(c.dims) for c in r.tensor_cores])
      row(f'pyr_{name}_core_in', [str(c.dtype_in) for c in r.tensor_cores])
      row(f'pyr_{name}_core_threads', [c.threads for c in r.tensor_cores])
    except Exception as e:
      row(f'pyr_{name}_err', f'{type(e).__name__}: {e}')

  # IMAGE, which is a getenv constant, so it needs its own process.
  with Context(IMAGE=1):
    r = OP.PythonRenderer(Target())
    row('pyr_image_empty_arch', r.target.arch)
    row('pyr_image_empty_device', r.target.device)
    row('pyr_image_empty_renderer', r.target.renderer)
    r = OP.PythonRenderer(Target(arch='gfx1100'))
    row('pyr_image_gfx_arch', r.target.arch)
    row('pyr_image_gfx_device', r.target.device)

  # EMULATE, also a getenv constant: the refusal at :167. Each value needs a
  # FRESH process because getenv is @functools.cache'd at import time, and this
  # process already read it.
  emu = os.environ.get('EMULATE', '')
  row('py_emulate_read', emu)
  try:
    OP.PythonRenderer(Target(arch='gfx1100'))
    row('py_emulate_ok', True)
  except AssertionError as e:
    row('py_emulate_ok', False)
    row('py_emulate_msg', str(e))
  except Exception as e:
    row('py_emulate_ok', False)
    row('py_emulate_msg', f'{type(e).__name__}: {e}')

  # ---- PythonCompiler.compile, ops_python.py:160 ---------------------------
  # base64.b64decode, over inputs chosen to hit every interesting shape: a
  # length that is not a multiple of 4, padding at both ends, and bytes that are
  # not printable.
  for k, raw in [('empty', b''), ('one', b'\x00'), ('two', b'\x00\xff'),
                 ('three', b'\x00\xff\x7f'), ('four', b'\x00\xff\x7f\x01'),
                 ('hi', bytes(range(256))), ('ascii', b'the quick brown fox'),
                 ('nl', b'a\nb\tc')]:
    src = base64.b64encode(raw).decode()
    row(f'pyc_{k}_src', src)
    row(f'pyc_{k}_hex', OP.PythonCompiler().compile(src).hex())
    row(f'pyc_{k}_same', OP.PythonCompiler().compile(src) == raw)
  row('pyc_is_base64_b64decode', OP.PythonCompiler().compile.__func__ is base64.b64decode)

  # ---- PythonRenderer.code_for_op / compiler, :163-164 ---------------------
  from tinygrad.uop.ops import python_alu
  row('pyr_code_for_op_is_python_alu', OP.PythonRenderer.code_for_op is python_alu)
  row('pyr_compiler_class', type(OP.PythonRenderer.compiler).__name__)
  row('pyr_compiler_is_instance', isinstance(OP.PythonRenderer.compiler, OP.PythonCompiler))

  # ---- PythonRenderer.supported_dtypes, :182 --------------------------------
  sd = OP.PythonRenderer.supported_dtypes(OP.PythonRenderer(Target()))
  row('pysd_n', len(sd))
  row('pysd_sorted', sorted(str(d) for d in sd))
  row('pysd_has_half', 'dtypes.f16' in {str(d) for d in sd})   # half was RENAMED to f16; 'float16' is dead
  row('pysd_super_n', len(OP.Renderer.supported_dtypes(OP.PythonRenderer(Target()))))

  # ---- PythonDevice.__init__, :186 ------------------------------------------
  # HostAllocator(self), [PythonRenderer], PythonProgram -- the order and the
  # class identities, read off the live device.
  from tinygrad import Device
  with Context(DEV='PYTHON'):
    dev = Device['PYTHON']
    row('pyd_class', type(dev).__name__)
    row('pyd_renderer', type(dev.renderer).__name__)
    row('pyd_compiler', type(dev.compiler).__name__)
    row('pyd_runtime_t', dev.runtime_t.__name__)
    row('pyd_allocator', type(dev.allocator).__name__)
    row('pyd_renderer_is_ops_python_renderer', type(dev.renderer) is OP.PythonRenderer)
    row('pyd_runtime_t_is_python_program', dev.runtime_t is OP.PythonProgram)
    row('pyd_renderers', [c.__name__ for c in dev.renderers])
    row('pyd_device', dev.device)
    row('pyd_arch', dev.arch)
    row('pyd_peer_group', dev.peer_group)
    row('pyd_allocator_is_host_allocator',
        type(dev.allocator).__name__ == 'HostAllocator')
    row('pyd_maxdim', getattr(dev, 'maxdim', None))

  # ---- wmma, :33-44. A WALL in the port; the CPython answer is pinned so the
  # wall names a real fragment list. METAL's tc table is the one that needs no
  # GPU, because frag_coords is pure.
  r = OP.PythonRenderer(Target(arch='METAL'))
  row('pywma_ncores', len(r.tensor_cores))
  for ci, tcore in enumerate(r.tensor_cores[:2]):
    frags = tcore.frag_coords()
    row(f'pywma_c{ci}_dims', tuple(tcore.dims))
    row(f'pywma_c{ci}_dtype_in', str(tcore.dtype_in))
    row(f'pywma_c{ci}_threads', tcore.threads)
    row(f'pywma_c{ci}_nfrags', len(frags))
    row(f'pywma_c{ci}_frag_shape', [len(f) for f in frags])
    row(f'pywma_c{ci}_frag_lane0', [f[0] for f in frags])
    # the three assertion lines, evaluated for real, one input shape
    # `inp` is THREE fragments, and each fragment is a list of `len(co[0])`
    # per-lane lists of `len(co[0][0])` elements. Measured: frags[0][0] is a list
    # of 2 (row, col) pairs, so 2 elements per thread, 32 lanes.
    # The first draft built a FLAT list of floats and CPython answered
    # "TypeError: 'float' object is not subscriptable" -- which is what
    # `out = [x[:] for x in inp[2]]` (:39) does to a flat list.
    n = len(frags[0][0])
    lanes = len(frags[0])
    # and `out[e][goff+lane] +=` (:43) indexes the second axis by LANE, so the
    # first axis is the `e` (row) axis of size n. The transpose of this -- a list
    # of `lanes` rows of `n` values -- is what the second attempt sent, and
    # CPython answered "A must have 2 elements per thread, it has 32".
    inp = [[[float(lane + 10 * f + e) for lane in range(lanes)] for e in range(n)]
           for f in range(3)]
    try:
      out = OP.wmma(r.tensor_cores, (tcore.dims, tcore.dtype_in, tcore.threads), inp,
                    tcore.threads)
      row(f'pywma_c{ci}_out0', out[0])
      row(f'pywma_c{ci}_out1', out[1])
      row(f'pywma_c{ci}_out2', out[2])
    except Exception as e:
      row(f'pywma_c{ci}_err', f'{type(e).__name__}: {e}')
    # the element-count assertion, with a SHORT fragment, which must fail
    try:
      OP.wmma(r.tensor_cores, (tcore.dims, tcore.dtype_in, tcore.threads),
              [[0.0], [0.0], [0.0]], tcore.threads)
      row(f'pywma_c{ci}_short_ok', True)
    except AssertionError as e:
      row(f'pywma_c{ci}_short_ok', False)
      row(f'pywma_c{ci}_short_msg', str(e))
    # the warp-size assertion
    try:
      OP.wmma(r.tensor_cores, (tcore.dims, tcore.dtype_in, tcore.threads), inp,
              tcore.threads - 1 if tcore.threads > 1 else 1)
      row(f'pywma_c{ci}_oddwarp_ok', True)
    except AssertionError as e:
      row(f'pywma_c{ci}_oddwarp_ok', False)
      row(f'pywma_c{ci}_oddwarp_msg', str(e))
    # and the lookup, which is `next(...)`: a NON-MATCH must raise StopIteration
    try:
      OP.wmma(r.tensor_cores, ((1, 1, 1), tcore.dtype_in, tcore.threads), inp, tcore.threads)
      row(f'pywma_c{ci}_nomatch_ok', True)
    except StopIteration:
      row(f'pywma_c{ci}_nomatch_ok', False)
      row(f'pywma_c{ci}_nomatch_msg', 'StopIteration')
    except Exception as e:
      row(f'pywma_c{ci}_nomatch_ok', False)
      row(f'pywma_c{ci}_nomatch_msg', f'{type(e).__name__}: {e}')

  # ---- PythonProgram.__init__, :47-51 ---------------------------------------
  # the two dicts it builds, read off a real program by intercepting a render.
  from tinygrad import Tensor, Context as C
  caps = []
  _r = OP.PythonRenderer.render
  OP.PythonRenderer.render = lambda self, uops: (caps.append(uops), _r(self, uops))[1]
  with C(DEV='PYTHON'):
    (Tensor([1.0, 2.0, 3.0, 4.0]).realize() + 1).tolist()
  OP.PythonRenderer.render = _r
  row('pypp_nuops', len(caps[-1]))
  row('pypp_ops', [str(u.op) for u in caps[-1]])
  row('pypp_nsrc', [len(u.src) for u in caps[-1]])
  row('pypp_uop_to_index', [i for i, _ in enumerate(caps[-1])])
  row('pypp_loop_end_keys', sum(1 for u in caps[-1] if str(u.op) in ('Ops.END', 'Ops.BACKEDGE')))
  row('pypp_pickle_len', len(caps[-1]) and len(__import__('pickle').dumps(caps[-1])))
  row('pypp_b64_len', len(base64.b64encode(__import__('pickle').dumps(caps[-1]))))
  row('pypp_lib_roundtrip', len(__import__('pickle').loads(base64.b64decode(
      base64.b64encode(__import__('pickle').dumps(caps[-1]))))))


if __name__ == '__main__':
  try:
    main()
  except Exception:
    traceback.print_exc()
    sys.exit(1)