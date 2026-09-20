<script setup lang="ts">
export interface InfoRow {
  label: string
  value: string
  align?: 'left' | 'right'
  span?: 'full'
}

withDefaults(
  defineProps<{
    rows: InfoRow[]
    title?: string
    columns?: 1 | 2
  }>(),
  { columns: 2 },
)
</script>

<template>
  <div class="rounded-lg border border-hairline bg-surface p-5">
    <h2 v-if="title" class="mb-4 text-sm font-semibold text-ink">{{ title }}</h2>
    <dl class="grid grid-cols-1 gap-4" :class="columns === 2 ? 'sm:grid-cols-2' : ''">
      <div
        v-for="row in rows"
        :key="row.label"
        :class="[row.align === 'right' ? 'sm:text-right' : '', row.span === 'full' ? 'sm:col-span-2' : '']"
      >
        <dt class="text-xs text-ink-muted">{{ row.label }}</dt>
        <dd class="mt-1 text-sm text-ink">{{ row.value }}</dd>
      </div>
    </dl>
  </div>
</template>
