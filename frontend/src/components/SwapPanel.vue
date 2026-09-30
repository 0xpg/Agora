<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import { useRouter } from 'vue-router'
import type { Investor, TokenizedAsset } from '@/types/market'
import { useWalletStore } from '@/stores/wallet'
import { usePortfolioStore } from '@/stores/portfolio'
import { useTradeHistoryStore, type TradeStatus } from '@/stores/tradeHistory'
import { TARGET_CHAIN_NAME } from '@/config/chain'
import { eligibilityReason, eligibilityState } from '@/composables/useEligibility'
import { useNow } from '@/composables/useNow'
import { createUnavailableExecutor, useSwapTransaction, type SwapRequest } from '@/composables/useSwapTransaction'
import { createMarketExecutor } from '@/execution/swapExecutor'
import { marketFor } from '@/execution/market'
import { assessSwap, maxPayAmount, type Quote, type QuoteMode, type SwapSide } from '@/utils/quote'
import { formatAge, formatCurrency } from '@/utils/format'
import TokenAmountInput from '@/components/TokenAmountInput.vue'
import QuoteBreakdown from '@/components/QuoteBreakdown.vue'
import PolicyNotice from '@/components/PolicyNotice.vue'
import TradeReceipt from '@/components/TradeReceipt.vue'

const props = defineProps<{ asset: TokenizedAsset; investor: Investor }>()
const emit = defineEmits<{ 'update:postSwapPrice': [value: number | undefined] }>()

const wallet = useWalletStore()
const portfolio = usePortfolioStore()
const history = useTradeHistoryStore()
const router = useRouter()
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

// ---------------------------------------------------------------------------
// Execution

/** The deployed market behind this asset, when one exists on the target chain. */
const market = computed(() => marketFor(props.asset.id))
const tradable = computed(() => market.value !== null)

const executor = computed(() => {
  const deployed = market.value
  if (!deployed) return createUnavailableExecutor()
  return createMarketExecutor(deployed, wallet, {
    // The panel's own assessment, re-run at the moment of submission. The
    // executor then simulates against live pool state on top of this.
    preflight: () => {
      const refusal = assessment.value.blockers[0]
      if (!refusal) return null
      return { kind: 'reverted', title: refusal.title, detail: refusal.detail, retryable: true }
    },
  })
})

const {
  stage: txStage,
  swapHash,
  failure: txFailure,
  outcome,
  nextStep,
  activeStep,
  busy: txBusy,
  refreshSteps,
  runNextStep,
  submit,
  reset: resetTx,
  dismissFailure,
} = useSwapTransaction(() => executor.value)

/** The quote as it stood when the trade was submitted — what the receipt describes. */
const acceptedQuote = ref<Quote | null>(null)

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
    spotPrice: current.spotPrice,
    postSwapPrice: current.postSwapPrice,
    bandLower: assessment.value.active.bandLower,
    bandUpper: assessment.value.active.bandUpper,
  }
})

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

const canSubmit = computed(
  () => wallet.canTransact && tradable.value && assessment.value.tradable && request.value !== null,
)

/** What the primary button says, which is also what is happening right now. */
const actionLabel = computed(() => {
  switch (txStage.value) {
    case 'checking':
      return 'Checking the pool…'
    case 'prepare_signature':
      return `${activeStep.value?.label ?? 'Confirm'} — sign in your wallet…`
    case 'prepare_submitted':
      return `${activeStep.value?.label ?? 'Preparing'}…`
    case 'swap_signature':
      return 'Confirm the swap in your wallet…'
    case 'swap_submitted':
      return 'Waiting for confirmation…'
    default:
      if (nextStep.value) return nextStep.value.label
      return side.value === 'buy' ? `Buy ${props.asset.symbol}` : `Sell ${props.asset.symbol}`
  }
})

/** The plain-language "what is happening" line under each in-flight stage. */
const stageDetail = computed(() => {
  switch (txStage.value) {
    case 'checking':
      return 'Reading live pool state to make sure this trade will be accepted.'
    case 'prepare_signature':
      return activeStep.value?.detail ?? 'Sign the transaction in your wallet.'
    case 'prepare_submitted':
      return 'On its way. Waiting for the network to confirm it.'
    case 'swap_signature':
      return 'Sign the swap in your wallet. Nothing is spent until you do.'
    case 'swap_submitted':
      return 'Submitted. Waiting for the network to include it in a block.'
    default:
      return ''
  }
})

