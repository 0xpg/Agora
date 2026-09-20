import { defineStore } from 'pinia'
import { ref } from 'vue'

export type WalletNetwork = 'arbitrum' | 'wrong'

// A local, simulated wallet session — this app has no real wallet connector.
// A fresh visit starts disconnected so the "disconnected wallet" state is
// what people actually see, not a toggle buried behind a happy-path default.
export const useWalletStore = defineStore('wallet', () => {
  const connected = ref(false)
  const network = ref<WalletNetwork | null>(null)

  // A freshly connected wallet lands on whatever network it was last used on —
  // simulated here as "wrong" so the required wrong-network state is reachable
  // through the normal connect flow, not hidden behind a dev-only toggle.
  function connect() {
    connected.value = true
    network.value = 'wrong'
  }

  function disconnect() {
    connected.value = false
    network.value = null
  }

  function switchNetwork() {
    network.value = 'arbitrum'
  }

  return { connected, network, connect, disconnect, switchNetwork }
})
