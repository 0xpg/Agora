<script setup lang="ts">
import { computed } from 'vue'
import type { TokenizedAsset } from '@/types/market'
import type { Quote } from '@/utils/quote'
import { formatCurrency } from '@/utils/format'
import InfoTooltip from '@/components/InfoTooltip.vue'

const props = defineProps<{
  asset: TokenizedAsset
  quote: Quote
  slippageBps: number
}>()

// Anything past this much curve movement is worth a second look before signing.
const IMPACT_WARN_PCT = 0.5
const IMPACT_HIGH_PCT = 1.5

const currency = computed(() => props.asset.currency)
const money = (value: number, digits = 2) => formatCurrency(value, currency.value, digits)
const tokens = (value: number) => `${value.toLocaleString('en-US', { maximumFractionDigits: 4 })} ${props.asset.symbol}`

const impactClass = computed(() => {
  const impact = props.quote.priceImpactPct
  if (impact >= IMPACT_HIGH_PCT) return 'text-critical'
  if (impact >= IMPACT_WARN_PCT) return 'text-warning'
  return 'text-ink'
})

const feeNote = computed(
  () =>
    `This pool's fee moves with the distance between pool price and NAV: ${props.asset.policy.baseFeeBps} bps at NAV, up to ${props.asset.policy.edgeFeeBps} bps at the edge of the permitted range.`,
)

const cap = computed(() => props.asset.policy.maxTradeNotional)
const capUsedPct = computed(() => (cap.value > 0 ? Math.min((props.quote.notional / cap.value) * 100, 100) : 0))
</script>

<template>
  <dl class="space-y-2 text-xs">
    <div class="flex items-baseline justify-between gap-3">
      <dt class="text-ink-muted">Rate</dt>
      <dd class="tabular-nums text-ink">1 {{ asset.symbol }} = {{ money(quote.executionPrice, 4) }}</dd>
    </div>

    <div class="flex items-baseline justify-between gap-3">
      <dt class="text-ink-muted">Reference NAV</dt>
      <dd class="tabular-nums text-ink">{{ money(asset.policy.targetPrice, 4) }}</dd>
    </div>

    <div class="flex items-baseline justify-between gap-3">
      <dt class="flex items-center gap-1 text-ink-muted">
        Price impact
        <InfoTooltip text="How far your own trade moves the pool price along its curve. Larger trades move it further." />
      </dt>
      <dd class="tabular-nums" :class="impactClass">{{ quote.priceImpactPct.toFixed(3) }}%</dd>
    </div>

    <div class="flex items-baseline justify-between gap-3">
      <dt class="flex items-center gap-1 text-ink-muted">
        Pool fee
        <InfoTooltip :text="feeNote" />
      </dt>
      <dd class="tabular-nums text-ink">
        {{ quote.feeBps.toFixed(1) }} bps
        <span class="text-ink-muted">
          ({{ quote.side === 'buy' ? money(quote.feeAmount) : tokens(quote.feeAmount) }})
        </span>
      </dd>
    </div>

    <div class="flex items-baseline justify-between gap-3">
      <dt class="text-ink-muted">Pool price after</dt>
      <dd class="tabular-nums text-ink">{{ money(quote.postSwapPrice, 4) }}</dd>
    </div>

    <div class="flex items-baseline justify-between gap-3 border-t border-hairline pt-2">
      <dt class="flex items-center gap-1 text-ink-muted">
        {{ quote.mode === 'exactIn' ? 'Minimum received' : 'Maximum paid' }}
        <InfoTooltip
          :text="`The pool re-prices between your quote and your transaction. At ${(slippageBps / 100).toFixed(2)}% tolerance the swap reverts rather than settling worse than this.`"
        />
      </dt>
      <dd class="font-medium tabular-nums text-ink">
        <template v-if="quote.mode === 'exactIn'">
          {{ quote.side === 'buy' ? tokens(quote.slippageBound) : money(quote.slippageBound) }}
        </template>
        <template v-else>
          {{ quote.side === 'buy' ? money(quote.slippageBound) : tokens(quote.slippageBound) }}
        </template>
      </dd>
    </div>

    <div v-if="cap > 0" class="border-t border-hairline pt-2">
      <div class="flex items-baseline justify-between gap-3">
        <dt class="text-ink-muted">Trade size</dt>
        <dd class="tabular-nums text-ink">{{ money(quote.notional, 0) }} of {{ money(cap, 0) }} limit</dd>
      </div>
      <div class="mt-1.5 h-1 overflow-hidden rounded-full bg-page">
        <div
          class="h-full rounded-full transition-[width]"
          :class="capUsedPct >= 100 ? 'bg-critical' : capUsedPct > 80 ? 'bg-warning' : 'bg-primary'"
          :style="{ width: `${capUsedPct}%` }"
        />
      </div>
    </div>
  </dl>
</template>
