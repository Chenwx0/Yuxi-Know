"""测试 GEELATO_AUTH_REQUIRE_USER_EXIST 配置

测试场景：
1. require_user_exist=true 时，用户不存在应报错
2. require_user_exist=false 时，用户不存在应自动创建用户
"""

import sys
import os

sys.path.insert(0, "/app")

import requests
from server.utils.config_utils import get_geelato_auth_config
from server.utils.crypto_utils import AESCrypto

API_BASE_URL = "http://localhost:5050"
GEELATO_AUTH_KEY = "f47ac10b-58cc-4372-a567-0e02b2c3d479"


def test_geelato_auth(auth_key: str, username: str):
    """测试 Geelato Auth 认证"""
    config = get_geelato_auth_config()

    print(f"\n配置信息:")
    print(f"   enabled: {config['enabled']}")
    print(f"   require_user_exist: {config['require_user_exist']}")

    if not config["enabled"]:
        print("❌ Geelato Auth 未启用！")
        return False, None

    if not config["secret_key"]:
        print("❌ 加密密钥未配置！")
        return False, None

    if auth_key not in config["keys"]:
        print(f"❌ 认证 Key 不在配置列表中！")
        return False, None

    # 生成加密数据
    plaintext = f"{auth_key}:{username}"
    encrypted = AESCrypto.encrypt(plaintext, config["secret_key"])
    auth_header = f"{config['prefix']} {encrypted}"
    print(f"\n请求信息:")
    print(f"   用户名: {username}")
    print(f"   原始数据: {plaintext}")
    print(f"   Authorization: {auth_header[:80]}...")

    # 调用 API
    agents_url = f"{API_BASE_URL}/api/chat/agent"
    response = requests.get(
        agents_url,
        headers={"Authorization": auth_header}
    )

    print(f"\n响应信息:")
    print(f"   状态码: {response.status_code}")

    if response.status_code == 200:
        agents = response.json()["agents"]
        print(f"   ✓ 认证成功")
        print(f"   获取到 {len(agents)} 个智能体")
        return True, response.json()
    else:
        print(f"   ❌ 认证失败")
        print(f"   错误信息: {response.text}")
        return False, response.text


def main():
    print("=" * 60)
    print("测试 GEELATO_AUTH_REQUIRE_USER_EXIST 配置")
    print("=" * 60)

    config = get_geelato_auth_config()
    require_user_exist = config["require_user_exist"]

    # 使用一个不存在的用户名测试
    test_username = f"test_geelato_user_{os.getpid()}"

    print(f"\n测试用户: {test_username}")
    print(f"当前配置: GEELATO_AUTH_REQUIRE_USER_EXIST={require_user_exist}")

    success, result = test_geelato_auth(GEELATO_AUTH_KEY, test_username)

    print("\n" + "=" * 60)
    print("测试结果分析")
    print("=" * 60)

    if require_user_exist:
        if success:
            print("❌ 预期失败但成功了！")
            print("   当 require_user_exist=true 时，用户不存在应该报错")
        else:
            print("✓ 符合预期！")
            print("   当 require_user_exist=true 时，用户不存在正确报错")
    else:
        if success:
            print("✓ 符合预期！")
            print("   当 require_user_exist=false 时，自动创建用户并认证成功")
        else:
            print("❌ 预期成功但失败了！")
            print("   当 require_user_exist=false 时，应该自动创建用户")


if __name__ == "__main__":
    main()
