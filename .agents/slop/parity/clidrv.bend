# clidrv.bend -- GENERATED differential driver for tinybendygrad/llm/cli.bend.
# Prints (preset/role, value) for every preset x role plus end_turn, one row per line.
# `IO.print` APPENDS A NEWLINE (MEASURED), so the payload carries none; role values that end in
# "\n\n" therefore produce their own blank line, exactly as upstream's print does.
import Base
import ../../../tinybendygrad/llm/cli.bend as C

def role_of(+pr: U32, +r: String) -> String:
  Maybe.default(&1, String, C.Template.role(pr, r), "RAISE")

def main() -> IO(Unit):
  do IO<Unit>:
    IO.print(String.concat(["llama/user\t", role_of(0, "user")]))
    IO.print(String.concat(["llama/assistant\t", role_of(0, "assistant")]))
    IO.print(String.concat(["llama/system\t", role_of(0, "system")]))
    IO.print(String.concat(["llama/end_turn\t", C.Template.end_turn(0, "EOS")]))
    IO.print(String.concat(["olmo/user\t", role_of(1, "user")]))
    IO.print(String.concat(["olmo/assistant\t", role_of(1, "assistant")]))
    IO.print(String.concat(["olmo/system\t", role_of(1, "system")]))
    IO.print(String.concat(["olmo/end_turn\t", C.Template.end_turn(1, "EOS")]))
    IO.print(String.concat(["kimi/user\t", role_of(2, "user")]))
    IO.print(String.concat(["kimi/assistant\t", role_of(2, "assistant")]))
    IO.print(String.concat(["kimi/system\t", role_of(2, "system")]))
    IO.print(String.concat(["kimi/end_turn\t", C.Template.end_turn(2, "EOS")]))
    IO.print(String.concat(["qwen2/user\t", role_of(3, "user")]))
    IO.print(String.concat(["qwen2/assistant\t", role_of(3, "assistant")]))
    IO.print(String.concat(["qwen2/system\t", role_of(3, "system")]))
    IO.print(String.concat(["qwen2/end_turn\t", C.Template.end_turn(3, "EOS")]))
    IO.print(String.concat(["glm4/user\t", role_of(4, "user")]))
    IO.print(String.concat(["glm4/assistant\t", role_of(4, "assistant")]))
    IO.print(String.concat(["glm4/system\t", role_of(4, "system")]))
    IO.print(String.concat(["glm4/end_turn\t", C.Template.end_turn(4, "EOS")]))
    IO.print(String.concat(["tekken/user\t", role_of(5, "user")]))
    IO.print(String.concat(["tekken/assistant\t", role_of(5, "assistant")]))
    IO.print(String.concat(["tekken/system\t", role_of(5, "system")]))
    IO.print(String.concat(["tekken/end_turn\t", C.Template.end_turn(5, "EOS")]))
