# gates/models-rnnt-gate.bend -- the gate driver for `tinybendygrad/extra/models/rnnt.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/extra/models/rnnt.bend as P

import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/dtype.bend as DT
import ./../tinybendygrad/nn/__init__.bend as NN
import ./../tinybendygrad/nn/state.bend as ST
import ./../tinybendygrad/nn/layers.bend as LN
import ./../tinybendygrad/mixin/op.bend as MO
import ./../tinybendygrad/mixin/movement.bend as MX
import ./../tinybendygrad/mixin/reduce.bend as RC
import ./../tinybendygrad/mixin/elementwise.bend as EW
import ./../tinybendygrad/mixin/creation.bend as CR
import ./../tinybendygrad/mixin/rand.bend as RD
import ./../tinybendygrad/nn/optim.bend as OPT
import ./../tinybendygrad/extra/datasets/__init__.bend as D
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))

def rt_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# :9-94 RNNT.

# :10 def __init__(self, input_features=240, vocab_size=29, enc_hidden_size=1024, pred_hidden_size=320, joint_hidden_size=512, pre_enc_layers=2, post_enc_layers=3, pred_layers=2, stack_time_factor=2, dropout=0.32)
def rt_rnnt_init(input_features: U32, vocab_size: U32, enc_hidden_size: U32, pred_hidden_size: U32,
  joint_hidden_size: U32, pre_enc_layers: U32, post_enc_layers: U32, pred_layers: U32,
  stack_time_factor: U32, dropout: F32) -> D.Refused:
  D.refuse("extra/models/rnnt.py:10 RNNT.__init__ -- FIRST MISSING SYMBOL Encoder (:11) -> LSTM (:119) -> LSTMCell (:97); recurrence has no counterpart anywhere in tinybendygrad/")

# :15-16 @TinyJit / def __call__(self, x, y, hc=None)
def rt_rnnt_call(+x: T.Tensor, +y: T.Tensor) -> D.Refused:
  D.refuse("extra/models/rnnt.py:16 RNNT.__call__ -- FIRST MISSING SYMBOL TinyJit (:15); THE PORT's `extra/models/resnet.bend` HEADER measures this as PARTIAL -- engine/jit.bend is a port and the NAME is not")

# :22 def decode(self, x, x_lens)
def rt_rnnt_decode(+x: T.Tensor, x_lens: Maybe<&2, T.Tensor>) -> D.Refused:
  D.refuse("extra/models/rnnt.py:22 RNNT.decode -- FIRST MISSING SYMBOL Tensor.numpy (:28), the device-state seam THE PORT's `mixin/op.bend` HEADER names")

# :32 def _greedy_decode(self, logits, logit_len)
def rt_greedy_decode(+logits: T.Tensor, logit_len: U32) -> D.Refused:
  D.refuse("extra/models/rnnt.py:32 _greedy_decode -- FIRST MISSING SYMBOL Tensor.numpy (:45); the inner loop is also bounded by the literal 30 at :41 and by `labels` being a Python list that a Tensor indexes (:44)")

# :55 def _pred_joint(self, logit, label, hc, mask)
def rt_pred_joint(+logit: T.Tensor, +label: T.Tensor, +hc: T.Tensor, +mask: T.Tensor) -> D.Refused:
  D.refuse("extra/models/rnnt.py:55 _pred_joint -- FIRST MISSING SYMBOL self.prediction (:56) -> LSTM -> LSTMCell")

# :62 def load_from_pretrained(self)
def rt_rnnt_load_from_pretrained() -> D.Refused:
  D.refuse("extra/models/rnnt.py:62 RNNT.load_from_pretrained -- FIRST MISSING SYMBOL fetch (:64); THE PORT's `helpers.bend` HEADER records the HTTP seam as unported. The 33 `.assign` lines at :72-94 are torch-checkpoint loads, not arithmetic")

# :97-115 LSTMCell. THE RECURRENCE WALL, SPELLED OUT.

# :98 def __init__(self, input_size, hidden_size, dropout)
def rt_cell_init(input_size: U32, hidden_size: U32, dropout: F32) -> D.Refused:
  D.refuse("extra/models/rnnt.py:98 LSTMCell.__init__ -- REACHED: all four weights are Tensor.uniform, mixin/rand.bend:918 symbol=rd_uniform EXISTS (:101-104). BLOCKED BY: the missing class shell only -- this def's ARITHMETIC IS PORTED")

# :106 def __call__(self, x, hc)
def rt_cell_call(+x: T.Tensor, +hc: T.Tensor) -> D.Refused:
  D.refuse("extra/models/rnnt.py:106 LSTMCell.__call__ -- FIRST MISSING SYMBOL Tensor.chunk (:109); x.linear (:107) EXISTS, sigmoid/tanh (:110) EXIST at mixin/elementwise.bend:1173 symbol=g_unary/:1232, and Tensor.cat (:115) is MISSING")

