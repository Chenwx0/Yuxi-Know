# Yuxi-Know AI 对话功能集成文档

本文档详细说明了 Yuxi-Know 系统的 AI 对话功能如何集成到其他系统中。

---

## 目录

- [概述](#概述)
- [认证机制](#认证机制)
- [API 端点说明](#api-端点说明)
- [流式处理详解](#流式处理详解)
- [集成示例代码](#集成示例代码)
- [错误处理](#错误处理)
- [常见问题](#常见问题)

---

## 概述

Yuxi-Know 提供了一套完整的 AI 对话 API，支持：

- 智能体对话（基于 LangGraph v1）
- 流式响应返回
- 多模态支持（图片对话）
- 对话历史管理
- 会话线程管理
- 消息反馈

### 基础信息

| 项目 | 值 |
|------|-----|
| API 地址 | `http://your-server:5050/api` |
| 认证方式 | 多种认证方式（详见认证机制） |
| 响应格式 | JSON（流式：newline-delimited JSON） |
| 编码 | UTF-8 |

---

## 认证机制

Yuxi-Know 支持多种认证方式，可根据集成场景选择合适的认证方式：

### 认证方式对比

| 认证方式 | 适用场景 | 认证头格式 | 自动创建用户 | 安全级别 |
|---------|---------|-----------|-------------|---------|
| 本地 JWT | 前端用户登录 | `Bearer <jwt_token>` | 否 | 高 |
| SSO Token | 企业统一认证 | `Bearer <sso_token>` | 是 | 高 |
| Geelato Auth | 后端服务集成 | `geelato_auth <encrypted_data>` | 可配置 | 中 |

### 方式一：本地账号登录（JWT Token）

#### 1. 用户登录

**端点**: `POST /api/auth/token`

**请求格式**: `application/x-www-form-urlencoded`

**参数**:
| 参数名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| username | string | 是 | 用户 ID 或手机号 |
| password | string | 是 | 密码 |

**请求示例**:
```bash
curl -X POST "http://your-server:5050/api/auth/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "username=user123&password=password123"
```

**响应示例**:
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "bearer",
  "user_id": 1,
  "username": "张三",
  "user_id_login": "user123",
  "phone_number": "138****5678",
  "avatar": "https://example.com/avatar.jpg",
  "role": "user",
  "department_id": 1,
  "department_name": "技术部"
}
```

#### 2. 使用 Token 访问 API

```bash
Authorization: Bearer <access_token>
```

### 方式二：SSO Token 认证

如果系统配置了 SSO 单点登录，可以直接使用认证中心颁发的 Token 调用 API：

```bash
Authorization: Bearer <sso_token>
```

#### 验证流程

1. 系统首先尝试使用 introspect 端点验证 Token
2. 如果 introspect 失败，使用 userinfo 端点验证
3. 验证通过后，根据 Token 中的用户标识查找本地用户
4. **如果用户不存在，自动创建新用户**（无需预先登录）

#### 自动创建用户

当使用 SSO Token 首次调用 API 时，系统会自动创建用户：

- 用户名：从 SSO 用户信息中提取（根据字段映射配置）
- 角色：默认为 `user`
- 登录来源：标记为 `sso`
- 部门：分配到默认部门

#### 配置要求

```env
# SSO 必需配置
SSO_ENABLED=true
SSO_AUTHORIZATION_URL=https://auth.example.com/oauth2/authorize
SSO_TOKEN_URL=https://auth.example.com/oauth2/token
SSO_USER_INFO_URL=https://auth.example.com/oauth2/userinfo
SSO_CLIENT_ID=your_client_id
SSO_CLIENT_SECRET=your_client_secret
SSO_REDIRECT_URI=http://localhost:5173/sso/callback

# SSO 字段映射配置（根据认证中心返回字段调整）
SSO_FIELD_MAPPING_USERNAME=name
SSO_FIELD_MAPPING_USERID=id
SSO_FIELD_MAPPING_PHONE=mobilePhone
SSO_FIELD_MAPPING_AVATAR=avatar
```

### 方式三：Geelato Auth 认证

适用于后端服务集成，通过预共享的加密密钥和认证 Key 进行认证。

#### 认证头格式

```
Authorization: geelato_auth <加密数据>
```

#### 加密数据生成

1. **拼接认证数据**：`<auth_key>:<username>`
2. **使用 AES-256-CBC 加密**：
   - 密钥：32 字节，Base64 编码
   - IV：16 字节，随机生成
   - 输出：Base64(IV + 密文)

#### 用户存在性配置

通过 `GEELATO_AUTH_REQUIRE_USER_EXIST` 控制用户不存在时的行为：

| 配置值 | 用户不存在时的行为 |
|--------|------------------|
| `true`（默认） | 返回 401 认证错误 |
| `false` | 自动创建用户并认证成功 |

#### JavaScript/TypeScript 示例

```typescript
import CryptoJS from 'crypto-js';

function encryptAuthData(authKey: string, username: string, secretKey: string): string {
  // 拼接认证数据
  const plaintext = `${authKey}:${username}`;
  
  // 解码密钥
  const key = CryptoJS.enc.Base64.parse(secretKey);
  
  // 生成随机 IV
  const iv = CryptoJS.lib.WordArray.random(16);
  
  // AES-CBC 加密
  const encrypted = CryptoJS.AES.encrypt(plaintext, key, {
    iv: iv,
    mode: CryptoJS.mode.CBC,
    padding: CryptoJS.pad.Pkcs7
  });
  
  // 返回 Base64(IV + 密文)
  const combined = iv.concat(encrypted.ciphertext);
  return CryptoJS.enc.Base64.stringify(combined);
}

// 使用示例
const secretKey = "your-base64-encoded-secret-key";
const authKey = "f47ac10b-58cc-4372-a567-0e02b2c3d479";
const username = "admin";

const encrypted = encryptAuthData(authKey, username, secretKey);
const authHeader = `geelato_auth ${encrypted}`;

// 发送请求
fetch("http://your-server:5050/api/chat/agent", {
  headers: { "Authorization": authHeader }
});
```

#### 配置要求

服务端需配置以下环境变量：

```env
# Geelato Auth 必需配置
GEELATO_AUTH_ENABLED=true
GEELATO_AUTH_SECRET_KEY=<Base64编码的32字节密钥>
GEELATO_AUTH_KEYS=<认证Key列表，逗号分隔>

# 可选配置
GEELATO_AUTH_PREFIX=geelato_auth
GEELATO_AUTH_REQUIRE_USER_EXIST=true
```

详细配置说明请参考 [Geelato Auth 认证文档](./geelato-auth.md)。

---

## API 端点说明

### 智能体信息

#### 1. 获取可用智能体列表

**端点**: `GET /api/chat/agent`

**认证**: 需要登录

**请求示例**:
```bash
curl -X GET "http://your-server:5050/api/chat/agent" \
  -H "Authorization: Bearer your_token_here"
```

**响应示例**:
```json
{
  "agents": [
    {
      "id": "chatbot",
      "name": "智能助手",
      "description": "通用智能对话助手",
      "examples": ["你好今天天气如何", "帮我写一封邮件"],
      "has_checkpointer": true,
      "capabilities": ["text_chat", "multimodal"]
    }
  ]
}
```

#### 2. 获取单个智能体详细信息

**端点**: `GET /api/chat/agent/{agent_id}`

**认证**: 需要登录

**响应示例**:
```json
{
  "id": "chatbot",
  "name": "智能助手",
  "description": "通用智能对话助手",
  "examples": ["你好今天天气如何"],
  "configurable_items": [
    {
      "key": "temperature",
      "label": "温度",
      "type": "number",
      "default": 0.7,
      "min": 0,
      "max": 2,
      "step": 0.1
    }
  ],
  "has_checkpointer": true,
  "capabilities": ["text_chat", "multimodal"]
}
```

### 对话接口

#### 1. 发起对话（流式响应）

**端点**: `POST /api/chat/agent/{agent_id}`

**认证**: 需要登录

**Content-Type**: `application/json`

**参数**:
| 参数名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| query | string | 是 | 用户问题/输入 |
| config | object | 否 | 配置参数 |
| meta | object | 否 | 元数据 |
| image_content | string | 否 | base64 编码的图片数据 |

**config 可选参数**:
| 参数名 | 类型 | 说明 |
|--------|------|------|
| thread_id | string | 对话线程 ID，用于保持上下文 |
| model | string | 使用的模型名称 |
| temperature | number | 温度参数 (0-2) |
| max_tokens | number | 最大生成的 token 数 |

**请求示例**:
```bash
curl -X POST "http://your-server:5050/api/chat/agent/chatbot" \
  -H "Authorization: Bearer your_token_here" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "什么是人工智能？",
    "config": {
      "thread_id": "thread_123456",
      "temperature": 0.7
    }
  }'
```

**响应格式**: 流式 JSON (每行一个 JSON 对象)

#### 事件类型详解

| status | 说明 | 字段 |
|--------|------|------|
| `init` | 初始化，开始处理 | meta, msg |
| `loading` | 流式返回中 | content, msg, metadata |
| `agent_state` | 智能体状态更新 | agent_state, meta |
| `interrupted` | 中断（敏感内容或人工审批） | message, meta, interrupt |
| `error` | 错误 | error_type, error_message, meta |
| `finished` | 完成 | meta |

**完整流式响应示例**:
```json
{"request_id":"req_abc123","status":"init","meta":{"agent_id":"chatbot","query":"什么是人工智能？"},"msg":{"role":"user","content":"什么是人工智能？","type":"human"}}

{"request_id":"req_abc123","response":"人工智能（Artificial Intelligence，简称 AI）是计算机科学的一个分支，","status":"loading","msg":{}}

{"request_id":"req_abc123","status":"finished","meta":{"request_id":"req_abc123","time_cost":2.345}}
```

#### 2. 恢复中断的对话

**端点**: `POST /api/chat/agent/{agent_id}/resume`

**认证**: 需要登录

**参数**:
| 参数名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| thread_id | string | 是 | 对话线程 ID |
| approved | boolean | 是 | 是否批准继续 |
| config | object | 否 | 配置参数 |

**请求示例**:
```bash
curl -X POST "http://your-server:5050/api/chat/agent/chatbot/resume" \
  -H "Authorization: Bearer your_token_here" \
  -H "Content-Type: application/json" \
  -d '{
    "thread_id": "thread_123456",
    "approved": true
  }'
```

#### 3. 简单问答（非流式）

**端点**: `POST /api/chat/call`

**认证**: 需要登录

**参数**:
| 参数名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| query | string | 是 | 问题 |
| meta | object | 否 | 元数据 |

**请求示例**:
```bash
curl -X POST "http://your-server:5050/api/chat/call" \
  -H "Authorization: Bearer your_token_here" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "你好"
  }'
```

**响应示例**:
```json
{
  "response": "你好！有什么我可以帮助你的吗？",
  "request_id": "uuid-1234-5678"
}
```

### 对话历史

#### 1. 获取智能体历史消息

**端点**: `GET /api/chat/agent/{agent_id}/history`

**认证**: 需要登录

**查询参数**:
| 参数名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| thread_id | string | 是 | 对话线程 ID |

**请求示例**:
```bash
curl -X GET "http://your-server:5050/api/chat/agent/chatbot/history?thread_id=thread_abc123" \
  -H "Authorization: Bearer your_token_here"
```

**响应示例**:
```json
{
  "messages": [
    {
      "id": 1,
      "role": "user",
      "content": "什么是 Python？",
      "message_type": "text",
      "created_at": "2026-02-09T10:00:00Z",
      "feedback": null
    },
    {
      "id": 2,
      "role": "assistant",
      "content": "Python 是一种高级编程语言...",
      "message_type": "text",
      "created_at": "2026-02-09T10:00:01Z",
      "feedback": {
        "rating": "like",
        "reason": null
      }
    }
  ]
}
```

### 图片处理

#### 上传图片（多模态对话）

**端点**: `POST /api/chat/image/upload`

**认证**: 需要登录

**Content-Type**: `multipart/form-data`

**参数**:
| 参数名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| file | File | 是 | 图片文件 |

**限制**:
- 最大文件大小: 10MB
- 格式: JPEG, PNG, GIF, WebP

**请求示例**:
```bash
curl -X POST "http://your-server:5050/api/chat/image/upload" \
  -H "Authorization: Bearer your_token_here" \
  -F "file=/path/to/image.jpg"
```

**响应示例**:
```json
{
  "success": true,
  "image_content": "base64_encoded_image_data",
  "thumbnail_content": "base64_encoded_thumbnail",
  "width": 1920,
  "height": 1080,
  "format": "JPEG",
  "mime_type": "image/jpeg",
  "size_bytes": 123456
}
```

### 消息反馈

#### 提交消息反馈

**端点**: `POST /api/chat/message/{message_id}/feedback`

**认证**: 需要登录

**参数**:
```json
{
  "rating": "like",  // or "dislike"
  "reason": "回答很有帮助"  // 可选
}
```

**请求示例**:
```bash
curl -X POST "http://your-server:5050/api/chat/message/1/feedback" \
  -H "Authorization: Bearer your_token_here" \
  -H "Content-Type: application/json" \
  -d '{
    "rating": "like",
    "reason": "回答很有帮助"
  }'
```

---

## 流式处理详解

### SSE (Server-Sent Events) 格式

返回的数据采用 newline-delimited JSON (NDJSON) 格式，每行是一个独立的 JSON 对象。

### 解析示例

#### JavaScript/TypeScript

```typescript
async function streamChat(agentId: string, query: string, token: string) {
  const response = await fetch(`http://your-server:5050/api/chat/agent/${agentId}`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ query })
  });

  const reader = response.body?.getReader();
  const decoder = new TextDecoder();

  if (!reader) throw new Error('Response body is null');

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    const chunk = decoder.decode(value);
    const lines = chunk.split('\n');

    for (const line of lines) {
      if (!line.trim()) continue;

      try {
        const data = JSON.parse(line);
        handleStreamEvent(data);
      } catch (e) {
        console.error('Failed to parse line:', line);
      }
    }
  }
}

