# Agora

Permissioned Uniswap v4 AMM liquidity for tokenized real-world assets.

Each market pairs concentrated AMM liquidity with a permissioned asset adapter, a settlement token, and an `AgoraHook` that:

- rejects swaps while the issuer NAV is stale or trading is paused;
- rejects initialization and swaps outside the active NAV price band;
- requires the band to be re-synced after every NAV update; and
- increases LP fees from `baseFee` at the band midpoint to `edgeFee` at either edge.

Eligibility is not inferred from `msg.sender` inside the hook because v4 normally sees a router. Agora reuses Uniswap v4 periphery's `PermissionsAdapter`, permissioned router, and `PermissionedPositionManager`. `AgoraAllowlistChecker` maps the issuer-controlled EAS eligibility result to both swap and liquidity permissions. There is no ZK proof path: this is an explicitly permissioned market.

```text
eligible user -> permissioned router -> PermissionsAdapter -> PoolManager -> AgoraHook
```

## Components

| Contract | Responsibility |
|---|---|
| `AgoraHook` | NAV freshness, synchronized price band, dynamic fee, pause |
| `AgoraAllowlistChecker` | Agora eligibility → v4 permission flags |
| Uniswap `PermissionsAdapter` | Safely wraps the permissioned asset for `PoolManager` custody |
| Uniswap permissioned router | Checks the actual trader and wraps/unwraps the asset |
| Uniswap `PermissionedPositionManager` | Eligibility-gated, non-transferable LP positions |
| `PermissionedAssetToken` | Issuer token and wallet-to-wallet transfer compliance |
| `IdentityRegistry` | EAS-backed eligibility cache |
| `NAVOracle` | Issuer NAV and staleness bound |
| `MarketFactory` | Deploys the asset, registry, NAV oracle, and allowlist checker |

## Market deployment

1. Deploy the shared Uniswap v4 permissioned-pool infrastructure.
2. Call `MarketFactory.deployMarket` to create the Agora asset contracts.
3. Create a verified `PermissionsAdapter` for the asset using `AgoraAllowlistChecker`.
4. Mine and deploy `AgoraHook` at an address with `BEFORE_INITIALIZE`, `BEFORE_SWAP`, and `AFTER_SWAP` flags.
5. Allow-list the hook on the adapter and enable swapping.
6. Publish NAV, call `syncPriceBand`, initialize a dynamic-fee pool, and add concentrated liquidity through `PermissionedPositionManager`.

The price bounds passed to `syncPriceBand` are Uniswap `sqrt(token1/token0)` Q64.96 values and must include token decimal scaling. Updating NAV intentionally stops trading until matching bounds are published; this prevents a new NAV from silently using an old range.

Do not exempt the shared `PoolManager` in `PermissionedAssetToken`. The adapter exists to avoid turning shared protocol custody into a global compliance bypass.

## Quick start

```shell
git clone --recurse-submodules https://github.com/0xpg/Agora.git
cd Agora
forge build
forge test -vv
```

For an existing clone, fetch dependencies with `git submodule update --init --recursive`. Foundry remappings point at Uniswap v4 core/periphery and OpenZeppelin.

CI runs `forge fmt --check`, `forge build --sizes`, and `forge test -vvv`.

The frontend is a Vue demo. Its swap button is deliberately non-transactional until deployed router, adapter, hook, and pool addresses are added to `config/addresses.json`.

## Production gaps

- Add a CREATE2 hook-mining deployment script and full pool initialization script.
- Connect the frontend to the deployed permissioned router and quote path.
- Put issuer ownership behind a multisig/timelock.
- Source NAV from a production-grade signed or attested feed.
