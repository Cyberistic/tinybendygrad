# 1:1 PATH MIRROR of extra/datasets/imagenet.py (91 LOC upstream). PORTED -- the
# FILE-LIST HALF, over a USER-PROVIDED ROOT.
#
# WHAT UPSTREAM IS. Three defs that answer "which files are the dataset", and
# nothing else. Upstream's own comment says it: "for imagenet download
# prepare.sh and run it". The module's first executable line is a directory walk
# and its last def is a list of paths.
#   * `get_imagenet_categories` (upstream:9) is `json.load(open(BASEDIR /
#     "imagenet_class_index.json"))` read as `{v[0]: int(k) for k,v in ci.items()}`
#     -- so the KEY is the class index and the VALUE's first element is the wnid.
#   * `get_train_files` (upstream:28) is `glob.glob(p := str(BASEDIR /
#     "train/*/*"))` and `get_val_files` (upstream:33) is the same over `val/*/*`,
#     each guarded by `raise FileNotFoundError(f"No {training,validation} files in
#     {p}")`. THE WALRUS: the glob result AND the pattern come from one expression,
#     so the pattern is part of the answer.
#
# THE ROOT IS THE CALLER'S, NOT OURS. Upstream's `BASEDIR` is
# `pathlib.Path(__file__).parent / "imagenet"` (upstream:25), a path inside the
# installed package, and `tinygrad/nn/datasets.py`'s `ImageNet` class takes a
# root directory THE USER PROVIDES. So this port takes the root as an argument:
# `get_train_files(root)`. The root is the host's business and the port's job is
# to read it and to say clearly when it is not there.
#
# THE ABSENCE IS NAMED, NOT EMPTY. `extra/datasets/__init__.bend:28-34` is the
# rule this file follows: "a dataset loader that can report an empty dataset
# instead of admitting it is absent is the one lie this file must not tell". So
# `Has` is the answer and `Lacks` is the refusal, and `Lacks` is NOT an empty
# list: an ImageNet tree with no train files, a tree with no `train/` directory,
# and no tree at all are three different facts, and upstream tells them apart
# too (its `FileNotFoundError` names the pattern it found nothing under).
# `D.Refused` is the port's named "cannot answer" value (`__init__.bend:40-46`);
# its `at` carries the upstream address AND the path that was missing.
#
# THE PRIMITIVES, AND WHERE THEY LIVE. MEASURED, not assumed:
#   * LISTING A DIRECTORY: `Sz.read_dir` (`tinybendygrad/sz.bend:124`), the ONLY
#     directory listing in the port. It is `@unsafe` -- a foreign call, because
#     `base.bend` has no `File.list` (the TODO at `sz.bend:120` says so) -- and it
#     answers the NAMES of a directory, except "." and "..", in the order the host
#     lists them (`runtime/sz.c:31-63`). A directory it cannot open is NO NAMES,
#     which is why `Sz.is_dir` is asked first.
#   * IS A NAME A DIRECTORY: `Sz.is_dir` (`tinybendygrad/sz.bend:132`), 1 or 0
#     (`runtime/sz.c:106-113`). It is an LSTAT, so a symlink to a directory is
#     NOT a directory here.
#   * READING A FILE: `File.open` + `File.read` + `File.close` from `base.bend`
#     (`:288`, `:293`, `:323`). `File.read` answers a `Result`, and the Fail arm
#     is the file that is not there -- the port's own idiom for it is
#     `tinybendygrad/helpers.bend:2736-2759`.
#   * A GLOB: THERE IS NONE. `train/*/*` is expanded HERE, from the two
#     primitives above, and the expansion is measured against CPython's
#     `glob.glob` -- see `.agents/slop/imagenet2/REPORT.md`.
#   * A JSON PARSER: THERE IS NONE EITHER. `tinybendygrad/viz/serve.bend:804`
#     says "`json.loads` IS NOT PORTED" and `tinybendygrad/nn/state.bend:97`
#     calls `json.loads` "a PARSER" it lacks. So the class index is read by the
#     READER BELOW, which is a decoder for the class-index format and NOT a JSON
#     parser: it refuses any shape it does not know instead of guessing one.
#
# NOT PORTED, AND NAMED SO NOBODY INVENTS IT: `image_resize` (upstream:37),
#   `rand_flip` (upstream:43), `center_crop` (upstream:48),
#   `random_resized_crop` (upstream:57), `preprocess_train` (upstream:88) -- the
#   TRAINING-TIME TRANSFORMS, which need the imaging library and are not this
#   file's half -- and the `MNISTMOCK` branch of `get_train_files`
#   (upstream:17-23), which calls `create_fake_mnist_imagenet` from
#   `extra/datasets/fake_imagenet_from_mnist.py` to BUILD the tree this file
#   then reads. The mock's own `imagenet_class_index.json` is
#   `{"0": ["0", "0"], ...}` (`fake_imagenet_from_mnist.py:26`), and the reader
#   below accepts that shape as well as the real one's
#   `{"0": ["tench", 0], ...}`.
# TODO(p3) `@functools.cache` (upstream:8/16/32) AND `@diskcache` (upstream:27).
#   Upstream caches all three answers. Bend has no mutable globals
#   (`tinybendygrad/helpers.bend:2546`), so a cache is not a decorator here: the
#   port's own spelling of a keyed table is the first-wins `Reg` scan
#   (`tinybendygrad/device.bend:296-323`), and the caller holding the first
#   answer IS the cache. `@diskcache` additionally wants a disk cache the port
#   does not have.
#
# ORDER IS LOAD-BEARING: a def may call only defs declared ABOVE it, so the
# file is in dependency order and not in reading order.
import Base
import ../../../tinybendygrad/extra/datasets/__init__.bend as D

