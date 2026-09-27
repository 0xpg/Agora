import { createElement, useEffect, useState, type FunctionComponent } from 'react'
import { createRoot } from 'react-dom/client'
import {
  PrivyProvider,
  useConnectOrCreateWallet,
  useConnectWallet,
  useCreateWallet,
  useModalStatus,
  usePrivy,
  useWallets,
  type ConnectedWallet,
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
 * Makes the wallet forget this site, so reconnecting asks for approval again
 * instead of Privy silently picking the still-authorized wallet back up.
 * Privy's own disconnect only closes WalletConnect sessions — for MetaMask and
 * other browser extensions it just logs a warning — so extensions are asked to
 * revoke the account permission (EIP-2255) as well.
 */
async function forgetWallet(wallet: ConnectedWallet) {
  if (wallet.walletClientType === 'privy') return
  if (wallet.connectorType === 'injected') {
    try {
      const provider = await wallet.getEthereumProvider()
      await provider.request({ method: 'wallet_revokePermissions', params: [{ eth_accounts: {} }] })
    } catch (err) {
      console.warn(`Could not revoke ${wallet.walletClientType} permissions:`, err)
    }
  }
  wallet.disconnect()
}

// Not every extension supports revoking, and one that does not stays connected
// underneath. So Agora also hides the wallet itself until the user signs in
// again through Privy's modal — remembered across reloads, where Privy would
// otherwise bring it back. Storage can be unavailable (private mode, blocked
// site data); then the flag lasts only for this visit.
const SIGNED_OUT_KEY = 'agora:wallet-signed-out'

function readSignedOut(): boolean {
  try {
    return localStorage.getItem(SIGNED_OUT_KEY) === '1'
  } catch {
    return false
  }
}

function writeSignedOut(signedOut: boolean) {
  try {
    if (signedOut) localStorage.setItem(SIGNED_OUT_KEY, '1')
    else localStorage.removeItem(SIGNED_OUT_KEY)
  } catch {
    // Not persisted; the in-memory flag still covers this visit.
  }
}

/**
 * Renders nothing. Its only job is to read Privy's hooks and push what they say
 * into the Pinia store, so Vue components never touch React.
 */
const PrivySync: FunctionComponent<{ store: WalletStore }> = ({ store }) => {
  const { ready, authenticated, user, logout } = usePrivy()
  const { wallets, ready: walletsReady } = useWallets()
  const { isOpen } = useModalStatus()

  const [signedOut, setSignedOutState] = useState(readSignedOut)
  function setSignedOut(next: boolean) {
    writeSignedOut(next)
    setSignedOutState(next)
  }

  const { connectOrCreateWallet } = useConnectOrCreateWallet({
    onSuccess: () => {
      setSignedOut(false)
      store.reportError(null)
    },
    onError: (code) => {
      if (isUserCancellation(code)) return
      // The raw Privy code means nothing to an investor, so it goes to the
      // console for debugging and the banner speaks plainly.
      console.warn('Privy connectOrCreateWallet failed:', code)
      store.reportError(`We couldn't connect your wallet. Make sure it's unlocked and set to ${TARGET_CHAIN.name}, then try again.`)
    },
  })

  // Privy's connectOrCreateWallet is a silent no-op for a signed-in user, so a
  // session that holds no connected wallet — an email login from before
  // createOnLogin was set, or an external wallet linked on another visit — needs
  // its own route to one.
  const { connectWallet } = useConnectWallet({
    onSuccess: () => store.reportError(null),
    onError: (code) => {
      if (isUserCancellation(code)) return
      console.warn('Privy connectWallet failed:', code)
      store.reportError("Your wallet didn't respond. Open it, make sure it's unlocked, then click Connect Wallet again.")
    },
  })
  const { createWallet } = useCreateWallet()

  // An email or social sign-in also counts as coming back.
  useEffect(() => {
    if (authenticated) setSignedOut(false)
  }, [authenticated])

  const wallet = signedOut ? undefined : wallets[0]
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
        createWallet()
          .then(() => store.reportError(null))
          .catch((err: unknown) => {
            console.warn('Privy createWallet failed:', err)
            store.reportError("We couldn't set up your wallet just now. Please try again in a moment.")
          })
      },
      // Privy's logout ends the account session, but an external wallet
      // connected without authenticating outlives it, so every connected
      // wallet is released too — not just the one on screen.
      disconnect: async () => {
        setSignedOut(true)
        await Promise.all(wallets.map(forgetWallet))
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
  }, [store, authenticated, user, connectOrCreateWallet, connectWallet, createWallet, logout, wallet, wallets])

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
    console.error('Wallet onboarding is disabled: VITE_PRIVY_APP_ID is not set.')
    store.reportUnavailable('Wallet sign-in is temporarily unavailable. Please check back soon.')
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
