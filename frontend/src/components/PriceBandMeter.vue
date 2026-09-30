<script setup lang="ts">
import { computed } from 'vue'
import type { TokenizedAsset } from '@/types/market'
import { activePolicy, guardZone, nowSeconds } from '@/utils/quote'
import { formatCurrency } from '@/utils/format'

const props = defineProps<{
  asset: TokenizedAsset
  /** Where the quoted trade would leave the pool price, when one is on screen. */
  postSwapPrice?: number
}>()

const active = computed(() => activePolicy(props.asset.policy, nowSeconds()))
const guard = computed(() => guardZone(props.asset.policy))

// The track spans the permitted range. A price outside it still has to be
// visible, so the scale widens to include it rather than pinning it to the edge.
const scale = computed(() => {
  const { bandLower, bandUpper } = active.value
  const span = bandUpper - bandLower
  const lo = Math.min(bandLower, props.asset.lastPrice, props.postSwapPrice ?? bandLower) - span * 0.04
  const hi = Math.max(bandUpper, props.asset.lastPrice, props.postSwapPrice ?? bandUpper) + span * 0.04
  return { lo, hi }
})

function pct(price: number): number {
  const { lo, hi } = scale.value
  if (hi <= lo) return 50
  return Math.min(Math.max(((price - lo) / (hi - lo)) * 100, 0), 100)
}

const bandStart = computed(() => pct(active.value.bandLower))
const bandEnd = computed(() => pct(active.value.bandUpper))
const freeStart = computed(() => pct(Math.max(guard.value.lower, active.value.bandLower)))
const freeEnd = computed(() => pct(Math.min(guard.value.upper, active.value.bandUpper)))

const currency = computed(() => props.asset.currency)
const priceOutsideBand = computed(
  () => props.asset.lastPrice < active.value.bandLower || props.asset.lastPrice > active.value.bandUpper,
)
const price = (value: number) => formatCurrency(value, currency.value, 4)

// A plain-language summary, so the meter is not the only way to read this.
const summary = computed(() => {
  const a = props.asset
  const parts = [
    `Pool price ${price(a.lastPrice)}, NAV ${price(a.policy.targetPrice)}.`,
    `Permitted range ${price(active.value.bandLower)} to ${price(active.value.bandUpper)}.`,
  ]
  if (priceOutsideBand.value) parts.push('Price is outside the permitted range, so trading is halted.')
  else if (guard.value.enabled) {
    parts.push(`Both directions trade between ${price(guard.value.lower)} and ${price(guard.value.upper)}.`)
  }
  if (props.postSwapPrice !== undefined) parts.push(`This trade would move it to ${price(props.postSwapPrice)}.`)
  return parts.join(' ')
})
</script>

<template>
  <div class="rounded-lg border border-hairline bg-surface p-5">
    <div class="flex flex-wrap items-baseline justify-between gap-x-3 gap-y-1">
      <h2 class="text-sm font-semibold text-ink">Permitted price range</h2>
      <span v-if="active.temporary" class="rounded-full bg-warning/10 px-2 py-0.5 text-[10px] font-medium text-warning">
        Temporary issuer policy
      </span>
    </div>
    <p class="mt-1 text-xs text-ink-muted">
      The pool refuses any swap that would start or land outside this range.
    </p>

    <div class="mt-5" role="img" :aria-label="summary">
      <!-- Track. The full width is the scale; the permitted range is the lit part of it. -->
      <div class="relative h-2.5 rounded-full bg-page ring-1 ring-hairline ring-inset">
        <div
          class="absolute inset-y-0 bg-critical/15"
          :style="{ left: `${bandStart}%`, width: `${bandEnd - bandStart}%` }"
        />
        <div
          v-if="guard.enabled"
          class="absolute inset-y-0 bg-primary/25"
          :style="{ left: `${freeStart}%`, width: `${Math.max(freeEnd - freeStart, 0)}%` }"
        />
        <div
          v-else
          class="absolute inset-y-0 bg-primary/25"
          :style="{ left: `${bandStart}%`, width: `${bandEnd - bandStart}%` }"
        />

        <!-- Range ends -->
        <span class="absolute -top-1 h-4.5 w-px bg-ink-muted" :style="{ left: `${bandStart}%` }" />
        <span class="absolute -top-1 h-4.5 w-px bg-ink-muted" :style="{ left: `${bandEnd}%` }" />

        <!-- NAV, the price the range and the fee curve are anchored to -->
        <span
          class="absolute -top-1.5 h-5.5 w-0.5 -translate-x-1/2 rounded-full bg-nav"
          :style="{ left: `${pct(asset.policy.targetPrice)}%` }"
        />

        <!-- Where the quoted trade would land -->
        <span
          v-if="postSwapPrice !== undefined"
          class="absolute -top-1 h-4.5 w-0.5 -translate-x-1/2 rounded-full bg-primary/70"
          :style="{ left: `${pct(postSwapPrice)}%` }"
        />

        <!-- Live pool price -->
        <span
          class="absolute -top-2 size-6.5 -translate-x-1/2 rounded-full border-2 bg-surface"
          :class="priceOutsideBand ? 'border-critical' : 'border-ink'"
          :style="{ left: `${pct(asset.lastPrice)}%` }"
        />
      </div>

      <div class="mt-2 flex justify-between text-[11px] tabular-nums text-ink-muted">
        <span>{{ price(active.bandLower) }}</span>
        <span>{{ price(active.bandUpper) }}</span>
      </div>
    </div>

    <dl class="mt-4 grid grid-cols-2 gap-x-4 gap-y-3 text-xs sm:grid-cols-4">
      <div>
        <dt class="flex items-center gap-1.5 text-ink-muted">
          <span class="h-2 w-0.5 rounded-full bg-ink" />
          Pool price
        </dt>
        <dd class="mt-0.5 tabular-nums" :class="priceOutsideBand ? 'text-critical' : 'text-ink'">
          {{ price(asset.lastPrice) }}
        </dd>
      </div>
      <div>
        <dt class="flex items-center gap-1.5 text-ink-muted">
          <span class="h-2 w-0.5 rounded-full bg-nav" />
          Reference NAV
        </dt>
        <dd class="mt-0.5 tabular-nums text-ink">{{ price(asset.policy.targetPrice) }}</dd>
      </div>
      <div v-if="postSwapPrice !== undefined">
        <dt class="flex items-center gap-1.5 text-ink-muted">
          <span class="h-2 w-0.5 rounded-full bg-primary/70" />
          After this trade
        </dt>
        <dd class="mt-0.5 tabular-nums text-ink">{{ price(postSwapPrice) }}</dd>
      </div>
      <div v-if="guard.enabled">
        <dt class="text-ink-muted">Both directions</dt>
        <dd class="mt-0.5 tabular-nums text-ink">{{ price(guard.lower) }} – {{ price(guard.upper) }}</dd>
      </div>
    </dl>

    <p class="mt-4 border-t border-hairline pt-3 text-xs text-ink-secondary">
      The fee rises with distance from NAV, from
      <span class="tabular-nums text-ink">{{ active.baseFeeBps }} bps</span> at NAV to
      <span class="tabular-nums text-ink">{{ active.edgeFeeBps }} bps</span> at the edge of the range.
      <template v-if="guard.enabled">
        Past the shaded ends, the pool accepts only swaps that move price back toward NAV.
      </template>
    </p>
  </div>
</template>
