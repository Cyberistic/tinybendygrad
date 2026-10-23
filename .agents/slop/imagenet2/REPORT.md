# THE IMAGENET LOADER, PORTED: `tinybendygrad/extra/datasets/imagenet.bend`

**HEAD measured:** `8dde14ef7460f4cf9d5c9ef3d3aee23601bd428b`
(`the project is on Bend v2.0.38, and every pin that names the compiler moved with it`,
2026-10-23 03:33:22 +0300). **Timestamp of every measurement below:**
`Fri Oct 23 00:07Z` .. `00:45Z` (2026-10-23), UTC.
**The HEAD MOVED under me:** the session started at `98b17949dd78a3a773c7e40ac079267739faaa28`
and the tree was at `8dde14ef...` when the last measurement was taken. Nothing here
is a claim about a commit; it is a claim about the FILES AS THEY STOOD at that
timestamp.

**Bend:** `bin/bend` -> `references/bend/bend2/main.ts`, **bend 2.0.38** (the
compiler prints "bend 2.0.38 is available: run bend update" on every run, which
means the pin is already there).
**CPython for the oracle:** `.venv/bin/python` = **3.12.10** (`sys.version`).

---

## 1. THE CONTRACT, IN ONE PARAGRAPH

Upstream's `extra/datasets/imagenet.py` answers three questions and the port must
answer the same three over a **caller-provided root** (`get_train_files(root)`,
`get_val_files(root)`, `get_imagenet_categories(root)`), each returning the port's
own `Load` type: `Has{value}` for the answer and `Lacks{why: D.Refused}` for the
refusal, and the refusal is **never** an empty list, because
`extra/datasets/__init__.bend:28-34` says a loader that can report an empty
dataset instead of admitting it is absent "is the one lie this file must not
tell". `get_train_files` must return **the sorted list of the paths under
`<root>/train/*/*`** and `get_val_files` the same under `<root>/val/*/*`, where
`*/*` is CPython's `glob.glob` semantics exactly: the depth-one name must be a
**directory**, a leading dot is **hidden at both depths**, and a directory at
depth two **is** in the answer; `get_imagenet_categories` must return
**`{wnid: class index}`** read out of `<root>/imagenet_class_index.json` the way
upstream reads it -- the JSON **key** is the class index (`int(k)`) and the
**value's first element** is the wnid (`v[0]`) -- and it must say so plainly when
the file is not there or is not that shape.

---

## 2. THE PORT'S PRIMITIVES: WHAT I FOUND AND WHAT THEY ACTUALLY DO

I read every body I cite. Nothing here is from memory.

| what | where | what it ACTUALLY does (read, not assumed) |
|---|---|---|
| **list a directory** | `tinybendygrad/sz.bend:124` `Sz.read_dir(path) -> IO(List<String>)` | `@unsafe` -- a **foreign call**, because `base.bend` has no `File.list` (the TODO at `sz.bend:120` says so). The C is `runtime/sz.c:31-63`: it `opendir`s, `readdir`s, and **skips `.` and `..`**; the names come back in the order the host lists them. **A directory it cannot open is NO NAMES** (not an error) -- `runtime/sz.c:37-41` returns the errno and the packer builds `Nil{}` (`runtime/sz.js:9-13` catches and answers `Nil{}`). That is why `Sz.is_dir` has to be asked FIRST. |
| **is this name a directory** | `tinybendygrad/sz.bend:132` `Sz.is_dir(path) -> IO(U32)` | `@unsafe`, 1 or 0. `runtime/sz.c:106-113`: **`lstat`**, not `stat`, so **a symlink to a directory is NOT a directory here**. A path that cannot be stat'd is 0. |
| **read a file** | `base.bend:288` `File.open`, `:293` `File.read`, `:323` `File.close` | `File.open` answers `Result<&1,&1,U32&String,File>`; `File.read` answers `File & Result<&1,&1,U32&String,String>` -- **the Fail arm is the file that is not there**. The port's own idiom for that is `tinybendygrad/helpers.bend:2736-2759` (`lines()`), which I followed. |
| **a glob** | **THERE IS NONE** | Measured: `grep -rn "glob" --include='*.bend' tinybendygrad/` returns **no** glob implementation -- the hits are `global_max`, `global_prod_max` and `is_global` in the renderers. So `train/*/*` is expanded **here**, from the two primitives above. |
| **a JSON parser** | **THERE IS NONE** | Measured: `tinybendygrad/viz/serve.bend:804` says "`json.loads` IS NOT PORTED", and `tinybendygrad/nn/state.bend:97` calls `json.loads` "a PARSER" it lacks. `viz/serve.bend:338-355` is an **encoder** (`json.dumps`), not a decoder. So the class index is read by a **decoder for the class-index format** (below), which refuses any shape it does not know. |
| **a dict** | `base.bend:93` `Map<a, -V: Kind(a)>` | A string-keyed persistent map: `Map.new`, `Map.set` (insert-or-update), `Map.keys`, `Map.get` (which answers the map BESIDE the value, `base.bend:2831`). This is upstream's `{wnid: int}`. |

