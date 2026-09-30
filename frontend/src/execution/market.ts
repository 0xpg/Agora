import type { Address } from 'viem'
import markets from '@config/markets.json'
import { TARGET_CHAIN_ID } from '@/config/chain'

/**
 * The contracts behind one tradable market, as `config/markets.json` records
 * them after deployment. A catalogue asset is only tradable when an entry here
 * carries its id; everything else in the catalogue is listing data with no
 * market behind it yet.
 */
export interface DeployedMarket {
  id: string
  name: string
  symbol: string
  assetToken: Address
  settlementToken: Address
  identityRegistry: Address
  navOracle: Address
  allowlistChecker: Address
  poolManager: Address
  hook: Address
  liquidityRouter: Address
  /** The only route a swap may take — it is what establishes the eligible end user. */
  swapRouter: Address
  /** Pool currencies, ordered by address as the pool key requires. */
  currency0: Address
  currency1: Address
  fee: number
  tickSpacing: number
}

const byChain = markets as Record<string, DeployedMarket[] | undefined>

/** Every deployed market on the chain this build targets. */
export const DEPLOYED_MARKETS: DeployedMarket[] = byChain[String(TARGET_CHAIN_ID)] ?? []

export function marketFor(assetId: string): DeployedMarket | null {
  return DEPLOYED_MARKETS.find((market) => market.id === assetId) ?? null
}

/**
 * True when the asset token is the pool's `currency0`. Swap direction is
 * expressed as `zeroForOne`, so which side the asset sits on decides how a buy
 * or a sell maps onto it.
 */
export function assetIsCurrency0(market: DeployedMarket): boolean {
  return market.assetToken.toLowerCase() === market.currency0.toLowerCase()
}

/**
 * Selling the asset moves price down; buying moves it up. `zeroForOne` means
 * selling `currency0` for `currency1`, so it follows the asset's position in
 * the pair rather than being fixed.
 */
export function zeroForOne(market: DeployedMarket, side: 'buy' | 'sell'): boolean {
  return side === 'sell' ? assetIsCurrency0(market) : !assetIsCurrency0(market)
}