# :118-148 LSTM.

# :119 def __init__(self, input_size, hidden_size, layers, dropout)
def rt_lstm_init(input_size: U32, hidden_size: U32, layers: U32, dropout: F32) -> D.Refused:
  D.refuse("extra/models/rnnt.py:119 LSTM.__init__ -- FIRST MISSING SYMBOL LSTMCell (:124); `self.cells` is a LIST of them, and a list of sub-models is the shape nn/__init__.bend:21-32 settled on for `*_st` defs")

# :126 def __call__(self, x, hc)
def rt_lstm_call(+x: T.Tensor, +hc: Maybe<&2, T.Tensor>) -> D.Refused:
  D.refuse("extra/models/rnnt.py:126 LSTM.__call__ -- FIRST MISSING SYMBOL TinyJit on the INNER _do_step (:127,:128); the time loop (:135) is Python control flow, not a graph")

# :144 def do_step(self, x, hc)
def rt_lstm_do_step(+x: T.Tensor, +hc: T.Tensor) -> D.Refused:
  D.refuse("extra/models/rnnt.py:144 LSTM.do_step -- FIRST MISSING SYMBOL LSTMCell.__call__ (:147) -> Tensor.chunk; Tensor.stack (:148) EXISTS at mixin/movement.bend:1252 symbol=mxw_stk.done")

# :151-158 StackTime.

# :152 def __init__(self, factor)
def rt_stacktime_init(factor: U32) -> U32: factor

# :155 def __call__(self, x, x_lens)
def rt_stacktime_call(+x: T.Tensor, x_lens: Maybe<&2, T.Tensor>) -> D.Refused:
  D.refuse("extra/models/rnnt.py:155 StackTime.__call__ -- mxw_pad EXISTS (:156) and mxw_reshape EXISTS (:157); BLOCKED BY the two-tuple return (:158), which carries an Option")

# :161-171 Encoder.

# :162 def __init__(self, input_size, hidden_size, pre_layers, post_layers, stack_time_factor, dropout)
def rt_encoder_init(input_size: U32, hidden_size: U32, pre_layers: U32, post_layers: U32, stack_time_factor: U32) -> D.Refused:
  D.refuse("extra/models/rnnt.py:162 Encoder.__init__ -- FIRST MISSING SYMBOL LSTM (:163)")

# :167 def __call__(self, x, x_lens)
def rt_encoder_call(+x: T.Tensor, x_lens: Maybe<&2, T.Tensor>) -> D.Refused:
  D.refuse("extra/models/rnnt.py:167 Encoder.__call__ -- FIRST MISSING SYMBOL self.pre_rnn (:168) -> LSTM -> LSTMCell")

# :174-184 Prediction.

# :175 def __init__(self, vocab_size, hidden_size, layers, dropout)
def rt_prediction_init(vocab_size: U32, hidden_size: U32, layers: U32) -> D.Refused:
  D.refuse("extra/models/rnnt.py:175 Prediction.__init__ -- FIRST MISSING SYMBOL Embedding (:178) -- THE FIRST MISSING SYMBOL OF THE FILE")

# :181 def __call__(self, x, hc, m)
def rt_prediction_call(+x: T.Tensor, +hc: T.Tensor, +m: T.Tensor) -> D.Refused:
  D.refuse("extra/models/rnnt.py:181 Prediction.__call__ -- FIRST MISSING SYMBOL self.emb (:182), the same missing Embedding")

# :187-202 Joint. the two defs that are almost portable.

# :188 def __init__(self, vocab_size, pred_hidden_size, enc_hidden_size, joint_hidden_size, dropout)
def rt_joint_init(vocab_size: U32, pred_hidden_size: U32, enc_hidden_size: U32, joint_hidden_size: U32) -> D.Refused:
  D.refuse("extra/models/rnnt.py:188 Joint.__init__ -- BOTH are Linear (:191,:192) and nn/layers.bend:518 symbol=nn_linear EXISTS; BLOCKED BY the missing class shell")

# :194 def __call__(self, f, g)
def rt_joint_call(+f: T.Tensor, +g: T.Tensor) -> D.Refused:
  D.refuse("extra/models/rnnt.py:194 Joint.__call__ -- nn_expand EXISTS (:196,:197), nn_relu EXISTS (:200), nn_linear EXISTS (:200,:202); FIRST MISSING SYMBOL Tensor.cat (:199)")

# There is no `if __name__ == "__main__":` in rnnt.py. `main` prints TWO rows.

def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, rt_lstm_init(240, 1024, 2, 0.32))
    srow("rnnt_refused_at", rt_at(a))
    row("rnnt_recurrence_exists", False{})
    row("rnnt_sigmoid_exists", True{})
