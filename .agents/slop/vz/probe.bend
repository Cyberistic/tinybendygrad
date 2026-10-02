import Base
import ../../tinybendygrad/helpers.bend as H
import ../../tinybendygrad/LAWS/spec.bend as S

def main() -> IO(Unit):
  IO.print("split=[" ++ String.concat(["|", String.split("a:b c", " ")]) ++ "]")
  IO.print("sw=[" ++ String.concat(["|", String.split_with("a:b:c", ":")]) ++ "]")
  IO.print("sw2=[" ++ String.concat(["|", String.split_with("a:b:c", "")]) ++ "]")
  IO.print("sw3=[" ++ String.concat(["|", String.split_with("LINE:X", "LINE:")]) ++ "]")
  IO.print("swm=[" ++ String.concat(["|", String.split_many(":")("a:b:c")]) ++ "]")
  IO.print("startswith=" ++ U32.show(Bool.to_u32(String.starts_with("LINE:abc", "LINE:"))))
  IO.print("endswith=" ++ U32.show(Bool.to_u32(String.ends_with("LINE:abc", "LINE:"))))
  IO.print("join=" ++ String.join(["a","b"], ","))
  IO.print("I64=" ++ H.I64.show(H.I64.i64_of_i32(7)))
  IO.print("hexdig_str2=" ++ hex_str2([255u32, 0u32, 16u32]))
  IO.print("trim=[" ++ String.trim("  x  ") ++ "]")
  IO.print("replace=[" ++ String.replace_all("a:b", ":", "") ++ "]")
