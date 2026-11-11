# gates/datasets-gate.bend -- the gate driver for `tinybendygrad/nn/datasets.bend`.
#
# The rows moved here from the port file, which keeps the port and loses the
# instrument: `gates/README.md:173` -- "a gate's `.bend` driver and its CPython
# oracle sit in `gates/`, named by the gate that needs them."
#
# Every row calls a port def through `P.` and defines nothing the port needs.

import Base
import ./../tinybendygrad/nn/datasets.bend as P

import ./../tinybendygrad/helpers.bend as H
def row(nm: String, b: Bool) -> IO(Unit):
  IO.print(String.concat([nm, "=", Bool.show(b)]))
def urow(nm: String, v: U32) -> IO(Unit):
  IO.print(String.concat([nm, "=", U32.show(v)]))
def srow(nm: String, v: String) -> IO(Unit):
  IO.print(String.concat([nm, "=", v]))

# all eight mnist/fashion URLs, so the two bases share no member and a
# duplicated base is a COUNT change and not a string change.
def mn_urls() -> List<&2, String>:
  [P.mn_url(False{}, P.IMAGES_TRAIN()), P.mn_url(False{}, P.LABELS_TRAIN()),
   P.mn_url(False{}, P.IMAGES_T10K()),  P.mn_url(False{}, P.LABELS_T10K()),
   P.mn_url(True{},  P.IMAGES_TRAIN()), P.mn_url(True{},  P.LABELS_TRAIN()),
   P.mn_url(True{},  P.IMAGES_T10K()),  P.mn_url(True{},  P.LABELS_T10K())]

def dst_url_n() -> U32: U32.from_nat(List.length(&2, String, H.dedup_str(mn_urls())))

# --- 1: the URL table, :5, :6 and :11 ---------------------------------------
def t_url() -> IO(Unit):
  do IO<Unit>:
    srow("dst_url_mnist", P.mn_base_url(False{}))
    srow("dst_url_fashion", P.mn_base_url(True{}))
    srow("dst_url_train_images", P.mn_url(False{}, P.IMAGES_TRAIN()))
    srow("dst_url_train_labels", P.mn_url(False{}, P.LABELS_TRAIN()))
    srow("dst_url_t10k_images", P.mn_url(False{}, P.IMAGES_T10K()))
    srow("dst_url_t10k_labels", P.mn_url(False{}, P.LABELS_T10K()))
    srow("dst_url_fashion_t10k_labels", P.mn_url(True{}, P.LABELS_T10K()))
    srow("dst_url_cifar", P.CIFAR_URL())
    urow("dst_url_n", dst_url_n())

# --- 2: the header skips and the reshape, :7 ---------------------------------
def t_idx() -> IO(Unit):
  do IO<Unit>:
    urow("dst_skip_idx3", P.SKIP_IDX3())
    urow("dst_skip_idx1", P.SKIP_IDX1())
    srow("dst_img_shape", P.shape_str(P.MN_IMG()))
    urow("dst_img_row", P.shape_bytes(P.MN_IMG()))
    srow("dst_mnist", P.dst_mnist())
    srow("dst_mnist_files", P.ds_files())
    urow("dst_mnist_n", P.dst_mn_n())
    # THE CLAIM, once per member, because a per-member fixture is the only thing
    # that says WHICH skip is wrong.
    row("dst_train_images_divides", P.Ds.divides(P.E_TRAIN_IMAGES()))
    row("dst_train_labels_divides", P.Ds.divides(P.E_TRAIN_LABELS()))
    row("dst_t10k_images_divides", P.Ds.divides(P.E_T10K_IMAGES()))
    row("dst_t10k_labels_divides", P.Ds.divides(P.E_T10K_LABELS()))
    urow("dst_train_images_payload", P.Ds.payload(P.E_TRAIN_IMAGES()))
    urow("dst_t10k_images_payload", P.Ds.payload(P.E_T10K_IMAGES()))
    urow("dst_train_images_rows", P.Ds.rows(P.E_TRAIN_IMAGES()))
    urow("dst_train_labels_rows", P.Ds.rows(P.E_TRAIN_LABELS()))
    # THE NEGATIVE FIXTURE. The idx3 payload under the idx1 skip is 8 bytes past
    # a row boundary, so this row is what says the two skips are NOT the same
    # number -- a mutation that made them equal dies here and nowhere else, and
    # the two `*_rows` rows above do NOT see it, because division truncates.
    urow("dst_images_skip8_payload", P.Ds.payload(P.E_SKIP8()))
    row("dst_images_skip8_divides", P.Ds.divides(P.E_SKIP8()))
    urow("dst_images_skip8_rows", P.Ds.rows(P.E_SKIP8()))
    # the label rows are NOT reshaped: `per` is 1, so rows == payload. This is
    # the asymmetry between the two halves of one tuple.
    row("dst_labels_unreshaped", U32.is_eq(P.Ds.rows(P.E_TRAIN_LABELS()),
                                           P.Ds.payload(P.E_TRAIN_LABELS())))

