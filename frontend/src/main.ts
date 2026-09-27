import './assets/main.css'

import { createApp } from 'vue'
import { createPinia } from 'pinia'

import App from './App.vue'
import router from './router'
import { installAccessGuard } from './router/access'
import { useWalletStore } from './stores/wallet'

const app = createApp(App)
const pinia = createPinia()

app.use(pinia)
// The guard must be in place before the router resolves the first route.
const wallet = useWalletStore(pinia)
installAccessGuard(router, wallet)
app.use(router)

app.mount('#app')

// Privy's SDK is large and drags in React, so it loads as its own chunk after
// mount — the first paint never waits on it. It still loads unprompted rather
// than on first click, because that is what restores a stored session (and the
// active address) on every visit.
void import('./wallet/privyBridge')
  .then(({ mountPrivyBridge }) => mountPrivyBridge(wallet))
  .catch(() => wallet.reportUnavailable("Wallet sign-in didn't load. Refresh the page to try again."))
