# STUB -- 1:1 PATH MIRROR of extra/datasets/__init__.py (43 LOC upstream). NOT YET PORTED.
#
# WHAT UPSTREAM IS. Two loaders, and NEITHER is a bare `fetch`: both do real work on
# the bytes AFTER the download, which is why this file is class (b) and not (a).
#   * `fetch_mnist(tensors=False)` (upstream:6) is four `fetch` calls and then IDX
#     header arithmetic -- `[0x10:]` on the images (upstream:8, skipping the 16-byte
#     magic+count header) and `[8:]` on the labels (upstream:9) -- then
#     `.reshape((-1, 28*28))` and `.astype(np.float32)`.
#   * `fetch_cifar()` (upstream:20) is ONE `fetch` and then `tarfile.open(fn,
#     mode='r:gz')` (upstream:34), a `pickle.load` per batch (upstream:35-36) and
#     `_load_disk_tensor` (upstream:26), whose
#     `assert idx == X.shape[0] and X.shape[0] == Y.shape[0]` (upstream:31) is the
#     batch-boundary claim the whole loader rests on.
# TODO(port): STOPPED AT `fetch_mnist` (extra/datasets/__init__.py:6). MISSING:
#   (1) `fetch` ITSELF. `tinybendygrad/helpers.bend:2815` records the whole HTTP
#       seam as unported -- "The HTTP machinery (fetch, fetch_fw,
#       _ensure_downloads_dir) is urllib plus a temp file plus an atomic rename ...
#       I/O of exactly the kind the master plan puts in runtime/" -- and
#       `helpers.bend` has no `fetch` def to call.
#   (2) AN NDARRAY. `.reshape`, `.astype` and `np.frombuffer` have no counterpart
#       here: `Tensor` in `tensor.bend` is a UOp slot in an arena, not a buffer, so
#       `parse(...)` (upstream:7) cannot be written at all yet.
#   (3) `gzip`, `tarfile`, `pickle`, and `os.path.isfile` for the `/tmp/cifar_extracted`
#       cache flag (upstream:25).
# NOT PORTED, AND NAMED SO NOBODY INVENTS IT: `cifar_mean` (upstream:15),
#   `cifar_std` (upstream:16), `_load_disk_tensor` (upstream:26).
#
# WHY THESE DEFUSE RETURN `Refused` INSTEAD OF UPSTREAM'S RETURN TYPE. `fetch_mnist`
# returns four ndarrays, or four `Tensor`s when `tensors=True`; `fetch_cifar` returns
# four `Tensor.empty` disk buffers. Neither type exists at this seam, so the return
# type here is `Refused` and NOT a four-tuple. The alternative -- returning an empty
# list, which is what a thin stub reaches for -- is a value indistinguishable from a
# dataset of size zero, and a dataset loader that can report an empty dataset instead
# of admitting it is absent is the one lie this file must not tell.
#
# `Refused`/`refuse` are declared HERE and imported as `D` by the sibling stubs, so
# the refusal is one definition rather than ten copies of it.
import Base

type Refused is Data:
  Refused{at: String}

# `at` is the upstream `path:line function` of the def that is missing, so a refusal
# carries the address of the work rather than a claim that there is none.
def refuse(at: String) -> Refused:
  Refused{at}

# upstream: `def fetch_mnist(tensors=False)` -> 4 numpy arrays, or 4 `Tensor`s
def fetch_mnist(tensors: Bool) -> Refused:
  refuse("extra/datasets/__init__.py:6 fetch_mnist")

# upstream: `def fetch_cifar()` -> 4 `Tensor.empty` on `disk:/tmp/cifar_{train,test}_{x,y}`
def fetch_cifar() -> Refused:
  refuse("extra/datasets/__init__.py:20 fetch_cifar")