# Geelato Auth 前端集成指南

## 概述

本文档提供前端应用集成 Geelato Auth 认证方式的详细指南，包括 JavaScript/TypeScript、Vue.js、React 等主流前端框架的实现示例。

## 前置条件

1. 获取加密密钥（`GEELATO_AUTH_SECRET_KEY`）
2. 获取认证 Key（`GEELATO_AUTH_KEYS` 中的一个）
3. 确保目标用户名在系统中存在
4. 安装加密库依赖

## 安装依赖

### npm/yarn

```bash
# 使用 cryptography 库（推荐，纯 JavaScript 实现）
npm install crypto-js

# 或使用 Web Crypto API（浏览器原生支持，无需安装）
```

### pnpm

```bash
pnpm add crypto-js
```

## 加密实现

### 方式一：使用 crypto-js

```typescript
import CryptoJS from 'crypto-js'

/**
 * Geelato Auth 加密工具
 */
export class GeelatoAuthCrypto {
  /**
   * 加密认证数据
   * @param plaintext 明文数据 (auth_key:username)
   * @param secretKeyBase64 Base64 编码的加密密钥
   * @returns Base64 编码的加密数据 (IV + 密文)
   */
  static encrypt(plaintext: string, secretKeyBase64: string): string {
    // 解码密钥
    const key = CryptoJS.enc.Base64.parse(secretKeyBase64)
    
    // 生成随机 IV (16 字节)
    const iv = CryptoJS.lib.WordArray.random(16)
    
    // AES-256-CBC 加密
    const encrypted = CryptoJS.AES.encrypt(plaintext, key, {
      iv: iv,
      mode: CryptoJS.mode.CBC,
      padding: CryptoJS.pad.Pkcs7
    })
    
    // 组合 IV + 密文并返回 Base64
    const combined = iv.concat(encrypted.ciphertext)
    return CryptoJS.enc.Base64.stringify(combined)
  }
  
  /**
   * 解密认证数据（用于调试）
   * @param encryptedBase64 Base64 编码的加密数据
   * @param secretKeyBase64 Base64 编码的加密密钥
   * @returns 解密后的明文
   */
  static decrypt(encryptedBase64: string, secretKeyBase64: string): string {
    // 解码密钥和加密数据
    const key = CryptoJS.enc.Base64.parse(secretKeyBase64)
    const combined = CryptoJS.enc.Base64.parse(encryptedBase64)
    
    // 提取 IV (前 16 字节) 和密文
    const iv = CryptoJS.lib.WordArray.create(combined.words.slice(0, 4), 16)
    const ciphertext = CryptoJS.lib.WordArray.create(combined.words.slice(4), combined.sigBytes - 16)
    
    // AES-256-CBC 解密
    const decrypted = CryptoJS.AES.decrypt(
      { ciphertext: ciphertext } as CryptoJS.lib.CipherParams,
      key,
      {
        iv: iv,
        mode: CryptoJS.mode.CBC,
        padding: CryptoJS.pad.Pkcs7
      }
    )
    
    return decrypted.toString(CryptoJS.enc.Utf8)
  }
}
```

### 方式二：使用 Web Crypto API（浏览器原生）

```typescript
/**
 * Geelato Auth 加密工具（Web Crypto API 版本）
 */
export class GeelatoAuthCryptoWeb {
  /**
   * Base64 解码为 Uint8Array
   */
  private static base64ToBytes(base64: string): Uint8Array {
    const binaryString = atob(base64)
    const bytes = new Uint8Array(binaryString.length)
    for (let i = 0; i < binaryString.length; i++) {
      bytes[i] = binaryString.charCodeAt(i)
    }
    return bytes
  }
  
  /**
   * Uint8Array 编码为 Base64
   */
  private static bytesToBase64(bytes: Uint8Array): string {
    let binary = ''
    for (let i = 0; i < bytes.length; i++) {
      binary += String.fromCharCode(bytes[i])
    }
    return btoa(binary)
  }
  
  /**
   * 加密认证数据
   * @param plaintext 明文数据 (auth_key:username)
   * @param secretKeyBase64 Base64 编码的加密密钥
   * @returns Base64 编码的加密数据 (IV + 密文)
   */
  static async encrypt(plaintext: string, secretKeyBase64: string): Promise<string> {
    // 解码密钥
    const keyBytes = this.base64ToBytes(secretKeyBase64)
    
    // 导入密钥
    const cryptoKey = await crypto.subtle.importKey(
      'raw',
      keyBytes,
      { name: 'AES-CBC' },
      false,
      ['encrypt']
    )
    
    // 生成随机 IV
    const iv = crypto.getRandomValues(new Uint8Array(16))
    
    // PKCS7 填充
    const encoder = new TextEncoder()
    const data = encoder.encode(plaintext)
    const blockSize = 16
    const paddingLen = blockSize - (data.length % blockSize)
    const paddedData = new Uint8Array(data.length + paddingLen)
    paddedData.set(data)
    paddedData.fill(paddingLen, data.length)
    
    // AES-CBC 加密
    const encrypted = await crypto.subtle.encrypt(
      { name: 'AES-CBC', iv: iv },
      cryptoKey,
      paddedData
    )
    
    // 组合 IV + 密文
    const combined = new Uint8Array(iv.length + encrypted.byteLength)
    combined.set(iv)
    combined.set(new Uint8Array(encrypted), iv.length)
    
    return this.bytesToBase64(combined)
  }
}
```

