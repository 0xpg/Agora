import type { PoolPolicy, TokenizedAsset } from '@/types/market'
import { formatCurrency, formatDuration } from '@/utils/format'

/**
 * Quoting for one NAV-anchored concentrated-liquidity pool.
 *
 * The pool holds a single liquidity position spanning the issuer's permitted
 * price range, so a swap moves price along the constant-product curve between
 * the range ends. Everything here mirrors `AgoraHook`: the fee curve, the
 * rebalancing guard and the range checks are computed on the square root of
 * price, as the hook does, so a quote refuses exactly what a swap would revert
 * on.
 *
 * Prices are quote currency per asset token. The pool's own token ordering is an
 * on-chain detail; in here "sell" always means asset in, quote out (which moves
 * price down) and "buy" means quote in, asset out (which moves price up).
 *
 * These are display quotes computed off pool state. Execution must re-quote
 * through the permissioned router, which is the only route that establishes the
 * eligible end user.
 */

const BPS = 10_000

/** Which way the investor is trading the asset token. */
export type SwapSide = 'buy' | 'sell'

/** Whether the amount the investor typed is what they pay or what they receive. */
export type QuoteMode = 'exactIn' | 'exactOut'

export function nowSeconds(): number {
  return Math.floor(Date.now() / 1000)
}

/**
 * The price range and fee curve in force right now — the standing policy, or a
 * temporary override while one has not yet expired. Mirrors
 * `AgoraHook.activePolicy()`.
 */
export interface ActivePolicy {
  bandLower: number
  bandUpper: number
  baseFeeBps: number
  edgeFeeBps: number
  /** True while a temporary issuer override is in force. */
  temporary: boolean
  /** When that override lapses, or null when the standing policy applies. */
  expiresAt: number | null
}

export function activePolicy(policy: PoolPolicy, now = nowSeconds()): ActivePolicy {
  const temp = policy.temporaryPolicy
  if (temp && temp.expiresAt > now) {
    return {
      bandLower: temp.bandLower,
      bandUpper: temp.bandUpper,
      baseFeeBps: temp.baseFeeBps,
      edgeFeeBps: temp.edgeFeeBps,
      temporary: true,
      expiresAt: temp.expiresAt,
    }
  }
  return {
    bandLower: policy.bandLower,
    bandUpper: policy.bandUpper,
    baseFeeBps: policy.baseFeeBps,
    edgeFeeBps: policy.edgeFeeBps,
    temporary: false,
    expiresAt: null,
  }
}

/**
 * The fee a swap starting at `price` would pay, in basis points. Lowest at the
 * target price and rising linearly to the edge fee at whichever end of the range
 * the price sits nearer. Mirrors `AgoraHook._feeAt`, which interpolates on the
 * square root of price and is evaluated on the pre-swap price — so one swap pays
 * one fee rate throughout.
 */
export function feeBpsAt(price: number, active: ActivePolicy, targetPrice: number): number {
  const lower = Math.sqrt(active.bandLower)
  const upper = Math.sqrt(active.bandUpper)
  const mid = targetPrice > 0 ? Math.sqrt(targetPrice) : (lower + upper) / 2
  const sqrtPrice = Math.sqrt(price)

  const span = sqrtPrice > mid ? upper - mid : mid - lower
  if (span <= 0) return active.edgeFeeBps
  const distance = Math.min(Math.abs(sqrtPrice - mid), span)
  return active.baseFeeBps + ((active.edgeFeeBps - active.baseFeeBps) * distance) / span
}

/**
 * The prices at which the rebalancing guard starts refusing one direction. The
 * hook offsets the *square root* of the target price by `directionalGuardBps`,
 * so converting back gives a slightly asymmetric pair in price terms — which is
 * what the pool actually enforces.
 */
export interface GuardZone {
  lower: number
  upper: number
  enabled: boolean
}

