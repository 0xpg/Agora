<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRoute, RouterLink } from 'vue-router'
import { getAssetById, getDefaultTradeAsset } from '@/data/mockAssets'
import { mockInvestor } from '@/data/mockInvestor'
import { ELIGIBILITY_TIER_LABEL } from '@/types/market'
import { eligibilityState } from '@/composables/useEligibility'
import { useNow } from '@/composables/useNow'
import { premiumDiscountPct } from '@/utils/pricing'
import { activePolicy, feeBpsAt } from '@/utils/quote'
import {
  formatAge,
  formatBps,
  formatCompactNumber,
  formatCurrency,
  formatMaturity,
  formatPercent,
  formatRate,
} from '@/utils/format'
import PoolStatusBadge from '@/components/PoolStatusBadge.vue'
import EligibilityBadge from '@/components/EligibilityBadge.vue'
import MarketRulesPanel from '@/components/MarketRulesPanel.vue'
import PoolPolicyPanel from '@/components/PoolPolicyPanel.vue'
import PriceBandMeter from '@/components/PriceBandMeter.vue'
import PriceVsNavChart from '@/components/PriceVsNavChart.vue'
import SummaryMetrics, { type MetricItem } from '@/components/SummaryMetrics.vue'
import AssetInfoRows, { type InfoRow } from '@/components/AssetInfoRows.vue'
import SwapPanel from '@/components/SwapPanel.vue'

const route = useRoute()
const now = useNow(1000)
const requestedAsset = computed(() => (route.params.id ? getAssetById(String(route.params.id)) : undefined))
const notFound = computed(() => Boolean(route.params.id) && !requestedAsset.value)
const asset = computed(() => requestedAsset.value ?? getDefaultTradeAsset())
const investor = computed(() => mockInvestor)

const eligibility = computed(() => eligibilityState(asset.value, investor.value))
const premium = computed(() => premiumDiscountPct(asset.value))

// Where the swap panel's live quote would leave the pool price, drawn onto the
// range meter so the trade and the policy are read together.
const quotedPrice = ref<number | undefined>(undefined)

const TIMEFRAMES = [
  { label: '1M', days: 30 },
  { label: '3M', days: 90 },
  { label: '6M', days: 180 },
  { label: 'All', days: Infinity },
] as const
const timeframe = ref<(typeof TIMEFRAMES)[number]>(TIMEFRAMES[2])

const navSeries = computed(() => {
  const days = timeframe.value.days
  return Number.isFinite(days) ? asset.value.navHistory.slice(-days) : asset.value.navHistory
})
const priceSeries = computed(() => {
  const days = timeframe.value.days
  return Number.isFinite(days) ? asset.value.priceHistory.slice(-days) : asset.value.priceHistory
})

const navAge = computed(() => Math.max(now.value - asset.value.policy.navUpdatedAt, 0))
const currentFee = computed(() => {
  const active = activePolicy(asset.value.policy, now.value)
  return feeBpsAt(asset.value.lastPrice, active, asset.value.policy.targetPrice)
})

const priceMetrics = computed<MetricItem[]>(() => [
  {
    label: 'Pool Price',
    value: formatCurrency(asset.value.lastPrice, asset.value.currency),
    inlineNote: formatPercent(asset.value.change24hPct),
    inlineNoteClass: asset.value.change24hPct >= 0 ? 'text-success' : 'text-critical',
  },
  {
    label: 'Reference NAV',
    value: formatCurrency(asset.value.nav, asset.value.currency),
    caption: `Published ${formatAge(navAge.value)}`,
  },
  {
    label: 'Premium',
    value: formatBps(premium.value),
    valueClass: premium.value >= 0 ? 'text-success' : 'text-critical',
    inlineNote: premium.value >= 0 ? 'Premium' : 'Discount',
  },
  {
    label: 'Fee Now',
    value: `${currentFee.value.toFixed(1)} bps`,
    caption: 'Rises away from NAV',
  },
])

const supplyMetrics = computed<MetricItem[]>(() => [
  { label: 'Total Supply', value: formatCompactNumber(asset.value.totalSupply) },
  { label: 'Market Cap (NAV)', value: formatCurrency(asset.value.totalSupply * asset.value.nav, asset.value.currency, 0) },
  { label: 'Min. Investment', value: formatCurrency(asset.value.minInvestment, asset.value.currency, 0) },
])

