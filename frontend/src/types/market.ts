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

export type MarketStatus = 'open' | 'restricted' | 'paused'

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

export interface MarketRules {
  tradingWindow: string
  lockupPeriodDays: number
  minHoldingPeriodDays: number
  maxOwnershipPct: number
  transferRestrictions: string
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
  marketStatus: MarketStatus
  rules: MarketRules
  navHistory: NavPoint[]
  priceHistory: NavPoint[]
}

export interface Investor {
  name: string
  tier: EligibilityTier
  kycStatus: KycStatus
  jurisdiction: string
}
