<script setup lang="ts">
import { computed } from 'vue'
import type { TokenizedAsset } from '@/types/market'
import { useNow } from '@/composables/useNow'
import { activePolicy, feeBpsAt, guardZone, permittedSide } from '@/utils/quote'
import { formatAge, formatCurrency, formatDuration } from '@/utils/format'
import InfoTooltip from '@/components/InfoTooltip.vue'

const props = defineProps<{ asset: TokenizedAsset }>()

// NAV ages and temporary policies lapse while the page is open, so this panel
// reads a ticking clock rather than the time it happened to mount at.
const now = useNow(1000)

const policy = computed(() => props.asset.policy)
const active = computed(() => activePolicy(policy.value, now.value))
const guard = computed(() => guardZone(policy.value))
const currentFee = computed(() => feeBpsAt(props.asset.lastPrice, active.value, policy.value.targetPrice))
const navAge = computed(() => Math.max(now.value - policy.value.navUpdatedAt, 0))
const navStale = computed(() => navAge.value > policy.value.navMaxAgeSeconds)
const bandUnsynced = computed(() => policy.value.bandSyncedNavUpdatedAt !== policy.value.navUpdatedAt)
const temporaryRemaining = computed(() =>
  active.value.expiresAt === null ? null : Math.max(active.value.expiresAt - now.value, 0),
)

const money = (value: number) => formatCurrency(value, props.asset.currency, 0)

interface PolicyRow {
  label: string
  value: string
  hint?: string
  tone?: 'warning' | 'critical'
}

const rows = computed<PolicyRow[]>(() => {
  const list: PolicyRow[] = [
    {
      label: 'Fee now',
      value: `${currentFee.value.toFixed(1)} bps`,
      hint: `The fee is set by how far pool price sits from NAV: ${active.value.baseFeeBps} bps at NAV, rising to ${active.value.edgeFeeBps} bps at the edge of the permitted range.`,
    },
    {
      label: 'Fee range',
      value: `${active.value.baseFeeBps} – ${active.value.edgeFeeBps} bps`,
    },
    {
      label: 'Max per swap',
      value: policy.value.maxTradeNotional > 0 ? money(policy.value.maxTradeNotional) : 'No limit',
      hint: 'The largest single swap this pool accepts. Larger size has to be split across several swaps.',
    },
    {
      label: 'NAV published',
      value: formatAge(navAge.value),
      tone: navStale.value ? 'critical' : bandUnsynced.value ? 'warning' : undefined,
      hint: bandUnsynced.value
        ? 'A new NAV has been published and the issuer has not yet re-anchored the price range to it. Swaps are refused until they do.'
        : undefined,
    },
    {
      label: 'NAV must be under',
      value: formatDuration(policy.value.navMaxAgeSeconds),
      hint: 'Past this age the pool refuses every swap until the issuer publishes a new NAV.',
    },
  ]

  if (policy.value.largeTradeNotional > 0) {
    list.push({
      label: `Swaps over ${money(policy.value.largeTradeNotional)}`,
      value: `NAV under ${formatDuration(policy.value.largeTradeMaxNavAgeSeconds)}`,
      tone: navAge.value > policy.value.largeTradeMaxNavAgeSeconds ? 'warning' : undefined,
      hint: 'Trades this large are held to a tighter NAV freshness rule than ordinary ones.',
    })
  }

  list.push({
    label: 'Rebalancing guard',
    value: guard.value.enabled ? `±${policy.value.directionalGuardBps} bps of NAV` : 'Not enabled',
    hint: guard.value.enabled
      ? 'Inside this zone both directions trade. Outside it, the pool accepts only swaps that move price back toward NAV.'
      : 'This pool accepts both directions anywhere inside its permitted price range.',
  })

  const onlySide = permittedSide(props.asset)
  if (onlySide) {
    list.push({
      label: 'Accepted direction',
      value: onlySide === 'buy' ? 'Buys only' : 'Sells only',
      tone: 'warning',
      hint: `Price has passed the guard, so the pool takes only the direction that moves it back toward NAV. ${onlySide === 'buy' ? 'Sells' : 'Buys'} are refused until it returns.`,
    })
  }

  if (temporaryRemaining.value !== null) {
    list.push({
      label: 'Temporary policy',
      value: `Expires in ${formatDuration(temporaryRemaining.value)}`,
      tone: 'warning',
      hint: 'The issuer has applied a short-lived price range and fee curve. It lapses on its own, restoring the standing policy.',
    })
  }

  return list
})
</script>

<template>
  <div class="rounded-lg border border-hairline bg-surface p-5">
    <h2 class="text-sm font-semibold text-ink">Pool policy</h2>
    <p class="mt-1 text-xs leading-relaxed text-ink-secondary">
      {{ asset.issuer }} sets the rules this pool trades under. They are enforced on every swap, so a trade that
      breaks one is refused rather than filled at a worse price.
    </p>

    <dl class="mt-4 grid grid-cols-1 gap-x-4 gap-y-3 sm:grid-cols-2">
      <div v-for="row in rows" :key="row.label" class="min-w-0">
        <dt class="flex items-center gap-1 text-xs text-ink-muted">
          <span class="truncate">{{ row.label }}</span>
          <InfoTooltip v-if="row.hint" :text="row.hint" />
        </dt>
        <dd
          class="mt-0.5 text-sm tabular-nums"
          :class="row.tone === 'critical' ? 'text-critical' : row.tone === 'warning' ? 'text-warning' : 'text-ink'"
        >
          {{ row.value }}
        </dd>
      </div>
    </dl>
  </div>
</template>