# ===========================================================================
# THE ANSWER
# ===========================================================================

# `Has` is the answer and `Lacks` is the refusal. One type for both file lists
# and the class map, so "the loader could not answer" is one shape.
type Load<a, -A: Kind(a)> is Kind(a):
  Has{value: A}
  Lacks{why: D.Refused}

def ans.has(fs: List<&2, String>) -> Load<&2, List<&2, String>>: Has{fs}

def ans.lacks(why: String) -> Load<&2, List<&2, String>>: Lacks{D.refuse(why)}

def cats.has(m: Map<&2, U32>) -> Load<&2, Map<&2, U32>>: Has{m}

def cats.lacks(why: String) -> Load<&2, Map<&2, U32>>: Lacks{D.refuse(why)}

# ===========================================================================
# READING A FILE
# ===========================================================================

def read.pick(r: Result<&1, &1, U32 & String, String>) -> Maybe<&2, String>:
  match r:
    case Done{value}: Some{value}
    case Fail{error}: None{}

def read.close(m: File & Result<&1, &1, U32 & String, String>) -> IO(Maybe<&2, String>):
  (f, r) = m
  do IO<Maybe<&2, String>>:
    u : Unit <- File.close(f)
    IO.pure(Maybe<&2, String>, read.pick(r))

def read.body(f: File) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    m : File & Result<&1, &1, U32 & String, String> <- File.read(f, 2147483647)
    read.close(m)

def read.go(f: Result<&1, &1, U32 & String, File>) -> IO(Maybe<&2, String>):
  match f:
    case Done{value}: read.body(value)
    case Fail{error}: IO.pure(Maybe<&2, String>, None{})

def read.text(path: String) -> IO(Maybe<&2, String>):
  do IO<Maybe<&2, String>>:
    f : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    read.go(f)

# ===========================================================================
# THE CLASS INDEX READER
#
# A decoder for the class-index format, NOT a JSON parser: the port has none
# (`viz/serve.bend:804`, `nn/state.bend:97`), and a general one is a project
# with its own termination story -- see `.agents/slop/imagenet2/REPORT.md`.
#
# THE FORMAT IT READS, and the two shapes in evidence:
#   {"0": ["tench", 0], "1": ["goldfish", 1], ...}     the real file
#   {"0": ["0", "0"], "1": ["1", "1"], ...}             the mock's own file
# so: an object; every key a decimal number (upstream's `int(k)`); every value
# a two-element array whose FIRST element is a string (upstream's `v[0]`, the
# wnid) and whose second element is a number or a string (upstream ignores it,
# and this reader insists it is a NUMBER OR A STRING rather than guessing).
# ANYTHING ELSE IS REFUSED, with the place it refused.
#
# It is a CHARACTER-AT-A-TIME machine, the port's own idiom for a parser
# (`tinybendygrad/sz.bend:967-988` runs its lexer exactly this way): one char
# per step, the state carries everything, and the char list shrinks by one per
# step. That is what makes it TERMINATE -- a recursive-descent parser that
# returns "the rest of the input" cannot be written here, because Bend's
# termination checker wants a self-call's argument to be a SYNTACTICALLY
# smaller part of its parameter and a computed suffix is not one
# (MEASURED, `.agents/slop/imagenet2/t1-suffix.bend`).
#
# THE WHITESPACE IS `Char.is_space`, WHICH IS ONE CHARACTER WIDER THAN JSON's:
# Base's is `x == 32 or 9 <= x <= 13` (`base.bend:1950-1953`), so a vertical tab
# or a form feed BETWEEN TWO TOKENS is accepted here and rejected by `json`.
# Nothing writes one, and the refusal is the port's habit, so the wider set is
# the price of one `Char.is_space` call instead of four match arms in six
# places. NAMED, not hidden.
# ===========================================================================

