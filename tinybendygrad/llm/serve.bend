# tinybendygrad/llm/serve.bend -- port of tinygrad/llm/serve.py
#
# partial, and the split is the point. `llm/serve.py` is 176 lines in four pieces:
#
#   1. `StreamRouter` -- PORTED HERE. A pure string state machine: it splits streamed text on
#      `<think>` / `</think>` / `<tool_call>` and yields `(field, text)` deltas. No regex, no JSON, no I/O.
#   2. `parse_tool_call` -- NOT PORTABLE AS WRITTEN. Two `re.match`/`re.finditer` patterns (DOTALL) over a
#      JSON body plus `json.loads` per argument. Bend has neither a regex engine nor a JSON parser, so
#      this needs a hand-written matcher and decoder; it is the same class of gap as
#      `SimpleTokenizer.encode` (see `cli.bend`'s header).
#   3. `normalize_messages` -- mutates a caller's dicts (joins text parts, empties null content). Needs a
#      mutable message representation; it ports with the JSON layer, not before it.
#   4. `Handler` / `LLMServer` -- `http.server`, `uuid`, `time`, and `model.Transformer`. Not ported.
#
# - and the state machine is the piece with a gate. The port is pure -- `route` returns the new `Router`
# and the list of deltas instead of mutating and yielding -- because Bend has no mutable cell. That is a
# representation change and NOT a behaviour change, and `gates/llm_serve_router-gate.py` proves it by
# running upstream's `StreamRouter` beside this one over the same piece sequences.
#
# TWO SIGNATURES, MEASURED rather than guessed (`bin/bend --check-only`): `String.take`/`String.drop`
# take a `Nat`, and `String.length` RETURNS one; `String.starts_with(a, b)` takes two `String`s. The first
# the argument's -- a trap worth recording, since `IO.print` is the only output in this tree.

import Base

# serve.py:44-47 -- the router's four modes. Upstream carries them as `str`; the value is that they are
# COMPARED and never parsed, so a `U32` constant per mode is the same contract with less to compare.

def Router.undecided() -> U32: 0    # no output yet; a leading `<think>` decides
def Router.reasoning() -> U32: 1
def Router.content() -> U32: 2
def Router.tool() -> U32: 3

#: a delta's field, exactly upstream's two strings
def Delta.reasoning() -> U32: 0     # "reasoning_content"
def Delta.content() -> U32: 1       # "content"

type Delta is Data:
  Delta{field: U32, text: String}

type Router is Data:
  Router{buf: String, mode: U32}

def Router.of(+reasoning: Bool) -> Router:
  Router{"", Bool.pick(U32, reasoning, Router.reasoning(), Router.undecided())}

def Router.buf(r: Router) -> String:
  match r:
    case Router{buf, mode}: buf

def Router.mode(r: Router) -> U32:
  match r:
    case Router{buf, mode}: mode

# `serve.py:48-55` -- `split(tag, final) -> (before, matched)`, with `self.buf` rebound. A SUBSTRING search,
# because `String.split` takes a single `Char` and every tag here is longer than one.

def Router.at(+fuel: Nat, +tag: String, +buf: String, +i: Nat) -> Maybe<&1, Nat>:
  match fuel:
    case 0n: None{}
    case 1n+q:
      Bool.pick(Maybe<&1, Nat>, String.starts_with(String.drop(buf, i), tag), Some{i},
        Router.at(q, tag, buf, Nat.add(i, 1n)))

#: `serve.py:50` -- `if tag in self.buf`. The FUEL LEADS because a self-call must decrease an argument and
#: Bend reads arguments left to right; `i` grows, so it cannot be the one that shrinks.
def Router.find(+tag: String, +buf: String) -> Maybe<&1, Nat>:
  Router.at(String.length(buf), tag, buf, 0n)

#: the longest suffix of `buf` that is a PREFIX of `tag` (0 when `final`), which is what a streaming
#: splitter must hold back: `tag.startswith(buf[-i:])` in `serve.py:52`.
def Router.hold.at(+fuel: Nat, +tag: String, +buf: String, +i: Nat, +best: Nat, +len: Nat) -> Nat:
  match fuel:
    case 0n: best
    case 1n+q:
      +b = Bool.pick(Nat, String.starts_with(tag, String.drop(buf, Nat.sub(len, i))), i, best)
      Router.hold.at(q, tag, buf, Nat.add(i, 1n), b, len)

def Router.hold(+tag: String, +buf: String, +final: Bool) -> Nat:
  match final:
    case True{}: 0n
    case False{}:
      +len = String.length(buf)
      Router.hold.at(Nat.min(len, String.length(tag)), tag, buf, 1n, 0n, len)

#: `(before, matched, rest)` -- `rest` is the buffer AFTER the tag; the caller keeps the old buffer when
#: `matched` is False and `hold` has already been taken off, matching the mutation order upstream uses.
type Split is Data:
  Split{before: String, matched: Bool, rest: String}

def Router.split.by(m: Maybe<&1, Nat>, +tag: String, +buf: String, +final: Bool) -> Split:
  match m:
    case Some{+i}:
      Split{String.take(buf, i), True{}, String.drop(buf, Nat.add(i, String.length(tag)))}
    case None{}:
      +h = Router.hold(tag, buf, final)
      +keep = Nat.sub(String.length(buf), h)
      Split{String.take(buf, keep), False{}, String.drop(buf, keep)}

