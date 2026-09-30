<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import type { Investor, TokenizedAsset } from '@/types/market'
import { useWalletStore } from '@/stores/wallet'
import { TARGET_CHAIN_NAME } from '@/config/chain'
import { eligibilityReason, eligibilityState } from '@/composables/useEligibility'
import { useNow } from '@/composables/useNow'
import {
  createSimulatedExecutor,
  useSwapTransaction,
  type SwapRequest,
} from '@/composables/useSwapTransaction'
import { createDemoMarketExecutor } from '@/composables/useDemoMarketExecutor'
import { assessSwap, maxPayAmount, type QuoteMode, type SwapSide } from '@/utils/quote'
import { formatAge, formatCurrency } from '@/utils/format'
import TokenAmountInput from '@/components/TokenAmountInput.vue'
import QuoteBreakdown from '@/components/QuoteBreakdown.vue'
import PolicyNotice from '@/components/PolicyNotice.vue'

const props = defineProps<{ asset: TokenizedAsset; investor: Investor }>()
const emit = defineEmits<{ 'update:postSwapPrice': [value: number | undefined] }>()

const wallet = useWalletStore()
const now = useNow()

const SLIPPAGE_PRESETS = [10, 50, 100] as const

const side = ref<SwapSide>('buy')
const mode = ref<QuoteMode>('exactIn')
/** The figure typed into whichever field is driving the quote. */
const amount = ref<number | null>(null)
const slippageBps = ref<number>(50)
const showSettings = ref(false)

const eligibility = computed(() => eligibilityState(props.asset, props.investor))
const eligibilityDetail = computed(() => eligibilityReason(props.asset, props.investor))

const assessment = computed(() =>
  assessSwap({
    asset: props.asset,
    side: side.value,
    mode: mode.value,
    amount: amount.value ?? 0,
    slippageBps: slippageBps.value,
    now: now.value,
  }),
)

const quote = computed(() => assessment.value.quote)
const poolBlocker = computed(() => assessment.value.blockers.find((blocker) => blocker.poolWide) ?? null)
// A pool-wide refusal already stops everything, so the narrower reason a
// particular trade would also fail is noise on top of it.
const tradeBlocker = computed(() =>
  poolBlocker.value ? null : (assessment.value.blockers.find((blocker) => !blocker.poolWide) ?? null),
)

// Both legs read off the quote, except the one being typed into — that one keeps
// showing exactly what was typed.
const payAmount = computed(() => (mode.value === 'exactIn' ? amount.value : (quote.value?.amountIn ?? null)))
const receiveAmount = computed(() => (mode.value === 'exactOut' ? amount.value : (quote.value?.amountOut ?? null)))

const payToken = computed(() => (side.value === 'buy' ? props.asset.currency : props.asset.symbol))
const receiveToken = computed(() => (side.value === 'buy' ? props.asset.symbol : props.asset.currency))

function setPay(value: number | null) {
  mode.value = 'exactIn'
  amount.value = value
}

function setReceive(value: number | null) {
  mode.value = 'exactOut'
  amount.value = value
}

const executorOptions = {
  // The pool can refuse between quote and signature. This is the same check the
  // panel renders, re-run at the moment of submission.
  preflight: () => {
    const refusal = assessment.value.blockers[0]
    if (!refusal) return null
    return { title: refusal.title, detail: refusal.detail, retryable: false }
  },
}
const executor = props.asset.id === 'agora-demo-note'
  ? createDemoMarketExecutor(wallet, executorOptions)
  : createSimulatedExecutor(executorOptions)

const {
  stage: txStage,
  txHash,
  failure: txFailure,
  busy: txBusy,
  simulated,
  needsApproval: allowanceMissing,
  approve,
  submit,
  reset: resetTx,
} = useSwapTransaction(executor)

function selectSide(choice: SwapSide) {
  if (side.value === choice) return
  side.value = choice
  // The figure meant one token a moment ago; carrying it over would silently
  // change what it means, so the quote starts again.
  amount.value = null
  mode.value = 'exactIn'
  resetTx()
}

function flipSide() {
  selectSide(side.value === 'buy' ? 'sell' : 'buy')
}

const maxPay = computed(() => maxPayAmount(props.asset, side.value, slippageBps.value, now.value))

const secondaryPay = computed(() => {
  if (side.value === 'buy' || payAmount.value === null) return ''
  return `≈ ${formatCurrency(payAmount.value * props.asset.lastPrice, props.asset.currency)}`
})

const secondaryReceive = computed(() => {
  if (side.value === 'sell' || receiveAmount.value === null) return ''
  return `≈ ${formatCurrency(receiveAmount.value * props.asset.lastPrice, props.asset.currency)}`
})

const navAge = computed(() => formatAge(assessment.value.navAgeSeconds))


const request = computed<SwapRequest | null>(() => {
  const current = quote.value
  if (!current) return null
  return {
    assetId: props.asset.id,
    side: side.value,
    mode: mode.value,
    amountIn: current.amountIn,
    amountOut: current.amountOut,
    bound: current.slippageBound,
    slippageBps: slippageBps.value,
    sqrtPriceLimitX96: BigInt(Math.floor(Math.sqrt(
      current.postSwapPrice * (side.value === 'buy' ? 1 + slippageBps.value / 10_000 : 1 - slippageBps.value / 10_000),
    ) * 2 ** 96)),
  }
})

