<script setup lang="ts">
import { computed } from 'vue'
import { RouterLink } from 'vue-router'
import { mockInvestor } from '@/data/mockInvestor'
import { useWalletStore } from '@/stores/wallet'
import { usePortfolioStore } from '@/stores/portfolio'
import { useTradeHistoryStore, type TradeRecord } from '@/stores/tradeHistory'
import { ELIGIBILITY_TIER_LABEL } from '@/types/market'
import { TARGET_CHAIN_EXPLORER_NAME, TARGET_CHAIN_NAME, explorerTxUrl } from '@/config/chain'
import { DEPLOYED_MARKETS } from '@/execution/market'
import { formatCurrency, truncateAddress } from '@/utils/format'
import PolicyNotice from '@/components/PolicyNotice.vue'

const wallet = useWalletStore()
const portfolio = usePortfolioStore()
const history = useTradeHistoryStore()

const held = computed(() => portfolio.positions.filter((position) => position.balance > 0))
const explorerName = computed(() => TARGET_CHAIN_EXPLORER_NAME ?? 'explorer')

const STATUS_STYLE: Record<TradeRecord['status'], { label: string; dot: string; text: string }> = {
  confirmed: { label: 'Confirmed', dot: 'bg-good', text: 'text-success' },
  reverted: { label: 'Reverted', dot: 'bg-critical', text: 'text-critical' },
  rejected: { label: 'Declined', dot: 'bg-warning', text: 'text-warning' },
  failed: { label: 'Failed', dot: 'bg-critical', text: 'text-critical' },
}

function when(timestamp: number): string {
  return new Date(timestamp * 1000).toLocaleString('en-US', { dateStyle: 'medium', timeStyle: 'short' })
}

function tokens(value: number, symbol: string): string {
  return `${value.toLocaleString('en-US', { maximumFractionDigits: 6 })} ${symbol}`
}

function paidLeg(record: TradeRecord): string {
  return record.side === 'buy'
    ? formatCurrency(record.amountIn, record.settlementSymbol, 2)
    : tokens(record.amountIn, record.symbol)
}

function receivedLeg(record: TradeRecord): string {
  return record.side === 'buy'
    ? tokens(record.amountOut, record.symbol)
    : formatCurrency(record.amountOut, record.settlementSymbol, 2)
}
</script>

