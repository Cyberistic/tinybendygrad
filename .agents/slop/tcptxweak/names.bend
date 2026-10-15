import ../../../tinybendygrad/LAWS/spec.bend as S
import ../../../tinybendygrad/renderer/tc.bend as T

def row1(+nm: String, +dt: S.Dt) -> String:
  String.concat([nm, "|", T.dt_name(dt), "|", U32.show(S.Dt.pri(dt)), "\n"])

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([row1("void", S.void()), row1("bool", S.boolean()), row1("i8", S.int8()),
      row1("u8", S.uint8()), row1("i16", S.int16()), row1("u16", S.uint16()), row1("i32", S.int32()),
      row1("u32", S.uint32()), row1("i64", S.int64()), row1("u64", S.uint64()),
      row1("weakint", S.weakint()), row1("weakfloat", S.weakfloat()), row1("f16", S.half()),
      row1("bf16", S.bfloat16()), row1("f32", S.single()), row1("f64", S.double()),
      row1("fp8e4m3", S.fp8e4m3()), row1("fp8e4m3fnuz", S.fp8e4m3fnuz()), row1("fp8e5m2", S.fp8e5m2()),
      row1("fp8e5m2fnuz", S.fp8e5m2fnuz())]))