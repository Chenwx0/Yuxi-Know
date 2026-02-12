"""OAuth2 认证中心客户端封装

提供与统一认证中心交互的功能，包括：
- 构建授权 URL
- 授权码换取访问令牌
- 获取用户信息
- 验证 Token 有效性

使用方法:
    from server.utils.oauth2_client import get_oauth2_client

    oauth_client = get_oauth2_client()
    if oauth_client:
        # 构建授权 URL
        auth_url = oauth_client.build_authorization_url()
        # 获取用户信息
        user_info = await oauth_client.get_user_info(access_token)
"""

import os
from typing import Any
from urllib.parse import urlencode

import httpx

from src.utils import logger


class OAuth2Client:
    """OAuth2 认证中心客户端"""

    def __init__(
        self,
        authorization_url: str | None = None,
        token_url: str | None = None,
        user_info_url: str | None = None,
        introspect_url: str | None = None,
        client_id: str | None = None,
        client_secret: str | None = None,
        redirect_uri: str | None = None,
        scope: str | None = None,
    ):
        """初始化 OAuth2 客户端

        Args:
            authorization_url: OAuth2 授权端点 URL
            token_url: OAuth2 Token 端点 URL
            user_info_url: 用户信息端点 URL
            introspect_url: Token 内省端点 URL（可选）
            client_id: 客户端 ID
            client_secret: 客户端密钥
            redirect_uri: 回调地址
            scope: 授权范围
        """
        self.authorization_url = authorization_url
        self.token_url = token_url
        self.user_info_url = user_info_url
        self.introspect_url = introspect_url
        self.client_id = client_id
        self.client_secret = client_secret
        self.redirect_uri = redirect_uri
        self.scope = scope or "openid profile email"

    def build_authorization_url(self, state: str | None = None) -> str:
        """构建授权 URL

        Args:
            state: 用于 CSRF 防护的状态参数，建议使用随机生成的唯一值

        Returns:
            完整的授权 URL
        """
        params = {
            "response_type": "code",
            "client_id": self.client_id,
            "redirect_uri": self.redirect_uri,
            "scope": self.scope,
        }
        if state:
            params["state"] = state

        query_string = urlencode(params)
        return f"{self.authorization_url}?{query_string}"

    async def exchange_code_for_token(self, code: str) -> dict[str, Any]:
        """用授权码换取访问令牌

        Args:
            code: 认证中心回调返回的授权码

        Returns:
            包含 access_token 的响应数据

        Raises:
            httpx.HTTPError: 请求失败时抛出
        """
        data = {
            "grant_type": "authorization_code",
            "code": code,
            "client_id": self.client_id,
            "client_secret": self.client_secret,
            "redirect_uri": self.redirect_uri,
        }

        logger.debug(f"正在用授权码换取 Token: {self.token_url}")

        async with httpx.AsyncClient() as client:
            response = await client.post(self.token_url, data=data)
            response.raise_for_status()
            return response.json()

    async def get_user_info(self, access_token: str) -> dict[str, Any]:
        """获取用户信息

        Args:
            access_token: OAuth2 访问令牌

        Returns:
            用户信息字典

        Raises:
            httpx.HTTPError: 请求失败时抛出
        """
        headers = {"Authorization": f"Bearer {access_token}"}

        logger.debug(f"正在获取用户信息: {self.user_info_url}")

        async with httpx.AsyncClient() as client:
            response = await client.get(self.user_info_url, headers=headers)
            response.raise_for_status()
            return response.json()

    async def introspect_token(self, token: str) -> dict[str, Any]:
        """验证 Token 有效性

        调用 introspect 端点验证 Token 是否有效。

        Args:
            token: 待验证的 OAuth2 Token

        Returns:
            Token 信息字典，包含 active 字段表示是否有效

        Raises:
            httpx.HTTPError: 请求失败时抛出
        """
        data = {
            "token": token,
            "client_id": self.client_id,
            "client_secret": self.client_secret,
        }

        logger.debug(f"正在验证 Token: {self.introspect_url}")

        async with httpx.AsyncClient() as client:
            response = await client.post(self.introspect_url, data=data)
            response.raise_for_status()
            return response.json()

    def get_field_mapping(self) -> dict[str, str]:
        """获取用户字段映射配置

        从环境变量读取字段映射配置。

        Returns:
            字段映射字典
        """
        return {
            "username": os.environ.get("SSO_FIELD_MAPPING_USERNAME", "username"),
            "user_id_sso": os.environ.get("SSO_FIELD_MAPPING_USERID", "sub"),
            "phone_number": os.environ.get("SSO_FIELD_MAPPING_PHONE", "phone_number"),
            "avatar": os.environ.get("SSO_FIELD_MAPPING_AVATAR", "picture"),
            "email": os.environ.get("SSO_FIELD_MAPPING_EMAIL", "email"),
        }


# 全局客户端实例
_oauth2_client: OAuth2Client | None = None


def get_oauth2_client() -> OAuth2Client | None:
    """获取 OAuth2 客户端实例

    如果 SSO 未启用或配置不完整，返回 None。

    Returns:
        OAuth2 客户端实例，或 None
    """
    global _oauth2_client

    if _oauth2_client is not None:
        return _oauth2_client

    enabled = os.environ.get("SSO_ENABLED", "false").lower() == "true"
    if not enabled:
        return None

    # 检查必要配置
    required_fields = [
        "SSO_AUTHORIZATION_URL",
        "SSO_TOKEN_URL",
        "SSO_USER_INFO_URL",
        "SSO_CLIENT_ID",
        "SSO_CLIENT_SECRET",
        "SSO_REDIRECT_URI",
    ]

    missing_fields = [field for field in required_fields if not os.environ.get(field)]
    if missing_fields:
        logger.warning(f"SSO 配置不完整，缺少: {', '.join(missing_fields)}")
        return None

    _oauth2_client = OAuth2Client(
        authorization_url=os.environ.get("SSO_AUTHORIZATION_URL"),
        token_url=os.environ.get("SSO_TOKEN_URL"),
        user_info_url=os.environ.get("SSO_USER_INFO_URL"),
        introspect_url=os.environ.get("SSO_INTROSPECT_URL"),
        client_id=os.environ.get("SSO_CLIENT_ID"),
        client_secret=os.environ.get("SSO_CLIENT_SECRET"),
        redirect_uri=os.environ.get("SSO_REDIRECT_URI"),
        scope=os.environ.get("SSO_SCOPE"),
    )

    logger.info("OAuth2 客户端初始化成功")
    return _oauth2_client


def reset_oauth2_client() -> None:
    """重置全局 OAuth2 客户端实例

    用于测试或配置更新后重新初始化。
    """
    global _oauth2_client
    _oauth2_client = None
    logger.debug("OAuth2 客户端实例已重置")
