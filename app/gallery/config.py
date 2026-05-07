from __future__ import annotations

import os
from pathlib import Path
from urllib.parse import quote_plus


BASE_DIR = Path(__file__).resolve().parent.parent


def _resolve_instance_dir() -> Path:
    configured_dir = os.environ.get("INSTANCE_DIR")
    if configured_dir:
        return Path(configured_dir)

    # App Engine standard file system is read-only except /tmp.
    if os.environ.get("APP_ENV") == "production":
        return Path("/tmp/instance")

    return BASE_DIR / "instance"


INSTANCE_DIR = _resolve_instance_dir()


def _bool_env(name: str, default: bool = False) -> bool:
    raw_value = os.environ.get(name)
    if raw_value is None:
        return default
    return raw_value.lower() in {"1", "true", "yes", "on"}


def build_database_uri() -> str:
    explicit_uri = os.environ.get("DATABASE_URL")
    if explicit_uri:
        return explicit_uri

    db_name = os.environ.get("DB_NAME", "photo_gallery")
    db_user = quote_plus(os.environ.get("DB_USER", "gallery_user"))
    db_password = quote_plus(os.environ.get("DB_PASSWORD", "gallery_password"))

    connection_name = os.environ.get("INSTANCE_CONNECTION_NAME")
    if connection_name:
        socket_dir = os.environ.get("DB_SOCKET_DIR", "/cloudsql")
        return (
            f"mysql+pymysql://{db_user}:{db_password}@/{db_name}"
            f"?unix_socket={socket_dir}/{connection_name}"
        )

    db_host = os.environ.get("DB_HOST")
    if db_host:
        db_port = os.environ.get("DB_PORT", "3306")
        return f"mysql+pymysql://{db_user}:{db_password}@{db_host}:{db_port}/{db_name}"

    try:
        INSTANCE_DIR.mkdir(parents=True, exist_ok=True)
    except OSError:
        pass
    sqlite_path = INSTANCE_DIR / "gallery.db"
    return f"sqlite:///{sqlite_path.as_posix()}"


class Config:
    APP_ENV = os.environ.get("APP_ENV", "development")
    APP_TITLE = os.environ.get("APP_TITLE", "4220 Project 4")
    LOCAL_UPLOAD_DIR = os.environ.get("LOCAL_UPLOAD_DIR", str(INSTANCE_DIR / "uploads"))
    MAX_CONTENT_LENGTH = int(os.environ.get("MAX_CONTENT_LENGTH", str(16 * 1024 * 1024)))
    PHOTO_BUCKET = os.environ.get("PHOTO_BUCKET", "")
    SECRET_KEY = os.environ.get("SECRET_KEY", "dev-secret-key")
    SESSION_COOKIE_HTTPONLY = True
    SESSION_COOKIE_SECURE = _bool_env(
        "SESSION_COOKIE_SECURE",
        default=APP_ENV == "production",
    )
    SQLALCHEMY_DATABASE_URI = build_database_uri()
    SQLALCHEMY_TRACK_MODIFICATIONS = False
    STORAGE_BACKEND = os.environ.get(
        "STORAGE_BACKEND",
        "gcs" if PHOTO_BUCKET else "local",
    )
    AUTO_CREATE_ADMIN = _bool_env("AUTO_CREATE_ADMIN", default=APP_ENV == "production")
    ADMIN_EMAIL = os.environ.get("ADMIN_EMAIL", "admin@example.com").strip().lower()
    ADMIN_PASSWORD = os.environ.get("ADMIN_PASSWORD", "class-admin-4220")

