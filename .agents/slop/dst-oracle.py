#!/usr/bin/env python3
"""CPython oracle for tinybendygrad/nn/datasets.bend.

THIRD LANE. It imports NOTHING from `tinygrad` on purpose: `mnist()` never reads the
IDX header, so every claim in the .bend file is either a literal from
`nn/datasets.py`'s text or arithmetic over the PUBLISHED file sizes -- and a shared
helper would only let a mis-transcription travel.

    python3 .agents/slop/dst-oracle.py > /tmp/dst.txt
    ./bin/bend tinybendygrad/nn/datasets.bend > /tmp/dst.bend
    diff /tmp/dst.txt /tmp/dst.bend

ROW NAMES MATCH THE .bend GATE EXACTLY, and `print` (not `sys.stdout.write`) is what
reproduces `IO.print`'s own trailing newline.
"""

rows = []
def row(nm, b): rows.append(f"{nm}={b}")
def urow(nm, v): rows.append(f"{nm}={v}")
def srow(nm, v): rows.append(f"{nm}={v}")

# --- nn/datasets.py:5-8 verbatim ---------------------------------------------
MNIST_URL = "https://storage.googleapis.com/cvdf-datasets/mnist/"
FASHION_URL = "http://fashion-mnist.s3-website.eu-central-1.amazonaws.com/"
CIFAR_URL = "https://data.brainchip.com/dataset-mirror/cifar10/cifar-10-binary.tar.gz"

IMAGES_TRAIN, LABELS_TRAIN = "train-images-idx3-ubyte.gz", "train-labels-idx1-ubyte.gz"
IMAGES_T10K, LABELS_T10K = "t10k-images-idx3-ubyte.gz", "t10k-labels-idx1-ubyte.gz"

# :7 -- the two hardcoded skips, and the hardcoded reshape. THE FINDING of the
# port is that tinygrad reads NO header: the magic, the dimension count and the
# element type are in the file and none of them is consulted.
SKIP_IDX3, SKIP_IDX1 = 0x10, 8
IMG_DIMS, LBL_DIMS = (1, 28, 28), (1,)
CIFAR_ROW, CIFAR_LABEL_OFF = 3073, 1
CF_DIMS = (3, 32, 32)
CIFAR_BATCHES = [f"cifar-10-batches-bin/data_batch_{i}.bin" for i in range(1, 6)]
CIFAR_TEST = "cifar-10-batches-bin/test_batch.bin"

def prod(xs):
  p = 1
  for x in xs: p *= x
  return p

def shape_str(dims): return "-1," + ",".join(str(d) for d in dims)

def mn_url(fashion, file): return (FASHION_URL if fashion else MNIST_URL) + file

# the PUBLISHED sizes of the four MNIST files. These are what make the counts
# DERIVABLE rather than read off a download.
MN = [("train_images", IMAGES_TRAIN, SKIP_IDX3, 47040016, prod(IMG_DIMS)),
      ("train_labels", LABELS_TRAIN, SKIP_IDX1, 60008, prod(LBL_DIMS)),
      ("t10k_images",  IMAGES_T10K,  SKIP_IDX3, 7840016, prod(IMG_DIMS)),
      ("t10k_labels",  LABELS_T10K,  SKIP_IDX1, 10008,   prod(LBL_DIMS))]
# the negative fixture for THE CLAIM: the idx3 payload under the idx1 skip
SKIP8 = ("train_images", IMAGES_TRAIN, SKIP_IDX1, 47040016, prod(IMG_DIMS))

def payload(e): return e[3] - e[2]
def rows_of(e): return payload(e) // e[4]
def divides(e): return payload(e) % e[4] == 0

def t_url():
  srow("dst_url_mnist", MNIST_URL)
  srow("dst_url_fashion", FASHION_URL)
  srow("dst_url_train_images", mn_url(False, IMAGES_TRAIN))
  srow("dst_url_train_labels", mn_url(False, LABELS_TRAIN))
  srow("dst_url_t10k_images", mn_url(False, IMAGES_T10K))
  srow("dst_url_t10k_labels", mn_url(False, LABELS_T10K))
  srow("dst_url_fashion_t10k_labels", mn_url(True, LABELS_T10K))
  srow("dst_url_cifar", CIFAR_URL)
  eight = [mn_url(f, n) for f in (False, True)
           for n in (IMAGES_TRAIN, LABELS_TRAIN, IMAGES_T10K, LABELS_T10K)]
  urow("dst_url_n", len(dict.fromkeys(eight)))

def t_idx():
  urow("dst_skip_idx3", SKIP_IDX3)
  urow("dst_skip_idx1", SKIP_IDX1)
  srow("dst_img_shape", shape_str(IMG_DIMS))
  urow("dst_img_row", prod(IMG_DIMS))
  srow("dst_mnist", " ".join(f"{e[0]}:{rows_of(e)}" for e in MN))
  srow("dst_mnist_files", ",".join(e[1] for e in MN))
  urow("dst_mnist_n", len(MN))
  row("dst_train_images_divides", divides(MN[0]))
  row("dst_train_labels_divides", divides(MN[1]))
  row("dst_t10k_images_divides", divides(MN[2]))
  row("dst_t10k_labels_divides", divides(MN[3]))
  urow("dst_train_images_payload", payload(MN[0]))
  urow("dst_t10k_images_payload", payload(MN[2]))
  urow("dst_train_images_rows", rows_of(MN[0]))
  urow("dst_train_labels_rows", rows_of(MN[1]))
  urow("dst_images_skip8_payload", payload(SKIP8))
  row("dst_images_skip8_divides", divides(SKIP8))
  urow("dst_images_skip8_rows", rows_of(SKIP8))
  row("dst_labels_unreshaped", rows_of(MN[1]) == payload(MN[1]))

def t_cifar():
  srow("dst_cifar_batch1", CIFAR_BATCHES[0])
  srow("dst_cifar_batch5", CIFAR_BATCHES[-1])
  srow("dst_cifar_test", CIFAR_TEST)
  urow("dst_cifar_nbatch", len(CIFAR_BATCHES))
  urow("dst_cifar_batches_n", len(dict.fromkeys(CIFAR_BATCHES)))
  urow("dst_cifar_row", CIFAR_ROW)
  batch_rows, test_rows = 10000, 10000
  urow("dst_cifar_train_rows", len(CIFAR_BATCHES) * batch_rows)
  urow("dst_cifar_test_rows", test_rows)
  urow("dst_cifar_train_bytes", len(CIFAR_BATCHES) * batch_rows * CIFAR_ROW)
  srow("dst_cifar_shape", shape_str(CF_DIMS))
  urow("dst_cifar_image_bytes", prod(CF_DIMS))
  urow("dst_cifar_label_off", CIFAR_LABEL_OFF)
  row("dst_cifar_split", CIFAR_ROW - CIFAR_LABEL_OFF == prod(CF_DIMS))
  row("dst_cifar_split_off0", CIFAR_ROW - 0 == prod(CF_DIMS))
  row("dst_cifar_split_off2", CIFAR_ROW - 2 == prod(CF_DIMS))
  row("dst_cifar_shape_text", shape_str(CF_DIMS) == "-1,3,32,32")
  row("dst_cifar_image_named", prod(CF_DIMS) == CIFAR_ROW - CIFAR_LABEL_OFF)

for fn in (t_url, t_idx, t_cifar): fn()
rows.append("dst-done=1")   # the Bend main's sentinel, so the diff is byte-for-byte
print("\n".join(rows))