# --- 3: cifar, :11-14 ---------------------------------------------------------
def t_cifar() -> IO(Unit):
  do IO<Unit>:
    srow("dst_cifar_batch1", P.cifar_batch(1))
    srow("dst_cifar_batch5", P.cifar_batch(5))
    srow("dst_cifar_test", P.cifar_test())
    urow("dst_cifar_nbatch", P.CIFAR_NBATCH())
    # five DISTINCT members: a `range(1,6)` that ran to 5 twice would still count
    # five, so the count row alone is not the claim.
    urow("dst_cifar_batches_n", U32.from_nat(List.length(&2, String,
      H.dedup_str(P.cifar_batches()))))
    urow("dst_cifar_row", P.CIFAR_ROW())
    urow("dst_cifar_train_rows", P.dst_cifar_rows())
    urow("dst_cifar_test_rows", P.dst_cifar_test_rows())
    urow("dst_cifar_train_bytes", P.cifar_train_bytes())
    srow("dst_cifar_shape", P.shape_str(P.CF_IMG()))
    urow("dst_cifar_image_bytes", P.shape_bytes(P.CF_IMG()))
    urow("dst_cifar_label_off", P.CIFAR_LABEL_OFF())
    # THE CORRESPONDENCE. 3073 - 1 == 3 * 32 * 32 is what makes `train[:, 1:]`
    # and `reshape(-1,3,32,32)` the same tensor, and it is a claim about three
    # numbers a mutation can move independently.
    # THE IMAGE is what follows the label, so its byte count is the row minus the
    # ONE label byte. The LABEL's own offset is 0 and is a different fact, and
    # conflating the two is what made this row disagree with the oracle.
    row("dst_cifar_split", U32.is_eq(U32.sub(P.CIFAR_ROW(), 1),
                                     P.shape_bytes(P.CF_IMG())))
    # and the two ways it can be WRONG: no label column at all, and a label that
    # costs two bytes. Both are off by one byte and both are silent in the row
    # counts above.
    row("dst_cifar_split_off0", U32.is_eq(U32.sub(P.CIFAR_ROW(), 0),
                                          P.shape_bytes(P.CF_IMG())))
    row("dst_cifar_split_off2", U32.is_eq(U32.sub(P.CIFAR_ROW(), 2),
                                          P.shape_bytes(P.CF_IMG())))
    row("dst_cifar_shape_text", String.eq(P.shape_str(P.CF_IMG()), "-1,3,32,32"))
    row("dst_cifar_image_named", U32.is_eq(P.shape_bytes(P.CF_IMG()),
                                           P.CIFAR_IMAGE_BYTES()))

