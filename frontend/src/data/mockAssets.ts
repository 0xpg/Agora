import type {
  AssetClass,
  MarketRules,
  MarketStatus,
  NavPoint,
  PoolType,
  TokenizedAsset,
  EligibilityTier,
} from '@/types/market'

// Deterministic PRNG so charts stay stable across reloads instead of reshuffling.
function mulberry32(seed: number) {
  let a = seed
  return () => {
    a |= 0
    a = (a + 0x6d2b79f5) | 0
    let t = Math.imul(a ^ (a >>> 15), 1 | a)
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296
  }
}

function hashSeed(input: string): number {
  let hash = 0
  for (let i = 0; i < input.length; i++) {
    hash = (Math.imul(31, hash) + input.charCodeAt(i)) | 0
  }
  return hash
}

const DAY_SECONDS = 86400
const HISTORY_DAYS = 180

function buildHistory(seedKey: string, startValue: number, driftPerDay: number, volatility: number) {
  const rand = mulberry32(hashSeed(seedKey))
  const now = Math.floor(Date.now() / 1000 / DAY_SECONDS) * DAY_SECONDS
  const start = now - HISTORY_DAYS * DAY_SECONDS

  const navHistory: NavPoint[] = []
  const priceHistory: NavPoint[] = []
  let nav = startValue

  for (let i = 0; i <= HISTORY_DAYS; i++) {
    const time = start + i * DAY_SECONDS
    const shock = (rand() - 0.5) * 2 * volatility
    nav = Math.max(nav * (1 + driftPerDay + shock), startValue * 0.4)
    navHistory.push({ time, value: Number(nav.toFixed(4)) })

    // Price trades around NAV with its own smaller-amplitude premium/discount noise.
    const spread = (rand() - 0.5) * 2 * (volatility * 0.6)
    const price = nav * (1 + spread)
    priceHistory.push({ time, value: Number(price.toFixed(4)) })
  }

  return { navHistory, priceHistory }
}

function makeAsset(input: {
  id: string
  symbol: string
  name: string
  assetClass: AssetClass
  issuer: string
  domicile: string
  currency: string
  maturityDate: string | null
  startNav: number
  driftPerDay: number
  volatility: number
  yieldPct: number | null
  liquidity: number
  volume30d: number
  poolType: PoolType
  kycRequired: boolean
  totalSupply: number
  minInvestment: number
  requiredTiers: EligibilityTier[]
  marketStatus: MarketStatus
  rules: MarketRules
}): TokenizedAsset {
  const { navHistory, priceHistory } = buildHistory(input.id, input.startNav, input.driftPerDay, input.volatility)
  const nav = navHistory[navHistory.length - 1]!.value
  const lastPrice = priceHistory[priceHistory.length - 1]!.value
  const prevPrice = priceHistory[priceHistory.length - 2]!.value
  const change24hPct = ((lastPrice - prevPrice) / prevPrice) * 100

  // Stagger each asset's batch-auction round so countdowns don't all line up —
  // 3 to 12 minutes out from module load, deterministic per asset id.
  const roundRand = mulberry32(hashSeed(`${input.id}-round`))
  const roundOffsetSeconds = 180 + Math.floor(roundRand() * (720 - 180))
  const roundClosesAt = Math.floor(Date.now() / 1000) + roundOffsetSeconds

  return {
    id: input.id,
    symbol: input.symbol,
    name: input.name,
    assetClass: input.assetClass,
    issuer: input.issuer,
    domicile: input.domicile,
    currency: input.currency,
    maturityDate: input.maturityDate,
    nav,
    lastPrice,
    change24hPct,
    yieldPct: input.yieldPct,
    liquidity: input.liquidity,
    volume30d: input.volume30d,
    poolType: input.poolType,
    kycRequired: input.kycRequired,
    totalSupply: input.totalSupply,
    minInvestment: input.minInvestment,
    requiredTiers: input.requiredTiers,
    marketStatus: input.marketStatus,
    rules: input.rules,
    navHistory,
    priceHistory,
    roundClosesAt,
  }
}

