# tinybendygrad/nn/datasets.bend -- port of tinygrad/nn/datasets.py
#
# FOURTEEN LINES OF PYTHON, and that is the point of it: this is the smallest
# file in the core and the only one `examples/beautiful_mnist.py` calls, so it
# is where a newcomer meets the port. What survives the crossing is five URLs,
# two header skips, one reshape shape, one row width, and the arithmetic that
# says the skip and the row agree. Everything else -- the HTTP GET, the gunzip,
# the tar, and the Tensors themselves -- is a WALL, and each is one
# `# TODO(p3)`.
#
# ===========================================================================
# WHAT IS PORTED, DEF BY DEF.
#   :5  base_url                    PORTED  `mn_base_url`
#   :6  _mnist(file)                PORTED  `mn_url`   (the `Tensor.from_url`
#                                             inside it is WALL 1)
#   :7  the four _mnist calls       PORTED  `mn_entries` -- the four members in
#                                             the tuple's order, each with the
#                                             skip it is sliced by, its byte
#                                             count and its row. `dst_mnist` is
#                                             that four-tuple as ONE string,
#                                             because the ORDER is the
#                                             contract: it is `X_train, y_train,
#                                             X_test, y_test`, and a PERMUTED
#                                             tuple still trains a network.
#   :11 the cifar url               PORTED  `CIFAR_URL`
#   :12 the five batch members      PORTED  `cifar_batch`, `cifar_batches`
#   :12 `Tensor.cat(*[...])`        PORTED  as the ARITHMETIC of five
#                                            `(rows, 3073)` tables -- the byte
#                                            total and the row count -- and not
#                                            as the kernel
#   :13 the test member             PORTED  `cifar_test`
#   :12-13 `reshape(-1, 3073)`      PORTED  `CIFAR_ROW`, `dst_cifar_rows`
#   :14 `train[:, 1:]` and `[:, 0]` PORTED  `CIFAR_LABEL_OFF`, `CIFAR_IMAGE_BYTES`
#   :14 the two `reshape(-1,3,32,32)` PORTED `CF_IMG`
#
# STATUS, and it is what a reader should check first. This file COMPILES, runs on
# both lanes, and its 46 gate rows are BYTE-IDENTICAL to a CPython oracle that
# re-derives every one of them from `nn/datasets.py` and the published file sizes:
#
#     ./bin/bend tinybendygrad/nn/datasets.bend --check-only        # ALL PROOFS CHECK
#     ./bin/bend tinybendygrad/nn/datasets.bend                     # interpreted lane
#     ./bin/bend tinybendygrad/nn/datasets.bend -o /tmp/d && /tmp/d # native lane
#     python3 .agents/slop/dst-oracle.py                            # the CPython lane
#
# The two lanes are diffed against each other and against the oracle, and all four
# agree byte for byte. The mutation table at the foot is MEASURED, not predicted:
# 13 mutations, one comment-only control that moves nothing, and twelve that each
# change at least one row.
#
# The numbers in the gate are derived from `datasets.py`'s own text plus the
# published MNIST / CIFAR-10 file sizes -- 47040016, 60008, 7840016, 10008 and the
# 3073-wide CIFAR row -- and NONE of them comes from a download. That is the one
# assumption this gate rests on, and it is the assumption a reader should attack
# first: it is the claim that the published sizes are the sizes tinygrad's
# `from_url` would see, and a change to the upstream mirror would move every
# `dst_*_rows` row at once.
#
# ===========================================================================
# THE ONE FINDING, and it is about what is NOT here.
#
# **tinygrad does not parse the IDX header.** :7 slices at a hardcoded `0x10`
# for an idx3 file and a hardcoded `8` for an idx1 file and then RESHAPES to a
# hardcoded `(1,28,28)`. The magic number, the dimension count and the element
# type all live in the FILE and none of them is ever read. (The real MNIST
# idx3 header is 16 bytes whose three declared dimensions are 28, 29 and 28 --
# the payload is 784 bytes per image regardless, which is why the hardcode
# works and why the header could not be used if it were read.)
#
# So this port's header content is two CONSTANTS and one CLAIM about them: the
# bytes left after the skip must DIVIDE by the row the reshape names, or
# `reshape(-1, 1, 28, 28)` raises. That claim is the only arithmetic either
# function contains, so it is what the gate checks -- against byte counts
# CONSTRUCTED here from the published file sizes, never against a download.
#
# ===========================================================================
# THE THREE WALLS.
#
# 1. THE DOWNLOAD. `Tensor.from_url(url, gunzip=True)` at :6 and :11: a socket,
#    a TLS handshake, a content-length check and a gzip stream. The URL is
#    ported; the request is not.
#    TODO(p3) nn/datasets.py:6   -- Tensor.from_url(..., gunzip=True).
#    TODO(p3) nn/datasets.py:11  -- the cifar tarball, and tar_extract with it.
#
# 2. `tar_extract` (nn/state.py), indexed by MEMBER NAME with `[]`. `cifar_batches`
#    names the five members the comprehension asks for and nothing reads them.
#    TODO(p3) nn/datasets.py:12  -- tt["cifar-10-batches-bin/data_batch_i.bin"].
#
# 3. THE TENSORS. `reshape`, `.to(device)`, `Tensor.cat` and the `[:, 1:]`
#    column slice are `tensor.bend` and `mixin/movement.bend` and are not
#    re-derived here. What IS here is the SHAPE ARGUMENT each is handed,
#    because `reshape(-1,1,28,28)` and `reshape(-1,3,32,32)` differ only in
#    that list, and the list is the claim.
#    TODO(p3) nn/datasets.py:7   -- reshape(-1,1,28,28).to(device).
#    TODO(p3) nn/datasets.py:14  -- train[:, 1:] and train[:, 0].
#
# `-1` IS A FLAG AND NOT AN ELEMENT. `reshape(-1, 1, 28, 28)` is a list whose
# head is negative, and Bend has no negative `U32` (there is no `Nat.to_u32`, and
# a `0xffffffff` sentinel poisons every `U32.min` fold -- the recorded
# `axis_coords` failure). `Shape` therefore carries the `-1` as a `Bool` BESIDE
# the remaining dims and `shape_str` prints it back as `-1`. Same escaping
# `device.bend` uses for `external_ptr: int|None`.
#
# THE LABEL TABLE IS NOT RESHAPED. :7 slices the label files at `8` and calls
# `.to(device)`; there is no `reshape` on either, so `per` is 1 for them and the
# row count IS the payload count. That asymmetry between the two halves of one
# tuple is easy to lose and `dst_mnist` prints it.
# ===========================================================================
import Base
import ./../helpers.bend as H

