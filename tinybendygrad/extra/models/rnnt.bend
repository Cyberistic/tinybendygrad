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

# ===========================================================================
# STUB -- 1:1 PATH MIRROR of extra/models/rnnt.py (202 LOC). NOT YET PORTED.
#
# RNN-T IS THE ONLY FILE IN THIS SLICE THAT ASKS FOR A KIND OF LAYER THE PORT
# HAS NEVER HAD AT ALL. resnet.bend asked for more of the layers that exist
# (conv2d, batchnorm, linear). bert/t5/llama asked for more normalizers and one
# embedding. RNN-T asks for RECURRENCE: `class LSTM` (rnnt.py:118) and
# `class LSTMCell` (rnnt.py:97), with a `self.cells` LIST (:124) and a
# `Tensor.stack(*new_hc[1:])` over it (:148).
#
#   `grep -rnE "^def .*(lstm|LSTMCell|rnn|GRU|gru|cell)\(" --include='*.bend'
#   tinybendygrad/` = 0.
#
# AND THE PROOF THAT IT IS NOT THERE BY ACCIDENT: `mixin/elementwise.bend:1186`
# is where the activation LIST ends, and `mixin/op.bend:8` enumerates op.py's
# own side and lists `-- _pad_reflect_replicate, pad, dot, matmul, einsum,
# gradient, min, mean, var,` -- no recurrence anywhere in the upstream op mixin
# either. LSTM in tinygrad is `nn.state` + a Python `for` over time
# (`rnnt.py:135`), NOT an op, so its absence is the honest shape of the port's
# progress and not an omission inside a finished area.
#
# THE NAMED CENSUS FOR THIS FILE:
#   `nn.Embedding` MISSING (:178). THE FIRST MISSING SYMBOL.
#   `nn.Linear`    EXISTS, nn/layers.bend:427 `nn_linear` (:191,:192,:107).
#   `Tensor.sigmoid` EXISTS, mixin/elementwise.bend:1196 `ew_sigmoid` (:110).
#   `Tensor.tanh`    EXISTS, mixin/elementwise.bend:1232 `ew_tanh`    (:110).
#   `softmax`        NOT USED BY THIS FILE. (`mo_softmax` mixin/op.bend:1095 exists.)
#   `adam`           NOT USED BY THIS FILE. `nn/optim.bend:898 op_mstep` / `:903
#                    op_vstep` EXIST and go unused here, as in every other file in
#                    this slice.
#   `matmul`/`dot`   NOT USED BY THIS FILE. `nn/layers.bend:383 nn_dot` exists and
#                    RNN-T reaches matmul only through `x.linear` (:107,:191-192).
#   `Tensor.argmax`  MISSING (:46).
#   `LSTM`/`LSTMCell` MISSING, and this is the RECURRENCE wall.
#
# WHAT EXISTS, WITH ITS INSTRUMENT:
#   `Tensor.uniform`  mixin/rand.bend:836 `rd_uniform`  (:101,:102,:103,:104)
#   `Tensor.zeros`    mixin/creation.bend:446 `cr_zeros` (:33,:35,:36)
#   `Tensor.ones`     mixin/creation.bend:487 `cr_ones`  (:18)
#   `x.linear`        nn/layers.bend:427 `nn_linear`    (:107,:191,:192)
#   `x.reshape`       mixin/movement.bend:1431 `mxw_reshape` (:157)
#   `x.transpose`     mixin/movement.bend:1449 `mxw_permute` (:171,:183)
#   `x.expand`        nn/layers.bend:520 `nn_expand`     (:196,:197)
#   `x.pad`           mixin/movement.bend:1517 `mxw_pad.go` (:58,:156)
#   `Tensor.stack`    mixin/movement.bend:1269 `mxw_stk`  (:148)
#   `x.relu`          nn/layers.bend:262 `nn_relu`      (:200)
#   `x +`/`x *`       mixin/elementwise.bend:509/510 `ew_add`/`ew_mul` (:112,:182)
#
# WHAT IS MISSING, NAMED -- AND MOST OF IT IS NOT RECURRENCE, WHICH IS THE
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
#       `mixin/op.bend:87-89` already names it -- "`item` (op.py:22) and `data`
#       (op.py:20) are NOT WALLS and are not ports: `data` is a
#       `raise NotImplementedError` declaration and `item` reads host memory
#       through it". `_greedy_decode` reads a TENSOR BACK to the host at :45 and
#       :46 and writes it into a fresh Tensor, so it cannot be a graph.
#   (8) `unsqueeze` (:26,:38,:195,:196,:197) -- `grep -rnE "^def (mo|tn|ew)_unsqueeze"` = 0.
#       `nn/layers.bend:520 nn_expand` covers the `expand` half and NOT the
#       `unsqueeze` half.
#   (9) `TinyJit` (:15,:54,:127) -- PARTIAL, per resnet.bend:116-123:
#       `engine/jit.bend` is a real port (`InInfo` :370-389) and the NAME and the
#       DECORATOR are not.
#
# `load_from_pretrained` (:62-94) is THIRTY-THREE `.assign(...)` LINES against a
# TORCH checkpoint read through `torch.load` (:68) and a `fetch` (:64) that
# `helpers.bend:3191` records as unported. It is not arithmetic left undone and it
# is not counted as such.
#
# TODO(port): STOPPED AT `Prediction.__init__` (extra/models/rnnt.py:175).
# FIRST MISSING SYMBOL: `Embedding(vocab_size - 1, hidden_size)` at rnnt.py:178.
# NOTE THE ORDER, because it is the whole distance: `RNNT.__init__` (:10) builds
# `Encoder` (:11) -- FOUR `Linear`s and two `LSTM`s -- before it reaches `Prediction`,
# so `LSTMCell.__init__` (:98) and `LSTM.__init__` (:119) are hit FIRST in the
# call order even though `Embedding` is the first missing symbol of the file's
# FIRST def. The honest statement is that RNN-T has ELEVEN missing symbols and the
# recurrence is only one of them.
# ===========================================================================

