import Base
import ./../../tensor.bend as T
import ./../../helpers.bend as H
import ./../../LAWS/spec.bend as S
import ./../../dtype.bend as DT
import ./../../nn/__init__.bend as NN
import ./../../nn/state.bend as ST
import ./../../nn/layers.bend as LN
import ./../../mixin/op.bend as MO
import ./../../mixin/movement.bend as MX
import ./../../mixin/reduce.bend as RC
import ./../../mixin/elementwise.bend as EW
import ./../../mixin/creation.bend as CR
import ./../../mixin/rand.bend as RD
import ./../../nn/optim.bend as OPT
import ./../datasets/__init__.bend as D

# stub -- 1:1 path mirror of extra/models/rnnt.py (202 loc). not yet ported.
#
# rnn-t is the only file in this slice that asks for a kind of layer the port
# HAS NEVER HAD AT ALL. resnet.bend asked for more of the layers that exist
# (conv2d, batchnorm, linear). bert/t5/llama asked for more normalizers and one
# embedding. RNN-T asks for RECURRENCE: `class LSTM` (rnnt.py:118) and
# `class LSTMCell` (rnnt.py:88), with a `self.cells` LIST (:124) and a
# `Tensor.stack(*new_hc[1:])` over it (:148).
#
#   `grep -rnE "^def .*(lstm|LSTMCell|rnn|GRU|gru|cell)\(" --include='*.bend'
#   tinybendygrad/` = 0.
#
# and the proof that it is not there by accident: `mixin/elementwise.bend:1164`
# is where the activation LIST ends, and `mixin/op.bend:8` enumerates op.py's
# own side and lists `-- _pad_reflect_replicate, pad, dot, matmul, einsum,
# gradient, min, mean, var,` -- no recurrence anywhere in the upstream op mixin
# either. LSTM in tinygrad is `nn.state` + a Python `for` over time
# (`rnnt.py:135`), NOT an op, so its absence is the honest shape of the port's
# progress and not an omission inside a finished area.
#
# the named census for this file:
#   `nn.Embedding` MISSING (:178). THE FIRST MISSING SYMBOL.
#   `nn.Linear`    EXISTS, nn/layers.bend:518 symbol=nn_linear (:191,:192,:107).
#   `Tensor.sigmoid` EXISTS, mixin/elementwise.bend:1186 symbol=ew_sigmoid (:110).
#   `Tensor.tanh`    EXISTS, mixin/elementwise.bend:1235 symbol=ew_tanh    (:110).
#   `softmax`        NOT USED BY THIS FILE. (`mo_softmax` mixin/op.bend:1141 symbol=mo_softmax exists.)
#   `adam`           NOT USED BY THIS FILE. `nn/optim.bend:858 symbol=op_mstep` / `:903 op_vstep` EXIST and go unused
#                    here, as in every other file in
#                    this slice.
#   `matmul`/`dot`   NOT USED BY THIS FILE. `tinybendygrad/nn/layers.bend:374 symbol=nn_dot.order nn_dot` exists and
#                    RNN-T reaches matmul only through `x.linear` (:107,:191-192).
#   `Tensor.argmax`  MISSING (:46).
#   `LSTM`/`LSTMCell` MISSING, and this is the RECURRENCE wall.
#
# WHAT EXISTS, WITH ITS INSTRUMENT:
#   `Tensor.uniform`  mixin/rand.bend:918 symbol=rd_uniform  (:101,:102,:103,:104)
#   `Tensor.zeros`    mixin/creation.bend:526 symbol=cr_zeros (:33,:35,:36)
#   `Tensor.ones`     mixin/creation.bend:567 symbol=cr_ones  (:18)
#   `x.linear`        nn/layers.bend:518 symbol=nn_linear    (:107,:191,:192)
#   `x.reshape`       mixin/movement.bend:1417 symbol=mxw_reshape (:157)
#   `x.transpose`     mixin/movement.bend:1435 symbol=mxw_permute (:171,:183)
#   `x.expand`        nn/layers.bend:625 symbol=nn_expand     (:196,:197)
#   `x.pad`           mixin/movement.bend:1504 symbol=mxw_pad (:58,:156)
#   `Tensor.stack`    mixin/movement.bend:1257 symbol=mxw_stk  (:148)
#   `x.relu`          nn/layers.bend:292 symbol=nn_relu      (:200)
#   `x +`/`x *`       mixin/elementwise.bend:499/510 `ew_add`/`ew_mul` (:112,:182)
#
# what is missing, named -- and most of it is not recurrence, which is the
# FINDING: fixing LSTM would NOT make this file run.
#   (1) `nn.Embedding` (:178) -- MISSING.
#   (2) `Tensor.cat`   (:59,:115,:140,:199,:289,:296) -- MISSING, and it appears in
#       SIX places, three of them in `Tensor.cat(h, c)` at :115 which is the LSTM
#       cell's own RETURN.
#   (3) `Tensor.chunk` (:109) -- MISSING. `gates.chunk(4, 1)` splits the four gates.
#   (4) `Tensor.dropout` (:113,:201) -- MISSING.
#   (5) `Tensor.argmax` (:46) -- MISSING.
#   (6) `Tensor.clip`   (:43) -- MISSING.
#   (7) `Tensor.numpy`  (:28,:45,:46) -- MISSING, and it is the DEVICE-STATE SEAM:
#       `THE PORT's `mixin/op.bend` HEADER` already names it -- "`item` (mixin/op.py:22) and `data`
#       (mixin/op.py:20) are NOT WALLS and are not ports: `data` is a
#       `raise NotImplementedError` declaration and `item` reads host memory
#       through it". `_greedy_decode` (extra/models/rnnt.py:32) reads a TENSOR BACK to the host
#       at extra/models/rnnt.py:45 with `numpy` and extra/models/rnnt.py:46 and writes it into a fresh Tensor, so it cannot be a graph.
#   (8) `unsqueeze` (extra/models/rnnt.py:26, :38, :196, :197) --
#       `tinybendygrad/nn/layers.bend:506 symbol=nn_transpose nn_expand` covers the `expand` half and NOT the
#       `unsqueeze` half.
#   (9) `TinyJit` (:15,:54,:127) -- PARTIAL, per THE PORT's `extra/models/resnet.bend` HEADER:
#       `engine/jit.bend` is a real port (`InInfo` :370-389) and the NAME and the
#       DECORATOR are not.
#
# `load_from_pretrained` (:62-94) is THIRTY-THREE `.assign(...)` LINES against a
# TORCH checkpoint read through `torch.load` (:68) and a `fetch` (:64) that
# `helpers.bend:3123` records as unported. It is not arithmetic left undone and it
# is not counted as such.
#
# TODO(port): STOPPED AT `Prediction.__init__` (extra/models/rnnt.py:175).
# FIRST MISSING SYMBOL: `Embedding(vocab_size - 1, hidden_size)` at rnnt.py:178.
# NOTE THE ORDER, because it is the whole distance: `RNNT.__init__` (:10) builds
# `Encoder` (extra/models/rnnt.py:11) -- FOUR `Linear`s and two `LSTM`s -- before it reaches `Prediction`,
# so `LSTMCell.__init__` (:98) and `LSTM.__init__` (:119) are hit FIRST in the
# call order even though `Embedding` is the first missing symbol of the file's
# FIRST def. The honest statement is that RNN-T has ELEVEN missing symbols and the
# recurrence is only one of them.
# THE GATE MOVED TO `gates/models-rnnt-gate.bend`.
#
# The rows are consumers: each calls a def above through `P.`, and the
# driver defines nothing this file needs, which is the line
# `gates/README.md:173` draws.
#
# Its rows are the model's own census -- the refusal address and the
# `*_exists` claims about which symbols are in the tree -- and
# `gates/models-gate.py` checks every `_exists` claim against its OWN probe, so
# the claims are load-bearing rather than labels.