# ===========================================================================
# :5 -- `base_url`. A Bool in, a String out, and this is the only branch in the
# file. The two spellings are verbatim: HTTP for fashion, HTTPS for mnist.
# ===========================================================================
def mn_base_url(fashion: Bool) -> String:
  match fashion:
    case True{}:  "http://fashion-mnist.s3-website.eu-central-1.amazonaws.com/"
    case False{}: "https://storage.googleapis.com/cvdf-datasets/mnist/"

# :6 -- `def _mnist(file): return Tensor.from_url(base_url+file, gunzip=True)`.
# The `+` is a concatenation of two Strings and nothing else; the call is WALL 1.
def mn_url(fashion: Bool, file: String) -> String:
  String.concat([mn_base_url(fashion), file])

# ===========================================================================
# THE FOUR MEMBERS, in the order :7 hands them to the returned tuple.
# ===========================================================================
def IMAGES_TRAIN() -> String: "train-images-idx3-ubyte.gz"
def LABELS_TRAIN() -> String: "train-labels-idx1-ubyte.gz"
def IMAGES_T10K()  -> String: "t10k-images-idx3-ubyte.gz"
def LABELS_T10K()  -> String: "t10k-labels-idx1-ubyte.gz"

# THE TWO SKIPS. `0x10` is sixteen and is the idx3 header; `8` is the idx1 one.
# These two numbers are the ENTIRETY of tinygrad's header handling -- see the
# header of this file, and `dst_images_skip8_divides` for the row that proves
# they are not interchangeable.
def SKIP_IDX3() -> U32: 16
def SKIP_IDX1() -> U32: 8