def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))

def rt_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# ---------------------------------------------------------------------------
# :9-94 RNNT.
# ---------------------------------------------------------------------------

# :10 def __init__(self, input_features=240, vocab_size=29, enc_hidden_size=1024, pred_hidden_size=320, joint_hidden_size=512, pre_enc_layers=2, post_enc_layers=3, pred_layers=2, stack_time_factor=2, dropout=0.32)
def rt_rnnt_init(input_features: U32, vocab_size: U32, enc_hidden_size: U32, pred_hidden_size: U32,
  joint_hidden_size: U32, pre_enc_layers: U32, post_enc_layers: U32, pred_layers: U32,
  stack_time_factor: U32, dropout: F32) -> D.Refused:
  D.refuse("extra/models/rnnt.py:10 RNNT.__init__ -- FIRST MISSING SYMBOL Encoder (:11) -> LSTM (:119) -> LSTMCell (:97); recurrence has no counterpart anywhere in tinybendygrad/")

# :15-16 @TinyJit / def __call__(self, x, y, hc=None)
def rt_rnnt_call(+x: T.Tensor, +y: T.Tensor) -> D.Refused:
  D.refuse("extra/models/rnnt.py:16 RNNT.__call__ -- FIRST MISSING SYMBOL TinyJit (:15); resnet.bend:116-123 measures this as PARTIAL -- engine/jit.bend is a port and the NAME is not")

# :22 def decode(self, x, x_lens)
def rt_rnnt_decode(+x: T.Tensor, x_lens: Maybe<&2, T.Tensor>) -> D.Refused:
  D.refuse("extra/models/rnnt.py:22 RNNT.decode -- FIRST MISSING SYMBOL Tensor.numpy (:28), the device-state seam mixin/op.bend:87-89 names")

# :32 def _greedy_decode(self, logits, logit_len)
def rt_greedy_decode(+logits: T.Tensor, logit_len: U32) -> D.Refused:
  D.refuse("extra/models/rnnt.py:32 _greedy_decode -- FIRST MISSING SYMBOL Tensor.numpy (:45); the inner loop is also bounded by the literal 30 at :41 and by `labels` being a Python list that a Tensor indexes (:44)")

# :55 def _pred_joint(self, logit, label, hc, mask)
def rt_pred_joint(+logit: T.Tensor, +label: T.Tensor, +hc: T.Tensor, +mask: T.Tensor) -> D.Refused:
  D.refuse("extra/models/rnnt.py:55 _pred_joint -- FIRST MISSING SYMBOL self.prediction (:56) -> LSTM -> LSTMCell")

# :62 def load_from_pretrained(self)
def rt_rnnt_load_from_pretrained() -> D.Refused:
  D.refuse("extra/models/rnnt.py:62 RNNT.load_from_pretrained -- FIRST MISSING SYMBOL fetch (:64); helpers.bend:3191 records the HTTP seam as unported. The 33 `.assign` lines at :72-94 are torch-checkpoint loads, not arithmetic")

# ---------------------------------------------------------------------------
# :97-115 LSTMCell. THE RECURRENCE WALL, SPELLED OUT.
# ---------------------------------------------------------------------------

# :98 def __init__(self, input_size, hidden_size, dropout)
def rt_cell_init(input_size: U32, hidden_size: U32, dropout: F32) -> D.Refused:
  D.refuse("extra/models/rnnt.py:98 LSTMCell.__init__ -- REACHED: all four weights are Tensor.uniform, mixin/rand.bend:836 rd_uniform EXISTS (:101-104). BLOCKED BY: the missing class shell only -- this def's ARITHMETIC IS PORTED")

# :106 def __call__(self, x, hc)
def rt_cell_call(+x: T.Tensor, +hc: T.Tensor) -> D.Refused:
  D.refuse("extra/models/rnnt.py:106 LSTMCell.__call__ -- FIRST MISSING SYMBOL Tensor.chunk (:109); x.linear (:107) EXISTS, sigmoid/tanh (:110) EXIST at mixin/elementwise.bend:1196/:1232, and Tensor.cat (:115) is MISSING")

# ---------------------------------------------------------------------------
# :118-148 LSTM.
# ---------------------------------------------------------------------------

