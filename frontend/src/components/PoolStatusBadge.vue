<script setup lang="ts">
import { computed } from 'vue'
import type { TokenizedAsset } from '@/types/market'
import { poolCondition } from '@/utils/quote'
import { POOL_CONDITION_CONFIG } from '@/utils/statusConfig'

const props = defineProps<{
  asset: TokenizedAsset
}>()

const config = computed(() => POOL_CONDITION_CONFIG[poolCondition(props.asset)])
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