const needsApproval = computed(() => (request.value ? allowanceMissing(request.value) : true))
const canSubmit = computed(() => wallet.canTransact && assessment.value.tradable && request.value !== null)

const actionLabel = computed(() => {
  switch (txStage.value) {
    case 'approve_signing':
      return 'Confirm in your wallet…'
    case 'approve_confirming':
      return `Approving ${payToken.value}…`
    case 'swap_signing':
      return 'Confirm in your wallet…'
    case 'swap_confirming':
      return 'Submitting swap…'
    default:
      return needsApproval.value
        ? `Approve ${payToken.value}`
        : side.value === 'buy'
          ? `Buy ${props.asset.symbol}`
          : `Sell ${props.asset.symbol}`
  }
})

async function onAction() {
  if (!request.value) return
  if (needsApproval.value) {
    await approve(request.value)
    return
  }
  await submit(request.value)
}

// The trade page draws the quoted price onto its range meter.
watch(
  () => quote.value?.postSwapPrice,
  (value) => emit('update:postSwapPrice', value),
  { immediate: true },
)

watch(
  () => props.asset.id,
  () => {
    side.value = 'buy'
    mode.value = 'exactIn'
    amount.value = null
    resetTx()
  },
)

// A change to the trade invalidates a finished one; the receipt should not
// linger over a quote it no longer describes.
watch([() => amount.value, () => mode.value, () => slippageBps.value], () => {
  if (txStage.value === 'confirmed' || txStage.value === 'failed') resetTx()
})
</script>

