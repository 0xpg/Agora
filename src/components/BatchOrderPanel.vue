<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import type { Investor, TokenizedAsset } from '@/types/market'
import { useWalletStore } from '@/stores/wallet'
import { useOrdersStore } from '@/stores/orders'
import { eligibilityReason, eligibilityState } from '@/composables/useEligibility'
import { roundStatusFor, formatCountdown } from '@/utils/roundStatus'
import { formatCurrency } from '@/utils/format'
import TokenAmountInput from '@/components/TokenAmountInput.vue'
import OrderStatusBadge from '@/components/OrderStatusBadge.vue'

const props = defineProps<{
  asset: TokenizedAsset
  investor: Investor
}>()

const wallet = useWalletStore()
const ordersStore = useOrdersStore()

const state = computed(() => eligibilityState(props.asset, props.investor))
const reason = computed(() => eligibilityReason(props.asset, props.investor))
const marketOpen = computed(() => props.asset.marketStatus === 'open')
const eligible = computed(() => state.value === 'eligible')

const roundStatus = computed(() => roundStatusFor(props.asset, ordersStore.now))
const secondsRemaining = computed(() => Math.max(0, props.asset.roundClosesAt - ordersStore.now))

const side = ref<'buy' | 'sell'>('buy')
const units = ref(1)
const limitPrice = ref(props.asset.nav)
const approved = ref(false)
const dismissed = ref(false)

watch(
  () => props.asset.id,
  () => {
    side.value = 'buy'
    units.value = 1
    limitPrice.value = props.asset.nav
    approved.value = false
    dismissed.value = false
  },
)

const activeOrder = computed(() => ordersStore.orderForAsset(props.asset.id))
const showForm = computed(() => !activeOrder.value || (dismissed.value && activeOrder.value.status !== 'pending'))

const escrowToken = computed(() => (side.value === 'buy' ? props.asset.currency : props.asset.symbol))
const estimatedTotal = computed(() => (units.value > 0 ? units.value * limitPrice.value : 0))
const belowMinInvestment = computed(
  () => side.value === 'buy' && estimatedTotal.value > 0 && estimatedTotal.value < props.asset.minInvestment,
)
const canSubmit = computed(() => approved.value && units.value > 0 && limitPrice.value > 0 && !belowMinInvestment.value)

function approve() {
  approved.value = true
}

function submit() {
  if (!canSubmit.value) return
  ordersStore.submitOrder(props.asset, side.value, units.value, limitPrice.value)
  approved.value = false
}

function cancel() {
  if (activeOrder.value) ordersStore.cancelOrder(activeOrder.value.id)
}

function placeAnother() {
  units.value = 1
  limitPrice.value = props.asset.nav
  approved.value = false
  dismissed.value = true
}

const resultCopy = computed(() => {
  const order = activeOrder.value
  if (!order) return ''
  switch (order.status) {
    case 'settled':
      return `Filled ${order.units} ${props.asset.symbol} at your limit of ${formatCurrency(order.limitPrice, props.asset.currency)}.`
    case 'partially_filled':
      return `${order.filledUnits} of ${order.units} units filled. ${formatCurrency(order.refundAmount, props.asset.currency)} ${order.side === 'buy' ? 'refunded' : 'returned'} for the unfilled remainder.`
    case 'unmatched':
      return `This order didn't clear the round. Refund of ${formatCurrency(order.refundAmount, props.asset.currency)} is processing.`
    case 'refunded':
      return `${formatCurrency(order.refundAmount, props.asset.currency)} ${order.side === 'buy' ? 'refunded to your wallet' : 'returned'}.`
    case 'cancelled':
      return `Cancelled before the round closed. ${formatCurrency(order.refundAmount, props.asset.currency)} released back to you.`
    default:
      return ''
  }
})
</script>

