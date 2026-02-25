import re

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from src.storage.postgres.manager import pg_manager
from src.storage.postgres.models_business import User, Department
from server.utils.auth_utils import AuthUtils
from src.utils import logger
from src.utils.datetime_utils import utc_now_naive
from server.utils.user_utils import generate_unique_user_id, validate_username

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="/api/auth/token", auto_error=False)

PUBLIC_PATHS = [
    r"^/api/auth/token$",
    r"^/api/auth/check-first-run$",
    r"^/api/auth/initialize$",
    r"^/api/auth/sso/login$",
    r"^/api/auth/sso/callback$",
    r"^/api/auth/sso/enabled$",
    r"^/api$",
    r"^/api/system/health$",
    r"^/api/system/info$",
]


async def get_db():
    async with pg_manager.get_async_session_context() as db:
        yield db


def get_authorization_header(request: Request) -> str | None:
    """从请求头获取 Authorization 值

    直接获取完整的 Authorization 头内容，不做前缀解析。
    """
    auth_header = request.headers.get("Authorization")
    return auth_header


async def _try_geelato_auth(auth_header: str, db: AsyncSession) -> User | None:
    from server.utils.config_utils import get_geelato_auth_config
    from server.utils.crypto_utils import AESCrypto

    config = get_geelato_auth_config()
    if not config["enabled"]:
        return None

    parts = auth_header.split(" ", 1)
    if len(parts) != 2 or parts[0] != config["prefix"]:
        return None

    encrypted_data = parts[1]

    try:
        decrypted = AESCrypto.decrypt(encrypted_data, config["secret_key"])
    except ValueError as e:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"认证数据解密失败: {str(e)}",
            headers={"WWW-Authenticate": config["prefix"]},
        )

    auth_parts = decrypted.split(":", 1)
    if len(auth_parts) != 2:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="认证数据格式错误",
            headers={"WWW-Authenticate": config["prefix"]},
        )

    auth_key = auth_parts[0]
    username = auth_parts[1]

    if auth_key not in config["keys"]:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="无效的 Geelato Auth Key",
            headers={"WWW-Authenticate": config["prefix"]},
        )

    result = await db.execute(select(User).filter(User.username == username))
    user = result.scalar_one_or_none()

    if user:
        user.last_login = utc_now_naive()
        await db.commit()
        await db.refresh(user)
        return user

    if config["require_user_exist"]:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=f"用户不存在: {username}",
            headers={"WWW-Authenticate": config["prefix"]},
        )

    user = await _create_geelato_auth_user(username, db)
    return user


async def _create_geelato_auth_user(username: str, db: AsyncSession) -> User:
    """创建 Geelato Auth 用户

    当 require_user_exist=false 且用户不存在时，自动创建用户。

    Args:
        username: 用户名
        db: 数据库会话

    Returns:
        User 对象
    """
    is_valid, error_msg = validate_username(username)
    if not is_valid:
        username = f"geelato_user_{username[:8]}"

    existing_user_ids_result = await db.execute(select(User.user_id))
    existing_user_ids = [user_id for (user_id,) in existing_user_ids_result.all()]
    user_id = generate_unique_user_id(username, existing_user_ids)

    dept_result = await db.execute(select(Department).filter(Department.name == "默认部门"))
    default_dept = dept_result.scalar_one_or_none()

    name_check = await db.execute(select(User).filter(User.username == username))
    if name_check.scalar_one_or_none():
        counter = 1
        while True:
            new_name = f"{username}_{counter}"
            name_check = await db.execute(select(User).filter(User.username == new_name))
            if not name_check.scalar_one_or_none():
                username = new_name
                break
            counter += 1

    user = User(
        username=username,
        user_id=user_id,
        phone_number=None,
        password_hash="GEELATO_AUTH",
        avatar=None,
        role="user",
        department_id=default_dept.id if default_dept else None,
        login_source="geelato_auth",
        last_login=utc_now_naive(),
    )

    db.add(user)
    await db.commit()
    await db.refresh(user)

    logger.info(f"Geelato Auth 自动创建用户: {username}")

    return user


