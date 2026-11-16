# gates/test_pkl_imagenet-gate.bend -- the gate driver for `tinybendygrad/examples/test_pkl_imagenet.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/examples/test_pkl_imagenet.bend as P

import ./../tinybendygrad/tensor.bend as T
import ./../tinybendygrad/helpers.bend as H
import ./../tinybendygrad/LAWS/spec.bend as S
import ./../tinybendygrad/nn/state.bend as ST
import ./../tinybendygrad/nn/onnx.bend as ONNX
import ./../tinybendygrad/engine/jit.bend as JIT
import ./../tinybendygrad/extra/datasets/__init__.bend as D
def srow(nm: String, v: String) -> IO(Unit): IO.print(String.concat([nm, "=", v]))
def row(nm: String, b: Bool) -> IO(Unit): IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit): IO.print(String.concat([nm, "=", U32.show(v)]))

def pkl_at(r: D.Refused) -> String:
  match r:
    case D.Refused{at}: at

# :7   with open(fetch(sys.argv[1]), "rb") as f:
# two missing symbols in one line, in this order: `sys.argv` (no argv reader)
# and `fetch` (no def). The second is the wall that also blocks the unpickler,
# because there is no byte source either.

def pkl_open(path: String) -> D.Refused:
  D.refuse("examples/test_pkl_imagenet.py:7 FIRST MISSING SYMBOL fetch -- grep -c '^def fetch(' = 0; helpers.bend:2694 symbol=lines is that file's ONLY I/O construct, so the HTTP machinery (fetch, fetch_fw, _ensure_downloads_dir) is NOT ported")

# :8   run_onnx_jit = pickle.load(f)
def pkl_load() -> D.Refused:
  D.refuse("examples/test_pkl_imagenet.py:8 FIRST MISSING SYMBOL pickle -- NO UNPICKLER EXISTS; helpers.bend:2694 symbol=lines is that file's ONLY I/O construct and it reads LINES, so the sqlite disk cache (whose values are pickle) is NOT ported: Bend has no pickle and no object graph")

# :9   input_name = run_onnx_jit.captured.expected_names[0]
# The RECORD EXISTS (InInfo engine/jit.bend:376 symbol=InInfo, ii_vars engine/jit.bend:383
# symbol=InInfo.vars); the object does not.
def pkl_input_name() -> D.Refused:
  D.refuse("examples/test_pkl_imagenet.py:9 BLOCKED ON pickle.load; engine/jit.bend:376 symbol=InInfo and engine/jit.bend:387 symbol=InInfo.dt hold expected_input_info but the object does not")

# :10  device = run_onnx_jit.captured.expected_input_info[0][-1]
def pkl_device() -> D.Refused:
  D.refuse("examples/test_pkl_imagenet.py:10 BLOCKED ON pickle.load; InInfo.dev engine/jit.bend:391 symbol=InInfo.dev exists but the object does not")

# :13  for i,(img,y) in enumerate(imagenet_dataloader(cnt=getenv("CNT", 100))):
# `getenv("CNT", 100)` IS PORTED -- helpers.bend:304 symbol=getenv_int `getenv_int` is the typed
# spelling of exactly this call -- and the dataloader is not.
def pkl_dataloader(cnt: U32) -> D.Refused:
  D.refuse("examples/test_pkl_imagenet.py:13 FIRST MISSING SYMBOL imagenet_dataloader (examples/test_onnx_imagenet.py:25); nn/datasets.bend has no imagenet table")

# :15  p = run_onnx_jit({input_name: img.to(device)})
def pkl_run() -> D.Refused:
  D.refuse("examples/test_pkl_imagenet.py:15 BLOCKED ON OnnxRunner -- nn/onnx.bend STAGE 3 NOT DONE, and STAGE 4's 167 op bodies NOT DONE. THE PORTED HALF IS nn/onnx.bend:507 symbol=onx_dom (the STAGE 2 Domain table); THERE IS NO `OnnxRunner` DEF IN THE PORT -- IT IS ONNX.py:294 symbol=OnnxRunner.__init__ UPSTREAM")

# :17  t = p.to('cpu').argmax().item()
def pkl_predict() -> D.Refused:
  D.refuse("examples/test_pkl_imagenet.py:17 FIRST MISSING SYMBOL Tensor.argmax -- grep -c '^def mo_argmax' = 0; the eval loop cannot produce a prediction")

# :18  hit += y == t
def pkl_score() -> D.Refused:
  D.refuse("examples/test_pkl_imagenet.py:18 BLOCKED ON Tensor.item (0 non-renderer defs) and Tensor.to (mixin/movement.bend wall list)")

# :6-19 `if __name__ == "__main__":`. `main` below mirrors it and NOTHING ELSE.
# The bodies are in upstream line order, so the first refusal a caller sees is
# the FIRST missing symbol (:7 `fetch`) and not the biggest one (:8 `pickle`).

def main() -> IO(Unit):
  do IO<Unit>:
    a : D.Refused <- IO.pure(D.Refused, pkl_load())
    srow("test_pkl_imagenet_refused_at", pkl_at(a))
    row("test_pkl_imagenet_ported", False{})