<template>
  <div class="rounded-lg border border-hairline bg-surface p-5">
    <h2 class="mb-4 text-sm font-semibold text-ink">Place Order</h2>

    <div v-if="!wallet.connected" class="rounded-md border border-hairline bg-page p-4 text-center">
      <p class="text-sm font-medium text-ink">Connect your wallet to trade</p>
      <p class="mt-1 text-sm text-ink-secondary">Orders settle through Agora's periodic batch auction rounds.</p>
      <button
        type="button"
        class="mt-3 rounded-full bg-primary px-4 py-2 text-sm font-semibold text-white transition hover:bg-primary/90"
        @click="wallet.connect()"
      >
        Connect Wallet
      </button>
    </div>

    <div v-else-if="wallet.network === 'wrong'" class="rounded-md border border-critical/30 bg-critical/5 p-4 text-center">
      <p class="text-sm font-medium text-critical">Wrong network</p>
      <p class="mt-1 text-sm text-ink-secondary">Switch to Arbitrum One to trade tokenized assets on Agora.</p>
      <button
        type="button"
        class="mt-3 rounded-full bg-primary px-4 py-2 text-sm font-semibold text-white transition hover:bg-primary/90"
        @click="wallet.switchNetwork()"
      >
        Switch to Arbitrum One
      </button>
    </div>

    <div v-else-if="!marketOpen" class="rounded-md border border-hairline bg-page p-4">
      <p class="text-sm font-medium text-critical">Market {{ asset.marketStatus }}</p>
      <p class="mt-1 text-sm text-ink-secondary">{{ asset.rules.transferRestrictions }}</p>
    </div>

    <div v-else-if="!eligible" class="rounded-md border border-hairline bg-page p-4">
      <p class="text-sm font-medium text-critical">You're not eligible to trade this asset</p>
      <p class="mt-1 text-sm text-ink-secondary">{{ reason }}</p>
    </div>

    <div v-else-if="activeOrder && !showForm" class="space-y-3">
      <div class="flex items-center justify-between">
        <OrderStatusBadge :status="activeOrder.status" />
        <span v-if="activeOrder.status === 'pending'" class="text-xs tabular-nums text-ink-muted">
          Round closes in {{ formatCountdown(secondsRemaining) }}
        </span>
      </div>

      <dl class="space-y-1 text-sm">
        <div class="flex justify-between">
          <dt class="text-ink-muted">{{ activeOrder.side === 'buy' ? 'Buying' : 'Selling' }}</dt>
          <dd class="tabular-nums text-ink">{{ activeOrder.units }} {{ asset.symbol }}</dd>
        </div>
        <div class="flex justify-between">
          <dt class="text-ink-muted">Limit price</dt>
          <dd class="tabular-nums text-ink">{{ formatCurrency(activeOrder.limitPrice, asset.currency) }}</dd>
        </div>
      </dl>

      <p v-if="activeOrder.status === 'pending'" class="text-xs text-ink-muted">
        Orders enter this round and settle once it closes — this isn't an instant trade.
      </p>
      <p v-else class="rounded-md bg-page px-3 py-2 text-xs text-ink-secondary">{{ resultCopy }}</p>

      <button
        v-if="activeOrder.status === 'pending'"
        type="button"
        class="w-full rounded-md border border-hairline py-2 text-sm font-medium text-ink-secondary transition hover:border-critical hover:text-critical"
        @click="cancel"
      >
        Cancel Order
      </button>
      <button
        v-else
        type="button"
        class="w-full rounded-md border border-hairline py-2 text-sm font-medium text-ink-secondary transition hover:border-primary hover:text-primary"
        @click="placeAnother"
      >
        Place Another Order
      </button>
    </div>

    <div v-else-if="roundStatus !== 'open'" class="rounded-md border border-hairline bg-page p-4 text-center">
      <p class="text-sm font-medium text-ink">This round is closed</p>
      <p class="mt-1 text-sm text-ink-secondary">New orders reopen with the next batch auction round.</p>
    </div>

    <form v-else class="space-y-3" @submit.prevent="submit">
      <div class="flex rounded-md border border-hairline p-1 text-sm">
        <button
          type="button"
          class="flex-1 rounded px-3 py-1.5 font-medium transition"
          :class="side === 'buy' ? 'bg-good text-white' : 'text-ink-secondary'"
          @click="side = 'buy'"
        >
          Buy
        </button>
        <button
          type="button"
          class="flex-1 rounded px-3 py-1.5 font-medium transition"
          :class="side === 'sell' ? 'bg-critical text-white' : 'text-ink-secondary'"
          @click="side = 'sell'"
        >
          Sell
        </button>
      </div>

      <TokenAmountInput label="Amount" :token="asset.symbol" editable :model-value="units" @update:model-value="units = $event" />

      <label class="block">
        <span class="text-xs font-medium tracking-wide text-ink-muted">LIMIT PRICE</span>
        <div class="mt-1 flex items-center justify-between gap-2 rounded-md border border-hairline bg-page p-3">
          <input
            v-model.number="limitPrice"
            type="number"
            min="0"
            step="any"
            class="w-full bg-transparent text-lg font-semibold tabular-nums text-ink focus:outline-none"
          />
          <span class="shrink-0 rounded-full border border-hairline px-2.5 py-1 text-xs font-medium text-ink-secondary">
            {{ asset.currency }}
          </span>
        </div>
      </label>

      <dl class="space-y-1 text-xs text-ink-muted">
        <div class="flex justify-between">
          <dt>Reference NAV</dt>
          <dd class="tabular-nums text-ink-secondary">{{ formatCurrency(asset.nav, asset.currency) }}</dd>
        </div>
        <div class="flex justify-between">
          <dt>Max total if filled</dt>
          <dd class="tabular-nums text-ink-secondary">{{ formatCurrency(estimatedTotal, asset.currency) }}</dd>
        </div>
        <div class="flex justify-between">
          <dt>Round closes in</dt>
          <dd class="tabular-nums text-ink-secondary">{{ formatCountdown(secondsRemaining) }}</dd>
        </div>
      </dl>

      <p class="rounded-md bg-page px-3 py-2 text-xs text-ink-secondary">
        This order enters the current batch auction round and clears against the round's uniform price once it
        closes — it will settle later, not immediately.
      </p>

      <p v-if="belowMinInvestment" class="text-xs text-critical">
        Minimum investment is {{ formatCurrency(asset.minInvestment, asset.currency) }}.
      </p>

      <button
        v-if="!approved"
        type="button"
        class="w-full rounded-md border border-primary py-2 text-sm font-medium text-primary transition hover:bg-primary-soft disabled:opacity-40"
        :disabled="units <= 0 || belowMinInvestment"
        @click="approve"
      >
        Approve {{ escrowToken }} for Escrow
      </button>
      <button
        v-else
        type="submit"
        class="w-full rounded-md bg-primary py-2 text-sm font-medium text-white transition disabled:opacity-40"
        :disabled="!canSubmit"
      >
        Submit {{ side === 'buy' ? 'Buy' : 'Sell' }} Order
      </button>
    </form>

    <div class="mt-4 rounded-md bg-page p-3">
      <p class="text-xs font-semibold text-ink">Regulatory &amp; Transfer Restrictions</p>
      <p class="mt-1 text-xs text-ink-secondary">{{ asset.rules.transferRestrictions }}</p>
    </div>
  </div>
</template>
