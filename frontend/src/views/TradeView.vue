<script setup lang="ts">
import { computed, ref } from 'vue'
import { useRoute, RouterLink } from 'vue-router'
import { getAssetById, getDefaultTradeAsset } from '@/data/mockAssets'
import { mockInvestor } from '@/data/mockInvestor'
import { ELIGIBILITY_TIER_LABEL } from '@/types/market'
import { eligibilityState } from '@/composables/useEligibility'
import { useOrdersStore } from '@/stores/orders'
import { roundStatusFor } from '@/utils/roundStatus'
import { premiumDiscountPct } from '@/utils/pricing'
import { formatBps, formatCompactNumber, formatCurrency, formatMaturity, formatPercent, formatRate } from '@/utils/format'
import MarketStatusBadge from '@/components/MarketStatusBadge.vue'
import RoundStatusBadge from '@/components/RoundStatusBadge.vue'
import EligibilityBadge from '@/components/EligibilityBadge.vue'
import MarketRulesPanel from '@/components/MarketRulesPanel.vue'
import PriceVsNavChart from '@/components/PriceVsNavChart.vue'
import SummaryMetrics, { type MetricItem } from '@/components/SummaryMetrics.vue'
import AssetInfoRows, { type InfoRow } from '@/components/AssetInfoRows.vue'
import BatchOrderPanel from '@/components/BatchOrderPanel.vue'

const route = useRoute()
const requestedAsset = computed(() => (route.params.id ? getAssetById(String(route.params.id)) : undefined))
const notFound = computed(() => Boolean(route.params.id) && !requestedAsset.value)
const asset = computed(() => requestedAsset.value ?? getDefaultTradeAsset())
const investor = computed(() => mockInvestor)

const ordersStore = useOrdersStore()
const eligibility = computed(() => eligibilityState(asset.value, investor.value))
const roundStatus = computed(() => roundStatusFor(asset.value, ordersStore.now))
const premium = computed(() => premiumDiscountPct(asset.value))

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

const lastNavUpdate = computed(() => {
  const point = asset.value.navHistory[asset.value.navHistory.length - 1]
  if (!point) return ''
  return new Date(point.time * 1000).toLocaleDateString('en-US', { year: 'numeric', month: 'short', day: 'numeric' })
})

const priceMetrics = computed<MetricItem[]>(() => [
  {
    label: 'Pool Price',
    value: formatCurrency(asset.value.lastPrice, asset.value.currency),
    inlineNote: formatPercent(asset.value.change24hPct),
    inlineNoteClass: asset.value.change24hPct >= 0 ? 'text-success' : 'text-critical',
  },
  { label: 'Reference NAV', value: formatCurrency(asset.value.nav, asset.value.currency) },
  {
    label: 'Premium',
    value: formatBps(premium.value),
    valueClass: premium.value >= 0 ? 'text-success' : 'text-critical',
    inlineNote: premium.value >= 0 ? 'Premium' : 'Discount',
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
  { label: 'Liquidity', value: formatCurrency(asset.value.liquidity, asset.value.currency, 0) },
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
      <div class="mb-1 flex items-center gap-1.5 text-[11px] font-medium uppercase tracking-wide text-ink-muted">
        <RouterLink to="/markets" class="hover:text-ink">Agora DEX</RouterLink>
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
        <div class="lg:col-span-1">
          <BatchOrderPanel :asset="asset" :investor="investor" />
        </div>

        <div class="lg:col-span-2">
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
                  {{ asset.poolType === 'nav_managed' ? 'NAV-managed' : 'Standard pool' }}
                </span>
              </div>
            </div>
            <div class="flex flex-wrap items-center gap-2">
              <MarketStatusBadge :status="asset.marketStatus" />
              <RoundStatusBadge :status="roundStatus" />
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

          <div class="mt-4 rounded-lg border border-hairline bg-surface p-5">
            <div class="h-72">
              <PriceVsNavChart :nav-series="navSeries" :price-series="priceSeries" />
            </div>
            <p class="mt-2 text-right text-xs text-ink-muted">NAV history as of {{ lastNavUpdate }}</p>
          </div>

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