<template>
  <div class="rounded-lg border border-hairline bg-surface p-5">
    <div class="mb-4 flex items-center justify-between gap-2">
      <h2 class="text-sm font-semibold text-ink">Swap</h2>
      <button
        type="button"
        class="rounded px-1.5 py-0.5 text-[11px] font-medium text-ink-muted hover:text-ink"
        :aria-expanded="showSettings"
        @click="showSettings = !showSettings"
      >
        Slippage {{ (slippageBps / 100).toFixed(2) }}%
      </button>
    </div>

    <div v-if="showSettings" class="mb-4 rounded-md border border-hairline bg-page p-3">
      <p class="text-[11px] font-medium tracking-wide text-ink-muted">Slippage tolerance</p>
      <p class="mt-1 text-xs text-ink-secondary">
        The pool re-prices between your quote and your transaction. Below this bound the swap reverts instead of
        settling worse than quoted.
      </p>
      <div class="mt-2 flex gap-1.5">
        <button
          v-for="preset in SLIPPAGE_PRESETS"
          :key="preset"
          type="button"
          class="rounded-md border px-2.5 py-1 text-xs font-medium tabular-nums transition"
          :class="
            slippageBps === preset
              ? 'border-primary/60 bg-primary/10 text-primary'
              : 'border-hairline text-ink-secondary hover:text-ink'
          "
          @click="slippageBps = preset"
        >
          {{ (preset / 100).toFixed(2) }}%
        </button>
      </div>
    </div>

    <!-- Gates, in the order they actually bind. -->
    <div v-if="!wallet.connected" class="rounded-md border border-hairline bg-page p-4 text-center">
      <p class="text-sm font-medium text-ink">Connect your wallet to trade</p>
      <p class="mt-1 text-sm text-ink-secondary">
        Swaps settle immediately against this asset's NAV-anchored liquidity pool.
      </p>
      <button
        type="button"
        class="mt-3 rounded-full bg-primary px-4 py-2 text-sm font-semibold text-on-accent disabled:opacity-50"
        :disabled="wallet.unavailable || !wallet.ready || wallet.connecting"
        @click="wallet.connect()"
      >
        {{ wallet.connecting ? 'Connecting…' : 'Connect Wallet' }}
      </button>
      <p v-if="wallet.error" class="mt-2 text-xs text-critical">{{ wallet.error }}</p>
    </div>

    <PolicyNotice
      v-else-if="!wallet.canTransact"
      tone="critical"
      title="Wrong network"
      :detail="`Agora's pools live on ${TARGET_CHAIN_NAME}. Switch networks to trade.`"
    >
      <button
        type="button"
        class="mt-2 rounded-full bg-primary px-4 py-1.5 text-sm font-semibold text-on-accent disabled:opacity-50"
        :disabled="wallet.switching"
        @click="wallet.switchToTargetChain()"
      >
        {{ wallet.switching ? 'Switching…' : `Switch to ${TARGET_CHAIN_NAME}` }}
      </button>
    </PolicyNotice>

    <PolicyNotice
      v-else-if="eligibility !== 'eligible'"
      tone="critical"
      title="You're not eligible to trade this asset"
      :detail="eligibilityDetail"
    />

    <div v-else class="space-y-3">
      <PolicyNotice
        v-if="poolBlocker"
        :tone="poolBlocker.code === 'paused' ? 'warning' : 'critical'"
        :title="poolBlocker.title"
        :detail="poolBlocker.detail"
      />

      <div class="flex rounded-md border border-hairline p-1 text-sm">
        <button
          v-for="choice in (['buy', 'sell'] as const)"
          :key="choice"
          type="button"
          class="flex-1 rounded px-3 py-1.5 font-medium capitalize transition"
          :class="
            side === choice
              ? choice === 'buy'
                ? 'bg-good text-on-accent'
                : 'bg-critical text-on-accent'
              : 'text-ink-secondary hover:text-ink'
          "
          @click="selectSide(choice)"
        >
          {{ choice }}
        </button>
      </div>

      <TokenAmountInput
        label="You pay"
        :token="payToken"
        :model-value="payAmount"
        :secondary="secondaryPay"
        :max="maxPay"
        :invalid="tradeBlocker !== null"
        @update:model-value="setPay"
      />

      <div class="flex items-center justify-center">
        <button
          type="button"
          class="rounded-full border border-hairline bg-page p-1.5 text-ink-muted transition hover:text-ink"
          :aria-label="side === 'buy' ? `Switch to selling ${asset.symbol}` : `Switch to buying ${asset.symbol}`"
          @click="flipSide"
        >
          <svg viewBox="0 0 16 16" class="size-3.5" fill="none" stroke="currentColor" stroke-width="1.5">
            <path d="M5 2.5v11M5 13.5 2.5 11M11 13.5v-11M11 2.5 13.5 5" stroke-linecap="round" />
          </svg>
        </button>
      </div>

      <TokenAmountInput
        label="You receive"
        :token="receiveToken"
        :model-value="receiveAmount"
        :secondary="secondaryReceive"
        @update:model-value="setReceive"
      />

      <p class="text-[11px] text-ink-muted">
        <template v-if="mode === 'exactIn'">
          Exact input — you pay {{ payToken }} exactly, and receive at least the quoted {{ receiveToken }}.
        </template>
        <template v-else>
          Exact output — you receive {{ receiveToken }} exactly, and pay at most the quoted {{ payToken }}.
        </template>
      </p>

      <QuoteBreakdown
        v-if="quote"
        :asset="asset"
        :quote="quote"
        :slippage-bps="slippageBps"
        class="rounded-md border border-hairline bg-page p-3"
      />

      <PolicyNotice
        v-for="warning in assessment.warnings"
        :key="warning.code"
        tone="warning"
        :title="warning.title"
        :detail="warning.detail"
      />

      <PolicyNotice
        v-if="tradeBlocker"
        tone="critical"
        :title="tradeBlocker.title"
        :detail="tradeBlocker.detail"
      >
        <button
          v-if="tradeBlocker.maxAmount !== undefined && mode === 'exactIn'"
          type="button"
          class="mt-2 text-xs font-medium text-primary hover:underline"
          @click="setPay(Number((tradeBlocker.maxAmount * 0.999).toFixed(6)))"
        >
          Use the largest amount that clears
        </button>
      </PolicyNotice>

      <!-- Transaction states -->
      <PolicyNotice
        v-if="txStage === 'confirmed'"
        tone="success"
        title="Swap confirmed"
        :detail="
          simulated
            ? 'Simulated settlement — execution is not yet wired to the permissioned router, so nothing settled on-chain.'
            : 'Your swap settled against the pool.'
        "
      >
        <p v-if="txHash" class="mt-1.5 truncate font-mono text-[11px] text-ink-muted">
          {{ txHash }}
        </p>
        <button type="button" class="mt-2 text-xs font-medium text-primary hover:underline" @click="resetTx()">
          Make another swap
        </button>
      </PolicyNotice>

      <PolicyNotice
        v-else-if="txStage === 'failed' && txFailure"
        tone="critical"
        :title="txFailure.title"
        :detail="txFailure.detail"
      >
        <button type="button" class="mt-2 text-xs font-medium text-primary hover:underline" @click="resetTx()">
          Dismiss
        </button>
      </PolicyNotice>

      <PolicyNotice
        v-else-if="txBusy"
        tone="info"
        busy
        :title="actionLabel"
        :detail="
          txStage === 'approve_signing' || txStage === 'swap_signing'
            ? 'Waiting for you to sign in your wallet.'
            : 'Waiting for the network to confirm.'
        "
      />

      <button
        v-else
        type="button"
        class="w-full rounded-md py-2.5 text-sm font-semibold transition disabled:cursor-not-allowed disabled:opacity-40"
        :class="needsApproval ? 'border border-primary text-primary' : 'bg-primary text-on-accent'"
        :disabled="!canSubmit"
        @click="onAction"
      >
        {{ amount === null || amount === 0 ? 'Enter an amount' : actionLabel }}
      </button>

      <p class="text-[11px] leading-relaxed text-ink-muted">
        NAV published {{ navAge }}. The pool refuses swaps that would start or land outside its permitted price range,
        exceed its per-swap limit, or run against a NAV that has gone stale.
      </p>
    </div>
  </div>
</template>
