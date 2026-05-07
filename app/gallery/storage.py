from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from uuid import uuid4

from google.cloud import storage


@dataclass(frozen=True)
class StorageResult:
    key: str
    size: int


class LocalStorage:
    def __init__(self, base_dir: str) -> None:
        self.base_dir = Path(base_dir)
        self.base_dir.mkdir(parents=True, exist_ok=True)

    def save(self, data: bytes, *, owner_id: int, filename: str, content_type: str) -> StorageResult:
        suffix = Path(filename).suffix.lower()
        key = f"user_{owner_id}/{uuid4().hex}{suffix}"
        destination = self.base_dir / key
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        return StorageResult(key=key, size=len(data))

    def download(self, key: str) -> bytes:
        return (self.base_dir / key).read_bytes()


class GoogleCloudStorage:
    def __init__(self, bucket_name: str) -> None:
        self.client = storage.Client()
        self.bucket = self.client.bucket(bucket_name)

    def save(self, data: bytes, *, owner_id: int, filename: str, content_type: str) -> StorageResult:
        suffix = Path(filename).suffix.lower()
        key = f"user_{owner_id}/{uuid4().hex}{suffix}"
        blob = self.bucket.blob(key)
        blob.upload_from_string(data, content_type=content_type)
        return StorageResult(key=key, size=len(data))

    def download(self, key: str) -> bytes:
        return self.bucket.blob(key).download_as_bytes()


def build_storage(config: dict):
    if config["STORAGE_BACKEND"] == "gcs":
        bucket_name = config.get("PHOTO_BUCKET")
        if not bucket_name:
            raise ValueError("PHOTO_BUCKET must be set when STORAGE_BACKEND is 'gcs'.")
        return GoogleCloudStorage(bucket_name)
    return LocalStorage(config["LOCAL_UPLOAD_DIR"])