export function guardZone(policy: PoolPolicy): GuardZone {
  if (policy.directionalGuardBps === 0 || policy.targetPrice <= 0) {
    return { lower: policy.bandLower, upper: policy.bandUpper, enabled: false }
  }
  const mid = Math.sqrt(policy.targetPrice)
  return {
    lower: ((mid * (BPS - policy.directionalGuardBps)) / BPS) ** 2,
    upper: ((mid * (BPS + policy.directionalGuardBps)) / BPS) ** 2,
    enabled: true,
  }
}

/**
 * The prices a swap can actually be filled at: where liquidity exists, bounded
 * by where price is permitted. Depth stops at whichever end comes first.
 */
export function tradableRange(policy: PoolPolicy, active: ActivePolicy): { lower: number; upper: number } {
  return {
    lower: Math.max(policy.liquidityLower, active.bandLower),
    upper: Math.min(policy.liquidityUpper, active.bandUpper),
  }
}

/**
 * Virtual liquidity for the range position, back-solved from the pool's reported
 * value. A concentrated position of liquidity `L` over [`lower`, `upper`] holds
 * `L * (1/√p - 1/√upper)` asset tokens and `L * (√p - √lower)` of quote; setting
 * the value of the two equal to `tvl` pins `L`.
 */
export function poolLiquidity(tvl: number, price: number, lower: number, upper: number): number {
  const sqrtPrice = Math.sqrt(price)
  const assetLeg = price * (1 / sqrtPrice - 1 / Math.sqrt(upper))
  const quoteLeg = sqrtPrice - Math.sqrt(lower)
  const perUnit = assetLeg + quoteLeg
  return perUnit > 0 ? tvl / perUnit : 0
}

/** How much the range can still absorb before price reaches one of its ends. */
export interface RangeDepth {
  /** Asset tokens the pool can still sell (a buy) before price hits the top. */
  assetOut: number
  /** Quote the pool can still take in (a buy) before price hits the top. */
  quoteIn: number
  /** Asset tokens the pool can still take in (a sell) before price hits the bottom. */
  assetIn: number
  /** Quote the pool can still pay out (a sell) before price hits the bottom. */
  quoteOut: number
}

export function rangeDepth(liquidity: number, price: number, range: { lower: number; upper: number }): RangeDepth {
  const sqrtPrice = Math.sqrt(price)
  const lower = Math.sqrt(range.lower)
  const upper = Math.sqrt(range.upper)
  return {
    assetOut: Math.max(liquidity * (1 / sqrtPrice - 1 / upper), 0),
    quoteIn: Math.max(liquidity * (upper - sqrtPrice), 0),
    assetIn: Math.max(liquidity * (1 / lower - 1 / sqrtPrice), 0),
    quoteOut: Math.max(liquidity * (sqrtPrice - lower), 0),
  }
}

export interface Quote {
  side: SwapSide
  mode: QuoteMode
  /** Asset tokens leaving or entering the investor's wallet. */
  assetAmount: number
  /** Quote currency entering or leaving it. */
  quoteAmount: number
  /** What the investor pays, in the input token. Fee included. */
  amountIn: number
  /** What they receive, in the output token. */
  amountOut: number
  /** Fee rate this swap pays, set by where price sits in the range. */
  feeBps: number
  /** The fee itself, in the input token. */
  feeAmount: number
  /** Pool price before the swap. */
  spotPrice: number
  /** Average price actually paid per asset token, fee excluded. */
  executionPrice: number
  /** Where the swap leaves the pool price. */
  postSwapPrice: number
  /** How far the curve moves the price against the trader, as a percentage. */
  priceImpactPct: number
  /** The quote-currency size of the trade, which the pool's caps are measured against. */
  notional: number
  /** Worst output accepted, or worst input paid, at the chosen slippage tolerance. */
  slippageBound: number
}

export interface QuoteInput {
  asset: TokenizedAsset
  side: SwapSide
  mode: QuoteMode
  /** The figure the investor typed, read as input or output per `mode`. */
  amount: number
  slippageBps: number
  now?: number
}

/**
 * Prices a swap against the range position. Returns null when there is nothing
 * to price, or when the trade is larger than the range can fill — the depth cap
 * is reported as a blocker instead, by `assessSwap`.
 */
