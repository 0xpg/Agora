<script setup lang="ts">
import { watch } from 'vue'
import { RouterView, useRoute } from 'vue-router'
import AppHeader from '@/components/layout/AppHeader.vue'
import { mockInvestor } from '@/data/mockInvestor'
import { useWalletStore } from '@/stores/wallet'
import { usePortfolioStore } from '@/stores/portfolio'
import { useTradeHistoryStore } from '@/stores/tradeHistory'

const route = useRoute()
const wallet = useWalletStore()
const portfolio = usePortfolioStore()
const history = useTradeHistoryStore()

// Holdings and trade history both belong to whichever wallet is connected, so
// they follow it: read on connect, cleared on disconnect, re-read when the
// wallet switches account or lands on the right chain.
watch(
  [() => wallet.address, () => wallet.onTargetChain],
  ([address]) => {
    history.setWallet(address)
    void portfolio.refresh()
  },
  { immediate: true },
)
</script>

<template>
  <div class="min-h-screen bg-page">
    <AppHeader v-if="route.name !== 'landing'" :investor="mockInvestor" />
    <RouterView />
  </div>
</template>