# the `.npy` path -- mnist without the socket.
#
# WHAT THIS IS. A SECOND ROUTE to the same four tensors, one that does not go
# through `Tensor.from_url` and therefore does not go through WALL 1. The BYTES
# are PREPARED ON THE HOST -- that is DATA PREPARATION and not the port -- and
# the ARITHMETIC of the files they land in is here, in the port.
#
# THE `.npy` v1 FORMAT, as the port reads it. The header is
#
#     6 bytes  the magic  \x93NUMPY
#     2 bytes  the version  1.0
#     2 bytes  the header's OWN LENGTH, little-endian uint16
#     L bytes  the header dict, space-padded so that 10 + L is a multiple of 64
#
# and the PAYLOAD follows it, `numel * itemsize` bytes. So
#
#     file_bytes = 10 + header_len + payload_bytes
#
# and the header's length field IS the presence check. => WALL 4,
# `os.path.isfile`, is not called by this path, and that is deliberate: a `.npy`
# file that is not there fails to open, and one that is truncated fails to
# decode, so the length field answers "is this file whole" and the open answers
# "is it there". The port does not need a third question.
#
# THE FOUR WALLS, RE-EXAMINED. `tinybendygrad/nn/mnist_cnn.bend`'s header
# carries the long version. The short one is:
#
#   W1 THE HTTP GET -- STILL A WALL. The `.npy` route moves the socket to
#      the HOST and leaves the port the arithmetic. It does not make the port
#      capable of a socket and it does not pretend to.
#   W2 the tensors -- still a wall for `tensor.bend`'s `Tensor`, which is a
#      UOP SLOT IN AN ARENA AND NOT A BUFFER. What IS here is the shape and
#      the byte count the tensor would have, which is the arithmetic half of
#      `reshape(-1,1,28,28)` and of the `.to(device)`.
#   W3 `tarfile`/`pickle` -- NOT REACHED. MNIST has no tar and no pickle;
#      the label file is a flat `uint8` vector and the image file is a `uint8`
#      matrix. The wall is untouched and it is named so that "not reached" is a
#      measurement and not an omission.
#   W4 `os.path.isfile` -- NOT CALLED, as above.
#
# what the `.npy` path and the idx path must agree on. Both produce the same
# four tensors, so the row counts, the byte counts and the per-image row width
# are the SAME NUMBERS, and `dst_npy_matches_idx` is the row that says so. The
# two routes read different bytes -- the IDX files carry a 16- or 8-byte header
# and the `.npy` files carry a 118-byte one -- and the SAME payload after it,
# which is why the two payloads agree and the two file sizes do not.

# the `.npy` header's three fixed parts and the one field that is not fixed.
def NPY_MAGIC() -> U32: 6
def NPY_VERSION() -> U32: 2
def NPY_LENFIELD() -> U32: 2
def NPY_FIXED() -> U32: 10

# `|u1` -- the dtype all four files carry, and its ITEM size. `|u1` is
# numpy's spelling for "one unsigned byte, no byte order", and it is the
# dtype the MNIST payload has in every representation.
def NPY_U1_ITEM() -> U32: 1

# ONE `.npy` FILE: its name, its file name, its header's own length, and its
# shape. The shape is EXPLICIT -- a `.npy` header states the dimensions and
# there is no `-1` to infer -- so `infer` is False and `P.shape_str` prints the
# dimensions without a leading `-1`.
type Npy is Data:
  Npy{nm: String, file: String, header_len: U32, shape: P.Shape}

def Npy.nm(x: Npy) -> String:
  match x:
    case Npy{nm, file, header_len, shape}: nm

def Npy.file(x: Npy) -> String:
  match x:
    case Npy{nm, file, header_len, shape}: file

def Npy.header_len(x: Npy) -> U32:
  match x:
    case Npy{nm, file, header_len, shape}: header_len

def Npy.shape(x: Npy) -> P.Shape:
  match x:
    case Npy{nm, file, header_len, shape}: shape

# THE ELEMENT COUNT, and then the PAYLOAD. `Npy.dims` is a projection, so each
# call makes a FRESH list and the two uses of the shape do not collide.
def Npy.dims(x: Npy) -> List<&2, U32>: P.Shape.rest(Npy.shape(x))

def Npy.numel(x: Npy) -> U32: H.prod_u32(Npy.dims(x))

def Npy.payload(x: Npy) -> U32: U32.mul(Npy.numel(x), NPY_U1_ITEM())

