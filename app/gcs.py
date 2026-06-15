import io
import os

import joblib
from google.cloud import storage

BUCKET_NAME = os.environ.get("GCS_BUCKET_NAME", "oneteam-vpc-9-ml-models")
_DEFAULT_BLOB = "models/house_price_model.pkl"


def _client():
    return storage.Client()


def upload_model(model, blob_path: str = None) -> str:
    blob_path = blob_path or _DEFAULT_BLOB
    buf = io.BytesIO()
    joblib.dump(model, buf)
    buf.seek(0)
    client = _client()
    bucket = client.bucket(BUCKET_NAME)
    blob = bucket.blob(blob_path)
    blob.upload_from_file(buf, content_type="application/octet-stream")
    return blob_path


def download_model(blob_path: str = None):
    blob_path = blob_path or _DEFAULT_BLOB
    client = _client()
    bucket = client.bucket(BUCKET_NAME)
    blob = bucket.blob(blob_path)
    buf = io.BytesIO()
    blob.download_to_file(buf)
    buf.seek(0)
    return joblib.load(buf)


def model_exists(blob_path: str = None) -> bool:
    blob_path = blob_path or _DEFAULT_BLOB
    client = _client()
    bucket = client.bucket(BUCKET_NAME)
    return bucket.blob(blob_path).exists()