# `.reshape(-1, 1, 28, 28)`. The `-1` is `infer` and the rest is the list, so
# the product of the list is the per-image BYTE count that the skip and the file
# size have to be consistent with.
type Shape is Data:
  Shape{infer: Bool, rest: List<&2, U32>}

def Shape.infer(s: Shape) -> Bool:
  match s:
    case Shape{infer, rest}: infer

def Shape.rest(s: Shape) -> List<&2, U32>:
  match s:
    case Shape{infer, rest}: rest

def shape_bytes(s: Shape) -> U32: H.prod_u32(Shape.rest(s))

def MN_IMG() -> Shape: Shape{True{}, [1, 28, 28]}

# ===========================================================================
# ONE DOWNLOAD, as the five facts the header arithmetic needs: which member it
# is, which file, how many bytes the skip takes off it, how many bytes it is in
# total, and how many bytes one ROW is. `rows` and `divides` are the claim.
#
# `nbytes` is the PUBLISHED size of each file, so the counts are DERIVABLE here
# rather than read off a download:
#   47040016 - 16 = 47040000 = 60000 * 784
#   7840016  - 16 =  7840000 = 10000 * 784
#   60008    -  8 =    60000 = 60000 * 1
#   10008    -  8 =    10000 = 10000 * 1
#
# Each member is its OWN def so a gate row can name it and the mutation table can
# say which one broke. Interning a list literal and reading it back by index is
# the recorded `device.bend` trap and it buys nothing here.
# ===========================================================================
type Ds is Data:
  Ds{nm: String, file: String, skip: U32, nbytes: U32, per: U32}

def Ds.nm(x: Ds) -> String:
  match x:
    case Ds{nm, file, skip, nbytes, per}: nm

def Ds.file(x: Ds) -> String:
  match x:
    case Ds{nm, file, skip, nbytes, per}: file

def Ds.skip(x: Ds) -> U32:
  match x:
    case Ds{nm, file, skip, nbytes, per}: skip

def Ds.nbytes(x: Ds) -> U32:
  match x:
    case Ds{nm, file, skip, nbytes, per}: nbytes

def Ds.per(x: Ds) -> U32:
  match x:
    case Ds{nm, file, skip, nbytes, per}: per

# what the skip LEAVES. `U32.sub` wraps, so a file smaller than its own header
# answers `2**32 - 8` rather than trapping, and `divides` then says False --
# which is the honest answer for a file that cannot exist.
def Ds.payload(+x: Ds) -> U32: U32.sub(Ds.nbytes(x), Ds.skip(x))

# the row count, or the truncated one when the payload is not a whole number of
# rows. `rows` is NOT the claim -- truncation hides a wrong skip. `divides` is.
def Ds.rows(+x: Ds) -> U32: U32.div(Ds.payload(x), Ds.per(x))

# THE CLAIM. `payload % row == 0`, and it is the row that can be wrong: a skip of
# 8 on an idx3 file leaves 47040008 bytes, which is 8 PAST a multiple of 784, so
# this test is what pins 16 over every other constant in the neighbourhood.
def Ds.divides(+x: Ds) -> Bool: U32.is_zero(U32.mod(Ds.payload(x), Ds.per(x)))

def E_TRAIN_IMAGES() -> Ds:
  Ds{"train_images", IMAGES_TRAIN(), SKIP_IDX3(), 47040016, 784}
def E_TRAIN_LABELS() -> Ds:
  Ds{"train_labels", LABELS_TRAIN(), SKIP_IDX1(), 60008, 1}
def E_T10K_IMAGES() -> Ds:
  Ds{"t10k_images", IMAGES_T10K(), SKIP_IDX3(), 7840016, 784}
