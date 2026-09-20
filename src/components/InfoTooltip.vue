<script setup lang="ts">
defineProps<{
  text: string
}>()
</script>

<template>
  <span
    class="group relative inline-flex items-center outline-none"
    tabindex="0"
    role="note"
    :aria-label="text"
  >
    <slot>
      <span
        class="flex h-3.5 w-3.5 items-center justify-center rounded-full border border-ink-muted text-[9px] font-semibold text-ink-muted"
      >
        i
      </span>
    </slot>
    <span
      class="pointer-events-none absolute bottom-full left-1/2 z-10 mb-1.5 w-max max-w-56 -translate-x-1/2 rounded-md bg-ink px-2 py-1.5 text-xs leading-snug text-white opacity-0 shadow-lg transition-opacity group-hover:opacity-100 group-focus-within:opacity-100"
    >
      {{ text }}
    </span>
  </span>
</template>
