import { defineConfig } from 'cf/config'

export default defineConfig({
  worker: {
    name: 'agora',
    compatibilityDate: '2026-09-25',
    observability: {
      enabled: true,
    },
    assets: {
      notFoundHandling: 'single-page-application',
    },
  },
})
