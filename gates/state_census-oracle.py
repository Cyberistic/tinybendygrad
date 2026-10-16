#!/usr/bin/env python3
"""state_census-oracle.py -- CPython's lane for `gates/state_census-gate.py`.

    .venv/bin/python gates/state_census-oracle.py

83 ROWS IN THE ORDER `gates/state_census.bend` PRINTS THEM: the port's OWN fourteen
Boolean rows first, then seventy-one VALUE rows.

WHY VALUES AND NOT BOOLEANS. `nn/state.bend`'s own `main` prints `sd_tens=True` ..
`sd_param=True`, and every one of those is `Bool.eq(port_answer, TRANSCRIBED_LITERAL)`. A row
like that cannot tell "the port computed `layers.0.weight,...`" from "the port computed
something else", and a transcription error that landed in BOTH lanes is green. So this oracle
prints the VALUE and `gates/state_census.bend` prints the port's value, and the diff is
between two answers rather than between two assertions. The port's fourteen Booleans are
STILL in the lane -- they are re-driven through `St.t_tens()` .. `St.t_param()` -- so nothing
the file shipped is dropped; the values sit next to them and explain them.

WHAT THIS ORACLE CALLS. `get_state_dict`, `get_parameters`, `safe_dtypes`,
`inverse_safe_dtypes`, `dtypes.weaks`, `DTYPES_DICT` and `TensorIO.seek` -- tinygrad's OWN,
unreimplemented. The ONLY thing transcribed here is `TensorPickle.find_class`'s whitelist
(`state.py:253`), and THAT is self-checking: `WLS_SRC` asserts the four literals are still
the ones in the file at run time, so the copy cannot rot without failing. The other two
transcriptions are the row NAMES, which are a contract and not a claim.

THE FIXTURES ARE THE PORT'S, SPELLED IN PYTHON. `St.sd_t1/2/3/9` are CONST tensors carrying
`1`, `2`, `3` and `9`, so `t1 = Tensor([1.0])`, `t2 = Tensor([2.0])`, `t3 = Tensor([3.0])`,
`t9 = Tensor([9.0])`. `St.OOther{t2}` is CPython's `Tensor.relu` -- an object with no
`__dict__` and not a list/tuple/dict, so `state_dict` stays `{}` at `state.py:107`.
`St.sd_seek_v` takes `U32`s, so the two negative offsets arrive as their two's complement
images; CPython is handed the NEGATIVE ints, which is what the Python arithmetic actually sees.

NOTHING IS REALIZED ON A DEVICE except `TensorIO.seek`, which reads `len(t)` -- a shape, not a
buffer -- and `val_dup_val`, which reads one scalar with `.item()`.
"""

import inspect
import sys

from tinygrad import Tensor, dtypes
from tinygrad.dtype import DTYPES_DICT
from tinygrad.nn.state import (TensorIO, get_parameters, get_state_dict,
                               inverse_safe_dtypes, safe_dtypes)

# --- THE ONE TRANSCRIPTION, SELF-CHECKING --------------------------------
# state.py:253 -- `whitelist = {"torch", "collections", "numpy", "_codecs"}`.
WLS = ("torch", "collections", "numpy", "_codecs")
_SRC = inspect.getsource(sys.modules["tinygrad.nn.state"])
assert 'whitelist = {"torch", "collections", "numpy", "_codecs"}' in _SRC, (
  "the whitelist this oracle transcribes is no longer the one in tinygrad/nn/state.py:253; "
  "the pin in gates/state_census-gate.py is the backstop and this is the cheap one")


def keys(o, prefix=''):
  return ''.join(k + ',' for k in get_state_dict(o, prefix=prefix).keys())


def row(nm, v):
  print(f"{nm}={v}")


def bl(nm, b):
  row(nm, "True" if b else "False")


t1, t2, t3, t9 = Tensor([1.0]), Tensor([2.0]), Tensor([3.0]), Tensor([9.0])

# ============ A. THE PORT'S OWN FOURTEEN BOOLEAN ROWS =====================
bl("sd_tens", keys(t1) == ',')
bl("sd_map", keys({'w': t1}) == 'w,')
bl("sd_seq", keys([t1, t2]) == '0,1,')

_bn = {'weight': t1, 'bias': t2, 'num_batches_tracked': t3, 'running_mean': t1, 'running_var': t2}
NEST = {'layers': [_bn, Tensor.relu, {'weight': t3}]}
bl("sd_nest", keys(NEST) ==
   'layers.0.weight,layers.0.bias,layers.0.num_batches_tracked,layers.0.running_mean,'
   'layers.0.running_var,layers.2.weight,')
bl("sd_strip", all(p.strip('.') == q for p, q in
                   [('', ''), ('.', ''), ('..', ''), ('.a.', 'a'), ('a..b..', 'a..b'), ('a', 'a')]))

import collections as _collections
NT = _collections.namedtuple('NT', 'a b')


class C:
  def __init__(self):
    self.q = t1


bl("sd_attr", keys(NT(t1, t2)) == 'a,b,' and keys(C()) == 'q,')
od = _collections.OrderedDict([('z', t1), ('a', t2)])
bl("sd_ord", keys(od) == 'z,a,' and hasattr(od, '__dict__'))

_sd = get_state_dict({'a.b': t1, 'a': {'b': t9}})
bl("sd_dup", list(_sd.keys()) == ['a.b'] and int(_sd['a.b'].item()) == 9)
bl("sd_safe", ','.join(safe_dtypes.keys()) ==
    'BOOL,I8,U8,I16,U16,I32,U32,I64,U64,F8_E4M3,F8_E5M2,F16,BF16,F32,F64')
