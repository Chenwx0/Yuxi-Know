[根目录](../CLAUDE.md) > **test**

# test (测试模块)

## 变更记录 (Changelog)

### 2026-02-05
- 模块文档初始化
- 记录测试组织和运行方式

---

## 相对路径面包屑

[根目录](../CLAUDE.md) > **test**

---

## 模块职责

提供完整的测试套件，包括：
- API 路由测试
- 集成测试
- 单元测试
- 并发测试
- 工具脚本

---

## 技术栈

- **测试框架**: pytest
- **异步测试**: pytest-asyncio
- **HTTP Mock**: pytest-httpx
- **覆盖率**: pytest-cov
- **Python 版本**: 3.12+

---

## 目录结构

```
test/
├── api/                    # API 路由测试
│   ├── conftest.py        # API 测试 fixture
│   ├── test_auth_router.py
│   ├── test_chat_router.py
│   ├── test_dashboard_router.py
│   ├── test_department_router.py
│   ├── test_evaluation_router.py
│   ├── test_graph_router_list.py
│   ├── test_knowledge_router.py
│   ├── test_mindmap_router.py
│   ├── test_system_router.py
│   ├── test_task_router.py
│   └── test_unified_graph_router.py
├── conftest.py             # 全局 fixture
├── test_concurrency.py     # 并发测试
├── test_graph_unit.py      # 图谱单元测试
├── test_manual_eval.py     # 手动评估测试
├── test_mysql_connection.py # MySQL 连接测试
├── test_mysql_import.py    # MySQL 导入测试
├── test_neo4j.py           # Neo4j 测试
└── bruteforce_simulation.py # 暴力破解模拟测试
```

---

## 配置

### pytest 配置 (pyproject.toml)

```python
[tool.pytest.ini_options]
addopts = "-v --tb=short"
testpaths = ["test"]
markers = [
    "auth: marks tests that require authentication",
    "slow: marks tests as slow",
    "integration: marks tests as integration tests"
]
asyncio_mode = "auto"
asyncio_default_fixture_loop_scope = "function"
```

### 测试标记

- `@pytest.mark.auth`: 需要认证的测试
- `@pytest.mark.slow`: 慢速测试
- `@pytest.mark.integration`: 集成测试

---

## 全局 Fixture

### conftest.py

定义全局测试 fixture：
- 数据库连接
- 应用客户端（FastAPI TestClient）
- 测试用户
- 测试数据

### api/conftest.py

API 专用 fixture：
- 认证令牌
- 智能体配置
- 知识库数据

---

## 测试分类

### 1. API 路由测试 (test/api/)

每个路由对应一个测试文件：

| 文件 | 测试内容 |
|------|---------|
| `test_auth_router.py` | 用户认证、令牌管理 |
| `test_chat_router.py` | 智能体对话、流式响应 |
| `test_dashboard_router.py` | 仪表盘数据 |
| `test_knowledge_router.py` | 知识库 CRUD |
| `test_graph_router.py` | 图谱接口 |
| `test_system_router.py` | 系统健康、配置 |
| `test_task_router.py` | 异步任务管理 |
| `test_evaluation_router.py` | 评估基准和结果 |

### 2. 集成测试

- `test_graph_unit.py`: 图谱功能单元测试
- `test_neo4j.py`: Neo4j 连接和操作测试
- `test_mysql_connection.py`: MySQL 连接测试
- `test_mysql_import.py`: MySQL 数据导入测试

### 3. 特殊测试

- `test_concurrency.py`: 并发场景测试
- `test_manual_eval.py`: 手动评估流程测试
- `bruteforce_simulation.py`: 安全测试（暴力破解模拟）

---

## 运行测试

### 运行所有测试

```bash
make router-tests
# 或
docker compose exec api uv run pytest test/
```

### 运行特定测试文件

```bash
docker compose exec api uv run pytest test/api/test_auth_router.py
```

### 运行特定测试函数

```bash
docker compose exec api uv run pytest test/api/test_auth_router.py::test_login
```

### 运行带标记的测试

```bash
# 只运行认证相关的测试
docker compose exec api uv run pytest -m auth

# 跳过慢速测试
docker compose exec api uv run pytest -m "not slow"
```

### 查看覆盖率

```bash
docker compose exec api uv run pytest --cov=src --cov-report=html test/
```

覆盖率报告生成在 `htmlcov/` 目录。

---

## 测试示例

### 典型 API 测试

```python
import pytest
from httpx import AsyncClient

@pytest.mark.asyncio
async def test_create_knowledge_database(async_client: AsyncClient):
    response = await async_client.post(
        "/api/knowledge/databases",
        json={"name": "测试知识库", "type": "milvus"}
    )
    assert response.status_code == 200
    data = response.json()
    assert data["name"] == "测试知识库"
```

---

## 最佳实践

### 1. 测试命名

- 使用描述性的函数名
- 格式: `test_<功能>_<场景>`

### 2. 测试隔离

- 每个测试应该独立运行
- 使用 fixture 初始化和清理

### 3. 异步测试

- 所有 API 测试都应该是异步的
- 使用 `@pytest.mark.asyncio` 标记

### 4. Mock 的使用

- 对于外部服务使用 mock
- 避免测试依赖于外部服务

---

## 工具脚本

### test/broken_test.py

用于调试的单测试脚本。

### test/bruteforce_simulation.py

安全测试工具，模拟暴力破解攻击以测试限流中间件。

---

## 常见问题

### Q: 测试失败，提示数据库连接错误？

确保：
- Docker 服务正在运行
- 数据库已初始化
- 环境变量配置正确

### Q: 如何调试测试？

1. 添加 `-s` 参数查看输出：`pytest -s`
2. 使用 `pdb` 或 `ipdb` 调试：`pytest --pdb`
3. 查看详细错误信息：`pytest -vv`

### Q: 测试运行太慢？

1. 使用标记跳过慢速测试：`-m "not slow"`
2. 使用并行测试：`pytest-xdist`
3. 只运行特定测试文件

---

## 相关文档

- [根目录 CLAUDE.md](../CLAUDE.md)
- [pytest 文档](https://docs.pytest.org/)
- [FastAPI 测试文档](https://fastapi.tiangolo.com/tutorial/testing/)
