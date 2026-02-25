"""检查 admin 用户是否存在"""

import sys
import asyncio

sys.path.insert(0, "/app")

from src.storage.postgres.manager import pg_manager
from src.storage.postgres.models_business import User
from sqlalchemy import select


async def check_user():
    async with pg_manager.get_async_session_context() as db:
        result = await db.execute(select(User).filter(User.username == "admin"))
        user = result.scalar_one_or_none()

        if user:
            print(f"✓ 用户存在:")
            print(f"   ID: {user.id}")
            print(f"   用户名: {user.username}")
            print(f"   角色: {user.role}")
            print(f"   登录来源: {user.login_source}")
        else:
            print("❌ 用户不存在")

        # 列出所有用户
        result = await db.execute(select(User))
        users = result.scalars().all()
        print(f"\n所有用户 ({len(users)}):")
        for u in users:
            print(f"   - {u.username} (ID: {u.id}, 角色: {u.role})")


if __name__ == "__main__":
    asyncio.run(check_user())
