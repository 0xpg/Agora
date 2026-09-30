import { computed, ref } from 'vue'

/**
 * The stages a swap passes through, from the investor's point of view. Approval
 * and the swap itself each need a wallet signature and then a confirmation, so
 * each has a "waiting on you" stage and a "waiting on the chain" stage — the two
 * feel different and read differently.
 */
export type SwapStage =
  | 'idle'
  | 'approve_signing'
  | 'approve_confirming'
  | 'swap_signing'
  | 'swap_confirming'
  | 'confirmed'
  | 'failed'

export interface SwapFailure {
  title: string
  detail: string
  /** True when retrying could plausibly work — a rejection, not a refusal. */
  retryable: boolean
}

/** What the executor is asked to do. Amounts are already in display units. */
export interface SwapRequest {
  assetId: string
  side: 'buy' | 'sell'
  mode: 'exactIn' | 'exactOut'
  amountIn: number
  amountOut: number
  /** The slippage-bounded worst acceptable result. */
  bound: number
  slippageBps: number
}

/**
 * Submits approvals and swaps. The only implementation today is the simulator
 * below; a live one routes through the permissioned router, which is the route
 * that establishes the eligible end user. Keeping it behind this interface is
 * what lets the panel's stages be real before the router address exists.
 */
export interface SwapExecutor {
  /** True when the input token still needs an allowance for this request. */
  needsApproval: (request: SwapRequest) => boolean
  approve: (request: SwapRequest) => Promise<{ hash: string }>
  swap: (request: SwapRequest) => Promise<{ hash: string }>
  /**
   * Re-checked immediately before signing. The pool can refuse between quote and
   * execution — NAV ages out, the issuer pauses, another swap moves price to the
   * edge of the range — and that is a failure the investor has to see.
   */
  preflight?: (request: SwapRequest) => SwapFailure | null
  /** True when settlement is simulated rather than submitted to a chain. */
  readonly simulated: boolean
}

function randomHash(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32))
  return `0x${Array.from(bytes, (b) => b.toString(16).padStart(2, '0')).join('')}`
}

/**
 * Stands in for the router until deployed addresses land in
 * `config/addresses.json`. It does not touch a chain: it waits, then reports
 * success, so the panel's stages can be built and reviewed now. The panel says
 * plainly that nothing settled.
 */
export function createSimulatedExecutor(options: { preflight?: (r: SwapRequest) => SwapFailure | null } = {}): SwapExecutor {
  // Allowances granted in this session, keyed by the token the swap spends.
  const allowances = new Set<string>()
  const key = (r: SwapRequest) => `${r.assetId}:${r.side}`
  const wait = (ms: number) => new Promise<void>((resolve) => setTimeout(resolve, ms))

  return {
    simulated: true,
    needsApproval: (request) => !allowances.has(key(request)),
    approve: async (request) => {
      await wait(900)
      allowances.add(key(request))
      return { hash: randomHash() }
    },
    swap: async () => {
      await wait(1400)
      return { hash: randomHash() }
    },
    preflight: options.preflight,
  }
}

/**
 * Drives one swap through approval, submission and confirmation, and holds the
 * failure if any stage does not complete.
 */
export function useSwapTransaction(executor: SwapExecutor) {
  const stage = ref<SwapStage>('idle')
  const txHash = ref<string | null>(null)
  const failure = ref<SwapFailure | null>(null)
  const lastRequest = ref<SwapRequest | null>(null)

  const busy = computed(
    () =>
      stage.value === 'approve_signing' ||
      stage.value === 'approve_confirming' ||
      stage.value === 'swap_signing' ||
      stage.value === 'swap_confirming',
  )

  function reset() {
    stage.value = 'idle'
    txHash.value = null
    failure.value = null
    lastRequest.value = null
  }

  function fail(next: SwapFailure) {
    failure.value = next
    stage.value = 'failed'
  }

  function describe(error: unknown): SwapFailure {
    const message = error instanceof Error ? error.message : String(error)
    // Wallets report a user-cancelled prompt as a rejection; it is not an error
    // worth alarming anyone about.
    if (/reject|denied|cancel/i.test(message)) {
      return { title: 'Signature declined', detail: 'You dismissed the request in your wallet. Nothing was submitted.', retryable: true }
    }
    return { title: 'Transaction failed', detail: message, retryable: true }
  }

  function needsApproval(request: SwapRequest): boolean {
    return executor.needsApproval(request)
  }

  async function approve(request: SwapRequest) {
    failure.value = null
    lastRequest.value = request
    stage.value = 'approve_signing'
    try {
      // The signature prompt and the confirmation are separate waits, so the
      // stage advances as soon as the wallet hands the transaction back.
      const pending = executor.approve(request)
      stage.value = 'approve_confirming'
      await pending
      stage.value = 'idle'
    } catch (error) {
      fail(describe(error))
    }
  }

  async function submit(request: SwapRequest) {
    failure.value = null
    lastRequest.value = request

    const refusal = executor.preflight?.(request)
    if (refusal) {
      fail(refusal)
      return
    }

    stage.value = 'swap_signing'
    try {
      const pending = executor.swap(request)
      stage.value = 'swap_confirming'
      const { hash } = await pending
      txHash.value = hash
      stage.value = 'confirmed'
    } catch (error) {
      fail(describe(error))
    }
  }

  return {
    stage,
    txHash,
    failure,
    lastRequest,
    busy,
    simulated: executor.simulated,
    needsApproval,
    approve,
    submit,
    reset,
  }
}
