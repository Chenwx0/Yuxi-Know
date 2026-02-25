/**
 * Apifox 接口前置脚本 - Geelato Auth 认证
 * 
 * 使用方法：
 * 1. 在 Apifox 中打开接口设置
 * 2. 进入「前置脚本」标签页
 * 3. 将此脚本复制到前置脚本编辑器中
 * 4. 在环境变量中配置以下变量：
 *    - GEELATO_AUTH_SECRET_KEY: 加密密钥（Base64编码）
 *    - GEELATO_AUTH_KEY: 认证 Key
 *    - GEELATO_AUTH_USERNAME: 用户名
 */

// ==================== 配置区域 ====================
// 可以直接在这里配置，也可以使用环境变量

// 加密密钥（Base64编码，32字节）
const SECRET_KEY = pm.environment.get("GEELATO_AUTH_SECRET_KEY") || "your-base64-encoded-secret-key";

// 认证 Key
const AUTH_KEY = pm.environment.get("GEELATO_AUTH_KEY") || "f47ac10b-58cc-4372-a567-0e02b2c3d479";

// 用户名
const USERNAME = pm.environment.get("GEELATO_AUTH_USERNAME") || "admin";

// 认证前缀
const AUTH_PREFIX = "geelato_auth";

// ==================== 加密实现 ====================

/**
 * Base64 解码为 WordArray
 */
function base64ToWordArray(base64) {
    return CryptoJS.enc.Base64.parse(base64);
}

/**
 * 生成随机 IV（16字节）
 */
function generateIV() {
    return CryptoJS.lib.WordArray.random(16);
}

/**
 * AES-256-CBC 加密
 * @param {string} plaintext - 明文数据
 * @param {string} secretKeyBase64 - Base64编码的密钥
 * @returns {string} Base64编码的加密数据（IV + 密文）
 */
function encrypt(plaintext, secretKeyBase64) {
    // 解码密钥
    const key = base64ToWordArray(secretKeyBase64);
    
    // 生成随机 IV
    const iv = generateIV();
    
    // AES-256-CBC 加密
    const encrypted = CryptoJS.AES.encrypt(plaintext, key, {
        iv: iv,
        mode: CryptoJS.mode.CBC,
        padding: CryptoJS.pad.Pkcs7
    });
    
    // 组合 IV + 密文
    const combined = iv.concat(encrypted.ciphertext);
    
    // 返回 Base64 编码
    return CryptoJS.enc.Base64.stringify(combined);
}

/**
 * 生成 Geelato Auth 认证头
 */
function generateAuthHeader() {
    // 拼接认证数据
    const plaintext = `${AUTH_KEY}:${USERNAME}`;
    
    // 加密
    const encrypted = encrypt(plaintext, SECRET_KEY);
    
    // 生成认证头
    return `${AUTH_PREFIX} ${encrypted}`;
}

// ==================== 执行认证 ====================

try {
    // 生成认证头
    const authHeader = generateAuthHeader();
    
    // 设置请求头
    pm.request.headers.add({
        key: "Authorization",
        value: authHeader
    });
    
    // 输出调试信息（可在 Apifox 控制台查看）
    console.log("=== Geelato Auth 认证信息 ===");
    console.log("用户名:", USERNAME);
    console.log("认证 Key:", AUTH_KEY);
    console.log("认证头:", authHeader);
    console.log("================================");
    
} catch (error) {
    console.error("Geelato Auth 认证失败:", error.message);
}
