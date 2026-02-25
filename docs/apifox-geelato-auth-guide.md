# Apifox Geelato Auth 认证配置指南

## 概述

本文档说明如何在 Apifox 中配置 Geelato Auth 认证，实现接口调用时自动生成认证信息。

## 前置条件

1. 已获取加密密钥（`GEELATO_AUTH_SECRET_KEY`）
2. 已获取认证 Key（`GEELATO_AUTH_KEYS` 中的一个）
3. 已安装 Apifox 客户端

## 配置步骤

### 步骤 1：配置环境变量

在 Apifox 中配置以下环境变量：

1. 打开 Apifox，进入项目设置
2. 点击「环境管理」→「全局变量」或选择特定环境
3. 添加以下变量：

| 变量名 | 类型 | 值 | 说明 |
|--------|------|-----|------|
| `GEELATO_AUTH_SECRET_KEY` | string | `<你的加密密钥>` | Base64 编码的 32 字节密钥 |
| `GEELATO_AUTH_KEY` | string | `<你的认证Key>` | 认证 Key |
| `GEELATO_AUTH_USERNAME` | string | `<用户名>` | 用于认证的用户名 |

### 步骤 2：添加前置脚本

#### 方式一：接口级别（推荐用于测试）

1. 打开需要认证的接口
2. 点击「前置脚本」标签页
3. 将 `scripts/apifox-geelato-auth.js` 的内容复制到编辑器中
4. 保存接口

#### 方式二：项目级别（推荐用于生产）

1. 点击项目设置（齿轮图标）
2. 进入「公共脚本」→「前置脚本」
3. 将 `scripts/apifox-geelato-auth.js` 的内容复制到编辑器中
4. 保存设置

### 步骤 3：发送请求

配置完成后，发送请求时会自动添加 `Authorization` 头：

```
Authorization: geelato_auth <加密数据>
```

## 脚本说明

### 核心函数

```javascript
// 加密函数
function encrypt(plaintext, secretKeyBase64) {
    // AES-256-CBC 加密
    // 返回 Base64 编码的加密数据（IV + 密文）
}

// 生成认证头
function generateAuthHeader() {
    // 拼接认证数据: auth_key:username
    // 加密并生成认证头
}
```

### 调试信息

脚本执行后会在 Apifox 控制台输出调试信息：

```
=== Geelato Auth 认证信息 ===
用户名: admin
认证 Key: f47ac10b-58cc-4372-a567-0e02b2c3d479
认证头: geelato_auth xxxxx...
================================
```

## 环境变量配置示例

### 开发环境

```json
{
    "GEELATO_AUTH_SECRET_KEY": "j0+UH13Xf0aqMfr/5yHX5is/kGu2o2m/mCcMsBBcYsI=",
    "GEELATO_AUTH_KEY": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
    "GEELATO_AUTH_USERNAME": "admin"
}
```

### 测试环境

```json
{
    "GEELATO_AUTH_SECRET_KEY": "test-secret-key-base64",
    "GEELATO_AUTH_KEY": "test-auth-key",
    "GEELATO_AUTH_USERNAME": "test-user"
}
```

## 常见问题

### Q: 提示"认证数据解密失败"

**原因**：加密密钥不正确

**解决方案**：
1. 检查 `GEELATO_AUTH_SECRET_KEY` 是否与服务端配置一致
2. 确保密钥是 Base64 编码的 32 字节字符串

### Q: 提示"无效的 Geelato Auth Key"

**原因**：认证 Key 不在服务端配置的 Key 列表中

**解决方案**：
1. 检查 `GEELATO_AUTH_KEY` 是否正确
2. 确认服务端 `GEELATO_AUTH_KEYS` 配置中包含该 Key

### Q: 提示"用户不存在"

**原因**：用户名在系统中不存在

**解决方案**：
1. 检查 `GEELATO_AUTH_USERNAME` 是否正确
2. 确认用户已在系统中注册

### Q: 如何验证加密是否正确？

可以在 Apifox 控制台查看生成的认证头，然后使用后端测试脚本验证：

```bash
# 在服务端容器中执行
docker compose exec api uv run python -c "
from server.utils.crypto_utils import AESCrypto
secret_key = 'your-secret-key'
encrypted = 'your-encrypted-data'
print(AESCrypto.decrypt(encrypted, secret_key))
"
```

## 安全注意事项

1. **不要在代码中硬编码密钥**：使用环境变量
2. **不要将密钥提交到版本控制**：添加到 `.gitignore`
3. **生产环境使用不同的密钥**：为不同环境配置不同的认证 Key
4. **定期轮换密钥**：建议每 90 天更换一次密钥

## 完整脚本

脚本文件位置：[scripts/apifox-geelato-auth.js](../scripts/apifox-geelato-auth.js)
