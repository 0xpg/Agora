import type {
  AssetClass,
  MarketRules,
  NavPoint,
  PoolPolicy,
  PoolType,
  TemporaryPolicy,
  TokenizedAsset,
  EligibilityTier,
} from '@/types/market'
import { poolCondition } from '@/utils/quote'

const HOUR = 3600

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

function buildHistory(
  seedKey: string,
  startValue: number,
  driftPerDay: number,
  volatility: number,
  // Where the pool trades relative to NAV, in basis points. The noise around it
  // is small, so this is what decides whether a pool sits mid-range, past its
  // rebalancing guard, or outside its permitted range altogether.
  premiumBps: number,
) {
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
    const price = nav * (1 + premiumBps / 10_000 + spread)
    priceHistory.push({ time, value: Number(price.toFixed(4)) })
  }

  return { navHistory, priceHistory }
}

/**
 * How a pool's policy is written in this fixture: widths and ages relative to
 * NAV and to now, so the fixture stays meaningful whatever price the generator
 * produces. `makeAsset` resolves it into the absolute prices and timestamps the
 * hook actually holds.
 */
interface PolicySpec {
  /** Half-width of the permitted price range, in bps either side of NAV. */
  bandWidthBps: number
  /**
   * Half-width of the range liquidity is actually provided over. Defaults to the
   * permitted band; a real pool concentrates inside it.
   */
  liquidityWidthBps?: number
  baseFeeBps: number
  edgeFeeBps: number
  directionalGuardBps: number
  maxTradeNotional: number
  largeTradeNotional: number
  /** How long ago the issuer published the NAV this pool is anchored to. */
  navAgeSeconds: number
  navMaxAgeSeconds: number
  largeTradeMaxNavAgeSeconds: number
  /** False while the issuer has published a NAV but not yet re-anchored the range. */
  bandSynced?: boolean
  paused?: boolean
  /** A live issuer override, given as a widened range and raised fees. */
  temporary?: { bandWidthBps: number; baseFeeBps: number; edgeFeeBps: number; expiresInSeconds: number }
}

function resolvePolicy(spec: PolicySpec, nav: number, now: number): PoolPolicy {
  const navUpdatedAt = now - spec.navAgeSeconds
  const width = spec.bandWidthBps / 10_000

  let temporaryPolicy: TemporaryPolicy | null = null
  if (spec.temporary) {
    const tempWidth = spec.temporary.bandWidthBps / 10_000
    temporaryPolicy = {
      bandLower: nav * (1 - tempWidth),
      bandUpper: nav * (1 + tempWidth),
      baseFeeBps: spec.temporary.baseFeeBps,
      edgeFeeBps: spec.temporary.edgeFeeBps,
      expiresAt: now + spec.temporary.expiresInSeconds,
    }
  }

  const liquidityWidth = (spec.liquidityWidthBps ?? spec.bandWidthBps) / 10_000

  return {
    bandLower: nav * (1 - width),
    bandUpper: nav * (1 + width),
    liquidityLower: nav * (1 - liquidityWidth),
    liquidityUpper: nav * (1 + liquidityWidth),
    targetPrice: nav,
    baseFeeBps: spec.baseFeeBps,
    edgeFeeBps: spec.edgeFeeBps,
    directionalGuardBps: spec.directionalGuardBps,
    maxTradeNotional: spec.maxTradeNotional,
    largeTradeNotional: spec.largeTradeNotional,
    navUpdatedAt,
    navMaxAgeSeconds: spec.navMaxAgeSeconds,
    largeTradeMaxNavAgeSeconds: spec.largeTradeMaxNavAgeSeconds,
    // An unsynced pool is one whose range still points at the previous NAV.
    bandSyncedNavUpdatedAt: spec.bandSynced === false ? navUpdatedAt - 6 * HOUR : navUpdatedAt,
    paused: spec.paused ?? false,
    temporaryPolicy,
  }
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
  premiumBps: number
  policy: PolicySpec
  yieldPct: number | null
  liquidity: number
  volume30d: number
  poolType: PoolType
  kycRequired: boolean
  totalSupply: number
  minInvestment: number
  requiredTiers: EligibilityTier[]
  rules: MarketRules
}): TokenizedAsset {
  const { navHistory, priceHistory } = buildHistory(
    input.id,
    input.startNav,
    input.driftPerDay,
    input.volatility,
    input.premiumBps,
  )
  const nav = navHistory[navHistory.length - 1]!.value
  const lastPrice = priceHistory[priceHistory.length - 1]!.value
  const prevPrice = priceHistory[priceHistory.length - 2]!.value
  const change24hPct = ((lastPrice - prevPrice) / prevPrice) * 100

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
    rules: input.rules,
    policy: resolvePolicy(input.policy, nav, Math.floor(Date.now() / 1000)),
    navHistory,
    priceHistory,
  }
}