function handleStreamEvent(data: any) {
  switch (data.status) {
    case 'init':
      console.log('Connection initialized');
      break;
    case 'loading':
      process.stdout.write(data.response || '');
      break;
    case 'error':
      console.error('Error:', data.error_message);
      break;
    case 'finished':
      console.log('\nChat completed');
      break;
  }
}
```

---

## 集成示例代码

### 完整的集成示例（JavaScript/TypeScript）

```typescript
import axios from 'axios';
import CryptoJS from 'crypto-js';

interface YuxiChatConfig {
  baseUrl: string;
  token?: string;
  geelatoAuth?: {
    authKey: string;
    username: string;
    secretKey: string;
  };
}

class YuxiChatClient {
  private config: YuxiChatConfig;

  constructor(config: YuxiChatConfig) {
    this.config = config;
  }

  async login(username: string, password: string): Promise<boolean> {
    const url = `${this.config.baseUrl}/api/auth/token`;
    const data = new URLSearchParams();
    data.append('username', username);
    data.append('password', password);

    try {
      const response = await axios.post(url, data.toString(), {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' }
      });

      this.config.token = response.data.access_token;
      return true;
    } catch (error) {
      console.error('Login failed:', error.response?.data || error.message);
      return false;
    }
  }

  setGeelatoAuth(authKey: string, username: string, secretKey: string): void {
    this.config.geelatoAuth = { authKey, username, secretKey };
  }

