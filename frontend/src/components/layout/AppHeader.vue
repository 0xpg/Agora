<script setup lang="ts">
import { computed, ref, useId } from 'vue'
import { RouterLink, useRoute, useRouter } from 'vue-router'
import type { Investor } from '@/types/market'
import { mockAssets } from '@/data/mockAssets'
import { useWalletStore } from '@/stores/wallet'
import { TARGET_CHAIN_NAME } from '@/config/chain'
import { formatCompactCurrency, truncateAddress } from '@/utils/format'

defineProps<{
  investor: Investor
}>()

const wallet = useWalletStore()
const route = useRoute()
const router = useRouter()

const totalLiquidity = computed(() => mockAssets.reduce((sum, asset) => sum + asset.liquidity, 0))
const walletLabel = computed(() => (wallet.address ? truncateAddress(wallet.address) : ''))

const mobileNavOpen = ref(false)
const mobileNavId = useId()
const NAV_LINKS = [
  { to: '/markets', label: 'Markets' },
  { to: '/trade', label: 'Trade' },
  { to: '/portfolio', label: 'Portfolio' },
  { to: '/docs', label: 'Docs' },
] as const

// Close the mobile menu whenever a nav link inside it is followed.
function closeMobileNav() {
  mobileNavOpen.value = false
}

// Disconnecting ends the session, so it returns to the logged-out landing page.
async function disconnect() {
  await wallet.disconnect()
  router.push('/')
}
</script>

<template>
  <header class="sticky top-0 z-50 border-b border-hairline bg-page/80 backdrop-blur-md">
    <div class="mx-auto flex max-w-6xl items-center justify-between gap-4 px-6 py-3">
      <div class="flex items-center gap-3">
        <RouterLink to="/" class="flex items-center gap-2">
          <span class="flex h-5 w-5 rotate-45 rounded-[3px] bg-primary shadow-[0_0_16px_var(--color-primary)]" />
          <span class="text-base font-semibold tracking-tight text-ink">Agora</span>
        </RouterLink>
        <span
          class="hidden items-center gap-1.5 whitespace-nowrap rounded-full border border-hairline bg-surface px-2.5 py-1 text-xs text-ink-muted xl:inline-flex"
        >
          <span class="h-1.5 w-1.5 shrink-0 rounded-full bg-good" />
          RWA DEX &middot; {{ TARGET_CHAIN_NAME }}
        </span>
        <nav class="hidden items-center gap-3 text-sm md:flex">
          <RouterLink
            v-for="link in NAV_LINKS"
            :key="link.to"
            :to="link.to"
            class="font-medium text-ink-secondary transition hover:text-primary"
            :class="route.path === link.to ? 'text-primary' : ''"
          >
            {{ link.label }}
          </RouterLink>
        </nav>
      </div>

      <div class="flex items-center gap-2">
        <button
          type="button"
          class="rounded-md p-1.5 text-ink transition hover:bg-surface md:hidden"
          :aria-expanded="mobileNavOpen"
          :aria-controls="mobileNavId"
          aria-label="Toggle navigation menu"
          @click="mobileNavOpen = !mobileNavOpen"
        >
          <svg viewBox="0 0 20 20" fill="none" class="h-5 w-5" aria-hidden="true">
            <path
              v-if="!mobileNavOpen"
              d="M3 5h14M3 10h14M3 15h14"
              stroke="currentColor"
              stroke-width="1.5"
              stroke-linecap="round"
            />
            <path v-else d="M5 5l10 10M15 5L5 15" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" />
          </svg>
        </button>
        <span
          class="hidden shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full border border-hairline bg-surface px-2.5 py-1 text-xs text-ink-secondary md:inline-flex"
        >
          TVL <span class="font-semibold tabular-nums text-ink">{{ formatCompactCurrency(totalLiquidity) }}</span>
        </span>

        <template v-if="!wallet.connected">
          <button
            type="button"
            class="rounded-full bg-primary px-3.5 py-1.5 text-xs font-semibold text-on-accent transition hover:bg-primary/90 disabled:opacity-50"
            :disabled="wallet.unavailable || !wallet.ready || wallet.connecting"
            :aria-busy="!wallet.unavailable && (!wallet.ready || wallet.connecting)"
            @click="wallet.connect()"
          >
            {{ wallet.connecting ? 'Connecting…' : 'Connect Wallet' }}
          </button>
        </template>
        <template v-else>
          <button
            v-if="wallet.wrongNetwork"
            type="button"
            class="inline-flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full border border-critical/40 bg-critical/10 px-2.5 py-1 text-xs font-semibold text-critical transition hover:bg-critical/20 disabled:opacity-50"
            :disabled="wallet.switching"
            :aria-busy="wallet.switching"
            @click="wallet.switchToTargetChain()"
          >
            <span class="h-1.5 w-1.5 shrink-0 rounded-full bg-critical" />
            <span class="hidden md:inline">Switch to {{ TARGET_CHAIN_NAME }}</span>
            <span class="md:hidden">Wrong Network</span>
          </button>
          <span
            v-else
            class="hidden shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full border border-hairline bg-surface px-2.5 py-1 text-xs text-ink-secondary md:inline-flex"
          >
            <span class="h-1.5 w-1.5 shrink-0 rounded-full bg-good" />
            {{ TARGET_CHAIN_NAME }}
          </span>

          <button
            type="button"
            class="inline-flex shrink-0 items-center gap-2 whitespace-nowrap rounded-full border border-hairline bg-surface px-3 py-1.5 text-xs font-medium text-ink transition hover:border-primary/50"
            @click="disconnect()"
          >
            <span
              class="flex h-4 w-4 items-center justify-center rounded-full bg-primary/15 text-[9px] font-semibold text-primary-ink"
            >
              {{ investor.name.charAt(0) }}
            </span>
            {{ walletLabel }}
          </button>
        </template>
      </div>
    </div>

    <p v-if="wallet.error" role="alert" class="border-t border-critical/30 bg-critical/15 px-6 py-2 text-xs text-critical">
      {{ wallet.error }}
    </p>

    <nav v-if="mobileNavOpen" :id="mobileNavId" class="border-t border-hairline px-6 py-3 md:hidden">
      <RouterLink
        v-for="link in NAV_LINKS"
        :key="link.to"
        :to="link.to"
        class="block rounded-md px-2 py-2 text-sm font-medium text-ink-secondary hover:bg-surface hover:text-ink"
        :class="route.path === link.to ? 'bg-surface text-primary' : ''"
        @click="closeMobileNav"
      >
        {{ link.label }}
      </RouterLink>
    </nav>
  </header>
</template>
