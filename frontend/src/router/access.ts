import { watch } from 'vue'
import type { Router } from 'vue-router'
import type { WalletStore } from '@/stores/wallet'

// Wallet sessions restore asynchronously, so a gated route has to wait for that
// before deciding. If the SDK never reports in, the visitor is treated as
// signed out rather than left on a blank page.
const SESSION_RESTORE_TIMEOUT_MS = 10_000

function whenSessionKnown(wallet: WalletStore): Promise<void> {
  if (wallet.ready || wallet.unavailable) return Promise.resolve()
  return new Promise((resolve) => {
    const timer = setTimeout(done, SESSION_RESTORE_TIMEOUT_MS)
    const stop = watch(
      () => wallet.ready || wallet.unavailable,
      (known) => known && done(),
    )
    function done() {
      clearTimeout(timer)
      stop()
      resolve()
    }
  })
}

/**
 * Markets, trading and the portfolio are for signed-in investors only; the
 * landing page (and docs) stay public. Following a gated link while signed out
 * opens the sign-in modal instead, and once it succeeds the visitor lands where
 * they were headed.
 */
export function installAccessGuard(router: Router, wallet: WalletStore) {
  // Where a signed-out visitor was trying to go, taken as soon as they sign in.
  let pendingPath: string | null = null

  router.beforeEach(async (to, from) => {
    if (!to.meta.requiresAuth) return true
    await whenSessionKnown(wallet)
    if (wallet.connected) return true

    pendingPath = to.fullPath
    // A click on the landing page is a request to sign in, so answer it with
    // the modal and stay put. A direct visit (typed URL, bookmark, reload)
    // lands on the homepage first — no modal the visitor did not ask for.
    if (from.name === 'landing') {
      wallet.connect()
      return false
    }
    return { name: 'landing' }
  })

  watch(
    () => wallet.connected,
    (connected) => {
      const route = router.currentRoute.value
      if (connected) {
        if (pendingPath && route.name === 'landing') void router.push(pendingPath)
        pendingPath = null
      } else if (wallet.ready && route.meta.requiresAuth) {
        // Signing out on a gated page sends the visitor back to the homepage.
        void router.replace({ name: 'landing' })
      }
    },
  )
}
