[根目录](../CLAUDE.md) > **web**

# web (前端模块)

## 变更记录 (Changelog)

### 2026-02-05
- 模块文档初始化
- 记录前端架构、路由、API 接口等关键信息

---

## 相对路径面包屑

[根目录](../CLAUDE.md) > **web**

---

## 模块职责

提供完整的前端用户界面，包括：
- 智能体对话界面
- 知识库管理界面
- 知识图谱可视化
- 系统管理界面
- 仪表盘与数据分析

---

## 技术栈

- **框架**: Vue 3.5.21
- **构建工具**: Vite 7.1.5
- **UI 组件库**: Ant Design Vue 4.2.6
- **状态管理**: Pinia 3.0.3
- **路由**: Vue Router 4.5.1
- **图标**: @ant-design/icons-vue, lucide-vue-next
- **HTTP 客户端**: 原生 Fetch API
- **包管理器**: pnpm 10.11.0

---

## 入口与启动

### 入口文件

- **主入口**: `web/src/main.js`
- **路由定义**: `web/src/router/index.js`
- **根组件**: `web/src/App.vue`

### 启动命令

```bash
# 开发模式（在容器内）
cd web
pnpm run server      # 启动开发服务器

# 生产构建
pnpm run build
```

### 代理配置

所有 `/api` 请求通过 Vite 代理转发到后端：

```javascript
// vite.config.js
proxy: {
  '^/api': {
    target: env.VITE_API_URL || 'http://api:5050',
    changeOrigin: true
  }
}
```

---

## 路由结构

| 路径 | 组件 | 说明 | 权限 |
|------|------|------|------|
| `/` | HomeView | 首页 | 公开 |
| `/login` | LoginView | 登录页 | 公开 |
| `/agent` | AgentView | 智能体列表页 | 管理员 |
| `/agent/:agent_id` | AgentSingleView | 智能体单页对话 | 登录用户 |
| `/graph` | GraphView | 知识图谱 | 管理员 |
| `/database` | DataBaseView | 知识库列表 | 管理员 |
| `/database/:database_id` | DataBaseInfoView | 知识库详情 | 管理员 |
| `/dashboard` | DashboardView | 仪表盘 | 管理员 |

### 路由守卫

- 全局前置守卫检查 `requiresAuth` 和 `requiresAdmin`
- 自动获取用户信息
- 普通用户访问管理员页面时自动重定向到默认智能体页面

---

## API 接口

所有 API 定义在 `web/src/apis/` 下：

| 文件 | 职责 |
|------|------|
| `base.js` | 基础 HTTP 客户端配置 |
| `agent_api.js` | 智能体相关 API |
| `dashboard_api.js` | 仪表盘数据 API |
| `department_api.js` | 部门管理 API |
| `graph_api.js` | 知识图谱 API |
| `knowledge_api.js` | 知识库 API |
| `mcp_api.js` | MCP 服务器 API |
| `mindmap_api.js` | 思维导图 API |
| `system_api.js` | 系统配置 API |
| `tasker.js` | 任务管理工具 |

---

## 状态管理 (Pinia Stores)

| 文件 | 用途 |
|------|------|
| `stores/user.js` | 用户信息、登录状态 |
| `stores/agent.js` | 智能体配置、列表 |
| `stores/config.js` | 系统配置 |
| `stores/database.js` | 知识库状态 |
| `stores/graphStore.js` | 图谱数据 |
| `stores/theme.js` | 主题（暗黑模式） |
| `stores/chatUI.js` | 聊天界面 UI 状态 |
| `stores/tasker.js` | 任务状态 |
| `stores/info.js` | 平台信息（版本、功能开关） |

所有 stores 使用 `pinia-plugin-persistedstate` 持久化到 localStorage。

---

## 目录结构

```
web/
├── public/              # 静态资源
├── src/
│   ├── apis/           # API 接口定义
│   ├── assets/         # 静态资源（CSS、图片）
│   ├── components/     # Vue 组件
│   ├── composables/    # 组合式函数
│   ├── layouts/        # 布局组件
│   ├── router/         # 路由配置
│   ├── stores/         # Pinia stores
│   ├── utils/          # 工具函数
│   ├── views/          # 页面视图
│   ├── App.vue         # 根组件
│   └── main.js         # 入口文件
├── index.html
├── vite.config.js
├── eslint.config.js
└── package.json
```

---

## 关键组件

### 页面组件 (views/)
- **AgentView**: 智能体列表和配置
- **AgentSingleView**: 智能体单页对话界面
- **GraphView**: 知识图谱可视化（G6 + Sigma）
- **DataBaseView**: 知识库列表和管理
- **DataBaseInfoView**: 知识库详情、文件管理
- **DashboardView**: 系统仪表盘和统计

### 通用组件 (components/)
- **AgentChatComponent**: 智能体聊天界面
- **KnowledgeBaseCard**: 知识库卡片
- **GraphCanvas**: 图谱画布
- **FileTable**: 文件列表表格
- **SettingsModal**: 设置弹窗
- **TaskCenterDrawer**: 任务中心抽屉

### 工具渲染组件 (ToolCallingResult/)
- 知识库工具调用渲染
- 图谱工具调用渲染
- Web搜索工具调用渲染
- TodoList 工具调用渲染
- WriteFile 工具调用渲染
- Calculator 工具调用渲染

---

## 开发规范

### 前端开发规范

1. **API 接口**: 所有 API 接口定义在 `web/src/apis/` 下
2. **图标**: 优先使用 `lucide-vue-next`（注意尺寸），或 `@ant-design/icons-vue`
3. **样式**: 使用 Less，优先引用 `web/src/assets/css/base.css` 中的颜色变量
4. **UI 风格**: 简洁一致，无悬停位移，避免过度使用阴影和渐变色
5. **格式化**: 开发完成后运行 `npm run format`

### 组合式函数 (Composables)

| 文件 | 用途 |
|------|------|
| `useAgentStreamHandler.js` | 处理智能体流式响应 |
| `useApproval.js` | 人工审批流程 |
| `useGraph.js` | 图谱数据处理 |

---

## 数据流

### 用户交互流程

1. 用户登录 → `user store` 保存 token 和用户信息
2. 访问页面 → 路由守卫检查权限
3. 调用 API → `apis/` 下的函数发起请求
4. 更新状态 → 对应 store 更新数据
5. 视图更新 → 组件响应式更新

### 智能体对话流程

1. 用户输入 → `AgentInputArea`
2. 发送 API → `agent_api.js`
3. 流式响应 → `useAgentStreamHandler`
4. 渲染消息 → `AgentChatComponent` / `AgentMessageComponent`

---

## 常用工具函数

- `errorHandler.js`: 统一错误处理
- `chatExporter.js`: 聊天记录导出
- `agentValidator.js`: 智能体配置验证
- `chunkUtils.js`: 文本分块工具

---

## 样式系统

### 颜色变量

定义在 `web/src/assets/css/base.css` 中，包括：
- 主色调
- 背景色
- 文字颜色
- 边框颜色

### 暗黑模式

通过 `theme store` 控制，使用 Ant Design Vue 的暗黑模式主题。

---

## 测试

当前前端模块暂无自动化测试。

---

## 相关文档

- [根目录 CLAUDE.md](../CLAUDE.md)
