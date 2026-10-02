import sys, os, json, struct
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from tinygrad import Tensor, dtypes
from tinygrad import nn

# --- safe_save: write a real file and re-read the header -------------------
from tinygrad.helpers import round_up
t = {'w': Tensor.zeros(2, 3, device='PYTHON'), 'b': Tensor.zeros(3, device='PYTHON')}
nn.state.safe_save(t, '/tmp/nnstate.safetensors')
raw = open('/tmp/nnstate.safetensors', 'rb').read()
n = struct.unpack('<q', raw[0:8])[0]
j = raw[8:8+n]
body = j.rstrip()
print('ss_n=%d' % n)
print('ss_jlen=%d' % len(body))
print('ss_pad=%d' % (n - len(body)))
print('ss_hdr=%s' % ','.join('%s:%s:%s:%d-%d' % (k, v['dtype'], tuple(v['shape']), v['data_offsets'][0], v['data_offsets'][1])
                             for k, v in json.loads(body).items()))

# --- safe_load ------------------------------------------------------------
sd = nn.state.safe_load('/tmp/nnstate.safetensors')
print('sl_keys=%s' % ','.join(sd.keys()))
print('sl_shape=%s' % ','.join('%s:%s' % (k, tuple(v.shape)) for k, v in sd.items()))
print('sl_dt=%s' % ','.join('%s:%s' % (k, v.dtype.name) for k, v in sd.items()))

# --- TensorIO.seek --------------------------------------------------------
from tinygrad.nn.state import TensorIO
u = Tensor([1, 2, 3, 4], dtype=dtypes.u8, device='PYTHON').contiguous()
io = TensorIO(u)
print('tio_len=%d' % len(io._tensor))
print('tio_chain=%s' % ','.join(str(io.seek(off)) for off in (1, 1, 3, -1, 10, -10, 2)))
io.seek(0, 0)
print('tio_w1=%s' % ','.join(str(io.seek(off, wh)) for off, wh in ((-5, 0), (0, 0), (2, 0), (10, 0), (0, 1), (-1, 1), (0, 2), (-4, 2), (1, 2), (99, 3))))
print('tio_readable=%s seekable=%s' % (io.readable(), io.seekable()))
for nm, x in (('1du8', u), ('2d', Tensor.zeros(2, 2, device='PYTHON')), ('1df32', Tensor.zeros(3, device='PYTHON'))):
  try:
    TensorIO(x)
    print('tio_guard_%s=False' % nm)
  except ValueError:
    print('tio_guard_%s=True' % nm)
