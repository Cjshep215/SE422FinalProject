from __future__ import annotations

from dataclasses import dataclass
from functools import wraps
from io import BytesIO
from pathlib import Path

from PIL import Image, UnidentifiedImageError
from flask import (
    Blueprint,
    Response,
    current_app,
    flash,
    g,
    redirect,
    render_template,
    request,
    send_file,
    session,
    url_for,
)
from sqlalchemy import or_
from werkzeug.datastructures import FileStorage
from werkzeug.exceptions import RequestEntityTooLarge
from werkzeug.utils import secure_filename

from gallery.models import Photo, User, db


bp = Blueprint("gallery", __name__)
ALLOWED_IMAGE_FORMATS = {"JPEG", "PNG", "GIF", "WEBP"}


@dataclass(frozen=True)
class UploadPayload:
    filename: str
    content_type: str
    data: bytes
    width: int
    height: int


def login_required(view):
    @wraps(view)
    def wrapped_view(*args, **kwargs):
        if g.get("user") is None:
            flash("Sign in to continue.", "error")
            return redirect(url_for("gallery.login"))
        return view(*args, **kwargs)

    return wrapped_view


def _normalize_upload(upload: FileStorage) -> UploadPayload:
    raw_bytes = upload.read()
    if not raw_bytes:
        raise ValueError("One of the selected files was empty.")

    try:
        with Image.open(BytesIO(raw_bytes)) as image:
            image.load()
            image_format = (image.format or "").upper()
            width, height = image.size
    except UnidentifiedImageError as exc:
        raise ValueError(f"'{upload.filename}' is not a supported image file.") from exc

    if image_format not in ALLOWED_IMAGE_FORMATS:
        supported = ", ".join(sorted(ALLOWED_IMAGE_FORMATS))
        raise ValueError(f"Unsupported image format for '{upload.filename}'. Use {supported}.")

    safe_name = secure_filename(upload.filename or "")
    if not safe_name:
        safe_name = f"upload.{image_format.lower()}"

    content_type = Image.MIME.get(image_format, upload.mimetype or "application/octet-stream")

    return UploadPayload(
        filename=safe_name,
        content_type=content_type,
        data=raw_bytes,
        width=width,
        height=height,
    )


def _photo_title(uploaded_file_name: str, title_seed: str, index: int, total: int) -> str:
    if title_seed and total == 1:
        return title_seed
    if title_seed and total > 1:
        return f"{title_seed} {index}"
    return Path(uploaded_file_name).stem.replace("_", " ").replace("-", " ").title()


@bp.errorhandler(RequestEntityTooLarge)
def file_too_large(_error) -> tuple[Response, int]:
    flash("That file was too large. Increase MAX_CONTENT_LENGTH or upload a smaller image.", "error")
    return redirect(url_for("gallery.dashboard")), 413


@bp.get("/")
def home() -> str | Response:
    if g.get("user"):
        return redirect(url_for("gallery.dashboard"))
    return redirect(url_for("gallery.login"))


@bp.route("/register", methods=["GET", "POST"])
def register() -> str | Response:
    if g.get("user"):
        return redirect(url_for("gallery.dashboard"))

    if request.method == "POST":
        email = request.form.get("email", "").strip().lower()
        password = request.form.get("password", "")
        confirm_password = request.form.get("confirm_password", "")

        if not email:
            flash("Email is required.", "error")
        elif "@" not in email or "." not in email.split("@")[-1]:
            flash("Enter a valid email address.", "error")
        elif len(password) < 8:
            flash("Choose a password with at least 8 characters.", "error")
        elif password != confirm_password:
            flash("Passwords did not match.", "error")
        elif User.query.filter_by(email=email).first():
            flash("That email is already registered.", "error")
        else:
            user = User(email=email)
            user.set_password(password)
            db.session.add(user)
            db.session.commit()
            session.clear()
            session["user_id"] = user.id
            flash("Account created. Welcome to your gallery.", "success")
            return redirect(url_for("gallery.dashboard"))

    return render_template("auth.html", mode="register")


@bp.route("/login", methods=["GET", "POST"])
def login() -> str | Response:
    if g.get("user"):
        return redirect(url_for("gallery.dashboard"))

    if request.method == "POST":
        email = request.form.get("email", "").strip().lower()
        password = request.form.get("password", "")
        user = User.query.filter_by(email=email).first()

        if user is None or not user.check_password(password):
            flash("Invalid email or password.", "error")
        else:
            session.clear()
            session["user_id"] = user.id
            flash("Signed in successfully.", "success")
            return redirect(url_for("gallery.dashboard"))

    return render_template("auth.html", mode="login")


@bp.post("/logout")
@login_required
def logout() -> Response:
    session.clear()
    flash("You are signed out.", "success")
    return redirect(url_for("gallery.login"))


@bp.get("/dashboard")
@login_required
def dashboard() -> str:
    query_text = request.args.get("q", "").strip()
    photo_query = Photo.query.filter_by(owner_id=g.user.id)

    if query_text:
        like_query = f"%{query_text}%"
        photo_query = photo_query.filter(
            or_(
                Photo.title.ilike(like_query),
                Photo.description.ilike(like_query),
                Photo.original_filename.ilike(like_query),
            )
        )

    photos = photo_query.order_by(Photo.created_at.desc()).all()
    return render_template("dashboard.html", photos=photos, query_text=query_text)


@bp.post("/photos/upload")
@login_required
def upload_photos() -> Response:
    uploads = [item for item in request.files.getlist("photos") if item and item.filename]
    title_seed = request.form.get("title", "").strip()
    description = request.form.get("description", "").strip()

    if not uploads:
        flash("Select at least one image to upload.", "error")
        return redirect(url_for("gallery.dashboard"))

    storage = current_app.extensions["photo_storage"]
    uploaded_count = 0

    for index, upload in enumerate(uploads, start=1):
        try:
            payload = _normalize_upload(upload)
        except ValueError as exc:
            flash(str(exc), "error")
            continue

        storage_result = storage.save(
            payload.data,
            owner_id=g.user.id,
            filename=payload.filename,
            content_type=payload.content_type,
        )

        photo = Photo(
            owner_id=g.user.id,
            title=_photo_title(payload.filename, title_seed, index, len(uploads)),
            description=description,
            original_filename=payload.filename,
            storage_key=storage_result.key,
            content_type=payload.content_type,
            file_size=storage_result.size,
            width=payload.width,
            height=payload.height,
        )
        db.session.add(photo)
        uploaded_count += 1

    if uploaded_count:
        db.session.commit()
        flash(f"Uploaded {uploaded_count} photo(s).", "success")
    else:
        db.session.rollback()
        flash("No photos were uploaded.", "error")

    return redirect(url_for("gallery.dashboard"))


@bp.get("/photos/<int:photo_id>/download")
@login_required
def download_photo(photo_id: int):
    photo = Photo.query.filter_by(id=photo_id, owner_id=g.user.id).first_or_404()
    binary_data = current_app.extensions["photo_storage"].download(photo.storage_key)

    return send_file(
        BytesIO(binary_data),
        mimetype=photo.content_type,
        as_attachment=True,
        download_name=photo.original_filename,
    )


@bp.get("/healthz")
def healthcheck() -> tuple[dict[str, str], int]:
    return {"status": "ok"}, 200

