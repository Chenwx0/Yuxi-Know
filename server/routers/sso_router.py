"""SSO 单点登录路由

提供与统一认证中心交互的 API 端点：
- 检查 SSO 是否启用
- 生成授权 URL
- 处理 SSO 回调
"""

import secrets
from typing import Any

from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.storage.postgres.manager import pg_manager
from src.storage.postgres.models_business import User, Department
from server.utils.auth_middleware import get_db
from server.utils.auth_utils import AuthUtils
from server.utils.oauth2_client import get_oauth2_client
from src.utils.datetime_utils import utc_now_naive
from server.utils.user_utils import generate_unique_user_id, validate_username
from src.utils import logger

sso = APIRouter(prefix="/auth/sso", tags=["sso-authentication"])


# ============================================================================
# 数据模型
# ============================================================================


class SSOLoginResponse(BaseModel):
    """SSO 登录响应"""

    authorization_url: str
    state: str


class SSOCallbackRequest(BaseModel):
    """SSO 回调请求"""

    code: str
    state: str | None = None


class TokenResponse(BaseModel):
    """Token 响应"""

    access_token: str
    token_type: str
    user_id: int
    username: str
    user_id_login: str
    phone_number: str | None = None
    avatar: str | None = None
    role: str
    department_id: int | None = None
    department_name: str | None = None


# ============================================================================
# 核心路由
# ============================================================================


@sso.get("/enabled")
async def check_sso_enabled():
    """检查 SSO 是否启用

    Returns:
        包含 enabled 字段的响应
    """
    oauth_client = get_oauth2_client()
    return {"enabled": oauth_client is not None}


@sso.get("/login", response_model=SSOLoginResponse)
async def sso_login():
    """生成 SSO 授权 URL

    生成随机 state 用于 CSRF 防护，构建完整的授权 URL。

    Returns:
        包含 authorization_url 和 state 的响应

    Raises:
        HTTPException: SSO 未启用时抛出
    """
    oauth_client = get_oauth2_client()
    if not oauth_client:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="SSO 未启用",
        )

    # 生成随机 state 用于 CSRF 防护
    state = secrets.token_urlsafe(32)

    authorization_url = oauth_client.build_authorization_url(state=state)

    return {
        "authorization_url": authorization_url,
        "state": state,
    }


@sso.post("/callback", response_model=TokenResponse)
async def sso_callback(
    callback_data: SSOCallbackRequest,
    db: AsyncSession = Depends(get_db),
):
    """处理 SSO 回调

    使用授权码换取访问令牌，获取用户信息，创建或获取本地用户，
    然后生成本地 JWT Token 返回。

    Args:
        callback_data: 包含授权码和 state 的请求数据
        db: 数据库会话

    Returns:
        包含本地 JWT Token 和用户信息的响应

    Raises:
        HTTPException: 回调处理失败时抛出
    """
    oauth_client = get_oauth2_client()
    if not oauth_client:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="SSO 未启用",
        )

    # 1. 用授权码换取访问令牌
    try:
        token_data = await oauth_client.exchange_code_for_token(callback_data.code)
        access_token = token_data.get("access_token")
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"授权码换取 Token 失败: {str(e)}",
        )

    # 2. 获取用户信息
    try:
        user_info = await oauth_client.get_user_info(access_token)
        logger.info(f"SSO 用户信息: {user_info}")
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"获取用户信息失败: {str(e)}",
        )

    # 处理嵌套的 data 字段（部分认证中心返回格式为 {code, msg, data: {...}}）
    if isinstance(user_info, dict) and "data" in user_info:
        user_info = user_info["data"]

    # 3. 根据字段映射提取用户数据
    field_mapping = oauth_client.get_field_mapping()
    mapped_data = {
        "username": user_info.get(field_mapping["username"]),
        "user_id_sso": user_info.get(field_mapping["user_id_sso"]),
        "phone_number": user_info.get(field_mapping["phone_number"]),
        "avatar": user_info.get(field_mapping["avatar"]),
        "email": user_info.get(field_mapping["email"]),
    }

    # 4. 验证必要字段
    if not mapped_data["username"] or not mapped_data["user_id_sso"]:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="用户信息不完整，缺少用户名或用户 ID",
        )

    # 5. 查找或创建本地用户
    user, is_new_user = await _ensure_local_user(mapped_data, db)

    # 6. 生成本地 JWT Token
    token_data = {"sub": str(user.id)}
    local_jwt_token = AuthUtils.create_access_token(token_data)

    # 7. 获取部门名称
    department_name = None
    if user.department_id:
        result = await db.execute(select(Department.name).filter(Department.id == user.department_id))
        department_name = result.scalar_one_or_none()

    return {
        "access_token": local_jwt_token,
        "token_type": "bearer",
        "user_id": user.id,
        "username": user.username,
        "user_id_login": user.user_id,
        "phone_number": user.phone_number,
        "avatar": user.avatar,
        "role": user.role,
        "department_id": user.department_id,
        "department_name": department_name,
    }


