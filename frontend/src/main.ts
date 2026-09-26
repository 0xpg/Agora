import './assets/main.css'

import { createApp } from 'vue'
import { createPinia } from 'pinia'

import App from './App.vue'
import router from './router'
import { useWalletStore } from './stores/wallet'

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)
app.use(router)

app.mount('#app')

// Privy's SDK is large and drags in React, so it loads as its own chunk after
// mount — the first paint never waits on it. It still loads unprompted rather
// than on first click, because that is what restores a stored session (and the
// active address) on every visit.
const wallet = useWalletStore(pinia)
void import('./wallet/privyBridge')
  .then(({ mountPrivyBridge }) => mountPrivyBridge(wallet))
  .catch(() => wallet.reportUnavailable('Wallet onboarding failed to load. Reload the page to try again.'))