## API 客户端封装

### TypeScript 封装

```typescript
import CryptoJS from 'crypto-js'

export interface GeelatoAuthConfig {
  baseUrl: string
  secretKey: string
  authKey: string
  prefix?: string
}

export class GeelatoAuthClient {
  private config: GeelatoAuthConfig
  
  constructor(config: GeelatoAuthConfig) {
    this.config = {
      prefix: 'geelato_auth',
      ...config
    }
  }
  
  /**
   * 加密认证数据
   */
  private encrypt(plaintext: string): string {
    const key = CryptoJS.enc.Base64.parse(this.config.secretKey)
    const iv = CryptoJS.lib.WordArray.random(16)
    
    const encrypted = CryptoJS.AES.encrypt(plaintext, key, {
      iv: iv,
      mode: CryptoJS.mode.CBC,
      padding: CryptoJS.pad.Pkcs7
    })
    
    const combined = iv.concat(encrypted.ciphertext)
    return CryptoJS.enc.Base64.stringify(combined)
  }
  
  /**
   * 生成认证头
   */
  private getAuthHeader(username: string): string {
    const authData = `${this.config.authKey}:${username}`
    const encrypted = this.encrypt(authData)
    return `${this.config.prefix} ${encrypted}`
  }
  
  /**
   * GET 请求
   */
  async get<T>(endpoint: string, username: string, options?: RequestInit): Promise<T> {
    const response = await fetch(`${this.config.baseUrl}${endpoint}`, {
      method: 'GET',
      headers: {
        'Authorization': this.getAuthHeader(username),
        'Content-Type': 'application/json',
        ...options?.headers
      },
      ...options
    })
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`)
    }
    
    return response.json()
  }
  
  /**
   * POST 请求
   */
  async post<T>(endpoint: string, username: string, body?: unknown, options?: RequestInit): Promise<T> {
    const response = await fetch(`${this.config.baseUrl}${endpoint}`, {
      method: 'POST',
      headers: {
        'Authorization': this.getAuthHeader(username),
        'Content-Type': 'application/json',
        ...options?.headers
      },
      body: body ? JSON.stringify(body) : undefined,
      ...options
    })
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`)
    }
    
    return response.json()
  }
  
  /**
   * 通用请求方法
   */
  async request<T>(
    method: string,
    endpoint: string,
    username: string,
    body?: unknown,
    options?: RequestInit
  ): Promise<T> {
    const response = await fetch(`${this.config.baseUrl}${endpoint}`, {
      method,
      headers: {
        'Authorization': this.getAuthHeader(username),
        'Content-Type': 'application/json',
        ...options?.headers
      },
      body: body ? JSON.stringify(body) : undefined,
      ...options
    })
    
    if (!response.ok) {
      throw new Error(`HTTP ${response.status}: ${response.statusText}`)
    }
    
    return response.json()
  }
}
```

## Vue.js 集成示例

### 组合式 API (Composition API)

```vue
<template>
  <div>
    <button @click="fetchAgents">获取智能体列表</button>
    <pre>{{ agents }}</pre>
  </div>
</template>

<script setup lang="ts">
import { ref } from 'vue'
import { GeelatoAuthClient } from '@/utils/geelato-auth'

const agents = ref<any[]>(null)

// 配置（实际项目中应从环境变量或配置文件读取）
const client = new GeelatoAuthClient({
  baseUrl: 'http://localhost:5050',
  secretKey: import.meta.env.VITE_GEELATO_AUTH_SECRET_KEY,
  authKey: import.meta.env.VITE_GEELATO_AUTH_KEY
})

const fetchAgents = async () => {
  try {
    const result = await client.get('/api/chat/agent', 'admin')
    agents.value = result
  } catch (error) {
    console.error('获取智能体列表失败:', error)
  }
}
</script>
```

### 提供全局服务

```typescript
// src/services/geelato-auth.ts
import { GeelatoAuthClient } from '@/utils/geelato-auth'

let client: GeelatoAuthClient | null = null

export function initGeelatoAuth(config: {
  baseUrl: string
  secretKey: string
  authKey: string
}) {
  client = new GeelatoAuthClient(config)
}

export function getGeelatoAuthClient(): GeelatoAuthClient {
  if (!client) {
    throw new Error('Geelato Auth 未初始化，请先调用 initGeelatoAuth')
  }
  return client
}
```

```typescript
// main.ts
import { initGeelatoAuth } from '@/services/geelato-auth'

initGeelatoAuth({
  baseUrl: import.meta.env.VITE_API_BASE_URL,
  secretKey: import.meta.env.VITE_GEELATO_AUTH_SECRET_KEY,
  authKey: import.meta.env.VITE_GEELATO_AUTH_KEY
})
```

## React 集成示例

### 自定义 Hook

```typescript
// hooks/useGeelatoAuth.ts
import { useCallback, useMemo } from 'react'
import { GeelatoAuthClient } from '@/utils/geelato-auth'

interface UseGeelatoAuthOptions {
  baseUrl: string
  secretKey: string
  authKey: string
  username: string
}

export function useGeelatoAuth(options: UseGeelatoAuthOptions) {
  const client = useMemo(() => new GeelatoAuthClient({
    baseUrl: options.baseUrl,
    secretKey: options.secretKey,
    authKey: options.authKey
  }), [options.baseUrl, options.secretKey, options.authKey])
  
  const get = useCallback(<T>(endpoint: string) => {
    return client.get<T>(endpoint, options.username)
  }, [client, options.username])
  
  const post = useCallback(<T>(endpoint: string, body?: unknown) => {
    return client.post<T>(endpoint, options.username, body)
  }, [client, options.username])
  
  return { get, post, client }
}
```

### 组件使用

```tsx
import { useGeelatoAuth } from '@/hooks/useGeelatoAuth'

function AgentList() {
  const { get } = useGeelatoAuth({
    baseUrl: process.env.REACT_APP_API_BASE_URL!,
    secretKey: process.env.REACT_APP_GEELATO_AUTH_SECRET_KEY!,
    authKey: process.env.REACT_APP_GEELATO_AUTH_KEY!,
    username: 'admin'
  })
  
  const [agents, setAgents] = useState<any[]>([])
  const [loading, setLoading] = useState(false)
  
  const fetchAgents = async () => {
    setLoading(true)
    try {
      const result = await get<any[]>('/api/chat/agent')
      setAgents(result)
    } catch (error) {
      console.error('获取智能体列表失败:', error)
    } finally {
      setLoading(false)
    }
  }
  
  return (
    <div>
      <button onClick={fetchAgents} disabled={loading}>
        {loading ? '加载中...' : '获取智能体列表'}
      </button>
      <ul>
        {agents.map(agent => (
          <li key={agent.id}>{agent.name}</li>
        ))}
      </ul>
    </div>
  )
}
```

## 环境变量配置

### Vue.js (Vite)

```env
# .env.local
VITE_API_BASE_URL=http://localhost:5050
VITE_GEELATO_AUTH_SECRET_KEY=your-base64-encoded-secret-key
VITE_GEELATO_AUTH_KEY=f47ac10b-58cc-4372-a567-0e02b2c3d479
```

### React (Create React App)

```env
# .env.local
REACT_APP_API_BASE_URL=http://localhost:5050
REACT_APP_GEELATO_AUTH_SECRET_KEY=your-base64-encoded-secret-key
REACT_APP_GEELATO_AUTH_KEY=f47ac10b-58cc-4372-a567-0e02b2c3d479
```

### Next.js

```env
# .env.local
NEXT_PUBLIC_API_BASE_URL=http://localhost:5050
NEXT_PUBLIC_GEELATO_AUTH_SECRET_KEY=your-base64-encoded-secret-key
NEXT_PUBLIC_GEELATO_AUTH_KEY=f47ac10b-58cc-4372-a567-0e02b2c3d479
```

## 安全注意事项

### 前端安全

1. **不要在代码中硬编码密钥**：使用环境变量
2. **不要将密钥提交到版本控制**：添加 `.env.local` 到 `.gitignore`
3. **生产环境使用 HTTPS**：防止中间人攻击
4. **限制密钥权限**：为不同环境使用不同的认证 Key

### 密钥存储建议

```typescript
// 推荐：从后端动态获取配置
async function initAuth() {
  const config = await fetch('/api/auth/config').then(r => r.json())
  initGeelatoAuth(config)
}

// 不推荐：硬编码在代码中
const SECRET_KEY = 'your-secret-key' // ❌ 危险！
```

## 错误处理

```typescript
async function callApi() {
  try {
    const result = await client.get('/api/chat/agent', 'admin')
    return result
  } catch (error) {
    if (error instanceof Error) {
      if (error.message.includes('401')) {
        console.error('认证失败：检查密钥和用户名是否正确')
      } else if (error.message.includes('403')) {
        console.error('权限不足：用户没有访问权限')
      } else {
        console.error('请求失败:', error.message)
      }
    }
    throw error
  }
}
```

## 调试技巧

### 验证加密结果

```typescript
// 使用解密方法验证加密是否正确
const plaintext = 'auth-key:username'
const encrypted = GeelatoAuthCrypto.encrypt(plaintext, secretKey)
const decrypted = GeelatoAuthCrypto.decrypt(encrypted, secretKey)

console.log('原文:', plaintext)
console.log('解密后:', decrypted)
console.log('匹配:', plaintext === decrypted)
```

### 查看请求头

```typescript
// 在浏览器开发者工具中查看请求头
const authHeader = client.getAuthHeader('admin')
console.log('Authorization:', authHeader)
```

## 完整示例

```typescript
// utils/geelato-auth.ts
import CryptoJS from 'crypto-js'

export interface GeelatoAuthConfig {
  baseUrl: string
  secretKey: string
  authKey: string
  prefix?: string
}

export class GeelatoAuthClient {
  private config: Required<GeelatoAuthConfig>
  
  constructor(config: GeelatoAuthConfig) {
    this.config = {
      prefix: 'geelato_auth',
      ...config
    }
  }
  
  private encrypt(plaintext: string): string {
    const key = CryptoJS.enc.Base64.parse(this.config.secretKey)
    const iv = CryptoJS.lib.WordArray.random(16)
    const encrypted = CryptoJS.AES.encrypt(plaintext, key, {
      iv,
      mode: CryptoJS.mode.CBC,
      padding: CryptoJS.pad.Pkcs7
    })
    return CryptoJS.enc.Base64.stringify(iv.concat(encrypted.ciphertext))
  }
  
  private getAuthHeader(username: string): string {
    const encrypted = this.encrypt(`${this.config.authKey}:${username}`)
    return `${this.config.prefix} ${encrypted}`
  }
  
  async request<T>(method: string, endpoint: string, username: string, body?: unknown): Promise<T> {
    const response = await fetch(`${this.config.baseUrl}${endpoint}`, {
      method,
      headers: {
        Authorization: this.getAuthHeader(username),
        'Content-Type': 'application/json'
      },
      body: body ? JSON.stringify(body) : undefined
    })
    
    if (!response.ok) {
      const error = await response.text()
      throw new Error(`HTTP ${response.status}: ${error}`)
    }
    
    return response.json()
  }
  
  get<T>(endpoint: string, username: string) {
    return this.request<T>('GET', endpoint, username)
  }
  
  post<T>(endpoint: string, username: string, body?: unknown) {
    return this.request<T>('POST', endpoint, username, body)
  }
  
  put<T>(endpoint: string, username: string, body?: unknown) {
    return this.request<T>('PUT', endpoint, username, body)
  }
  
  delete<T>(endpoint: string, username: string) {
    return this.request<T>('DELETE', endpoint, username)
  }
}
```

## 常见问题

### Q: 前端暴露密钥是否安全？

A: 如果前端代码会被公开访问，建议：
1. 使用后端代理请求
2. 为前端应用分配受限权限的认证 Key
3. 限制可访问的 API 接口

### Q: 如何处理 Token 过期？

A: Geelato Auth 不涉及 Token 过期问题，每次请求都会重新验证。如果需要限制有效期，可以添加时间戳验证。

### Q: 如何实现多用户切换？

A: 在调用 API 时传入不同的用户名即可：

```typescript
// 用户 A
await client.get('/api/data', 'user-a')

// 用户 B
await client.get('/api/data', 'user-b')
```