  private encryptGeelatoAuth(): string {
    if (!this.config.geelatoAuth) {
      throw new Error('Geelato Auth not configured');
    }

    const { authKey, username, secretKey } = this.config.geelatoAuth;
    
    const plaintext = `${authKey}:${username}`;
    const key = CryptoJS.enc.Base64.parse(secretKey);
    const iv = CryptoJS.lib.WordArray.random(16);
    
    const encrypted = CryptoJS.AES.encrypt(plaintext, key, {
      iv: iv,
      mode: CryptoJS.mode.CBC,
      padding: CryptoJS.pad.Pkcs7
    });
    
    const combined = iv.concat(encrypted.ciphertext);
    return CryptoJS.enc.Base64.stringify(combined);
  }

  private getHeaders(): Record<string, string> {
    const headers = {} as Record<string, string>;

    if (this.config.geelatoAuth) {
      const encrypted = this.encryptGeelatoAuth();
      headers['Authorization'] = `geelato_auth ${encrypted}`;
    } else if (this.config.token) {
      headers['Authorization'] = `Bearer ${this.config.token}`;
    }

    return headers;
  }

  async getAgents(): Promise<any[]> {
    const url = `${this.config.baseUrl}/api/chat/agent`;
    const response = await axios.get(url, { headers: this.getHeaders() });
    return response.data.agents || [];
  }

