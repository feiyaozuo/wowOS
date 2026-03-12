"""wowOS Desktop server: serves Launcher + App/File/Settings UIs and proxies to wowOS API."""
import os
import requests
from pathlib import Path
from flask import Flask, request, send_from_directory, Response

ROOT = Path(__file__).resolve().parent
API_BASE = os.environ.get("WOWOS_API_URL", "http://127.0.0.1:8080").rstrip("/")
APP_CENTER_BASE = os.environ.get("WOWOS_APP_CENTER_URL", "http://127.0.0.1:8000").rstrip("/")
DESKTOP_PORT = int(os.environ.get("WOWOS_DESKTOP_PORT", "9090"))

app = Flask(__name__, static_folder=None)


@app.route("/")
def launcher():
    return send_from_directory(ROOT / "launcher", "index.html")


@app.route("/app-center")
def app_center():
    return send_from_directory(ROOT / "app_center_ui", "index.html")


@app.route("/file-center")
def file_center():
    return send_from_directory(ROOT / "file_center_ui", "index.html")


@app.route("/settings")
def settings():
    return send_from_directory(ROOT / "settings_ui", "index.html")


@app.route("/home")
def home():
    return send_from_directory(ROOT / "home_ui", "index.html")


@app.route("/llm")
def llm():
    return send_from_directory(ROOT / "llm_ui", "index.html")


@app.route("/launcher/<path:path>")
def launcher_static(path):
    return send_from_directory(ROOT / "launcher", path)


@app.route("/app-center-ui/<path:path>")
def app_center_static(path):
    return send_from_directory(ROOT / "app_center_ui", path)


@app.route("/file-center-ui/<path:path>")
def file_center_static(path):
    return send_from_directory(ROOT / "file_center_ui", path)


@app.route("/settings-ui/<path:path>")
def settings_static(path):
    return send_from_directory(ROOT / "settings_ui", path)


@app.route("/home-ui/<path:path>")
def home_ui_static(path):
    return send_from_directory(ROOT / "home_ui", path)


@app.route("/llm-ui/<path:path>")
def llm_ui_static(path):
    return send_from_directory(ROOT / "llm_ui", path)


@app.route("/api/proxy/<path:path>", methods=["GET", "POST", "PUT", "DELETE", "PATCH"])
def api_proxy(path):
    """Proxy to wowOS API to avoid CORS."""
    url = f"{API_BASE}/api/v1/{path}"
    headers = {k: v for k, v in request.headers if k.lower() != "host"}
    try:
        if request.method == "GET":
            r = requests.get(url, headers=headers, params=request.args, timeout=10)
        elif request.method == "POST":
            if request.content_type and "multipart/form-data" in (request.content_type or ""):
                r = requests.post(
                    url, headers=headers, params=request.args,
                    data=request.get_data(), timeout=10
                )
            else:
                r = requests.post(
                    url, headers=headers, params=request.args,
                    data=request.get_data() if not request.get_json(silent=True) else None,
                    json=request.get_json(silent=True), timeout=10
                )
        elif request.method == "DELETE":
            r = requests.delete(url, headers=headers, timeout=10)
        else:
            r = requests.request(request.method, url, headers=headers, timeout=10)
        return Response(r.content, status=r.status_code, content_type=r.headers.get("Content-Type", "application/json"))
    except Exception as e:
        return Response(f'{{"error":"{str(e)}"}}', status=502, content_type="application/json")


@app.route("/api/app-center/<path:path>")
def app_center_proxy(path):
    """Proxy to app center (apps.json, packages)."""
    url = f"{APP_CENTER_BASE}/{path}"
    try:
        r = requests.get(url, timeout=10)
        return Response(r.content, status=r.status_code, content_type=r.headers.get("Content-Type", "application/json"))
    except Exception as e:
        return Response(f'{{"error":"{str(e)}"}}', status=502, content_type="application/json")


def run():
    app.run(host="0.0.0.0", port=DESKTOP_PORT, debug=False, threaded=True)


if __name__ == "__main__":
    run()
