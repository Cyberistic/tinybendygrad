import Base
import ../../../tinybendygrad/runtime/ops_webgpu.bend as W

def main() -> IO(Unit):
  do IO<Unit>:
    xs : List<&2, U32> <- IO.pure(List<&2, U32>, W.bgl.flat(W.bgl.of(3, 1), Nil{}))
    a : Unit <- IO.print("flat=" ++ U32.show(W.backend_of("WGPUBackendType_Metal")))
    b : Unit <- IO.print(U32.show(W.QUERY_BUF_SIZE()))
    c : Unit <- IO.print(String.join(H_dummy(xs), ","))
    d : Unit <- IO.print(U32.show(W.UNIFORM_SIZE()))
    e : Unit <- IO.print(U32.show(xs_len(xs)))
    return a

def H_dummy(xs: List<&2, U32>) -> List<&2, String>: Nil{}
def xs_len(xs: List<&2, U32>) -> U32: U32.from_nat(List.length(&2, U32, xs))