  async chatStream(agentId: string, query: string, threadId?: string, onMessage?: (content: string) => void): Promise<string> {
    const url = `${this.config.baseUrl}/api/chat/agent/${agentId}`;
    const data: any = { query };
    if (threadId) {
      data.config = { thread_id: threadId };
    }

    const response = await axios({
      method: 'POST',
      url,
      headers: { ...this.getHeaders(), 'Content-Type': 'application/json' },
      data,
      responseType: 'stream'
    });

    let fullResponse = '';
    let buffer = '';

    for await (const chunk of response.data) {
      buffer += chunk.toString();
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';

      for (const line of lines) {
        if (!line.trim()) continue;

        try {
          const event = JSON.parse(line);
          const status = event.status;

          if (status === 'loading') {
            const content = event.response || '';
            fullResponse += content;
            if (onMessage) {
              onMessage(content);
            }
          } else if (status === 'error') {
            throw new Error(event.error_message || 'Unknown error');
          }
        } catch (e) {
          console.error('Failed to parse line:', line);
        }
      }
    }

    return fullResponse;
  }

  async getHistory(agentId: string, threadId: string): Promise<any[]> {
    const url = `${this.config.baseUrl}/api/chat/agent/${agentId}/history`;
    const response = await axios.get(url, {
      headers: this.getHeaders(),
      params: { thread_id: threadId }
    });
    return response.data.messages || [];
  }

