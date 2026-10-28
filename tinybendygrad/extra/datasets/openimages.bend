# STUB -- 1:1 PATH MIRROR of extra/datasets/openimages.py (209 LOC upstream). NOT YET PORTED.
#
# WHAT UPSTREAM IS. Open Images v6 -> COCO, for the detection MLPerf benchmark. It is
# (b), and it is the only file in this slice whose constant table is bigger than its
# logic: `MLPERF_CLASSES` (upstream:18-56) is 601 names in 39 lines, and the
# correctness hinge is the JOIN between that list and the CSV, not the list itself.
#   * `get_image_list` (upstream:100) is two `isin` predicates chained:
#     `class_map[class_map["DisplayName"].isin(classes)]["LabelName"]` then
#     `annotations[annotations["LabelName"].isin(labels)]["ImageID"].unique()`
#     (upstream:101-102). Display name joins to Label name joins to ImageID, and a
#     display name missing from `MLPERF_CLASSES` silently drops the class.
#   * `export_to_coco` (upstream:70) is `pd.factorize(annotations["ImageID"].tolist())[0]`
#     (upstream:77) for the integer id -- which is ORDER-SENSITIVE: factorize numbers
#     rows by first appearance, so `imgs` (upstream:81-83) and `annots` (upstream:87)
#     must both walk the SAME frame or every annotation points at the wrong image.
#     Then the bbox conversion `x, y, w, h = xmin*img_w, ymin*img_h, (xmax-xmin)*img_w,
#     (ymax-ymin)*img_h` (upstream:89) turns Open Images' normalised corners into
#     COCO's xywh pixels -- the conversion is where a sign or an axis error hides.
#   * `fetch_openimages` (upstream:111) reaches for
#     `boto3.resource("s3", config=botocore.config.Config(signature_version=
#     botocore.UNSIGNED)).Bucket(BUCKET_NAME)` (upstream:112): UNSIGNED, so this is
#     public data and NOT a credentialed downloader. The images come from a bucket and
#     the CSVs from `fetch` (upstream:120/123/128), so it is two transports.
#   * `normalize` (upstream:197) is the ONLY tinygrad arithmetic in the file and it is
#     three lines: mean `[0.485, 0.456, 0.406]`, std `[0.229, 0.224, 0.225]`,
#     `((img.permute([0,3,1,2]) / 255.0) - mean) / std` then
#     `img.cast(dtypes.default_float)` (upstream:200-201). The trailing cast is what
#     makes the result `dtypes.default_float` and not the dtype `255.0` forced.
# TODO(port): STOPPED AT `openimages` (extra/datasets/openimages.py:59), the
#   module's entry point and the first def after the class table.
#   MISSING: `MLPERF_CLASSES` as a value first -- it must be the real 601-name list,
#     not a placeholder, because it is the left side of the join above; `boto3` +
#     `botocore` (upstream:7) for the UNSIGNED S3 bucket and its `ClientError` branch
#     (upstream:108); `fetch` for the three CSVs (the `helpers.bend:3194` HTTP seam);
#     `pandas` -- `read_csv` (upstream:125/129), `merge`, `isin`, `groupby`,
#     `factorize`, `apply(..., axis=1, result_type="expand")` (upstream:78), i.e. a
#     dataframe engine, not a CSV reader; `PIL.Image` (upstream:5) for `extract_dims`
#     (upstream:68) and `image_load` (upstream:144); numpy for `prepare_target`'s
#     `clip`/boolean-index (upstream:150-153); `concurrent.futures.ThreadPoolExecutor`
#     (upstream:133) and `torch`/`torchvision.transforms.functional` (upstream:169,
#     178) for the flip and resize; `tqdm` (upstream:135) and `diskcache`-style env
#     `getenv("BASEDIR", ...)` (upstream:208).
#   The one thing that IS reachable is `normalize` -- `Tensor` and `dtypes` are ported
#   (`tensor.bend:200`, `dtype.bend:57`) -- but it cannot be written honestly until
#   `permute` and `cast` on the port's Tensor exist, so it is left named, not faked.
# NOT PORTED, AND NAMED SO NOBODY INVENTS IT: `MLPERF_CLASSES` (upstream:18),
#   `extract_dims`, `export_to_coco`, `get_image_list`, `download_image`,
#   `fetch_openimages`, `image_load`, `prepare_target`, `download_dataset`,
#   `random_horizontal_flip`, `resize`, `normalize`, `get_dataset_count`, and the
#   `__main__` block (upstream:207).
import Base
import ./__init__.bend as D

# upstream: `def openimages(base_dir:Path, subset:str, ann_file:Path)` -> None; raises ValueError
#            on a subset outside `['train', 'validation']` (upstream:60-62)
def openimages(base_dir: String, subset: String, ann_file: String) -> D.Refused:
  D.refuse("extra/datasets/openimages.py:59 openimages")

# upstream: `def get_image_list(class_map, annotations, classes=MLPERF_CLASSES)` -> ImageIDs
def get_image_list(class_map: String, annotations: String, classes: String) -> D.Refused:
  D.refuse("extra/datasets/openimages.py:100 get_image_list")

# upstream: `def export_to_coco(class_map, annotations, image_list, dataset_path, output_path, subset, classes=MLPERF_CLASSES)`
def export_to_coco(class_map: String, annotations: String, image_list: String, dataset_path: String,
                   output_path: String, subset: String, classes: String) -> D.Refused:
  D.refuse("extra/datasets/openimages.py:70 export_to_coco")

# upstream: `def fetch_openimages(output_fn:str, base_dir:Path, subset:str)` -> None
def fetch_openimages(output_fn: String, base_dir: String, subset: String) -> D.Refused:
  D.refuse("extra/datasets/openimages.py:111 fetch_openimages")

# upstream: `def download_image(bucket, subset, image_id, data_dir)`; `sys.exit` on ClientError
def download_image(bucket: String, subset: String, image_id: String, data_dir: String) -> D.Refused:
  D.refuse("extra/datasets/openimages.py:105 download_image")

# upstream: `def prepare_target(annotations, img_id, img_size)` -> dict of boxes/labels/image_id
def prepare_target(annotations: String, img_id: String, img_size: String) -> D.Refused:
  D.refuse("extra/datasets/openimages.py:146 prepare_target")

# upstream: `def normalize(img:Tensor, device:list[str]|None=None)` -> Tensor
#            ((img.permute([0,3,1,2]) / 255.0 - mean) / std).cast(dtypes.default_float)
def normalize(img: String, device: String) -> D.Refused:
  D.refuse("extra/datasets/openimages.py:197 normalize")

# upstream: `def resize(img:Image, tgt:dict|None=None, size:tuple=(800,800))`
def resize(img: String, tgt: String, size: String) -> D.Refused:
  D.refuse("extra/datasets/openimages.py:177 resize")