# THE BYTES PER ROW, and it is DERIVED and not typed: it is the product of
# every dimension but the first. For the image files that is 1*28*28 = 784 --
# the same row width `P.Ds.per` carries on the IDX side -- and for the label
# files it is the empty product, which is 1 (`prod_u32` of `Nil{}` is 1, and
# `helpers.py:14`'s `prod` says so). => the label files' row count is their
# ELEMENT COUNT, and the same `rows` def says so for both halves of the tuple
# because the per-row width is derived rather than written down twice.
def Npy.per(x: Npy) -> U32: H.prod_u32(List.drop(&2, U32, Npy.dims(x), 1n))

# THE FILE SIZE, which is the header plus the payload. `+x` because the record
# is read twice -- once for the header's length and once for the payload -- and
# a `Data` record may be read twice.
def Npy.file_bytes(+x: Npy) -> U32:
  U32.add(U32.add(NPY_FIXED(), Npy.header_len(x)), Npy.payload(x))

# THE CLAIM, and it is the SAME claim the IDX path makes: the payload is a
# whole number of rows. A `.npy` payload that is not would be a truncated
# write, and this is the row that would say so.
def Npy.divides(+x: Npy) -> Bool: U32.is_zero(U32.mod(Npy.payload(x), Npy.per(x)))

def Npy.rows(+x: Npy) -> U32: U32.div(Npy.payload(x), Npy.per(x))

# the label files are not reshaped: one dimension, and the row count is the
# element count. This is the same asymmetry between the two halves of one tuple
# that `dst_labels_unreshaped` records on the IDX side.
def Npy.flat(x: Npy) -> Bool: U32.is_eq(U32.from_nat(List.length(&2, U32, Npy.dims(x))), 1)

def NPY_TRAIN_IMAGES() -> Npy:
  Npy{"train_images", "mnist_train_images.npy", 118, P.Shape{False{}, [60000, 1, 28, 28]}}
def NPY_TRAIN_LABELS() -> Npy:
  Npy{"train_labels", "mnist_train_labels.npy", 118, P.Shape{False{}, [60000]}}
def NPY_T10K_IMAGES() -> Npy:
  Npy{"t10k_images", "mnist_test_images.npy", 118, P.Shape{False{}, [10000, 1, 28, 28]}}
def NPY_T10K_LABELS() -> Npy:
  Npy{"t10k_labels", "mnist_test_labels.npy", 118, P.Shape{False{}, [10000]}}

def npy_entries() -> List<&2, Npy>:
  [NPY_TRAIN_IMAGES(), NPY_TRAIN_LABELS(), NPY_T10K_IMAGES(), NPY_T10K_LABELS()]

def dst_npy_n() -> U32: U32.from_nat(List.length(&2, Npy, npy_entries()))

# THE FILE COLUMN of the `.npy` table, in the tuple's order, for the same
# reason `P.ds_files` exists on the IDX side: a table whose file column disagreed
# with the rows above it would be caught by the column and not by the counts.
def npy_files.go(xs: List<&2, Npy>, acc: List<&2, String>) -> List<&2, String>:
  match xs:
    case Nil{}: acc
    case +x <> t: npy_files.go(t, List.append(&2, String, acc, [Npy.file(x)]))

def npy_files() -> String: String.join(npy_files.go(npy_entries(), Nil{}), ",")