export const mockAssets: TokenizedAsset[] = [
  makeAsset({
    id: 'agora-demo-note',
    symbol: 'ADN',
    name: 'Agora Demo Note',
    assetClass: 'Private Credit',
    issuer: 'Agora',
    domicile: 'United States',
    currency: 'dUSD',
    maturityDate: null,
    startNav: 1,
    driftPerDay: 0,
    volatility: 0,
    premiumBps: 0,
    policy: {
      // The hook's bounds are set on the square root of price — 0.95 and 1.05 of
      // it — which is [0.9025, 1.1025] in price and so not symmetric. This takes
      // the inner width, matching the lower bound exactly and staying inside the
      // upper, so the UI never prices a swap outside what the pool permits.
      bandWidthBps: 975,
      // Liquidity sits in ticks -600..600, which is [0.9418, 1.0618] in price —
      // well inside the permitted band. Depth stops here, not at the band.
      liquidityWidthBps: 582,
      baseFeeBps: 5,
      edgeFeeBps: 50,
      directionalGuardBps: 250,
      maxTradeNotional: 10_000,
      largeTradeNotional: 5_000,
      navAgeSeconds: 0,
      navMaxAgeSeconds: 24 * HOUR,
      largeTradeMaxNavAgeSeconds: HOUR,
    },
    yieldPct: null,
    liquidity: 5_910,
    volume30d: 0,
    poolType: 'nav_managed',
    kycRequired: false,
    totalSupply: 100_000,
    minInvestment: 1,
    requiredTiers: ['accredited', 'qualified_purchaser', 'institutional'],
    rules: {
      lockupPeriodDays: 0,
      minHoldingPeriodDays: 0,
      maxOwnershipPct: 100,
      transferRestrictions: 'Base Sepolia demo access list.',
    },
  }),
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
    premiumBps: -195,
    policy: {
      // Trading below the guard, so the pool takes only buys until price
      // returns toward NAV. NAV is older than large trades are allowed to use.
      bandWidthBps: 250,
      baseFeeBps: 12,
      edgeFeeBps: 120,
      directionalGuardBps: 80,
      maxTradeNotional: 400_000,
      largeTradeNotional: 150_000,
      navAgeSeconds: 3 * HOUR,
      navMaxAgeSeconds: 24 * HOUR,
      largeTradeMaxNavAgeSeconds: HOUR,
    },
    yieldPct: 5.8,
    liquidity: 312_000,
    volume30d: 420_000,
    poolType: 'standard',
    kycRequired: true,
    totalSupply: 2_500_000,
    minInvestment: 25_000,
    requiredTiers: ['accredited', 'qualified_purchaser', 'institutional'],
    rules: {
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
    premiumBps: 60,
    policy: {
      // Running under a temporary issuer override: a wider range and raised
      // fees that lapse on their own.
      bandWidthBps: 200,
      baseFeeBps: 20,
      edgeFeeBps: 150,
      directionalGuardBps: 0,
      maxTradeNotional: 500_000,
      largeTradeNotional: 200_000,
      navAgeSeconds: 2 * HOUR,
      navMaxAgeSeconds: 24 * HOUR,
      largeTradeMaxNavAgeSeconds: 4 * HOUR,
      temporary: { bandWidthBps: 400, baseFeeBps: 45, edgeFeeBps: 300, expiresInSeconds: 45 * 60 },
    },
    yieldPct: 9.75,
    liquidity: 458_000,
    volume30d: 210_000,
    poolType: 'standard',
    kycRequired: true,
    totalSupply: 1_800_000,
    minInvestment: 100_000,
    requiredTiers: ['qualified_purchaser', 'institutional'],
    rules: {
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
    premiumBps: 18,
    policy: {
      // The deepest, healthiest pool — the one Trade opens by default. Its
      // per-swap cap is low enough that oversized trades are easy to hit.
      bandWidthBps: 120,
      baseFeeBps: 6,
      edgeFeeBps: 60,
      directionalGuardBps: 0,
      maxTradeNotional: 250_000,
      largeTradeNotional: 100_000,
      navAgeSeconds: 40 * 60,
      navMaxAgeSeconds: 24 * HOUR,
      largeTradeMaxNavAgeSeconds: 2 * HOUR,
    },
    yieldPct: 4.35,
    liquidity: 890_000,
    volume30d: 1_650_000,
    poolType: 'nav_managed',
    kycRequired: false,
    totalSupply: 5_000_000,
    minInvestment: 1_000,
    requiredTiers: ['retail', 'accredited', 'qualified_purchaser', 'institutional'],
    rules: {
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
    premiumBps: 70,
    policy: {
      // A NAV has just been published and the range is not yet re-anchored to it.
      bandWidthBps: 300,
      baseFeeBps: 30,
      edgeFeeBps: 250,
      directionalGuardBps: 0,
      maxTradeNotional: 200_000,
      largeTradeNotional: 100_000,
      navAgeSeconds: 12 * 60,
      navMaxAgeSeconds: 48 * HOUR,
      largeTradeMaxNavAgeSeconds: 6 * HOUR,
      bandSynced: false,
    },
    yieldPct: null,
    liquidity: 145_000,
    volume30d: 60_000,
    poolType: 'standard',
    kycRequired: true,
    totalSupply: 400_000,
    minInvestment: 50_000,
    requiredTiers: ['qualified_purchaser', 'institutional'],
    rules: {
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
    premiumBps: 45,
    policy: {
      // Paused by the issuer.
      bandWidthBps: 250,
      baseFeeBps: 15,
      edgeFeeBps: 140,
      directionalGuardBps: 100,
      maxTradeNotional: 350_000,
      largeTradeNotional: 150_000,
      navAgeSeconds: 5 * HOUR,
      navMaxAgeSeconds: 24 * HOUR,
      largeTradeMaxNavAgeSeconds: 2 * HOUR,
      paused: true,
    },
    yieldPct: 6.4,
    liquidity: 268_000,
    volume30d: 90_000,
    poolType: 'standard',
    kycRequired: true,
    totalSupply: 3_200_000,
    minInvestment: 20_000,
    requiredTiers: ['accredited', 'qualified_purchaser', 'institutional'],
    rules: {
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
    premiumBps: 25,
    policy: {
      // NAV has gone past its freshness limit, so the pool refuses every swap
      // until the issuer publishes the next one.
      bandWidthBps: 150,
      baseFeeBps: 18,
      edgeFeeBps: 130,
      directionalGuardBps: 60,
      maxTradeNotional: 200_000,
      largeTradeNotional: 75_000,
      navAgeSeconds: 9 * HOUR,
      navMaxAgeSeconds: 6 * HOUR,
      largeTradeMaxNavAgeSeconds: 2 * HOUR,
    },
    yieldPct: 7.15,
    liquidity: 198_000,
    volume30d: 140_000,
    poolType: 'standard',
    kycRequired: true,
    totalSupply: 2_000_000,
    minInvestment: 10_000,
    requiredTiers: ['accredited', 'qualified_purchaser', 'institutional'],
    rules: {
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
    premiumBps: 330,
    policy: {
      // Price has drifted above the permitted range, which stops all trading
      // until liquidity brings it back inside.
      bandWidthBps: 250,
      baseFeeBps: 14,
      edgeFeeBps: 110,
      directionalGuardBps: 90,
      maxTradeNotional: 600_000,
      largeTradeNotional: 250_000,
      navAgeSeconds: 90 * 60,
      navMaxAgeSeconds: 24 * HOUR,
      largeTradeMaxNavAgeSeconds: 3 * HOUR,
    },
    yieldPct: 6.1,
    liquidity: 402_000,
    volume30d: 310_000,
    poolType: 'nav_managed',
    kycRequired: true,
    totalSupply: 4_000_000,
    minInvestment: 250_000,
    requiredTiers: ['institutional'],
    rules: {
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
  return [...mockAssets].filter((asset) => poolCondition(asset) === 'open').sort((a, b) => b.liquidity - a.liquidity)[0]!
}
