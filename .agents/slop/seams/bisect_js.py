#!/usr/bin/env python3
"""bisect_js.py -- generate TRUNCATED variants of kernel_mnist.bend, one per
stage, so a lane's cost can be ATTRIBUTED rather than guessed.

    .venv/bin/python .agents/slop/seams/bisect_js.py

Each variant keeps the same defs and replaces `main` with one that stops after
a named stage.  The variants are written beside the kernel, under names that
say what they compute.
"""
import pathlib

HERE = pathlib.Path(__file__).resolve().parent
SRC = (HERE / "kernel_mnist.bend").read_text()

HEAD = SRC[: SRC.index("def main() -> IO(Unit):")]

COMPUTE = '''    +wb : List<&2, U32> <- read_bytes(WS(), 17064)
    +ib : List<&2, U32> <- read_bytes(IS(), 784)
    +w : List<&2, F32> = List.reverse(&2, F32, to_floats(wb, Nil{}))
    +im : List<&2, F32> = List.reverse(&2, F32, to_units(ib, Nil{}))
    +c1 : List<&2, F32> = conv1(w, im)
    +r1 : List<&2, F32> = relu(3136n, c1)
    +p1 : List<&2, F32> = pool1(784n, r1)
    +c2 : List<&2, F32> = conv2(w, p1)
    +r2 : List<&2, F32> = relu(1568n, c2)
    +p2 : List<&2, F32> = pool2(392n, r2)
    +lg : List<&2, F32> = fc(w, p2)
'''

STAGES = {
    "read": '''
    +wb : List<&2, U32> <- read_bytes(WS(), 17064)
    +ib : List<&2, U32> <- read_bytes(IS(), 784)
    +w : List<&2, F32> = List.reverse(&2, F32, to_floats(wb, Nil{}))
    +im : List<&2, F32> = List.reverse(&2, F32, to_units(ib, Nil{}))
    IO.print(String.concat(["read w0=", F32.show(fget(w, 0n)), " im0=", F32.show(fget(im, 0n))]))
''',
    "conv1": COMPUTE[: COMPUTE.index("    +r1 :")].replace(
        "    +lg : List<&2, F32> = fc(w, p2)\n", "") + '''
    IO.print(String.concat(["conv1 done"]))
''',
    "conv1write": COMPUTE[: COMPUTE.index("    +r1 :")].replace(
        "    +lg : List<&2, F32> = fc(w, p2)\n", "") + '''
    +o1 : Unit <- write_bytes(OS(), "w", bytes_of(c1, 3136n))
    IO.print(String.concat(["conv1 written"]))
''',
    "pool1": COMPUTE[: COMPUTE.index("    +c2 :")].replace(
        "    +lg : List<&2, F32> = fc(w, p2)\n", "") + '''
    IO.print(String.concat(["pool1 done"]))
''',
    "conv2": COMPUTE[: COMPUTE.index("    +r2 :")].replace(
        "    +lg : List<&2, F32> = fc(w, p2)\n", "") + '''
    IO.print(String.concat(["conv2 done"]))
''',
    "fc": COMPUTE + '''
    IO.print(String.concat(["fc done"]))
''',
    "compute": COMPUTE + '''
    +s : String = show_logits(10n, lg, "")
    IO.print(String.concat(["compute done", s]))
''',
    "write1": COMPUTE + '''
    +s : String = show_logits(10n, lg, "")
    +o1 : Unit <- write_bytes(OS(), "w", bytes_of(c1, 3136n))
    IO.print(String.concat(["write1 done", s]))
''',
    "write8": COMPUTE + '''
    +s : String = show_logits(10n, lg, "")
    +o1 : Unit <- write_bytes(OS(), "w", bytes_of(c1, 3136n))
    +o2 : Unit <- write_bytes(OS(), "a", bytes_of(r1, 3136n))
    +o3 : Unit <- write_bytes(OS(), "a", bytes_of(p1, 784n))
    +o4 : Unit <- write_bytes(OS(), "a", bytes_of(c2, 1568n))
    +o5 : Unit <- write_bytes(OS(), "a", bytes_of(r2, 1568n))
    +o6 : Unit <- write_bytes(OS(), "a", bytes_of(p2, 392n))
    +o7 : Unit <- write_bytes(OS(), "a", bytes_of(p2, 392n))
    +o8 : Unit <- write_bytes(OS(), "a", bytes_of(lg, 10n))
    IO.print(String.concat(["write8 done", s]))
''',
}


def main() -> int:
    for name, body in STAGES.items():
        text = HEAD + "\ndef main() -> IO(Unit):\n  do IO<Unit>:" + body
        (HERE / f"jsvar_{name}.bend").write_text(text)
        print(f"jsvar_{name}.bend")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