# --- 4: the `.npy` path -----------------------------------------------------
def t_npy() -> IO(Unit):
  do IO<Unit>:
    srow("dst_npy_train_images_file", Npy.file(NPY_TRAIN_IMAGES()))
    srow("dst_npy_train_images_shape", P.shape_str(Npy.shape(NPY_TRAIN_IMAGES())))
    urow("dst_npy_train_images_payload", Npy.payload(NPY_TRAIN_IMAGES()))
    urow("dst_npy_train_images_file_bytes", Npy.file_bytes(NPY_TRAIN_IMAGES()))
    urow("dst_npy_train_images_rows", Npy.rows(NPY_TRAIN_IMAGES()))
    srow("dst_npy_train_labels_file", Npy.file(NPY_TRAIN_LABELS()))
    srow("dst_npy_train_labels_shape", P.shape_str(Npy.shape(NPY_TRAIN_LABELS())))
    urow("dst_npy_train_labels_payload", Npy.payload(NPY_TRAIN_LABELS()))
    urow("dst_npy_train_labels_file_bytes", Npy.file_bytes(NPY_TRAIN_LABELS()))
    urow("dst_npy_train_labels_rows", Npy.rows(NPY_TRAIN_LABELS()))
    srow("dst_npy_t10k_images_file", Npy.file(NPY_T10K_IMAGES()))
    srow("dst_npy_t10k_images_shape", P.shape_str(Npy.shape(NPY_T10K_IMAGES())))
    urow("dst_npy_t10k_images_payload", Npy.payload(NPY_T10K_IMAGES()))
    urow("dst_npy_t10k_images_file_bytes", Npy.file_bytes(NPY_T10K_IMAGES()))
    urow("dst_npy_t10k_images_rows", Npy.rows(NPY_T10K_IMAGES()))
    srow("dst_npy_t10k_labels_file", Npy.file(NPY_T10K_LABELS()))
    srow("dst_npy_t10k_labels_shape", P.shape_str(Npy.shape(NPY_T10K_LABELS())))
    urow("dst_npy_t10k_labels_payload", Npy.payload(NPY_T10K_LABELS()))
    urow("dst_npy_t10k_labels_file_bytes", Npy.file_bytes(NPY_T10K_LABELS()))
    urow("dst_npy_t10k_labels_rows", Npy.rows(NPY_T10K_LABELS()))
    # THE HEADER'S OWN LENGTH, and it is the same for all four because the
    # header dict's TEXT is the same length for a four-dim and a one-dim shape:
    # "(10000, 1, 28, 28)" and "(10000,)" are the same number of characters
    # after the padding, and the padding is what makes the total a multiple of
    # 64. ONE row for all four, and the per-file rows above carry the file
    # sizes that depend on it.
    urow("dst_npy_header_len", Npy.header_len(NPY_TRAIN_IMAGES()))
    urow("dst_npy_fixed", NPY_FIXED())
    urow("dst_npy_n", dst_npy_n())
    srow("dst_npy_files", npy_files())
    # THE CLAIM, on the `.npy` payload.
    row("dst_npy_train_images_divides", Npy.divides(NPY_TRAIN_IMAGES()))
    row("dst_npy_t10k_images_divides", Npy.divides(NPY_T10K_IMAGES()))
    # THE ASYMMETRY, on the `.npy` side.
    row("dst_npy_labels_flat", Npy.flat(NPY_TRAIN_LABELS()))
    row("dst_npy_images_not_flat", Bool.not(Npy.flat(NPY_TRAIN_IMAGES())))
    # THE TWO ROUTES MUST AGREE on the payload and on the row count, and they
    # must NOT agree on the file size -- the IDX files carry a 16- or 8-byte
    # header and the `.npy` files carry a 118-byte one. Three rows, because a
    # single "they agree" row would be true if the payloads agreed AND if the
    # file sizes agreed, and the second is wrong.
    row("dst_npy_matches_idx_payload", U32.is_eq(Npy.payload(NPY_TRAIN_IMAGES()),
                                                 P.Ds.payload(P.E_TRAIN_IMAGES())))
    row("dst_npy_matches_idx_rows", U32.is_eq(Npy.rows(NPY_TRAIN_IMAGES()),
                                               P.Ds.rows(P.E_TRAIN_IMAGES())))
    row("dst_npy_differs_idx_file", Bool.not(U32.is_eq(Npy.file_bytes(NPY_TRAIN_IMAGES()),
                                                        P.Ds.nbytes(P.E_TRAIN_IMAGES()))))

def main() -> IO(Unit):
  do IO<Unit>:
    a : Unit <- t_url()
    b : Unit <- t_idx()
    c : Unit <- t_cifar()
    d : Unit <- t_npy()
    IO.print("dst-done=1")

