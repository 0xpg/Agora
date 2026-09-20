<script setup lang="ts">
import { computed, ref, useId } from 'vue'
import { RouterLink, useRoute } from 'vue-router'
import type { Investor } from '@/types/market'
import { ELIGIBILITY_TIER_LABEL } from '@/types/market'
import { mockAssets } from '@/data/mockAssets'
import { useWalletStore } from '@/stores/wallet'
import { formatCompactCurrency, truncateAddress } from '@/utils/format'

const props = defineProps<{
  investor: Investor
}>()

const wallet = useWalletStore()
const route = useRoute()

const totalLiquidity = computed(() => mockAssets.reduce((sum, asset) => sum + asset.liquidity, 0))
const walletLabel = computed(() => truncateAddress(props.investor.walletAddress))

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
</script>

<template>
  <header class="sticky top-0 z-50 border-b border-black/40 bg-ink">
    <div class="mx-auto flex max-w-6xl items-center justify-between gap-4 px-6 py-3">
      <div class="flex items-center gap-3">
        <RouterLink to="/markets" class="flex items-center gap-2">
          <span class="flex h-5 w-5 rotate-45 rounded-[3px] bg-white" />
          <span class="text-base font-semibold tracking-tight text-white">Agora</span>
        </RouterLink>
        <span
          class="hidden items-center gap-1.5 whitespace-nowrap rounded-full border border-white/15 bg-white/10 px-2.5 py-1 text-xs text-white/70 xl:inline-flex"
        >
          <span class="h-1.5 w-1.5 shrink-0 rounded-full bg-good" />
          RWA DEX &middot; Mainnet
        </span>
        <nav class="hidden items-center gap-3 text-sm md:flex">
          <RouterLink
            v-for="link in NAV_LINKS"
            :key="link.to"
            :to="link.to"
            class="font-medium text-white hover:text-white/80"
            :class="route.path === link.to ? 'underline underline-offset-4' : ''"
          >
            {{ link.label }}
          </RouterLink>
        </nav>
      </div>

      <div class="flex items-center gap-2">
        <button
          type="button"
          class="rounded-md p-1.5 text-white transition hover:bg-white/10 md:hidden"
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
          class="hidden shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full border border-white/15 bg-white/10 px-2.5 py-1 text-xs text-white/80 md:inline-flex"
        >
          TVL <span class="font-semibold tabular-nums text-white">{{ formatCompactCurrency(totalLiquidity) }}</span>
        </span>

        <template v-if="!wallet.connected">
          <button
            type="button"
            class="rounded-full bg-primary px-3.5 py-1.5 text-xs font-semibold text-white transition hover:bg-primary/90"
            @click="wallet.connect()"
          >
            Connect Wallet
          </button>
        </template>
        <template v-else>
          <button
            v-if="wallet.network === 'wrong'"
            type="button"
            class="inline-flex shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full border border-critical/40 bg-critical/10 px-2.5 py-1 text-xs font-semibold text-critical transition hover:bg-critical/20"
            @click="wallet.switchNetwork()"
          >
            <span class="h-1.5 w-1.5 shrink-0 rounded-full bg-critical" />
            <span class="hidden md:inline">Switch to Arbitrum One</span>
            <span class="md:hidden">Wrong Network</span>
          </button>
          <span
            v-else
            class="hidden shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full border border-white/15 bg-white/10 px-2.5 py-1 text-xs text-white/80 md:inline-flex"
          >
            <span class="h-1.5 w-1.5 shrink-0 rounded-full bg-good" />
            Arbitrum One
          </span>

          <span
            class="hidden shrink-0 items-center gap-1.5 whitespace-nowrap rounded-full border border-white/15 bg-white/10 px-2.5 py-1 text-xs font-medium text-white/90 lg:inline-flex"
          >
            <span
              class="h-1.5 w-1.5 shrink-0 rounded-full"
              :class="investor.kycStatus === 'verified' ? 'bg-good' : 'bg-warning'"
            />
            {{ ELIGIBILITY_TIER_LABEL[investor.tier] }}
          </span>

          <button
            type="button"
            class="inline-flex shrink-0 items-center gap-2 whitespace-nowrap rounded-full bg-white px-3 py-1.5 text-xs font-medium text-ink transition hover:bg-white/90"
            @click="wallet.disconnect()"
          >
            <span
              class="flex h-4 w-4 items-center justify-center rounded-full bg-page text-[9px] font-semibold text-ink-secondary"
            >
              {{ investor.name.charAt(0) }}
            </span>
            {{ walletLabel }}
          </button>
        </template>
      </div>
    </div>

    <nav v-if="mobileNavOpen" :id="mobileNavId" class="border-t border-white/10 px-6 py-3 md:hidden">
      <RouterLink
        v-for="link in NAV_LINKS"
        :key="link.to"
        :to="link.to"
        class="block rounded-md px-2 py-2 text-sm font-medium text-white hover:bg-white/10"
        :class="route.path === link.to ? 'bg-white/10' : ''"
        @click="closeMobileNav"
      >
        {{ link.label }}
      </RouterLink>
    </nav>
  </header>
</template>
