import Base
import ./../../tinybendygrad/helpers.bend as H

def cx_df(f: H.Flags) -> String:
  match f:
    case H.Flags{nc, df, di, sd}: df

def cx_di(f: H.Flags) -> String:
  match f:
    case H.Flags{nc, df, di, sd}: di

def cx_nc(f: H.Flags) -> U32:
  match f:
    case H.Flags{nc, df, di, sd}: Bool.to_u32(nc)

def p(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

def boot_rows(+f0: H.Flags) -> IO(Unit):
  do IO<Unit>:
    p("ctx_boot_df", cx_df(f0))
    p("ctx_boot_di", cx_di(f0))
    p("ctx_nc", U32.show(cx_nc(f0)))

def two_rows(+a: H.Flags, +b: H.Flags) -> IO(Unit):
  do IO<Unit>:
    p("a_df", cx_df(a))
    p("a_di", cx_di(a))
    p("b_df", cx_df(b))

def main() -> IO(Unit):
  do IO<Unit>:
    f : H.Flags <- H.Flags.from_env()
    boot_rows(f)