/** The steps still outstanding, shown before anything is signed. */
const stepHint = computed(() => {
  const step = nextStep.value
  if (!step || txBusy.value || txFailure.value) return ''
  return step.detail
})

const failureTone = computed(() => (txFailure.value?.kind === 'rejected' ? 'warning' : 'critical'))

function recordAttempt(status: TradeStatus, hash: string | null, reason?: string, timestamp?: number) {
  const accepted = acceptedQuote.value
  if (!accepted) return
  history.record({
    assetId: props.asset.id,
    symbol: props.asset.symbol,
    settlementSymbol: props.asset.currency,
    side: accepted.side,
    mode: accepted.mode,
    amountIn: outcome.value?.amountIn ?? accepted.amountIn,
    amountOut: outcome.value?.amountOut ?? accepted.amountOut,
    executionPrice: accepted.executionPrice,
    feeBps: accepted.feeBps,
    feeAmount: accepted.feeAmount,
    priceImpactPct: accepted.priceImpactPct,
    hash,
    status,
    reason,
    timestamp: timestamp ?? Math.floor(Date.now() / 1000),
  })
}

async function onAction() {
  const current = request.value
  if (!current || txBusy.value) return

  if (nextStep.value) {
    await runNextStep(current)
    return
  }

  acceptedQuote.value = quote.value
  await submit(current)
}

/** Clears the failure and leaves the entered amounts exactly as they were. */
function retry() {
  dismissFailure()
}

/**
 * Takes the size the pool said it could fill. Applied to whichever field the
 * investor pinned, so the trade keeps its shape.
 */
function useSuggestedAmount(value: number) {
  // A hair under what the chain quoted, so rounding cannot put it back over.
  amount.value = Number((value * 0.999).toFixed(6))
  dismissFailure()
}

function tradeAgain() {
  resetTx()
  amount.value = null
  mode.value = 'exactIn'
  acceptedQuote.value = null
}

function goToPortfolio() {
  void router.push({ name: 'portfolio' })
}

// Once a trade settles, holdings and balances are stale — re-read them rather
// than making anyone reload the page.
watch(txStage, (stage) => {
  if (stage === 'confirmed') {
    recordAttempt('confirmed', swapHash.value, undefined, outcome.value?.timestamp)
    void portfolio.refresh()
    return
  }
  if (stage === 'rejected' || stage === 'reverted' || stage === 'failed') {
    recordAttempt(stage, swapHash.value, txFailure.value?.detail)
    // A revert still consumed gas and may have moved allowances.
    if (stage === 'reverted') void portfolio.refresh()
  }
})

// What is still outstanding depends on the amount and the wallet, so it is
// re-read as the trade changes rather than cached from the first look.
watch(
  [request, () => wallet.address, () => wallet.onTargetChain],
  () => {
    void refreshSteps(request.value)
  },
  { immediate: true },
)

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
    acceptedQuote.value = null
    resetTx()
  },
)

// Editing the trade invalidates a finished one — the receipt must not linger
// over a quote it no longer describes. Editing after a failure is the investor
// correcting it, so the explanation steps aside and the entered amounts stay
// exactly where they are.
watch([amount, mode, slippageBps], () => {
  if (txStage.value === 'confirmed') resetTx()
  else if (txFailure.value) dismissFailure()
})
</script>