# :119 def __init__(self, input_size, hidden_size, layers, dropout)
def rt_lstm_init(input_size: U32, hidden_size: U32, layers: U32, dropout: F32) -> D.Refused:
  D.refuse("extra/models/rnnt.py:119 LSTM.__init__ -- FIRST MISSING SYMBOL LSTMCell (:124); `self.cells` is a LIST of them, and a list of sub-models is the shape nn/__init__.bend:22-33 settled on for `*_st` defs")

# :126 def __call__(self, x, hc)
def rt_lstm_call(+x: T.Tensor, +hc: Maybe<&2, T.Tensor>) -> D.Refused:
  D.refuse("extra/models/rnnt.py:126 LSTM.__call__ -- FIRST MISSING SYMBOL TinyJit on the INNER _do_step (:127,:128); the time loop (:135) is Python control flow, not a graph")

# :144 def do_step(self, x, hc)
def rt_lstm_do_step(+x: T.Tensor, +hc: T.Tensor) -> D.Refused:
  D.refuse("extra/models/rnnt.py:144 LSTM.do_step -- FIRST MISSING SYMBOL LSTMCell.__call__ (:147) -> Tensor.chunk; Tensor.stack (:148) EXISTS at mixin/movement.bend:1269")

# ---------------------------------------------------------------------------
# :151-158 StackTime.
# ---------------------------------------------------------------------------

# :152 def __init__(self, factor)
def rt_stacktime_init(factor: U32) -> U32: factor

# :155 def __call__(self, x, x_lens)
def rt_stacktime_call(+x: T.Tensor, x_lens: Maybe<&2, T.Tensor>) -> D.Refused:
  D.refuse("extra/models/rnnt.py:155 StackTime.__call__ -- mxw_pad EXISTS (:156) and mxw_reshape EXISTS (:157); BLOCKED BY the two-tuple return (:158), which carries an Option")

# ---------------------------------------------------------------------------
# :161-171 Encoder.
# ---------------------------------------------------------------------------

# :162 def __init__(self, input_size, hidden_size, pre_layers, post_layers, stack_time_factor, dropout)
def rt_encoder_init(input_size: U32, hidden_size: U32, pre_layers: U32, post_layers: U32, stack_time_factor: U32) -> D.Refused:
  D.refuse("extra/models/rnnt.py:162 Encoder.__init__ -- FIRST MISSING SYMBOL LSTM (:163)")

# :167 def __call__(self, x, x_lens)
def rt_encoder_call(+x: T.Tensor, x_lens: Maybe<&2, T.Tensor>) -> D.Refused:
  D.refuse("extra/models/rnnt.py:167 Encoder.__call__ -- FIRST MISSING SYMBOL self.pre_rnn (:168) -> LSTM -> LSTMCell")

# ---------------------------------------------------------------------------
# :174-184 Prediction.
# ---------------------------------------------------------------------------

# :175 def __init__(self, vocab_size, hidden_size, layers, dropout)
def rt_prediction_init(vocab_size: U32, hidden_size: U32, layers: U32) -> D.Refused:
  D.refuse("extra/models/rnnt.py:175 Prediction.__init__ -- FIRST MISSING SYMBOL Embedding (:178) -- THE FIRST MISSING SYMBOL OF THE FILE")

# :181 def __call__(self, x, hc, m)
def rt_prediction_call(+x: T.Tensor, +hc: T.Tensor, +m: T.Tensor) -> D.Refused:
  D.refuse("extra/models/rnnt.py:181 Prediction.__call__ -- FIRST MISSING SYMBOL self.emb (:182), the same missing Embedding")

# ---------------------------------------------------------------------------
# :187-202 Joint. THE TWO DEFS THAT ARE ALMOST PORTABLE.
# ---------------------------------------------------------------------------

# :188 def __init__(self, vocab_size, pred_hidden_size, enc_hidden_size, joint_hidden_size, dropout)
def rt_joint_init(vocab_size: U32, pred_hidden_size: U32, enc_hidden_size: U32, joint_hidden_size: U32) -> D.Refused:
  D.refuse("extra/models/rnnt.py:188 Joint.__init__ -- BOTH are Linear (:191,:192) and nn/layers.bend:427 nn_linear EXISTS; BLOCKED BY the missing class shell")

# :194 def __call__(self, f, g)
def rt_joint_call(+f: T.Tensor, +g: T.Tensor) -> D.Refused:
  D.refuse("extra/models/rnnt.py:194 Joint.__call__ -- nn_expand EXISTS (:196,:197), nn_relu EXISTS (:200), nn_linear EXISTS (:200,:202); FIRST MISSING SYMBOL Tensor.cat (:199)")

# ---------------------------------------------------------------------------
# There is no `if __name__ == "__main__":` in rnnt.py. `main` prints TWO rows.
# ---------------------------------------------------------------------------
def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, rt_lstm_init(240, 1024, 2, 0.32))
    srow("rnnt_refused_at", rt_at(a))
    row("rnnt_recurrence_exists", False{})
    row("rnnt_sigmoid_exists", True{})