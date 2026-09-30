<script setup lang="ts">
import { computed } from 'vue'
import type { TokenizedAsset } from '@/types/market'
import type { Quote } from '@/utils/quote'
import type { ExecutionOutcome } from '@/execution/swapExecutor'
import { TARGET_CHAIN_EXPLORER_NAME, explorerAddressUrl, explorerTxUrl } from '@/config/chain'
import { formatCurrency, truncateAddress } from '@/utils/format'

const props = defineProps<{
  asset: TokenizedAsset
  /** The quote the investor accepted. */
  quote: Quote
  /** What the chain actually did. */
  outcome: ExecutionOutcome
  wallet: string
}>()

defineEmits<{ again: []; portfolio: [] }>()

const money = (value: number) => formatCurrency(value, props.asset.currency, 4)
const tokens = (value: number) => `${value.toLocaleString('en-US', { maximumFractionDigits: 6 })} ${props.asset.symbol}`

// The receipt reports what settled. Where the transfer logs gave exact amounts
// those win over the quote, which was only ever an estimate.
const paid = computed(() => props.outcome.amountIn ?? props.quote.amountIn)
const received = computed(() => props.outcome.amountOut ?? props.quote.amountOut)
const estimated = computed(() => props.outcome.amountIn === null || props.outcome.amountOut === null)

const assetAmount = computed(() => (props.quote.side === 'buy' ? received.value : paid.value))
const quoteAmount = computed(() => (props.quote.side === 'buy' ? paid.value : received.value))
const executionPrice = computed(() =>
  assetAmount.value > 0 ? quoteAmount.value / assetAmount.value : props.quote.executionPrice,
)

const settledAt = computed(() =>
  new Date(props.outcome.timestamp * 1000).toLocaleString('en-US', {
    dateStyle: 'medium',
    timeStyle: 'short',
  }),
)

const txUrl = computed(() => explorerTxUrl(props.outcome.hash))
const walletUrl = computed(() => explorerAddressUrl(props.wallet))
const explorerName = computed(() => TARGET_CHAIN_EXPLORER_NAME ?? 'the explorer')

interface Row {
  label: string
  value: string
  mono?: boolean
}

const rows = computed<Row[]>(() => [
  { label: 'Asset', value: `${props.asset.name} (${props.asset.symbol})` },
  { label: 'Side', value: props.quote.side === 'buy' ? `Bought ${props.asset.symbol}` : `Sold ${props.asset.symbol}` },
  { label: 'You paid', value: props.quote.side === 'buy' ? money(paid.value) : tokens(paid.value) },
  { label: 'You received', value: props.quote.side === 'buy' ? tokens(received.value) : money(received.value) },
  { label: 'Execution price', value: `${money(executionPrice.value)} per ${props.asset.symbol}` },
  {
    label: 'Fee',
    value: `${props.quote.feeBps.toFixed(1)} bps (${
      props.quote.side === 'buy' ? money(props.quote.feeAmount) : tokens(props.quote.feeAmount)
    })`,
  },
  { label: 'Price impact', value: `${props.quote.priceImpactPct.toFixed(3)}%` },
  { label: 'Wallet', value: truncateAddress(props.wallet), mono: true },
  { label: 'Settled', value: settledAt.value },
])
</script>

<template>
  <div class="rounded-md border border-primary/30 bg-primary/5 p-4" role="status">
    <div class="flex items-start gap-2.5">
      <span class="mt-1.5 size-1.5 shrink-0 rounded-full bg-good" aria-hidden="true" />
      <div class="min-w-0 flex-1">
        <h3 class="text-sm font-semibold text-success">Trade confirmed</h3>
        <p class="mt-1 text-xs text-ink-secondary">Settled on-chain in block {{ outcome.blockNumber.toString() }}.</p>
      </div>
    </div>

    <dl class="mt-4 space-y-2 border-t border-primary/20 pt-3 text-xs">
      <div v-for="row in rows" :key="row.label" class="flex items-baseline justify-between gap-3">
        <dt class="shrink-0 text-ink-muted">{{ row.label }}</dt>
        <dd class="min-w-0 truncate text-right tabular-nums text-ink" :class="row.mono ? 'font-mono' : ''">
          {{ row.value }}
        </dd>
      </div>

      <div class="flex items-baseline justify-between gap-3">
        <dt class="shrink-0 text-ink-muted">Transaction</dt>
        <dd class="min-w-0 truncate text-right">
          <a
            v-if="txUrl"
            :href="txUrl"
            target="_blank"
            rel="noopener noreferrer"
            class="rounded font-mono text-primary hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          >
            {{ truncateAddress(outcome.hash, 10, 8) }}
          </a>
          <span v-else class="font-mono text-ink">{{ truncateAddress(outcome.hash, 10, 8) }}</span>
        </dd>
      </div>
    </dl>

    <p v-if="estimated" class="mt-2 text-[11px] leading-relaxed text-ink-muted">
      Amounts shown are from your accepted quote — this transaction's transfer logs could not be read back.
    </p>

    <div class="mt-4 flex flex-wrap gap-2 border-t border-primary/20 pt-3">
      <button
        type="button"
        class="rounded-full bg-primary px-3.5 py-1.5 text-xs font-semibold text-on-accent transition hover:brightness-110 focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        @click="$emit('again')"
      >
        Trade again
      </button>
      <button
        type="button"
        class="rounded-full border border-hairline px-3.5 py-1.5 text-xs font-medium text-ink transition hover:border-primary/60 hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        @click="$emit('portfolio')"
      >
        View portfolio
      </button>
      <a
        v-if="txUrl"
        :href="txUrl"
        target="_blank"
        rel="noopener noreferrer"
        class="rounded-full border border-hairline px-3.5 py-1.5 text-xs font-medium text-ink transition hover:border-primary/60 hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
      >
        Open in {{ explorerName }}
      </a>
      <a
        v-if="walletUrl"
        :href="walletUrl"
        target="_blank"
        rel="noopener noreferrer"
        class="sr-only focus:not-sr-only focus:rounded-full focus:border focus:border-hairline focus:px-3.5 focus:py-1.5 focus:text-xs focus:text-ink"
      >
        View wallet in {{ explorerName }}
      </a>
    </div>
  </div>
</template>
