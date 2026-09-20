<script setup lang="ts">
import { RouterLink } from 'vue-router'
import type { Investor, TokenizedAsset } from '@/types/market'
import { eligibilityState } from '@/composables/useEligibility'
import { formatCurrency, formatPercent } from '@/utils/format'
import { premiumDiscountPct } from '@/utils/pricing'
import { roundStatusFor, formatCountdown } from '@/utils/roundStatus'
import { useOrdersStore } from '@/stores/orders'
import PriceVsNavChart from '@/components/PriceVsNavChart.vue'
import EligibilityBadge from '@/components/EligibilityBadge.vue'
import RoundStatusBadge from '@/components/RoundStatusBadge.vue'

defineProps<{
  assets: TokenizedAsset[]
  investor: Investor
}>()

const ordersStore = useOrdersStore()
</script>

<template>
  <div>
    <div class="overflow-x-auto rounded-lg border border-hairline bg-surface">
      <table class="w-full min-w-[860px] text-left text-sm">
        <thead>
          <tr class="border-b border-hairline text-xs text-ink-muted">
            <th class="px-4 py-3 font-medium">Asset</th>
            <th class="px-4 py-3 font-medium">Class</th>
            <th class="px-4 py-3 text-right font-medium">NAV</th>
            <th class="px-4 py-3 text-right font-medium">Price</th>
            <th class="px-4 py-3 text-right font-medium">Prem/Disc</th>
            <th class="px-4 py-3 text-right font-medium">24h</th>
            <th class="w-28 px-4 py-3 font-medium">Trend</th>
            <th class="px-4 py-3 font-medium">Eligibility</th>
            <th class="px-4 py-3 font-medium">Round</th>
          </tr>
        </thead>
        <tbody>
          <RouterLink
            v-for="asset in assets"
            :key="asset.id"
            :to="`/trade/${asset.id}`"
            custom
            v-slot="{ navigate }"
          >
            <tr
              class="cursor-pointer border-b border-hairline last:border-b-0 hover:bg-page"
              @click="navigate"
            >
              <td class="px-4 py-3">
                <div class="font-medium text-ink">{{ asset.name }}</div>
                <div class="text-xs text-ink-muted">{{ asset.symbol }} &middot; {{ asset.issuer }}</div>
              </td>
              <td class="px-4 py-3 text-ink-secondary">{{ asset.assetClass }}</td>
              <td class="px-4 py-3 text-right tabular-nums text-ink">
                {{ formatCurrency(asset.nav, asset.currency) }}
              </td>
              <td class="px-4 py-3 text-right tabular-nums text-ink">
                {{ formatCurrency(asset.lastPrice, asset.currency) }}
              </td>
              <td
                class="px-4 py-3 text-right tabular-nums"
                :class="premiumDiscountPct(asset) >= 0 ? 'text-success' : 'text-critical'"
              >
                {{ formatPercent(premiumDiscountPct(asset)) }}
              </td>
              <td
                class="px-4 py-3 text-right tabular-nums"
                :class="asset.change24hPct >= 0 ? 'text-success' : 'text-critical'"
              >
                {{ formatPercent(asset.change24hPct) }}
              </td>
              <td class="h-12 w-28 px-4 py-3">
                <div class="h-8 w-full">
                  <PriceVsNavChart :nav-series="asset.navHistory" compact />
                </div>
              </td>
              <td class="px-4 py-3">
                <EligibilityBadge :state="eligibilityState(asset, investor)" />
              </td>
              <td class="px-4 py-3">
                <RoundStatusBadge :status="roundStatusFor(asset, ordersStore.now)" />
                <div v-if="roundStatusFor(asset, ordersStore.now) === 'open'" class="mt-1 text-xs tabular-nums text-ink-muted">
                  Closes in {{ formatCountdown(Math.max(0, asset.roundClosesAt - ordersStore.now)) }}
                </div>
              </td>
            </tr>
          </RouterLink>
          <tr v-if="assets.length === 0">
            <td colspan="9" class="px-4 py-10 text-center text-sm text-ink-muted">
              No assets match these filters.
            </td>
          </tr>
        </tbody>
      </table>
    </div>
  </div>
</template>
