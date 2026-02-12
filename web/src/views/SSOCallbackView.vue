<template>
  <div class="sso-callback-container">
    <a-spin :spinning="loading" tip="正在处理登录..." size="large">
      <div v-if="error" class="error-content">
        <a-result
          status="error"
          title="登录失败"
          :sub-title="error"
        >
          <template #extra>
            <a-button type="primary" @click="goToLogin">
              返回登录
            </a-button>
          </template>
        </a-result>
      </div>
    </a-spin>
  </div>
</template>

<script setup>
import { ref, onMounted } from 'vue'
import { useRoute, useRouter } from 'vue-router'
import { useUserStore } from '@/stores/user'

const route = useRoute()
const router = useRouter()
const userStore = useUserStore()

const loading = ref(true)
const error = ref('')

onMounted(async () => {
  const code = route.query.code
  const state = route.query.state
  const savedState = sessionStorage.getItem('sso_state')

  // 清除 state
  sessionStorage.removeItem('sso_state')

  if (!code) {
    error.value = '未收到授权码'
    loading.value = false
    return
  }

  // 验证 state 防止 CSRF 攻击
  if (state && savedState && state !== savedState) {
    error.value = '安全验证失败，请重新登录'
    loading.value = false
    return
  }

  try {
    // 调用 SSO 回调 API
    await userStore.ssoCallback({ code, state })

    // 登录成功，跳转到首页
    router.push('/')
  } catch (err) {
    console.error('SSO 回调处理失败:', err)
    error.value = err.message || '登录处理失败，请稍后重试'
    loading.value = false
  }
})

const goToLogin = () => {
  router.push('/login')
}
</script>

<style lang="less" scoped>
.sso-callback-container {
  display: flex;
  justify-content: center;
  align-items: center;
  height: 100vh;
  background-color: var(--gray-10);
  background-image: radial-gradient(var(--gray-200) 1px, transparent 1px);
  background-size: 24px 24px;

  .error-content {
    max-width: 480px;
    padding: 40px;
    background: var(--gray-0);
    border-radius: 16px;
    box-shadow: 0 0px 40px var(--shadow-1);
  }

  :deep(.ant-result-title) {
    color: var(--gray-700);
  }

  :deep(.ant-result-subtitle) {
    color: var(--gray-500);
  }

  :deep(.ant-spin-nested-loading) {
    width: 100%;
    height: 100%;
  }
}
</style>
