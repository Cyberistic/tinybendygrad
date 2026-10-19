# STUB -- 1:1 PATH MIRROR of extra/datasets/imagenet_download.py (51 LOC upstream). NOT YET PORTED.
#
# WHAT UPSTREAM IS. The ILSVRC2012 fetcher, and it is NOT class (c). The obvious
# reason to skip it -- "ImageNet is behind a registration wall" -- was CHECKED AND IS
# FALSE, and the check is recorded here so nobody re-derives it from memory.
#   MEASURED 2026-10-19, `curl -sSL -o /dev/null -w '%{http_code} %{content_type} %{size_download}'
#   https://image-net.org/data/ILSVRC/2012/ILSVRC2012_img_val.tar`:
#       http=200 type=application/x-tar, and 86,900,736 of 6,744,924,160 bytes had
#       arrived when the 12s cap hit. Anonymous, unauthenticated, and it STARTS.
#   So the download is open; the reason this is still a stub is `fetch`, not a login.
# It is not a thin fetch wrapper either: three of its five defs are filesystem logic
# that runs on already-downloaded bytes.
#   * `imagenet_extract` (upstream:7) walks `tar.getmembers()` and extracts each
#     member, with the `small` flag only choosing a `tqdm` progress bar (upstream:9-12).
#   * `imagenet_prepare_val` (upstream:15) is the one that matters: it reads the synset
#     label file, `images.sort()` (upstream:22), then for each label does
#     `os.makedirs(...)` + `os.replace(.../<image>, .../<synset>/<image>)` (upstream:25-26)
#     and finally `os.remove` of the label file (upstream:27). That sort-then-rename is
#     a data-ordering claim: label N goes to the Nth sorted filename.
# TODO(port): STOPPED AT `imagenet_extract` (extra/datasets/imagenet_download.py:7).
#   MISSING: `tarfile.open` + `getmembers()` + member-wise `extract` -- a gzip/tar
#   reader, which the port has no seam for (`sz.bend` reads a directory, not an
#   archive); `tqdm` (`helpers.bend:2823` records that only `trange` is ported and
#   "What is left of `tqdm` is its terminal progress bar"); `os.makedirs`,
#   `os.replace`, `os.remove`, `os.listdir` and `Path` arithmetic for the
#   `__file__`-relative roots; and `fetch(url, local_path)` (upstream:43-45,49), which
#   is the `helpers.bend:2815` HTTP seam. `fetch`'s SECOND ARGUMENT is the whole
#   design here -- upstream downloads STRAIGHT TO THE FINAL PATH, so a partial
#   download leaves a truncated `ILSVRC2012_img_val.tar` that `tarfile.open` will
#   later accept and read short. Whatever ports `fetch` must port that hazard too.
# NOT PORTED, AND NAMED SO NOBODY INVENTS IT: `imagenet_prepare_val` (upstream:15),
#   `imagenet_prepare_train` (upstream:29), and the `__main__` block
#   (upstream:39-51), whose `IMGNET_TRAIN` gate holds the 138GB train tar.
import Base
import ./__init__.bend as D

# upstream: `def imagenet_extract(file, path, small=False)` -> None (extracts in place)
def imagenet_extract(file: String, path: String, small: Bool) -> D.Refused:
  D.refuse("extra/datasets/imagenet_download.py:7 imagenet_extract")

# upstream: `def imagenet_prepare_val()` -> None (sorts, mkdirs and renames val/)
def imagenet_prepare_val() -> D.Refused:
  D.refuse("extra/datasets/imagenet_download.py:15 imagenet_prepare_val")

# upstream: `def imagenet_prepare_train()` -> None (untar each train/<n>.tar into train/<n>/)
def imagenet_prepare_train() -> D.Refused:
  D.refuse("extra/datasets/imagenet_download.py:29 imagenet_prepare_train")

# upstream: the `if __name__ == "__main__":` block at extra/datasets/imagenet_download.py:39
def main() -> D.Refused:
  D.refuse("extra/datasets/imagenet_download.py:43 fetch (helpers.bend:2815 HTTP seam)")