import { createElement, useEffect, type FunctionComponent } from 'react'
import { createRoot } from 'react-dom/client'
import {
  PrivyProvider,
  useConnectOrCreateWallet,
  useConnectWallet,
  useCreateWallet,
  useModalStatus,
  usePrivy,
  useWallets,
} from '@privy-io/react-auth'
import { TARGET_CHAIN } from '@/config/chain'
import { readThemeColor } from '@/utils/themeTokens'
import type { WalletStore } from '@/stores/wallet'

// Privy reports the active chain in CAIP-2 form ("eip155:84532").
function parseCaip2ChainId(caip2: string): number | null {
  const reference = Number(caip2.split(':')[1])
  return Number.isInteger(reference) ? reference : null
}

// Abandoning the onboarding flow is a normal outcome, not a failure worth
// putting an alert on screen.
function isUserCancellation(code: string): boolean {
  return /cancel|denied|exited|rejected/.test(code)
}

/**
 * Renders nothing. Its only job is to read Privy's hooks and push what they say
 * into the Pinia store, so Vue components never touch React.
 */
const PrivySync: FunctionComponent<{ store: WalletStore }> = ({ store }) => {
  const { ready, authenticated, user, logout } = usePrivy()
  const { wallets, ready: walletsReady } = useWallets()
  const { isOpen } = useModalStatus()
  const { connectOrCreateWallet } = useConnectOrCreateWallet({
    onSuccess: () => store.reportError(null),
    onError: (code) => {
      if (isUserCancellation(code)) return
      store.reportError(`Could not connect a wallet (${code}). Please try again.`)
    },
  })

  // Privy's connectOrCreateWallet is a silent no-op for a signed-in user, so a
  // session that holds no connected wallet — an email login from before
  // createOnLogin was set, or an external wallet linked on another visit — needs
  // its own route to one.
  const { connectWallet } = useConnectWallet({
    onError: (code) => {
      if (isUserCancellation(code)) return
      store.reportError(`Could not reconnect your wallet (${code}). Please try again.`)
    },
  })
  const { createWallet } = useCreateWallet()

  const wallet = wallets[0]
  const address = wallet?.address ?? null
  const chainId = wallet ? parseCaip2ChainId(wallet.chainId) : null

  useEffect(() => {
    store.syncSession({
      ready: ready && walletsReady,
      authenticated,
      address,
      chainId,
      connecting: isOpen,
    })
  }, [store, ready, walletsReady, authenticated, address, chainId, isOpen])

  useEffect(() => {
    store.attachDriver({
      connect: () => {
        if (!authenticated) return connectOrCreateWallet()
        const linked = user?.wallet
        if (linked && linked.walletClientType !== 'privy') return connectWallet()
        createWallet().catch(() => store.reportError('Could not create a wallet for your account. Please try again.'))
      },
      // Privy's logout ends the account session, but an external wallet
      // connected without authenticating outlives it, so drop that too. Some
      // clients (MetaMask, Phantom) cannot be disconnected programmatically and
      // will no-op here; logout still clears Agora's own session.
      disconnect: async () => {
        wallet?.disconnect()
        await logout()
      },
      switchChain: (id) => {
        if (!wallet) throw new Error('No wallet is connected')
        return wallet.switchChain(id)
      },
      getProvider: () => {
        if (!wallet) throw new Error('No wallet is connected')
        return wallet.getEthereumProvider()
      },
    })
  }, [store, authenticated, user, connectOrCreateWallet, connectWallet, createWallet, logout, wallet])

  return null
}

/**
 * Mounts Privy's React SDK in its own detached root. Privy's web SDK is
 * React-only — there is no supported Vue build — so this file is the entire
 * React surface of the app, and it is deliberately headless: Privy portals its
 * modal onto document.body, so the host element never renders anything.
 */
export function mountPrivyBridge(store: WalletStore) {
  const appId = import.meta.env.VITE_PRIVY_APP_ID
  if (!appId) {
    store.reportUnavailable('Wallet onboarding is unavailable: VITE_PRIVY_APP_ID is not set.')
    return
  }

  const host = document.createElement('div')
  host.dataset.privyBridge = ''
  document.body.append(host)

  createRoot(host).render(
    createElement(PrivyProvider, {
      appId,
      config: {
        // Privy renders its own modal, so it has to be told the theme — left
        // alone it ships a light one that arrives as a white sheet over the
        // dark app. Given a background it derives its own foreground from the
        // luminance, so it is handed the elevated surface the rest of the app
        // floats things on, and the emerald accent for its buttons.
        appearance: {
          theme: readThemeColor('--color-elevated', '#101815'),
          accentColor: readThemeColor('--color-primary', '#10b981'),
        },
        // Wallet first, with email as the path that gets someone without a
        // wallet an embedded one.
        loginMethods: ['wallet', 'email'],
        // Agora's contracts live on one chain, so that is both the chain users
        // are prompted onto and the only one permitted.
        defaultChain: TARGET_CHAIN,
        supportedChains: [TARGET_CHAIN],
        // An email login otherwise leaves the account with no wallet at all —
        // Privy defaults this to 'off' — and so nothing Agora can transact with.
        embeddedWallets: { ethereum: { createOnLogin: 'users-without-wallets' } },
      },
      children: createElement(PrivySync, { store }),
    }),
  )
}
