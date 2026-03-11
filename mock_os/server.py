"""mock_os 模拟服务：与真实 OS API 一致的端点，用于本地开发。"""
import io
import json
import os
import re
from pathlib import Path
from flask import Flask, request, jsonify, send_file

app = Flask(__name__)
DATA_DIR = Path(os.environ.get("WOWOS_MOCK_DATA", "./mock-data"))
FILES_DIR = DATA_DIR / "files"
AUDIT_ENTRIES = []
AUTO_APPROVE = os.environ.get("WOWOS_MOCK_AUTO_APPROVE", "1") == "1"

FILES_DIR.mkdir(parents=True, exist_ok=True)


def _mock_redact(data: bytes, source_level: int, target_level: int) -> bytes:
    if source_level <= target_level:
        return data
    try:
        text = data.decode("utf-8")
        text = re.sub(r"\d", "*", text)
        return text.encode("utf-8")
    except Exception:
        return data


@app.route("/api/v1/health", methods=["GET"])
def health():
    return jsonify({"status": "ok", "service": "wowos-mock"})


@app.route("/api/v1/tokens", methods=["POST"])
def create_token():
    body = request.get_json() or {}
    app_id = body.get("app_id", "mock-app")
    resources = body.get("resources", ["file/*"])
    max_level = int(body.get("max_level", 3))
    ttl = int(body.get("ttl", 3600))
    token = f"mock-token-{app_id}-{max_level}"
    return jsonify({"token": token}), 200


@app.route("/api/v1/files", methods=["POST"])
def upload_file():
    token = request.headers.get("Authorization", "").replace("Bearer ", "")
    if not token:
        return jsonify({"error": "Missing token"}), 401
    f = request.files.get("file")
    if not f:
        return jsonify({"error": "No file"}), 400
    data = f.read()
    name = f.filename or "unnamed"
    privacy_level = int(request.form.get("privacy_level", 3))
    file_id = f"file_mock_{len(list(FILES_DIR.glob('*')))}"
    path = FILES_DIR / f"{file_id}.data"
    path.write_bytes(data)
    meta = {"file_id": file_id, "name": name, "privacy_level": privacy_level}
    (FILES_DIR / f"{file_id}.meta.json").write_text(
        json.dumps(meta, ensure_ascii=False), encoding="utf-8"
    )
    return jsonify({"file_id": file_id}), 200


@app.route("/api/v1/files/<file_id>", methods=["GET"])
def get_file(file_id):
    token = request.headers.get("Authorization", "").replace("Bearer ", "")
    if not token:
        return jsonify({"error": "Missing token"}), 401
    requested_level = int(request.args.get("level", 3))
    path = FILES_DIR / f"{file_id}.data"
    if not path.exists():
        return jsonify({"error": "Not found"}), 404
    data = path.read_bytes()
    meta_path = FILES_DIR / f"{file_id}.meta.json"
    metadata = json.loads(meta_path.read_text(encoding="utf-8")) if meta_path.exists() else {}
    original_level = metadata.get("privacy_level", 3)
    data = _mock_redact(data, original_level, requested_level)
    AUDIT_ENTRIES.append({
        "event_type": "data_access",
        "resource": file_id,
        "original_level": original_level,
        "accessed_level": requested_level,
        "result": "success",
    })
    return send_file(
        io.BytesIO(data),
        download_name=metadata.get("name", "file"),
        as_attachment=True,
    )


@app.route("/api/v1/audit", methods=["GET"])
def get_audit():
    limit = int(request.args.get("limit", 100))
    return jsonify({"items": AUDIT_ENTRIES[-limit:][::-1]}), 200


def run():
    port = int(os.environ.get("WOWOS_MOCK_PORT", "8081"))
    app.run(host="0.0.0.0", port=port, debug=False)


if __name__ == "__main__":
    run()
