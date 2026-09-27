<script setup lang="ts">
import { computed, onBeforeUnmount, onMounted, ref } from 'vue'
import { TARGET_CHAIN } from '@/config/chain'

// Base produces a block every couple of seconds; refreshing more often than
// this would only spend RPC calls on a number nobody reads that closely.
const BLOCK_POLL_MS = 10_000

type NetworkStatus = 'checking' | 'live' | 'down'

const now = ref(new Date())
const blockNumber = ref<bigint | null>(null)
const status = ref<NetworkStatus>('checking')

// The status line reports what the footer can actually observe — whether the
// chain answers — rather than asserting health it has no way to know.
const STATUS_LABEL: Record<NetworkStatus, string> = {
  checking: 'Connecting to network',
  live: 'All systems operational',
  down: 'Network unreachable',
}
const STATUS_DOT: Record<NetworkStatus, string> = {
  checking: 'bg-ink-muted',
  live: 'bg-good',
  down: 'bg-critical',
}

const utcTime = computed(() => now.value.toISOString().slice(11, 19))
const blockLabel = computed(() => (blockNumber.value === null ? '—' : blockNumber.value.toLocaleString('en-US')))
const year = computed(() => now.value.getUTCFullYear())

let clockTimer: ReturnType<typeof setInterval> | undefined
let blockTimer: ReturnType<typeof setInterval> | undefined
// viem loads asynchronously, so the page may already be gone when it arrives.
let unmounted = false

onMounted(async () => {
  clockTimer = setInterval(() => (now.value = new Date()), 1000)

  // viem is a large chunk the landing page otherwise never needs up front.
  const { createPublicClient, http } = await import('viem')
  const client = createPublicClient({ chain: TARGET_CHAIN, transport: http() })
  async function refreshBlock() {
    try {
      blockNumber.value = await client.getBlockNumber()
      status.value = 'live'
    } catch {
      status.value = 'down'
    }
  }
  if (unmounted) return
  await refreshBlock()
  if (unmounted) return
  blockTimer = setInterval(refreshBlock, BLOCK_POLL_MS)
})

onBeforeUnmount(() => {
  unmounted = true
  clearInterval(clockTimer)
  clearInterval(blockTimer)
})
</script>

<template>
  <footer class="border-t border-hairline">
    <div
      class="mx-auto flex max-w-6xl flex-col items-center justify-between gap-3 px-6 py-4 text-xs text-ink-muted sm:flex-row"
    >
      <div class="flex flex-wrap items-center justify-center gap-x-4 gap-y-2">
        <span class="inline-flex items-center gap-2 font-semibold uppercase tracking-wide text-ink">
          <span class="h-2 w-2 shrink-0 rounded-full" :class="STATUS_DOT[status]" />
          {{ STATUS_LABEL[status] }}
        </span>
        <span class="hidden h-3.5 w-px bg-hairline sm:inline-block" aria-hidden="true" />
        <span>Oracle: Chainlink NAV Stream Proof</span>
      </div>
      <div class="flex flex-wrap items-center justify-center gap-x-4 gap-y-2 font-medium uppercase tracking-wide">
        <span class="tabular-nums">UTC {{ utcTime }} &middot; Block {{ blockLabel }}</span>
        <span aria-hidden="true">&middot;</span>
        <span class="normal-case">&copy; {{ year }} Agora Institutional</span>
      </div>
    </div>
  </footer>
</template>