const infoRows = computed<InfoRow[]>(() => [
  { label: 'Issuer', value: asset.value.issuer },
  { label: 'Domicile', value: asset.value.domicile },
  { label: 'Yield', value: formatRate(asset.value.yieldPct) },
  { label: 'Pool Liquidity', value: formatCurrency(asset.value.liquidity, asset.value.currency, 0) },
  { label: 'Maturity', value: formatMaturity(asset.value.maturityDate) },
  {
    label: 'Eligibility',
    value: asset.value.requiredTiers.map((tier) => ELIGIBILITY_TIER_LABEL[tier]).join(' or '),
    align: 'right',
  },
])
</script>

<template>
  <div class="mx-auto max-w-6xl px-6 py-8">
    <div v-if="notFound" class="py-16 text-center">
      <p class="text-sm text-ink-secondary">Asset not found.</p>
      <RouterLink to="/trade" class="mt-2 inline-block text-sm text-primary hover:underline">Back to Trade</RouterLink>
    </div>

    <template v-else>
      <div class="mb-1 flex items-center gap-1.5 text-[11px] font-medium tracking-wide text-ink-muted uppercase">
        <RouterLink to="/markets" class="hover:text-ink">Agora</RouterLink>
        <span>/</span>
        <RouterLink to="/trade" class="hover:text-ink">Trade</RouterLink>
        <span>/</span>
        <span class="text-ink">{{ asset.symbol }}</span>
      </div>

      <div class="mb-6 flex items-center justify-between gap-3">
        <h1 class="text-xl font-semibold text-ink">Trade</h1>
        <EligibilityBadge :state="eligibility" />
      </div>

      <div class="grid grid-cols-1 gap-6 lg:grid-cols-3">
        <div class="lg:col-span-1 lg:order-2">
          <SwapPanel :key="asset.id" :asset="asset" :investor="investor" @update:post-swap-price="quotedPrice = $event" />
        </div>

        <div class="lg:col-span-2 lg:order-1">
          <div class="flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
            <div class="flex items-center gap-3">
              <span
                class="flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-primary text-sm font-semibold text-on-accent"
              >
                {{ asset.symbol.charAt(0) }}
              </span>
              <div>
                <div class="flex items-center gap-2">
                  <span class="font-semibold text-ink">{{ asset.symbol }}</span>
                  <span class="text-xs text-ink-muted">{{ asset.assetClass }}</span>
                </div>
                <div class="text-sm text-ink-secondary">{{ asset.name }}</div>
                <span
                  class="mt-1 inline-block rounded-full border border-hairline px-2 py-0.5 text-[10px] font-medium text-ink-secondary"
                >
                  {{ asset.poolType === 'nav_managed' ? 'NAV-managed pool' : 'Standard pool' }}
                </span>
              </div>
            </div>
            <div class="flex flex-wrap items-center gap-2">
              <PoolStatusBadge :asset="asset" />
              <div class="flex rounded-md border border-hairline p-0.5 text-xs">
                <button
                  v-for="tf in TIMEFRAMES"
                  :key="tf.label"
                  type="button"
                  class="rounded px-2 py-1 font-medium transition"
                  :class="timeframe.label === tf.label ? 'bg-page text-ink' : 'text-ink-muted'"
                  @click="timeframe = tf"
                >
                  {{ tf.label }}
                </button>
              </div>
            </div>
          </div>

          <SummaryMetrics :metrics="priceMetrics" class="mt-4" />

          <PriceBandMeter :asset="asset" :post-swap-price="quotedPrice" class="mt-4" />

          <div class="mt-4 rounded-lg border border-hairline bg-surface p-5">
            <div class="h-72">
              <PriceVsNavChart :nav-series="navSeries" :price-series="priceSeries" />
            </div>
            <p class="mt-2 text-right text-xs text-ink-muted">Pool price against reference NAV</p>
          </div>

          <PoolPolicyPanel :asset="asset" class="mt-4" />

          <AssetInfoRows :rows="infoRows" class="mt-4" />

          <SummaryMetrics :metrics="supplyMetrics" class="mt-4" />

          <div class="mt-4">
            <MarketRulesPanel :rules="asset.rules" :required-tiers="asset.requiredTiers" />
          </div>
        </div>
      </div>
    </template>
  </div>
</template>
