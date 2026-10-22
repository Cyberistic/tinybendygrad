# STUB -- 1:1 PATH MIRROR of extra/datasets/librispeech.py (82 LOC upstream). NOT YET PORTED.
#
# WHAT UPSTREAM IS. A SPEECH-FEATURE EXTRACTOR, and it is the only file in this
# directory whose WORK HAPPENS AT IMPORT TIME rather than inside a def.
#   * `FILTER_BANK` (upstream:22) is a mel filter bank, built at module level by
#     `librosa.filters.mel(sr=16000, n_fft=512, n_mels=80, fmin=0, fmax=8000)`, and
#     `WINDOW` (upstream:23) is a Hann window of 320, built by
#     `librosa.filters.get_window("hann", 320)`. **THEY ARE CONSTANTS, NOT FUNCTIONS.**
#   * `BASEDIR` (upstream:18) and the `with open(BASEDIR / "dev-clean-wav.json")`
#     (upstream:19-20) run AT IMPORT, so the module cannot even be imported until a
#     human has downloaded a dataset and converted every flac to wav by hand --
#     upstream's own docstring (upstream:7-17) says so, and gives the `ffmpeg` loop.
#   * `feature_extract(x, x_lens)` (upstream:25) is the real work: pre-emphasis
#     (`x[:, 1:] - 0.97 * x[:, :-1]`), an STFT (`librosa.stft`), a power spectrum
#     (`(x**2).sum(-1)`), the mel filter bank (`np.matmul`), a log, and a feature
#     splice. `load_wav(file)` (upstream:63) reads audio; `iterate(bs=1, start=0)`
#     (upstream:67) walks the manifest; `if __name__ == "__main__":` (upstream:80).
# TODO(port): STOPPED AT LINE 4 (extra/datasets/librispeech.py:4) -- `import librosa`.
#   **THIS FILE IS A WALL, AND IT IS THE FIRST ONE IN THIS DIRECTORY THAT IS A WALL
#   RATHER THAN A SEAM.**  `AGENTS.md`'s rule is that the port ships NO EXTERNAL
#   DEPENDENCIES -- "every import under `tinybendygrad/` is `Base` or another `.bend`
#   file in this repo" -- and upstream's four imports here are `json` (fine, it is
#   stdlib), `pathlib` (fine), `numpy` (NOT fine) and `librosa` + `soundfile` (NOT
#   fine, and neither is in this repo).  SO THE MISSING PIECES ARE, IN ORDER:
#   (1) `librosa` AND `soundfile` -- TWO THIRD-PARTY PACKAGES, and their DSP
#       (`filters.mel`, `filters.get_window`, `stft`) has no counterpart here.  A
#       mel filter bank and an STFT are NOT SMALL; PORTING THEM IS A PROJECT, and
#       naming that is worth more than a stub that pretends.
#   (2) AN NDARRAY. `np.expand_dims`, `np.matmul`, `np.stack`, and the
#       `x[:, 1:]` slicing are all ndarray operations.  `Tensor` in `tensor.bend` is
#       a UOp SLOT IN AN ARENA, not a buffer, and `tensor.bend:1341` says so: a
#       "list/tuple/bytes/ndarray/Path" is "the uop the maker already" holds.  So
#       `feature_extract` has nowhere to put its argument.
#   (3) THE MANIFEST. `dev-clean-wav.json` is not in the repo and cannot be: it is
#       a human's download, and the flacs it names must be converted to wav by
#       hand with `ffmpeg` before ANY of this runs.
#   (4) `json` AND `pathlib` ARE PORTABLE and are the only parts of this file that
#       are -- and they are the two lines upstream spends them on for a manifest
#       that does not exist here.
# NOT PORTED, AND NAMED SO NOBODY INVENTS IT: `feature_extract` (upstream:25),
#   `load_wav` (upstream:63), `iterate` (upstream:67), `FILTER_BANK` (upstream:22),
#   `WINDOW` (upstream:23), `BASEDIR` (upstream:18).
#
# WHY THIS RETURNS `Refused` INSTEAD OF UPSTREAM'S RETURN TYPE.  Upstream's
# `iterate` yields `(x, x_lens)` pairs of ndarrays.  Neither type exists at this
# seam, so the return type here is `Refused` and NOT a tuple.  The alternative --
# returning an empty list, which is what a thin stub reaches for -- is a value
# indistinguishable from a dataset of size zero, and a dataset loader that can
# report an empty dataset instead of admitting it is absent is the one lie this
# file must not tell.
#
# `Refused`/`refuse` are declared in `./__init__.bend` and imported as `D` by the
# sibling stubs, so the refusal is one definition rather than eleven copies of it.
import Base
import ./__init__.bend as D

# upstream: `def iterate(bs=1, start=0)` -> pairs of ndarrays, from a manifest a
# human must download and convert by hand
def main() -> D.Refused:
  D.refuse("extra/datasets/librispeech.py:4 import librosa (a third-party package, and the port ships none)")
