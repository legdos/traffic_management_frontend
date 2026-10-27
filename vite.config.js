import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import vueDevTools from 'vite-plugin-vue-devtools'

export default defineConfig({
  plugins: [vue(), vueDevTools()],
  resolve: { alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) } },
  server: {
    proxy: {
      '/factories': { target: 'http://127.0.0.1:8080', changeOrigin: true },
      '/needs': { target: 'http://127.0.0.1:8080', changeOrigin: true },
      '/vehicles': { target: 'http://127.0.0.1:8080', changeOrigin: true },
      '/actions': { target: 'http://127.0.0.1:8080', changeOrigin: true },
      '/pois': { target: 'http://127.0.0.1:8080', changeOrigin: true },
      '/tasks': { target: 'http://127.0.0.1:8080', changeOrigin: true },
      '/matching': { target: 'http://127.0.0.1:8080', changeOrigin: true },
      '/simulation': { target: 'http://127.0.0.1:8080', changeOrigin: true },
    },
  },
})
