import sys, os, json, struct
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, ROOT)
from tinygrad import Tensor, dtypes
from tinygrad import nn
from tinygrad.helpers import Context

class Net:
  def __init__(self):
    self.l1 = nn.Linear(4, 5)
    self.l2 = nn.Linear(5, 6)
    self.n = nn.BatchNorm(5)

net = Net()
sd = nn.state.get_state_dict(net)
print('gsd_a=%s' % ','.join(sd.keys()))
print('gpar_a=%d' % len(nn.state.get_parameters(net)))
print('gpar_dt=%s' % ','.join(t.dtype.name for t in nn.state.get_parameters(net)))

c = nn.Conv2d(1, 4, 3)
print('gsd_conv=%s' % ','.join(nn.state.get_state_dict(c).keys()))
print('gsd_lin=%s' % ','.join(nn.state.get_state_dict(nn.Linear(3, 2)).keys()))

print('gsd_root=%s' % ','.join(nn.state.get_state_dict(Tensor.zeros(3, device='PYTHON')).keys()))
print('gsd_int=%s' % repr(list(nn.state.get_state_dict(7).keys())))
print('gsd_prefix=%s' % ','.join(nn.state.get_state_dict({'a': Tensor.zeros(1, device='PYTHON')}, 'p.').keys()))
print('gsd_seq=%s' % ','.join(nn.state.get_state_dict([Tensor.zeros(1, device='PYTHON'),
                                                       {'b': Tensor.zeros(1, device='PYTHON')}]).keys()))
from collections import OrderedDict, namedtuple
print('gsd_od=%s' % ','.join(nn.state.get_state_dict(OrderedDict([('z', Tensor.zeros(1, device='PYTHON')),
                                                                   ('a', Tensor.zeros(1, device='PYTHON'))])).keys()))
P = namedtuple('P', ['w', 'n'])
print('gsd_nt=%s' % ','.join(nn.state.get_state_dict(P(Tensor.zeros(1, device='PYTHON'), 5)).keys()))
# the dict.update collision: a key that appears twice
print('gsd_dup=%s' % ','.join(nn.state.get_state_dict({'a': Tensor.zeros(1, device='PYTHON'),
                                                       'a.b': Tensor.zeros(2, device='PYTHON')}).keys()))
d = nn.state.get_state_dict({'a': Tensor.zeros(1, device='PYTHON'), 'a.b': Tensor.zeros(2, device='PYTHON')})
print('gsd_dup_dt=%s' % ','.join('%s:%s' % (k, v.dtype.name) for k, v in d.items()))

# --- load_state_dict, no realize -----------------------------------------
class M:
  def __init__(self):
    self.a = Tensor.zeros(2, 3, device='PYTHON')
    self.b = Tensor.zeros(4, device='PYTHON')
m = M()
try:
  r = nn.state.load_state_dict(m, {'a': Tensor.zeros(2, 3, device='PYTHON')}, strict=False, verbose=False, realize=False)
  print('lsd_skip=%s' % ','.join(k for k in nn.state.get_state_dict(m) if k not in {'a': 0}))
except Exception as e:
  print('lsd_exc=%s' % e)
m2 = M()
try:
  nn.state.load_state_dict(m2, {'a': Tensor.zeros(3, 2, device='PYTHON')}, strict=False, verbose=False, realize=False)
  print('lsd_reshape=ok')
except Exception as e:
  print('lsd_reshape=%s' % e)
m3 = M()
try:
  nn.state.load_state_dict(m3, {'a': Tensor.zeros(2, 3, device='PYTHON'), 'b': Tensor.zeros(9, device='PYTHON')}, verbose=False, realize=False)
  print('lsd_raise=none')
except ValueError as e:
  print('lsd_raise=%s' % e)
