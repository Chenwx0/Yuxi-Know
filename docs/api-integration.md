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
- [最佳实践](#最佳实践)
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
| 认证方式 | Bearer Token (JWT) |
| 响应格式 | JSON（流式：newline-delimited JSON） |
| 编码 | UTF-8 |

---

## 认证机制

### 1. 用户登录

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

### 2. 使用 Token 访问 API

在请求头中添加：
```
Authorization: Bearer <access_token>
```

---

## API 端点说明

### 智能体管理

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
| model | string | 使用的模型名称（通过模型管理接口获取） |
| agent_config_id | number | 智能体配置 ID |
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
    },
    "meta": {
      "request_id": "req_abc123",
      "user_data": {
        "source": "external_app"
      }
    }
  }'
```

**响应格式**: 流式 JSON (每行一个 JSON 对象)

流式响应包含以下事件类型：

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
{"request_id":"req_abc123","status":"init","meta":{"agent_id":"chatbot","query":"什么是人工智能？","request_id":"req_abc123"},"msg":{"role":"user","content":"什么是人工智能？","type":"human"}}

{"request_id":"req_abc123","response":"人工智能（Artificial Intelligence，简称 AI）是计算机科学的一个分支，","status":"loading","msg":{...}}

{"request_id":"req_abc123","response":"它旨在创建能够执行通常需要人类智能的复杂任务的系统。","status":"loading","msg":{...}}

{"request_id":"req_abc123","response":"这些任务包括识别语音、","status":"loading","msg":{...}}

{"request_id":"req_abc123","status":"agent_state","agent_state":{"todos":[],"files":[]},"meta":{"request_id":"req_abc123"}}

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

**meta 可选参数**:
| 参数名 | 类型 | 说明 |
|--------|------|------|
| model_provider | string | 模型提供商 |
| model_name | string | 模型名称 |
| model_spec | string | 模型规格 |

**请求示例**:
```bash
curl -X POST "http://your-server:5050/api/chat/call" \
  -H "Authorization: Bearer your_token_here" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "你好",
    "meta": {
      "model_provider": "openai",
      "model_name": "gpt-4"
    }
  }'
```

**响应示例**:
```json
{
  "response": "你好！有什么我可以帮助你的吗？",
  "request_id": "uuid-1234-5678"
}
```

### 模型管理

> **注意**: 模型管理接口需要管理员权限。

#### 1. 查看支持的模型提供商

系统默认支持以下模型提供商：

| provider | 名称 | 默认模型 | 说明 |
|----------|------|----------|------|
| `openai` | OpenAI | gpt-4o-mini | OpenAI 官方模型 |
| `deepseek` | DeepSeek | deepseek-chat | DeepSeek AI |
| `zhipu` | 智谱AI | glm-4.5-flash | 智谱 AI 模型 |
| `siliconflow` | SiliconFlow | deepseek-ai/DeepSeek-V3.2 | 硅基流动平台 |
| `dashscope` | 阿里百炼 | qwen-max-latest | 阿里云模型 |

#### 2. 获取指定提供商的模型列表

**端点**: `GET /api/chat/models`

**认证**: 需要管理员权限

**查询参数**:
| 参数名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| model_provider | string | 是 | 模型提供商 ID |

**请求示例**:
```bash
curl -X GET "http://your-server:5050/api/chat/models?model_provider=siliconflow" \
  -H "Authorization: Bearer your_token_here"
```

**响应示例**:
```json
{
  "models": [
    "deepseek-ai/DeepSeek-V3.2",
    "Qwen/Qwen3-235B-A22B-Thinking-2507",
    "Qwen/Qwen3-235B-A22B-Instruct-2507",
    "moonshotai/Kimi-K2-Instruct-0905",
    "zai-org/GLM-4.6"
  ]
}
```

**使用示例（结合对话接口）**:
```javascript
// 1. 获取 SiliconFlow 的可用模型
const modelsResponse = await fetch(
  'http://your-server:5050/api/chat/models?model_provider=siliconflow',
  { headers: { 'Authorization': 'Bearer your_token' } }
);
const { models } = await modelsResponse.json();

// 2. 选择第一个模型进行对话
const selectedModel = models[0]; // "deepseek-ai/DeepSeek-V3.2"

