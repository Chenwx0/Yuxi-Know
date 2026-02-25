"""测试 Geelato Auth API 调用"""

import sys
sys.path.insert(0, "/app")

import requests
from server.utils.config_utils import get_geelato_auth_config
from server.utils.crypto_utils import AESCrypto

config = get_geelato_auth_config()

auth_key = config['keys'][0]
username = "admin"
plaintext = f"{auth_key}:{username}"
encrypted = AESCrypto.encrypt(plaintext, config['secret_key'])

auth_header = f"{config['prefix']} {encrypted}"
print(f"Authorization: {auth_header}")

url = "http://localhost:5050/api/chat/agent"
headers = {"Authorization": auth_header}

response = requests.get(url, headers=headers)
print(f"\nStatus: {response.status_code}")
print(f"Response: {response.text[:500]}")
