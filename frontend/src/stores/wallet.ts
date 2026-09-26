import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import type { Hex, WalletClient } from 'viem'
import { TARGET_CHAIN, TARGET_CHAIN_ID, TARGET_CHAIN_NAME } from '@/config/chain'

/** A snapshot of the wallet session, as reported by the SDK driving this store. */
export interface WalletSession {
  /** False until the SDK has loaded and restored any stored session. */
  ready: boolean
  /** True when Privy holds an account session (email, social, or embedded wallet). */
  authenticated: boolean
  address: string | null
  chainId: number | null
  /** True while an onboarding flow is on screen. */
  connecting: boolean
}

/**
 * The EIP-1193 surface viem's `custom` transport actually needs. Declared
 * structurally rather than as viem's own `EIP1193Provider`, whose per-method
 * request overloads are stricter than any SDK provider satisfies.
 */
export type Eip1193Provider = {
  request: (args: { method: string; params?: unknown[] }) => Promise<unknown>
}

/**
 * What the store needs from the wallet SDK. The Privy bridge registers an
 * implementation once it has loaded; nothing outside that bridge imports Privy,
 * so the rest of the app — and a future SDK swap — deals only with this shape.
 */
export interface WalletDriver {
  /** Opens Privy's onboarding flow: connect an external wallet, or create an embedded one. */
  connect: () => void
  disconnect: () => Promise<void>
  switchChain: (chainId: number) => Promise<void>
  getProvider: () => Promise<Eip1193Provider>
}

export const useWalletStore = defineStore('wallet', () => {
  const ready = ref(false)
  const authenticated = ref(false)
  const address = ref<string | null>(null)
  const chainId = ref<number | null>(null)
  const connecting = ref(false)
  const switching = ref(false)
  const error = ref<string | null>(null)
  // Onboarding can be permanently unavailable — no app ID configured, or the
  // SDK chunk failed to load. Distinct from `!ready`, which is transient, so the
  // UI can say "broken" rather than claiming it is still loading.
  const unavailable = ref(false)

  let driver: WalletDriver | null = null

  // An external wallet can be connected without a Privy account session, so a
  // usable wallet is an address — not `authenticated`.
  const connected = computed(() => address.value !== null)
  const onTargetChain = computed(() => chainId.value === TARGET_CHAIN_ID)
  // Only claim a wrong network once the chain is actually known.
  const wrongNetwork = computed(() => connected.value && chainId.value !== null && !onTargetChain.value)
  // The precondition for anything that touches the chain. Unlike `wrongNetwork`,
  // which stays quiet until the chain is known because it drives a "switch
  // network" prompt, this fails closed while `chainId` is null — an order must
  // never be submitted against a chain Agora's contracts may not be deployed on.
  // `getWalletClient` enforces the same rule imperatively, with distinct errors
  // for diagnostics; keep the two in sync.
  const canTransact = computed(() => connected.value && onTargetChain.value)

  function attachDriver(next: WalletDriver) {
    driver = next
  }

  function syncSession(session: WalletSession) {
    ready.value = session.ready
    authenticated.value = session.authenticated
    address.value = session.address
    chainId.value = session.chainId
    connecting.value = session.connecting
  }

  function reportError(message: string | null) {
    error.value = message
  }

  function reportUnavailable(message: string) {
    unavailable.value = true
    error.value = message
  }

  function connect() {
    if (!driver) return
    error.value = null
    driver.connect()
  }

  async function disconnect() {
    if (!driver) return
    error.value = null
    await driver.disconnect()
  }

  async function switchToTargetChain() {
    if (!driver) return
    error.value = null
    switching.value = true
    try {
      await driver.switchChain(TARGET_CHAIN_ID)
    } catch {
      error.value = `Could not switch to ${TARGET_CHAIN_NAME}. Approve the request in your wallet, or switch networks there yourself.`
    } finally {
      switching.value = false
    }
  }

  /**
   * The signer for eligibility reads and order submission. Pinned to the target
   * chain and refused off it, so a transaction can never be signed against a
   * chain Agora's contracts are not deployed on.
   */
  async function getWalletClient(): Promise<WalletClient> {
    if (!driver || !address.value) throw new Error('No wallet is connected')
    if (!onTargetChain.value) throw new Error(`Wallet is not on ${TARGET_CHAIN_NAME}`)

    // viem's signing crypto is a large chunk that only matters once someone
    // actually transacts, so it loads here rather than on every page view.
    const [{ createWalletClient, custom }, provider] = await Promise.all([
      import('viem'),
      driver.getProvider(),
    ])
    return createWalletClient({
      account: address.value as Hex,
      chain: TARGET_CHAIN,
      transport: custom(provider),
    })
  }

  return {
    ready,
    authenticated,
    address,
    chainId,
    connecting,
    switching,
    error,
    unavailable,
    connected,
    onTargetChain,
    wrongNetwork,
    canTransact,
    attachDriver,
    syncSession,
    reportError,
    reportUnavailable,
    connect,
    disconnect,
    switchToTargetChain,
    getWalletClient,
  }
})

export type WalletStore = ReturnType<typeof useWalletStore>
