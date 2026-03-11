"""Family ledger: accounts, transactions, balance sheet; receipts uploaded via SDK to OS."""
import json
import os
import sqlite3
import sys

# Allow running from project root or /apps
ROOT = os.path.dirname(os.path.abspath(__file__))
if ROOT not in sys.path:
    sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.dirname(ROOT))))

try:
    from wowos_sdk import Client
except ImportError:
    Client = None

from flask import Flask, render_template, request, jsonify

app = Flask(__name__, template_folder=os.path.join(ROOT, "templates"))
client = Client("com.wowos.family-ledger") if Client else None

_proj_root = os.path.dirname(os.path.dirname(ROOT))
DB_PATH = os.environ.get(
    "WOWOS_LEDGER_DB",
    os.path.join(_proj_root, "data", "family-ledger.db"),
)
os.makedirs(os.path.dirname(DB_PATH) or ".", exist_ok=True)


def init_db():
    conn = sqlite3.connect(DB_PATH)
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS accounts (
            id TEXT PRIMARY KEY,
            name TEXT,
            type TEXT,
            balance REAL,
            owner TEXT
        )
    """
    )
    conn.execute(
        """
        CREATE TABLE IF NOT EXISTS transactions (
            id TEXT PRIMARY KEY,
            date INTEGER,
            amount REAL,
            category TEXT,
            from_account TEXT,
            to_account TEXT,
            note TEXT,
            receipt_file_id TEXT
        )
    """
    )
    conn.commit()
    return conn


@app.route("/")
def index():
    return render_template("index.html")


@app.route("/api/balance", methods=["GET"])
def get_balance():
    conn = init_db()
    assets = (
        conn.execute(
            "SELECT SUM(balance) FROM accounts WHERE type IN ('cash','bank','investment','asset')"
        ).fetchone()[0]
        or 0
    )
    liabilities = (
        conn.execute("SELECT SUM(balance) FROM accounts WHERE type = 'liability'")
        .fetchone()[0]
        or 0
    )
    net = assets - liabilities
    return jsonify({"assets": assets, "liabilities": liabilities, "net": net})


@app.route("/api/transactions", methods=["POST"])
def add_transaction():
    data = request.get_json() or {}
    conn = init_db()
    receipt_file_id = None
    if data.get("receipt_data") and client:
        receipt_file_id = client.upload_file(
            data["receipt_data"].encode() if isinstance(data["receipt_data"], str) else data["receipt_data"],
            "receipt.jpg",
            privacy_level=2,
        )
    conn.execute(
        """
        INSERT OR REPLACE INTO transactions
        (id, date, amount, category, from_account, to_account, note, receipt_file_id)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    """,
        (
            data.get("id", ""),
            data.get("date", 0),
            data.get("amount", 0),
            data.get("category", ""),
            data.get("from_account", ""),
            data.get("to_account", ""),
            data.get("note", ""),
            receipt_file_id,
        ),
    )
    conn.commit()
    return jsonify({"status": "ok", "receipt_id": receipt_file_id})


if __name__ == "__main__":
    port = int(os.environ.get("WOWOS_APP_PORT", "5001"))
    app.run(host="0.0.0.0", port=port)