  async submitFeedback(messageId: number, rating: string, reason?: string): Promise<boolean> {
    const url = `${this.config.baseUrl}/api/chat/message/${messageId}/feedback`;
    const data: any = { rating };
    if (reason) {
      data.reason = reason;
    }

    const response = await axios.post(url, data, { headers: this.getHeaders() });
    return response.status === 200;
  }
}

// 使用示例
(async () => {
  const client = new YuxiChatClient({
    baseUrl: 'http://localhost:5050'
  });

  // 方式一：使用账号密码登录
  if (await client.login('admin', 'password')) {
    console.log('登录成功');
  }

  // 方式二：使用 SSO Token（直接使用认证中心的 Token）
  // const client = new YuxiChatClient({ baseUrl: 'http://localhost:5050', token: 'sso_token' });

  // 方式三：使用 Geelato Auth
  // client.setGeelatoAuth(
  //   'f47ac10b-58cc-4372-a567-0e02b2c3d479',
  //   'admin',
  //   'your-base64-encoded-secret-key'
  // );

  // 获取智能体列表
  const agents = await client.getAgents();
  console.log('可用智能体:', agents.map((a: any) => a.name));

  // 流式对话
  const agentId = agents[0].id;
  console.log('\nAI: ');
  
  await client.chatStream(agentId, '什么是人工智能？', undefined, (content) => {
    process.stdout.write(content);
  });

  console.log('\n');
})();
```

### 完整的集成示例（Vue.js）

```vue
<template>
  <div>
    <button @click="login">登录</button>
    <button @click="fetchAgents">获取智能体</button>
    <button @click="startChat">开始对话</button>
    <div v-if="chatResponse">{{ chatResponse }}</div>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue';
import axios from 'axios';
import CryptoJS from 'crypto-js';

const baseUrl = ref('http://localhost:5050');
const token = ref('');
const userInfo = ref(null);

const geelatoAuthConfig = ref({
  authKey: 'f47ac10b-58cc-4372-a567-0e02b2c3d479',
  username: 'admin',
  secretKey: 'your-base64-encoded-secret-key'
});

const encryptGeelatoAuth = () => {
  const { authKey, username, secretKey } = geelatoAuthConfig.value;
  const plaintext = `${authKey}:${username}`;
  const key = CryptoJS.enc.Base64.parse(secretKey);
  const iv = CryptoJS.lib.WordArray.random(16);
  const encrypted = CryptoJS.AES.encrypt(plaintext, key, {
    iv,
    mode: CryptoJS.mode.CBC,
    padding: CryptoJS.pad.Pkcs7
  });
  const combined = iv.concat(encrypted.ciphertext);
  return CryptoJS.enc.Base64.stringify(combined);
};

const getHeaders = () => {
  const headers = {} as Record<string, string>;

  if (geelatoAuthConfig.value.authKey) {
    const encrypted = encryptGeelatoAuth();
    headers['Authorization'] = `geelato_auth ${encrypted}`;
  } else if (token.value) {
    headers['Authorization'] = `Bearer ${token.value}`;
  }

  return headers;
};

const login = async () => {
  try {
    const response = await axios.post(`${baseUrl.value}/api/auth/token`, {
      username: 'admin',
      password: 'password'
    }, {
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' }
    });

    token.value = response.data.access_token;
    userInfo.value = response.data;
    console.log('登录成功');
  } catch (error) {
    console.error('登录失败:', error);
  }
};

const agents = ref([]);
const fetchAgents = async () => {
  try {
    const response = await axios.get(`${baseUrl.value}/api/chat/agent`, {
      headers: getHeaders()
    });
    agents.value = response.data.agents || [];
  } catch (error) {
    console.error('获取智能体失败:', error);
  }
};

