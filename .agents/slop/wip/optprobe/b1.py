import os, sys
os.environ["DEV"] = "PYTHON"
os.environ["IGNORE_BEAM_CACHE"] = "1"
os.environ["CACHELEVEL"] = "0"
os.environ["DEBUG"] = "2"
from tinygrad import Tensor
from tinygrad.helpers import Context
case = sys.argv[1]
with Context(BEAM=1):
  if case == "plus":
    a = Tensor([1.0,2.0,3.0,4.0]).contiguous().realize()
    print("RESULT", (a+1).realize().tolist())
  elif case == "reduce":
    a = Tensor.empty(16,32).realize(); b = Tensor.empty(16,32).realize()
    print("RESULT", (a*b).sum(axis=1).realize().tolist()[:2])
  elif case == "matmul":
    a = Tensor.empty(64,64).realize(); b = Tensor.empty(64,64).realize()
    print("RESULT", (a@b).realize().tolist()[0][:2])
