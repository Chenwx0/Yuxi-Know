import re

from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError
from sqlalchemy.ext.asyncio import AsyncSession

from src.storage.postgres.manager import pg_manager
from src.storage.postgres.models_business import User
from server.utils.auth_utils import AuthUtils

# 定义OAuth2密码承载器，指定token URL
oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/token", auto_error=False)

# 公开路径列表，无需登录即可访问
PUBLIC_PATHS = [
    r"^/api/auth/token$",  # 登录
    r"^/api/auth/check-first-run$",  # 检查是否首次运行
    r"^/api/auth/initialize$",  # 初始化系统
    r"^/api/auth/sso/login$",  # SSO 登录获取授权 URL
    r"^/api/auth/sso/callback$",  # SSO 回调处理
    r"^/api/auth/sso/enabled$",  # 检查 SSO 是否启用
    r"^/api$",  # Health Check
    r"^/api/system/health$",  # Health Check
    r"^/api/system/info$",  # 获取系统信息配置
]


# 获取数据库会话（异步版本）
async def get_db():
    async with pg_manager.get_async_session_context() as db:
        yield db


# 获取当前用户（异步版本）
async def get_current_user(token: str | None = Depends(oauth2_scheme), db: AsyncSession = Depends(get_db)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="无效的凭证",
        headers={"WWW-Authenticate": "Bearer"},
    )

    # 允许无token访问公开路径
    if token is None:
        return None

    # 解析 Token 类型和内容
    token_type, actual_token = AuthUtils.parse_authorization_header(token)

    try:
        if AuthUtils.is_local_jwt_auth(token):
            # 本地 JWT 验证模式
            payload = AuthUtils.verify_access_token(actual_token)
            user_id = payload.get("sub")
            if user_id is None:
                raise credentials_exception
        else:
            # OAuth2 Token 验证模式（Bearer 前缀）
            from server.utils.oauth2_client import get_oauth2_client

            oauth_client = get_oauth2_client()
            if not oauth_client:
                raise ValueError("SSO 未启用")

            # 验证 Token 有效性
            token_info = await oauth_client.introspect_token(actual_token)
            if not token_info.get("active"):
                raise ValueError("Token 已失效")

            # 从 Token 中提取用户标识
            user_id = token_info.get("sub") or token_info.get("user_id")
            if user_id is None:
                raise ValueError("Token 中缺少用户标识")

            # 如果 user_id 不是整数（Token 中的 sub 通常是字符串），需要额外处理
            # 这里假设 Token 中的 user_id 与本地 User.id 一致
            # 实际 OAuth2 场景中，通常需要额外查找用户

            # 修正：OAuth2 Token 验证后，需要根据 SSO user_id 查找本地用户
            # 但当前模式下 SSO 登录后直接返回本地 JWT，所以 Bearer 模式实际很少使用
            # 这里提供完整实现以支持直接使用 Bearer Token 的场景

            # 获取 SSO user_id
            sso_user_id = token_info.get("sub") or token_info.get("user_id")
            if not sso_user_id:
                raise ValueError("Token 中缺少用户标识")

            # 查找关联的本地用户
            from sqlalchemy import select

            result = await db.execute(select(User).filter(User.user_id_sso == sso_user_id))
            user = result.scalar_one_or_none()
            if user is None:
                raise credentials_exception

            return user

    except JWTError:
        raise credentials_exception
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(e),
            headers={"WWW-Authenticate": "Bearer"},
        )

    # 查找用户（异步版本）
    from sqlalchemy import select

    result = await db.execute(select(User).filter(User.id == int(user_id)))
    user = result.scalar_one_or_none()
    if user is None:
        raise credentials_exception

    return user


# 获取已登录用户（抛出401如果未登录）
async def get_required_user(user: User | None = Depends(get_current_user)):
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="请登录后再访问",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


# 获取管理员用户
async def get_admin_user(current_user: User = Depends(get_required_user)):
    if current_user.role not in ["admin", "superadmin"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="需要管理员权限",
        )
    return current_user


# 获取超级管理员用户
async def get_superadmin_user(current_user: User = Depends(get_required_user)):
    if current_user.role != "superadmin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="需要超级管理员权限",
        )
    return current_user


# 检查路径是否为公开路径
def is_public_path(path: str) -> bool:
    path = path.rstrip("/")  # 去除尾部斜杠以便于匹配
    for pattern in PUBLIC_PATHS:
        if re.match(pattern, path):
            return True
    return False