// 3. 在对话中指定使用该模型
await chatStream({
  agentId: 'chatbot',
  query: '你好',
  config: {
    model: selectedModel  // 使用指定的模型
  }
});
```

### 线程（会话）管理

#### 1. 创建新对话线程

**端点**: `POST /api/chat/thread`

**认证**: 需要登录

**参数**:
| 参数名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| title | string | 否 | 对话标题 |
| agent_id | string | 是 | 智能体 ID |
| metadata | object | 否 | 元数据 |

**请求示例**:
```bash
curl -X POST "http://your-server:5050/api/chat/thread" \
  -H "Authorization: Bearer your_token_here" \
  -H "Content-Type: application/json" \
  -d '{
    "title": "关于 Python 的问题",
    "agent_id": "chatbot"
  }'
```

**响应示例**:
```json
{
  "id": "thread_abc123",
  "user_id": "1",
  "agent_id": "chatbot",
  "title": "关于 Python 的问题",
  "created_at": "2026-02-09T10:00:00Z",
  "updated_at": "2026-02-09T10:00:00Z"
}
```

#### 2. 获取用户的对话线程列表

**端点**: `GET /api/chat/threads`

**认证**: 需要登录

**查询参数**:
| 参数名 | 类型 | 必填 | 说明 |
|--------|------|------|------|
| agent_id | string | 是 | 智能体 ID |

**请求示例**:
```bash
curl -X GET "http://your-server:5050/api/chat/threads?agent_id=chatbot" \
  -H "Authorization: Bearer your_token_here"
```

**响应示例**:
```json
[
  {
    "id": "thread_abc123",
    "user_id": "1",
    "agent_id": "chatbot",
    "title": "关于 Python 的问题",
    "created_at": "2026-02-09T10:00:00Z",
    "updated_at": "2026-02-09T10:05:00Z"
  }
]
```

#### 3. 获取智能体历史消息

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

#### 4. 删除对话线程

**端点**: `DELETE /api/chat/thread/{thread_id}`

**认证**: 需要登录

**响应示例**:
```json
{
  "success": true
}
```

#### 5. 更新对话线程信息

**端点**: `PUT /api/chat/thread/{thread_id}`

**认证**: 需要登录

**参数**:
```json
{
  "title": "新标题"
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

#### 1. 提交消息反馈

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

**响应示例**:
```json
{
  "id": 1,
  "message_id": 1,
  "rating": "like",
  "reason": "回答很有帮助",
  "created_at": "2026-02-09T10:00:00Z"
}
```

#### 2. 获取消息反馈

**端点**: `GET /api/chat/message/{message_id}/feedback`

**认证**: 需要登录

**响应示例**:
```json
{
  "rating": "like",
  "reason": "回答很有帮助"
}
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
      // 流式输出
      process.stdout.write(data.response || '');
      break;
    case 'agent_state':
      console.log('Agent state updated:', data.agent_state);
      break;
    case 'interrupted':
      console.log('Chat interrupted:', data.message);
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

#### Python

```python
import requests
import json

def stream_chat(agent_id: str, query: str, token: str):
    url = f"http://your-server:5050/api/chat/agent/{agent_id}"
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }
    data = {"query": query}

    with requests.post(url, headers=headers, json=data, stream=True) as response:
        for line in response.iter_lines():
            if not line:
                continue

            try:
                event = json.loads(line.decode('utf-8'))
                handle_event(event)
            except json.JSONDecodeError:
                continue

def handle_event(event: dict):
    status = event.get('status')

    if status == 'init':
        print("[初始化]")
    elif status == 'loading':
        # 流式输出
        content = event.get('response', '')
        print(content, end='', flush=True)
    elif status == 'agent_state':
        print(f"\n[状态更新] {event.get('agent_state')}")
    elif status == 'interrupted':
        print(f"\n[中断] {event.get('message')}")
    elif status == 'error':
        print(f"\n[错误] {event.get('error_message')}")
    elif status == 'finished':
        print("\n[完成]")
```

#### Java (使用 OkHttp)

```java
import okhttp3.*;
import org.json.JSONObject;

import java.io.IOException;

public class ChatClient {
    private final OkHttpClient client = new OkHttpClient();
    private final String baseUrl;
    private final String token;

    public ChatClient(String baseUrl, String token) {
        this.baseUrl = baseUrl;
        this.token = token;
    }

