import {
  decodeEventLog,
  encodeFunctionData,
  formatUnits,
  parseUnits,
  type Address,
  type Hex,
  type TransactionReceipt,
} from 'viem'
import type { WalletStore } from '@/stores/wallet'
import { TARGET_CHAIN } from '@/config/chain'
import {
  assetTokenAbi,
  erc20Abi,
  identityRegistryAbi,
  mintableAbi,
  publicClient,
  readAllowance,
  readBalance,
  readDecimals,
  swapRouterAbi,
} from '@/execution/chain'
import { assetIsCurrency0, zeroForOne, type DeployedMarket } from '@/execution/market'
import { describeExecutionError } from '@/execution/errors'
import type { PreparationStep, SwapExecutor, SwapFailure, SwapRequest } from '@/composables/useSwapTransaction'

const MAX_UINT256 = 2n ** 256n - 1n

// The ends of the range a v4 pool can price in. A swap's price limit has to sit
// strictly inside them, and strictly on the far side of the current price.
const MIN_SQRT_PRICE = 4295128739n
const MAX_SQRT_PRICE = 1461446703485210103287273052203988822378723970342n

/**
 * The worst pool price this swap may reach, as a Q64.96 square root. It is the
 * on-chain half of slippage protection: the pool stops rather than filling past
 * it.
 *
 * Derived from the quote the investor reviewed, then constrained twice. It is
 * forced strictly onto the correct side of the current price, so a valid trade
 * cannot revert merely because rounding put the bound on the wrong side. And it
 * is kept inside the issuer's permitted band — a limit beyond the band lets
 * price settle outside it, which the hook checks after the swap and reverts.
 */
export function priceLimit(input: {
  spotPrice: number
  postSwapPrice: number
  slippageBps: number
  /** True when a rising pool price is what this trade causes. */
  priceRises: boolean
  /** The ends of the band the pool permits, which the limit may not cross. */
  bandLower: number
  bandUpper: number
}): bigint {
  // A non-finite bound would become NaN and then an invalid BigInt, so the
  // fallback is the widest limit the pool allows.
  if (!Number.isFinite(input.spotPrice) || !Number.isFinite(input.bandLower) || !Number.isFinite(input.bandUpper)) {
    return input.priceRises ? MAX_SQRT_PRICE - 1n : MIN_SQRT_PRICE + 1n
  }

  const slip = input.slippageBps / 10_000
  const bound = input.priceRises
    ? Math.max(input.postSwapPrice, input.spotPrice) * (1 + slip)
    : Math.min(input.postSwapPrice, input.spotPrice) * (1 - slip)

  const sqrtBound = BigInt(Math.floor(Math.sqrt(Math.max(bound, 0)) * 2 ** 96))
  const sqrtSpot = BigInt(Math.floor(Math.sqrt(Math.max(input.spotPrice, 0)) * 2 ** 96))

  // Held a hair inside the band rather than exactly on it: the band the UI holds
  // comes from a float, and the hook compares against its own exact value.
  const INSIDE_BAND = 1e-6
  const sqrtBandLow = BigInt(Math.ceil(Math.sqrt(Math.max(input.bandLower, 0)) * (1 + INSIDE_BAND) * 2 ** 96))
  const sqrtBandHigh = BigInt(Math.floor(Math.sqrt(Math.max(input.bandUpper, 0)) * (1 - INSIDE_BAND) * 2 ** 96))

  if (input.priceRises) {
    // Must exceed the current price, without passing the top of the band.
    const floor = sqrtSpot + 1n
    const capped = sqrtBound < sqrtBandHigh ? sqrtBound : sqrtBandHigh
    return bigintClamp(capped > floor ? capped : floor, MIN_SQRT_PRICE + 1n, MAX_SQRT_PRICE - 1n)
  }
  const ceiling = sqrtSpot - 1n
  const floored = sqrtBound > sqrtBandLow ? sqrtBound : sqrtBandLow
  return bigintClamp(floored < ceiling ? floored : ceiling, MIN_SQRT_PRICE + 1n, MAX_SQRT_PRICE - 1n)
}

