from __future__ import annotations

from pathlib import Path

from flask import Flask, g, session

from gallery.config import Config
from gallery.models import User, db
from gallery.storage import build_storage


def create_app(test_config: dict | None = None) -> Flask:
    app = Flask(__name__, instance_relative_config=True)
    app.config.from_object(Config)

    if test_config:
        app.config.update(test_config)

    try:
        Path(app.instance_path).mkdir(parents=True, exist_ok=True)
    except OSError:
        # App Engine has a read-only /workspace; use /tmp for writable runtime files.
        app.config["INSTANCE_PATH"] = "/tmp/instance"
    Path(app.config["LOCAL_UPLOAD_DIR"]).mkdir(parents=True, exist_ok=True)

    db.init_app(app)
    app.extensions["photo_storage"] = build_storage(app.config)

    from gallery.routes import bp

    app.register_blueprint(bp)

    @app.before_request
    def load_current_user() -> None:
        user_id = session.get("user_id")
        g.user = db.session.get(User, user_id) if user_id else None

    @app.context_processor
    def inject_template_context() -> dict:
        return {
            "app_title": app.config["APP_TITLE"],
            "current_user": g.get("user"),
        }

    with app.app_context():
        db.create_all()

        if app.config.get("AUTO_CREATE_ADMIN") and not app.config.get("TESTING"):
            admin_email = app.config.get("ADMIN_EMAIL", "").strip().lower()
            admin_password = app.config.get("ADMIN_PASSWORD", "")

            if admin_email and admin_password:
                admin_user = User.query.filter_by(email=admin_email).first()
                if admin_user is None:
                    admin_user = User(email=admin_email)
                    admin_user.set_password(admin_password)
                    db.session.add(admin_user)
                    db.session.commit()
                app.logger.warning("ADMIN_LOGIN_EMAIL=%s", admin_email)
                app.logger.warning("ADMIN_LOGIN_PASSWORD=%s", admin_password)

    return app