    public void streamChat(String agentId, String query, ChatCallback callback) {
        String url = baseUrl + "/api/chat/agent/" + agentId;

        JSONObject jsonBody = new JSONObject();
        jsonBody.put("query", query);

        RequestBody body = RequestBody.create(
            jsonBody.toString(),
            MediaType.parse("application/json")
        );

        Request request = new Request.Builder()
            .url(url)
            .addHeader("Authorization", "Bearer " + token)
            .post(body)
            .build();

        client.newCall(request).enqueue(new Callback() {
            @Override
            public void onResponse(Call call, Response response) throws IOException {
                try (BufferedSource source = response.body().source()) {
                    while (!source.exhausted()) {
                        String line = source.readUtf8Line();
                        if (line == null || line.isEmpty()) continue;

                        try {
                            JSONObject event = new JSONObject(line);
                            callback.onEvent(event);
                        } catch (Exception e) {
                            // Ignore malformed lines
                        }
                    }
                    callback.onComplete();
                }
            }

            @Override
            public void onFailure(Call call, IOException e) {
                callback.onError(e);
            }
        });
    }

    public interface ChatCallback {
        void onEvent(JSONObject event);
        void onComplete();
        void onError(Exception e);
    }
}
```

---

## 集成示例代码

### 完整的集成示例（Python）

```python
import requests
import json
import uuid

class YuxiChatClient:
    def __init__(self, base_url: str = "http://localhost:5050"):
        self.base_url = base_url
        self.token = None
        self.user_info = None

    def login(self, username: str, password: str) -> bool:
        """用户登录"""
        url = f"{self.base_url}/api/auth/token"
        data = {
            "username": username,
            "password": password
        }

        response = requests.post(url, data=data)
        if response.status_code == 200:
            result = response.json()
            self.token = result['access_token']
            self.user_info = result
            return True
        return False

    def get_agents(self) -> list:
        """获取可用智能体列表"""
        url = f"{self.base_url}/api/chat/agent"
        response = requests.get(url, headers=self._get_headers())
        return response.json().get('agents', [])

    def get_models(self, model_provider: str) -> list:
        """获取指定模型提供商的模型列表（需要管理员权限）

        支持的提供商:
        - openai: OpenAI
        - deepseek: DeepSeek AI
        - zhipu: 智谱AI
        - siliconflow: 硅基流动
        - dashscope: 阿里百炼
        """
        url = f"{self.base_url}/api/chat/models"
        params = {"model_provider": model_provider}
        response = requests.get(url, headers=self._get_headers(), params=params)
        return response.json().get('models', [])

    def chat_with_model(self, agent_id: str, query: str,
                        model_name: str, thread_id: str = None) -> str:
        """使用指定模型进行对话

        Args:
            agent_id: 智能体 ID
            query: 用户问题
            model_name: 模型名称（通过 get_models() 获取）
            thread_id: 对话线程 ID（可选）

        Returns:
            完整的响应内容
        """
        full_response = ""
        url = f"{self.base_url}/api/chat/agent/{agent_id}"
        data = {"query": query}

        # 配置使用指定模型
        if model_name or thread_id:
            data["config"] = {}
            if model_name:
                data["config"]["model"] = model_name
            if thread_id:
                data["config"]["thread_id"] = thread_id

        response = requests.post(
            url,
            headers=self._get_headers(),
            json=data,
            stream=True
        )

        for line in response.iter_lines():
            if not line:
                continue

            try:
                event = json.loads(line.decode('utf-8'))
                status = event.get('status')

                if status == 'loading':
                    content = event.get('response', '')
                    full_response += content
                elif status == 'error':
                    raise Exception(event.get('error_message', 'Unknown error'))
                elif status == 'interrupted':
                    raise Exception(event.get('message', 'Chat interrupted'))

            except json.JSONDecodeError:
                continue

        return full_response

    def create_thread(self, agent_id: str, title: str = None) -> str:
        """创建对话线程"""
        url = f"{self.base_url}/api/chat/thread"
        data = {"agent_id": agent_id}
        if title:
            data["title"] = title

        response = requests.post(url, headers=self._get_headers(), json=data)
        return response.json().get('id')

    def chat_stream(self, agent_id: str, query: str,
                   thread_id: str = None, on_message=None) -> str:
        """流式对话"""
        url = f"{self.base_url}/api/chat/agent/{agent_id}"
        data = {"query": query}
        if thread_id:
            data["config"] = {"thread_id": thread_id}

        full_response = ""
        response = requests.post(
            url,
            headers=self._get_headers(),
            json=data,
            stream=True
        )

        for line in response.iter_lines():
            if not line:
                continue

            try:
                event = json.loads(line.decode('utf-8'))
                status = event.get('status')

                if status == 'loading':
                    content = event.get('response', '')
                    full_response += content
                    if on_message:
                        on_message(content, event)
                elif status == 'error':
                    error_msg = event.get('error_message', 'Unknown error')
                    raise Exception(error_msg)
                elif status == 'interrupted':
                    raise Exception(event.get('message', 'Chat interrupted'))

            except json.JSONDecodeError:
                continue

        return full_response

    def get_history(self, agent_id: str, thread_id: str) -> list:
        """获取对话历史"""
        url = f"{self.base_url}/api/chat/agent/{agent_id}/history"
        params = {"thread_id": thread_id}
        response = requests.get(url, headers=self._get_headers(), params=params)
        return response.json().get('messages', [])

    def submit_feedback(self, message_id: int, rating: str, reason: str = None) -> bool:
        """提交消息反馈"""
        url = f"{self.base_url}/api/chat/message/{message_id}/feedback"
        data = {"rating": rating}
        if reason:
            data["reason"] = reason

        response = requests.post(url, headers=self._get_headers(), json=data)
        return response.status_code == 200

    def _get_headers(self):
        return {"Authorization": f"Bearer {self.token}" if self.token else None}


