<script setup lang="ts">
import { nextTick, ref, useId, watch } from 'vue'

/**
 * A confirmation before something the investor cannot casually undo.
 *
 * Built on the native `<dialog>` element, which gives the things a hand-rolled
 * modal usually gets wrong for free: it renders in the browser's top layer so no
 * `z-index` can cover it, it traps focus, it returns focus to whatever opened
 * it, and Escape closes it. The safe choice takes focus, so a stray Enter
 * dismisses rather than confirms.
 */
const props = withDefaults(
  defineProps<{
    open: boolean
    title: string
    message: string
    /** An extra line under the message — an address, an amount, whatever is at stake. */
    detail?: string
    confirmLabel?: string
    cancelLabel?: string
    /** Destructive actions get the critical treatment; anything else the accent. */
    tone?: 'critical' | 'primary'
    /** While true the dialog stays open, the buttons lock, and confirm shows progress. */
    busy?: boolean
    busyLabel?: string
  }>(),
  {
    detail: '',
    confirmLabel: 'Confirm',
    cancelLabel: 'Cancel',
    tone: 'critical',
    busy: false,
    busyLabel: 'Working…',
  },
)

const emit = defineEmits<{ confirm: []; cancel: [] }>()

const dialog = ref<HTMLDialogElement | null>(null)
const cancelButton = ref<HTMLButtonElement | null>(null)
const titleId = useId()
const messageId = useId()

watch(
  () => props.open,
  async (open) => {
    const el = dialog.value
    if (!el) return
    if (open) {
      if (!el.open) el.showModal()
      // Focus the way out, not the way through.
      await nextTick()
      cancelButton.value?.focus()
    } else if (el.open) {
      el.close()
    }
  },
)

function requestCancel() {
  if (props.busy) return
  emit('cancel')
}

/**
 * The backdrop is part of the dialog element, so a click that lands on the
 * element itself — rather than on the card inside it — came from outside.
 */
function onDialogClick(event: MouseEvent) {
  if (event.target === dialog.value) requestCancel()
}
</script>

<template>
  <dialog
    ref="dialog"
    class="dialog w-[min(28rem,calc(100vw-2rem))] rounded-xl border border-hairline bg-surface p-0 text-ink shadow-2xl shadow-black/60"
    :aria-labelledby="titleId"
    :aria-describedby="messageId"
    :aria-busy="busy"
    @click="onDialogClick"
    @cancel.prevent="requestCancel"
    @close="open && requestCancel()"
  >
    <div class="p-5 sm:p-6">
      <div class="flex gap-3.5">
        <span
          class="mt-0.5 flex size-9 shrink-0 items-center justify-center rounded-full"
          :class="tone === 'critical' ? 'bg-critical/10 text-critical' : 'bg-primary/10 text-primary'"
          aria-hidden="true"
        >
          <svg viewBox="0 0 20 20" class="size-4.5" fill="none" stroke="currentColor" stroke-width="1.6">
            <path d="M10 6.5v4" stroke-linecap="round" />
            <circle cx="10" cy="13.75" r="0.85" fill="currentColor" stroke="none" />
            <circle cx="10" cy="10" r="7.25" />
          </svg>
        </span>

        <div class="min-w-0 flex-1">
          <h2 :id="titleId" class="text-base font-semibold text-ink">{{ title }}</h2>
          <p :id="messageId" class="mt-1.5 text-sm leading-relaxed text-ink-secondary">{{ message }}</p>
          <p
            v-if="detail"
            class="mt-3 truncate rounded-md border border-hairline bg-page px-2.5 py-1.5 font-mono text-xs text-ink-muted"
          >
            {{ detail }}
          </p>
          <slot />
        </div>
      </div>

      <div class="mt-6 flex flex-col-reverse gap-2 sm:flex-row sm:justify-end">
        <button
          ref="cancelButton"
          type="button"
          class="rounded-full border border-hairline px-4 py-2 text-sm font-medium text-ink transition hover:border-ink-muted hover:text-ink focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-primary disabled:opacity-50"
          :disabled="busy"
          @click="requestCancel"
        >
          {{ cancelLabel }}
        </button>
        <button
          type="button"
          class="rounded-full px-4 py-2 text-sm font-semibold transition focus-visible:outline-2 focus-visible:outline-offset-2 disabled:cursor-not-allowed disabled:opacity-60"
          :class="
            tone === 'critical'
              ? 'bg-critical text-on-accent hover:brightness-110 focus-visible:outline-critical'
              : 'bg-primary text-on-accent hover:brightness-110 focus-visible:outline-primary'
          "
          :disabled="busy"
          @click="emit('confirm')"
        >
          {{ busy ? busyLabel : confirmLabel }}
        </button>
      </div>
    </div>
  </dialog>
</template>

<style scoped>
/* The element is centred by the top layer, not by the page, so it needs its own
   margins rather than a positioned wrapper. */
.dialog {
  margin: auto;
}

.dialog::backdrop {
  background-color: color-mix(in oklab, var(--color-page) 72%, transparent);
  backdrop-filter: blur(3px);
}

@media (prefers-reduced-motion: no-preference) {
  .dialog[open] {
    animation: dialog-in 0.18s cubic-bezier(0.16, 1, 0.3, 1);
  }

  .dialog[open]::backdrop {
    animation: backdrop-in 0.18s ease;
  }
}

@keyframes dialog-in {
  from {
    opacity: 0;
    transform: translateY(6px) scale(0.98);
  }
  to {
    opacity: 1;
    transform: none;
  }
}

@keyframes backdrop-in {
  from {
    opacity: 0;
  }
  to {
    opacity: 1;
  }
}
</style>
