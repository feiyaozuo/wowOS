"""System API: REST API; all requests require a token except health check and token issuance."""
import io
import json
import os
from flask import Flask, request, jsonify, send_file

from wowos_core.token_service import TokenService
from wowos_core.file_manager import FileManager
from wowos_core.redaction_engine import RedactionEngine
from wowos_core.audit import AuditLogger

app = Flask(__name__)
file_manager = FileManager()
redaction_engine = RedactionEngine()
audit_logger = AuditLogger()


def _get_data_type_from_name(name: str) -> str:
    if not name:
        return "text"
    lower = name.lower()
    if any(lower.endswith(e) for e in (".jpg", ".jpeg", ".png", ".gif", ".webp")):
        return "image"
    return "text"


# Admin auth: only requests with WOWOS_ADMIN_TOKEN may call tokens/audit etc.
ADMIN_TOKEN = os.environ.get("WOWOS_ADMIN_TOKEN", "")


def _auth_token():
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        return None
    return auth_header.split()[1]


def _require_admin():
    """Verify admin; return (error_response, status_code) if ADMIN_TOKEN not set or token missing/invalid."""
    if not ADMIN_TOKEN:
        return jsonify({"error": "Admin not configured"}), 503
    token = _auth_token()
    if not token or token != ADMIN_TOKEN:
        audit_logger.log({
            "event_type": "admin_access",
            "resource": request.path,
            "result": "unauthorized",
        })
        return jsonify({"error": "Admin token required"}), 403
    return None


@app.route("/api/v1/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "service": "wowos-api"})


@app.route("/api/v1/files/<file_id>", methods=["GET"])
def get_file(file_id):
    token = _auth_token()
    if not token:
        return jsonify({"error": "Missing token"}), 401

    requested_level = int(request.args.get("level", 3))
    resource = f"file/{file_id}"
    if not TokenService.verify_token(token, resource, requested_level, "read"):
        audit_logger.log({
            "event_type": "data_access",
            "resource": file_id,
            "result": "unauthorized",
        })
        return jsonify({"error": "Unauthorized"}), 403

    data, metadata = file_manager.read_file(file_id)
    if data is None:
        return jsonify({"error": "Not found"}), 404

    original_level = metadata.get("privacy_level", 3)
    redacted = False
    if requested_level < original_level:
        data_type = metadata.get("type") or _get_data_type_from_name(metadata.get("name", ""))
        data = redaction_engine.redact(data, data_type, original_level, requested_level)
        redacted = True

    payload = TokenService.decode_payload(token)
    user_id = (payload.get("user_id")) if payload else None
    app_id = (payload.get("app_id")) if payload else None
    token_id = payload.get("token_id") if payload else None

    audit_logger.log({
        "event_type": "data_access",
        "user_id": user_id,
        "app_id": app_id,
        "resource": file_id,
        "original_level": original_level,
        "accessed_level": requested_level,
        "redacted": redacted,
        "token_id": token_id,
        "result": "success",
    })

    return send_file(
        io.BytesIO(data),
        download_name=metadata.get("name", "file"),
        as_attachment=True,
    )


@app.route("/api/v1/files", methods=["POST"])
def upload_file():
    token = _auth_token()
    if not token:
        return jsonify({"error": "Missing token"}), 401

    if not request.files.get("file"):
        return jsonify({"error": "No file"}), 400

    f = request.files["file"]
    data = f.read()
    name = f.filename or "unnamed"
    privacy_level = int(request.form.get("privacy_level", 3))
    tags = request.form.get("tags")
    if tags:
        try:
            tags = json.loads(tags)
        except json.JSONDecodeError:
            tags = []
    else:
        tags = []

    resource_wildcard = "file/*"
    if not TokenService.verify_token(token, resource_wildcard, privacy_level, "write"):
        audit_logger.log({
            "event_type": "file_upload",
            "resource": "file/*",
            "result": "unauthorized",
        })
        return jsonify({"error": "Unauthorized"}), 403

    payload = TokenService.decode_payload(token)
    user_id = payload.get("user_id") if payload else None
    owner = str(user_id) if user_id else None

    metadata = {
        "name": name,
        "privacy_level": privacy_level,
        "owner": owner,
        "tags": tags,
    }
    file_id = file_manager.store_file(data, metadata)
    return jsonify({"file_id": file_id}), 200


@app.route("/api/v1/files/<file_id>", methods=["DELETE"])
def delete_file(file_id):
    token = _auth_token()
    if not token:
        return jsonify({"error": "Missing token"}), 401

    resource = f"file/{file_id}"
    if not TokenService.verify_token(token, resource, 0, "write"):
        return jsonify({"error": "Unauthorized"}), 403

    file_manager.delete_file(file_id)
    return jsonify({"status": "deleted"}), 200


@app.route("/api/v1/tokens", methods=["POST"])
def create_token():
    """Issue token; admin only (or after first-run wizard sets admin token)."""
    err = _require_admin()
    if err is not None:
        return err
    body = request.get_json() or {}
    app_id = body.get("app_id")
    user_id = body.get("user_id", "default")
    resources = body.get("resources", ["file/*"])
    max_level = int(body.get("max_level", 3))
    ttl = int(body.get("ttl", 3600))
    if not app_id:
        return jsonify({"error": "app_id required"}), 400

    token = TokenService.generate_token(app_id, user_id, resources, max_level, ttl)
    payload = TokenService.decode_payload(token)
    token_id = payload.get("token_id") if payload else None
    audit_logger.log({
        "event_type": "token_issued",
        "app_id": app_id,
        "user_id": user_id,
        "resource": "tokens",
        "token_id": token_id,
        "result": "success",
    })
    return jsonify({"token": token}), 200


@app.route("/api/v1/audit", methods=["GET"])
def get_audit():
    """Query audit log; admin only; pagination and default redaction of sensitive fields."""
    err = _require_admin()
    if err is not None:
        return err
    limit = min(int(request.args.get("limit", 100)), 1000)
    offset = max(0, int(request.args.get("offset", 0)))
    redact = request.args.get("redact", "1").lower() in ("1", "true", "yes")
    import sqlite3
    conn = sqlite3.connect(audit_logger.db_path)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        "SELECT * FROM audit_log ORDER BY id DESC LIMIT ? OFFSET ?", (limit, offset)
    ).fetchall()
    conn.close()
    items = [dict(r) for r in rows]
    if redact and items:
        for row in items:
            if row.get("user_id"):
                row["user_id"] = (row["user_id"][:1] + "***") if len(row["user_id"]) > 1 else "***"
            if row.get("token_id"):
                row["token_id"] = (row["token_id"][:8] + "***") if len(row["token_id"]) > 8 else "***"
    return jsonify({"items": items, "limit": limit, "offset": offset}), 200


@app.route("/api/v1/tokens/revoke", methods=["POST"])
def revoke_token():
    """Revoke token; admin only."""
    err = _require_admin()
    if err is not None:
        return err
    body = request.get_json() or {}
    token_id = body.get("token_id")
    if not token_id:
        return jsonify({"error": "token_id required"}), 400
    TokenService.revoke_token(token_id)
    audit_logger.log({
        "event_type": "token_revoked",
        "resource": "tokens",
        "token_id": token_id,
        "result": "success",
    })
    return jsonify({"status": "revoked", "token_id": token_id}), 200


def run():
    from wowos_core.bootstrap import check_production_key_material
    check_production_key_material()
    port = int(os.environ.get("WOWOS_API_PORT", "8080"))
    app.run(host="0.0.0.0", port=port, debug=os.environ.get("FLASK_DEBUG", "0") == "1")


if __name__ == "__main__":
    run()