export function quoteSwap(input: QuoteInput): Quote | null {
  const { asset, side, mode, amount, slippageBps } = input
  if (!(amount > 0)) return null

  const active = activePolicy(asset.policy, input.now ?? nowSeconds())
  const spotPrice = asset.lastPrice
  const range = tradableRange(asset.policy, active)
  const liquidity = poolLiquidity(asset.liquidity, spotPrice, range.lower, range.upper)
  if (liquidity <= 0) return null

  const feeBps = feeBpsAt(spotPrice, active, asset.policy.targetPrice)
  const feeRate = feeBps / BPS
  if (feeRate >= 1) return null

  const sqrtPrice = Math.sqrt(spotPrice)
  const sqrtLower = Math.sqrt(range.lower)
  const sqrtUpper = Math.sqrt(range.upper)

  let assetAmount: number
  let quoteAmount: number
  let amountIn: number
  let amountOut: number
  let feeAmount: number
  let sqrtPost: number

  if (side === 'buy') {
    // Quote in, asset out. Price rises.
    if (mode === 'exactIn') {
      amountIn = amount
      feeAmount = amountIn * feeRate
      const netIn = amountIn - feeAmount
      sqrtPost = sqrtPrice + netIn / liquidity
      if (sqrtPost > sqrtUpper) return null
      amountOut = liquidity * (1 / sqrtPrice - 1 / sqrtPost)
      quoteAmount = amountIn
      assetAmount = amountOut
    } else {
      amountOut = amount
      // √p' = L / (L/√p - Δx); the subtraction underflows once the ask exceeds
      // what the range holds, which `sqrtPost > sqrtUpper` then rejects.
      const denominator = liquidity / sqrtPrice - amountOut
      if (denominator <= 0) return null
      sqrtPost = liquidity / denominator
      if (sqrtPost > sqrtUpper) return null
      const netIn = liquidity * (sqrtPost - sqrtPrice)
      amountIn = netIn / (1 - feeRate)
      feeAmount = amountIn - netIn
      quoteAmount = amountIn
      assetAmount = amountOut
    }
  } else {
    // Asset in, quote out. Price falls.
    if (mode === 'exactIn') {
      amountIn = amount
      feeAmount = amountIn * feeRate
      const netIn = amountIn - feeAmount
      sqrtPost = liquidity / (liquidity / sqrtPrice + netIn)
      if (sqrtPost < sqrtLower) return null
      amountOut = liquidity * (sqrtPrice - sqrtPost)
      assetAmount = amountIn
      quoteAmount = amountOut
    } else {
      amountOut = amount
      sqrtPost = sqrtPrice - amountOut / liquidity
      if (sqrtPost < sqrtLower) return null
      const netIn = liquidity * (1 / sqrtPost - 1 / sqrtPrice)
      amountIn = netIn / (1 - feeRate)
      feeAmount = amountIn - netIn
      assetAmount = amountIn
      quoteAmount = amountOut
    }
  }

  if (!Number.isFinite(amountIn) || !Number.isFinite(amountOut) || amountOut <= 0) return null

  // Impact is measured on the curve alone, with the fee taken out, so the two
  // costs read as separate lines rather than one compounding into the other.
  const netQuote = side === 'buy' ? quoteAmount - feeAmount : quoteAmount
  const netAsset = side === 'sell' ? assetAmount - feeAmount : assetAmount
  const executionPrice = netAsset > 0 ? netQuote / netAsset : spotPrice
  const priceImpactPct = Math.abs(executionPrice / spotPrice - 1) * 100

  const slippage = slippageBps / BPS
  const slippageBound = mode === 'exactIn' ? amountOut * (1 - slippage) : amountIn * (1 + slippage)

  return {
    side,
    mode,
    assetAmount,
    quoteAmount,
    amountIn,
    amountOut,
    feeBps,
    feeAmount,
    spotPrice,
    executionPrice,
    postSwapPrice: sqrtPost ** 2,
    priceImpactPct,
    notional: quoteAmount,
    slippageBound,
  }
}

/**
 * The pool's live condition, independent of any particular trade — what a status
 * badge shows and what the trade page leads with.
 */
