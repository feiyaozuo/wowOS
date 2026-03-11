"""系统服务 API：对外提供 REST API，所有请求需携带 Token（除健康检查与 Token 签发）。"""
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


def _auth_token():
    auth_header = request.headers.get("Authorization")
    if not auth_header or not auth_header.startswith("Bearer "):
        return None
    return auth_header.split()[1]


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
    """生成临时 Token；生产环境需经用户授权界面。"""
    body = request.get_json() or {}
    app_id = body.get("app_id")
    user_id = body.get("user_id", "default")
    resources = body.get("resources", ["file/*"])
    max_level = int(body.get("max_level", 3))
    ttl = int(body.get("ttl", 3600))
    if not app_id:
        return jsonify({"error": "app_id required"}), 400

    token = TokenService.generate_token(app_id, user_id, resources, max_level, ttl)
    return jsonify({"token": token}), 200


@app.route("/api/v1/audit", methods=["GET"])
def get_audit():
    """查询审计日志；生产环境需管理员权限。"""
    limit = int(request.args.get("limit", 100))
    import sqlite3
    conn = sqlite3.connect(audit_logger.db_path)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        "SELECT * FROM audit_log ORDER BY id DESC LIMIT ?", (limit,)
    ).fetchall()
    conn.close()
    items = [dict(r) for r in rows]
    return jsonify({"items": items}), 200


def run():
    port = int(os.environ.get("WOWOS_API_PORT", "8080"))
    app.run(host="0.0.0.0", port=port, debug=os.environ.get("FLASK_DEBUG", "0") == "1")


if __name__ == "__main__":
    run()
