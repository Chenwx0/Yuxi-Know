-- SSO 单点登录功能数据库迁移脚本
-- 创建时间：2026-02-12
-- 说明：为 User 表添加 SSO 相关字段

-- 添加 SSO 用户 ID 字段
ALTER TABLE users ADD COLUMN user_id_sso VARCHAR(100);

-- 添加登录来源字段
ALTER TABLE users ADD COLUMN login_source VARCHAR(20) DEFAULT 'local';

-- 添加索引优化查询性能
CREATE INDEX idx_user_id_sso ON users(user_id_sso);

-- 添加注释
COMMENT ON COLUMN users.user_id_sso IS 'SSO 用户唯一标识，用于关联认证中心用户';
COMMENT ON COLUMN users.login_source IS '登录来源：local=本地，sso=SSO，both=两者都支持';
