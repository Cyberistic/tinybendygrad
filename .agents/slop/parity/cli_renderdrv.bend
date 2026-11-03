# cli_renderdrv.bend -- differential driver for `FallbackTemplate.render` in `tinybendygrad/llm/cli.bend`.
#
# WHY THE LINES ARE ESCAPED: every chat template's role string ENDS IN NEWLINES, so printing the rendered
# text raw would make a line-based diff compare fragments. `esc` maps '\n' to '|' and leaves everything
# else, and the oracle does the same substitution -- so a row IS the rendered text.
#
# THE VOCABULARY IS A STUB: `bos` and `eos` are DECODED strings passed in, which is the seam the port
# takes them through because `SimpleTokenizer.encode` needs a regex engine (see cli.bend's header).
#
# `IO.print` APPENDS A NEWLINE.
import Base
import ../../../tinybendygrad/llm/cli.bend as C

def esc(+cs: List<&2, Char>, acc: String) -> String:
  match cs:
    case Nil{}: acc
    case h <> t:
      esc(t, String.concat([acc, Bool.pick(String, U32.is_eq(Char.to_u32(h), 10),
        "|", Char.show(h))]))

def esc.str(+s: String) -> String: esc(String.to_list(s), "")

def esc.maybe(m: Maybe<&1, String>) -> String:
  match m:
    case None{}: "NONE"
    case Some{s}: esc.str(s)

def show(+name: String, m: Maybe<&1, String>) -> IO(Unit):
  IO.print(String.concat([name, "\t", esc.maybe(m)]))

def go(+name: String, +preset: U32, +bos: String, +eos: String, +msgs: List<&2, C.Msg>,
  +gen: Bool) -> IO(Unit):
  show(name, C.Template.render(preset, bos, eos, msgs, gen))

def conv() -> List<&2, C.Msg>:
  [C.Msg{"user", C.CText{"hi"}}, C.Msg{"assistant", C.CText{"yo"}}]

def main() -> IO(Unit):
  do IO<Unit>:
    go("llama", C.Preset.llama(), "", "EOS", conv(), True{})
    go("olmo", C.Preset.olmo(), "", "EOS", conv(), True{})
    go("kimi", C.Preset.kimi_k2(), "", "EOS", conv(), True{})
    go("qwen2", C.Preset.qwen2(), "", "EOS", conv(), True{})
    go("glm4", C.Preset.glm4(), "", "EOS", conv(), True{})
    go("tekken_user", C.Preset.tekken(), "", "EOS",
       [C.Msg{"user", C.CText{"hi"}}], True{})
    go("tekken_system", C.Preset.tekken(), "", "EOS",
       [C.Msg{"system", C.CText{"hi"}}], True{})
    go("parts", C.Preset.llama(), "", "EOS",
       [C.Msg{"user", C.CParts{"ab"}}], True{})
    go("none", C.Preset.llama(), "", "EOS", [C.Msg{"user", C.CEmpty{}}], True{})
    go("badpart", C.Preset.llama(), "", "EOS",
       [C.Msg{"user", C.CBad{"image"}}], True{})
    go("nogen", C.Preset.llama(), "", "EOS", conv(), False{})
    go("bos", C.Preset.llama(), "BOS", "EOS", conv(), True{})
