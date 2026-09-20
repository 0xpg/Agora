<script setup lang="ts">
import { computed, ref } from 'vue'
import { mockAssets } from '@/data/mockAssets'
import { mockInvestor } from '@/data/mockInvestor'
import { useAssetFilters } from '@/composables/useAssetFilters'
import { premiumDiscountPct } from '@/utils/pricing'
import { formatBps, formatCurrency } from '@/utils/format'
import AssetFilterBar from '@/components/AssetFilterBar.vue'
import AssetCard from '@/components/AssetCard.vue'
import AssetTable from '@/components/AssetTable.vue'
import SummaryMetrics, { type MetricItem } from '@/components/SummaryMetrics.vue'

const totalLiquidity = computed(() => mockAssets.reduce((sum, asset) => sum + asset.liquidity, 0))
const totalVolume30d = computed(() => mockAssets.reduce((sum, asset) => sum + asset.volume30d, 0))
const avgPremiumPct = computed(
  () => mockAssets.reduce((sum, asset) => sum + premiumDiscountPct(asset), 0) / mockAssets.length,
)

const metrics = computed<MetricItem[]>(() => [
  { label: 'TOTAL LIQUIDITY', value: formatCurrency(totalLiquidity.value, 'USD', 0), accentBarClass: 'bg-critical' },
  {
    label: '30D VOLUME',
    value: formatCurrency(totalVolume30d.value, 'USD', 0),
    caption: 'Settled on-chain',
    captionDotClass: 'bg-good',
  },
  {
    label: 'AVG. PREMIUM TO NAV',
    value: formatBps(avgPremiumPct.value),
    valueClass: avgPremiumPct.value >= 0 ? 'text-success' : 'text-critical',
    caption: 'Oracle-verified NAV',
  },
  { label: 'ASSETS LISTED', value: String(mockAssets.length), caption: 'ERC-3643 / ERC-20 RWA' },
])

const {
  search,
  classFilter,
  onlyEligible,
  issuerFilter,
  domicileFilter,
  currencyFilter,
  maturityFilter,
  assetClasses,
  issuers,
  domiciles,
  currencies,
  maturities,
  filteredAssets,
} = useAssetFilters(mockAssets, mockInvestor)
const view = ref<'cards' | 'list'>('cards')
</script>

<template>
  <div class="mx-auto max-w-6xl px-6 py-8">
    <div class="mb-6 flex flex-col gap-1">
      <h1 class="text-xl font-semibold text-ink">Markets</h1>
      <p class="text-sm text-ink-muted">Discover tokenized assets and their current batch auction rounds.</p>
    </div>

    <SummaryMetrics :metrics="metrics" class="mb-6" />

    <div class="mb-4 flex flex-col gap-1 sm:flex-row sm:items-end sm:justify-between">
      <div>
        <h2 class="text-base font-semibold text-ink">Assets</h2>
        <p class="text-xs text-ink-muted">Tokenized instruments with pooled secondary liquidity.</p>
      </div>
      <div class="flex shrink-0 rounded-md border border-hairline p-0.5 text-xs">
        <button
          type="button"
          class="rounded px-2.5 py-1.5 font-medium transition"
          :class="view === 'cards' ? 'bg-page text-ink' : 'text-ink-muted'"
          @click="view = 'cards'"
        >
          Cards
        </button>
        <button
          type="button"
          class="rounded px-2.5 py-1.5 font-medium transition"
          :class="view === 'list' ? 'bg-page text-ink' : 'text-ink-muted'"
          @click="view = 'list'"
        >
          List
        </button>
      </div>
    </div>

    <AssetFilterBar
      v-model:search="search"
      v-model:class-filter="classFilter"
      v-model:only-eligible="onlyEligible"
      v-model:issuer-filter="issuerFilter"
      v-model:domicile-filter="domicileFilter"
      v-model:currency-filter="currencyFilter"
      v-model:maturity-filter="maturityFilter"
      :asset-classes="assetClasses"
      :issuers="issuers"
      :domiciles="domiciles"
      :currencies="currencies"
      :maturities="maturities"
      class="mb-4"
    />

    <div v-if="view === 'cards'" class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
      <AssetCard v-for="asset in filteredAssets" :key="asset.id" :asset="asset" :investor="mockInvestor" />
      <p v-if="filteredAssets.length === 0" class="col-span-full py-10 text-center text-sm text-ink-muted">
        No assets match these filters.
      </p>
    </div>
    <AssetTable v-else :assets="filteredAssets" :investor="mockInvestor" />
  </div>
</template>
