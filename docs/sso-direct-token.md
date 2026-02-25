# SSO 直接 Token 调用方案

## 功能说明

现在支持直接使用认证中心的 Token 调用项目接口，无需先通过 SSO 回调获取本地 JWT Token。

## 使用方法

### 1. 认证中心 Token 调用

在 HTTP 请求的 `Authorization` 头中使用 `Bearer` 前缀：

```bash
# 使用 curl 示例
curl -H "Authorization: Bearer <认证中心Token>" \
  http://localhost:5050/api/knowledge/databases

# 使用 Python requests 示例
import requests

token = "<认证中心Token>"
headers = {
    "Authorization": f"Bearer {token}"
}
response = requests.get("http://localhost:5050/api/knowledge/databases", headers=headers)
```

### 2. 本地 JWT Token 调用（原有方式）

继续使用 `JWTBearer` 前缀：

```bash
curl -H "Authorization: JWTBearer <本地JWTToken>" \
  http://localhost:5050/api/knowledge/databases
```

## 验证流程

系统会按以下优先级验证 Token：

1. **Token 格式检测**：
   - `JWTBearer` 或无前缀：使用本地 JWT 验证
   - `Bearer`：使用认证中心 Token 验证

2. **认证中心 Token 验证**（按优先级）：
   - **方法1**：使用 `introspect` 端点验证（如果配置）
   - **方法2**：使用 `userinfo` 端点验证（如果 introspect 失败）
   - **方法3**：解析 Token 中的用户标识（作为最终备用）

3. **用户关联**：
   - 验证通过后，根据 Token 中的用户标识查找本地用户
   - 本地用户必须存在且已通过 SSO 登录过至少一次

## 配置要求

### 必需配置

| 配置项 | 说明 | 示例 |
|--------|------|------|
| `SSO_ENABLED` | 启用 SSO 功能 | `true` |
| `SSO_AUTHORIZATION_URL` | 授权端点 | `https://auth.example.com/oauth2/authorize` |
| `SSO_TOKEN_URL` | Token 端点 | `https://auth.example.com/oauth2/token` |
| `SSO_USER_INFO_URL` | 用户信息端点 | `https://auth.example.com/oauth2/userinfo` |
| `SSO_CLIENT_ID` | 客户端 ID | `yuxi-know` |
| `SSO_CLIENT_SECRET` | 客户端密钥 | `your-secret` |
| `SSO_REDIRECT_URI` | 回调地址 | `http://localhost:5173/sso/callback` |

### 可选配置

| 配置项 | 说明 | 示例 |
|--------|------|------|
| `SSO_INTROSPECT_URL` | Token 验证端点 | `https://auth.example.com/oauth2/introspect` |
| `SSO_FIELD_MAPPING_USERID` | 用户标识字段 | `id`（根据认证中心返回字段调整） |

## 错误处理

| 错误码 | 说明 | 解决方案 |
|--------|------|----------|
| 401 | Token 验证失败 | 检查 Token 是否有效、未过期 |
| 401 | 无效的凭证 | 检查 Token 格式是否正确 |
| 401 | SSO 未启用 | 确保 `SSO_ENABLED=true` |
| 401 | 无法从用户信息中提取用户标识 | 检查 `SSO_FIELD_MAPPING_USERID` 配置 |
| 404 | 用户不存在 | 确保用户已通过 SSO 登录过至少一次 |

## 安全注意事项

1. **Token 保护**：认证中心 Token 应妥善保管，避免泄露
2. **过期管理**：系统会自动处理 Token 过期，过期后需重新获取
3. **权限继承**：使用认证中心 Token 时，权限基于本地用户角色
4. **网络安全**：生产环境建议使用 HTTPS 传输 Token

## 示例场景

### 场景1：后端服务调用

其他系统的后端服务可以直接使用认证中心颁发的 Token 调用接口：

```python
# 后端服务调用示例
import requests

def call_yuxi_api(endpoint, token):
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json"
    }
    return requests.get(f"http://yuxi-know-api:5050/api{endpoint}", headers=headers)

# 使用认证中心 Token
response = call_yuxi_api("/knowledge/databases", "<认证中心Token>")
```

### 场景2：前端直接集成

前端应用可以直接使用认证中心的 Token 访问 API：

```javascript
// 前端调用示例
async function fetchWithSSOToken(url, options = {}) {
  const token = localStorage.getItem('sso_token');
  const headers = {
    ...options.headers,
    'Authorization': `Bearer ${token}`
  };
  return fetch(url, {
    ...options,
    headers
  });
}

// 使用示例
const response = await fetchWithSSOToken('http://localhost:5050/api/knowledge/databases');
```

## 兼容性

- ✅ 完全兼容原有本地 JWT Token 调用方式
- ✅ 支持标准 OAuth2/OpenID Connect 认证中心
- ✅ 支持自定义认证中心（需提供 userinfo 端点）
- ✅ 支持 Token 验证失败时的优雅降级