# 使用示例
if __name__ == "__main__":
    # 初始化客户端
    client = YuxiChatClient("http://localhost:5050")

    # 登录
    if not client.login("username", "password"):
        print("登录失败")
        exit(1)

    # 获取智能体列表
    agents = client.get_agents()
    print(f"可用智能体: {[a['name'] for a in agents]}")

    # 选择智能体
    agent_id = agents[0]['id']

    # 创建对话线程
    thread_id = client.create_thread(agent_id, "测试对话")
    print(f"创建线程: {thread_id}")

    # 示例 1: 使用默认模型进行流式对话
    print("\n=== 使用默认模型 ===")
    def on_message(content, event):
        print(content, end='', flush=True)

    print("\nAI: ", end='')
    response = client.chat_stream(
        agent_id,
        "什么是人工智能？",
        thread_id,
        on_message
    )
    print("\n")

    # 示例 2: 获取并使用指定模型（需要管理员权限）
    print("\n=== 使用指定模型 ===")
    try:
        # 获取 SiliconFlow 提供商的模型列表
        models = client.get_models("siliconflow")
        print(f"SiliconFlow 可用模型: {models[:3]}...")  # 显示前3个

        if models:
            # 使用第一个模型进行对话
            selected_model = models[0]
            print(f"\n使用模型: {selected_model}")

            response = client.chat_with_model(
                agent_id,
                "用简单的语言解释量子计算",
                model_name=selected_model,
                thread_id=thread_id
            )
            print(f"响应: {response[:100]}...")  # 显示前100字符
    except Exception as e:
        print(f"获取模型失败（可能需要管理员权限）: {e}")

    # 获取历史记录
    history = client.get_history(agent_id, thread_id)
    print(f"\n历史消息数: {len(history)}")
```

### 完整的集成示例（JavaScript/Node.js）

```javascript
const axios = require('axios');

class YuxiChatClient {
  constructor(baseUrl = 'http://localhost:5050') {
    this.baseUrl = baseUrl;
    this.token = null;
    this.userInfo = null;
  }

  async login(username, password) {
    try {
      const response = await axios.post(`${this.baseUrl}/api/auth/token`, {
        username,
        password
      }, {
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        transformRequest: [data => {
          return Object.keys(data)
            .map(key => `${encodeURIComponent(key)}=${encodeURIComponent(data[key])}`)
            .join('&');
        }]
      });

      this.token = response.data.access_token;
      this.userInfo = response.data;
      return true;
    } catch (error) {
      console.error('Login failed:', error.response?.data || error.message);
      return false;
    }
  }

  getHeaders() {
    return this.token ? { 'Authorization': `Bearer ${this.token}` } : {};
  }

  async getAgents() {
    const response = await axios.get(
      `${this.baseUrl}/api/chat/agent`,
      { headers: this.getHeaders() }
    );
    return response.data.agents;
  }

  async getModels(modelProvider) {
    /**
     * 获取指定模型提供商的模型列表（需要管理员权限）
     *
     * 支持的提供商:
     * - openai: OpenAI
     * - deepseek: DeepSeek AI
     * - zhipu: 智谱AI
     * - siliconflow: 硅基流动
     * - dashscope: 阿里百炼
     */
    const response = await axios.get(
      `${this.baseUrl}/api/chat/models`,
      {
        headers: this.getHeaders(),
        params: { model_provider: modelProvider }
      }
    );
    return response.data.models;
  }

