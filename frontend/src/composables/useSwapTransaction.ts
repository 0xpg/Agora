import { computed, ref, shallowRef } from 'vue'
import type { Address, Hex } from 'viem'
import { describeExecutionError } from '@/execution/errors'
import type { ExecutionOutcome } from '@/execution/swapExecutor'

/**
 * The stages a swap passes through, from the investor's point of view. Approval
 * and the swap each need a signature and then a confirmation, and those two
 * waits feel different: one is waiting on you, the other on the network.
 */
export type SwapStage =
  | 'idle'
  /** Reading chain state and simulating against the live pool before prompting. */
  | 'checking'
  /** A preparation transaction is waiting for a signature, then for a block. */
  | 'prepare_signature'
  | 'prepare_submitted'
  | 'swap_signature'
  | 'swap_submitted'
  | 'confirmed'
  | 'rejected'
  | 'reverted'
  | 'failed'

/** Why a swap did not complete. `kind` decides how it is presented. */
export interface SwapFailure {
  kind: 'rejected' | 'reverted' | 'failed'
  /** The contract error name, when the revert decoded to one. */
  code?: string
  title: string
  detail: string
  /** False when retrying the same trade cannot work — a refusal, not a mishap. */
  retryable: boolean
  /**
   * An amount that would clear, in the units the investor is typing, when the
   * refusal is about size. Offered as a one-tap correction.
   */
  suggestedAmount?: number
}

/** What the executor is asked to do. Amounts are in display units. */
export interface SwapRequest {
  assetId: string
  side: 'buy' | 'sell'
  mode: 'exactIn' | 'exactOut'
  amountIn: number
  amountOut: number
  /** The slippage-bounded worst acceptable result. */
  bound: number
  slippageBps: number
  /** Pool price before the swap, and where the quote says it would land. */
  spotPrice: number
  postSwapPrice: number
  /** The permitted price range in force, which the swap may not be priced outside. */
  bandLower: number
  bandUpper: number
}

/**
 * One transaction that has to land before the swap can be sent — registering for
 * access, funding the wallet from a demo faucet, granting the router an
 * allowance. Each is a single signature and names itself, so nobody is asked to
 * sign something the screen has not explained.
 */
export interface PreparationStep {
  id: 'register' | 'mint' | 'approve'
  /** What the button says while this step is the next one. */
  label: string
  /** What it does and why. */
  detail: string
  /** The call itself, so it can be simulated ahead of the swap as well as sent. */
  to: Address
  data: Hex
  send: () => Promise<Hex>
}

/**
 * Submits preparation transactions and swaps against a deployed market. Sending
 * and confirming are separate calls so the UI can distinguish "waiting for your
 * signature" from "waiting for the network".
 */
export interface SwapExecutor {
  /** False when no deployed market backs this asset, so nothing can be sent. */
  readonly ready: boolean
  /** The spender an approval is granted to. */
  readonly routerAddress: Address | null
  /** Everything outstanding before this trade can be sent, in order. */
  prepare: (request: SwapRequest) => Promise<PreparationStep[]>
  /**
   * Re-checked immediately before prompting. The pool can refuse between quote
   * and execution — NAV ages out, the issuer pauses, another swap moves price to
   * the edge of the range — and that is a refusal the investor has to see
   * before signing rather than as a failed transaction afterwards.
   */
  preflight: (request: SwapRequest) => Promise<SwapFailure | null>
  sendSwap: (request: SwapRequest) => Promise<Hex>
  waitFor: (hash: Hex, request: SwapRequest) => Promise<ExecutionOutcome>
}

/**
 * Stands in for assets that have no deployed market on this chain. It cannot
 * send anything, and the panel says so rather than offering a button that
 * would do nothing.
 */
export function createUnavailableExecutor(): SwapExecutor {
  const refuse = async (): Promise<never> => {
    throw new Error('This asset has no deployed market on this network.')
  }
  return {
    ready: false,
    routerAddress: null,
    prepare: async () => [],
    preflight: async () => ({
      kind: 'failed',
      title: 'Not tradable on this network',
      detail: 'This asset is listed for reference. No market has been deployed for it on the configured chain yet.',
      retryable: false,
    }),
    sendSwap: refuse,
    waitFor: refuse,
  }
}

/**
 * Drives one swap from approval through confirmation, holding whatever stopped
 * it. The investor's entered amounts are deliberately not this composable's to
 * clear — a failed attempt has to leave them in place to be corrected.
 */