function bigintClamp(value: bigint, low: bigint, high: bigint): bigint {
  if (value < low) return low
  return value > high ? high : value
}

/**
 * Display units to base units. A double holds about 15 significant digits, so
 * `toFixed(18)` on one prints its binary tail — 1234.567891 comes out as
 * 1234.567890999999917767. Rounding to 15 digits first and handing the decimal
 * string to `parseUnits` keeps the number the investor actually typed.
 */
export function toBaseUnits(value: number, decimals: number): bigint {
  if (!Number.isFinite(value) || value <= 0) return 0n
  const rounded = Number(value.toPrecision(15))
  const text = String(rounded)
  // Exponential notation ("1e-18") is not a decimal string; those go the long way.
  return parseUnits(text.includes('e') ? rounded.toFixed(decimals) : text, decimals)
}

/**
 * Base units back to display units. Goes through the exact decimal string rather
 * than dividing, which for an 18-decimal balance of 100000 would otherwise
 * render as 99999.99999999999.
 */
export function fromBaseUnits(value: bigint, decimals: number): number {
  return Number(formatUnits(value, decimals))
}

/**
 * A v4 `BalanceDelta` packs both currencies into one int256: `amount0` in the
 * high 128 bits, `amount1` in the low. Each is signed, and positive means the
 * caller receives.
 */
export function unpackBalanceDelta(packed: bigint): { amount0: bigint; amount1: bigint } {
  const mask = (1n << 128n) - 1n
  const toSigned = (v: bigint) => (v >= 1n << 127n ? v - (1n << 128n) : v)
  return { amount0: toSigned(packed >> 128n), amount1: toSigned(packed & mask) }
}

/** What actually happened on chain, read back from the mined transaction. */
export interface ExecutionOutcome {
  hash: Hex
  status: 'success' | 'reverted'
  blockNumber: bigint
  /** When the block was mined, in unix seconds. */
  timestamp: number
  /** Exact amounts moved, recovered from the transfer logs. */
  amountIn: number | null
  amountOut: number | null
  gasUsed: bigint
}

const TRANSFER_EVENT = {
  type: 'event',
  name: 'Transfer',
  inputs: [
    { indexed: true, name: 'from', type: 'address' },
    { indexed: true, name: 'to', type: 'address' },
    { indexed: false, name: 'value', type: 'uint256' },
  ],
} as const

/**
 * Sums the token movement for one address out of a receipt's transfer logs, so
 * the receipt reports what the chain actually moved rather than what was quoted.
 */
function settledAmount(
  receipt: TransactionReceipt,
  token: Address,
  account: Address,
  direction: 'in' | 'out',
  decimals: number,
): number | null {
  let total = 0n
  let seen = false
  for (const log of receipt.logs) {
    if (log.address.toLowerCase() !== token.toLowerCase()) continue
    try {
      const { args } = decodeEventLog({ abi: [TRANSFER_EVENT], data: log.data, topics: log.topics })
      const matches =
        direction === 'out'
          ? args.from.toLowerCase() === account.toLowerCase()
          : args.to.toLowerCase() === account.toLowerCase()
      if (!matches) continue
      total += args.value
      seen = true
    } catch {
      // Not a Transfer from this token; the pool emits plenty else.
    }
  }
  return seen ? fromBaseUnits(total, decimals) : null
}

/**
 * Executes against a deployed market: a real ERC-20 approval and a real swap
 * through the market's permissioned router, each split so the wallet prompt and
 * the on-chain confirmation are separate observable steps.
 */