  async createThread(agentId, title = null) {
    const data = { agent_id: agentId };
    if (title) data.title = title;

    const response = await axios.post(
      `${this.baseUrl}/api/chat/thread`,
      data,
      { headers: this.getHeaders() }
    );
    return response.data.id;
  }

  async *chatStream(agentId, query, threadId = null) {
    const url = `${this.baseUrl}/api/chat/agent/${agentId}`;
    const data = { query };
    if (threadId) data.config = { thread_id };

    const response = await axios({
      method: 'POST',
      url,
      headers: { ...this.getHeaders(), 'Content-Type': 'application/json' },
      data,
      responseType: 'stream'
    });

    let buffer = '';

    for await (const chunk of response.data) {
      buffer += chunk.toString();
      const lines = buffer.split('\n');
      buffer = lines.pop() || ''; // Keep incomplete line in buffer

      for (const line of lines) {
        if (!line.trim()) continue;

        try {
          const event = JSON.parse(line);
          yield event;
        } catch (e) {
          console.error('Failed to parse line:', line);
        }
      }
    }

    // Process remaining buffer
    if (buffer.trim()) {
      try {
        const event = JSON.parse(buffer);
        yield event;
      } catch (e) {
        console.error('Failed to parse final line:', buffer);
      }
    }
  }

  async getHistory(agentId, threadId) {
    const response = await axios.get(
      `${this.baseUrl}/api/chat/agent/${agentId}/history`,
      { headers: this.getHeaders(), params: { thread_id } }
    );
    return response.data.messages;
  }

  async submitFeedback(messageId, rating, reason = null) {
    const data = { rating };
    if (reason) data.reason = reason;

    await axios.post(
      `${this.baseUrl}/api/chat/message/${messageId}/feedback`,
      data,
      { headers: this.getHeaders() }
    );
    return true;
  }

  async uploadImage(imagePath) {
    const FormData = require('form-data');
    const fs = require('fs');

    const form = new FormData();
    form.append('file', fs.createReadStream(imagePath));

    const response = await axios.post(
      `${this.baseUrl}/api/chat/image/upload`,
      form,
      {
        headers: {
          ...form.getHeaders(),
          ...this.getHeaders()
        }
      }
    );
    return response.data;
  }
}

// 使用示例
(async () => {
  const client = new YuxiChatClient('http://localhost:5050');

  // 登录
  if (!await client.login('username', 'password')) {
    console.log('登录失败');
    return;
  }

  // 获取智能体列表
  const agents = await client.getAgents();
  console.log('可用智能体:', agents.map(a => a.name));

  // 选择智能体
  const agentId = agents[0].id;

  // 创建对话线程
  const threadId = await client.createThread(agentId, '测试对话');
  console.log('创建线程:', threadId);

  // 示例 1: 使用默认模型进行流式对话
  console.log('\n=== 使用默认模型 ===');
  console.log('\nAI: ');
  for await (const event of client.chatStream(agentId, '什么是人工智能？', { thread_id: threadId })) {
    if (event.status === 'loading') {
      process.stdout.write(event.response || '');
    } else if (event.status === 'error') {
      console.error('\n错误:', event.error_message);
      break;
    } else if (event.status === 'interrupted') {
      console.log('\n中断:', event.message);
      break;
    }
  }

  // 示例 2: 获取并使用指定模型（需要管理员权限）
  console.log('\n=== 使用指定模型 ===');
  try {
    const models = await client.getModels('siliconflow');
    console.log('SiliconFlow 可用模型:', models.slice(0, 3).join(', ') + '...');

    if (models.length > 0) {
      const selectedModel = models[0];
      console.log(`\n使用模型: ${selectedModel}`);

      for await (const event of client.chatStream(agentId, '用简化的语言解释量子计算', {
        thread_id: threadId,
        model: selectedModel
      })) {
        if (event.status === 'loading') {
          process.stdout.write(event.response || '');
        }
      }
    }
  } catch (error) {
    console.log('获取模型失败（可能需要管理员权限）');
  }

  console.log('\n\n对话完成');
})();
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
| 423 | 账户被锁定 |
| 500 | 服务器内部错误 |

### 错误响应格式

```json
{
  "detail": "错误描述信息"
}
```

###流式错误事件

在流式响应中，错误会作为 `status: "error"` 的事件返回：