export type PoolCondition = 'open' | 'paused' | 'nav_update' | 'outside_band' | 'rebalance_only'

/**
 * Ordered by how completely each condition stops trading, so a badge shows the
 * most limiting one. `rebalance_only` comes last because one direction still trades.
 */
export function poolCondition(asset: TokenizedAsset, now = nowSeconds()): PoolCondition {
  const policy = asset.policy
  if (policy.paused) return 'paused'
  if (now - policy.navUpdatedAt > policy.navMaxAgeSeconds) return 'nav_update'
  if (policy.bandSyncedNavUpdatedAt !== policy.navUpdatedAt) return 'nav_update'

  const active = activePolicy(policy, now)
  if (asset.lastPrice < active.bandLower || asset.lastPrice > active.bandUpper) return 'outside_band'

  const guard = guardZone(policy)
  if (guard.enabled && (asset.lastPrice <= guard.lower || asset.lastPrice >= guard.upper)) {
    return 'rebalance_only'
  }
  return 'open'
}

/**
 * True when the pool will take at least one direction. Under the rebalancing
 * guard only one side trades, which still counts — unlike a paused, halted or
 * mid-NAV-update pool, which takes nothing.
 */
export function isTradablePool(asset: TokenizedAsset, now = nowSeconds()): boolean {
  const condition = poolCondition(asset, now)
  return condition === 'open' || condition === 'rebalance_only'
}

/** Which side the rebalancing guard still accepts, or null when both trade. */
export function permittedSide(asset: TokenizedAsset): SwapSide | null {
  const guard = guardZone(asset.policy)
  if (!guard.enabled) return null
  if (asset.lastPrice <= guard.lower) return 'buy'
  if (asset.lastPrice >= guard.upper) return 'sell'
  return null
}

/**
 * The largest trade the pool would accept right now, as quote-currency
 * notional, or null when nothing caps it. That is the per-swap limit — and,
 * once NAV is already too old to satisfy the large-trade rule, the threshold
 * that rule starts at, since everything from there up is refused.
 */
export function notionalCeiling(policy: PoolPolicy, now = nowSeconds()): number | null {
  const navAge = Math.max(now - policy.navUpdatedAt, 0)
  const limits: number[] = []
  if (policy.maxTradeNotional > 0) limits.push(policy.maxTradeNotional)
  if (policy.largeTradeNotional > 0 && navAge > policy.largeTradeMaxNavAgeSeconds) {
    limits.push(policy.largeTradeNotional)
  }
  return limits.length > 0 ? Math.min(...limits) : null
}

/**
 * Both ceilings land a trade exactly on a boundary the pool compares against,
 * where rounding decides which side of it the trade falls. Offering slightly
 * less keeps a "max" amount from quoting as a refusal.
 */
const INSIDE_EDGE = 0.9995

/**
 * The largest amount that can go in the "you pay" field and still clear:
 * whichever binds first, the depth left in the permitted range or the pool's
 * notional ceiling. Null when the pool cannot take this direction at all.
 */
export function maxPayAmount(
  asset: TokenizedAsset,
  side: SwapSide,
  slippageBps: number,
  now = nowSeconds(),
): number | null {
  const active = activePolicy(asset.policy, now)
  const range = tradableRange(asset.policy, active)
  const liquidity = poolLiquidity(asset.liquidity, asset.lastPrice, range.lower, range.upper)
  if (liquidity <= 0) return null

  const depth = rangeDepth(liquidity, asset.lastPrice, range)
  const feeRate = feeBpsAt(asset.lastPrice, active, asset.policy.targetPrice) / BPS
  if (feeRate >= 1) return null
  const ceiling = notionalCeiling(asset.policy, now)

  if (side === 'buy') {
    // Buying pays in the quote currency, so the notional ceiling applies to the
    // field directly.
    const byDepth = depth.quoteIn / (1 - feeRate)
    const limit = (ceiling === null ? byDepth : Math.min(byDepth, ceiling)) * INSIDE_EDGE
    return limit > 0 ? limit : null
  }

  // Selling is measured on the quote currency it pays out, so the ceiling on the
  // asset side is whatever input produces that much output.
  const targetOut = (ceiling === null ? depth.quoteOut : Math.min(depth.quoteOut, ceiling)) * INSIDE_EDGE
  if (!(targetOut > 0)) return null
  const edge = quoteSwap({ asset, side: 'sell', mode: 'exactOut', amount: targetOut, slippageBps, now })
  return edge?.amountIn ?? null
}

