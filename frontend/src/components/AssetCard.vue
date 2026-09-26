<script setup lang="ts">
import { computed } from 'vue'
import { RouterLink } from 'vue-router'
import type { Investor, TokenizedAsset } from '@/types/market'
import { eligibilityState, eligibilityReasonShort } from '@/composables/useEligibility'
import { MARKET_STATUS_CONFIG } from '@/utils/statusConfig'
import { roundStatusFor, formatCountdown } from '@/utils/roundStatus'
import { formatCurrency, formatPercent, formatRate } from '@/utils/format'
import { premiumDiscountPct } from '@/utils/pricing'
import { useOrdersStore } from '@/stores/orders'
import PriceVsNavChart from '@/components/PriceVsNavChart.vue'
import RoundStatusBadge from '@/components/RoundStatusBadge.vue'
import InfoTooltip from '@/components/InfoTooltip.vue'

const props = defineProps<{
  asset: TokenizedAsset
  investor: Investor
}>()

const ordersStore = useOrdersStore()

const state = computed(() => eligibilityState(props.asset, props.investor))
const marketOpen = computed(() => props.asset.marketStatus === 'open')
const tradable = computed(() => state.value === 'eligible' && marketOpen.value)
const premium = computed(() => premiumDiscountPct(props.asset))
const statusVisual = computed(() => MARKET_STATUS_CONFIG[props.asset.marketStatus])
const roundStatus = computed(() => roundStatusFor(props.asset, ordersStore.now))
const secondsRemaining = computed(() => Math.max(0, props.asset.roundClosesAt - ordersStore.now))

// Only surface a note when something actually blocks trading — an eligible,
// open-market asset needs no extra text competing with the price.
const blockingNote = computed(() => {
  if (!marketOpen.value) {
    return { text: statusVisual.value.label, critical: props.asset.marketStatus === 'restricted' }
  }
  if (state.value !== 'eligible') {
    return { text: eligibilityReasonShort(props.asset, props.investor), critical: state.value === 'restricted' }
  }
  return null
})
</script>

<template>
  <RouterLink
    :to="`/trade/${asset.id}`"
    class="flex flex-col gap-3 rounded-lg border border-hairline bg-surface p-4 transition hover:border-ink-muted"
  >
    <div class="flex items-start justify-between gap-2">
      <div class="min-w-0">
        <div class="flex items-center gap-2">
          <span class="font-semibold text-ink">{{ asset.symbol }}</span>
          <span class="truncate text-xs text-ink-muted">{{ asset.assetClass }}</span>
        </div>
        <div class="truncate text-sm text-ink-secondary">{{ asset.name }}</div>
      </div>
      <RoundStatusBadge :status="roundStatus" />
    </div>

    <div class="flex flex-wrap items-center gap-1.5">
      <span class="rounded-full border border-hairline px-2 py-0.5 text-[10px] font-medium text-ink-secondary">
        {{ asset.poolType === 'nav_managed' ? 'NAV-managed' : 'Standard pool' }}
      </span>
      <span
        v-if="asset.kycRequired"
        class="rounded-full border border-hairline px-2 py-0.5 text-[10px] font-medium text-ink-secondary"
      >
        KYC required
      </span>
      <span
        v-if="roundStatus === 'open'"
        class="rounded-full border border-hairline px-2 py-0.5 text-[10px] font-medium tabular-nums text-primary-ink"
      >
        Closes in {{ formatCountdown(secondsRemaining) }}
      </span>
    </div>

    <div class="h-16 w-full">
      <PriceVsNavChart :nav-series="asset.priceHistory" compact hover-readout />
    </div>

    <div class="grid grid-cols-3 gap-2 text-xs">
      <div>
        <div class="text-ink-muted">Yield</div>
        <div class="mt-0.5 font-medium tabular-nums text-ink">{{ formatRate(asset.yieldPct) }}</div>
      </div>
      <div>
        <div class="flex items-center gap-1 text-ink-muted">
          Premium
          <InfoTooltip text="How far the market price is from NAV (fair value)." />
        </div>
        <div class="mt-0.5 font-medium tabular-nums" :class="premium >= 0 ? 'text-success' : 'text-critical'">
          {{ formatPercent(premium) }}
        </div>
      </div>
      <div>
        <div class="text-ink-muted">Liquidity</div>
        <div class="mt-0.5 font-medium tabular-nums text-ink">
          {{ formatCurrency(asset.liquidity, asset.currency, 0) }}
        </div>
      </div>
    </div>

    <p
      v-if="blockingNote"
      class="rounded-md bg-page px-2.5 py-1.5 text-xs"
      :class="blockingNote.critical ? 'text-critical' : 'text-ink-secondary'"
    >
      {{ blockingNote.text }}
    </p>

    <div class="flex items-center justify-between border-t border-hairline pt-3 text-xs">
      <span class="truncate text-ink-muted">{{ asset.issuer }}</span>
      <span class="font-medium text-primary">{{ tradable ? 'Trade' : 'View' }} &rarr;</span>
    </div>
  </RouterLink>
</template>