type Entry is Data:
  Entry{name: String, index: U32}

# The states. `Want` is "one more character, and then this state"; the rest are
# the places the format can be in. The index and the name travel IN the state,
# so the only thing the machine accumulates besides it is the entries so far.
type St is Data:
  Want{tok: Char, next: St}
  SOpen{}
  SNameQ{index: U32}
  SScalar{index: U32, name: String}
  SSep{}
  SKStr{acc: List<&2, Char>}
  SNStr{acc: List<&2, Char>, index: U32}
  SSStr{acc: List<&2, Char>, index: U32, name: String}
  SNum{acc: List<&2, Char>, index: U32, name: String}
  SNumEnd{acc: List<&2, Char>, index: U32, name: String}
  SClose{index: U32, name: String}
  SDone{}
  SFail{why: String}

# the entry is complete: (name, index)
def ci.entry(index: U32, name: String, es: List<&2, Entry>) -> (St & List<&2, Entry>):
  (SSep{}, List.append(&2, Entry, es, [Entry{name, index}]))

def ci.key.done.pick(idx: Maybe<&2, U32>, es: List<&2, Entry>) -> (St & List<&2, Entry>):
  match idx:
    case Some{index}: (Want{':', Want{'[', SNameQ{index}}}, es)
    case None{}: (SFail{"a class index key is not a number"}, es)

def ci.key.done(acc: List<&2, Char>, es: List<&2, Entry>) -> (St & List<&2, Entry>):
  ci.key.done.pick(U32.read(String.from_list(acc)), es)

# in the key string: the key is the class index
def ci.kstr(acc: List<&2, Char>, es: List<&2, Entry>, +c: Char) -> (St & List<&2, Entry>):
  match c:
    case '"': ci.key.done(acc, es)
    case '\\': (SFail{"a backslash in a class index key"}, es)
    case _: (SKStr{List.append(&2, Char, acc, [c])}, es)

# in the name string: the name is the wnid
def ci.nstr(acc: List<&2, Char>, index: U32, es: List<&2, Entry>, +c: Char) -> (St & List<&2, Entry>):
  match c:
    case '"': (Want{',', SScalar{index, String.from_list(acc)}}, es)
    case '\\': (SFail{"a backslash in a class name"}, es)
    case _: (SNStr{List.append(&2, Char, acc, [c]), index}, es)

# in a string second element
def ci.sstr(acc: List<&2, Char>, index: U32, name: String, es: List<&2, Entry>, +c: Char) -> (St & List<&2, Entry>):
  match c:
    case '"': (SClose{index, name}, es)
    case '\\': (SFail{"a backslash in a class value"}, es)
    case _: (SSStr{List.append(&2, Char, acc, [c]), index, name}, es)

# the ']' that closes the value's array: the state that CONSUMES it is the one
# that pushes the entry, because a state is entered by consuming a character.
def ci.close(index: U32, name: String, es: List<&2, Entry>, +c: Char) -> (St & List<&2, Entry>):
  match c:
    case ']': ci.entry(index, name, es)
    case _: (SFail{"expected ']'"}, es)

def ci.numchar.pick(isdigit: Bool, c: Char) -> Bool:
  # the characters a JSON number may hold
  match isdigit:
    case True{}: True{}
    case False{}:
      match c:
        case '.': True{}
        case 'e': True{}
        case 'E': True{}
        case '+': True{}
        case '-': True{}
        case _: False{}

def ci.numchar(+c: Char) -> Bool:
  ci.numchar.pick(Char.is_digit(c), c)

def ci.num.done.pick(num: Maybe<&2, U32>, index: U32, name: String, es: List<&2, Entry>) -> (St & List<&2, Entry>):
  match num:
    case Some{value}: ci.entry(index, name, es)
    case None{}: (SFail{"the second element of a class value is not a number"}, es)

def ci.num.done(acc: List<&2, Char>, index: U32, name: String, es: List<&2, Entry>) -> (St & List<&2, Entry>):
  ci.num.done.pick(U32.read(String.from_list(acc)), index, name, es)

# the number ended and the ']' is not here yet
def ci.numend.pick(isws: Bool, acc: List<&2, Char>, index: U32, name: String, es: List<&2, Entry>, c: Char) -> (St & List<&2, Entry>):
  match isws:
    case True{}: (SNumEnd{acc, index, name}, es)
    case False{}:
      match c:
        case ']': ci.num.done(acc, index, name, es)
        case _: (SFail{"expected ']'"}, es)

