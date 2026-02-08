[根目录](../CLAUDE.md) > **server**

# server (后端模块)

## 变更记录 (Changelog)

### 2026-02-05
- 模块文档初始化
- 记录 API 路由、中间件、配置等关键信息

---

## 相对路径面包屑

[根目录](../CLAUDE.md) > **server**

---

## 模块职责

提供 FastAPI RESTful API 服务，包括：
- API 路由注册和请求处理
- 中间件配置（认证、限流、日志）
- 服务生命周期管理
- 请求/响应验证

---

## 技术栈

- **框架**: FastAPI
- **ASGI 服务器**: Uvicorn
- **Python 版本**: 3.12+
- **依赖管理**: uv

---

## 入口与启动

### 主入口文件

- **应用入口**: `server/main.py`
- **启动命令**:
  ```bash
  uvicorn server.main:app --host 0.0.0.0 --port 5050 --reload
  ```

### Docker 容器配置

容器名称: `api-dev`
内部端口: 5050
暴露端口: 5050:5050

---

## API 路由结构

所有路由在 `server/routers/__init__.py` 中注册，前缀为 `/api`：

| 路由 | 文件 | 功能描述 |
|------|------|---------|
| `/api/system/*` | `system_router.py` | 系统健康检查、配置 |
| `/api/auth/*` | `auth_router.py` | 用户认证、令牌 |
| `/api/chat/*` | `chat_router.py` | 智能体对话接口 |
| `/api/dashboard/*` | `dashboard_router.py` | 仪表盘数据 |
| `/api/departments/*` | `department_router.py` | 部门管理 |
| `/api/knowledge/*` | `knowledge_router.py` | 知识库 CRUD |
| `/api/evaluation/*` | `evaluation_router.py` | 评估基准、结果 |
| `/api/mindmap/*` | `mindmap_router.py` | 思维导图生成 |
| `/api/graph/*` | `graph_router.py` | 知识图谱接口 |
| `/api/tasks/*` | `task_router.py` | 异步任务管理 |
| `/api/system/mcp-servers/*` | `mcp_router.py` | MCP 服务器管理 |

---

## 中间件

### 1. CORS 中间件

允许跨域请求，配置在 `main.py`：

```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)
```

### 2. 访问日志中间件

- **文件**: `server/utils/access_log_middleware.py`
- **功能**: 记录每个请求的处理时间

### 3. 登录限流中间件

- **文件**: `server/main.py` (LoginRateLimitMiddleware 类)
- **功能**: 防止登录接口暴力破解
- **配置**:
  - 限流窗口: 60 秒
  - 最大尝试次数: 10 次
  - 限流端点: `/api/auth/token`

### 4. 身份认证中间件

- **文件**: `server/main.py` (AuthMiddleware 类)
- **功能**: 检查公开路径，当前为简化实现允许所有路径

---

## 生命周期管理

### Lifespan 事件

- **文件**: `server/utils/lifespan.py`
- **启动流程**:
  1. 初始化 PostgreSQL 连接 (`pg_manager`)
  2. 创建业务数据表
  3. 创建知识库 Schema
  4. 初始化 MCP 服务器配置
  5. 初始化知识库管理器
  6. 启动任务调度器 (`tasker`)

- **关闭流程**:
  1. 关闭任务调度器
  2. 关闭数据库连接

---

## 目录结构

```
server/
├── routers/              # 路由定义
│   ├── __init__.py      # 路由注册
│   ├── auth_router.py   # 认证
│   ├── chat_router.py   # 聊天
│   ├── dashboard_router.py
│   ├── department_router.py
│   ├── evaluation_router.py
│   ├── graph_router.py
│   ├── knowledge_router.py
│   ├── mcp_router.py
│   ├── mindmap_router.py
│   ├── system_router.py
│   └── task_router.py
├── utils/               # 工具函数
│   ├── __init__.py
│   ├── access_log_middleware.py
│   ├── auth_middleware.py
│   ├── auth_utils.py
│   ├── common_utils.py
│   ├── lifespan.py
│   ├── migrate.py
│   ├── singleton.py
│   └── user_utils.py
└── main.py             # 应用入口
```

---

## 工具函数

### auth_utils.py

JWT 令牌生成和验证工具：
- `create_access_token()`: 生成访问令牌
- `decode_token()`: 解码令牌
- `get_current_user()`: 获取当前用户

### user_utils.py

用户相关工具：
- 用户信息获取
- 权限验证

### migrate.py

数据库迁移工具

### common_utils.py

通用工具函数：
- 日志配置
- 其他公共功能

---

## 依赖关系

`server` 模块依赖 `src` 模块的核心业务逻辑：
- `src/services`: 业务服务层
- `src.repositories`: 数据访问层
- `src.storage`: 数据库管理
- `src.knowledge`: 知识库管理
- `src.config`: 配置管理

---

## 配置

### 环境变量

关键环境变量：
- `POSTGRES_URL`: PostgreSQL 连接字符串
- `NEO4J_URI`, `NEO4J_USERNAME`, `NEO4J_PASSWORD`: Neo4j 配置
- `MILVUS_URI`, `MILVUS_DB_NAME`, `MILVUS_TOKEN`: Milvus 配置
- `MINIO_URI`, `MINIO_ACCESS_KEY`, `MINIO_SECRET_KEY`: MinIO 配置
- `YUXI_SUPER_ADMIN_NAME`, `YUXI_SUPER_ADMIN_PASSWORD`: 超级管理员账户

### 健康检查

```bash
curl http://localhost:5050/api/system/health
```

---

## 运行方式

### Docker Compose

```bash
docker compose up -d api
```

### 直接运行（开发模式）

```bash
uv run uvicorn server.main:app --host 0.0.0.0 --port 5050 --reload
```

---

## 测试

测试文件位于 `test/api/` 目录：
- `test_auth_router.py`: 认证路由测试
- `test_chat_router.py`: 聊天路由测试
- `test_dashboard_router.py`: 仪表盘测试
- `test_knowledge_router.py`: 知识库测试
- `test_graph_router.py`: 图谱测试
- 等

运行测试：

```bash
make router-tests
# 或
docker compose exec api uv run pytest test/api/
```

---

## 常见问题

### Q: 如何添加新的 API 路由？

1. 在 `server/routers/` 下创建新文件
2. 定义 `APIRouter` 并编写路由处理函数
3. 在 `server/routers/__init__.py` 中注册

### Q: 如何调试路由问题？

1. 查看容器日志: `docker logs api-dev --tail 100`
2. 使用 FastAPI 自动文档: http://localhost:5050/docs
3. 添加日志输出到处理函数

### Q: 热重载不生效？

确保：
- 使用 `--reload` 参数启动
- 修改的是容器内挂载的目录 (`src/`, `server/`)
- 检查日志是否有错误

---

## 相关文档

- [根目录 CLAUDE.md](../CLAUDE.md)
- [src 模块文档](../src/CLAUDE.md)
- [FastAPI 文档](https://fastapi.tiangolo.com/)
