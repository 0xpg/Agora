# Agora

NAV-aware Uniswap v4 AMM liquidity for tokenized real-world assets.

Agora combines concentrated liquidity with issuer-defined market controls. `AgoraHook` provides:

- a NAV-linked trading range;
- dynamic fees around a target price;
- directional rebalancing when the pool moves outside its target zone;
- per-swap limits and stricter NAV freshness for large trades;
- issuer pause controls; and
- temporary emergency parameters with automatic expiry.

## Architecture

```text
Privy wallet -> permissioned router -> asset adapter -> Uniswap v4 PoolManager -> AgoraHook
```

| Component | Responsibility |
|---|---|
| `AgoraHook` | Price bounds, dynamic fees, risk limits, and emergency controls |
| `NAVOracle` | Issuer-published NAV and freshness policy |
| `PermissionedAssetToken` | Token issuance and transfer restrictions |
| `MarketFactory` | Deploys the contracts for a new market |
| Privy | Wallet and email onboarding |

Identity and compliance integration is intentionally deferred until the policy is finalized. Privy currently handles onboarding only.

## Market controls

After publishing NAV, the issuer calls `syncPriceBand` with decimal-aware Uniswap Q64.96 square-root price bounds. A new NAV invalidates the previous band until this synchronization is complete.

`setRiskControls` configures the target price, directional guard, maximum swap amount, and the tighter freshness requirement for large swaps. `setTemporaryPolicy` applies short-lived bounds and fees that expire without a cleanup transaction.

Issuer ownership should be transferred to a Safe before production use.

## Development

```shell
git clone --recurse-submodules https://github.com/0xpg/Agora.git
cd Agora
forge build
forge test -vv
```

For an existing clone:

```shell
git submodule update --init --recursive
```

CI runs `forge fmt --check`, `forge build --sizes`, and `forge test -vvv`.

The Vue frontend uses Privy for wallet onboarding. Swap execution remains disabled until deployed pool, router, adapter, and hook addresses are added to `config/addresses.json`.

## Before production

- Add CREATE2 hook deployment and pool initialization scripts.
- Connect frontend quoting and execution to the permissioned router.
- Finalize the identity and compliance policy.
- Use a production-grade NAV feed.