export function useSwapTransaction(executor: () => SwapExecutor) {
  const stage = ref<SwapStage>('idle')
  const preparationHash = ref<Hex | null>(null)
  const swapHash = ref<Hex | null>(null)
  const failure = ref<SwapFailure | null>(null)
  // Shallow: an outcome is a plain snapshot and never mutated in place.
  const outcome = shallowRef<ExecutionOutcome | null>(null)
  const settledRequest = shallowRef<SwapRequest | null>(null)
  /** What still has to happen before the swap, refreshed as the trade changes. */
  const steps = shallowRef<PreparationStep[]>([])
  /** The step currently being signed or confirmed. */
  const activeStep = shallowRef<PreparationStep | null>(null)

  // One in-flight attempt at a time. The button is disabled while busy, but a
  // double submit can still arrive from a keyboard repeat or a double tap, and
  // that must never become two transactions.
  let inFlight = false

  const busy = computed(
    () =>
      stage.value === 'checking' ||
      stage.value === 'prepare_signature' ||
      stage.value === 'prepare_submitted' ||
      stage.value === 'swap_signature' ||
      stage.value === 'swap_submitted',
  )

  const settled = computed(
    () => stage.value === 'confirmed' || stage.value === 'rejected' || stage.value === 'reverted' || stage.value === 'failed',
  )

  function reset() {
    stage.value = 'idle'
    preparationHash.value = null
    swapHash.value = null
    failure.value = null
    outcome.value = null
    settledRequest.value = null
  }

  /** Clears the failure but keeps the entered trade, ready to be retried. */
  function dismissFailure() {
    failure.value = null
    if (stage.value === 'rejected' || stage.value === 'reverted' || stage.value === 'failed') {
      stage.value = 'idle'
    }
  }

  function fail(next: SwapFailure) {
    failure.value = next
    stage.value = next.kind
  }

  /** The next outstanding preparation step, or null when the swap can be sent. */
  const nextStep = computed<PreparationStep | null>(() => steps.value[0] ?? null)

  async function refreshSteps(request: SwapRequest | null) {
    if (!request || !executor().ready) {
      steps.value = []
      return
    }
    try {
      steps.value = await executor().prepare(request)
    } catch {
      // Unreadable chain state should not strand the panel: leave the steps as
      // they were and let the submit path report whatever actually fails.
    }
  }

  /** Signs and confirms the next preparation transaction. */
  async function runNextStep(request: SwapRequest) {
    const step = nextStep.value
    if (!step || inFlight) return
    inFlight = true
    failure.value = null
    activeStep.value = step
    try {
      stage.value = 'prepare_signature'
      let hash: Hex
      try {
        hash = await step.send()
      } catch (error) {
        fail(describeExecutionError(error))
        return
      }
      preparationHash.value = hash
      stage.value = 'prepare_submitted'

      const result = await executor().waitFor(hash, request)
      if (result.status === 'reverted') {
        fail({
          kind: 'reverted',
          title: `${step.label} failed`,
          detail: 'The transaction was mined but reverted, so nothing changed. Nothing was spent beyond gas.',
          retryable: true,
        })
        return
      }
      stage.value = 'idle'
      // Re-read rather than assuming: the step may not have cleared everything.
      await refreshSteps(request)
    } catch (error) {
      fail(describeExecutionError(error))
    } finally {
      inFlight = false
      activeStep.value = null
    }
  }

  async function submit(request: SwapRequest) {
    if (inFlight) return
    inFlight = true
    failure.value = null
    try {

      stage.value = 'checking'
      const refusal = await executor().preflight(request)
      if (refusal) {
        fail(refusal)
        return
      }

      stage.value = 'swap_signature'
      let hash: Hex
      try {
        hash = await executor().sendSwap(request)
      } catch (error) {
        fail(describeExecutionError(error))
        return
      }
      swapHash.value = hash
      stage.value = 'swap_submitted'

      const result = await executor().waitFor(hash, request)
      outcome.value = result
      settledRequest.value = request
      if (result.status === 'reverted') {
        fail({
          kind: 'reverted',
          title: 'The transaction reverted',
          detail:
            'It was mined but the pool rejected it, so nothing was exchanged. Conditions can change between quoting and confirming — check the pool state and try again.',
          retryable: true,
        })
        return
      }
      stage.value = 'confirmed'
    } catch (error) {
      fail(describeExecutionError(error))
    } finally {
      inFlight = false
    }
  }

  return {
    stage,
    preparationHash,
    swapHash,
    failure,
    outcome,
    settledRequest,
    steps,
    nextStep,
    activeStep,
    busy,
    settled,
    refreshSteps,
    runNextStep,
    submit,
    reset,
    dismissFailure,
  }
}
