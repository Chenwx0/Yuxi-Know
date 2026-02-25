"""完整测试三种 API 认证方式

测试：
1. 本地 JWT 认证
2. SSO Token 认证
3. Geelato Auth 认证
"""

import sys
import os

sys.path.insert(0, "/app")

import requests
from server.utils.config_utils import get_geelato_auth_config
from server.utils.crypto_utils import AESCrypto

API_BASE_URL = "http://localhost:5050"

# 测试账号
LOCAL_USERNAME = "admin"
LOCAL_PASSWORD = "geelato@2026"
GEELATO_AUTH_KEY = "f47ac10b-58cc-4372-a567-0e02b2c3d479"


def test_local_jwt_auth(username: str, password: str):
    """测试本地 JWT 认证"""
    print("\n" + "=" * 60)
    print("方式一：本地 JWT 认证")
    print("=" * 60)

    # 1. 登录获取 Token
    print(f"\n1. 登录中...")
    print(f"   用户名: {username}")
    print(f"   密码: {password}")
    login_url = f"{API_BASE_URL}/api/auth/token"
    response = requests.post(
        login_url,
        data={"username": username, "password": password},
        headers={"Content-Type": "application/x-www-form-urlencoded"}
    )

    if response.status_code != 200:
        print(f"❌ 登录失败: {response.status_code}")
        print(f"   Response: {response.text}")
        return False

    token = response.json()["access_token"]
    print(f"✓ 登录成功，获取 Token: {token[:30]}...")

    # 2. 使用 Token 调用 API
    print(f"\n2. 调用 API...")
    agents_url = f"{API_BASE_URL}/api/chat/agent"
    response = requests.get(
        agents_url,
        headers={"Authorization": f"Bearer {token}"}
    )

    if response.status_code != 200:
        print(f"❌ API 调用失败: {response.status_code}")
        print(f"   Response: {response.text}")
        return False

    agents = response.json()["agents"]
    print(f"✓ API 调用成功")
    print(f"   获取到 {len(agents)} 个智能体:")
    for agent in agents:
        print(f"   - {agent['name']} ({agent['id']})")

    return True


def test_sso_token_auth(sso_token: str):
    """测试 SSO Token 认证"""
    print("\n" + "=" * 60)
    print("方式二：SSO Token 认证")
    print("=" * 60)

    # 1. 使用 SSO Token 调用 API
    print(f"\n1. 使用 SSO Token 调用 API...")
    print(f"   Token: {sso_token[:30]}...")

    agents_url = f"{API_BASE_URL}/api/chat/agent"
    response = requests.get(
        agents_url,
        headers={"Authorization": f"Bearer {sso_token}"}
    )

    if response.status_code != 200:
        print(f"❌ API 调用失败: {response.status_code}")
        print(f"   Response: {response.text}")
        return False

    agents = response.json()["agents"]
    print(f"✓ API 调用成功")
    print(f"   获取到 {len(agents)} 个智能体:")
    for agent in agents:
        print(f"   - {agent['name']} ({agent['id']})")

    return True


def test_geelato_auth(auth_key: str, username: str):
    """测试 Geelato Auth 认证"""
    print("\n" + "=" * 60)
    print("方式三：Geelato Auth 认证")
    print("=" * 60)

    config = get_geelato_auth_config()

    if not config["enabled"]:
        print("❌ Geelato Auth 未启用！")
        return False

    if not config["secret_key"]:
        print("❌ 加密密钥未配置！")
        return False

    if auth_key not in config["keys"]:
        print(f"❌ 认证 Key 不在配置列表中！")
        return False

    # 1. 生成加密数据
    print(f"\n1. 生成加密数据...")
    plaintext = f"{auth_key}:{username}"
    encrypted = AESCrypto.encrypt(plaintext, config["secret_key"])
    auth_header = f"{config['prefix']} {encrypted}"
    print(f"   原始数据: {plaintext}")
    print(f"   加密后: {encrypted[:50]}...")

    # 2. 使用加密数据调用 API
    print(f"\n2. 调用 API...")
    print(f"   Authorization: {auth_header[:80]}...")

    agents_url = f"{API_BASE_URL}/api/chat/agent"
    response = requests.get(
        agents_url,
        headers={"Authorization": auth_header}
    )

    if response.status_code != 200:
        print(f"❌ API 调用失败: {response.status_code}")
        print(f"   Response: {response.text}")
        return False

    agents = response.json()["agents"]
    print(f"✓ API 调用成功")
    print(f"   获取到 {len(agents)} 个智能体:")
    for agent in agents:
        print(f"   - {agent['name']} ({agent['id']})")

    return True


def main():
    print("=" * 60)
    print("Yuxi-Know API 认证方式完整测试")
    print("=" * 60)

    results = {}

    # 测试方式一：本地 JWT 认证
    print("\n\n" + "─" * 60)
    print("测试方式一：本地 JWT 认证")
    print("─" * 60)
    results["local_jwt"] = test_local_jwt_auth(LOCAL_USERNAME, LOCAL_PASSWORD)

    # 测试方式二：SSO Token 认证
    print("\n\n" + "─" * 60)
    print("测试方式二：SSO Token 认证")
    print("─" * 60)
    sso_token = os.environ.get("TEST_SSO_TOKEN", "")
    if sso_token:
        print(f"Token: {sso_token[:30]}...")
        results["sso_token"] = test_sso_token_auth(sso_token)
    else:
        print("⚠️  跳过：未设置 TEST_SSO_TOKEN 环境变量")
        print("   设置方式: export TEST_SSO_TOKEN=your_sso_token")
        results["sso_token"] = None

    # 测试方式三：Geelato Auth 认证
    print("\n\n" + "─" * 60)
    print("测试方式三：Geelato Auth 认证")
    print("─" * 60)
    results["geelato_auth"] = test_geelato_auth(GEELATO_AUTH_KEY, LOCAL_USERNAME)

    # 测试结果汇总
    print("\n\n" + "=" * 60)
    print("测试结果汇总")
    print("=" * 60)

    for method, result in results.items():
        if result is None:
            print(f"⚠️  {method}: 跳过")
        elif result:
            print(f"✓ {method}: 通过")
        else:
            print(f"❌ {method}: 失败")

    passed = sum(1 for r in results.values() if r is True)
    failed = sum(1 for r in results.values() if r is False)
    skipped = sum(1 for r in results.values() if r is None)
    total = len(results)

    print(f"\n总计: {passed} 通过, {failed} 失败, {skipped} 跳过")

    if failed == 0:
        print("\n✓ 所有已测试的认证方式通过！")
        return 0
    else:
        print(f"\n❌ {failed} 个认证方式测试失败！")
        return 1


if __name__ == "__main__":
    sys.exit(main())
