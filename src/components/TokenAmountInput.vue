<script setup lang="ts">
import { useId } from 'vue'

const props = withDefaults(
  defineProps<{
    label: string
    token: string
    editable: boolean
    modelValue: number
    displayValue?: string
    disabled?: boolean
  }>(),
  { disabled: false },
)

defineEmits<{ 'update:modelValue': [value: number] }>()

const inputId = useId()
</script>

<template>
  <div class="rounded-md border border-hairline bg-page p-3">
    <label :for="editable ? inputId : undefined" class="text-[11px] font-medium tracking-wide text-ink-muted">
      {{ label }}
    </label>
    <div class="mt-1 flex items-center justify-between gap-2">
      <input
        v-if="editable"
        :id="inputId"
        type="number"
        min="1"
        step="1"
        :disabled="disabled"
        :value="modelValue"
        class="w-full bg-transparent text-lg font-semibold tabular-nums text-ink focus:outline-none disabled:opacity-50"
        @input="$emit('update:modelValue', Number(($event.target as HTMLInputElement).value))"
      />
      <span v-else class="text-lg font-semibold tabular-nums text-ink">{{ displayValue }}</span>
      <span class="shrink-0 rounded-full border border-hairline px-2.5 py-1 text-xs font-medium text-ink-secondary">
        {{ token }}
      </span>
    </div>
  </div>
</template>