def ci.numend(acc: List<&2, Char>, index: U32, name: String, es: List<&2, Entry>, +c: Char) -> (St & List<&2, Entry>):
  ci.numend.pick(Char.is_space(c), acc, index, name, es, c)

# in a number second element
def ci.num.pick(isnum: Bool, acc: List<&2, Char>, index: U32, name: String, es: List<&2, Entry>, +c: Char) -> (St & List<&2, Entry>):
  match isnum:
    case True{}: (SNum{List.append(&2, Char, acc, [c]), index, name}, es)
    case False{}:
      match c:
        case ']': ci.num.done(acc, index, name, es)
        case _: ci.numend(acc, index, name, es, c)

def ci.num(acc: List<&2, Char>, index: U32, name: String, es: List<&2, Entry>, +c: Char) -> (St & List<&2, Entry>):
  ci.num.pick(ci.numchar(c), acc, index, name, es, c)

# the second element of a value: a string or a number
def ci.scalar.num.pick(isdigit: Bool, c: Char, index: U32, name: String, es: List<&2, Entry>) -> (St & List<&2, Entry>):
  match isdigit:
    case True{}: (SNum{[c], index, name}, es)
    case False{}: (SFail{"a class value is not [name, number]"}, es)

def ci.scalar.num(+c: Char, index: U32, name: String, es: List<&2, Entry>) -> (St & List<&2, Entry>):
  ci.scalar.num.pick(Char.is_digit(c), c, index, name, es)

def ci.scalar.pick(isws: Bool, index: U32, name: String, es: List<&2, Entry>, +c: Char) -> (St & List<&2, Entry>):
  match isws:
    case True{}: (SScalar{index, name}, es)
    case False{}:
      match c:
        case '"': (SSStr{Nil{}, index, name}, es)
        case '-': (SNum{['-'], index, name}, es)
        case _: ci.scalar.num(c, index, name, es)

def ci.scalar(index: U32, name: String, es: List<&2, Entry>, +c: Char) -> (St & List<&2, Entry>):
  ci.scalar.pick(Char.is_space(c), index, name, es, c)

# after an entry: the next key's quote, or the end of the object
def ci.sep.pick(isws: Bool, es: List<&2, Entry>, c: Char) -> (St & List<&2, Entry>):
  match isws:
    case True{}: (SSep{}, es)
    case False{}:
      match c:
        # the ',' is followed by WHITESPACE and then the key's quote, and the
        # state that skips the whitespace is the `Want` -- `SKStr` is INSIDE a
        # string and does not skip it, so going straight to it would read the
        # whitespace as the closing quote of an empty key.
        case ',': (Want{'"', SKStr{Nil{}}}, es)
        case '}': (SDone{}, es)
        case _: (SFail{"expected ',' or '}'"}, es)

def ci.sep(es: List<&2, Entry>, +c: Char) -> (St & List<&2, Entry>):
  ci.sep.pick(Char.is_space(c), es, c)

# just after '{': the first key's quote, or the end of an empty object
def ci.open.pick(isws: Bool, es: List<&2, Entry>, c: Char) -> (St & List<&2, Entry>):
  match isws:
    case True{}: (SOpen{}, es)
    case False{}:
      match c:
        case '"': (SKStr{Nil{}}, es)
        case '}': (SDone{}, es)
        case _: (SFail{"expected a key or '}'"}, es)

def ci.open(es: List<&2, Entry>, +c: Char) -> (St & List<&2, Entry>):
  ci.open.pick(Char.is_space(c), es, c)

# the name's quote
def ci.nameq.pick(isws: Bool, index: U32, es: List<&2, Entry>, c: Char) -> (St & List<&2, Entry>):
  match isws:
    case True{}: (SNameQ{index}, es)
    case False{}:
      match c:
        case '"': (SNStr{Nil{}, index}, es)
        case _: (SFail{"expected the class name"}, es)

def ci.nameq(index: U32, es: List<&2, Entry>, +c: Char) -> (St & List<&2, Entry>):
  ci.nameq.pick(Char.is_space(c), index, es, c)

# one more character, and then the state that follows it
def ci.want.hit.pick(ishit: Bool, tok: Char, next: St, es: List<&2, Entry>) -> (St & List<&2, Entry>):
  match ishit:
    case True{}: (next, es)
    case False{}: (SFail{"expected " ++ Char.show(tok)}, es)

def ci.want.hit(c: Char, +tok: Char, next: St, es: List<&2, Entry>) -> (St & List<&2, Entry>):
  ci.want.hit.pick(Char.is_eq(c, tok), tok, next, es)

