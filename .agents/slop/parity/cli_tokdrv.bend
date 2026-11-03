# cli_tokdrv.bend -- GENERATED-STYLE differential driver for `Tokenizer.decode` and `.is_end`.
#
# The vocabulary is a STUB: three token ids with multi-byte UTF-8 payloads, so the port's `utf8.of` is
# exercised across a 2-byte and a 4-byte code point, and one id (99) that is ABSENT -- upstream raises
# `KeyError` there and the port answers `None`, which prints as NONE.
#
# `IO.print` APPENDS A NEWLINE, so no payload carries one.
import Base
import ../../../tinybendygrad/llm/cli.bend as C

def vocab() -> List<&2, C.Tok>:
  [C.Tok{0, [104, 195, 169]}, C.Tok{1, [108, 108, 111]}, C.Tok{2, [240, 159, 153, 130]}]

def ends() -> List<&2, U32>: [0, 3]

def dec(+tag: String, +ids: List<&2, U32>) -> IO(Unit):
  IO.print(String.concat([tag, "\t", Maybe.default(&1, String, C.Tokenizer.decode(vocab(), ids), "NONE")]))

def end(+tid: U32) -> IO(Unit):
  IO.print(String.concat(["end/", U32.show(tid), "\t",
    Bool.pick(String, C.Tokenizer.is_end(ends(), tid), "True", "False")]))

def main() -> IO(Unit):
  do IO<Unit>:
    dec("dec/0,1", [0, 1])
    dec("dec/2", [2])
    dec("dec/empty", Nil{})
    dec("dec/0,2,1", [0, 2, 1])
    dec("dec/missing", [0, 99])
    end(0)
    end(3)
    end(1)
    end(4)
    end(99)