```json
{
  "request_id": "req_abc123",
  "status": "error",
  "error_type": "agent_error",
  "error_message": "智能体获取失败",
  "meta": {
    "request_id": "req_abc123"
  }
}
```

### 错误类型

| error_type | 说明 |
|------------|------|
| `agent_error` | 智能体错误 |
| `no_department` | 用户未绑定部门 |
| `content_guard_blocked` | 内容守卫拦截 |
| `unexpected_error` | 未知错误 |

---

## 最佳实践

### 1. Token 管理

```python
# Token 过期后自动重新登录
def ensure_token(client, username, password):
    if not client.token:
        return client.login(username, password)

    try:
        # 尝试调用一个需要认证的接口
        client.get_agents()
        return True
    except:
        return client.login(username, password)
```

### 2. 线程管理

```python
# 使用线程 ID 保持对话上下文
class ConversationManager:
    def __init__(self, client):
        self.client = client
        self.threads = {}  # agent_id -> thread_id

    def chat(self, agent_id, query):
        if agent_id not in self.threads:
            self.threads[agent_id] = self.client.create_thread(agent_id)

        return self.client.chat_stream(
            agent_id,
            query,
            self.threads[agent_id]
        )
```

### 3. 超时处理

```python
import signal

class TimeoutException(Exception):
    pass

def timeout_handler(signum, frame):
    raise TimeoutException("请求超时")

def chat_with_timeout(client, agent_id, query, timeout=30):
    signal.signal(signal.SIGALRM, timeout_handler)
    signal.alarm(timeout)

    try:
        return client.chat_stream(agent_id, query)
    finally:
        signal.alarm(0)
```

### 4. 重试机制

```python
import time
from functools import wraps

def retry(max_retries=3, delay=1):
    def decorator(func):
        @wraps(func)
        def wrapper(*args, **kwargs):
            for attempt in range(max_retries):
                try:
                    return func(*args, **kwargs)
                except Exception as e:
                    if attempt == max_retries - 1:
                        raise
                    time.sleep(delay * (attempt + 1))
        return wrapper
    return decorator

@retry(max_retries=3, delay=2)
def reliable_chat(client, agent_id, query):
    return client.chat_stream(agent_id, query)
```

### 5. 消息缓存

```python
import json
from pathlib import Path

class CacheManager:
    def __init__(self, cache_dir='cache'):
        self.cache_dir = Path(cache_dir)
        self.cache_dir.mkdir(exist_ok=True)

    def get_cached_history(self, thread_id):
        cache_file = self.cache_dir / f"{thread_id}.json"
        if cache_file.exists():
            with open(cache_file, 'r') as f:
                return json.load(f)
        return None

    def cache_history(self, thread_id, history):
        cache_file = self.cache_dir / f"{thread_id}.json"
        with open(cache_file, 'w') as f:
            json.dump(history, f)
```

---

## 常见问题

### Q1: Token 过期如何处理？

A: 当收到 401 状态码时，需要重新登录获取新的 token。

### Q2: 如何实现流式打字效果？

A: 使用逐字符或逐段输出，配合前端动画效果。JavaScript 示例已在上面提供。

### Q3: 如何处理网络中断？

A: 实现自动重连机制，保存未确认的消息，待网络恢复后重试。

### Q4: 如何限制响应长度？

A: 在 `config` 中设置 `max_tokens` 参数：

```json
{
  "query": "请详细解释...",
  "config": {
    "max_tokens": 500
  }
}
```

### Q5: 如何使用多模态功能？

A: 先上传图片获取 base64 数据，然后在对话请求中使用：

```python
# 上传图片
image_data = client.upload_image('/path/to/image.jpg')['image_content']

# 在对话中使用
client.chat_stream(agent_id, "描述这张图片", image_content=image_data)
```

### Q6: 如何获取智能体的完整配置？

A: 调用 `GET /api/chat/agent/{agent_id}/config` 获取完整配置，包括可配置项。

### Q7: 如何设置默认智能体？

A: 调用 `GET /api/chat/default_agent` 获取默认智能体 ID，或使用 `POST /api/chat/set_default_agent` 设置（需要管理员权限）。

---

## 版本更新记录

| 日期 | 版本 | 更新内容 |
|------|------|----------|
| 2026-02-09 | 1.0.0 | 初始版本，完整的对话集成 API 文档 |

---

## 技术支持

如有问题，请联系项目维护者或提交 Issue。
