<script setup lang="ts">
import { computed } from 'vue'
import { RouterLink } from 'vue-router'
import { mockAssets } from '@/data/mockAssets'
import { mockInvestor } from '@/data/mockInvestor'
import { premiumDiscountPct } from '@/utils/pricing'
import { formatBps, formatCurrency } from '@/utils/format'
import AssetCard from '@/components/AssetCard.vue'
import SummaryMetrics, { type MetricItem } from '@/components/SummaryMetrics.vue'

const VALUE_PROPS = [
  {
    title: 'Discover',
    body: 'Browse tokenized real-world assets across real estate, credit, treasuries, and more — filtered by class, issuer, and eligibility.',
  },
  {
    title: 'Verified Access',
    body: "Every asset lists the investor tier and KYC status it requires, so you know upfront whether you're eligible to trade it.",
  },
  {
    title: 'Transparent NAV',
    body: "See how each asset's market price compares to its reference NAV, with full price history alongside it.",
  },
  {
    title: 'Batch-Auction Settlement',
    body: 'Orders enter a timed round and settle against a fair, uniform clearing price once it closes — this is not an instant swap.',
  },
] as const

const HOW_IT_WORKS = [
  {
    title: 'Discover a market',
    body: 'Browse tokenized assets by class, issuer, or eligibility, and see each one’s live NAV and pricing context.',
  },
  {
    title: 'Confirm eligibility',
    body: 'Every asset lists its required investor tier and KYC status, so you always know where you stand before trading.',
  },
  {
    title: 'Submit an order into a round',
    body: 'Place a buy or sell order with a limit price. It enters the current batch auction round instead of executing immediately.',
  },
  {
    title: 'Get your settlement or refund',
    body: "Once the round closes, your order settles, partially fills, or is refunded — you'll see the result and any funds returned.",
  },
] as const

const FOOTER_LINKS = [
  { to: '/markets', label: 'Markets' },
  { to: '/trade', label: 'Trade' },
  { to: '/portfolio', label: 'Portfolio' },
  { to: '/docs', label: 'Docs' },
] as const

// A mix of open markets, not filtered to only what this particular investor is
// eligible for — an anonymous visitor hasn't connected a wallet yet, and seeing
// a restricted card here doubles as a preview of the "Verified Access" idea.
const previewAssets = computed(() =>
  [...mockAssets]
    .filter((asset) => asset.marketStatus === 'open')
    .sort((a, b) => b.liquidity - a.liquidity)
    .slice(0, 3),
)

const previewMetrics = computed<MetricItem[]>(() => {
  const totalLiquidity = mockAssets.reduce((sum, asset) => sum + asset.liquidity, 0)
  const avgPremiumPct =
    mockAssets.reduce((sum, asset) => sum + premiumDiscountPct(asset), 0) / mockAssets.length
  return [
    { label: 'TOTAL LIQUIDITY', value: formatCurrency(totalLiquidity, 'USD', 0) },
    {
      label: 'AVG. PREMIUM TO NAV',
      value: formatBps(avgPremiumPct),
      valueClass: avgPremiumPct >= 0 ? 'text-success' : 'text-critical',
    },
    { label: 'ASSETS LISTED', value: String(mockAssets.length) },
  ]
})
</script>

