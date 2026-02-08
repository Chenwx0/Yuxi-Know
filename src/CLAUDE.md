[根目录](../CLAUDE.md) > **src**

# src (核心模块)

## 变更记录 (Changelog)

### 2026-02-05
- 模块文档初始化
- 记录核心业务逻辑架构和关键组件

---

## 相对路径面包屑

[根目录](../CLAUDE.md) > **src**

---

## 模块职责

实现所有核心业务逻辑，包括：
- 智能体实现（基于 LangGraph v1）
- 知识库管理（RAG + 知识图谱）
- 数据存储和访问
- 业务服务层
- 数据模型定义
- 文档解析插件

---

## 技术栈

- **AI 框架**: LangChain, LangGraph v1, LightRAG
- **数据库**: SQLAlchemy (PostgreSQL), Neo4j, Milvus
- **文件存储**: MinIO
- **版本兼容**: Python 3.12+

---

## 目录结构

```
src/
├── agents/              # 智能体实现
│   ├── chatbot/        # 聊天机器人
│   ├── deep_agent/     # 深度分析智能体
│   ├── reporter/       # 报告生成智能体
│   ├── common/         # 通用智能体基类和工具
│   │   ├── base.py
│   │   ├── state.py
│   │   ├── context.py
│   │   ├── middlewares/
│   │   ├── subagents/
│   │   ├── tools.py
│   │   └── toolkits/
│   └── models.py
├── knowledge/           # 知识库管理
│   ├── adapters/       # 知识库适配器接口
│   ├── implementations/# 具体实现（Milvus, LightRAG）
│   ├── base.py         # 基类定义
│   ├── factory.py      # 工厂模式
│   ├── manager.py      # 知识库管理器
│   ├── indexing.py     # 索引构建
│   ├── services/       # 知识库服务
│   └── utils/
├── storage/             # 存储层
│   ├── db/             # SQLAlchemy ORM
│   ├── postgres/       # PostgreSQL 管理
│   └── minio/          # MinIO 对象存储
├── services/            # 服务层
│   ├── chat_stream_service.py
│   ├── conversation_service.py
│   ├── evaluation_service.py
│   ├── feedback_service.py
│   ├── history_query_service.py
│   ├── mcp_service.py
│   ├── task_service.py
│   └── doc_converter.py
├── repositories/        # 数据访问层
│   ├── agent_config_repository.py
│   ├── conversation_repository.py
│   ├── knowledge_base_repository.py
│   ├── knowledge_file_repository.py
│   ├── user_repository.py
│   ├── department_repository.py
│   ├── mcp_server_repository.py
│   ├── task_repository.py
│   ├── evaluation_repository.py
│   ├── message_feedback_repository.py
│   └── operation_log_repository.py
├── models/              # 数据模型
│   ├── chat.py
│   ├── rerank.py
│   └── embed.py
├── plugins/             # 文档解析插件
│   ├── document_processor_base.py
│   ├── document_processor_factory.py
│   ├── deepseek_ocr_parser.py
│   ├── mineru_parser.py
│   ├── mineru_official_parser.py
│   ├── paddlex_parser.py
│   ├── rapid_ocr_processor.py
│   └── guard.py
├── config/              # 配置管理
│   ├── app.py
│   └── static/models.py
├── utils/               # 工具函数
│   ├── datetime_utils.py
│   ├── logging_config.py
│   ├── prompts.py
│   ├── web_search.py
│   ├── image_processor.py
│   └── evaluation_metrics.py
└── __init__.py
```

---

## 核心子模块

### 1. agents (智能体)

基于 LangGraph v1 的智能体实现框架：

