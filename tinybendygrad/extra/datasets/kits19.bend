# STUB -- 1:1 PATH MIRROR of extra/datasets/kits19.py (219 LOC upstream). NOT YET PORTED.
#
# WHAT UPSTREAM IS. The KiTS19 kidney tumour 3-D segmentation loader. It is (b) and
# the honest headline is that it is the only file in this slice that imports BOTH
# torch and tinygrad, so it is also the only one where a tensor operation is
# tinygrad's rather than numpy's:
#   * `resample3d` (upstream:34) computes `new_shape = (spc_arr / targ_arr *
#     shp_arr).astype(int).tolist()` (upstream:37) and then calls
#     `F.interpolate(torch.from_numpy(...), size=new_shape, mode="trilinear",
#     align_corners=True)` for the image and `mode="nearest"` for the label
#     (upstream:38-39). The mode differs BY TENSOR and that is the correctness
#     claim: interpolating a uint8 label trilinearly invents intensities between
#     classes. `align_corners=True` is also not the default.
#   * `sliding_window_inference` (upstream:114) is the one that reaches the PORT's
#     tensor: `from tinygrad.tensor import Tensor` (upstream:11) and a `model` passed
#     in. The volume is walked in `roi_shape` (upstream:108 `pad_input` defaults to
#     `(128,128,128)`) at `overlap=0.5` and the windows are stitched -- which is why
#     `padding_mode="constant", padding_val=-2.2` (upstream:108) is a SPECIFIC number:
#     -2.2 sits below `normal_intensity`'s `min_clip=-79.0` normalisation floor and
#     outside the CT range, so padding is detectable instead of being read as tissue.
#   * `normal_intensity` (upstream:44) is `np.clip(image, -79.0, 304.0)` then
#     `(image - 101.0) / 76.9` -- three literals, and the whole reason is that the
#     pad value above must fall outside them.
# TODO(port): STOPPED AT `get_train_files` (extra/datasets/kits19.py:19), the first
#   def, whose body is a directory scan (upstream:20):
#   `sorted([x for x in BASEDIR.iterdir() if x.stem.startswith("case") and
#    int(x.stem.split("_")[-1]) < 210 and x not in get_val_files()])`.
#   MISSING: `fetch` (upstream:24, the `helpers.bend:3193` HTTP seam) which
#   `get_val_files` needs for `evaluation_cases.txt`; `pathlib`/`iterdir`/`functools.cache`
#   for the scan; `nibabel` (`nib.load`, `image.header["pixdim"][1:4].tolist()`,
#   `get_fdata()`, upstream:28-30) for NIfTI volumes; `scipy.signal`/`scipy.ndimage`
#   (upstream:6) for `gaussian_kernel` (upstream:99) and the filtering; torch and
#   `torch.nn.functional` (upstream:8-9) for `interpolate` -- and the port's own
#   `Tensor` (upstream:11) is a UOp slot in an arena (`tensor.bend:200`), not the
#   runtime tensor `model` needs, so `sliding_window_inference` has no callee at all.
# NOT PORTED, AND NAMED SO NOBODY INVENTS IT: `get_val_files` (upstream:23),
#   `load_pair`, `resample3d`, `normal_intensity`, `pad_to_min_shape`, `preprocess`,
#   `preprocess_dataset`, `iterate` (upstream:73), `gaussian_kernel`, `pad_input`,
#   `sliding_window_inference`, `rand_flip`, `random_brightness_augmentation`,
#   `gaussian_noise`, `_rand_foreg_cropb`, `_rand_crop`, `rand_balanced_crop`
#   (upstream:210).
import Base
import ./__init__.bend as D

# upstream: `@functools.cache def get_train_files()` -> `list[Path]` of `case_*` dirs
def get_train_files() -> D.Refused:
  D.refuse("extra/datasets/kits19.py:19 get_train_files")

# upstream: `@functools.cache def get_val_files()` -> `list[Path]` from evaluation_cases.txt
def get_val_files() -> D.Refused:
  D.refuse("extra/datasets/kits19.py:23 get_val_files")

# upstream: `def load_pair(file_path)` -> `(image, label, image_spacings)` as float32/uint8
def load_pair(file_path: String) -> D.Refused:
  D.refuse("extra/datasets/kits19.py:27 load_pair")

# upstream: `def resample3d(image, label, image_spacings, target_spacing=(1.6,1.2,1.2))`
def resample3d(image: String, label: String, image_spacings: String, target_spacing: String) -> D.Refused:
  D.refuse("extra/datasets/kits19.py:34 resample3d")

# upstream: `def normal_intensity(image, min_clip=-79.0, max_clip=304.0, mean=101.0, std=76.9)`
def normal_intensity(image: String, min_clip: F32, max_clip: F32, mean: F32, std: F32) -> D.Refused:
  D.refuse("extra/datasets/kits19.py:44 normal_intensity")

# upstream: `def pad_input(volume, roi_shape, strides, padding_mode="constant", padding_val=-2.2, dim=3)`
def pad_input(volume: String, roi_shape: String, strides: String, padding_mode: String, padding_val: F32, dim: U32) -> D.Refused:
  D.refuse("extra/datasets/kits19.py:108 pad_input")

# upstream: `def sliding_window_inference(model, inputs, labels, roi_shape=(128,128,128), overlap=0.5, gpus=None)`
def sliding_window_inference(model: String, inputs: String, labels: String, roi_shape: String, overlap: F32, gpus: String) -> D.Refused:
  D.refuse("extra/datasets/kits19.py:114 sliding_window_inference")