<template>
  <div>
    <header class="border-b border-black/40 bg-ink">
      <div class="mx-auto flex max-w-6xl items-center justify-between gap-4 px-6 py-4">
        <RouterLink to="/" class="flex items-center gap-2">
          <span class="flex h-5 w-5 rotate-45 rounded-[3px] bg-white" />
          <span class="text-base font-semibold tracking-tight text-white">Agora</span>
        </RouterLink>
        <div class="flex items-center gap-4">
          <a href="#how-it-works" class="hidden text-sm font-medium text-white/80 hover:text-white sm:inline">
            How it works
          </a>
          <RouterLink
            to="/markets"
            class="rounded-full bg-primary px-4 py-2 text-sm font-semibold text-white transition hover:bg-primary/90"
          >
            Enter Agora
          </RouterLink>
        </div>
      </div>
    </header>

    <section class="mx-auto max-w-5xl px-6 pt-20 pb-16 text-center sm:pt-28">
      <div class="hero-fade">
        <h1 class="text-4xl font-semibold tracking-tight text-ink sm:text-6xl">
          Real-world assets, made discoverable and tradable.
        </h1>
        <p class="mx-auto mt-6 max-w-2xl text-lg text-ink-secondary">
          Explore tokenized assets, understand their value, and participate in transparent market rounds&mdash;all in
          one place.
        </p>
        <div class="mt-8 flex flex-col items-center justify-center gap-3 sm:flex-row">
          <RouterLink
            to="/markets"
            class="rounded-full bg-primary px-6 py-3 text-sm font-semibold text-white transition hover:bg-primary/90"
          >
            Enter Agora
          </RouterLink>
          <a
            href="#how-it-works"
            class="rounded-full border border-hairline px-6 py-3 text-sm font-semibold text-ink transition hover:border-ink-muted"
          >
            How it works
          </a>
        </div>
      </div>
    </section>

    <section class="mx-auto max-w-6xl px-6 py-16">
      <div class="grid grid-cols-1 gap-6 sm:grid-cols-2 lg:grid-cols-4">
        <div
          v-for="(item, index) in VALUE_PROPS"
          :key="item.title"
          class="rounded-lg border border-hairline bg-surface p-6 transition hover:border-ink-muted"
        >
          <span class="text-xs font-medium tabular-nums text-primary">{{ String(index + 1).padStart(2, '0') }}</span>
          <h3 class="mt-3 text-sm font-semibold text-ink">{{ item.title }}</h3>
          <p class="mt-1 text-sm text-ink-secondary">{{ item.body }}</p>
        </div>
      </div>
    </section>

    <section class="mx-auto max-w-6xl px-6 py-16">
      <div class="mb-8 text-center">
        <h2 class="text-2xl font-semibold text-ink">A glimpse of the markets</h2>
        <p class="mt-2 text-sm text-ink-secondary">Real assets, real batch-auction rounds &mdash; this is what you'll see inside.</p>
      </div>
      <SummaryMetrics :metrics="previewMetrics" class="mb-6" />
      <div class="grid grid-cols-1 gap-4 sm:grid-cols-3">
        <AssetCard v-for="asset in previewAssets" :key="asset.id" :asset="asset" :investor="mockInvestor" />
      </div>
      <div class="mt-6 text-center">
        <RouterLink to="/markets" class="text-sm font-semibold text-primary hover:underline">
          See all markets &rarr;
        </RouterLink>
      </div>
    </section>

    <section id="how-it-works" class="mx-auto max-w-4xl scroll-mt-6 px-6 py-16">
      <h2 class="text-2xl font-semibold text-ink">How it works</h2>
      <ol class="mt-8 space-y-8">
        <li v-for="(step, index) in HOW_IT_WORKS" :key="step.title" class="flex gap-4">
          <span
            class="flex h-8 w-8 shrink-0 items-center justify-center rounded-full bg-primary-soft text-sm font-semibold tabular-nums text-primary-ink"
          >
            {{ index + 1 }}
          </span>
          <div>
            <h3 class="text-sm font-semibold text-ink">{{ step.title }}</h3>
            <p class="mt-1 text-sm text-ink-secondary">{{ step.body }}</p>
          </div>
        </li>
      </ol>
      <p class="mt-8 rounded-md border border-warning/40 bg-warning/10 px-4 py-3 text-xs text-ink-secondary">
        Some parts of this flow &mdash; like live wallet connections and on-chain settlement &mdash; are still being
        finalized. What you see today runs on representative data while the underlying integration comes together.
      </p>
    </section>

    <footer class="border-t border-hairline">
      <div class="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 px-6 py-8 text-xs text-ink-muted sm:flex-row">
        <span>&copy; 2026 Agora.</span>
        <nav class="flex flex-wrap items-center justify-center gap-4">
          <RouterLink v-for="link in FOOTER_LINKS" :key="link.to" :to="link.to" class="hover:text-ink">
            {{ link.label }}
          </RouterLink>
        </nav>
      </div>
    </footer>
  </div>
</template>

<style scoped>
@media (prefers-reduced-motion: no-preference) {
  .hero-fade {
    animation: hero-fade-in 0.6s ease-out;
  }
}

@keyframes hero-fade-in {
  from {
    opacity: 0;
    transform: translateY(8px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
</style>
