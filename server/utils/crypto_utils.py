"""加密工具模块

提供 AES-256-CBC 对称加密功能，用于 Geelato Auth 认证方式。
"""

import base64
import os

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.backends import default_backend


class AESCrypto:
    """AES-256-CBC 加密工具"""

    BLOCK_SIZE = 16
    KEY_SIZE = 32

    @staticmethod
    def generate_key() -> str:
        """生成随机密钥（Base64编码）

        Returns:
            Base64编码的32字节随机密钥
        """
        key = os.urandom(AESCrypto.KEY_SIZE)
        return base64.b64encode(key).decode("utf-8")

    @staticmethod
    def encrypt(plaintext: str, secret_key_b64: str) -> str:
        """加密数据

        Args:
            plaintext: 明文数据
            secret_key_b64: Base64编码的密钥

        Returns:
            Base64编码的加密数据（IV + 密文）

        Raises:
            ValueError: 密钥格式错误
        """
        try:
            key = base64.b64decode(secret_key_b64)
        except Exception as e:
            raise ValueError(f"密钥格式错误: {e}")

        if len(key) != AESCrypto.KEY_SIZE:
            raise ValueError(f"密钥长度错误，期望 {AESCrypto.KEY_SIZE} 字节，实际 {len(key)} 字节")

        iv = os.urandom(AESCrypto.BLOCK_SIZE)

        plaintext_bytes = plaintext.encode("utf-8")
        padding_len = AESCrypto.BLOCK_SIZE - len(plaintext_bytes) % AESCrypto.BLOCK_SIZE
        padded_data = plaintext_bytes + bytes([padding_len] * padding_len)

        cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
        encryptor = cipher.encryptor()
        ciphertext = encryptor.update(padded_data) + encryptor.finalize()

        return base64.b64encode(iv + ciphertext).decode("utf-8")

    @staticmethod
    def decrypt(encrypted_b64: str, secret_key_b64: str) -> str:
        """解密数据

        Args:
            encrypted_b64: Base64编码的加密数据（IV + 密文）
            secret_key_b64: Base64编码的密钥

        Returns:
            解密后的明文

        Raises:
            ValueError: 密钥或数据格式错误
        """
        try:
            key = base64.b64decode(secret_key_b64)
        except Exception as e:
            raise ValueError(f"密钥格式错误: {e}")

        if len(key) != AESCrypto.KEY_SIZE:
            raise ValueError(f"密钥长度错误，期望 {AESCrypto.KEY_SIZE} 字节，实际 {len(key)} 字节")

        try:
            encrypted_data = base64.b64decode(encrypted_b64)
        except Exception as e:
            raise ValueError(f"加密数据格式错误: {e}")

        if len(encrypted_data) < AESCrypto.BLOCK_SIZE * 2:
            raise ValueError("加密数据长度不足")

        iv = encrypted_data[: AESCrypto.BLOCK_SIZE]
        ciphertext = encrypted_data[AESCrypto.BLOCK_SIZE :]

        cipher = Cipher(algorithms.AES(key), modes.CBC(iv), backend=default_backend())
        decryptor = cipher.decryptor()
        padded_data = decryptor.update(ciphertext) + decryptor.finalize()

        padding_len = padded_data[-1]
        if padding_len > AESCrypto.BLOCK_SIZE or padding_len == 0:
            raise ValueError("填充数据无效，可能密钥错误")

        plaintext_bytes = padded_data[:-padding_len]

        return plaintext_bytes.decode("utf-8")
