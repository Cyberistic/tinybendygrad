# STUB -- 1:1 PATH MIRROR of extra/datasets/imagenet.py (91 LOC upstream). NOT YET PORTED.
#
# WHAT UPSTREAM IS. The ImageNet FILE LIST plus the training-time image transforms.
# Not a fetch wrapper: nothing here downloads. Every def reaches the filesystem or
# the imaging library, and the module's first executable line is a directory walk.
#   * `BASEDIR` (upstream:14/25) is selected by `if getenv("MNISTMOCK"):` --
#     `<pkg>/mnist` vs `<pkg>/imagenet` -- so the whole module has TWO shapes and a
#     mock run is the mock branch, not a flag threaded through.
#   * `get_val_files` (upstream:33) is `glob.glob(p := str(BASEDIR / "val/*/*"))`
#     guarded by `raise FileNotFoundError(f"No validation files in {p}")` (upstream:34),
#     which is the walrus: the glob result AND the pattern come from one expression.
#   * `random_resized_crop` (upstream:57) is the real work -- a `for _ in range(100)`
#     rejection sampler (upstream:63) with `min(min(w*aspect_ratio/h,
#     h/aspect_ratio/w), scale[1])` (upstream:65) as the cap, falling back to
#     `center_crop` (upstream:81) when `random_solution_found` is False.
# TODO(port): STOPPED AT `get_imagenet_categories` (extra/datasets/imagenet.py:9).
#   MISSING: `json.load(open(...))` (upstream:10) -- a JSON object keyed by string and
#   read as `{v[0]: int(k) for k,v in ci.items()}`, so it needs a JSON decoder and a
#   dict; `@functools.cache` (upstream:8/16/27/32), which is the port's `Reg`
#   first-wins pattern (device.bend:298) not a decorator; `@diskcache`
#   (upstream:27); `glob.glob` over `pathlib.Path`; `PIL.Image` for `img.resize`,
#   `img.crop` and `Image.BILINEAR` (upstream:41/52/75/84); and `random` /
#   `math.sqrt` for the sampler.
# NOT PORTED, AND NAMED SO NOBODY INVENTS IT: `image_resize` (upstream:37),
#   `rand_flip` (upstream:43), `center_crop` (upstream:48),
#   `random_resized_crop` (upstream:57), `preprocess_train` (upstream:88),
#   and the `MNISTMOCK` branch of `get_train_files` (upstream:17-23), which calls
#   `create_fake_mnist_imagenet` from `extra/datasets/fake_imagenet_from_mnist.py`.
#
# `get_val_files` is stubbed here and not only at the stop point because
# `extra/datasets/preprocess_imagenet.py:2` imports it, so the dependency has to be
# declared on both sides or the sibling stub below has nothing to point at.
import Base
import ./__init__.bend as D

# upstream: `def get_imagenet_categories()` -> `{wnid: int}` over 1000 classes
def get_imagenet_categories() -> D.Refused:
  D.refuse("extra/datasets/imagenet.py:9 get_imagenet_categories")

# upstream: `@diskcache def get_train_files()` -> `list[str]` from `<BASEDIR>/train/*/*`
def get_train_files() -> D.Refused:
  D.refuse("extra/datasets/imagenet.py:28 get_train_files")

# upstream: `@functools.cache def get_val_files()` -> `list[str]` from `<BASEDIR>/val/*/*`
def get_val_files() -> D.Refused:
  D.refuse("extra/datasets/imagenet.py:33 get_val_files")