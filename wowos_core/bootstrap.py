"""Production startup check: refuse to start and log when secret/salt/device_password are missing."""
import os
import sys

VAR_LIB = os.environ.get("VAR_LIB_WOWOS", "/var/lib/wowos")
DEVICE_SALT_PATH = os.environ.get(
    "WOWOS_DEVICE_SALT_PATH",
    os.path.join(VAR_LIB, "device_salt"),
)
ENV_FILE = os.path.join(VAR_LIB, "env")
DEV_MODE = os.environ.get("WOWOS_DEV_MODE", "").lower() in ("1", "true", "yes")


def check_production_key_material() -> None:
    """In production, validate key material; log and exit on missing items."""
    if DEV_MODE:
        return
    errors = []
    if not os.path.isfile(DEVICE_SALT_PATH):
        errors.append(f"missing device salt file: {DEVICE_SALT_PATH}")
    secret = os.environ.get("WOWOS_SECRET_KEY", "")
    if not secret or secret.strip() == "":
        errors.append("WOWOS_SECRET_KEY is not set (required in production)")
    elif secret == "device-unique-secret-dev-only":
        errors.append("WOWOS_SECRET_KEY must not be the dev default in production")
    device_pass = os.environ.get("WOWOS_DEVICE_PASSWORD", "")
    if not device_pass or (device_pass.strip() == "" or device_pass == "user_supplied"):
        errors.append(
            "WOWOS_DEVICE_PASSWORD must be set and not default (e.g. via " + ENV_FILE + ")"
        )
    if errors:
        msg = "wowOS production mode: refusing to start - " + "; ".join(errors)
        print(msg, file=sys.stderr)
        sys.exit(1)
