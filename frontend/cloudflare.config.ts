import { bindings, defineConfig, triggers } from 'cf/config'

export default defineConfig({
  worker: {
    name: 'agora',
    entrypoint: './worker/index.ts',
    compatibilityDate: '2026-09-25',
    env: {
      DB: bindings.d1({ name: 'agora-indexer', id: '4a8f86cc-9d75-462b-a74b-b1f722ba091e' }),
    },
    triggers: [triggers.scheduled({ schedule: '* * * * *' })],
    observability: {
      enabled: true,
    },
    assets: {
      notFoundHandling: 'single-page-application',
      runWorkerFirst: ['/api/*'],
    },
  },
})
