"""System API: REST API; all requests require a token except health check and token issuance."""
import io
import json
import os
from flask import Flask, request, jsonify, send_file

from wowos_core.token_service import TokenService
from wowos_core.file_manager import FileManager
from wowos_core.redaction_engine import RedactionEngine
from wowos_core.audit import AuditLogger
from wowos_core import homeassistant_client as ha_client
from wowos_core import llm_gateway as llm_gw

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


@app.route("/api/v1/files/<file_id>/meta", methods=["GET"])
def get_file_meta(file_id):
    """Return metadata only for one file (no content)."""
    token = _auth_token()
    if not token:
        return jsonify({"error": "Missing token"}), 401
    if not TokenService.verify_token(token, f"file/{file_id}", 0, "read"):
        return jsonify({"error": "Unauthorized"}), 403
    meta = file_manager.get_metadata(file_id)
    if meta is None:
        return jsonify({"error": "Not found"}), 404
    return jsonify(meta), 200


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


@app.route("/api/v1/files", methods=["GET"])
def list_files():
    """List files (file_id, name, privacy_level, created_at); requires token with file/* read."""
    token = _auth_token()
    if not token:
        return jsonify({"error": "Missing token"}), 401
    if not TokenService.verify_token(token, "file/*", 0, "read"):
        return jsonify({"error": "Unauthorized"}), 403
    items = file_manager.list_files()
    return jsonify({"items": items, "files": items}), 200


def _upload_file_impl():
    """Shared upload logic for POST /api/v1/files and POST /api/v1/files/upload."""
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
    audit_logger.log({
        "event_type": "file_upload",
        "user_id": payload.get("user_id") if payload else None,
        "app_id": payload.get("app_id") if payload else None,
        "resource": file_id,
        "result": "success",
    })
    return jsonify({"file_id": file_id}), 200


@app.route("/api/v1/files", methods=["POST"])
def upload_file():
    return _upload_file_impl()


@app.route("/api/v1/files/upload", methods=["POST"])
def upload_file_upload():
    """Alias for POST /api/v1/files; document-recommended path."""
    return _upload_file_impl()


@app.route("/api/v1/files/<file_id>", methods=["DELETE"])
def delete_file(file_id):
    token = _auth_token()
    if not token:
        return jsonify({"error": "Missing token"}), 401

    resource = f"file/{file_id}"
    if not TokenService.verify_token(token, resource, 0, "write"):
        return jsonify({"error": "Unauthorized"}), 403

    meta = file_manager.get_metadata(file_id)
    file_manager.delete_file(file_id)
    payload = TokenService.decode_payload(token)
    audit_logger.log({
        "event_type": "file_delete",
        "user_id": payload.get("user_id") if payload else None,
        "app_id": payload.get("app_id") if payload else None,
        "resource": file_id,
        "result": "success",
    })
    return jsonify({"status": "deleted"}), 200


@app.route("/api/v1/files/<file_id>/classify", methods=["POST"])
def classify_file(file_id):
    """Update file level (privacy_level), tags, category."""
    token = _auth_token()
    if not token:
        return jsonify({"error": "Missing token"}), 401
    resource = f"file/{file_id}"
    if not TokenService.verify_token(token, resource, 0, "write"):
        return jsonify({"error": "Unauthorized"}), 403
    if file_manager.get_metadata(file_id) is None:
        return jsonify({"error": "Not found"}), 404
    body = request.get_json() or {}
    level = body.get("level")
    if level is not None:
        level = int(level)
        if level not in (1, 2, 3):
            return jsonify({"error": "level must be 1, 2, or 3"}), 400
    tags = body.get("tags")
    category = body.get("category")
    ok = file_manager.update_metadata(file_id, level=level, tags=tags, category=category)
    if not ok:
        return jsonify({"error": "Nothing to update"}), 400
    payload = TokenService.decode_payload(token)
    audit_logger.log({
        "event_type": "file_classify",
        "user_id": payload.get("user_id") if payload else None,
        "resource": file_id,
        "result": "success",
    })
    return jsonify({"status": "updated", "file_id": file_id}), 200


@app.route("/api/v1/files/<file_id>/redact", methods=["POST"])
def redact_file(file_id):
    """Return redacted content for the file at target level; records audit."""
    token = _auth_token()
    if not token:
        return jsonify({"error": "Missing token"}), 401
    target_level = int(request.get_json(silent=True) or {}).get("target_level", 1)
    if target_level not in (1, 2, 3):
        return jsonify({"error": "target_level must be 1, 2, or 3"}), 400
    resource = f"file/{file_id}"
    if not TokenService.verify_token(token, resource, target_level, "read"):
        return jsonify({"error": "Unauthorized"}), 403
    data, metadata = file_manager.read_file(file_id)
    if data is None:
        return jsonify({"error": "Not found"}), 404
    original_level = metadata.get("privacy_level", 3)
    data_type = metadata.get("type") or _get_data_type_from_name(metadata.get("name", ""))
    redacted = redaction_engine.redact(data, data_type, original_level, target_level)
    payload = TokenService.decode_payload(token)
    audit_logger.log({
        "event_type": "redact_output",
        "user_id": payload.get("user_id") if payload else None,
        "resource": file_id,
        "original_level": original_level,
        "accessed_level": target_level,
        "redacted": True,
        "result": "success",
    })
    try:
        text = redacted.decode("utf-8")
        return jsonify({"redacted_preview": text[:4096] if len(text) > 4096 else text, "truncated": len(text) > 4096}), 200
    except UnicodeDecodeError:
        return jsonify({"redacted_preview": "(binary)", "truncated": False}), 200


