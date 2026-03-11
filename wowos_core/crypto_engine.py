"""Crypto storage engine: per-file FEK, device master key encrypts FEK. Format: nonce(12)+ciphertext; FEK blob: encrypted_fek+nonce_master(12)."""
import os
import hashlib
from typing import Tuple

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

NONCE_LEN = 12
FEK_LEN = 32

# Device salt file path; must exist in production and be unique per device
DEVICE_SALT_PATH = os.environ.get(
    "WOWOS_DEVICE_SALT_PATH",
    os.path.join(os.environ.get("VAR_LIB_WOWOS", "/var/lib/wowos"), "device_salt"),
)
DEV_MODE = os.environ.get("WOWOS_DEV_MODE", "").lower() in ("1", "true", "yes")


def _get_salt() -> bytes:
    """Read device salt; raise in production if missing; use fixed salt in dev."""
    if os.path.isfile(DEVICE_SALT_PATH):
        with open(DEVICE_SALT_PATH, "rb") as f:
            return f.read()
    if DEV_MODE:
        return b"wowos_salt"
    raise RuntimeError(
        f"Production mode: missing device salt at {DEVICE_SALT_PATH}. "
        "Run firstboot wizard or create salt file."
    )


def get_device_key() -> bytes:
    """Derive device master key from device ID + user password + device salt; PBKDF2 when no HSM."""
    device_id = os.environ.get("WOWOS_DEVICE_ID", "")
    if not device_id:
        try:
            with open("/sys/class/net/eth0/address") as f:
                device_id = f.read().strip()
        except (FileNotFoundError, OSError):
            device_id = "wowos-dev-fallback"
    user_password = os.environ.get("WOWOS_DEVICE_PASSWORD", "user_supplied")
    salt = _get_salt()
    return hashlib.pbkdf2_hmac(
        "sha256", (device_id + user_password).encode(), salt, 100000
    )


_device_key: bytes = None


def _device_key_bytes() -> bytes:
    global _device_key
    if _device_key is None:
        _device_key = get_device_key()
    return _device_key


class CryptoEngine:
    @staticmethod
    def encrypt_file(data: bytes) -> Tuple[bytes, bytes]:
        """Return (nonce + ciphertext, encrypted_fek + nonce_master)."""
        fek = os.urandom(FEK_LEN)
        aesgcm = AESGCM(fek)
        nonce = os.urandom(NONCE_LEN)
        encrypted_data = aesgcm.encrypt(nonce, data, None)
        # Store as nonce + ciphertext for easy parse on decrypt
        data_blob = nonce + encrypted_data

        key = _device_key_bytes()
        aesgcm_master = AESGCM(key)
        nonce_master = os.urandom(NONCE_LEN)
        encrypted_fek = aesgcm_master.encrypt(nonce_master, fek, None)
        fek_blob = encrypted_fek + nonce_master
        return data_blob, fek_blob

    @staticmethod
    def decrypt_file(encrypted_data: bytes, encrypted_fek_with_nonce: bytes) -> bytes:
        """encrypted_data = nonce(12)+ciphertext; encrypted_fek_with_nonce = encrypted_fek+nonce_master(12)."""
        if len(encrypted_data) < NONCE_LEN:
            raise ValueError("encrypted_data too short")
        nonce = encrypted_data[:NONCE_LEN]
        ciphertext = encrypted_data[NONCE_LEN:]

        if len(encrypted_fek_with_nonce) < NONCE_LEN:
            raise ValueError("encrypted_fek_with_nonce too short")
        encrypted_fek = encrypted_fek_with_nonce[:-NONCE_LEN]
        nonce_master = encrypted_fek_with_nonce[-NONCE_LEN:]

        key = _device_key_bytes()
        aesgcm_master = AESGCM(key)
        fek = aesgcm_master.decrypt(nonce_master, encrypted_fek, None)
        aesgcm = AESGCM(fek)
        return aesgcm.decrypt(nonce, ciphertext, None)