async def _create_or_get_sso_user(
    user_info: dict, sso_user_id: str, db: AsyncSession
) -> User:
    """创建或获取 SSO 用户

    如果用户不存在，自动创建新用户。

    Args:
        user_info: SSO 返回的用户信息
        sso_user_id: SSO 用户唯一标识
        db: 数据库会话

    Returns:
        User 对象
    """
    result = await db.execute(
        select(User).filter(User.user_id_sso == sso_user_id, User.is_deleted == 0)
    )
    user = result.scalar_one_or_none()

    if user:
        user.last_login = utc_now_naive()
        if user_info.get("avatar"):
            user.avatar = user_info.get("avatar")
        if user_info.get("phone_number"):
            user.phone_number = user_info.get("phone_number")
        await db.commit()
        await db.refresh(user)
        return user

    username = user_info.get("username") or user_info.get("name") or f"sso_user_{sso_user_id[:8]}"
    phone_number = user_info.get("phone_number")
    avatar = user_info.get("avatar")

    is_valid, error_msg = validate_username(username)
    if not is_valid:
        username = f"sso_user_{sso_user_id[:8]}"

    existing_user_ids_result = await db.execute(select(User.user_id))
    existing_user_ids = [user_id for (user_id,) in existing_user_ids_result.all()]
    user_id = generate_unique_user_id(username, existing_user_ids)

    dept_result = await db.execute(select(Department).filter(Department.name == "默认部门"))
    default_dept = dept_result.scalar_one_or_none()

    name_check = await db.execute(select(User).filter(User.username == username))
    if name_check.scalar_one_or_none():
        counter = 1
        while True:
            new_name = f"{username}_{counter}"
            name_check = await db.execute(select(User).filter(User.username == new_name))
            if not name_check.scalar_one_or_none():
                username = new_name
                break
            counter += 1

    user = User(
        username=username,
        user_id=user_id,
        user_id_sso=sso_user_id,
        phone_number=phone_number,
        password_hash="SSO",
        avatar=avatar,
        role="user",
        department_id=default_dept.id if default_dept else None,
        login_source="sso",
        last_login=utc_now_naive(),
    )

    db.add(user)
    await db.commit()
    await db.refresh(user)

    logger.info(f"SSO 自动创建用户: {username} (SSO ID: {sso_user_id})")

    return user


async def get_current_user(
    request: Request,
    token: str | None = Depends(oauth2_scheme),
    db: AsyncSession = Depends(get_db),
):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="无效的凭证",
        headers={"WWW-Authenticate": "Bearer"},
    )

    auth_header = get_authorization_header(request)

    if auth_header is None and token is None:
        return None

    if auth_header:
        try:
            geelato_user = await _try_geelato_auth(auth_header, db)
            if geelato_user:
                return geelato_user
        except HTTPException:
            raise

    if token:
        try:
            payload = AuthUtils.verify_access_token(token)
            user_id = payload.get("sub")
            if user_id is None:
                raise credentials_exception

            result = await db.execute(select(User).filter(User.id == int(user_id)))
            user = result.scalar_one_or_none()
            if user is None:
                raise credentials_exception

            return user
        except ValueError:
            pass
        except JWTError:
            pass

        from server.utils.oauth2_client import get_oauth2_client

        oauth_client = get_oauth2_client()
        if not oauth_client:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="SSO 未启用，且 Token 不是有效的本地 JWT",
                headers={"WWW-Authenticate": "Bearer"},
            )

        sso_user_id = None
        user_info = None
        try:
            try:
                if oauth_client.introspect_url:
                    token_info = await oauth_client.introspect_token(token)
                    if token_info.get("active"):
                        sso_user_id = token_info.get("sub") or token_info.get("user_id")
                        logger.debug(f"Introspect 验证成功，用户标识: {sso_user_id}")
            except Exception as e:
                logger.debug(f"Introspect 验证失败，尝试使用 UserInfo 验证: {e}")

            if not sso_user_id:
                try:
                    user_info = await oauth_client.get_user_info(token)
                    logger.debug(f"UserInfo 返回: {user_info}")
                    if isinstance(user_info, dict) and "data" in user_info:
                        user_info = user_info["data"]
                    field_mapping = oauth_client.get_field_mapping()
                    sso_user_id = user_info.get(field_mapping["user_id_sso"])
                    if not sso_user_id:
                        raise ValueError("无法从用户信息中提取用户标识")
                    logger.debug(f"UserInfo 验证成功，用户标识: {sso_user_id}")
                except Exception as e:
                    logger.debug(f"UserInfo 验证也失败: {e}")
                    raise ValueError("Token 验证失败")

            if not sso_user_id:
                raise ValueError("Token 中缺少用户标识")

            field_mapping = oauth_client.get_field_mapping()
            mapped_user_info = {
                "username": user_info.get(field_mapping["username"]) if user_info else None,
                "phone_number": user_info.get(field_mapping["phone_number"]) if user_info else None,
                "avatar": user_info.get(field_mapping["avatar"]) if user_info else None,
            }

            user = await _create_or_get_sso_user(mapped_user_info, sso_user_id, db)

            return user
        except ValueError as e:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=str(e),
                headers={"WWW-Authenticate": "Bearer"},
            )
        except Exception as e:
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail=f"Token 验证失败: {str(e)}",
                headers={"WWW-Authenticate": "Bearer"},
            )

    return None


async def get_required_user(user: User | None = Depends(get_current_user)):
    if user is None:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="请登录后再访问",
            headers={"WWW-Authenticate": "Bearer"},
        )
    return user


def get_admin_user(current_user: User = Depends(get_required_user)):
    if current_user.role not in ["admin", "superadmin"]:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="需要管理员权限",
        )
    return current_user


def get_superadmin_user(current_user: User = Depends(get_required_user)):
    if current_user.role != "superadmin":
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="需要超级管理员权限",
        )
    return current_user


def is_public_path(path: str) -> bool:
    path = path.rstrip("/")
    for pattern in PUBLIC_PATHS:
        if re.match(pattern, path):
            return True
    return False