### The four Bend facts the port made me measure (each one is an instrument, not a belief)

| fact | how it was measured | what it cost |
|---|---|---|
| **a def may call only a def declared ABOVE it** | `t4-order.bend`: `def a() -> U32: b()` with `b` below -> `Error: expected : a filled definition (an unfilled law is a dead claim...)`, rc=1 | the file is in **dependency order**, not reading order |
| **a self-call's argument must be a SYNTACTICALLY smaller part** | `t1-suffix.bend`: a self-call on a runtime-computed SUFFIX -> `Error: ... a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks)` | **this is why the JSON reader is a character-at-a-time machine** and not a recursive-descent parser: a parser that returns "the rest of the input" cannot be written here. `t2-tails.bend` measures the three tails that DO work (a `List<&1,...>` tail, a `List<&2,...>` tail, a `String` tail). |
| **a `match` cannot scrutinise a computed value** | the compiler says `a parameter or field scrutinee (a match cannot scrutinize a computed value: give it its own def)` | every predicate test is a **parameter** of a helper def, not an expression in the `match` |
| **a `+` binding is how a value is used twice** | `t5-pluslet.bend`: `+c : String = a ++ b` then `c ++ c` -> `xyxy` | the reader's `+c`/`+tok`/`+acc` annotations are load-bearing, not decoration |

Also measured: **char literals work in `match` cases** (`t6-charlit.bend`: `case '"'` /
`case '\t'` -> `quote` / `tab`), and `Char.is_space` is `x == 32 or 9 <= x <= 13`
(`base.bend:1950-1953`), i.e. **one character wider than JSON's whitespace** (it
takes a vertical tab and a form feed, which JSON does not). That leniency is
named in the file and in section 6 below.

---

## 3. WHAT I IMPLEMENTED