<template>
  <div class="rounded-lg border border-hairline bg-surface p-5">
    <div class="mb-4 flex items-center justify-between gap-2">
      <h2 class="text-sm font-semibold text-ink">Swap</h2>
      <button
        type="button"
        class="rounded px-1.5 py-0.5 text-[11px] font-medium text-ink-muted hover:text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        :aria-expanded="showSettings"
        @click="showSettings = !showSettings"
      >
        Slippage {{ (slippageBps / 100).toFixed(2) }}%
      </button>
    </div>

    <div v-if="showSettings" class="mb-4 rounded-md border border-hairline bg-page p-3">
      <p class="text-[11px] font-medium tracking-wide text-ink-muted">Slippage tolerance</p>
      <p class="mt-1 text-xs text-ink-secondary">
        The pool re-prices between your quote and your transaction. Past this bound the swap stops rather than settling
        worse than you accepted.
      </p>
      <div class="mt-2 flex gap-1.5">
        <button
          v-for="preset in SLIPPAGE_PRESETS"
          :key="preset"
          type="button"
          class="rounded-md border px-2.5 py-1 text-xs font-medium tabular-nums transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
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

    <PolicyNotice
      v-else-if="!tradable"
      tone="info"
      title="Not tradable on this network yet"
      :detail="`${asset.name} is listed for reference. No market has been deployed for it on ${TARGET_CHAIN_NAME}, so there is nothing to swap against.`"
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
          class="flex-1 rounded px-3 py-1.5 font-medium capitalize transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          :class="
            side === choice
              ? choice === 'buy'
                ? 'bg-good text-on-accent'
                : 'bg-critical text-on-accent'
              : 'text-ink-secondary hover:text-ink'
          "
          :disabled="txBusy"
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
        :disabled="txBusy"
        :invalid="tradeBlocker !== null"
        @update:model-value="setPay"
      />

      <div class="flex items-center justify-center">
        <button
          type="button"
          class="rounded-full border border-hairline bg-page p-1.5 text-ink-muted transition hover:text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          :aria-label="side === 'buy' ? `Switch to selling ${asset.symbol}` : `Switch to buying ${asset.symbol}`"
          :disabled="txBusy"
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
        :disabled="txBusy"
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

      <PolicyNotice v-if="tradeBlocker" tone="critical" :title="tradeBlocker.title" :detail="tradeBlocker.detail">
        <button
          v-if="tradeBlocker.maxAmount !== undefined && mode === 'exactIn'"
          type="button"
          class="mt-2 rounded text-xs font-medium text-primary hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          @click="setPay(Number((tradeBlocker.maxAmount * 0.999).toFixed(6)))"
        >
          Use the largest amount that clears
        </button>
      </PolicyNotice>

      <!-- Transaction states. Each is announced, so a screen reader follows the
           swap without watching the button. -->
      <TradeReceipt
        v-if="txStage === 'confirmed' && outcome && acceptedQuote && wallet.address"
        :asset="asset"
        :quote="acceptedQuote"
        :outcome="outcome"
        :wallet="wallet.address"
        @again="tradeAgain"
        @portfolio="goToPortfolio"
      />

      <PolicyNotice
        v-else-if="txFailure"
        :tone="failureTone"
        :title="txFailure.title"
        :detail="txFailure.detail"
      >
        <div class="mt-2 flex flex-wrap gap-3">
          <button
            v-if="txFailure.suggestedAmount !== undefined"
            type="button"
            class="rounded text-xs font-medium text-primary hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            @click="useSuggestedAmount(txFailure.suggestedAmount)"
          >
            Use {{ txFailure.suggestedAmount.toLocaleString('en-US', { maximumFractionDigits: 4 }) }} instead
          </button>
          <button
            v-else-if="txFailure.retryable"
            type="button"
            class="rounded text-xs font-medium text-primary hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            @click="retry"
          >
            Try again
          </button>
          <button
            type="button"
            class="rounded text-xs font-medium text-ink-muted hover:text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            @click="tradeAgain"
          >
            Start over
          </button>
        </div>
      </PolicyNotice>

      <PolicyNotice v-else-if="txBusy" tone="info" busy :title="actionLabel" :detail="stageDetail" />

      <button
        v-else
        type="button"
        class="w-full rounded-md py-2.5 text-sm font-semibold transition focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:cursor-not-allowed disabled:opacity-40"
        :class="nextStep ? 'border border-primary text-primary' : 'bg-primary text-on-accent'"
        :disabled="!canSubmit"
        @click="onAction"
      >
        {{ amount === null || amount === 0 ? 'Enter an amount' : actionLabel }}
      </button>

      <p v-if="stepHint" class="text-[11px] leading-relaxed text-ink-muted">{{ stepHint }}</p>

      <p class="text-[11px] leading-relaxed text-ink-muted">
        NAV published {{ navAge }}. The pool refuses swaps that would start or land outside its permitted price range,
        exceed its per-swap limit, or run against a NAV that has gone stale.
      </p>
    </div>
  </div>
</template>