#### common/ (通用组件)
- **base.py**: 智能体基类
- **state.py**: 状态定义
- **context.py**: 上下文管理
- **middlewares/**: 中间件机制（附件、上下文、动态工具、运行时配置）
- **subagents/**: 子智能体（计算器等）
- **tools.py**: 工具定义
- **toolkits/**: 工具包（MySQL 数据库工具等）

#### chatbot/ (聊天机器人)
- 标准聊天智能体实现

#### deep_agent/ (深度分析智能体)
- 支持深度推理、任务追踪
- 多步骤问题解决

#### reporter/ (报告生成智能体)
- 自动生成报告

### 2. knowledge (知识库)

支持多种知识库实现：

#### 适配器模式
- **base.py**: 知识库基类定义
- **factory.py**: 知识库工厂
- **manager.py**: 知识库生命周期管理

#### 实现
- **Milvus**: 向量数据库实现 (`implementations/milvus.py`)
- **LightRAG**: RAG + 知识图谱实现 (`implementations/lightrag.py`)

#### 服务
- **upload_graph_service.py**: 图谱上传服务

#### 工具
- **kb_utils.py**: 知识库工具
- **url_fetcher.py**: URL 获取器
- **url_validator.py**: URL 验证器

### 3. storage (存储层)

管理所有数据存储：

#### PostgreSQL
- **manager.py**: PostgreSQL 连接管理器
- **models_business.py**: 业务数据模型
- **models_knowledge.py**: 知识库相关模型

#### MinIO
- **client.py**: MinIO 客户端
- **utils.py**: MinIO 工具函数

### 4. services (服务层)

业务逻辑服务：

#### 聊天相关
- **chat_stream_service.py**: 流式聊天服务
- **conversation_service.py**: 对话服务
- **history_query_service.py**: 历史查询服务

#### 评估与反馈
- **evaluation_service.py**: 评估服务
- **feedback_service.py**: 反馈服务

#### 其他
- **mcp_service.py**: MCP 服务器管理
- **task_service.py**: 异步任务管理
- **doc_converter.py**: 文档转换

### 5. repositories (数据访问层)

封装数据库访问操作，每个实体对应一个 repository：

- **agent_config_repository.py**: 智能体配置
- **conversation_repository.py**: 对话
- **knowledge_base_repository.py**: 知识库
- **knowledge_file_repository.py**: 知识库文件
- **user_repository.py**: 用户
- **department_repository.py**: 部门
- **task_repository.py**: 任务
- **evaluation_repository.py**: 评估
- **mcp_server_repository.py**: MCP 服务器

### 6. plugins (文档解析插件)

支持多种文档格式解析：

- **document_processor_base.py**: 解析器基类
- **document_processor_factory.py**: 解析器工厂
- **rapid_ocr_processor.py**: RapidOCR 解析
- **mineru_parser.py**: MinerU 解析
- **mineru_official_parser.py**: MinerU 官方解析
- **paddlex_parser.py**: PaddleX OCR 解析
- **deepseek_ocr_parser.py**: DeepSeek OCR 解析
- **guard.py**: 内容守卫

### 7. models (数据模型)

- **chat.py**: 聊天相关模型
- **rerank.py**: 重排序模型
- **embed.py**: Embedding 模型

### 8. config (配置)

- **app.py**: 应用配置
- **static/models.py**: 静态模型配置

### 9. utils (工具函数)

- **datetime_utils.py**: 日期时间工具
- **logging_config.py**: 日志配置
- **prompts.py**: Prompt 模板
- **web_search.py**: 网络搜索
- **image_processor.py**: 图像处理
- **evaluation_metrics.py**: 评估指标

---

## 数据模型

### PostgreSQL 模型 (storage/postgres/)

#### 业务数据 (models_business.py)
- **User**: 用户
- **Department**: 部门
- **Conversation**: 对话
- **Message**: 消息
- **MessageFeedback**: 消息反馈
- **ConversationStats**: 对话统计
- **ToolCall**: 工具调用记录
- **AgentConfig**: 智能体配置
- **MCPServer**: MCP 服务器
- **OperationLog**: 操作日志
- **EvaluationRecord**: 评估记录

#### 知识库数据 (models_knowledge.py)
- **KnowledgeDatabase**: 知识库
- **KnowledgeFile**: 知识库文件
- **KnowledgeChunk**: 文档分块

---

## 关键流程

### 智能体对话流程

```
1. 接收用户输入
   ↓
2. 通过 chat_stream_service 处理
   ↓
3. 加载智能体配置 (agent_config_repository)
   ↓
4. 构建智能体实例 (agents/)
   ↓
5. 加载知识库工具 (knowledge/)
   ↓
6. 执行 LangGraph 流程
   ↓
7. 流式返回结果
```

### 知识库创建流程

```
1. 创建知识库记录 (knowledge_base_repository)
   ↓
2. 上传文件 (storage/minio/)
   ↓
3. 解析文档 (plugins/)
   ↓
4. 分块 (indexing/)
   ↓
5. Embedding (models/embed.py)
   ↓
6. 索引入库 (implementations/milvus.py 或 lightrag.py)
```

---

## 配置管理

### 应用配置 (config/app.py)

- 数据库连接配置
- AI 模型配置
- 存储配置
- 其他系统配置

### 静态配置 (config/static/models.py)

- 模型列表
- 默认参数

---

## 依赖关系

```
server (FastAPI)
    ↓
services (业务服务层)
    ↓
repositories (数据访问层) + knowledge (知识库层)
    ↓
storage (存储层)
```

---

## 测试

测试文件位于 `test/` 目录：
- `test/api/`: API 测试
- `test/graph_unit.py`: 图谱单元测试
- `test_manual_eval.py`: 手动评估
- `test_neo4j.py`: Neo4j 测试
- 等

运行测试：

```bash
docker compose exec api uv run pytest test/
```

---

## 常见问题

### Q: 如何添加新的智能体？

1. 在 `src/agents/` 下创建新目录
2. 继承 `agents/common/base.py` 中的基类
3. 实现 LangGraph 流程
4. 在 `repositories/agent_config_repository.py` 中注册

### Q: 如何添加新的知识库类型？

1. 在 `src/knowledge/implementations/` 下创建新文件
2. 继承 `knowledge/base.py` 中的基类
3. 实现必要的抽象方法
4. 在 `knowledge/factory.py` 中注册

### Q: 如何添加新的文档解析器？

1. 创建新解析器类，继承 `plugins/document_processor_base.py`
2. 实现必要的解析方法
3. 在 `plugins/document_processor_factory.py` 中注册

---

## 相关文档

- [根目录 CLAUDE.md](../CLAUDE.md)
- [server 模块文档](../server/CLAUDE.md)
- [AGENTS.md](../AGENTS.md)
