# Changelog

## Unreleased

### Secondary market moved from periodic auctions to an adaptive AMM

- Replaced the periodic call/batch auction markets with a NAV-anchored concentrated-liquidity AMM. `AgoraHook` is the policy hook for one permissioned pool: a NAV-linked price range, a fee that scales with distance from a target price, directional rebalancing outside a guard zone, per-swap size limits with stricter NAV freshness for large trades, an issuer pause, and temporary parameters that expire without a cleanup transaction.
- Foundry contracts: `IdentityRegistry`, `PermissionedAssetToken`, `NAVOracle`, `AgoraHook`, `MarketFactory`, `AgoraAllowlistChecker`.
- `IEligibilityOracle` interface extracted from `IdentityRegistry`, so market contracts depend on the interface rather than the concrete registry.
- CI workflow (forge fmt, build, test) on push and pull request.

### Frontend

- Removed the auction flow. No auction screens, order states, countdowns, terminology or configuration remain; `MarketRules.tradingWindow` and the `marketStatus` enum went with it, since trading is continuous and a pool's tradability is derived from its policy and the investor's eligibility.
- Immediate-swap experience supporting both exact-input and exact-output trades, with either leg of the swap specifiable.
- Quote engine (`src/utils/quote.ts`) mirroring the hook's own math on the square root of price, so a quote refuses exactly what a swap would revert on. `assessSwap` reports the quote alongside every reason the pool would refuse it, in the hook's check order.
- Surfaces pool price, reference NAV, premium/discount, the permitted price range, the live dynamic fee and its range, price impact, slippage bound, per-swap limit, NAV freshness and the rebalancing guard.
- User-facing messages for each refusal: paused, NAV out of date, range being re-anchored, price outside the permitted range, trade above the per-swap limit, trade too large for the range to fill, NAV too old for a trade this size, and rebalancing-only.
- Transaction states for approval signing and confirmation, swap signing and confirmation, success and failure, behind a `SwapExecutor` interface. The shipped executor simulates settlement and says so; a live one implements the same interface against the permissioned router.
- Privy onboarding for both wallet and email users.
- Docs page describing Agora by its AMM mechanics, with pool-state explanations drawn from the same table the status badges use.
