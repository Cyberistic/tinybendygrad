# T4 -- may a def call a def declared BELOW it?
import Base

def a() -> U32: b()

def b() -> U32: 1

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(U32.show(a()))
    IO.print("")
