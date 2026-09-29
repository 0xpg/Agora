# Frontend integration

Agora is an immediate-execution AMM built on Uniswap v4. The frontend must quote and swap through the permissioned router; direct `PoolManager` routes are unsupported because they do not establish the eligible end user.

## Reads

| UI value | Source |
|---|---|
| Pool price | v4 pool `slot0` converted from `sqrtPriceX96` |
| Reference NAV | `NAVOracle.getNAV()` |
| NAV freshness | `NAVOracle.isStale()` |
| Active band | `AgoraHook.lowerSqrtPriceX96()` / `upperSqrtPriceX96()` |
| Trading paused | `AgoraHook.paused()` |
| Active fees and bounds | `AgoraHook.activePolicy()` |
| Inventory target and guard | `AgoraHook.targetSqrtPriceX96()` / `directionalGuardBps()` |
| Trade limits | `AgoraHook.maxSwapAmount()` / `largeSwapAmount()` |
| Eligibility | `AgoraAllowlistChecker.checkAllowlist(account, assetToken)` |
| Liquidity and volume | indexed v4 pool data |

## Swap flow

1. Resolve the market's permission adapter, hook, pool key, and permissioned router from `config/addresses.json`.
2. Authenticate or connect the wallet through Privy, then check its EAS tier, permissions, and NAV freshness.
3. Quote through the same permissioned route used for execution.
4. Approve the underlying asset or settlement token as required by the router.
5. Submit the swap with a user-selected slippage bound.
6. Surface hook failures distinctly: paused, stale NAV, unsynchronized band, or price outside band.

The hook enforces protocol bounds; user slippage protection is still required. A transaction may revert between quote and execution if NAV changes, the issuer pauses, eligibility expires, or another swap moves price to the band edge.

Both exact-input and exact-output swaps are subject to `maxSwapAmount`. At or beyond the directional guard, only swaps that move price back toward `targetSqrtPriceX96` are accepted. Trades at least `largeSwapAmount` require the NAV update to be no older than `largeSwapMaxStaleness`.

## Issuer update flow

1. Pause the hook when operational coordination is required.
2. Publish the new NAV.
3. Calculate decimal-aware Q64.96 lower and upper bounds.
4. Call `syncPriceBand(lower, upper)`.
5. Reposition concentrated liquidity if the old range no longer serves the new NAV.
6. Unpause.

Issuer administration should be transferred to a Safe. For short-lived incidents, use `setTemporaryPolicy`; its bounds and fees stop applying at `expiresAt` without a cleanup transaction. Configure EAS tiers with `setTierPermissions`; the stock permissioned-pool integration supports separate swap and liquidity rights.

Every NAV update invalidates the prior band automatically until step 4 completes.
