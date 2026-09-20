import { createRouter, createWebHistory } from 'vue-router'

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
      component: () => import('../views/MarketsView.vue'),
    },
    {
      path: '/trade/:id?',
      name: 'trade',
      component: () => import('../views/TradeView.vue'),
    },
    {
      path: '/portfolio',
      name: 'portfolio',
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
