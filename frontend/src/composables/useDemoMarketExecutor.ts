import { createPublicClient, http, parseAbi, parseUnits, type Address } from 'viem'
import markets from '@config/markets.json'
import type { WalletStore } from '@/stores/wallet'
import type { SwapExecutor, SwapFailure, SwapRequest } from '@/composables/useSwapTransaction'
import { TARGET_CHAIN } from '@/config/chain'

const market = markets['84532'][0]!
const MAX_UINT256 = 2n ** 256n - 1n
const publicClient = createPublicClient({ chain: TARGET_CHAIN, transport: http() })

const erc20Abi = parseAbi([
  'function approve(address spender, uint256 amount) returns (bool)',
])

const swapRouterAbi = parseAbi([
  'function swap((address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks) key,(bool zeroForOne,int256 amountSpecified,uint160 sqrtPriceLimitX96) params,(bool takeClaims,bool settleUsingBurn) testSettings,bytes hookData) payable returns (int256 delta)',
])

function units(value: number): bigint {
  return parseUnits(value.toFixed(18).replace(/\.?0+$/, ''), 18)
}

export function createDemoMarketExecutor(
  wallet: WalletStore,
  options: { preflight?: (request: SwapRequest) => SwapFailure | null } = {},
): SwapExecutor {
  let approvedToken: Address | null = null

  function payToken(request: SwapRequest): Address {
    return (request.side === 'buy' ? market.settlementToken : market.assetToken) as Address
  }

  return {
    simulated: false,
    needsApproval: (request) => approvedToken !== payToken(request),
    approve: async (request) => {
      const client = await wallet.getWalletClient()
      const hash = await client.writeContract({
        account: client.account!,
        chain: TARGET_CHAIN,
        address: payToken(request),
        abi: erc20Abi,
        functionName: 'approve',
        args: [market.swapRouter as Address, MAX_UINT256],
      })
      await publicClient.waitForTransactionReceipt({ hash })
      approvedToken = payToken(request)
      return { hash }
    },
    swap: async (request) => {
      const client = await wallet.getWalletClient()
      const exactAmount = request.mode === 'exactIn' ? request.amountIn : request.amountOut
      const amountSpecified = request.mode === 'exactIn' ? -units(exactAmount) : units(exactAmount)
      const hash = await client.writeContract({
        account: client.account!,
        chain: TARGET_CHAIN,
        address: market.swapRouter as Address,
        abi: swapRouterAbi,
        functionName: 'swap',
        args: [
          {
            currency0: market.currency0 as Address,
            currency1: market.currency1 as Address,
            fee: market.fee,
            tickSpacing: market.tickSpacing,
            hooks: market.hook as Address,
          },
          {
            zeroForOne: request.side === 'sell',
            amountSpecified,
            sqrtPriceLimitX96: request.sqrtPriceLimitX96,
          },
          { takeClaims: false, settleUsingBurn: false },
          '0x',
        ],
      })
      await publicClient.waitForTransactionReceipt({ hash })
      return { hash }
    },
    preflight: options.preflight,
  }
}
