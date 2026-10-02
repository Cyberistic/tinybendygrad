import Base

def sel(p: U32) -> String:
  match p:
    case 0:  "a"
    case 1:  "b"
    case 2:  "c"
    case 3:  "d"
    case 5:  "f"
    case 7:  "h"
    case 8:  "i"
    case 12: "m"
    case 14: "o"
    case 15: "p"
    case _:   "z"

def sel_desc(p: U32) -> String:
  match p:
    case 15: "p"
    case 14: "o"
    case 12: "m"
    case 8:  "i"
    case 7:  "h"
    case 5:  "f"
    case 3:  "d"
    case 2:  "c"
    case 1:  "b"
    case 0:  "a"
    case _:   "z"

def one(s: String) -> String:
  match s:
    case "p0": "n0"
    case "p1": "n1"
    case _   : "other"

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat([sel(0), sel(1), sel(2), sel(3), sel(4), sel(5), sel(8), sel(12), sel(15), sel(99),
      " | ", sel_desc(0), sel_desc(1), sel_desc(2), sel_desc(3), sel_desc(12), sel_desc(15),
      " | ", one("p0"), one("p1"), one("px")]))
