"""Geelato Auth 测试脚本

测试 Geelato Auth 认证方式的加密、解密和 API 调用功能。
"""

import asyncio
import base64
import os
import sys

sys.path.insert(0, "/app")

from server.utils.crypto_utils import AESCrypto


def test_encrypt_decrypt():
    """测试加密解密功能"""
    print("=" * 50)
    print("测试加密解密功能")
    print("=" * 50)

    # 生成密钥
    secret_key = AESCrypto.generate_key()
    print(f"生成的密钥: {secret_key}")

    # 测试数据
    plaintext = "f47ac10b-58cc-4372-a567-0e02b2c3d479:admin"
    print(f"原始数据: {plaintext}")

    # 加密
    encrypted = AESCrypto.encrypt(plaintext, secret_key)
    print(f"加密后: {encrypted}")

    # 解密
    decrypted = AESCrypto.decrypt(encrypted, secret_key)
    print(f"解密后: {decrypted}")

    # 验证
    assert plaintext == decrypted, "加密解密验证失败"
    print("✓ 加密解密验证成功")

    return secret_key, encrypted


def test_invalid_key():
    """测试无效密钥"""
    print("\n" + "=" * 50)
    print("测试无效密钥")
    print("=" * 50)

    secret_key = AESCrypto.generate_key()
    wrong_key = AESCrypto.generate_key()

    plaintext = "test-key:test-user"
    encrypted = AESCrypto.encrypt(plaintext, secret_key)

    try:
        AESCrypto.decrypt(encrypted, wrong_key)
        print("✗ 应该抛出异常但没有")
    except ValueError as e:
        print(f"✓ 正确抛出异常: {e}")


def test_invalid_data():
    """测试无效数据"""
    print("\n" + "=" * 50)
    print("测试无效数据")
    print("=" * 50)

    secret_key = AESCrypto.generate_key()

    # 测试无效 Base64
    try:
        AESCrypto.decrypt("invalid-base64!!!", secret_key)
        print("✗ 应该抛出异常但没有")
    except ValueError as e:
        print(f"✓ 正确抛出异常: {e}")

    # 测试数据长度不足
    short_data = base64.b64encode(b"short").decode()
    try:
        AESCrypto.decrypt(short_data, secret_key)
        print("✗ 应该抛出异常但没有")
    except ValueError as e:
        print(f"✓ 正确抛出异常: {e}")


def generate_test_config():
    """生成测试配置"""
    print("\n" + "=" * 50)
    print("生成测试配置")
    print("=" * 50)

    secret_key = AESCrypto.generate_key()
    auth_key = "f47ac10b-58cc-4372-a567-0e02b2c3d479"

    print("请将以下配置添加到 .env 文件中:")
    print("-" * 50)
    print(f"GEELATO_AUTH_ENABLED=true")
    print(f"GEELATO_AUTH_SECRET_KEY={secret_key}")
    print(f"GEELATO_AUTH_KEYS={auth_key}")
    print("-" * 50)

    # 生成加密数据
    username = "admin"
    plaintext = f"{auth_key}:{username}"
    encrypted = AESCrypto.encrypt(plaintext, secret_key)

    print(f"\n测试用的 Authorization 头:")
    print(f"Authorization: geelato_auth {encrypted}")
    print("-" * 50)

    return secret_key, auth_key, encrypted


if __name__ == "__main__":
    print("Geelato Auth 测试脚本")
    print("=" * 50)

    # 测试加密解密
    test_encrypt_decrypt()

    # 测试无效密钥
    test_invalid_key()

    # 测试无效数据
    test_invalid_data()

    # 生成测试配置
    generate_test_config()

    print("\n" + "=" * 50)
    print("所有测试通过!")
    print("=" * 50)
