"""测试 Geelato Auth 配置和认证"""

import os
import sys

sys.path.insert(0, "/app")

from server.utils.config_utils import get_geelato_auth_config
from server.utils.crypto_utils import AESCrypto


def test_config():
    """测试配置读取"""
    print("=" * 50)
    print("Geelato Auth 配置检查")
    print("=" * 50)

    config = get_geelato_auth_config()
    print(f"enabled: {config['enabled']}")
    print(f"prefix: {config['prefix']}")
    print(f"secret_key: {config['secret_key'][:20]}..." if config['secret_key'] else "secret_key: (未配置)")
    print(f"keys: {config['keys']}")
    print(f"require_user_exist: {config['require_user_exist']}")

    if not config['enabled']:
        print("\n❌ Geelato Auth 未启用！请设置 GEELATO_AUTH_ENABLED=true")
        return False

    if not config['secret_key']:
        print("\n❌ 加密密钥未配置！请设置 GEELATO_AUTH_SECRET_KEY")
        return False

    if not config['keys']:
        print("\n❌ 认证 Key 列表为空！请设置 GEELATO_AUTH_KEYS")
        return False

    print("\n✓ 配置检查通过")
    return True


def test_encrypt():
    """测试加密功能"""
    print("\n" + "=" * 50)
    print("加密功能测试")
    print("=" * 50)

    config = get_geelato_auth_config()

    auth_key = config['keys'][0] if config['keys'] else "test-key"
    username = "admin"
    plaintext = f"{auth_key}:{username}"

    print(f"原始数据: {plaintext}")

    try:
        encrypted = AESCrypto.encrypt(plaintext, config['secret_key'])
        print(f"加密后: {encrypted}")

        decrypted = AESCrypto.decrypt(encrypted, config['secret_key'])
        print(f"解密后: {decrypted}")

        if decrypted == plaintext:
            print("\n✓ 加密解密测试通过")
            print(f"\n测试用的 Authorization 头:")
            print(f"Authorization: {config['prefix']} {encrypted}")
            return True
        else:
            print("\n❌ 加密解密结果不匹配")
            return False
    except Exception as e:
        print(f"\n❌ 加密解密测试失败: {e}")
        return False


if __name__ == "__main__":
    print("Geelato Auth 诊断脚本\n")

    if not test_config():
        sys.exit(1)

    if not test_encrypt():
        sys.exit(1)

    print("\n" + "=" * 50)
    print("所有检查通过！")
    print("=" * 50)
