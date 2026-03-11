"""加密存储引擎：文件级 FEK，设备主密钥加密 FEK。存储格式：nonce(12) + ciphertext；FEK 包：encrypted_fek + nonce_master(12)。"""
import os
import hashlib
from typing import Tuple

from cryptography.hazmat.primitives.ciphers.aead import AESGCM

NONCE_LEN = 12
FEK_LEN = 32


def get_device_key() -> bytes:
    """从设备 ID + 用户密码派生设备主密钥；无 HSM 时使用 PBKDF2。"""
    device_id = os.environ.get("WOWOS_DEVICE_ID", "")
    if not device_id:
        try:
            with open("/sys/class/net/eth0/address") as f:
                device_id = f.read().strip()
        except (FileNotFoundError, OSError):
            device_id = "wowos-dev-fallback"
    user_password = os.environ.get("WOWOS_DEVICE_PASSWORD", "user_supplied")
    salt = b"wowos_salt"
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
        """返回 (nonce + 密文, encrypted_fek + nonce_master)。"""
        fek = os.urandom(FEK_LEN)
        aesgcm = AESGCM(fek)
        nonce = os.urandom(NONCE_LEN)
        encrypted_data = aesgcm.encrypt(nonce, data, None)
        # 存储格式：nonce + ciphertext，便于解密时解析
        data_blob = nonce + encrypted_data

        key = _device_key_bytes()
        aesgcm_master = AESGCM(key)
        nonce_master = os.urandom(NONCE_LEN)
        encrypted_fek = aesgcm_master.encrypt(nonce_master, fek, None)
        fek_blob = encrypted_fek + nonce_master
        return data_blob, fek_blob

    @staticmethod
    def decrypt_file(encrypted_data: bytes, encrypted_fek_with_nonce: bytes) -> bytes:
        """encrypted_data = nonce(12) + ciphertext；encrypted_fek_with_nonce = encrypted_fek + nonce_master(12)。"""
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
