import { createRouter, createWebHistory } from 'vue-router'

declare module 'vue-router' {
  interface RouteMeta {
    /** Signed-in investors only; enforced by `installAccessGuard`. */
    requiresAuth?: boolean
  }
}

const router = createRouter({
  history: createWebHistory(import.meta.env.BASE_URL),
  routes: [
    {
      path: '/',
      name: 'landing',
      component: () => import('../views/LandingView.vue'),
    },
    {
      path: '/markets',
      name: 'markets',
      meta: { requiresAuth: true },
      component: () => import('../views/MarketsView.vue'),
    },
    {
      path: '/trade/:id?',
      name: 'trade',
      meta: { requiresAuth: true },
      component: () => import('../views/TradeView.vue'),
    },
    {
      path: '/portfolio',
      name: 'portfolio',
      meta: { requiresAuth: true },
      component: () => import('../views/PortfolioView.vue'),
    },
    {
      path: '/docs',
      name: 'docs',
      component: () => import('../views/DocsView.vue'),
    },
  ],
})

export default router