export function createMarketExecutor(
  market: DeployedMarket,
  wallet: WalletStore,
  options: { preflight?: (request: SwapRequest) => SwapFailure | null } = {},
): SwapExecutor {
  // Token decimals never change, so they are read once per market.
  let decimalsCache: { asset: number; settlement: number } | null = null

  async function decimals() {
    decimalsCache ??= {
      asset: await readDecimals(market.assetToken),
      settlement: await readDecimals(market.settlementToken),
    }
    return decimalsCache
  }

  function payToken(request: SwapRequest): Address {
    return request.side === 'buy' ? market.settlementToken : market.assetToken
  }

  async function payDecimals(request: SwapRequest): Promise<number> {
    const d = await decimals()
    return request.side === 'buy' ? d.settlement : d.asset
  }

  /**
   * Whether the token's eligibility check applies to a swap at all. It is
   * skipped when either party to the transfer is an exempt operator, and a
   * swap's counterparty is always the pool manager — so an exempt pool manager
   * means no wallet needs registering, and asking one to would spend gas for
   * nothing.
   */
  let bindsCache: boolean | null = null
  async function eligibilityBinds(): Promise<boolean> {
    if (bindsCache !== null) return bindsCache
    try {
      const exempt = await publicClient().readContract({
        address: market.assetToken,
        abi: assetTokenAbi,
        functionName: 'exemptOperators',
        args: [market.poolManager],
      })
      bindsCache = !exempt
    } catch {
      // Unreadable: assume it binds, which only costs an extra offered step.
      bindsCache = true
    }
    return bindsCache
  }

  async function account(): Promise<Address> {
    const address = wallet.address
    if (!address) throw new Error('No wallet is connected')
    return address as Address
  }

  /** The swap call, shared by the pre-flight simulation and the real send. */
  async function swapArgs(request: SwapRequest) {
    const rises = request.side === 'buy'
    return [
      {
        currency0: market.currency0,
        currency1: market.currency1,
        fee: market.fee,
        tickSpacing: market.tickSpacing,
        hooks: market.hook,
      },
      {
        zeroForOne: zeroForOne(market, request.side),
        // Negative is exact-input, positive is exact-output.
        amountSpecified:
          request.mode === 'exactIn'
            ? -toBaseUnits(request.amountIn, await payDecimals(request))
            : toBaseUnits(request.amountOut, (await decimals())[request.side === 'buy' ? 'asset' : 'settlement']),
        sqrtPriceLimitX96: priceLimit({
          spotPrice: request.spotPrice,
          postSwapPrice: request.postSwapPrice,
          slippageBps: request.slippageBps,
          priceRises: rises,
          bandLower: request.bandLower,
          bandUpper: request.bandUpper,
        }),
      },
      { takeClaims: false, settleUsingBurn: false },
      '0x' as Hex,
    ] as const
  }

  /**
   * Compares what the pool would actually fill against what was asked for. A
   * shortfall means the trade is bigger than the liquidity inside the permitted
   * range, and the fillable size is offered back as a correction.
   */
  async function fillShortfall(request: SwapRequest, delta: bigint): Promise<SwapFailure | null> {
    const { amount0, amount1 } = unpackBalanceDelta(delta)
    const d = await decimals()
    const assetIs0 = assetIsCurrency0(market)
    const assetDelta = assetIs0 ? amount0 : amount1
    const settleDelta = assetIs0 ? amount1 : amount0

    // The leg the investor pinned: exact-input fixes what they pay, exact-output
    // what they receive.
    const [filledRaw, askedDisplay, unitDecimals, unit] =
      request.mode === 'exactIn'
        ? request.side === 'buy'
          ? [-settleDelta, request.amountIn, d.settlement, 'settlement token']
          : [-assetDelta, request.amountIn, d.asset, market.symbol]
        : request.side === 'buy'
          ? [assetDelta, request.amountOut, d.asset, market.symbol]
          : [settleDelta, request.amountOut, d.settlement, 'settlement token']

    const filled = fromBaseUnits(filledRaw < 0n ? -filledRaw : filledRaw, unitDecimals)
    // A hair of tolerance: rounding in the pool's own maths, not a short fill.
    if (filled >= askedDisplay * 0.9999) return null

    return {
      kind: 'failed',
      title: 'Larger than the pool can fill',
      detail: `The liquidity inside this pool's permitted price range can only take about ${filled.toLocaleString('en-US', { maximumFractionDigits: 4 })} ${unit} right now, not ${askedDisplay.toLocaleString('en-US', { maximumFractionDigits: 4 })}.`,
      retryable: true,
      suggestedAmount: filled,
    }
  }

  /**
   * Everything that has to happen before the swap can be sent, in order. Each is
   * one signature with its own label, so the investor is never asked to sign
   * something the screen has not named.
   */
  async function computeSteps(request: SwapRequest): Promise<PreparationStep[]> {
    const owner = await account()
    const steps: PreparationStep[] = []
    const send = (to: Address, data: Hex) => async () => {
      const client = await wallet.getWalletClient()
      return client.sendTransaction({ account: client.account!, chain: TARGET_CHAIN, to, data })
    }

    // 1. Eligibility, but only where it actually applies to a swap.
    const registry = market.identityRegistry
    const eligible = !(await eligibilityBinds())
      ? true
      : await publicClient()
          .readContract({ address: registry, abi: identityRegistryAbi, functionName: 'isEligible', args: [owner] })
          .catch(() => true)
    if (!eligible) {
      steps.push({
        id: 'register',
        label: 'Enable access',
        detail: `${market.name} only transfers to registered wallets. This registers yours on-chain — a one-off, and it costs only gas.`,
        to: registry,
        data: encodeFunctionData({ abi: identityRegistryAbi, functionName: 'register' }),
        send: send(registry, encodeFunctionData({ abi: identityRegistryAbi, functionName: 'register' })),
      })
    }

    // 2. Funds. The demo settlement token is a faucet, so a wallet short of it
    //    can mint the difference. A real settlement token has no such step and
    //    the shortfall is reported as a plain failure instead.
    const payingWith = payToken(request)
    const decimalsForPay = await payDecimals(request)
    const needed = toBaseUnits(request.mode === 'exactIn' ? request.amountIn : request.bound, decimalsForPay)
    const held = await readBalance(payingWith, owner)
    if (held < needed && request.side === 'buy') {
      const shortfall = needed - held
      const mintable = await publicClient()
        .simulateContract({
          account: owner,
          address: payingWith,
          abi: mintableAbi,
          functionName: 'mint',
          args: [owner, shortfall],
        })
        .then(() => true)
        .catch(() => false)
      const mintCall = encodeFunctionData({ abi: mintableAbi, functionName: 'mint', args: [owner, shortfall] })
      if (mintable) {
        steps.push({
          id: 'mint',
          label: `Get demo ${request.side === 'buy' ? 'funds' : 'tokens'}`,
          detail: `This market settles in a demo token with an open faucet. This mints the ${fromBaseUnits(shortfall, decimalsForPay).toLocaleString('en-US', { maximumFractionDigits: 4 })} you are short.`,
          to: payingWith,
          data: mintCall,
          send: send(payingWith, mintCall),
        })
      }
    }

    // 3. Allowance for the router.
    const allowance = await readAllowance(payingWith, owner, market.swapRouter)
    const approveCall = encodeFunctionData({
      abi: erc20Abi,
      functionName: 'approve',
      args: [market.swapRouter, MAX_UINT256],
    })
    if (allowance < needed) {
      steps.push({
        id: 'approve',
        label: `Approve ${request.side === 'buy' ? 'settlement token' : market.symbol}`,
        detail: 'This lets the router move the token you are spending. It is a permission, not the trade itself.',
        to: payingWith,
        data: approveCall,
        send: send(payingWith, approveCall),
      })
    }

    return steps
  }

  return {
    ready: true,
    routerAddress: market.swapRouter,
    prepare: computeSteps,

    async preflight(request) {
      const local = options.preflight?.(request)
      if (local) return local

      const owner = await account()

      // Eligibility, where it applies, is enforced by the token's own registry.
      // Read that registry directly rather than `AgoraAllowlistChecker`, which
      // holds its oracle as an immutable and can point at one the token no
      // longer uses.
      const eligible = !(await eligibilityBinds())
        ? true
        : await publicClient()
            .readContract({ address: market.identityRegistry, abi: identityRegistryAbi, functionName: 'isEligible', args: [owner] })
            .catch(() => true)
      if (!eligible) {
        return {
          kind: 'failed',
          title: 'This wallet is not registered for this market',
          detail: `${market.name} only transfers to registered wallets. Enable access first, then submit the swap.`,
          retryable: true,
        }
      }

      // Selling needs the asset in hand, and there is no faucet for it.
      if (request.side === 'sell') {
        const decimalsForPay = await payDecimals(request)
        const needed = toBaseUnits(request.mode === 'exactIn' ? request.amountIn : request.bound, decimalsForPay)
        const held = await readBalance(market.assetToken, owner)
        if (held < needed) {
          return {
            kind: 'failed',
            title: `Not enough ${market.symbol}`,
            detail: `This trade spends ${fromBaseUnits(needed, decimalsForPay).toLocaleString('en-US', { maximumFractionDigits: 4 })} ${market.symbol} and the wallet holds ${fromBaseUnits(held, decimalsForPay).toLocaleString('en-US', { maximumFractionDigits: 4 })}.`,
            retryable: true,
          }
        }
      }

      // Simulating against live pool state surfaces the hook's own refusal with
      // its real reason, before anyone is asked to sign. The outstanding
      // preparation calls go in front of it, so the swap is simulated as it will
      // actually execute — without them it would only ever report a missing
      // allowance and nothing beyond it could be checked.
      const pending = await computeSteps(request)
      const swapCall = {
        to: market.swapRouter,
        data: encodeFunctionData({ abi: swapRouterAbi, functionName: 'swap', args: await swapArgs(request) }),
      }

      try {
        const simulated = await publicClient().simulateCalls({
          account: owner,
          calls: [...pending.map((step) => ({ to: step.to, data: step.data })), swapCall],
        })
        const result = simulated.results[simulated.results.length - 1]
        if (!result) return null
        if (result.status !== 'success') {
          return {
            kind: 'reverted',
            title: 'The pool would refuse this trade',
            detail:
              'Simulating it against the current pool state failed, so it was not submitted. Pool conditions may have moved since your quote.',
            retryable: true,
          }
        }
        // A swap that runs out of liquidity inside its price limit fills
        // partially and does *not* revert, so the quote alone cannot rule it
        // out. The chain is the authority on how much is fillable.
        return await fillShortfall(request, BigInt(result.data))
      } catch (bundleError) {
        // Not every node implements bundled simulation. Fall back to simulating
        // the swap alone, which still catches a refusal once an allowance exists.
        try {
          const { result } = await publicClient().simulateContract({
            account: owner,
            address: market.swapRouter,
            abi: swapRouterAbi,
            functionName: 'swap',
            args: await swapArgs(request),
          })
          return await fillShortfall(request, result as bigint)
        } catch (error) {
          const failure = describeExecutionError(error)
          // An allowance not yet granted is not a refusal by the pool — the
          // preparation steps are what answer it.
          if (failure.code === 'ERC20InsufficientAllowance') return null
          // A bundled-simulation transport error must not masquerade as a refusal.
          if (failure.kind === 'failed' && !failure.code && bundleError) return null
          return failure
        }
      }
    },

    async sendSwap(request) {
      const client = await wallet.getWalletClient()
      return client.writeContract({
        account: client.account!,
        chain: TARGET_CHAIN,
        address: market.swapRouter,
        abi: swapRouterAbi,
        functionName: 'swap',
        args: await swapArgs(request),
      })
    },

    async waitFor(hash, request) {
      const receipt = await publicClient().waitForTransactionReceipt({ hash })
      const block = await publicClient().getBlock({ blockNumber: receipt.blockNumber })
      const owner = await account()
      const d = await decimals()
      const assetIsPayment = request.side === 'sell'

      return {
        hash,
        // A mined transaction that reverted still returns a receipt, so the
        // status is the only thing that says whether it worked.
        status: receipt.status === 'success' ? 'success' : 'reverted',
        blockNumber: receipt.blockNumber,
        timestamp: Number(block.timestamp),
        amountIn:
          receipt.status === 'success'
            ? settledAmount(
                receipt,
                assetIsPayment ? market.assetToken : market.settlementToken,
                owner,
                'out',
                assetIsPayment ? d.asset : d.settlement,
              )
            : null,
        amountOut:
          receipt.status === 'success'
            ? settledAmount(
                receipt,
                assetIsPayment ? market.settlementToken : market.assetToken,
                owner,
                'in',
                assetIsPayment ? d.settlement : d.asset,
              )
            : null,
        gasUsed: receipt.gasUsed,
      }
    },
  }
}
