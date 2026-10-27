import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import vueDevTools from 'vite-plugin-vue-devtools'

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    vue(),
    vueDevTools(),
  ],
  resolve: {
    alias: {
      '@': new URL('./src', import.meta.url).pathname,
    },
  },
  server: {
    proxy: {
      // 工厂接口转发
      '/factories': {
        target: 'http://localhost:8080',
        changeOrigin: true,
      },
      // 车辆接口转发（之前漏掉的）
      '/vehicles': {
        target: 'http://localhost:8080',
        changeOrigin: true,
      },
      // 仿真控制接口转发
      '/sim': {
        target: 'http://localhost:8080',
        changeOrigin: true,
      },
    },
  },
})