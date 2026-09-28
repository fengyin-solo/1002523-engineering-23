import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// 所有地址/端口都来自统一配置（.env.example 为模板，scripts/ 与 docker-compose 同源注入）：
// VITE_PROXY_TARGET 控制 /api 代理目标，FRONTEND_HOST/PORT 控制 dev server 监听。
const proxyTarget = process.env.VITE_PROXY_TARGET ?? 'http://127.0.0.1:8000'
const host = process.env.FRONTEND_HOST ?? '127.0.0.1'
const port = Number(process.env.FRONTEND_PORT ?? '5173')

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
    },
  },
  server: {
    host,
    port,
    // 关掉自动打开页面：起服务时只打印地址，不拉起浏览器
    open: false,
    strictPort: false,
    proxy: {
      '/api': {
        target: proxyTarget,
        changeOrigin: true,
      },
    },
  },
  build: {
    outDir: 'dist',
    sourcemap: false,
  },
})
