<script setup lang="ts">
import { computed } from 'vue'
import type { MarketStatus } from '@/types/market'
import { MARKET_STATUS_CONFIG } from '@/utils/statusConfig'

const props = defineProps<{
  status: MarketStatus
}>()

const config = computed(() => MARKET_STATUS_CONFIG[props.status])
</script>

<template>
  <span
    class="inline-flex items-center gap-1.5 rounded-full border border-hairline px-2.5 py-1 text-xs font-medium"
    :class="config.text"
  >
    <span class="h-1.5 w-1.5 rounded-full" :class="config.dot" />
    {{ config.label }}
  </span>
</template>