# ============================================================================
# 辅助函数
# ============================================================================


async def _ensure_local_user(
    mapped_data: dict[str, Any], db: AsyncSession
) -> tuple[User, bool]:
    """确保本地用户存在，不存在则创建

    根据 user_id_sso 查找用户，不存在则创建新用户。

    Args:
        mapped_data: 映射后的用户数据
        db: 数据库会话

    Returns:
        (User 对象, 是否为新用户)

    Raises:
        HTTPException: 用户创建失败时抛出
    """
    user_id_sso = mapped_data["user_id_sso"]
    phone_number = mapped_data["phone_number"]
    avatar = mapped_data["avatar"]

    # 尝试通过 user_id_sso 查找
    result = await db.execute(
        select(User).filter(User.user_id_sso == user_id_sso, User.is_deleted == 0)
    )
    user = result.scalar_one_or_none()

    if user is None:
        # 新用户，创建账户
        return await _create_new_user(mapped_data, db)
    else:
        # 已存在用户，更新信息
        await _update_user_info(user, phone_number, avatar, db)
        await db.refresh(user)
        return user, False


async def _create_new_user(
    mapped_data: dict[str, Any], db: AsyncSession
) -> tuple[User, bool]:
    """创建新本地用户

    Args:
        mapped_data: 映射后的用户数据
        db: 数据库会话

    Returns:
        (新创建的 User 对象, True)

    Raises:
        HTTPException: 用户创建失败时抛出
    """
    username = mapped_data["username"]
    user_id_sso = mapped_data["user_id_sso"]
    phone_number = mapped_data["phone_number"]
    avatar = mapped_data["avatar"]

    # 验证用户名格式
    is_valid, error_msg = validate_username(username)
    if not is_valid:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"用户名格式错误: {error_msg}",
        )

    # 生成本地唯一 user_id
    existing_user_ids_result = await db.execute(select(User.user_id))
    existing_user_ids = [user_id for (user_id,) in existing_user_ids_result.all()]
    user_id = generate_unique_user_id(username, existing_user_ids)

    # 获取默认部门
    dept_result = await db.execute(select(Department).filter(Department.name == "默认部门"))
    default_dept = dept_result.scalar_one_or_none()

    # 检查用户名冲突
    name_check = await db.execute(select(User).filter(User.username == username))
    if name_check.scalar_one_or_none():
        # 用户名已存在，添加序号
        counter = 1
        while True:
            new_name = f"{username}_{counter}"
            name_check = await db.execute(select(User).filter(User.username == new_name))
            if not name_check.scalar_one_or_none():
                username = new_name
                break
            counter += 1

    # 创建新用户
    user = User(
        username=username,
        user_id=user_id,
        user_id_sso=user_id_sso,
        phone_number=phone_number,
        password_hash="SSO",  # 标记为 SSO 用户
        avatar=avatar,
        role="user",
        department_id=default_dept.id if default_dept else None,
        login_source="sso",
        last_login=utc_now_naive(),
    )

    db.add(user)
    await db.commit()
    await db.refresh(user)

    return user, True


async def _update_user_info(
    user: User, phone_number: str | None, avatar: str | None, db: AsyncSession
) -> None:
    """更新用户信息

    更新头像和手机号（如果更权威的话）。

    Args:
        user: 用户对象
        phone_number: 新手机号
        avatar: 新头像 URL
        db: 数据库会话
    """
    # 更新头像
    if avatar:
        user.avatar = avatar

    # 更新手机号（仅当用户没有手机号时）
    if phone_number and not user.phone_number:
        # 检查手机号是否已被其他用户使用
        phone_check = await db.execute(
            select(User).filter(User.phone_number == phone_number, User.id != user.id)
        )
        if not phone_check.scalar_one_or_none():
            user.phone_number = phone_number

    # 更新登录来源
    if user.login_source != "both":
        user.login_source = "both"

    # 更新最后登录时间
    user.last_login = utc_now_naive()

    await db.commit()