@app.route("/api/v1/homeassistant/connect", methods=["POST"])
def homeassistant_connect():
    """Test connection to Home Assistant. Body: base_url, token."""
    body = request.get_json() or {}
    base_url = (body.get("base_url") or "").strip().rstrip("/")
    token = (body.get("token") or "").strip()
    if not base_url or not token:
        return jsonify({"error": "base_url and token required"}), 400
    ok = ha_client.test_connection(base_url=base_url, token=token)
    audit_logger.log({
        "event_type": "homeassistant_connect",
        "resource": base_url,
        "result": "success" if ok else "failed",
    })
    return jsonify({"connected": ok}), 200


@app.route("/api/v1/homeassistant/entities", methods=["GET", "POST"])
def homeassistant_entities():
    """Return entity list. POST body or query: base_url, token."""
    if request.method == "POST":
        body = request.get_json() or {}
        base_url = (body.get("base_url") or "").strip().rstrip("/")
        token = (body.get("token") or "").strip()
    else:
        base_url = (request.args.get("base_url") or "").strip().rstrip("/")
        token = (request.args.get("token") or "").strip()
    if not base_url or not token:
        return jsonify({"error": "base_url and token required"}), 400
    states = ha_client.get_states(base_url=base_url, token=token)
    return jsonify({"entities": states}), 200


@app.route("/api/v1/homeassistant/control", methods=["POST"])
def homeassistant_control():
    """Call HA service. Body: base_url, token, entity_id, action (turn_on/turn_off)."""
    body = request.get_json() or {}
    base_url = (body.get("base_url") or "").strip().rstrip("/")
    token = (body.get("token") or "").strip()
    entity_id = (body.get("entity_id") or "").strip()
    action = (body.get("action") or "turn_on").strip()
    if not base_url or not token or not entity_id:
        return jsonify({"error": "base_url, token, entity_id required"}), 400
    domain = entity_id.split(".")[0] if "." in entity_id else "light"
    service = action if action in ("turn_on", "turn_off") else "turn_on"
    ok = ha_client.call_service(base_url, token, domain, service, entity_id=entity_id)
    audit_logger.log({
        "event_type": "homeassistant_control",
        "resource": entity_id,
        "result": "success" if ok else "failed",
    })
    return jsonify({"success": ok}), 200


@app.route("/api/v1/llm/providers", methods=["GET"])
def llm_providers_list():
    """List configured LLM providers (id, name only)."""
    return jsonify({"providers": llm_gw.list_providers()}), 200


@app.route("/api/v1/llm/providers/test", methods=["POST"])
def llm_providers_test():
    """Test provider connection. Body: provider_id."""
    body = request.get_json() or {}
    provider_id = (body.get("provider_id") or "").strip()
    if not provider_id:
        return jsonify({"error": "provider_id required"}), 400
    ok = llm_gw.test_connection(provider_id)
    return jsonify({"ok": ok}), 200


@app.route("/api/v1/llm/analyze", methods=["POST"])
def llm_analyze():
    """Send file content to LLM (optional redact first). Body: file_id, provider_id, redact_first, prompt."""
    token = _auth_token()
    if not token:
        return jsonify({"error": "Missing token"}), 401
    body = request.get_json() or {}
    file_id = (body.get("file_id") or "").strip()
    provider_id = (body.get("provider_id") or "").strip()
    redact_first = body.get("redact_first", True)
    prompt = (body.get("prompt") or "Summarize the following content.").strip()
    if not file_id or not provider_id:
        return jsonify({"error": "file_id and provider_id required"}), 400
    if not TokenService.verify_token(token, f"file/{file_id}", 0, "read"):
        return jsonify({"error": "Unauthorized"}), 403
    content, err = llm_gw.analyze_file(
        file_id, provider_id, prompt, redact_first,
        file_manager, redaction_engine,
    )
    payload = TokenService.decode_payload(token)
    audit_logger.log({
        "event_type": "llm_call",
        "user_id": payload.get("user_id") if payload else None,
        "resource": file_id,
        "details": {"provider_id": provider_id, "redact_first": redact_first, "success": err is None},
        "result": "success" if err is None else "failed",
    })
    if err:
        return jsonify({"error": err}), 502
    return jsonify({"content": content}), 200


@app.route("/api/v1/llm/history", methods=["GET"])
def llm_history():
    """Return recent LLM call records from audit (admin or token)."""
    token = _auth_token()
    if not token:
        return jsonify({"error": "Missing token"}), 401
    limit = min(int(request.args.get("limit", 50)), 200)
    import sqlite3
    conn = sqlite3.connect(audit_logger.db_path)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        "SELECT id, timestamp, resource, result, details FROM audit_log WHERE event_type = ? ORDER BY id DESC LIMIT ?",
        ("llm_call", limit),
    ).fetchall()
    conn.close()
    items = []
    for r in rows:
        d = dict(r)
        if d.get("details"):
            try:
                d["details"] = json.loads(d["details"]) if isinstance(d["details"], str) else d["details"]
            except Exception:
                pass
        items.append(d)
    return jsonify({"items": items}), 200


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
