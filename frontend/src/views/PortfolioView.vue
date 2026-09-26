<script setup lang="ts">
import { RouterLink } from 'vue-router'
import { mockInvestor } from '@/data/mockInvestor'
import { useWalletStore } from '@/stores/wallet'
import { ELIGIBILITY_TIER_LABEL } from '@/types/market'
import { truncateAddress } from '@/utils/format'

const wallet = useWalletStore()
</script>

<template>
  <div class="mx-auto max-w-6xl px-6 py-8">
    <div class="mb-6 flex flex-col gap-1">
      <h1 class="text-xl font-semibold text-ink">Portfolio</h1>
      <p class="text-sm text-ink-muted">Your identity, eligibility, and holdings.</p>
    </div>

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
        <div class="text-xs text-ink-muted">KYC Status</div>
        <div class="mt-1 flex items-center gap-1.5 text-sm font-semibold text-ink">
          <span class="h-1.5 w-1.5 rounded-full" :class="mockInvestor.kycStatus === 'verified' ? 'bg-good' : 'bg-warning'" />
          {{ mockInvestor.kycStatus }}
        </div>
      </div>
      <div class="rounded-lg border border-hairline bg-surface p-4">
        <div class="text-xs text-ink-muted">Wallet</div>
        <div class="mt-1 text-sm font-semibold tabular-nums text-ink">
          {{ wallet.address ? truncateAddress(wallet.address) : 'Not connected' }}
        </div>
      </div>
    </div>

    <div class="mt-6 rounded-lg border border-hairline bg-surface p-8 text-center">
      <p class="text-sm font-medium text-ink">No positions yet</p>
      <p class="mt-1 text-xs text-ink-muted">Trades you settle will show up here.</p>
      <RouterLink to="/markets" class="mt-3 inline-block text-sm text-primary hover:underline">Browse Markets &rarr;</RouterLink>
    </div>
  </div>
</template>
