import { defineStore } from 'pinia'
import { computed, ref } from 'vue'
import type { Address } from 'viem'
import { DEPLOYED_MARKETS, type DeployedMarket } from '@/execution/market'
import { fromBaseUnits } from '@/execution/swapExecutor'
import { erc20Abi, publicClient, readBalance, readDecimals } from '@/execution/chain'
import { useWalletStore } from '@/stores/wallet'

/**
 * What the connected wallet actually holds, read from the deployed markets on
 * the configured chain. Nothing here is fabricated: an asset with no deployed
 * market contributes no position, and a wallet holding nothing reports nothing.
 */
export interface Position {
  marketId: string
  name: string
  symbol: string
  assetToken: Address
  /** Units of the asset token held. */
  balance: number
  /** The market's settlement currency symbol, for pricing context. */
  settlementSymbol: string
}

export const usePortfolioStore = defineStore('portfolio', () => {
  const positions = ref<Position[]>([])
  const settlementBalance = ref<number | null>(null)
  const settlementSymbol = ref<string>('')
  const loading = ref(false)
  /** Set when the chain could not be read; the UI offers a retry rather than an empty state. */
  const error = ref<string | null>(null)
  const loadedFor = ref<string | null>(null)

  // Decimals are immutable per token, so they are read once.
  const decimalsCache = new Map<string, number>()

  async function decimalsOf(token: Address): Promise<number> {
    const key = token.toLowerCase()
    const known = decimalsCache.get(key)
    if (known !== undefined) return known
    const value = await readDecimals(token)
    decimalsCache.set(key, value)
    return value
  }

  const hasMarkets = computed(() => DEPLOYED_MARKETS.length > 0)
  const totalPositions = computed(() => positions.value.filter((p) => p.balance > 0).length)

  async function readPosition(market: DeployedMarket, owner: Address): Promise<Position> {
    const [raw, decimals] = await Promise.all([
      readBalance(market.assetToken, owner),
      decimalsOf(market.assetToken),
    ])
    return {
      marketId: market.id,
      name: market.name,
      symbol: market.symbol,
      assetToken: market.assetToken,
      balance: fromBaseUnits(raw, decimals),
      settlementSymbol: settlementSymbol.value,
    }
  }

  /**
   * Re-reads every balance. Called on connect and again after a confirmed
   * trade, which is what keeps holdings current without a page reload.
   */
  async function refresh() {
    const wallet = useWalletStore()
    const owner = wallet.address as Address | null

    if (!owner || !wallet.onTargetChain) {
      positions.value = []
      settlementBalance.value = null
      loadedFor.value = null
      error.value = null
      return
    }
    if (DEPLOYED_MARKETS.length === 0) {
      positions.value = []
      settlementBalance.value = null
      loadedFor.value = owner
      return
    }

    loading.value = true
    error.value = null
    try {
      // Every market in this deployment settles in the same token.
      const settlement = DEPLOYED_MARKETS[0]!.settlementToken
      const [settlementRaw, settlementDecimals, symbol] = await Promise.all([
        readBalance(settlement, owner),
        decimalsOf(settlement),
        settlementSymbol.value
          ? Promise.resolve(settlementSymbol.value)
          : publicClient().readContract({ address: settlement, abi: erc20Abi, functionName: 'symbol' }),
      ])
      settlementBalance.value = fromBaseUnits(settlementRaw, settlementDecimals)
      settlementSymbol.value = symbol

      positions.value = await Promise.all(DEPLOYED_MARKETS.map((market) => readPosition(market, owner)))
      loadedFor.value = owner
    } catch (cause) {
      error.value =
        cause instanceof Error
          ? `Couldn't read your balances from the network. ${cause.message.split('\n')[0]}`
          : "Couldn't read your balances from the network."
    } finally {
      loading.value = false
    }
  }

  /** The units of one market's asset this wallet holds, if it has been read. */
  function balanceOf(marketId: string): number | null {
    return positions.value.find((position) => position.marketId === marketId)?.balance ?? null
  }

  return {
    positions,
    settlementBalance,
    settlementSymbol,
    loading,
    error,
    loadedFor,
    hasMarkets,
    totalPositions,
    refresh,
    balanceOf,
  }
})
