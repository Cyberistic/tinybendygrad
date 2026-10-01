import Base
import ./../../tinybendygrad/LAWS/spec.bend as S
import ./../../tinybendygrad/dtype.bend as DT
import ./../../tinybendygrad/uop/ops.bend as O
import ./../../tinybendygrad/tensor.bend as T

type SEntry is Data:
  SEntry{k: String, t: T.Tensor}

type SObj is Data:
  STensor{t: T.Tensor}
  SNamed{items: List<&2, SEntry>}
  SAttrs{items: List<&2, SEntry>}
  SSeq{items: List<&2, SObj>}
  SMap{items: List<&2, SEntry>}
  SPlain{}

def st_key(e: SEntry) -> String:
  match e:
    case SEntry{k, t}: k

def st_keys.go(+es: List<&2, SEntry>, acc: String) -> String:
  match es:
    case Nil{}: acc
    case e <> +t: st_keys.go(t, String.append(acc, String.append(st_key(e), ",")))

def main() -> IO(Unit): IO.print("ok")