const chatResponse = ref('');
const startChat = async () => {
  if (agents.value.length === 0) {
    console.error('请先获取智能体列表');
    return;
  }

  const agentId = agents.value[0].id;
  console.log('\nAI: ');
  chatResponse.value = '';

  try {
    const response = await axios({
      method: 'POST',
      url: `${baseUrl.value}/api/chat/agent/${agentId}`,
      headers: { ...getHeaders(), 'Content-Type': 'application/json' },
      data: { query: '什么是人工智能？' },
      responseType: 'stream'
    });

    let buffer = '';
    for await (const chunk of response.data) {
      buffer += chunk.toString();
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';

      for (const line of lines) {
        if (!line.trim()) continue;

        try {
          const event = JSON.parse(line);
          if (event.status === 'loading') {
            const content = event.response || '';
            chatResponse.value += content;
            process.stdout.write(content);
          }
        } catch (e) {
          console.error('Failed to parse line:', line);
        }
      }
    }
  } catch (error) {
    console.error('对话失败:', error);
  }
};
</script>
```

---

## 错误处理

### HTTP 状态码

| 状态码 | 说明 |
|--------|------|
| 200 | 成功 |
| 400 | 请求参数错误 |
| 401 | 未认证（Token 无效或过期） |
| 403 | 权限不足 |
| 404 | 资源不存在 |
| 422 | 验证失败 |
| 500 | 服务器内部错误 |

### 错误响应格式

```json
{
  "detail": "错误描述信息"
}
```

### 流式错误事件

在流式响应中，错误会作为 `status: "error"` 的事件返回：

```json
{
  "request_id": "req_abc123",
  "status": "error",
  "error_type": "agent_error",
  "error_message": "智能体获取失败"
}
```

---

## 常见问题

### Q1: Token 过期如何处理？

A: 当收到 401 状态码时，需要重新登录获取新的 token。

### Q2: 如何实现流式打字效果？

A: 使用逐字符或逐段输出，配合前端动画效果。JavaScript 示例已在上面提供。

### Q3: 如何限制响应长度？

A: 在 `config` 中设置 `max_tokens` 参数：

```json
{
  "query": "请详细解释...",
  "config": {
    "max_tokens": 500
  }
}
```

### Q4: 如何使用多模态功能？

A: 先上传图片获取 base64 数据，然后在对话请求中使用：

```typescript
// 上传图片
const formData = new FormData();
formData.append('file', imageFile);
const uploadResponse = await axios.post(
  "http://your-server:5050/api/chat/image/upload",
  formData,
  { headers: { 'Authorization': `Bearer ${token}` } }
);
const imageContent = uploadResponse.data.image_content;

// 在对话中使用
await client.chatStream(agentId, "描述这张图片", undefined, onMessage);
// 需要在请求中添加 image_content 参数
```

### Q5: SSO Token 认证失败怎么办？

A: 常见原因：
1. SSO 未启用 - 检查 `SSO_ENABLED=true`
2. Token 无效或过期 - 确保使用有效的 SSO Token
3. 字段映射配置错误 - 检查 `SSO_FIELD_MAPPING_*` 配置

### Q6: Geelato Auth 认证失败怎么办？

A: 常见原因：
1. 加密密钥不正确 - 检查 `GEELATO_AUTH_SECRET_KEY` 配置
2. 认证 Key 不在列表中 - 检查 `GEELATO_AUTH_KEYS` 配置
3. 用户不存在且 `GEELATO_AUTH_REQUIRE_USER_EXIST=true` - 设置为 `false` 可自动创建用户

### Q7: 如何让 Geelato Auth 自动创建用户？

A: 设置 `GEELATO_AUTH_REQUIRE_USER_EXIST=false`，当用户不存在时会自动创建。

---

## 相关文档

- [Geelato Auth 认证文档](./geelato-auth.md) - 后端服务集成认证方式详解
- [Geelato Auth 前端集成指南](./geelato-auth-frontend.md) - 前端应用集成指南
- [SSO 直接 Token 调用方案](./sso-direct-token.md) - SSO Token 直接调用接口说明

---

## 版本更新记录

| 日期 | 版本 | 更新内容 |
|------|------|----------|
| 2026-02-25 | 2.1.0 | 更新认证机制说明：SSO Token 支持自动创建用户，Geelato Auth 新增 `REQUIRE_USER_EXIST` 配置 |
| 2026-02-13 | 2.0.0 | 新增 Geelato Auth 和 SSO Token 认证方式，精简文档内容 |
| 2026-02-09 | 1.0.0 | 初始版本 |