`tinybendygrad/extra/datasets/imagenet.bend`, **520 lines**, replacing the
46-line stub that refused all three defs. It is in dependency order (Bend's rule).

* **The answer type** (`Load<a, -A: Kind(a)>`): `Has{value}` / `Lacks{why:
  D.Refused}`. `D.Refused` is the port's named "cannot answer" value
  (`extra/datasets/__init__.bend:40-46`), and its `at` carries **the upstream
  address AND the path that was missing** -- so the refusal is one vocabulary
  (`D.refuse`) and the *arm* says whether the answer is missing because the data
  is absent or because the work is not ported.
* **`get_train_files(root)` / `get_val_files(root)`**: `Sz.is_dir` on
  `<root>/<split>`, then `Sz.read_dir` on it, then for every **visible** name
  that `Sz.is_dir` says is a directory, `Sz.read_dir` again and every visible
  name under it, joined to the parent path. The list is **sorted**
  (`List.sort`), because `glob.glob` answers in `os.scandir` order and the ORDER
  IS NOT THE CLAIM -- the claim is the set of paths, and a reproducible answer
  is worth more than upstream's arbitrary one.
* **`get_imagenet_categories(root)`**: `File.open`/`File.read` on
  `<root>/imagenet_class_index.json`, then the **class-index reader**, then the
  entries folded into a `Map<&2, U32>` keyed by the wnid -- upstream's dict.
* **The class-index reader** (`ci.*`): a **character-at-a-time machine** over the
  file's characters, the port's own idiom for a parser
  (`tinybendygrad/sz.bend:967-988` runs its lexer exactly this way: one char per
  step, the state carries everything, the char list shrinks by one per step).
  It reads the object shape
  `{"0": ["tench", 0], "1": ["goldfish", 1], ...}` **and** the mock's own shape
  `{"0": ["0", "0"], ...}` (`extra/datasets/fake_imagenet_from_mnist.py:26`),
  requires the key to be a decimal number (upstream's `int(k)`), requires the
  value's first element to be a string (upstream's `v[0]`), and requires the
  value's second element to be **a number or a string** -- upstream ignores it,
  and this reader insists on what it is rather than guessing.

### The safety verdict, MEASURED

* `bin/bend tinybendygrad/extra/datasets/imagenet.bend --verdict` ->
  `Error: 15 defs rely on unsafe or foreign code:` and the list names
  `expand.list, expand.dir, expand.one, split.files.go, split.files.pick,
  split.files, get_train_files, get_val_files` (rc=1). **The file PARSES AND
  TYPE-CHECKS; the SAFETY verdict is what fails**, and the cause is the two
  `@unsafe` filesystem primitives -- there is no other directory listing in the
  port. This is the standing class `checks/port-compile-gate.py:147` reads
  (`RE_FOREIGN`), and that gate's own header says only FINDING is a defect.
* **The class-index reader alone is PROVED.** A measurement copy with the
  directory-listing half removed (`.agents/slop/imagenet2/reader-only.bend`,
  422 lines, generated from the real file) ->
  `bin/bend reader-only.bend --verdict` -> **`ALL PROOFS CHECK`**, rc=0. That
  verdict is bend2's **and** the Lean kernel's (`references/bend/bend2/main.ts:851`
  and the guide: "prints ALL PROOFS CHECK only when every def outside Base is a
  valid proof, which bend2 and the kernel both accept"). So `ci.*` and
  `get_imagenet_categories` carry **no unproved step at all**, and only the
  directory-listing half rests on the port's foreign seam.

---

## 4. WHAT IS SPECIFIED, NOT IMPLEMENTED, AND WHY

### 4.1 A GENERAL JSON PARSER -- the real gap, and what it would take

**The port has none**, and the class-index reader is **not** one: it is a
decoder for one format, and it refuses everything else. A general JSON parser
is a project of its own, and the reason is Bend's own shape, not taste:

* **It needs mutual recursion.** `value` calls `array`, `array` calls `value`.
  Bend **refuses** mutual recursion outright, and its own answer is "two
  mutually recursive functions become one def with an extra argument selecting
  which to run" (`references/bend/bend2/guide`). So the parser is **ONE def with
  a mode selector**, and the mode is not a small thing: the states are
  `value`, `array`, `object`, `string`, `number`, `literal`, and each of them
  needs to know whether it is at the first element, after a comma, or after a
  colon.
* **It needs a stack.** A character-at-a-time machine over nested JSON has to
  carry the open containers, so the state is a stack of partially built
  containers, and the push/pop discipline is where the bugs live.
* **It needs the termination argument the class-index reader does not.** The
  reader's grammar is FLAT -- an object of two-element arrays -- so one
  character per step and a shrinking list is a complete termination argument.
  A general parser's grammar is not flat, so "one char per step" is no longer
  enough on its own.
* **Where it would live:** a **new module**, `tinybendygrad/json.bend`, beside
  `helpers.bend` and `sz.bend`, NOT `LAWS/spec.bend`. `LAWS/spec.bend` is the
  *specification* IR (`tinygrad/spec/tinyspec.tex` made into a pure Bend
  datatype) and is a **fold over an inductive tree with no effects**; a JSON
  parser is an **effectful** decoder over a byte stream and has no business in
  the laws file. It would be a `type Json is Data:` with the six JSON value
  kinds, plus `json_parse(text: String) -> IO(Maybe<&2, Json>)`, and it would
  answer for `viz/serve.bend`'s `json.loads` wall (`viz/serve.bend:804`) and
  `nn/state.bend`'s as well.
* **What it would NOT be:** a change to `imagenet.bend`. The reader here would
  become a projection over `Json`, and the projection is the part that knows
  about `int(k)` and `v[0]`.

**Until that module exists, the class-index reader is the right size**: it reads
the two shapes that exist in this repo and refuses the rest, and it is proved.

### 4.2 `@functools.cache` (upstream:8/16/32) AND `@diskcache` (upstream:27)

Upstream caches all three answers. **Not ported**, and named in the file's
header with the reason: Bend has no mutable globals
(`tinybendygrad/helpers.bend:2546` records that), so a cache cannot be a
decorator here. The port's own spelling of a keyed table is the **first-wins
`Reg` scan** (`tinybendygrad/device.bend:296-323`), and the caller holding the
first answer **is** the cache. `@diskcache` additionally wants a disk cache the
port does not have.

### 4.3 The training-time transforms and the mock branch -- NOT MINE

`image_resize` (upstream:37), `rand_flip` (upstream:43), `center_crop`
(upstream:48), `random_resized_crop` (upstream:57), `preprocess_train`
(upstream:88) and the `MNISTMOCK` branch of `get_train_files` (upstream:17-23)
are **named in the file's header and NOT implemented**, as instructed: they are
the training-time transforms (they need the imaging library) and the mock
branch (it BUILDS the tree this file then reads, via
`create_fake_mnist_imagenet`). The mock's own class-index shape **is** read by
the reader here, and the mock row is in the table below.

### 4.4 The symlinked class directory -- a MEASURED divergence, not a bug I hid

CPython's `glob` **follows** a symlinked class directory (its
`os.DirEntry.is_dir()` follows); `Sz.is_dir` is an **`lstat`**
(`runtime/sz.c:106-113`), so the port **skips** it. Measured on the same tree:

```
tree:  train/real/inside.JPEG  and  train/linkdir -> real   (a symlink)
port:  train=train/real/inside.JPEG
cpy:   train=train/linkdir/inside.JPEG|train/real/inside.JPEG
```

The port's answer is the *stricter* one and the tree in this repo has no
symlinked class directory, so the tables below are unaffected. **A symlinked
class directory is the one input where the port and CPython differ, and the
divergence is `lstat` versus `stat`, in `runtime/sz.c`.** Changing it would mean
changing `Sz.is_dir` for every caller in the port -- which is not this unit's
call.

### 4.5 The port's refusal is MORE SPECIFIC than upstream's

Upstream has **one** refusal per split: `FileNotFoundError(f"No training files
in {p}")`, raised when the glob matched **nothing** -- and a missing `train/`
directory is a glob that matched nothing. The port has **two**: "`<root>/train`
is not a directory" and "No training files in `<root>/train/*/*`". The second
message is upstream's verbatim; the first names a fact upstream cannot tell
apart. **Both are refusals, and neither is an empty list.**

### 4.6 DOES `get_imagenet_categories` READ THE SAME JSON SHAPE UPSTREAM DOES?

**YES, for every shape that exists in this repo, and it is STRICT where upstream
is loose.** Upstream's comprehension is `{v[0]: int(k) for k,v in ci.items()}`
over `json.load(open(BASEDIR / "imagenet_class_index.json"))`, so it needs two
things and nothing else: the **key** is a string `int()` accepts, and the
**value's first element** is the wnid. The reader here needs exactly those two
and reads the value's **second** element only to CHECK that it is a number or a
string -- upstream **ignores** it entirely. So:

| | upstream | this port |
|---|---|---|
| the real file `{"0": ["tench", 0], ...}` | `{v[0]: int(k)}` | **the same map** (measured: `cat=goldfish=1\|great white shark=2\|tench=0`, CPython's answer is byte-identical) |
| the mock's file `{"0": ["0", "0"], ...}` | `{v[0]: int(k)}` | **the same map** (measured: `cat=0=0\|1=1\|2=2`, CPython's answer byte-identical) |
| a value with a THIRD element | accepted | **REFUSED** |
| a value whose second element is an OBJECT or an ARRAY | accepted (upstream ignores it) | **REFUSED** |
| a backslash escape in a name or a key | accepted by `json` | **REFUSED** (named in the file's header) |
| a key that is not a decimal number | `int(k)` would raise | **REFUSED** |

The two differences that are NOT refusals are the **whitespace** (JSON's four
against `Char.is_space`'s six) and the **escapes**. Everything else the reader
rejects, upstream would have accepted and silently ignored -- which is the
"prefer refused over a guess" rule applied to a decoder.

---

## 5. THE PROBE, THE ORACLE, AND THE EXPECTED VALUES

**The fixture** (`.agents/slop/imagenet2/mkfixture.py`) is a FAKE tree of
**one-line placeholder files** -- **no real data and no download** -- at
`/private/var/folders/yd/qy2_4vk13kq_b0dsnv_71wvr0000gn/T/opencode/imagenet-fixture`.
It is built to exercise the five things the two implementations must agree on:
a class directory with two files; a **hidden** class directory `.hidden`; a
**loose file** at depth one; an **empty** class directory; and a **directory at
depth two** (`subdir`, which glob's `*` matches and so must the port). It also
carries the class index in the real shape and, under `mock/`, in the mock's
shape.

**The oracle** (`.agents/slop/imagenet2/oracle.py`) is upstream's own logic,
verbatim, with `BASEDIR` replaced by the root: `json.load(open(...))` read as
`{v[0]: int(k) for k,v in ci.items()}`, and `glob.glob(p := str(BASEDIR /
"train/*/*"))` with upstream's `FileNotFoundError`. The file list is **sorted**,
because `glob.glob` answers in `os.scandir` order and the order is not the claim.

**The probe** (`.agents/slop/imagenet2/probe.bend`) is the port's loader, and it
prints the same three lines. Its output, verbatim (`.agents/slop/imagenet2/probe.out`):

```
train=train/n01440764/n01440764_10026.JPEG|train/n01440764/n01440764_10027.JPEG|train/n01440764/subdir|train/n01443537/n01443537_10007.JPEG
val=val/n01440764/n01440764_10026.JPEG|val/n01443537/n01443537_10007.JPEG
cat=goldfish=1|great white shark=2|tench=0
```

**The expectations are a SEPARATE LITERAL** (`.agents/slop/imagenet2/expected.rows`,
TAB-separated `name`/`want`), written **before** the probe was run against them,
and they come from a source that is not the thing they check: the file lists and
the class map from **CPython's answer for the same tree**, and the refusals from
**the port's own message templates read off the code** (`split.files.pick`,
`split.files.empty`, `cats.pick`). A row whose `want` were copied from its `got`
would check nothing.

**The table** (`.agents/slop/imagenet2/rows.rows`, TAB-separated `name`/`got`/`want`,
written by `.agents/slop/imagenet2/checkrows.py`, which runs the probe AND the
oracle and compares both against the literal):

| row | got == want | the oracle |
|---|---|---|
| `train_files` | YES | **the same string** |
| `val_files` | YES | **the same string** |
| `categories` | YES | **the same string** |
| `mock_categories` | YES | **the same string** |
| `train_files_absent` | YES | the oracle refuses with upstream's own `FileNotFoundError` |
| `train_files_empty` | YES | the oracle refuses with upstream's own `FileNotFoundError` |
| `categories_absent` | YES | the oracle refuses (no such file) |
| `root_absent` | YES | the oracle refuses with upstream's own `FileNotFoundError` |

**8 of 8 rows agree**, and every row where the oracle HAS an answer has the
oracle's answer too. `checkrows.py` exits 0 when they agree and 1 when they do
not, so it is a gate and not a report. Cost: **4 probe runs, 10.0 s wall** (one
bend process at a time).

---

## 6. THE CONTROL

**Perturb one expectation, show the row goes red, restore it.**

The `train_files` row's `want` was changed from `train/n01443537/n01443537_10007.JPEG`
to `train/n01443537/n01443537_99999.JPEG` (one path, one character class of
change), and the harness was re-run:

```
FAIL  train_files
PASS  val_files
PASS  categories
PASS  mock_categories
PASS  train_files_absent
PASS  train_files_empty
PASS  categories_absent
PASS  root_absent

7 of 8 rows agree with the literal expectations      (rc=1)
```

**Exactly one row went red**, the row that was perturbed went red, and the other
seven did not move -- so the row is a check and not a tautology. The expectation
was then **restored** and the harness re-run: **8 of 8, rc=0** (the restored run
is `.agents/slop/imagenet2/checkrows.out`).

### The two real defects the probe found, and what they were

The probe was NOT green on its first run, and the two defects it found are the
reason the table above is worth reading:

1. **The hidden filter was applied at ONE depth.** The first run's `train` row
   contained `train/.hidden/hidden.JPEG`, which CPython's glob does not match.
   The port filtered the depth-TWO names and not the depth-ONE ones, so a hidden
   class directory leaked in. **Fixed** by `names.vis.put` (`imagenet.bend:153`),
   which filters the depth-one names the same way.
2. **A state is entered by consuming a character.** The first run's class map
   was `REFUSED: ... expected ',' or '}'`. The reader had a `SEntry` state that
   PUSHED the entry, but the state that consumed the `]` was a different one, so
   the `,` or `}` **after** the `]` was swallowed and the reader then refused.
   **Fixed** by `ci.close` (`imagenet.bend:309`), the state that CONSUMES the `]`
   being the one that pushes the entry. A third defect, the same shape, was the
   whitespace **after** a `,`: `SKStr` is INSIDE a string and does not skip
   whitespace, so the space was read as the closing quote of an empty key --
   fixed by going through `Want{'"', SKStr{Nil{}}}`, the state that skips
   whitespace.

---

## 7. THE SCOPE LIMITS, STATED

* **This is the FILE-LIST HALF of "can we run ImageNet using Bend".** It
  answers *which files are the dataset* and *what the class index says*. It does
  **not** read a pixel, resize, crop, flip, or normalise one: the transforms
  are upstream's and they need the imaging library, which the port does not
  have. A training loop still needs `Tensor`s, and `extra/datasets/__init__.bend:20-21`
  records that the port has no ndarray and no `Tensor.empty` yet.
* **The class index is read by a FORMAT DECODER, not by a JSON parser** (section
  4.1). It refuses what it does not know. It does not read escapes (`\"`, `\\`,
  `\uXXXX`): a backslash inside a class name or key is a **refusal**, not a
  guess, and no such name exists in either shape in this repo.
* **Its whitespace is `Char.is_space`, one character wider than JSON's** (a
  vertical tab and a form feed between two tokens are accepted here and
  rejected by `json`). Named, not hidden.
* **The file lists are SORTED; upstream's are not** (`glob.glob` answers in
  `os.scandir` order). The SET is the claim; the order is the port's, for
  reproducibility.
* **A symlinked class directory is skipped by the port and followed by CPython**
  (section 4.4). The one input where the two differ, measured.
* **The port's refusal is richer than upstream's** (section 4.5): two named
  refusals where upstream has one.
* **`@functools.cache` and `@diskcache` are not ported** (section 4.2).
* **The two directory primitives are `@unsafe`**, so the file's SAFETY verdict is
  FAIL for the listing half and PASS for the reader half (section 3). There is
  no other directory listing in the port to use instead.

---

## 8. THE FILES

| file | what it is |
|---|---|
| `tinybendygrad/extra/datasets/imagenet.bend` | **the port**, 520 lines, replaces the 46-line stub |
| `.agents/slop/imagenet2/probe.bend` | the probe: the loader over the fake tree, 77 lines |
| `.agents/slop/imagenet2/probe.out` | its output, verbatim (3 lines) |
| `.agents/slop/imagenet2/expected.rows` | the HAND-WRITTEN expectations (`name`/`want`) |
| `.agents/slop/imagenet2/rows.rows` | the table (`name`/`got`/`want`), written by the harness |
| `.agents/slop/imagenet2/checkrows.py` | the harness: probe + oracle vs the literals, rc 0/1 |
| `.agents/slop/imagenet2/checkrows.out` | the harness's last (green) run |
| `.agents/slop/imagenet2/oracle.py` | the CPython oracle: upstream's logic verbatim |
| `.agents/slop/imagenet2/mkfixture.py` | the fake tree: placeholder files, no download |
| `.agents/slop/imagenet2/reader-only.bend` | the MEASUREMENT COPY that isolates the reader's verdict (`ALL PROOFS CHECK`) |
| `.agents/slop/imagenet2/t0-imports.bend` .. `t8-reader.bend` | the nine Bend measurements: the import shape (`t0`), the suffix that is NOT a smaller part (`t1`), the three tails that are (`t2`), `List.sort`'s result quant (`t3`), the declared-above rule (`t4`), the reusable let (`t5`), char literals in `match` (`t6`), `U32.read` over a char list (`t7`), and the reader's end state (`t8`) |

**NO COMMIT WAS MADE.** Nothing was staged, nothing was committed, no mutating
git command was run; every git read used `env -u GIT_INDEX_FILE`.