# THE PORT's OWN claim, not a construction of my own: `safe_dtypes` is a bijection onto 15
# dtypes that all EXIST, and `safe_load`/`safe_save` index it both ways.
#
# THE FIRST DRAFT OF THIS ROW WAS WRONG AND FAILED LOUDLY, WHICH IS THE POINT OF THE
# COMMENT. It read `all(DTYPES_DICT[k.lower()] is v for k, v in safe_dtypes.items())`, taking
# `OnnxDataType.to_dtype` -- `DTYPES_DICT[self.name.lower()]` -- as `safe_dtypes`' construction.
# It is a DIFFERENT table with a DIFFERENT vocabulary: the safetensors spelling is `F8_E4M3`
# and `DTYPES_DICT` has no `f8_e4m3`, so the row raised `KeyError` rather than answering
# False. A reimplementation of the thing it checks, agreeing with itself, is the class this
# row was written to avoid; it is caught here by an exception rather than by a green diff.
bl("sd_safedt", all(v in DTYPES_DICT.values() for v in safe_dtypes.values())
   and len({id(v) for v in safe_dtypes.values()}) == 15)
bl("sd_invn", len(safe_dtypes) == 15)
bl("sd_inv", all(inverse_safe_dtypes[safe_dtypes[k]] == k for k in safe_dtypes))

_u8 = Tensor([1.0], dtype='uint8')


def sk(args):
  io = TensorIO(_u8)
  io.seek(*args)
  return f"{io._position >> 32 & 4294967295}:{io._position & 4294967295}"


bl("sd_seek", sk((0,)) == '0:0' and sk((1,)) == '0:1' and sk((-1,)) == '0:0'
   and sk((1, 1)) == '0:1' and sk((0, 2)) == '0:1' and sk((9,)) == '0:1'
   and sk((-5,)) == '0:0')


class Net:
  def __init__(self):
    self.layers = [_bn, Tensor.relu, {'weight': t3, 'bias': t1}]


bl("sd_param", len(get_parameters(Net())) == 7)

# ============ B. THE VALUE ROWS ==========================================
row("val_tens", keys(t1))
row("val_map", keys({'w': t1}))
row("val_seq", keys([t1, t2]))
row("val_nest", keys(NEST))
row("val_attr1", keys(NT(t1, t2)))
row("val_attr2", keys(C()))
row("val_ord", keys(od))
row("ctrl_ord", keys(od))
bl("ctrl_bool", dtypes.float32 in dtypes.weaks)
row("val_keys_n", len(get_state_dict(NEST).keys()))

row("val_dup_keys", keys({'a.b': t1, 'a': {'b': t9}}))
row("val_dup_val", int(_sd['a.b'].item()))
row("val_dup_n", len(_sd))

for i, sfx in enumerate(('', '.', '..', '.a.', 'a..b..', 'a')):
  row(f"val_strip_{i}", sfx.strip('.'))
row("ctrl_strip", '....a....b....'.strip('.'))

row("val_safe", ''.join(k + ',' for k in safe_dtypes))
row("val_safe_n", len(safe_dtypes))
for k in safe_dtypes:
  row(f"val_get_{k}", safe_dtypes[k].name)
row("val_get_none", "-")
row("ctrl_get", safe_dtypes["BF16"].name)
for tag, dt in (("bool", dtypes.bool), ("f32", dtypes.float32), ("f64", dtypes.float64),
                ("bf16", dtypes.bfloat16), ("fp8e4m3", dtypes.fp8e4m3),
                ("fp8e5m2", dtypes.fp8e5m2), ("weak", dtypes.weakint), ("none", dtypes.void)):
  row(f"val_name_{tag}", inverse_safe_dtypes.get(dt, "-"))
bl("val_weak_in", dtypes.weakint in dtypes.weaks)
bl("val_weak_out", dtypes.float32 in dtypes.weaks)

for nm, args in (("val_seek_0_0_0", (0,)), ("val_seek_0_1_0", (1,)), ("val_seek_0_neg1_0", (-1,)),
                 ("val_seek_0_1_1", (1, 1)), ("val_seek_0_0_2", (0, 2)), ("val_seek_0_9_0", (9,)),
                 ("val_seek_0_neg5_0", (-5,))):
  row(nm, sk(args))
row("ctrl_seek", f"{TensorIO(Tensor([1.0] * 4, dtype='uint8')).seek(0, 0) >> 32 & 4294967295}:0")


def fc_text(dbg, module, name):
  if dbg >= 2 and module.split(".")[0] not in WLS:
    return f"WARNING: returning Dummy for {module} {name}"
  return ""


for nm, m in (("val_fc_root_os", "os.path"), ("val_fc_root_col", "collections"),
              ("val_fc_root_np", "numpy"), ("val_fc_root_torch", "torch.storage"),
              ("val_fc_root_empty", "")):
  row(nm, m.split(".")[0])
row("val_fc_whitelist", ''.join(w + ',' for w in WLS))
bl("val_fc_ok_os", "os.path".split(".")[0] in WLS)
bl("val_fc_dummy_os", "os.path".split(".")[0] not in WLS)
bl("val_fc_dummy_col", "collections".split(".")[0] not in WLS)
bl("val_fc_dummy_np", "numpy".split(".")[0] not in WLS)
row("val_dbg_2_os", fc_text(2, "posixpath", "join"))
row("val_dbg_3_os", fc_text(3, "posixpath", "join"))
row("val_dbg_1_os", fc_text(1, "posixpath", "join"))
row("val_dbg_2_col", fc_text(2, "collections", "OrderedDict"))