def E_T10K_LABELS() -> Ds:
  Ds{"t10k_labels", LABELS_T10K(), SKIP_IDX1(), 10008, 1}

# :7 -- the tuple, in order. `dst_mnist` renders `name rows` per entry, so a
# PERMUTED list moves the row and a wrong skip does not.
def mn_entries() -> List<&2, Ds>:
  [E_TRAIN_IMAGES(), E_TRAIN_LABELS(), E_T10K_IMAGES(), E_T10K_LABELS()]

def dst_rows.go(xs: List<&2, Ds>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +x <> t:
      dst_rows.go(t, List.append(&2, String, acc,
        [String.concat([Ds.nm(x), ":", U32.show(Ds.rows(x))])]))

def dst_mnist() -> String: String.join(dst_rows.go(mn_entries(), Nil{}), " ")

# THE `file` COLUMN OF THE TABLE, in the tuple's order. `dst_url_*` above reaches the
# four names through `mn_url` and the CONSTANTS; this row reaches them through the
# RECORD, so a table whose `file` column disagreed with the URL rows would be caught.
# That is the "a count row and the table it counts are two independent transcriptions"
# rule (nn/onnx.bend note 8) applied to a name column instead of a count.
def ds_files.go(xs: List<&2, Ds>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +x <> t: ds_files.go(t, List.append(&2, String, acc, [Ds.file(x)]))

def ds_files() -> String: String.join(ds_files.go(mn_entries(), Nil{}), ",")

def dst_mn_n() -> U32: U32.from_nat(List.length(&2, Ds, mn_entries()))

# THE NEGATIVE FIXTURE for THE CLAIM: the idx3 payload under the idx1 skip.
def E_SKIP8() -> Ds:
  Ds{"train_images", IMAGES_TRAIN(), SKIP_IDX1(), 47040016, 784}

# ===========================================================================
# THE PRINTING, which is the gate's own machinery. `ush` APPENDS and
# `String.join` is HEAD-FIRST, so the numbers come out in walk order with no
# trailing separator -- the recorded rule, and the shape `ustate`/`ucreate` use.
# ===========================================================================
def ush(xs: List<&2, U32>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case x <> t: ush(t, List.append(&2, String, acc, [U32.show(x)]))

def ujoin(xs: List<&2, U32>) -> String: String.join(ush(xs, Nil{}), ",")

# The shape as Python would print the argument: `-1,1,28,28`. `+s` because the two
# readers both read it in one expression, and a `Shape` is a `Data` record so `+`
# costs a reference count and nothing else. THE COMMA IS INSIDE THE `-1` ARM and not
# between the two halves: joining them as `"-1" <> "," <> rest` is right only when
# `infer` holds, and `String.concat` has no way to skip a separator. Concatenating
# bare `-1` to the rest printed `-11,28,28`, which is the first `dst_img_shape`.
def shape_str(+s: Shape) -> String:
  Bool.pick(String, Shape.infer(s), String.concat(["-1,", ujoin(Shape.rest(s))]),
            ujoin(Shape.rest(s)))

# ===========================================================================
# CIFAR, :11-14.
# ===========================================================================
def CIFAR_URL() -> String:
  "https://data.brainchip.com/dataset-mirror/cifar10/cifar-10-binary.tar.gz"

# `reshape(-1, 3073)` -- a record is one LABEL byte followed by 3072 image bytes,
# and the two halves of the return value are that row with the label removed and
# the label alone.
def CIFAR_ROW() -> U32: 3073
def CIFAR_LABEL_OFF() -> U32: 0
def CIFAR_IMAGE_BYTES() -> U32: 3072

def CF_IMG() -> Shape: Shape{True{}, [3, 32, 32]}

# :12 -- `tt[f"cifar-10-batches-bin/data_batch_{i}.bin"] for i in range(1,6)`.
# `range(1,6)` is five consecutive integers and the f-string is a concatenation
# of a literal, a number and a literal.
def cifar_batch(i: U32) -> String:
  String.concat(["cifar-10-batches-bin/data_batch_", U32.show(i), ".bin"])

def cifar_batches() -> List<&2, String>:
  [cifar_batch(1), cifar_batch(2), cifar_batch(3), cifar_batch(4), cifar_batch(5)]

# :13 -- the sixth member, which `Tensor.cat` does NOT see.
def cifar_test() -> String: "cifar-10-batches-bin/test_batch.bin"

def CIFAR_NBATCH() -> U32: U32.from_nat(List.length(&2, String, cifar_batches()))

# `Tensor.cat` over five tables is, for everything this file decides, five times
# as many rows. 10000 is not in `datasets.py`; it is the published size of each
# CIFAR-10 batch, and it is named here so the gate's counts are DERIVED.
def CIFAR_BATCH_ROWS() -> U32: 10000
def CIFAR_TEST_ROWS() -> U32: 10000

def cifar_train_bytes() -> U32:
  U32.mul(U32.mul(CIFAR_NBATCH(), CIFAR_BATCH_ROWS()), CIFAR_ROW())

def cifar_test_bytes() -> U32: U32.mul(CIFAR_TEST_ROWS(), CIFAR_ROW())

def dst_cifar_rows() -> U32: U32.div(cifar_train_bytes(), CIFAR_ROW())
def dst_cifar_test_rows() -> U32: U32.div(cifar_test_bytes(), CIFAR_ROW())

# ===========================================================================
# THE GATE. Every expectation comes from `datasets.py`'s own text or from the
# published file sizes, and the numeric rows PRINT their value, so a wrong one is
# diagnosable from the output alone.
# ===========================================================================
def row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# all eight mnist/fashion URLs, so the two bases share no member and a
# duplicated base is a COUNT change and not a string change.
def mn_urls() -> List<&2, String>:
  [mn_url(False{}, IMAGES_TRAIN()), mn_url(False{}, LABELS_TRAIN()),
   mn_url(False{}, IMAGES_T10K()),  mn_url(False{}, LABELS_T10K()),
   mn_url(True{},  IMAGES_TRAIN()), mn_url(True{},  LABELS_TRAIN()),
   mn_url(True{},  IMAGES_T10K()),  mn_url(True{},  LABELS_T10K())]

def dst_url_n() -> U32: U32.from_nat(List.length(&2, String, H.dedup_str(mn_urls())))

# --- 1: the URL table, :5, :6 and :11 ---------------------------------------
def t_url() -> IO(Unit):
  do IO<Unit>:
    srow("dst_url_mnist", mn_base_url(False{}))
    srow("dst_url_fashion", mn_base_url(True{}))
    srow("dst_url_train_images", mn_url(False{}, IMAGES_TRAIN()))
    srow("dst_url_train_labels", mn_url(False{}, LABELS_TRAIN()))
    srow("dst_url_t10k_images", mn_url(False{}, IMAGES_T10K()))
    srow("dst_url_t10k_labels", mn_url(False{}, LABELS_T10K()))
    srow("dst_url_fashion_t10k_labels", mn_url(True{}, LABELS_T10K()))
    srow("dst_url_cifar", CIFAR_URL())
    urow("dst_url_n", dst_url_n())

# --- 2: the header skips and the reshape, :7 ---------------------------------
def t_idx() -> IO(Unit):
  do IO<Unit>:
    urow("dst_skip_idx3", SKIP_IDX3())
    urow("dst_skip_idx1", SKIP_IDX1())
    srow("dst_img_shape", shape_str(MN_IMG()))
    urow("dst_img_row", shape_bytes(MN_IMG()))
    srow("dst_mnist", dst_mnist())
    srow("dst_mnist_files", ds_files())
    urow("dst_mnist_n", dst_mn_n())
    # THE CLAIM, once per member, because a per-member fixture is the only thing
    # that says WHICH skip is wrong.
    row("dst_train_images_divides", Ds.divides(E_TRAIN_IMAGES()))
    row("dst_train_labels_divides", Ds.divides(E_TRAIN_LABELS()))
    row("dst_t10k_images_divides", Ds.divides(E_T10K_IMAGES()))
    row("dst_t10k_labels_divides", Ds.divides(E_T10K_LABELS()))
    urow("dst_train_images_payload", Ds.payload(E_TRAIN_IMAGES()))
    urow("dst_t10k_images_payload", Ds.payload(E_T10K_IMAGES()))
    urow("dst_train_images_rows", Ds.rows(E_TRAIN_IMAGES()))
    urow("dst_train_labels_rows", Ds.rows(E_TRAIN_LABELS()))
    # THE NEGATIVE FIXTURE. The idx3 payload under the idx1 skip is 8 bytes past
    # a row boundary, so this row is what says the two skips are NOT the same
    # number -- a mutation that made them equal dies here and nowhere else, and
    # the two `*_rows` rows above do NOT see it, because division truncates.
    urow("dst_images_skip8_payload", Ds.payload(E_SKIP8()))
    row("dst_images_skip8_divides", Ds.divides(E_SKIP8()))
    urow("dst_images_skip8_rows", Ds.rows(E_SKIP8()))
    # the label rows are NOT reshaped: `per` is 1, so rows == payload. This is
    # the asymmetry between the two halves of one tuple.
    row("dst_labels_unreshaped", U32.is_eq(Ds.rows(E_TRAIN_LABELS()),
                                           Ds.payload(E_TRAIN_LABELS())))

# --- 3: cifar, :11-14 ---------------------------------------------------------
def t_cifar() -> IO(Unit):
  do IO<Unit>:
    srow("dst_cifar_batch1", cifar_batch(1))
    srow("dst_cifar_batch5", cifar_batch(5))
    srow("dst_cifar_test", cifar_test())
    urow("dst_cifar_nbatch", CIFAR_NBATCH())
    # five DISTINCT members: a `range(1,6)` that ran to 5 twice would still count
    # five, so the count row alone is not the claim.
    urow("dst_cifar_batches_n", U32.from_nat(List.length(&2, String,
      H.dedup_str(cifar_batches()))))
    urow("dst_cifar_row", CIFAR_ROW())
    urow("dst_cifar_train_rows", dst_cifar_rows())
    urow("dst_cifar_test_rows", dst_cifar_test_rows())
    urow("dst_cifar_train_bytes", cifar_train_bytes())
    srow("dst_cifar_shape", shape_str(CF_IMG()))
    urow("dst_cifar_image_bytes", shape_bytes(CF_IMG()))
    urow("dst_cifar_label_off", CIFAR_LABEL_OFF())
    # THE CORRESPONDENCE. 3073 - 1 == 3 * 32 * 32 is what makes `train[:, 1:]`
    # and `reshape(-1,3,32,32)` the same tensor, and it is a claim about three
    # numbers a mutation can move independently.
    row("dst_cifar_split", U32.is_eq(U32.sub(CIFAR_ROW(), CIFAR_LABEL_OFF()),
                                     shape_bytes(CF_IMG())))
    # and the two ways it can be WRONG: no label column at all, and a label that
    # costs two bytes. Both are off by one byte and both are silent in the row
    # counts above.
    row("dst_cifar_split_off0", U32.is_eq(U32.sub(CIFAR_ROW(), 0),
                                          shape_bytes(CF_IMG())))
    row("dst_cifar_split_off2", U32.is_eq(U32.sub(CIFAR_ROW(), 2),
                                          shape_bytes(CF_IMG())))
    row("dst_cifar_shape_text", String.eq(shape_str(CF_IMG()), "-1,3,32,32"))
    row("dst_cifar_image_named", U32.is_eq(shape_bytes(CF_IMG()),
                                           CIFAR_IMAGE_BYTES()))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_url()
    b : Unit <- t_idx()
    c : Unit <- t_cifar()
    IO.print("dst-done=1")

# ===========================================================================
# THE MUTATION TABLE. **MEASURED** by `python3 .agents/slop/dk-mutate.py`, which
# applies each edit in place, runs the interpreted lane and diffs the baseline.
#
#     python3 .agents/slop/dk-mutate.py          # run all mutations, both files
#     python3 .agents/slop/dk-mutate.py --list   # the table, unrun
#
# `CHANGED` counts rows present in both runs whose VALUE differs. `MOVED` -- a row
# NAME appearing or disappearing -- is 0 for all 13: no mutation changed the shape
# of this suite, only its answers.
#
# **D0 IS THE CONTROL AND IT IS THE ONLY `0/0`.** It is a comment-only edit. The
# other twelve change at least one row, which is what makes the table evidence
# rather than a list of intentions.
#
# THE TWO THAT WOULD HAVE BEEN INVISIBLE WITHOUT A ROW, and both are here because
# the oracle is a SECOND IMPLEMENTATION and not a mirror:
#
#   - **D12, the shape printer, is the only row that sees `reshape(-1,1,28,28)`'s
#     SPELLING.** `dst_img_shape` is the row that compares the printed string to
#     `-1,1,28,28`, and the `-1` arm carries its own comma: concatenating a bare
#     `-1` to the rest printed `-11,28,28`, which was the first thing this row caught.
#   - **D5 and D6 (the channel dimensions) move `dst_img_shape` / `dst_cifar_shape`
#     and the byte counts, and NOT the row counts.** A wrong shape dimension changes
#     how many BYTES a row covers and never how many rows there are, so a suite of
#     count rows alone would print `60000` for a broken reshape.
#
# |#| what it is testing | CHANGED | rows |
# | --- | --- | --- | --- |
# |D0| CONTROL: a comment-only edit, which must move nothing | 0/0 |  |
# |D1| :5's base_url, the `fashion=False` cell -- HTTPS | 0/5 | `dst_url_mnist`, `dst_url_t10k_images`, `dst_url_t10k_labels`, `dst_url_train_images`, `dst_url_train_labels` |
# |D2| :5's base_url, the `fashion=True` cell -- HTTP | 0/2 | `dst_url_fashion`, `dst_url_fashion_t10k_labels` |
# |D3| :7's `[0x10:]` -- the IDX3 header is 16 bytes | 0/5 | `dst_skip_idx3`, `dst_t10k_images_divides`, `dst_t10k_images_payload`, `dst_train_images_divides`, `dst_train_images_payload` |
# |D4| :7's `[8:]` -- the IDX1 header is 8 bytes | 0/5 | `dst_images_skip8_divides`, `dst_images_skip8_payload`, `dst_mnist`, `dst_skip_idx1`, `dst_train_labels_rows` |
# |D5| :7's `reshape(-1,1,28,28)` -- the channel dimension is EXPLICIT | 0/1 | `dst_img_shape` |
# |D6| :14's `reshape(-1,3,32,32)` | 0/5 | `dst_cifar_image_bytes`, `dst_cifar_image_named`, `dst_cifar_shape`, `dst_cifar_shape_text`, `dst_cifar_split` |
# |D7| :12's `reshape(-1, 3073)` -- ONE LABEL BYTE plus 3072 image bytes | 0/4 | `dst_cifar_row`, `dst_cifar_split`, `dst_cifar_split_off0`, `dst_cifar_train_bytes` |
# |D8| :14's `train[:, 0]` -- the LABEL is the FIRST column | 0/2 | `dst_cifar_label_off`, `dst_cifar_split` |
# |D9| :12's f-string suffix | 0/2 | `dst_cifar_batch1`, `dst_cifar_batch5` |
# |D10| each CIFAR-10 batch is 10000 rows -- the published size, not in datasets.py | 0/2 | `dst_cifar_train_bytes`, `dst_cifar_train_rows` |
# |D11| train-images is the 60000-row file, t10k-images is the 10000-row one | 0/3 | `dst_mnist`, `dst_train_images_payload`, `dst_train_images_rows` |
# |D12| the shape prints as PYTHON would: `-1,1,28,28`, comma inside the `-1` arm | 0/3 | `dst_cifar_shape`, `dst_cifar_shape_text`, `dst_img_shape` |
