import { fileURLToPath, URL } from 'node:url'

import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import vueDevTools from 'vite-plugin-vue-devtools'
import tailwindcss from '@tailwindcss/vite'

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    vue(),
    vueDevTools(),
    tailwindcss(),
  ],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url)),
      // The deployment manifest lives beside the contracts, above this app's root.
      '@config': fileURLToPath(new URL('../config', import.meta.url)),
    },
  },
  server: {
    // Vite infers the workspace root as frontend/ (the repo has no root
    // package.json), so reading ../config needs explicit permission in dev.
    fs: {
      allow: [fileURLToPath(new URL('..', import.meta.url))],
    },
  },
})
