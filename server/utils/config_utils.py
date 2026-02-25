"""配置工具模块

提供 Geelato Auth 配置读取功能。
"""

import os
from typing import Any


def get_geelato_auth_config() -> dict[str, Any]:
    """获取 Geelato Auth 配置

    Returns:
        包含以下字段的配置字典:
        - enabled: 是否启用
        - prefix: 认证前缀
        - secret_key: 加密密钥
        - keys: 认证 Key 列表
        - require_user_exist: 是否要求用户存在
    """
    keys_str = os.environ.get("GEELATO_AUTH_KEYS", "")
    keys = [key.strip() for key in keys_str.split(",") if key.strip()]

    return {
        "enabled": os.environ.get("GEELATO_AUTH_ENABLED", "false").lower() == "true",
        "prefix": os.environ.get("GEELATO_AUTH_PREFIX", "geelato_auth"),
        "secret_key": os.environ.get("GEELATO_AUTH_SECRET_KEY", ""),
        "keys": keys,
        "require_user_exist": os.environ.get("GEELATO_AUTH_REQUIRE_USER_EXIST", "true").lower()
        == "true",
    }
