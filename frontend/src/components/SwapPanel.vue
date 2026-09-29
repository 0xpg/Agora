<script setup lang="ts">
import { computed, ref, watch } from 'vue'
import type { Investor, TokenizedAsset } from '@/types/market'
import { useWalletStore } from '@/stores/wallet'
import { TARGET_CHAIN_NAME } from '@/config/chain'
import { eligibilityReason, eligibilityState } from '@/composables/useEligibility'
import { formatCurrency } from '@/utils/format'
import TokenAmountInput from '@/components/TokenAmountInput.vue'

const props = defineProps<{ asset: TokenizedAsset; investor: Investor }>()
const wallet = useWalletStore()
const side = ref<'buy' | 'sell'>('buy')
const units = ref(1)
const approved = ref(false)
const submitted = ref(false)
const state = computed(() => eligibilityState(props.asset, props.investor))
const reason = computed(() => eligibilityReason(props.asset, props.investor))
const total = computed(() => units.value * props.asset.lastPrice)
const canSwap = computed(() => wallet.canTransact && approved.value && units.value > 0)

watch(() => props.asset.id, () => {
  side.value = 'buy'
  units.value = 1
  approved.value = false
  submitted.value = false
})
</script>

<template>
  <div class="rounded-lg border border-hairline bg-surface p-5">
    <h2 class="mb-4 text-sm font-semibold text-ink">Swap</h2>

    <div v-if="!wallet.connected" class="rounded-md border border-hairline bg-page p-4 text-center">
      <p class="text-sm font-medium text-ink">Connect your wallet to trade</p>
      <p class="mt-1 text-sm text-ink-secondary">Swaps execute against Agora's permissioned Uniswap v4 pool.</p>
      <button type="button" class="mt-3 rounded-full bg-primary px-4 py-2 text-sm font-semibold text-on-accent disabled:opacity-50"
        :disabled="wallet.unavailable || !wallet.ready || wallet.connecting" @click="wallet.connect()">
        {{ wallet.connecting ? 'Connecting…' : 'Connect Wallet' }}
      </button>
    </div>

    <div v-else-if="!wallet.canTransact" class="rounded-md border border-critical/30 bg-critical/5 p-4 text-center">
      <p class="text-sm font-medium text-critical">Wrong network</p>
      <button type="button" class="mt-3 rounded-full bg-primary px-4 py-2 text-sm font-semibold text-on-accent"
        @click="wallet.switchToTargetChain()">Switch to {{ TARGET_CHAIN_NAME }}</button>
    </div>

    <div v-else-if="asset.marketStatus !== 'open'" class="rounded-md bg-page p-4 text-sm text-critical">
      Market {{ asset.marketStatus }}.
    </div>

    <div v-else-if="state !== 'eligible'" class="rounded-md bg-page p-4">
      <p class="text-sm font-medium text-critical">You're not eligible to trade this asset</p>
      <p class="mt-1 text-sm text-ink-secondary">{{ reason }}</p>
    </div>

    <div v-else class="space-y-3">
      <div class="flex rounded-md border border-hairline p-1 text-sm">
        <button v-for="choice in ['buy', 'sell'] as const" :key="choice" type="button"
          class="flex-1 rounded px-3 py-1.5 font-medium capitalize"
          :class="side === choice ? (choice === 'buy' ? 'bg-good text-on-accent' : 'bg-critical text-on-accent') : 'text-ink-secondary'"
          @click="side = choice; approved = false; submitted = false">{{ choice }}</button>
      </div>

      <TokenAmountInput label="Amount" :token="asset.symbol" editable :model-value="units" @update:model-value="units = $event" />

      <dl class="space-y-1 text-xs text-ink-muted">
        <div class="flex justify-between"><dt>Pool price</dt><dd>{{ formatCurrency(asset.lastPrice, asset.currency) }}</dd></div>
        <div class="flex justify-between"><dt>Reference NAV</dt><dd>{{ formatCurrency(asset.nav, asset.currency) }}</dd></div>
        <div class="flex justify-between"><dt>Estimated total</dt><dd>{{ formatCurrency(total, asset.currency) }}</dd></div>
      </dl>

      <p class="rounded-md bg-page px-3 py-2 text-xs text-ink-secondary">
        The swap reverts if NAV is stale or execution would move the pool outside its issuer-defined NAV band.
      </p>

      <button v-if="!approved" type="button" class="w-full rounded-md border border-primary py-2 text-sm font-medium text-primary"
        :disabled="units <= 0" @click="approved = true">Approve {{ side === 'buy' ? asset.currency : asset.symbol }}</button>
      <button v-else type="button" class="w-full rounded-md bg-primary py-2 text-sm font-medium text-on-accent disabled:opacity-40"
        :disabled="!canSwap" @click="submitted = true">Swap {{ side === 'buy' ? 'into' : 'from' }} {{ asset.symbol }}</button>
      <p v-if="submitted" class="text-xs text-warning">Demo only: connect the v4 router transaction before deployment.</p>
    </div>
  </div>
</template>
