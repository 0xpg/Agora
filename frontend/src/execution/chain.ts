import { createPublicClient, http, parseAbi, type Address, type PublicClient } from 'viem'
import { TARGET_CHAIN } from '@/config/chain'

/**
 * Read-only chain access. One client for the whole app: viem dedupes and
 * batches through it, and nothing here needs a signer.
 */
let client: PublicClient | null = null

export function publicClient(): PublicClient {
  client ??= createPublicClient({ chain: TARGET_CHAIN, transport: http() })
  return client
}

export const erc20Abi = parseAbi([
  'function approve(address spender, uint256 amount) returns (bool)',
  'function allowance(address owner, address spender) view returns (uint256)',
  'function balanceOf(address account) view returns (uint256)',
  'function decimals() view returns (uint8)',
  'function symbol() view returns (string)',
])

/**
 * The registry the asset token consults on every transfer, which is what
 * actually gates a swap. Note this is not necessarily the one
 * `AgoraAllowlistChecker` reads: that contract holds its oracle as an immutable,
 * so if the token's registry is later replaced the checker keeps pointing at the
 * old one. The token's registry is the authority.
 */
export const identityRegistryAbi = parseAbi([
  'function isEligible(address investor) view returns (bool)',
  'function tierOf(address investor) view returns (uint8)',
  'function register()',
])

/**
 * The token's own gate. It skips the eligibility check entirely when either
 * side of a transfer is an exempt operator, so whether eligibility binds on a
 * swap depends on whether the pool manager is exempt.
 */
export const assetTokenAbi = parseAbi([
  'function identityRegistry() view returns (address)',
  'function exemptOperators(address operator) view returns (bool)',
])

/** A faucet-style demo token. Absent on any real settlement token. */
export const mintableAbi = parseAbi(['function mint(address to, uint256 amount)'])

/**
 * Agora's eligibility surface, as the permissioned pool stack consumes it.
 * `PermissionFlag` is a `bytes2` bitfield, not a boolean: the checker returns
 * `NONE` for an ineligible account and the tier's granted flags otherwise. The
 * individual bits are defined in v4-periphery, so this only distinguishes
 * "something was granted" from "nothing was".
 */
export const allowlistAbi = parseAbi([
  'function checkAllowlist(address account, address tokenAddress) view returns (bytes2)',
])

/** True when the checker granted this account any permission at all. */
export function hasAnyPermission(flags: `0x${string}`): boolean {
  return /[1-9a-f]/i.test(flags.slice(2))
}

/**
 * Errors the token itself can raise during a swap. They are declared alongside
 * the router so a revert decodes to its name instead of a bare selector — a
 * swap that fails for want of an allowance has to say so.
 */
const tokenErrorsAbi = parseAbi([
  'error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed)',
  'error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed)',
])

/** The hook's refusals, so they decode by name rather than by selector. */
const hookErrorsAbi = parseAbi([
  'error StaleNAV()',
  'error UnsyncedPriceBand()',
  'error PriceOutsideBand()',
  'error SwapsPaused()',
  'error SwapTooLarge()',
  'error RebalanceOnly()',
  'error WrongPool()',
])

/**
 * `PoolSwapTest` from the v4 core test helpers, which is what this deployment
 * uses as its permissioned swap route.
 */
export const swapRouterAbi = [
  ...parseAbi([
    'function swap((address currency0,address currency1,uint24 fee,int24 tickSpacing,address hooks) key,(bool zeroForOne,int256 amountSpecified,uint160 sqrtPriceLimitX96) params,(bool takeClaims,bool settleUsingBurn) testSettings,bytes hookData) payable returns (int256 delta)',
  ]),
  ...tokenErrorsAbi,
  ...hookErrorsAbi,
] as const

export async function readDecimals(token: Address): Promise<number> {
  return publicClient().readContract({ address: token, abi: erc20Abi, functionName: 'decimals' })
}

export async function readBalance(token: Address, owner: Address): Promise<bigint> {
  return publicClient().readContract({ address: token, abi: erc20Abi, functionName: 'balanceOf', args: [owner] })
}

export async function readAllowance(token: Address, owner: Address, spender: Address): Promise<bigint> {
  return publicClient().readContract({
    address: token,
    abi: erc20Abi,
    functionName: 'allowance',
    args: [owner, spender],
  })
}