export const mockAssets: TokenizedAsset[] = [
  makeAsset({
    id: 'meridian-tower',
    symbol: 'MTWR',
    name: 'Meridian Tower',
    assetClass: 'Commercial Real Estate',
    issuer: 'Meridian Capital Partners',
    domicile: 'United States',
    currency: 'USD',
    maturityDate: null,
    startNav: 102,
    driftPerDay: 0.0003,
    volatility: 0.006,
    yieldPct: 5.8,
    liquidity: 312_000,
    volume30d: 420_000,
    poolType: 'standard',
    kycRequired: true,
    totalSupply: 2_500_000,
    minInvestment: 25_000,
    requiredTiers: ['accredited', 'qualified_purchaser', 'institutional'],
    marketStatus: 'open',
    rules: {
      tradingWindow: 'Mon-Fri, 09:00-16:00 ET',
      lockupPeriodDays: 90,
      minHoldingPeriodDays: 30,
      maxOwnershipPct: 5,
      transferRestrictions: 'Transfers to non-qualified investors require issuer approval.',
    },
  }),
  makeAsset({
    id: 'atlas-private-credit',
    symbol: 'APC1',
    name: 'Atlas Private Credit Fund I',
    assetClass: 'Private Credit',
    issuer: 'Atlas Credit Partners',
    domicile: 'Cayman Islands',
    currency: 'USD',
    maturityDate: '2029-06-30',
    startNav: 98,
    driftPerDay: 0.00025,
    volatility: 0.003,
    yieldPct: 9.75,
    liquidity: 458_000,
    volume30d: 210_000,
    poolType: 'standard',
    kycRequired: true,
    totalSupply: 1_800_000,
    minInvestment: 100_000,
    requiredTiers: ['qualified_purchaser', 'institutional'],
    marketStatus: 'open',
    rules: {
      tradingWindow: 'Mon-Fri, 09:00-16:00 ET',
      lockupPeriodDays: 180,
      minHoldingPeriodDays: 90,
      maxOwnershipPct: 10,
      transferRestrictions: 'Restricted to Qualified Purchasers per fund offering memorandum.',
    },
  }),
  makeAsset({
    id: 'ust-2y-ladder',
    symbol: 'UST2Y',
    name: 'UST 2Y Ladder Note',
    assetClass: 'US Treasuries',
    issuer: 'Agora Treasury Desk',
    domicile: 'United States',
    currency: 'USD',
    maturityDate: '2028-03-15',
    startNav: 100,
    driftPerDay: 0.00012,
    volatility: 0.0012,
    yieldPct: 4.35,
    liquidity: 890_000,
    volume30d: 1_650_000,
    poolType: 'nav_managed',
    kycRequired: false,
    totalSupply: 5_000_000,
    minInvestment: 1_000,
    requiredTiers: ['retail', 'accredited', 'qualified_purchaser', 'institutional'],
    marketStatus: 'open',
    rules: {
      tradingWindow: '24/5, market hours align with US Treasury market',
      lockupPeriodDays: 0,
      minHoldingPeriodDays: 1,
      maxOwnershipPct: 2,
      transferRestrictions: 'No transfer restrictions beyond standard KYC/AML checks.',
    },
  }),
  makeAsset({
    id: 'vermeer-collection-trust',
    symbol: 'VMCT',
    name: 'Vermeer Collection Trust',
    assetClass: 'Fine Art',
    issuer: 'Custodia Fine Art Trust',
    domicile: 'Luxembourg',
    currency: 'EUR',
    maturityDate: null,
    startNav: 250,
    driftPerDay: 0.0004,
    volatility: 0.004,
    yieldPct: null,
    liquidity: 145_000,
    volume30d: 60_000,
    poolType: 'standard',
    kycRequired: true,
    totalSupply: 400_000,
    minInvestment: 50_000,
    requiredTiers: ['qualified_purchaser', 'institutional'],
    marketStatus: 'open',
    rules: {
      tradingWindow: 'Mon-Fri, 09:00-16:00 ET',
      lockupPeriodDays: 365,
      minHoldingPeriodDays: 180,
      maxOwnershipPct: 15,
      transferRestrictions: 'Right of first refusal held by issuer on all secondary transfers.',
    },
  }),
  makeAsset({
    id: 'helios-solar-infra',
    symbol: 'HSOL',
    name: 'Helios Solar Infrastructure',
    assetClass: 'Infrastructure',
    issuer: 'Helios Infra Holdings',
    domicile: 'United States',
    currency: 'USD',
    maturityDate: '2045-12-31',
    startNav: 110,
    driftPerDay: 0.00035,
    volatility: 0.0035,
    yieldPct: 6.4,
    liquidity: 268_000,
    volume30d: 90_000,
    poolType: 'standard',
    kycRequired: true,
    totalSupply: 3_200_000,
    minInvestment: 20_000,
    requiredTiers: ['accredited', 'qualified_purchaser', 'institutional'],
    marketStatus: 'paused',
    rules: {
      tradingWindow: 'Mon-Fri, 09:00-16:00 ET',
      lockupPeriodDays: 60,
      minHoldingPeriodDays: 30,
      maxOwnershipPct: 8,
      transferRestrictions: 'Trading paused during quarterly NAV recalculation.',
    },
  }),
  makeAsset({
    id: 'pacific-trade-finance-pool',
    symbol: 'PTFP',
    name: 'Pacific Trade Finance Pool',
    assetClass: 'Trade Finance',
    issuer: 'Pacific Trade Finance Co',
    domicile: 'Singapore',
    currency: 'USD',
    maturityDate: '2027-01-31',
    startNav: 100,
    driftPerDay: 0.0002,
    volatility: 0.0015,
    yieldPct: 7.15,
    liquidity: 198_000,
    volume30d: 140_000,
    poolType: 'standard',
    kycRequired: true,
    totalSupply: 2_000_000,
    minInvestment: 10_000,
    requiredTiers: ['accredited', 'qualified_purchaser', 'institutional'],
    marketStatus: 'restricted',
    rules: {
      tradingWindow: 'Mon-Fri, 09:00-16:00 ET',
      lockupPeriodDays: 45,
      minHoldingPeriodDays: 30,
      maxOwnershipPct: 10,
      transferRestrictions: 'Trading temporarily restricted pending issuer compliance review.',
    },
  }),
  makeAsset({
    id: 'cascade-logistics-reit',
    symbol: 'CLRT',
    name: 'Cascade Logistics REIT',
    assetClass: 'Commercial Real Estate',
    issuer: 'Cascade Realty Partners',
    domicile: 'United States',
    currency: 'USD',
    maturityDate: null,
    startNav: 95,
    driftPerDay: 0.00028,
    volatility: 0.0045,
    yieldPct: 6.1,
    liquidity: 402_000,
    volume30d: 310_000,
    poolType: 'nav_managed',
    kycRequired: true,
    totalSupply: 4_000_000,
    minInvestment: 250_000,
    requiredTiers: ['institutional'],
    marketStatus: 'open',
    rules: {
      tradingWindow: 'Mon-Fri, 09:00-16:00 ET',
      lockupPeriodDays: 90,
      minHoldingPeriodDays: 60,
      maxOwnershipPct: 20,
      transferRestrictions: 'Restricted to institutional investors per issuer placement terms.',
    },
  }),
]

export function getAssetById(id: string): TokenizedAsset | undefined {
  return mockAssets.find((asset) => asset.id === id)
}

// "Trade" has no listing page of its own — it jumps straight into the most liquid open market.
export function getDefaultTradeAsset(): TokenizedAsset {
  return [...mockAssets].filter((asset) => asset.marketStatus === 'open').sort((a, b) => b.liquidity - a.liquidity)[0]!
}