def ci.want.pick(isws: Bool, +tok: Char, next: St, es: List<&2, Entry>, c: Char) -> (St & List<&2, Entry>):
  match isws:
    case True{}: (Want{tok, next}, es)
    case False{}: ci.want.hit(c, tok, next, es)

def ci.want(+tok: Char, next: St, es: List<&2, Entry>, +c: Char) -> (St & List<&2, Entry>):
  ci.want.pick(Char.is_space(c), tok, next, es, c)

# one character, one step
def ci.step(s: St, es: List<&2, Entry>, +c: Char) -> (St & List<&2, Entry>):
  match s:
    case Want{+tok, next}: ci.want(tok, next, es, c)
    case SOpen{}: ci.open(es, c)
    case SNameQ{index}: ci.nameq(index, es, c)
    case SScalar{index, name}: ci.scalar(index, name, es, c)
    case SSep{}: ci.sep(es, c)
    case SKStr{acc}: ci.kstr(acc, es, c)
    case SNStr{acc, index}: ci.nstr(acc, index, es, c)
    case SSStr{acc, index, name}: ci.sstr(acc, index, name, es, c)
    case SNum{acc, index, name}: ci.num(acc, index, name, es, c)
    case SNumEnd{acc, index, name}: ci.numend(acc, index, name, es, c)
    case SClose{index, name}: ci.close(index, name, es, c)
    case SDone{}: (s, es)
    case SFail{why}: (s, es)

# The state and the entries travel together, because a `let` cannot destructure
# a CALL's result -- only a parameter's -- and the step returns both.
def ci.step2(m: (St & List<&2, Entry>), +c: Char) -> (St & List<&2, Entry>):
  (s, es) = m
  ci.step(s, es, c)

# The machine. One character per step; the list shrinks, so it terminates.
def ci.go(bs: List<&2, Char>, m: (St & List<&2, Entry>)) -> (St & List<&2, Entry>):
  match bs:
    case Nil{}: m
    case +c <> r: ci.go(r, ci.step2(m, c))

# the whole file
def ci.read(txt: String) -> (St & List<&2, Entry>):
  ci.go(String.to_list(txt), (Want{'{', SOpen{}}, Nil{}))

# the entries as the map upstream builds: {wnid: index}
def ci.map.go(es: List<&2, Entry>, m: Map<&2, U32>) -> Map<&2, U32>:
  match es:
    case Nil{}: m
    case Entry{name, index} <> t: ci.map.go(t, Map.set(&2, U32, m, name, index))

def ci.map(es: List<&2, Entry>) -> Map<&2, U32>:
  ci.map.go(es, Map.new(&2, U32))

# ===========================================================================
# THE THREE DEFS
# ===========================================================================

def cats.pick2(st: St, es: List<&2, Entry>, path: String) -> IO(Load<&2, Map<&2, U32>>):
  match st:
    case SDone{}: IO.pure(Load<&2, Map<&2, U32>>, cats.has(ci.map(es)))
    case SFail{why}: IO.pure(Load<&2, Map<&2, U32>>, cats.lacks("extra/datasets/imagenet.py:9 get_imagenet_categories: " ++ path ++ ": " ++ why))
    case _: IO.pure(Load<&2, Map<&2, U32>>, cats.lacks("extra/datasets/imagenet.py:9 get_imagenet_categories: " ++ path ++ ": the class index did not close"))

def cats.go.pick(m: (St & List<&2, Entry>), path: String) -> IO(Load<&2, Map<&2, U32>>):
  (st, es) = m
  do IO<Load<&2, Map<&2, U32>>>:
    cats.pick2(st, es, path)

def cats.go(txt: String, path: String) -> IO(Load<&2, Map<&2, U32>>):
  cats.go.pick(ci.read(txt), path)

def cats.pick(txt: Maybe<&2, String>, path: String) -> IO(Load<&2, Map<&2, U32>>):
  match txt:
    case None{}: IO.pure(Load<&2, Map<&2, U32>>, cats.lacks("extra/datasets/imagenet.py:9 get_imagenet_categories: no " ++ path))
    case Some{value}: cats.go(value, path)

# upstream: `def get_imagenet_categories()` -> `{wnid: int}` over 1000 classes
def get_imagenet_categories(root: String) -> IO(Load<&2, Map<&2, U32>>):
  do IO<Load<&2, Map<&2, U32>>>:
    +path : String = root ++ "/imagenet_class_index.json"
    txt : Maybe<&2, String> <- read.text(path)
    cats.pick(txt, path)