<template>
  <div class="mx-auto max-w-6xl px-6 py-8">
    <div class="mb-6 flex flex-col gap-1">
      <h1 class="text-xl font-semibold text-ink">Portfolio</h1>
      <p class="text-sm text-ink-muted">Your holdings and trade history on {{ TARGET_CHAIN_NAME }}.</p>
    </div>

    <!-- Identity summary -->
    <div class="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-4">
      <div class="rounded-lg border border-hairline bg-surface p-4">
        <div class="text-xs text-ink-muted">Investor</div>
        <div class="mt-1 text-sm font-semibold text-ink">{{ mockInvestor.name }}</div>
      </div>
      <div class="rounded-lg border border-hairline bg-surface p-4">
        <div class="text-xs text-ink-muted">Tier</div>
        <div class="mt-1 text-sm font-semibold text-ink">{{ ELIGIBILITY_TIER_LABEL[mockInvestor.tier] }}</div>
      </div>
      <div class="rounded-lg border border-hairline bg-surface p-4">
        <div class="text-xs text-ink-muted">Settlement balance</div>
        <div class="mt-1 text-sm font-semibold tabular-nums text-ink">
          <span v-if="portfolio.loading && portfolio.settlementBalance === null" class="text-ink-muted">Loading…</span>
          <span v-else-if="portfolio.settlementBalance === null" class="text-ink-muted">—</span>
          <span v-else>
            {{ portfolio.settlementBalance.toLocaleString('en-US', { maximumFractionDigits: 4 }) }}
            {{ portfolio.settlementSymbol }}
          </span>
        </div>
      </div>
      <div class="rounded-lg border border-hairline bg-surface p-4">
        <div class="text-xs text-ink-muted">Wallet</div>
        <div class="mt-1 text-sm font-semibold tabular-nums text-ink">
          {{ wallet.address ? truncateAddress(wallet.address) : 'Not connected' }}
        </div>
      </div>
    </div>

    <!-- Positions -->
    <section class="mt-8">
      <div class="mb-3 flex items-center justify-between gap-3">
        <h2 class="text-sm font-semibold text-ink">Positions</h2>
        <button
          v-if="wallet.canTransact && portfolio.hasMarkets"
          type="button"
          class="rounded text-xs font-medium text-primary hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:opacity-50"
          :disabled="portfolio.loading"
          @click="portfolio.refresh()"
        >
          {{ portfolio.loading ? 'Refreshing…' : 'Refresh' }}
        </button>
      </div>

      <PolicyNotice
        v-if="!wallet.connected"
        tone="info"
        title="Connect a wallet to see your holdings"
        detail="Positions are read from the chain for whichever wallet is connected."
      />

      <PolicyNotice
        v-else-if="!wallet.onTargetChain"
        tone="warning"
        :title="`Switch to ${TARGET_CHAIN_NAME}`"
        detail="Your holdings live on the chain Agora's markets are deployed to."
      />

      <PolicyNotice
        v-else-if="portfolio.error"
        tone="critical"
        title="Couldn't load your holdings"
        :detail="portfolio.error"
      >
        <button
          type="button"
          class="mt-2 rounded text-xs font-medium text-primary hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          @click="portfolio.refresh()"
        >
          Try again
        </button>
      </PolicyNotice>

      <!-- Loading skeleton, only on a first read with nothing to show yet. -->
      <div v-else-if="portfolio.loading && portfolio.positions.length === 0" class="space-y-2" aria-busy="true">
        <span class="sr-only">Loading your positions…</span>
        <div v-for="n in 2" :key="n" class="h-16 animate-pulse rounded-lg border border-hairline bg-surface" />
      </div>

      <PolicyNotice
        v-else-if="!portfolio.hasMarkets"
        tone="info"
        title="No markets deployed on this network"
        :detail="`Nothing is tradable on ${TARGET_CHAIN_NAME} yet, so there are no positions to hold.`"
      />

      <PolicyNotice v-else-if="held.length === 0" tone="info" title="No positions yet" detail="Assets you buy will appear here.">
        <RouterLink
          to="/markets"
          class="mt-2 inline-block rounded text-xs font-medium text-primary hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
        >
          Browse markets →
        </RouterLink>
      </PolicyNotice>

      <ul v-else class="space-y-2">
        <li
          v-for="position in held"
          :key="position.marketId"
          class="flex flex-wrap items-center justify-between gap-3 rounded-lg border border-hairline bg-surface p-4"
        >
          <div class="min-w-0">
            <div class="flex items-center gap-2">
              <span class="font-semibold text-ink">{{ position.symbol }}</span>
              <span class="truncate text-xs text-ink-muted">{{ position.name }}</span>
            </div>
            <div class="mt-0.5 font-mono text-[11px] text-ink-muted">{{ truncateAddress(position.assetToken) }}</div>
          </div>
          <div class="flex items-center gap-4">
            <div class="text-right">
              <div class="text-xs text-ink-muted">Holding</div>
              <div class="mt-0.5 text-sm font-semibold tabular-nums text-ink">
                {{ position.balance.toLocaleString('en-US', { maximumFractionDigits: 6 }) }} {{ position.symbol }}
              </div>
            </div>
            <RouterLink
              :to="`/trade/${position.marketId}`"
              class="rounded-full border border-hairline px-3 py-1.5 text-xs font-medium text-ink transition hover:border-primary/60 hover:text-primary focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
            >
              Trade
            </RouterLink>
          </div>
        </li>
      </ul>
    </section>

    <!-- Recent trades -->
    <section class="mt-8">
      <div class="mb-3 flex items-center justify-between gap-3">
        <h2 class="text-sm font-semibold text-ink">Recent trades</h2>
        <button
          v-if="history.hasAny"
          type="button"
          class="rounded text-xs font-medium text-ink-muted hover:text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
          @click="history.clear()"
        >
          Clear
        </button>
      </div>

      <PolicyNotice
        v-if="!wallet.connected"
        tone="info"
        title="Connect a wallet to see your trades"
        detail="Trades are recorded against the wallet that made them."
      />

      <PolicyNotice
        v-else-if="!history.hasAny"
        tone="info"
        title="No trades yet"
        detail="Every attempt you make from the Trade page shows up here, including ones that were declined or reverted."
      />

      <ul v-else class="space-y-2">
        <li
          v-for="record in history.records"
          :key="record.id"
          class="rounded-lg border border-hairline bg-surface p-4"
        >
          <div class="flex flex-wrap items-start justify-between gap-x-4 gap-y-2">
            <div class="min-w-0">
              <div class="flex flex-wrap items-center gap-x-2 gap-y-1">
                <span class="text-sm font-semibold text-ink">
                  {{ record.side === 'buy' ? 'Bought' : 'Sold' }} {{ record.symbol }}
                </span>
                <span
                  class="inline-flex items-center gap-1.5 rounded-full border border-hairline px-2 py-0.5 text-[10px] font-medium"
                  :class="STATUS_STYLE[record.status].text"
                >
                  <span class="h-1.5 w-1.5 rounded-full" :class="STATUS_STYLE[record.status].dot" />
                  {{ STATUS_STYLE[record.status].label }}
                </span>
              </div>
              <p v-if="record.status === 'confirmed'" class="mt-1 text-xs tabular-nums text-ink-secondary">
                {{ paidLeg(record) }} → {{ receivedLeg(record) }}
              </p>
              <p v-else-if="record.reason" class="mt-1 text-xs text-ink-secondary">{{ record.reason }}</p>
            </div>
            <div class="text-right text-xs">
              <div class="tabular-nums text-ink-muted">{{ when(record.timestamp) }}</div>
              <a
                v-if="record.hash && explorerTxUrl(record.hash)"
                :href="explorerTxUrl(record.hash)!"
                target="_blank"
                rel="noopener noreferrer"
                class="mt-0.5 inline-block rounded font-mono text-primary hover:underline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary"
              >
                {{ truncateAddress(record.hash, 8, 6) }} ↗
              </a>
              <span v-else-if="!record.hash" class="mt-0.5 block text-ink-muted">Never submitted</span>
            </div>
          </div>
        </li>
      </ul>

      <p v-if="history.hasAny" class="mt-3 text-[11px] leading-relaxed text-ink-muted">
        This list is kept in this browser. A declined or reverted transaction emits nothing on-chain, so it cannot be
        recovered from {{ explorerName }} — trades made on another device will not appear here.
      </p>
    </section>

    <p v-if="DEPLOYED_MARKETS.length > 0" class="mt-8 text-[11px] text-ink-muted">
      Reading {{ DEPLOYED_MARKETS.length }} deployed
      {{ DEPLOYED_MARKETS.length === 1 ? 'market' : 'markets' }} on {{ TARGET_CHAIN_NAME }}.
    </p>
  </div>
</template>