def Router.split(+tag: String, +buf: String, +final: Bool) -> Split:
  Router.split.by(Router.find(tag, buf), tag, buf, final)

# `serve.py:56-70` -- `route`. The yields become a LIST because the function is pure, and the DEFS ARE
# ordered so that no two call each other: Bend refuses mutual recursion (the same wall `run` in
# `ops_python.bend` hit), so the pipeline is written bottom-up -- content, then reason, then decide, then
# the dispatch. Upstream gets away with one method because Python evaluates in sequence.

def Router.route.emit(+field: U32, +s: String, +acc: List<&2, Delta>) -> List<&2, Delta>:
  Bool.pick(List<&2, Delta>, String.is_empty(s), acc, Delta{field, s} <> acc)

def Router.route.content.matched(matched: Bool, +r: Router, +final: Bool, acc: List<&2, Delta>,
  +before: String, +rest: String) -> Router & List<&2, Delta>:
  match matched:
    case False{}:
      (Router{rest, Router.mode(r)}, Router.route.emit(Delta.content(), before, acc))
    case True{}:
      (Router{String.concat(["<tool_call>", rest]), Router.tool()},
        Router.route.emit(Delta.content(), before, acc))

def Router.route.content.by(+r: Router, +final: Bool, acc: List<&2, Delta>, sp: Split)
  -> Router & List<&2, Delta>:
  match sp:
    case Split{before, matched, rest}:
      Router.route.content.matched(matched, r, final, acc, before, rest)

def Router.route.content.mode(mode: U32, +r: Router, +final: Bool, acc: List<&2, Delta>)
  -> Router & List<&2, Delta>:
  match mode:
    case 3: (r, acc)                                     # a tool_call region emits nothing
    case _: Router.route.content.by(r, final, acc, Router.split("<tool_call>", Router.buf(r), final))

def Router.route.content(+r: Router, +final: Bool, acc: List<&2, Delta>) -> Router & List<&2, Delta>:
  Router.route.content.mode(Router.mode(r), r, final, acc)

def Router.route.reason.matched(matched: Bool, +r: Router, +final: Bool, acc: List<&2, Delta>,
  +before: String, +rest: String) -> Router & List<&2, Delta>:
  match matched:
    case False{}:
      (Router{rest, Router.reasoning()}, Router.route.emit(Delta.reasoning(), before, acc))
    case True{}:
      Router.route.content(Router{rest, Router.content()}, final,
        Router.route.emit(Delta.reasoning(), before, acc))

def Router.route.reason.by(+r: Router, +final: Bool, acc: List<&2, Delta>, sp: Split)
  -> Router & List<&2, Delta>:
  match sp:
    case Split{before, matched, rest}:
      Router.route.reason.matched(matched, r, final, acc, before, rest)

def Router.route.reason(+r: Router, +final: Bool, acc: List<&2, Delta>) -> Router & List<&2, Delta>:
  Router.route.reason.by(r, final, acc, Router.split("</think>", Router.buf(r), final))

def Router.holds(+r: Router, +final: Bool) -> Bool:
  Bool.and(Bool.not(final),
    Bool.and(Nat.is_lt(String.length(Router.buf(r)), 5n), String.starts_with("<think>", Router.buf(r))))

def Router.route.decide.think(is_think: Bool, +r: Router, +final: Bool, acc: List<&2, Delta>)
  -> Router & List<&2, Delta>:
  match is_think:
    case True{}:
      Router.route.reason(Router{String.drop(Router.buf(r), 5n), Router.reasoning()}, final, acc)
    case False{}:
      Router.route.content(Router{Router.buf(r), Router.content()}, final, acc)

def Router.route.decide.by(hold: Bool, +r: Router, +final: Bool, acc: List<&2, Delta>)
  -> Router & List<&2, Delta>:
  match hold:
    case True{}: (r, acc)
    case False{}:
      Router.route.decide.think(String.starts_with(Router.buf(r), "<think>"), r, final, acc)

def Router.route.decide(+r: Router, +final: Bool, acc: List<&2, Delta>) -> Router & List<&2, Delta>:
  Router.route.decide.by(Router.holds(r, final), r, final, acc)

def Router.route.go.mode(mode: U32, +r: Router, +final: Bool, acc: List<&2, Delta>)
  -> Router & List<&2, Delta>:
  match mode:
    case 1: Router.route.reason(r, final, acc)
    case 2: Router.route.content(r, final, acc)
    case 3: (r, acc)
    case _: Router.route.decide(r, final, acc)

def Router.route.go(+r: Router, +final: Bool, acc: List<&2, Delta>) -> Router & List<&2, Delta>:
  Router.route.go.mode(Router.mode(r), r, final, acc)

def Router.route(+r: Router, +piece: String, +final: Bool) -> Router & List<&2, Delta>:
  Router.route.go(Router{String.concat([Router.buf(r), piece]), Router.mode(r)}, final, Nil{})

# TODO(parity): `parse_tool_call` (serve.py:10-30) -- needs a hand-written matcher for two regexes and a
#   JSON decoder; both are language gaps, not effort (see cli.bend's header for the same class).
# TODO(parity): `normalize_messages` (serve.py:32-41) -- needs a mutable message representation.
# TODO(parity): `Handler` / `LLMServer` (serve.py:71-176) -- HTTP, uuid, time and `model.Transformer`.
