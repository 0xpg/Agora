import type { Chain } from 'viem'
import { baseSepolia } from 'viem/chains'
import deployments from '@config/addresses.json'

// config/addresses.json is the deployment manifest shared with the contracts, and
// the only source of truth for which chain Agora targets — the UI must never
// hard-code one. It is keyed by chain ID, so a lone entry needs no
// disambiguation; VITE_CHAIN_ID picks between them once a second one lands.
const manifest: Record<string, { chainName: string } | undefined> = deployments

// The manifest only names a chain. Privy and viem need the full definition (RPC
// URLs, native currency, explorer), so each deployed chain is mapped explicitly
// here rather than by pulling in viem's entire chain list — adding a deployment
// stays a deliberate edit, and an unmapped one fails loudly at startup.
const CHAIN_DEFINITIONS: Record<string, Chain | undefined> = {
  '84532': baseSepolia,
}

function resolveTargetChain(): Chain {
  const deployed = Object.keys(manifest)
  const configured = import.meta.env.VITE_CHAIN_ID

  let id: string
  if (configured) {
    if (!manifest[configured]) {
      throw new Error(`VITE_CHAIN_ID=${configured} has no deployment in config/addresses.json`)
    }
    id = configured
  } else {
    const [only] = deployed
    if (deployed.length !== 1 || !only) {
      throw new Error(
        `config/addresses.json holds ${deployed.length} deployments — set VITE_CHAIN_ID to pick one of: ${deployed.join(', ')}`,
      )
    }
    id = only
  }

  const chain = CHAIN_DEFINITIONS[id]
  if (!chain) {
    throw new Error(`Chain ${id} is deployed but has no definition in src/config/chain.ts`)
  }
  return chain
}

export const TARGET_CHAIN = resolveTargetChain()
export const TARGET_CHAIN_ID = TARGET_CHAIN.id
export const TARGET_CHAIN_NAME = TARGET_CHAIN.name
