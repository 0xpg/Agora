export type EligibilityTier = 'retail' | 'accredited' | 'qualified_purchaser' | 'institutional'

export const ELIGIBILITY_TIER_LABEL: Record<EligibilityTier, string> = {
  retail: 'Retail',
  accredited: 'Accredited Investor',
  qualified_purchaser: 'Qualified Purchaser',
  institutional: 'Institutional',
}

export const ELIGIBILITY_TIER_RANK: Record<EligibilityTier, number> = {
  retail: 0,
  accredited: 1,
  qualified_purchaser: 2,
  institutional: 3,
}

export type KycStatus = 'verified' | 'pending' | 'unverified'

export type PoolType = 'nav_managed' | 'standard'

export type AssetClass =
  | 'Commercial Real Estate'
  | 'Private Credit'
  | 'US Treasuries'
  | 'Fine Art'
  | 'Infrastructure'
  | 'Trade Finance'

export interface NavPoint {
  time: number // unix seconds
  value: number
}

// Trading itself is continuous, so these are the issuer's holding and transfer
// terms only — nothing here schedules when a swap may happen.
export interface MarketRules {
  lockupPeriodDays: number
  minHoldingPeriodDays: number
  maxOwnershipPct: number
  transferRestrictions: string
}

/**
 * A short-lived issuer override. While `expiresAt` is in the future it replaces
 * the standing price range and fee curve; it then lapses on its own, with no
 * cleanup transaction. Mirrors `AgoraHook.temporaryPolicy`.
 */
export interface TemporaryPolicy {
  bandLower: number
  bandUpper: number
  baseFeeBps: number
  edgeFeeBps: number
  expiresAt: number // unix seconds
}

/**
 * The issuer-configured policy the pool's hook applies to every swap. Prices are
 * in the market's quote currency per asset token — the hook stores them as
 * Q64.96 square roots, which is an encoding detail the UI never shows.
 *
 * @see AgoraHook.activePolicy / setRiskControls / syncPriceBand
 */
export interface PoolPolicy {
  /** Ends of the permitted price range. A swap reverts if it starts or lands outside. */
  bandLower: number
  bandUpper: number
  /** The NAV-anchored price the fee curve and the rebalancing guard centre on. */
  targetPrice: number
  /** Fee charged at the target price, rising linearly to `edgeFeeBps` at the range edge. */
  baseFeeBps: number
  edgeFeeBps: number
  /**
   * Half-width of the zone around the target price where both directions trade
   * freely. Past it, only swaps that move price back toward the target are
   * accepted. 0 disables the guard.
   */
  directionalGuardBps: number
  /** Largest permitted trade, as notional in the quote currency. 0 disables the cap. */
  maxTradeNotional: number
  /** Notional at or above which the tighter NAV freshness rule applies. 0 disables it. */
  largeTradeNotional: number
  /** When the issuer last published NAV. */
  navUpdatedAt: number // unix seconds
  /** How old NAV may be before every swap is refused. */
  navMaxAgeSeconds: number
  /** The tighter age limit that large trades must additionally satisfy. */
  largeTradeMaxNavAgeSeconds: number
  /**
   * The NAV publication the current range was synced against. A newer NAV
   * invalidates the range until the issuer re-syncs it.
   */
  bandSyncedNavUpdatedAt: number // unix seconds
  /** Issuer kill switch. */
  paused: boolean
  temporaryPolicy: TemporaryPolicy | null
}

export interface TokenizedAsset {
  id: string
  symbol: string
  name: string
  assetClass: AssetClass
  issuer: string
  domicile: string
  currency: string
  nav: number
  lastPrice: number
  change24hPct: number
  yieldPct: number | null
  liquidity: number
  volume30d: number
  poolType: PoolType
  kycRequired: boolean
  maturityDate: string | null // ISO date; null means perpetual (no fixed maturity)
  totalSupply: number
  minInvestment: number
  requiredTiers: EligibilityTier[]
  rules: MarketRules
  policy: PoolPolicy
  navHistory: NavPoint[]
  priceHistory: NavPoint[]
}

export interface Investor {
  name: string
  tier: EligibilityTier
  kycStatus: KycStatus
  jurisdiction: string
}
