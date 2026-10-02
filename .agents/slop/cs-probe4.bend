import Base

def sp.join(xs: List<&2, String>) -> String: String.join(xs, "|")
def sp.n(xs: List<&2, String>) -> U32: U32.from_nat(List.length(&2, String, xs))

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["p_empty=[", sp.join(String.split("", ' ')), "] n=", U32.show(sp.n(String.split("", ' ')))]))
    IO.print(String.concat(["p_two=[", sp.join(String.split("-O3 -mcumode", ' ')), "] n=", U32.show(sp.n(String.split("-O3 -mcumode", ' ')))]))
    IO.print(String.concat(["p_dbl=[", sp.join(String.split("a  b", ' ')), "] n=", U32.show(sp.n(String.split("a  b", ' ')))]))
    IO.print(String.concat(["p_spaces=[", sp.join(String.split("  ", ' ')), "] n=", U32.show(sp.n(String.split("  ", ' ')))]))
    IO.print(String.concat(["p_lead=[", sp.join(String.split(" lead", ' ')), "] n=", U32.show(sp.n(String.split(" lead", ' ')))]))
    IO.print(String.concat(["p_trail=[", sp.join(String.split("trail ", ' ')), "] n=", U32.show(sp.n(String.split("trail ", ' ')))]))
    IO.print(String.concat(["p_tab=[", sp.join(String.split("a\tb", ' ')), "] n=", U32.show(sp.n(String.split("a\tb", ' ')))]))
    IO.print(String.concat(["p_one=[", sp.join(String.split("solo", ' ')), "] n=", U32.show(sp.n(String.split("solo", ' ')))]))
    IO.print(String.concat(["p_nl=[", sp.join(String.split(".text\nfoo", '\n')), "] n=", U32.show(sp.n(String.split(".text\nfoo", '\n')))]))
    IO.print(String.concat(["p_nl2=[", sp.join(String.split("\n.text", '\n')), "] n=", U32.show(sp.n(String.split("\n.text", '\n')))]))
    IO.print(String.concat(["p_nl3=[", sp.join(String.split("x\n\ny", '\n')), "] n=", U32.show(sp.n(String.split("x\n\ny", '\n')))]))
    IO.print(String.concat(["p_comma=[", sp.join(String.split("a630,x", ',')), "] n=", U32.show(sp.n(String.split("a630,x", ',')))]))
    IO.print(String.concat(["p_colon=[", sp.join(String.split("mod:Name", ':')), "] n=", U32.show(sp.n(String.split("mod:Name", ':')))]))
    IO.print("probe4-done=1")