# THE MUTATION TABLE. MEASURED by `.venv/bin/python gates/datasets-mutate.py`, which
# applies each edit in place, runs the interpreted lane and diffs the baseline.
# (RESTORED 2026-10-16 from `.agents/slop/dk-mutate.py`, blob e853efc4b, 20941 B, byte for
# byte. The sweep of 2026-10-05 took it and this recipe outlived it, which made the recipe a
# claim about a file that did not exist.)
#
#     .venv/bin/python gates/datasets-mutate.py          # run all mutations, both files
#     .venv/bin/python gates/datasets-mutate.py --list   # the table, unrun
#
# `CHANGED` counts rows present in both runs whose VALUE differs. `MOVED` -- a row
# NAME appearing or disappearing -- is 0 for all 13: no mutation changed the shape
# of this suite, only its answers.
#
# D0 IS THE CONTROL AND IT IS THE ONLY `0/0`. It is a comment-only edit. The
# other twelve change at least one row, which is what makes the table evidence
# rather than a list of intentions.
#
# the two that would have been invisible without a row, and both are here because
# the oracle is a SECOND IMPLEMENTATION and not a mirror:
#
#   - D12, the shape printer, is the only row that sees `reshape(-1,1,28,28)`'s
#     SPELLING. `dst_img_shape` is the row that compares the printed string to
#     `-1,1,28,28`, and the `-1` arm carries its own comma: concatenating a bare
#     `-1` to the rest printed `-11,28,28`, which was the first thing this row caught.
#   - D5 and D6 (the channel dimensions) move `dst_img_shape` / `dst_cifar_shape`
#     and the byte counts, and NOT the row counts. A wrong shape dimension changes
#     how many BYTES a row covers and never how many rows there are, so a suite of
#     count rows alone would print `60000` for a broken reshape.
#
# |#| what it is testing | CHANGED | rows |
# | --- | --- | --- | --- |
# |D0| CONTROL: a comment-only edit, which must move nothing | 0/0 |  |
# |D1| :5's base_url, the `fashion=False` cell -- HTTPS | 0/5 | `dst_url_mnist`, `dst_url_t10k_images`, `dst_url_t10k_labels`, `dst_url_train_images`, `dst_url_train_labels` |
# |D2| :5's base_url, the `fashion=True` cell -- HTTP | 0/2 | `dst_url_fashion`, `dst_url_fashion_t10k_labels` |
# |D3| :7's `[0x10:]` -- the IDX3 header is 16 bytes | 0/5 | `dst_skip_idx3`, `dst_t10k_images_divides`, `dst_t10k_images_payload`, `dst_train_images_divides`, `dst_train_images_payload` |
# |D4| :7's `[8:]` -- the IDX1 header is 8 bytes | 0/5 | `dst_images_skip8_divides`, `dst_images_skip8_payload`, `P.dst_mnist`, `dst_skip_idx1`, `dst_train_labels_rows` |
# |D5| :7's `reshape(-1,1,28,28)` -- the channel dimension is EXPLICIT | 0/1 | `dst_img_shape` |
# |D6| :14's `reshape(-1,3,32,32)` | 0/5 | `dst_cifar_image_bytes`, `dst_cifar_image_named`, `dst_cifar_shape`, `dst_cifar_shape_text`, `dst_cifar_split` |
# |D7| :12's `reshape(-1, 3073)` -- ONE LABEL BYTE plus 3072 image bytes | 0/4 | `dst_cifar_row`, `dst_cifar_split`, `dst_cifar_split_off0`, `dst_cifar_train_bytes` |
# |D8| :14's `train[:, 0]` -- the LABEL is the FIRST column | 0/2 | `dst_cifar_label_off`, `dst_cifar_split` |
# |D9| :12's f-string suffix | 0/2 | `dst_cifar_batch1`, `dst_cifar_batch5` |
# |D10| each CIFAR-10 batch is 10000 rows -- the published size, not in datasets.py | 0/2 | `dst_cifar_train_bytes`, `dst_cifar_train_rows` |
# |D11| train-images is the 60000-row file, t10k-images is the 10000-row one | 0/3 | `P.dst_mnist`, `dst_train_images_payload`, `dst_train_images_rows` |
# |D12| the shape prints as PYTHON would: `-1,1,28,28`, comma inside the `-1` arm | 0/3 | `dst_cifar_shape`, `dst_cifar_shape_text`, `dst_img_shape` |
