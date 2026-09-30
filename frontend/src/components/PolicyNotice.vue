<script setup lang="ts">
import { computed } from 'vue'

export type NoticeTone = 'critical' | 'warning' | 'info' | 'success'

const props = withDefaults(
  defineProps<{
    tone?: NoticeTone
    title: string
    detail?: string
    /** Shows a spinner in place of the status dot. */
    busy?: boolean
  }>(),
  { tone: 'info', detail: '', busy: false },
)

const TONES: Record<NoticeTone, { box: string; dot: string; title: string }> = {
  critical: { box: 'border-critical/30 bg-critical/5', dot: 'bg-critical', title: 'text-critical' },
  warning: { box: 'border-warning/30 bg-warning/5', dot: 'bg-warning', title: 'text-warning' },
  info: { box: 'border-hairline bg-page', dot: 'bg-ink-muted', title: 'text-ink' },
  success: { box: 'border-primary/30 bg-primary/5', dot: 'bg-good', title: 'text-success' },
}

const tone = computed(() => TONES[props.tone])
</script>

<template>
  <div class="rounded-md border p-3" :class="tone.box" role="status">
    <div class="flex gap-2.5">
      <span
        class="mt-1.5 size-1.5 shrink-0 rounded-full"
        :class="[tone.dot, busy ? 'animate-pulse' : '']"
        aria-hidden="true"
      />
      <div class="min-w-0 flex-1">
        <p class="text-sm font-medium" :class="tone.title">{{ title }}</p>
        <p v-if="detail" class="mt-1 text-xs leading-relaxed text-ink-secondary">{{ detail }}</p>
        <slot />
      </div>
    </div>
  </div>
</template>
