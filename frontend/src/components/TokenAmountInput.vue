<script setup lang="ts">
import { ref, useId, watch } from 'vue'

const props = withDefaults(
  defineProps<{
    label: string
    token: string
    modelValue: number | null
    /** The other leg's value, or whatever context belongs under the amount. */
    secondary?: string
    disabled?: boolean
    /** Offers a one-tap fill with the largest amount the pool will take. */
    max?: number | null
    invalid?: boolean
  }>(),
  { disabled: false, invalid: false, max: null, secondary: '' },
)

const emit = defineEmits<{ 'update:modelValue': [value: number | null] }>()

const inputId = useId()
// The field keeps its own text so half-typed values ("0.", "") survive, and so a
// recomputed quote never rewrites what someone is in the middle of typing.
const draft = ref(toText(props.modelValue))
const focused = ref(false)

function toText(value: number | null): string {
  if (value === null || !Number.isFinite(value)) return ''
  return String(Number(value.toFixed(6)))
}

watch(
  () => props.modelValue,
  (value) => {
    if (!focused.value) draft.value = toText(value)
  },
)

function onInput(event: Event) {
  const raw = (event.target as HTMLInputElement).value
  // Digits and a single decimal point only; anything else is dropped rather than
  // rejected, so the field never fights the person typing into it.
  const cleaned = raw.replace(/[^\d.]/g, '').replace(/(\..*)\./g, '$1')
  draft.value = cleaned
  if (cleaned === '' || cleaned === '.') {
    emit('update:modelValue', null)
    return
  }
  const parsed = Number(cleaned)
  if (Number.isFinite(parsed)) emit('update:modelValue', parsed)
}

function onBlur() {
  focused.value = false
  // Snap the text back to the canonical form of whatever the quote settled on.
  draft.value = toText(props.modelValue)
}

function fillMax() {
  if (props.max === null || props.max === undefined) return
  const value = Number(props.max.toFixed(6))
  draft.value = toText(value)
  emit('update:modelValue', value)
}
</script>

<template>
  <div
    class="rounded-md border bg-page p-3 transition-colors"
    :class="invalid ? 'border-critical/60' : 'border-hairline focus-within:border-primary/50'"
  >
    <div class="flex items-center justify-between gap-2">
      <label :for="inputId" class="text-[11px] font-medium tracking-wide text-ink-muted">{{ label }}</label>
      <button
        v-if="max !== null && max !== undefined && !disabled"
        type="button"
        class="rounded px-1.5 py-0.5 text-[10px] font-semibold tracking-wide text-primary uppercase hover:bg-primary/10"
        @click="fillMax"
      >
        Max
      </button>
    </div>

    <div class="mt-1 flex items-center justify-between gap-2">
      <input
        :id="inputId"
        type="text"
        inputmode="decimal"
        autocomplete="off"
        spellcheck="false"
        placeholder="0.00"
        :disabled="disabled"
        :value="draft"
        class="w-full min-w-0 bg-transparent text-lg font-semibold tabular-nums text-ink placeholder:text-ink-muted focus:outline-none disabled:opacity-50"
        @input="onInput"
        @focus="focused = true"
        @blur="onBlur"
      />
      <span class="shrink-0 rounded-full border border-hairline px-2.5 py-1 text-xs font-medium text-ink-secondary">
        {{ token }}
      </span>
    </div>

    <p v-if="secondary" class="mt-1 truncate text-[11px] tabular-nums text-ink-muted">{{ secondary }}</p>
  </div>
</template>