export type SwapBlockerCode =
  | 'paused'
  | 'stale_nav'
  | 'band_unsynced'
  | 'stale_nav_large_trade'
  | 'price_outside_band'
  | 'trade_exceeds_max'
  | 'rebalance_only'
  | 'exceeds_range_depth'

export interface SwapBlocker {
  code: SwapBlockerCode
  title: string
  /** What it means and what the investor can do, in one or two sentences. */
  detail: string
  /**
   * True when the pool refuses every trade right now, false when it is this
   * particular trade that is refused. Drives whether the panel hides the form or
   * just marks the amount.
   */
  poolWide: boolean
  /**
   * The largest amount that would clear, in whichever unit the investor is
   * typing. Set only where there is a figure to offer them.
   */
  maxAmount?: number
}

export interface SwapAssessment {
  quote: Quote | null
  active: ActivePolicy
  guard: GuardZone
  depth: RangeDepth
  feeBps: number
  navAgeSeconds: number
  /** Everything refusing this trade, most fundamental first. */
  blockers: SwapBlocker[]
  /** Conditions worth flagging that do not refuse the trade. */
  warnings: SwapBlocker[]
  /** True when the pool is open and the trade as entered would be accepted. */
  tradable: boolean
}

/**
 * Everything the swap panel needs to decide what to show: the quote, the pool's
 * live limits, and every reason the pool would refuse. Checks run in the hook's
 * own order, so the first blocker is the one a submitted swap would revert on.
 */
