# STUB -- 1:1 PATH MIRROR of extra/datasets/fake_imagenet_from_mnist.py (40 LOC upstream). NOT YET PORTED.
#
# WHAT UPSTREAM IS. The `MNISTMOCK` path made real: it writes a 10-class ImageNet
# tree of upscaled 28x28 MNIST digits so `imagenet.py`'s mock branch has something to
# glob. It is (b), not (a): the fetches it depends on happen in another file, and this
# file's own work is writing 140k JPEGs across a process pool.
#   * `act` (upstream:11) is per-image: `np.uint8(X_train[i]).reshape(28, 28)` (upstream:14),
#     the name `f"train/{Y_train[i]}/{i}.jpg"` (upstream:15) -- note the class DIRECTORY
#     is the digit label, which is exactly what `imagenet.py:22`'s
#     `glob.glob(BASEDIR / "train/*/*")` expects -- and
#     `Image.fromarray(img).resize((224, 224)).convert('RGB').save(basedir / nm)`
#     (upstream:19), the only colour conversion in the file.
#   * `create_fake_mnist_imagenet` (upstream:21) writes `imagenet_class_index.json`
#     (upstream:25-26) as `{str(i): [str(i), str(i)] for i in range(10)}`, which is the
#     file `imagenet.py:10` reads -- so this mock and that reader are ONE contract and
#     the keys must be strings on both sides. Then `Pool(64)` (upstream:36) runs
#     `imap_unordered` twice, train then val (upstream:37-38).
# TODO(port): STOPPED AT `act` (extra/datasets/fake_imagenet_from_mnist.py:11).
#   MISSING: `PIL.Image.fromarray(...).resize(...).convert('RGB').save(...)` -- an image
#   encoder and a JPEG writer, neither of which exists in the port; the module-level
#   `X_train, Y_test = fetch_mnist()` (upstream:9) whose ndarrays come back
#   `Refused` from `./__init__.bend`; `multiprocessing.Pool(64)` with
#   `imap_unordered` (a fan-out over `trange`, and `helpers.bend:2823` records only
#   `trange` as ported); and `pathlib.Path.mkdir(parents=True, exist_ok=True)`
#   (upstream:23,29-30). `os.cpu_count` is not needed -- 64 is a literal upstream.
# NOT PORTED, AND NAMED SO NOBODY INVENTS IT: `gen` (upstream:32) and the
#   `__main__` block (upstream:40), and the `create_fake_mnist_imagenet(BASEDIR)`
#   call that `imagenet.py:20` makes -- so `imagenet.bend`'s MNISTMOCK branch is
#   still unreachable.
import Base
import ./__init__.bend as D

# upstream: `def act(arg)` where `arg = (basedir, i, train)`, one JPEG out
def act(basedir: String, i: U32, train: Bool) -> D.Refused:
  D.refuse("extra/datasets/fake_imagenet_from_mnist.py:11 act")

# upstream: `def create_fake_mnist_imagenet(basedir:pathlib.Path)` -> None
def create_fake_mnist_imagenet(basedir: String) -> D.Refused:
  D.refuse("extra/datasets/fake_imagenet_from_mnist.py:21 create_fake_mnist_imagenet")