<script setup lang="ts">
import { computed } from 'vue'

export interface MetricItem {
  label: string
  value: string
  valueClass?: string
  inlineNote?: string
  inlineNoteClass?: string
  caption?: string
  captionDotClass?: string
  accentBarClass?: string
}

const props = defineProps<{
  metrics: MetricItem[]
}>()

const colsClass = computed(() => {
  const n = props.metrics.length
  if (n <= 2) return 'sm:grid-cols-2'
  if (n === 3) return 'sm:grid-cols-3'
  return 'sm:grid-cols-4'
})
</script>

<template>
  <div
    class="grid grid-cols-1 divide-y divide-hairline rounded-lg border border-hairline bg-surface sm:divide-x sm:divide-y-0"
    :class="colsClass"
  >
    <div v-for="metric in metrics" :key="metric.label" class="p-4">
      <div class="text-[11px] font-medium tracking-wide text-ink-muted">{{ metric.label }}</div>
      <div class="mt-1 flex items-baseline gap-1.5">
        <span class="text-xl font-semibold tabular-nums" :class="metric.valueClass ?? 'text-ink'">{{ metric.value }}</span>
        <span v-if="metric.inlineNote" class="text-xs font-medium tabular-nums" :class="metric.inlineNoteClass ?? 'text-ink-muted'">
          {{ metric.inlineNote }}
        </span>
      </div>
      <div v-if="metric.accentBarClass" class="mt-2 h-0.5 w-6 rounded-full" :class="metric.accentBarClass" />
      <div v-else-if="metric.caption" class="mt-2 flex items-center gap-1.5 text-xs text-ink-muted">
        <span v-if="metric.captionDotClass" class="h-1.5 w-1.5 rounded-full" :class="metric.captionDotClass" />
        {{ metric.caption }}
      </div>
    </div>
  </div>
</template>
