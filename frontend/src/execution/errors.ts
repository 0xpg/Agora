import { BaseError, ContractFunctionRevertedError } from 'viem'
import type { SwapFailure } from '@/composables/useSwapTransaction'

/**
 * The hook's own refusals, mapped to what they mean for the investor. These are
 * the errors `AgoraHook` declares; anything else falls through to its raw name.
 */
const HOOK_REVERTS: Record<string, { title: string; detail: string }> = {
  SwapsPaused: {
    title: 'Trading is paused',
    detail: 'The issuer paused this pool. Nothing was spent — swaps reopen when they unpause it.',
  },
  StaleNAV: {
    title: 'NAV is out of date',
    detail: 'The pool needs a newer published NAV than it has. Trading resumes once the issuer publishes one.',
  },
  UnsyncedPriceBand: {
    title: 'Price range is being re-anchored',
    detail: 'A new NAV was published and the issuer has not yet re-anchored the permitted price range to it.',
  },
  PriceOutsideBand: {
    title: 'Price is outside the permitted range',
    detail: 'Filling this trade would take the pool outside the range its issuer permits, so it was refused.',
  },
  SwapTooLarge: {
    title: 'Trade is above the per-swap limit',
    detail: 'This pool caps how much one swap may move. Try a smaller size.',
  },
  ERC20InsufficientAllowance: {
    title: 'Approval needed first',
    detail: 'The router is not yet allowed to spend this token on your behalf. Approve it, then submit the swap.',
  },
  ERC20InsufficientBalance: {
    title: 'Not enough balance',
    detail: 'This wallet does not hold enough of the token this trade spends.',
  },
  RebalanceOnly: {
    title: 'Only the other direction is accepted',
    detail:
      'Price has moved far enough from NAV that the pool takes only swaps bringing it back. Yours would push it further out.',
  },
}

function isUserRejection(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error)
  // Wallets report a dismissed prompt in their own words; EIP-1193 gives it 4001.
  return /user rejected|user denied|rejected the request|denied transaction|cancell?ed/i.test(message) ||
    (typeof error === 'object' && error !== null && 'code' in error && (error as { code: unknown }).code === 4001)
}

/** Pulls the custom error name out of a reverted simulation, when there is one. */
function revertName(error: unknown): string | null {
  if (!(error instanceof BaseError)) return null
  const revert = error.walk((e) => e instanceof ContractFunctionRevertedError)
  if (!(revert instanceof ContractFunctionRevertedError)) return null
  return revert.data?.errorName ?? revert.reason ?? null
}

export function describeExecutionError(error: unknown): SwapFailure {
  if (isUserRejection(error)) {
    return {
      kind: 'rejected',
      title: 'You declined the request',
      detail: 'Nothing was submitted and nothing was spent. Your amounts are still here if you want to try again.',
      retryable: true,
    }
  }

  const name = revertName(error)
  const known = name ? HOOK_REVERTS[name] : undefined
  if (known) return { kind: 'reverted', code: name ?? undefined, ...known, retryable: true }
  if (name) {
    return {
      kind: 'reverted',
      code: name,
      title: 'The pool refused this trade',
      detail: `The contract rejected it with ${name}. Nothing was spent.`,
      retryable: true,
    }
  }

  const message = error instanceof Error ? error.message : String(error)
  if (/insufficient funds/i.test(message)) {
    return {
      kind: 'failed',
      title: 'Not enough balance',
      detail: 'This wallet does not hold enough to cover the trade and its gas.',
      retryable: true,
    }
  }
  return {
    kind: 'failed',
    title: 'Transaction failed',
    detail: message.split('\n')[0] ?? 'The transaction could not be completed.',
    retryable: true,
  }
}