export function assessSwap(input: QuoteInput): SwapAssessment {
  const { asset } = input
  const policy = asset.policy
  const now = input.now ?? nowSeconds()
  const active = activePolicy(policy, now)
  const guard = guardZone(policy)
  const range = tradableRange(policy, active)
  const liquidity = poolLiquidity(asset.liquidity, asset.lastPrice, range.lower, range.upper)
  const depth = rangeDepth(liquidity, asset.lastPrice, range)
  const feeBps = feeBpsAt(asset.lastPrice, active, policy.targetPrice)
  const navAgeSeconds = Math.max(now - policy.navUpdatedAt, 0)
  const quote = quoteSwap({ ...input, now })

  const blockers: SwapBlocker[] = []
  const warnings: SwapBlocker[] = []

  if (policy.paused) {
    blockers.push({
      code: 'paused',
      title: 'Trading is paused',
      detail: `${asset.issuer} has paused this pool. Swaps reopen once the issuer unpauses it — no action is needed from you.`,
      poolWide: true,
    })
  }

  if (navAgeSeconds > policy.navMaxAgeSeconds) {
    blockers.push({
      code: 'stale_nav',
      title: 'NAV is out of date',
      detail: `Swaps need a NAV published within ${formatDuration(policy.navMaxAgeSeconds)}; the last one is ${formatDuration(navAgeSeconds)} old. Trading resumes when ${asset.issuer} publishes the next NAV.`,
      poolWide: true,
    })
  } else if (policy.bandSyncedNavUpdatedAt !== policy.navUpdatedAt) {
    blockers.push({
      code: 'band_unsynced',
      title: 'Price range is being re-anchored',
      detail: `A new NAV has been published and ${asset.issuer} is re-anchoring the permitted price range to it. Swaps are refused for the few minutes this takes.`,
      poolWide: true,
    })
  }

  const priceOutsideBand = asset.lastPrice < active.bandLower || asset.lastPrice > active.bandUpper
  if (priceOutsideBand) {
    blockers.push({
      code: 'price_outside_band',
      title: 'Pool price is outside its permitted range',
      detail: 'The pool has moved beyond the range the issuer permits, so every swap is refused until liquidity brings price back inside it.',
      poolWide: true,
    })
  }

  // Trade-specific checks, measured on notional. When the amount the investor
  // typed is itself the quote-currency leg, the notional is known even if the
  // trade is too big for the curve to price — so the cap can still be named,
  // which is the more useful message of the two.
  const typedInQuoteCurrency = (input.mode === 'exactIn') === (input.side === 'buy')
  const notional = quote?.notional ?? (typedInQuoteCurrency ? input.amount : null)

  if (notional !== null) {
    if (policy.maxTradeNotional > 0 && notional > policy.maxTradeNotional) {
      blockers.push({
        code: 'trade_exceeds_max',
        title: 'Trade is above the per-swap limit',
        detail: `This pool caps a single swap at ${formatCurrency(policy.maxTradeNotional, asset.currency, 0)}. Split it into smaller swaps to trade the full size.`,
        poolWide: false,
      })
    }

    const isLargeTrade = policy.largeTradeNotional > 0 && notional >= policy.largeTradeNotional
    if (isLargeTrade && navAgeSeconds > policy.largeTradeMaxNavAgeSeconds) {
      blockers.push({
        code: 'stale_nav_large_trade',
        title: 'Too large for the current NAV',
        detail: `Trades of this size need a NAV published within ${formatDuration(policy.largeTradeMaxNavAgeSeconds)}; the last one is ${formatDuration(navAgeSeconds)} old. Trade a smaller size, or wait for the next NAV.`,
        poolWide: false,
      })
    } else if (isLargeTrade) {
      warnings.push({
        code: 'stale_nav_large_trade',
        title: 'Large trade',
        detail: `At this size the pool requires NAV to be newer than ${formatDuration(policy.largeTradeMaxNavAgeSeconds)}. It is ${formatDuration(navAgeSeconds)} old, so the trade is accepted — but a slow confirmation could age it out.`,
        poolWide: false,
      })
    }
  }

  // The guard depends only on direction, so it is reported as soon as a side is
  // chosen. Selling pushes price down, buying pushes it up; past the guard the
  // pool takes only the direction that moves price back toward target.
  const blockedBySell = guard.enabled && asset.lastPrice <= guard.lower && input.side === 'sell'
  const blockedByBuy = guard.enabled && asset.lastPrice >= guard.upper && input.side === 'buy'
  if (blockedBySell || blockedByBuy) {
    blockers.push({
      code: 'rebalance_only',
      title: `Only ${blockedBySell ? 'buys' : 'sells'} are accepted right now`,
      detail: `Pool price has moved far enough from NAV that the pool accepts only swaps bringing it back. ${blockedBySell ? 'Selling' : 'Buying'} would push it further out, so it is refused until price returns toward NAV.`,
      poolWide: false,
    })
  }

  // A null quote on a positive amount means the curve could not fill it inside
  // the range — the only reason `quoteSwap` declines an otherwise valid request.
  if (!quote && input.amount > 0 && liquidity > 0 && !priceOutsideBand) {
    // The depth figures are the curve's own, before fees. The cap on what the
    // investor may type has to include the fee when the fee comes off the input.
    const feeRate = feeBps / BPS
    const cap =
      input.mode === 'exactIn'
        ? (input.side === 'buy' ? depth.quoteIn : depth.assetIn) / (1 - feeRate)
        : input.side === 'buy'
          ? depth.assetOut
          : depth.quoteOut
    const unit = typedInQuoteCurrency ? asset.currency : asset.symbol
    blockers.push({
      code: 'exceeds_range_depth',
      title: 'Trade is larger than the range can fill',
      detail: `Filling it would push price outside the permitted range. The most this pool can take in one swap right now is about ${cap.toLocaleString('en-US', { maximumFractionDigits: 2 })} ${unit}.`,
      poolWide: false,
      /** The largest amount, in the units the investor is typing, that would clear. */
      maxAmount: cap,
    })
  }

  return {
    quote,
    active,
    guard,
    depth,
    feeBps,
    navAgeSeconds,
    blockers,
    warnings,
    tradable: blockers.length === 0 && quote !== null,
  }
}
