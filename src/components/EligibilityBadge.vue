<script setup lang="ts">
import { computed } from 'vue'
import type { EligibilityState } from '@/composables/useEligibility'
import { ELIGIBILITY_CONFIG } from '@/utils/statusConfig'

const props = defineProps<{
  state: EligibilityState
}>()

const config = computed(() => ELIGIBILITY_CONFIG[props.state])
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
